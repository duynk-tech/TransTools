using System.Windows;
using TransTools.ViewModels;
using TransTools.Views;

namespace TransTools;

public partial class MainWindow : Window
{
    private readonly MeetingViewModel _meetingViewModel = new();
    private readonly NotebookViewModel _notebookViewModel = new();
    private readonly QuickTranslateViewModel _translateViewModel = new();
    private readonly ConversationViewModel _conversationViewModel;
    private readonly LearningViewModel _learningViewModel = new();
    private readonly TextReaderViewModel _readerViewModel = new();
    private readonly SettingsViewModel _settingsViewModel;

    private readonly TransTools.Services.Experience.DashboardAppearance _appearance = new();

    private readonly Dictionary<string, System.Windows.Controls.UserControl> _views = new();
    private TransTools.Services.HotkeyService? _hotkeys;
    private FloatingSubtitleWindow? _subtitleWindow;
    private ChipChipMascotWindow? _mascotWindow;
    private ConversationMiniWindow? _miniChat;
    private bool _closeAllowed;
    private bool _savingForClose;
    private bool _mascotWasVisibleBeforeHud;

    public MainWindow()
    {
        _conversationViewModel = new ConversationViewModel(() => _meetingViewModel.IsBusy);
        _notebookViewModel.SetConversations(_conversationViewModel.Sessions);
        _conversationViewModel.SessionsSaved += () => _notebookViewModel.SetConversations(_conversationViewModel.Sessions);
        _notebookViewModel.ResumeConversationRequested += id => {
            if (!_conversationViewModel.CanChangeSession) { _notebookViewModel.Status = "Dừng phiên trò chuyện hiện tại trước khi mở hội thoại khác."; return; }
            var session = _conversationViewModel.Sessions.FirstOrDefault(s => s.Id == id);
            if (session == null) { _notebookViewModel.Status = "Hội thoại này không còn trong danh sách."; return; }
            _conversationViewModel.SelectedSession = session;
            NavConversation.IsChecked = true;
        };
        _settingsViewModel = new SettingsViewModel(() => _meetingViewModel.IsBusy || !_conversationViewModel.CanChangeSession);
        _meetingViewModel.OtherAudioBusy = () => !_conversationViewModel.CanChangeSession;
        InitializeComponent();
        ApplyBackground();

        _meetingViewModel.OnCaptionPresented += caption => _subtitleWindow?.UpdateCaption(caption);
        _meetingViewModel.OnCaptionIncoming += caption => _subtitleWindow?.UpdateIncoming(caption);

        _meetingViewModel.OnSessionSaved += session => _ = _notebookViewModel.LoadSessionsAsync();

        SourceInitialized += (_, _) => {
            _hotkeys = new TransTools.Services.HotkeyService(this);
            if (!_hotkeys.Register(1, 0x44) || !_hotkeys.Register(2, 0x54)) _settingsViewModel.Status = "Một phím tắt Ctrl+Alt+D/T đang được ứng dụng khác sử dụng.";
            _hotkeys.Pressed += async id => {
                try {
                    if (_translateViewModel.IsTranslating) return;
                    var text = id == 1 ? await Task.Run(TransTools.Services.HotkeyService.SelectedText) : "";
                    if (string.IsNullOrWhiteSpace(text) && Clipboard.ContainsText()) text = Clipboard.GetText();
                    Show(); Activate(); NavTranslate.IsChecked = true;
                    ShowView("translate", () => new QuickTranslateView(_translateViewModel, _readerViewModel));
                    if (!string.IsNullOrWhiteSpace(text)) { _translateViewModel.SourceText = text; await _translateViewModel.TranslateAsync(); }
                    else _translateViewModel.Status = "Chọn văn bản hoặc sao chép đoạn cần dịch trước khi bấm Ctrl+Alt+D.";
                } catch (Exception ex) { _translateViewModel.Status = ex.Message; }
            };
        };

        TransTools.Services.Experience.BreakReminder.Shared.Due += ShowBreakReminder;

        // Default to Meeting View
        ShowMeetingView();
    }

