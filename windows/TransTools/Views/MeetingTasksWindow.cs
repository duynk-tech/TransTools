using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;
using TransTools.Models;
using TransTools.Services.Notebook;

namespace TransTools.Views;

public sealed class MeetingTasksWindow : Window
{
    private readonly MeetingSession _session;
    private readonly Func<string, CancellationToken, Task<string>>? _generate;
    private readonly CancellationTokenSource _lifetime = new();
    private readonly StackPanel _items = new();
    private readonly TextBlock _status = new() { TextWrapping = TextWrapping.Wrap, Margin = new Thickness(0, 10, 0, 10) };
    private readonly Button _analyze;
    private bool _running;

    public MeetingTasksWindow(MeetingSession session, Func<string, CancellationToken, Task<string>>? generate)
    {
        _session = session; _generate = generate;
        Title = "Việc cần làm sau cuộc họp"; Width = 780; Height = 620; MinWidth = 600; MinHeight = 400;
        WindowStartupLocation = WindowStartupLocation.CenterOwner;
        Background = Brushes.White;
        var layout = new DockPanel(); Content = layout;
        var heading = new StackPanel { Margin = new Thickness(24, 18, 24, 18) };
        heading.Children.Add(new TextBlock { Text = "Việc cần làm sau cuộc họp", FontSize = 22, FontWeight = FontWeights.SemiBold });
        heading.Children.Add(new TextBlock { Text = session.Title, TextTrimming = TextTrimming.CharacterEllipsis, Margin = new Thickness(0, 6, 0, 0) });
        var header = new Border { Background = Mint(), Child = heading }; DockPanel.SetDock(header, Dock.Top); layout.Children.Add(header);
        var footer = new StackPanel { Orientation = Orientation.Horizontal, HorizontalAlignment = HorizontalAlignment.Right, Margin = new Thickness(20) };
        _analyze = new Button { Content = "Phân tích lại", Style = (Style)FindResource("SecondaryButton"), Margin = new Thickness(0, 0, 8, 0) };
        _analyze.Click += async (_, _) => await AnalyzeAsync(); footer.Children.Add(_analyze);
        var copy = new Button { Content = "Sao chép danh sách", Style = (Style)FindResource("SecondaryButton"), Margin = new Thickness(0, 0, 8, 0) };
        copy.Click += (_, _) => {
            var lines = _items.Children.OfType<Border>().Select(b => (Grid)b.Child).Select(g => ((CheckBox)g.Children[0], (TextBox)g.Children[1])).Where(p => !string.IsNullOrWhiteSpace(p.Item2.Text)).Select(p => $"- [{(p.Item1.IsChecked == true ? "x" : " ")}] {p.Item2.Text}");
            var text = string.Join(Environment.NewLine, lines);
            if (text.Length > 0) { Clipboard.SetText(text); _status.Text = "Đã sao chép danh sách"; }
        }; footer.Children.Add(copy);
        var close = new Button { Content = "Đóng", Style = (Style)FindResource("SecondaryButton") }; close.Click += (_, _) => Close(); footer.Children.Add(close);
        DockPanel.SetDock(footer, Dock.Bottom); layout.Children.Add(footer);
        var body = new DockPanel { Margin = new Thickness(24, 10, 24, 0) };
        DockPanel.SetDock(_status, Dock.Top); body.Children.Add(_status);
        body.Children.Add(new ScrollViewer { VerticalScrollBarVisibility = ScrollBarVisibility.Auto, Content = _items }); layout.Children.Add(body);
        Loaded += async (_, _) => await AnalyzeAsync();
        Closed += (_, _) => _lifetime.Cancel();
    }
    private static SolidColorBrush Mint() => new(Color.FromRgb(225, 238, 230));
    private async Task AnalyzeAsync()
    {
        if (_running) return;
        _running = true; _analyze.IsEnabled = false; _status.Text = "Đang phân tích bản ghi…";
        try {
            var tasks = await MeetingTaskExtractor.ExtractAsync(_session, _generate, _lifetime.Token);
            if (_lifetime.IsCancellationRequested) return;
            _items.Children.Clear();
            foreach (var task in tasks) {
                var grid = new Grid(); grid.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto }); grid.ColumnDefinitions.Add(new ColumnDefinition()); grid.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
                var check = new CheckBox { VerticalAlignment = VerticalAlignment.Top, Margin = new Thickness(0, 10, 12, 0) }; grid.Children.Add(check);
                var text = new TextBox { Text = task.Title, TextWrapping = TextWrapping.Wrap, AcceptsReturn = true, MaxHeight = 170, VerticalScrollBarVisibility = ScrollBarVisibility.Auto, ToolTip = task.Assignee, Margin = new Thickness(0), Padding = new Thickness(8) }; Grid.SetColumn(text, 1); grid.Children.Add(text);
                var remove = new Button { Content = "\uE74D", FontFamily = new FontFamily("Segoe MDL2 Assets"), Width = 32, Padding = new Thickness(4), MinHeight = 32, Style = (Style)FindResource("DestructiveButton"), Margin = new Thickness(8, 0, 0, 0), ToolTip = "Xóa việc" }; Grid.SetColumn(remove, 2); grid.Children.Add(remove);
                var card = new Border { Child = grid, BorderBrush = new SolidColorBrush(Color.FromRgb(194, 221, 213)), BorderThickness = new Thickness(1), CornerRadius = new CornerRadius(12), Padding = new Thickness(12), Margin = new Thickness(0, 0, 0, 10) };
                remove.Click += (_, _) => _items.Children.Remove(card); _items.Children.Add(card);
            }
            _status.Text = tasks.Count == 0 ? "Chưa tìm thấy việc cần làm trong bản ghi." : "Kiểm tra và chỉnh sửa danh sách trước khi sử dụng.";
        } catch (OperationCanceledException) when (_lifetime.IsCancellationRequested) { }
        catch (Exception ex) { if (!_lifetime.IsCancellationRequested) _status.Text = "Chưa phân tích được: " + ex.Message; }
        finally { _running = false; if (!_lifetime.IsCancellationRequested) _analyze.IsEnabled = true; }
    }
}
