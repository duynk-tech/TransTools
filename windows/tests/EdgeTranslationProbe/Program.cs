using System.IO;
using System.Windows;
using Microsoft.Web.WebView2.Core;
using Microsoft.Web.WebView2.Wpf;

internal static class Program
{
    [STAThread]
    public static void Main(string[] args)
    {
        var reportPath = args.Length == 2 && args[0] == "--availability-report" ? Path.GetFullPath(args[1]) : null;
        var app = new Application();
        var view = new WebView2();
        var window = new Window { Title = "Trans Tools · Local translation compatibility probe", Width = 860, Height = 760, Content = view };
        bool reported = false;
        void SaveReport(string json) {
            if (reportPath == null || reported) return;
            Directory.CreateDirectory(Path.GetDirectoryName(reportPath)!);
            File.WriteAllText(reportPath, json); reported = true; window.Close();
        }
        var timeout = new System.Windows.Threading.DispatcherTimer { Interval = TimeSpan.FromSeconds(30) };
        timeout.Tick += (_, _) => { timeout.Stop(); SaveReport(System.Text.Json.JsonSerializer.Serialize(new { kind = "translation-compatibility-probe", offlineVerified = false, error = "availability-timeout" })); };
        if (reportPath != null) timeout.Start();
        window.Loaded += async (_, _) => {
            try {
                var profile = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "TransTools-TranslationProbe", "WebView2");
                var environment = await CoreWebView2Environment.CreateAsync(userDataFolder: profile);
                await view.EnsureCoreWebView2Async(environment);
                view.CoreWebView2.SetVirtualHostNameToFolderMapping("trans-tools-probe.example", Path.Combine(AppContext.BaseDirectory, "page"), CoreWebView2HostResourceAccessKind.DenyCors);
                view.CoreWebView2.NavigationStarting += (_, e) => { if (!e.Uri.StartsWith("https://trans-tools-probe.example/", StringComparison.Ordinal)) e.Cancel = true; };
                view.CoreWebView2.NewWindowRequested += (_, e) => e.Handled = true;
                if (reportPath != null) {
                    view.CoreWebView2.WebMessageReceived += (_, e) => SaveReport(e.WebMessageAsJson);
                    view.CoreWebView2.NavigationCompleted += async (_, e) => {
                        if (!e.IsSuccess) { SaveReport(System.Text.Json.JsonSerializer.Serialize(new { kind = "translation-compatibility-probe", offlineVerified = false, error = e.WebErrorStatus.ToString() })); return; }
                        try { await view.CoreWebView2.ExecuteScriptAsync("""
                            (async () => {
                                const checks = [];
                                for (const [sourceLanguage,targetLanguage] of [['en','vi'],['vi','en']]) {
                                    try { checks.push({sourceLanguage,targetLanguage,availability: typeof globalThis.Translator?.availability === 'function' ? await Translator.availability({sourceLanguage,targetLanguage}) : 'api-absent'}); }
                                    catch (error) { checks.push({sourceLanguage,targetLanguage,error:String(error)}); }
                                }
                                chrome.webview.postMessage({kind:'translation-compatibility-probe',host:'WebView2',userAgent:navigator.userAgent,secureContext:isSecureContext,offlineVerified:false,modelDownloadAttempted:false,checks});
                            })();
                            """); } catch (Exception ex) { SaveReport(System.Text.Json.JsonSerializer.Serialize(new { kind = "translation-compatibility-probe", offlineVerified = false, error = ex.Message })); }
                    };
                }
                view.CoreWebView2.Navigate("https://trans-tools-probe.example/index.html");
            } catch (Exception ex) {
                if (reportPath != null) SaveReport(System.Text.Json.JsonSerializer.Serialize(new { kind = "translation-compatibility-probe", offlineVerified = false, error = ex.Message }));
                else MessageBox.Show("WebView2 probe could not start: " + ex.Message, "Compatibility probe");
                window.Close();
            }
        };
        window.Closed += (_, _) => { timeout.Stop(); view.Dispose(); };
        app.Run(window);
    }
}
