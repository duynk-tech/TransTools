import XCTest
@testable import TransTools
final class MeetingAssistBoardTests: XCTestCase {
    @MainActor func testNewSessionClearsHiddenPanelResultsAndInvalidatesOldRequests() throws {
        let store = MeetingAssistantDraftStore()
        let previousSession = store.sessionID
        store.text = "Keep my unfinished draft"
        store.result = try MeetingAssistResult.parse("{\"summary\":\"Old meeting\",\"questions\":[],\"replies\":[]}")
        store.resultContextDate = Date()
        store.lastContext = "Old context"
        let request = try XCTUnwrap(store.beginRequest(composing: false))
        store.resetSession()
        XCTAssertNotEqual(store.sessionID, previousSession)
        XCTAssertNil(store.result)
        XCTAssertNil(store.resultContextDate)
        XCTAssertTrue(store.lastContext.isEmpty)
        XCTAssertEqual(store.text, "Keep my unfinished draft")
        XCTAssertNil(store.beginRequest(composing: true), "Keep the gate until the cancelled old request finishes")
        store.finishRequest(request)
        XCTAssertNotNil(store.beginRequest(composing: true))
    }
    func testRetryBackoffAndAccessBlock() {
        let now = Date(timeIntervalSince1970: 1000)
        var retry = MeetingAssistantRetry()
        let quota = NSError(domain: "provider", code: 429)
        retry.failed(quota, now: now)
        XCTAssertEqual(retry.wait(now: now), 60)
        retry.failed(quota, now: now)
        XCTAssertEqual(retry.wait(now: now), 120)
        retry.failed(quota, now: now)
        retry.failed(quota, now: now)
        XCTAssertEqual(retry.wait(now: now), 300)
        retry.reset()
        retry.failed(URLError(.timedOut), now: now)
        XCTAssertEqual(retry.wait(now: now), 30)
        XCTAssertEqual(retry.wait(now: now.addingTimeInterval(31)), 0)
        retry.failed(NSError(domain: "provider", code: 403), now: now)
        XCTAssertTrue(retry.accessBlocked)
        XCTAssertGreaterThan(retry.wait(now: now.addingTimeInterval(10000)), 0)
        retry.reset()
        XCTAssertFalse(retry.accessBlocked)
        XCTAssertEqual(retry.wait(now: now), 0)
    }
    func testActionableErrorsForSlowNetworkAndQuota() {
        XCTAssertTrue(MeetingAssistantFailure.message(URLError(.timedOut)).contains("quá lâu"))
        XCTAssertTrue(MeetingAssistantFailure.message(URLError(.notConnectedToInternet)).contains("vẫn được giữ"))
        XCTAssertTrue(MeetingAssistantFailure.message(NSError(domain: "provider", code: 429)).contains("hạn mức"))
        XCTAssertTrue(MeetingAssistantFailure.message(NSError(domain: "provider", code: 403)).contains("quyền"))
        XCTAssertEqual(MeetingAssistantFailure.message(MeetingAssistantResponseError.invalidFormat), MeetingAssistantResponseError.invalidFormat.localizedDescription)
    }
    func testContextKeepsNewestWordsAndBoundedPayload() {
        let text = MeetingAssistantContext.recent(["old topic", "  ", "long earlier prefix then latest question"], count: 2, perLine: 15, limit: 100)
        XCTAssertEqual(text, "latest question")
        XCTAssertEqual(MeetingAssistantContext.recent(["12345", "67890"], count: 2, perLine: 5, limit: 7), "5\n67890")
    }

