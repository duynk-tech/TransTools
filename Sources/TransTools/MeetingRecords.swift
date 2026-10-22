import Foundation

struct MeetingSession: Identifiable, Codable, Equatable {
    let id: UUID
    var title: String
    let createdAt: Date
    let durationSeconds: TimeInterval
    let audioSource: String
    var notes: String
    var captions: [CaptionRecord]
    var conversationProfile: ConversationTopicProfile?

    init(
        id: UUID = UUID(),
        title: String,
        createdAt: Date = Date(),
        durationSeconds: TimeInterval,
        audioSource: String,
        notes: String = "",
        captions: [CaptionRecord],
        conversationProfile: ConversationTopicProfile? = nil
    ) {
        self.id = id
        self.title = title
        self.createdAt = createdAt
        self.durationSeconds = durationSeconds
        self.audioSource = audioSource
        self.notes = notes
        self.captions = captions
        self.conversationProfile = conversationProfile
    }
}

struct CaptionRecord: Identifiable, Codable, Equatable {
    let id: UUID
    let start: TimeInterval
    let end: TimeInterval
    let original: String
    let vietnamese: String
    var speakers: [Int]? = nil
    // Optional fields allow older notebooks to decode without invented metadata.
    var sourceLanguage: String? = nil
    var targetLanguage: String? = nil
    var translationProvider: String? = nil
    var translationModel: String? = nil
    var sourceRevision: Int? = nil
    var translationSource: String? = nil
    var translationRevision: Int? = nil
}
