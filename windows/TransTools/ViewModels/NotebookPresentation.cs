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
    [ObservableProperty, NotifyCanExecuteChangedFor(nameof(IncreaseCaptionFontCommand)), NotifyCanExecuteChangedFor(nameof(DecreaseCaptionFontCommand))] private double _captionFontSize = 14;
    [ObservableProperty] private ICollectionView? _captionView;
    public string CaptionModeKey => CaptionMode == "Tiếng gốc" ? "original" : CaptionMode == "Bản dịch" ? "translation" : "bilingual";
    public bool ShowOriginal => CaptionMode != "Bản dịch";
    public bool ShowTranslation => CaptionMode != "Tiếng gốc";
    partial void OnCaptionModeChanged(string value) { OnPropertyChanged(nameof(ShowOriginal)); OnPropertyChanged(nameof(ShowTranslation)); OnPropertyChanged(nameof(CaptionModeKey)); }
    [RelayCommand] private void ClearCaptionSearch() => CaptionSearch = "";
    public bool HasSelectedSession => SelectedSession != null;
    public int FilteredCaptionCount => CaptionView?.Cast<Caption>().Count() ?? 0;
    partial void OnCaptionSearchChanged(string value) => CaptionView?.Refresh();
    partial void OnCaptionViewChanged(ICollectionView? oldValue, ICollectionView? newValue)
    {
        if (oldValue != null) oldValue.CollectionChanged -= CaptionViewChanged;
        if (newValue != null) newValue.CollectionChanged += CaptionViewChanged;
        OnPropertyChanged(nameof(FilteredCaptionCount));
    }
    private void CaptionViewChanged(object? sender, System.Collections.Specialized.NotifyCollectionChangedEventArgs e) => OnPropertyChanged(nameof(FilteredCaptionCount));
    partial void OnSelectedSessionChanged(MeetingSession? value)
    {
        OnPropertyChanged(nameof(IsConversationSelected)); OnPropertyChanged(nameof(IsMeetingSelected)); OnPropertyChanged(nameof(HasSelectedSession));
        CaptionView = CollectionViewSource.GetDefaultView(value?.Captions ?? new List<Caption>());
        CaptionView.Filter = item => item is Caption c && (string.IsNullOrWhiteSpace(CaptionSearch) || c.Original.Contains(CaptionSearch, StringComparison.OrdinalIgnoreCase) || c.Vietnamese.Contains(CaptionSearch, StringComparison.OrdinalIgnoreCase));
    }
    private bool CanIncreaseCaptionFont() => CaptionFontSize < 22;
    [RelayCommand(CanExecute = nameof(CanIncreaseCaptionFont))] private void IncreaseCaptionFont() => CaptionFontSize = Math.Min(22, CaptionFontSize + 1);
    private bool CanDecreaseCaptionFont() => CaptionFontSize > 12;
    [RelayCommand(CanExecute = nameof(CanDecreaseCaptionFont))] private void DecreaseCaptionFont() => CaptionFontSize = Math.Max(12, CaptionFontSize - 1);
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
