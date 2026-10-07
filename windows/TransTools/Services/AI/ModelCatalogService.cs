using System.Net.Http;
using System.IO;
using System.Text.Json;
namespace TransTools.Services.AI;
public sealed class ModelCatalogService
{
    private static readonly HttpClient Client = new() { Timeout = TimeSpan.FromSeconds(30) };
    public async Task<List<string>> FetchAsync(string provider, string key)
    {
        if (string.IsNullOrWhiteSpace(key)) throw new InvalidOperationException("Nhập API key trước khi tải model.");
        var url = provider switch {
            "gemini" => "https://generativelanguage.googleapis.com/v1beta/models?pageSize=1000",
            "claude" => "https://api.anthropic.com/v1/models?limit=1000",
            "deepseek" => "https://api.deepseek.com/models",
            _ => "https://api.openai.com/v1/models"
        };
        var models = new List<string>();
        var baseUrl = url;
        var seenPages = new HashSet<string>();
        for (var page = 0; page < 100; page++) {
        if (!seenPages.Add(url)) throw new InvalidDataException("Danh sách model có trang lặp.");
        using var request = new HttpRequestMessage(HttpMethod.Get, url);
        if (provider == "gemini") request.Headers.Add("x-goog-api-key", key);
        else if (provider == "claude") { request.Headers.Add("x-api-key", key); request.Headers.Add("anthropic-version", "2023-06-01"); }
        else request.Headers.Add("Authorization", "Bearer " + key);
        using var response = await Client.SendAsync(request); response.EnsureSuccessStatusCode();
        using var document = JsonDocument.Parse(await response.Content.ReadAsStringAsync());
        foreach (var item in document.RootElement.GetProperty(provider == "gemini" ? "models" : "data").EnumerateArray())
        {
            if (provider == "gemini") {
                if (!item.TryGetProperty("supportedGenerationMethods", out var methods) || !methods.EnumerateArray().Any(m => m.GetString() == "generateContent")) continue;
                models.Add(item.GetProperty("name").GetString()!.Replace("models/", ""));
            } else models.Add(item.GetProperty("id").GetString()!);
        }
        if (provider == "gemini" && document.RootElement.TryGetProperty("nextPageToken", out var next) && !string.IsNullOrEmpty(next.GetString())) {
            url = baseUrl + "&pageToken=" + Uri.EscapeDataString(next.GetString()!); continue;
        }
        if (provider == "claude" && document.RootElement.TryGetProperty("has_more", out var more) && more.GetBoolean()) {
            url = baseUrl + "&after_id=" + Uri.EscapeDataString(document.RootElement.GetProperty("last_id").GetString()!); continue;
        }
        return models.Distinct().Order().ToList();
        }
        throw new InvalidDataException("Danh sách model vượt giới hạn trang.");
    }
}
