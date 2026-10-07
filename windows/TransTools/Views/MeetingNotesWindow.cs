using System.Windows;
using System.Windows.Controls;
using System.Windows.Documents;
using System.Windows.Media;
using System.Text.RegularExpressions;

namespace TransTools.Views;

public sealed class MeetingNotesWindow : Window
{
    private readonly TextBox _editor;
    public string Notes => _editor.Text;
    public MeetingNotesWindow(string notes, string summary)
    {
        Title = "Ghi chú cuộc họp"; Width = 760; Height = 560; MinWidth = 600; MinHeight = 400;
        WindowStartupLocation = WindowStartupLocation.CenterOwner;
        Background = new SolidColorBrush(Color.FromRgb(245, 248, 247));
        var layout = new DockPanel { Margin = new Thickness(20) };
        Content = layout;
        var title = new TextBlock { Text = "Ghi chú", FontSize = 22, FontWeight = FontWeights.SemiBold, Margin = new Thickness(0, 0, 0, 16) };
        DockPanel.SetDock(title, Dock.Top); layout.Children.Add(title);
        var footer = new StackPanel { Orientation = Orientation.Horizontal, HorizontalAlignment = HorizontalAlignment.Right, Margin = new Thickness(0, 16, 0, 0) };
        DockPanel.SetDock(footer, Dock.Bottom); layout.Children.Add(footer);
        if (!string.IsNullOrWhiteSpace(summary)) {
            var useSummary = new Button { Content = "Dùng bản tóm tắt", Style = (Style)FindResource("SecondaryButton"), Margin = new Thickness(0, 0, 8, 0) };
            useSummary.Click += (_, _) => _editor!.Text = summary;
            footer.Children.Add(useSummary);
        }
        var close = new Button { Content = "Đóng", Style = (Style)FindResource("SecondaryButton"), Margin = new Thickness(0, 0, 8, 0) };
        close.Click += (_, _) => { DialogResult = false; }; footer.Children.Add(close);
        var save = new Button { Content = "Lưu ghi chú", IsDefault = true };
        save.Click += (_, _) => { DialogResult = true; }; footer.Children.Add(save);
        _editor = new TextBox { Text = notes, AcceptsReturn = true, AcceptsTab = true, TextWrapping = TextWrapping.Wrap,
            VerticalScrollBarVisibility = ScrollBarVisibility.Auto, FontSize = 14, Padding = new Thickness(14) };
        var preview = new FlowDocumentScrollViewer { IsToolBarVisible = false, VerticalScrollBarVisibility = ScrollBarVisibility.Auto };
        var tabs = new TabControl();
        tabs.Items.Add(new TabItem { Header = "Viết", Content = _editor });
        var previewTab = new TabItem { Header = "Xem trước", Content = preview }; tabs.Items.Add(previewTab);
        tabs.SelectionChanged += (_, _) => { if (previewTab.IsSelected) preview.Document = Format(Notes); };
        layout.Children.Add(tabs);
    }
    // Parse text as document content; never execute HTML or load user-provided XAML.
    private static FlowDocument Format(string markdown)
    {
        var document = new FlowDocument { FontSize = 14, PagePadding = new Thickness(16) };
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
