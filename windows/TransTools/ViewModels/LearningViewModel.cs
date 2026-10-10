using System;
using System.Collections.ObjectModel;
using System.IO;
using System.Text.Json;
using System.Threading.Tasks;
using CommunityToolkit.Mvvm.ComponentModel;
using CommunityToolkit.Mvvm.Input;
using TransTools.Models;
using TransTools.Services.Storage;
using TransTools.Services.Learning;
using TransTools.Services.Speech;

namespace TransTools.ViewModels;

public class AlphabetItem
{
    public string Character { get; set; } = string.Empty;
    public string Transcription { get; set; } = string.Empty;
    public string Example { get; set; } = string.Empty;
    public string RecordingId { get; set; } = "";
    public string Tip { get; set; } = "";
}

public partial class LearningViewModel : ObservableObject
{

    private readonly LearningStore _store;
    private LearningContent? _content;
    public string[] LearningGoals { get; } = ["Cuộc họp & Công việc", "Giao tiếp đời sống", "Phỏng vấn & Nghề nghiệp"];
    public string[] LearningLevels { get; } = ["Cơ bản", "Trung cấp", "Nâng cao"];
    [ObservableProperty] private string _learningGoal = "Cuộc họp & Công việc";
    [ObservableProperty] private string _learningLevel = "Cơ bản";
    [ObservableProperty] private bool _isGeneratingLessons;
    [ObservableProperty] private string _lessonGenerationStatus = "";
    partial void OnLearningGoalChanged(string value) { if (_initialized) { SaveGoal(); NextLesson(); } }
    partial void OnLearningLevelChanged(string value) { if (_initialized) SaveGoal(); }
    [RelayCommand(IncludeCancelCommand = true)] private async Task GenerateLessonsAsync(CancellationToken token)
    {
        if (IsGeneratingLessons) return;
        var language = SelectedLanguage; var goal = LearningGoal; var level = LearningLevel; IsGeneratingLessons = true;
        try {
            var config = new SecureCredentialStore().LoadConfiguredProvider() ?? throw new InvalidOperationException("Cấu hình AI trong Cài đặt trước khi tạo bài.");
            LessonGenerationStatus = "Đang chuẩn bị bài mới…";
            var prompt = $"Create 6 distinct short complete sentences in language {language}, for goal {goal}, level {level}. Give accurate Vietnamese meaning and brief Vietnamese context. Avoid names and personal facts. Return ONLY JSON: {{\"lessons\":[{{\"original\":\"...\",\"meaning\":\"...\",\"context\":\"...\"}}]}}.";
            var json = await new TransTools.Services.Translation.LLMTranslationService().GenerateAsync(prompt, "You prepare language learning exercises. Return only valid JSON without Markdown.", config, token);
            token.ThrowIfCancellationRequested(); _adaptive.AddGenerated(AdaptiveLessons.ParseGenerated(json, language, goal));
            LessonGenerationStatus = "Đã có bài mới. Nội dung do AI tạo, có thể có sai sót."; NextLesson();
        } catch (OperationCanceledException) { LessonGenerationStatus = "Đã hủy tạo bài."; }
        catch (Exception ex) { LessonGenerationStatus = "Chưa tạo được bài mới: " + ex.Message; }
        finally { IsGeneratingLessons = false; }
    }
    private readonly AdaptiveLessons _adaptive = new(Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData), "TransTools"));
    [ObservableProperty] private AdaptiveLesson? _currentLesson;
    [ObservableProperty] private string _lessonFeedback = "";
    [ObservableProperty] private string _lessonAnswer = "";
    [ObservableProperty] private bool _lessonRevealed;
    [ObservableProperty] private int _lessonDifficulty = 1;
    public ObservableCollection<string> LessonChoices { get; } = new();
    public bool CanAnswerLesson => CurrentLesson != null && string.IsNullOrEmpty(LessonFeedback);
    public bool ShowLessonText => CurrentLesson != null && (LessonDifficulty == 1 || LessonRevealed);
    public bool ShowLessonChoices => CurrentLesson != null && LessonDifficulty < 3;
    public bool ShowLessonWriting => CurrentLesson != null && LessonDifficulty == 3;
    public bool HasLessonFeedback => !string.IsNullOrEmpty(LessonFeedback);
    public string LessonSourceText => CurrentLesson != null && _adaptive.Lessons.Any(l => l.Id == CurrentLesson.Id) ? "Bài do AI tạo theo mục tiêu · Có thể có sai sót." : "Câu có sẵn · Chủ yếu về công việc. Ưu tiên câu đến hạn; tăng thử thách sau nhiều ngày làm tốt.";
    public string LessonStage => LessonDifficulty == 1 ? "Hiểu câu" : LessonDifficulty == 2 ? "Nghe và hiểu" : "Nhớ và viết lại";
    partial void OnLessonFeedbackChanged(string value) { OnPropertyChanged(nameof(CanAnswerLesson)); OnPropertyChanged(nameof(HasLessonFeedback)); }
    partial void OnLessonRevealedChanged(bool value) => OnPropertyChanged(nameof(ShowLessonText));
    [RelayCommand] private void NextLesson()
    {
        var lessons = (_content?.Daily.Where(l => l.Language == SelectedLanguage).Select(l => AdaptiveLesson.Create(l.Language,l.OriginalText,l.VietnameseMeaning,l.ContextNote)) ?? []).Concat(Scenarios.SelectMany(s => s.Dialogues.Select(d => AdaptiveLesson.Create(s.Language,d.Original,d.Translation,s.Description))));
        CurrentLesson = _adaptive.Next(_adaptive.Lessons.Where(l => l.Language == SelectedLanguage && l.Goal == LearningGoal).Concat(lessons), DateTime.Now); LessonFeedback = ""; LessonAnswer = ""; LessonRevealed = false;
        LessonDifficulty = CurrentLesson == null ? 1 : _adaptive.Get(CurrentLesson.Id).Difficulty;
        LessonChoices.Clear();
        if (CurrentLesson != null) foreach (var choice in Scenarios.SelectMany(s => s.Dialogues).Select(d => d.Translation).Concat(_adaptive.Lessons.Where(l => l.Language == SelectedLanguage).Select(l => l.Meaning)).Where(t => t != CurrentLesson.Meaning).Distinct().Take(2).Append(CurrentLesson.Meaning).OrderBy(_ => Random.Shared.Next())) LessonChoices.Add(choice);
        foreach (var name in new[] { nameof(CanAnswerLesson), nameof(ShowLessonText), nameof(ShowLessonChoices), nameof(ShowLessonWriting), nameof(LessonStage), nameof(LessonSourceText) }) OnPropertyChanged(name);
    }
    [RelayCommand] private void AnswerLesson(string? choice) { if (choice != null) GradeLesson(choice == CurrentLesson?.Meaning); }
    [RelayCommand] private void CheckWrittenLesson() { if (!string.IsNullOrWhiteSpace(LessonAnswer)) GradeLesson(LessonAnswer.Trim().Equals(CurrentLesson?.Original.Trim(), StringComparison.OrdinalIgnoreCase)); }
    [RelayCommand] private void RevealLesson() => LessonRevealed = true;
    [RelayCommand] private async Task SpeakLessonAsync() { if (CurrentLesson == null) return; try { await VoicePreferences.SpeakAsync(CurrentLesson.Original, SelectedLanguage); } catch (Exception ex) { Status = ex.Message; } }
    private void GradeLesson(bool correct)
    {
        if (!CanAnswerLesson || CurrentLesson == null) return;
        try { _adaptive.Record(CurrentLesson, correct, DateTime.Now); LessonFeedback = correct ? "Đúng rồi!" : "Hãy xem nghĩa và ôn lại câu này."; LessonRevealed = true; }
        catch (Exception ex) { Status = "Chưa lưu được tiến độ: " + ex.Message; }
    }

    public DailySentence? DailySentence => _content?.Daily.FirstOrDefault(s => s.Language == SelectedLanguage);
    public ObservableCollection<PracticeScenario> Scenarios { get; } = new();
    private void RefreshContent() {
        Scenarios.Clear(); if (_content != null) foreach (var scenario in _content.Scenarios.Where(s => s.Language == SelectedLanguage)) Scenarios.Add(scenario);
        OnPropertyChanged(nameof(DailySentence)); NextLesson();
    }
    [RelayCommand] private async Task SpeakDailyAsync() { if (DailySentence == null) return; try { await VoicePreferences.SpeakAsync(DailySentence.OriginalText, SelectedLanguage); } catch (Exception ex) { Status=ex.Message; } }
    [RelayCommand] private async Task SpeakDialogueAsync(PracticeDialogue? dialogue) { if (dialogue == null) return; try { await VoicePreferences.SpeakAsync(dialogue.Original,SelectedLanguage); } catch (Exception ex) { Status=ex.Message; } }
    [RelayCommand] private void AddStarterWords() {
        if (!_canSaveVocabulary || _content == null) return;
        try {
            var added = _content.Starters.Where(w => w.LanguageCode == SelectedLanguage && !VocabularyList.Any(old => old.LanguageCode == SelectedLanguage && old.Word.Equals(w.Word,StringComparison.OrdinalIgnoreCase))).Select(w => w with {Id=Guid.NewGuid(),CreatedAt=DateTime.Now}).ToList();
            if (added.Count==0) {Status="Các từ khởi đầu đã có trong sổ từ vựng."; return;}
            Persist(VocabularyList.Concat(added)); foreach(var word in added) VocabularyList.Add(word); RefreshVocabulary(); Status=$"Đã thêm {added.Count} từ khởi đầu.";
        } catch (Exception ex) {Status=ex.Message;}
    }
    private Dictionary<string,int> _reviewHistory = new();
    public ObservableCollection<VocabularyItem> VisibleVocabulary { get; } = new();
    public int DueCount => VisibleVocabulary.Count(w => w.DueAt <= DateTime.Now);
    public bool IsJapanese => SelectedLanguage == "ja";
    partial void OnSelectedLanguageChanged(string value) { RecordingPlayer.Stop(); RefreshVocabulary(); RefreshContent(); LoadAlphabetList(); OnPropertyChanged(nameof(IsJapanese)); if (_initialized && _canSaveVocabulary) { try { Persist(VocabularyList); } catch (Exception ex) { Status = ex.Message; } } }
    partial void OnSelectedWordChanged(VocabularyItem? value) => IsFlashcardFlipped = false;
    private void RefreshVocabulary() {
        VisibleVocabulary.Clear(); foreach (var word in VocabularyList.Where(w => w.LanguageCode == SelectedLanguage)) VisibleVocabulary.Add(word);
        SelectedWord = VisibleVocabulary.FirstOrDefault(); UpdateProgress();
    }
    private void UpdateProgress() {
        WordsLearnedToday = _reviewHistory.GetValueOrDefault(DateTime.Today.ToString("yyyy-MM-dd"));
        DailyStreak = SrsScheduler.Streak(_reviewHistory, DateTime.Today); OnPropertyChanged(nameof(DueCount));
    }
    private void Persist(IEnumerable<VocabularyItem> words, Dictionary<string,int>? history = null) => _store.Save(new LearningState(words.ToList(), history ?? _reviewHistory, Math.Clamp(DailyGoal,1,100), SelectedLanguage, LearningGoal, LearningLevel));
    [RelayCommand] private void SaveGoal() { if (!_canSaveVocabulary) return; try { DailyGoal = Math.Clamp(DailyGoal,1,100); Persist(VocabularyList); Status = "Đã lưu mục tiêu học"; } catch (Exception ex) { Status = ex.Message; } }
    [RelayCommand] private void StartReview() { UpdateProgress(); SelectedWord = VisibleVocabulary.Where(w => w.DueAt <= DateTime.Now).OrderBy(w => w.DueAt).FirstOrDefault(); Status = SelectedWord == null ? "Đã ôn hết từ đến hạn." : "Nhớ nghĩa trước khi lật thẻ; sau đó chọn mức ghi nhớ."; }
    [RelayCommand] private void GradeReview(string grade) {
        if (!_canSaveVocabulary || SelectedWord == null || !IsFlashcardFlipped || !Enum.TryParse<ReviewGrade>(grade,true,out var result)) return;
        try {
            var updated = SrsScheduler.Review(SelectedWord, result, DateTime.Now);
            var items = VocabularyList.Select(w => w.Id == updated.Id ? updated : w).ToList();
            var history = new Dictionary<string,int>(_reviewHistory); var today = DateTime.Today.ToString("yyyy-MM-dd"); history[today] = history.GetValueOrDefault(today) + 1;
            Persist(items,history); _reviewHistory = history; VocabularyList[VocabularyList.IndexOf(SelectedWord)] = updated;
            RefreshVocabulary(); StartReview();
        } catch (Exception ex) { Status = "Không lưu được kết quả ôn: " + ex.Message; }
    }
    private bool _canSaveVocabulary = true;
    private bool _initialized;
    private TransTools.Views.LearningBoardWindow? _board;

    public string[] Languages { get; } = ["en", "ja", "zh", "ko"];
    public ObservableCollection<VocabularyItem> VocabularyList { get; } = new();
    public ObservableCollection<AlphabetItem> AlphabetList { get; } = new();

    [ObservableProperty] private string _status = "Sẵn sàng";
    [ObservableProperty] private bool _isKatakana;
    partial void OnIsKatakanaChanged(bool value) => LoadAlphabetList();
    [ObservableProperty]
    private string _selectedLanguage = "en";

    [ObservableProperty]
    private bool _isAlphabetViewActive = false;

    [ObservableProperty]
    private int _dailyStreak;

    [ObservableProperty]
    private int _wordsLearnedToday;

    [ObservableProperty]
    private int _dailyGoal = 20;

    [ObservableProperty]
    private VocabularyItem? _selectedWord;

    [ObservableProperty]
    private bool _isFlashcardFlipped;

    [ObservableProperty]
    private string _newWord = string.Empty;

    [ObservableProperty]
    private string _newMeaning = string.Empty;

    [ObservableProperty]
    private string _newPhonetic = string.Empty;

    public LearningViewModel()
    {
        var appData = Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData);
        _store = new LearningStore(Path.Combine(appData, "TransTools"));

        try { LoadInitialVocabulary(); } catch (Exception ex) { _canSaveVocabulary = false; Status = "Không đọc được từ vựng; giữ nguyên tệp để khôi phục: " + ex.Message; }
        try { _content = LearningContent.Parse(VoiceService.ResourceText("Learning/curated.json")); RefreshContent(); }
        catch (Exception ex) { Status="Không đọc được học liệu: " + ex.Message; }
        LoadAlphabetList(); _initialized = true;
    }

    private void LoadInitialVocabulary()
    {
        var state = _store.Load();
        _reviewHistory = state.DailyReviews ?? throw new InvalidDataException("Thiếu tiến độ học.");
        if (state.Words == null) throw new InvalidDataException("Thiếu danh sách từ.");
        foreach (var word in state.Words) VocabularyList.Add(word);
        DailyGoal = Math.Clamp(state.DailyGoal,1,100); LearningGoal = LearningGoals.Contains(state.Goal) ? state.Goal : LearningGoals[0]; LearningLevel = LearningLevels.Contains(state.Level) ? state.Level : LearningLevels[0];
        SelectedLanguage = new[] { "en", "ja", "zh", "ko" }.Contains(state.Language) ? state.Language : "en";
        RefreshVocabulary();
    }

    public void LoadAlphabetList()
    {
        AlphabetList.Clear();
        switch (SelectedLanguage)
        {
            case "ja":
                using (var resource = System.Windows.Application.GetResourceStream(new Uri("pack://application:,,,/TransTools;component/Resources/Learning/japanese.json"))!.Stream) {
                    using var document = JsonDocument.Parse(resource);
                    foreach (var item in document.RootElement.EnumerateArray()) AlphabetList.Add(new AlphabetItem {
                        Character = item.GetProperty(IsKatakana ? "Katakana" : "Hiragana").GetString()!,
                        Transcription = item.GetProperty("Romaji").GetString()!, Example = item.GetProperty("Example").GetString()!,
                        RecordingId = item.GetProperty("Id").GetString()! switch { "dji" => "ji2", "dzu" => "zu2", var id => id },
                        Tip = item.GetProperty("Tip").GetString()! });
                }
                break;
            case "zh":
                using (var resource = System.Windows.Application.GetResourceStream(new Uri("pack://application:,,,/TransTools;component/Resources/Learning/chinese.json"))!.Stream) {
                    var items = JsonSerializer.Deserialize<System.Collections.Generic.List<AlphabetItem>>(resource);
                    if (items != null) foreach (var item in items) AlphabetList.Add(item);
                }
                break;
            case "ko":
                var symbols = "ㄱ ㄴ ㄷ ㄹ ㅁ ㅂ ㅅ ㅇ ㅈ ㅊ ㅋ ㅌ ㅍ ㅎ ㅏ ㅑ ㅓ ㅕ ㅗ ㅛ ㅜ ㅠ ㅡ ㅣ".Split(' ');
                var readings = "giyeok nieun digeut rieul mieum bieup siot ieung jieut chieut kieuk tieut pieup hieut a ya eo yeo o yo u yu eu i".Split(' ');
                for (var i = 0; i < symbols.Length; i++) AlphabetList.Add(new AlphabetItem { Character = symbols[i], Transcription = readings[i], RecordingId = symbols[i], Tip = "Nghe bản ghi người thật trước khi nhắc lại." });
                break;
            default: // en IPA
                var ipa = new[] { "eɪ", "biː", "siː", "diː", "iː", "ef", "dʒiː", "eɪtʃ", "aɪ", "dʒeɪ", "keɪ", "el", "em", "en", "oʊ", "piː", "kjuː", "ɑːr", "es", "tiː", "juː", "viː", "ˈdʌbəljuː", "eks", "waɪ", "ziː" };
                for (var i = 0; i < 26; i++) AlphabetList.Add(new AlphabetItem { Character = ((char)('A' + i)).ToString(), RecordingId = ((char)('A' + i)).ToString(), Transcription = "/" + ipa[i] + "/", Tip = "Tên chữ khác âm trong từ. Nghe bản ghi rồi nhắc lại." });
                break;
        }
    }

    [RelayCommand]
    public async Task SpeakAlphabetCharAsync(AlphabetItem? item)
    {
        if (item == null) return;
        try { await RecordingPlayer.PlayAsync(string.IsNullOrWhiteSpace(item.RecordingId) ? item.Character : item.RecordingId, SelectedLanguage); }
        catch (Exception ex) { Status = ex.Message; }

    }

    [RelayCommand] private void DeleteWord()
    {
        if (SelectedWord == null || !_canSaveVocabulary) return;
        try {
            var items = VocabularyList.Where(word => word != SelectedWord).ToList();
            Persist(items);
            VocabularyList.Remove(SelectedWord); RefreshVocabulary(); Status = "Đã xóa từ";
        } catch (Exception ex) { Status = "Không xóa được từ: " + ex.Message; }
    }
    [RelayCommand] private void StopPronunciation() => RecordingPlayer.Stop();
    [RelayCommand] private void LearnWithChipChip()
    {
        if (_board == null) { _board = new TransTools.Views.LearningBoardWindow(this); _board.Closed += (_, _) => _board = null; }
        _board.Show(); _board.Activate(); System.Windows.Application.Current.MainWindow.Hide();
    }

    [RelayCommand]
    public void FlipFlashcard()
    {
        IsFlashcardFlipped = !IsFlashcardFlipped;
    }

    [RelayCommand]
    public async Task SpeakCurrentWordAsync()
    {
        if (SelectedWord == null) return;
        try { await VoicePreferences.SpeakAsync(SelectedWord.Word, SelectedWord.LanguageCode); }
        catch (Exception ex) { Status = ex.Message; }
    }

    [RelayCommand]
    public void AddWord()
    {
        if (!_canSaveVocabulary || string.IsNullOrWhiteSpace(NewWord)) return;

        var item = new VocabularyItem
        {
            Word = NewWord.Trim(),
            Meaning = NewMeaning.Trim(),
            Phonetic = NewPhonetic.Trim(),
            LanguageCode = SelectedLanguage
        };

        var items = new System.Collections.Generic.List<VocabularyItem>(VocabularyList);
        items.Insert(0, item);
        try {
            Persist(items); VocabularyList.Insert(0,item); RefreshVocabulary(); SelectedWord = item; Status = "Đã lưu từ";
        } catch (Exception ex) { Status = "Không lưu được từ: " + ex.Message; return; }

        NewWord = string.Empty;
        NewMeaning = string.Empty;
        NewPhonetic = string.Empty;
    }
}
