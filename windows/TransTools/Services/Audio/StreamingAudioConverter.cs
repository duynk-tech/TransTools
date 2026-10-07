using NAudio.Wave;
using NAudio.Wave.SampleProviders;
namespace TransTools.Services.Audio;
// Keep the resampler state for the complete capture session, not for each callback.
public sealed class StreamingAudioConverter
{
    private readonly BufferedWaveProvider _input;
    private readonly WdlResamplingSampleProvider _resampler;
    private readonly float[] _samples = new float[4096];
    public StreamingAudioConverter(WaveFormat format) {
        _input = new BufferedWaveProvider(format) { ReadFully = false, BufferDuration = TimeSpan.FromSeconds(5), DiscardOnBufferOverflow = false };
        _resampler = new WdlResamplingSampleProvider(new Downmix(_input.ToSampleProvider()), 16000);
    }
    public byte[] Convert(byte[] buffer, int count) {
        _input.AddSamples(buffer, 0, count);
        using var output = new System.IO.MemoryStream();
        int read;
        while ((read = _resampler.Read(_samples, 0, _samples.Length)) > 0) {
            for (var i = 0; i < read; i++) {
                var value = float.IsFinite(_samples[i]) ? (short)Math.Clamp((int)(_samples[i] * 32767f), short.MinValue, short.MaxValue) : (short)0;
                output.WriteByte((byte)value); output.WriteByte((byte)(value >> 8));
            }
        }
        return output.ToArray();
    }
    private sealed class Downmix(ISampleProvider source) : ISampleProvider
    {
        private float[] _buffer = Array.Empty<float>();
        public WaveFormat WaveFormat { get; } = WaveFormat.CreateIeeeFloatWaveFormat(source.WaveFormat.SampleRate, 1);
        public int Read(float[] buffer, int offset, int count) {
            var channels = source.WaveFormat.Channels;
            if (_buffer.Length < count * channels) _buffer = new float[count * channels];
            var read = source.Read(_buffer, 0, count * channels) / channels;
            for (var i = 0; i < read; i++) { float sum = 0; for (var channel = 0; channel < channels; channel++) sum += _buffer[i * channels + channel]; buffer[offset + i] = sum / channels; }
            return read;
        }
    }
}
