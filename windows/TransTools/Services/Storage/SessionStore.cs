using System;
using System.Collections.Generic;
using System.IO;
using System.Text.Json;
using System.Threading.Tasks;
using System.Threading;
using TransTools.Models;

namespace TransTools.Services.Storage;

public class SessionStore
{
    private readonly string _filePath;
    private static readonly SemaphoreSlim WriteLock = new(1, 1);

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
        catch (JsonException ex)
        {
            throw new InvalidDataException("Dữ liệu sổ tay bị lỗi; giữ nguyên tệp để khôi phục.", ex);
        }
    }

    public async Task SaveSessionsAsync(List<MeetingSession> sessions)
    {
        var json = JsonSerializer.Serialize(sessions, new JsonSerializerOptions { WriteIndented = true });
        await WriteLock.WaitAsync();
        try
        {
            var temporary = _filePath + ".tmp";
            await File.WriteAllTextAsync(temporary, json);
            File.Move(temporary, _filePath, overwrite: true);
        }
        finally { WriteLock.Release(); }
    }
}
