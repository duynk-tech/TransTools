using System.Buffers.Binary;
using TransTools.Services.Audio;
namespace TransTools.Services.Speech;

public sealed class PersonalVoiceRecorder : IDisposable
{
    private readonly WasapiAudioCaptureService _capture = new();
    private readonly object _gate = new();
    private readonly byte[] _pcm = new byte[8 * 16000 * 2];
    private int _length;
    private bool _recording, _started, _disposed;
    public event Action? LimitReached;
    public PersonalVoiceRecorder() => _capture.OnAudio16kHzMonoChunk += Append;
    private void Append(byte[] chunk)
    {
        bool reached;
        lock (_gate) {
            if (!_recording || _disposed) return;
            var count = Math.Min(chunk.Length, _pcm.Length - _length) & ~1;
            chunk.AsSpan(0, count).CopyTo(_pcm.AsSpan(_length));
            _length += count;
            reached = _length == _pcm.Length;
            if (reached) _recording = false;
        }
        // The UI must marshal this event before stopping capture.
        if (reached) LimitReached?.Invoke();
    }
    public void Start()
    {
        lock (_gate) {
            ObjectDisposedException.ThrowIf(_disposed, this);
            if (_started) throw new InvalidOperationException("Dừng bản thu hiện tại trước khi thu lại.");
            Array.Clear(_pcm); _length = 0; _recording = _started = true;
        }
        try { _capture.StartCapture(false, true); }
        catch { lock (_gate) { _recording = _started = false; Array.Clear(_pcm); _length = 0; } throw; }
    }
    public float[] Finish()
    {
        lock (_gate) {
            ObjectDisposedException.ThrowIf(_disposed, this);
            if (!_started) throw new InvalidOperationException("Chưa bắt đầu thu giọng.");
            _recording = false;
        }
        _capture.StopCapture();
        lock (_gate) {
            try {
                ObjectDisposedException.ThrowIf(_disposed, this);
                if (_length < 3 * 16000 * 2) throw new InvalidOperationException("Hãy thu ít nhất 3 giây.");
                var samples = new float[_length / 2];
                for (var i = 0; i < samples.Length; i++) samples[i] = BinaryPrimitives.ReadInt16LittleEndian(_pcm.AsSpan(i * 2, 2)) / 32768f;
                return samples;
            } finally { Array.Clear(_pcm); _length = 0; _started = false; }
        }
    }
    public void Dispose()
    {
        lock (_gate) { if (_disposed) return; _disposed = true; _recording = _started = false; Array.Clear(_pcm); _length = 0; }
        _capture.OnAudio16kHzMonoChunk -= Append;
        _capture.Dispose();
    }
}
