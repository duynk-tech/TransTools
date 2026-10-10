using TransTools.Models;
namespace TransTools.Services.Learning;
public enum ReviewGrade { Again, Hard, Good, Easy }
public static class SrsScheduler
{
    public static VocabularyItem Review(VocabularyItem word, ReviewGrade grade, DateTime now) {
        var item = word with { LastReviewedAt = now };
        item.IntervalDays = Math.Clamp(item.IntervalDays, 1, 3650);
        item.EaseFactor = double.IsFinite(item.EaseFactor) ? Math.Clamp(item.EaseFactor, 1.3, 3) : 2.5;
        item.Repetition = Math.Clamp(item.Repetition, 0, 1000);
        switch (grade) {
            case ReviewGrade.Again:
                item.MasteryScore = 0; item.Repetition = 0; item.IntervalDays = 1; item.EaseFactor = Math.Max(1.3, item.EaseFactor - .2); item.DueAt = now.AddMinutes(10); break;
            case ReviewGrade.Hard:
                item.Repetition = Math.Max(1, item.Repetition); item.IntervalDays = Math.Min(3650, Math.Max(1, (int)(item.IntervalDays * 1.2))); item.EaseFactor = Math.Max(1.3, item.EaseFactor - .15); item.DueAt = now.AddDays(item.IntervalDays); break;
            case ReviewGrade.Good:
                item.IntervalDays = item.Repetition == 0 ? 1 : item.Repetition == 1 ? 3 : Math.Min(3650, Math.Max(item.IntervalDays + 1, (int)(item.IntervalDays * item.EaseFactor)));
                item.Repetition++; item.MasteryScore = Math.Min(5, item.Repetition); item.DueAt = now.AddDays(item.IntervalDays); break;
            case ReviewGrade.Easy:
                item.IntervalDays = item.Repetition == 0 ? 4 : Math.Min(3650, Math.Max(item.IntervalDays + 2, (int)(item.IntervalDays * (item.EaseFactor + .5))));
                item.Repetition += 2; item.EaseFactor = Math.Min(3, item.EaseFactor + .15); item.MasteryScore = Math.Min(5, item.Repetition); item.DueAt = now.AddDays(item.IntervalDays); break;
            default: throw new ArgumentOutOfRangeException(nameof(grade));
        }
        return item;
    }
    public static int Streak(IReadOnlyDictionary<string,int> history, DateTime today) {
        var day = today.Date;
        if (!history.TryGetValue(day.ToString("yyyy-MM-dd"),out var current) || current <= 0) day = day.AddDays(-1);
        var count = 0;
        while (history.TryGetValue(day.ToString("yyyy-MM-dd"),out var reviews) && reviews > 0) { count++; day = day.AddDays(-1); }
        return count;
    }
}
