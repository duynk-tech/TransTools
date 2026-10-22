import Foundation

enum LiveTranslationPacing: String, CaseIterable, Identifiable {
    case fast, balanced, contextual
    var id: String { rawValue }
    var title: String {
        switch self { case .fast: return "Nhanh"; case .balanced: return "Cân bằng"; case .contextual: return "Đủ ngữ cảnh" }
    }
    var pause: TimeInterval {
        switch self { case .fast: return 0.08; case .balanced: return 0.12; case .contextual: return 0.45 }
    }
    var maximumWait: TimeInterval {
        switch self { case .fast: return 0.25; case .balanced: return 0.45; case .contextual: return 1.0 }
    }
    private var fragmentPause: TimeInterval {
        switch self { case .fast: return 0.12; case .balanced: return 0.18; case .contextual: return 0.45 }
    }
    func ready(text: String, quiet: TimeInterval, elapsed: TimeInterval) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let sentenceEnded = trimmed.last.map { ".!?。！？".contains($0) } ?? false
        // Keep tiny fragments long enough to avoid translating every word,
        // without forcing the old 1.5 second wait in every pacing mode.
        let wordCount = trimmed.split(whereSeparator: { $0.isWhitespace }).count
        let isShortFragment = wordCount < 4 && !sentenceEnded
            && !trimmed.contains(where: { "。！？，、".contains($0) }) && trimmed.count < 16
        let contextPause = isShortFragment ? max(pause, fragmentPause) : pause
        if elapsed >= maximumWait && (!isShortFragment || quiet >= contextPause) { return true }
        return quiet >= (sentenceEnded ? min(pause, 0.25) : contextPause)
    }
}
