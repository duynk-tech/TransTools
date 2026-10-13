using System.IO;
using System.Text.Json;
using System.Windows.Media.Imaging;

namespace TransTools.Services.Experience;

public sealed class DashboardAppearance
{
    private sealed record Preference(string Mode);
    private static string Folder => Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData), "TransTools", "Appearance");
    private static string PreferencePath => Path.Combine(Folder, "background.json");
    private static string PhotoPath => Path.Combine(Folder, "background-image");
    public string Mode { get; private set; } = "auto";
    public BitmapImage? Photo { get; private set; }
    public DashboardAppearance()
    {
        try {
            if (File.Exists(PreferencePath)) Mode = JsonSerializer.Deserialize<Preference>(File.ReadAllText(PreferencePath))?.Mode ?? "auto";
            if (Mode == "photo") Photo = LoadPhoto(PhotoPath);
            if (Mode is not ("auto" or "morning" or "noon" or "afternoon" or "night" or "mint" or "photo")) Mode = "auto";
        } catch { Mode = "auto"; Photo = null; }
    }
    public void Select(string mode)
    {
        if (mode is not ("auto" or "morning" or "noon" or "afternoon" or "night" or "mint")) throw new ArgumentException("Nền không được hỗ trợ.");
        Save(mode); Mode = mode; Photo = null;
    }
    public void SelectPhoto(string path)
    {
        // Fully decode once, release the input file and cap display memory.
        var image = LoadPhoto(path);
        Directory.CreateDirectory(Folder);
        File.Copy(path, PhotoPath + ".tmp", true);
        File.Move(PhotoPath + ".tmp", PhotoPath, true);
        Save("photo"); Photo = image; Mode = "photo";
    }
    private static BitmapImage LoadPhoto(string path)
    {
        using var input = File.OpenRead(path);
        var decoder = BitmapDecoder.Create(input, BitmapCreateOptions.PreservePixelFormat, BitmapCacheOption.OnDemand);
        var frame = decoder.Frames[0]; var width = frame.PixelWidth; var height = frame.PixelHeight;
        input.Position = 0;
        var image = new BitmapImage(); image.BeginInit(); image.CacheOption = BitmapCacheOption.OnLoad;
        if (Math.Max(width, height) > 2560) { if (width >= height) image.DecodePixelWidth = 2560; else image.DecodePixelHeight = 2560; }
        image.StreamSource = input; image.EndInit(); image.Freeze(); return image;
    }
    private static void Save(string mode)
    {
        Directory.CreateDirectory(Folder);
        File.WriteAllText(PreferencePath + ".tmp", JsonSerializer.Serialize(new Preference(mode)));
        File.Move(PreferencePath + ".tmp", PreferencePath, true);
    }
}
