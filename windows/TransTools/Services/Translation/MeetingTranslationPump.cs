using System.Threading.Channels;
using TransTools.Models;

namespace TransTools.Services.Translation;

// One owner consumes recognition and deferred work. Wake-ups coalesce; no polling timer.
public sealed class MeetingTranslationPump
{
    private readonly Channel<byte> _wake = Channel.CreateBounded<byte>(new BoundedChannelOptions(1) { FullMode = BoundedChannelFullMode.DropOldest, SingleReader = true });
    public void NotifyWork() => _wake.Writer.TryWrite(0);

    public async Task RunAsync(ChannelReader<Caption> input, Func<bool> canTranslate,
        Func<Caption, CancellationToken, Task> translate,
        Func<Caption, bool, CancellationToken, Task> present, CancellationToken token)
    {
        var deferred = new Queue<Caption>();
        while (true) {
            token.ThrowIfCancellationRequested();
            if (canTranslate() && deferred.TryDequeue(out var previous)) {
                await translate(previous, token);
                // Transcript changes only: do not replay old HUD captions or automatic speech.
                await present(previous, true, token);
                continue;
            }
            if (input.TryRead(out var caption)) {
                if (canTranslate()) await translate(caption, token);
                else deferred.Enqueue(caption);
                await present(caption, false, token);
                continue;
            }
            if (input.Completion.IsCompleted) {
                await input.Completion;
                return; // Stopping in original-only mode never waits for a future mode switch.
            }
            await _wake.Reader.ReadAsync(token);
        }
    }
}
