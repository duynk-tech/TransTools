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
        // Character prefixes also support scripts without spaces (Chinese/Japanese).
        if committed.unicodeScalars.contains(where: { $0.value >= 0x2E80 }), text.hasPrefix(committed) {
            return String(text.dropFirst(committed.count)).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if text.unicodeScalars.contains(where: { $0.value >= 0x2E80 }), committed.hasPrefix(text) { return "" }
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

/// Caption chunks preserve the original text; sentence boundaries come from
/// Foundation's linguistic segmentation, with a safety limit for unpunctuated speech.
enum CaptionSegmenter {
    static func chunks(_ text: String) -> [String] {
        var sentences: [String] = []
        text.enumerateSubstrings(in: text.startIndex..<text.endIndex, options: [.bySentences, .substringNotRequired]) { _, range, _, _ in
            sentences.append(String(text[range]))
        }
        if sentences.isEmpty { sentences = [text] }
        // Foundation can treat titles such as “Dr.” as a standalone sentence.
        let abbreviations: Set<String> = ["mr", "mrs", "ms", "dr", "prof", "sr", "jr", "e.g", "i.e", "vs", "etc"]
        var merged: [String] = []
        for sentence in sentences {
            if let previous = merged.last,
               let lastWord = SpeechTextReconciler.words(previous).last,
               abbreviations.contains(SpeechTextReconciler.normalized(lastWord)) {
                merged[merged.count - 1] += sentence
            } else { merged.append(sentence) }
        }
        return merged.flatMap { sentence -> [String] in
            var remaining = sentence.trimmingCharacters(in: .whitespacesAndNewlines)
            var result: [String] = []
            while remaining.count > 160 || SpeechTextReconciler.words(remaining).count > 28 {
                var wordCount = 0
                var previousWasSpace = true
                var boundary = remaining.startIndex
                var naturalBoundary: String.Index?
                for (offset, index) in remaining.indices.enumerated() {
                    let character = remaining[index]
                    if !character.isWhitespace && previousWasSpace { wordCount += 1 }
                    previousWasSpace = character.isWhitespace
                    if offset >= 60 && (character.isWhitespace || ",;:，、；：".contains(character)) {
                        naturalBoundary = remaining.index(after: index)
                    }
                    if offset >= 159 || wordCount > 28 {
                        boundary = naturalBoundary ?? index
                        break
                    }
                }
                guard boundary > remaining.startIndex else { break }
                result.append(String(remaining[..<boundary]).trimmingCharacters(in: .whitespacesAndNewlines))
                remaining = String(remaining[boundary...]).trimmingCharacters(in: .whitespacesAndNewlines)
            }
            if !remaining.isEmpty { result.append(remaining) }
            return result
        }
    }
}
