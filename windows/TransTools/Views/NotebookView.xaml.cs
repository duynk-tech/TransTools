using System.Windows.Controls;
using TransTools.ViewModels;

namespace TransTools.Views;

public partial class NotebookView : UserControl
{
    private void ShowExport_Click(object sender, System.Windows.RoutedEventArgs e) => ExportPopup.IsOpen = true;

    public NotebookView(NotebookViewModel viewModel)
    {
        InitializeComponent();
        DataContext = viewModel;
    }
}
