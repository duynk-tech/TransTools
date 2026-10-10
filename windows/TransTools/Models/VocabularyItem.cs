using System;

namespace TransTools.Models;

public record VocabularyItem
{
    public Guid Id { get; set; } = Guid.NewGuid();
    public string Word { get; set; } = string.Empty;
    public string Meaning { get; set; } = string.Empty;
    public string Phonetic { get; set; } = string.Empty;
    public string ExampleSentence { get; set; } = string.Empty;
    public string ExampleTranslation { get; set; } = string.Empty;
    public string LanguageCode { get; set; } = "en"; // en, ja, zh, ko
    public int MasteryScore { get; set; } = 0; // 0 - 5
    public DateTime DueAt { get; set; } = DateTime.MinValue;
    public DateTime? LastReviewedAt { get; set; }
    public int IntervalDays { get; set; } = 1;
    public int Repetition { get; set; }
    public double EaseFactor { get; set; } = 2.5;
    public DateTime CreatedAt { get; set; } = DateTime.Now;
}
