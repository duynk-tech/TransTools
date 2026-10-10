using System.IO;
using System.Text.Json;
using TransTools.Services.Speech;
namespace TransTools.Services.Reading;
public sealed record ReadingPreference(double SentencePause = .35, double ParagraphPause = .8, bool Normalize = true);
public sealed class ReadingPreferencesStore
{
    private readonly string _path;
    public ReadingPreferencesStore(string? path = null) => _path = path ?? Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData), "TransTools", "reading-preferences.json");
    public ReadingPreference Load()
    {
        try { return File.Exists(_path) ? Bounded(JsonSerializer.Deserialize<ReadingPreference>(File.ReadAllText(_path)) ?? new()) : new(); }
        catch (Exception e) when (e is IOException or JsonException or UnauthorizedAccessException) { return new(); }
    }
    private static ReadingPreference Bounded(ReadingPreference value) => value with { SentencePause = SpeechReadingPlan.Bound(value.SentencePause, 2, .35), ParagraphPause = SpeechReadingPlan.Bound(value.ParagraphPause, 4, .8) };
    public void Save(ReadingPreference value)
    {
        Directory.CreateDirectory(Path.GetDirectoryName(_path)!);
        var temporary = _path + "." + Guid.NewGuid().ToString("N") + ".tmp";
        try { File.WriteAllText(temporary, JsonSerializer.Serialize(Bounded(value))); File.Move(temporary, _path, true); }
        finally { if (File.Exists(temporary)) File.Delete(temporary); }
    }
}
