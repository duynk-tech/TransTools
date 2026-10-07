namespace TransTools.Services.Speech;
public static class CaptionDisplayTiming
{
    // Count graphemes rather than UTF-16 units; bilingual text needs extra reading time.
    public static double HoldSeconds(string original,string translation) {
        var length = new System.Globalization.StringInfo(original ?? "").LengthInTextElements;
        var translated = new System.Globalization.StringInfo(translation ?? "").LengthInTextElements;
        return Math.Clamp(Math.Max(length,translated) / 22.0 + (translated > 0 ? .6 : 0), 1.5, 5);
    }
}
