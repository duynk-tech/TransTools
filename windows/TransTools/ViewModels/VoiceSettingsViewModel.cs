using CommunityToolkit.Mvvm.ComponentModel;
using CommunityToolkit.Mvvm.Input;
using TransTools.Services.Speech;
using System.Collections.ObjectModel;
using TransTools.Services.Storage;
namespace TransTools.ViewModels;
public sealed record PersonalVoiceOption(Guid? Id, string Name);
public partial class VoiceSettingsViewModel : ObservableObject
{
    public PersonalVoiceRecorderViewModel CreateRecorder() => new(() => _audioBusy() || IsPreviewing);
    public SettingsViewModel Management { get; }
    private readonly Func<bool> _audioBusy;
    private bool _loading, _canSave = true;
    public string[] Languages { get; } = ["vi", "en", "ja", "zh", "ko"];
    public string[] Engines => Language == "zh" ? ["Giọng cơ bản", "Edge"] : Language == "vi" && VoiceService.HasVieNeuProcessor ? ["Supertonic 3", "Giọng cơ bản", "Edge", "VieNeu v3 Turbo"] : ["Supertonic 3", "Giọng cơ bản", "Edge"];
    public bool SupportsNatural => Language != "zh";
    public bool CanManagePersonalVoice => CanConfigure && SupportsPersonalVoice && SelectedPersonalVoice?.Id != null;
    public bool SupportsPersonalVoice => Language == "vi" && Engine == "VieNeu v3 Turbo";
    public ObservableCollection<PersonalVoiceOption> PersonalVoices { get; } = new();
    [ObservableProperty] [NotifyPropertyChangedFor(nameof(CanManagePersonalVoice))] private PersonalVoiceOption? _selectedPersonalVoice;
    public string PersonalVoiceHint => PersonalVoices.Count > 1 ? "Chọn hồ sơ giọng đã lưu để đọc và xuất audio." : "Chưa có giọng cá nhân. Giọng dựng sẵn vẫn dùng được.";
    public bool CanChangeRate => CanConfigure && Engine != "VieNeu v3 Turbo";
    public bool CanConfigure => !IsPreviewing && !IsBuildingVoice;
    [ObservableProperty] private string _language = "vi";
    [ObservableProperty] private string _engine = "Giọng cơ bản";
    [ObservableProperty] private double _rate = 1;
    [ObservableProperty] private string _sampleText = "Xin chào! Hãy cùng Trans Tools nghe và học ngôn ngữ mỗi ngày.";
    [ObservableProperty] private string _status = "Chọn giọng và nghe thử một đoạn văn.";
    [ObservableProperty] [NotifyCanExecuteChangedFor(nameof(CreateRecordingVoiceCommand))] [NotifyPropertyChangedFor(nameof(CanChangeRate), nameof(CanConfigure), nameof(CanManagePersonalVoice))] private bool _isPreviewing;
    public VoiceSettingsViewModel(SettingsViewModel management, Func<bool>? audioBusy = null)
    {
        Management = management; _audioBusy = audioBusy ?? (() => false); LoadPreference();
        VoicePreferences.Changed += code => {
            if (code != Language || IsPreviewing) return;
            var dispatcher = System.Windows.Application.Current?.Dispatcher;
            if (dispatcher == null || dispatcher.CheckAccess()) LoadPreference(); else dispatcher.InvokeAsync(() => { if (!IsPreviewing && code == Language) LoadPreference(); });
        };
    }
    private void LoadPreference()
    {
        _loading = true;
        try { var p = VoicePreferences.Get(Language); Engine = Engines.Contains(p.Engine) ? p.Engine : "Giọng cơ bản"; Rate = Engine == "VieNeu v3 Turbo" ? 1 : p.Rate;
            PersonalVoices.Clear(); PersonalVoices.Add(new(null, "Giọng dựng sẵn"));
            var store = new PersonalVoiceStore(PersonalVoiceStore.DefaultRoot); RefreshRecordings(store);
            foreach (var profile in store.Load().Where(profile => store.HasModel(profile.Id))) PersonalVoices.Add(new(profile.Id, profile.Name));
            if (p.PersonalVoiceId is Guid missingId && PersonalVoices.All(voice => voice.Id != missingId)) PersonalVoices.Add(new(missingId, "Giọng đã chọn không còn dữ liệu — chọn lại giọng"));
            SelectedPersonalVoice = PersonalVoices.FirstOrDefault(voice => voice.Id == p.PersonalVoiceId) ?? PersonalVoices[0];
            OnPropertyChanged(nameof(PersonalVoiceHint)); _canSave = true; }
        catch (Exception ex) { _canSave = false; Status = "Không đọc được cấu hình giọng; giữ nguyên dữ liệu: " + ex.Message; }
        finally { _loading = false; }
    }
    partial void OnIsPreviewingChanged(bool value) { if (!value) LoadPreference(); }
    partial void OnLanguageChanged(string value)
    {
        OnPropertyChanged(nameof(Engines)); OnPropertyChanged(nameof(SupportsNatural)); OnPropertyChanged(nameof(SupportsPersonalVoice)); OnPropertyChanged(nameof(CanManagePersonalVoice)); LoadPreference();
        SampleText = value switch { "en" => "Hello! Let us listen and learn together every day.", "ja" => "こんにちは。一緒に言語を学びましょう。", "zh" => "你好！让我们一起学习语言。", "ko" => "안녕하세요! 함께 언어를 배워요.", _ => "Xin chào! Hãy cùng Trans Tools nghe và học ngôn ngữ mỗi ngày." };
    }
    partial void OnEngineChanged(string value) { OnPropertyChanged(nameof(CanChangeRate)); OnPropertyChanged(nameof(SupportsPersonalVoice)); OnPropertyChanged(nameof(CanManagePersonalVoice)); if (value == "VieNeu v3 Turbo") Rate = 1; SavePreference(); }
    partial void OnRateChanged(double value) => SavePreference();
    partial void OnSelectedPersonalVoiceChanged(PersonalVoiceOption? value)
    {
        if (_loading || value == null || !SupportsPersonalVoice) return;
        if (_audioBusy() || IsPreviewing) { Status = "Dừng phiên đang dùng âm thanh trước khi đổi giọng."; LoadPreference(); return; }
        try { VoicePreferences.SelectPersonalVoice(value.Id); Status = value.Id == null ? "Đã chọn giọng dựng sẵn" : "Đã chọn giọng " + value.Name; }
        catch (Exception ex) { LoadPreference(); Status = "Chưa chọn được giọng: " + ex.Message; }
    }
    [RelayCommand] private void RefreshPersonalVoices() => LoadPreference();
    public void RenamePersonalVoice(string name)
    {
        if (!CanManagePersonalVoice || SelectedPersonalVoice?.Id is not Guid id) return;
        if (_audioBusy()) { Status = "Dừng phiên đang dùng âm thanh trước khi đổi tên giọng."; return; }
        try { new PersonalVoiceStore(PersonalVoiceStore.DefaultRoot).Rename(id, name); LoadPreference(); Status = "Đã đổi tên giọng."; }
        catch (Exception ex) { Status = "Chưa đổi được tên: " + ex.Message; }
    }
    public void DeletePersonalVoice(Guid id)
    {
        if (!CanManagePersonalVoice || SelectedPersonalVoice?.Id != id) return;
        if (_audioBusy()) { Status = "Dừng phiên đang dùng âm thanh trước khi xóa giọng."; return; }
        try {
            new PersonalVoiceStore(PersonalVoiceStore.DefaultRoot).MoveToTrash(id);
            if (VoicePreferences.Get("vi").PersonalVoiceId == id) VoicePreferences.SelectPersonalVoice(null);
            LoadPreference(); Status = "Đã chuyển giọng vào Thùng rác và dùng giọng dựng sẵn.";
        } catch (Exception ex) { LoadPreference(); Status = "Chưa hoàn tất xóa giọng: " + ex.Message; }
    }
    private void SavePreference()
    {
        if (_loading || !_canSave || !Engines.Contains(Engine)) return;
        try { VoicePreferences.Save(Language, Engine, Rate); Status = "Đã lưu giọng đọc cho ngôn ngữ này"; }
        catch (Exception ex) { Status = "Chưa lưu được giọng đọc: " + ex.Message; }
    }
    [RelayCommand] private async Task PreviewAsync()
    {
        if (IsPreviewing || string.IsNullOrWhiteSpace(SampleText)) return;
        if (_audioBusy()) { Status = "Dừng phiên đang dùng âm thanh trước khi nghe thử."; return; }
        IsPreviewing = true;
        try { Status = "Đang nghe thử…"; await VoiceService.Shared.SpeakAsync(SampleText, Language, Engine, Rate); Status = "Đã nghe thử"; }
        catch (Exception ex) { Status = ex.Message; }
        finally { IsPreviewing = false; }
    }
    [RelayCommand] private void StopPreview() { if (IsPreviewing) VoiceService.Shared.Stop(); }
}
