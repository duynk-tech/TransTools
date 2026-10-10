using System.Text.RegularExpressions;
namespace TransTools.Services.Speech;
public sealed record ReadingPart(string Text, double Pause);
public static class SpeechReadingPlan
{
    private static readonly HashSet<string> Abbreviations = new(StringComparer.OrdinalIgnoreCase) { "Mr", "Mrs", "Ms", "Dr", "Prof", "Sr", "Jr", "St", "e.g", "i.e", "v.v", "TP" };
    public static double Bound(double value, double maximum, double fallback) => double.IsFinite(value) ? Math.Clamp(value, 0, maximum) : fallback;
    public static IReadOnlyList<ReadingPart> Parts(string text, double sentencePause, double paragraphPause)
    {
        var result = new List<ReadingPart>();
        var betweenSentences = Bound(sentencePause, 2, .35);
        var betweenParagraphs = Bound(paragraphPause, 4, .8);
        foreach (var paragraph in text.Replace("\r\n", "\n").Replace('\r', '\n').Split('\n'))
        {
            var content = paragraph.Trim();
            if (content.Length == 0) continue;
            var start = 0;
            for (var i = 0; i < content.Length; i++)
            {
                var punctuation = content[i];
                if (!".!?。！？".Contains(punctuation)) continue;
                var end = i + 1;
                while (end < content.Length && "\"”’'»」』)]".Contains(content[end])) end++;
                var cjk = "。！？".Contains(punctuation);
                if (end < content.Length && !char.IsWhiteSpace(content[end]) && !cjk) continue;
                if (punctuation == '.' && end < content.Length)
                {
                    var word = Regex.Match(content[..i], @"[\p{L}.]+$").Value;
                    if (Abbreviations.Contains(word) || word.Length == 1 && char.IsLetter(word[0])) continue;
                }
                var sentence = content[start..end].Trim();
                if (sentence.Length > 0) result.Add(new(sentence, betweenSentences));
                start = end; i = end - 1;
            }
            var tail = content[start..].Trim();
            if (tail.Length > 0) result.Add(new(tail, betweenSentences));
            if (result.Count > 0) result[^1] = result[^1] with { Pause = betweenParagraphs };
        }
        return result;
    }
    public static async Task PlayAsync(IReadOnlyList<ReadingPart> parts, Func<string, CancellationToken, Task> speak, CancellationToken token)
    {
        for (var i = 0; i < parts.Count; i++)
        {
            token.ThrowIfCancellationRequested();
            await speak(parts[i].Text, token);
            token.ThrowIfCancellationRequested();
            if (i < parts.Count - 1 && parts[i].Pause > 0) await Task.Delay(TimeSpan.FromSeconds(parts[i].Pause), token);
        }
    }
}
