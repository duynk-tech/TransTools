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
            foreach (var (width, height) in new[] { (1280, 820), (1100, 740), (1000, 600) }) {
                window.Width = width; window.Height = height;
                foreach (var route in new[] { "Cuộc họp", "Sổ tay", "Dịch nhanh", "Học ngôn ngữ", "Trò chuyện", "Cài đặt" }) {
                    var button = Descendants(window).OfType<RadioButton>().First(b => Equals(b.Content, route));
                    button.IsChecked = true; Pump(); window.UpdateLayout();
                    if (width == 1280) Capture(window, output, $"{width}-idle-{route}.png");
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
                    var filename = $"{width}-{Array.IndexOf(new[] { "Cuộc họp", "Sổ tay", "Dịch nhanh", "Học ngôn ngữ", "Trò chuyện", "Cài đặt" }, route)}.png";
                    ValidateControlLayout(window, route);
                    Capture(window, output, filename);
                    Console.WriteLine($"PASS: rendered {route} at {width}x{height}");
                    if (route == "Cài đặt") {
                        var sections = Descendants(window).OfType<TabControl>().First();
                        for (var i = 0; i < sections.Items.Count; i++) {
                            sections.SelectedIndex = i; Pump(); window.UpdateLayout();
                            Capture(window, output, $"{width}-settings-{i}.png");
                            Console.WriteLine($"PASS: settings section {i} at {width}x{height}");
                        }
                    }
                }
            }
            var chatModel = Descendants(window).OfType<ConversationView>().FirstOrDefault()?.DataContext as ConversationViewModel;
            // The cached conversation view may be hidden; create an isolated fixture instead.
            chatModel = new ConversationViewModel(() => false);
            chatModel.Messages.Add(new ChatMessageItem { Text = "A long reply should wrap and remain readable in the mini chat window. The user should be able to follow the conversation while the main window is closed.", Translation = "Câu trả lời dài cần xuống dòng và vẫn dễ đọc trong cửa sổ trò chuyện nhỏ." });
            var mini = new ConversationMiniWindow(chatModel); mini.Show(); Pump(); ValidateControlLayout(mini, "Mini chat"); Capture(mini, output, "mini-chat.png"); mini.CloseForExit(); chatModel.Dispose();
            var hud = new FloatingSubtitleWindow(); hud.Show(); hud.UpdateSubtitle("The last complete sentence must stay visible until the next caption is ready.", "Câu hoàn chỉnh gần nhất phải được giữ lại cho đến khi phụ đề tiếp theo sẵn sàng."); Pump(); ValidateControlLayout(hud, "Phụ đề nổi"); Capture(hud, output, "subtitles.png"); hud.Hide();
            File.WriteAllLines(Path.Combine(output, "bindings.txt"), errors.Lines);
            if (errors.Lines.Count != 0) throw new Exception("WPF binding errors detected; see bindings.txt.");
            File.WriteAllText(Path.Combine(output, "result.txt"), "PASS: six routes, three window sizes, no WPF binding errors. Audio, model inference and Windows 10/11 interactive tests remain separate.");
            app.Shutdown(); return 0;
        } catch (Exception ex) { File.WriteAllText(Path.Combine(output, "failure.txt"), ex.ToString()); Console.Error.WriteLine(ex); return 1; }
    }
    private static void ValidateControlLayout(Window window, string route)
    {
        var root = (FrameworkElement)window.Content;
        var viewport = new Rect(0, 0, root.ActualWidth, root.ActualHeight);
        var controls = Descendants(root).OfType<FrameworkElement>().Where(e => e.IsVisible && (e is Button || e is ComboBox || e is RadioButton)).Select(e => (Element: e, Bounds: VisibleBounds(e, root))).Where(e => e.Bounds.Width > 1 && e.Bounds.Height > 1 && viewport.IntersectsWith(e.Bounds)).ToArray();
        for (var i = 0; i < controls.Length; i++) for (var j = i + 1; j < controls.Length; j++) {
            var overlap = Rect.Intersect(controls[i].Bounds, controls[j].Bounds);
            if (!overlap.IsEmpty && overlap.Width > 2 && overlap.Height > 2)
                throw new Exception($"Overlapping controls in {route}: {controls[i].Element.Name} ({controls[i].Element.GetType().Name}) and {controls[j].Element.Name} ({controls[j].Element.GetType().Name}), {overlap}");
        }
        Console.WriteLine($"PASS: no button/dropdown overlap in {route}");
    }
    private static Rect VisibleBounds(FrameworkElement element, FrameworkElement root)
    {
        var bounds = element.TransformToAncestor(root).TransformBounds(new Rect(element.RenderSize));
        for (DependencyObject? ancestor = VisualTreeHelper.GetParent(element); ancestor != null && ancestor != root; ancestor = VisualTreeHelper.GetParent(ancestor))
            if (ancestor is FrameworkElement frame && (frame.ClipToBounds || frame is ScrollContentPresenter))
                bounds.Intersect(frame.TransformToAncestor(root).TransformBounds(new Rect(frame.RenderSize)));
        bounds.Intersect(new Rect(root.RenderSize));
        return bounds;
    }
    private static void Capture(Window window, string output, string name)
    {
        window.UpdateLayout(); var root = (FrameworkElement)window.Content;
        var bitmap = new RenderTargetBitmap((int)Math.Ceiling(root.ActualWidth), (int)Math.Ceiling(root.ActualHeight), 96, 96, PixelFormats.Pbgra32);
        // VisualBrush removes the content's layout offset; include the Window background.
        var drawing = new DrawingVisual();
        using (var context = drawing.RenderOpen()) {
            var bounds = new Rect(0, 0, root.ActualWidth, root.ActualHeight);
            context.DrawRectangle(window.Background, null, bounds);
            context.DrawRectangle(new VisualBrush(root) { Stretch = Stretch.Fill }, null, bounds);
        }
        bitmap.Render(drawing);
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
