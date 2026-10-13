using System.IO;
using System.Text.Json;
using CommunityToolkit.Mvvm.ComponentModel;
namespace TransTools.Services.Experience;

public partial class AssistantIdentity : ObservableObject
{
    public static AssistantIdentity Shared { get; } = new();
    private readonly string _path = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData), "TransTools", "assistant.json");
    [ObservableProperty] private string _customName = "";
    public string DisplayName => string.IsNullOrWhiteSpace(CustomName) ? "Chip Chip" : CustomName;
    partial void OnCustomNameChanged(string value) => OnPropertyChanged(nameof(DisplayName));
    private AssistantIdentity()
    {
        try { if (File.Exists(_path)) CustomName = JsonSerializer.Deserialize<string>(File.ReadAllText(_path)) ?? ""; }
        catch (Exception ex) when (ex is IOException or UnauthorizedAccessException or JsonException) { }
    }
    public void Save(string name)
    {
        name = name.Trim();
        if (name.Length > 40 || name.Any(char.IsControl)) throw new InvalidOperationException("Tên trợ lý cần tối đa 40 ký tự, không có xuống dòng.");
        Directory.CreateDirectory(Path.GetDirectoryName(_path)!);
        File.WriteAllText(_path + ".tmp", JsonSerializer.Serialize(name)); File.Move(_path + ".tmp", _path, true);
        CustomName = name;
    }
}
