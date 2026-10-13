using System.IO;
using System.Security.Cryptography;
using System.Text.Json;
using NAudio.Wave;
namespace TransTools.Services.Speech;
public sealed class RecordingPlayer
{
    private static CancellationTokenSource? _current;
    public static void Stop() => _current?.Cancel();
    public static string Root => Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData), "TransTools", "Pronunciation");
    public static async Task PlayAsync(string id, string language)
    {
        Stop(); var cts = new CancellationTokenSource(); _current = cts;
        try {
            var folder = Path.Combine(Root, language switch { "en" => "AudioLangEnglish", "ja" => "NHKJapanese", "zh" => "ZIMChinese", _ => "Korean" });
            var manifest = Path.Combine(folder, "manifest.json");
            if (!File.Exists(manifest)) throw new InvalidOperationException("Chưa cài bản ghi phát âm. Nhập bộ dữ liệu trong Cài đặt; không phát thay bằng TTS.");
            using var data = JsonDocument.Parse(await File.ReadAllTextAsync(manifest, cts.Token));
            var key = language switch { "en" => "symbol", "ja" => "id", _ => "text" };
            var entry = data.RootElement.GetProperty("entries").EnumerateArray().FirstOrDefault(x => x.GetProperty(key).GetString() == id);
            if (entry.ValueKind == JsonValueKind.Undefined) throw new InvalidOperationException("Chưa có bản ghi cho âm đã chọn.");
            var name = entry.GetProperty("file").GetString()!;
            if (Path.GetFileName(name) != name) throw new InvalidDataException("Tên tệp không hợp lệ.");
            var path = Path.Combine(folder, name);
            await using (var stream = File.OpenRead(path)) {
                if (!Convert.ToHexString(await SHA256.HashDataAsync(stream, cts.Token)).Equals(entry.GetProperty("sha256").GetString(), StringComparison.OrdinalIgnoreCase)) throw new InvalidDataException("Bản ghi bị thay đổi hoặc hỏng.");
            }
            using var reader = new AudioFileReader(path); using var output = new WaveOutEvent(); output.Init(reader); output.Play();
            while (output.PlaybackState == PlaybackState.Playing) await Task.Delay(50, cts.Token);
        } catch (OperationCanceledException) { }
        finally { if (_current == cts) _current = null; cts.Dispose(); }
    }
}
