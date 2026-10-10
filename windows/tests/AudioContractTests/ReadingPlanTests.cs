using TransTools.Services.Speech;
using TransTools.Services.Reading;
internal static class ReadingPlanTests
{
    public static async Task RunAsync()
    {
        void Check(bool value, string message) { if (!value) throw new Exception(message); }
        var catalog = "{\"schemaVersion\":1,\"revision\":1,\"models\":[{\"id\":\"supertonic-3\",\"engineID\":\"supertonic\",\"version\":\"3.0.0\",\"name\":\"Supertonic 3\",\"summary\":\"Giọng đọc\",\"recommended\":true}]}";
        var feed = TransTools.Services.Models.RemoteModelCatalog.Parse(System.Text.Encoding.UTF8.GetBytes(catalog));
        Check(feed.Revision == 1 && feed.Models[0].Summary == "Giọng đọc", "Remote catalog did not preserve valid metadata");
        foreach (var invalid in new[] { catalog.Replace("supertonic-3", "unknown"), catalog.Replace("3.0.0", "9.0.0"), catalog.Replace("schemaVersion\":1", "schemaVersion\":2") }) {
            var rejected = false; try { TransTools.Services.Models.RemoteModelCatalog.Parse(System.Text.Encoding.UTF8.GetBytes(invalid)); } catch (System.IO.InvalidDataException) { rejected = true; }
            Check(rejected, "Remote catalog accepted unsupported model/schema/version");
        }
        var source = "Số 3.14 đúng. “Xin chào!”\r\nĐoạn hai chưa có dấu";
        var parts = SpeechReadingPlan.Parts(source, .35, .8);
        Check(parts.Select(p => p.Text).SequenceEqual(new[] { "Số 3.14 đúng.", "“Xin chào!”", "Đoạn hai chưa có dấu" }), "Reading plan lost text, quotes or decimal punctuation");
        Check(parts.Select(p => p.Pause).SequenceEqual(new[] { .35, .8, .8 }), "Sentence/paragraph pauses differ from macOS");
        Check(SpeechReadingPlan.Parts("Dr. Smith nói. Câu tiếp theo.", 0, 0).Count == 2, "Title abbreviation created an artificial sentence");
        var cjk = "第一句。第二句！第三句？";
        var cjkParts = SpeechReadingPlan.Parts(cjk, .2, .9);
        Check(cjkParts.Count == 3 && string.Concat(cjkParts.Select(p => p.Text)) == cjk, "CJK reading plan changed source text");
        var bounded = SpeechReadingPlan.Parts("First. Second.\nThird.", double.NaN, 10);
        Check(bounded[0].Pause == .35 && bounded[1].Pause == 4 && bounded[2].Pause == 4, "Invalid pause values were not bounded");
        var heard = new List<string>();
        await SpeechReadingPlan.PlayAsync(SpeechReadingPlan.Parts("One. Two.\nThree.", 0, 0), (text, _) => { heard.Add(text); return Task.CompletedTask; }, CancellationToken.None);
        Check(heard.SequenceEqual(new[] { "One.", "Two.", "Three." }), "Reading playback reordered or lost a sentence");
        using (var cancellation = new CancellationTokenSource())
        {
            heard.Clear(); var started = new TaskCompletionSource(TaskCreationOptions.RunContinuationsAsynchronously);
            var playback = SpeechReadingPlan.PlayAsync(SpeechReadingPlan.Parts("One. Two.", 2, 4), (text, _) => { heard.Add(text); started.TrySetResult(); return Task.CompletedTask; }, cancellation.Token);
            await started.Task.WaitAsync(TimeSpan.FromSeconds(2)); cancellation.Cancel();
            var stopped = false; try { await playback.WaitAsync(TimeSpan.FromSeconds(2)); } catch (OperationCanceledException) { stopped = true; }
            Check(stopped && heard.SequenceEqual(new[] { "One." }), "Stop did not cancel the pause before the next sentence");
        }
        var folder = Path.Combine(Path.GetTempPath(), "trans-tools-reading-" + Guid.NewGuid().ToString("N"));
        try {
            var path = Path.Combine(folder, "preferences.json"); var store = new ReadingPreferencesStore(path);
            Check(store.Load() == new ReadingPreference(), "Missing reader preferences did not use defaults");
            var quickPath = Path.Combine(folder, "quick.json");
            var quick = new TransTools.Services.Translation.QuickEditorPreferencesStore(quickPath);
            Check(quick.Load() == 15, "Quick editor default differs from Mac");
            quick.Save(19); Check(new TransTools.Services.Translation.QuickEditorPreferencesStore(quickPath).Load() == 19, "Quick font did not survive reload");
            quick.Save(30); Check(quick.Load() == 22, "Quick font upper bound failed");
            quick.Save(-1); Check(quick.Load() == 12, "Quick font lower bound failed");
            File.WriteAllText(quickPath, "{broken"); Check(quick.Load() == 15 && File.ReadAllText(quickPath) == "{broken", "Quick font corrupt load modified stored data");
            store.Save(new(.7, 1.6, false)); Check(new ReadingPreferencesStore(path).Load() == new ReadingPreference(.7, 1.6, false), "Reading preferences did not survive reload");
            store.Save(new(-5, 9, true)); Check(store.Load() == new ReadingPreference(0, 4, true), "Persisted reader pauses were not bounded");
            File.WriteAllText(path, "{broken"); Check(store.Load() == new ReadingPreference() && File.ReadAllText(path) == "{broken", "Corrupt preference load changed stored data or prevented reading");
            Check(Directory.GetFiles(folder, "*.tmp").Length == 0, "Atomic reading preference writes left temporary files");
        } finally { if (Directory.Exists(folder)) Directory.Delete(folder, true); }
        Console.WriteLine("PASS: reading sentence/paragraph plan, source preservation, cancellation during pauses and persisted settings");
    }
}
