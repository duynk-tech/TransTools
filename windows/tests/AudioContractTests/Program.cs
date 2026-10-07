using NAudio.Wave;
using TransTools.Services.Speech;

void Check(bool condition, string name) { if (!condition) throw new Exception(name); Console.WriteLine("PASS: " + name); }
// Exercise the actual WAV writer contract used by the meeting pipeline.
byte[] pcm = new byte[80000];
byte[] wav;
using (var stream = new MemoryStream()) {
    using var writer = new WaveFileWriter(stream, new WaveFormat(16000, 16, 1));
    writer.Write(pcm, 0, pcm.Length);
    writer.Flush();
    wav = stream.ToArray();
}
using (var reader = new WaveFileReader(new MemoryStream(wav))) {
    Check(reader.WaveFormat.SampleRate == 16000 && reader.WaveFormat.Channels == 1, "Whisper WAV format");
    Check(reader.Length == pcm.Length, "PCM length preserved");
    Check(Math.Abs(reader.TotalTime.TotalSeconds - 2.5) < .001, "chunk duration");
}
foreach (var (language, prefix) in new[] { ("vi", "vi-VN"), ("Tiếng Việt", "vi-VN"), ("ja", "ja-JP"), ("Tiếng Trung", "zh-CN"), ("ko", "ko-KR"), ("en", "en-US") })
    Check(EdgeTtsService.VoiceForLanguage(language).StartsWith(prefix), "voice for " + language);

SupertonicTests.Run();

var format = WaveFormat.CreateIeeeFloatWaveFormat(48000, 2);
var input = new byte[48000 * 2 * 4];
for (var i = 0; i < 48000; i++) { var sample = BitConverter.GetBytes((float)(.3 * Math.Sin(i * 2 * Math.PI * 440 / 48000))); sample.CopyTo(input, i * 8); sample.CopyTo(input, i * 8 + 4); }
var converter = new TransTools.Services.Audio.StreamingAudioConverter(format);
using var converted = new MemoryStream();
for (var offset = 0; offset < input.Length; offset += 3840) converted.Write(converter.Convert(input[offset..Math.Min(input.Length, offset + 3840)], Math.Min(3840, input.Length - offset)));
Check(Math.Abs(converted.Length - 32000) < 400, "streaming resampler preserves one-second duration across 100 packets");
Check(converted.ToArray().Any(b => b != 0), "streaming audio remains audible");

Check(CaptionTextSegmenter.Split("第一句。第二句！第三句？").Count == 3, "CJK sentence boundaries without spaces");
var longText = string.Join(" ", Enumerable.Repeat("learning", 100));
var parts = CaptionTextSegmenter.Split(longText);
Check(parts.All(part => part.Length <= 160) && string.Join(" ", parts) == longText, "long subtitle splits without dropping words");

await VieNeuTests.RunAsync();

StorageTests.Run();

var asset = new TransTools.Services.Updates.UpdateAsset("https://github.com/duynk-tech/TransTools/releases/download/v1.4.3/TransTools-Setup.exe", new string('a',64), 100);
var release = new TransTools.Services.Updates.WindowsRelease(1,"1.4.3","Release","Notes","https://github.com/duynk-tech/TransTools/releases/tag/v1.4.3",asset);
release.Validate();
Check(true, "Windows update manifest accepts pinned HTTPS asset");
foreach (var bad in new[] { release with { Installer = asset with { Url = "https://attacker.invalid/setup.exe" } }, release with { Installer = asset with { Size = 0 } }, release with { Installer = asset with { Sha256 = "bad" } }, release with { Version = "../../setup" } }) {
    bool rejected = false; try { bad.Validate(); } catch (InvalidDataException) { rejected = true; }
    Check(rejected, "Windows update rejects untrusted or malformed release");
}

LearningTests.Run();

Check(CaptionDisplayTiming.HoldSeconds("Hi", "") == 1.5, "short captions retain minimum reading time");
Check(CaptionDisplayTiming.HoldSeconds(new string('a',1000), new string('b',1000)) == 5, "long captions cannot stall display indefinitely");
Check(CaptionDisplayTiming.HoldSeconds(new string('a',60), new string('b',60)) > CaptionDisplayTiming.HoldSeconds(new string('a',60), ""), "bilingual captions receive extra reading time");

var endpoint = new TransTools.Services.Speech.UtteranceEndpoint(2);
var silence = new byte[32000];
var voice = new byte[3200];
for (var i = 0; i < voice.Length; i += 2) { voice[i] = 0; voice[i + 1] = 8; }
Check(!endpoint.Accept(silence) && !endpoint.Accept(silence), "initial silence never sends an empty utterance");
Check(!endpoint.Accept(voice), "speech does not trigger premature send");
Check(!endpoint.Accept(silence), "one-second hesitation preserves utterance with two-second delay");
Check(!endpoint.Accept(voice), "resumed speech resets pause counter");
Check(!endpoint.Accept(silence) && endpoint.Accept(silence), "utterance ends only after full configured pause");

var sessionFolder = Path.Combine(Path.GetTempPath(), "trans-tools-session-contract-" + Guid.NewGuid());
try {
    var sessionStore = new TransTools.Services.Storage.SessionStore(sessionFolder);
    var sessionId = Guid.NewGuid();
    await Task.WhenAll(
        sessionStore.UpdateSessionAsync(sessionId, () => new TransTools.Models.MeetingSession(), s => s.Notes = "My notes"),
        sessionStore.UpdateSessionAsync(sessionId, () => new TransTools.Models.MeetingSession(), s => s.Summary = "AI summary"),
        sessionStore.UpdateSessionAsync(sessionId, () => new TransTools.Models.MeetingSession(), s => s.Captions = [new TransTools.Models.Caption { Original = "Keep all words", Vietnamese = "Giữ đủ chữ" }]));
    var stored = (await sessionStore.LoadSessionsAsync()).Single();
    Check(stored.Notes == "My notes" && stored.Summary == "AI summary" && stored.Captions.Count == 1, "concurrent meeting, notes and summary updates preserve all fields");
    await sessionStore.UpdateSessionAsync(sessionId, () => throw new Exception("Must reuse ID"), s => s.DurationSeconds = 5);
    Check((await sessionStore.LoadSessionsAsync()).Count == 1, "saving an existing session does not duplicate it");
} finally { if (Directory.Exists(sessionFolder)) Directory.Delete(sessionFolder, true); }

var readSource = "CPU 80%, RAM 16GB. Ngày hôm nay vẫn đẹp.";
var readTokens = SpeechReadingPreparation.Tokens(readSource);
var spokenCopy = SpeechReadingPreparation.Apply(readSource, readTokens, [new(1, "tám mươi phần trăm")]);
Check(spokenCopy == "CPU tám mươi phần trăm, RAM 16GB. Ngày hôm nay vẫn đẹp.", "AI reading changes only the enumerated token span");
foreach (var invalidReading in new[] { new SpeechReadingPreparation.Reading(99, "rewrite"), new SpeechReadingPreparation.Reading(0, "line\nbreak") }) {
    bool rejected = false; try { SpeechReadingPreparation.Apply(readSource, readTokens, [invalidReading]); } catch (InvalidDataException) { rejected = true; }
    Check(rejected, "AI reading rejects unknown spans and control characters");
}
