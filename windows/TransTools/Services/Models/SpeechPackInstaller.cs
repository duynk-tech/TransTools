namespace TransTools.Services.Models;
public static class SpeechPackInstaller
{
    public static async Task InstallAsync(Func<bool, CancellationToken, Task> installComponent, CancellationToken token)
    {
        foreach (var vieNeu in new[] { false, true }) {
            token.ThrowIfCancellationRequested();
            await installComponent(vieNeu, token);
            token.ThrowIfCancellationRequested();
        }
    }
}
