using System.Collections.ObjectModel;
using System.IO;
using System.Threading.Channels;
using CommunityToolkit.Mvvm.ComponentModel;
using CommunityToolkit.Mvvm.Input;
using NAudio.Wave;
using TransTools.Models;
using TransTools.Services.Audio;
using TransTools.Services.Speech;
using TransTools.Services.Storage;
using TransTools.Services.Translation;
namespace TransTools.ViewModels;

public partial class MeetingViewModel : ObservableObject, IDisposable
{
    private readonly WasapiAudioCaptureService _audio = new();
    private readonly WhisperSttService _stt = new();
    private readonly GoogleTranslationService _google = new();
    private readonly SecureCredentialStore _credentials = new();
    private readonly object _lock = new();
    private readonly MemoryStream _buffer = new();
    private readonly List<(string Text, double Start, double End)> _segments = new();
    private Channel<byte[]>? _audioQueue;
    private Channel<Caption>? _translationQueue;
    private Channel<Caption>? _displayQueue;
    private CancellationTokenSource? _cts;
    private Task? _processing;
    private DateTime _lastVoice;
    private double _offset;
    private bool _overflow;
    private DateTime _started;
    private Guid _sessionId = Guid.NewGuid();
    private bool _sessionSystemAudio = true;
    private string _sessionDomain = "Thông dụng";
    private string _sessionSource = "en", _sessionTarget = "vi", _sessionTranslationMode = "Google";
    private AIProviderConfig? _sessionAi;
    [ObservableProperty] private bool _isPreparing;
    private CancellationTokenSource? _prepareCancellation;
    public bool CanConfigureMeeting => !IsBusy;
    public bool CanToggleRecording => !IsStopping;
    partial void OnIsPreparingChanged(bool value) { OnPropertyChanged(nameof(IsBusy)); OnPropertyChanged(nameof(CanConfigureMeeting)); }
    partial void OnIsRecordingChanged(bool value) { OnPropertyChanged(nameof(IsBusy)); OnPropertyChanged(nameof(CanConfigureMeeting)); }
    partial void OnIsStoppingChanged(bool value) { OnPropertyChanged(nameof(IsBusy)); OnPropertyChanged(nameof(CanConfigureMeeting)); OnPropertyChanged(nameof(CanToggleRecording)); }
    [RelayCommand] public void CancelPreparation() => _prepareCancellation?.Cancel();
    private volatile bool _flushPresentation;
    public Func<bool>? OtherAudioBusy { get; set; }
    public bool IsBusy => IsRecording || IsStopping || IsPreparing;
    [ObservableProperty] private bool _isRecording;
    [ObservableProperty] private bool _isStopping;
    [ObservableProperty] private string _status = "Sẵn sàng";
    [ObservableProperty] private float _audioLevel;
    [ObservableProperty] private string _currentLiveOriginal = "";
    [ObservableProperty] private string _currentLiveVietnamese = "";
    [ObservableProperty] private bool _captureSystemAudio = true;
    [ObservableProperty] private bool _captureMicrophone;
    [ObservableProperty] private string _sourceLanguage = "en";
    [ObservableProperty] private string _targetLanguage = "vi";
    [ObservableProperty] private string _translationMode = "Google";
    public string[] DisplayModes { get; } = ["Song ngữ", "Tiếng gốc", "Bản dịch"];
    public string DisplayModeKey => TransTools.Services.Experience.SubtitlePreferences.Shared.DisplayMode;
    public string SelectedDisplayMode
    {
        get => DisplayModeKey switch { "original" => "Tiếng gốc", "translation" => "Bản dịch", _ => "Song ngữ" };
        set
        {
            var key = value switch { "Tiếng gốc" => "original", "Bản dịch" => "translation", _ => "bilingual" };
            var preferences = TransTools.Services.Experience.SubtitlePreferences.Shared;
            if (preferences.DisplayMode == key) return;
            preferences.DisplayMode = key;
            NotifyDisplayMode();
            try { preferences.Save(); } catch { Status = "Chưa lưu được cách hiển thị phụ đề."; }
        }
    }
    private void NotifyDisplayMode()
    {
        OnPropertyChanged(nameof(SelectedDisplayMode)); OnPropertyChanged(nameof(DisplayModeKey));
    }
    private void DisplayPreferencesChanged() => Ui(NotifyDisplayMode);
    public string[] CaptureSources { get; } = ["Âm thanh hệ thống", "Microphone"];
    [ObservableProperty] private string _captureSource = "Âm thanh hệ thống";
    partial void OnCaptureSourceChanged(string value) { CaptureSystemAudio = value == "Âm thanh hệ thống"; CaptureMicrophone = !CaptureSystemAudio; }
    public string[] TargetLanguages { get; } = ["en", "vi", "ja", "zh", "ko"];
    [RelayCommand] private void SwapLanguages()
    {
        if (IsBusy || SourceLanguage == "auto") return;
        (SourceLanguage, TargetLanguage) = (TargetLanguage, SourceLanguage);
    }
    public string[] Languages { get; } = { "en", "vi", "ja", "zh", "ko", "auto" };
    public string[] TranslationModes { get; } = { "Google", "AI", "Tiếng gốc" };
    public ObservableCollection<Caption> Captions { get; } = new();
    public event Action<string, string>? OnSubtitleUpdated;
    public event Action<Caption>? OnCaptionPresented;
    public event Action<Caption>? OnCaptionIncoming;
    public event Action<MeetingSession>? OnSessionSaved;
    public MeetingViewModel()
    {
        Captions.CollectionChanged += (_, _) => { OnPropertyChanged(nameof(CanExportMeeting)); ExportMeetingCommand.NotifyCanExecuteChanged(); };
        TransTools.Services.Experience.SubtitlePreferences.Shared.Changed += DisplayPreferencesChanged;
        _audio.OnAudioLevelChanged += level => Ui(() => AudioLevel = level);
        _audio.OnAudio16kHzMonoChunk += AcceptAudio;
        _stt.OnSegmentTranscribed += (text, start, end) => _segments.Add((text, start, end));
    }
    private static void Ui(Action action) => System.Windows.Application.Current?.Dispatcher.BeginInvoke(action);
    private void AcceptAudio(byte[] chunk)
    {
        lock (_lock) {
            if (!IsRecording || _audioQueue == null) return;
            _buffer.Write(chunk);
            double sum = 0;
            for (var i = 0; i + 1 < chunk.Length; i += 2) { var v = BitConverter.ToInt16(chunk, i) / 32768.0; sum += v * v; }
            if (Math.Sqrt(sum / Math.Max(1, chunk.Length / 2)) > .008) _lastVoice = DateTime.UtcNow;
            // Preserve utterances across callbacks, close on silence or at 8 seconds.
            if ((_buffer.Length >= 16000 && (DateTime.UtcNow - _lastVoice).TotalSeconds >= .8) || _buffer.Length >= 256000) {
                if (!_audioQueue.Writer.TryWrite(_buffer.ToArray())) {
                    _overflow = true; Ui(() => StopRecordingCommand.Execute(null));
                }
                _buffer.SetLength(0);
            }
        }
    }
    [RelayCommand] public async Task StartRecordingAsync()
    {
        if (IsRecording || IsStopping || IsPreparing) return;
        if (OtherAudioBusy?.Invoke() == true) { Status = "Kết thúc luyện nói trước khi bắt đầu cuộc họp."; return; }
        IsPreparing = true; _prepareCancellation = new();
        try {
            if (CaptureSystemAudio == CaptureMicrophone) throw new InvalidOperationException("Chọn một nguồn âm thanh.");
            // Persist the stopped session before a new recognition session clears the screen.
            if (Captions.Count > 0) await PersistCurrentSessionAsync();
            _sessionDomain = TransTools.Services.Experience.SubtitlePreferences.Shared.Domain;
            _sessionSource = SourceLanguage; _sessionTarget = TargetLanguage; _sessionTranslationMode = TranslationMode;
            _sessionAi = _sessionTranslationMode == "AI" ? _credentials.LoadConfiguredProvider() ?? throw new InvalidOperationException("Chọn AI và model trong Cài đặt.") : null;
            Status = "Đang chuẩn bị nhận diện...";
            await _stt.InitializeModelAsync(language: _sessionSource, cancellationToken: _prepareCancellation.Token);
            _cts?.Dispose(); _cts = new(); _sessionId = Guid.NewGuid(); _sessionSystemAudio = CaptureSystemAudio; _offset = 0; _overflow = false; _started = DateTime.Now;
            _flushPresentation = false; Captions.Clear(); CurrentLiveOriginal = ""; CurrentLiveVietnamese = "";
            _audioQueue = Channel.CreateBounded<byte[]>(new BoundedChannelOptions(8) { SingleReader = true, FullMode = BoundedChannelFullMode.Wait });
            _translationQueue = Channel.CreateBounded<Caption>(new BoundedChannelOptions(64) { SingleReader = true, SingleWriter = true });
            // Only the visible overlay may skip a stale backlog. The transcript retains every caption.
            _displayQueue = Channel.CreateBounded<Caption>(new BoundedChannelOptions(3) { SingleReader = true, SingleWriter = true, FullMode = BoundedChannelFullMode.DropOldest });
            lock (_lock) { _buffer.SetLength(0); _lastVoice = DateTime.UtcNow; }
            var token = _cts.Token;
            _processing = Task.WhenAll(Task.Run(() => RecognizeAsync(token)), Task.Run(() => TranslateAsync(token)), Task.Run(() => PresentAsync(token)));
            IsRecording = true; _audio.StartCapture(CaptureSystemAudio, CaptureMicrophone); Status = "Đang dịch...";
        } catch (Exception ex) {
            _audio.StopCapture(); _audioQueue?.Writer.TryComplete(); _cts?.Cancel(); IsRecording = false;
            if (_processing != null) { try { await _processing; } catch { } }
            _stt.Dispose(); Status = ex is OperationCanceledException ? "Đã hủy bắt đầu cuộc họp." : ex.Message;
        }
        finally { _prepareCancellation?.Dispose(); _prepareCancellation = null; IsPreparing = false; }
    }
    [RelayCommand] public async Task StopRecordingAsync()
    {
        if (!IsRecording || IsStopping) return;
        _flushPresentation = true; IsStopping = true; IsRecording = false; _audio.StopCapture(); Status = "Đang hoàn tất phần âm thanh cuối...";
        try {
            byte[]? final;
            lock (_lock) { final = _buffer.Length > 0 ? _buffer.ToArray() : null; _buffer.SetLength(0); }
            if (final != null && _audioQueue != null) await _audioQueue.Writer.WriteAsync(final);
            _audioQueue?.Writer.TryComplete();
            // Drain the last utterance instead of silently throwing it away.
            if (_processing != null) await _processing;
            await PersistCurrentSessionAsync();
            Status = _overflow ? "Đã dừng vì xử lý không theo kịp. Một đoạn âm thanh chưa được xử lý." : "Đã dừng; có thể lưu Sổ tay.";
        } catch (Exception ex) { Status = "Lỗi hoàn tất: " + ex.Message; }
        finally { if (_processing?.IsCompleted == true) _stt.Dispose(); IsStopping = false; AudioLevel = 0; }
    }
    [RelayCommand] public async Task ClearCaptionsAsync() { if (IsStopping || IsPreparing) return; if (System.Windows.MessageBox.Show("Xóa toàn bộ nội dung cuộc họp hiện tại?", "Xóa nội dung", System.Windows.MessageBoxButton.YesNo, System.Windows.MessageBoxImage.Warning, System.Windows.MessageBoxResult.No) != System.Windows.MessageBoxResult.Yes) return; await StopRecordingAsync(); _flushPresentation = false; Captions.Clear(); CurrentLiveOriginal = ""; CurrentLiveVietnamese = ""; }
    [RelayCommand] public async Task SaveSessionAsync()
    {
        if (IsStopping || IsPreparing) { Status = "Chờ hoàn tất âm thanh cuối trước khi lưu."; return; }
        await StopRecordingAsync(); if (Captions.Count == 0) return;
        await PersistCurrentSessionAsync(); Status = "Đã lưu Sổ tay";
    }
    public MeetingSession CreateExportSnapshot() => new() {
        Title = "Cuộc họp · " + (_started == default ? DateTime.Now : _started).ToString("dd/MM HH:mm"),
        CreatedAt = _started == default ? DateTime.Now : _started,
        AudioSource = _sessionSystemAudio ? "Âm thanh hệ thống" : "Microphone",
        DurationSeconds = Captions.Count == 0 ? 0 : Captions.Max(c => c.End),
        Captions = Captions.Select(c => new Caption { Id = c.Id, Start = c.Start, End = c.End, Original = c.Original, Vietnamese = c.Vietnamese }).ToList()
    };
    public bool CanExportMeeting => Captions.Count > 0;
    [RelayCommand(CanExecute = nameof(CanExportMeeting))] private void ExportMeeting(string? format)
    {
        if (Captions.Count == 0) { Status = "Chưa có nội dung để xuất."; return; }
        var session = CreateExportSnapshot();
        var extension = format == "Word" ? "docx" : format == "SRT" ? "srt" : "txt";
        var dialog = new Microsoft.Win32.SaveFileDialog { FileName = "Cuộc họp " + session.CreatedAt.ToString("yyyy-MM-dd HH-mm") + "." + extension, Filter = $"{format} (*.{extension})|*.{extension}" };
        if (dialog.ShowDialog() != true) return;
        try {
            if (extension == "docx") TransTools.Services.Export.DocxExportService.ExportMeetingSession(session, dialog.FileName);
            else File.WriteAllText(dialog.FileName, FormatExport(session, extension), new System.Text.UTF8Encoding(false));
            Status = "Đã xuất bản ghi " + format;
        } catch (Exception ex) { Status = "Chưa xuất được bản ghi: " + ex.Message; }
    }
    public static string FormatExport(MeetingSession session, string format)
    {
        if (format == "srt") return string.Join("\n\n", session.Captions.Select((c,i) => $"{i+1}\n{TimeSpan.FromSeconds(c.Start):hh\\:mm\\:ss\\,fff} --> {TimeSpan.FromSeconds(Math.Max(c.Start,c.End)):hh\\:mm\\:ss\\,fff}\n{c.Original}\n{c.Vietnamese}")) + "\n";
        return session.Title + "\n\n" + string.Join("\n\n",session.Captions.Select(c => $"[{c.FormattedTimestamp}]\n{c.Original}\n{c.Vietnamese}"));
    }
    private async Task PersistCurrentSessionAsync()
    {
        if (Captions.Count == 0) return;
        var snapshot = Captions.ToList();
        var store = new SessionStore();
        var session = await store.UpdateSessionAsync(_sessionId,
            () => new MeetingSession { Id = _sessionId, Title = "Cuộc họp · " + _started.ToString("dd/MM HH:mm"), CreatedAt = _started },
            stored => {
                stored.Captions = snapshot; stored.DurationSeconds = snapshot.Max(c => c.End);
                stored.AudioSource = _sessionSystemAudio ? "Âm thanh hệ thống" : "Microphone";
            });
        OnSessionSaved?.Invoke(session);
    }
    private async Task RecognizeAsync(CancellationToken token)
    {
        try {
            await foreach (var pcm in _audioQueue!.Reader.ReadAllAsync(token)) {
                var duration = pcm.Length / 32000.0;
                try {
                    using var output = new MemoryStream(); byte[] wav;
                    using (var writer = new WaveFileWriter(output, new WaveFormat(16000, 16, 1))) { writer.Write(pcm); writer.Flush(); wav = output.ToArray(); }
                    _segments.Clear(); using var stream = new MemoryStream(wav); await _stt.ProcessAudioAsync(stream, token);
                    foreach (var segment in _segments) {
                        var pieces = CaptionTextSegmenter.Split(segment.Text);
                        var chars = Math.Max(1, pieces.Sum(t => t.Length)); var consumed = 0;
                        foreach (var text in pieces) {
                            var caption = new Caption { Original = text, Start = _offset + segment.Start + (segment.End - segment.Start) * consumed / chars,
                                End = _offset + segment.Start + (segment.End - segment.Start) * (consumed + text.Length) / chars };
                            consumed += text.Length;
                            await System.Windows.Application.Current.Dispatcher.InvokeAsync(() => { Captions.Add(caption); OnCaptionIncoming?.Invoke(caption); });
                            await _translationQueue!.Writer.WriteAsync(caption, token);
                        }
                    }
                } catch (OperationCanceledException) { throw; }
                catch (Exception ex) { Ui(() => Status = "Lỗi nhận diện: " + ex.Message); }
                finally { _offset += duration; }
            }
        } finally { _translationQueue?.Writer.TryComplete(); }
    }
    private async Task TranslateAsync(CancellationToken token)
    {
        try {
        await foreach (var caption in _translationQueue!.Reader.ReadAllAsync(token)) {
            try {
                if (_sessionTranslationMode == "Tiếng gốc") { await _displayQueue!.Writer.WriteAsync(caption,token); continue; }
                string translated;
                if (_sessionTranslationMode == "AI") {
                    var config = _sessionAi ?? throw new InvalidOperationException("Cấu hình AI không còn khả dụng.");
                    translated = await new LLMTranslationService().TranslateWithAIAsync(caption.Original, _sessionTarget, $"{_sessionDomain}. Tự nhiên, giữ đúng thuật ngữ chuyên ngành, không thêm nội dung", config);
                } else translated = await _google.TranslateAsync(caption.Original, _sessionSource, _sessionTarget, token);
                await System.Windows.Application.Current.Dispatcher.InvokeAsync(() => {
                    caption.Vietnamese = translated; OnCaptionIncoming?.Invoke(caption);
                });
                await _displayQueue!.Writer.WriteAsync(caption,token);
            } catch (OperationCanceledException) { throw; }
            catch (Exception ex) { Ui(() => Status = "Lỗi dịch: " + ex.Message); await _displayQueue!.Writer.WriteAsync(caption,token); }
        }
        } finally { _displayQueue?.Writer.TryComplete(); }
    }
    private async Task PresentAsync(CancellationToken token) {
        await foreach (var caption in _displayQueue!.Reader.ReadAllAsync(token)) {
            await System.Windows.Application.Current.Dispatcher.InvokeAsync(() => {
                CurrentLiveOriginal = caption.Original; CurrentLiveVietnamese = caption.Vietnamese;
                OnSubtitleUpdated?.Invoke(caption.Original,caption.Vietnamese); OnCaptionPresented?.Invoke(caption);
            });
            var until = DateTime.UtcNow.AddSeconds(TransTools.Services.Speech.CaptionDisplayTiming.HoldSeconds(caption.Original,caption.Vietnamese, TransTools.Services.Experience.SubtitlePreferences.Shared.Pacing));
            while (!_flushPresentation && DateTime.UtcNow < until) await Task.Delay(100,token);
        }
    }
    public void Dispose() {
        TransTools.Services.Experience.SubtitlePreferences.Shared.Changed -= DisplayPreferencesChanged;
        _prepareCancellation?.Cancel(); _cts?.Cancel(); _audio.Dispose();
        var pending = _processing ?? Task.CompletedTask;
        _ = pending.ContinueWith(_ => { _stt.Dispose(); _cts?.Dispose(); _buffer.Dispose(); }, TaskScheduler.Default);
    }
}
