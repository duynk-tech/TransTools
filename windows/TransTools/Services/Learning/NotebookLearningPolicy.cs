using TransTools.Models;
namespace TransTools.Services.Learning;
public static class NotebookLearningPolicy
{
    public static IEnumerable<Caption> Candidates(IEnumerable<Caption> captions, string language) => captions.Where(row =>
        !string.IsNullOrWhiteSpace(row.OriginalTextForLearning ?? row.Original) && !string.IsNullOrWhiteSpace(row.Vietnamese)
        && (row.OriginalTextForLearning ?? row.Original).Length <= 300 && row.Vietnamese.Length <= 500
        && (row.SourceLanguage == null || row.SourceLanguage == language)
        && (row.TargetLanguage == null || row.TargetLanguage == "vi")
        && (row.TranslationSource == null || row.TranslationSource == row.Original));
}
