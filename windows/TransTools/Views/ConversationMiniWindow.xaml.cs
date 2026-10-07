using System.Collections.Specialized;
using System.Windows;
using System.Windows.Threading;
using TransTools.ViewModels;

namespace TransTools.Views;
public partial class ConversationMiniWindow : Window
{
    private readonly ConversationViewModel _model;
    private bool _exiting;
    public ConversationMiniWindow(ConversationViewModel model)
    {
        InitializeComponent(); _model = model; DataContext = model;
        Left = Math.Max(SystemParameters.WorkArea.Left, SystemParameters.WorkArea.Right - Width - 24);
        Top = Math.Max(SystemParameters.WorkArea.Top, SystemParameters.WorkArea.Bottom - Height - 24);
        IsVisibleChanged += (_, _) => {
            _model.Messages.CollectionChanged -= MessagesChanged;
            if (IsVisible) { _model.Messages.CollectionChanged += MessagesChanged; ScrollLatest(); }
        };
        Closing += (_, e) => { if (!_exiting) { e.Cancel = true; Hide(); OpenMain(); } };
    }
    private void MessagesChanged(object? sender, NotifyCollectionChangedEventArgs e) => ScrollLatest();
    private void ScrollLatest() => Dispatcher.BeginInvoke(DispatcherPriority.Loaded, new Action(() => {
        if (MessagesList.Items.Count > 0) MessagesList.ScrollIntoView(MessagesList.Items[^1]);
    }));
    private void OpenMain() { Hide(); Application.Current.MainWindow.Show(); Application.Current.MainWindow.Activate(); }
    private void OpenMain_Click(object sender, RoutedEventArgs e) => OpenMain();
    public void CloseForExit() { _exiting = true; _model.Messages.CollectionChanged -= MessagesChanged; Close(); }
}
