using System.IO;
namespace TransTools.Services.Storage;
public sealed record StorageEntry(string Id, string Title, string Detail, string Path, bool Removable, long Bytes = 0, int Files = 0, string? Error = null)
{
    public string Size => Error ?? $"{Bytes / 1048576.0:F1} MB · {Files} tệp";
}
public static class StorageInventory
{
    public static IReadOnlyList<StorageEntry> Entries(string root) => new[] {
        new StorageEntry("supertonic", "Supertonic 3", "Mô hình giọng tự nhiên · Offline", System.IO.Path.Combine(root, "models", "supertonic-3"), true),
        new StorageEntry("vieneu", "VieNeu v3 Turbo", "Giọng tiếng Việt · Offline sau khi tải", System.IO.Path.Combine(root, "models", "vieneu-v3-turbo"), true),
        new StorageEntry("whisper", "Whisper", "Mô hình nhận diện giọng nói · Offline", System.IO.Path.Combine(root, "models", "whisper"), true),
        new StorageEntry("recordings", "Bản ghi phát âm", "Bản ghi người thật dùng cho học chữ", System.IO.Path.Combine(root, "Pronunciation"), true),
        new StorageEntry("temporary", "Cache tạm", "Có thể tạo lại khi sử dụng", System.IO.Path.Combine(root, "temp"), true),
        new StorageEntry("secure", "Cấu hình AI", "Khóa mã hóa và model đã chọn", System.IO.Path.Combine(root, "secure"), false),
        new StorageEntry("personal", "Sổ tay, hội thoại và từ vựng", "Dữ liệu học tập; không xóa khi dọn cache", root, false)
    };
    public static StorageEntry Scan(StorageEntry entry) {
        long bytes = 0; int files = 0;
        try {
            if (!Directory.Exists(entry.Path)) return entry;
            if ((File.GetAttributes(entry.Path) & FileAttributes.ReparsePoint) != 0) return entry with { Error = "Thư mục liên kết không được quét" };
            var stack = new Stack<string>(); stack.Push(entry.Path);
            while (stack.Count > 0) {
                var path = stack.Pop();
                foreach (var file in Directory.EnumerateFiles(path)) {
                    if ((File.GetAttributes(file) & FileAttributes.ReparsePoint) != 0) continue;
                    bytes += new FileInfo(file).Length; files++;
                }
                if (entry.Id == "personal") continue; // Top-level JSON only; child groups are counted separately.
                foreach (var directory in Directory.EnumerateDirectories(path))
                    if ((File.GetAttributes(directory) & FileAttributes.ReparsePoint) == 0) stack.Push(directory);
            }
            return entry with { Bytes = bytes, Files = files };
        } catch (Exception ex) { return entry with { Bytes = bytes, Files = files, Error = "Không quét được: " + ex.Message }; }
    }
}
