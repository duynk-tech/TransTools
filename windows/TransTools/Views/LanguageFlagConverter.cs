using System.Globalization;
using System.Windows;
using System.Windows.Data;
using System.Windows.Media;

namespace TransTools.Views;

// Frozen, shared vector flags keep language controls consistent across Windows fonts/DPI.
public sealed class LanguageFlagConverter : IValueConverter
{
    private static readonly Dictionary<string, DrawingImage> Images = new[] { "en", "vi", "ja", "zh", "ko", "auto" }.ToDictionary(code => code, Build);
    public object? Convert(object value, Type targetType, object parameter, CultureInfo culture)
    {
        var label = value?.ToString() ?? "";
        var code = label switch {
            "en" or "Tiếng Anh" or "Tiếng Anh (English)" => "en",
            "vi" or "Tiếng Việt" => "vi",
            "ja" or "Tiếng Nhật" or "Tiếng Nhật (日本語)" => "ja",
            "zh" or "Tiếng Trung" or "Tiếng Trung (中文)" => "zh",
            "ko" or "Tiếng Hàn" or "Tiếng Hàn (한국어)" => "ko",
            "auto" or "Tự động" or "Tất cả" => "auto", _ => ""
        };
        return Images.GetValueOrDefault(code);
    }
    public object ConvertBack(object value, Type targetType, object parameter, CultureInfo culture) => Binding.DoNothing;
    private static SolidColorBrush Color(string hex) => new((System.Windows.Media.Color)ColorConverter.ConvertFromString(hex));
    private static void Star(DrawingContext dc, Brush brush, double x, double y, double radius, double angle = -Math.PI / 2)
    {
        var geometry = new StreamGeometry();
        using (var path = geometry.Open()) {
            Point Vertex(int index) { var r = index % 2 == 0 ? radius : radius * .382; var a = angle + index * Math.PI / 5; return new(x + Math.Cos(a) * r, y + Math.Sin(a) * r); }
            path.BeginFigure(Vertex(0), true, true);
            for (var index = 1; index < 10; index++) path.LineTo(Vertex(index), true, false);
        }
        dc.DrawGeometry(brush, null, geometry);
    }
    private static DrawingImage Build(string code)
    {
        var group = new DrawingGroup { ClipGeometry = new RectangleGeometry(new Rect(0, 0, 30, 20), 2, 2) };
        using (var dc = group.Open()) {
            dc.DrawRectangle(code == "auto" ? Brushes.Transparent : Brushes.White, null, new Rect(0, 0, 30, 20));
            switch (code) {
                case "vi":
                    dc.DrawRectangle(Color("#DA251D"), null, new Rect(0, 0, 30, 20)); Star(dc, Color("#FFFF00"), 15, 10, 6); break;
                case "en":
                    for (var row = 0; row < 13; row += 2) dc.DrawRectangle(Color("#B22234"), null, new Rect(0, row * 20.0 / 13, 30, 20.0 / 13));
                    dc.DrawRectangle(Color("#3C3B6E"), null, new Rect(0, 0, 12, 140.0 / 13));
                    for (var row = 0; row < 9; row++) for (var col = 0; col < (row % 2 == 0 ? 6 : 5); col++) Star(dc, Brushes.White, 1 + col * 2 + (row % 2), .7 + row * 1.16, .43);
                    break;
                case "ja": dc.DrawEllipse(Color("#BC002D"), null, new Point(15, 10), 6, 6); break;
                case "zh":
                    dc.DrawRectangle(Color("#DE2910"), null, new Rect(0, 0, 30, 20)); Star(dc, Color("#FFDE00"), 5, 5, 3);
                    foreach (var point in new[] { new Point(10, 2), new Point(12, 4), new Point(12, 7), new Point(10, 9) }) Star(dc, Color("#FFDE00"), point.X, point.Y, 1, Math.Atan2(5 - point.Y, 5 - point.X));
                    break;
                case "ko":
                    dc.DrawEllipse(Color("#0047A0"), null, new Point(15, 10), 4, 4);
                    dc.DrawGeometry(Color("#CD2E3A"), null, Geometry.Parse("M11,10 C11,4.67 19,4.67 19,10 C19,12.67 15,12.67 15,10 C15,7.33 11,7.33 11,10 Z"));
                    void Trigram(double x, double y, double angle, bool[] broken) {
                        dc.PushTransform(new RotateTransform(angle, x, y));
                        for (var row = 0; row < 3; row++) {
                            var top = y - 2.5 + row * 2;
                            if (broken[row]) { dc.DrawRectangle(Brushes.Black, null, new Rect(x - 2.5, top, 1.9, 1)); dc.DrawRectangle(Brushes.Black, null, new Rect(x + .6, top, 1.9, 1)); }
                            else dc.DrawRectangle(Brushes.Black, null, new Rect(x - 2.5, top, 5, 1));
                        }
                        dc.Pop();
                    }
                    Trigram(6, 5, -45, [false, false, false]); Trigram(24, 15, -45, [true, true, true]);
                    Trigram(24, 5, 45, [true, false, true]); Trigram(6, 15, 45, [false, true, false]);
                    break;
                default:
                    var pen = new Pen(Color("#287568"), 1.3);
                    dc.DrawEllipse(null, pen, new Point(15, 10), 8, 8); dc.DrawEllipse(null, pen, new Point(15, 10), 3.5, 8);
                    dc.DrawLine(pen, new Point(7, 10), new Point(23, 10));
                    break;
            }
            if (code != "auto") dc.DrawRoundedRectangle(null, new Pen(Color("#AFC4BC"), .5), new Rect(.25, .25, 29.5, 19.5), 2, 2);
        }
        group.Freeze(); var image = new DrawingImage(group); image.Freeze(); return image;
    }
}
