using System.Text.Json;
using TransTools.Services.Speech;
public static class VieNeuTests
{
    public static async Task RunAsync() {
        var folder = Environment.GetEnvironmentVariable("VIENEU_TEST_MODEL");
        var resources = Environment.GetEnvironmentVariable("VIENEU_TEST_RESOURCES");
        var golden = Environment.GetEnvironmentVariable("VIENEU_TEST_GOLDEN");
        if (string.IsNullOrWhiteSpace(folder) || string.IsNullOrWhiteSpace(resources) || string.IsNullOrWhiteSpace(golden)) { Console.WriteLine("SKIP: VieNeu real model (set VIENEU_TEST_MODEL/RESOURCES/GOLDEN)"); return; }
        var library = Path.Combine(resources, OperatingSystem.IsWindows() ? "sea_g2p_rs.dll" : "libsea_g2p_rs.dylib");
        using var phonemizer = new VieNeuPhonemizer(library, Path.Combine(folder, "sea_g2p.bin"));
        var tokenizer = new VieNeuTokenizer(Path.Combine(folder, "assets/VieNeu-TTS-v3-Turbo/onnx_update/tokenizer.json"));
        using var fixtures = JsonDocument.Parse(File.ReadAllText(golden));
        foreach (var fixture in fixtures.RootElement.EnumerateArray()) {
            var text = fixture.GetProperty("text").GetString()!; var phones = phonemizer.Phonemes(text);
            if (phones != fixture.GetProperty("phonemes").GetString()) throw new Exception("VieNeu phoneme mismatch: " + text);
            if (!tokenizer.Encode(phones).SequenceEqual(fixture.GetProperty("tokens").EnumerateArray().Select(v => v.GetInt32()))) throw new Exception("VieNeu BPE mismatch: " + text);
        }
        Console.WriteLine($"PASS: VieNeu native phonemes + BPE match {fixtures.RootElement.GetArrayLength()} upstream golden fixtures");
        using var model = new VieNeuEngine(folder, File.ReadAllText(Path.Combine(resources, "voices_v3_turbo.json")), library);
        var count = 0; float peak = 0;
        await model.SynthesizeAsync("Xin chào, chúc bạn học tập vui vẻ.", "Hải Đăng", samples => { if (samples.Any(sample => !float.IsFinite(sample))) throw new Exception("VieNeu non-finite audio"); count += samples.Length; peak = Math.Max(peak, samples.Select(Math.Abs).DefaultIfEmpty().Max()); return Task.CompletedTask; }, CancellationToken.None);
        if (count < 4800 || peak < .0001) throw new Exception("VieNeu silent/empty audio");
        Console.WriteLine($"PASS: VieNeu C# ONNX generated {count/48000.0:F2}s nonempty finite audio");
        using var cancelled = new CancellationTokenSource(); cancelled.Cancel();
        try { await model.SynthesizeAsync("Xin chào", "Hải Đăng", _ => Task.CompletedTask, cancelled.Token); throw new Exception("cancellation ignored"); } catch (OperationCanceledException) { Console.WriteLine("PASS: VieNeu cancellation"); }
    }
}
