using TransTools.Services.Models;
namespace TransTools.Services.Translation;
public static class InstalledTranslation
{
    public static MarianTranslationService Open(string root, string source, string target)
    {
        if (source != "en" || target != "vi") throw new NotSupportedException("Bộ dịch Offline hiện hỗ trợ Anh → Việt. Chọn đúng ngôn ngữ hoặc chọn công cụ dịch khác.");
        if (!TranslationPackInstaller.IsInstalled(root)) throw new InvalidOperationException("Tải bộ dịch Anh → Việt trong Cài đặt → Mô hình AI trước khi dùng Offline.");
        return new MarianTranslationService(TranslationPackInstaller.Folder(root), source, target);
    }
}
