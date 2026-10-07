using System;
using System.Collections.Generic;
using System.Threading.Tasks;
using Windows.Media.SpeechSynthesis;
using Windows.Storage.Streams;
using System.IO;
using NAudio.Wave;

namespace TransTools.Services.Speech;

public class WindowsMediaTtsService : IDisposable
{
    private readonly SpeechSynthesizer _synthesizer = new();

    public IReadOnlyList<VoiceInformation> GetAvailableVoices()
    {
        return SpeechSynthesizer.AllVoices;
    }

    public async Task SpeakAsync(string text, string? voiceId = null, string? language = null, System.Threading.CancellationToken token = default, double rate = 1)
    {
        if (string.IsNullOrWhiteSpace(text)) return;

        if (!string.IsNullOrWhiteSpace(voiceId))
        {
            foreach (var voice in SpeechSynthesizer.AllVoices)
            {
                if (voice.Id == voiceId)
                {
                    _synthesizer.Voice = voice;
                    break;
                }
            }
        }

        if (language != null) {
            var code = EdgeTtsService.VoiceForLanguage(language)[..2];
            var matching = SpeechSynthesizer.AllVoices.FirstOrDefault(v => v.Language.StartsWith(code + "-", StringComparison.OrdinalIgnoreCase));
            if (matching == null) throw new InvalidOperationException("Chưa cài giọng cơ bản cho ngôn ngữ này.");
            _synthesizer.Voice = matching;
        }
        _synthesizer.Options.SpeakingRate = Math.Clamp(rate, .7, 1.5);
        token.ThrowIfCancellationRequested();
        using var stream = await _synthesizer.SynthesizeTextToStreamAsync(text);
        using var netStream = stream.AsStreamForRead();
        using var waveStream = new WaveFileReader(netStream);
        using var waveOut = new WaveOutEvent();
        waveOut.Init(waveStream);
        token.ThrowIfCancellationRequested();
        waveOut.Play();

        while (waveOut.PlaybackState == PlaybackState.Playing)
        {
            await Task.Delay(50, token);
        }
    }
    public void Dispose() => _synthesizer.Dispose();
}
