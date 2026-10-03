import XCTest
@testable import TransTools

final class ConversationTopicTests: XCTestCase {
    func testSessionPreservesMultilinePromptAndTopic() throws {
        let profile = ConversationTopicProfile(topic: .technology, customPrompt: "Đóng vai đồng nghiệp.\nHỏi tôi về API và cách debug.")
        let session = MeetingSession(title: "Test", durationSeconds: 12, audioSource: "Luyện nói với AI", captions: [], conversationProfile: profile)
        let restored = try JSONDecoder().decode(MeetingSession.self, from: JSONEncoder().encode(session))
        XCTAssertEqual(restored.conversationProfile, profile)
        XCTAssertTrue(restored.conversationProfile!.context.contains("Hỏi tôi về API"))
    }
    func testOldNotebookWithoutTopicStillDecodes() throws {
        let session = MeetingSession(title: "Old", durationSeconds: 1, audioSource: "Luyện nói với AI", captions: [])
        let data = try JSONEncoder().encode(session)
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        object.removeValue(forKey: "conversationProfile")
        let restored = try JSONDecoder().decode(MeetingSession.self, from: JSONSerialization.data(withJSONObject: object))
        XCTAssertNil(restored.conversationProfile)
        XCTAssertEqual(restored.title, "Old")
    }
    func testContextBoundsCustomPrompt() {
        let profile = ConversationTopicProfile(topic: .custom, customPrompt: String(repeating: "x", count: 3000))
        XCTAssertEqual(profile.context.filter { $0 == "x" }.count, 2000)
    }
}
