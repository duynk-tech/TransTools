using System.ComponentModel;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Data;
using TransTools.Models;
using TransTools.ViewModels;
namespace TransTools.Views;
public partial class NotebookVocabularyView : UserControl
{
    private readonly LearningViewModel _model;
    private readonly ICollectionView _words;
    public NotebookVocabularyView(LearningViewModel model)
    {
        _model = model;
        InitializeComponent();
        DataContext = model;
        // Independent view: searching here cannot filter the learning/review collection.
        _words = new ListCollectionView(model.VisibleVocabulary);
        _words.Filter = item => item is VocabularyItem word && (AllWords.IsChecked == true || (MasteredWords.IsChecked == true ? word.MasteryScore >= 4 : word.MasteryScore < 4)) && (string.IsNullOrWhiteSpace(SearchBox.Text) ||
            word.Word.Contains(SearchBox.Text, StringComparison.OrdinalIgnoreCase) ||
            word.Meaning.Contains(SearchBox.Text, StringComparison.OrdinalIgnoreCase) ||
            word.ExampleSentence.Contains(SearchBox.Text, StringComparison.OrdinalIgnoreCase));
        WordsList.ItemsSource = _words;
        model.VisibleVocabulary.CollectionChanged += (_, _) => UpdateEmpty();
        UpdateEmpty();
    }
    private void StateChanged(object sender, RoutedEventArgs e) { if (_words == null) return; _words.Refresh(); UpdateEmpty(); }
    private void SearchChanged(object sender, TextChangedEventArgs e) { if (_words == null) return; _words.Refresh(); UpdateEmpty(); }
    private void UpdateEmpty() => EmptyState.Visibility = _words.IsEmpty ? Visibility.Visible : Visibility.Collapsed;
    private void ShowAdd_Click(object sender, RoutedEventArgs e) => AddWordPopup.IsOpen = true;
    private async void Speak_Click(object sender, RoutedEventArgs e)
    {
        if (sender is Button { DataContext: VocabularyItem word }) { _model.SelectedWord = word; await _model.SpeakCurrentWordAsync(); }
    }
    private void Delete_Click(object sender, RoutedEventArgs e)
    {
        if (sender is not Button { DataContext: VocabularyItem word }) return;
        if (MessageBox.Show(Window.GetWindow(this), $"Xóa từ “{word.Word}” khỏi sổ từ vựng?", "Xóa từ", MessageBoxButton.YesNo, MessageBoxImage.Question) != MessageBoxResult.Yes) return;
        _model.SelectedWord = word; _model.DeleteWordCommand.Execute(null);
    }
}
