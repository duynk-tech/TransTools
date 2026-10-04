using System;
using System.Windows;
using System.Windows.Input;

namespace TransTools.Views;

public partial class FloatingSubtitleWindow : Window
{
    private double _baseFontSize = 16;
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
            switch (_displayMode)
            {
                case 1: // Original Only
                    OriginalText.Visibility = Visibility.Visible;
                    OriginalText.Text = original;
                    TranslatedText.Visibility = Visibility.Collapsed;
                    break;
                case 2: // Translation Only
                    OriginalText.Visibility = Visibility.Collapsed;
                    TranslatedText.Visibility = Visibility.Visible;
                    TranslatedText.Text = vietnamese;
                    break;
                default: // Bilingual
                    OriginalText.Visibility = Visibility.Visible;
                    OriginalText.Text = original;
                    TranslatedText.Visibility = Visibility.Visible;
                    TranslatedText.Text = vietnamese;
                    break;
            }
        });
    }

    private void Mode_Checked(object sender, RoutedEventArgs e)
    {
        if (ModeOriginal?.IsChecked == true) _displayMode = 1;
        else if (ModeTranslation?.IsChecked == true) _displayMode = 2;
        else _displayMode = 0;
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

    private void CloseButton_Click(object sender, RoutedEventArgs e)
    {
        Hide();
    }
}
