using System.Windows;
using System.Windows.Input;
using TransTools.ViewModels;
namespace TransTools.Views;
public partial class LearningBoardWindow : Window
{
    private readonly LearningViewModel _model;
    private int _index;
    private readonly AlphabetItem[] _lessons;
    private readonly string _language;
    public LearningBoardWindow(LearningViewModel model) {
        InitializeComponent(); _model = model; _lessons = model.AlphabetList.ToArray(); _language = model.SelectedLanguage; DataContext = model; UpdateLesson();
        Closed += (_, _) => { _model.StopPronunciationCommand.Execute(null); Application.Current.MainWindow.Show(); Application.Current.MainWindow.Activate(); };
    }
    private void UpdateLesson() {
        if (_lessons.Length == 0) return;
        var item = _lessons[_index]; CharacterLabel.Text = item.Character; TranscriptionLabel.Text = item.Transcription;
        TipLabel.Text = string.Join("\n", new[] { item.Example, item.Tip }.Where(s => !string.IsNullOrWhiteSpace(s)));
        ProgressLabel.Text = $"{_index + 1} / {_lessons.Length}"; PreviousButton.IsEnabled = _index > 0; NextButton.IsEnabled = _index < _lessons.Length - 1; WritingCanvas.Strokes.Clear();
    }
    private void Previous(object sender, RoutedEventArgs e) { if (_index > 0) { _model.StopPronunciationCommand.Execute(null); _index--; UpdateLesson(); } }
    private void Next(object sender, RoutedEventArgs e) { if (_index + 1 < _lessons.Length) { _model.StopPronunciationCommand.Execute(null); _index++; UpdateLesson(); } }
    private async void Read(object sender, RoutedEventArgs e) { if (_lessons.Length > 0) try { await TransTools.Services.Speech.RecordingPlayer.PlayAsync(_lessons[_index].RecordingId, _language); } catch (Exception ex) { _model.Status = ex.Message; } }
    private void ClearWriting(object sender, RoutedEventArgs e) => WritingCanvas.Strokes.Clear();
    private void CloseBoard(object sender, RoutedEventArgs e) => Close();
    private void DragHeader(object sender, MouseButtonEventArgs e) {
        var source = e.OriginalSource as DependencyObject;
        while (source != null) {
            if (source is System.Windows.Controls.Primitives.ButtonBase) return;
            source = source is System.Windows.Media.Visual ? System.Windows.Media.VisualTreeHelper.GetParent(source) : LogicalTreeHelper.GetParent(source);
        }
        if (e.LeftButton == MouseButtonState.Pressed) DragMove();
    }
}
