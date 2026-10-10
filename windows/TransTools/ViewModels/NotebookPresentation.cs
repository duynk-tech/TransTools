using System.ComponentModel;
using System.Windows.Data;
using CommunityToolkit.Mvvm.ComponentModel;
using CommunityToolkit.Mvvm.Input;
using TransTools.Models;
namespace TransTools.ViewModels;
public partial class NotebookViewModel
{
    public string[] CaptionModes { get; } = ["Song ngữ", "Tiếng gốc", "Bản dịch"];
    [ObservableProperty] private string _captionMode = "Song ngữ";
    [ObservableProperty] private string _captionSearch = "";
    [ObservableProperty] private double _captionFontSize = 14;
    [ObservableProperty] private ICollectionView? _captionView;
    public bool ShowOriginal => CaptionMode != "Bản dịch";
    public bool ShowTranslation => CaptionMode != "Tiếng gốc";
    partial void OnCaptionModeChanged(string value) { OnPropertyChanged(nameof(ShowOriginal)); OnPropertyChanged(nameof(ShowTranslation)); }
    partial void OnCaptionSearchChanged(string value) => CaptionView?.Refresh();
    partial void OnSelectedSessionChanged(MeetingSession? value)
    {
        OnPropertyChanged(nameof(IsConversationSelected)); OnPropertyChanged(nameof(IsMeetingSelected));
        CaptionView = CollectionViewSource.GetDefaultView(value?.Captions ?? new List<Caption>());
        CaptionView.Filter = item => item is Caption c && (string.IsNullOrWhiteSpace(CaptionSearch) || c.Original.Contains(CaptionSearch, StringComparison.OrdinalIgnoreCase) || c.Vietnamese.Contains(CaptionSearch, StringComparison.OrdinalIgnoreCase));
    }
    [RelayCommand] private void IncreaseCaptionFont() => CaptionFontSize = Math.Min(24, CaptionFontSize + 1);
    [RelayCommand] private void DecreaseCaptionFont() => CaptionFontSize = Math.Max(10, CaptionFontSize - 1);
}

public partial class NotebookViewModel
{
    [RelayCommand] private async Task SpeakOriginalAsync(Caption? caption)
    {
        if (caption == null || string.IsNullOrWhiteSpace(caption.Original)) return;
        try { await TransTools.Services.Speech.VoicePreferences.SpeakAsync(caption.Original, SelectedSession?.SourceLanguage ?? "en"); }
        catch (Exception ex) { Status = ex.Message; }
    }
    [RelayCommand] private async Task SpeakTranslationAsync(Caption? caption)
    {
        if (caption == null || string.IsNullOrWhiteSpace(caption.Vietnamese)) return;
        try { await TransTools.Services.Speech.VoicePreferences.SpeakAsync(caption.Vietnamese, "vi"); }
        catch (Exception ex) { Status = ex.Message; }
    }
    [RelayCommand] private void CopyOriginal(Caption? caption) => CopyCaptionText(caption?.Original);
    [RelayCommand] private void CopyTranslation(Caption? caption) => CopyCaptionText(caption?.Vietnamese);
    [RelayCommand] private void CopyBilingual(Caption? caption)
    {
        if (caption != null) CopyCaptionText($"[{caption.FormattedTimestamp}]\n{caption.Original}\n{caption.Vietnamese}");
    }
    private void CopyCaptionText(string? text)
    {
        if (string.IsNullOrWhiteSpace(text)) return;
        try { System.Windows.Clipboard.SetText(text); Status = "Đã sao chép"; }
        catch (Exception ex) { Status = ex.Message; }
    }
}
