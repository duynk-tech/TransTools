using System;

namespace TransTools.Models;

public class Caption : CommunityToolkit.Mvvm.ComponentModel.ObservableObject
{
    public Guid Id { get; set; } = Guid.NewGuid();
    public double Start { get; set; }
    public double End { get; set; }
    public string Original { get; set; } = string.Empty;
    private string _vietnamese = string.Empty;
    public string Vietnamese { get => _vietnamese; set => SetProperty(ref _vietnamese, value); }

    public string FormattedTimestamp => TimeSpan.FromSeconds(Start).ToString(@"hh\:mm\:ss\,fff");
}
