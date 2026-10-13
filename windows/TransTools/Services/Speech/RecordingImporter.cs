using System.IO;
using System.Security.Cryptography;
using System.Text.Json;
namespace TransTools.Services.Speech;
public static class RecordingImporter
{
    // Import one of the existing offline catalogs; never substitute generated audio.
    public static async Task ImportAsync(string manifestPath, CancellationToken token)
    {
        var source = Path.GetDirectoryName(manifestPath)!;
        var name = Path.GetFileName(source);
        if (!new[] { "AudioLangEnglish", "NHKJapanese", "ZIMChinese", "Korean" }.Contains(name)) throw new InvalidDataException("Chọn manifest.json trong thư mục AudioLangEnglish, NHKJapanese, ZIMChinese hoặc Korean.");
        using var manifest = JsonDocument.Parse(await File.ReadAllTextAsync(manifestPath, token));
        var entries = manifest.RootElement.GetProperty("entries");
        if (entries.GetArrayLength() == 0) throw new InvalidDataException("Bộ bản ghi trống.");
        Directory.CreateDirectory(RecordingPlayer.Root);
        var staging = Path.Combine(RecordingPlayer.Root, ".import-" + Guid.NewGuid());
        Directory.CreateDirectory(staging);
        try {
            foreach (var entry in entries.EnumerateArray()) {
                token.ThrowIfCancellationRequested();
                var file = entry.GetProperty("file").GetString()!;
                if (string.IsNullOrWhiteSpace(file) || Path.GetFileName(file) != file || !new[] { ".mp3", ".wav", ".m4a", ".ogg" }.Contains(Path.GetExtension(file).ToLowerInvariant())) throw new InvalidDataException("Tên audio không hợp lệ.");
                var inputPath = Path.Combine(source, file);
                if (new FileInfo(inputPath).Length > 20 * 1024 * 1024) throw new InvalidDataException("Bản ghi vượt giới hạn 20 MB.");
                await using var input = File.OpenRead(inputPath);
                var hash = Convert.ToHexString(await SHA256.HashDataAsync(input, token));
                if (!hash.Equals(entry.GetProperty("sha256").GetString(), StringComparison.OrdinalIgnoreCase)) throw new InvalidDataException("Bản ghi bị hỏng: " + file);
                input.Position = 0;
                await using var output = File.Create(Path.Combine(staging, file)); await input.CopyToAsync(output, token);
            }
            File.Copy(manifestPath, Path.Combine(staging, "manifest.json"));
            var destination = Path.Combine(RecordingPlayer.Root, name);
            if (Directory.Exists(destination)) throw new InvalidOperationException("Bộ này đã được cài. Gỡ bộ cũ trong thư mục dữ liệu trước khi nhập lại.");
            Directory.Move(staging, destination);
        } finally { if (Directory.Exists(staging)) Directory.Delete(staging, true); }
    }
}
