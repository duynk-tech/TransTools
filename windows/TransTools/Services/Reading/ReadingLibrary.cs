using System.IO;
using System.Net;
using System.Net.Http;
using System.Text;
using System.Text.Json;
using System.Text.RegularExpressions;
namespace TransTools.Services.Reading;
public sealed record ReadingStory(string Id, string Title, string Language, string Source, Uri Page, Uri TextUrl, bool Wiki)
{
    public string Description => (Language == "vi" ? "Tiếng Việt" : "Tiếng Anh") + " · " + Source;
}
public sealed record ReadingPart(int Number, int Count, string Text)
{
    public string Label => $"Phần {Number} / {Count}";
}
public sealed class ReadingLibrary
{
    private readonly HttpClient _client;
    public ReadingLibrary(HttpClient? client = null) => _client = client ?? SharedClient;
    private static readonly HttpClient SharedClient = new();
    public static IReadOnlyList<ReadingStory> Catalog { get; } = new[] {
        new ReadingStory("tam-cam", "Tấm Cám", "vi", "Wikisource", new("https://vi.wikisource.org/wiki/T%E1%BA%A5m_C%C3%A1m"), new("https://vi.wikisource.org/w/api.php?action=parse&page=T%E1%BA%A5m_C%C3%A1m&prop=text&format=json"), true),
        Gutenberg("grimm", "Grimms’ Fairy Tales", "2591"), Gutenberg("andersen", "Andersen’s Fairy Tales", "1597"), Gutenberg("aesop", "Aesop’s Fables", "11339")
    };
    private static ReadingStory Gutenberg(string id, string title, string book) => new(id, title, "en", "Project Gutenberg", new($"https://www.gutenberg.org/ebooks/{book}"), new($"https://www.gutenberg.org/ebooks/{book}.txt.utf-8"), false);
    private async Task<string> FetchAsync(Uri uri, int limit, CancellationToken token)
    {
        if (uri.Scheme != "https" || uri.Host is not ("vi.wikisource.org" or "en.wikisource.org" or "www.gutenberg.org")) throw new InvalidDataException("Nguồn truyện không được hỗ trợ.");
        using var deadline = CancellationTokenSource.CreateLinkedTokenSource(token); deadline.CancelAfter(TimeSpan.FromSeconds(25));
        using var request = new HttpRequestMessage(HttpMethod.Get, uri);
        request.Headers.UserAgent.ParseAdd("TransTools/1.4 (ReadingLibrary; https://github.com/duynk-tech/TransTools)");
        using var response = await _client.SendAsync(request, HttpCompletionOption.ResponseHeadersRead, deadline.Token);
        response.EnsureSuccessStatusCode();
        if (response.Content.Headers.ContentLength > limit) throw new InvalidDataException("Nội dung quá lớn để tải trong thư viện.");
        await using var stream = await response.Content.ReadAsStreamAsync(deadline.Token); using var output = new MemoryStream();
        var buffer = new byte[16384]; int read;
        while ((read = await stream.ReadAsync(buffer, deadline.Token)) > 0) {
            if (output.Length + read > limit) throw new InvalidDataException("Nội dung quá lớn để tải trong thư viện.");
            output.Write(buffer, 0, read);
        }
        return new UTF8Encoding(false, true).GetString(output.ToArray());
    }
    public async Task<IReadOnlyList<ReadingStory>> SearchAsync(string query, string language, CancellationToken token)
    {
        var result = new List<ReadingStory>();
        foreach (var code in language == "all" ? new[] { "vi", "en" } : new[] { language }) {
            if (code is not ("vi" or "en")) throw new ArgumentException("Ngôn ngữ không được hỗ trợ.");
            var host = code + ".wikisource.org";
            var uri = new Uri($"https://{host}/w/api.php?action=query&list=search&srsearch={Uri.EscapeDataString(query)}&srnamespace=0&srlimit=20&format=json");
            using var json = JsonDocument.Parse(await FetchAsync(uri, 2_000_000, token));
            if (!json.RootElement.TryGetProperty("query", out var root) || !root.TryGetProperty("search", out var rows)) throw new InvalidDataException("Chưa đọc được kết quả tìm kiếm.");
            foreach (var row in rows.EnumerateArray()) {
                var id = row.GetProperty("pageid").GetInt64(); var title = row.GetProperty("title").GetString();
                if (!string.IsNullOrWhiteSpace(title)) result.Add(new($"{host}-{id}", title, code, "Wikisource", new($"https://{host}/w/index.php?curid={id}"), new($"https://{host}/w/api.php?action=parse&pageid={id}&prop=text&format=json"), true));
            }
        }
        return result;
    }
    public async Task<IReadOnlyList<ReadingPart>> LoadAsync(ReadingStory story, CancellationToken token)
    {
        var content = await FetchAsync(story.TextUrl, 4_000_000, token);
        if (story.Wiki) {
            using var json = JsonDocument.Parse(content);
            content = ExtractParagraphs(json.RootElement.GetProperty("parse").GetProperty("text").GetProperty("*").GetString() ?? "");
        } else {
            var start = content.IndexOf("*** START OF", StringComparison.OrdinalIgnoreCase);
            if (start >= 0) { var end = content.IndexOf("***", start + 3, StringComparison.Ordinal); if (end >= 0) content = content[(end + 3)..]; }
            var endMarker = content.IndexOf("*** END OF", StringComparison.OrdinalIgnoreCase); if (endMarker >= 0) content = content[..endMarker];
        }
        return SplitParts(content);
    }
    public static string ExtractParagraphs(string html)
    {
        var paragraphs = Regex.Matches(html, @"<p(?:\s[^>]*)?>[\s\S]*?</p>", RegexOptions.IgnoreCase, TimeSpan.FromSeconds(2));
        return string.Join("\n\n", paragraphs.Select(match => {
            var value = Regex.Replace(match.Value, @"<(script|style)\b[^>]*>[\s\S]*?</\1>", "", RegexOptions.IgnoreCase, TimeSpan.FromSeconds(2));
            value = Regex.Replace(value, @"<br\s*/?>", "\n", RegexOptions.IgnoreCase, TimeSpan.FromSeconds(2));
            return WebUtility.HtmlDecode(Regex.Replace(value, "<[^>]*>", "", RegexOptions.None, TimeSpan.FromSeconds(2))).Trim();
        }).Where(value => !string.IsNullOrWhiteSpace(value)));
    }
    public static IReadOnlyList<ReadingPart> SplitParts(string content)
    {
        content = content.Trim(); if (content.Length == 0) throw new InvalidDataException("Nguồn này chưa có văn bản để đọc.");
        var pieces = new List<string>(); var offset = 0;
        while (offset < content.Length) {
            var length = Math.Min(4500, content.Length - offset);
            if (offset + length < content.Length) {
                var newline = content.LastIndexOf('\n', offset + length - 1, length);
                if (newline - offset > 2000) length = newline - offset + 1;
                else { var space = content.LastIndexOf(' ', offset + length - 1, length); if (space - offset > 2000) length = space - offset + 1; }
                if (char.IsHighSurrogate(content[offset + length - 1])) length--;
            }
            pieces.Add(content.Substring(offset, length)); offset += length;
        }
        return pieces.Select((text, i) => new ReadingPart(i + 1, pieces.Count, text)).ToArray();
    }
}
