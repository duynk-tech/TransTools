using System.Globalization;
using System.Windows;
using System.Windows.Data;
namespace TransTools.Views;
public sealed class ProviderLabelConverter : IValueConverter
{
    public object Convert(object value, Type targetType, object parameter, CultureInfo culture) => value?.ToString() switch {
        "openai" => "OpenAI", "gemini" => "Google Gemini", "claude" => "Anthropic Claude", "deepseek" => "DeepSeek", _ => value?.ToString() ?? ""
    };
    public object ConvertBack(object value, Type targetType, object parameter, CultureInfo culture) => DependencyProperty.UnsetValue;
}
