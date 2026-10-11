using CommunityToolkit.Mvvm.ComponentModel;
using CommunityToolkit.Mvvm.Input;
using TransTools.Services.Speech;
using TransTools.Services.Storage;
namespace TransTools.ViewModels;

public partial class PersonalVoiceRecorderViewModel : ObservableObject, IDisposable
{
    private PersonalVoiceRecorder? _recorder;
    private float[]? _samples;
    private CancellationTokenSource? _creation;
    private bool _disposed;
    private readonly Func<bool> _audioBusy;
    [ObservableProperty] [NotifyPropertyChangedFor(nameof(CanSave), nameof(CanEdit))] private bool _isRecording;
    [ObservableProperty] [NotifyPropertyChangedFor(nameof(CanSave), nameof(CanEdit))] private bool _isProcessing;
    [ObservableProperty] [NotifyPropertyChangedFor(nameof(CanSave))] private bool _hasUsableRecording;
    [ObservableProperty] [NotifyPropertyChangedFor(nameof(CanSave))] private string _voiceName = "Giọng của tôi";
    [ObservableProperty] private string _referenceText = "Xin chào, tôi rất vui được gặp bạn. Hôm nay chúng ta cùng học điều mới.";
    [ObservableProperty] private string _status = "Đọc tự nhiên từ 3 đến 8 giây ở nơi yên tĩnh. Bản thu lưu trên máy.";
    public bool CanEdit => !IsRecording && !IsProcessing;
    public bool CanSave => HasUsableRecording && CanEdit && !string.IsNullOrWhiteSpace(VoiceName) && VoiceName.Length <= 100;
    public PersonalVoiceRecorderViewModel(Func<bool> audioBusy) => _audioBusy = audioBusy;
    [RelayCommand] private void ToggleRecording()
    {
        if (_disposed || IsProcessing) return;
        if (IsRecording) { FinishRecording(); return; }
        if (_audioBusy()) { Status = "Dừng phiên đang dùng âm thanh trước khi thu giọng."; return; }
        try {
            _recorder?.Dispose(); _recorder = new PersonalVoiceRecorder();
            _recorder.LimitReached += () => System.Windows.Application.Current?.Dispatcher.InvokeAsync(() => { if (!_disposed && IsRecording) FinishRecording(); });
            _samples = null; HasUsableRecording = false;
            _recorder.Start(); IsRecording = true; Status = "Đang thu — đọc rõ, tự nhiên. Tự dừng sau 8 giây.";
        } catch (Exception ex) { _recorder?.Dispose(); _recorder = null; IsRecording = false; Status = "Chưa thu được: " + ex.Message; }
    }
    private void FinishRecording()
    {
        try {
            _samples = _recorder!.Finish();
            var quality = PersonalVoiceQuality.Analyze(_samples);
            HasUsableRecording = quality.IsUsable;
            Status = quality.IsUsable ? $"Đã thu {quality.DurationSeconds:F1} giây. Đặt tên và tạo giọng, hoặc thu lại." : "Âm lượng quá nhỏ hoặc bị vỡ tiếng. Hãy thu lại.";
        } catch (Exception ex) { _samples = null; HasUsableRecording = false; Status = ex.Message; }
        finally { IsRecording = false; _recorder?.Dispose(); _recorder = null; }
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
    [RelayCommand] private void CancelCreation() => _creation?.Cancel();
    public void Dispose()
    {
        if (_disposed) return; _disposed = true; _creation?.Cancel(); _recorder?.Dispose(); _recorder = null;
        if (_samples != null) Array.Clear(_samples); _samples = null;
    }
}
