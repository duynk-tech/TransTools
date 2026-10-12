using System.Text.Json;
using TransTools.Models;

namespace TransTools.Services.Notebook;

public sealed record MeetingTask(string Title, string Assignee);

public static class MeetingTaskExtractor
{
    public static async Task<IReadOnlyList<MeetingTask>> ExtractAsync(MeetingSession session,
        Func<string, CancellationToken, Task<string>>? generate, CancellationToken token)
    {
        var transcript = string.Join("\n", session.Captions.Select(c => c.Original + (string.IsNullOrWhiteSpace(c.Vietnamese) ? "" : " (" + c.Vietnamese + ")")));
        if (string.IsNullOrWhiteSpace(transcript)) return [];
        if (generate != null) {
            try {
                using var request = CancellationTokenSource.CreateLinkedTokenSource(token);
                request.CancelAfter(TimeSpan.FromSeconds(40));
                var response = await generate(transcript[..Math.Min(transcript.Length, 6000)], request.Token).WaitAsync(request.Token);
                token.ThrowIfCancellationRequested();
                var parsed = Parse(response);
                if (parsed != null) return parsed;
            } catch (OperationCanceledException) when (token.IsCancellationRequested) { throw; }
            catch (OperationCanceledException) { } // Provider deadline: retain transcript and use the existing local fallback.
            catch (Exception ex) when (ex is System.Net.Http.HttpRequestException or JsonException or InvalidOperationException or TaskCanceledException) { }
        }
        token.ThrowIfCancellationRequested();
        var keywords = new[] { "cần ", "sẽ ", "phải ", "nhờ ", "gửi ", "kiểm tra", "chuẩn bị", "báo cáo", "review", "deadline", "update", "deploy", "fix", "follow up", "hạn chót", "ngày mai", "tuần sau", "will do", "need to", "must", "please", "action item", "todo", "assign" };
        return session.Captions.Select(c => string.IsNullOrWhiteSpace(c.Vietnamese) ? c.Original : c.Vietnamese)
            .Select(t => t.Trim()).Where(t => t.Length > 10 && t.Length < 600 && keywords.Any(k => t.Contains(k, StringComparison.OrdinalIgnoreCase)))
            .Distinct(StringComparer.OrdinalIgnoreCase).Take(8).Select(t => new MeetingTask(t, "")).ToArray();
    }

    public static IReadOnlyList<MeetingTask>? Parse(string response)
    {
        if (response.Length > 32000) return null;
        var text = response.Trim();
        if (text.StartsWith("```")) {
            var start = text.IndexOf('\n'); var end = text.LastIndexOf("```", StringComparison.Ordinal);
            if (start < 0 || end <= start) return null;
            text = text[(start + 1)..end].Trim();
        }
        try {
            using var doc = JsonDocument.Parse(text, new JsonDocumentOptions { MaxDepth = 8 });
            if (doc.RootElement.ValueKind != JsonValueKind.Array) return null;
            var tasks = new List<MeetingTask>();
            foreach (var item in doc.RootElement.EnumerateArray()) {
                if (item.ValueKind != JsonValueKind.Object || !item.TryGetProperty("title", out var titleValue) || titleValue.ValueKind != JsonValueKind.String) continue;
                var title = titleValue.GetString()!.Trim();
                if (title.Length == 0 || title.Length > 600 || tasks.Any(t => t.Title.Equals(title, StringComparison.OrdinalIgnoreCase))) continue;
                var assignee = item.TryGetProperty("assignee", out var a) && a.ValueKind == JsonValueKind.String ? a.GetString()!.Trim() : "";
                if (assignee.Length > 100) assignee = "";
                tasks.Add(new(title, assignee));
                if (tasks.Count == 20) break;
            }
            return tasks;
        } catch (JsonException) { return null; }
    }
}
