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
    public let audioResult: TTSAudioResult
    public let onComplete: (@Sendable () -> Void)?
    public init(id: UUID = UUID(), audioResult: TTSAudioResult, onComplete: (@Sendable () -> Void)? = nil) {
        self.id = id; self.audioResult = audioResult; self.onComplete = onComplete
    }
}

@MainActor
public final class TTSAudioPlayer: NSObject, ObservableObject, AVAudioPlayerDelegate {
    public static let shared = TTSAudioPlayer()
    @Published public var policy = TTSPlaybackPolicy(rawValue: UserDefaults.standard.string(forKey: "TTS_PlaybackPolicy") ?? "interrupt") ?? .interruptCurrent {
        didSet { UserDefaults.standard.set(policy.rawValue, forKey: "TTS_PlaybackPolicy") }
    }
    @Published public private(set) var isPlaying = false
    @Published public private(set) var currentUtteranceID: UUID?
    private var player: AVAudioPlayer?
    private var queue: [QueuedAudioItem] = []
    private var current: QueuedAudioItem?
    private override init() { super.init() }

    public func play(result: TTSAudioResult, utteranceID: UUID = UUID(), overridePolicy: TTSPlaybackPolicy? = nil, onComplete: (@Sendable () -> Void)? = nil) throws {
        // Validate before replacing currently audible speech.
        guard !result.audioData.isEmpty else { throw URLError(.cannotDecodeContentData) }
        let validated = try AVAudioPlayer(data: result.audioData)
        guard validated.duration > 0 else { throw URLError(.cannotDecodeContentData) }
        let item = QueuedAudioItem(id: utteranceID, audioResult: result, onComplete: onComplete)
        if (overridePolicy ?? policy) == .interruptCurrent { stop() }
        if current != nil { queue.append(item) } else { try start(item, player: validated) }
    }
    private func start(_ item: QueuedAudioItem, player audio: AVAudioPlayer) throws {
        audio.delegate = self
        guard audio.prepareToPlay(), audio.play() else { throw URLError(.cannotDecodeContentData) }
        player = audio; current = item; currentUtteranceID = item.id; isPlaying = true
    }
    public func stop() {
        player?.stop(); player = nil; current = nil; queue.removeAll()
        isPlaying = false; currentUtteranceID = nil
    }
    private func finish(_ finished: AVAudioPlayer) {
        guard player === finished else { return }
        let completion = current?.onComplete
        player = nil; current = nil; isPlaying = false; currentUtteranceID = nil
        if !queue.isEmpty {
            let next = queue.removeFirst()
            do { try start(next, player: AVAudioPlayer(data: next.audioResult.audioData)) }
            catch { queue.removeAll(); next.onComplete?() }
        }
        completion?()
    }
    nonisolated public func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in self.finish(player) }
    }
    nonisolated public func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {
        Task { @MainActor in self.finish(player) }
    }
}
