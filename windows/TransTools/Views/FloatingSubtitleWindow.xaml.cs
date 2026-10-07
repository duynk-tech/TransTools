using System;
using System.Windows;
using System.Windows.Input;

namespace TransTools.Views;

public partial class FloatingSubtitleWindow : Window
{
    public event Action? StopRequested;
    private double _baseFontSize = 16;
    private string _original = "";
    private string _translation = "";
    private int _displayMode = 0; // 0: Bilingual, 1: Original Only, 2: Translation Only

    public FloatingSubtitleWindow()
    {
        InitializeComponent();
        Left = (SystemParameters.PrimaryScreenWidth - Width) / 2;
        Top = SystemParameters.PrimaryScreenHeight - Height - 80;
    }

    public void UpdateSubtitle(string original, string vietnamese)
    {
        Dispatcher.Invoke(() =>
        {

            // An empty transient recognition update must not erase the last readable caption.
            if (string.IsNullOrWhiteSpace(original) && string.IsNullOrWhiteSpace(vietnamese)) return;
            _original = original; _translation = vietnamese;
            switch (_displayMode)
            {
                case 1: // Original Only
                    OriginalText.Visibility = Visibility.Visible;
                    OriginalText.Text = original;
                    TranslatedText.Visibility = Visibility.Collapsed;
                    break;
                case 2: // Translation Only
                    OriginalText.Visibility = Visibility.Collapsed;
                    TranslatedText.Visibility = string.IsNullOrWhiteSpace(vietnamese) ? Visibility.Collapsed : Visibility.Visible;
                    TranslatedText.Text = vietnamese;
                    break;
                default: // Bilingual
                    OriginalText.Visibility = Visibility.Visible;
                    OriginalText.Text = original;
                    TranslatedText.Visibility = string.IsNullOrWhiteSpace(vietnamese) ? Visibility.Collapsed : Visibility.Visible;
                    TranslatedText.Text = vietnamese;
                    break;
            }
            Dispatcher.BeginInvoke(System.Windows.Threading.DispatcherPriority.Loaded, new Action(() => CaptionScroll.ScrollToEnd()));
        });
    }
    public void SetMeetingState(bool running) => StopButton.IsEnabled = running;
    private void StopMeeting_Click(object sender, RoutedEventArgs e) => StopRequested?.Invoke();

    private void Mode_Checked(object sender, RoutedEventArgs e)
    {
        if (ModeOriginal?.IsChecked == true) _displayMode = 1;
        else if (ModeTranslation?.IsChecked == true) _displayMode = 2;
        else _displayMode = 0;
        if (OriginalText != null) UpdateSubtitle(_original, _translation);
    }

    private void FontIncrease_Click(object sender, RoutedEventArgs e)
    {
        _baseFontSize = Math.Min(26, _baseFontSize + 2);
        ApplyFontSize();
    }

    private void FontDecrease_Click(object sender, RoutedEventArgs e)
    {
        _baseFontSize = Math.Max(12, _baseFontSize - 2);
        ApplyFontSize();
    }

    private void ApplyFontSize()
    {
        TranslatedText.FontSize = _baseFontSize;
        OriginalText.FontSize = Math.Max(10, _baseFontSize - 3);
    }

    private void Window_MouseLeftButtonDown(object sender, MouseButtonEventArgs e)
    {
        if (e.ButtonState == MouseButtonState.Pressed)
        {
            DragMove();
        }
    }

    private void OpenMain_Click(object sender, RoutedEventArgs e) { Application.Current.MainWindow.Show(); Application.Current.MainWindow.Activate(); }

    private void CloseButton_Click(object sender, RoutedEventArgs e)
    {
        Hide();
    }
}
