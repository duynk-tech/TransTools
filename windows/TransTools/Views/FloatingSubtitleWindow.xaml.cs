using System.Collections.ObjectModel;
using System.Globalization;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Controls.Primitives;
using System.Windows.Input;
using System.Windows.Media;
using TransTools.Models;
using TransTools.Services.Experience;
namespace TransTools.Views;
public partial class FloatingSubtitleWindow : Window
{
    public event Action? StopRequested;
    public event Action? StartRequested;
    public event Action<bool>? MascotVisibilityChanged;
    private readonly SubtitlePreferences _preferences = SubtitlePreferences.Shared;
    private readonly ObservableCollection<Caption> _history = new();
    private Caption? _current, _incoming;
    private bool _running, _reviewing;
    public bool IsMascotDisplayed => IsVisible && _preferences.ShowMascot && ActualWidth >= 560;
    public int HistoryCount => _history.Count;
    public FloatingSubtitleWindow()
    {
        InitializeComponent(); ReviewList.ItemsSource = _history;
        SetBounds(); ApplyPreferences(); RenderContent();
        SizeChanged += (_, _) => { ApplyMascot(); PacingLabel.Visibility = ActualWidth < 600 ? Visibility.Collapsed : Visibility.Visible; FollowLatest(); };
        IsVisibleChanged += (_, _) => ApplyMascot();
    }
    private static Caption Copy(Caption caption) => new() { Id = caption.Id, Start = caption.Start, End = caption.End, Original = caption.Original, Vietnamese = caption.Vietnamese };
    public void UpdateSubtitle(string original, string translation) => UpdateCaption(new Caption { Original = original, Vietnamese = translation });
    public void UpdateCaption(Caption caption)
    {
        Dispatcher.Invoke(() => {
            if (string.IsNullOrWhiteSpace(caption.Original) && string.IsNullOrWhiteSpace(caption.Vietnamese)) return;
            var index = _history.ToList().FindIndex(item => item.Id == caption.Id); var snapshot = Copy(caption);
            if (index >= 0) _history[index] = snapshot; else { _history.Add(snapshot); while (_history.Count > 30) _history.RemoveAt(0); }
            if (index < 0 || _current?.Id == caption.Id) _current = snapshot;
            if (_incoming?.Id == caption.Id) _incoming = null;
            RenderContent();
        });
    }
    public void UpdateIncoming(Caption caption)
    {
        Dispatcher.Invoke(() => { if (_current?.Id == caption.Id || (_incoming != null && caption.Start < _incoming.Start)) return; _incoming = Copy(caption); RenderContent(); });
    }
    public void ResetSession()
    {
        _history.Clear(); _current = _incoming = null; _reviewing = false; RenderContent();
    }
    public void SetMeetingState(bool running, bool canToggle = true)
    {
        _running = running; StopButton.Content = running ? "Tạm dừng" : "Bắt đầu"; StopButton.IsEnabled = canToggle;
        RenderContent();
    }
    private void RenderContent()
    {
        StateLabel.Text = _reviewing ? "Xem lại" : _running ? "Theo dõi cuộc họp" : "Tạm dừng";
        CaptionScroll.Visibility = _reviewing ? Visibility.Collapsed : Visibility.Visible;
        ReviewList.Visibility = _reviewing ? Visibility.Visible : Visibility.Collapsed;
        var original = _current?.Original ?? _incoming?.Original ?? "";
        var translation = _current?.Vietnamese ?? "";
        OriginalText.Text = original;
        OriginalText.Visibility = _preferences.ShowOriginal && !string.IsNullOrWhiteSpace(translation) && !string.IsNullOrWhiteSpace(original) ? Visibility.Visible : Visibility.Collapsed;
        TranslatedText.Text = !string.IsNullOrWhiteSpace(translation) ? translation : !string.IsNullOrWhiteSpace(original) ? original : _running ? "Đang lắng nghe cuộc họp…" : "Phụ đề sẽ hiển thị khi cuộc họp bắt đầu";
        var previous = _history.Count > 1 ? _history[^2] : null;
        ContextText.Text = previous == null ? "" : string.IsNullOrWhiteSpace(previous.Vietnamese) ? previous.Original : previous.Vietnamese;
        ContextText.Visibility = _preferences.ShowContext && previous != null ? Visibility.Visible : Visibility.Collapsed;
        IncomingPanel.Visibility = _preferences.ShowNext && _current != null && _incoming != null && _incoming.Id != _current.Id ? Visibility.Visible : Visibility.Collapsed;
        IncomingText.Text = _incoming?.Original ?? "";
        IncomingText.Visibility = _preferences.ShowOriginal ? Visibility.Visible : Visibility.Collapsed;
        IncomingTranslation.Text = string.IsNullOrWhiteSpace(_incoming?.Vietnamese) ? "Đang dịch…" : _incoming.Vietnamese;
        ChromeChanged(this, new RoutedEventArgs()); FollowLatest();
    }
    private void FollowLatest()
    {
        if (_reviewing) return;
        Dispatcher.BeginInvoke(System.Windows.Threading.DispatcherPriority.Loaded, new Action(() => { if (!_reviewing) CaptionScroll.ScrollToEnd(); }));
    }
    private void CaptionScroll_Changed(object sender, ScrollChangedEventArgs e)
    {
        if (e.ExtentHeightChange != 0 || e.ViewportHeightChange != 0) FollowLatest();
    }
    private void ToggleMeeting_Click(object sender, RoutedEventArgs e) { if (_running) StopRequested?.Invoke(); else StartRequested?.Invoke(); }
    private void Review_Click(object sender, RoutedEventArgs e) { _reviewing = !_reviewing; RenderContent(); }
    private void ShowSettings_Click(object sender, RoutedEventArgs e) { SettingsButton.ContextMenu.PlacementTarget = SettingsButton; SettingsButton.ContextMenu.IsOpen = true; }
    private void Pacing_Click(object sender, RoutedEventArgs e)
    {
        if (sender is MenuItem { Tag: string mode }) { _preferences.Pacing = mode; SavePreferences(); }
    }
    private void Appearance_Click(object sender, RoutedEventArgs e)
    {
        _preferences.ShowMascot = ShowMascot.IsChecked; _preferences.ShowNext = ShowNext.IsChecked; _preferences.ShowContext = ShowContext.IsChecked;
        _preferences.ShowOriginal = ShowOriginal.IsChecked; _preferences.Light = LightBackground.IsChecked; _preferences.Locked = LockPosition.IsChecked;
        SavePreferences();
    }
    private void Layout_Click(object sender, RoutedEventArgs e) { _preferences.Side = !_preferences.Side; SetBounds(); SavePreferences(); }
    private void Position_Click(object sender, RoutedEventArgs e)
    {
        var area = SystemParameters.WorkArea; Left = Math.Clamp(Left, area.Left + 16, Math.Max(area.Left + 16, area.Right - Width - 16));
        Top = sender is MenuItem { Tag: "top" } ? area.Top + 24 : Math.Max(area.Top + 16, area.Bottom - Height - 80);
    }
    private void FontSize_Click(object sender, RoutedEventArgs e)
    {
        if (sender is MenuItem { Tag: string size } && double.TryParse(size, NumberStyles.Number, CultureInfo.InvariantCulture, out var value)) { _preferences.FontSize = Math.Clamp(value, 15, 24); SavePreferences(); }
    }
    private void SavePreferences()
    {
        ApplyPreferences(); RenderContent();
        try { _preferences.Save(); } catch { StateLabel.Text = "Chưa lưu được tùy chỉnh"; }
    }
    private static Brush MakeBrush(string color) => (Brush)new BrushConverter().ConvertFromString(color)!;
    private void ApplyPreferences()
    {
        ShowMascot.IsChecked = _preferences.ShowMascot; ShowNext.IsChecked = _preferences.ShowNext; ShowContext.IsChecked = _preferences.ShowContext;
        ShowOriginal.IsChecked = _preferences.ShowOriginal; LightBackground.IsChecked = _preferences.Light; LockPosition.IsChecked = _preferences.Locked;
        Surface.Background = MakeBrush(_preferences.Light ? "#F5FFFFFF" : "#F20E1A18");
        var ink = MakeBrush(_preferences.Light ? "#292F2D" : "#FFFFFF"); var muted = MakeBrush(_preferences.Light ? "#65756F" : "#B0C3BB");
        TranslatedText.Foreground = ink; OriginalText.Foreground = IncomingText.Foreground = muted;
        var accent = MakeBrush(_preferences.Light ? "#287568" : "#A6E0CA");
        StateLabel.Foreground = PacingLabel.Foreground = IncomingTranslation.Foreground = accent;
        StateBadge.Background = MakeBrush(_preferences.Light ? "#E0EFE9" : "#244A42");
        foreach (var button in ToolbarActions.Children.OfType<Button>()) { button.Background = StateBadge.Background; button.Foreground = accent; }
        Resources["HudOriginalVisibility"] = _preferences.ShowOriginal ? Visibility.Visible : Visibility.Collapsed;
        ContextText.Foreground = MakeBrush(_preferences.Light ? "#7C9187" : "#96B3A7");
        Resources["HudInkBrush"] = ink; Resources["HudMutedBrush"] = muted;
        Resources["HudMainFont"] = _preferences.FontSize; Resources["HudOriginalSize"] = Math.Max(12, _preferences.FontSize - 3.5);
        TranslatedText.FontSize = _preferences.FontSize; OriginalText.FontSize = Math.Max(12, _preferences.FontSize - 3.5);
        IncomingText.FontSize = Math.Max(11, _preferences.FontSize - 4.5); IncomingTranslation.FontSize = Math.Max(13, _preferences.FontSize - 2);
        LayoutItem.Header = _preferences.Side ? "Chuyển thành dải ngang" : "Chuyển thành khung bên cạnh";
        PacingLabel.Text = _preferences.Pacing switch { "contextual" => "Nhịp thong thả", "fast" => "Nhịp nhanh", _ => "Nhịp cân bằng" };
        if (SettingsButton.ContextMenu.Items[0] is MenuItem pacing) foreach (var item in pacing.Items.OfType<MenuItem>()) item.IsChecked = Equals(item.Tag, _preferences.Pacing);
        ApplyMascot();
    }
    private void ApplyMascot()
    {
        MascotColumn.Visibility = _preferences.ShowMascot && ActualWidth >= 560 ? Visibility.Visible : Visibility.Collapsed;
        MascotVisibilityChanged?.Invoke(IsMascotDisplayed);
    }
    private void SetBounds()
    {
        var area = SystemParameters.WorkArea; Width = _preferences.Side ? Math.Min(440, area.Width - 32) : Math.Min(900, area.Width * .60); Height = _preferences.Side ? 300 : 180;
        Left = _preferences.Side ? area.Right - Width - 20 : area.Left + (area.Width - Width) / 2; Top = Math.Max(area.Top + 16, area.Bottom - Height - 80);
    }
    private void ChromeChanged(object sender, RoutedEventArgs e)
    {
        if (ToolbarActions == null) return;
        var visible = IsMouseOver || IsKeyboardFocusWithin || _reviewing;
        ToolbarActions.Opacity = visible ? 1 : 0; ToolbarActions.IsHitTestVisible = visible;
        foreach (var button in ToolbarActions.Children.OfType<Button>()) button.IsTabStop = visible;
    }
    private void Window_MouseLeftButtonDown(object sender, MouseButtonEventArgs e)
    {
        if (_preferences.Locked || e.ButtonState != MouseButtonState.Pressed) return;
        for (DependencyObject? source = e.OriginalSource as DependencyObject; source != null; source = source is Visual ? VisualTreeHelper.GetParent(source) : LogicalTreeHelper.GetParent(source))
            if (source is ButtonBase or MenuItem or ScrollBar or TextBox) return;
        DragMove();
    }
    private void OpenMain_Click(object sender, RoutedEventArgs e) { Application.Current.MainWindow.Show(); Application.Current.MainWindow.Activate(); }
    private void CloseButton_Click(object sender, RoutedEventArgs e) => Hide();
}
