using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;
using TransTools.Models;
using TransTools.Services.Notebook;

namespace TransTools.Views;

public sealed class MeetingTasksWindow : Window
{
    // This template is fixed application markup, never user or AI content.
    private static readonly Style CompletionStyle = (Style)System.Windows.Markup.XamlReader.Parse("""
        <Style xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml" TargetType="CheckBox">
          <Setter Property="Width" Value="24"/><Setter Property="Height" Value="24"/><Setter Property="Cursor" Value="Hand"/>
          <Setter Property="Template"><Setter.Value><ControlTemplate TargetType="CheckBox">
            <Border x:Name="Circle" Width="22" Height="22" CornerRadius="11" Background="Transparent" BorderBrush="#8CA69C" BorderThickness="1.5">
              <TextBlock x:Name="Tick" Text="✓" Visibility="Collapsed" Foreground="White" FontSize="14" FontWeight="Bold" VerticalAlignment="Center" HorizontalAlignment="Center"/>
            </Border>
            <ControlTemplate.Triggers>
              <Trigger Property="IsChecked" Value="True"><Setter TargetName="Circle" Property="Background" Value="#287568"/><Setter TargetName="Circle" Property="BorderBrush" Value="#287568"/><Setter TargetName="Tick" Property="Visibility" Value="Visible"/></Trigger>
              <Trigger Property="IsMouseOver" Value="True"><Setter TargetName="Circle" Property="BorderBrush" Value="#287568"/></Trigger>
              <Trigger Property="IsKeyboardFocused" Value="True"><Setter TargetName="Circle" Property="BorderBrush" Value="#287568"/></Trigger>
              <Trigger Property="IsEnabled" Value="False"><Setter Property="Opacity" Value="0.5"/></Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate></Setter.Value></Setter>
        </Style>
        """);
    private readonly MeetingSession _session;
    private readonly Func<string, CancellationToken, Task<string>>? _generate;
    private readonly CancellationTokenSource _lifetime = new();
    private readonly StackPanel _items = new();
    private readonly DockPanel _addRow = new() { Margin = new Thickness(0, 12, 0, 12) };
    private readonly TextBlock _status = new() { TextWrapping = TextWrapping.Wrap, Margin = new Thickness(0, 10, 0, 10) };
    private readonly Button _analyze;
    private bool _running;

