using System;
using System.IO;
using System.Security.Cryptography;
using System.Text;

namespace TransTools.Services.Storage;

public class SecureCredentialStore
{
    private readonly string _storageDir;

    public SecureCredentialStore()
    {
        var appData = Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData);
        _storageDir = Path.Combine(appData, "TransTools", "secure");
        Directory.CreateDirectory(_storageDir);
    }

    public void SaveApiKey(string providerId, string apiKey)
    {
        var path = Path.Combine(_storageDir, $"{providerId.ToLowerInvariant()}.enc");
        if (string.IsNullOrWhiteSpace(apiKey))
        {
            if (File.Exists(path)) File.Delete(path);
            return;
        }

        var plainBytes = Encoding.UTF8.GetBytes(apiKey);
        var encryptedBytes = ProtectedData.Protect(plainBytes, null, DataProtectionScope.CurrentUser);
        File.WriteAllBytes(path, encryptedBytes);
    }

    public string LoadApiKey(string providerId)
    {
        var path = Path.Combine(_storageDir, $"{providerId.ToLowerInvariant()}.enc");
        if (!File.Exists(path)) return string.Empty;

        try
        {
            var encryptedBytes = File.ReadAllBytes(path);
            var plainBytes = ProtectedData.Unprotect(encryptedBytes, null, DataProtectionScope.CurrentUser);
            return Encoding.UTF8.GetString(plainBytes);
        }
        catch
        {
            return string.Empty;
        }
    }
}
