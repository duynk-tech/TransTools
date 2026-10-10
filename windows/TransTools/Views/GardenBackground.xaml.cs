using System.Windows.Controls;
using System.Windows.Media;
namespace TransTools.Views;
public partial class GardenBackground : UserControl
{
    public GardenBackground()
    {
        InitializeComponent();
        var hour = DateTime.Now.Hour;
        var (top, bottom) = hour switch {
            < 6 or >= 19 => ("#D4E0F2", "#DBEDEB"),
            < 11 => ("#F0FAED", "#D9F0E3"),
            < 15 => ("#E0F7FA", "#E0F5E3"),
            _ => ("#FCEDD9", "#E6F0E0")
        };
        SkyTop.Color = (Color)ColorConverter.ConvertFromString(top);
        SkyBottom.Color = (Color)ColorConverter.ConvertFromString(bottom);
        Sun.Opacity = hour < 6 || hour >= 19 ? 0.2 : 0.7;
    }
}
