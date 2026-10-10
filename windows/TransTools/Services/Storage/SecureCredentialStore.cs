using System;
using System.IO;
using System.Security.Cryptography;
using System.Text;
using TransTools.Models;

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

    private static string ValidateProvider(string provider) => new[] { "openai", "gemini", "claude", "deepseek", "ollama" }.Contains(provider) ? provider : throw new InvalidDataException("Nhà cung cấp không hợp lệ.");
    public void SaveModel(string providerId, string model)
        => File.WriteAllText(Path.Combine(_storageDir, ValidateProvider(providerId) + ".model"), model.Trim());

    public void SaveActiveProvider(string provider) => File.WriteAllText(Path.Combine(_storageDir, "active-provider"), ValidateProvider(provider));
    public string LoadActiveProvider() => File.Exists(Path.Combine(_storageDir, "active-provider")) ? File.ReadAllText(Path.Combine(_storageDir, "active-provider")) : "openai";
    public AIProviderConfig? LoadConfiguredProvider()
    {
        foreach (var provider in new[] { ValidateProvider(LoadActiveProvider()) })
        {
            var key = LoadApiKey(provider);
            var path = Path.Combine(_storageDir, provider + ".model");
            var model = File.Exists(path) ? File.ReadAllText(path).Trim() : "";
            if (!string.IsNullOrWhiteSpace(key) && !string.IsNullOrWhiteSpace(model))
                return new AIProviderConfig { ProviderId = provider, ApiKey = key, SelectedModel = model };
        }
        return null;
    }

    public void SaveApiKey(string providerId, string apiKey)
    {
        var path = Path.Combine(_storageDir, $"{ValidateProvider(providerId.ToLowerInvariant())}.enc");
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
        var path = Path.Combine(_storageDir, $"{ValidateProvider(providerId.ToLowerInvariant())}.enc");
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
