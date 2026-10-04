using System;
using System.Collections.ObjectModel;
using System.IO;
using System.Text.Json;
using System.Threading.Tasks;
using CommunityToolkit.Mvvm.ComponentModel;
using CommunityToolkit.Mvvm.Input;
using TransTools.Models;
using TransTools.Services.Speech;

namespace TransTools.ViewModels;

public class AlphabetItem
{
    public string Character { get; set; } = string.Empty;
    public string Transcription { get; set; } = string.Empty;
    public string Example { get; set; } = string.Empty;
}

public partial class LearningViewModel : ObservableObject
{
    private readonly EdgeTtsService _edgeTts = new();
    private readonly string _storagePath;

    public ObservableCollection<VocabularyItem> VocabularyList { get; } = new();
    public ObservableCollection<AlphabetItem> AlphabetList { get; } = new();

    [ObservableProperty]
    private string _selectedLanguage = "en";

    [ObservableProperty]
    private bool _isAlphabetViewActive = false;

    [ObservableProperty]
    private int _dailyStreak = 7;

    [ObservableProperty]
    private int _wordsLearnedToday = 12;

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
        _storagePath = Path.Combine(appData, "TransTools", "vocabulary.json");

        LoadInitialVocabulary();
        LoadAlphabetList();
    }

    private void LoadInitialVocabulary()
    {
        VocabularyList.Add(new VocabularyItem { Word = "resilience", Phonetic = "/rɪˈzɪl.jəns/", Meaning = "khả năng phục hồi, kiên cường", ExampleSentence = "She showed great resilience in the face of adversity." });
        VocabularyList.Add(new VocabularyItem { Word = "meticulous", Phonetic = "/məˈtɪk.jə.ləs/", Meaning = "tỉ mỉ, cẩn thận", ExampleSentence = "He was meticulous in his preparation for the interview." });
        VocabularyList.Add(new VocabularyItem { Word = "perseverance", Phonetic = "/ˌpɜː.sɪˈvɪə.rəns/", Meaning = "sự kiên trì, bền bỉ", ExampleSentence = "Success requires hard work and perseverance." });
        VocabularyList.Add(new VocabularyItem { Word = "proactive", Phonetic = "/prəʊˈæk.tɪv/", Meaning = "chủ động", ExampleSentence = "Companies are looking for proactive employees." });

        SelectedWord = VocabularyList[0];
    }

    public void LoadAlphabetList()
    {
        AlphabetList.Clear();
        switch (SelectedLanguage)
        {
            case "ja":
                AlphabetList.Add(new AlphabetItem { Character = "あ", Transcription = "a", Example = "朝 (asa - buổi sáng)" });
                AlphabetList.Add(new AlphabetItem { Character = "い", Transcription = "i", Example = "犬 (inu - con chó)" });
                AlphabetList.Add(new AlphabetItem { Character = "う", Transcription = "u", Example = "海 (umi - biển)" });
                AlphabetList.Add(new AlphabetItem { Character = "え", Transcription = "e", Example = "駅 (eki - nhà ga)" });
                AlphabetList.Add(new AlphabetItem { Character = "お", Transcription = "o", Example = "お茶 (ocha - trà)" });
                AlphabetList.Add(new AlphabetItem { Character = "か", Transcription = "ka", Example = "傘 (kasa - cái ô)" });
                AlphabetList.Add(new AlphabetItem { Character = "き", Transcription = "ki", Example = "木 (ki - cái cây)" });
                AlphabetList.Add(new AlphabetItem { Character = "く", Transcription = "ku", Example = "車 (kuruma - ô tô)" });
                break;
            case "zh":
                AlphabetList.Add(new AlphabetItem { Character = "b", Transcription = "b (pô)", Example = "爸 (bà - bố)" });
                AlphabetList.Add(new AlphabetItem { Character = "p", Transcription = "p (phô)", Example = "朋 (péng - bạn)" });
                AlphabetList.Add(new AlphabetItem { Character = "m", Transcription = "m (mô)", Example = "妈 (mā - mẹ)" });
                AlphabetList.Add(new AlphabetItem { Character = "f", Transcription = "f (phơ)", Example = "风 (fēng - gió)" });
                AlphabetList.Add(new AlphabetItem { Character = "d", Transcription = "d (tưa)", Example = "大 (dà - lớn)" });
                AlphabetList.Add(new AlphabetItem { Character = "t", Transcription = "t (thưa)", Example = "天 (tiān - trời)" });
                AlphabetList.Add(new AlphabetItem { Character = "n", Transcription = "n (nưa)", Example = "你 (nǐ - bạn)" });
                AlphabetList.Add(new AlphabetItem { Character = "l", Transcription = "l (lưa)", Example = "来 (lái - đến)" });
                break;
            case "ko":
                AlphabetList.Add(new AlphabetItem { Character = "ㄱ", Transcription = "g/k (giyeok)", Example = "가방 (gabang - cặp sách)" });
                AlphabetList.Add(new AlphabetItem { Character = "ㄴ", Transcription = "n (nieun)", Example = "나무 (namu - cái cây)" });
                AlphabetList.Add(new AlphabetItem { Character = "ㄷ", Transcription = "d/t (digeut)", Example = "다리 (dari - cây cầu)" });
                AlphabetList.Add(new AlphabetItem { Character = "ㄹ", Transcription = "r/l (rieul)", Example = "라디오 (radio)" });
                AlphabetList.Add(new AlphabetItem { Character = "ㅁ", Transcription = "m (mieum)", Example = "마음 (maeum - tấm lòng)" });
                AlphabetList.Add(new AlphabetItem { Character = "ㅂ", Transcription = "b/p (bieup)", Example = "바다 (bada - biển)" });
                break;
            default: // en IPA
                AlphabetList.Add(new AlphabetItem { Character = "/iː/", Transcription = "Long E", Example = "see, heat, feel" });
                AlphabetList.Add(new AlphabetItem { Character = "/ɪ/", Transcription = "Short I", Example = "sit, hit, gym" });
                AlphabetList.Add(new AlphabetItem { Character = "/e/", Transcription = "Short E", Example = "bed, pen, ten" });
                AlphabetList.Add(new AlphabetItem { Character = "/æ/", Transcription = "Short A", Example = "cat, black, hat" });
                AlphabetList.Add(new AlphabetItem { Character = "/ɑː/", Transcription = "Long A", Example = "father, car, heart" });
                AlphabetList.Add(new AlphabetItem { Character = "/θ/", Transcription = "Voiceless TH", Example = "think, thought, math" });
                AlphabetList.Add(new AlphabetItem { Character = "/ð/", Transcription = "Voiced TH", Example = "this, that, mother" });
                break;
        }
    }

    [RelayCommand]
    public async Task SpeakAlphabetCharAsync(AlphabetItem? item)
    {
        if (item == null) return;
        var voice = SelectedLanguage switch
        {
            "ja" => "ja-JP-NanamiNeural",
            "zh" => "zh-CN-XiaoxiaoNeural",
            "ko" => "ko-KR-SunHiNeural",
            _ => "en-US-JennyNeural"
        };
        await _edgeTts.SpeakAsync(item.Character, voice);
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
        var voice = SelectedLanguage switch
        {
            "ja" => "ja-JP-NanamiNeural",
            "zh" => "zh-CN-XiaoxiaoNeural",
            "ko" => "ko-KR-SunHiNeural",
            _ => "en-US-JennyNeural"
        };
        await _edgeTts.SpeakAsync(SelectedWord.Word, voice);
    }

    [RelayCommand]
    public void AddWord()
    {
        if (string.IsNullOrWhiteSpace(NewWord)) return;

        var item = new VocabularyItem
        {
            Word = NewWord.Trim(),
            Meaning = NewMeaning.Trim(),
            Phonetic = NewPhonetic.Trim(),
            LanguageCode = SelectedLanguage
        };

        VocabularyList.Insert(0, item);
        SelectedWord = item;

        NewWord = string.Empty;
        NewMeaning = string.Empty;
        NewPhonetic = string.Empty;
    }
}
