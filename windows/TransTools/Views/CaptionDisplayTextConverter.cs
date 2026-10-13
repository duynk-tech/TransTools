using System.Globalization;
using System.Windows.Data;
namespace TransTools.Views;
public sealed class CaptionDisplayTextConverter : IMultiValueConverter
{
    public static string Select(string original, string translation, string mode, bool secondary)
    {
        if (secondary) return mode == "bilingual" ? translation : "";
        return mode == "translation" && !string.IsNullOrWhiteSpace(translation) ? translation : original;
    }
    public object Convert(object[] values, Type targetType, object parameter, CultureInfo culture)
    {
        var original = values.ElementAtOrDefault(0) as string ?? "";
        var translation = values.ElementAtOrDefault(1) as string ?? "";
        var mode = values.ElementAtOrDefault(2) as string ?? "bilingual";
        return Equals(parameter, "hudTranslation") ? mode == "original" ? "" : translation : Select(original, translation, mode, Equals(parameter, "secondary"));
    }
    public object[] ConvertBack(object value, Type[] targetTypes, object parameter, CultureInfo culture) => throw new NotSupportedException();
}