    private void ShowBackground_Click(object sender, RoutedEventArgs e)
    {
        BackgroundButton.ContextMenu.PlacementTarget = BackgroundButton;
        BackgroundButton.ContextMenu.IsOpen = true;
    }
    private void ChooseBackground_Click(object sender, RoutedEventArgs e)
    {
        try { if (sender is System.Windows.Controls.MenuItem { Tag: string mode }) { _appearance.Select(mode); ApplyBackground(); } }
        catch (Exception ex) { MessageBox.Show(this, ex.Message, "Chọn nền", MessageBoxButton.OK, MessageBoxImage.Information); }
    }
    private void ChoosePhoto_Click(object sender, RoutedEventArgs e)
    {
        var dialog = new Microsoft.Win32.OpenFileDialog { Title = "Chọn ảnh nền", Filter = "Ảnh (*.jpg;*.jpeg;*.png;*.bmp)|*.jpg;*.jpeg;*.png;*.bmp" };
        if (dialog.ShowDialog(this) != true) { ApplyBackground(); return; }
        try { _appearance.SelectPhoto(dialog.FileName); ApplyBackground(); }
        catch (Exception ex) { ApplyBackground(); MessageBox.Show(this, "Không thể dùng ảnh này. " + ex.Message, "Chọn nền", MessageBoxButton.OK, MessageBoxImage.Information); }
    }
    private void ApplyBackground()
    {
        DashboardGarden.SetPeriod(_appearance.Mode);
        var photo = _appearance.Mode == "photo" && _appearance.Photo != null;
        DashboardPhoto.Source = _appearance.Photo;
        DashboardPhoto.Visibility = PhotoVeil.Visibility = photo ? Visibility.Visible : Visibility.Collapsed;
        DashboardGarden.Visibility = photo ? Visibility.Collapsed : Visibility.Visible;
        foreach (var item in BackgroundButton.ContextMenu.Items.OfType<System.Windows.Controls.MenuItem>()) item.IsChecked = Equals(item.Tag, _appearance.Mode);
    }

    private void ShowView(string route, Func<System.Windows.Controls.UserControl> create)
    {
        if (MainContentGrid == null) return;
        if (!_views.TryGetValue(route, out var view)) { view = create(); _views.Add(route, view); }
        if (MainContentGrid.Children.Contains(view)) return;
        MainContentGrid.Children.Clear(); MainContentGrid.Children.Add(view);
    }

    private void ShowMeetingView()
    {
        if (MainContentGrid == null) return;
        ShowView("meeting", () => new MeetingView(_meetingViewModel));
    }

    private void NavMeeting_Checked(object sender, RoutedEventArgs e)
    {
        ShowMeetingView();
    }

    private void NavNotebook_Checked(object sender, RoutedEventArgs e)
    {
        if (MainContentGrid == null) return;
        ShowView("notebook", () => new NotebookView(_notebookViewModel, _learningViewModel));
    }

    private void NavTranslate_Checked(object sender, RoutedEventArgs e)
    {
        if (MainContentGrid == null) return;
        ShowView("translate", () => new QuickTranslateView(_translateViewModel, _readerViewModel));
    }

    private void NavConversation_Checked(object sender, RoutedEventArgs e)
    {
        if (MainContentGrid == null) return;
        ShowView("conversation", () => new ConversationView(_conversationViewModel));
    }

    private void NavLearning_Checked(object sender, RoutedEventArgs e)
    {
        if (MainContentGrid == null) return;
        ShowView("learning", () => new LearningView(_learningViewModel));
    }

    private void NavReader_Checked(object sender, RoutedEventArgs e)
    {
        if (MainContentGrid == null) return;
        ShowView("reader", () => new TextReaderView(_readerViewModel));
    }

    private void NavSettings_Checked(object sender, RoutedEventArgs e)
    {
        if (MainContentGrid == null) return;
        ShowView("settings", () => new SettingsView(_settingsViewModel, () => _meetingViewModel.IsBusy || !_conversationViewModel.CanChangeSession || _readerViewModel.IsBusy));
    }

    private async void StartMeetingFromMascot()
    {
        try {
            if (!_meetingViewModel.IsRecording) await _meetingViewModel.StartRecordingCommand.ExecuteAsync(null);
            if (_meetingViewModel.IsRecording) { ShowSubtitle(); Hide(); }
        } catch (Exception ex) { _meetingViewModel.Status = ex.Message; Show(); Activate(); }
    }
    private void ShowSubtitle()
    {
        if (_subtitleWindow?.IsVisible != true) ToggleSubtitle_Click(this, new RoutedEventArgs());
    }

