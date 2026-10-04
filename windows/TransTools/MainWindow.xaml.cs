using System.Windows;
using TransTools.ViewModels;
using TransTools.Views;

namespace TransTools;

public partial class MainWindow : Window
{
    private readonly MeetingViewModel _meetingViewModel = new();
    private readonly NotebookViewModel _notebookViewModel = new();
    private readonly QuickTranslateViewModel _translateViewModel = new();
    private readonly ConversationViewModel _conversationViewModel = new();
    private readonly LearningViewModel _learningViewModel = new();
    private readonly SettingsViewModel _settingsViewModel = new();

    private FloatingSubtitleWindow? _subtitleWindow;
    private ChipChipMascotWindow? _mascotWindow;

    public MainWindow()
    {
        InitializeComponent();

        // Connect subtitle updates to floating window
        _meetingViewModel.OnSubtitleUpdated += (orig, vi) =>
        {
            _subtitleWindow?.UpdateSubtitle(orig, vi);
        };

        // Default to Meeting View
        ShowMeetingView();
    }

    private void ShowMeetingView()
    {
        MainContentGrid.Children.Clear();
        MainContentGrid.Children.Add(new MeetingView(_meetingViewModel));
    }

    private void NavMeeting_Checked(object sender, RoutedEventArgs e)
    {
        ShowMeetingView();
    }

    private void NavNotebook_Checked(object sender, RoutedEventArgs e)
    {
        MainContentGrid.Children.Clear();
        MainContentGrid.Children.Add(new NotebookView(_notebookViewModel));
    }

    private void NavTranslate_Checked(object sender, RoutedEventArgs e)
    {
        MainContentGrid.Children.Clear();
        MainContentGrid.Children.Add(new QuickTranslateView(_translateViewModel));
    }

    private void NavConversation_Checked(object sender, RoutedEventArgs e)
    {
        MainContentGrid.Children.Clear();
        MainContentGrid.Children.Add(new ConversationView(_conversationViewModel));
    }

    private void NavLearning_Checked(object sender, RoutedEventArgs e)
    {
        MainContentGrid.Children.Clear();
        MainContentGrid.Children.Add(new LearningView(_learningViewModel));
    }

    private void NavSettings_Checked(object sender, RoutedEventArgs e)
    {
        MainContentGrid.Children.Clear();
        MainContentGrid.Children.Add(new SettingsView(_settingsViewModel));
    }

    private void ToggleSubtitle_Click(object sender, RoutedEventArgs e)
    {
        if (_subtitleWindow == null)
        {
            _subtitleWindow = new FloatingSubtitleWindow();
        }

        if (_subtitleWindow.IsVisible)
        {
            _subtitleWindow.Hide();
        }
        else
        {
            _subtitleWindow.Show();
        }
    }

    private void ToggleMascot_Click(object sender, RoutedEventArgs e)
    {
        if (_mascotWindow == null)
        {
            _mascotWindow = new ChipChipMascotWindow();
        }

        if (_mascotWindow.IsVisible)
        {
            _mascotWindow.Hide();
        }
        else
        {
            _mascotWindow.Show();
        }
    }

    protected override void OnClosed(System.EventArgs e)
    {
        base.OnClosed(e);
        _subtitleWindow?.Close();
        _mascotWindow?.Close();
        _meetingViewModel.StopRecording();
        Application.Current.Shutdown();
    }
}
