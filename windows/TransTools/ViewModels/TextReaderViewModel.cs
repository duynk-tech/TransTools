using System.IO;
using CommunityToolkit.Mvvm.ComponentModel;
using CommunityToolkit.Mvvm.Input;
using Microsoft.Win32;
using TransTools.Services.Speech;
namespace TransTools.ViewModels;
public partial class TextReaderViewModel : ObservableObject
{
    public string[] Languages { get; } = { "vi", "en", "ja", "zh", "ko" };
    public string[] Engines => Language == "zh" ? new[] { "Edge", "Giọng cơ bản" } : Language == "vi" && VoiceService.HasVieNeuProcessor ? new[] { "Edge", "Supertonic 3", "VieNeu v3 Turbo", "Giọng cơ bản" } : new[] { "Edge", "Supertonic 3", "Giọng cơ bản" };
    public bool CanChangeRate => Engine != "VieNeu v3 Turbo";
    [ObservableProperty] private string _text = "";
    [ObservableProperty] private string _language = "vi";
    [ObservableProperty] private string _engine = "Edge";
    [ObservableProperty] private double _rate = 1;
    [ObservableProperty] private string _status = "Nhập đoạn văn để nghe hoặc lưu audio";
    [ObservableProperty] private bool _isBusy;
    public bool CanExport => Engine != "Giọng cơ bản";
    private bool _loadingPreference;
    public TextReaderViewModel() => LoadPreference();
    private void LoadPreference() { _loadingPreference = true; try { var preference = VoicePreferences.Get(Language); Engine = Engines.Contains(preference.Engine) ? preference.Engine : "Giọng cơ bản"; Rate = Engine == "VieNeu v3 Turbo" ? 1 : preference.Rate; } finally { _loadingPreference = false; } }
    partial void OnLanguageChanged(string value) { OnPropertyChanged(nameof(Engines)); LoadPreference(); }
    partial void OnRateChanged(double value) { if (!_loadingPreference) VoicePreferences.Save(Language, Engine, value); }
    partial void OnEngineChanged(string value) { OnPropertyChanged(nameof(CanExport)); OnPropertyChanged(nameof(CanChangeRate)); if (value == "VieNeu v3 Turbo") Rate = 1; if (!_loadingPreference) VoicePreferences.Save(Language, value, Rate); }
    [RelayCommand] private async Task ReadAsync()
    {
        if (IsBusy || string.IsNullOrWhiteSpace(Text)) return; IsBusy = true;
        try { Status = "Đang đọc..."; await VoiceService.Shared.SpeakAsync(Text, Language, Engine, Rate); Status = "Đã hoàn tất"; }
        catch (Exception ex) { Status = ex.Message; }
        finally { IsBusy = false; }
    }
    [RelayCommand] private void Stop() => VoiceService.Shared.Stop();
    [RelayCommand] private async Task ExportAsync()
    {
        if (IsBusy || !CanExport || string.IsNullOrWhiteSpace(Text)) return;
        var ext = Engine == "Edge" ? "mp3" : "wav";
        var dialog = new SaveFileDialog { Filter = $"Audio (*.{ext})|*.{ext}", FileName = "Trans Tools Audio." + ext };
        if (dialog.ShowDialog() != true) return; IsBusy = true;
        try { Status = "Đang tạo audio..."; await VoiceService.Shared.ExportAsync(Text, Language, Engine, Rate, dialog.FileName, CancellationToken.None); Status = "Đã lưu audio"; }
        catch (Exception ex) { Status = ex.Message; }
        finally { IsBusy = false; }
    }
}
