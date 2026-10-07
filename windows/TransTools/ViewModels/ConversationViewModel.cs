using System;
using System.Collections.ObjectModel;
using System.Threading.Tasks;
using System.Linq;
using TransTools.Services.Storage;
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

public partial class ConversationViewModel : ObservableObject, IDisposable
{
    private readonly SecureCredentialStore _credentials = new();
    private readonly LLMTranslationService _llmService = new();
    private readonly GoogleTranslationService _googleService = new();


    public ObservableCollection<ChatMessageItem> Messages { get; } = new();

    private readonly ConversationStore _store = new();
    public ObservableCollection<ConversationSession> Sessions { get; } = new();
    [ObservableProperty] private ConversationSession? _selectedSession;
    [ObservableProperty] private string _customPrompt = "";
    [ObservableProperty] private bool _showVietnameseTranslation = true;
    [ObservableProperty] private string _status = "Sẵn sàng";
    private readonly Func<bool> _meetingBusy;
    public int[] SendDelays { get; } = [1, 2, 3, 4, 5, 6, 8, 10];
    [ObservableProperty] private int _sendDelaySeconds = 2;
    [ObservableProperty] private bool _sendRecognizedSpeechAutomatically = true;
    public string GreetingName => Environment.UserName;
    [RelayCommand] private async Task StartConversationAsync()
    {
        if (IsThinking || IsListening || Messages.Count != 0) return;
        IsThinking = true;
        try {
            var config = _credentials.LoadConfiguredProvider() ?? throw new InvalidOperationException("Nhập API key và chọn mô hình trong Cài đặt để trò chuyện.");
            Status = "Đang chuẩn bị lời chào...";
            var reply = await _llmService.GenerateAsync("Begin the conversation with a warm greeting and one opening question.",
                $"You are my language practice partner. Speak in {TargetLanguage}. Topic: {CurrentTopic}. Address me as {GreetingName} naturally if appropriate. Keep it to 1–2 sentences. {CustomPrompt}", config);
            var translation = CanShowTranslation && ShowVietnameseTranslation ? await _googleService.TranslateAsync(reply, "auto", "vi") : "";
            Messages.Add(new ChatMessageItem { Text = reply, Translation = translation });
            await SaveConversationAsync();
            if (AutoSpeakResponse) await VoicePreferences.SpeakAsync(reply, TargetLanguage);
            Status = "Đến lượt bạn";
        } catch (Exception ex) { Status = ex.Message; }
        finally { IsThinking = false; }
    }
    private ConversationRecorder? _recorder;
    private CancellationTokenSource? _recognition;
    [ObservableProperty] private bool _isListening;
    public bool CanChangeSession => !IsThinking && !IsListening;
    public string MicrophoneLabel => IsListening ? "Dừng thu" : "Nói bằng micro";
    partial void OnIsListeningChanged(bool value) { OnPropertyChanged(nameof(CanChangeSession)); OnPropertyChanged(nameof(MicrophoneLabel)); }
    [RelayCommand] private async Task ToggleMicrophoneAsync() {
        if (IsThinking) return;
        if (!IsListening) {
            if (_meetingBusy()) { Status = "Kết thúc cuộc họp trước khi luyện nói để tránh thu âm chồng nhau."; return; }
            try {
                VoiceService.Shared.Stop(); _recorder = new ConversationRecorder { SilenceDelaySeconds = SendDelaySeconds };
                _recorder.LimitReached += () => System.Windows.Application.Current.Dispatcher.BeginInvoke(new Action(() => ToggleMicrophoneCommand.Execute(null)));
                _recorder.Start(); IsListening = true; Status = $"Đang nghe · chờ {SendDelaySeconds} giây khi bạn ngừng nói";
            } catch (Exception ex) { _recorder?.Dispose(); _recorder = null; Status = ex.Message; }
            return;
        }
        UserInput = "";
        IsListening = false; IsThinking = true; _recognition = new CancellationTokenSource();
        try {
            Status = "Đang nhận diện giọng nói...";
            var text = await _recorder!.FinishAsync(VoicePreferences.LanguageCode(TargetLanguage), _recognition.Token);
            UserInput = text; Status = text.Length == 0 ? "Chưa nhận diện được lời nói." : "Kiểm tra câu vừa nói rồi bấm Gửi.";
        } catch (OperationCanceledException) { Status = "Đã hủy nhận diện"; }
        catch (Exception ex) { Status = "Không nhận diện được: " + ex.Message; }
        finally { _recorder?.Dispose(); _recorder = null; _recognition.Dispose(); _recognition = null; IsThinking = false; }
        if (SendRecognizedSpeechAutomatically && !string.IsNullOrWhiteSpace(UserInput)) await SendMessageAsync();
    }
    [RelayCommand] private void CancelRecognition() => _recognition?.Cancel();
    public void Dispose() { _recognition?.Cancel(); if (IsListening) { _recorder?.Dispose(); _recorder = null; IsListening = false; } }

