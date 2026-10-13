using System;

namespace TransTools.Models;

public class Caption : CommunityToolkit.Mvvm.ComponentModel.ObservableObject
{
    public Guid Id { get; set; } = Guid.NewGuid();
    public double Start { get; set; }
    public double End { get; set; }
    public string Original { get; set; } = string.Empty;
    public string? SourceLanguage { get; set; }
    public string? TargetLanguage { get; set; }
    public string? TranslationSource { get; set; }
    public string? OriginalTextForLearning { get; set; }
    private string _translationError = "";
    [System.Text.Json.Serialization.JsonIgnore] public string TranslationError { get => _translationError; set { if (SetProperty(ref _translationError, value)) OnPropertyChanged(nameof(TranslationPendingMessage)); } }
    [System.Text.Json.Serialization.JsonIgnore] public string TranslationPendingMessage => string.IsNullOrEmpty(TranslationError) ? "Đang dịch..." : "Chưa dịch được: " + TranslationError;
    private string _vietnamese = string.Empty;
    public string Vietnamese { get => _vietnamese; set => SetProperty(ref _vietnamese, value); }

    private int _displayOrdinal;
    [System.Text.Json.Serialization.JsonIgnore] public int DisplayOrdinal { get => _displayOrdinal; set => SetProperty(ref _displayOrdinal, value); }

    [System.Text.Json.Serialization.JsonIgnore] public string? DisplayTimestamp { get; set; }
    public string FormattedTimestamp => DisplayTimestamp ?? TimeSpan.FromSeconds(Start).ToString(@"hh\:mm\:ss\,fff");
}
