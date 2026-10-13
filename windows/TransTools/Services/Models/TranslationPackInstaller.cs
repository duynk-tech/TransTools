using System.IO;
using System.Net.Http;
using System.Security.Cryptography;
namespace TransTools.Services.Models;
public static class TranslationPackInstaller
{
    public const string Revision = "30bcd461c0d7338ad106b36314d3eedc2d4e998c";
    private static readonly SemaphoreSlim Gate = new(1, 1);
    private static readonly HttpClient Client = new() { Timeout = TimeSpan.FromMinutes(10) };
    private static readonly Dictionary<string, string> Files = new() {
        ["onnx/encoder_model_quantized.onnx"] = "dfcd7a32be3fdd21cbcf5d354520d626f1768fd6e205ca62a6a11a4641d31f36",
        ["onnx/decoder_model_quantized.onnx"] = "cde3e02aaca72cfaf2267f6c31c4dcc1b323d769bf90c273f2a1c1d56198ddba",
        ["source.spm"] = "fdd9ab486ca8ea060967105e30db7d8928729c78a67448711d2dd7c3153b37cd",
        ["vocab.json"] = "bcc8bbafeb0b6b58fecf244f8da996da9aa45dbea7871164f9c8ce480507f9fe"
    };
    public static string Folder(string root) => Path.Combine(root, "models", "opus-en-vi");
    public static bool IsInstalled(string root) {
        var folder = Folder(root);
        try { return File.ReadAllText(Path.Combine(folder, "installed-revision.txt")) == Revision && Files.Keys.All(name => File.Exists(Path.Combine(folder, name))) && File.Exists(Path.Combine(folder, "generation_config.json")); }
        catch (IOException) { return false; } catch (UnauthorizedAccessException) { return false; }
    }
    public static async Task InstallAsync(string root, IProgress<long>? downloadedBytes, CancellationToken token)
    {
        await Gate.WaitAsync(token).ConfigureAwait(false);
        string? staging = null;
        try {
            if (IsInstalled(root)) return;
            var destination = Folder(root);
            if (Directory.Exists(destination)) throw new IOException("Bộ dịch chưa đầy đủ. Gỡ bộ cũ trước khi tải lại.");
            var parent = Path.GetDirectoryName(destination)!; Directory.CreateDirectory(parent);
            staging = Path.Combine(parent, ".translation-install-" + Guid.NewGuid().ToString("N"));
            Directory.CreateDirectory(Path.Combine(staging, "onnx"));
            long total = 0;
            foreach (var file in Files) {
                using var response = await Client.GetAsync("https://huggingface.co/Xenova/opus-mt-en-vi/resolve/" + Revision + "/" + file.Key, HttpCompletionOption.ResponseHeadersRead, token).ConfigureAwait(false);
                response.EnsureSuccessStatusCode();
                await using var input = await response.Content.ReadAsStreamAsync(token).ConfigureAwait(false);
                var path = Path.Combine(staging, file.Key);
                await using (var output = File.Create(path)) {
                    var buffer = new byte[65536]; long length = 0; int count;
                    while ((count = await input.ReadAsync(buffer, token).ConfigureAwait(false)) != 0) {
                        length += count; if (length > 128 * 1024 * 1024) throw new InvalidDataException("Tệp mô hình vượt kích thước cho phép.");
                        await output.WriteAsync(buffer.AsMemory(0, count), token).ConfigureAwait(false); total += count; downloadedBytes?.Report(total);
                    }
                }
                await using var verified = File.OpenRead(path);
                var hash = Convert.ToHexString(await SHA256.HashDataAsync(verified, token).ConfigureAwait(false));
                if (!hash.Equals(file.Value, StringComparison.OrdinalIgnoreCase)) throw new InvalidDataException("Tệp tải về chưa đúng mô hình. Hãy thử lại.");
            }
            await File.WriteAllTextAsync(Path.Combine(staging, "generation_config.json"), "{\"decoder_start_token_id\":53684,\"eos_token_id\":0,\"pad_token_id\":53684}", token);
            await File.WriteAllTextAsync(Path.Combine(staging, "source.txt"), "Xenova/opus-mt-en-vi · https://huggingface.co/Xenova/opus-mt-en-vi\nOriginal: https://huggingface.co/Helsinki-NLP/opus-mt-en-vi\nRevision: " + Revision, token);
            await File.WriteAllTextAsync(Path.Combine(staging, "installed-revision.txt"), Revision, token);
            token.ThrowIfCancellationRequested(); Directory.Move(staging, destination); staging = null;
        } finally {
            if (staging != null && Directory.Exists(staging)) { try { Directory.Delete(staging, true); } catch (IOException) { } catch (UnauthorizedAccessException) { } }
            Gate.Release();
        }
    }
}
