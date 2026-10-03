import Foundation
import AVFoundation

public final class SystemTTSEngine: NSObject, TTSEngine, @unchecked Sendable {
    public static let shared = SystemTTSEngine()

    public var isAvailable: Bool {
        return true
    }

    public var supportedLanguages: [String] {
        return ["vi-VN", "en-US", "ja-JP", "zh-CN", "ko-KR", "fr-FR", "de-DE", "it-IT"]
    }

    private let synthesizer = AVSpeechSynthesizer()
    private let lock = NSLock()
    private var capture: SystemSpeechCapture?
    public override init() { super.init() }

    public func synthesize(text: String, language: String, options: TTSOptions = .default) async throws -> TTSAudioResult {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw URLError(.cannotDecodeContentData) }
        let operation = SystemSpeechCapture()
        lock.withLock { capture = operation }
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                operation.begin(continuation)
                Task { @MainActor in
                    guard !Task.isCancelled, !operation.isFinished else { return }
                    let utterance = AVSpeechUtterance(string: trimmed)
                    utterance.voice = options.voiceID.flatMap(AVSpeechSynthesisVoice.init(identifier:)) ?? AVSpeechSynthesisVoice(language: Self.normalizeLocale(language))
                    utterance.rate = max(0.25, min(0.75, options.prosody?.rate ?? options.rate))
                    utterance.volume = options.volume
                    utterance.pitchMultiplier = options.pitch
                    self.synthesizer.write(utterance) { buffer in
                        guard let pcm = buffer as? AVAudioPCMBuffer else { return }
                        if pcm.frameLength == 0 { operation.finish() }
                        else if let copy = Self.copyBuffer(pcm) { operation.append(copy) }
                    }
                }
                Task {
                    try? await Task.sleep(nanoseconds: 60_000_000_000)
                    operation.fail(URLError(.timedOut))
                }
            }
        } onCancel: {
            operation.fail(CancellationError())
            Task { @MainActor in self.synthesizer.stopSpeaking(at: .immediate) }
        }
    }
    public func stop() {
        lock.withLock { capture }?.fail(CancellationError())
        Task { @MainActor in self.synthesizer.stopSpeaking(at: .immediate) }
    }

    private static func normalizeLocale(_ code: String) -> String {
        switch code.lowercased() {
        case "vi", "vi-vn": return "vi-VN"
        case "en", "en-us": return "en-US"
        case "ja", "ja-jp": return "ja-JP"
        case "zh", "zh-cn": return "zh-CN"
        case "ko", "ko-kr": return "ko-KR"
        case "fr", "fr-fr": return "fr-FR"
        case "de", "de-de": return "de-DE"
        default: return code
        }
    }

    private static func copyBuffer(_ buffer: AVAudioPCMBuffer) -> AVAudioPCMBuffer? {
        guard let copy = AVAudioPCMBuffer(pcmFormat: buffer.format, frameCapacity: buffer.frameCapacity) else { return nil }
        copy.frameLength = buffer.frameLength
        if let src = buffer.floatChannelData, let dst = copy.floatChannelData {
            for ch in 0..<Int(buffer.format.channelCount) {
                dst[ch].initialize(from: src[ch], count: Int(buffer.frameLength))
            }
        }
        return copy
    }

    public static func bufferToWav(_ buffer: AVAudioPCMBuffer) -> Data? {
        let channelCount = Int(buffer.format.channelCount)
        let frameLength = Int(buffer.frameLength)
        let sampleRate = Int(buffer.format.sampleRate)
        guard channelCount > 0, frameLength > 0, let channelData = buffer.floatChannelData else { return nil }

        let bytesPerSample = 2 // 16-bit PCM
        let subChunk2Size = frameLength * channelCount * bytesPerSample
        let chunkSize = 36 + subChunk2Size

        var data = Data()
        data.reserveCapacity(44 + subChunk2Size)

        // RIFF header
        data.append(contentsOf: [0x52, 0x49, 0x46, 0x46]) // "RIFF"
        data.append(UInt32(chunkSize).littleEndianData)
        data.append(contentsOf: [0x57, 0x41, 0x56, 0x45]) // "WAVE"

        // "fmt " chunk
        data.append(contentsOf: [0x66, 0x6D, 0x74, 0x20]) // "fmt "
        data.append(UInt32(16).littleEndianData)          // subChunk1Size (16 for PCM)
        data.append(UInt16(1).littleEndianData)           // audioFormat (1 for PCM)
        data.append(UInt16(channelCount).littleEndianData)
        data.append(UInt32(sampleRate).littleEndianData)
        data.append(UInt32(sampleRate * channelCount * bytesPerSample).littleEndianData) // byteRate
        data.append(UInt16(channelCount * bytesPerSample).littleEndianData)              // blockAlign
        data.append(UInt16(16).littleEndianData)                                        // bitsPerSample

        // "data" chunk
        data.append(contentsOf: [0x64, 0x61, 0x74, 0x61]) // "data"
        data.append(UInt32(subChunk2Size).littleEndianData)

        // Interleave float to 16-bit Int
        for frame in 0..<frameLength {
            for ch in 0..<channelCount {
                let sample = channelData[ch][frame]
                let clamped = max(-1.0, min(1.0, sample))
                let int16Sample = Int16(clamped * 32767.0)
                data.append(UInt16(bitPattern: int16Sample).littleEndianData)
            }
        }

        return data
    }
}

