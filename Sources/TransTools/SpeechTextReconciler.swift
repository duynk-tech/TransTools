import Foundation

/// Match recognizer revisions by words, ignoring case and punctuation.
enum SpeechTextReconciler {
    /// Match the formatted text to timestamped speech segments without rebuilding
    /// punctuation. This lets a restarted recognizer replay audio without erasing
    /// or duplicating words already committed to the meeting transcript.
    static func timedRanges(_ text: String, segments: [(String, Double, Double)]) -> [(Range<String.Index>, Double, Double)]? {
        var cursor = text.startIndex
        var ranges: [(Range<String.Index>, Double, Double)] = []
        for (word, start, end) in segments {
            guard !word.isEmpty, start.isFinite, end.isFinite,
                  let range = text.range(of: word, options: [.caseInsensitive, .diacriticInsensitive], range: cursor..<text.endIndex) else { return nil }
            ranges.append((range, start, end))
            cursor = range.upperBound
        }
        return ranges.isEmpty ? nil : ranges
    }

    static func remainder(_ text: String, segments: [(String, Double, Double)], through boundary: Double) -> String? {
        guard let ranges = timedRanges(text, segments: segments) else { return nil }
        let consumed = ranges.prefix(while: { $0.2 <= boundary + 0.06 }).count
        guard consumed > 0 else { return text }
        // Only discard a contiguous replay prefix, never words in the middle.
        guard !ranges.dropFirst(consumed).contains(where: { $0.2 <= boundary + 0.06 }) else { return nil }
        guard consumed < ranges.count else { return "" }
        return String(text[ranges[consumed].0.lowerBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func endTime(ofPrefix prefix: String, in text: String, segments: [(String, Double, Double)]) -> Double? {
        guard text.hasPrefix(prefix), let ranges = timedRanges(text, segments: segments) else { return nil }
        let boundary = text.index(text.startIndex, offsetBy: prefix.count)
        return ranges.last(where: { $0.0.upperBound <= boundary })?.2
    }
    /// A growing hypothesis may reuse a translation only while its entire source prefix is unchanged.
    static func canPublishTranslation(source: String, current: String) -> Bool {
        if source == current { return true }
        guard current.hasPrefix(source), current.count > source.count else { return false }
        let boundary = current.index(current.startIndex, offsetBy: source.count)
        return current[boundary].isWhitespace || source.unicodeScalars.contains(where: { $0.value >= 0x2E80 })
    }
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
        // A cumulative hypothesis can revise the last word of an already
        // committed clause ("integration tests" -> "integration test").
        // Require a substantial unchanged opening and only one edit near its
        // boundary; unrelated tails must remain new speech.
        let shared = zip(a, b).prefix(while: { $0 == $1 }).count
        if shared >= 8, b.count - shared <= 3, a.count >= b.count - 1 {
            let oldTail = Array(b.dropFirst(shared))
            var candidates: [(Int, Int)] = []
            for boundary in max(shared, b.count - 1)...min(a.count, b.count + 1) {
                let newTail = Array(a[shared..<boundary])
                var costs = Array(0...newTail.count)
                for (row, word) in oldTail.enumerated() {
                    var next = [row + 1]
                    for (column, actual) in newTail.enumerated() {
                        next.append(min(costs[column] + (word == actual ? 0 : 1), costs[column + 1] + 1, next[column] + 1))
                    }
                    costs = next
                }
                if costs.last! <= 1 { candidates.append((boundary, costs.last!)) }
            }
            // Prefer the same word count on tied edits; never consume extra
            // new words merely because an insertion also has distance one.
            if let best = candidates.min(by: {
                $0.1 == $1.1 ? abs($0.0 - b.count) < abs($1.0 - b.count) : $0.1 < $1.1
            }) {
                return input.dropFirst(best.0).joined(separator: " ")
            }
        }
        return nil // New utterance rather than blindly dropping a word count.
    }
    static func keepLongerPartial(_ previous: String, incoming: String, final: Bool) -> String {
        let old = words(previous).map(normalized), next = words(incoming).map(normalized)
        if old.count > next.count, old.starts(with: next) { return previous }
        if !old.starts(with: Array(next.prefix(min(2, next.count)))) {
            for count in stride(from: min(old.count, next.count), through: 2, by: -1) {
                if old.suffix(count) == next.prefix(count) {
                    return (words(previous).dropLast(count) + words(incoming)).joined(separator: " ")
                }
            }
        }
        return incoming
    }
    /// Rolling hypotheses may retain a committed opening but replace an entire
    /// spoken tail. Preserve that tail when this looks like new speech rather
    /// than a spelling correction; return only the newly introduced words.
    static func replacementTail(_ previous: String, incoming: String) -> String? {
        let oldWords = words(previous), newWords = words(incoming)
        let old = oldWords.map(normalized), next = newWords.map(normalized)
        let shared = zip(old, next).prefix(while: { $0 == $1 }).count
        guard shared >= 3, old.count - shared >= 3, next.count - shared >= 3 else { return nil }
        let fillers: Set<String> = ["i", "a", "an", "the", "to", "you", "it", "is", "only", "do", "not", "with", "can"]
        let oldTail = Set(old.dropFirst(shared)).subtracting(fillers)
        let newTail = Set(next.dropFirst(shared)).subtracting(fillers)
        guard !oldTail.isEmpty, !newTail.isEmpty, oldTail.isDisjoint(with: newTail) else { return nil }
        let start = ["i", "you", "we", "he", "she", "they"].contains(next[shared - 1]) ? shared - 1 : shared
        return newWords.dropFirst(start).joined(separator: " ")
    }
    static func beginsNewUtterance(_ previous: String, incoming: String) -> Bool {
        let old = words(previous).map(normalized), next = words(incoming).map(normalized)
        guard old.count >= 2, next.count >= 3 else { return false }
        if old.count <= 3 {
            let filler: Set<String> = ["i", "a", "an", "the", "to", "only", "you", "it", "is"]
            if !Set(old).subtracting(filler).intersection(Set(next).subtracting(filler)).isEmpty { return false }
        }
        // Preserve revisions and tails that retain the same opening phrase.
        // A rolling recognizer can omit isFinal and reset its timestamps; an
        // unrelated opening must be appended rather than overwrite received text.
        func contains(_ words: [String], _ opening: [String]) -> Bool {
            guard words.count >= opening.count else { return false }
            return (0...(words.count - opening.count)).contains { Array(words[$0..<($0 + opening.count)]) == opening }
        }
        return !contains(old, Array(next.prefix(2))) && !contains(next, Array(old.prefix(2)))
    }
}

/// Caption chunks preserve the original text; sentence boundaries come from
/// Foundation's linguistic segmentation, with a safety limit for unpunctuated speech.
enum CaptionSegmenter {
    /// Silence is a secondary boundary when the recognizer omits punctuation.
    /// Slice the original hypothesis so pauses never discard or rewrite words.
    static func chunks(_ text: String, raw: String, segments: [(String, Double, Double)]) -> [String] {
        guard let suffix = raw.range(of: text, options: .backwards), suffix.upperBound == raw.endIndex,
              let ranges = SpeechTextReconciler.timedRanges(raw, segments: segments) else { return chunks(text) }
        let active = ranges.filter { $0.0.lowerBound >= suffix.lowerBound }
        var start = suffix.lowerBound
        var result: [String] = []
        for index in active.indices.dropFirst() {
            let previous = active[index - 1], next = active[index]
            let phrase = String(raw[start..<next.0.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
            if next.1 - previous.2 >= 0.65, SpeechTextReconciler.words(phrase).count >= 3 {
                result += chunks(phrase)
                start = next.0.lowerBound
            }
        }
        result += chunks(String(raw[start...]))
        return result
    }
    static func chunks(_ text: String, characterLimit: Int = 160, wordLimit: Int = 28) -> [String] {
        let characterLimit = max(40, characterLimit), wordLimit = max(8, wordLimit)
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
            while remaining.count > characterLimit || SpeechTextReconciler.words(remaining).count > wordLimit {
                var wordCount = 0
                var previousWasSpace = true
                var boundary = remaining.startIndex
                var naturalBoundary: String.Index?
                for (offset, index) in remaining.indices.enumerated() {
                    let character = remaining[index]
                    if !character.isWhitespace && previousWasSpace { wordCount += 1 }
                    previousWasSpace = character.isWhitespace
                    if offset >= characterLimit / 3 && (character.isWhitespace || ",;:，、；：".contains(character)) {
                        naturalBoundary = remaining.index(after: index)
                    }
                    if offset >= characterLimit - 1 || wordCount > wordLimit {
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
