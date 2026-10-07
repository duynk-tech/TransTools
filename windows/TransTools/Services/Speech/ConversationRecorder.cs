using System.IO;
using System.Text;
using NAudio.Wave;
using TransTools.Services.Audio;
namespace TransTools.Services.Speech;

// One bounded utterance; audio remains in memory and is never saved with the chat.
public sealed class ConversationRecorder : IDisposable
{
    private const int MaximumBytes = 60 * 16000 * 2;
    private readonly object _sync = new();
    private readonly WasapiAudioCaptureService _capture = new();
    private readonly MemoryStream _audio = new();
    private bool _accepting;
    private UtteranceEndpoint _endpoint = new(2);
    public int SilenceDelaySeconds { get; init; } = 2;
    public event Action? LimitReached;
    public ConversationRecorder() { _capture.OnAudio16kHzMonoChunk += Append; }
    private void Append(byte[] chunk) {
        bool reached = false;
        lock (_sync) {
            if (!_accepting) return;
            var count = Math.Min(chunk.Length, MaximumBytes - (int)_audio.Length); count -= count % 2;
            _audio.Write(chunk, 0, count);
            if (_endpoint.Accept(chunk.AsSpan(0, count))) { _accepting = false; reached = true; }
            if (_audio.Length >= MaximumBytes) { _accepting = false; reached = true; }
        }
        if (reached) LimitReached?.Invoke();
    }
    public void Start() {
        lock (_sync) { _audio.SetLength(0); _endpoint = new UtteranceEndpoint(SilenceDelaySeconds); _accepting = true; }
        try { _capture.StartCapture(false, true); }
        catch { lock (_sync) _accepting = false; throw; }
    }
    public async Task<string> FinishAsync(string language, CancellationToken token) {
        _capture.StopCapture();
        byte[] bytes;
        lock (_sync) { _accepting = false; bytes = _audio.ToArray(); _audio.SetLength(0); }
        if (bytes.Length < 16000) throw new InvalidOperationException("Đoạn thu quá ngắn; hãy nói ít nhất nửa giây.");
        using var recognition = new WhisperSttService();
        var text = new StringBuilder();
        recognition.OnSegmentTranscribed += (segment, _, _) => { if (!string.IsNullOrWhiteSpace(segment)) text.Append(segment).Append(' '); };
        await recognition.InitializeModelAsync(language: language, cancellationToken: token);
        token.ThrowIfCancellationRequested();
        await Task.Run(async () => {
            using var wav = new MemoryStream();
            using (var writer = new WaveFileWriter(new NonClosingStream(wav), new WaveFormat(16000, 16, 1))) writer.Write(bytes, 0, bytes.Length);
            wav.Position = 0; await recognition.ProcessAudioAsync(wav, token);
        }, token);
        return text.ToString().Trim();
    }
    public void Dispose() { lock (_sync) _accepting = false; _capture.Dispose(); _audio.Dispose(); }
    private sealed class NonClosingStream(Stream inner) : Stream {
        public override bool CanRead => inner.CanRead; public override bool CanSeek => inner.CanSeek; public override bool CanWrite => inner.CanWrite;
        public override long Length => inner.Length; public override long Position { get => inner.Position; set => inner.Position = value; }
        public override void Flush() => inner.Flush(); public override int Read(byte[] b, int o, int n) => inner.Read(b,o,n);
        public override long Seek(long o, SeekOrigin origin) => inner.Seek(o,origin); public override void SetLength(long value) => inner.SetLength(value);
        public override void Write(byte[] b,int o,int n) => inner.Write(b,o,n);
    }
}
