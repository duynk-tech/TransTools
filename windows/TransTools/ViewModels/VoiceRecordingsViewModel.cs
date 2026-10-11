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
    [ObservableProperty] [NotifyPropertyChangedFor(nameof(CanManageRecording))] [NotifyCanExecuteChangedFor(nameof(CreateRecordingVoiceCommand))] private PersonalVoiceProfile? _selectedRecording;
    [ObservableProperty]
    [NotifyCanExecuteChangedFor(nameof(CreateRecordingVoiceCommand))]
    [NotifyPropertyChangedFor(nameof(CanConfigure), nameof(CanManagePersonalVoice), nameof(CanChangeRate), nameof(CanManageRecording))]
    private bool _isBuildingVoice;
    private CancellationTokenSource? _buildingVoice;
    private CancellationTokenSource? _recordingPreview;
    public bool CanManageRecording => CanConfigure && SelectedRecording != null;
    public void RenameRecording(string name)
    {
        if (!CanManageRecording || SelectedRecording == null || _audioBusy()) return;
        try { new PersonalVoiceStore(PersonalVoiceStore.DefaultRoot).Rename(SelectedRecording.Id, name); LoadPreference(); Status = "Đã đổi tên bản thu."; }
        catch (Exception ex) { Status = "Chưa đổi được tên: " + ex.Message; }
    }
    public void DeleteRecording(Guid id)
    {
        if (!CanManageRecording || SelectedRecording?.Id != id || _audioBusy()) return;
        try {
            new PersonalVoiceStore(PersonalVoiceStore.DefaultRoot).MoveToTrash(id);
            if (VoicePreferences.Get("vi").PersonalVoiceId == id) VoicePreferences.SelectPersonalVoice(null);
            LoadPreference(); Status = "Đã chuyển bản thu và hồ sơ giọng vào Thùng rác.";
        } catch (Exception ex) { LoadPreference(); Status = "Chưa xóa được bản thu: " + ex.Message; }
    }
    [RelayCommand] private void OpenRecordingFolder()
    {
        if (!CanManageRecording || SelectedRecording == null) return;
        try { Process.Start(new ProcessStartInfo("explorer.exe", "/select,\"" + new PersonalVoiceStore(PersonalVoiceStore.DefaultRoot).RecordingPath(SelectedRecording.Id) + "\"") { UseShellExecute = true }); }
        catch (Exception ex) { Status = "Chưa mở được thư mục: " + ex.Message; }
    }
    [RelayCommand] private async Task PreviewOriginalRecordingAsync()
    {
        if (!CanManageRecording || SelectedRecording == null) return;
        if (_audioBusy()) { Status = "Dừng phiên đang dùng âm thanh trước khi nghe bản thu."; return; }
        var id = SelectedRecording.Id;
        using var cancellation = new CancellationTokenSource(); _recordingPreview = cancellation; IsPreviewing = true;
        try {
            var store = new PersonalVoiceStore(PersonalVoiceStore.DefaultRoot);
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
        OnPropertyChanged(nameof(HasRecordings));
    }
    private bool CanCreateSavedVoice() => CanConfigure && SelectedRecording != null;
    [RelayCommand(CanExecute = nameof(CanCreateSavedVoice))] private async Task CreateRecordingVoiceAsync()
    {
        if (!CanConfigure || SelectedRecording == null) return;
        if (_audioBusy()) { Status = "Dừng phiên đang dùng âm thanh trước khi tạo giọng."; return; }
        var id = SelectedRecording.Id;
        var store = new PersonalVoiceStore(PersonalVoiceStore.DefaultRoot);
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
