using System.IO;
using System.Text.Json;
using Microsoft.ML.OnnxRuntime;
using Microsoft.ML.OnnxRuntime.Tensors;
namespace TransTools.Services.Translation;

// Offline token inference. Tokenization and model installation are separate; never downloads files.
public sealed class MarianTokenDecoder : IDisposable
{
    private readonly InferenceSession _encoder, _decoder;
    private readonly object _gate = new();
    private readonly long _start, _end, _pad;
    private bool _disposed;
    public MarianTokenDecoder(string folder)
    {
        using var configuration = JsonDocument.Parse(File.ReadAllText(Path.Combine(folder, "generation_config.json")));
        _start = configuration.RootElement.GetProperty("decoder_start_token_id").GetInt64();
        _end = configuration.RootElement.GetProperty("eos_token_id").GetInt64();
        _pad = configuration.RootElement.GetProperty("pad_token_id").GetInt64();
        using var options = new SessionOptions { IntraOpNumThreads = 2, InterOpNumThreads = 1 };
        options.AddSessionConfigEntry("session.intra_op.allow_spinning", "0");
        options.AddSessionConfigEntry("session.inter_op.allow_spinning", "0");
        _encoder = new InferenceSession(Path.Combine(folder, "onnx", "encoder_model_quantized.onnx"), options);
        try { _decoder = new InferenceSession(Path.Combine(folder, "onnx", "decoder_model_quantized.onnx"), options); }
        catch { _encoder.Dispose(); throw; }
    }
    public long[] Generate(IReadOnlyList<long> sourceIds, CancellationToken token)
    {
        if (sourceIds.Count is < 1 or > 512 || sourceIds.Any(id => id < 0)) throw new ArgumentException("Đoạn văn vượt giới hạn mô hình.", nameof(sourceIds));
        var source = sourceIds.ToArray();
        lock (_gate) {
            ObjectDisposedException.ThrowIf(_disposed, this); token.ThrowIfCancellationRequested();
            var ids = new DenseTensor<long>(source, new[] { 1, source.Length });
            var mask = new DenseTensor<long>(Enumerable.Repeat(1L, source.Length).ToArray(), new[] { 1, source.Length });
            using var encoderOutput = _encoder.Run(new[] { NamedOnnxValue.CreateFromTensor("input_ids", ids), NamedOnnxValue.CreateFromTensor("attention_mask", mask) }, new[] { "last_hidden_state" });
            var encoded = encoderOutput.First().AsTensor<float>();
            var hidden = new DenseTensor<float>(encoded.ToArray(), encoded.Dimensions.ToArray());
            var generated = new List<long> { _start };
            for (var step = 0; step < 256; step++) {
                token.ThrowIfCancellationRequested();
                using var outputs = _decoder.Run(new[] {
                    NamedOnnxValue.CreateFromTensor("input_ids", new DenseTensor<long>(generated.ToArray(), new[] { 1, generated.Count })),
                    NamedOnnxValue.CreateFromTensor("encoder_attention_mask", mask),
                    NamedOnnxValue.CreateFromTensor("encoder_hidden_states", hidden)
                }, new[] { "logits" });
                var logits = outputs.First().AsTensor<float>();
                var vocabulary = logits.Dimensions[2]; var last = generated.Count - 1;
                long next = -1; var best = float.NegativeInfinity;
                for (var word = 0; word < vocabulary; word++) {
                    var score = logits[0, last, word];
                    if (word != _pad && float.IsFinite(score) && score > best) { best = score; next = word; }
                }
                if (next < 0) throw new InvalidDataException("Mô hình chưa trả kết quả dịch hợp lệ.");
                token.ThrowIfCancellationRequested();
                if (next == _end) return generated.Skip(1).ToArray();
                generated.Add(next);
            }
            throw new InvalidDataException("Bản dịch chưa kết thúc. Hãy dùng đoạn văn ngắn hơn.");
        }
    }
    public void Dispose() { lock (_gate) { if (_disposed) return; _disposed = true; _encoder.Dispose(); _decoder.Dispose(); } }
}
