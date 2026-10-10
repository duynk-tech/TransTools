using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Media;
using System.Windows;
using System.ComponentModel;
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
        Loaded += (_, _) => { _viewModel.Messages.CollectionChanged -= MessagesChanged; _viewModel.Messages.CollectionChanged += MessagesChanged; _viewModel.PropertyChanged -= PresentationChanged; _viewModel.PropertyChanged += PresentationChanged; ScrollLatest(); };
        Unloaded += (_, _) => { _viewModel.Messages.CollectionChanged -= MessagesChanged; _viewModel.PropertyChanged -= PresentationChanged; };
    }

    private void MessagesChanged(object? sender, System.Collections.Specialized.NotifyCollectionChangedEventArgs e) => ScrollLatest();
    private void PresentationChanged(object? sender, PropertyChangedEventArgs e) { if (e.PropertyName is nameof(ConversationViewModel.ShowVietnameseTranslation) or nameof(ConversationViewModel.TargetLanguage)) ScrollLatest(); }
    private void ScrollLatest()
    {
        Dispatcher.BeginInvoke(System.Windows.Threading.DispatcherPriority.Loaded, new Action(() => {
            if (!IsLoaded || MessageList.Items.Count == 0) return;
            MessageList.ScrollIntoView(MessageList.Items[^1]);
            MessageList.UpdateLayout();
            FindScrollViewer(MessageList)?.ScrollToEnd();
            Dispatcher.BeginInvoke(System.Windows.Threading.DispatcherPriority.ContextIdle, new Action(() => {
                if (IsLoaded) { MessageList.UpdateLayout(); FindScrollViewer(MessageList)?.ScrollToEnd(); }
            }));
        }));
    }

    private static ScrollViewer? FindScrollViewer(DependencyObject root)
    {
        if (root is ScrollViewer scroll) return scroll;
        for (var i = 0; i < VisualTreeHelper.GetChildrenCount(root); i++) {
            var found = FindScrollViewer(VisualTreeHelper.GetChild(root, i)); if (found != null) return found;
        }
        return null;
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
