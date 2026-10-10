using CommunityToolkit.Mvvm.ComponentModel;
using CommunityToolkit.Mvvm.Input;
using TransTools.Services.Speech;
namespace TransTools.ViewModels;
public partial class VoiceSettingsViewModel : ObservableObject
{
    public SettingsViewModel Management { get; }
    private readonly Func<bool> _audioBusy;
    private bool _loading, _canSave = true;
    public string[] Languages { get; } = ["vi", "en", "ja", "zh", "ko"];
    public string[] Engines => Language == "zh" ? ["Giọng cơ bản", "Edge"] : Language == "vi" && VoiceService.HasVieNeuProcessor ? ["Supertonic 3", "Giọng cơ bản", "Edge", "VieNeu v3 Turbo"] : ["Supertonic 3", "Giọng cơ bản", "Edge"];
    public bool SupportsNatural => Language != "zh";
    public bool CanChangeRate => !IsPreviewing && Engine != "VieNeu v3 Turbo";
    public bool CanConfigure => !IsPreviewing;
    [ObservableProperty] private string _language = "vi";
    [ObservableProperty] private string _engine = "Giọng cơ bản";
    [ObservableProperty] private double _rate = 1;
    [ObservableProperty] private string _sampleText = "Xin chào! Hãy cùng Trans Tools nghe và học ngôn ngữ mỗi ngày.";
    [ObservableProperty] private string _status = "Chọn giọng và nghe thử một đoạn văn.";
    [ObservableProperty] [NotifyPropertyChangedFor(nameof(CanChangeRate), nameof(CanConfigure))] private bool _isPreviewing;
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
        try { var p = VoicePreferences.Get(Language); Engine = Engines.Contains(p.Engine) ? p.Engine : "Giọng cơ bản"; Rate = Engine == "VieNeu v3 Turbo" ? 1 : p.Rate; _canSave = true; }
        catch (Exception ex) { _canSave = false; Status = "Không đọc được cấu hình giọng; giữ nguyên dữ liệu: " + ex.Message; }
        finally { _loading = false; }
    }
    partial void OnLanguageChanged(string value)
    {
        OnPropertyChanged(nameof(Engines)); OnPropertyChanged(nameof(SupportsNatural)); LoadPreference();
        SampleText = value switch { "en" => "Hello! Let us listen and learn together every day.", "ja" => "こんにちは。一緒に言語を学びましょう。", "zh" => "你好！让我们一起学习语言。", "ko" => "안녕하세요! 함께 언어를 배워요.", _ => "Xin chào! Hãy cùng Trans Tools nghe và học ngôn ngữ mỗi ngày." };
    }
    partial void OnEngineChanged(string value) { OnPropertyChanged(nameof(CanChangeRate)); if (value == "VieNeu v3 Turbo") Rate = 1; SavePreference(); }
    partial void OnRateChanged(double value) => SavePreference();
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
