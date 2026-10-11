using System.Windows;
using System.Windows.Documents;
using System.Windows.Media;
using System.ComponentModel;
using TransTools.ViewModels;
namespace TransTools.Views;
public partial class PersonalVoiceRecorderWindow : Window
{
    private readonly PersonalVoiceRecorderViewModel _model;
    public PersonalVoiceRecorderWindow(PersonalVoiceRecorderViewModel model)
    {
        InitializeComponent(); _model = model; DataContext = model; model.PropertyChanged += ModelChanged;
        RenderGuide(); Closed += (_, _) => { model.PropertyChanged -= ModelChanged; model.Dispose(); };
    }
    private void ModelChanged(object? sender, PropertyChangedEventArgs e)
    {
        if (e.PropertyName is nameof(_model.RecordedSeconds) or nameof(_model.GuideEnabled) or nameof(_model.IsRecording) or nameof(_model.ReferenceText)) RenderGuide();
    }
    private void RenderGuide()
    {
        ReadingBoard.Inlines.Clear();
        var words = _model.ReferenceText.Split(' ', StringSplitOptions.RemoveEmptyEntries);
        var active = _model.IsRecording && _model.GuideEnabled ? Math.Min(words.Length - 1, (int)(_model.RecordedSeconds / 8 * words.Length)) : -1;
        for (var i = 0; i < words.Length; i++) {
            var word = new Run(words[i] + (i + 1 < words.Length ? " " : ""));
            if (i == active) { word.Background = new SolidColorBrush(Color.FromRgb(214, 237, 228)); word.Foreground = new SolidColorBrush(Color.FromRgb(40, 117, 104)); word.FontWeight = FontWeights.SemiBold; }
            ReadingBoard.Inlines.Add(word);
        }
    }
    private void Close_Click(object sender, RoutedEventArgs e) => Close();
}