    public MeetingTasksWindow(MeetingSession session, Func<string, CancellationToken, Task<string>>? generate)
    {
        _session = session; _generate = generate;
        Title = "Việc cần làm sau cuộc họp"; Width = 640; Height = 500; MinWidth = 600; MinHeight = 400;
        WindowStartupLocation = WindowStartupLocation.CenterOwner;
        Background = Brushes.White;
        var layout = new DockPanel(); Content = layout;
        var heading = new DockPanel { Margin = new Thickness(20, 16, 20, 16) };
        var close = new Button { Content = "\uE711", FontFamily = new FontFamily("Segoe MDL2 Assets"), Width = 32, MinHeight = 32, Padding = new Thickness(0), Style = (Style)FindResource("SecondaryButton"), ToolTip = "Đóng", VerticalAlignment = VerticalAlignment.Center, Margin = new Thickness(12, 0, 0, 0) };
        close.Click += (_, _) => Close(); DockPanel.SetDock(close, Dock.Right); heading.Children.Add(close);
        var icon = new TextBlock { Text = "\uE9D5", FontFamily = new FontFamily("Segoe MDL2 Assets"), FontSize = 20, Foreground = new SolidColorBrush(Color.FromRgb(40, 117, 104)), VerticalAlignment = VerticalAlignment.Center, Margin = new Thickness(0, 0, 12, 0) };
        DockPanel.SetDock(icon, Dock.Left); heading.Children.Add(icon);
        var titles = new StackPanel();
        titles.Children.Add(new TextBlock { Text = "Việc cần làm sau cuộc họp (AI)", Style = (Style)FindResource("PageHeading") });
        titles.Children.Add(new TextBlock { Text = session.Title, FontSize = 12, Foreground = new SolidColorBrush(Color.FromRgb(101, 117, 111)), TextTrimming = TextTrimming.CharacterEllipsis, ToolTip = session.Title, Margin = new Thickness(0, 2, 0, 0) });
        heading.Children.Add(titles);
        var header = new Border { Background = Mint(), Child = heading }; DockPanel.SetDock(header, Dock.Top); layout.Children.Add(header);
        var footer = new StackPanel { Orientation = Orientation.Horizontal, HorizontalAlignment = HorizontalAlignment.Right, Margin = new Thickness(20, 12, 20, 12) };
        _analyze = new Button { Content = "Phân tích lại", Style = (Style)FindResource("SecondaryButton"), Margin = new Thickness(0, 0, 8, 0) };
        _analyze.Click += async (_, _) => await AnalyzeAsync(); footer.Children.Add(_analyze);
        var copy = new Button { Content = "Sao chép danh sách", Style = (Style)FindResource("SecondaryButton"), Margin = new Thickness(0, 0, 8, 0) };
        copy.Click += (_, _) => {
            var lines = _items.Children.OfType<Border>().Select(b => (Grid)b.Child).Select(g => ((CheckBox)g.Children[0], (TextBox)g.Children[1])).Where(p => !string.IsNullOrWhiteSpace(p.Item2.Text)).Select(p => $"- [{(p.Item1.IsChecked == true ? "x" : " ")}] {p.Item2.Text}");
            var text = string.Join(Environment.NewLine, lines);
            if (text.Length > 0) { Clipboard.SetText(text); _status.Text = "Đã sao chép danh sách"; }
        }; footer.Children.Add(copy);
        var footerSurface = new Border { Background = Mint(), Child = footer };
        DockPanel.SetDock(footerSurface, Dock.Bottom); layout.Children.Add(footerSurface);
        var body = new DockPanel { Margin = new Thickness(24, 10, 24, 0) };
        DockPanel.SetDock(_status, Dock.Top); body.Children.Add(_status);
        var addRow = _addRow;
        var add = new Button { Content = "Thêm việc", Style = (Style)FindResource("SecondaryButton"), Margin = new Thickness(8, 0, 0, 0) };
        var input = new TextBox { ToolTip = "Nội dung việc mới", MaxLength = 600, Margin = new Thickness(0) };
        void AddManual() { var value = input.Text.Trim(); if (value.Length == 0 || _running) return; AddTask(new(value, "")); input.Clear(); input.Focus(); }
        add.Click += (_, _) => AddManual();
        input.KeyDown += (_, e) => { if (e.Key == System.Windows.Input.Key.Enter) { AddManual(); e.Handled = true; } };
        DockPanel.SetDock(add, Dock.Right); addRow.Children.Add(add); addRow.Children.Add(input);
        DockPanel.SetDock(addRow, Dock.Bottom); body.Children.Add(addRow);
        body.Children.Add(new ScrollViewer { VerticalScrollBarVisibility = ScrollBarVisibility.Auto, Content = _items }); layout.Children.Add(body);
        Loaded += async (_, _) => await AnalyzeAsync();
        Closed += (_, _) => _lifetime.Cancel();
    }
    private static SolidColorBrush Mint() => new(Color.FromRgb(225, 238, 230));
    private void AddTask(MeetingTask task)
    {
        var grid = new Grid();
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        grid.ColumnDefinitions.Add(new ColumnDefinition());
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        var check = new CheckBox { Style = CompletionStyle, ToolTip = "Đánh dấu hoàn thành", VerticalAlignment = VerticalAlignment.Top, Margin = new Thickness(0, 10, 12, 0) }; grid.Children.Add(check);
        var text = new TextBox { Text = task.Title, TextWrapping = TextWrapping.Wrap, AcceptsReturn = true, MaxLength = 600, MaxHeight = 170, VerticalScrollBarVisibility = ScrollBarVisibility.Auto, Margin = new Thickness(0), Padding = new Thickness(8) }; Grid.SetColumn(text, 1); grid.Children.Add(text);
        check.Checked += (_, _) => { text.TextDecorations = TextDecorations.Strikethrough; text.Foreground = new SolidColorBrush(Color.FromRgb(115, 130, 124)); };
        check.Unchecked += (_, _) => { text.TextDecorations = null; text.Foreground = new SolidColorBrush(Color.FromRgb(36, 61, 53)); };
        var remove = new Button { Content = "\uE74D", FontFamily = new FontFamily("Segoe MDL2 Assets"), Width = 32, Padding = new Thickness(4), MinHeight = 32, Style = (Style)FindResource("DestructiveButton"), Margin = new Thickness(8, 0, 0, 0), ToolTip = "Xóa việc", VerticalAlignment = VerticalAlignment.Top }; Grid.SetColumn(remove, 3); grid.Children.Add(remove);
        if (task.Assignee.Length > 0) {
            var badge = new Border { Background = Mint(), CornerRadius = new CornerRadius(10), Padding = new Thickness(7, 4, 7, 4), Margin = new Thickness(8, 4, 0, 0), VerticalAlignment = VerticalAlignment.Top,
                Child = new TextBlock { Text = task.Assignee, MaxWidth = 90, TextTrimming = TextTrimming.CharacterEllipsis, ToolTip = task.Assignee, FontSize = 11 } };
            Grid.SetColumn(badge, 2); grid.Children.Add(badge);
        }
        var card = new Border { Child = grid, BorderBrush = new SolidColorBrush(Color.FromRgb(194, 221, 213)), BorderThickness = new Thickness(1), CornerRadius = new CornerRadius(12), Padding = new Thickness(12), Margin = new Thickness(0, 0, 0, 10) };
        remove.Click += (_, _) => _items.Children.Remove(card); _items.Children.Add(card);
    }
    private async Task AnalyzeAsync()
    {
        if (_running) return;
        _running = true; _analyze.IsEnabled = false; _items.IsEnabled = _addRow.IsEnabled = false; _status.Text = "Đang phân tích bản ghi…";
        try {
            var tasks = await MeetingTaskExtractor.ExtractAsync(_session, _generate, _lifetime.Token);
            if (_lifetime.IsCancellationRequested) return;
            _items.Children.Clear();
            foreach (var task in tasks) AddTask(task);
            _status.Text = tasks.Count == 0 ? "Chưa tìm thấy việc cần làm trong bản ghi." : "Kiểm tra và chỉnh sửa danh sách trước khi sử dụng.";
        } catch (OperationCanceledException) when (_lifetime.IsCancellationRequested) { }
        catch (Exception ex) { if (!_lifetime.IsCancellationRequested) _status.Text = "Chưa phân tích được: " + ex.Message; }
        finally { _running = false; if (!_lifetime.IsCancellationRequested) { _analyze.IsEnabled = true; _items.IsEnabled = _addRow.IsEnabled = true; } }
    }
}
