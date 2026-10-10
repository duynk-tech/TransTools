using System.IO;
using System.Windows;
using Microsoft.Web.WebView2.Core;
using Microsoft.Web.WebView2.Wpf;

internal static class Program
{
    [STAThread]
    public static void Main()
    {
        var app = new Application();
        var view = new WebView2();
        var window = new Window { Title = "Trans Tools · Local translation compatibility probe", Width = 860, Height = 760, Content = view };
        window.Loaded += async (_, _) => {
            try {
                var profile = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "TransTools-TranslationProbe", "WebView2");
                var environment = await CoreWebView2Environment.CreateAsync(userDataFolder: profile);
                await view.EnsureCoreWebView2Async(environment);
                view.CoreWebView2.SetVirtualHostNameToFolderMapping("trans-tools-probe.example", Path.Combine(AppContext.BaseDirectory, "page"), CoreWebView2HostResourceAccessKind.DenyCors);
                view.CoreWebView2.NavigationStarting += (_, e) => { if (!e.Uri.StartsWith("https://trans-tools-probe.example/", StringComparison.Ordinal)) e.Cancel = true; };
                view.CoreWebView2.NewWindowRequested += (_, e) => e.Handled = true;
                view.CoreWebView2.Navigate("https://trans-tools-probe.example/index.html");
            } catch (Exception ex) {
                MessageBox.Show("WebView2 probe could not start: " + ex.Message, "Compatibility probe");
                window.Close();
            }
        };
        window.Closed += (_, _) => view.Dispose();
        app.Run(window);
    }
}
