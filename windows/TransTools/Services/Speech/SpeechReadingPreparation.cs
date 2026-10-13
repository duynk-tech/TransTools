using System.IO;
using System.Text;
using System.Text.Json;
using System.Text.RegularExpressions;
namespace TransTools.Services.Speech;

public static class SpeechReadingPreparation
{
    public sealed record Token(int Id, string Text, int Start, int Length);
    public sealed record Reading(int Id, string Spoken);
    private static readonly Regex Candidates = new(@"(?<![\p{L}\p{N}])(?:\d{1,4}[/-]\d{1,2}[/-]\d{1,4}|\d+(?:[.,]\d+)?\s*(?:%|GB|MB|KB|GHz|MHz|kg|km|cm|mm|mg|ml|°C|VND|USD)|\d+(?:[.,]\d+)?\s*[:/]\s*\d+(?:[.,]\d+)?|(?:[A-Z]\.){2,}|[A-ZĐ]{2,}(?:/[A-Z]{2,})?|\d+(?:[.,]\d+)?|[IVXLCDM]+)(?![\p{L}\p{N}])", RegexOptions.CultureInvariant);
    public static Token[] Tokens(string source) => Candidates.Matches(source).Select((match, id) => new Token(id, match.Value, match.Index, match.Length)).ToArray();
    public static string Apply(string source, IReadOnlyList<Token> tokens, IEnumerable<Reading> readings)
    {
        var replacements = new List<(Token Token, string Spoken)>(); var seen = new HashSet<int>();
        foreach (var reading in readings) {
            var token = tokens.FirstOrDefault(value => value.Id == reading.Id);
            var spoken = reading.Spoken?.Trim() ?? "";
            if (!seen.Add(reading.Id) || token == null || spoken.Length is 0 or > 160 || spoken.Any(char.IsControl) || spoken.Contains('\u2028') || spoken.Contains('\u2029')) throw new InvalidDataException("Cách đọc AI không hợp lệ.");
            if (token.Start < 0 || token.Length <= 0 || token.Start + token.Length > source.Length || source.Substring(token.Start, token.Length) != token.Text) throw new InvalidDataException("Phạm vi chuẩn hóa không khớp văn bản.");
            replacements.Add((token, spoken));
        }
        var result = new StringBuilder(source);
        foreach (var (token, spoken) in replacements.OrderByDescending(value => value.Token.Start)) result.Remove(token.Start, token.Length).Insert(token.Start, spoken);
        return result.ToString();
    }
    public static string ParseAndApply(string source, Token[] tokens, string response)
    {
        if (response.Length > 65536) throw new InvalidDataException("Phản hồi chuẩn hóa quá dài.");
        response = response.Trim();
        if (response.StartsWith("```") && response.EndsWith("```")) response = response[(response.IndexOf('\n') + 1)..^3].Trim();
        using var document = JsonDocument.Parse(response);
        var readings = document.RootElement.GetProperty("readings").EnumerateArray().Select(value => new Reading(value.GetProperty("id").GetInt32(), value.GetProperty("spoken").GetString() ?? ""));
        return Apply(source, tokens, readings);
    }
}
