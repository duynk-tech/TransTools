using System.IO;
using Microsoft.ML.OnnxRuntime;
using Microsoft.ML.OnnxRuntime.Tensors;
namespace TransTools.Services.Speech;

public static class VieNeuSpeakerEncoder
{
    // Called explicitly while creating a voice profile, never during meeting capture.
    public static float[] Extract(float[] samples, string encoderPath, CancellationToken token = default)
    {
        var features = VieNeuSpeakerFeatures.Extract(samples, token);
        token.ThrowIfCancellationRequested();
        using var options = new SessionOptions {
            IntraOpNumThreads = 2, InterOpNumThreads = 1,
            GraphOptimizationLevel = GraphOptimizationLevel.ORT_ENABLE_ALL
        };
        options.AddSessionConfigEntry("session.intra_op.allow_spinning", "0");
        options.AddSessionConfigEntry("session.inter_op.allow_spinning", "0");
        using var session = new InferenceSession(encoderPath, options);
        using var run = new RunOptions();
        using var cancellation = token.Register(() => run.Terminate = true);
        var input = NamedOnnxValue.CreateFromTensor("input", new DenseTensor<float>(features, new[] { 1, features.Length / 80, 80 }));
        using var output = session.Run(new[] { input }, new[] { "output" }, run);
        token.ThrowIfCancellationRequested();
        var embedding = output.Single(item => item.Name == "output").AsTensor<float>().ToArray();
        ValidateEmbedding(embedding);
        return embedding;
    }
    public static void ValidateEmbedding(float[] embedding)
    {
        if (embedding.Length != 192 || embedding.Any(value => !float.IsFinite(value)) || !embedding.Any(value => Math.Abs(value) > .00001f))
            throw new InvalidDataException("Không trích xuất được giọng hợp lệ.");
    }
}
