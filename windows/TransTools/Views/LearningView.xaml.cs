using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using TransTools.ViewModels;

namespace TransTools.Views;

public partial class LearningView : UserControl
{
    private readonly LearningViewModel _viewModel;

    public LearningView(LearningViewModel viewModel)
    {
        _viewModel = viewModel;
        InitializeComponent();
        DataContext = viewModel;
        Unloaded += (_, _) => { if (_viewModel.IsGeneratingLessons) _viewModel.GenerateLessonsCancelCommand.Execute(null); };
    }

    private void ShowGoal_Click(object sender, RoutedEventArgs e) => LearningGoalPopup.IsOpen = true;

    private void Flashcard_Click(object sender, MouseButtonEventArgs e)
    {
        var source = e.OriginalSource as System.Windows.DependencyObject;
        while (source != null) {
            if (source is System.Windows.Controls.Primitives.ButtonBase) return;
            source = source is System.Windows.Media.Visual ? System.Windows.Media.VisualTreeHelper.GetParent(source) : System.Windows.LogicalTreeHelper.GetParent(source);
        }
        _viewModel.FlipFlashcard();
    }

    private void TodayTab_Checked(object sender, RoutedEventArgs e) { ShowSection("today"); }
    private void PracticeTab_Checked(object sender, RoutedEventArgs e) => ShowSection("practice");
    private void StartReview_Click(object sender,RoutedEventArgs e) { VocabularyTab.IsChecked = true; ShowSection("vocabulary"); _viewModel.StartReviewCommand.Execute(null); }
    private void ShowSection(string section) {
        if (VocabTabGrid != null) VocabTabGrid.Visibility=section=="vocabulary" ? Visibility.Visible : Visibility.Collapsed;
        if (AlphabetTabBorder != null) AlphabetTabBorder.Visibility=section=="alphabet" ? Visibility.Visible : Visibility.Collapsed;
        if (TodayPanel != null) TodayPanel.Visibility=section=="today" ? Visibility.Visible : Visibility.Collapsed;
        if (PracticePanel != null) PracticePanel.Visibility=section=="practice" ? Visibility.Visible : Visibility.Collapsed;
    }

    private void VocabTab_Checked(object sender, RoutedEventArgs e)
    {
        ShowSection("vocabulary");
    }
    private void AlphabetTab_Checked(object sender,RoutedEventArgs e) => ShowSection("alphabet");

    private void Language_SelectionChanged(object sender, SelectionChangedEventArgs e)
    {
        if (sender is ComboBox cb && cb.SelectedItem is ComboBoxItem item && item.Tag is string lang)
        {
            _viewModel.SelectedLanguage = lang;

        }
    }

    private void AlphabetItem_Click(object sender, MouseButtonEventArgs e)
    {
        if (sender is FrameworkElement elem && elem.DataContext is AlphabetItem item)
        {
            _ = _viewModel.SpeakAlphabetCharAsync(item);
        }
    }
}
