using TransTools.Services.Speech;
public static class SupertonicTests
{
 public static void Run() {
  if (SupertonicEngine.Preprocess("Hello", "en") != "<en>Hello.</en>") throw new Exception("language wrapping");
  var folder = Environment.GetEnvironmentVariable("SUPERtonic_TEST_MODEL");
  if (string.IsNullOrWhiteSpace(folder)) { Console.WriteLine("SKIP: real Supertonic inference (set SUPERtonic_TEST_MODEL)"); return; }
  using var engine = new SupertonicEngine(folder);
  foreach (var (lang,text) in new[] { ("vi","Xin chào bạn."), ("en","Hello, welcome."), ("ja","こんにちは。"), ("ko","안녕하세요.") }) {
   var samples = engine.Synthesize(text, lang, 1f, CancellationToken.None);
   if (samples.Length < engine.SampleRate / 4) throw new Exception("audio too short");
   if (samples.Any(sample => !float.IsFinite(sample)) || samples.Max(sample => Math.Abs(sample)) < .0001f) throw new Exception("invalid or silent audio");
   Console.WriteLine($"PASS: {lang} Supertonic {samples.Length/(double)engine.SampleRate:F2}s");
  }
 }
}
