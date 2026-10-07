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
            < 6 or >= 19 => ("#CEDDE2", "#E0EBE5"),
            < 11 => ("#DAEBEF", "#ECF5EE"),
            < 15 => ("#D8ECF4", "#EAF3EC"),
            _ => ("#EBDDD2", "#EAF0E4")
        };
        SkyTop.Color = (Color)ColorConverter.ConvertFromString(top);
        SkyBottom.Color = (Color)ColorConverter.ConvertFromString(bottom);
        Sun.Opacity = hour < 6 || hour >= 19 ? 0.2 : 0.7;
    }
}
