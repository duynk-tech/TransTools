using System;
using System.Diagnostics;
using System.IO;
using System.Collections.ObjectModel;
using System.Threading.Tasks;
using TransTools.Services.AI;
using TransTools.Services.Speech;
using CommunityToolkit.Mvvm.ComponentModel;
using CommunityToolkit.Mvvm.Input;
using TransTools.Services.Storage;

namespace TransTools.ViewModels;

public partial class SettingsViewModel : ObservableObject
{
    public string[] TranslationDomains => TransTools.Services.Experience.SubtitlePreferences.Domains;
    public string[] SubtitlePacingOptions { get; } = ["Nhanh", "Cân bằng", "Đủ ngữ cảnh"];
    public double[] SubtitleFontSizes { get; } = [15, 18, 21, 24];
    [ObservableProperty] private string _translationDomain = "Thông dụng";
    [ObservableProperty] private string _subtitlePacing = "Cân bằng";
    [ObservableProperty] private double _subtitleFontSize = 18;
    [ObservableProperty] private bool _subtitleLight;
    [ObservableProperty] private bool _subtitleOriginal = true;
    [ObservableProperty] private bool _subtitleContext = true;
    [ObservableProperty] private bool _subtitleNext = true;
    [ObservableProperty] private bool _subtitleMascot;
    [ObservableProperty] private bool _subtitleSide;
    private void LoadSubtitlePreferences()
    {
        var p = TransTools.Services.Experience.SubtitlePreferences.Shared;
        TranslationDomain = p.Domain; SubtitlePacing = p.Pacing == "fast" ? "Nhanh" : p.Pacing == "contextual" ? "Đủ ngữ cảnh" : "Cân bằng";
        SubtitleFontSize = p.FontSize; SubtitleLight = p.Light; SubtitleOriginal = p.ShowOriginal; SubtitleContext = p.ShowContext;
        SubtitleNext = p.ShowNext; SubtitleMascot = p.ShowMascot; SubtitleSide = p.Side;
    }
    [RelayCommand] private void SaveSubtitlePreferences()
    {
        try {
            var p = TransTools.Services.Experience.SubtitlePreferences.Shared;
            p.Domain = TranslationDomains.Contains(TranslationDomain) ? TranslationDomain : "Thông dụng";
            p.Pacing = SubtitlePacing == "Nhanh" ? "fast" : SubtitlePacing == "Đủ ngữ cảnh" ? "contextual" : "balanced";
            p.FontSize = Math.Clamp(SubtitleFontSize, 15, 24); p.Light = SubtitleLight; p.ShowOriginal = SubtitleOriginal; p.ShowContext = SubtitleContext;
            p.ShowNext = SubtitleNext; p.ShowMascot = SubtitleMascot; p.Side = SubtitleSide; p.Save(); Status = "Đã lưu tùy chỉnh dịch và phụ đề";
        } catch (Exception ex) { Status = "Chưa lưu được tùy chỉnh: " + ex.Message; }
    }
    [RelayCommand] private void OpenMicrophonePrivacy() => OpenWindowsSetting("ms-settings:privacy-microphone");
    [RelayCommand] private void OpenSoundSettings() => OpenWindowsSetting("ms-settings:sound");
    private void OpenWindowsSetting(string uri) { try { Process.Start(new ProcessStartInfo(uri) { UseShellExecute = true }); } catch (Exception ex) { Status = ex.Message; } }
    [ObservableProperty] private string _assistantName = TransTools.Services.Experience.AssistantIdentity.Shared.CustomName;
    [RelayCommand] private void SaveAssistantName()
    {
        try { TransTools.Services.Experience.AssistantIdentity.Shared.Save(AssistantName); Status = "Đã lưu tên trợ lý"; }
        catch (Exception ex) { Status = ex.Message; }
    }
    private TransTools.Services.Updates.WindowsRelease? _release;
    private CancellationTokenSource? _updateDownload;
    [ObservableProperty] private string _updateStatus = "Kiểm tra phiên bản mới khi bạn cần.";
    [ObservableProperty] private string _releaseNotes = "";
    [ObservableProperty] private bool _isUpdating;
    [ObservableProperty] private bool _canInstallUpdate;
    [ObservableProperty] private double _updateProgress;
    [RelayCommand] private async Task CheckUpdateAsync() {
        if (IsUpdating) return; IsUpdating = true; CanInstallUpdate = false;
        try {
            UpdateStatus = "Đang kiểm tra...";
            _release = await TransTools.Services.Updates.WindowsUpdater.CheckAsync(CancellationToken.None);
            var current = typeof(SettingsViewModel).Assembly.GetName().Version ?? new Version(0,0,0);
            var latest = Version.Parse(_release.Version); ReleaseNotes = _release.Notes;
            CanInstallUpdate = latest > current && _release.Installer != null;
            UpdateStatus = latest <= current ? "Bạn đang dùng phiên bản mới nhất." : CanInstallUpdate ? "Có bản cập nhật v" + _release.Version : "Chưa có bộ cài Windows cho phiên bản này.";
        } catch (Exception ex) { UpdateStatus = "Không kiểm tra được: " + ex.Message; }
        finally { IsUpdating = false; }
    }
    [RelayCommand] private void CancelUpdate() => _updateDownload?.Cancel();
    [RelayCommand] private async Task InstallUpdateAsync() {
        if (IsUpdating || !CanInstallUpdate || _release == null) return;
        if (_meetingBusy() || IsInstallingVoice) { UpdateStatus = "Kết thúc phiên làm việc và tải mô hình trước khi cập nhật."; return; }
        IsUpdating = true; _updateDownload = new();
        try {
            UpdateStatus = "Đang tải bộ cài..."; UpdateProgress = 0;
            var path = await TransTools.Services.Updates.WindowsUpdater.DownloadAsync(_release, new Progress<double>(value => UpdateProgress = value), _updateDownload.Token);
            UpdateStatus = "Đã kiểm tra bộ cài. Lưu công việc trước khi tiếp tục.";
            if (System.Windows.MessageBox.Show("Bộ cài đã được kiểm tra SHA-256. Mở bộ cài cập nhật? Hãy lưu công việc trước khi tiếp tục.", "Cập nhật Trans Tools", System.Windows.MessageBoxButton.YesNo) == System.Windows.MessageBoxResult.Yes)
                Process.Start(new ProcessStartInfo(path) { UseShellExecute = true });
        } catch (OperationCanceledException) { UpdateStatus = "Đã hủy tải cập nhật."; }
        catch (Exception ex) { UpdateStatus = "Không cập nhật được: " + ex.Message; }
        finally { IsUpdating = false; _updateDownload.Dispose(); _updateDownload = null; }
    }
    public int[] BreakIntervals { get; } = { 25, 45, 60, 90 };
    [ObservableProperty] private bool _breakReminderEnabled = TransTools.Services.Experience.BreakReminder.Shared.Enabled;
    [ObservableProperty] private int _breakMinutes = TransTools.Services.Experience.BreakReminder.Shared.Minutes;
    [RelayCommand] private void SaveBreakReminder() {
        try { TransTools.Services.Experience.BreakReminder.Shared.Configure(BreakReminderEnabled, BreakMinutes); Status = "Đã lưu nhịp nhắc nghỉ."; }
        catch (Exception ex) { Status = "Không lưu được: " + ex.Message; }
    }
    private readonly SecureCredentialStore _credentialStore = new();
    private readonly string _appDataDir;
    private readonly Func<bool> _meetingBusy;
    public ObservableCollection<StorageEntry> StorageGroups { get; } = new();
    [ObservableProperty] private StorageEntry? _selectedStorage;
    [ObservableProperty] private bool _isScanningStorage;
    [RelayCommand] private async Task RefreshStorageAsync()
    {
        if (IsScanningStorage) return; IsScanningStorage = true;
        try {
            var entries = await Task.Run(() => StorageInventory.Entries(_appDataDir).Select(StorageInventory.Scan).Where(e => e.Bytes > 0 || e.Error != null).ToList());
            StorageGroups.Clear(); foreach (var entry in entries) StorageGroups.Add(entry);
            CacheSize = $"{entries.Sum(e => e.Bytes) / 1048576.0:F1} MB";
        } finally { IsScanningStorage = false; }
    }
    [RelayCommand] private async Task RemoveStorageAsync()
    {
        var entry = SelectedStorage;
        if (entry == null || !entry.Removable) { Status = "Chọn nhóm mô hình hoặc cache có thể dọn."; return; }
        if (IsInstallingVoice || IsUpdating || _meetingBusy()) { Status = "Kết thúc cuộc họp và tải mô hình trước khi dọn dữ liệu."; return; }
        if (System.Windows.MessageBox.Show($"Chuyển {entry.Title} vào Thùng rác? Cần tải hoặc nhập lại để sử dụng tiếp.", "Dọn dữ liệu", System.Windows.MessageBoxButton.YesNo) != System.Windows.MessageBoxResult.Yes) return;
        try {
            if (entry.Id == "supertonic") await VoiceService.Shared.RemoveModelAsync();
            else if (entry.Id == "vieneu") await VoiceService.Shared.RemoveModelAsync(vieNeu: true);
            else {
                if (entry.Id == "recordings") RecordingPlayer.Stop();
                if (Directory.Exists(entry.Path)) Microsoft.VisualBasic.FileIO.FileSystem.DeleteDirectory(entry.Path, Microsoft.VisualBasic.FileIO.UIOption.OnlyErrorDialogs, Microsoft.VisualBasic.FileIO.RecycleOption.SendToRecycleBin);
            }
            LocalVoiceStatus = VoiceService.Shared.IsInstalled ? "Supertonic 3 đã cài" : "Chưa tải Supertonic 3";
            Status = "Đã chuyển vào Thùng rác; dữ liệu học tập được giữ lại."; await RefreshStorageAsync();
        } catch (Exception ex) { Status = "Không dọn được: " + ex.Message; }
    }

