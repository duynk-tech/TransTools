using System;
using System.Drawing;
using System.Drawing.Imaging;
using System.IO;
using System.Threading.Tasks;
using Windows.Graphics.Imaging;
using Windows.Media.Ocr;
using Windows.Storage.Streams;

namespace TransTools.Services.OCR;

public class WindowsOcrService
{
    public static async Task<string> RecognizeTextFromBitmapAsync(Bitmap bitmap, string languageTag = "en-US")
    {
        var language = new Windows.Globalization.Language(languageTag);
        var engine = OcrEngine.TryCreateFromLanguage(language) ?? OcrEngine.TryCreateFromUserProfileLanguages();
        if (engine == null)
        {
            throw new InvalidOperationException("Hệ điều hành Windows chưa hỗ trợ gói ngôn ngữ OCR này.");
        }

        using var memoryStream = new MemoryStream();
        bitmap.Save(memoryStream, ImageFormat.Bmp);
        memoryStream.Position = 0;

        using var randomAccessStream = memoryStream.AsRandomAccessStream();
        var decoder = await BitmapDecoder.CreateAsync(randomAccessStream);
        var softwareBitmap = await decoder.GetSoftwareBitmapAsync();

        var result = await engine.RecognizeAsync(softwareBitmap);
        return result.Text;
    }

    public static Bitmap CaptureScreenRegion(Rectangle region)
    {
        var bmp = new Bitmap(region.Width, region.Height, PixelFormat.Format32bppArgb);
        using var g = Graphics.FromImage(bmp);
        g.CopyFromScreen(region.Left, region.Top, 0, 0, region.Size, CopyPixelOperation.SourceCopy);
        return bmp;
    }
}
