using System.Windows.Controls;
using TransTools.ViewModels;

namespace TransTools.Views;

public partial class NotebookView : UserControl
{
    private void ShowExport_Click(object sender, System.Windows.RoutedEventArgs e) => ExportPopup.IsOpen = true;

    private void CopyOriginal_Click(object sender, System.Windows.RoutedEventArgs e)
    {
        if (DataContext is NotebookViewModel vm && sender is MenuItem { DataContext: TransTools.Models.Caption caption }) vm.CopyOriginalCommand.Execute(caption);
    }
    private void CopyTranslation_Click(object sender, System.Windows.RoutedEventArgs e)
    {
        if (DataContext is NotebookViewModel vm && sender is MenuItem { DataContext: TransTools.Models.Caption caption }) vm.CopyTranslationCommand.Execute(caption);
    }
    private void CopyBilingual_Click(object sender, System.Windows.RoutedEventArgs e)
    {
        if (DataContext is NotebookViewModel vm && sender is MenuItem { DataContext: TransTools.Models.Caption caption }) vm.CopyBilingualCommand.Execute(caption);
    }

    public NotebookView(NotebookViewModel viewModel)
    {
        InitializeComponent();
        DataContext = viewModel;
    }
}
