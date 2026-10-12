using System.Globalization;
using System.Windows;
using System.Windows.Media;
using TransTools.Services.Conversation;
namespace TransTools.Views;
// Topic details are static and drawn only when layout or the selected topic changes.
public sealed class ConversationScenery : FrameworkElement
{
    public static readonly DependencyProperty TopicProperty = DependencyProperty.Register(nameof(Topic), typeof(string), typeof(ConversationScenery), new FrameworkPropertyMetadata("", FrameworkPropertyMetadataOptions.AffectsRender));
    public string Topic { get => (string)GetValue(TopicProperty); set => SetValue(TopicProperty, value); }
    public ConversationScenery() { IsHitTestVisible = false; Focusable = false; }
    protected override void OnRender(DrawingContext dc)
    {
        base.OnRender(dc);
        var icons = ConversationTopics.Normalize(Topic) switch {
            "Công việc & Cuộc họp" or "Phỏng vấn" => new[] { "\uE80F", "leaf", "sun" },
            "Du lịch & Khám phá" => new[] { "\uE709", "\uE707", "bird" },
            "Công nghệ & Lập trình" => new[] { "\uE7F4", "\uE968", "\uE80F", "leaf" },
            "Học tập" => new[] { "\uE736", "\uE70F", "bird", "leaf" },
            "Chủ đề riêng" => new[] { "leaf", "bird", "cat", "sun" },
            _ => new[] { "cat", "leaf", "bird" }
        };
        var brush = new SolidColorBrush(Color.FromArgb(46, 40, 117, 104)); brush.Freeze();
        double[] x = [.08, .91, .88, .14], y = [.76, .57, .87, .25];
        for (var i = 0; i < icons.Length; i++) {
            if (icons[i].Length > 1) {
                var size = i == 2 ? 38 : 28;
                dc.PushTransform(new TranslateTransform(ActualWidth * x[i] - size / 2, ActualHeight * y[i] - size / 2));
                dc.PushTransform(new ScaleTransform(size / 32.0, size / 32.0));
                DrawNature(dc, icons[i], brush);
                dc.Pop(); dc.Pop(); continue;
            }
            var text = new FormattedText(icons[i], CultureInfo.InvariantCulture, FlowDirection.LeftToRight, new Typeface("Segoe MDL2 Assets"), i == 2 ? 38 : 28, brush, VisualTreeHelper.GetDpi(this).PixelsPerDip);
            dc.DrawText(text, new Point(ActualWidth * x[i] - text.Width / 2, ActualHeight * y[i] - text.Height / 2));
        }
        var flower = new SolidColorBrush(Color.FromArgb(71, 196, 122, 150)); flower.Freeze();
        for (var i = 0; i < 6; i++) {
            var px = ActualWidth * (i < 3 ? .04 + i * .025 : .91 + (i - 3) * .025);
            var py = ActualHeight * .93;
            for (var petal = 0; petal < 5; petal++) { var angle = petal * Math.PI * 2 / 5; dc.DrawEllipse(flower, null, new Point(px + Math.Cos(angle) * 4, py + Math.Sin(angle) * 4), 3, 3); }
            dc.DrawEllipse(brush, null, new Point(px, py), 2, 2);
        }
    }
    private static void DrawNature(DrawingContext dc, string kind, Brush brush)
    {
        var pen = new Pen(brush, 2) { StartLineCap = PenLineCap.Round, EndLineCap = PenLineCap.Round };
        switch (kind) {
            case "leaf":
                dc.DrawGeometry(brush, null, Geometry.Parse("M3,28 C1,8 16,2 29,3 C28,19 20,30 3,28 Z"));
                dc.DrawLine(new Pen(Brushes.White, 1), new Point(5,26), new Point(24,8)); break;
            case "bird":
                dc.DrawGeometry(null, pen, Geometry.Parse("M2,13 Q10,5 16,17 Q22,5 30,13")); break;
            case "cat":
                dc.DrawGeometry(brush, null, Geometry.Parse("M5,8 L4,1 L12,6 Q16,4 20,6 L28,1 L27,10 Q32,24 22,28 Q14,32 7,25 Q1,17 5,8 Z"));
                dc.DrawEllipse(Brushes.White, null, new Point(11,15), 1.5, 1.5); dc.DrawEllipse(Brushes.White, null, new Point(22,15), 1.5, 1.5); break;
            case "sun":
                dc.DrawEllipse(brush, null, new Point(16,16), 7, 7);
                for (var i = 0; i < 8; i++) { var angle = i * Math.PI / 4; dc.DrawLine(pen, new Point(16 + Math.Cos(angle)*11,16 + Math.Sin(angle)*11), new Point(16 + Math.Cos(angle)*15,16 + Math.Sin(angle)*15)); } break;
        }
    }

}
