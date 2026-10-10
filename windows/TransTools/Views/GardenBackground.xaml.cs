using System.Windows.Controls;
using System.Windows.Media;
namespace TransTools.Views;
public partial class GardenBackground : UserControl
{
    public GardenBackground()
    {
        InitializeComponent();
        SetPeriod("auto");
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
