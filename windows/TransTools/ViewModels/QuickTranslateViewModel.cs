using System;
using System.Threading.Tasks;
using CommunityToolkit.Mvvm.ComponentModel;
using CommunityToolkit.Mvvm.Input;
using TransTools.Models;
using TransTools.Services.Speech;
using TransTools.Services.Storage;
using TransTools.Services.Translation;

namespace TransTools.ViewModels;

public partial class QuickTranslateViewModel : ObservableObject
{
    private readonly GoogleTranslationService _googleTranslate = new();
    private readonly LLMTranslationService _llmTranslate = new();
    private readonly EdgeTtsService _edgeTts = new();
    private readonly SecureCredentialStore _credentialStore = new();

    [ObservableProperty]
    private string _sourceText = string.Empty;

    [ObservableProperty]
    private string _translatedText = string.Empty;

    [ObservableProperty]
    private string _grammarExplanation = string.Empty;

    [ObservableProperty]
    private string _sourceLanguage = "auto";

    [ObservableProperty]
    private string _targetLanguage = "vi";

    [ObservableProperty]
    private string _selectedDomain = "Thông dụng";

    [ObservableProperty]
    private string _selectedStyle = "Tự nhiên"; // Tự nhiên, Trang trọng, Học thuật, Ngắn gọn

    [ObservableProperty]
    private bool _isTranslating;

    [ObservableProperty]
    private string _status = "Sẵn sàng";

    [RelayCommand]
    public async Task TranslateAsync()
    {
        if (string.IsNullOrWhiteSpace(SourceText)) return;

        IsTranslating = true;
        Status = "Đang dịch văn bản...";
        GrammarExplanation = string.Empty;

        try
        {
            // If OpenAI/Gemini/DeepSeek key is available, translate with style; otherwise fast Google Translate
            var openAiKey = _credentialStore.LoadApiKey("openai");
            var geminiKey = _credentialStore.LoadApiKey("gemini");
            var deepSeekKey = _credentialStore.LoadApiKey("deepseek");

            if (!string.IsNullOrWhiteSpace(openAiKey))
            {
                var config = new AIProviderConfig { ProviderId = "openai", ApiKey = openAiKey, SelectedModel = "gpt-4o-mini" };
                TranslatedText = await _llmTranslate.TranslateWithAIAsync(SourceText, TargetLanguage, $"{SelectedDomain} • {SelectedStyle}", config);
            }
            else if (!string.IsNullOrWhiteSpace(geminiKey))
            {
                var config = new AIProviderConfig { ProviderId = "gemini", ApiKey = geminiKey, SelectedModel = "gemini-1.5-flash" };
                TranslatedText = await _llmTranslate.TranslateWithAIAsync(SourceText, TargetLanguage, $"{SelectedDomain} • {SelectedStyle}", config);
            }
            else
            {
                TranslatedText = await _googleTranslate.TranslateAsync(SourceText, SourceLanguage, TargetLanguage);
            }

            Status = "Hoàn tất dịch thuật";
        }
        catch (Exception ex)
        {
            Status = $"Lỗi: {ex.Message}";
        }
        finally
        {
            IsTranslating = false;
        }
    }

    [RelayCommand]
    public async Task CheckGrammarAsync()
    {
        if (string.IsNullOrWhiteSpace(SourceText)) return;

        IsTranslating = true;
        Status = "Đang kiểm tra ngữ pháp...";

        try
        {
            var openAiKey = _credentialStore.LoadApiKey("openai");
            var geminiKey = _credentialStore.LoadApiKey("gemini");

            if (!string.IsNullOrWhiteSpace(openAiKey) || !string.IsNullOrWhiteSpace(geminiKey))
            {
                var config = !string.IsNullOrWhiteSpace(openAiKey)
                    ? new AIProviderConfig { ProviderId = "openai", ApiKey = openAiKey, SelectedModel = "gpt-4o-mini" }
                    : new AIProviderConfig { ProviderId = "gemini", ApiKey = geminiKey, SelectedModel = "gemini-1.5-flash" };

                var prompt = "Review this text for grammar, spelling and phrasing. Provide the corrected version followed by brief explanations in Vietnamese.";
                TranslatedText = await _llmTranslate.TranslateWithAIAsync(SourceText, "English", prompt, config);
                Status = "Đã hoàn thành sửa ngữ pháp!";
            }
            else
            {
                Status = "Cần nhập API Key (OpenAI hoặc Gemini) trong phần Cài đặt để sử dụng tính năng sửa ngữ pháp.";
            }
        }
        catch (Exception ex)
        {
            Status = $"Lỗi sửa ngữ pháp: {ex.Message}";
        }
        finally
        {
            IsTranslating = false;
        }
    }

    [RelayCommand]
    public async Task SpeakSourceAsync()
    {
        if (string.IsNullOrWhiteSpace(SourceText)) return;
        Status = "Đang đọc văn bản gốc...";
        await _edgeTts.SpeakAsync(SourceText, "en-US-JennyNeural");
        Status = "Hoàn tất";
    }

    [RelayCommand]
    public async Task SpeakTranslatedAsync()
    {
        if (string.IsNullOrWhiteSpace(TranslatedText)) return;
        Status = "Đang đọc bản dịch...";
        await _edgeTts.SpeakAsync(TranslatedText, "vi-VN-HoaiMyNeural");
        Status = "Hoàn tất";
    }
}
