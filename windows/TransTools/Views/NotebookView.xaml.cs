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

    private NotebookVocabularyView? _vocabulary;
    private LearningViewModel? _learning;
    private void Records_Checked(object sender, System.Windows.RoutedEventArgs e)
    {
        if (RecordsPanel == null) return;
        RecordsPanel.Visibility = System.Windows.Visibility.Visible;
        VocabularyPanel.Visibility = System.Windows.Visibility.Collapsed;
    }
    private void Words_Checked(object sender, System.Windows.RoutedEventArgs e)
    {
        if (VocabularyPanel == null || _learning == null) return;
        _vocabulary ??= new NotebookVocabularyView(_learning);
        VocabularyPanel.Content = _vocabulary;
        VocabularyPanel.Visibility = System.Windows.Visibility.Visible;
        RecordsPanel.Visibility = System.Windows.Visibility.Collapsed;
    }
    private void ImportLearning_Click(object sender, System.Windows.RoutedEventArgs e)
    {
        if (_learning != null && DataContext is NotebookViewModel model && model.SelectedSession is { } session) {
            var dialog = new NotebookLearningWindow(session, _learning) { Owner = Window.GetWindow(this) };
            if (dialog.ShowDialog() == true) model.Status = dialog.ImportStatus;
        }
    }
    public NotebookView(NotebookViewModel viewModel, LearningViewModel? learning = null)
    {
        InitializeComponent();
        DataContext = viewModel;
        _learning = learning ?? new LearningViewModel();
        WordTabCount.SetBinding(TextBlock.TextProperty, new System.Windows.Data.Binding("VocabularyList.Count") { Source = _learning, Mode = System.Windows.Data.BindingMode.OneWay });
    }
}
