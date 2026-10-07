// C# + ONNX port of LocalSpeechBackend/VieNeu, based on Apache-2.0 onnx_runtime_lite.py.
using System.IO;
using System.Numerics;
using System.Text.Json;
using System.Text.RegularExpressions;
using Microsoft.ML.OnnxRuntime;
using Microsoft.ML.OnnxRuntime.Tensors;
namespace TransTools.Services.Speech;
public sealed class VieNeuEngine : IDisposable
{
    private const int Hidden = 768, Channels = 16, AudioVocab = 1024;
    private readonly List<InferenceSession> _sessions = new();
    private readonly InferenceSession _prefill, _decode, _acoustic, _codec;
    private readonly VieNeuTokenizer _tokenizer;
    private readonly VieNeuPhonemizer _phonemizer;
    private readonly JsonDocument _metadata;
    private readonly Dictionary<string, Voice> _voices;
    private readonly float[] _textEmb, _audioEmb, _projection, _bias, _lnW, _lnB;
    private readonly float _epsilon;
    private sealed class Voice { public float[] speaker_emb { get; set; } = Array.Empty<float>(); public int[][]? codes { get; set; } }
    public int SampleRate => 48000;
    public VieNeuEngine(string folder, string voicesJson, string library) {
        var graph = Path.Combine(folder, "assets", "VieNeu-TTS-v3-Turbo", "onnx_update");
        var codecPath = Path.Combine(folder, "assets", "MOSS-Audio-Tokenizer-Nano-ONNX");
        _tokenizer = new VieNeuTokenizer(Path.Combine(graph, "tokenizer.json"));
        var arrays = VieNeuArrays.Load(Path.Combine(graph, "vieneu_v3_heads.npz"));
        float[] Required(string key, int count) => arrays.TryGetValue(key, out var values) && values.Length == count ? values : throw new InvalidDataException("Trọng số không tương thích: " + key);
        _textEmb = Required("text_emb", 419 * Hidden); _audioEmb = Required("audio_emb", Channels * AudioVocab * Hidden);
        _projection = Required("xvec_w", Hidden * 192); _bias = Required("xvec_b", Hidden); _lnW = Required("xvec_ln_w", Hidden); _lnB = Required("xvec_ln_b", Hidden); _epsilon = Required("xvec_ln_eps", 1)[0];
        using var voices = JsonDocument.Parse(voicesJson);
        _voices = JsonSerializer.Deserialize<Dictionary<string, Voice>>(voices.RootElement.GetProperty("presets").GetRawText())!;
        _metadata = JsonDocument.Parse(File.ReadAllText(Path.Combine(codecPath, "codec_browser_onnx_meta.json")));
        _phonemizer = new VieNeuPhonemizer(library, Path.Combine(folder, "sea_g2p.bin"));
        try {
            using var options = new SessionOptions { IntraOpNumThreads = Math.Clamp(Environment.ProcessorCount / 2, 1, 4), InterOpNumThreads = 1 };
            options.AddSessionConfigEntry("session.intra_op.allow_spinning", "0"); options.AddSessionConfigEntry("session.inter_op.allow_spinning", "0");
            InferenceSession Load(string path) { var session = new InferenceSession(path, options); _sessions.Add(session); return session; }
            _prefill = Load(Path.Combine(graph, "vieneu_prefill.onnx")); _decode = Load(Path.Combine(graph, "vieneu_decode_step.onnx")); _acoustic = Load(Path.Combine(graph, "vieneu_acoustic_cached.onnx")); _codec = Load(Path.Combine(codecPath, "moss_audio_tokenizer_decode_step.onnx"));
        } catch { Dispose(); throw; }
    }
    private static NamedOnnxValue F(string name, float[] data, params int[] shape) => NamedOnnxValue.CreateFromTensor(name, new DenseTensor<float>(data, shape));
    private static NamedOnnxValue I(string name, long[] data, params int[] shape) => NamedOnnxValue.CreateFromTensor(name, new DenseTensor<long>(data, shape));
    private static NamedOnnxValue N(string name, int[] data, params int[] shape) => NamedOnnxValue.CreateFromTensor(name, new DenseTensor<int>(data, shape));
    private static DisposableNamedOnnxValue Output(IDisposableReadOnlyCollection<DisposableNamedOnnxValue> output, string name) => output.FirstOrDefault(v => v.Name == name) ?? throw new InvalidDataException("Thiếu đầu ra: " + name);
    private static float[] Floats(IDisposableReadOnlyCollection<DisposableNamedOnnxValue> output, string name) => Output(output, name).AsTensor<float>().ToArray();
    private static float[] Dot(float[] matrix, int rows, int columns, float[] vector, int offset = 0) {
        var output = new float[rows]; var width = Vector<float>.Count;
        for (var row = 0; row < rows; row++) {
            var at = offset + row * columns; var sum = Vector<float>.Zero; int column = 0;
            for (; column + width <= columns; column += width) sum += new Vector<float>(matrix, at + column) * new Vector<float>(vector, column);
            float value = Vector.Sum(sum); for (; column < columns; column++) value += matrix[at + column] * vector[column]; output[row] = value;
        }
        return output;
    }
    private float[] Anchor(Voice voice) {
        if (voice.speaker_emb.Length != 192) throw new InvalidDataException("Speaker embedding không hợp lệ.");
        var value = Dot(_projection, Hidden, 192, voice.speaker_emb);
        for (var i = 0; i < Hidden; i++) value[i] += _bias[i];
        var mean = value.Average(); var scale = MathF.Sqrt(value.Select(v => (v - mean) * (v - mean)).Average() + _epsilon);
        for (var i = 0; i < Hidden; i++) value[i] = (value[i] - mean) / scale * _lnW[i] + _lnB[i]; return value;
    }
    private float[] Embed(int text, int[] codes, float[] anchor) {
        if (text < 0 || text >= 419 || codes.Length != Channels || codes.Any(c => c < 0 || c > AudioVocab)) throw new InvalidDataException("Token giọng không hợp lệ.");
        var output = _textEmb[(text * Hidden)..((text + 1) * Hidden)];
        for (var ch = 0; ch < Channels; ch++) if (codes[ch] != AudioVocab) { var at = (ch * AudioVocab + codes[ch]) * Hidden; for (var i = 0; i < Hidden; i++) output[i] += _audioEmb[at + i]; }
        for (var i = 0; i < Hidden; i++) output[i] += anchor[i]; return output;
    }
    private static List<NamedOnnxValue> Past(IDisposableReadOnlyCollection<DisposableNamedOnnxValue> output, int layers) {
        var inputs = new List<NamedOnnxValue>();
        for (var i = 0; i < layers; i++) foreach (var kind in new[] { "k", "v" }) inputs.Add(NamedOnnxValue.CreateFromTensor($"past_{kind}_{i}", Output(output, $"present_{kind}_{i}").AsTensor<float>()));
        return inputs;
    }
    private static int Sample(float[] logits, List<int> history) {
        foreach (var code in history.Distinct()) logits[code] = logits[code] < 0 ? logits[code] * 1.2f : logits[code] / 1.2f;
        var best = Enumerable.Range(0, logits.Length).OrderByDescending(i => logits[i]).Take(25).ToArray();
        var peak = logits[best[0]] / .8f;
        var candidates = best.Select(i => (Id: i, Weight: Math.Exp(logits[i] / .8f - peak))).ToArray();
        var total = candidates.Sum(v => v.Weight); var kept = new List<(int Id, double Weight)>(); double cumulative = 0;
        foreach (var value in candidates) { if (cumulative >= total * .95) break; kept.Add(value); cumulative += value.Weight; }
        var choice = Random.Shared.NextDouble() * cumulative; double cursor = 0;
        foreach (var value in kept) { cursor += value.Weight; if (cursor >= choice) return value.Id; } return kept[^1].Id;
    }
    private (int[] Codes, bool Eos) AcousticFrame(float[] hidden, List<int>[] history, CancellationToken token) {
        var output = _acoustic.Run(new[] { F("token_emb", hidden.Concat(_textEmb[(5 * Hidden)..(6 * Hidden)]).ToArray(), 1, 2, Hidden), I("position_ids", new long[] { 0, 1 }, 1, 2), F("past_k_0", Array.Empty<float>(), 1, 8, 0, 96), F("past_v_0", Array.Empty<float>(), 1, 8, 0, 96) });
        try {
            var values = Floats(output, "hidden"); var slot0 = values[..Hidden]; var codes = new int[Channels];
            for (var ch = 0; ch < Channels; ch++) {
                token.ThrowIfCancellationRequested(); var vector = ch == 0 ? values[^Hidden..] : values;
                var code = Sample(Dot(_audioEmb, AudioVocab, Hidden, vector, ch * AudioVocab * Hidden), history[ch]); codes[ch] = code; history[ch].Add(code); if (history[ch].Count > 64) history[ch].RemoveAt(0);
                if (ch < Channels - 1) {
                    var feed = Past(output, 1); var at = (ch * AudioVocab + code) * Hidden; feed.Add(F("token_emb", _audioEmb[at..(at + Hidden)], 1, 1, Hidden)); feed.Add(I("position_ids", new long[] { ch + 2 }, 1, 1));
                    var next = _acoustic.Run(feed); output.Dispose(); output = next; values = Floats(output, "hidden");
                }
            }
            var logits = Dot(_textEmb, 419, Hidden, slot0); var best = Array.IndexOf(logits, logits.Max()); return (codes, best == 6);
        } finally { output.Dispose(); }
    }
    private List<NamedOnnxValue> InitialCodecState() {
        var state = new List<NamedOnnxValue>(); var spec = _metadata.RootElement.GetProperty("streaming_decode");
        int[] Shape(JsonElement entry, string key) => entry.GetProperty(key).EnumerateArray().Select(x => x.GetInt32()).ToArray();
        foreach (var entry in spec.GetProperty("transformer_offsets").EnumerateArray()) { var shape = Shape(entry, "shape"); state.Add(N(entry.GetProperty("input_name").GetString()!, new int[shape.Aggregate(1, (a, b) => a * b)], shape)); }
        foreach (var entry in spec.GetProperty("attention_caches").EnumerateArray()) foreach (var (prefix, key) in new[] { ("offset", "offset_shape"), ("cached_keys", "cache_shape"), ("cached_values", "cache_shape"), ("cached_positions", "positions_shape") }) {
            var shape = Shape(entry, key); var count = shape.Aggregate(1, (a, b) => a * b); var name = entry.GetProperty(prefix + "_input_name").GetString()!;
            state.Add(prefix is "cached_keys" or "cached_values" ? F(name, new float[count], shape) : N(name, Enumerable.Repeat(prefix == "cached_positions" ? -1 : 0, count).ToArray(), shape));
        }
        return state;
    }
    private List<NamedOnnxValue> CodecState(IDisposableReadOnlyCollection<DisposableNamedOnnxValue> output) {
        var state = new List<NamedOnnxValue>(); var spec = _metadata.RootElement.GetProperty("streaming_decode");
        foreach (var entry in spec.GetProperty("transformer_offsets").EnumerateArray()) state.Add(NamedOnnxValue.CreateFromTensor(entry.GetProperty("input_name").GetString()!, Output(output, entry.GetProperty("output_name").GetString()!).AsTensor<int>()));
        foreach (var entry in spec.GetProperty("attention_caches").EnumerateArray()) foreach (var prefix in new[] { "offset", "cached_keys", "cached_values", "cached_positions" }) {
            var name = entry.GetProperty(prefix + "_input_name").GetString()!; var value = Output(output, entry.GetProperty(prefix + "_output_name").GetString()!);
            state.Add(prefix is "cached_keys" or "cached_values" ? NamedOnnxValue.CreateFromTensor(name, value.AsTensor<float>()) : NamedOnnxValue.CreateFromTensor(name, value.AsTensor<int>()));
        }
        return state;
    }
    public string Phonemes(string text) => _phonemizer.Phonemes(text);
    public async Task SynthesizeAsync(string text, string voiceName, Func<float[], Task> emit, CancellationToken token) {
        if (text.Length == 0 || text.Length > 500 || !_voices.TryGetValue(voiceName, out var voice)) throw new InvalidOperationException("Đoạn đọc hoặc giọng VieNeu không hợp lệ.");
        token.ThrowIfCancellationRequested(); var phones = _phonemizer.Phonemes(text); var ids = _tokenizer.Encode(phones);
        if (ids.Length == 0 || ids.Length >= 1024) throw new InvalidOperationException("Đoạn đọc quá dài sau chuẩn hóa.");
        var anchor = Anchor(voice); var padding = Enumerable.Repeat(AudioVocab, Channels).ToArray(); var prompt = new List<float>();
        foreach (var id in new[] { 16, 3 }.Concat(ids).Append(4)) prompt.AddRange(Embed(id, padding, anchor));
        var refs = (voice.codes ?? Array.Empty<int[]>()).ToList(); if (refs.Count > 1 && refs[^1][0] == 455) refs.RemoveAt(refs.Count - 1);
        foreach (var codes in refs) prompt.AddRange(Embed(7, codes, anchor)); var length = prompt.Count / Hidden;
        if (length >= 1536) throw new InvalidOperationException("Ngữ cảnh giọng quá dài.");
        var output = _prefill.Run(new[] { F("inputs_embeds", prompt.ToArray(), 1, length, Hidden) });
        IDisposableReadOnlyCollection<DisposableNamedOnnxValue>? codecOutput = null;
        try {
            var hidden = Floats(output, "hidden")[^Hidden..]; var history = Enumerable.Range(0, Channels).Select(_ => new List<int>()).ToArray(); var frames = new List<int[]>(); var state = InitialCodecState();
            var stripped = Regex.Replace(phones, "</?en>", "");
            var syllables = Math.Max(1, stripped.Split((char[]?)null, StringSplitOptions.RemoveEmptyEntries).Sum(word => Math.Max(1, Regex.Matches(word, "[aeiouyæɐɑɒɔəɘɛɜɤɯɵøœʉʊʌɪɨɚɝᵻᵿ]+").Count)));
            var shortPhrase = syllables <= 4 && stripped.Length <= 24 * syllables;
            var ceiling = Math.Min(300, shortPhrase ? Math.Min(24 + stripped.Length * 2, 13 + 5 * (syllables - 1)) : 24 + stripped.Length * 2);
            var shortAudio = new List<float>();
            for (var step = 0; step < ceiling; step++) {
                token.ThrowIfCancellationRequested(); var (codes, eos) = AcousticFrame(hidden, history, token); frames.Add(codes);
                if (!eos) {
                    var feed = Past(output, 12); feed.Add(F("inputs_embeds", Embed(5, codes, anchor), 1, 1, Hidden)); feed.Add(I("position_ids", new long[] { length + step }, 1, 1));
                    var next = _decode.Run(feed); output.Dispose(); output = next; hidden = Floats(output, "hidden");
                }
                if (frames.Count >= 6 || eos) {
                    var feed = new List<NamedOnnxValue>(state) { N("audio_codes", frames.SelectMany(frame => frame).ToArray(), 1, frames.Count, Channels), N("audio_code_lengths", new[] { frames.Count }, 1) };
                    var next = _codec.Run(feed); codecOutput?.Dispose(); codecOutput = next; state = CodecState(next); frames.Clear();
                    var audio = Output(next, "audio").AsTensor<float>(); var count = Output(next, "audio_lengths").AsTensor<int>().First(); var shape = audio.Dimensions.ToArray(); var values = audio.ToArray();
                    if (shape.Length != 3 || shape[0] != 1 || shape[1] != 2 || count < 0 || count > shape[2]) throw new InvalidDataException("Audio VieNeu không tương thích.");
                    var samples = Enumerable.Range(0, count).Select(i => (values[i] + values[shape[2] + i]) * .5f).ToArray();
                    if (samples.Any(v => !float.IsFinite(v))) throw new InvalidDataException("Audio VieNeu không hữu hạn.");
                    token.ThrowIfCancellationRequested(); if (shortPhrase) shortAudio.AddRange(samples); else if (samples.Length > 0) await emit(samples);
                }
                if (eos) { if (shortPhrase && shortAudio.Count > 0) await emit(shortAudio.ToArray()); return; }
            }
            throw new InvalidOperationException("VieNeu chưa kết thúc câu; chia đoạn ngắn hơn và thử lại.");
        } finally { output.Dispose(); codecOutput?.Dispose(); }
    }
    public void Dispose() { foreach (var session in _sessions) session.Dispose(); _sessions.Clear(); _phonemizer?.Dispose(); _metadata?.Dispose(); }
}
