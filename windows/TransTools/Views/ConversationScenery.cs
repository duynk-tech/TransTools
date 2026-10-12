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
            "Công việc & Cuộc họp" or "Phỏng vấn" => new[] { "\uE80F", "\uE8F1", "\uE706" },
            "Du lịch & Khám phá" => new[] { "\uE709", "\uE707", "\uE8F1" },
            "Công nghệ & Lập trình" => new[] { "\uE7F4", "\uE968", "\uE80F", "\uE8F1" },
            "Học tập" => new[] { "\uE736", "\uE70F", "\uE8F1", "\uE706" },
            _ => new[] { "\uE8F1", "\uE706", "\uE707" }
        };
        var brush = new SolidColorBrush(Color.FromArgb(46, 40, 117, 104)); brush.Freeze();
        double[] x = [.08, .91, .88, .14], y = [.76, .57, .87, .25];
        for (var i = 0; i < icons.Length; i++) {
            var text = new FormattedText(icons[i], CultureInfo.InvariantCulture, FlowDirection.LeftToRight, new Typeface("Segoe MDL2 Assets"), i == 2 ? 38 : 28, brush, VisualTreeHelper.GetDpi(this).PixelsPerDip);
            dc.DrawText(text, new Point(ActualWidth * x[i] - text.Width / 2, ActualHeight * y[i] - text.Height / 2));
        }
    }
}
