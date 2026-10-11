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

    public string FormattedDuration
    {
        get
        {
            if (IsConversation) return "Hội thoại đã lưu";
            var duration = double.IsFinite(DurationSeconds) ? Math.Max(0, Math.Floor(DurationSeconds)) : 0;
            var minutes = Math.Floor(duration / 60);
            var seconds = duration % 60;
            return minutes > 0 ? $"{minutes:0} phút {seconds:0} giây" : $"{seconds:0} giây";
        }
    }
    [System.Text.Json.Serialization.JsonIgnore]
    public string DateGroup
    {
        get
        {
            var date = CreatedAt.Kind == DateTimeKind.Utc ? CreatedAt.ToLocalTime().Date : CreatedAt.Date;
            return date == DateTime.Today ? "Hôm nay" : date == DateTime.Today.AddDays(-1) ? "Hôm qua" : "Trước đó";
        }
    }

    public string FormattedDate => CreatedAt.ToString("HH:mm • dd/MM/yyyy");
}
