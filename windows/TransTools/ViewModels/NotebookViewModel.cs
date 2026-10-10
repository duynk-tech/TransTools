using System;
using System.Collections.ObjectModel;
using System.IO;
using System.Linq;
using System.Text;
using System.Threading.Tasks;
using CommunityToolkit.Mvvm.ComponentModel;
using CommunityToolkit.Mvvm.Input;
using Microsoft.Win32;
using TransTools.Models;
using TransTools.Services.Export;
using TransTools.Services.Storage;
using TransTools.Services.Translation;

namespace TransTools.ViewModels;

public partial class NotebookViewModel : ObservableObject
{
    private readonly SessionStore _sessionStore = new();
    private readonly SecureCredentialStore _credentialStore = new();
    private readonly LLMTranslationService _llmService = new();

    public ObservableCollection<MeetingSession> Sessions { get; } = new();
    public System.ComponentModel.ICollectionView SessionsView { get; private set; } = null!;
    partial void OnSearchKeywordChanged(string value) => SessionsView?.Refresh();
    [RelayCommand] private async Task OpenNotesAsync()
    {
        if (!IsMeetingSelected) return;
        var session = SelectedSession!;
        var editor = new TransTools.Views.MeetingNotesWindow(session.Notes, session.Summary ?? "") { Owner = System.Windows.Application.Current.MainWindow };
        if (editor.ShowDialog() != true) return;
        var notes = editor.Notes;
        await _sessionStore.UpdateSessionAsync(session.Id, () => session, stored => stored.Notes = notes);
        var visible = Sessions.FirstOrDefault(s => s.Id == session.Id); if (visible != null) visible.Notes = notes;
        OnPropertyChanged(nameof(SelectedSession)); Status = "Đã lưu ghi chú";
    }

    [ObservableProperty]
    private MeetingSession? _selectedSession;

    [ObservableProperty]
    private string _searchKeyword = string.Empty;

    [ObservableProperty]
    private bool _isSummarizing;

    [ObservableProperty]
    private string _status = "Sẵn sàng";

    private readonly Dictionary<Guid, ConversationSession> _conversations = new();
    [ObservableProperty] private string _recordKind = "Tất cả";
    public event Action<Guid>? ResumeConversationRequested;
    public Func<IEnumerable<Guid>, Task<bool>>? DeleteConversationsRequested { get; set; }
    [RelayCommand] private async Task ConfirmDeleteAllRecordsAsync()
    {
        if (Sessions.Count == 0) return;
        if (IsSummarizing || RecordManagementBusy?.Invoke() == true) { Status = "Dừng phiên hoặc chờ phân tích xong trước khi xóa bản ghi."; return; }
        var confirm = new TransTools.Views.ConfirmDeleteWindow($"{Sessions.Count} bản ghi đã lưu", true) { Owner = System.Windows.Application.Current.MainWindow };
        if (confirm.ShowDialog() == true) await DeleteAllRecordsAsync();
    }
    public async Task<bool> DeleteAllRecordsAsync()
    {
        if (IsSummarizing || RecordManagementBusy?.Invoke() == true) return false;
        var records = Sessions.ToList();
        try {
            var chats = records.Where(s => s.IsConversation).Select(s => s.Id).ToArray();
            if (chats.Length > 0 && (DeleteConversationsRequested == null || !await DeleteConversationsRequested(chats))) return false;
            var meetings = records.Where(s => !s.IsConversation).ToList(); await _sessionStore.DeleteSessionsAsync(meetings.Select(s => s.Id));
            System.Windows.Application.Current.Dispatcher.Invoke(() => { foreach (var record in records) Sessions.Remove(record); SessionsView.Refresh(); SelectedSession = SessionsView.Cast<MeetingSession>().FirstOrDefault(); Status = "Đã xóa tất cả bản ghi"; }); return true;
        } catch (Exception ex) { System.Windows.Application.Current.Dispatcher.Invoke(() => Status = "Chưa xóa hết bản ghi: " + ex.Message); return false; }
    }
    public Func<Guid, Task<bool>>? DeleteConversationRequested { get; set; }
    public Func<bool>? RecordManagementBusy { get; set; }
    [RelayCommand] private async Task ConfirmDeleteRecordAsync(MeetingSession? target)
    {
        if (target == null) return;
        if (RecordManagementBusy?.Invoke() == true) { Status = "Dừng phiên đang hoạt động trước khi xóa bản ghi."; return; }
        var confirm = new TransTools.Views.ConfirmDeleteWindow(target.Title) { Owner = System.Windows.Application.Current.MainWindow };
        if (confirm.ShowDialog() == true) await DeleteRecordByIdAsync(target);
    }
    public async Task<bool> DeleteRecordByIdAsync(MeetingSession target)
    {
        if (IsSummarizing || RecordManagementBusy?.Invoke() == true) return false;
        try {
            if (target.IsConversation) { if (DeleteConversationRequested == null || !await DeleteConversationRequested(target.Id)) return false; }
            else await _sessionStore.DeleteSessionAsync(target.Id);
            System.Windows.Application.Current.Dispatcher.Invoke(() => { Sessions.Remove(target); SessionsView.Refresh(); SelectedSession = SessionsView.Cast<MeetingSession>().FirstOrDefault(); Status = "Đã xóa bản ghi"; }); return true;
        } catch (Exception ex) { System.Windows.Application.Current.Dispatcher.Invoke(() => Status = "Chưa xóa được bản ghi: " + ex.Message); return false; }
    }
    public Func<Guid, string, Task<bool>>? RenameConversationRequested { get; set; }
    [RelayCommand] private async Task RenameRecordAsync()
    {
        var target = SelectedSession; if (target == null) return;
        var editor = new TransTools.Views.RenameRecordWindow(target.Title) { Owner = System.Windows.Application.Current.MainWindow };
        if (editor.ShowDialog() == true) await RenameRecordTitleAsync(target, editor.RecordTitle);
    }
    public async Task<bool> RenameRecordTitleAsync(MeetingSession target, string title)
    {
        title = title.Trim(); if (title.Length == 0 || title.Length > 200) return false;
        try {
            if (target.IsConversation) { if (RenameConversationRequested == null || !await RenameConversationRequested(target.Id, title)) return false; }
            else await _sessionStore.UpdateSessionAsync(target.Id, () => target, stored => stored.Title = title);
            var finalTitle = title;
            System.Windows.Application.Current.Dispatcher.Invoke(() => { target.Title = finalTitle; SessionsView.Refresh(); OnPropertyChanged(nameof(SelectedSession)); Status = "Đã đổi tên bản ghi"; }); return true;
        } catch (Exception ex) { System.Windows.Application.Current.Dispatcher.Invoke(() => Status = "Chưa đổi được tên: " + ex.Message); return false; }
    }

