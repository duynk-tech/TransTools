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
    }

    private void InputTextBox_KeyDown(object sender, KeyEventArgs e)
    {
        if (e.Key == Key.Enter)
        {
            _ = _viewModel.SendMessageAsync();
        }
    }
}
