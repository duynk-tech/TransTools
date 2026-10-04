import Foundation
import LocalSpeechBackend
import AVFoundation

/// Shared adapter used by listening, conversations, vocabulary and WAV export.
/// The native model never starts a Python worker.
final class NativeVieNeu {
    static let shared = NativeVieNeu()
    static var resources: URL {
        let bundled = (Bundle.main.resourceURL ?? Bundle.main.bundleURL).appendingPathComponent("SpeechNative")
        if FileManager.default.fileExists(atPath: bundled.path) { return bundled }
        // SwiftPM tests do not run inside the packaged app.
        var source = URL(fileURLWithPath: #filePath)
        for _ in 0..<5 { source.deleteLastPathComponent() }
        return source.appendingPathComponent("Resources/SpeechNative")
    }
    func synthesize(text: String, voice: String, options: TTSOptions,
                    onChunk: (@Sendable (TTSAudioResult) async throws -> Void)?) async throws -> TTSAudioResult {
        let capture = NativeAudioCapture()
        try await VieNeuSession.shared.synthesize(text: text, voice: voice, directory: ExternalTTSModel.vieneu.directory, resources: Self.resources) { part in
            guard part.allSatisfy({ $0.isFinite }) else { throw URLError(.cannotDecodeContentData) }
            let p = part.map { min(1, max(-1, $0*options.volume)) }
            let packet = Self.result(p)
            try capture.append(p, packet: packet, collect: onChunk == nil)
            if let onChunk { try await onChunk(packet) }
        }
        let output = capture.snapshot()
        var samples = output.samples
        guard output.total >= 4800, output.peak > 0.0001, let last = output.last else { throw URLError(.cannotDecodeContentData) }
        if onChunk != nil { return last }
        let rate = max(0.7, min(1.5, options.rate/0.44))
        if abs(rate-1) > 0.02 { samples = try Self.adjustSpeed(samples, rate: rate) }
        return Self.result(samples)
    }
    private static func result(_ samples: [Float]) -> TTSAudioResult {
        var pcm = Data(capacity: samples.count*2)
        for value in samples { var sample = Int16(max(-32768, min(32767, Int(value*32768)))).littleEndian; withUnsafeBytes(of: &sample) { pcm.append(contentsOf: $0) } }
        let data = PCM16Wave.header(bytes: UInt32(pcm.count), sampleRate: 48000, channels: 1) + pcm
        return TTSAudioResult(audioData: data, duration: Double(samples.count)/48000, sampleRate: 48000, engineType: "VieNeuNative")
    }
    /// Native offline time-pitch rendering for WAV export. Playback already uses
    /// the continuous player's time-pitch node and does not buffer a paragraph.
    private static func adjustSpeed(_ samples: [Float], rate: Float) throws -> [Float] {
        let engine = AVAudioEngine(), player = AVAudioPlayerNode(), pitch = AVAudioUnitTimePitch()
        let format = AVAudioFormat(standardFormatWithSampleRate: 48000, channels: 1)!
        engine.attach(player); engine.attach(pitch); pitch.rate = rate
        engine.connect(player, to: pitch, format: format); engine.connect(pitch, to: engine.mainMixerNode, format: format)
        try engine.enableManualRenderingMode(.offline, format: format, maximumFrameCount: 4096)
        let input = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(samples.count))!
        input.frameLength = input.frameCapacity
        samples.withUnsafeBufferPointer { input.floatChannelData![0].update(from: $0.baseAddress!, count: samples.count) }
        player.scheduleBuffer(input); try engine.start(); player.play()
        defer { player.stop(); engine.stop(); engine.disableManualRenderingMode() }
        let output = AVAudioPCMBuffer(pcmFormat: engine.manualRenderingFormat, frameCapacity: 4096)!
        let expected = Int(ceil(Double(samples.count)/Double(rate)))
        var result: [Float] = []; result.reserveCapacity(expected)
        var retries = 0
        while result.count < expected {
            try Task.checkCancellation()
            let status = try engine.renderOffline(AVAudioFrameCount(min(4096,expected-result.count)), to: output)
            switch status {
            case .success: result += UnsafeBufferPointer(start: output.floatChannelData![0], count: Int(output.frameLength)); retries = 0
            case .cannotDoInCurrentContext, .insufficientDataFromInputNode: retries += 1; if retries > 16 { throw URLError(.cannotDecodeContentData) }
            case .error: throw URLError(.cannotDecodeContentData)
            @unknown default: throw URLError(.cannotDecodeContentData)
            }
        }
        return result
    }
}

/// A callback may cross executors, so its accumulator has a real lock rather
/// than captured mutable locals that become data races in Swift 6.
final class NativeAudioCapture: @unchecked Sendable {
    private let lock = NSLock()
    private var samples: [Float] = [], last: TTSAudioResult?, peak: Float = 0, total = 0
    func append(_ part: [Float], packet: TTSAudioResult? = nil, collect: Bool = false) throws {
        lock.lock(); defer { lock.unlock() }
        guard part.allSatisfy({ $0.isFinite }), total + part.count <= 48000*120 else { throw URLError(.cannotDecodeContentData) }
        total += part.count; peak = max(peak, part.map(abs).max() ?? 0)
        if let packet { last = packet }
        if collect { samples += part }
    }
    func snapshot() -> (samples: [Float], last: TTSAudioResult?, total: Int, peak: Float) {
        lock.lock(); defer { lock.unlock() }; return (samples,last,total,peak)
    }
}
