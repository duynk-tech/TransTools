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
        InitializeComponent();
        _viewModel = viewModel;
        DataContext = viewModel;
    }

    private void Flashcard_Click(object sender, MouseButtonEventArgs e)
    {
        _viewModel.FlipFlashcard();
    }

    private void VocabTab_Checked(object sender, RoutedEventArgs e)
    {
        if (VocabTabGrid != null) VocabTabGrid.Visibility = Visibility.Visible;
        if (AlphabetTabBorder != null) AlphabetTabBorder.Visibility = Visibility.Collapsed;
    }

    private void AlphabetTab_Checked(object sender, RoutedEventArgs e)
    {
        if (VocabTabGrid != null) VocabTabGrid.Visibility = Visibility.Collapsed;
        if (AlphabetTabBorder != null) AlphabetTabBorder.Visibility = Visibility.Visible;
    }

    private void Language_SelectionChanged(object sender, SelectionChangedEventArgs e)
    {
        if (sender is ComboBox cb && cb.SelectedItem is ComboBoxItem item && item.Tag is string lang)
        {
            _viewModel.SelectedLanguage = lang;
            _viewModel.LoadAlphabetList();
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
