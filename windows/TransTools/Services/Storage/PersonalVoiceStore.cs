using System.IO;
using System.Text.Json;
using TransTools.Services.Speech;
namespace TransTools.Services.Storage;

public sealed record PersonalVoiceProfile(Guid Id, string Name, DateTime CreatedAt, string ReferenceText, double DurationSeconds);
public sealed class PersonalVoiceStore(string root)
{
    private string Folder(Guid id) => Path.Combine(root,id.ToString("D"));
    public string VoicePath(Guid id) => Path.Combine(Folder(id),"Models","vieneu","voice.json");
    public IReadOnlyList<PersonalVoiceProfile> Load()
    {
        if (!Directory.Exists(root)) return [];
        var profiles=new List<PersonalVoiceProfile>();
        foreach(var folder in Directory.EnumerateDirectories(root)) {
            if (!Guid.TryParse(Path.GetFileName(folder),out var id)) continue;
            var file=Path.Combine(folder,"profile.json");
            if (!File.Exists(file)) continue;
            var profile=JsonSerializer.Deserialize<PersonalVoiceProfile>(File.ReadAllText(file)) ?? throw new InvalidDataException("Hồ sơ giọng rỗng.");
            if(profile.Id!=id) throw new InvalidDataException("Hồ sơ giọng không khớp thư mục.");
            profiles.Add(profile);
        }
        return profiles.OrderByDescending(profile=>profile.CreatedAt).ToArray();
    }
    public PersonalVoiceProfile Save(string name,string referenceText,float[] samples,float[] embedding)
    {
        if(string.IsNullOrWhiteSpace(name) || name.Length>100 || referenceText.Length>2000) throw new ArgumentException("Tên hoặc đoạn đọc không hợp lệ.");
        if(samples.Length<48000 || samples.Length>128000 || samples.Any(value=>!float.IsFinite(value))) throw new ArgumentException("Bản thu cần từ 3 đến 8 giây.");
        VieNeuSpeakerEncoder.ValidateEmbedding(embedding);
        Directory.CreateDirectory(root);
        var profile=new PersonalVoiceProfile(Guid.NewGuid(),name.Trim(),DateTime.UtcNow,referenceText,samples.Length/16000.0);
        var temp=Path.Combine(root,".pending-"+profile.Id); var target=Folder(profile.Id);
        try {
            Directory.CreateDirectory(Path.Combine(temp,"Models","vieneu"));
            File.WriteAllText(Path.Combine(temp,"profile.json"),JsonSerializer.Serialize(profile));
            File.WriteAllText(Path.Combine(temp,"Models","vieneu","voice.json"),JsonSerializer.Serialize(new {speaker_emb=embedding}));
            using(var writer=new BinaryWriter(File.Create(Path.Combine(temp,"reference.wav")))) {
                int bytes=samples.Length*2;
                writer.Write(System.Text.Encoding.ASCII.GetBytes("RIFF"));writer.Write(36+bytes);writer.Write(System.Text.Encoding.ASCII.GetBytes("WAVEfmt "));
                writer.Write(16);writer.Write((short)1);writer.Write((short)1);writer.Write(16000);writer.Write(32000);writer.Write((short)2);writer.Write((short)16);
                writer.Write(System.Text.Encoding.ASCII.GetBytes("data"));writer.Write(bytes);
                foreach(var value in samples) writer.Write((short)Math.Round(Math.Clamp(value,-1f,1f)*32767));
            }
            Directory.Move(temp,target);
            return profile;
        } finally {if(Directory.Exists(temp)) Directory.Delete(temp,true);}
    }
}
