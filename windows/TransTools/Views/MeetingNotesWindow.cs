using System.Windows;
using System.Windows.Controls;
using System.Windows.Documents;
using System.Windows.Media;
using System.Text.RegularExpressions;

namespace TransTools.Views;

public sealed class MeetingNotesWindow : Window
{
    private readonly TextBox _editor;
    private FlowDocumentScrollViewer _preview = null!;
    private void RefreshPreview() { if (_preview != null) _preview.Document = Format(string.IsNullOrWhiteSpace(Notes) ? "Chưa có ghi chú. Chọn Chỉnh sửa để tự viết." : Notes); }
    public string Notes => _editor.Text;
    public MeetingNotesWindow(string notes, string summary, string sessionTitle = "")
    {
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
        tools.Children.Add(edit); DockPanel.SetDock(tools, Dock.Top); layout.Children.Add(tools);
        var reading = new Grid(); reading.Children.Add(_preview); reading.Children.Add(_editor);
        layout.Children.Add(new Border { Child = reading, Background = Brushes.White, BorderBrush = new SolidColorBrush(Color.FromRgb(194, 221, 213)), BorderThickness = new Thickness(1), CornerRadius = new CornerRadius(12), Padding = new Thickness(8) });

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
