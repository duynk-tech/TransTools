import Foundation

/// Conservative checks flag suspicious output; they are not a word-level ASR verifier.
enum VieNeuReadingPolicy {
    static func chunks(_ text: String, limit: Int = 140) -> [String] {
        var remaining = text.trimmingCharacters(in: .whitespacesAndNewlines)[...]
        var result: [String] = []
        while remaining.count > limit {
            let end = remaining.index(remaining.startIndex, offsetBy: limit)
            let prefix = remaining[..<end]
            let boundaries = prefix.indices.filter { index in
                let c = prefix[index]
                guard ",;:—".contains(c) else { return false }
                let next = remaining.index(after: index)
                return next == remaining.endIndex || remaining[next].isWhitespace
            }
            let meaningful = boundaries.filter { prefix[..<$0].split(whereSeparator: { $0.isWhitespace }).count >= 6 }
            let boundary = meaningful.last.map { remaining.index(after: $0) }
                ?? prefix.lastIndex(where: { $0.isWhitespace })
            guard let cut = boundary, cut > remaining.startIndex else { break }
            result.append(String(remaining[..<cut]).trimmingCharacters(in: .whitespacesAndNewlines))
            remaining = remaining[cut...].drop(while: { $0.isWhitespace })
        }
        if !remaining.isEmpty { result.append(String(remaining)) }
        return result
    }

    static func suspicious(samples: [Float], text: String) -> Bool {
        guard !samples.isEmpty, samples.allSatisfy({ $0.isFinite }) else { return true }
        let words = text.split(whereSeparator: { $0.isWhitespace }).filter { $0.contains(where: { $0.isLetter || $0.isNumber }) }.count
        let seconds = Double(samples.count) / 48000
        // Allow naturally brief vocabulary; only flag clearly truncated longer phrases.
        return samples.map(abs).max()! < 0.0001 || seconds < 0.10 || (words >= 5 && seconds < Double(words) * 0.065)
    }
}
