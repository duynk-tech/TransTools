using System.ComponentModel;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;
using System.Windows.Threading;
using TransTools.ViewModels;

namespace TransTools.Views;

public partial class MeetingView : UserControl
{
    private readonly MeetingViewModel _viewModel;
    private bool _scrollPending;
    private int _loadRevision;
    public event Action<string>? VoiceSettingsRequested;
    private void VoiceSettings_Click(object sender, RoutedEventArgs e)
    {
        EarphonePopup.IsOpen = false;
        VoiceSettingsRequested?.Invoke(_viewModel.ReadTarget == "Tiếng gốc" ? _viewModel.SourceLanguage == "auto" ? "en" : _viewModel.SourceLanguage : _viewModel.TargetLanguage);
    }
    public MeetingView(MeetingViewModel viewModel)
    {
        InitializeComponent(); _viewModel = viewModel; DataContext = viewModel;
        Loaded += (_, _) => {
            Detach(); _loadRevision++; _scrollPending = false;
            viewModel.Captions.CollectionChanged += CaptionsChanged;
            viewModel.PropertyChanged += PresentationChanged;
            viewModel.OnCaptionLayoutChanged += ScrollLatest;
            ScrollLatest();
        };
        Unloaded += (_, _) => { Detach(); _loadRevision++; _scrollPending = false; };
        CaptionList.SizeChanged += (_, _) => ScrollLatest();
    }
    private void Detach()
    {
        _viewModel.Captions.CollectionChanged -= CaptionsChanged;
        _viewModel.PropertyChanged -= PresentationChanged;
        _viewModel.OnCaptionLayoutChanged -= ScrollLatest;
    }
    private void ShowEarphones_Click(object sender, RoutedEventArgs e) { _viewModel.RefreshPlaybackDevices(); EarphonePopup.IsOpen = !EarphonePopup.IsOpen; }
    private void ShowTranslationSettings_Click(object sender, RoutedEventArgs e) => TranslationSettingsPopup.IsOpen = !TranslationSettingsPopup.IsOpen;
    private void CaptionsChanged(object? sender, System.Collections.Specialized.NotifyCollectionChangedEventArgs e) => ScrollLatest();
    private void PresentationChanged(object? sender, PropertyChangedEventArgs e)
    {
        if (e.PropertyName is nameof(MeetingViewModel.DisplayModeKey) or nameof(MeetingViewModel.SourceLanguage) or nameof(MeetingViewModel.TargetLanguage)) ScrollLatest();
    }
    private void ScrollLatest()
    {
        if (!IsLoaded || _scrollPending) return;
        _scrollPending = true;
        var revision = _loadRevision;
        Dispatcher.BeginInvoke(DispatcherPriority.Loaded, new Action(() => {
            if (!IsLoaded || revision != _loadRevision) return;
            ScrollAfterLayout();
            Dispatcher.BeginInvoke(DispatcherPriority.ContextIdle, new Action(() => {
                if (!IsLoaded || revision != _loadRevision) return;
                ScrollAfterLayout(); _scrollPending = false;
            }));
        }));
    }
    private void ScrollAfterLayout()
    {
        if (CaptionList.Items.Count == 0) { FindScrollViewer(CaptionList)?.ScrollToTop(); return; }
        CaptionList.ScrollIntoView(CaptionList.Items[^1]);
        CaptionList.UpdateLayout();
        FindScrollViewer(CaptionList)?.ScrollToEnd();
    }
    private static ScrollViewer? FindScrollViewer(DependencyObject root)
    {
        if (root is ScrollViewer scroll) return scroll;
        for (var i = 0; i < VisualTreeHelper.GetChildrenCount(root); i++) {
            var found = FindScrollViewer(VisualTreeHelper.GetChild(root, i)); if (found != null) return found;
        }
        return null;
    }
}
