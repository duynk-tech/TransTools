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

    public QuickTranslateView(QuickTranslateViewModel viewModel)
    {
        InitializeComponent();
        _viewModel = viewModel;
        DataContext = viewModel;
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
            int screenWidth = (int)SystemParameters.PrimaryScreenWidth;
            int screenHeight = (int)SystemParameters.PrimaryScreenHeight;
            if (screenWidth <= 0) screenWidth = 1920;
            if (screenHeight <= 0) screenHeight = 1080;

            var snippetRect = new Rectangle(screenWidth / 4, screenHeight / 4, screenWidth / 2, screenHeight / 2);
            using var bmp = WindowsOcrService.CaptureScreenRegion(snippetRect);
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
