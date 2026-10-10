using System.Collections.Specialized;
using System.Collections.ObjectModel;
using System.ComponentModel;
using System.Windows.Controls;
using System.Windows.Media;
using System.Windows;
using System.Windows.Threading;
using TransTools.ViewModels;

namespace TransTools.Views;
public partial class ConversationMiniWindow : Window
{
    private readonly ConversationViewModel _model;
    private bool _exiting;
    public ObservableCollection<ChatMessageItem> RecentMessages { get; } = new();
    private void RefreshRecentMessages() { RecentMessages.Clear(); foreach (var message in _model.Messages.TakeLast(6)) RecentMessages.Add(message); }
    public ConversationMiniWindow(ConversationViewModel model)
    {
        InitializeComponent(); _model = model; DataContext = model; RefreshRecentMessages();
        Left = Math.Max(SystemParameters.WorkArea.Left, SystemParameters.WorkArea.Right - Width - 24);
        Top = Math.Max(SystemParameters.WorkArea.Top, SystemParameters.WorkArea.Bottom - Height - 24);
        IsVisibleChanged += (_, _) => {
            _model.Messages.CollectionChanged -= MessagesChanged; _model.PropertyChanged -= PresentationChanged;
            if (IsVisible) { _model.Messages.CollectionChanged += MessagesChanged; _model.PropertyChanged += PresentationChanged; RefreshRecentMessages(); ScrollLatest(); }
        };
        Closing += (_, e) => { if (!_exiting) { e.Cancel = true; Hide(); OpenMain(); } };
    }
    private void MessagesChanged(object? sender, NotifyCollectionChangedEventArgs e) { RefreshRecentMessages(); ScrollLatest(); }
    private void PresentationChanged(object? sender, PropertyChangedEventArgs e) { if (e.PropertyName is nameof(ConversationViewModel.ShowMiniTranslation) or nameof(ConversationViewModel.TargetLanguage) or nameof(ConversationViewModel.UserInput) or nameof(ConversationViewModel.IsConversationActive)) ScrollLatest(); }
    private void ScrollLatest() => Dispatcher.BeginInvoke(DispatcherPriority.Loaded, new Action(() => {
        if (!IsVisible || MessagesList.Items.Count == 0) return;
        MessagesList.ScrollIntoView(MessagesList.Items[^1]); MessagesList.UpdateLayout(); FindScroll(MessagesList)?.ScrollToEnd();
        Dispatcher.BeginInvoke(DispatcherPriority.ContextIdle, new Action(() => { if (IsVisible) { MessagesList.UpdateLayout(); FindScroll(MessagesList)?.ScrollToEnd(); } }));
    }));
    private static ScrollViewer? FindScroll(DependencyObject root) {
        if (root is ScrollViewer scroll) return scroll;
        for (var i = 0; i < VisualTreeHelper.GetChildrenCount(root); i++) { var found = FindScroll(VisualTreeHelper.GetChild(root, i)); if (found != null) return found; }
        return null;
    }
    private void OpenMain() { Hide(); Application.Current.MainWindow.Show(); Application.Current.MainWindow.Activate(); }
    private void OpenMain_Click(object sender, RoutedEventArgs e) => OpenMain();
    public void CloseForExit() { _exiting = true; _model.Messages.CollectionChanged -= MessagesChanged; _model.PropertyChanged -= PresentationChanged; Close(); }
}
