using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;
namespace TransTools.Views;
public sealed class LicenseWindow : Window
{
    public LicenseWindow(string model, string license) {
        Title = "Giấy phép " + model; Width = 760; Height = 600; MinWidth = 540; MinHeight = 420; WindowStartupLocation = WindowStartupLocation.CenterOwner; Owner = Application.Current.MainWindow; Background = Brushes.White;
        var grid = new Grid { Margin = new Thickness(24) }; grid.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto }); grid.RowDefinitions.Add(new RowDefinition()); grid.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto }); Content = grid;
        var header = new StackPanel { Margin = new Thickness(0, 0, 0, 18) }; header.Children.Add(new TextBlock { Text = "Điều khoản sử dụng · " + model, FontSize = 24, FontWeight = FontWeights.Bold, Foreground = new SolidColorBrush(Color.FromRgb(38, 119, 107)), TextWrapping = TextWrapping.Wrap }); header.Children.Add(new TextBlock { Text = "Đọc giấy phép trước khi tải. Đồng ý nghĩa là bạn chấp nhận các điều kiện sử dụng và phân phối mô hình.", FontSize = 14, Foreground = Brushes.DimGray, TextWrapping = TextWrapping.Wrap, Margin = new Thickness(0, 10, 0, 0) }); grid.Children.Add(header);
        var body = new TextBox { Text = license, IsReadOnly = true, TextWrapping = TextWrapping.Wrap, VerticalScrollBarVisibility = ScrollBarVisibility.Auto, Padding = new Thickness(16), FontSize = 14, Background = new SolidColorBrush(Color.FromRgb(246, 250, 248)), Foreground = Brushes.Black, BorderBrush = new SolidColorBrush(Color.FromRgb(117, 187, 174)) }; Grid.SetRow(body, 1); grid.Children.Add(body);
        var actions = new StackPanel { Orientation = Orientation.Horizontal, HorizontalAlignment = HorizontalAlignment.Right, Margin = new Thickness(0, 18, 0, 0) }; var cancel = new Button { Content = "Hủy", IsCancel = true, Margin = new Thickness(0, 0, 8, 0) }; var agree = new Button { Content = "Đồng ý & Tải mô hình" }; agree.Click += (_, _) => DialogResult = true; actions.Children.Add(cancel); actions.Children.Add(agree); Grid.SetRow(actions, 2); grid.Children.Add(actions);
    }
}
