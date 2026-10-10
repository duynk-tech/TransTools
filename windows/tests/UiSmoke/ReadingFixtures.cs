using System.Net;
using System.Net.Http;
using System.Text;
using System.Text.Json;
using TransTools.Services.Reading;
internal sealed class ReadingFixtureHandler : HttpMessageHandler
{
    public bool Fail { get; set; }
    public bool Oversized { get; set; }
    public TaskCompletionSource<HttpResponseMessage>? Pending { get; set; }
    public static string Sample => string.Join("\n\n", Enumerable.Range(0, 100).Select(i => $"Đoạn {i}: Ngày xưa, những câu chuyện được kể bằng tiếng Việt. Cần giữ nguyên nội dung, dấu câu và cách viết để người đọc có thể nghe đầy đủ."));
    public static HttpResponseMessage SearchResponse() => Json(new { query = new { search = new[] { new { pageid = 123, title = "Truyện cổ tích" } } } });
    private static HttpResponseMessage Json(object value) => new(HttpStatusCode.OK) { Content = new StringContent(JsonSerializer.Serialize(value), Encoding.UTF8, "application/json") };
    protected override Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken token)
    {
        if (Pending != null) return Pending.Task;
        if (Fail) return Task.FromResult(new HttpResponseMessage(HttpStatusCode.BadGateway));
        if (Oversized) return Task.FromResult(new HttpResponseMessage(HttpStatusCode.OK) { Content = new ByteArrayContent(new byte[4_000_001]) });
        if (request.RequestUri!.Query.Contains("list=search")) return Task.FromResult(SearchResponse());
        if (request.RequestUri.Query.Contains("action=parse")) return Task.FromResult(Json(new { parse = new { text = new Dictionary<string,string> { ["*"] = "<p>" + Sample.Replace("\n\n", "</p><p>") + "</p>" } } }));
        return Task.FromResult(new HttpResponseMessage(HttpStatusCode.OK) { Content = new StringContent("Header\n*** START OF THE PROJECT GUTENBERG EBOOK ***\n" + Sample + "\n*** END OF THE PROJECT GUTENBERG EBOOK ***\nLicense", Encoding.UTF8) });
    }
}
