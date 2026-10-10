using System.IO;
using System.Text;
using System.Text.Json;
namespace TransTools.Services.Conversation;
public sealed record ConversationPreferences(int DelaySeconds, string LearnerName);
public sealed class ConversationPreferencesStore(string? path = null)
{
    private readonly string _path = path ?? Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData), "TransTools", "conversation-preferences.json");
    public static ConversationPreferences Normalize(ConversationPreferences value) => new(Math.Clamp(value.DelaySeconds, 1, 30), string.Concat((value.LearnerName ?? "").EnumerateRunes().Where(r => !Rune.IsControl(r)).Take(60).Select(r => r.ToString())));
    public ConversationPreferences Load()
    {
        try { return File.Exists(_path) ? Normalize(JsonSerializer.Deserialize<ConversationPreferences>(File.ReadAllText(_path)) ?? throw new JsonException()) : Normalize(new(2, Environment.UserName)); }
        catch (Exception e) when (e is IOException or JsonException or UnauthorizedAccessException) { return Normalize(new(2, Environment.UserName)); }
    }
    public void Save(ConversationPreferences value)
    {
        Directory.CreateDirectory(Path.GetDirectoryName(_path)!);
        var temporary = _path + "." + Guid.NewGuid().ToString("N") + ".tmp";
        try { File.WriteAllText(temporary, JsonSerializer.Serialize(Normalize(value))); File.Move(temporary, _path, true); }
        finally { if (File.Exists(temporary)) File.Delete(temporary); }
    }
}
