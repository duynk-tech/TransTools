using System.Text.RegularExpressions;
namespace TransTools.Services.Speech;
public static class CaptionTextSegmenter
{
    public static IReadOnlyList<string> Split(string text)
    {
        var output = new List<string>();
        foreach (var sentence in Regex.Split(text.Trim(), @"(?<=[.!?])\s+|(?<=[。！？])")) {
            var remaining = sentence.Trim();
            while (remaining.Length > 160) {
                var cut = remaining.LastIndexOf(' ', 159, 100);
                if (cut < 60) cut = 160;
                if (cut < remaining.Length && char.IsHighSurrogate(remaining[cut - 1])) cut--;
                output.Add(remaining[..cut].Trim()); remaining = remaining[cut..].Trim();
            }
            if (remaining.Length > 0) output.Add(remaining);
        }
        return output;
    }
}
