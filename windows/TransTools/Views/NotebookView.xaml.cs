using System.Windows.Controls;
using TransTools.ViewModels;

namespace TransTools.Views;

public partial class NotebookView : UserControl
{
    public NotebookView(NotebookViewModel viewModel)
    {
        InitializeComponent();
        DataContext = viewModel;
    }
}
