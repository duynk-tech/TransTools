using System;

namespace TransTools.Models;

public class Caption
{
    public Guid Id { get; set; } = Guid.NewGuid();
    public double Start { get; set; }
    public double End { get; set; }
    public string Original { get; set; } = string.Empty;
    public string Vietnamese { get; set; } = string.Empty;

    public string FormattedTimestamp => TimeSpan.FromSeconds(Start).ToString(@"hh\:mm\:ss\,fff");
}
