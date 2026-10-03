import Foundation

enum LiveTranslationPacing: String, CaseIterable, Identifiable {
    case fast, balanced, contextual
    var id: String { rawValue }
    var title: String {
        switch self { case .fast: return "Nhanh"; case .balanced: return "Cân bằng"; case .contextual: return "Đủ ngữ cảnh" }
    }
    var pause: TimeInterval {
        switch self { case .fast: return 0.3; case .balanced: return 0.8; case .contextual: return 1.2 }
    }
    var maximumWait: TimeInterval {
        switch self { case .fast: return 1; case .balanced: return 2; case .contextual: return 3 }
    }
    func ready(text: String, quiet: TimeInterval, elapsed: TimeInterval) -> Bool {
        if elapsed >= maximumWait { return true }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let sentenceEnded = trimmed.last.map { ".!?。！？".contains($0) } ?? false
        return quiet >= (sentenceEnded ? min(pause, 0.25) : pause)
    }
}