    [ObservableProperty] private string _localVoiceStatus = VoiceService.Shared.IsInstalled ? "Supertonic 3 đã cài" : "Chưa tải Supertonic 3";
    [ObservableProperty] private bool _isInstallingVoice;
    private CancellationTokenSource? _installation;
    [RelayCommand] private void CancelVoiceInstall() => _installation?.Cancel();
    [RelayCommand] private async Task InstallVoiceAsync()
    {
        if (IsInstallingVoice) return;
        if (new TransTools.Views.LicenseWindow("Supertonic 3", VoiceService.ResourceText("SpeechNative/Supertonic-Model-OpenRAIL.txt")).ShowDialog() != true) return;
        IsInstallingVoice = true; _installation = new CancellationTokenSource();
        try { await VoiceService.Shared.InstallAsync(new Progress<string>(message => LocalVoiceStatus = message), _installation.Token); }
        catch (OperationCanceledException) { LocalVoiceStatus = "Đã hủy tải; có thể tiếp tục sau."; }
        catch (Exception ex) { LocalVoiceStatus = ex.Message; }
        finally { IsInstallingVoice = false; _installation?.Dispose(); _installation = null; CalculateCacheSize(); }
    }
    public bool HasVieNeuProcessor => VoiceService.HasVieNeuProcessor;
    [RelayCommand] private async Task InstallVieNeuAsync()
    {
        if (IsInstallingVoice) return;
        if (!HasVieNeuProcessor) { LocalVoiceStatus = "Bản app chưa có bộ chuyển âm native; cần build Windows với SEA-G2P."; return; }
        if (new TransTools.Views.LicenseWindow("VieNeu v3 Turbo", VoiceService.ResourceText("SpeechNative/VieNeu-LICENSE.txt")).ShowDialog() != true) return;
        IsInstallingVoice = true; _installation = new CancellationTokenSource();
        try { await VoiceService.Shared.InstallAsync(new Progress<string>(message => LocalVoiceStatus = message), _installation.Token, vieNeu: true); }
        catch (OperationCanceledException) { LocalVoiceStatus = "Đã hủy tải VieNeu"; }
        catch (Exception ex) { LocalVoiceStatus = ex.Message; }
        finally { IsInstallingVoice = false; _installation.Dispose(); _installation = null; CalculateCacheSize(); }
    }
    [RelayCommand] private void OpenVoiceLicense() => Process.Start(new ProcessStartInfo("https://huggingface.co/supertone-oss-archive/supertonic-3/blob/main/LICENSE") { UseShellExecute = true });
    [RelayCommand] private async Task RemoveVoiceAsync()
    {
        if (IsInstallingVoice) return;
        try { await VoiceService.Shared.RemoveModelAsync(); LocalVoiceStatus = "Đã chuyển mô hình vào Thùng rác"; CalculateCacheSize(); }
        catch (Exception ex) { LocalVoiceStatus = "Không gỡ được: " + ex.Message; }
    }

