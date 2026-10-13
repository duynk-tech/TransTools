using System.Globalization;
using System.Text;
using System.Text.RegularExpressions;
namespace TransTools.Services.Speech;
public static class ReferenceWordCheck
{
    public static bool IsNearMatch(string expected, string actual)
    {
        static string[] Words(string value) {
            var normalized = new string(value.Normalize(NormalizationForm.FormD).Where(c => CharUnicodeInfo.GetUnicodeCategory(c) != UnicodeCategory.NonSpacingMark).ToArray()).ToLowerInvariant().Replace('đ', 'd');
            return Regex.Matches(normalized, @"[\p{L}\p{N}]+").Select(match => match.Value).Take(512).ToArray();
        }
        var reference = Words(expected); var recognized = Words(actual);
        if (reference.Length == 0 || recognized.Length == 0) return false;
        var previous = new int[recognized.Length + 1];
        foreach (var word in reference) {
            var next = new int[previous.Length];
            for (var j = 0; j < recognized.Length; j++) next[j + 1] = word == recognized[j] ? previous[j] + 1 : Math.Max(previous[j + 1], next[j]);
            previous = next;
        }
        return previous[^1] * 100 >= reference.Length * 85;
    }
}
