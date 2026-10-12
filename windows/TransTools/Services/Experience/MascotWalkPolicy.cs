namespace TransTools.Services.Experience;
public readonly record struct MascotWalkStep(double X, int Direction, double PauseSeconds);
public static class MascotWalkPolicy
{
    public static string IdlePose(double idleSeconds, int hour, bool workBusy, string foregroundProcess = "", bool reduceMotion = false)
    {
        if (workBusy) return "thinking";
        if (!double.IsFinite(idleSeconds) || idleSeconds < 20) return "thinking";
        var night = hour >= 22 || hour < 7;
        if (night && idleSeconds >= 180) return "sleeping";
        if (reduceMotion) return idleSeconds >= 300 ? "sleeping" : "thinking";
        var process = foregroundProcess.ToLowerInvariant();
        var writing = new[] { "notes", "winword", "onenote", "code", "excel", "antigravity", "outlook", "notepad" }.Any(process.Contains);
        // Match macOS dwell times; the current Windows image pack has six poses.
        string[] poses = night ? ["thinking", "coffee"] : writing ? ["writing", "thinking", "coffee", "strolling"]
            : hour is >= 7 and < 10 or >= 14 and < 16 ? ["coffee", "flowers", "strolling", "thinking"]
            : ["flowers", "strolling", "thinking", "coffee"];
        return poses[(int)(Math.Min(idleSeconds - 20, int.MaxValue) / 75) % poses.Length];
    }
    public static bool CanWalk(bool visible, bool enabled, bool workBusy, bool interacting, bool reduceMotion, double idleSeconds) =>
        visible && enabled && !workBusy && !interacting && !reduceMotion && idleSeconds >= 20;
    public static MascotWalkStep Step(double x, int direction, double minimum, double maximum, double elapsedSeconds)
    {
        if (maximum <= minimum) return new(Math.Clamp(x, minimum, Math.Max(minimum, maximum)), direction, 0);
        x = Math.Clamp(x, minimum, maximum);
        direction = direction < 0 ? -1 : 1;
        var ramp = Math.Clamp(Math.Min(x - minimum, maximum - x) / 30, .65, 1);
        var next = x + direction * 42 * ramp * Math.Clamp(elapsedSeconds, 0, .1);
        if (next >= maximum) return new(maximum, -1, 1.2);
        if (next <= minimum) return new(minimum, 1, 1.2);
        return new(next, direction, 0);
    }
}
