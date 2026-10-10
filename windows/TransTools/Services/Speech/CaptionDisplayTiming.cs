namespace TransTools.Services.Speech;
public static class CaptionDisplayTiming
{
    // Count graphemes rather than UTF-16 units; bilingual text needs extra reading time.
    public static double HoldSeconds(string original,string translation, string? pacing = null) {
        var length = new System.Globalization.StringInfo(original ?? "").LengthInTextElements;
        var translated = new System.Globalization.StringInfo(translation ?? "").LengthInTextElements;
        if (pacing != null) {
            var (rate, min, max) = pacing switch { "contextual" => (16.0, 3.6, 6.0), "fast" => (24.0, 1.6, 3.2), _ => (20.0, 2.6, 4.8) };
            return Math.Clamp(Math.Max(length, translated) / rate + 1.2, min, max);
        }
        return Math.Clamp(Math.Max(length,translated) / 22.0 + (translated > 0 ? .6 : 0), 1.5, 5);
    }
}
