using System.IO;
using System.Text.Json;
using System.Security.Cryptography;
using System.Text;
namespace TransTools.Services.Learning;
public sealed record AdaptiveLesson(string Id, string Language, string Original, string Meaning, string Context, string Goal = "Cuộc họp & Công việc")
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
    private readonly string _lessonsPath;
    public List<AdaptiveLesson> Lessons { get; private set; } = new();
    public static List<AdaptiveLesson> ParseGenerated(string json, string language, string goal)
    {
        if (Encoding.UTF8.GetByteCount(json) > 32000) throw new InvalidDataException("Bài tạo quá dài.");
        using var doc = JsonDocument.Parse(json); var rows = doc.RootElement.GetProperty("lessons");
        if (rows.GetArrayLength() < 3 || rows.GetArrayLength() > 8) throw new InvalidDataException("Số bài không hợp lệ.");
        var lessons = new List<AdaptiveLesson>();
        foreach (var row in rows.EnumerateArray()) {
            var original = row.GetProperty("original").GetString()?.Trim() ?? ""; var meaning = row.GetProperty("meaning").GetString()?.Trim() ?? ""; var context = row.GetProperty("context").GetString()?.Trim() ?? "";
            if (original.Length == 0 || original.Length > 300 || meaning.Length == 0 || meaning.Length > 500 || context.Length > 500) throw new InvalidDataException("Nội dung bài không hợp lệ.");
            var id = Convert.ToHexString(SHA256.HashData(Encoding.UTF8.GetBytes(language + "|" + goal + "|" + original)));
            lessons.Add(new(id, language, original, meaning, context, goal));
        }
        return lessons.DistinctBy(l => l.Id).ToList();
    }
    public void AddGenerated(IEnumerable<AdaptiveLesson> lessons)
    {
        if (!_canSave) throw new InvalidDataException("Dữ liệu cũ chưa đọc được; giữ nguyên tệp.");
        var next = Lessons.Concat(lessons).DistinctBy(l => l.Id).Take(500).ToList(); var temp = _lessonsPath + ".tmp";
        Directory.CreateDirectory(Path.GetDirectoryName(_lessonsPath)!);
        try { File.WriteAllText(temp, JsonSerializer.Serialize(next)); File.Move(temp, _lessonsPath, true); Lessons = next; } finally { if (File.Exists(temp)) File.Delete(temp); }
    }
    private Dictionary<string, LessonProgress> _progress;
    private readonly bool _canSave = true;
    public AdaptiveLessons(string root)
    {
        _path = Path.Combine(root, "adaptive-lessons-v1.json"); _lessonsPath = Path.Combine(root, "adaptive-generated-v1.json");
        try { if (File.Exists(_lessonsPath)) Lessons = JsonSerializer.Deserialize<List<AdaptiveLesson>>(File.ReadAllText(_lessonsPath)) ?? throw new InvalidDataException(); } catch { _canSave = false; }
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
