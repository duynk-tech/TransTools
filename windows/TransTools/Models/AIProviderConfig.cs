namespace TransTools.Models;

public enum SubtitleMode
{
    Bilingual,
    OriginalOnly,
    TranslationOnly
}

public class AIProviderConfig
{
    public string ProviderId { get; set; } = "openai"; // openai, gemini, claude, groq, deepseek, ollama
    public string DisplayName { get; set; } = "OpenAI";
    public string ApiKey { get; set; } = string.Empty;
    public string SelectedModel { get; set; } = "gpt-4o-mini";
    public string CustomEndpoint { get; set; } = string.Empty;
    public bool IsEnabled { get; set; } = true;
}
