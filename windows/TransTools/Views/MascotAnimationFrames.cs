using System.IO;
using System.Text.Json;
using System.Windows;
using System.Windows.Media.Imaging;
namespace TransTools.Views;
// Encoded resources are loaded once; only the playing clip is decoded and retained.
internal static class MascotAnimationFrames
{
    internal sealed record Clip(double Fps, byte[][] Encoded);
    private static readonly Dictionary<string, Clip> Clips = Load();
    internal static void WarmUp() { _ = Clips.Count; }
    private static Dictionary<string, Clip> Load()
    {
        var result = new Dictionary<string, Clip>();
        const string root = "pack://application:,,,/TransTools;component/Resources/Mascot/Activities/animations/";
        using var manifest = Application.GetResourceStream(new Uri(root + "manifest.json"))!.Stream;
        using var document = JsonDocument.Parse(manifest);
        foreach (var entry in document.RootElement.GetProperty("clips").EnumerateObject()) {
            var bytes = new List<byte[]>();
            foreach (var frame in entry.Value.GetProperty("frames").EnumerateArray()) {
                using var stream = Application.GetResourceStream(new Uri(root + frame.GetString()))!.Stream;
                using var buffer = new MemoryStream(); stream.CopyTo(buffer); bytes.Add(buffer.ToArray());
            }
            result[entry.Name] = new(entry.Value.GetProperty("fps").GetDouble(), bytes.ToArray());
        }
        return result;
    }
    internal static (double Fps, BitmapImage[] Frames)? Decode(string activity)
    {
        if (!Clips.TryGetValue(activity, out var clip)) return null;
        var frames = clip.Encoded.Select(bytes => {
            using var stream = new MemoryStream(bytes, false);
            var image = new BitmapImage(); image.BeginInit(); image.CacheOption = BitmapCacheOption.OnLoad;
            image.DecodePixelWidth = 192; image.StreamSource = stream; image.EndInit(); image.Freeze(); return image;
        }).ToArray();
        return (clip.Fps, frames);
    }
}
