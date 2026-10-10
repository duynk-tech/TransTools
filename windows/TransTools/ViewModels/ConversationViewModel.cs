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
    public event Action? SessionsSaved;
    public ObservableCollection<ConversationSession> Sessions { get; } = new();
    [ObservableProperty] private ConversationSession? _selectedSession;
    [ObservableProperty] private string _customPrompt = "";
    [ObservableProperty] private bool _showVietnameseTranslation = true;
    [ObservableProperty] private string _status = "Sẵn sàng";
    private readonly Func<bool> _meetingBusy;
    private readonly Func<Task>? _beginListeningOverride;
    private Task BeginListeningAsync()
    {
        if (!string.IsNullOrWhiteSpace(UserInput)) { Status = "Kiểm tra câu đã nhập rồi bấm Gửi."; return Task.CompletedTask; }
        return _beginListeningOverride?.Invoke() ?? ToggleMicrophoneAsync();
    }
    private readonly TransTools.Services.Conversation.ConversationPreferencesStore _preferences;
    [ObservableProperty] private string _learnerName = "";
    [ObservableProperty] private int _sendDelaySeconds = 2;
    [ObservableProperty] private bool _sendRecognizedSpeechAutomatically = true;
    public string GreetingName => LearnerName.Trim();
    partial void OnLearnerNameChanged(string value) { var clean = TransTools.Services.Conversation.ConversationPreferencesStore.Normalize(new(SendDelaySeconds, value)).LearnerName; if (clean != value) { LearnerName = clean; return; } SavePreferences(); }
    partial void OnSendDelaySecondsChanged(int value) { var bounded = Math.Clamp(value, 1, 30); if (bounded != value) { SendDelaySeconds = bounded; return; } if (_recorder != null) _recorder.SilenceDelaySeconds = bounded; if (IsListening) Status = $"Đang nghe · chờ {bounded} giây khi bạn ngừng nói"; SavePreferences(); }
    private void SavePreferences() { if (_preferences == null) return; try { _preferences.Save(new(SendDelaySeconds, LearnerName)); } catch (Exception ex) when (ex is System.IO.IOException or UnauthorizedAccessException) { Status = "Chưa lưu được tùy chọn trò chuyện"; } }
    [RelayCommand] private void IncreaseSendDelay() => SendDelaySeconds = Math.Min(30, SendDelaySeconds + 1);
    [RelayCommand] private void DecreaseSendDelay() => SendDelaySeconds = Math.Max(1, SendDelaySeconds - 1);
    private int _conversationGeneration;
    private CancellationTokenSource? _replyCancellation;
    [ObservableProperty, NotifyPropertyChangedFor(nameof(CanEditLearnerName)), NotifyPropertyChangedFor(nameof(ConversationActionLabel)), NotifyCanExecuteChangedFor(nameof(ToggleConversationCommand))] private bool _isConversationActive;
    public string ConversationActionLabel => IsConversationActive ? "Kết thúc" : Messages.Count == 0 ? "Bắt đầu trò chuyện" : "Tiếp tục nói";
    public bool CanToggleConversation => IsConversationActive || (!IsThinking && !IsListening);
    public bool CanSaveConversation => Messages.Count > 0;
    public bool CanSendMessage => !IsThinking && !IsListening && !string.IsNullOrWhiteSpace(UserInput);
    [RelayCommand(CanExecute = nameof(CanToggleConversation), AllowConcurrentExecutions = true)] private async Task ToggleConversationAsync()
    {
        if (IsConversationActive) EndConversation(); else await StartConversationAsync();
    }
    [RelayCommand] private void EndConversation()
    {
        ++_conversationGeneration; IsConversationActive = false;
        _replyCancellation?.Cancel(); _recognition?.Cancel();
        if (IsListening) { _recorder?.Dispose(); _recorder = null; IsListening = false; }
        VoiceService.Shared.Stop(); Status = "Đã kết thúc trò chuyện";
    }
    [RelayCommand] private async Task StartConversationAsync()
    {
        if (IsThinking || IsListening) return;
        if (_meetingBusy()) { Status = "Kết thúc cuộc họp trước khi luyện nói để tránh thu âm chồng nhau."; return; }
        if (Messages.Count != 0) { IsConversationActive = true; await BeginListeningAsync(); return; }
        IsThinking = true; IsConversationActive = true;
        var generation = _conversationGeneration;
        using var replyCancellation = new CancellationTokenSource(); _replyCancellation = replyCancellation;
        try {
            var config = _credentials.LoadConfiguredProvider() ?? throw new InvalidOperationException("Nhập API key và chọn mô hình trong Cài đặt để trò chuyện.");
            Status = "Đang chuẩn bị lời chào...";
            var reply = await _llmService.GenerateAsync("Begin the conversation with a warm greeting and one opening question.",
                $"Your name is {TransTools.Services.Experience.AssistantIdentity.Shared.DisplayName}. You are my language practice partner. Speak in {TargetLanguage}. Topic: {CurrentTopic}. {(GreetingName.Length == 0 ? "Use a general greeting." : $"Address me as {GreetingName} naturally if appropriate.")} Keep it to 1–2 sentences. {CustomPrompt}", config, replyCancellation.Token);
            var translation = CanShowTranslation && ShowVietnameseTranslation ? await _googleService.TranslateAsync(reply, "auto", "vi", replyCancellation.Token) : "";
            if (generation != _conversationGeneration) return;
            Messages.Add(new ChatMessageItem { Text = reply, Translation = translation });
            await SaveConversationAsync();
            replyCancellation.Token.ThrowIfCancellationRequested();
            if (AutoSpeakResponse) await VoicePreferences.SpeakAsync(reply, TargetLanguage);
            Status = "Đến lượt bạn";
        } catch (Exception ex) { if (generation == _conversationGeneration) { IsConversationActive = false; Status = ex.Message; } }
        finally { _replyCancellation = null; IsThinking = false; if (generation != _conversationGeneration) Status = "Đã kết thúc trò chuyện"; }
        if (IsConversationActive && generation == _conversationGeneration) await BeginListeningAsync();
    }
    private ConversationRecorder? _recorder;
    private CancellationTokenSource? _recognition;
    [ObservableProperty, NotifyPropertyChangedFor(nameof(CanEditLearnerName))] private bool _isListening;
    public bool CanChangeSession => !IsThinking && !IsListening;
    public bool InputReadOnly => IsThinking || IsListening;
    public bool CanEditLearnerName => !IsConversationActive && CanChangeSession;
    public string MicrophoneLabel => IsListening ? "Dừng thu" : "Nói bằng micro";
    partial void OnIsListeningChanged(bool value) { OnPropertyChanged(nameof(CanChangeSession)); OnPropertyChanged(nameof(MicrophoneLabel)); OnPropertyChanged(nameof(CanSendMessage)); OnPropertyChanged(nameof(InputReadOnly)); ToggleConversationCommand.NotifyCanExecuteChanged(); }
    [RelayCommand] private async Task ToggleMicrophoneAsync() {
        if (IsThinking) return;
        if (!IsListening) {
            if (_meetingBusy()) { Status = "Kết thúc cuộc họp trước khi luyện nói để tránh thu âm chồng nhau."; return; }
            try {
                VoiceService.Shared.Stop(); _recorder = new ConversationRecorder { SilenceDelaySeconds = SendDelaySeconds };
                var activeRecorder = _recorder;
                _recorder.LimitReached += () => System.Windows.Application.Current.Dispatcher.BeginInvoke(new Action(() => { if (IsListening && ReferenceEquals(_recorder, activeRecorder)) ToggleMicrophoneCommand.Execute(null); }));
                _recorder.Start(); IsListening = true; IsConversationActive = true; Status = $"Đang nghe · chờ {SendDelaySeconds} giây khi bạn ngừng nói";
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
        if (IsConversationActive && SendRecognizedSpeechAutomatically && !string.IsNullOrWhiteSpace(UserInput)) await SendMessageAsync();
    }
    [RelayCommand] private void CancelRecognition() => _recognition?.Cancel();
    public void Dispose() { _replyCancellation?.Cancel(); _recognition?.Cancel(); if (IsListening) { _recorder?.Dispose(); _recorder = null; IsListening = false; } }

    partial void OnIsThinkingChanged(bool value) { OnPropertyChanged(nameof(CanChangeSession)); OnPropertyChanged(nameof(CanSendMessage)); OnPropertyChanged(nameof(InputReadOnly)); ToggleConversationCommand.NotifyCanExecuteChanged(); }
    public bool CanShowTranslation => !TargetLanguage.Contains("Việt", StringComparison.OrdinalIgnoreCase);

    public ConversationViewModel(Func<bool>? meetingBusy = null, TransTools.Services.Conversation.ConversationPreferencesStore? preferences = null, Func<Task>? beginListening = null)
    {
        _meetingBusy = meetingBusy ?? (() => false);
        _beginListeningOverride = beginListening;
        Messages.CollectionChanged += (_, _) => { OnPropertyChanged(nameof(ConversationActionLabel)); OnPropertyChanged(nameof(CanSaveConversation)); };
        _preferences = preferences ?? new(); var saved = _preferences.Load(); _sendDelaySeconds = saved.DelaySeconds; _learnerName = saved.LearnerName;
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
        await SaveConversationAsync(); IsConversationActive = false; ++_conversationGeneration; SelectedSession = null; Messages.Clear(); Status = "Trò chuyện mới";
    }
    [RelayCommand] private async Task SaveConversationAsync()
    {
        if (Messages.Count == 0) return;
        var session = SelectedSession;
        if (session == null) { session = new ConversationSession(); Sessions.Insert(0, session); }
        if (!session.HasCustomTitle) session.Title = CurrentTopic + " · " + DateTime.Now.ToString("dd/MM HH:mm");
        session.Topic = CurrentTopic; session.Language = TargetLanguage; session.Prompt = CustomPrompt;
        session.UpdatedAt = DateTime.Now; session.Messages = Messages.ToList();
        await _store.SaveAsync(Sessions); OnUi(() => { SelectedSession = session; Status = "Đã lưu hội thoại"; SessionsSaved?.Invoke(); });
    }
    private static void OnUi(Action action)
    {
        var dispatcher = System.Windows.Application.Current?.Dispatcher;
        if (dispatcher == null || dispatcher.CheckAccess()) action(); else dispatcher.Invoke(action);
    }
    public async Task<bool> RenameSessionAsync(Guid id, string title)
    {
        title = title.Trim(); var target = Sessions.FirstOrDefault(s => s.Id == id);
        if (target == null || title.Length == 0 || title.Length > 200) return false;
        var old = target.Title; var custom = target.HasCustomTitle;
        target.Title = title; target.HasCustomTitle = true;
        try { await _store.SaveAsync(Sessions); OnUi(() => SessionsSaved?.Invoke()); return true; }
        catch { target.Title = old; target.HasCustomTitle = custom; throw; }
    }
    public async Task<bool> DeleteSessionsByIdsAsync(IEnumerable<Guid> ids)
    {
        if (!CanChangeSession) return false;
        var targets = ids.ToHashSet(); var kept = Sessions.Where(s => !targets.Contains(s.Id)).ToList();
        await _store.SaveAsync(kept);
        OnUi(() => { foreach (var item in Sessions.Where(s => targets.Contains(s.Id)).ToList()) Sessions.Remove(item); if (SelectedSession != null && targets.Contains(SelectedSession.Id)) { SelectedSession = null; Messages.Clear(); IsConversationActive = false; } SessionsSaved?.Invoke(); }); return true;
    }
    public async Task<bool> DeleteSessionByIdAsync(Guid id)
    {
        if (!CanChangeSession) return false;
        var target = Sessions.FirstOrDefault(s => s.Id == id); if (target == null) return false;
        await _store.SaveAsync(Sessions.Where(s => s.Id != id).ToList());
        OnUi(() => { Sessions.Remove(target); if (SelectedSession?.Id == id) { SelectedSession = null; Messages.Clear(); IsConversationActive = false; } SessionsSaved?.Invoke(); });
        return true;
    }
    [RelayCommand] private async Task DeleteConversationAsync()
    {
        if (IsThinking || IsListening || SelectedSession == null) return;
        var target = SelectedSession;
        var confirm = new TransTools.Views.ConfirmDeleteWindow(target.Title) { Owner = System.Windows.Application.Current.MainWindow };
        if (confirm.ShowDialog() != true) return;
        try { await DeleteSessionByIdAsync(target.Id); Status = "Đã xóa hội thoại"; }
        catch (Exception ex) { Status = "Chưa xóa được hội thoại: " + ex.Message; }
    }

    [ObservableProperty]
    private string _currentTopic = "Phỏng vấn xin việc (Job Interview)";

    [ObservableProperty]
    private string _targetLanguage = "Tiếng Anh (English)";

    [ObservableProperty]
    private string _userInput = string.Empty;

    [ObservableProperty]
    [NotifyPropertyChangedFor(nameof(CanEditLearnerName))]
    private bool _isThinking;

    [ObservableProperty]
    private bool _autoSpeakResponse = true;

    partial void OnUserInputChanged(string value) => OnPropertyChanged(nameof(CanSendMessage));

    [RelayCommand]
    public async Task SendMessageAsync()
    {
        if (IsThinking || IsListening || string.IsNullOrWhiteSpace(UserInput)) return;

        var text = UserInput;
        UserInput = string.Empty;

        // User message
        var userMsg = new ChatMessageItem { IsUser = true, Text = text };
        Messages.Add(userMsg);

        IsThinking = true; IsConversationActive = true;
        var generation = _conversationGeneration;
        var replyCompleted = false;
        using var replyCancellation = new CancellationTokenSource(); _replyCancellation = replyCancellation;
        try
        {
            await SaveConversationAsync();
            replyCancellation.Token.ThrowIfCancellationRequested();
            var prompt = $"Your name is {TransTools.Services.Experience.AssistantIdentity.Shared.DisplayName}. We are roleplaying: {CurrentTopic}. Reply naturally in {TargetLanguage} as my conversation partner. Keep reply concise (1-3 sentences) suitable for language learning practice. {CustomPrompt}";

            var config = _credentials.LoadConfiguredProvider()
                ?? throw new InvalidOperationException("Nhập API key và model trong Cài đặt để trò chuyện.");
            var history = string.Join("\n", Messages.TakeLast(20).Select(m =>
                $"{(m.IsUser ? "User" : "Assistant")}: {m.Text}"));
            var aiReply = await _llmService.GenerateAsync(history, prompt, config, replyCancellation.Token);
            var aiVi = CanShowTranslation && ShowVietnameseTranslation ? await _googleService.TranslateAsync(aiReply, "auto", "vi", replyCancellation.Token) : "";

            if (generation != _conversationGeneration) return;
            var aiMsg = new ChatMessageItem { IsUser = false, Text = aiReply, Translation = aiVi };
            Messages.Add(aiMsg);

            await SaveConversationAsync();
            replyCancellation.Token.ThrowIfCancellationRequested();
            if (AutoSpeakResponse)
            {
                await VoicePreferences.SpeakAsync(aiReply, TargetLanguage);
            }
            replyCompleted = true;
        }
        catch (Exception ex)
        {
            if (generation == _conversationGeneration) Status = $"Không gửi được: {ex.Message}";
        }
        finally
        {
            _replyCancellation = null; IsThinking = false;
            if (generation != _conversationGeneration) Status = "Đã kết thúc trò chuyện";
        }
        if (replyCompleted && IsConversationActive && generation == _conversationGeneration) await BeginListeningAsync();
    }
}
