import Foundation

enum NotebookSubtitleExport {
    static func content(captions: [CaptionRecord], mode: Int) -> String {
        captions.enumerated().map { index, item in
            let text: String
            switch mode {
            case 1: text = item.original
            case 2: text = item.vietnamese.isEmpty ? item.original : item.vietnamese
            default: text = item.original + (item.vietnamese.isEmpty ? "" : "\n" + item.vietnamese)
            }
            return "\(index + 1)\n\(MeetingModel.timestamp(item.start)) --> \(MeetingModel.timestamp(max(item.end, item.start + 0.1)))\n\(text)\n"
        }.joined(separator: "\n")
    }
}
