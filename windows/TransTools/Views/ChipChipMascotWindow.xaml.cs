using System.Windows;
using System.Windows.Input;
using System.Windows.Media.Animation;
namespace TransTools.Views;
public partial class ChipChipMascotWindow : Window
{
    private readonly System.Windows.Threading.DispatcherTimer _reminderTimer = new() { Interval = TimeSpan.FromSeconds(20) };
    private bool _reminding;
    private bool _wasVisible;
    public event Action? LearningRequested;
    public event Action? MeetingRequested;
    public event Action? SubtitleRequested;
    private void StartMeeting_Click(object sender, RoutedEventArgs e) => MeetingRequested?.Invoke();
    private void OpenSubtitle_Click(object sender, RoutedEventArgs e) => SubtitleRequested?.Invoke();
    private void StartLearning_Click(object sender, RoutedEventArgs e) => LearningRequested?.Invoke();
    private void OpenApplication_Click(object sender, RoutedEventArgs e) { Application.Current.MainWindow.Show(); Application.Current.MainWindow.Activate(); }
    public void ShowReminder(string text) {
        _wasVisible = IsVisible; _reminding = true; BubbleText.Text = text; Show(); SpeechBubble.Visibility = Visibility.Visible;
        _reminderTimer.Stop(); _reminderTimer.Start();
    }
    public ChipChipMascotWindow() {
        InitializeComponent(); SetBinding(TitleProperty, new System.Windows.Data.Binding("DisplayName") { Source = TransTools.Services.Experience.AssistantIdentity.Shared }); Left = SystemParameters.WorkArea.Right - Width - 30; Top = SystemParameters.WorkArea.Bottom - Height - 30;
        IsVisibleChanged += (_, _) => { if (!IsVisible) ResetAnimation(); };
        _reminderTimer.Tick += (_, _) => { _reminderTimer.Stop(); _reminding = false; ResetAnimation(); if (!_wasVisible) Hide(); };
        Closed += (_, _) => { _reminderTimer.Stop(); ResetAnimation(); };
    }
    private void MascotEnter(object sender, MouseEventArgs e) {
        if (!_reminding) BubbleText.Text = "Cùng học với " + TransTools.Services.Experience.AssistantIdentity.Shared.DisplayName + " nhé!";
        SpeechBubble.Visibility = Visibility.Visible;
        if (SystemParameters.ClientAreaAnimation) MascotRotation.BeginAnimation(System.Windows.Media.RotateTransform.AngleProperty,
            new DoubleAnimation(-5, 5, TimeSpan.FromMilliseconds(250)) { AutoReverse = true, RepeatBehavior = new RepeatBehavior(2), FillBehavior = FillBehavior.Stop });
    }
    private void ResetAnimation() { MascotRotation.BeginAnimation(System.Windows.Media.RotateTransform.AngleProperty, null); MascotRotation.Angle = 0; if (!_reminding) SpeechBubble.Visibility = Visibility.Collapsed; }
    private void MascotLeave(object sender, MouseEventArgs e) => ResetAnimation();
    private void MascotDown(object sender, MouseButtonEventArgs e) {
        if (e.ClickCount == 2) { LearningRequested?.Invoke(); e.Handled = true; return; }
        if (e.LeftButton == MouseButtonState.Pressed) DragMove();
    }
}
