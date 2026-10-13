// Adapted from the Supertone MIT example used by the Mac backend.
using System.IO;
using System.Text;
using System.Text.Json;
using System.Text.RegularExpressions;
using Microsoft.ML.OnnxRuntime;
using Microsoft.ML.OnnxRuntime.Tensors;
namespace TransTools.Services.Speech;
public sealed class SupertonicEngine : IDisposable
{
    private readonly InferenceSession _duration, _encoder, _vector, _vocoder;
    private readonly long[] _index;
    private readonly DenseTensor<float> _styleDp, _styleTtl;
    private readonly int _sampleRate, _baseChunk, _compress, _latentDim;
    public int SampleRate => _sampleRate;
    public SupertonicEngine(string folder)
    {
        using var options = new SessionOptions { IntraOpNumThreads = Math.Clamp(Environment.ProcessorCount / 2, 1, 4), InterOpNumThreads = 1 };
        InferenceSession Load(string name) => new(Path.Combine(folder, "onnx", name + ".onnx"), options);
        options.AddSessionConfigEntry("session.intra_op.allow_spinning", "0");
        options.AddSessionConfigEntry("session.inter_op.allow_spinning", "0");
        _index = JsonSerializer.Deserialize<long[]>(File.ReadAllText(Path.Combine(folder, "onnx/unicode_indexer.json")))!;
        using var config = JsonDocument.Parse(File.ReadAllText(Path.Combine(folder, "onnx/tts.json")));
        var ae = config.RootElement.GetProperty("ae"); var ttl = config.RootElement.GetProperty("ttl");
        _sampleRate = ae.GetProperty("sample_rate").GetInt32(); _baseChunk = ae.GetProperty("base_chunk_size").GetInt32();
        _compress = ttl.GetProperty("chunk_compress_factor").GetInt32(); _latentDim = ttl.GetProperty("latent_dim").GetInt32();
        using var voice = JsonDocument.Parse(File.ReadAllText(Path.Combine(folder, "voice_styles/F1.json")));
        DenseTensor<float> Style(string name) {
            var v = voice.RootElement.GetProperty(name);
            var dims = v.GetProperty("dims").EnumerateArray().Select(x => x.GetInt32()).ToArray();
            var values = v.GetProperty("data").EnumerateArray().SelectMany(x => x.EnumerateArray()).SelectMany(x => x.EnumerateArray()).Select(x => x.GetSingle()).ToArray();
            return new(values, dims);
        }
        _styleDp = Style("style_dp"); _styleTtl = Style("style_ttl");
        var loaded = new List<InferenceSession>();
        try {
            InferenceSession Graph(string name) { var session = Load(name); loaded.Add(session); return session; }
            _duration = Graph("duration_predictor"); _encoder = Graph("text_encoder"); _vector = Graph("vector_estimator"); _vocoder = Graph("vocoder");
        } catch { foreach (var session in loaded) session.Dispose(); throw; }
    }
    private static NamedOnnxValue F(string name, DenseTensor<float> value) => NamedOnnxValue.CreateFromTensor(name, value);
    public float[] Synthesize(string text, string language, float speed, CancellationToken token)
    {
        if (!new[] { "vi", "en", "ja", "ko" }.Contains(language)) throw new InvalidOperationException("Supertonic chưa hỗ trợ ngôn ngữ này.");
        if (text.Length > 300 || string.IsNullOrWhiteSpace(text)) throw new InvalidOperationException("Đoạn đọc phải từ 1 đến 300 ký tự.");
        var normalized = Preprocess(text, language);
        var runes = normalized.EnumerateRunes().ToArray();
        var ids = new DenseTensor<long>(runes.Select(r => r.Value < _index.Length ? _index[r.Value] : -1L).ToArray(), new[] { 1, runes.Length });
        var mask = new DenseTensor<float>(Enumerable.Repeat(1f, runes.Length).ToArray(), new[] { 1, 1, runes.Length });
        var inputs = new[] { NamedOnnxValue.CreateFromTensor("text_ids", ids), F("text_mask", mask) };
        token.ThrowIfCancellationRequested();
        using var dp = _duration.Run(inputs.Append(F("style_dp", _styleDp)).ToArray());
        var seconds = dp.First(x => x.Name == "duration").AsTensor<float>().First() / Math.Clamp(speed, .7f, 1.5f);
        if (!float.IsFinite(seconds) || seconds <= 0 || seconds > 60) throw new InvalidDataException("Thời lượng audio mô hình không hợp lệ.");
        using var enc = _encoder.Run(inputs.Append(F("style_ttl", _styleTtl)).ToArray());
        var embTensor = enc.First(x => x.Name == "text_emb").AsTensor<float>();
        var emb = new DenseTensor<float>(embTensor.ToArray(), embTensor.Dimensions.ToArray());
        var length = ((int)(seconds * _sampleRate) + _baseChunk * _compress - 1) / (_baseChunk * _compress);
        var dims = new[] { 1, _latentDim * _compress, length };
        var noise = new float[dims[1] * length];
        for (var i = 0; i < noise.Length; i++) noise[i] = (float)(Math.Sqrt(-2 * Math.Log(Math.Max(.0001, Random.Shared.NextDouble()))) * Math.Cos(2 * Math.PI * Random.Shared.NextDouble()));
        var latent = new DenseTensor<float>(noise, dims);
        var latentMask = new DenseTensor<float>(Enumerable.Repeat(1f, length).ToArray(), new[] { 1, 1, length });
        for (var step = 0; step < 8; step++) {
            token.ThrowIfCancellationRequested();
            using var result = _vector.Run(new[] { F("noisy_latent", latent), F("text_emb", emb), F("style_ttl", _styleTtl), F("latent_mask", latentMask), F("text_mask", mask), F("current_step", new(new[] { (float)step }, new[] { 1 })), F("total_step", new(new[] { 8f }, new[] { 1 })) });
            var tensor = result.First(x => x.Name == "denoised_latent").AsTensor<float>();
            latent = new(tensor.ToArray(), dims);
        }
        token.ThrowIfCancellationRequested(); using var output = _vocoder.Run(new[] { F("latent", latent) });
        var samples = output.First(x => x.Name == "wav_tts").AsTensor<float>().Take((int)(seconds * _sampleRate)).ToArray();
        if (samples.Length == 0 || samples.Any(x => !float.IsFinite(x)) || !samples.Any(x => Math.Abs(x) > .0001)) throw new InvalidDataException("Mô hình không tạo được audio hợp lệ.");
        return samples;
    }
    public static string Preprocess(string text, string language)
    {
        var s = text.Normalize(NormalizationForm.FormKD);
        s = string.Concat(s.EnumerateRunes().Where(r => !(r.Value >= 0x1F300 && r.Value <= 0x1FAFF || r.Value >= 0x2600 && r.Value <= 0x27BF || r.Value >= 0x1F1E6 && r.Value <= 0x1F1FF)).Select(r => r.ToString()));
        foreach (var c in new[] { "–", "‑", "—" }) s = s.Replace(c, "-");
        foreach (var c in new[] { "_", "[", "]", "|", "/", "#", "→", "←" }) s = s.Replace(c, " ");
        s = s.Replace("“", "\"").Replace("”", "\"").Replace("‘", "'").Replace("’", "'").Replace("´", "'").Replace("`", "'");
        foreach (var c in new[] { "♥", "☆", "♡", "©", "\\" }) s = s.Replace(c, "");
        s = s.Replace("@", " at ").Replace("e.g.,", "for example, ").Replace("i.e.,", "that is, ");
        s = Regex.Replace(s, @"\s+", " ").Trim(); s = Regex.Replace(s, @" ([,.!?;:'])", "$1");
        if (!Regex.IsMatch(s, "[.!?;:,'\"”)\\]}…。]$")) s += ".";
        return $"<{language}>{s}</{language}>";
    }
    public void Dispose() { _duration.Dispose(); _encoder.Dispose(); _vector.Dispose(); _vocoder.Dispose(); }
}
