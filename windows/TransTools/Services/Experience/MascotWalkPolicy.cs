namespace TransTools.Services.Experience;
public readonly record struct MascotWalkStep(double X, int Direction, double PauseSeconds);
public static class MascotWalkPolicy
{
    public static string IdlePose(double idleSeconds, int hour, bool workBusy) => workBusy ? "thinking" : idleSeconds >= 180 && (hour >= 22 || hour < 7) ? "sleeping" : "coffee";
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
