using NAudio.CoreAudioApi;
using NAudio.Wave;
namespace TransTools.Services.Audio;
public sealed record PlaybackDevice(string Id, string Name);
public static class PlaybackDevices
{
    public static PlaybackDevice[] List()
    {
        using var enumerator = new MMDeviceEnumerator();
        var devices = enumerator.EnumerateAudioEndPoints(DataFlow.Render, DeviceState.Active);
        return devices.Select(device => { using (device) return new PlaybackDevice(device.ID, device.FriendlyName); }).ToArray();
    }
    public static string DefaultId()
    {
        using var enumerator = new MMDeviceEnumerator(); using var device = enumerator.GetDefaultAudioEndpoint(DataFlow.Render, Role.Multimedia); return device.ID;
    }
    public static bool CanRead(bool systemCapture, string? capturedId, string? playbackId) => !string.IsNullOrWhiteSpace(playbackId) && (!systemCapture || (!string.IsNullOrWhiteSpace(capturedId) && !string.Equals(capturedId, playbackId, StringComparison.OrdinalIgnoreCase)));
    public static async Task PlayAsync(WaveStream audio, string deviceId, CancellationToken token)
    {
        using var enumerator = new MMDeviceEnumerator(); using var device = enumerator.GetDevice(deviceId);
        if (device.State != DeviceState.Active) throw new InvalidOperationException("Thiết bị nghe đã ngắt kết nối.");
        using var output = new WasapiOut(device, AudioClientShareMode.Shared, true, 100);
        var stopped = new TaskCompletionSource<Exception?>(TaskCreationOptions.RunContinuationsAsynchronously);
        output.PlaybackStopped += (_, e) => stopped.TrySetResult(e.Exception);
        token.ThrowIfCancellationRequested(); output.Init(audio); output.Play();
        try { var error = await stopped.Task.WaitAsync(token); if (error != null) throw new InvalidOperationException("Không phát được giọng đọc trên thiết bị đã chọn.", error); }
        finally { output.Stop(); }
    }
}
