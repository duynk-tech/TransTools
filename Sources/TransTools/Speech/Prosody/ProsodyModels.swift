import Foundation

public struct TextRange: Codable, Equatable, Sendable {
    public let location: Int
    public let length: Int
    public let intensity: Float // 0.0 to 1.0 (moderate emphasis ~ 0.5-0.7, strong emphasis ~ 0.8-1.0)
    public let matchedText: String

    public init(location: Int, length: Int, intensity: Float = 0.6, matchedText: String = "") {
        self.location = location
        self.length = length
        self.intensity = intensity
        self.matchedText = matchedText
    }
}

public struct SpeechPause: Codable, Equatable, Sendable {
    public let offset: Int // character index after which pause occurs
    public let duration: TimeInterval // seconds, e.g. 0.25 - 0.5
    public let reason: String

    public init(offset: Int, duration: TimeInterval, reason: String = "punctuation") {
        self.offset = offset
        self.duration = duration
        self.reason = reason
    }
}

public struct ProsodyResult: Equatable, Sendable {
    public let text: String
    public let emotion: SpeechEmotion
    public let rate: Float
    public let emphasis: [TextRange]
    public let pauses: [SpeechPause]

    public init(
        text: String,
        emotion: SpeechEmotion = .neutral,
        rate: Float = 0.44,
        emphasis: [TextRange] = [],
        pauses: [SpeechPause] = []
    ) {
        self.text = text
        self.emotion = emotion
        self.rate = rate
        self.emphasis = emphasis
        self.pauses = pauses
    }
}

public struct UtteranceItem: Codable, Equatable, Sendable, Identifiable {
    public let id: UUID
    public let text: String
    public let speakerRole: String
    public let language: String
    public let timestamp: Date

    public init(
        id: UUID = UUID(),
        text: String,
        speakerRole: String = "user",
        language: String = "vi",
        timestamp: Date = Date()
    ) {
        self.id = id
        self.text = text
        self.speakerRole = speakerRole
        self.language = language
        self.timestamp = timestamp
    }
}

public struct ConversationContext: Sendable {
    public let currentUtterance: String
    public let speakerRole: String
    public let detectedLanguage: String
    public let recentUtterances: [UtteranceItem]

    public init(
        currentUtterance: String,
        speakerRole: String = "speaker",
        detectedLanguage: String = "vi",
        recentUtterances: [UtteranceItem] = []
    ) {
        self.currentUtterance = currentUtterance
        self.speakerRole = speakerRole
        self.detectedLanguage = detectedLanguage
        // Keep strictly bounded to recent 2-4 items to prevent memory bloat
        let boundedCount = min(recentUtterances.count, 4)
        if boundedCount > 0 {
            self.recentUtterances = Array(recentUtterances.suffix(boundedCount)).map { UtteranceItem(id: $0.id, text: String($0.text.prefix(512)), speakerRole: $0.speakerRole, language: $0.language, timestamp: $0.timestamp) }
        } else {
            self.recentUtterances = []
        }
    }
}
