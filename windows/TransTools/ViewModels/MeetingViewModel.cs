using System;
using System.Collections.ObjectModel;
using System.IO;
using System.Threading;
using System.Threading.Tasks;
using CommunityToolkit.Mvvm.ComponentModel;
using CommunityToolkit.Mvvm.Input;
using TransTools.Models;
using TransTools.Services.Audio;
using TransTools.Services.Speech;
using TransTools.Services.Translation;

namespace TransTools.ViewModels;

public partial class MeetingViewModel : ObservableObject
{
    private readonly WasapiAudioCaptureService _audioService = new();
    private readonly WhisperSttService _sttService = new();
    private readonly GoogleTranslationService _translationService = new();

    private readonly MemoryStream _accumulatedBuffer = new();
    private readonly object _bufferLock = new();
    private CancellationTokenSource? _processingCts;

    [ObservableProperty]
    private bool _isRecording;

    [ObservableProperty]
    private string _status = "Sẵn sàng ghi âm cuộc họp";

    [ObservableProperty]
    private float _audioLevel;

    [ObservableProperty]
    private string _currentLiveOriginal = string.Empty;

    [ObservableProperty]
    private string _currentLiveVietnamese = string.Empty;

    [ObservableProperty]
    private bool _captureSystemAudio = true;

    [ObservableProperty]
    private bool _captureMicrophone = false;

    public ObservableCollection<Caption> Captions { get; } = new();

    public event Action<string, string>? OnSubtitleUpdated;

    public MeetingViewModel()
    {
        _audioService.OnAudioLevelChanged += level => AudioLevel = level;
        
        // Feed captured 16kHz PCM audio chunks to buffer
        _audioService.OnAudio16kHzMonoChunk += chunk =>
        {
            if (!_isRecording) return;
            lock (_bufferLock)
            {
                _accumulatedBuffer.Write(chunk, 0, chunk.Length);
            }
        };

        _sttService.OnSegmentTranscribed += async (text, start, end) =>
        {
            if (string.IsNullOrWhiteSpace(text)) return;

            CurrentLiveOriginal = text;
            var vi = await _translationService.TranslateAsync(text, "auto", "vi");
            CurrentLiveVietnamese = vi;

            var caption = new Caption
            {
                Start = start,
                End = end,
                Original = text,
                Vietnamese = vi
            };

            System.Windows.Application.Current?.Dispatcher.Invoke(() =>
            {
                Captions.Insert(0, caption);
                OnSubtitleUpdated?.Invoke(text, vi);
            });
        };
    }

    [RelayCommand]
    public async Task StartRecordingAsync()
    {
        if (IsRecording) return;

        try
        {
            Status = "Đang khởi tạo bộ giải mã Whisper...";
            await _sttService.InitializeModelAsync();

            lock (_bufferLock)
            {
                _accumulatedBuffer.SetLength(0);
            }

            _processingCts = new CancellationTokenSource();
            _audioService.StartCapture(CaptureSystemAudio, CaptureMicrophone);
            IsRecording = true;
            Status = "Đang lắng nghe và dịch thời gian thực...";

            // Background loop to slice and process accumulated audio
            _ = Task.Run(() => AudioProcessingLoopAsync(_processingCts.Token));
        }
        catch (Exception ex)
        {
            Status = $"Lỗi: {ex.Message}";
        }
    }

    [RelayCommand]
    public void StopRecording()
    {
        if (!IsRecording) return;
        _processingCts?.Cancel();
        _audioService.StopCapture();
        IsRecording = false;
        Status = "Đã dừng phiên họp.";
    }

    [RelayCommand]
    public void ClearCaptions()
    {
        Captions.Clear();
        CurrentLiveOriginal = string.Empty;
        CurrentLiveVietnamese = string.Empty;
    }

    private async Task AudioProcessingLoopAsync(CancellationToken token)
    {
        // 16000 samples/sec * 2 bytes = 32000 bytes/sec
        // Process in ~2.5-second chunks = 80,000 bytes
        const int thresholdBytes = 80000;

        while (!token.IsCancellationRequested)
        {
            byte[]? chunkToProcess = null;
            lock (_bufferLock)
            {
                if (_accumulatedBuffer.Length >= thresholdBytes)
                {
                    chunkToProcess = _accumulatedBuffer.ToArray();
                    _accumulatedBuffer.SetLength(0);
                }
            }

            if (chunkToProcess != null && chunkToProcess.Length > 0)
            {
                using var stream = new MemoryStream(chunkToProcess);
                try
                {
                    await _sttService.ProcessAudioAsync(stream, token);
                }
                catch (OperationCanceledException)
                {
                    break;
                }
                catch (Exception ex)
                {
                    System.Diagnostics.Debug.WriteLine($"Lỗi giải mã audio Whisper: {ex.Message}");
                }
            }

            await Task.Delay(500, token).ConfigureAwait(false);
        }
    }
}
