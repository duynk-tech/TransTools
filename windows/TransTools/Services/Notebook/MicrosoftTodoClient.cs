using System.IO;
using System.Net;
using System.Net.Http;
using System.Net.Http.Headers;
using System.Text;
using System.Text.Json;
namespace TransTools.Services.Notebook;
// Authentication and explicit user export stay at the caller; this class does not store tokens.
public sealed record MicrosoftTodoList(string Id, string Name);
public sealed class MicrosoftTodoClient(HttpClient client)
{
    public async Task<IReadOnlyList<MicrosoftTodoList>> ListAsync(string accessToken, CancellationToken cancellationToken)
    {
        if (string.IsNullOrWhiteSpace(accessToken) || accessToken.Any(char.IsControl)) throw new ArgumentException("Cần đăng nhập Microsoft.");
        using var deadline = CancellationTokenSource.CreateLinkedTokenSource(cancellationToken); deadline.CancelAfter(TimeSpan.FromSeconds(30));
        var lists = new List<MicrosoftTodoList>();
        var url = new Uri("https://graph.microsoft.com/v1.0/me/todo/lists?$top=100");
        for (var page = 0; page < 20; page++) {
            using var request = new HttpRequestMessage(HttpMethod.Get, url);
            request.Headers.Authorization = new AuthenticationHeaderValue("Bearer", accessToken);
            using var response = await client.SendAsync(request, HttpCompletionOption.ResponseHeadersRead, deadline.Token);
            if (response.StatusCode is HttpStatusCode.Unauthorized or HttpStatusCode.Forbidden) throw new InvalidOperationException("Cần đăng nhập lại hoặc cấp quyền đọc danh sách Microsoft To Do.");
            response.EnsureSuccessStatusCode();
            await using var stream = await response.Content.ReadAsStreamAsync(deadline.Token);
            using var document = await JsonDocument.ParseAsync(stream, new JsonDocumentOptions { MaxDepth = 16 }, deadline.Token);
            if (document.RootElement.ValueKind != JsonValueKind.Object || !document.RootElement.TryGetProperty("value", out var rows) || rows.ValueKind != JsonValueKind.Array) throw new InvalidDataException("Microsoft chưa trả danh sách hợp lệ.");
            foreach (var row in rows.EnumerateArray()) {
                if (row.ValueKind == JsonValueKind.Object && row.TryGetProperty("id", out var id) && id.ValueKind == JsonValueKind.String && row.TryGetProperty("displayName", out var name) && name.ValueKind == JsonValueKind.String && !string.IsNullOrWhiteSpace(id.GetString()) && !lists.Any(list => list.Id == id.GetString())) lists.Add(new(id.GetString()!, name.GetString()!));
            }
            if (!document.RootElement.TryGetProperty("@odata.nextLink", out var next)) return lists;
            if (next.ValueKind != JsonValueKind.String || !Uri.TryCreate(next.GetString(), UriKind.Absolute, out var continuation) || continuation.Scheme != "https" || continuation.Host != "graph.microsoft.com" || !continuation.IsDefaultPort || continuation.UserInfo.Length != 0 || !continuation.AbsolutePath.Equals("/v1.0/me/todo/lists", StringComparison.Ordinal)) throw new InvalidDataException("Địa chỉ trang danh sách không hợp lệ.");
            url = continuation;
        }
        throw new InvalidDataException("Quá nhiều trang danh sách. Chưa tải đầy đủ.");
    }
    public async Task<string> CreateTaskAsync(string accessToken, string listId, string title, bool completed,
        string sessionTitle, string assignee, CancellationToken cancellationToken)
    {
        if (string.IsNullOrWhiteSpace(accessToken) || accessToken.Any(char.IsControl)) throw new ArgumentException("Cần đăng nhập Microsoft trước khi xuất việc.");
        if (string.IsNullOrWhiteSpace(listId) || listId.Length > 512) throw new ArgumentException("Chọn danh sách việc cần xuất.");
        using var request = new HttpRequestMessage(HttpMethod.Post, "https://graph.microsoft.com/v1.0/me/todo/lists/" + Uri.EscapeDataString(listId) + "/tasks");
        request.Headers.Authorization = new AuthenticationHeaderValue("Bearer", accessToken);
        request.Content = new StringContent(MicrosoftTodoPayload.Create(title, completed, sessionTitle, assignee), Encoding.UTF8, "application/json");
        using var deadline = CancellationTokenSource.CreateLinkedTokenSource(cancellationToken); deadline.CancelAfter(TimeSpan.FromSeconds(30));
        // Do not retry POST automatically: a lost response could otherwise duplicate a task.
        using var response = await client.SendAsync(request, HttpCompletionOption.ResponseHeadersRead, deadline.Token);
        if (response.StatusCode != HttpStatusCode.Created) {
            if (response.StatusCode is HttpStatusCode.Unauthorized or HttpStatusCode.Forbidden) throw new InvalidOperationException("Cần đăng nhập lại hoặc cấp quyền xuất việc vào Microsoft To Do.");
            throw new HttpRequestException("Chưa xác nhận được việc đã xuất. Kiểm tra danh sách To Do trước khi thử lại.", null, response.StatusCode);
        }
        await using var stream = await response.Content.ReadAsStreamAsync(deadline.Token);
        using var document = await JsonDocument.ParseAsync(stream, new JsonDocumentOptions { MaxDepth = 16 }, deadline.Token);
        if (!document.RootElement.TryGetProperty("id", out var id) || id.ValueKind != JsonValueKind.String || string.IsNullOrWhiteSpace(id.GetString())) throw new InvalidDataException("Microsoft chưa trả mã việc đã tạo. Kiểm tra danh sách trước khi thử lại.");
        return id.GetString()!;
    }
}
