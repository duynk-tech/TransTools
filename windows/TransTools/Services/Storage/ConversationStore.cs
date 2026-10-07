using System.IO;
using System.Text.Json;
using TransTools.ViewModels;
namespace TransTools.Services.Storage;
public sealed class ConversationSession
{
    public Guid Id { get; set; } = Guid.NewGuid();
    public string Title { get; set; } = "Trò chuyện mới";
    public string Topic { get; set; } = "Giao tiếp hằng ngày";
    public string Language { get; set; } = "Tiếng Anh (English)";
    public string Prompt { get; set; } = "";
    public DateTime UpdatedAt { get; set; } = DateTime.Now;
    public List<ChatMessageItem> Messages { get; set; } = new();
}
public sealed class ConversationStore
{
    private readonly string _path = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData), "TransTools", "conversations.json");
    private static readonly SemaphoreSlim Gate = new(1);
    public List<ConversationSession> Load() => File.Exists(_path)
        ? JsonSerializer.Deserialize<List<ConversationSession>>(File.ReadAllText(_path)) ?? new() : new();
    public async Task SaveAsync(IEnumerable<ConversationSession> sessions)
    {
        var json = JsonSerializer.Serialize(sessions);
        await Gate.WaitAsync();
        try { Directory.CreateDirectory(Path.GetDirectoryName(_path)!); await File.WriteAllTextAsync(_path + ".tmp", json); File.Move(_path + ".tmp", _path, true); }
        finally { Gate.Release(); }
    }
}
