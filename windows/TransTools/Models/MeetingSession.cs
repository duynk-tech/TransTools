using System;
using System.Collections.Generic;

namespace TransTools.Models;

public class MeetingSession
{
    [System.Text.Json.Serialization.JsonIgnore] public bool IsConversation { get; set; }
    [System.Text.Json.Serialization.JsonIgnore] public string SourceLanguage { get; set; } = "en";
    [System.Text.Json.Serialization.JsonIgnore] public string KindLabel => IsConversation ? "Trò chuyện" : "Cuộc họp";
    public Guid Id { get; set; } = Guid.NewGuid();
    public string Title { get; set; } = "Cuộc họp mới";
    public DateTime CreatedAt { get; set; } = DateTime.Now;
    public double DurationSeconds { get; set; }
    public string AudioSource { get; set; } = "Loa hệ thống (Loopback)";
    public string Notes { get; set; } = string.Empty;
    public List<Caption> Captions { get; set; } = new();
    public string? Summary { get; set; }

    public string FormattedDuration => IsConversation ? "Hội thoại đã lưu" : TimeSpan.FromSeconds(DurationSeconds).ToString(@"hh\:mm\:ss");
    public string FormattedDate => CreatedAt.ToString("HH:mm • dd/MM/yyyy");
}
