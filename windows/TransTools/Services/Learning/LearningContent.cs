using System.IO;
using System.Text.Json;
using TransTools.Models;
namespace TransTools.Services.Learning;
public sealed record DailySentence(string Language,string OriginalText,string Reading,string VietnameseMeaning,string ContextNote,string KeyWord,string KeyWordMeaning,string KeyWordReading);
public sealed record PracticeDialogue(string Speaker,string Original,string Reading,string Translation);
public sealed record PracticeScenario(string Id,string Language,string Title,string Category,string Description,List<PracticeDialogue> Dialogues);
public sealed record LearningContent(List<DailySentence> Daily,List<VocabularyItem> Starters,List<PracticeScenario> Scenarios)
{
    public static LearningContent Parse(string json) => JsonSerializer.Deserialize<LearningContent>(json,new JsonSerializerOptions { PropertyNameCaseInsensitive=true }) ?? throw new InvalidDataException("Thiếu học liệu.");
}
