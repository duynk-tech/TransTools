using CommunityToolkit.Mvvm.ComponentModel;
using CommunityToolkit.Mvvm.Input;
using TransTools.Services.Speech;
using TransTools.Services.Storage;
using NAudio.Wave;
using System.IO;
using System.Buffers.Binary;
using System.Diagnostics;
using System.Windows.Threading;
using TransTools.Services.Translation;
namespace TransTools.ViewModels;

public partial class PersonalVoiceRecorderViewModel : ObservableObject, IDisposable
{
    private PersonalVoiceRecorder? _recorder;
    private float[]? _samples;
    private CancellationTokenSource? _creation, _preview, _script, _leadIn;
    private bool _disposed;
    private readonly Stopwatch _clock = new();
    private readonly DispatcherTimer _timer = new() { Interval = TimeSpan.FromMilliseconds(200) };
    [ObservableProperty] private double _recordedSeconds;
    [ObservableProperty] private bool _guideEnabled = true;
    private readonly Func<bool> _audioBusy;
    [ObservableProperty] [NotifyPropertyChangedFor(nameof(CanSave), nameof(CanEdit), nameof(CanPreview), nameof(CanToggle))] private bool _isRecording;
    [ObservableProperty] [NotifyPropertyChangedFor(nameof(CanSave), nameof(CanEdit), nameof(CanPreview), nameof(CanToggle))] private bool _isProcessing;
    [ObservableProperty] [NotifyPropertyChangedFor(nameof(CanSave))] private bool _hasUsableRecording;
    [ObservableProperty] [NotifyPropertyChangedFor(nameof(CanSave))] private string _voiceName = "Giọng của tôi";
    [ObservableProperty] private string _referenceText = "Xin chào, tôi rất vui được gặp bạn. Hôm nay chúng ta cùng học điều mới.";
    [ObservableProperty] private string _status = "Đọc tự nhiên từ 3 đến 8 giây ở nơi yên tĩnh. Bản thu lưu trên máy.";
    [ObservableProperty] [NotifyPropertyChangedFor(nameof(CanSave), nameof(CanEdit), nameof(CanPreview), nameof(CanToggle))] private bool _isPreviewing;
    [ObservableProperty] [NotifyPropertyChangedFor(nameof(CanSave), nameof(CanEdit), nameof(CanPreview))] private bool _isPreparing;
    [ObservableProperty] private int _countdown;
    public bool CanToggle => !IsProcessing && !IsPreviewing;
    public bool CanEdit => !IsRecording && !IsPreparing && !IsProcessing && !IsPreviewing;
    public bool CanPreview => _samples != null && CanEdit;
    public bool CanSave => HasUsableRecording && CanEdit && !string.IsNullOrWhiteSpace(VoiceName) && VoiceName.Length <= 100;
    public PersonalVoiceRecorderViewModel(Func<bool> audioBusy)
    {
        _audioBusy = audioBusy;
        _timer.Tick += (_, _) => { if (!_disposed && IsRecording) RecordedSeconds = Math.Min(8, _clock.Elapsed.TotalSeconds); };
    }
    partial void OnIsRecordingChanged(bool value)
    {
        if (value) { RecordedSeconds = 0; _clock.Restart(); _timer.Start(); }
        else { _timer.Stop(); _clock.Stop(); }
    }
    [RelayCommand(AllowConcurrentExecutions = true)] private async Task ToggleRecordingAsync()
    {
        if (_disposed || !CanToggle) return;
        if (IsPreparing) { _leadIn?.Cancel(); return; }
        if (IsRecording) { FinishRecording(); return; }
        if (_audioBusy()) { Status = "Dừng phiên đang dùng âm thanh trước khi thu giọng."; return; }
        using var leadIn = new CancellationTokenSource();
        _leadIn = leadIn; IsPreparing = true;
        try {
            for (var remaining = 3; remaining > 0; remaining--) {
                Countdown = remaining; Status = $"Bắt đầu sau {remaining}…";
                await Task.Delay(1000, leadIn.Token);
            }
            leadIn.Token.ThrowIfCancellationRequested();
            if (_disposed) return;
            if (_audioBusy()) { Status = "Dừng phiên đang dùng âm thanh trước khi thu giọng."; return; }
            _recorder?.Dispose(); _recorder = new PersonalVoiceRecorder();
            _recorder.LimitReached += () => System.Windows.Application.Current?.Dispatcher.InvokeAsync(() => { if (!_disposed && IsRecording) FinishRecording(); });
            _samples = null; HasUsableRecording = false;
            _recorder.Start(); IsRecording = true; Status = "Đang thu — đọc rõ, tự nhiên. Tự dừng sau 8 giây.";
        } catch (OperationCanceledException) { if (!_disposed) Status = "Đã hủy đếm ngược. Bản thu trước được giữ nguyên."; }
        catch (Exception ex) { _recorder?.Dispose(); _recorder = null; IsRecording = false; if (!_disposed) Status = "Chưa thu được: " + ex.Message; }
        finally { _leadIn = null; if (!_disposed) { IsPreparing = false; Countdown = 0; } }
    }
    private void FinishRecording()
    {
        try {
            _samples = _recorder!.Finish();
            var quality = PersonalVoiceQuality.Analyze(_samples);
            RecordedSeconds = quality.DurationSeconds;
            HasUsableRecording = quality.IsUsable;
            Status = quality.IsUsable ? $"Đã thu {quality.DurationSeconds:F1} giây. Đặt tên và tạo giọng, hoặc thu lại." : "Âm lượng quá nhỏ hoặc bị vỡ tiếng. Hãy thu lại.";
        } catch (Exception ex) { _samples = null; HasUsableRecording = false; Status = ex.Message; }
        finally { IsRecording = false; _recorder?.Dispose(); _recorder = null; OnPropertyChanged(nameof(CanPreview)); }
    }
    [RelayCommand] private async Task SaveRecordingAsync()
    {
        if (_disposed || !CanSave || _samples == null) return;
        var samples = _samples.ToArray(); var name = VoiceName.Trim(); var script = ReferenceText;
        IsProcessing = true;
        try {
            var profile = await Task.Run(() => new PersonalVoiceStore(PersonalVoiceStore.DefaultRoot).SaveRecording(name, script, samples));
            if (!_disposed) Status = "Đã lưu bản thu gốc " + profile.Name + ". Bản thu chưa có hồ sơ mô hình; chưa dùng để đọc.";
        } catch (Exception ex) { if (!_disposed) Status = "Chưa lưu được bản thu: " + ex.Message; }
        finally { Array.Clear(samples); if (!_disposed) IsProcessing = false; }
    }
    [RelayCommand] private async Task SaveVoiceAsync()
    {
        if (_disposed || !CanSave || _samples == null) return;
        if (_audioBusy()) { Status = "Dừng phiên đang dùng âm thanh trước khi tạo giọng."; return; }
        var samples = _samples.ToArray(); var name = VoiceName.Trim(); var script = ReferenceText;
        using var cts = new CancellationTokenSource(); _creation = cts; IsProcessing = true;
        try {
            var path = await PersonalVoiceEncoderInstaller.EnsureAsync(new Progress<string>(message => { if (!_disposed) Status = message; }), cts.Token);
            Status = "Đang tạo giọng…";
            var profile = await Task.Run(() => {
                var embedding = VieNeuSpeakerEncoder.Extract(samples, path, cts.Token);
                cts.Token.ThrowIfCancellationRequested();
                return new PersonalVoiceStore(PersonalVoiceStore.DefaultRoot).Save(name, script, samples, embedding);
            }, cts.Token);
            if (!_disposed) Status = "Đã lưu giọng " + profile.Name + ". Chọn trong Giọng của tôi để nghe thử.";
        } catch (OperationCanceledException) { if (!_disposed) Status = "Đã hủy tạo giọng."; }
        catch (Exception ex) { if (!_disposed) Status = "Chưa tạo được giọng: " + ex.Message; }
        finally { Array.Clear(samples); _creation = null; if (!_disposed) IsProcessing = false; }
    }
    [RelayCommand] private async Task PreviewRecordingAsync()
    {
        if (_disposed || !CanPreview || _samples == null) return;
        if (_audioBusy()) { Status = "Dừng phiên đang dùng âm thanh trước khi nghe bản thu."; return; }
        var pcm = new byte[_samples.Length * 2];
        for (var i = 0; i < _samples.Length; i++) BinaryPrimitives.WriteInt16LittleEndian(pcm.AsSpan(i * 2, 2), (short)Math.Round(Math.Clamp(_samples[i], -1f, 1f) * 32767));
        using var cts = new CancellationTokenSource(); _preview = cts; IsPreviewing = true;
        try {
            using var stream = new MemoryStream(pcm);
            using var reader = new RawSourceWaveStream(stream, new WaveFormat(16000, 16, 1));
            using var output = new WaveOutEvent(); output.Init(reader); output.Play();
            Status = "Đang nghe bản thu…";
            while (output.PlaybackState == PlaybackState.Playing) await Task.Delay(50, cts.Token);
            if (!_disposed) Status = "Đã nghe bản thu. Bạn có thể thu lại hoặc tạo giọng.";
        } catch (OperationCanceledException) { if (!_disposed) Status = "Đã dừng nghe bản thu."; }
        catch (Exception ex) { if (!_disposed) Status = "Chưa nghe được bản thu: " + ex.Message; }
        finally { Array.Clear(pcm); _preview = null; if (!_disposed) IsPreviewing = false; }
    }
    [RelayCommand] private void StopPreview() => _preview?.Cancel();
    public static bool IsValidReferenceText(string text)
    {
        var words = text.Split((char[]?)null, StringSplitOptions.RemoveEmptyEntries);
        return words.Length is >= 18 and <= 24 && text.Length <= 240 && !text.Contains('\n') && !text.Contains('\r') && !text.Any(char.IsDigit) && !text.Contains('#') && !text.Contains('*');
    }
    [RelayCommand] private async Task GenerateScriptAsync()
    {
        if (_disposed || !CanEdit) return;
        using var cts = new CancellationTokenSource(TimeSpan.FromSeconds(20)); _script = cts; IsProcessing = true;
        try {
            var config = new SecureCredentialStore().LoadConfiguredProvider();
            if (config == null) { Status = "Chưa cấu hình AI. Bạn vẫn có thể đọc đoạn mẫu có sẵn."; return; }
            Status = "AI đang chuẩn bị đoạn đọc mẫu…";
            const string prompt = "Viết đúng một đoạn tiếng Việt tự nhiên để người lớn thu giọng trong 6 đến 8 giây. Chỉ 18 đến 24 từ cách nhau bằng khoảng trắng, một hoặc hai câu ngắn, đa dạng dấu thanh. Chủ đề đời sống nhẹ nhàng, không tên riêng, số, viết tắt, quảng cáo hoặc nội dung nhạy cảm. Chỉ trả về đoạn văn, không tiêu đề, Markdown hay giải thích.";
            var text = (await new LLMTranslationService().GenerateAsync("Tạo đoạn đọc mẫu mới.", prompt, config, cts.Token)).Trim();
            cts.Token.ThrowIfCancellationRequested(); if (_disposed) return;
            if (!IsValidReferenceText(text)) { Status = "Đoạn AI chưa phù hợp thời lượng. Giữ mẫu hiện tại; bạn có thể thử lại."; return; }
            if (_samples != null) Array.Clear(_samples); _samples = null; HasUsableRecording = false; OnPropertyChanged(nameof(CanPreview));
            ReferenceText = text; RecordedSeconds = 0; Status = "Đã có đoạn mới. Đọc thử một lần trước khi thu.";
        } catch (OperationCanceledException) { if (!_disposed) Status = "Đã dừng tạo đoạn đọc. Giữ mẫu hiện tại."; }
        catch (Exception) { if (!_disposed) Status = "Chưa tạo được đoạn AI. Bạn có thể dùng mẫu có sẵn."; }
        finally { _script = null; if (!_disposed) IsProcessing = false; }
    }
    [RelayCommand] private void CancelCreation() { _creation?.Cancel(); _script?.Cancel(); }
    public void Dispose()
    {
        if (_disposed) return; _disposed = true; _timer.Stop(); _clock.Stop(); _creation?.Cancel(); _preview?.Cancel(); _script?.Cancel(); _leadIn?.Cancel(); _recorder?.Dispose(); _recorder = null;
        if (_samples != null) Array.Clear(_samples); _samples = null;
    }
}
