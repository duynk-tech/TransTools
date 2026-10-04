using System;
using System.IO;
using NAudio.Wave;
using NAudio.CoreAudioApi;
using NAudio.Wave.SampleProviders;

namespace TransTools.Services.Audio;

public class WasapiAudioCaptureService : IDisposable
{
    private WasapiLoopbackCapture? _loopbackCapture;
    private WasapiCapture? _micCapture;
    private bool _isCapturing;

    public event Action<byte[]>? OnAudio16kHzMonoChunk;
    public event Action<float>? OnAudioLevelChanged;

    public bool IsCapturing => _isCapturing;

    public void StartCapture(bool captureSystemAudio = true, bool captureMicrophone = false)
    {
        if (_isCapturing) return;

        try
        {
            if (captureSystemAudio)
            {
                _loopbackCapture = new WasapiLoopbackCapture();
                _loopbackCapture.DataAvailable += OnLoopbackDataAvailable;
                _loopbackCapture.StartRecording();
            }

            if (captureMicrophone)
            {
                _micCapture = new WasapiCapture();
                _micCapture.DataAvailable += OnMicDataAvailable;
                _micCapture.StartRecording();
            }

            _isCapturing = true;
        }
        catch (Exception ex)
        {
            StopCapture();
            throw new InvalidOperationException($"Lỗi khởi tạo thu âm WASAPI: {ex.Message}", ex);
        }
    }

    public void StopCapture()
    {
        if (_loopbackCapture != null)
        {
            _loopbackCapture.DataAvailable -= OnLoopbackDataAvailable;
            _loopbackCapture.StopRecording();
            _loopbackCapture.Dispose();
            _loopbackCapture = null;
        }

        if (_micCapture != null)
        {
            _micCapture.DataAvailable -= OnMicDataAvailable;
            _micCapture.StopRecording();
            _micCapture.Dispose();
            _micCapture = null;
        }

        _isCapturing = false;
    }

    private void OnLoopbackDataAvailable(object? sender, WaveInEventArgs e)
    {
        if (_loopbackCapture == null || e.BytesRecorded == 0) return;
        ProcessAudioBuffer(e.Buffer, e.BytesRecorded, _loopbackCapture.WaveFormat);
    }

    private void OnMicDataAvailable(object? sender, WaveInEventArgs e)
    {
        if (_micCapture == null || e.BytesRecorded == 0) return;
        ProcessAudioBuffer(e.Buffer, e.BytesRecorded, _micCapture.WaveFormat);
    }

    private void ProcessAudioBuffer(byte[] buffer, int count, WaveFormat format)
    {
        // Convert to 16kHz, 16-bit, Mono PCM required by Whisper
        using var inputStream = new MemoryStream(buffer, 0, count);
        using var rawSource = new RawSourceWaveStream(inputStream, format);
        
        var targetFormat = new WaveFormat(16000, 16, 1);
        using var resampler = new MediaFoundationResampler(rawSource, targetFormat)
        {
            ResamplerQuality = 60
        };

        var convertedBytes = new byte[count];
        int read = resampler.Read(convertedBytes, 0, convertedBytes.Length);
        if (read > 0)
        {
            var pcm16 = new byte[read];
            Array.Copy(convertedBytes, pcm16, read);

            // Compute RMS level for volume meters
            float sum = 0;
            for (int i = 0; i < read; i += 2)
            {
                short sample = BitConverter.ToInt16(pcm16, i);
                sum += sample * sample;
            }
            float rms = (float)Math.Sqrt(sum / (read / 2)) / 32768f;
            OnAudioLevelChanged?.Invoke(Math.Clamp(rms * 4f, 0f, 1f));

            OnAudio16kHzMonoChunk?.Invoke(pcm16);
        }
    }

    public void Dispose()
    {
        StopCapture();
    }
}
