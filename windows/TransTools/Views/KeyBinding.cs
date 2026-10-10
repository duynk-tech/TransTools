using System.Windows;
using System.Windows.Controls;
namespace TransTools.Views;
public static class KeyBinding
{
    public static readonly DependencyProperty ValueProperty = DependencyProperty.RegisterAttached("Value", typeof(string), typeof(KeyBinding), new FrameworkPropertyMetadata("", FrameworkPropertyMetadataOptions.BindsTwoWayByDefault, Changed));
    private static readonly DependencyProperty UpdatingProperty = DependencyProperty.RegisterAttached("Updating", typeof(bool), typeof(KeyBinding), new PropertyMetadata(false));
    public static string GetValue(DependencyObject obj) => (string)obj.GetValue(ValueProperty);
    public static void SetValue(DependencyObject obj, string value) => obj.SetValue(ValueProperty, value);
    private static void Changed(DependencyObject obj, DependencyPropertyChangedEventArgs args) {
        if (obj is not PasswordBox box) return;
        box.PasswordChanged -= PasswordChanged;
        if (!(bool)box.GetValue(UpdatingProperty)) box.Password = args.NewValue as string ?? "";
        box.PasswordChanged += PasswordChanged;
    }
    private static void PasswordChanged(object sender, RoutedEventArgs e) {
        var box = (PasswordBox)sender; box.SetValue(UpdatingProperty, true);
        try { box.SetCurrentValue(ValueProperty, box.Password); } finally { box.SetValue(UpdatingProperty, false); }
    }
}
