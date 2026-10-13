using System.Runtime.InteropServices;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Interop;
using System.Windows.Media;
using System.Windows.Shapes;
namespace TransTools.Views;
public sealed class RegionSelectionWindow : Window
{
    private readonly Canvas _canvas = new();
    private readonly Border _selection = new() { BorderBrush = new SolidColorBrush(Color.FromRgb(70, 174, 149)), BorderThickness = new Thickness(2), Background = new SolidColorBrush(Color.FromArgb(25, 255, 255, 255)) };
    private Point _start, _screenStart;
    private bool _selecting;
    public System.Drawing.Rectangle? Selection { get; private set; }
    public RegionSelectionWindow() {
        Title = "Chọn vùng chụp"; WindowStyle = WindowStyle.None; ResizeMode = ResizeMode.NoResize; Topmost = true; ShowInTaskbar = false; Background = new SolidColorBrush(Color.FromArgb(50, 0, 0, 0)); AllowsTransparency = true;
        Cursor = Cursors.Cross; Content = _canvas; _canvas.Children.Add(_selection);
        _canvas.Children.Add(new TextBlock { Text = "Kéo chọn vùng chữ · Esc để hủy", FontSize = 20, Foreground = Brushes.White, Margin = new Thickness(24) });
        SourceInitialized += (_, _) => { GetCursorPos(out var point); var monitor = MonitorFromPoint(point, 2); var info = new MonitorInfo { Size = Marshal.SizeOf<MonitorInfo>() }; if (GetMonitorInfo(monitor, ref info)) SetWindowPos(new WindowInteropHelper(this).Handle, new IntPtr(-1), info.Monitor.Left, info.Monitor.Top, info.Monitor.Right - info.Monitor.Left, info.Monitor.Bottom - info.Monitor.Top, 0x0040); };
        MouseLeftButtonDown += (_, e) => { _start = e.GetPosition(_canvas); _screenStart = PointToScreen(_start); _selecting = true; CaptureMouse(); };
        MouseMove += (_, e) => { if (!_selecting) return; var point = e.GetPosition(_canvas); Canvas.SetLeft(_selection, Math.Min(_start.X, point.X)); Canvas.SetTop(_selection, Math.Min(_start.Y, point.Y)); _selection.Width = Math.Abs(point.X - _start.X); _selection.Height = Math.Abs(point.Y - _start.Y); };
        MouseLeftButtonUp += (_, e) => { if (!_selecting) return; _selecting = false; ReleaseMouseCapture(); var end = PointToScreen(e.GetPosition(_canvas)); var rectangle = System.Drawing.Rectangle.FromLTRB((int)Math.Floor(Math.Min(_screenStart.X, end.X)), (int)Math.Floor(Math.Min(_screenStart.Y, end.Y)), (int)Math.Ceiling(Math.Max(_screenStart.X, end.X)), (int)Math.Ceiling(Math.Max(_screenStart.Y, end.Y))); if (rectangle.Width >= 4 && rectangle.Height >= 4) { Selection = rectangle; DialogResult = true; } else DialogResult = false; };
        KeyDown += (_, e) => { if (e.Key == Key.Escape) DialogResult = false; };
    }
    [StructLayout(LayoutKind.Sequential)] private struct NativePoint { public int X, Y; }
    [StructLayout(LayoutKind.Sequential)] private struct NativeRect { public int Left, Top, Right, Bottom; }
    [StructLayout(LayoutKind.Sequential)] private struct MonitorInfo { public int Size; public NativeRect Monitor, Work; public uint Flags; }
    [DllImport("user32.dll")] private static extern bool GetCursorPos(out NativePoint point);
    [DllImport("user32.dll")] private static extern IntPtr MonitorFromPoint(NativePoint point, uint flags);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] private static extern bool GetMonitorInfo(IntPtr monitor, ref MonitorInfo info);
    [DllImport("user32.dll")] private static extern bool SetWindowPos(IntPtr window, IntPtr order, int x, int y, int width, int height, uint flags);
}
