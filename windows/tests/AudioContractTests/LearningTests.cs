using System.Text.Json;
using TransTools.Models;
using TransTools.Services.Learning;
using TransTools.Services.Storage;
using TransTools.Services.Speech;
public static class LearningTests
{
    private static void Check(bool value,string label) { if (!value) throw new Exception(label); Console.WriteLine("PASS: " + label); }
    public static void Run() {
        Check(ReferenceWordCheck.IsNearMatch("Xin chào, tôi rất vui được gặp bạn.", "xin chao toi rat vui duoc gap ban"), "reference comparison accepts punctuation and accent variations");
        Check(!ReferenceWordCheck.IsNearMatch("Xin chào, tôi rất vui được gặp bạn.", "xin chào bạn") && !ReferenceWordCheck.IsNearMatch("xin chào", "") && !ReferenceWordCheck.IsNearMatch("một hai ba bốn năm", "năm bốn ba hai một"), "reference comparison flags missing or reordered speech");
        var fixtureRoot = Path.Combine(AppContext.BaseDirectory,"Fixtures");
        float[] ReadFloats(string name) { var bytes=File.ReadAllBytes(Path.Combine(fixtureRoot,name)); var values=new float[bytes.Length/4]; Buffer.BlockCopy(bytes,0,values,0,bytes.Length); return values; }
        var expected=ReadFloats("speaker-features.f32");
        var actual=TransTools.Services.Speech.VieNeuSpeakerFeatures.Extract(ReadFloats("speaker-input.f32"));
        Check(actual.Length==expected.Length && actual.Zip(expected).Max(pair=>Math.Abs(pair.First-pair.Second))<.002f,"speaker features match independent macOS Accelerate reference");
        foreach (var invalid in new[] { new float[192], new float[191], Enumerable.Repeat(float.NaN,192).ToArray() }) {
            bool rejected=false; try { TransTools.Services.Speech.VieNeuSpeakerEncoder.ValidateEmbedding(invalid); } catch(InvalidDataException) { rejected=true; }
            Check(rejected,"invalid personal voice embedding rejected");
        }
        var content = LearningContent.Parse(File.ReadAllText(Path.Combine(AppContext.BaseDirectory,"curated.json")));
        Check(content.Daily.Count==4 && content.Starters.Count==20 && content.Scenarios.Count==7,"curated learning catalog mirrors macOS");
        foreach (var language in new[] {"en","ja","zh","ko"}) Check(content.Daily.Any(s => s.Language==language) && content.Starters.Count(w=>w.LanguageCode==language)==5 && content.Scenarios.Where(s=>s.Language==language).All(s=>s.Dialogues.Count>=2),"complete curated examples for " + language);
        var now = new DateTime(2026,10,5,12,0,0); var word = new VocabularyItem { Word="ありがとう", LanguageCode="ja", Meaning="Cảm ơn" };
        var again = SrsScheduler.Review(word,ReviewGrade.Again,now); Check(again.DueAt == now.AddMinutes(10) && again.Repetition == 0,"forgotten word retries in ten minutes");
        var good = SrsScheduler.Review(word,ReviewGrade.Good,now); good = SrsScheduler.Review(good,ReviewGrade.Good,now.AddDays(1)); Check(good.IntervalDays == 3 && good.Repetition == 2,"SRS first and second remembered reviews match macOS");
        var easy = SrsScheduler.Review(word,ReviewGrade.Easy,now); Check(easy.IntervalDays == 4 && easy.Repetition == 2 && Math.Abs(easy.EaseFactor - 2.65)<.001,"easy word uses longer review interval");
        Check(word.LastReviewedAt == null && word.Repetition == 0,"review leaves original word untouched until persistence");
        var manual = good with { MasteredOverride = true };
        Check(manual.IsMastered && manual.DueAt == good.DueAt && manual.Repetition == good.Repetition, "manual mastery preserves review schedule");
        Check(!SrsScheduler.Review(manual,ReviewGrade.Again,now).IsMastered, "forgotten review clears manual mastery");
        Check(JsonSerializer.Deserialize<VocabularyItem>(JsonSerializer.Serialize(manual))!.IsMastered, "manual mastery survives serialization");
        Check(new VocabularyItem { MasteryScore = 5 }.IsMastered, "legacy mastery score remains compatible");
        var history = new Dictionary<string,int> { ["2026-10-04"]=2,["2026-10-03"]=1,["2026-10-01"]=1 };
        Check(SrsScheduler.Streak(history,now)==2 && SrsScheduler.Streak(history,now.AddDays(1))==0,"daily streak tolerates current unstudied day and stops at gaps");
        var root=Path.Combine(Path.GetTempPath(),"trans-tools-learning-"+Guid.NewGuid()); Directory.CreateDirectory(root);
        try {
            Check(!PersonalVoiceQuality.Analyze(new float[48000]).IsUsable && !PersonalVoiceQuality.Analyze(Enumerable.Repeat(1f,48000).ToArray()).IsUsable && PersonalVoiceQuality.Analyze(ReadFloats("speaker-input.f32")).IsUsable,"personal voice quality rejects silence and clipping but accepts Mac reference audio");
            var voiceStore=new PersonalVoiceStore(Path.Combine(root,"PersonalVoice"));
            var raw = voiceStore.SaveRecording("Bản thu chưa xử lý", "Đoạn văn mẫu", ReadFloats("speaker-input.f32"));
            Check(voiceStore.StoredBytes(raw.Id) == new FileInfo(voiceStore.RecordingPath(raw.Id)).Length + new FileInfo(Path.Combine(root, "PersonalVoice", raw.Id.ToString("D"), "profile.json")).Length, "raw recording storage size matches saved audio and metadata");
            Check(!voiceStore.HasModel(raw.Id), "Raw recording incorrectly has synthesized voice model");
            Check(File.Exists(Path.Combine(root, "PersonalVoice", raw.Id.ToString("D"), "reference.wav")), "Raw reference recording was not saved");
            Check(voiceStore.Load().Any(item => item.Id == raw.Id), "Raw recording missing from inventory");
            var rawBytes = File.ReadAllBytes(voiceStore.RecordingPath(raw.Id));
            var decodedRaw = voiceStore.LoadRecording(raw.Id);
            Check(decodedRaw.Length == ReadFloats("speaker-input.f32").Length, "Saved raw recording reloads exact sample count");
            Array.Clear(decodedRaw);
            voiceStore.SaveModel(raw.Id, Enumerable.Repeat(.1f,192).ToArray());
            Check(voiceStore.HasModel(raw.Id) && voiceStore.LoadEmbedding(raw.Id).Length == 192, "Raw recording model can be created separately");
            Check(rawBytes.SequenceEqual(File.ReadAllBytes(voiceStore.RecordingPath(raw.Id))) && voiceStore.Load().Single(item => item.Id == raw.Id) == raw, "Model creation preserves recording identity and audio");
            var profile=voiceStore.Save("Giọng của tôi","Xin chào 日本語",ReadFloats("speaker-input.f32"),Enumerable.Repeat(.1f,192).ToArray());
            Check(voiceStore.Load().Single(item => item.Id == profile.Id).ReferenceText=="Xin chào 日本語" && File.Exists(voiceStore.VoicePath(profile.Id)),"personal voice profile and embedding persist atomically");
            Check(voiceStore.LoadEmbedding(profile.Id).Length==192,"saved personal embedding validates before synthesis");
            var voiceBeforeRename=File.ReadAllBytes(voiceStore.VoicePath(profile.Id));
            voiceStore.Rename(profile.Id,"Giọng Việt 日本語");
            var renamed=voiceStore.Load().Single(item => item.Id == profile.Id);
            Check(renamed.Name=="Giọng Việt 日本語" && renamed.Id==profile.Id && renamed.ReferenceText==profile.ReferenceText && renamed.DurationSeconds==profile.DurationSeconds && File.ReadAllBytes(voiceStore.VoicePath(profile.Id)).SequenceEqual(voiceBeforeRename),"personal voice rename preserves identity, reference text and speaker data");
            File.WriteAllText(voiceStore.VoicePath(profile.Id),"{\"speaker_emb\":[0]}");
            bool invalidVoice=false;try {voiceStore.LoadEmbedding(profile.Id);} catch(InvalidDataException) {invalidVoice=true;}
            Check(invalidVoice,"corrupt personal embedding cannot enter synthesis");
            using(var wav=new BinaryReader(File.OpenRead(Path.Combine(root,"PersonalVoice",profile.Id.ToString("D"),"reference.wav")))) {
                wav.BaseStream.Position=24;Check(wav.ReadInt32()==16000 && wav.BaseStream.Length==96044,"personal reference WAV is bounded 16kHz mono PCM");
            }
            var legacy=Path.Combine(root,"vocabulary.json"); File.WriteAllText(legacy,JsonSerializer.Serialize(new[] {word}));
            var store=new LearningStore(root); var state=store.Load(); Check(state.Words.Single().Word==word.Word,"old vocabulary migrates without losing Unicode"); Check(state.DailyMinutes==10,"legacy vocabulary receives ten-minute daily goal");
            store.Save(state with {Words=new() {good},DailyReviews=history,DailyGoal=10,Language="ja",DailyMinutes=15});
            var loaded=store.Load(); Check(loaded.Words.Single().Repetition==2 && loaded.DailyGoal==10 && loaded.DailyMinutes==15 && loaded.Language=="ja" && loaded.DailyReviews.Count==3,"review schedule and progress persist together");
            Check(File.ReadAllText(legacy).Contains("ありがとう") || JsonSerializer.Deserialize<List<VocabularyItem>>(File.ReadAllText(legacy))!.Single().Word==word.Word,"migration preserves legacy source");
            var oldStateJson = JsonSerializer.SerializeToNode(loaded)!.AsObject(); oldStateJson.Remove("DailyMinutes"); File.WriteAllText(Path.Combine(root,"learning.json"), oldStateJson.ToJsonString());
            Check(store.Load().DailyMinutes == 10 && store.Load().Words.Single().Repetition == 2, "existing learning JSON defaults minutes without losing progress");
            File.WriteAllText(Path.Combine(root,"learning.json"),"broken"); bool rejected=false; try {store.Load();} catch(JsonException) {rejected=true;} Check(rejected,"corrupt learning state is rejected instead of replaced with empty data");
        } finally {Directory.Delete(root,true);}
    }
}