    [RelayCommand] private async Task ImportRecordingsAsync()
    {
        var dialog = new Microsoft.Win32.OpenFileDialog { Filter = "Bộ bản ghi (manifest.json)|manifest.json" };
        if (dialog.ShowDialog() != true) return;
        try { Status = "Đang kiểm tra bản ghi..."; await RecordingImporter.ImportAsync(dialog.FileName, CancellationToken.None); Status = "Đã nhập bộ phát âm offline"; CalculateCacheSize(); }
        catch (Exception ex) { Status = ex.Message; }
    }

    public string[] Providers { get; } = { "openai", "gemini", "claude", "deepseek" };
    public ObservableCollection<string> AvailableModels { get; } = new();
    [ObservableProperty] private string _activeProvider = "openai";
    [ObservableProperty] private string _catalogModel = "";
    [ObservableProperty] private bool _isLoadingModels;
    [RelayCommand] private async Task FetchModelsAsync()
    {
        if (IsLoadingModels) return; IsLoadingModels = true;
        try {
            var provider = ActiveProvider;
            var key = provider switch { "gemini" => GeminiKey, "claude" => ClaudeKey, "deepseek" => DeepSeekKey, _ => OpenAiKey };
            var models = await new ModelCatalogService().FetchAsync(provider, key);
            if (ActiveProvider != provider) { Status = "Nhà cung cấp đã thay đổi; hãy tải lại danh sách mô hình."; return; }
            AvailableModels.Clear(); foreach (var model in models) AvailableModels.Add(model);
            Status = $"Đã tải {models.Count} mô hình; chọn mô hình hỗ trợ trò chuyện.";
        } catch (Exception ex) { Status = "Không tải được danh sách mô hình: " + ex.Message; }
        finally { IsLoadingModels = false; }
    }
    partial void OnCatalogModelChanged(string value)
    {
        if (string.IsNullOrWhiteSpace(value)) return;
        switch (ActiveProvider) { case "gemini": GeminiModel = value; break; case "claude": ClaudeModel = value; break; case "deepseek": DeepSeekModel = value; break; default: OpenAiModel = value; break; }
    }
    partial void OnActiveProviderChanged(string value) { AvailableModels.Clear(); CatalogModel = ""; }

