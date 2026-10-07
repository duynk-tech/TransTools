using System;
using System.Net.Http;
using System.Text.Json;
using System.Threading.Tasks;
using System.Threading;

namespace TransTools.Services.Translation;

public class GoogleTranslationService
{
    private static readonly HttpClient _httpClient = new() { Timeout = TimeSpan.FromSeconds(30) };

    public async Task<string> TranslateAsync(string text, string sourceLang = "auto", string targetLang = "vi", CancellationToken cancellationToken = default)
    {
        if (string.IsNullOrWhiteSpace(text)) return string.Empty;

        var url = $"https://translate.googleapis.com/translate_a/single?client=gtx&sl={sourceLang}&tl={targetLang}&dt=t&q={Uri.EscapeDataString(text)}";

        try
        {
            var response = await _httpClient.GetStringAsync(url, cancellationToken);
            using var doc = JsonDocument.Parse(response);
            var root = doc.RootElement;
            if (root.ValueKind == JsonValueKind.Array && root.GetArrayLength() > 0)
            {
                var sentences = root[0];
                var translatedBuilder = new System.Text.StringBuilder();
                foreach (var sentence in sentences.EnumerateArray())
                {
                    if (sentence.GetArrayLength() > 0)
                    {
                        translatedBuilder.Append(sentence[0].GetString());
                    }
                }
                return translatedBuilder.ToString();
            }
        }
        catch (OperationCanceledException) { throw; }
        catch (Exception ex)
        {
            System.Diagnostics.Debug.WriteLine($"Google Translate error: {ex.Message}");
        }

        throw new InvalidOperationException("Không thể dịch văn bản. Kiểm tra kết nối và thử lại.");
    }
}