    partial void OnIsThinkingChanged(bool value) => OnPropertyChanged(nameof(CanChangeSession));
    public bool CanShowTranslation => !TargetLanguage.Contains("Việt", StringComparison.OrdinalIgnoreCase);

    public ConversationViewModel(Func<bool>? meetingBusy = null)
    {
        _meetingBusy = meetingBusy ?? (() => false);
        try { foreach (var session in _store.Load().OrderByDescending(s => s.UpdatedAt)) Sessions.Add(session); }
        catch (Exception ex) { Status = "Không đọc được hội thoại: " + ex.Message; }
    }
    partial void OnTargetLanguageChanged(string value) => OnPropertyChanged(nameof(CanShowTranslation));
    partial void OnSelectedSessionChanged(ConversationSession? value)
    {
        if (IsThinking || IsListening || value == null) return;
        Messages.Clear(); foreach (var message in value.Messages) Messages.Add(message);
        CurrentTopic = value.Topic; TargetLanguage = value.Language; CustomPrompt = value.Prompt;
    }
    [RelayCommand] private async Task NewConversationAsync()
    {
        if (IsThinking || IsListening) return;
        await SaveConversationAsync(); SelectedSession = null; Messages.Clear(); Status = "Trò chuyện mới";
    }
    [RelayCommand] private async Task SaveConversationAsync()
    {
        if (Messages.Count == 0) return;
        var session = SelectedSession;
        if (session == null) { session = new ConversationSession(); Sessions.Insert(0, session); }
        session.Title = CurrentTopic + " · " + DateTime.Now.ToString("dd/MM HH:mm");
        session.Topic = CurrentTopic; session.Language = TargetLanguage; session.Prompt = CustomPrompt;
        session.UpdatedAt = DateTime.Now; session.Messages = Messages.ToList();
        await _store.SaveAsync(Sessions); SelectedSession = session; Status = "Đã lưu hội thoại";
    }
    [RelayCommand] private async Task DeleteConversationAsync()
    {
        if (IsThinking || IsListening || SelectedSession == null) return;
        if (System.Windows.MessageBox.Show("Xóa hội thoại đã chọn?", "Hội thoại", System.Windows.MessageBoxButton.YesNo) != System.Windows.MessageBoxResult.Yes) return;
        Sessions.Remove(SelectedSession); SelectedSession = null; Messages.Clear(); await _store.SaveAsync(Sessions);
    }

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
        if (IsThinking || IsListening || string.IsNullOrWhiteSpace(UserInput)) return;

        var text = UserInput;
        UserInput = string.Empty;

        // User message
        var userMsg = new ChatMessageItem { IsUser = true, Text = text };
        Messages.Add(userMsg);

        IsThinking = true;
        try
        {
            var prompt = $"We are roleplaying: {CurrentTopic}. Reply naturally in {TargetLanguage} as my conversation partner. Keep reply concise (1-3 sentences) suitable for language learning practice. {CustomPrompt}";

            var config = _credentials.LoadConfiguredProvider()
                ?? throw new InvalidOperationException("Nhập API key và model trong Cài đặt để trò chuyện.");
            var history = string.Join("\n", Messages.TakeLast(20).Select(m =>
                $"{(m.IsUser ? "User" : "Assistant")}: {m.Text}"));
            var aiReply = await _llmService.GenerateAsync(history, prompt, config);
            var aiVi = CanShowTranslation && ShowVietnameseTranslation ? await _googleService.TranslateAsync(aiReply, "auto", "vi") : "";

            var aiMsg = new ChatMessageItem { IsUser = false, Text = aiReply, Translation = aiVi };
            Messages.Add(aiMsg);

            await SaveConversationAsync();
            if (AutoSpeakResponse)
            {
                await VoicePreferences.SpeakAsync(aiReply, TargetLanguage);
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
