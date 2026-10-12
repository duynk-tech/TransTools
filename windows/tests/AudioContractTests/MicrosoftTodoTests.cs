using System.Net;
using System.Text.Json;
using TransTools.Services.Notebook;
internal static class MicrosoftTodoTests
{
    public static async Task RunAsync()
    {
        var handler = new Fixture(); using var http = new HttpClient(handler); var client = new MicrosoftTodoClient(http);
        var id = await client.CreateTaskAsync("test-token", "list/id", "Kiểm tra 日本語", true, "Cuộc họp", "Duy", CancellationToken.None);
        if (id != "task-123" || handler.Calls != 1 || handler.Uri != "https://graph.microsoft.com/v1.0/me/todo/lists/list%2Fid/tasks" || handler.Token != "Bearer test-token") throw new Exception("To Do request changed endpoint, escaped list ID or authentication");
        using var body = JsonDocument.Parse(handler.Body!);
        if (body.RootElement.GetProperty("title").GetString() != "Kiểm tra 日本語" || body.RootElement.GetProperty("status").GetString() != "completed") throw new Exception("To Do request changed reviewed task");
        foreach (var status in new[] { HttpStatusCode.Unauthorized, HttpStatusCode.Forbidden, HttpStatusCode.ServiceUnavailable }) {
            handler.Status = status; var before = handler.Calls;
            try { await client.CreateTaskAsync("test-token", "list", "Task", false, "Meeting", "", CancellationToken.None); throw new Exception("Failed To Do request reported success"); }
            catch (InvalidOperationException) when (status is HttpStatusCode.Unauthorized or HttpStatusCode.Forbidden) { }
            catch (HttpRequestException) when (status == HttpStatusCode.ServiceUnavailable) { }
            if (handler.Calls != before + 1) throw new Exception("To Do automatically retried task creation");
        }
        handler.Status = HttpStatusCode.Created; handler.Pending = true;
        using var cancellation = new CancellationTokenSource();
        var pending = client.CreateTaskAsync("test-token", "list", "Task", false, "Meeting", "", cancellation.Token);
        cancellation.Cancel();
        try { await pending; throw new Exception("Canceled To Do request succeeded"); } catch (OperationCanceledException) { }
        handler.Pending = false; handler.Status = HttpStatusCode.OK;
        handler.Response = "{\"value\":[{\"id\":\"list1\",\"displayName\":\"Công việc\"}]}";
        var lists = await client.ListAsync("test-token", CancellationToken.None);
        if (lists.Count != 1 || lists[0].Name != "Công việc") throw new Exception("To Do list selection lost labels");
        handler.Response = "{\"value\":[],\"@odata.nextLink\":\"https://example.com/steal\"}";
        var beforeInvalidPage = handler.Calls;
        try { await client.ListAsync("test-token", CancellationToken.None); throw new Exception("Untrusted list continuation accepted"); } catch (InvalidDataException) { }
        if (handler.Calls != beforeInvalidPage + 1) throw new Exception("Token sent to untrusted continuation host");
        Console.WriteLine("PASS: To Do payload, authentication, escaped ID, errors, no retries and cancellation");
    }
    private sealed class Fixture : HttpMessageHandler
    {
        public string Response = "{\"id\":\"task-123\"}";
        public int Calls; public string? Uri, Token, Body; public bool Pending; public HttpStatusCode Status = HttpStatusCode.Created;
        protected override async Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken token)
        {
            Calls++; Uri = request.RequestUri!.AbsoluteUri; Token = request.Headers.Authorization?.ToString(); Body = request.Content == null ? "" : await request.Content.ReadAsStringAsync(token);
            if (Pending) await Task.Delay(Timeout.Infinite, token);
            return new HttpResponseMessage(Status) { Content = new StringContent(Response) };
        }
    }
}
