using System.Globalization;
using System.Windows.Data;
namespace TransTools.Views;
public sealed class LanguageLabelConverter : IValueConverter
{
    public object Convert(object value, Type targetType, object parameter, CultureInfo culture)
    {
        if (Equals(parameter, "short")) return value?.ToString() == "auto" ? "AUTO" : value?.ToString()?.ToUpperInvariant() ?? "";
        return value?.ToString() switch {
        "auto" => "Tự động", "en" => "Tiếng Anh", "vi" => "Tiếng Việt", "ja" => "Tiếng Nhật", "zh" => "Tiếng Trung", "ko" => "Tiếng Hàn", _ => value ?? ""
        };
    }
    public object ConvertBack(object value, Type targetType, object parameter, CultureInfo culture) => Binding.DoNothing;
}
