using System;
using System.Drawing;
using System.Windows;
using System.Windows.Controls;
using TransTools.Services.OCR;
using TransTools.ViewModels;

namespace TransTools.Views;

public partial class QuickTranslateView : UserControl
{
    private readonly QuickTranslateViewModel _viewModel;

    public QuickTranslateView(QuickTranslateViewModel viewModel, TextReaderViewModel? reader = null)
    {
        InitializeComponent();
        _viewModel = viewModel;
        DataContext = viewModel;
        ReaderContent.Content = new TextReaderView(reader ?? new TextReaderViewModel());
    }

    private void TranslationTool_Checked(object sender, RoutedEventArgs e)
    {
        if (TranslationContent == null || ReaderContent == null) return;
        TranslationContent.Visibility = Visibility.Visible; ReaderContent.Visibility = Visibility.Collapsed;
    }
    private void ReadingTool_Checked(object sender, RoutedEventArgs e)
    {
        if (TranslationContent == null || ReaderContent == null) return;
        TranslationContent.Visibility = Visibility.Collapsed; ReaderContent.Visibility = Visibility.Visible;
    }

    private void ClearSource_Click(object sender, RoutedEventArgs e)
    {
        _viewModel.SourceText = string.Empty;
        _viewModel.TranslatedText = string.Empty;
    }

    private void CopyTranslated_Click(object sender, RoutedEventArgs e)
    {
        if (!string.IsNullOrWhiteSpace(_viewModel.TranslatedText))
        {
            Clipboard.SetText(_viewModel.TranslatedText);
            _viewModel.Status = "Đã sao chép bản dịch vào bộ nhớ tạm!";
        }
    }

    private async void CaptureOcr_Click(object sender, RoutedEventArgs e)
    {
        try
        {
            _viewModel.Status = "Đang quét chữ từ ảnh màn hình...";
            var main = Application.Current.MainWindow;
            var visible = main.IsVisible;
            Bitmap? capture = null;
            main.Hide();
            try {
                var selector = new RegionSelectionWindow(); selector.ShowDialog();
                if (selector.Selection is { } region) capture = WindowsOcrService.CaptureScreenRegion(region);
            } finally { if (visible) main.Show(); }
            if (capture == null) { _viewModel.Status = "Đã hủy chụp màn hình"; return; }
            using var bmp = capture;
            var recognized = await WindowsOcrService.RecognizeTextFromBitmapAsync(bmp);

            if (!string.IsNullOrWhiteSpace(recognized))
            {
                _viewModel.SourceText = recognized;
                await _viewModel.TranslateAsync();
                _viewModel.Status = "Đã nhận diện chữ và dịch thành công!";
            }
            else
            {
                _viewModel.Status = "Không tìm thấy chữ trong vùng quét.";
            }
        }
        catch (Exception ex)
        {
            _viewModel.Status = $"Lỗi OCR: {ex.Message}";
        }
    }
}
