using System.IO;
using System.Text.Json;
namespace TransTools.Services.Experience;
public sealed class MascotPreferences(string? path = null)
{
    private readonly string _path = path ?? Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData), "TransTools", "mascot-activity.json");
    private sealed record Preference(string Activity, double? Left = null, double? Top = null);
    public (double Left, double Top)? LoadPosition() { try { var value = JsonSerializer.Deserialize<Preference>(File.ReadAllText(_path)); return value?.Left is double x && value.Top is double y && double.IsFinite(x) && double.IsFinite(y) ? (x, y) : null; } catch { return null; } }
    public void SavePosition(double left, double top) { if (double.IsFinite(left) && double.IsFinite(top)) Write(new Preference(Load(), left, top)); }
    public static string Normalize(string? activity) => activity is "auto" or "writing" or "thinking" or "sleeping" or "strolling" or "flowers" or "coffee" ? activity : "auto";
    public string Load() { try { return Normalize(JsonSerializer.Deserialize<Preference>(File.ReadAllText(_path))?.Activity); } catch { return "auto"; } }
    public void Save(string activity)
    {
        var position = LoadPosition(); Write(new Preference(Normalize(activity), position?.Left, position?.Top));
    }
    private void Write(Preference value)
    {
        Directory.CreateDirectory(Path.GetDirectoryName(_path)!);
        var temporary = _path + "." + Guid.NewGuid().ToString("N") + ".tmp";
        try { File.WriteAllText(temporary, JsonSerializer.Serialize(value)); File.Move(temporary, _path, true); }
        finally { if (File.Exists(temporary)) File.Delete(temporary); }
    }
}
