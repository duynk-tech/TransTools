using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;
namespace TransTools.Views;
public partial class GardenBackground : UserControl
{
    public GardenBackground() { InitializeComponent(); SetPeriod("auto"); }
    public void SetPeriod(string mode)
    {
        var hour = mode switch { "morning" => 8, "noon" => 12, "afternoon" => 17, "night" => 22, _ => DateTime.Now.Hour };
        var (top, bottom) = hour switch {
            < 5 or >= 19 => ("#D4E0F2", "#DBEDEB"),
            < 11 => ("#F0FAED", "#D9F0E3"),
            < 15 => ("#E0F7FA", "#E0F5E3"),
            _ => ("#FCEDD9", "#E6F0E0")
        };
        SkyTop.Color = (Color)ColorConverter.ConvertFromString(top);
        SkyBottom.Color = (Color)ColorConverter.ConvertFromString(bottom);
        Scenery.SetHour(hour);
        Scenery.Visibility = mode == "mint" ? Visibility.Collapsed : Visibility.Visible;
        if (mode == "mint") { SkyTop.Color = (Color)ColorConverter.ConvertFromString("#E0F5EF"); SkyBottom.Color = (Color)ColorConverter.ConvertFromString("#D0EADF"); }
    }
}

// The macOS garden uses proportional landscape coordinates and undistorted details.
// A frozen drawing is rebuilt only for a size or period change; there is no animation timer.
public sealed class GardenScene : FrameworkElement
{
    private int _hour;
    private DrawingGroup? _drawing;
    public GardenScene() { SizeChanged += (_, _) => { _drawing = null; InvalidateVisual(); }; }
    public void SetHour(int hour) { if (_hour == hour) return; _hour = hour; _drawing = null; InvalidateVisual(); }
    protected override void OnRender(DrawingContext dc)
    {
        base.OnRender(dc);
        if (ActualWidth <= 0 || ActualHeight <= 0) return;
        if (_drawing == null) { _drawing = Build(ActualWidth, ActualHeight); _drawing.Freeze(); }
        dc.DrawDrawing(_drawing);
    }
    private static SolidColorBrush Brush(string color, double opacity = 1)
    {
        var brush = new SolidColorBrush((Color)ColorConverter.ConvertFromString(color)) { Opacity = opacity };
        brush.Freeze(); return brush;
    }
    private static Pen Line(string color, double width, double opacity = 1) => new(Brush(color, opacity), width) { StartLineCap = PenLineCap.Round, EndLineCap = PenLineCap.Round, LineJoin = PenLineJoin.Round };
    private DrawingGroup Build(double w, double h)
    {
        var drawing = new DrawingGroup();
        using var dc = drawing.Open();
        var scale = Math.Min(w / 1000, h / 500);
        var night = _hour < 5 || _hour >= 19;
        var morning = _hour >= 5 && _hour < 11;
        var afternoon = _hour >= 15 && _hour < 19;
        void Path(string data, Brush fill, double sx, double sy, double x = 0, double y = 0, Pen? stroke = null)
        {
            var geometry = Geometry.Parse(data).Clone();
            geometry.Transform = new MatrixTransform(sx, 0, 0, sy, x, y);
            dc.DrawGeometry(fill, stroke, geometry);
        }
        void Cloud(double x, double y, double width) => Path("M.08,.30 C-.03,.26 .01,.14 .18,.15 C.17,-.01 .40,-.04 .48,.07 C.56,0 .70,.03 .72,.13 C.82,.09 .95,.13 .92,.22 C1.03,.25 .98,.32 .89,.31 C.66,.35 .30,.34 .08,.30 Z", new LinearGradientBrush(Colors.White, Color.FromRgb(232,242,245), 90) { Opacity = .75 }, width, width, x, y);
        var cx = w * (morning ? .18 : .84);
        var cy = h * (afternoon ? .40 : .33);
        var radius = (_hour >= 11 && _hour < 15 ? 29 : 25) * scale;
        if (night)
        {
            dc.DrawEllipse(Brush("#FFFFFF", .12), null, new(cx, cy), radius * 1.6, radius * 1.6);
            Path("M.35,-1 C-1.5,-1 -1.5,1 .35,1 C-.5,.6 -.5,-.6 .35,-1 Z", Brush("#FFFADF"), radius, radius, cx, cy);
            for (var i = 0; i < 15; i++) dc.DrawEllipse(Brush("#FFFFFF", .85), null, new(w * (.07 + (i * 7 % 19) * .047), h * (.06 + (i * 11 % 7) * .045)), (i % 3 + 1) * scale / 2, (i % 3 + 1) * scale / 2);
        }
        else
        {
            var sunlight = afternoon ? "#F5AB61" : "#FAD16E";
            dc.DrawEllipse(Brush("#FFFF00", .10), null, new(cx, cy), radius * 1.65, radius * 1.65);
            dc.DrawEllipse(Brush(sunlight, .70), null, new(cx, cy), radius, radius);
            for (var i = 0; i < 12; i++)
            {
                var angle = i * Math.PI / 6; var dx = Math.Cos(angle); var dy = Math.Sin(angle);
                dc.DrawLine(Line(sunlight, Math.Max(1, 2 * scale), .85), new(cx + dx * radius * 1.28, cy + dy * radius * 1.28), new(cx + dx * radius * 1.72, cy + dy * radius * 1.72));
            }
        }
        Cloud(w * (morning ? .33 : .1), h * .30, 110 * scale);
        Cloud(w * .71, h * .41, 90 * scale);
        foreach (var (u,v,span) in new[] { (.54,.24,15.0), (.60,.20,11.0), (.66,.27,13.0) })
            Path("M-1,-.22 Q-.40,-.60 0,0 Q.35,-.65 1,-.32", Brushes.Transparent, span * scale, span * scale, w*u, h*v, Line("#4A757D", Math.Max(1,1.7*scale), night ? .30 : .55));
        dc.DrawEllipse(Brush("#91C4A8", .18), null, new(w * .125, h * 1.01), w * .325, h * .20);
        dc.DrawEllipse(Brush("#78B59C", .16), null, new(w * .95, h * 1.005), w * .25, h * .175);
        Path("M0,.83 C.05,.82 .10,.67 .18,.70 C.25,.73 .26,.61 .32,.63 C.38,.60 .41,.76 .48,.76 C.55,.77 .57,.67 .65,.68 C.73,.73 .75,.61 .83,.65 C.90,.63 .93,.79 1,.81 L1,.91 L0,.91 Z", new LinearGradientBrush(Color.FromArgb(77,166,199,204), Color.FromArgb(41,171,209,191),90), w,h);
        Path("M0,.86 C.11,.83 .15,.73 .30,.77 C.39,.78 .47,.86 .58,.85 C.77,.85 .85,.72 1,.80 L1,1 L0,1 Z", Brush("#96C4AB", .22), w,h);
        Path("M.60,.79 C.58,.82 .46,.82 .49,.86 C.51,.90 .66,.90 .65,.94 L.70,.96 C.75,.89 .56,.90 .52,.85 C.49,.82 .60,.82 .61,.79 Z", new LinearGradientBrush(Color.FromRgb(224,247,250),Color.FromArgb(217,176,219,240),90),w,h,stroke:Line("#FFFFFF", Math.Max(1,scale), .35));
        Tree(dc,w*.09,h*.88,125*scale);
        Tree(dc,w*.91,h*.88,100*scale);
        Tree(dc,w*.96,h*.89,65*scale);
        return drawing;
    }
    private static void Tree(DrawingContext dc, double x, double bottom, double height)
    {
        Point P(double u,double v) => new(x+u*height,bottom-v*height);
        (double u,double v)[] outline = [(-.10,.97),(-.06,1.02),(.02,1),(.07,.96),(.14,.97),(.18,.92),(.23,.91),(.25,.85),(.31,.84),(.33,.78),(.38,.75),(.36,.69),(.41,.64),(.38,.59),(.39,.53),(.33,.49),(.30,.44),(.23,.43),(.17,.40),(.10,.43),(.02,.40),(-.04,.43),(-.12,.41),(-.18,.45),(-.26,.44),(-.31,.49),(-.38,.51),(-.37,.58),(-.42,.62),(-.39,.68),(-.40,.73),(-.34,.76),(-.33,.83),(-.27,.85),(-.24,.91),(-.18,.91),(-.15,.97)];
        var canopy = new StreamGeometry();
        using (var g=canopy.Open())
        {
            var first=outline[0]; var last=outline[^1];
            g.BeginFigure(P((first.u+last.u)/2,(first.v+last.v)/2),true,true);
            for(var i=0;i<outline.Length;i++) { var a=outline[i];var b=outline[(i+1)%outline.Length];g.QuadraticBezierTo(P(a.u,a.v),P((a.u+b.u)/2,(a.v+b.v)/2),true,false); }
        }
        dc.DrawGeometry(new LinearGradientBrush(Color.FromRgb(153,201,156),Color.FromRgb(84,158,122),90),null,canopy);
        var trunk=new StreamGeometry();
        using(var g=trunk.Open()) {g.BeginFigure(P(-.045,0),true,true);g.LineTo(P(-.025,.52),true,false);g.QuadraticBezierTo(P(-.04,.65),P(.015,.73),true,false);g.LineTo(P(.025,.48),true,false);g.LineTo(P(.045,0),true,false);}
        dc.DrawGeometry(Brush("#7A8561",.65),null,trunk);
        var branches=new StreamGeometry();
        using(var g=branches.Open()) {g.BeginFigure(P(0,.39),false,false);g.QuadraticBezierTo(P(-.09,.53),P(-.21,.65),true,false);g.BeginFigure(P(0,.48),false,false);g.QuadraticBezierTo(P(.12,.56),P(.22,.72),true,false);}
        dc.DrawGeometry(null,Line("#7A8561",height*.018,.65),branches);
        for(var i=0;i<22;i++)
        {
            var u=(i*7%13-6)*.043;var v=.55+(i*11%9)*.043;
            var leaf=new StreamGeometry();
            using(var g=leaf.Open()) {g.BeginFigure(P(u-.025,v),true,true);g.QuadraticBezierTo(P(u-.015,v+.055),P(u+.035,v+.025),true,false);g.QuadraticBezierTo(P(u+.02,v-.018),P(u-.025,v),true,false);}
            dc.DrawGeometry(Brush("#FFFFFF",.12),null,leaf);
        }
    }
}
