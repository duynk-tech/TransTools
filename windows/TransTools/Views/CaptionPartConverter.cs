using System.Globalization;
using System.Windows;
using System.Windows.Data;
namespace TransTools.Views;

public sealed class CaptionPartConverter : IMultiValueConverter
{
    public object Convert(object[] values, Type targetType, object parameter, CultureInfo culture)
    {
        var mode = values.ElementAtOrDefault(0) as string ?? "bilingual";
        var text = values.ElementAtOrDefault(1) as string ?? "";
        var part = parameter as string;
        var visible = part switch {
            "source" => mode != "translation",
            "translation" => mode != "original",
            "sourceAction" => mode != "translation" && !string.IsNullOrWhiteSpace(text),
            "translationAction" => mode != "original" && !string.IsNullOrWhiteSpace(text),
            _ => false
        };
        return visible ? Visibility.Visible : Visibility.Collapsed;
    }
    public object[] ConvertBack(object value, Type[] targetTypes, object parameter, CultureInfo culture) => throw new NotSupportedException();
}

public sealed class CaptionReadingLabelConverter : IMultiValueConverter
{
    public object Convert(object[] values, Type targetType, object parameter, CultureInfo culture)
    {
        var translation = Equals(parameter, "translation");
        return values.ElementAtOrDefault(0) is Guid id && values.ElementAtOrDefault(1) is Guid playing && id == playing && values.ElementAtOrDefault(2) is bool translated && translated == translation
            ? "Dừng" : translation ? "Dịch" : "Đọc";
    }
    public object[] ConvertBack(object value, Type[] targetTypes, object parameter, CultureInfo culture) => throw new NotSupportedException();
}
