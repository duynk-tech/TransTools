using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;
using TransTools.Models;
using TransTools.Services.Learning;
using TransTools.ViewModels;
namespace TransTools.Views;
public sealed class NotebookLearningWindow : Window
{
    public string ImportStatus { get; private set; } = "";
    public NotebookLearningWindow(MeetingSession session, LearningViewModel learning)
    {
        Title = "Học từ Sổ tay"; Width = 720; Height = 560; MinWidth = 580; MinHeight = 420;
        WindowStartupLocation = WindowStartupLocation.CenterOwner; Background = Brushes.White; ShowInTaskbar = false;
        var root = new DockPanel { Margin = new Thickness(24) }; Content = root;
        var heading = new StackPanel { Margin = new Thickness(0, 0, 0, 16) };
        heading.Children.Add(new TextBlock { Text = "Học từ Sổ tay", FontSize = 20, FontWeight = FontWeights.Bold });
        heading.Children.Add(new TextBlock { Text = session.Title, TextWrapping = TextWrapping.Wrap, Foreground = Brushes.DimGray, Margin = new Thickness(0, 8, 0, 8) });
        var languageName = learning.SelectedLanguage switch { "en" => "Tiếng Anh", "ja" => "Tiếng Nhật", "zh" => "Tiếng Trung", "ko" => "Tiếng Hàn", _ => learning.SelectedLanguage };
        heading.Children.Add(new TextBlock { Text = $"Tiếng gốc: {languageName} · Bản dịch: Tiếng Việt. Thêm tối đa 20 câu ngắn, không gửi lên AI.", TextWrapping = TextWrapping.Wrap });
        DockPanel.SetDock(heading, Dock.Top); root.Children.Add(heading);
        var pairs = NotebookLearningPolicy.Candidates(session.Captions, learning.SelectedLanguage).Take(20).ToList();
        var previewSession = new MeetingSession { Captions = pairs.Select(pair => new Caption { Original = pair.Original, OriginalTextForLearning = pair.OriginalTextForLearning, Vietnamese = pair.Vietnamese, SourceLanguage = pair.SourceLanguage, TargetLanguage = pair.TargetLanguage, TranslationSource = pair.TranslationSource }).ToList() };
        var footer = new StackPanel { Margin = new Thickness(0, 16, 0, 0) };
        var confirmed = new CheckBox { Content = "Tôi đã kiểm tra ngôn ngữ, các câu và bản dịch", Margin = new Thickness(0, 0, 0, 12) };
        footer.Children.Add(confirmed);
        var actions = new StackPanel { Orientation = Orientation.Horizontal, HorizontalAlignment = HorizontalAlignment.Right };
        var close = new Button { Content = "Đóng", IsCancel = true, Style = (Style)FindResource("SecondaryButton"), Margin = new Thickness(0, 0, 8, 0) };
        close.Click += (_, _) => Close(); actions.Children.Add(close);
        var add = new Button { Content = "Thêm vào bài học", IsEnabled = false };
        confirmed.Checked += (_, _) => add.IsEnabled = pairs.Count > 0;
        confirmed.Unchecked += (_, _) => add.IsEnabled = false;
        add.Click += (_, _) => { if (confirmed.IsChecked != true || pairs.Count == 0) return; ImportStatus = learning.ImportNotebook(previewSession); DialogResult = true; };
        actions.Children.Add(add); footer.Children.Add(actions);
        footer.Children.Add(new TextBlock { Text = "Bản ghi gốc được giữ nguyên. Câu dài, khác ngôn ngữ hoặc chưa dịch đủ được bỏ qua.", FontSize = 11, Foreground = Brushes.DimGray, TextWrapping = TextWrapping.Wrap, Margin = new Thickness(0, 12, 0, 0) });
        DockPanel.SetDock(footer, Dock.Bottom); root.Children.Add(footer);
        var contents = new StackPanel();
        if (pairs.Count == 0) contents.Children.Add(new TextBlock { Text = "Không có cặp câu phù hợp với ngôn ngữ đang học.", TextWrapping = TextWrapping.Wrap });
        foreach (var pair in pairs) {
            var card = new StackPanel();
            card.Children.Add(new TextBlock { Text = pair.OriginalTextForLearning ?? pair.Original, TextWrapping = TextWrapping.Wrap });
            card.Children.Add(new TextBlock { Text = pair.Vietnamese, TextWrapping = TextWrapping.Wrap, Foreground = new SolidColorBrush(Color.FromRgb(40, 117, 104)), Margin = new Thickness(0, 6, 0, 0) });
            contents.Children.Add(new Border { Child = card, BorderBrush = new SolidColorBrush(Color.FromRgb(194, 221, 213)), BorderThickness = new Thickness(1), CornerRadius = new CornerRadius(12), Padding = new Thickness(14), Margin = new Thickness(0, 0, 0, 12) });
        }
        root.Children.Add(new ScrollViewer { Content = contents, VerticalScrollBarVisibility = ScrollBarVisibility.Auto });
    }
}