    [ObservableProperty] private string _openAiModel = "";
    [ObservableProperty] private string _geminiModel = "";
    [ObservableProperty] private string _claudeModel = "";
    [ObservableProperty] private string _deepSeekModel = "";

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

    public SettingsViewModel(Func<bool>? meetingBusy = null)
    {
        _meetingBusy = meetingBusy ?? (() => false);
        var appData = Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData);
        _appDataDir = Path.Combine(appData, "TransTools");
        Directory.CreateDirectory(_appDataDir);

        ActiveProvider = _credentialStore.LoadActiveProvider();
        LoadSavedSettings();
        LoadSubtitlePreferences();
        TransTools.Services.Experience.SubtitlePreferences.Shared.Changed += LoadSubtitlePreferences;
        CalculateCacheSize();
        foreach (var provider in new[] { "openai", "gemini", "claude", "deepseek" })
        {
            var path = Path.Combine(_appDataDir, "secure", provider + ".model");
            var value = File.Exists(path) ? File.ReadAllText(path) : "";
            switch (provider) { case "openai": OpenAiModel = value; break;
                case "gemini": GeminiModel = value; break;
                case "claude": ClaudeModel = value; break;
                case "deepseek": DeepSeekModel = value; break; }
        }
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
        try {
        _credentialStore.SaveActiveProvider(ActiveProvider);
        _credentialStore.SaveApiKey("openai", OpenAiKey);
        _credentialStore.SaveApiKey("gemini", GeminiKey);
        _credentialStore.SaveApiKey("claude", ClaudeKey);
        _credentialStore.SaveApiKey("deepseek", DeepSeekKey);

        _credentialStore.SaveModel("openai", OpenAiModel);
        _credentialStore.SaveModel("gemini", GeminiModel);
        _credentialStore.SaveModel("claude", ClaudeModel);
        _credentialStore.SaveModel("deepseek", DeepSeekModel);
        Status = "Đã mã hóa và lưu tất cả API Key an toàn bằng Windows DPAPI!";
        } catch (Exception ex) { Status = "Không lưu được cấu hình AI: " + ex.Message; }
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
        if (IsUpdating || IsInstallingVoice || _meetingBusy()) { Status = "Kết thúc phiên và tải dữ liệu trước khi dọn cache."; return; }
        try
        {
            var tempDir = Path.Combine(_appDataDir, "temp");
            if (Directory.Exists(tempDir))
            {
                Microsoft.VisualBasic.FileIO.FileSystem.DeleteDirectory(tempDir, Microsoft.VisualBasic.FileIO.UIOption.OnlyErrorDialogs, Microsoft.VisualBasic.FileIO.RecycleOption.SendToRecycleBin);
            }
            CalculateCacheSize();
            Status = "Đã dọn sạch bộ nhớ đệm thành công!";
        }
        catch (Exception ex)
        {
            Status = $"Lỗi dọn cache: {ex.Message}";
        }
    }

    private async void CalculateCacheSize() { try { await RefreshStorageAsync(); } catch (Exception ex) { Status = ex.Message; } }
}
