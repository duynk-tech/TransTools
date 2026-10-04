import Foundation
import OnnxRuntimeBindings

/// Serializes inference and keeps all four ONNX sessions warm off the main actor.
public actor SupertonicSession {
    public static let shared = SupertonicSession()
    private var environment: ORTEnv?
    private var model: TextToSpeech?
    private var style: Style?
    private var loadedDirectory: URL?

    private var idleReleaseTask: Task<Void, Never>?
    private var lease = UUID()

    private func retainUntilIdle() {
        idleReleaseTask?.cancel()
        let token = UUID(); lease = token
        idleReleaseTask = Task { [weak self] in
            do { try await Task.sleep(nanoseconds: 120_000_000_000) } catch { return }
            await self?.releaseIfIdle(token)
        }
    }

    private func releaseIfIdle(_ token: UUID) {
        guard lease == token else { return }
        release()
    }

    public func release() {
        lease = UUID()
        idleReleaseTask?.cancel(); idleReleaseTask = nil
        style = nil
        model = nil
        environment = nil
        loadedDirectory = nil
    }

    public func prepare(directory: URL) throws {
        try Task.checkCancellation()
        defer { retainUntilIdle() }
        if model == nil || loadedDirectory != directory {
            release()
            let started = Date()
            let env = try ORTEnv(loggingLevel: .error)
            let loaded = try loadTextToSpeech(directory.appendingPathComponent("onnx").path, false, env)
            let voice = try loadVoiceStyle([directory.appendingPathComponent("voice_styles/F1.json").path], verbose: false)
            environment = env
            model = loaded
            style = voice
            loadedDirectory = directory
            #if DEBUG
            print("[TTS] ONNX model load: \(Int(Date().timeIntervalSince(started) * 1000)) ms")
            #endif
        }
        try Task.checkCancellation()
    }

    public func synthesize(text: String, language: String, directory: URL, speed: Float) throws -> (samples: [Float], sampleRate: Int) {
        try Task.checkCancellation()
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, text.count <= 2000 else {
            throw NSError(domain: "LocalTTS", code: 4, userInfo: [NSLocalizedDescriptionKey: "Đoạn đọc quá dài hoặc rỗng."])
        }
        guard AVAILABLE_LANGS.contains(language), language != "na" else {
            throw NSError(domain: "LocalTTS", code: 1, userInfo: [NSLocalizedDescriptionKey: "Ngôn ngữ chưa được mô hình hỗ trợ."])
        }
        try prepare(directory: directory)
        guard let model, let style else { throw CancellationError() }
        // Actor isolation keeps eviction from releasing sessions during inference.
        defer { retainUntilIdle() }
        let output = try model.call(text, language, style, 8, speed: min(1.5, max(0.7, speed)))
        try Task.checkCancellation()
        guard !output.wav.isEmpty, output.wav.allSatisfy({ $0.isFinite }), output.wav.contains(where: { abs($0) > 0.0001 }) else {
            throw NSError(domain: "LocalTTS", code: 2, userInfo: [NSLocalizedDescriptionKey: "Mô hình không tạo được âm thanh hợp lệ."])
        }
        return (output.wav, model.sampleRate)
    }
}
