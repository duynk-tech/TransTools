using System;
using System.Diagnostics;
using System.IO;
using CommunityToolkit.Mvvm.ComponentModel;
using CommunityToolkit.Mvvm.Input;
using TransTools.Services.Storage;

namespace TransTools.ViewModels;

public partial class SettingsViewModel : ObservableObject
{
    private readonly SecureCredentialStore _credentialStore = new();
    private readonly string _appDataDir;

    [ObservableProperty]
    private string _openAiKey = string.Empty;

    [ObservableProperty]
    private string _geminiKey = string.Empty;

    [ObservableProperty]
    private string _claudeKey = string.Empty;

    [ObservableProperty]
    private string _deepSeekKey = string.Empty;

    [ObservableProperty]
    private string _ollamaEndpoint = "http://localhost:11434";

    [ObservableProperty]
    private string _cacheSize = "0 MB";

    [ObservableProperty]
    private string _status = "Sẵn sàng";

    public SettingsViewModel()
    {
        var appData = Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData);
        _appDataDir = Path.Combine(appData, "TransTools");
        Directory.CreateDirectory(_appDataDir);

        LoadSavedSettings();
        CalculateCacheSize();
    }

    private void LoadSavedSettings()
    {
        OpenAiKey = _credentialStore.LoadApiKey("openai");
        GeminiKey = _credentialStore.LoadApiKey("gemini");
        ClaudeKey = _credentialStore.LoadApiKey("claude");
        DeepSeekKey = _credentialStore.LoadApiKey("deepseek");
    }

    [RelayCommand]
    public void SaveAllKeys()
    {
        _credentialStore.SaveApiKey("openai", OpenAiKey);
        _credentialStore.SaveApiKey("gemini", GeminiKey);
        _credentialStore.SaveApiKey("claude", ClaudeKey);
        _credentialStore.SaveApiKey("deepseek", DeepSeekKey);

        Status = "Đã mã hóa và lưu tất cả API Key an toàn bằng Windows DPAPI!";
    }

    [RelayCommand]
    public void OpenDataFolder()
    {
        if (Directory.Exists(_appDataDir))
        {
            Process.Start(new ProcessStartInfo("explorer.exe", _appDataDir) { UseShellExecute = true });
        }
    }

    [RelayCommand]
    public void ClearCache()
    {
        try
        {
            var tempDir = Path.Combine(_appDataDir, "temp");
            if (Directory.Exists(tempDir))
            {
                Directory.Delete(tempDir, true);
            }
            CalculateCacheSize();
            Status = "Đã dọn sạch bộ nhớ đệm thành công!";
        }
        catch (Exception ex)
        {
            Status = $"Lỗi dọn cache: {ex.Message}";
        }
    }

    private void CalculateCacheSize()
    {
        try
        {
            long size = 0;
            var dirInfo = new DirectoryInfo(_appDataDir);
            foreach (var file in dirInfo.GetFiles("*", SearchOption.AllDirectories))
            {
                size += file.Length;
            }
            CacheSize = $"{Math.Round((double)size / (1024 * 1024), 2)} MB";
        }
        catch
        {
            CacheSize = "Chưa xác định";
        }
    }
}
