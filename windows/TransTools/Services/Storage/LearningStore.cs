using System.IO;
using System.Text.Json;
using TransTools.Models;
namespace TransTools.Services.Storage;
public sealed record LearningState(List<VocabularyItem> Words, Dictionary<string,int> DailyReviews, int DailyGoal = 20, string Language = "en", string Goal = "Cuộc họp & Công việc", string Level = "Cơ bản");
public sealed class LearningStore(string root)
{
    private string PathName => Path.Combine(root,"learning.json");
    public LearningState Load() {
        if (File.Exists(PathName)) return JsonSerializer.Deserialize<LearningState>(File.ReadAllText(PathName)) ?? throw new InvalidDataException("Dữ liệu học tập rỗng.");
        var legacy = Path.Combine(root,"vocabulary.json");
        var words = File.Exists(legacy) ? JsonSerializer.Deserialize<List<VocabularyItem>>(File.ReadAllText(legacy)) ?? throw new InvalidDataException("Tệp từ vựng rỗng.") : new();
        return new LearningState(words,new());
    }
    public void Save(LearningState state) {
        Directory.CreateDirectory(root);
        var temp = PathName + "." + Guid.NewGuid().ToString("N") + ".tmp";
        try { File.WriteAllText(temp,JsonSerializer.Serialize(state)); File.Move(temp,PathName,true); }
        finally { if (File.Exists(temp)) File.Delete(temp); }
    }
}
