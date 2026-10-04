using System;
using System.Collections.Generic;
using System.IO;
using System.Text.Json;
using System.Threading.Tasks;
using TransTools.Models;

namespace TransTools.Services.Storage;

public class SessionStore
{
    private readonly string _filePath;

    public SessionStore()
    {
        var appData = Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData);
        var dir = Path.Combine(appData, "TransTools");
        Directory.CreateDirectory(dir);
        _filePath = Path.Combine(dir, "meeting_sessions.json");
    }

    public async Task<List<MeetingSession>> LoadSessionsAsync()
    {
        if (!File.Exists(_filePath)) return new List<MeetingSession>();
        try
        {
            var json = await File.ReadAllTextAsync(_filePath);
            return JsonSerializer.Deserialize<List<MeetingSession>>(json) ?? new List<MeetingSession>();
        }
        catch
        {
            return new List<MeetingSession>();
        }
    }

    public async Task SaveSessionsAsync(List<MeetingSession> sessions)
    {
        var json = JsonSerializer.Serialize(sessions, new JsonSerializerOptions { WriteIndented = true });
        await File.WriteAllTextAsync(_filePath, json);
    }
}
