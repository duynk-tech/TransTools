using System.Buffers.Binary;
using TransTools.Services.Audio;
namespace TransTools.Services.Speech;

public sealed class PersonalVoiceRecorder : IDisposable
{
    private readonly WasapiAudioCaptureService _capture = new();
    private readonly object _gate = new();
    private readonly byte[] _pcm = new byte[8 * 16000 * 2];
    private int _length;
    private bool _recording, _disposed;
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
            if (_recording) throw new InvalidOperationException("Đang thu giọng.");
            Array.Clear(_pcm); _length = 0; _recording = true;
        }
        try { _capture.StartCapture(false, true); }
        catch { lock (_gate) _recording = false; throw; }
    }
    public float[] Finish()
    {
        lock (_gate) { ObjectDisposedException.ThrowIf(_disposed, this); _recording = false; }
        _capture.StopCapture();
        lock (_gate) {
            if (_length < 3 * 16000 * 2) throw new InvalidOperationException("Hãy thu ít nhất 3 giây.");
            var samples = new float[_length / 2];
            for (var i = 0; i < samples.Length; i++) samples[i] = BinaryPrimitives.ReadInt16LittleEndian(_pcm.AsSpan(i * 2, 2)) / 32768f;
            Array.Clear(_pcm); _length = 0;
            return samples;
        }
    }
    public void Dispose()
    {
        lock (_gate) { if (_disposed) return; _disposed = true; _recording = false; Array.Clear(_pcm); _length = 0; }
        _capture.OnAudio16kHzMonoChunk -= Append;
        _capture.Dispose();
    }
}
