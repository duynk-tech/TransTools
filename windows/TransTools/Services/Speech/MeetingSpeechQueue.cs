using System.Threading.Channels;
namespace TransTools.Services.Speech;
public sealed record MeetingSpeechRequest(string Text, string Language, string DeviceId);
public sealed class MeetingSpeechQueue : IDisposable
{
    private readonly Channel<MeetingSpeechRequest> _queue = Channel.CreateBounded<MeetingSpeechRequest>(new BoundedChannelOptions(2) { SingleReader = true, SingleWriter = false, FullMode = BoundedChannelFullMode.DropOldest });
    private readonly CancellationTokenSource _cancel = new();
    private int _disposed;
    public Task Completion { get; }
    public MeetingSpeechQueue(Func<MeetingSpeechRequest, CancellationToken, Task> speak, Action<Exception> failed)
    {
        Completion = Task.Run(async () => {
            try { await foreach (var request in _queue.Reader.ReadAllAsync(_cancel.Token)) await speak(request, _cancel.Token); }
            catch (OperationCanceledException) when (_cancel.IsCancellationRequested) { }
            catch (Exception error) { _queue.Writer.TryComplete(); failed(error); }
        });
    }
    public bool Enqueue(MeetingSpeechRequest request) => Volatile.Read(ref _disposed) == 0 && !string.IsNullOrWhiteSpace(request.Text) && _queue.Writer.TryWrite(request);
    public void Dispose()
    {
        if (Interlocked.Exchange(ref _disposed, 1) != 0) return;
        _queue.Writer.TryComplete(); _cancel.Cancel();
        _ = Completion.ContinueWith(_ => _cancel.Dispose(), TaskScheduler.Default);
    }
}
