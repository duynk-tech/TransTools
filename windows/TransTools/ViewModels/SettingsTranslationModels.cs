using CommunityToolkit.Mvvm.ComponentModel;
using CommunityToolkit.Mvvm.Input;
using TransTools.Services.Models;
using TransTools.Services.Storage;
namespace TransTools.ViewModels;
public partial class SettingsViewModel
{
    [ObservableProperty] [NotifyPropertyChangedFor(nameof(ShowTranslationCard))] private bool _translationInstalled;
    [ObservableProperty] private bool _installingTranslation;
    [ObservableProperty] private string _translationInstallStatus = "Chưa tải · khoảng 98 MB";
    public bool ShowTranslationCard => ModelFilter == "translation" || (ModelFilter == "installed" && TranslationInstalled);
    private void RefreshTranslationModel()
    {
        TranslationInstalled = TranslationPackInstaller.IsInstalled(_appDataDir);
        OnPropertyChanged(nameof(ShowTranslationCard)); OnPropertyChanged(nameof(ModelFilterEmpty));
        if (!InstallingTranslation) TranslationInstallStatus = TranslationInstalled ? "Đã cài · dùng offline" : "Chưa tải · khoảng 98 MB";
    }
    [RelayCommand] private async Task InstallTranslationAsync()
    {
        if (!CanManageModels || InstallingTranslation) return;
        using var cancellation = new CancellationTokenSource(); _installation = cancellation;
        DownloadingModel = "translation"; InstallingTranslation = true; IsInstallingVoice = true;
        try {
            await TranslationPackInstaller.InstallAsync(_appDataDir, new Progress<long>(bytes => { if (InstallingTranslation) TranslationInstallStatus = $"Đang tải · {bytes / 1048576.0:F1} MB"; }), cancellation.Token);
            TranslationInstallStatus = "Đã tải bộ dịch Anh → Việt";
        } catch (OperationCanceledException) { TranslationInstallStatus = "Đã hủy tải"; }
        catch (Exception ex) { TranslationInstallStatus = "Chưa tải được · " + ex.Message; }
        finally {
            InstallingTranslation = false; IsInstallingVoice = false; DownloadingModel = ""; _installation = null;
            TranslationInstalled = TranslationPackInstaller.IsInstalled(_appDataDir);
            OnPropertyChanged(nameof(ShowTranslationCard)); OnPropertyChanged(nameof(ModelFilterEmpty));
            await RefreshStorageAsync();
        }
    }
    [RelayCommand] private async Task RemoveTranslationAsync()
    {
        await RemoveStorageAsync(new StorageEntry("translation-en-vi", "Dịch Anh → Việt", "Bộ dịch Offline", TranslationPackInstaller.Folder(_appDataDir), true));
        RefreshTranslationModel();
    }
}
