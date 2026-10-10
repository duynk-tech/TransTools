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
            var background = (Button)window.FindName("BackgroundButton");
            foreach (var mode in new[] { "morning", "noon", "afternoon", "night", "mint" }) {
                var item = background.ContextMenu.Items.OfType<MenuItem>().First(value => Equals(value.Tag, mode));
                item.RaiseEvent(new RoutedEventArgs(MenuItem.ClickEvent)); Pump();
                if (!item.IsChecked) throw new Exception("Background selection did not update: " + mode);
                Capture(window, output, "background-" + mode + ".png");
            }
            background.ContextMenu.Items.OfType<MenuItem>().First(value => Equals(value.Tag, "noon")).RaiseEvent(new RoutedEventArgs(MenuItem.ClickEvent)); Pump();
            foreach (var (width, height) in new[] { (1280, 820), (1200, 740), (1440, 900) }) {
                window.Width = width; window.Height = height;
                foreach (var route in new[] { "Cuộc họp", "Sổ tay", "Dịch nhanh", "Đọc văn bản", "Học ngôn ngữ", "Trò chuyện", "Cài đặt" }) {
                    var button = Descendants(window).OfType<RadioButton>().First(b => Equals(b.Content, route));
                    button.IsChecked = true; Pump(); window.UpdateLayout();
                    if (width == 1280) Capture(window, output, $"{width}-idle-{route}.png");
                    var reader = Descendants(window).OfType<TextReaderView>().FirstOrDefault();
                    if (reader != null) {
                        var options = (Button)reader.FindName("ReadingOptionsButton");
                        var popup = (System.Windows.Controls.Primitives.Popup)reader.FindName("ReadingOptionsPopup");
                        if (popup.IsOpen) throw new InvalidOperationException("Reading options must be collapsed initially");
                        options.RaiseEvent(new RoutedEventArgs(Button.ClickEvent)); Pump();
                        if (!popup.IsOpen || popup.Child == null) throw new InvalidOperationException("Reading options did not open");
                        ValidateControlLayout((FrameworkElement)popup.Child, "Reading options");
                        CaptureElement((FrameworkElement)popup.Child, output, $"{width}-reader-options-popup.png");
                        Capture(window, output, $"{width}-reader-options.png");
                        popup.IsOpen = false;
                    }
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
                    var filename = $"{width}-{Array.IndexOf(new[] { "Cuộc họp", "Sổ tay", "Dịch nhanh", "Đọc văn bản", "Học ngôn ngữ", "Trò chuyện", "Cài đặt" }, route)}.png";
                    ValidateControlLayout(window, route);
                    Capture(window, output, filename);
                    Console.WriteLine($"PASS: rendered {route} at {width}x{height}");
                    if (route == "Sổ tay" && width == 1280) {
                        var copyMenu = Descendants(window).OfType<MenuItem>().First(item => Equals(item.Header, "Sao chép"));
                        copyMenu.IsSubmenuOpen = true; Pump();
                        var copy = (MenuItem)copyMenu.Items[2];
                        if (copy.DataContext is not Caption caption) throw new Exception("Caption copy menu lost its row context");
                        copy.RaiseEvent(new RoutedEventArgs(MenuItem.ClickEvent)); Pump();
                        if (!Clipboard.ContainsText() || !Clipboard.GetText().Contains(caption.Original) || !Clipboard.GetText().Contains(caption.Vietnamese)) throw new Exception("Bilingual copy did not preserve both texts");
                        copyMenu.IsSubmenuOpen = false;
                    }
                    if (route == "Học ngôn ngữ") {
                        var learning = Descendants(window).OfType<LearningView>().First();
                        foreach (var label in new[] { "Hôm nay", "Chữ & Viết", "Từ vựng của tôi", "Luyện giao tiếp" }) {
                            var section = Descendants(learning).OfType<RadioButton>().First(item => Equals(item.Content, label));
                            section.IsChecked = true; Pump(); window.UpdateLayout();
                            ValidateControlLayout(window, "Learning: " + label);
                            Capture(window, output, $"{width}-learning-{Array.IndexOf(new[] { "Hôm nay", "Chữ & Viết", "Từ vựng của tôi", "Luyện giao tiếp" }, label)}.png");
                        }
                        var goal = (Button)learning.FindName("LearningGoalButton");
                        goal.RaiseEvent(new RoutedEventArgs(Button.ClickEvent)); Pump();
                        var popup = (System.Windows.Controls.Primitives.Popup)learning.FindName("LearningGoalPopup");
                        if (!popup.IsOpen || popup.Child == null) throw new Exception("Learning goal popup did not open");
                        ValidateControlLayout((FrameworkElement)popup.Child, "Learning goal");
                        CaptureElement((FrameworkElement)popup.Child, output, $"{width}-learning-goal.png");
                        popup.IsOpen = false;
                        Descendants(learning).OfType<RadioButton>().First(item => Equals(item.Content, "Hôm nay")).IsChecked = true;
                    }
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
            File.WriteAllText(Path.Combine(output, "result.txt"), "PASS: seven routes, three window sizes, no WPF binding errors. Audio, model inference and Windows 10/11 interactive tests remain separate.");
            app.Shutdown(); return 0;
        } catch (Exception ex) { File.WriteAllText(Path.Combine(output, "failure.txt"), ex.ToString()); Console.Error.WriteLine(ex); return 1; }
    }
    private static void ValidateControlLayout(Window window, string route)
        => ValidateControlLayout((FrameworkElement)window.Content, route);
    private static void ValidateControlLayout(FrameworkElement root, string route)
    {
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
    private static void CaptureElement(FrameworkElement element, string output, string name)
    {
        element.UpdateLayout();
        var bitmap = new RenderTargetBitmap((int)Math.Ceiling(element.ActualWidth), (int)Math.Ceiling(element.ActualHeight), 96, 96, PixelFormats.Pbgra32);
        var drawing = new DrawingVisual();
        using (var context = drawing.RenderOpen()) context.DrawRectangle(new VisualBrush(element), null, new Rect(0, 0, element.ActualWidth, element.ActualHeight));
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
