using System.IO;
using System.Net.Http;
using System.Security.Cryptography;
using System.Text.Json;
using NAudio.Wave;
namespace TransTools.Services.Speech;
public sealed class VoiceService
{
    public static VoiceService Shared { get; } = new();
    public static string ModelFolder => Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData), "TransTools", "models", "supertonic-3");
    private readonly SemaphoreSlim _gate = new(1);
    private readonly SemaphoreSlim _speakerGate = new(1);
    private CancellationTokenSource? _playback;
    private SupertonicEngine? _engine;
    private VieNeuEngine? _vieNeu;
    public static string VieNeuFolder => Path.Combine(Path.GetDirectoryName(ModelFolder)!, "vieneu-v3-turbo");
    public static string VieNeuLibrary => Path.Combine(AppContext.BaseDirectory, "SpeechNative", "sea_g2p_rs.dll");
    public static bool HasVieNeuProcessor => File.Exists(VieNeuLibrary);
    public bool IsVieNeuInstalled => !_installing && HasVieNeuProcessor && File.Exists(Path.Combine(VieNeuFolder, "installed.json"));
    public static string ResourceText(string path) { using var stream = System.Windows.Application.GetResourceStream(new Uri("pack://application:,,,/Resources/" + path))!.Stream; using var reader = new StreamReader(stream); return reader.ReadToEnd(); }
    private void ReleaseEngines() { _engine?.Dispose(); _engine = null; _vieNeu?.Dispose(); _vieNeu = null; }
    private void LoadEngine(string engine, CancellationToken token) {
        if (_installing) throw new InvalidOperationException("Đang cài mô hình; hãy chờ tải hoàn tất trước khi đọc.");
        if (engine == "VieNeu v3 Turbo" ? !IsVieNeuInstalled : !IsInstalled) throw new InvalidOperationException("Mô hình chưa sẵn sàng hoặc đã được gỡ.");
        if (engine == "VieNeu v3 Turbo") {
            if (_vieNeu != null) return;
            ReleaseEngines(); ModelVerifier.Verify(VieNeuFolder, ResourceText("SpeechNative/vieneu-native-manifest.json"), token);
            _vieNeu = new VieNeuEngine(VieNeuFolder, ResourceText("SpeechNative/voices_v3_turbo.json"), VieNeuLibrary);
        } else {
            if (_engine != null) return;
            ReleaseEngines(); ModelVerifier.Verify(ModelFolder, ResourceText("Models/supertonic.json"), token);
            _engine = new SupertonicEngine(ModelFolder);
        }
    }
    private volatile bool _installing;
    private readonly SemaphoreSlim _modelOperations = new(1);
    private DateTime _lastUse;
    private readonly Timer _idle;
    public bool IsInstalled => !_installing && File.Exists(Path.Combine(ModelFolder, "installed.json"));
    private VoiceService() { _idle = new Timer(_ => { if (_gate.Wait(0)) { try { if ((DateTime.UtcNow - _lastUse).TotalMinutes > 2) { ReleaseEngines(); } } finally { _gate.Release(); } } }, null, 30000, 30000); }
    public void Stop() => _playback?.Cancel();
    public async Task InstallAsync(IProgress<string> progress, CancellationToken token, bool vieNeu = false)
    {
        if (vieNeu && !HasVieNeuProcessor) throw new InvalidOperationException("Bản app này chưa đóng gói bộ chuyển âm VieNeu native. Cài bản Windows có bộ xử lý native trước.");
        var folder = vieNeu ? VieNeuFolder : ModelFolder;
        await _modelOperations.WaitAsync(token);
        _installing = true; Stop();
        try {
        await _gate.WaitAsync(token);
        try { ReleaseEngines(); } finally { _gate.Release(); }
        var resource = System.Windows.Application.GetResourceStream(new Uri("pack://application:,,,/Resources/" + (vieNeu ? "SpeechNative/vieneu-native-manifest.json" : "Models/supertonic.json") + ""))!;
        using var resourceStream = resource.Stream;
        using var manifest = await JsonDocument.ParseAsync(resourceStream, cancellationToken: token);
        var revision = manifest.RootElement.TryGetProperty("revision", out var revisionValue) ? revisionValue.GetString() : null;
        using var client = new HttpClient { Timeout = TimeSpan.FromMinutes(15) };
        Directory.CreateDirectory(folder);
        foreach (var file in manifest.RootElement.GetProperty("files").EnumerateArray()) {
            var relative = file.GetProperty("path").GetString()!;
            var path = Path.Combine(folder, relative); Directory.CreateDirectory(Path.GetDirectoryName(path)!);
            progress.Report("Đang tải " + relative);
            var expected = file.GetProperty("sha256").GetString();
            if (File.Exists(path)) { await using var existing = File.OpenRead(path); if (Convert.ToHexString(await SHA256.HashDataAsync(existing, token)).Equals(expected, StringComparison.OrdinalIgnoreCase)) continue; }
            using var response = await client.GetAsync(vieNeu ? file.GetProperty("url").GetString()! : $"https://huggingface.co/supertone-oss-archive/supertonic-3/resolve/{revision}/{relative}", HttpCompletionOption.ResponseHeadersRead, token);
            response.EnsureSuccessStatusCode();
            await using (var output = File.Create(path + ".partial")) await response.Content.CopyToAsync(output, token);
            await using (var input = File.OpenRead(path + ".partial")) {
                if (input.Length != file.GetProperty("size").GetInt64() || !Convert.ToHexString(await SHA256.HashDataAsync(input, token)).Equals(expected, StringComparison.OrdinalIgnoreCase)) throw new InvalidDataException("Dữ liệu tải không khớp: " + relative);
            }
            File.Move(path + ".partial", path, true);
        }
        await File.WriteAllTextAsync(Path.Combine(folder, "installed.json"), manifest.RootElement.GetRawText(), token);
        progress.Report(vieNeu ? "VieNeu v3 Turbo đã sẵn sàng" : "Supertonic 3 đã sẵn sàng");
        } finally { _installing = false; _modelOperations.Release(); }
    }
    public async Task<byte[]> SynthesizeAsync(string text, string language, string engine, double rate, CancellationToken token)
    {
        if (engine == "Edge") return await new EdgeTtsService().SynthesizeAsync(text, EdgeTtsService.VoiceForLanguage(language), rate, cancellationToken: token);
        if (engine == "VieNeu v3 Turbo") {
            if (language != "vi" || !IsVieNeuInstalled) throw new InvalidOperationException("VieNeu chỉ dùng cho tiếng Việt sau khi tải mô hình.");
            await _gate.WaitAsync(token);
            try { return await Task.Run(async () => {
                LoadEngine(engine, token); _lastUse = DateTime.UtcNow;
                using var stream = new MemoryStream(); using var writer = new WaveFileWriter(stream, new WaveFormat(48000, 16, 1));
                await _vieNeu!.SynthesizeAsync(text, "Hải Đăng", samples => { foreach (var sample in samples) writer.WriteSample(Math.Clamp(sample, -1f, 1f)); return Task.CompletedTask; }, token);
                writer.Flush(); return stream.ToArray();
            }, token); } finally { _lastUse = DateTime.UtcNow; _gate.Release(); }
        }
        if (engine != "Supertonic 3") throw new InvalidOperationException("Giọng cơ bản không hỗ trợ xuất audio.");
        if (!IsInstalled) throw new InvalidOperationException("Tải Supertonic 3 trong Cài đặt trước khi dùng.");
        await _gate.WaitAsync(token);
        try {
            return await Task.Run(() => {
                LoadEngine(engine, token); _lastUse = DateTime.UtcNow;
                using var stream = new MemoryStream();
                using var writer = new WaveFileWriter(stream, new WaveFormat(_engine!.SampleRate, 16, 1));
                foreach (var part in CaptionTextSegmenter.Split(text)) {
                    token.ThrowIfCancellationRequested();
                    var samples = _engine!.Synthesize(part, language, (float)rate, token);
                    if (writer.Length + samples.Length * 2L > 60 * 1024 * 1024) throw new InvalidOperationException("Audio vượt giới hạn 60 MB.");
                    foreach (var sample in samples) writer.WriteSample(Math.Clamp(sample, -1f, 1f));
                    for (var i = 0; i < _engine!.SampleRate / 4; i++) writer.WriteSample(0);
                }
                writer.Flush(); return stream.ToArray();
            }, token);
        } finally { _lastUse = DateTime.UtcNow; _gate.Release(); }
    }
    public async Task SpeakAsync(string text, string language, string engine, double rate = 1)
    {
        Stop(); var cts = new CancellationTokenSource(); _playback = cts;
        bool entered = false;
        try {
            await _speakerGate.WaitAsync(cts.Token); entered = true;
            if (engine == "Giọng cơ bản") { using var basic = new WindowsMediaTtsService(); await basic.SpeakAsync(text, language: language, token: cts.Token, rate: rate); return; }
            // Bound playback memory to one phrase; begin reading before the entire paragraph is synthesized.
            foreach (var part in CaptionTextSegmenter.Split(text)) {
                cts.Token.ThrowIfCancellationRequested();
                var bytes = await SynthesizeAsync(part, language, engine, rate, cts.Token);
                using var stream = new MemoryStream(bytes);
                using WaveStream reader = engine == "Edge" ? new Mp3FileReader(stream) : new WaveFileReader(stream);
                cts.Token.ThrowIfCancellationRequested();
                using var output = new WaveOutEvent(); output.Init(reader); output.Play();
                while (output.PlaybackState == PlaybackState.Playing) await Task.Delay(50, cts.Token);
            }
        } catch (OperationCanceledException) { }
        finally { if (entered) _speakerGate.Release(); if (_playback == cts) _playback = null; cts.Dispose(); }
    }
    public async Task ExportAsync(string text, string language, string engine, double rate, string destination, CancellationToken token)
    {
        var temporary = destination + "." + Guid.NewGuid().ToString("N") + ".partial";
        try {
            if (engine == "Edge") {
                if (text.Length > 30000) throw new InvalidOperationException("Chia văn bản thành phần nhỏ hơn trước khi xuất giọng trực tuyến.");
                var bytes = await SynthesizeAsync(text, language, engine, rate, token);
                await File.WriteAllBytesAsync(temporary, bytes, token);
            } else if (engine is "Supertonic 3" or "VieNeu v3 Turbo") {
                if (engine == "VieNeu v3 Turbo" && (language != "vi" || !IsVieNeuInstalled)) throw new InvalidOperationException("VieNeu chỉ dùng cho tiếng Việt sau khi tải mô hình.");
                if (engine == "Supertonic 3" && !IsInstalled) throw new InvalidOperationException("Tải Supertonic 3 trước khi xuất audio.");
                await _gate.WaitAsync(token);
                try {
                    await Task.Run(async () => {
                        LoadEngine(engine, token);
                        using var writer = new WaveFileWriter(temporary, new WaveFormat(engine == "VieNeu v3 Turbo" ? 48000 : _engine!.SampleRate, 16, 1));
                        foreach (var part in CaptionTextSegmenter.Split(text)) {
                            token.ThrowIfCancellationRequested();
                            void Write(float[] samples) { if (writer.Length + samples.Length * 2L > 60 * 1024 * 1024) throw new InvalidOperationException("Audio vượt giới hạn 60 MB; chia đoạn văn để xuất tiếp."); foreach (var sample in samples) writer.WriteSample(Math.Clamp(sample, -1f, 1f)); }
                            if (engine == "VieNeu v3 Turbo") await _vieNeu!.SynthesizeAsync(part, "Hải Đăng", samples => { Write(samples); return Task.CompletedTask; }, token);
                            else Write(_engine!.Synthesize(part, language, (float)rate, token));
                        }
                        if (writer.Length == 0) throw new InvalidDataException("Không có audio để xuất.");
                    }, token);
                } finally { _lastUse = DateTime.UtcNow; _gate.Release(); }
            } else throw new InvalidOperationException("Giọng này không hỗ trợ xuất audio.");
            token.ThrowIfCancellationRequested(); File.Move(temporary, destination, true);
        } finally { if (File.Exists(temporary)) File.Delete(temporary); }
    }
    public async Task RemoveModelAsync(bool vieNeu = false)
    {
        await _modelOperations.WaitAsync();
        try {
            Stop(); await _gate.WaitAsync();
            try { ReleaseEngines(); if (Directory.Exists(vieNeu ? VieNeuFolder : ModelFolder)) Microsoft.VisualBasic.FileIO.FileSystem.DeleteDirectory(vieNeu ? VieNeuFolder : ModelFolder, Microsoft.VisualBasic.FileIO.UIOption.OnlyErrorDialogs, Microsoft.VisualBasic.FileIO.RecycleOption.SendToRecycleBin); }
            finally { _gate.Release(); }
        } finally { _modelOperations.Release(); }
    }
}
