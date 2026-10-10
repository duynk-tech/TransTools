using System.Diagnostics;
using System.Reflection;
using System.Windows;
namespace TransTools.Views;
public partial class AboutWindow : Window
{
    public AboutWindow() { InitializeComponent(); var version = typeof(AboutWindow).Assembly.GetName().Version; VersionLabel.Text = $"v{version?.Major}.{version?.Minor}.{version?.Build}"; }
    private void Close_Click(object sender, RoutedEventArgs e) => Close();
    private void CopyEmail_Click(object sender, RoutedEventArgs e) { try { Clipboard.SetText("khacduy90@gmail.com"); CopyEmail.Content = "Đã chép"; } catch { CopyEmail.Content = "Chép lại"; } }
    private void GitHub_Click(object sender, RoutedEventArgs e) { try { Process.Start(new ProcessStartInfo("https://github.com/duynk-tech/TransTools") { UseShellExecute = true }); } catch { CopyEmail.Content = "Không mở được liên kết"; } }
}
