using System.Text.Json;
namespace TransTools.Services.Notebook;
// Build only a user-reviewed task; never send the entire meeting transcript.
public static class MicrosoftTodoPayload
{
    public static string Create(string title, bool completed, string sessionTitle, string assignee = "")
    {
        title = title.Trim();
        if (title.Length == 0 || title.Length > 600) throw new ArgumentException("Nội dung việc cần từ 1 đến 600 ký tự.");
        var context = "Trans Tools · " + sessionTitle;
        if (!string.IsNullOrWhiteSpace(assignee)) context += "\nNgười phụ trách: " + assignee;
        return JsonSerializer.Serialize(new { title, status = completed ? "completed" : "notStarted", body = new { contentType = "text", content = context } });
    }
}
