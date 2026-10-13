using System.Runtime.InteropServices;
using System.Windows;
using System.Windows.Automation;
using System.Windows.Interop;
namespace TransTools.Services;
public sealed class HotkeyService : IDisposable
{
    private readonly HwndSource _source;
    private readonly List<int> _registered = new();
    public event Action<int>? Pressed;
    public HotkeyService(Window window) { _source = HwndSource.FromHwnd(new WindowInteropHelper(window).Handle); _source.AddHook(Handle); }
    public bool Register(int id, uint key) { if (!RegisterHotKey(_source.Handle, id, 0x4000 | 0x0001 | 0x0002, key)) return false; _registered.Add(id); return true; }
    private IntPtr Handle(IntPtr hwnd, int message, IntPtr wParam, IntPtr lParam, ref bool handled) { if (message == 0x0312) { Pressed?.Invoke(wParam.ToInt32()); handled = true; } return IntPtr.Zero; }
    public static string SelectedText() {
        try {
            var focused = AutomationElement.FocusedElement;
            if (focused?.TryGetCurrentPattern(TextPattern.Pattern, out var pattern) == true) {
                var selection = ((TextPattern)pattern).GetSelection();
                return string.Join("\n", selection.Select(range => range.GetText(30000))).Trim();
            }
        } catch (ElementNotAvailableException) { } catch (InvalidOperationException) { }
        return "";
    }
    public void Dispose() { foreach (var id in _registered) UnregisterHotKey(_source.Handle, id); _source.RemoveHook(Handle); }
    [DllImport("user32.dll", SetLastError = true)] private static extern bool RegisterHotKey(IntPtr window, int id, uint modifiers, uint key);
    [DllImport("user32.dll")] private static extern bool UnregisterHotKey(IntPtr window, int id);
}