    private void ToggleSubtitle_Click(object sender, RoutedEventArgs e)
    {
        if (_subtitleWindow == null)
        {
            _subtitleWindow = new FloatingSubtitleWindow();
            _subtitleWindow.StopRequested += () => _meetingViewModel.StopRecordingCommand.Execute(null);
            _subtitleWindow.StartRequested += async () => {
                try { await _meetingViewModel.StartRecordingCommand.ExecuteAsync(null); }
                catch (Exception ex) { _meetingViewModel.Status = ex.Message; }
            };
            _subtitleWindow.MascotVisibilityChanged += visible => {
                if (visible) { _mascotWasVisibleBeforeHud |= _mascotWindow?.IsVisible == true; _mascotWindow?.Hide(); }
                else if (_mascotWasVisibleBeforeHud) { _mascotWindow?.Show(); _mascotWasVisibleBeforeHud = false; }
            };
            _meetingViewModel.PropertyChanged += (_, change) => {
                if (change.PropertyName == nameof(MeetingViewModel.IsRecording) && _meetingViewModel.IsRecording) _subtitleWindow.ResetSession();
                if (change.PropertyName is nameof(MeetingViewModel.IsRecording) or nameof(MeetingViewModel.IsPreparing) or nameof(MeetingViewModel.IsStopping))
                    _subtitleWindow.SetMeetingState(_meetingViewModel.IsRecording, !_meetingViewModel.IsPreparing && !_meetingViewModel.IsStopping);
            };
        }

        if (_subtitleWindow.IsVisible)
        {
            _subtitleWindow.Hide();
        }
        else
        {
            _subtitleWindow.SetMeetingState(_meetingViewModel.IsRecording, !_meetingViewModel.IsPreparing && !_meetingViewModel.IsStopping);
            _subtitleWindow.Show();
        }
    }

    private void ToggleMascot_Click(object sender, RoutedEventArgs e)
    {
        if (_subtitleWindow?.IsMascotDisplayed == true) { _subtitleWindow.Activate(); return; }
        if (_mascotWindow == null)
        {
            _mascotWindow = new ChipChipMascotWindow();
            _mascotWindow.LearningRequested += () => _learningViewModel.LearnWithChipChipCommand.Execute(null);
            _mascotWindow.MeetingRequested += StartMeetingFromMascot;
            _mascotWindow.SubtitleRequested += ShowSubtitle;
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

    private void ShowBreakReminder() {
        if (_mascotWindow == null) {
            _mascotWindow = new ChipChipMascotWindow();
            _mascotWindow.LearningRequested += () => _learningViewModel.LearnWithChipChipCommand.Execute(null);
            _mascotWindow.MeetingRequested += StartMeetingFromMascot;
            _mascotWindow.SubtitleRequested += ShowSubtitle;
        }
        _mascotWindow.ShowReminder("Nghỉ một chút nhé! Chớp mắt, uống nước và thư giãn vai.");
    }

    protected override async void OnClosing(System.ComponentModel.CancelEventArgs e)
    {
        if (_closeAllowed) { base.OnClosing(e); return; }
        if ((_meetingViewModel.IsRecording || _meetingViewModel.IsStopping) && _subtitleWindow?.IsVisible == true) {
            e.Cancel = true; Hide(); base.OnClosing(e); return;
        }
        if (_meetingViewModel.IsStopping || (_meetingViewModel.IsBusy && !_meetingViewModel.IsRecording)) {
            e.Cancel = true; _meetingViewModel.Status = "Chờ hoàn tất phiên cuộc họp trước khi đóng."; base.OnClosing(e); return;
        }
        if (_conversationViewModel.IsConversationActive) {
            e.Cancel = true; _miniChat ??= new ConversationMiniWindow(_conversationViewModel); _miniChat.Show(); Hide(); base.OnClosing(e); return;
        }
        if (_meetingViewModel.IsRecording || _meetingViewModel.Captions.Count > 0) {
            e.Cancel = true;
            if (_savingForClose) { base.OnClosing(e); return; }
            _savingForClose = true;
            base.OnClosing(e);
            try {
                await _meetingViewModel.StopRecordingAsync();
                await _meetingViewModel.SaveSessionAsync();
                _closeAllowed = true; Close();
            } catch (Exception ex) { _meetingViewModel.Status = "Chưa lưu được cuộc họp: " + ex.Message; _savingForClose = false; }
            return;
        }
        base.OnClosing(e);
    }

    protected override void OnClosed(System.EventArgs e)
    {
        base.OnClosed(e);
        _miniChat?.CloseForExit();
        _subtitleWindow?.Close();
        _mascotWindow?.Close();
        _hotkeys?.Dispose();
        TransTools.Services.Experience.BreakReminder.Shared.Due -= ShowBreakReminder;
        TransTools.Services.Experience.BreakReminder.Shared.Dispose();
        TransTools.Services.Speech.VoiceService.Shared.Stop();
        TransTools.Services.Speech.RecordingPlayer.Stop();
        _conversationViewModel.Dispose();
        _meetingViewModel.Dispose();
        Application.Current.Shutdown();
    }
}
