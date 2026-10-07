using System.Text.Json;
using TransTools.Models;
using TransTools.Services.Learning;
using TransTools.Services.Storage;
public static class LearningTests
{
    private static void Check(bool value,string label) { if (!value) throw new Exception(label); Console.WriteLine("PASS: " + label); }
    public static void Run() {
        var content = LearningContent.Parse(File.ReadAllText(Path.Combine(AppContext.BaseDirectory,"curated.json")));
        Check(content.Daily.Count==4 && content.Starters.Count==20 && content.Scenarios.Count==7,"curated learning catalog mirrors macOS");
        foreach (var language in new[] {"en","ja","zh","ko"}) Check(content.Daily.Any(s => s.Language==language) && content.Starters.Count(w=>w.LanguageCode==language)==5 && content.Scenarios.Where(s=>s.Language==language).All(s=>s.Dialogues.Count>=2),"complete curated examples for " + language);
        var now = new DateTime(2026,10,5,12,0,0); var word = new VocabularyItem { Word="ありがとう", LanguageCode="ja", Meaning="Cảm ơn" };
        var again = SrsScheduler.Review(word,ReviewGrade.Again,now); Check(again.DueAt == now.AddMinutes(10) && again.Repetition == 0,"forgotten word retries in ten minutes");
        var good = SrsScheduler.Review(word,ReviewGrade.Good,now); good = SrsScheduler.Review(good,ReviewGrade.Good,now.AddDays(1)); Check(good.IntervalDays == 3 && good.Repetition == 2,"SRS first and second remembered reviews match macOS");
        var easy = SrsScheduler.Review(word,ReviewGrade.Easy,now); Check(easy.IntervalDays == 4 && easy.Repetition == 2 && Math.Abs(easy.EaseFactor - 2.65)<.001,"easy word uses longer review interval");
        Check(word.LastReviewedAt == null && word.Repetition == 0,"review leaves original word untouched until persistence");
        var history = new Dictionary<string,int> { ["2026-10-04"]=2,["2026-10-03"]=1,["2026-10-01"]=1 };
        Check(SrsScheduler.Streak(history,now)==2 && SrsScheduler.Streak(history,now.AddDays(1))==0,"daily streak tolerates current unstudied day and stops at gaps");
        var root=Path.Combine(Path.GetTempPath(),"trans-tools-learning-"+Guid.NewGuid()); Directory.CreateDirectory(root);
        try {
            var legacy=Path.Combine(root,"vocabulary.json"); File.WriteAllText(legacy,JsonSerializer.Serialize(new[] {word}));
            var store=new LearningStore(root); var state=store.Load(); Check(state.Words.Single().Word==word.Word,"old vocabulary migrates without losing Unicode");
            store.Save(state with {Words=new() {good},DailyReviews=history,DailyGoal=10,Language="ja"});
            var loaded=store.Load(); Check(loaded.Words.Single().Repetition==2 && loaded.DailyGoal==10 && loaded.Language=="ja" && loaded.DailyReviews.Count==3,"review schedule and progress persist together");
            Check(File.ReadAllText(legacy).Contains("ありがとう") || JsonSerializer.Deserialize<List<VocabularyItem>>(File.ReadAllText(legacy))!.Single().Word==word.Word,"migration preserves legacy source");
            File.WriteAllText(Path.Combine(root,"learning.json"),"broken"); bool rejected=false; try {store.Load();} catch(JsonException) {rejected=true;} Check(rejected,"corrupt learning state is rejected instead of replaced with empty data");
        } finally {Directory.Delete(root,true);}
    }
}
