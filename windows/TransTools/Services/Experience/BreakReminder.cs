using System.Diagnostics;
using System.IO;
using System.Text.Json;
using System.Windows.Threading;
namespace TransTools.Services.Experience;

public sealed class BreakReminder : IDisposable
{
    public static BreakReminder Shared { get; } = new();
    private readonly DispatcherTimer _timer = new() { Interval = TimeSpan.FromSeconds(30) };
    private readonly Stopwatch _elapsed = new();
    private long _lastTick;
    private readonly string _path = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData), "TransTools", "experience.json");
    public bool Enabled { get; private set; }
    public int Minutes { get; private set; } = 45;
    public event Action? Due;
    private BreakReminder() {
        try { if (File.Exists(_path)) { var settings = JsonSerializer.Deserialize<Options>(File.ReadAllText(_path)); if (settings != null) { Enabled = settings.Enabled; Minutes = Math.Clamp(settings.Minutes, 15, 120); } } }
        catch (Exception ex) when (ex is IOException or JsonException or UnauthorizedAccessException) { }
        _timer.Tick += Tick;
        if (Enabled) Start();
    }
    public void Configure(bool enabled, int minutes) {
        minutes = Math.Clamp(minutes, 15, 120);
        Directory.CreateDirectory(Path.GetDirectoryName(_path)!);
        File.WriteAllText(_path + ".tmp", JsonSerializer.Serialize(new Options(enabled, minutes))); File.Move(_path + ".tmp", _path, true);
        Enabled = enabled; Minutes = minutes; _timer.Stop(); _elapsed.Reset();
        if (Enabled) Start();
    }
    private void Start() { _lastTick = Environment.TickCount64; _elapsed.Restart(); _timer.Start(); }
    private void Tick(object? sender, EventArgs e) {
        var now = Environment.TickCount64;
        // Resume after sleep/long dispatcher suspension with a fresh interval, not a burst of overdue reminders.
        if (now - _lastTick > 120000) _elapsed.Restart();
        _lastTick = now;
        if (_elapsed.Elapsed.TotalMinutes >= Minutes) { _elapsed.Restart(); Due?.Invoke(); }
    }
    public void Snooze() => _elapsed.Restart();
    public void Dispose() { _timer.Stop(); _timer.Tick -= Tick; _elapsed.Stop(); }
    private sealed record Options(bool Enabled, int Minutes);
}
