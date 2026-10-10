using System.IO;
using System.Text.Json;
using System.Security.Cryptography;
using System.Text;
namespace TransTools.Services.Learning;
public sealed record AdaptiveLesson(string Id, string Language, string Original, string Meaning, string Context)
{
    public static AdaptiveLesson Create(string language, string original, string meaning, string context) => new(Convert.ToHexString(SHA256.HashData(Encoding.UTF8.GetBytes(language + "|" + original))), language, original, meaning, context);
}
public sealed record LessonProgress(int Attempts = 0, int Successes = 0, int Difficulty = 1, DateTime Due = default, string[]? SuccessfulDays = null)
{
    public LessonProgress Record(bool correct, DateTime now)
    {
        var days = correct ? (SuccessfulDays ?? []).Append(now.ToString("yyyy-MM-dd")).Distinct().ToArray() : [];
        var success = Successes + (correct ? 1 : 0); var attempts = Attempts + 1; var difficulty = correct ? Difficulty : Math.Max(1, Difficulty - 1);
        if (correct && days.Length >= 3 && success * 5 >= attempts * 4) { difficulty = Math.Min(3, difficulty + 1); days = []; }
        return new(attempts, success, difficulty, now.AddDays(correct ? (difficulty == 3 ? 7 : 2) : 1), days);
    }
}
public sealed class AdaptiveLessons
{
    private readonly string _path;
    private Dictionary<string, LessonProgress> _progress;
    private readonly bool _canSave = true;
    public AdaptiveLessons(string root)
    {
        _path = Path.Combine(root, "adaptive-lessons-v1.json");
        try { _progress = File.Exists(_path) ? JsonSerializer.Deserialize<Dictionary<string, LessonProgress>>(File.ReadAllText(_path)) ?? throw new InvalidDataException("Thiếu tiến độ") : new(); }
        catch { _progress = new(); _canSave = false; }
    }
    public LessonProgress Get(string id) => _progress.GetValueOrDefault(id) ?? new();
    public AdaptiveLesson? Next(IEnumerable<AdaptiveLesson> lessons, DateTime now) => lessons.DistinctBy(l => l.Id).Where(l => Get(l.Id).Due <= now).OrderBy(l => Get(l.Id).Due).ThenBy(l => Get(l.Id).Attempts).ThenBy(l => l.Id).FirstOrDefault();
    public void Record(AdaptiveLesson lesson, bool correct, DateTime now)
    {
        if (!_canSave) throw new InvalidDataException("Chưa đọc được tiến độ cũ; dữ liệu được giữ nguyên.");
        var next = new Dictionary<string, LessonProgress>(_progress) { [lesson.Id] = Get(lesson.Id).Record(correct, now) };
        Directory.CreateDirectory(Path.GetDirectoryName(_path)!); var temp = _path + ".tmp";
        try { File.WriteAllText(temp, JsonSerializer.Serialize(next)); File.Move(temp, _path, true); _progress = next; }
        finally { if (File.Exists(temp)) File.Delete(temp); }
    }
}
