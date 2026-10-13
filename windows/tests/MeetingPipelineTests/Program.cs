using System.Diagnostics;
using System.Speech.Synthesis;
using System.Speech.AudioFormat;
using System.Text.Json;
using System.Text.RegularExpressions;
using NAudio.Wave;
using TransTools.Services.Speech;
using TransTools.Services.Translation;
if (args.Length != 2) throw new ArgumentException("Provide translator model and evidence directory.");
Directory.CreateDirectory(args[1]);
using var deadline = new CancellationTokenSource(TimeSpan.FromMinutes(8));
using var speech = new WhisperSttService();
await speech.InitializeModelAsync(language: "en", cancellationToken: deadline.Token);
await using var translator = new MarianTranslationService(args[0], "en", "vi");
var prompts = new[] {
    "Hello everyone. We need to review the project today.",
    "Please send the meeting report tomorrow morning.",
    "The customer asked us to fix the problem before Friday.",
    "We should test the application and discuss the results together."
};
var evidence = new List<object>();
foreach (var text in prompts) {
    using var synthesized = new MemoryStream();
    using (var speaker = new SpeechSynthesizer()) {
        var voice = speaker.GetInstalledVoices().FirstOrDefault(v => v.Enabled && v.VoiceInfo.Culture.TwoLetterISOLanguageName == "en") ?? throw new Exception("No Windows English voice for the fixture.");
        speaker.SelectVoice(voice.VoiceInfo.Name);
        speaker.SetOutputToAudioStream(synthesized, new SpeechAudioFormatInfo(16000, AudioBitsPerSample.Sixteen, AudioChannel.Mono));
        speaker.Speak(text); speaker.SetOutputToNull();
    }
    var pcm = synthesized.ToArray();
    if (pcm.Length == 0 || pcm.Length % 2 != 0) throw new Exception("Incomplete fixture PCM.");
    foreach (var chunkSeconds in new[] { 8, 4 }) {
        var recognized = new List<string>();
        void Segment(string value, double start, double end) => recognized.Add(value);
        speech.OnSegmentTranscribed += Segment;
        var watch = Stopwatch.StartNew();
        try {
            for (var offset = 0; offset < pcm.Length; offset += chunkSeconds * 32000) {
                using var wave = new MemoryStream();
                using (var writer = new WaveFileWriter(wave, new WaveFormat(16000, 16, 1))) { writer.Write(pcm, offset, Math.Min(chunkSeconds * 32000, pcm.Length - offset)); writer.Flush(); var bytes = wave.ToArray(); using var input = new MemoryStream(bytes); await speech.ProcessAudioAsync(input, deadline.Token); }
            }
        } finally { speech.OnSegmentTranscribed -= Segment; }
        var processingMs = watch.Elapsed.TotalMilliseconds;
        var transcript = string.Join(" ", recognized);
        var expected = Regex.Matches(text.ToLowerInvariant(), "[a-z]+").Select(m => m.Value).ToHashSet();
        var actual = Regex.Matches(transcript.ToLowerInvariant(), "[a-z]+").Select(m => m.Value).ToHashSet();
        var recall = expected.Count(word => actual.Contains(word)) / (double)expected.Count;
        watch.Restart(); var translation = await translator.TranslateAsync(transcript, deadline.Token); var translationMs = watch.Elapsed.TotalMilliseconds;
        evidence.Add(new { text, chunkSeconds, transcript, translation, recall, audioSeconds = pcm.Length / 32000.0, processingMs, translationMs, processorCount = Environment.ProcessorCount });
        await File.WriteAllTextAsync(Path.Combine(args[1], "meeting-pipeline.json"), JsonSerializer.Serialize(evidence, new JsonSerializerOptions { WriteIndented = true }));
        Console.WriteLine($"MEASURE: chunks={chunkSeconds}s recall={recall:F2} recognition={processingMs:F0}ms translation={translationMs:F0}ms | {transcript} | {translation}");
        if (recall < .70 || string.IsNullOrWhiteSpace(translation) || translation == transcript) throw new Exception("Recognition/translation pipeline failed the synthetic English fixture.");
    }
}
try {
    var online = await new GoogleTranslationService().TranslateAsync("Hello, how are you?", "en", "vi", deadline.Token);
    Console.WriteLine("GOOGLE PROBE: " + online);
} catch (Exception ex) { Console.WriteLine("GOOGLE PROBE FAILED: " + ex.Message); }
Console.WriteLine("PASS: actual Windows speech recognition to Offline translation pipeline; synthetic fixtures only, device capture not covered.");