    func testCadenceResumesAfterRemainingDelayWithoutDoubleWait() {
        let now = Date(timeIntervalSince1970: 1000)
        XCTAssertEqual(MeetingAssistantContext.waitSeconds(interval: 30, lastAttempt: now.addingTimeInterval(-20), now: now), 10)
        XCTAssertEqual(MeetingAssistantContext.waitSeconds(interval: 30, lastAttempt: now.addingTimeInterval(-40), now: now), 0)
        XCTAssertEqual(MeetingAssistantContext.waitSeconds(interval: 1, lastAttempt: now, now: now), 15)
        XCTAssertEqual(MeetingAssistantContext.waitSeconds(interval: 200, lastAttempt: now, now: now), 120)
        XCTAssertEqual(MeetingAssistantContext.waitSeconds(interval: 30, lastAttempt: now.addingTimeInterval(5), now: now), 30)
    }
    @MainActor func testSharedRequestGatePreventsOverlappingSuggestionsAndDrafts() throws {
        let store = MeetingAssistantDraftStore()
        let suggestion = try XCTUnwrap(store.beginRequest(composing: false))
        XCTAssertTrue(store.busy)
        XCTAssertFalse(store.draftBusy)
        XCTAssertNil(store.beginRequest(composing: true))
        store.finishRequest(UUID())
        XCTAssertTrue(store.busy, "An unrelated completion must not unlock an active request")
        store.finishRequest(suggestion)
        XCTAssertFalse(store.busy)
        XCTAssertGreaterThan(store.lastAutomaticAttempt, Date().addingTimeInterval(-2))
        let draft = try XCTUnwrap(store.beginRequest(composing: true))
        XCTAssertTrue(store.draftBusy)
        XCTAssertNil(store.beginRequest(composing: false))
        store.finishRequest(suggestion)
        XCTAssertTrue(store.draftBusy, "An old completion must not clear a newer draft")
        store.finishRequest(draft)
        XCTAssertFalse(store.draftBusy)
        XCTAssertNotNil(store.beginRequest(composing: false))
    }
    func testAcceptsMarkdownWrappedAndIntroducedJSON() throws {
        let pair = "{\"original\":\"Could you explain again?\",\"translation\":\"Bạn giải thích lại được không?\"}"
        XCTAssertEqual(try MeetingAssistSuggestion.parse("```json\n" + pair + "\n```").original, "Could you explain again?")
        XCTAssertEqual(try MeetingAssistSuggestion.parse("Câu gợi ý:\n" + pair).translation, "Bạn giải thích lại được không?")
        let result = try MeetingAssistResult.parse("```json\n{\"summary\":\"Kế hoạch.\",\"questions\":[],\"replies\":[]}\n```")
        XCTAssertEqual(result.summary, "Kế hoạch.")
        XCTAssertThrowsError(try MeetingAssistSuggestion.parse(pair + pair))
        XCTAssertThrowsError(try MeetingAssistSuggestion.parse(String(pair.dropLast())))
    }
    func testCollapsePreservesUserResizeWhileAssistantIsOpen() {
        let previous = NSRect(x: 100, y: 100, width: 780, height: 180)
        let expanded = NSRect(x: 100, y: 100, width: 1120, height: 180)
        let current = NSRect(x: 50, y: 50, width: 1220, height: 260)
        let restored = MeetingAssistantLayout.preservingResize(previous: previous, expanded: expanded, current: current)
        XCTAssertEqual(restored.size, NSSize(width: 880, height: 260))
        XCTAssertEqual(MeetingAssistantLayout.preservingResize(previous: previous, expanded: expanded, current: expanded).size, previous.size)
    }
    func testCollapseKeepsMovedPanelOnCurrentScreen() {
        let screen = NSRect(x: -1280, y: 0, width: 1280, height: 720)
        let frame = MeetingAssistantLayout.restoredFrame(
            previous: NSRect(x: 100, y: 100, width: 700, height: 300),
            current: NSRect(x: -300, y: 650, width: 1000, height: 500), screen: screen)
        XCTAssertEqual(frame, NSRect(x: -700, y: 420, width: 700, height: 300))
        XCTAssertTrue(screen.contains(frame))
    }
    func testCollapseFitsSmallerScreen() {
        let screen = NSRect(x: 0, y: 25, width: 600, height: 400)
        let frame = MeetingAssistantLayout.restoredFrame(
            previous: NSRect(x: 100, y: 100, width: 900, height: 500),
            current: NSRect(x: -200, y: -100, width: 1200, height: 600), screen: screen)
        XCTAssertEqual(frame, screen)
    }
    func testStructuredResultAndEmptySuggestions() throws {
        let value = try MeetingAssistResult.parse("{\"summary\":\"Chưa rõ quyết định.\",\"questions\":[],\"replies\":[]}")
        XCTAssertEqual(value.summary, "Chưa rõ quyết định.")
        XCTAssertTrue(value.replies.isEmpty)
    }
    func testRejectsMalformedOrOversizedSuggestions() throws {
        XCTAssertThrowsError(try MeetingAssistResult.parse("Not JSON"))
        let pair = ["original": "Could you clarify?", "translation": "Bạn giải thích thêm được không?"]
        let payload: [String: Any] = ["summary": "Summary", "questions": Array(repeating: pair, count: 4), "replies": []]
        let text = String(data: try JSONSerialization.data(withJSONObject: payload), encoding: .utf8)!
        XCTAssertThrowsError(try MeetingAssistResult.parse(text))
    }
    func testBilingualSuggestionsAndQuickDraftRequireBothTexts() throws {
        let pair = try MeetingAssistSuggestion.parse("{\"original\":\"Could you clarify?\",\"translation\":\"Bạn có thể giải thích rõ hơn không?\"}")
        XCTAssertEqual(pair.original, "Could you clarify?")
        XCTAssertFalse(pair.translation.isEmpty)
        XCTAssertThrowsError(try MeetingAssistSuggestion.parse("{\"original\":\"Hello\",\"translation\":\" \"}"))
        let result = try MeetingAssistResult.parse("{\"summary\":\"Thảo luận kế hoạch.\",\"questions\":[{\"original\":\"When?\",\"translation\":\"Khi nào?\"}],\"replies\":[]}")
        XCTAssertEqual(result.questions.first?.translation, "Khi nào?")
    }
}
