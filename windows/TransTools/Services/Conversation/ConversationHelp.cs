using System.Text.Json;
using System.IO;
namespace TransTools.Services.Conversation;

public sealed record ConversationSuggestion(string Text, string Vietnamese);
public static class ConversationHelp
{
    public static IReadOnlyList<ConversationSuggestion> Parse(string raw)
    {
        if (raw.Length > 16384) throw new InvalidDataException("Gợi ý quá dài.");
        var begin = raw.IndexOf('{'); var end = raw.LastIndexOf('}');
        if (begin < 0 || end < begin) throw new InvalidDataException("Chưa nhận được gợi ý hợp lệ.");
        using var document = JsonDocument.Parse(raw[begin..(end + 1)], new JsonDocumentOptions { MaxDepth = 8 });
        var results = new List<ConversationSuggestion>();
        foreach (var item in document.RootElement.GetProperty("suggestions").EnumerateArray().Take(3)) {
            var text = item.GetProperty("text").GetString()?.Trim() ?? "";
            var meaning = item.GetProperty("vietnamese").GetString()?.Trim() ?? "";
            if (text.Length == 0 || text.Length > 600 || meaning.Length > 800) throw new InvalidDataException("Gợi ý không phù hợp.");
            if (!results.Any(value => value.Text == text)) results.Add(new(text, meaning));
        }
        return results;
    }
}
