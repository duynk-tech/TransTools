using System.Windows.Controls;
using System.Windows.Media;
namespace TransTools.Views;
public partial class GardenBackground : UserControl
{
    public GardenBackground()
    {
        InitializeComponent();
        AddLeafHighlights();
        SetPeriod("auto");
    }
    // Deterministic vector details are created once, with frozen brushes and no timer.
    private void AddLeafHighlights()
    {
        var random = new Random(47);
        var leafBrush = new SolidColorBrush(Color.FromRgb(170, 207, 167));
        leafBrush.Freeze();
        foreach (var offset in new[] { new System.Windows.Point(0, 0), new System.Windows.Point(985, 43) })
        {
            for (var i = 0; i < 38; i++)
            {
                var angle = random.NextDouble() * Math.PI * 2;
                var radius = Math.Sqrt(random.NextDouble());
                var x = 113 + Math.Cos(angle) * radius * 57;
                var y = 445 + Math.Sin(angle) * radius * 60;
                var leaf = new System.Windows.Shapes.Ellipse
                {
                    Width = 6 + random.NextDouble() * 5, Height = 4 + random.NextDouble() * 3,
                    Fill = leafBrush, Opacity = 0.22 + random.NextDouble() * 0.18,
                    RenderTransform = new RotateTransform(-25), IsHitTestVisible = false
                };
                Canvas.SetLeft(leaf, x + offset.X);
                Canvas.SetTop(leaf, y + offset.Y);
                LandscapeCanvas.Children.Add(leaf);
            }
        }
    }
    public void SetPeriod(string mode)
    {
        var hour = mode switch { "morning" => 8, "noon" => 12, "afternoon" => 17, "night" => 22, _ => DateTime.Now.Hour };
        var (top, bottom) = hour switch {
            < 6 or >= 19 => ("#D4E0F2", "#DBEDEB"),
            < 11 => ("#F0FAED", "#D9F0E3"),
            < 15 => ("#E0F7FA", "#E0F5E3"),
            _ => ("#FCEDD9", "#E6F0E0")
        };
        SkyTop.Color = (Color)ColorConverter.ConvertFromString(top);
        SkyBottom.Color = (Color)ColorConverter.ConvertFromString(bottom);
        Sun.Opacity = hour < 6 || hour >= 19 ? 0.2 : 0.7;
        Scenery.Visibility = mode == "mint" ? System.Windows.Visibility.Collapsed : System.Windows.Visibility.Visible;
        if (mode == "mint") { SkyTop.Color = (Color)ColorConverter.ConvertFromString("#E0F5EF"); SkyBottom.Color = (Color)ColorConverter.ConvertFromString("#D0EADF"); }
    }
}
