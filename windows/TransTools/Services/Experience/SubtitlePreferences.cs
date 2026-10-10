using System.IO;
using System.Text.Json;
namespace TransTools.Services.Experience;
public sealed class SubtitlePreferences
{
    private static string PathName => Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData), "TransTools", "subtitle-appearance.json");
    public static SubtitlePreferences Shared { get; } = Load();
    public static string[] Domains { get; } = ["Thông dụng", "Kinh doanh & Hội họp", "Công nghệ thông tin", "Y tế & Sinh học", "Kinh tế & Tài chính", "Du lịch & Khách sạn", "Pháp luật"];
    public string DisplayMode { get; set; } = "bilingual";
    public string Domain { get; set; } = "Thông dụng";
    public event Action? Changed;
    public bool Light { get; set; }
    public bool ShowOriginal { get; set; } = true;
    public bool ShowContext { get; set; } = true;
    public bool ShowNext { get; set; } = true;
    public bool ShowMascot { get; set; }
    public bool Side { get; set; }
    public bool Locked { get; set; }
    public double FontSize { get; set; } = 18;
    public string Pacing { get; set; } = "balanced";
    private static SubtitlePreferences Load()
    {
        try {
            var value = File.Exists(PathName) ? JsonSerializer.Deserialize<SubtitlePreferences>(File.ReadAllText(PathName)) ?? new SubtitlePreferences() : new SubtitlePreferences();
            if (value.DisplayMode is not ("bilingual" or "original" or "translation")) value.DisplayMode = "bilingual";
            if (!Domains.Contains(value.Domain)) value.Domain = "Thông dụng";
            value.FontSize = Math.Clamp(value.FontSize, 15, 24);
            if (value.Pacing is not ("contextual" or "balanced" or "fast")) value.Pacing = "balanced";
            return value;
        } catch { return new(); }
    }
    public void Save()
    {
        Directory.CreateDirectory(Path.GetDirectoryName(PathName)!);
        File.WriteAllText(PathName + ".tmp", JsonSerializer.Serialize(this)); File.Move(PathName + ".tmp", PathName, true);
        Changed?.Invoke();
    }
}
