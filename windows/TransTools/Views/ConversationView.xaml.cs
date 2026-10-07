using System.Windows.Controls;
using System.Windows.Input;
using TransTools.ViewModels;

namespace TransTools.Views;

public partial class ConversationView : UserControl
{
    private readonly ConversationViewModel _viewModel;

    public ConversationView(ConversationViewModel viewModel)
    {
        InitializeComponent();
        _viewModel = viewModel;
        DataContext = viewModel;
        Loaded += (_, _) => { _viewModel.Messages.CollectionChanged -= MessagesChanged; _viewModel.Messages.CollectionChanged += MessagesChanged; ScrollLatest(); };
        Unloaded += (_, _) => _viewModel.Messages.CollectionChanged -= MessagesChanged;
    }

    private void MessagesChanged(object? sender, System.Collections.Specialized.NotifyCollectionChangedEventArgs e) => ScrollLatest();
    private void ScrollLatest()
    {
        Dispatcher.BeginInvoke(System.Windows.Threading.DispatcherPriority.Loaded, new Action(() => {
            if (MessageList.Items.Count > 0) MessageList.ScrollIntoView(MessageList.Items[^1]);
        }));
    }

    private void ShowLibrary_Click(object sender, System.Windows.RoutedEventArgs e) => LibraryPopup.IsOpen = true;
    private void ShowTopic_Click(object sender, System.Windows.RoutedEventArgs e) => TopicPopup.IsOpen = true;

    private void InputTextBox_KeyDown(object sender, KeyEventArgs e)
    {
        if (e.Key == Key.Enter)
        {
            _ = _viewModel.SendMessageAsync();
        }
    }
}
