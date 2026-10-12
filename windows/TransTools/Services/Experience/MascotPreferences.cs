using System.IO;
using System.Text.Json;
namespace TransTools.Services.Experience;
public sealed class MascotPreferences(string? path = null)
{
    private readonly string _path = path ?? Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData), "TransTools", "mascot-activity.json");
    private sealed record Preference(string Activity);
    public static string Normalize(string? activity) => activity is "auto" or "writing" or "thinking" or "sleeping" or "strolling" or "flowers" or "coffee" ? activity : "auto";
    public string Load() { try { return Normalize(JsonSerializer.Deserialize<Preference>(File.ReadAllText(_path))?.Activity); } catch { return "auto"; } }
    public void Save(string activity)
    {
        Directory.CreateDirectory(Path.GetDirectoryName(_path)!);
        var temporary = _path + "." + Guid.NewGuid().ToString("N") + ".tmp";
        try { File.WriteAllText(temporary, JsonSerializer.Serialize(new Preference(Normalize(activity)))); File.Move(temporary, _path, true); }
        finally { if (File.Exists(temporary)) File.Delete(temporary); }
    }
}
