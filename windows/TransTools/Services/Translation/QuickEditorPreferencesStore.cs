using System.IO;
using System.Text.Json;
namespace TransTools.Services.Translation;
public sealed class QuickEditorPreferencesStore
{
    private readonly string _path;
    public QuickEditorPreferencesStore(string? path = null) => _path = path ?? Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData), "TransTools", "quick-editor-preferences.json");
    public int Load()
    {
        try { return File.Exists(_path) ? Math.Clamp(JsonSerializer.Deserialize<int>(File.ReadAllText(_path)), 12, 22) : 15; }
        catch (Exception e) when (e is IOException or JsonException or UnauthorizedAccessException) { return 15; }
    }
    public void Save(int fontSize)
    {
        Directory.CreateDirectory(Path.GetDirectoryName(_path)!);
        var temporary = _path + "." + Guid.NewGuid().ToString("N") + ".tmp";
        try { File.WriteAllText(temporary, JsonSerializer.Serialize(Math.Clamp(fontSize, 12, 22))); File.Move(temporary, _path, true); }
        finally { if (File.Exists(temporary)) File.Delete(temporary); }
    }
}
