import Foundation
import AVFoundation

@MainActor
public final class TTSEngineRouter: ObservableObject {
    public static let shared = TTSEngineRouter()
    public var prosodyProcessor: ProsodyProcessing = RuleBasedProsodyProcessor.shared
    public let localEngine = LocalNaturalTTSEngine.shared
    public let systemEngine = SystemTTSEngine.shared
    public let audioPlayer = TTSAudioPlayer.shared
    private var generation = UUID()
    private init() {}

    public func synthesizeAndPlay(text: String, language: String, context: ConversationContext? = nil,
                                  options: TTSOptions = .default, utteranceID: UUID = UUID(),
                                  onComplete: (@Sendable () -> Void)? = nil) async throws -> TTSAudioResult {
        let token = UUID(); generation = token
        let start = Date()
        let context = context ?? ConversationContext(currentUtterance: text, detectedLanguage: language)
        let code = language.lowercased().split(separator: "-").first.map(String.init) ?? language
        // The caller uses direct AVSpeechSynthesizer fallback, without cloud requests.
        guard localEngine.isAvailable, localEngine.supportedLanguages.contains(code) else {
            throw NSError(domain: "LocalTTS", code: 20, userInfo: [NSLocalizedDescriptionKey: "Mô hình chưa cài hoặc ngôn ngữ chưa hỗ trợ."])
        }
        let chunks = LocalNaturalTTSEngine.segmentIntoChunks(text).flatMap { chunkTextForPlayback($0, limit: code == "ja" || code == "ko" ? 120 : 200) }
        guard !chunks.isEmpty else { throw CancellationError() }
        audioPlayer.stop()
        var last: TTSAudioResult?
        for (index, chunk) in chunks.enumerated() {
            try Task.checkCancellation()
            guard generation == token else { throw CancellationError() }
            var adjusted = options
            var prosody = prosodyProcessor.process(text: chunk, context: context)
            // Preserve user speed; semantic rate is relative to the rule processor's baseline.
            prosody = ProsodyResult(text: prosody.text, emotion: prosody.emotion,
                                    rate: max(0.25, min(0.75, options.rate * prosody.rate / 0.44)),
                                    emphasis: prosody.emphasis, pauses: prosody.pauses)
            adjusted.prosody = prosody
            let result = try await localEngine.synthesize(text: chunk, language: language, options: adjusted)
            try Task.checkCancellation()
            guard generation == token else { throw CancellationError() }
            try audioPlayer.play(result: result, utteranceID: utteranceID, overridePolicy: .queueSpeech,
                                 onComplete: index == chunks.count - 1 ? onComplete : nil)
            last = result
            #if DEBUG
            if index == 0 { print("[TTS] Engine: LocalNatural Language: \(language) Model: \(LocalTTSModelManifest.default.version) Prosody: \(prosody.emotion.rawValue) First audio: \(Int(Date().timeIntervalSince(start) * 1000)) ms") }
            #endif
        }
        return last!
    }
    /// Keep chunks small without cutting a word, URL, decimal or abbreviation.
    private func chunkTextForPlayback(_ text: String, limit: Int) -> [String] {
        guard text.count > limit else { return [text] }
        let words = text.split(whereSeparator: { $0.isWhitespace })
        guard words.count > 1 else { return [text] }
        var result: [String] = [], current = ""
        for word in words {
            if !current.isEmpty && current.count + word.count + 1 > limit { result.append(current); current = "" }
            current += (current.isEmpty ? "" : " ") + word
        }
        if !current.isEmpty { result.append(current) }
        return result
    }
    public func stop() {
        generation = UUID(); localEngine.stop(); systemEngine.stop(); audioPlayer.stop()
    }
}
