using System.Text;
using TransTools.Models;

namespace TransTools.Services.Export;

public static class TextExportService
{
    public static string Format(MeetingSession session)
    {
        var text = new StringBuilder();
        text.AppendLine("TRANS TOOLS — SỔ TAY");
        text.AppendLine($"Tiêu đề: {session.Title}");
        text.AppendLine($"Thời gian: {session.FormattedDate}");
        text.AppendLine($"Nguồn: {session.AudioSource}");
        text.AppendLine($"Số đoạn hội thoại: {session.Captions.Count}");
        text.AppendLine();
        if (!string.IsNullOrWhiteSpace(session.Notes)) {
            text.AppendLine("[GHI CHÚ]"); text.AppendLine(session.Notes); text.AppendLine();
        }
        text.AppendLine("[NỘI DUNG HỘI THOẠI SONG NGỮ]");
        for (var i = 0; i < session.Captions.Count; i++) {
            var caption = session.Captions[i];
            text.AppendLine($"#{i + 1} [{caption.FormattedTimestamp}]");
            text.AppendLine("Gốc: " + caption.Original);
            text.AppendLine("Dịch: " + caption.Vietnamese);
            text.AppendLine();
        }
        return text.ToString();
    }
}
