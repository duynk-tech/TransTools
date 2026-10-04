import Foundation
import AVFoundation

@MainActor
public final class TTSEngineRouter: ObservableObject {
    public static let shared = TTSEngineRouter()
    public var prosodyProcessor: ProsodyProcessing = RuleBasedProsodyProcessor.shared
    public let localEngine = LocalNaturalTTSEngine.shared
    public let systemEngine = SystemTTSEngine.shared
    public let audioPlayer = TTSAudioPlayer.shared
    @Published public private(set) var isProcessing = false
    private var generation = UUID()
    private var startedAudio = false
    private init() {}

    public func synthesizeAndPlay(text: String, language: String, context: ConversationContext? = nil,
                                  options: TTSOptions = .default, engine: LanguageVoiceEngine = .local, utteranceID: UUID = UUID(),
                                  onComplete: (@Sendable () -> Void)? = nil) async throws -> TTSAudioResult {
        let token = UUID(); generation = token; isProcessing = true; startedAudio = false
        defer { if generation == token { isProcessing = false } }
        let start = Date()
        let voice = engine.externalModel?.selectedVoice(for: language)
        let context = context ?? ConversationContext(currentUtterance: text, detectedLanguage: language)
        let code = language.lowercased().split(separator: "-").first.map(String.init) ?? language
        guard ExternalTTSModelManager.shared.installing == nil else {
            throw NSError(domain: "LocalTTS", code: 21, userInfo: [NSLocalizedDescriptionKey: "Đang cài mô hình. Dùng giọng dự phòng trong lúc chờ."])
        }
        if let model = engine.externalModel {
            guard model.availableOnDevice, model.isInstalled, model.languages.contains(code) else {
                throw NSError(domain: "LocalTTS", code: 20, userInfo: [NSLocalizedDescriptionKey: "Mô hình chưa cài hoặc ngôn ngữ chưa hỗ trợ."])
            }
            await LocalTTSSession.shared.releaseAndWait()
        } else {
            guard localEngine.isAvailable, localEngine.supportedLanguages.contains(code) else {
                throw NSError(domain: "LocalTTS", code: 20, userInfo: [NSLocalizedDescriptionKey: "Mô hình chưa cài hoặc ngôn ngữ chưa hỗ trợ."])
            }
            await ExternalTTSSession.shared.releaseAndWait()
        }
        try Task.checkCancellation()
        guard generation == token else { throw CancellationError() }
        let limit = engine.externalModel == nil ? 200 : 140
        let chunks = LocalNaturalTTSEngine.segmentIntoChunks(text).flatMap { chunkTextForPlayback($0, limit: code == "zh" || code == "ja" || code == "ko" ? 90 : limit) }
        guard !chunks.isEmpty else { throw CancellationError() }
        audioPlayer.stop()
        var last: TTSAudioResult?
        for (index, chunk) in chunks.enumerated() {
            try Task.checkCancellation()
            guard generation == token else { throw CancellationError() }
            try await audioPlayer.waitForQueueCapacity()
            guard generation == token else { throw CancellationError() }
            var adjusted = options
            var prosody = prosodyProcessor.process(text: chunk, context: context)
            // Preserve user speed; semantic rate is relative to the rule processor's baseline.
            prosody = ProsodyResult(text: prosody.text, emotion: prosody.emotion,
                                    rate: max(0.25, min(0.75, options.rate * prosody.rate / 0.44)),
                                    emphasis: prosody.emphasis, pauses: prosody.pauses)
            adjusted.prosody = prosody
            let result: TTSAudioResult
            if let model = engine.externalModel {
                // Preserve semantic content: model-specific style tags are never inserted into lessons.
                do {
                result = try await ExternalTTSSession.shared.synthesize(model: model, text: chunk, language: language, options: options, voice: voice, onChunk: { [weak self] packet in
                    guard let self else { throw CancellationError() }
                    try await self.enqueuePacket(packet, token: token, utteranceID: utteranceID, playbackRate: max(0.7, min(1.5, options.rate / 0.44)))
                })
                } catch {
                    if generation == token && startedAudio && !(error is CancellationError) {
                        throw NSError(domain: "LocalTTS", code: 22, userInfo: [NSLocalizedDescriptionKey: error.localizedDescription, "audioStarted": true])
                    }
                    throw error
                }
            } else {
                result = try await localEngine.synthesize(text: chunk, language: language, options: adjusted)
            }
            try Task.checkCancellation()
            guard generation == token else { throw CancellationError() }
            if engine.externalModel == nil {
                try audioPlayer.play(result: result, utteranceID: utteranceID, overridePolicy: .queueSpeech,
                                     onComplete: index == chunks.count - 1 ? onComplete : nil)
            } else if index == chunks.count - 1 {
                audioPlayer.completeAfterPlayback(utteranceID: utteranceID, onComplete)
            }
            last = result
            #if DEBUG
            if index == 0 { print("[TTS] Engine: LocalNatural Language: \(language) Model: \(engine.title) Prosody: \(prosody.emotion.rawValue) First audio: \(Int(Date().timeIntervalSince(start) * 1000)) ms") }
            #endif
        }
        return last!
    }
    private func enqueuePacket(_ packet: TTSAudioResult, token: UUID, utteranceID: UUID, playbackRate: Float) async throws {
        guard generation == token else { throw CancellationError() }
        try await audioPlayer.waitForQueueCapacity()
        guard generation == token else { throw CancellationError() }
        try audioPlayer.play(result: packet, utteranceID: utteranceID, overridePolicy: .queueSpeech, playbackRate: playbackRate)
        startedAudio = true
    }
    /// Export incrementally to disk: no full-paragraph WAV held in memory and no implicit engine switch.
    func exportWAV(text: String, language: String, engine: LanguageVoiceEngine, options: TTSOptions) async throws -> URL {
        guard engine.isLocal, ExternalTTSModelManager.shared.installing == nil else { throw URLError(.unsupportedURL) }
        let token = UUID(); generation = token; isProcessing = true
        defer { if generation == token { isProcessing = false } }
        let code = LanguageVoicePreferences.code(language)
        let voice = engine.externalModel?.selectedVoice(for: language)
        if let model = engine.externalModel {
            guard model.isInstalled, model.languages.contains(code) else { throw URLError(.unsupportedURL) }
            await LocalTTSSession.shared.releaseAndWait()
        } else {
            guard localEngine.isAvailable, localEngine.supportedLanguages.contains(code) else { throw URLError(.unsupportedURL) }
            await ExternalTTSSession.shared.releaseAndWait()
        }
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("TransTools-" + UUID().uuidString + ".wav")
        FileManager.default.createFile(atPath: file.path, contents: Data(repeating: 0, count: 44))
        let handle = try FileHandle(forWritingTo: file)
        var success = false
        defer { try? handle.close(); if !success { try? FileManager.default.removeItem(at: file) } }
        try handle.seekToEnd()
        var bytes: UInt32 = 0, rate: UInt32 = 0, channels: UInt16 = 0
        let chunks = LocalNaturalTTSEngine.segmentIntoChunks(text).flatMap { chunkTextForPlayback($0, limit: code == "zh" || code == "ja" || code == "ko" ? 90 : 140) }
        for chunk in chunks {
            try Task.checkCancellation(); guard generation == token else { throw CancellationError() }
            let result: TTSAudioResult
            if let model = engine.externalModel {
                result = try await ExternalTTSSession.shared.synthesize(model: model, text: chunk, language: language, options: options, voice: voice)
            } else { result = try await localEngine.synthesize(text: chunk, language: language, options: options) }
            try Task.checkCancellation(); guard generation == token else { throw CancellationError() }
            let payload = try PCM16Wave.read(result.audioData)
            if bytes == 0 { rate = payload.sampleRate; channels = payload.channels }
            guard rate == payload.sampleRate, channels == payload.channels, Int(bytes) + payload.samples.count <= 60 * 1024 * 1024 else { throw URLError(.dataLengthExceedsMaximum) }
            try handle.write(contentsOf: payload.samples); bytes += UInt32(payload.samples.count)
        }
        guard bytes > 0 else { throw URLError(.cannotDecodeContentData) }
        try handle.seek(toOffset: 0); try handle.write(contentsOf: PCM16Wave.header(bytes: bytes, sampleRate: rate, channels: channels))
        success = true; return file
    }
    /// Keep chunks small without cutting a word, URL, decimal or abbreviation.
    private func chunkTextForPlayback(_ text: String, limit: Int) -> [String] {
        guard text.count > limit else { return [text] }
        let words = text.split(whereSeparator: { $0.isWhitespace })
        guard words.count > 1 else {
            if text.contains(where: { char in char.unicodeScalars.contains { $0.value >= 0x3000 && $0.value <= 0xD7FF } }) {
                var remaining = text[...], pieces: [String] = []
                while !remaining.isEmpty {
                    let end = remaining.index(remaining.startIndex, offsetBy: min(limit, remaining.count))
                    pieces.append(String(remaining[..<end])); remaining = remaining[end...]
                }
                return pieces
            }
            return [text]
        }
        var result: [String] = [], current = ""
        for word in words {
            if !current.isEmpty && current.count + word.count + 1 > limit { result.append(current); current = "" }
            current += (current.isEmpty ? "" : " ") + word
        }
        if !current.isEmpty { result.append(current) }
        return result
    }
    public func stop() {
        generation = UUID(); isProcessing = false; ExternalTTSSession.shared.cancelCurrent(); localEngine.stop(); systemEngine.stop(); audioPlayer.stop()
    }
}
