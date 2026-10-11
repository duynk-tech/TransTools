using CommunityToolkit.Mvvm.ComponentModel;
using CommunityToolkit.Mvvm.Input;
using System.Collections.ObjectModel;
using TransTools.Services.Storage;
using TransTools.Services.Speech;
namespace TransTools.ViewModels;

public partial class VoiceSettingsViewModel
{
    public ObservableCollection<PersonalVoiceProfile> Recordings { get; } = new();
    [ObservableProperty] [NotifyCanExecuteChangedFor(nameof(CreateRecordingVoiceCommand))] private PersonalVoiceProfile? _selectedRecording;
    [ObservableProperty]
    [NotifyCanExecuteChangedFor(nameof(CreateRecordingVoiceCommand))]
    [NotifyPropertyChangedFor(nameof(CanConfigure), nameof(CanManagePersonalVoice), nameof(CanChangeRate))]
    private bool _isBuildingVoice;
    private CancellationTokenSource? _buildingVoice;
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
