using System.IO;
using System.Net.Http;
using System.Security.Cryptography;
using System.Text.Json;
namespace TransTools.Services.Updates;

public sealed record UpdateAsset(string Url, string Sha256, long Size);
public sealed record WindowsRelease(int SchemaVersion, string Version, string Title, string Notes, string ReleaseURL, UpdateAsset? Installer)
{
    public void Validate() {
        if (SchemaVersion != 1 || !System.Text.RegularExpressions.Regex.IsMatch(Version, @"^\d+\.\d+\.\d+$") ||
            !Uri.TryCreate(ReleaseURL, UriKind.Absolute, out var release) || release.Scheme != "https" || (release.Host != "github.com" || release.AbsolutePath != $"/duynk-tech/TransTools/releases/tag/v{Version}")) throw new InvalidDataException("Thông tin phiên bản không hợp lệ.");
        if (Installer == null) return;
        if (!Uri.TryCreate(Installer.Url, UriKind.Absolute, out var asset) || asset.Scheme != "https" || (asset.Host != "github.com" || asset.AbsolutePath != $"/duynk-tech/TransTools/releases/download/v{Version}/TransTools-Setup.exe") ||
            !System.Text.RegularExpressions.Regex.IsMatch(Installer.Sha256, @"^[a-fA-F0-9]{64}$") || Installer.Size <= 0 || Installer.Size > 512L * 1024 * 1024) throw new InvalidDataException("Gói cập nhật Windows không hợp lệ.");
    }
}
public static class WindowsUpdater
{
    public static async Task<WindowsRelease> CheckAsync(CancellationToken token) {
        using var client = new HttpClient { Timeout = TimeSpan.FromSeconds(30) };
        client.DefaultRequestHeaders.UserAgent.ParseAdd("TransTools-Updater");
        using var response = await client.GetAsync("https://api.github.com/repos/duynk-tech/TransTools/releases/latest", HttpCompletionOption.ResponseHeadersRead, token); response.EnsureSuccessStatusCode();
        await using var input = await response.Content.ReadAsStreamAsync(token);
        using var data = new MemoryStream(); var buffer = new byte[8192]; int count;
        while ((count = await input.ReadAsync(buffer, token)) > 0) { if (data.Length + count > 1024 * 1024) throw new InvalidDataException("Thông tin cập nhật quá lớn."); data.Write(buffer,0,count); }
        using var document = JsonDocument.Parse(data.ToArray());
        var root = document.RootElement;
        var tag = root.GetProperty("tag_name").GetString() ?? "";
        var version = tag.StartsWith("v") ? tag[1..] : tag;
        if (root.GetProperty("draft").GetBoolean() || root.GetProperty("prerelease").GetBoolean() || !System.Text.RegularExpressions.Regex.IsMatch(version, @"^\d+\.\d+\.\d+$")) throw new InvalidDataException("Phiên bản không hợp lệ.");
        UpdateAsset? installer = null;
        foreach (var file in root.GetProperty("assets").EnumerateArray()) {
            if (file.GetProperty("name").GetString() != "TransTools-Setup.exe") continue;
            var digest = file.TryGetProperty("digest", out var value) ? value.GetString() : null;
            if (digest == null || !digest.StartsWith("sha256:")) throw new InvalidDataException("Bộ cài thiếu SHA-256.");
            installer = new UpdateAsset(file.GetProperty("browser_download_url").GetString() ?? "", digest[7..], file.GetProperty("size").GetInt64());
        }
        var release = new WindowsRelease(1, version, root.GetProperty("name").GetString() ?? tag, root.GetProperty("body").GetString() ?? "", $"https://github.com/duynk-tech/TransTools/releases/tag/v{version}", installer);
        release.Validate(); return release;
    }
    public static async Task<string> DownloadAsync(WindowsRelease release, IProgress<double> progress, CancellationToken token) {
        release.Validate(); var asset = release.Installer ?? throw new InvalidOperationException("Phiên bản này chưa có bộ cài Windows.");
        var directory = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData), "TransTools", "temp", "updates"); Directory.CreateDirectory(directory);
        var path = Path.Combine(directory, "TransTools-Setup-" + release.Version + "-" + Guid.NewGuid().ToString("N") + ".exe");
        var temporary = path + ".partial";
        try {
            using var client = new HttpClient { Timeout = TimeSpan.FromMinutes(15) };
            using var response = await client.GetAsync(asset.Url, HttpCompletionOption.ResponseHeadersRead, token); response.EnsureSuccessStatusCode();
            await using var input = await response.Content.ReadAsStreamAsync(token);
            using var hash = IncrementalHash.CreateHash(HashAlgorithmName.SHA256); long length = 0;
            await using (var output = new FileStream(temporary, FileMode.CreateNew, FileAccess.Write, FileShare.None)) {
                var buffer = new byte[81920]; int count;
                while ((count = await input.ReadAsync(buffer, token)) > 0) {
                    length += count; if (length > asset.Size) throw new InvalidDataException("Bộ cài vượt kích thước công bố.");
                    hash.AppendData(buffer,0,count); await output.WriteAsync(buffer.AsMemory(0,count), token); progress.Report((double)length / asset.Size);
                }
            }
            if (length != asset.Size || !Convert.ToHexString(hash.GetHashAndReset()).Equals(asset.Sha256, StringComparison.OrdinalIgnoreCase)) throw new InvalidDataException("Bộ cài tải về không khớp SHA-256.");
            token.ThrowIfCancellationRequested(); File.Move(temporary,path); return path;
        } finally { if (File.Exists(temporary)) File.Delete(temporary); }
    }
}
