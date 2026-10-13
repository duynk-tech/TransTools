using System.IO;
using System.Net.Http;
using System.Text.Json;
namespace TransTools.Services.Models;
public sealed record CatalogEntry(string Id, string EngineID, string Version, string Name, string Summary, bool Recommended);
public sealed record CatalogFeed(int SchemaVersion, int Revision, CatalogEntry[] Models);
public sealed class RemoteModelCatalog
{
    public static readonly Uri Source = new("https://raw.githubusercontent.com/duynk-tech/TransTools/main/catalog/models-v1.json");
    private static readonly HttpClient Client = new(new HttpClientHandler { AllowAutoRedirect = false }) { Timeout = TimeSpan.FromSeconds(20) };
    private static readonly JsonSerializerOptions Json = new() { PropertyNameCaseInsensitive = true };
    private readonly string _path;
    public static CatalogFeed Defaults => new(1, 0, [new("supertonic-3", "supertonic", "3.0.0", "Supertonic 3", "Giọng đọc đa ngôn ngữ, chạy trên thiết bị.", true), new("vieneu-v3-turbo", "vieneu", "v3-turbo-native-1", "VieNeu-TTS v3 Turbo", "Tiếng Việt tự nhiên, hỗ trợ hồ sơ giọng từ mẫu.", true)]);
    public RemoteModelCatalog(string? path = null) => _path = path ?? Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData), "TransTools", "catalog-v1.json");
    public static CatalogFeed Parse(byte[] data)
    {
        if (data.Length > 256000) throw new InvalidDataException("Danh mục quá lớn.");
        var feed = JsonSerializer.Deserialize<CatalogFeed>(data, Json) ?? throw new InvalidDataException("Danh mục không hợp lệ.");
        if (feed.SchemaVersion != 1 || feed.Revision < 1 || feed.Models == null || feed.Models.Length > 100 || feed.Models.Select(e => e?.Id).Distinct().Count() != feed.Models.Length) throw new InvalidDataException("Danh mục không hợp lệ.");
        foreach (var entry in feed.Models) {
            var known = Defaults.Models.FirstOrDefault(e => e.Id == entry?.Id);
            if (entry == null || known == null || entry.EngineID != known.EngineID || entry.Version != known.Version || string.IsNullOrWhiteSpace(entry.Name) || entry.Name.Length > 100 || entry.Summary == null || entry.Summary.Length > 1000) throw new InvalidDataException("Mô hình chưa được ứng dụng hỗ trợ.");
        }
        return feed;
    }
    public CatalogFeed Load()
    {
        try { return File.Exists(_path) && new FileInfo(_path).Length <= 256000 ? Parse(File.ReadAllBytes(_path)) : Defaults; }
        catch (Exception e) when (e is IOException or JsonException or UnauthorizedAccessException) { return Defaults; }
    }
    public async Task<CatalogFeed> UpdateAsync(CancellationToken token = default)
    {
        using var response = await Client.GetAsync(Source, HttpCompletionOption.ResponseHeadersRead, token);
        response.EnsureSuccessStatusCode();
        if (response.Content.Headers.ContentLength > 256000) throw new InvalidDataException("Danh mục quá lớn.");
        await using var stream = await response.Content.ReadAsStreamAsync(token);
        using var bytes = new MemoryStream(); var buffer = new byte[8192]; int read;
        while ((read = await stream.ReadAsync(buffer, token)) > 0) { if (bytes.Length + read > 256000) throw new InvalidDataException("Danh mục quá lớn."); bytes.Write(buffer, 0, read); }
        var data = bytes.ToArray(); var feed = Parse(data);
        if (feed.Revision < Load().Revision) throw new InvalidDataException("Danh mục cũ hơn dữ liệu đã lưu.");
        Directory.CreateDirectory(Path.GetDirectoryName(_path)!); var temp = _path + "." + Guid.NewGuid().ToString("N") + ".tmp";
        try { await File.WriteAllBytesAsync(temp, data, token); token.ThrowIfCancellationRequested(); File.Move(temp, _path, true); }
        finally { if (File.Exists(temp)) File.Delete(temp); }
        return feed;
    }
}
