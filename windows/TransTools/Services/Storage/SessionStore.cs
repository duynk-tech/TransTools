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

    public SessionStore(string? directory = null)
    {
        var appData = Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData);
        var dir = directory ?? Path.Combine(appData, "TransTools");
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

    // Read/modify/write under one gate so meeting persistence cannot overwrite notes or an AI summary.
    public async Task<MeetingSession> UpdateSessionAsync(Guid id, Func<MeetingSession> create, Action<MeetingSession> update)
    {
        await WriteLock.WaitAsync();
        try {
            var sessions = await LoadSessionsAsync();
            var session = sessions.FirstOrDefault(value => value.Id == id);
            if (session == null) { session = create(); session.Id = id; sessions.Insert(0, session); }
            update(session);
            await WriteCoreAsync(sessions);
            return session;
        } finally { WriteLock.Release(); }
    }
    private async Task WriteCoreAsync(List<MeetingSession> sessions)
    {
        var json = JsonSerializer.Serialize(sessions, new JsonSerializerOptions { WriteIndented = true });
        var temporary = _filePath + ".tmp";
        await File.WriteAllTextAsync(temporary, json);
        File.Move(temporary, _filePath, overwrite: true);
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
