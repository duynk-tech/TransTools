import Foundation
import AVFoundation

public struct TTSOptions: Equatable, Sendable {
    public var rate: Float
    public var pitch: Float
    public var volume: Float
    public var voiceID: String?
    public var prosody: ProsodyResult?
    public var punctuationBreathing: Bool

    public init(
        rate: Float = 0.5,
        pitch: Float = 1.0,
        volume: Float = 1.0,
        voiceID: String? = nil,
        prosody: ProsodyResult? = nil,
        punctuationBreathing: Bool = true
    ) {
        self.rate = rate
        self.pitch = pitch
        self.volume = volume
        self.voiceID = voiceID
        self.prosody = prosody
        self.punctuationBreathing = punctuationBreathing
    }

    public static let `default` = TTSOptions()
}

public struct TTSAudioResult: @unchecked Sendable {
    public let audioData: Data
    public let format: AVAudioFormat?
    public let duration: TimeInterval
    public let sampleRate: Double
    public let channelCount: UInt32
    public let engineType: String
    public let metadata: [String: String]

    public init(
        audioData: Data,
        format: AVAudioFormat? = nil,
        duration: TimeInterval,
        sampleRate: Double = 24000,
        channelCount: UInt32 = 1,
        engineType: String,
        metadata: [String: String] = [:]
    ) {
        self.audioData = audioData
        self.format = format
        self.duration = duration
        self.sampleRate = sampleRate
        self.channelCount = channelCount
        self.engineType = engineType
        self.metadata = metadata
    }
}

public protocol TTSEngine: AnyObject, Sendable {
    var isAvailable: Bool { get }
    var supportedLanguages: [String] { get }

    func synthesize(
        text: String,
        language: String,
        options: TTSOptions
    ) async throws -> TTSAudioResult

    func stop()
}

public enum TTSEnginePreference: String, CaseIterable, Identifiable, Codable {
    case system = "system"
    case localNatural = "localNatural"

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .system:
            return "System Voice"
        case .localNatural:
            return "Natural Local Voice"
        }
    }

    public var subtitle: String {
        switch self {
        case .system:
            return "Fast • No download required"
        case .localNatural:
            return "More natural expression • Private • Offline"
        }
    }
}
