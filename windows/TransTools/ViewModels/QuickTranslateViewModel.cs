using System;
using System.Globalization;
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
    [ObservableProperty]
    [NotifyPropertyChangedFor(nameof(ContextButtonLabel))]
    private bool _showContext;
    public string ContextButtonLabel => ShowContext ? "Thu gọn" : "Ngữ cảnh & Mẫu câu";
    public string[] QuickPhrases => SelectedDomain switch
    {
        "Công nghệ thông tin" => ["Nhờ bạn review PR này giúp mình nhé", "Mình đã deploy bản fix lên staging để kiểm thử", "API đang trả về mã lỗi 500 do thiếu tham số", "Cần họp sync lại về database schema và endpoint", "Tính năng này đã hoàn thành và sẵn sàng merge"],
        "Kinh doanh & Hội họp" => ["Chúng ta có thể lên lịch họp sync-up vào ngày mai không?", "Xin gửi bạn tài liệu tổng kết biên bản cuộc họp", "Dự án hiện tại đang triển khai đúng tiến độ", "Nhờ anh/chị xác nhận lại ngân sách và thời hạn", "Rất vui được hợp tác cùng quý đối tác"],
        "Thông dụng" => ["Cảm ơn bạn rất nhiều vì đã hỗ trợ nhiệt tình!", "Hôm nay công việc của bạn có thuận lợi không?", "Hẹn gặp lại bạn vào buổi họp tiếp theo nhé", "Tôi hoàn toàn đồng ý với ý kiến của bạn", "Cho mình xin lỗi vì đã phản hồi chậm trễ"],
        "Kinh tế & Tài chính" => ["Báo cáo doanh thu quý này ghi nhận mức tăng trưởng tốt", "Các khoản chi phí phát sinh cần được ban giám đốc duyệt", "Chỉ số ROI và dòng tiền của quý này đang rất khả quan", "Kế hoạch phân bổ ngân sách dự kiến cho quý sau"],
        "Y tế & Sinh học" => ["Bệnh nhân cần được kiểm tra các chỉ số sinh hiệu định kỳ", "Phác đồ điều trị này đã được hội đồng chuyên môn thông qua", "Xin lưu ý về tiền sử dị ứng thuốc của người bệnh"],
        _ => []
    };
    public void SelectQuickPhrase(string phrase)
    {
        if (!CanConfigure || !Array.Exists(QuickPhrases, item => item == phrase)) return;
        SourceText = phrase;
    }
    public string CharacterCountLabel => new StringInfo(SourceText).LengthInTextElements.ToString("N0", CultureInfo.GetCultureInfo("vi-VN")) + " ký tự";

    [ObservableProperty]
    [NotifyCanExecuteChangedFor(nameof(IncreaseEditorFontCommand))]
    [NotifyCanExecuteChangedFor(nameof(DecreaseEditorFontCommand))]
    private int _editorFontSize = 15;

    private bool CanIncreaseEditorFont() => EditorFontSize < 22;
    private bool CanDecreaseEditorFont() => EditorFontSize > 12;
    [RelayCommand(CanExecute = nameof(CanIncreaseEditorFont))]
    private void IncreaseEditorFont() => EditorFontSize = Math.Min(22, EditorFontSize + 1);
    [RelayCommand(CanExecute = nameof(CanDecreaseEditorFont))]
    private void DecreaseEditorFont() => EditorFontSize = Math.Max(12, EditorFontSize - 1);

    private readonly QuickEditorPreferencesStore _editorPreferences = new();
    private bool _loadingEditorPreferences = true;
    partial void OnEditorFontSizeChanged(int value)
    {
        if (_loadingEditorPreferences) return;
        var bounded = Math.Clamp(value, 12, 22);
        if (bounded != value) { EditorFontSize = bounded; return; }
        try { _editorPreferences.Save(value); }
        catch (Exception e) when (e is System.IO.IOException or UnauthorizedAccessException) { Status = "Chưa lưu được cỡ chữ: " + e.Message; }
    }
    private readonly GoogleTranslationService _googleTranslate = new();
    private readonly LLMTranslationService _llmTranslate = new();

    private readonly SecureCredentialStore _credentialStore = new();

    [ObservableProperty]
    [NotifyPropertyChangedFor(nameof(CharacterCountLabel))]
    [NotifyCanExecuteChangedFor(nameof(TranslateCommand))]
    [NotifyCanExecuteChangedFor(nameof(CheckGrammarCommand))]
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
    [NotifyPropertyChangedFor(nameof(QuickPhrases))]
    private string _selectedDomain = TransTools.Services.Experience.SubtitlePreferences.Shared.Domain;
    public QuickTranslateViewModel()
    {
        EditorFontSize = _editorPreferences.Load();
        _loadingEditorPreferences = false;
        TransTools.Services.Experience.SubtitlePreferences.Shared.Changed += () => SelectedDomain = TransTools.Services.Experience.SubtitlePreferences.Shared.Domain;
    }
    partial void OnSelectedDomainChanged(string value)
    {
        var p = TransTools.Services.Experience.SubtitlePreferences.Shared;
        if (p.Domain == value || !TransTools.Services.Experience.SubtitlePreferences.Domains.Contains(value)) return;
        p.Domain = value;
        try { p.Save(); } catch (Exception ex) { Status = "Chưa lưu được chuyên ngành: " + ex.Message; }
    }

    [ObservableProperty]
    private string _selectedStyle = "Tự nhiên"; // Tự nhiên, Trang trọng, Học thuật, Ngắn gọn

    public bool CanConfigure => !IsTranslating;
    private bool CanProcess() => !IsTranslating && !string.IsNullOrWhiteSpace(SourceText);
    [ObservableProperty]
    [NotifyPropertyChangedFor(nameof(CanConfigure))]
    [NotifyCanExecuteChangedFor(nameof(TranslateCommand))]
    [NotifyCanExecuteChangedFor(nameof(CheckGrammarCommand))]
    private bool _isTranslating;

    [ObservableProperty]
    private string _status = "Sẵn sàng";

    [RelayCommand(CanExecute = nameof(CanProcess))]
    public async Task TranslateAsync()
    {
        if (!CanProcess()) return;
        var source = SourceText; var sourceLanguage = SourceLanguage; var targetLanguage = TargetLanguage;
        var domain = SelectedDomain; var style = SelectedStyle;
        bool Current() => SourceText == source && SourceLanguage == sourceLanguage && TargetLanguage == targetLanguage && SelectedDomain == domain && SelectedStyle == style;
        IsTranslating = true;
        Status = "Đang dịch văn bản...";
        GrammarExplanation = string.Empty;

        try
        {
            var config = _credentialStore.LoadConfiguredProvider();
            var result = config != null
                ? await _llmTranslate.TranslateWithAIAsync(source, targetLanguage, $"{domain} • {style}", config)
                : await _googleTranslate.TranslateAsync(source, sourceLanguage, targetLanguage);
            if (!Current()) { Status = "Nội dung đã thay đổi · nhấn Dịch lại."; return; }
            TranslatedText = result;

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

    [RelayCommand(CanExecute = nameof(CanProcess))]
    public async Task CheckGrammarAsync()
    {
        if (!CanProcess()) return;
        var source = SourceText; var sourceLanguage = SourceLanguage; var targetLanguage = TargetLanguage;
        var domain = SelectedDomain; var style = SelectedStyle;
        bool Current() => SourceText == source && SourceLanguage == sourceLanguage && TargetLanguage == targetLanguage && SelectedDomain == domain && SelectedStyle == style;
        IsTranslating = true;
        Status = "Đang kiểm tra ngữ pháp...";

        try
        {
            var config = _credentialStore.LoadConfiguredProvider();
            if (config != null)
            {
                var prompt = "Review this text for grammar, spelling and phrasing. Provide the corrected version followed by brief explanations in Vietnamese.";
                var result = await _llmTranslate.GenerateAsync(source, prompt, config);
                if (!Current()) { Status = "Nội dung đã thay đổi · kiểm tra lại ngữ pháp."; return; }
                TranslatedText = result;
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
        if (SourceLanguage == "auto") { Status = "Chọn ngôn ngữ gốc trước khi đọc để dùng đúng giọng."; return; }
        try { Status = "Đang đọc văn bản gốc..."; await VoicePreferences.SpeakAsync(SourceText, SourceLanguage); Status = "Hoàn tất"; }
        catch (Exception ex) { Status = ex.Message; }
    }

    [RelayCommand]
    public async Task SpeakTranslatedAsync()
    {
        if (string.IsNullOrWhiteSpace(TranslatedText)) return;
        try { Status = "Đang đọc bản dịch..."; await VoicePreferences.SpeakAsync(TranslatedText, TargetLanguage); Status = "Hoàn tất"; }
        catch (Exception ex) { Status = ex.Message; }
    }
}
