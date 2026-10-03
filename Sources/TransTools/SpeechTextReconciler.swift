import Foundation

/// Match recognizer revisions by words, ignoring case and punctuation.
enum SpeechTextReconciler {
    static func words(_ text: String) -> [String] { text.split(whereSeparator: { $0.isWhitespace }).map(String.init) }
    static func normalized(_ word: String) -> String {
        word.lowercased().trimmingCharacters(in: .punctuationCharacters)
    }
    static func removingOverlap(_ text: String, after previous: String) -> String {
        let input = words(text), tail = Array(words(previous).suffix(32))
        guard !input.isEmpty, !tail.isEmpty else { return text }
        guard min(input.count, tail.count) >= 2 else { return text }
        for count in stride(from: min(input.count, tail.count), through: 2, by: -1) {
            if tail.suffix(count).map(normalized) == input.prefix(count).map(normalized) {
                return input.dropFirst(count).joined(separator: " ")
            }
        }
        return text
    }
    /// Locate the committed boundary even if punctuation or earlier words were revised.
    static func remainder(_ text: String, committed: String) -> String? {
        let input = words(text), prefix = words(committed)
        guard !prefix.isEmpty else { return text }
        let a = input.map(normalized), b = prefix.map(normalized)
        if a.starts(with: b) { return input.dropFirst(b.count).joined(separator: " ") }
        if b.starts(with: a) { return "" } // Temporary shorter hypothesis: keep the existing live row.
        let anchor = Array(b.suffix(min(4, b.count)))
        guard a.count >= anchor.count else { return nil }
        for index in 0...(a.count - anchor.count) {
            if Array(a[index..<(index + anchor.count)]) == anchor {
                return input.dropFirst(index + anchor.count).joined(separator: " ")
            }
        }
        return nil // New utterance rather than blindly dropping a word count.
    }
    static func keepLongerPartial(_ previous: String, incoming: String, final: Bool) -> String {
        let old = words(previous).map(normalized), next = words(incoming).map(normalized)
        if old.count > next.count, old.starts(with: next) { return previous }
        return incoming
    }
}
