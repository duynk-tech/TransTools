using System;
using System.Net.Http;
using System.Text;
using System.Text.Json;
using System.Threading.Tasks;
using TransTools.Models;

namespace TransTools.Services.Translation;

public class LLMTranslationService
{
    private static readonly HttpClient _httpClient = new() { Timeout = TimeSpan.FromSeconds(30) };

    public async Task<string> TranslateWithAIAsync(string text, string targetLanguage, string style, AIProviderConfig config)
    {
        if (string.IsNullOrWhiteSpace(text)) return string.Empty;
        if (string.IsNullOrWhiteSpace(config.ApiKey) && config.ProviderId != "ollama")
        {
            throw new InvalidOperationException($"Chưa cấu hình API Key cho nhà cung cấp {config.DisplayName}.");
        }

        var systemPrompt = $"You are an expert translator. Translate the given text accurately into {targetLanguage}. Maintain natural tone with style: {style}. Return ONLY the direct translation without extra quotes or commentary.";

        return await GenerateAsync(text, systemPrompt, config);
    }

    public async Task<string> GenerateAsync(string text, string systemPrompt, AIProviderConfig config, CancellationToken cancellationToken = default)
    {
        if (string.IsNullOrWhiteSpace(config.SelectedModel))
            throw new InvalidOperationException("Chọn model AI trong Cài đặt trước khi sử dụng.");
        if (string.IsNullOrWhiteSpace(config.ApiKey) && config.ProviderId != "ollama")
            throw new InvalidOperationException("Chưa cấu hình API key.");
        return config.ProviderId.ToLowerInvariant() switch
        {
            "gemini" => await CallGeminiAsync(text, systemPrompt, config, cancellationToken),
            "claude" => await CallClaudeAsync(text, systemPrompt, config, cancellationToken),
            "ollama" => await CallOllamaAsync(text, systemPrompt, config, cancellationToken),
            _ => await CallOpenAICompatibleAsync(text, systemPrompt, config, cancellationToken) // OpenAI, Groq, DeepSeek
        };
    }

    private static async Task<string> CallOpenAICompatibleAsync(string text, string systemPrompt, AIProviderConfig config, CancellationToken cancellationToken)
    {
        var endpoint = !string.IsNullOrWhiteSpace(config.CustomEndpoint)
            ? config.CustomEndpoint
            : config.ProviderId.ToLowerInvariant() switch
            {
                "groq" => "https://api.groq.com/openai/v1/chat/completions",
                "deepseek" => "https://api.deepseek.com/v1/chat/completions",
                _ => "https://api.openai.com/v1/chat/completions"
            };

        using var request = new HttpRequestMessage(HttpMethod.Post, endpoint);
        request.Headers.Add("Authorization", $"Bearer {config.ApiKey}");

        var payload = new
        {
            model = config.SelectedModel,
            messages = new[]
            {
                new { role = "system", content = systemPrompt },
                new { role = "user", content = text }
            },
            temperature = 0.3
        };

        request.Content = new StringContent(JsonSerializer.Serialize(payload), Encoding.UTF8, "application/json");

        using var response = await _httpClient.SendAsync(request, cancellationToken);
        response.EnsureSuccessStatusCode();

        var json = await response.Content.ReadAsStringAsync(cancellationToken);
        using var doc = JsonDocument.Parse(json);
        return doc.RootElement.GetProperty("choices")[0].GetProperty("message").GetProperty("content").GetString()?.Trim() ?? string.Empty;
    }

    private static async Task<string> CallGeminiAsync(string text, string systemPrompt, AIProviderConfig config, CancellationToken cancellationToken)
    {
        var model = config.SelectedModel;
        var url = $"https://generativelanguage.googleapis.com/v1beta/models/{model}:generateContent?key={config.ApiKey}";

        var payload = new
        {
            system_instruction = new { parts = new[] { new { text = systemPrompt } } },
            contents = new[]
            {
                new { parts = new[] { new { text = text } } }
            }
        };

        using var request = new HttpRequestMessage(HttpMethod.Post, url);
        request.Content = new StringContent(JsonSerializer.Serialize(payload), Encoding.UTF8, "application/json");

        using var response = await _httpClient.SendAsync(request, cancellationToken);
        response.EnsureSuccessStatusCode();

        var json = await response.Content.ReadAsStringAsync(cancellationToken);
        using var doc = JsonDocument.Parse(json);
        return doc.RootElement.GetProperty("candidates")[0].GetProperty("content").GetProperty("parts")[0].GetProperty("text").GetString()?.Trim() ?? string.Empty;
    }

    private static async Task<string> CallClaudeAsync(string text, string systemPrompt, AIProviderConfig config, CancellationToken cancellationToken)
    {
        var endpoint = "https://api.anthropic.com/v1/messages";
        using var request = new HttpRequestMessage(HttpMethod.Post, endpoint);
        request.Headers.Add("x-api-key", config.ApiKey);
        request.Headers.Add("anthropic-version", "2023-06-01");

        var payload = new
        {
            model = config.SelectedModel,
            max_tokens = 1024,
            system = systemPrompt,
            messages = new[]
            {
                new { role = "user", content = text }
            }
        };

        request.Content = new StringContent(JsonSerializer.Serialize(payload), Encoding.UTF8, "application/json");
        using var response = await _httpClient.SendAsync(request, cancellationToken);
        response.EnsureSuccessStatusCode();

        var json = await response.Content.ReadAsStringAsync(cancellationToken);
        using var doc = JsonDocument.Parse(json);
        return doc.RootElement.GetProperty("content")[0].GetProperty("text").GetString()?.Trim() ?? string.Empty;
    }

    private static async Task<string> CallOllamaAsync(string text, string systemPrompt, AIProviderConfig config, CancellationToken cancellationToken)
    {
        var endpoint = string.IsNullOrWhiteSpace(config.CustomEndpoint) ? "http://localhost:11434/api/generate" : config.CustomEndpoint;
        var payload = new
        {
            model = config.SelectedModel,
            system = systemPrompt,
            prompt = text,
            stream = false
        };

        using var request = new HttpRequestMessage(HttpMethod.Post, endpoint);
        request.Content = new StringContent(JsonSerializer.Serialize(payload), Encoding.UTF8, "application/json");

        using var response = await _httpClient.SendAsync(request, cancellationToken);
        response.EnsureSuccessStatusCode();

        var json = await response.Content.ReadAsStringAsync(cancellationToken);
        using var doc = JsonDocument.Parse(json);
        return doc.RootElement.GetProperty("response").GetString()?.Trim() ?? string.Empty;
    }
}
