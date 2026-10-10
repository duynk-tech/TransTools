using System.Windows.Controls;
using TransTools.ViewModels;

namespace TransTools.Views;

public partial class MeetingView : UserControl
{
    public MeetingView(MeetingViewModel viewModel)
    {
        InitializeComponent();
        DataContext = viewModel;
        Loaded += (_, _) => { viewModel.Captions.CollectionChanged -= CaptionsChanged; viewModel.Captions.CollectionChanged += CaptionsChanged; };
        Unloaded += (_, _) => viewModel.Captions.CollectionChanged -= CaptionsChanged;
    }
    private void ShowEarphones_Click(object sender, System.Windows.RoutedEventArgs e) { ((MeetingViewModel)DataContext).RefreshPlaybackDevices(); EarphonePopup.IsOpen = !EarphonePopup.IsOpen; }
    private void ShowTranslationSettings_Click(object sender, System.Windows.RoutedEventArgs e) => TranslationSettingsPopup.IsOpen = !TranslationSettingsPopup.IsOpen;
    private void CaptionsChanged(object? sender, System.Collections.Specialized.NotifyCollectionChangedEventArgs e)
    {
        Dispatcher.BeginInvoke(System.Windows.Threading.DispatcherPriority.Loaded, new Action(() => {
            if (CaptionList.Items.Count > 0) CaptionList.ScrollIntoView(CaptionList.Items[^1]);
        }));
    }
}
