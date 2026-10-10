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
            var config = _credentialStore.LoadConfiguredProvider();
            TranslatedText = config != null
                ? await _llmTranslate.TranslateWithAIAsync(SourceText, TargetLanguage, $"{SelectedDomain} • {SelectedStyle}", config)
                : await _googleTranslate.TranslateAsync(SourceText, SourceLanguage, TargetLanguage);

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
            var config = _credentialStore.LoadConfiguredProvider();
            if (config != null)
            {
                var prompt = "Review this text for grammar, spelling and phrasing. Provide the corrected version followed by brief explanations in Vietnamese.";
                TranslatedText = await _llmTranslate.GenerateAsync(SourceText, prompt, config);
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