private extension FixedWidthInteger {
    var littleEndianData: Data {
        var val = self.littleEndian
        return Data(bytes: &val, count: MemoryLayout<Self>.size)
    }
}

/// Completes on Apple's end-of-stream buffer, never by guessing buffer inactivity.
private final class SystemSpeechCapture: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<TTSAudioResult, Error>?
    private var buffers: [AVAudioPCMBuffer] = []
    private var finished = false
    var isFinished: Bool { lock.withLock { finished } }
    func begin(_ value: CheckedContinuation<TTSAudioResult, Error>) {
        let cancelled = lock.withLock { () -> Bool in
            if finished { return true }; continuation = value; return false
        }
        if cancelled { value.resume(throwing: CancellationError()) }
    }
    func append(_ buffer: AVAudioPCMBuffer) { lock.withLock { if !finished { buffers.append(buffer) } } }
    func fail(_ error: Error) {
        let pending = lock.withLock { () -> CheckedContinuation<TTSAudioResult, Error>? in
            guard !finished else { return nil }; finished = true
            let value = continuation; continuation = nil; buffers.removeAll(); return value
        }
        pending?.resume(throwing: error)
    }
    func finish() {
        let snapshot = lock.withLock { () -> (CheckedContinuation<TTSAudioResult, Error>, [AVAudioPCMBuffer])? in
            guard !finished, let continuation else { return nil }
            finished = true; self.continuation = nil
            let result = (continuation, buffers); buffers.removeAll(); return result
        }
        guard let (continuation, chunks) = snapshot else { return }
        Task.detached {
            guard let first = chunks.first else { continuation.resume(throwing: URLError(.cannotDecodeContentData)); return }
            let frames = chunks.reduce(0) { $0 + $1.frameLength }
            guard let merged = AVAudioPCMBuffer(pcmFormat: first.format, frameCapacity: frames), let dst = merged.floatChannelData else {
                continuation.resume(throwing: URLError(.cannotDecodeContentData)); return
            }
            merged.frameLength = frames
            var offset = 0
            for chunk in chunks {
                guard let src = chunk.floatChannelData else { continuation.resume(throwing: URLError(.cannotDecodeContentData)); return }
                for channel in 0..<Int(first.format.channelCount) { dst[channel].advanced(by: offset).update(from: src[channel], count: Int(chunk.frameLength)) }
                offset += Int(chunk.frameLength)
            }
            guard let data = SystemTTSEngine.bufferToWav(merged) else { continuation.resume(throwing: URLError(.cannotDecodeContentData)); return }
            continuation.resume(returning: TTSAudioResult(audioData: data, duration: Double(frames) / first.format.sampleRate,
                sampleRate: first.format.sampleRate, engineType: "System"))
        }
    }
}
