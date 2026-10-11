using System.Threading.Channels;
using TransTools.Models;
using TransTools.Services.Translation;

internal static class MeetingTranslationTests
{
    public static async Task RunAsync()
    {
        var input = Channel.CreateUnbounded<Caption>();
        var pump = new MeetingTranslationPump();
        var enabled = 0;
        var originals = new TaskCompletionSource(TaskCreationOptions.RunContinuationsAsynchronously);
        var backfilled = new TaskCompletionSource(TaskCreationOptions.RunContinuationsAsynchronously);
        var translated = new List<string>(); var visible = new List<string>(); var backfill = new List<string>();
        var run = pump.RunAsync(input.Reader, () => Volatile.Read(ref enabled) == 1,
            (caption, token) => { translated.Add(caption.Original); caption.Vietnamese = "translated"; return Task.CompletedTask; },
            (caption, previous, token) => {
                if (previous) { backfill.Add(caption.Original); if (backfill.Count == 2) backfilled.SetResult(); }
                else { visible.Add(caption.Original); if (visible.Count == 2) originals.SetResult(); }
                return Task.CompletedTask;
            }, CancellationToken.None);
        await input.Writer.WriteAsync(new Caption { Original = "one" });
        await input.Writer.WriteAsync(new Caption { Original = "two" }); pump.NotifyWork();
        await originals.Task.WaitAsync(TimeSpan.FromSeconds(3));
        if (translated.Count != 0) throw new Exception("Original-only mode called translation");
        Volatile.Write(ref enabled, 1); pump.NotifyWork();
        await backfilled.Task.WaitAsync(TimeSpan.FromSeconds(3));
        input.Writer.TryComplete(); pump.NotifyWork(); await run.WaitAsync(TimeSpan.FromSeconds(3));
        if (!translated.SequenceEqual(new[] { "one", "two" }) || !visible.SequenceEqual(translated) || !backfill.SequenceEqual(translated)) throw new Exception("Backfill lost order, duplicated or replayed captions");

        var stopped = Channel.CreateUnbounded<Caption>(); stopped.Writer.TryWrite(new Caption { Original = "retained" }); stopped.Writer.TryComplete();
        await new MeetingTranslationPump().RunAsync(stopped.Reader, () => false,
            (_, _) => throw new Exception("Stopped original mode translated"), (_, _, _) => Task.CompletedTask, CancellationToken.None).WaitAsync(TimeSpan.FromSeconds(3));
        var idle = Channel.CreateUnbounded<Caption>(); using var cancellation = new CancellationTokenSource();
        var waiting = new MeetingTranslationPump().RunAsync(idle.Reader, () => true, (_, _) => Task.CompletedTask, (_, _, _) => Task.CompletedTask, cancellation.Token);
        cancellation.Cancel();
        try { await waiting.WaitAsync(TimeSpan.FromSeconds(3)); throw new Exception("Idle translation pump ignored cancellation"); }
        catch (OperationCanceledException) { }
        Console.WriteLine("PASS: original-only recognition, ordered backfill without HUD replay, paused stop and idle cancellation");
    }
}
