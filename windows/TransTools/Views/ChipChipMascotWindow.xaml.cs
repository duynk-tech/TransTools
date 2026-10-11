using System.Windows;
using System.Windows.Input;
using System.Windows.Media.Animation;
namespace TransTools.Views;
public partial class ChipChipMascotWindow : Window
{
    private readonly System.Windows.Threading.DispatcherTimer _reminderTimer = new() { Interval = TimeSpan.FromSeconds(20) };
    private bool _meetingRecording;
    private string _activity = "auto";
    private static readonly Dictionary<string, System.Windows.Media.Imaging.BitmapImage> ActivityImages = LoadActivityImages();
    private static Dictionary<string, System.Windows.Media.Imaging.BitmapImage> LoadActivityImages()
    {
        var images = new Dictionary<string, System.Windows.Media.Imaging.BitmapImage>();
        foreach (var name in new[] { "writing", "thinking", "sleeping", "strolling", "flowers", "coffee" }) {
            var image = new System.Windows.Media.Imaging.BitmapImage(); image.BeginInit();
            image.CacheOption = System.Windows.Media.Imaging.BitmapCacheOption.OnLoad;
            image.DecodePixelWidth = 192;
            image.UriSource = new Uri($"pack://application:,,,/TransTools;component/Resources/Mascot/Activities/{name}.png", UriKind.Absolute);
            image.EndInit(); image.Freeze(); images[name] = image;
        }
        return images;
    }
    private void ActivityChanged(object sender, System.Windows.Controls.SelectionChangedEventArgs e)
    {
        if (ActivityChoice?.SelectedValue is not string choice) return;
        _activity = choice; ApplyActivity();
    }
    private void ApplyActivity()
    {
        if (MascotImage == null) return;
        var selected = _meetingRecording ? "writing" : _activity == "auto" ? "coffee" : _activity;
        if (ActivityImages.TryGetValue(selected, out var image)) MascotImage.Source = image;
    }
    private bool _reminding;
    private bool _wasVisible;
    public event Action? LearningRequested;
    public event Action? MeetingRequested;
    public event Action? SubtitleRequested;
    private void StartMeeting_Click(object sender, RoutedEventArgs e) { MascotMenu.IsOpen = false; MeetingRequested?.Invoke(); }
    private void OpenSubtitle_Click(object sender, RoutedEventArgs e) { MascotMenu.IsOpen = false; SubtitleRequested?.Invoke(); }
    private void StartLearning_Click(object sender, RoutedEventArgs e) { MascotMenu.IsOpen = false; LearningRequested?.Invoke(); }
    private void OpenApplication_Click(object sender, RoutedEventArgs e) { MascotMenu.IsOpen = false; Application.Current.MainWindow.Show(); Application.Current.MainWindow.Activate(); }
    private void ShowMenu(object sender, MouseButtonEventArgs e) { MascotMenu.IsOpen = true; e.Handled = true; }
    private void CloseMenu(object sender, RoutedEventArgs e) => MascotMenu.IsOpen = false;
    public void AttachQuickTranslation(TransTools.ViewModels.QuickTranslateViewModel model)
    {
        QuickTranslationPanel.DataContext = model;
        QuickTranslationPanel.Visibility = Visibility.Visible;
    }
    private void CopyQuickTranslation(object sender, RoutedEventArgs e)
    {
        if (QuickTranslationPanel.DataContext is not TransTools.ViewModels.QuickTranslateViewModel model || string.IsNullOrWhiteSpace(model.TranslatedText)) return;
        try { Clipboard.SetText(model.TranslatedText); model.Status = "Đã sao chép"; }
        catch (Exception) { model.Status = "Chưa sao chép được. Hãy thử lại."; }
    }
    public void SetMeetingState(bool recording, bool canToggle)
    {
        _meetingRecording = recording; ApplyActivity();
        MeetingActionButton.IsEnabled = canToggle;
        MeetingActionIcon.Text = recording ? "\uE71A" : "\uE768";
        MeetingActionLabel.Text = recording ? "Dừng cuộc họp" : "Bắt đầu cuộc họp";
        System.Windows.Automation.AutomationProperties.SetName(MeetingActionButton, MeetingActionLabel.Text);
        MeetingStateLabel.Text = !canToggle ? "Đang xử lý cuộc họp…" : recording ? "Đang ghi chú cuộc họp" : "Hỗ trợ cuộc họp và học ngôn ngữ";
        var brush = new System.Windows.Media.BrushConverter();
        MeetingActionButton.Background = (System.Windows.Media.Brush)brush.ConvertFromString(recording ? "#FFF1F2" : "#EAF4F0")!;
        MeetingActionButton.Foreground = (System.Windows.Media.Brush)brush.ConvertFromString(recording ? "#DC2626" : "#287568")!;
        MeetingActionButton.BorderBrush = (System.Windows.Media.Brush)brush.ConvertFromString(recording ? "#FECDD3" : "#A8CEC3")!;
    }
    public void ShowReminder(string text) {
        _wasVisible = IsVisible; _reminding = true; BubbleText.Text = text; Show(); SpeechBubble.Visibility = Visibility.Visible;
        _reminderTimer.Stop(); _reminderTimer.Start();
    }
    public ChipChipMascotWindow() {
        InitializeComponent(); ApplyActivity();
        MascotMenu.Placement = System.Windows.Controls.Primitives.PlacementMode.Custom;
        MascotMenu.CustomPopupPlacementCallback = (popupSize, targetSize, offset) => [
            new System.Windows.Controls.Primitives.CustomPopupPlacement(new Point(-popupSize.Width, (targetSize.Height - popupSize.Height) / 2), System.Windows.Controls.Primitives.PopupPrimaryAxis.Vertical),
            new System.Windows.Controls.Primitives.CustomPopupPlacement(new Point(targetSize.Width + 10, (targetSize.Height - popupSize.Height) / 2), System.Windows.Controls.Primitives.PopupPrimaryAxis.Vertical)
        ];
        SetBinding(TitleProperty, new System.Windows.Data.Binding("DisplayName") { Source = TransTools.Services.Experience.AssistantIdentity.Shared }); Left = SystemParameters.WorkArea.Right - Width - 30; Top = SystemParameters.WorkArea.Bottom - Height - 30;
        IsVisibleChanged += (_, _) => { if (!IsVisible) { MascotMenu.IsOpen = false; ResetAnimation(); } };
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
