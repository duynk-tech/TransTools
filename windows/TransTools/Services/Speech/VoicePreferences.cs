using System.IO;
using System.Text.Json;
namespace TransTools.Services.Speech;
public sealed record VoicePreference(string Engine, double Rate, Guid? PersonalVoiceId = null);
public static class VoicePreferences
{
    public static event Action<string>? Changed;
    private static readonly object Gate = new();
    private static string PathName => Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData), "TransTools", "voices.json");
    public static string LanguageCode(string value) => EdgeTtsService.VoiceForLanguage(value)[..2];
    public static VoicePreference Get(string language) {
        lock (Gate) {
            var values = Load(); var code = LanguageCode(language);
            return values.TryGetValue(code, out var preference) ? preference : new VoicePreference(VoiceService.Shared.IsInstalled && code != "zh" ? "Supertonic 3" : "Giọng cơ bản", 1);
        }
    }
    public static void Save(string language, string engine, double rate) {
        lock (Gate) {
            var values = Load(); var code = LanguageCode(language);
            var personalId = engine == "VieNeu v3 Turbo" && code == "vi" && values.TryGetValue(code, out var old) && old.Engine == engine ? old.PersonalVoiceId : null;
            values[code] = new VoicePreference(engine, engine == "VieNeu v3 Turbo" ? 1 : Math.Clamp(rate, .7, 1.5), personalId);
            Directory.CreateDirectory(System.IO.Path.GetDirectoryName(PathName)!);
            File.WriteAllText(PathName + ".tmp", JsonSerializer.Serialize(values)); File.Move(PathName + ".tmp", PathName, true);
        }
        Changed?.Invoke(LanguageCode(language));
    }
    public static void SelectPersonalVoice(Guid? id)
    {
        if (id is Guid selected) new TransTools.Services.Storage.PersonalVoiceStore(TransTools.Services.Storage.PersonalVoiceStore.DefaultRoot).LoadEmbedding(selected);
        lock (Gate) {
            var values = Load(); values["vi"] = new VoicePreference("VieNeu v3 Turbo", 1, id);
            Directory.CreateDirectory(System.IO.Path.GetDirectoryName(PathName)!);
            File.WriteAllText(PathName + ".tmp", JsonSerializer.Serialize(values)); File.Move(PathName + ".tmp", PathName, true);
        }
        Changed?.Invoke("vi");
    }
    public static Guid? PersonalVoiceFor(string language, string engine) => engine == "VieNeu v3 Turbo" && LanguageCode(language) == "vi" ? Get("vi").PersonalVoiceId : null;
    private static Dictionary<string, VoicePreference> Load() => File.Exists(PathName) ? JsonSerializer.Deserialize<Dictionary<string, VoicePreference>>(File.ReadAllText(PathName)) ?? new() : new();
    public static Task SpeakAsync(string text, string language) {
        var preference = Get(language); return VoiceService.Shared.SpeakAsync(text, LanguageCode(language), preference.Engine, preference.Rate);
    }
}
