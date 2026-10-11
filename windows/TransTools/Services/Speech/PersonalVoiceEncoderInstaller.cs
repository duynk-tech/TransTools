using System.IO;
using System.Net.Http;
using System.Security.Cryptography;
using TransTools.Services.Storage;
namespace TransTools.Services.Speech;

public static class PersonalVoiceEncoderInstaller
{
    private const long Size = 28303423;
    private const string Hash = "a6ac6a63997761ae2997373e2ee1c47040854b4b759ea41ec48e4e42df0f4d73";
    private const string Url = "https://huggingface.co/pnnbao-ump/VieNeu-TTS-v3-Turbo/resolve/61b85e3d937fbbacb387714180e8182823512523/speaker_encoder.onnx";
    private static readonly SemaphoreSlim Gate = new(1);
    public static string ModelPath => Path.Combine(PersonalVoiceStore.DefaultRoot, "Runtime", "speaker_encoder.onnx");
    private static async Task<bool> ValidAsync(string path, CancellationToken token)
    {
        if (!File.Exists(path) || new FileInfo(path).Length != Size) return false;
        await using var input = File.OpenRead(path);
        return Convert.ToHexString(await SHA256.HashDataAsync(input, token)).Equals(Hash, StringComparison.OrdinalIgnoreCase);
    }
    public static async Task<string> EnsureAsync(IProgress<string>? progress, CancellationToken token)
    {
        await Gate.WaitAsync(token);
        string? temporary = null;
        try {
            if (await ValidAsync(ModelPath, token)) return ModelPath;
            progress?.Report("Đang tải bộ tạo giọng · chỉ cần tải lần đầu…");
            Directory.CreateDirectory(Path.GetDirectoryName(ModelPath)!);
            temporary = ModelPath + "." + Guid.NewGuid().ToString("N") + ".partial";
            using var client = new HttpClient { Timeout = TimeSpan.FromMinutes(5) };
            using var response = await client.GetAsync(Url, HttpCompletionOption.ResponseHeadersRead, token);
            response.EnsureSuccessStatusCode();
            if (response.Content.Headers.ContentLength is long length && length != Size) throw new InvalidDataException("Dung lượng bộ tạo giọng không khớp.");
            await using (var input = await response.Content.ReadAsStreamAsync(token))
            await using (var output = File.Create(temporary)) {
                var buffer = new byte[65536]; long total = 0; int read;
                while ((read = await input.ReadAsync(buffer, token)) > 0) {
                    total += read;
                    if (total > Size) throw new InvalidDataException("Bộ tạo giọng tải về quá lớn.");
                    await output.WriteAsync(buffer.AsMemory(0, read), token);
                }
                if (total != Size) throw new InvalidDataException("Bộ tạo giọng tải chưa đầy đủ.");
            }
            if (!await ValidAsync(temporary, token)) throw new InvalidDataException("Dữ liệu bộ tạo giọng không khớp. Hãy tải lại.");
            token.ThrowIfCancellationRequested();
            File.Move(temporary, ModelPath, true);
            progress?.Report("Bộ tạo giọng đã sẵn sàng.");
            return ModelPath;
        } finally {
            try { if (temporary != null && File.Exists(temporary)) File.Delete(temporary); }
            finally { Gate.Release(); }
        }
    }
}
