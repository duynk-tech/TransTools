import Foundation
import AVFoundation

public final class LocalNaturalTTSEngine: TTSEngine, @unchecked Sendable {
    public static let shared = LocalNaturalTTSEngine()

    public var isAvailable: Bool {
        return LocalTTSModelManager.isModelFileInstalled()
    }

    public var supportedLanguages: [String] {
        return ["vi", "vi-VN", "en", "en-US", "en-GB", "ja", "ja-JP", "ko", "ko-KR"]
    }

    private let stateQueue = DispatchQueue(label: "LocalNaturalTTSEngine.state")
    private var _isStopped = false
    private var isStopped: Bool {
        get { stateQueue.sync { _isStopped } }
        set { stateQueue.sync { _isStopped = newValue } }
    }

    private init() {}

    public func synthesize(
        text: String,
        language: String,
        options: TTSOptions = .default
    ) async throws -> TTSAudioResult {
        isStopped = false

        guard isAvailable else {
            throw NSError(
                domain: "LocalNaturalTTSEngine",
                code: -100,
                userInfo: [NSLocalizedDescriptionKey: "Mô hình Local Natural Voice chưa được tải về hoặc cài đặt."]
            )
        }

        try Task.checkCancellation()
        let prosody = options.prosody ?? RuleBasedProsodyProcessor.shared.process(
            text: text, context: ConversationContext(currentUtterance: text, detectedLanguage: language))
        let buffer = try await LocalTTSSession.shared.synthesizeChunk(text: text, prosody: prosody, language: language)
        try Task.checkCancellation()
        if let channel = buffer.floatChannelData?[0] {
            for frame in 0..<Int(buffer.frameLength) { channel[frame] *= max(0, min(1, options.volume)) }
        }
        guard !isStopped, let data = SystemTTSEngine.bufferToWav(buffer), !data.isEmpty else { throw CancellationError() }
        return TTSAudioResult(audioData: data, duration: Double(buffer.frameLength) / buffer.format.sampleRate,
                              sampleRate: buffer.format.sampleRate, engineType: "LocalNatural",
                              metadata: ["model": LocalTTSModelManifest.default.version])
    }

    public func stop() {
        isStopped = true
    }

    // MARK: - Sentence & Chunk Segmentation
    /// Segments text without breaking abbreviations, decimals, URLs, or honorifics
    public static func segmentIntoChunks(_ text: String) -> [String] {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        // Protect known abbreviations and patterns with placeholders
        var protected = trimmed

        // Protect URLs
        let urlRegex = try? NSRegularExpression(pattern: #"https?://[^\s]+"#, options: [])
        let urls = urlRegex?.matches(in: protected, range: NSRange(protected.startIndex..., in: protected)) ?? []
        var urlPlaceholders: [String: String] = [:]
        for (i, match) in urls.enumerated().reversed() {
            if let range = Range(match.range, in: protected) {
                let sub = String(protected[range])
                let token = "__URL_\(i)__"
                urlPlaceholders[token] = sub
                protected.replaceSubrange(range, with: token)
            }
        }

        // Protect Decimals (e.g. 3.14, 12.5)
        let decimalRegex = try? NSRegularExpression(pattern: #"\b\d+\.\d+\b"#, options: [])
        let decimals = decimalRegex?.matches(in: protected, range: NSRange(protected.startIndex..., in: protected)) ?? []
        var decimalPlaceholders: [String: String] = [:]
        for (i, match) in decimals.enumerated().reversed() {
            if let range = Range(match.range, in: protected) {
                let sub = String(protected[range])
                let token = "__DEC_\(i)__"
                decimalPlaceholders[token] = sub
                protected.replaceSubrange(range, with: token)
            }
        }

        // Protect Common Abbreviations & Honorifics
        let abbreviations = [
            "Mr.", "Mrs.", "Ms.", "Dr.", "Prof.", "Sr.", "Jr.",
            "e.g.", "i.e.", "etc.", "vs.", "al.", "U.S.", "A.I."
        ]
        for (i, abbr) in abbreviations.enumerated() {
            let token = "__ABBR_\(i)__"
            protected = protected.replacingOccurrences(of: abbr, with: token)
        }

        // Split on sentence boundaries: (. | ! | ? | \n) followed by whitespace or end of string
        var rawChunks: [String] = []
        var currentChunk = ""

        let punctuationSet: Set<Character> = [".", "!", "?", "。", "！", "？", "\n"]

        var iterator = protected.makeIterator()
        while let char = iterator.next() {
            currentChunk.append(char)
            if punctuationSet.contains(char) {
                let chunkTrimmed = currentChunk.trimmingCharacters(in: .whitespacesAndNewlines)
                if !chunkTrimmed.isEmpty {
                    rawChunks.append(chunkTrimmed)
                }
                currentChunk = ""
            }
        }

        let remaining = currentChunk.trimmingCharacters(in: .whitespacesAndNewlines)
        if !remaining.isEmpty {
            rawChunks.append(remaining)
        }

        // Restore placeholders
        var restoredChunks: [String] = []
        for var chunk in rawChunks {
            for (i, abbr) in abbreviations.enumerated() {
                chunk = chunk.replacingOccurrences(of: "__ABBR_\(i)__", with: abbr)
            }
            for (token, original) in decimalPlaceholders {
                chunk = chunk.replacingOccurrences(of: token, with: original)
            }
            for (token, original) in urlPlaceholders {
                chunk = chunk.replacingOccurrences(of: token, with: original)
            }
            if !chunk.isEmpty {
                restoredChunks.append(chunk)
            }
        }

        return restoredChunks.isEmpty ? [trimmed] : restoredChunks
    }
}
