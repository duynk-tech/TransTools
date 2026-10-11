using System.Windows;
using System.Windows.Controls;
using System.Windows.Documents;
using System.Windows.Media;
using System.Text.RegularExpressions;

namespace TransTools.Views;

public sealed class MeetingNotesWindow : Window
{
    private readonly TextBox _editor;
    private readonly Func<CancellationToken, Task<string>>? _generate;
    private readonly Button _generateButton;
    private readonly Button _cancelGeneration;
    private readonly TextBlock _message = new() { TextWrapping = TextWrapping.Wrap, Margin = new Thickness(0, 8, 0, 8) };
    private CancellationTokenSource? _request;
    private bool _closed;
    private FlowDocumentScrollViewer _preview = null!;
    private void RefreshPreview() { if (_preview != null) _preview.Document = Format(string.IsNullOrWhiteSpace(Notes) ? "Chưa có ghi chú. Chọn Chỉnh sửa để tự viết." : Notes); }
    public string Notes => _editor.Text;
    public MeetingNotesWindow(string notes, string summary, string sessionTitle = "", Func<CancellationToken, Task<string>>? generate = null)
    {
        _generate = generate;
        Title = "Ghi chú"; Width = 760; Height = 560; MinWidth = 600; MinHeight = 400;
        WindowStartupLocation = WindowStartupLocation.CenterOwner;
        Background = new SolidColorBrush(Color.FromRgb(245, 248, 247));
        var layout = new DockPanel { Margin = new Thickness(20) };
        Content = layout;
        var heading = new StackPanel { Margin = new Thickness(0, 0, 0, 16) };
        heading.Children.Add(new TextBlock { Text = "Ghi chú", FontSize = 22, FontWeight = FontWeights.SemiBold, Foreground = new SolidColorBrush(Color.FromRgb(40, 117, 104)) });
        heading.Children.Add(new TextBlock { Text = sessionTitle, TextTrimming = TextTrimming.CharacterEllipsis, Margin = new Thickness(0, 6, 0, 0), Foreground = Brushes.Gray });
        DockPanel.SetDock(heading, Dock.Top); layout.Children.Add(heading);
        var footer = new StackPanel { Orientation = Orientation.Horizontal, HorizontalAlignment = HorizontalAlignment.Right, Margin = new Thickness(0, 16, 0, 0) };
        DockPanel.SetDock(footer, Dock.Bottom); layout.Children.Add(footer);
        if (!string.IsNullOrWhiteSpace(summary)) {
            var useSummary = new Button { Content = "Thêm bản tóm tắt", Style = (Style)FindResource("SecondaryButton"), Margin = new Thickness(0, 0, 8, 0) };
            useSummary.Click += (_, _) => {
                _editor!.Text += (string.IsNullOrWhiteSpace(_editor.Text) ? "" : "\n\n---\n\n") + summary;
                RefreshPreview();
            };
            footer.Children.Add(useSummary);
        }
        var close = new Button { Content = "Đóng", Style = (Style)FindResource("SecondaryButton"), Margin = new Thickness(0, 0, 8, 0) };
        close.Click += (_, _) => { DialogResult = false; }; footer.Children.Add(close);
        var save = new Button { Content = "Lưu ghi chú", IsDefault = true };
        save.Click += (_, _) => { DialogResult = true; }; footer.Children.Add(save);
        _editor = new TextBox { Text = notes, AcceptsReturn = true, AcceptsTab = true, TextWrapping = TextWrapping.Wrap,
            VerticalScrollBarVisibility = ScrollBarVisibility.Auto, FontSize = 14, Padding = new Thickness(14) };
        _editor.Visibility = Visibility.Collapsed;
        _preview = new FlowDocumentScrollViewer { IsToolBarVisible = false, VerticalScrollBarVisibility = ScrollBarVisibility.Auto, Background = Brushes.White };
        RefreshPreview();
        var tools = new DockPanel { Margin = new Thickness(0, 0, 0, 12) };
        var edit = new Button { Content = "Chỉnh sửa", Style = (Style)FindResource("SecondaryButton"), HorizontalAlignment = HorizontalAlignment.Right };
        edit.Click += (_, _) => {
            var editing = _editor.Visibility != Visibility.Visible;
            _editor.Visibility = editing ? Visibility.Visible : Visibility.Collapsed;
            _preview.Visibility = editing ? Visibility.Collapsed : Visibility.Visible;
            edit.Content = editing ? "Xem Markdown" : "Chỉnh sửa";
            if (editing) _editor.Focus(); else RefreshPreview();
        };
        DockPanel.SetDock(edit, Dock.Right); tools.Children.Add(edit);
        _generateButton = new Button { Content = "Tạo ghi chú AI", IsEnabled = generate != null, HorizontalAlignment = HorizontalAlignment.Left, ToolTip = generate == null ? "Cấu hình AI và có bản ghi để tạo ghi chú" : "Thêm ghi chú AI từ bản ghi" };
        _generateButton.Click += async (_, _) => await GenerateNotesAsync();
        _cancelGeneration = new Button { Content = "Hủy", Visibility = Visibility.Collapsed, Style = (Style)FindResource("SecondaryButton"), Margin = new Thickness(8, 0, 0, 0) };
        _cancelGeneration.Click += (_, _) => _request?.Cancel();
        var aiActions = new StackPanel { Orientation = Orientation.Horizontal }; aiActions.Children.Add(_generateButton); aiActions.Children.Add(_cancelGeneration); tools.Children.Add(aiActions);
        DockPanel.SetDock(tools, Dock.Top); layout.Children.Add(tools);
        DockPanel.SetDock(_message, Dock.Bottom); layout.Children.Add(_message);
        Closed += (_, _) => { _closed = true; _request?.Cancel(); };
        var reading = new Grid(); reading.Children.Add(_preview); reading.Children.Add(_editor);
        layout.Children.Add(new Border { Child = reading, Background = Brushes.White, BorderBrush = new SolidColorBrush(Color.FromRgb(194, 221, 213)), BorderThickness = new Thickness(1), CornerRadius = new CornerRadius(12), Padding = new Thickness(8) });

    }
    public async Task GenerateNotesAsync()
    {
        if (_closed || _request != null || _generate == null) return;
        using var request = new CancellationTokenSource(TimeSpan.FromSeconds(40));
        _request = request; _generateButton.IsEnabled = false; _generateButton.Content = "Đang tạo…";
        _cancelGeneration.Visibility = Visibility.Visible; _message.Text = "";
        try {
            var result = await _generate(request.Token);
            if (_closed || request.IsCancellationRequested || !ReferenceEquals(_request, request)) return;
            if (string.IsNullOrWhiteSpace(result)) { _message.Text = "AI chưa trả về nội dung ghi chú."; return; }
            if (result.Length > 32000) { _message.Text = "Ghi chú AI quá dài. Hãy thử lại với bản ghi ngắn hơn."; return; }
            _editor.Text += (string.IsNullOrWhiteSpace(Notes) ? "" : "\n\n---\n\n") + result.Trim();
            RefreshPreview(); _message.Text = "Đã thêm ghi chú AI. Kiểm tra nội dung trước khi lưu.";
        } catch (OperationCanceledException) when (request.IsCancellationRequested) {
            if (!_closed) _message.Text = "Đã dừng tạo ghi chú.";
        } catch (Exception ex) { if (!_closed && !request.IsCancellationRequested) _message.Text = "Chưa tạo được ghi chú: " + ex.Message; }
        finally {
            if (ReferenceEquals(_request, request)) {
                _request = null;
                if (!_closed) { _generateButton.IsEnabled = true; _generateButton.Content = "Tạo ghi chú AI"; _cancelGeneration.Visibility = Visibility.Collapsed; }
            }
        }
    }
    // Parse text as document content; never execute HTML or load user-provided XAML.
    private static FlowDocument Format(string markdown)
    {
        var document = new FlowDocument { FontSize = 14, FontFamily = new FontFamily("Segoe UI"), Foreground = new SolidColorBrush(Color.FromRgb(36, 61, 53)), PagePadding = new Thickness(16) };
        foreach (var line in markdown.Replace("\r", "").Split('\n')) {
            var content = line; var size = 14.0; var heading = false;
            if (line.StartsWith("### ")) { content = line[4..]; size = 16; heading = true; }
            else if (line.StartsWith("## ")) { content = line[3..]; size = 18; heading = true; }
            else if (line.StartsWith("# ")) { content = line[2..]; size = 22; heading = true; }
            else if (line.StartsWith("- ") || line.StartsWith("* ")) content = "• " + line[2..];
            var paragraph = new Paragraph { FontSize = size, Margin = new Thickness(0, 0, 0, 8), FontWeight = heading ? FontWeights.SemiBold : FontWeights.Normal };
            foreach (var part in Regex.Split(content, @"(\*\*[^*]+\*\*)")) {
                if (part.StartsWith("**") && part.EndsWith("**") && part.Length > 4) paragraph.Inlines.Add(new Bold(new Run(part[2..^2])));
                else paragraph.Inlines.Add(new Run(part));
            }
            document.Blocks.Add(paragraph);
        }
        return document;
    }
}
