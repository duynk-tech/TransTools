using System;
using System.Collections.Generic;
using System.Threading.Tasks;
using Windows.Media.SpeechSynthesis;
using Windows.Storage.Streams;
using System.IO;
using NAudio.Wave;

namespace TransTools.Services.Speech;

public class WindowsMediaTtsService
{
    private readonly SpeechSynthesizer _synthesizer = new();

    public IReadOnlyList<VoiceInformation> GetAvailableVoices()
    {
        return SpeechSynthesizer.AllVoices;
    }

    public async Task SpeakAsync(string text, string? voiceId = null)
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

        using var stream = await _synthesizer.SynthesizeTextToStreamAsync(text);
        using var netStream = stream.AsStreamForRead();
        using var waveStream = new WaveFileReader(netStream);
        using var waveOut = new WaveOutEvent();
        waveOut.Init(waveStream);
        waveOut.Play();

        while (waveOut.PlaybackState == PlaybackState.Playing)
        {
            await Task.Delay(100);
        }
    }
}
