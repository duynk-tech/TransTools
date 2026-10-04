import Foundation
import AVFoundation

public enum TTSPlaybackPolicy: String, CaseIterable, Identifiable, Codable, Sendable {
    case interruptCurrent = "interrupt"
    case queueSpeech = "queue"
    public var id: String { rawValue }
    public var title: String {
        self == .interruptCurrent ? "Ngắt câu trước (Ưu tiên câu mới nhất)" : "Xếp hàng đợi (Đọc tuần tự từng câu)"
    }
}
public struct QueuedAudioItem: @unchecked Sendable {
    public let id: UUID
    fileprivate let packetID: UUID
    public let audioResult: TTSAudioResult
    public let onComplete: (@Sendable () -> Void)?
    public init(id: UUID = UUID(), audioResult: TTSAudioResult, onComplete: (@Sendable () -> Void)? = nil, packetID: UUID = UUID()) {
        self.packetID = packetID
        self.id = id; self.audioResult = audioResult; self.onComplete = onComplete
    }
}

@MainActor
public final class TTSAudioPlayer: NSObject, ObservableObject {
    public static let shared = TTSAudioPlayer()
    @Published public var policy = TTSPlaybackPolicy(rawValue: UserDefaults.standard.string(forKey: "TTS_PlaybackPolicy") ?? "interrupt") ?? .interruptCurrent {
        didSet { UserDefaults.standard.set(policy.rawValue, forKey: "TTS_PlaybackPolicy") }
    }
    @Published public private(set) var isPlaying = false
    @Published public private(set) var currentUtteranceID: UUID?
    private let engine = AVAudioEngine()
    private let node = AVAudioPlayerNode()
    private let timePitch = AVAudioUnitTimePitch()
    private var connectedRate: Float = 1
    private var connectedFormat: AVAudioFormat?
    private var queue: [QueuedAudioItem] = []
    private var current: QueuedAudioItem?
    private override init() { super.init(); engine.attach(node); engine.attach(timePitch) }

    /// Bound generated WAV buffers to the current chunk plus two waiting chunks.
    public func waitForQueueCapacity() async throws {
        while queue.count >= 2 {
            try Task.checkCancellation()
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        try Task.checkCancellation()
    }

    public func play(result: TTSAudioResult, utteranceID: UUID = UUID(), overridePolicy: TTSPlaybackPolicy? = nil, playbackRate: Float = 1, onComplete: (@Sendable () -> Void)? = nil) throws {
        // Decode before touching currently audible speech. Buffers are scheduled together,
        // so packet boundaries never wait for a new player/delegate/prepare cycle.
        let buffer = try pcmBuffer(result.audioData)
        let item = QueuedAudioItem(id: utteranceID, audioResult: result, onComplete: onComplete)
        if (overridePolicy ?? policy) == .interruptCurrent { stop() }
        if current == nil {
            if connectedFormat?.sampleRate != buffer.format.sampleRate || connectedFormat?.channelCount != buffer.format.channelCount {
                node.stop(); engine.stop(); engine.disconnectNodeOutput(node)
                engine.connect(node, to: timePitch, format: buffer.format)
                engine.disconnectNodeOutput(timePitch)
                engine.connect(timePitch, to: engine.mainMixerNode, format: buffer.format)
                connectedFormat = buffer.format
            }
            connectedRate = max(0.7, min(1.5, playbackRate)); timePitch.rate = connectedRate
            if !engine.isRunning { engine.prepare(); try engine.start() }
            current = item
        } else {
            guard connectedFormat?.sampleRate == buffer.format.sampleRate, connectedFormat?.channelCount == buffer.format.channelCount, abs(connectedRate - playbackRate) < 0.01 else {
                throw URLError(.cannotDecodeContentData)
            }
            queue.append(item)
        }
        node.scheduleBuffer(buffer, completionCallbackType: .dataPlayedBack) { [weak self] _ in
            Task { @MainActor in self?.finishPacket(item.packetID) }
        }
        if !node.isPlaying { node.play() }
        currentUtteranceID = current?.id; isPlaying = true
    }
    private func pcmBuffer(_ data: Data) throws -> AVAudioPCMBuffer {
        let payload = try PCM16Wave.read(data)
        let frames = payload.samples.count / (Int(payload.channels) * 2)
        guard frames > 0, frames <= Int(UInt32.max),
              let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: Double(payload.sampleRate), channels: AVAudioChannelCount(payload.channels), interleaved: false),
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(frames)),
              let samples = buffer.floatChannelData else { throw URLError(.cannotDecodeContentData) }
        buffer.frameLength = AVAudioFrameCount(frames)
        payload.samples.withUnsafeBytes { bytes in
            let pcm = bytes.bindMemory(to: UInt8.self)
            for frame in 0..<frames {
                for channel in 0..<Int(payload.channels) {
                    let offset = (frame * Int(payload.channels) + channel) * 2
                    let value = Int16(bitPattern: UInt16(pcm[offset]) | UInt16(pcm[offset + 1]) << 8)
                    samples[channel][frame] = Float(value) / 32768
                }
            }
        }
        return buffer
    }
    /// Attach completion only after the producer is done, including the already-drained case.
    public func completeAfterPlayback(utteranceID: UUID, _ completion: (@Sendable () -> Void)?) {
        if let last = queue.last, last.id == utteranceID {
            queue[queue.count - 1] = QueuedAudioItem(id: last.id, audioResult: last.audioResult, onComplete: completion, packetID: last.packetID)
        } else if let current, current.id == utteranceID {
            self.current = QueuedAudioItem(id: current.id, audioResult: current.audioResult, onComplete: completion, packetID: current.packetID)
        } else { completion?() }
    }
    public func stop() {
        node.stop(); engine.stop(); current = nil; queue.removeAll()
        isPlaying = false; currentUtteranceID = nil
    }
    private func finishPacket(_ packetID: UUID) {
        guard current?.packetID == packetID else { return }
        let completion = current?.onComplete
        if queue.isEmpty {
            current = nil; isPlaying = false; currentUtteranceID = nil
        } else {
            current = queue.removeFirst()
            currentUtteranceID = current?.id
        }
        completion?()
    }
}