    public bool IsConversationSelected => SelectedSession?.IsConversation == true;
    public bool IsMeetingSelected => SelectedSession != null && !IsConversationSelected;
    partial void OnRecordKindChanged(string value)
    {
        SessionsView.Refresh();
        if (SelectedSession != null && !SessionsView.Contains(SelectedSession)) SelectedSession = SessionsView.Cast<MeetingSession>().FirstOrDefault();
    }
    [RelayCommand] private void ResumeConversation()
    {
        if (IsConversationSelected && SelectedSession != null) ResumeConversationRequested?.Invoke(SelectedSession.Id);
    }
    public void SetConversations(IEnumerable<ConversationSession> conversations)
    {
        var previousId = SelectedSession?.Id;
        foreach (var old in Sessions.Where(s => s.IsConversation).ToList()) Sessions.Remove(old);
        _conversations.Clear();
        foreach (var source in conversations.OrderByDescending(s => s.UpdatedAt)) {
            _conversations[source.Id] = source;
            Sessions.Add(new MeetingSession {
                Id = source.Id, IsConversation = true, Title = source.Title, CreatedAt = source.UpdatedAt,
                AudioSource = "Luyện nói với AI", SourceLanguage = ConversationLanguage(source.Language),
                Captions = source.Messages.Select(m => new Caption {
                    Original = $"[{(m.IsUser ? "Bạn" : TransTools.Services.Experience.AssistantIdentity.Shared.DisplayName)}] {m.Text}",
                    Vietnamese = m.Translation, DisplayTimestamp = m.TimeString
                }).ToList()
            });
        }
        SelectedSession = Sessions.FirstOrDefault(s => s.Id == previousId && SessionsView.Contains(s)) ?? SessionsView.Cast<MeetingSession>().FirstOrDefault();
    }
    private static string ConversationLanguage(string language) => language.Contains("Nhật") ? "ja" : language.Contains("Trung") ? "zh" : language.Contains("Hàn") ? "ko" : language.Contains("Việt") ? "vi" : "en";
    public NotebookViewModel()
    {
        SessionsView = System.Windows.Data.CollectionViewSource.GetDefaultView(Sessions);
        SessionsView.SortDescriptions.Add(new System.ComponentModel.SortDescription(nameof(MeetingSession.CreatedAt), System.ComponentModel.ListSortDirection.Descending));
        SessionsView.Filter = item => item is MeetingSession session && (RecordKind == "Tất cả" || (RecordKind == "Trò chuyện" ? session.IsConversation : !session.IsConversation)) && (string.IsNullOrWhiteSpace(SearchKeyword) ||
            session.Title.Contains(SearchKeyword, StringComparison.OrdinalIgnoreCase) || session.Notes.Contains(SearchKeyword, StringComparison.OrdinalIgnoreCase) ||
            session.Captions.Any(c => c.Original.Contains(SearchKeyword, StringComparison.OrdinalIgnoreCase) || c.Vietnamese.Contains(SearchKeyword, StringComparison.OrdinalIgnoreCase)));
        _ = LoadSafelyAsync();
    }

