namespace TransTools.Services.Speech;

public sealed record PersonalVoiceQuality(double DurationSeconds, double Rms, int ClippedSamples, bool IsUsable)
{
    public static PersonalVoiceQuality Analyze(ReadOnlySpan<float> samples)
    {
        if (samples.Length < 48000 || samples.Length > 128000) throw new ArgumentException("Bản thu cần từ 3 đến 8 giây.");
        double energy = 0;
        int clipped = 0;
        foreach (var sample in samples) {
            if (!float.IsFinite(sample)) throw new ArgumentException("Bản thu có dữ liệu không hợp lệ.");
            energy += (double)(sample * sample);
            if (Math.Abs(sample) >= .98f) clipped++;
        }
        var rms = Math.Sqrt(energy / samples.Length);
        return new(samples.Length / 16000.0, rms, clipped, rms > .008 && clipped < samples.Length / 100);
    }
}
