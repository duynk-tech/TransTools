using System.Diagnostics;
using TransTools.ViewModels;
using TransTools.Models;
using TransTools.Views;
using System.IO;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using System.Windows.Threading;

internal static class Program
{
    [STAThread] private static int Main(string[] args)
    {
        var output = Path.GetFullPath(args.FirstOrDefault() ?? "windows/test-results/ui");
        Directory.CreateDirectory(output);
        var errors = new BindingErrors();
        PresentationTraceSources.DataBindingSource.Listeners.Add(errors);
        PresentationTraceSources.DataBindingSource.Switch.Level = SourceLevels.Error;
        try {
            var app = new TransTools.App(); app.InitializeComponent();
            var window = new TransTools.MainWindow(); app.MainWindow = window; window.Show();
            foreach (var (width, height) in new[] { (1280, 820), (1000, 600) }) {
                window.Width = width; window.Height = height;
                foreach (var route in new[] { "Cuộc họp", "Sổ tay", "Dịch nhanh", "Học ngôn ngữ", "Trò chuyện", "Cài đặt" }) {
                    var button = Descendants(window).OfType<RadioButton>().First(b => Equals(b.Content, route));
                    button.IsChecked = true; Pump(); window.UpdateLayout();
                    var meeting = Descendants(window).OfType<MeetingView>().FirstOrDefault()?.DataContext as MeetingViewModel;
                    if (meeting != null && meeting.Captions.Count == 0) {
                        for (var n = 0; n < 12; n++) meeting.Captions.Add(new Caption { Start = n * 8, End = n * 8 + 7, Original = "We should preserve the full conversation, including longer sentences and the context needed to understand the discussion.", Vietnamese = "Cần giữ đầy đủ cuộc hội thoại, bao gồm những câu dài và ngữ cảnh để hiểu đúng nội dung đang thảo luận." });
                    }
                    var conversation = Descendants(window).OfType<ConversationView>().FirstOrDefault()?.DataContext as ConversationViewModel;
                    if (conversation != null && conversation.Messages.Count == 0) {
                        for (var n = 0; n < 8; n++) conversation.Messages.Add(new ChatMessageItem { IsUser = n % 2 == 0, Text = "Let us practice a longer conversation about your work and the next project. What would you like to discuss today?", Translation = n % 2 == 0 ? "" : "Cùng luyện một cuộc trò chuyện dài về công việc và dự án sắp tới. Hôm nay bạn muốn thảo luận điều gì?" });
                    }
                    var notebook = Descendants(window).OfType<NotebookView>().FirstOrDefault()?.DataContext as NotebookViewModel;
                    if (notebook != null && notebook.Sessions.Count == 0) {
                        var sample = new MeetingSession { Title = "Cuộc họp dự án • Nội dung dài để kiểm tra bố cục", DurationSeconds = 96, Notes = "# Ghi chú cuộc họp\n- Giữ nguyên toàn bộ nội dung đã ghi nhận.", Captions = Enumerable.Range(0, 12).Select(n => new Caption { Start = n * 8, End = n * 8 + 7, Original = "The recording should remain readable when the window is resized and when a longer sentence arrives.", Vietnamese = "Bản ghi phải dễ đọc khi thay đổi kích thước cửa sổ và khi xuất hiện câu dài hơn." }).ToList() };
                        notebook.Sessions.Add(sample); notebook.SelectedSession = sample;
                    }
                    Pump(); window.UpdateLayout();
                    if (button.ActualHeight < 30 || button.ActualWidth < 60) throw new Exception("Navigation collapsed: " + route);
                    var root = (FrameworkElement)window.Content;
                    var bitmap = new RenderTargetBitmap((int)Math.Ceiling(root.ActualWidth), (int)Math.Ceiling(root.ActualHeight), 96, 96, PixelFormats.Pbgra32);
                    bitmap.Render(root);
                    var png = new PngBitmapEncoder(); png.Frames.Add(BitmapFrame.Create(bitmap));
                    var filename = $"{width}-{Array.IndexOf(new[] { "Cuộc họp", "Sổ tay", "Dịch nhanh", "Học ngôn ngữ", "Trò chuyện", "Cài đặt" }, route)}.png";
                    using var file = File.Create(Path.Combine(output, filename)); png.Save(file);
                    Console.WriteLine($"PASS: rendered {route} at {width}x{height}");
                }
            }
            var chatModel = Descendants(window).OfType<ConversationView>().FirstOrDefault()?.DataContext as ConversationViewModel;
            // The cached conversation view may be hidden; create an isolated fixture instead.
            chatModel = new ConversationViewModel(() => false);
            chatModel.Messages.Add(new ChatMessageItem { Text = "A long reply should wrap and remain readable in the mini chat window. The user should be able to follow the conversation while the main window is closed.", Translation = "Câu trả lời dài cần xuống dòng và vẫn dễ đọc trong cửa sổ trò chuyện nhỏ." });
            var mini = new ConversationMiniWindow(chatModel); mini.Show(); Pump(); Capture(mini, output, "mini-chat.png"); mini.CloseForExit(); chatModel.Dispose();
            var hud = new FloatingSubtitleWindow(); hud.Show(); hud.UpdateSubtitle("The last complete sentence must stay visible until the next caption is ready.", "Câu hoàn chỉnh gần nhất phải được giữ lại cho đến khi phụ đề tiếp theo sẵn sàng."); Pump(); Capture(hud, output, "subtitles.png"); hud.Hide();
            File.WriteAllLines(Path.Combine(output, "bindings.txt"), errors.Lines);
            if (errors.Lines.Count != 0) throw new Exception("WPF binding errors detected; see bindings.txt.");
            File.WriteAllText(Path.Combine(output, "result.txt"), "PASS: six routes, two window sizes, no WPF binding errors. Audio, model inference and Windows 10/11 interactive tests remain separate.");
            app.Shutdown(); return 0;
        } catch (Exception ex) { File.WriteAllText(Path.Combine(output, "failure.txt"), ex.ToString()); Console.Error.WriteLine(ex); return 1; }
    }
    private static void Capture(Window window, string output, string name)
    {
        window.UpdateLayout(); var root = (FrameworkElement)window.Content;
        var bitmap = new RenderTargetBitmap((int)Math.Ceiling(root.ActualWidth), (int)Math.Ceiling(root.ActualHeight), 96, 96, PixelFormats.Pbgra32); bitmap.Render(root);
        var png = new PngBitmapEncoder(); png.Frames.Add(BitmapFrame.Create(bitmap));
        using var file = File.Create(Path.Combine(output, name)); png.Save(file);
    }
    private static IEnumerable<DependencyObject> Descendants(DependencyObject root)
    {
        for (var i = 0; i < VisualTreeHelper.GetChildrenCount(root); i++) {
            var child = VisualTreeHelper.GetChild(root, i); yield return child;
            foreach (var descendant in Descendants(child)) yield return descendant;
        }
    }
    private static void Pump()
    {
        var frame = new DispatcherFrame();
        var timer = new DispatcherTimer(DispatcherPriority.Background) { Interval = TimeSpan.FromMilliseconds(250) };
        timer.Tick += (_, _) => { timer.Stop(); frame.Continue = false; }; timer.Start(); Dispatcher.PushFrame(frame);
    }
    private sealed class BindingErrors : TraceListener
    {
        public List<string> Lines { get; } = new();
        public override void Write(string? message) { if (!string.IsNullOrWhiteSpace(message)) Lines.Add(message); }
        public override void WriteLine(string? message) => Write(message);
    }
}
