using System.Diagnostics;
using System.Text.Json;
using TransTools.Services.Translation;
if (args.Length != 1) throw new ArgumentException("Provide the verified model directory.");
using var reference = JsonDocument.Parse(File.ReadAllText(Path.Combine(AppContext.BaseDirectory, "reference.json")));
using var decoder = new MarianTokenDecoder(args[0]);
foreach (var sample in reference.RootElement.GetProperty("samples").EnumerateArray()) {
    var input = sample.GetProperty("inputIds").EnumerateArray().Select(v => v.GetInt64()).ToArray();
    var expected = sample.GetProperty("outputIds").EnumerateArray().Select(v => v.GetInt64()).ToArray();
    var watch = Stopwatch.StartNew(); var output = decoder.Generate(input, CancellationToken.None);
    if (!output.SequenceEqual(expected)) throw new Exception("Windows token output differs from pinned ONNX CPU reference: " + sample.GetProperty("source").GetString());
    Console.WriteLine($"PASS: {sample.GetProperty("source").GetString()} | {watch.Elapsed.TotalMilliseconds:F0} ms | {output.Length} tokens");
}
using var canceled = new CancellationTokenSource(); canceled.Cancel();
try { decoder.Generate(new long[] { 0 }, canceled.Token); throw new Exception("Canceled translation ran."); } catch (OperationCanceledException) { }
try { decoder.Generate(new long[513], CancellationToken.None); throw new Exception("Long input was silently truncated."); } catch (ArgumentException) { }
Console.WriteLine("PASS: cancellation and input limit; native Windows tokenizer integration remains untested");
