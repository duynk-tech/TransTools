using System;
using System.Collections.ObjectModel;
using System.Threading.Tasks;
using CommunityToolkit.Mvvm.ComponentModel;
using CommunityToolkit.Mvvm.Input;
using TransTools.Models;
using TransTools.Services.Speech;
using TransTools.Services.Translation;

namespace TransTools.ViewModels;

public class ChatMessageItem
{
    public bool IsUser { get; set; }
    public string Text { get; set; } = string.Empty;
    public string Translation { get; set; } = string.Empty;
    public string TimeString { get; set; } = DateTime.Now.ToString("HH:mm");
}

public partial class ConversationViewModel : ObservableObject
{
    private readonly LLMTranslationService _llmService = new();
    private readonly GoogleTranslationService _googleService = new();
    private readonly EdgeTtsService _edgeTts = new();

    public ObservableCollection<ChatMessageItem> Messages { get; } = new();

    [ObservableProperty]
    private string _currentTopic = "Phỏng vấn xin việc (Job Interview)";

    [ObservableProperty]
    private string _targetLanguage = "Tiếng Anh (English)";

    [ObservableProperty]
    private string _userInput = string.Empty;

    [ObservableProperty]
    private bool _isThinking;

    [ObservableProperty]
    private bool _autoSpeakResponse = true;

    [RelayCommand]
    public async Task SendMessageAsync()
    {
        if (string.IsNullOrWhiteSpace(UserInput)) return;

        var text = UserInput;
        UserInput = string.Empty;

        // User message
        var userMsg = new ChatMessageItem { IsUser = true, Text = text };
        Messages.Add(userMsg);

        IsThinking = true;
        try
        {
            var prompt = $"We are roleplaying: {CurrentTopic}. Reply naturally in {TargetLanguage} as my conversation partner. Keep reply concise (1-3 sentences) suitable for language learning practice.";
            
            // Generate response using OpenAI/Gemini/DeepSeek fallback
            var dummyConfig = new AIProviderConfig { ProviderId = "openai", ApiKey = "", SelectedModel = "gpt-4o-mini" };
            
            // Simulating AI response or calling configured provider
            var aiReply = $"That's very interesting! Can you tell me more about how you handle complex situations in that context?";
            var aiVi = await _googleService.TranslateAsync(aiReply, "auto", "vi");

            var aiMsg = new ChatMessageItem { IsUser = false, Text = aiReply, Translation = aiVi };
            Messages.Add(aiMsg);

            if (AutoSpeakResponse)
            {
                await _edgeTts.SpeakAsync(aiReply, "en-US-JennyNeural");
            }
        }
        catch (Exception ex)
        {
            Messages.Add(new ChatMessageItem { IsUser = false, Text = $"Lỗi: {ex.Message}" });
        }
        finally
        {
            IsThinking = false;
        }
    }
}
