using System;
using System.IO;
using System.Net.Http;
using System.Threading;
using System.Threading.Tasks;
using Whisper.net;
using Whisper.net.Ggml;

namespace TransTools.Services.Speech;

public class WhisperSttService : IDisposable
{
    private WhisperFactory? _factory;
    private WhisperProcessor? _processor;
    private readonly string _modelsDirectory;
    private string _currentModelPath = string.Empty;

    public event Action<string, double, double>? OnSegmentTranscribed;
    public event Action<string>? OnStatusChanged;

    public WhisperSttService()
    {
        var appData = Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData);
        _modelsDirectory = Path.Combine(appData, "TransTools", "models", "whisper");
        Directory.CreateDirectory(_modelsDirectory);
    }

    public async Task InitializeModelAsync(GgmlType modelType = GgmlType.Base, string language = "auto", IProgress<double>? progress = null)
    {
        var modelFileName = $"ggml-{modelType.ToString().ToLower()}.bin";
        _currentModelPath = Path.Combine(_modelsDirectory, modelFileName);

        if (!File.Exists(_currentModelPath))
        {
            OnStatusChanged?.Invoke($"Đang tải mô hình nhận diện giọng nói {modelType}...");
            await DownloadModelAsync(modelType, _currentModelPath, progress);
        }

        OnStatusChanged?.Invoke("Đang khởi tạo bộ giải mã Whisper...");
        _factory?.Dispose();
        _processor?.Dispose();

        _factory = WhisperFactory.FromPath(_currentModelPath);
        _processor = _factory.CreateBuilder()
            .WithLanguage(language == "auto" ? "auto" : language)
            .WithSegmentEventHandler(segment =>
            {
                OnSegmentTranscribed?.Invoke(segment.Text.Trim(), segment.Start.TotalSeconds, segment.End.TotalSeconds);
            })
            .Build();

        OnStatusChanged?.Invoke("Mô hình nhận diện giọng nói đã sẵn sàng.");
    }

    public async Task ProcessAudioAsync(Stream pcm16Stream, CancellationToken cancellationToken = default)
    {
        if (_processor == null) return;
        await foreach (var result in _processor.ProcessAsync(pcm16Stream, cancellationToken))
        {
            // Handled via segment event handler
        }
    }

    private static async Task DownloadModelAsync(GgmlType modelType, string destinationPath, IProgress<double>? progress = null)
    {
        using var modelStream = await WhisperGgmlDownloader.GetGgmlModelAsync(modelType);
        using var fileStream = File.Create(destinationPath);

        var buffer = new byte[81920];
        long totalBytesRead = 0;
        int bytesRead;

        while ((bytesRead = await modelStream.ReadAsync(buffer)) > 0)
        {
            await fileStream.WriteAsync(buffer.AsMemory(0, bytesRead));
            totalBytesRead += bytesRead;
            // Approximate base model size ~148MB
            progress?.Report(Math.Min(1.0, (double)totalBytesRead / (148 * 1024 * 1024)));
        }
    }

    public void Dispose()
    {
        _processor?.Dispose();
        _factory?.Dispose();
    }
}
