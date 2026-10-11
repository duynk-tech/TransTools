using CommunityToolkit.Mvvm.ComponentModel;
using CommunityToolkit.Mvvm.Input;
using System.Collections.ObjectModel;
using NAudio.Wave;
using System.Diagnostics;
using TransTools.Services.Storage;
using TransTools.Services.Speech;
namespace TransTools.ViewModels;

public partial class VoiceSettingsViewModel
{
    public ObservableCollection<PersonalVoiceProfile> Recordings { get; } = new();
    [ObservableProperty] [NotifyPropertyChangedFor(nameof(CanManageRecording), nameof(CanUseRecordingVoice))] [NotifyCanExecuteChangedFor(nameof(CreateRecordingVoiceCommand))] private PersonalVoiceProfile? _selectedRecording;
    [ObservableProperty]
    [NotifyCanExecuteChangedFor(nameof(CreateRecordingVoiceCommand))]
    [NotifyPropertyChangedFor(nameof(CanConfigure), nameof(CanManagePersonalVoice), nameof(CanChangeRate), nameof(CanManageRecording), nameof(CanUseRecordingVoice))]
    private bool _isBuildingVoice;
    private CancellationTokenSource? _buildingVoice;
    private CancellationTokenSource? _recordingPreview;
    public bool CanManageRecording => CanConfigure && SelectedRecording != null && !_audioBusy();
    [ObservableProperty] [NotifyCanExecuteChangedFor(nameof(CreateRecordingVoiceCommand))] [NotifyPropertyChangedFor(nameof(RecordingModelStatus), nameof(CanUseRecordingVoice))] private bool _hasSelectedModel;
    public string RecordingModelStatus => SelectedRecording == null ? "Chưa có bản thu" : HasSelectedModel ? "Hồ sơ VieNeu đã tạo" : "Chưa tạo hồ sơ VieNeu";
    public bool CanUseRecordingVoice => CanManageRecording && HasSelectedModel && VoiceService.Shared.IsVieNeuInstalled;
    partial void OnSelectedRecordingChanged(PersonalVoiceProfile? value) => UpdateRecordingModelState();
    private void UpdateRecordingModelState()
    {
        HasSelectedModel = SelectedRecording != null && _personalVoiceStore.HasModel(SelectedRecording.Id);
        OnPropertyChanged(nameof(RecordingModelStatus)); OnPropertyChanged(nameof(CanUseRecordingVoice));
    }
    public void RemoveRecordingModel(Guid id)
    {
        if (!CanManageRecording || SelectedRecording?.Id != id || _audioBusy()) return;
        try {
            _personalVoiceStore.MoveModelToTrash(id);
            if (VoicePreferences.Get("vi").PersonalVoiceId == id) VoicePreferences.SelectPersonalVoice(null);
            LoadPreference(); Status = "Đã gỡ hồ sơ VieNeu, giữ nguyên bản thu gốc.";
        } catch (Exception ex) { LoadPreference(); Status = "Chưa gỡ được hồ sơ: " + ex.Message; }
    }
    [RelayCommand] private void UseRecordingVoice()
    {
        if (!CanUseRecordingVoice || SelectedRecording == null || _audioBusy()) return;
        try { VoicePreferences.SelectPersonalVoice(SelectedRecording.Id); Status = "Đã dùng giọng này cho tiếng Việt."; }
        catch (Exception ex) { Status = "Chưa chọn được giọng: " + ex.Message; }
    }
    [RelayCommand] private async Task TestRecordingVoiceAsync()
    {
        if (!CanUseRecordingVoice || SelectedRecording == null) return;
        if (_audioBusy()) { Status = "Dừng phiên đang dùng âm thanh trước khi đọc thử."; return; }
        var id = SelectedRecording.Id; IsPreviewing = true;
        try { Status = "Đang đọc thử câu mới…"; await VoiceService.Shared.SpeakAsync("Hôm nay là một ngày mới. Tôi muốn cùng bạn học thêm điều thú vị.", "vi", "VieNeu v3 Turbo", personalVoiceOverride: id); Status = "Đã đọc thử bằng hồ sơ đã chọn."; }
        catch (Exception ex) { Status = "Chưa đọc thử được: " + ex.Message; }
        finally { IsPreviewing = false; }
    }
    public void RenameRecording(string name)
    {
        if (!CanManageRecording || SelectedRecording == null || _audioBusy()) return;
        try { _personalVoiceStore.Rename(SelectedRecording.Id, name); LoadPreference(); Status = "Đã đổi tên bản thu."; }
        catch (Exception ex) { Status = "Chưa đổi được tên: " + ex.Message; }
    }
    public void DeleteRecording(Guid id)
    {
        if (!CanManageRecording || SelectedRecording?.Id != id || _audioBusy()) return;
        try {
            _personalVoiceStore.MoveToTrash(id);
            if (VoicePreferences.Get("vi").PersonalVoiceId == id) VoicePreferences.SelectPersonalVoice(null);
            LoadPreference(); Status = "Đã chuyển bản thu và hồ sơ giọng vào Thùng rác.";
        } catch (Exception ex) { LoadPreference(); Status = "Chưa xóa được bản thu: " + ex.Message; }
    }
    [RelayCommand] private void OpenRecordingFolder()
    {
        if (!CanManageRecording || SelectedRecording == null) return;
        try { Process.Start(new ProcessStartInfo("explorer.exe", "/select,\"" + _personalVoiceStore.RecordingPath(SelectedRecording.Id) + "\"") { UseShellExecute = true }); }
        catch (Exception ex) { Status = "Chưa mở được thư mục: " + ex.Message; }
    }
    [RelayCommand] private async Task PreviewOriginalRecordingAsync()
    {
        if (!CanManageRecording || SelectedRecording == null) return;
        if (_audioBusy()) { Status = "Dừng phiên đang dùng âm thanh trước khi nghe bản thu."; return; }
        var id = SelectedRecording.Id;
        using var cancellation = new CancellationTokenSource(); _recordingPreview = cancellation; IsPreviewing = true;
        try {
            var store = _personalVoiceStore;
            var samples = store.LoadRecording(id); Array.Clear(samples);
            using var reader = new WaveFileReader(store.RecordingPath(id));
            using var output = new WaveOutEvent(); output.Init(reader); output.Play();
            Status = "Đang nghe bản thu gốc…";
            while (output.PlaybackState == PlaybackState.Playing) await Task.Delay(50, cancellation.Token);
            Status = "Đã nghe bản thu gốc.";
        } catch (OperationCanceledException) { Status = "Đã dừng nghe bản thu."; }
        catch (Exception ex) { Status = "Chưa nghe được bản thu: " + ex.Message; }
        finally { _recordingPreview = null; IsPreviewing = false; }
    }
    public bool HasRecordings => Recordings.Count > 0;
    private void RefreshRecordings(PersonalVoiceStore store)
    {
        var selected = SelectedRecording?.Id;
        Recordings.Clear();
        foreach (var recording in store.Load()) Recordings.Add(recording);
        SelectedRecording = Recordings.FirstOrDefault(item => item.Id == selected) ?? Recordings.FirstOrDefault();
        UpdateRecordingModelState(); OnPropertyChanged(nameof(HasRecordings));
    }
    private bool CanCreateSavedVoice() => CanManageRecording && !HasSelectedModel && VoiceService.Shared.IsVieNeuInstalled;
    [RelayCommand(CanExecute = nameof(CanCreateSavedVoice))] private async Task CreateRecordingVoiceAsync()
    {
        if (!CanCreateSavedVoice() || SelectedRecording == null) return;
        if (_audioBusy()) { Status = "Dừng phiên đang dùng âm thanh trước khi tạo giọng."; return; }
        var id = SelectedRecording.Id;
        var store = _personalVoiceStore;
        using var cancellation = new CancellationTokenSource(); _buildingVoice = cancellation; IsBuildingVoice = true;
        float[]? samples = null;
        try {
            samples = store.LoadRecording(id);
            var encoder = await PersonalVoiceEncoderInstaller.EnsureAsync(new Progress<string>(message => Status = message), cancellation.Token);
            Status = "Đang tạo hồ sơ VieNeu từ bản thu đã lưu…";
            var embedding = await Task.Run(() => VieNeuSpeakerEncoder.Extract(samples, encoder, cancellation.Token), cancellation.Token);
            try { cancellation.Token.ThrowIfCancellationRequested(); store.SaveModel(id, embedding); }
            finally { Array.Clear(embedding); }
            LoadPreference(); Status = "Đã tạo hồ sơ VieNeu. Chọn giọng trong danh sách để đọc thử.";
        } catch (OperationCanceledException) { Status = "Đã hủy tạo giọng. Bản thu gốc được giữ nguyên."; }
        catch (Exception ex) { Status = "Chưa tạo được giọng: " + ex.Message; }
        finally { if (samples != null) Array.Clear(samples); _buildingVoice = null; IsBuildingVoice = false; }
    }
    [RelayCommand] private void CancelRecordingVoice() => _buildingVoice?.Cancel();
}
