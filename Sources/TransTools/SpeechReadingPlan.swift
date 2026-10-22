import Foundation

enum SpeechReadingPlan {
    struct Part { let text: String; var pause: Double }
    static func parts(_ text: String, sentencePause: Double, paragraphPause: Double) -> [Part] {
        var result: [Part] = []
        for paragraph in text.components(separatedBy: .newlines) {
            let content = paragraph.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !content.isEmpty else { continue }
            content.enumerateSubstrings(in: content.startIndex..<content.endIndex, options: .bySentences) { sentence, _, _, _ in
                if let sentence, !sentence.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    result.append(Part(text: sentence, pause: max(0, min(2, sentencePause))))
                }
            }
            if !result.isEmpty { result[result.count - 1].pause = max(0, min(4, paragraphPause)) }
        }
        return result
    }
}
