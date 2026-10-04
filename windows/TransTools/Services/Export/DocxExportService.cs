using System.IO;
using DocumentFormat.OpenXml;
using DocumentFormat.OpenXml.Packaging;
using DocumentFormat.OpenXml.Wordprocessing;
using TransTools.Models;

namespace TransTools.Services.Export;

public class DocxExportService
{
    public static void ExportMeetingSession(MeetingSession session, string filePath)
    {
        using var wordDocument = WordprocessingDocument.Create(filePath, WordprocessingDocumentType.Document);
        var mainPart = wordDocument.AddMainDocumentPart();
        mainPart.Document = new Document();
        var body = mainPart.Document.AppendChild(new Body());

        // Document Title
        var titlePara = body.AppendChild(new Paragraph());
        var titleRun = titlePara.AppendChild(new Run());
        titleRun.AppendChild(new Text(session.Title));
        titleRun.RunProperties = new RunProperties(new Bold(), new FontSize { Val = "36" }, new Color { Val = "003366" });

        // Meta Info
        var metaPara = body.AppendChild(new Paragraph());
        var metaRun = metaPara.AppendChild(new Run());
        metaRun.AppendChild(new Text($"Thời gian: {session.FormattedDate} | Thời lượng: {session.FormattedDuration} | Nguồn: {session.AudioSource}"));
        metaRun.RunProperties = new RunProperties(new Italic(), new FontSize { Val = "20" }, new Color { Val = "666666" });

        // Summary if present
        if (!string.IsNullOrWhiteSpace(session.Summary))
        {
            var summaryHead = body.AppendChild(new Paragraph());
            var sRun = summaryHead.AppendChild(new Run());
            sRun.AppendChild(new Text("Tóm tắt nội dung:"));
            sRun.RunProperties = new RunProperties(new Bold(), new FontSize { Val = "24" });

            var sumContent = body.AppendChild(new Paragraph());
            sumContent.AppendChild(new Run(new Text(session.Summary)));
        }

        // Notes if present
        if (!string.IsNullOrWhiteSpace(session.Notes))
        {
            var noteHead = body.AppendChild(new Paragraph());
            var nRun = noteHead.AppendChild(new Run());
            nRun.AppendChild(new Text("Ghi chú cuộc họp:"));
            nRun.RunProperties = new RunProperties(new Bold(), new FontSize { Val = "24" });

            var noteContent = body.AppendChild(new Paragraph());
            noteContent.AppendChild(new Run(new Text(session.Notes)));
        }

        // Transcript Header
        var transHead = body.AppendChild(new Paragraph());
        var tHeadRun = transHead.AppendChild(new Run());
        tHeadRun.AppendChild(new Text("Biên bản phụ đề chi tiết:"));
        tHeadRun.RunProperties = new RunProperties(new Bold(), new FontSize { Val = "26" }, new Color { Val = "003366" });

        foreach (var caption in session.Captions)
        {
            var p = body.AppendChild(new Paragraph());
            var timeRun = p.AppendChild(new Run(new Text($"[{caption.FormattedTimestamp}] ")));
            timeRun.RunProperties = new RunProperties(new Bold(), new Color { Val = "888888" });

            var origRun = p.AppendChild(new Run(new Text(caption.Original + " ")));
            var viRun = p.AppendChild(new Run(new Text(caption.Vietnamese)));
            viRun.RunProperties = new RunProperties(new Color { Val = "0066CC" });
        }
    }
}
