using System.IO;
using System.Security.Cryptography;
using System.Text.Json;
namespace TransTools.Services.Speech;
public static class ModelVerifier
{
    public static void Verify(string folder, string manifestJson, CancellationToken token) {
        using var manifest = JsonDocument.Parse(manifestJson);
        var root = Path.GetFullPath(folder).TrimEnd(Path.DirectorySeparatorChar) + Path.DirectorySeparatorChar;
        foreach (var file in manifest.RootElement.GetProperty("files").EnumerateArray()) {
            token.ThrowIfCancellationRequested(); var relative = file.GetProperty("path").GetString()!;
            var path = Path.GetFullPath(Path.Combine(root, relative));
            if (Path.IsPathRooted(relative) || !path.StartsWith(root, OperatingSystem.IsWindows() ? StringComparison.OrdinalIgnoreCase : StringComparison.Ordinal)) throw new InvalidDataException("Đường dẫn mô hình không hợp lệ.");
            for (var parent = new FileInfo(path).Directory; parent != null && parent.FullName.Length >= root.TrimEnd(Path.DirectorySeparatorChar).Length; parent = parent.Parent)
                if ((parent.Attributes & FileAttributes.ReparsePoint) != 0) throw new InvalidDataException("Mô hình không được dùng thư mục liên kết.");
            var info = new FileInfo(path);
            if ((info.Attributes & FileAttributes.ReparsePoint) != 0 || info.Length != file.GetProperty("size").GetInt64()) throw new InvalidDataException("Mô hình thiếu hoặc đã thay đổi; tải lại để tiếp tục.");
            using var stream = File.OpenRead(path); using var sha = IncrementalHash.CreateHash(HashAlgorithmName.SHA256); var buffer = new byte[1048576]; int read;
            while ((read = stream.Read(buffer, 0, buffer.Length)) > 0) { token.ThrowIfCancellationRequested(); sha.AppendData(buffer, 0, read); }
            if (!Convert.ToHexString(sha.GetHashAndReset()).Equals(file.GetProperty("sha256").GetString(), StringComparison.OrdinalIgnoreCase)) throw new InvalidDataException("Checksum mô hình không khớp; tải lại để tiếp tục.");
        }
    }
}
