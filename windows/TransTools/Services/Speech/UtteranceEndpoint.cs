namespace TransTools.Services.Speech;

// Counts PCM time, not wall-clock time: UI scheduling cannot shorten a pause.
public sealed class UtteranceEndpoint(int delaySeconds)
{
    private readonly int _requiredBytes = Math.Clamp(delaySeconds, 1, 10) * 32000;
    private bool _heardSpeech;
    private int _silentBytes;
    public bool Accept(ReadOnlySpan<byte> pcm)
    {
        if (pcm.Length < 2) return false;
        double energy = 0;
        for (var i = 0; i + 1 < pcm.Length; i += 2) {
            var sample = (short)(pcm[i] | (pcm[i + 1] << 8)) / 32768.0;
            energy += sample * sample;
        }
        if (Math.Sqrt(energy / (pcm.Length / 2)) >= 0.008) { _heardSpeech = true; _silentBytes = 0; }
        else if (_heardSpeech) _silentBytes += pcm.Length - pcm.Length % 2;
        return _heardSpeech && _silentBytes >= _requiredBytes;
    }
}
