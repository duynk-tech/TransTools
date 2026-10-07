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
    private StreamingAudioConverter? _converter;
    private readonly object _conversionLock = new();

    public event Action<byte[]>? OnAudio16kHzMonoChunk;
    public event Action<float>? OnAudioLevelChanged;

    public bool IsCapturing => _isCapturing;

    public void StartCapture(bool captureSystemAudio = true, bool captureMicrophone = false)
    {
        if (_isCapturing) return;
        if (captureSystemAudio == captureMicrophone) throw new InvalidOperationException("Chọn một nguồn thu âm.");

        try
        {
            if (captureSystemAudio)
            {
                _loopbackCapture = new WasapiLoopbackCapture();
                _loopbackCapture.DataAvailable += OnLoopbackDataAvailable;
                _converter = new StreamingAudioConverter(_loopbackCapture.WaveFormat);
                _loopbackCapture.StartRecording();
            }

            if (captureMicrophone)
            {
                _micCapture = new WasapiCapture();
                _micCapture.DataAvailable += OnMicDataAvailable;
                _converter = new StreamingAudioConverter(_micCapture.WaveFormat);
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
        lock (_conversionLock) _converter = null;
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
        byte[] pcm16;
        lock (_conversionLock) { if (_converter == null) return; pcm16 = _converter.Convert(buffer, count); }
        if (pcm16.Length == 0) return;
        double sum = 0;
        for (var i = 0; i + 1 < pcm16.Length; i += 2) { var sample = BitConverter.ToInt16(pcm16, i) / 32768.0; sum += sample * sample; }
        var rms = (float)Math.Sqrt(sum / (pcm16.Length / 2));
        OnAudioLevelChanged?.Invoke(Math.Clamp(rms * 4, 0, 1));
        OnAudio16kHzMonoChunk?.Invoke(pcm16);
    }

    public void Dispose()
    {
        StopCapture();
    }
}
