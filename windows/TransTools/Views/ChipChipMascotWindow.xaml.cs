using System.Windows;
using System.Windows.Input;
using System.Windows.Media.Animation;
namespace TransTools.Views;
public partial class ChipChipMascotWindow : Window
{
    private readonly System.Windows.Threading.DispatcherTimer _idlePoseTimer = new() { Interval = TimeSpan.FromSeconds(20) };
    private readonly System.Windows.Threading.DispatcherTimer _reminderTimer = new() { Interval = TimeSpan.FromSeconds(20) };
    private bool _meetingRecording;
    public Func<bool>? WorkBusy { get; set; }
    private readonly System.Windows.Threading.DispatcherTimer _walkTimer = new() { Interval = TimeSpan.FromSeconds(1) };
    private DateTime _walkTick = DateTime.UtcNow, _walkPause;
    private int _walkDirection = -1;
    private bool _dragging;
    [System.Runtime.InteropServices.StructLayout(System.Runtime.InteropServices.LayoutKind.Sequential)]
    private struct LastInput { public uint Size; public uint Tick; }
    [System.Runtime.InteropServices.DllImport("user32.dll")] private static extern bool GetLastInputInfo(ref LastInput value);
    private static double IdleSeconds() { var input = new LastInput { Size = (uint)System.Runtime.InteropServices.Marshal.SizeOf<LastInput>() }; return GetLastInputInfo(ref input) ? unchecked((uint)Environment.TickCount - input.Tick) / 1000.0 : 0; }
    private void StepWalking() {
        var now = DateTime.UtcNow; var elapsed = (now - _walkTick).TotalSeconds; _walkTick = now;
        var interacting = _dragging || IsMouseOver || MascotMenu.IsOpen || _reminding || Mouse.LeftButton == MouseButtonState.Pressed;
        if (!TransTools.Services.Experience.MascotWalkPolicy.CanWalk(IsVisible, _activity == "strolling", _meetingRecording || WorkBusy?.Invoke() == true, interacting, !SystemParameters.ClientAreaAnimation, IdleSeconds()) || now < _walkPause) {
            _walkTimer.Interval = TimeSpan.FromSeconds(1); return;
        }
        var area = WindowMonitorArea.WorkArea(this);
        var step = TransTools.Services.Experience.MascotWalkPolicy.Step(Left, _walkDirection, area.Left + 16, area.Right - Width - 16, elapsed);
        Left = step.X; Top = Math.Max(area.Top, area.Bottom - Height - 2); _walkDirection = step.Direction;
        if (step.PauseSeconds > 0) _walkPause = now.AddSeconds(step.PauseSeconds);
        _walkTimer.Interval = TimeSpan.FromSeconds(1.0 / 24);
    }
    public bool IsIdlePoseTimerRunning => _idlePoseTimer.IsEnabled;
    public bool IsWalkTimerRunning => _walkTimer.IsEnabled;
    public void RefreshWalkingState() { UpdateWalking(); ApplyActivity(); UpdateIdlePoseTimer(); }
    private void UpdateIdlePoseTimer() {
        _idlePoseTimer.Stop();
        if (IsVisible && _activity == "auto" && !_meetingRecording && WorkBusy?.Invoke() != true) _idlePoseTimer.Start();
    }
    private void UpdateWalking() {
        _walkTimer.Stop();
        if (IsVisible && _activity == "strolling" && !_meetingRecording && WorkBusy?.Invoke() != true) { _walkTick = DateTime.UtcNow; _walkTimer.Interval = TimeSpan.FromSeconds(1); _walkTimer.Start(); }
    }
    private string _activity = "auto";
    private readonly TransTools.Services.Experience.MascotPreferences _preferences;
    private bool _loadingPreferences = true;
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
        _activity = choice; ApplyActivity(); UpdateWalking(); UpdateIdlePoseTimer();
        if (!_loadingPreferences) { try { _preferences.Save(choice); } catch { BubbleText.Text = "Chưa lưu được hoạt cảnh. Bạn có thể chọn lại."; } }
    }
    private void ApplyActivity()
    {
        if (MascotImage == null) return;
        var selected = _meetingRecording ? "writing" : _activity == "auto" ? TransTools.Services.Experience.MascotWalkPolicy.IdlePose(IdleSeconds(), DateTime.Now.Hour, WorkBusy?.Invoke() == true, ForegroundProcess(), !SystemParameters.ClientAreaAnimation) : _activity;
        if (ActivityImages.TryGetValue(selected, out var image)) MascotImage.Source = image;
    }
    [System.Runtime.InteropServices.DllImport("user32.dll")] private static extern IntPtr GetForegroundWindow();
    [System.Runtime.InteropServices.DllImport("user32.dll")] private static extern uint GetWindowThreadProcessId(IntPtr window, out uint processId);
    private static string ForegroundProcess()
    {
        // Process name only, never window titles, document text or keystrokes.
        try {
            GetWindowThreadProcessId(GetForegroundWindow(), out var id);
            if (id == 0 || id > int.MaxValue) return "";
            using var process = System.Diagnostics.Process.GetProcessById((int)id);
            return process.ProcessName;
        } catch { return ""; }
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
        _meetingRecording = recording; ApplyActivity(); UpdateWalking(); UpdateIdlePoseTimer();
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
    public ChipChipMascotWindow(TransTools.Services.Experience.MascotPreferences? preferences = null) {
        _preferences = preferences ?? new();
        InitializeComponent(); _activity = _preferences.Load(); ActivityChoice.SelectedValue = _activity; _loadingPreferences = false; ApplyActivity();
        MascotMenu.Placement = System.Windows.Controls.Primitives.PlacementMode.Custom;
        MascotMenu.CustomPopupPlacementCallback = (popupSize, targetSize, offset) => [
            new System.Windows.Controls.Primitives.CustomPopupPlacement(new Point(-popupSize.Width, (targetSize.Height - popupSize.Height) / 2), System.Windows.Controls.Primitives.PopupPrimaryAxis.Vertical),
            new System.Windows.Controls.Primitives.CustomPopupPlacement(new Point(targetSize.Width + 10, (targetSize.Height - popupSize.Height) / 2), System.Windows.Controls.Primitives.PopupPrimaryAxis.Vertical)
        ];
        SetBinding(TitleProperty, new System.Windows.Data.Binding("DisplayName") { Source = TransTools.Services.Experience.AssistantIdentity.Shared }); Left = SystemParameters.WorkArea.Right - Width - 30; Top = SystemParameters.WorkArea.Bottom - Height - 30;
        var savedPosition = _preferences.LoadPosition();
        if (savedPosition is { } position) { Left = position.Left; Top = position.Top; }
        SourceInitialized += (_, _) => {
            var area = WindowMonitorArea.WorkArea(this);
            Left = Math.Clamp(Left, area.Left, Math.Max(area.Left, area.Right - Width));
            Top = Math.Clamp(Top, area.Top, Math.Max(area.Top, area.Bottom - Height));
        };
        _idlePoseTimer.Tick += (_, _) => { if (_activity == "auto") ApplyActivity(); };
        _walkTimer.Tick += (_, _) => StepWalking();
        IsVisibleChanged += (_, _) => { UpdateWalking(); if (IsVisible) ApplyActivity(); UpdateIdlePoseTimer(); if (!IsVisible) { SavePosition(); MascotMenu.IsOpen = false; ResetAnimation(); } };
        _reminderTimer.Tick += (_, _) => { _reminderTimer.Stop(); _reminding = false; ResetAnimation(); if (!_wasVisible) Hide(); };
        Closed += (_, _) => { SavePosition(); _idlePoseTimer.Stop(); _walkTimer.Stop(); _reminderTimer.Stop(); ResetAnimation(); };
    }
    private void SavePosition() { try { _preferences.SavePosition(Left, Top); } catch { } }
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
        if (e.LeftButton == MouseButtonState.Pressed) { _dragging = true; _walkTimer.Stop(); try { DragMove(); } finally { _dragging = false; SavePosition(); UpdateWalking(); } }
    }
}
