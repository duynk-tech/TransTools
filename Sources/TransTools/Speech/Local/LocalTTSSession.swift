import Foundation
import AVFoundation
import LocalSpeechBackend

public final class LocalTTSSession: @unchecked Sendable {
    public static let shared = LocalTTSSession()
    private var memoryPressureSource: DispatchSourceMemoryPressure?
    private init() {
        let source = DispatchSource.makeMemoryPressureSource(eventMask: [.warning, .critical], queue: .global(qos: .utility))
        source.setEventHandler { Task { await SupertonicSession.shared.release() } }
        source.resume()
        memoryPressureSource = source
    }
    deinit { memoryPressureSource?.cancel() }
    public func warmUpIfNeeded() async throws {
        try await SupertonicSession.shared.prepare(directory: LocalTTSModelManager.defaultActiveModelDirectory)
    }
    public func releaseAndWait() async { await SupertonicSession.shared.release() }
    public func releaseResources() { Task { await SupertonicSession.shared.release() } }

    public func synthesizeChunk(text: String, prosody: ProsodyResult, language: String) async throws -> AVAudioPCMBuffer {
        let directory = LocalTTSModelManager.defaultActiveModelDirectory
        let code = language.lowercased().split(separator: "-").first.map(String.init) ?? language
        let output = try await SupertonicSession.shared.synthesize(text: text, language: code, directory: directory, speed: prosody.rate / 0.44)
        try Task.checkCancellation()
        guard let format = AVAudioFormat(standardFormatWithSampleRate: Double(output.sampleRate), channels: 1),
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(output.samples.count)),
              let channel = buffer.floatChannelData?[0] else {
            throw NSError(domain: "LocalTTS", code: 3, userInfo: [NSLocalizedDescriptionKey: "Không tạo được bộ đệm phát giọng."])
        }
        buffer.frameLength = AVAudioFrameCount(output.samples.count)
        output.samples.withUnsafeBufferPointer { src in channel.update(from: src.baseAddress!, count: src.count) }
        return buffer
    }
}