    private async Task LoadSafelyAsync()
    {
        try { await LoadSessionsAsync(); }
        catch (Exception ex) { Status = ex.Message; }
    }

    public async Task LoadSessionsAsync()
    {
        var previousId = SelectedSession?.Id;
        var list = await _sessionStore.LoadSessionsAsync();
        foreach (var old in Sessions.Where(s => !s.IsConversation).ToList()) Sessions.Remove(old);
        foreach (var s in list.OrderByDescending(x => x.CreatedAt))
        {
            Sessions.Add(s);
        }
        SelectedSession = Sessions.FirstOrDefault(s => s.Id == previousId && SessionsView.Contains(s)) ?? SessionsView.Cast<MeetingSession>().FirstOrDefault();
    }

    [RelayCommand]
    public async Task SaveCurrentSessionAsync(MeetingSession session)
    {
        if (session.IsConversation) return;
        Sessions.Insert(0, session);
        SelectedSession = session;
        await _sessionStore.UpdateSessionAsync(session.Id, () => session, stored => { stored.Title = session.Title; stored.Captions = session.Captions; stored.DurationSeconds = session.DurationSeconds; });
        Status = "Đã lưu vào Sổ tay.";
    }

    [RelayCommand]
    public async Task GenerateSummaryAsync()
    {
        if (IsSummarizing || !IsMeetingSelected || SelectedSession == null || SelectedSession.Captions.Count == 0) return;
        var targetSession = SelectedSession;

        IsSummarizing = true;
        Status = "Đang tổng hợp và tóm tắt cuộc họp bằng AI...";

        try
        {
            var config = _credentialStore.LoadConfiguredProvider();

            if (config == null)
            {
                Status = "Vui lòng nhập API Key (OpenAI, Gemini hoặc DeepSeek) trong Cài đặt để tóm tắt cuộc họp.";
                return;
            }

            var transcriptBuilder = new StringBuilder();
            foreach (var cap in targetSession.Captions)
            {
                transcriptBuilder.AppendLine($"[{cap.FormattedTimestamp}] {cap.Original} -> {cap.Vietnamese}");
            }

            var prompt = "Bạn là trợ lý thư ký cuộc họp chuyên nghiệp. Hãy tóm tắt nội dung cuộc họp sau bằng tiếng Việt với định dạng:\n1. Tóm tắt tổng quan (2-3 câu)\n2. Các quyết định & ý chính đã thống nhất (gạch đầu dòng)\n3. Việc cần làm tiếp theo (Action items, nếu có)\n\nNội dung cuộc họp:\n" + transcriptBuilder.ToString();

            var summaryResult = await _llmService.GenerateAsync(transcriptBuilder.ToString(), "Tóm tắt bằng tiếng Việt: tổng quan, quyết định và việc cần làm. Không tự thêm thông tin.", config);
            await _sessionStore.UpdateSessionAsync(targetSession.Id, () => targetSession, stored => stored.Summary = summaryResult);
            var visible = Sessions.FirstOrDefault(s => s.Id == targetSession.Id); if (visible != null) visible.Summary = summaryResult;

            // Trigger UI property changed notification
            OnPropertyChanged(nameof(SelectedSession));

            Status = "Đã tạo bản tóm tắt cuộc họp thành công!";
        }
        catch (Exception ex)
        {
            Status = $"Lỗi tạo tóm tắt: {ex.Message}";
        }
        finally
        {
            IsSummarizing = false;
        }
    }

    [RelayCommand]
    public void ExportDocx()
    {
        if (SelectedSession == null) return;

        var sfd = new SaveFileDialog
        {
            Filter = "Word Document (*.docx)|*.docx",
            FileName = $"{SelectedSession.Title}.docx"
        };

        if (sfd.ShowDialog() == true)
        {
            DocxExportService.ExportMeetingSession(SelectedSession, sfd.FileName);
            Status = "Đã xuất file Word thành công!";
        }
    }

    [RelayCommand]
    public void ExportSrt()
    {
        if (SelectedSession is not { IsConversation: false } session) return;

        var sfd = new SaveFileDialog
        {
            Filter = "SubRip Subtitle (*.srt)|*.srt",
            FileName = $"{session.Title}.srt"
        };

        if (sfd.ShowDialog() == true)
        {
            var lines = session.Captions.Select((c, idx) =>
                $"{idx + 1}\n{c.FormattedTimestamp} --> {TimeSpan.FromSeconds(Math.Max(c.End, c.Start + 1)):hh\\:mm\\:ss\\,fff}\n{c.Original}\n{c.Vietnamese}\n");

            File.WriteAllText(sfd.FileName, string.Join("\n", lines));
            Status = "Đã xuất file SRT thành công!";
        }
    }
}
