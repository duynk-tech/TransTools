import XCTest
@testable import TransTools

final class SubtitleQuickStoreTests: XCTestCase {
    @MainActor func testHistoryBoundAndSessionResetPreservesDraft() {
        let store = SubtitleQuickStore()
        store.text = "Ý đang nhập dở"
        for index in 0..<25 {
            store.record(.init(mode: .translate, input: "\(index)", output: "Result", meaning: "Nghĩa", language: .english))
        }
        XCTAssertEqual(store.history.count, 20)
        XCTAssertEqual(store.history.first?.input, "5")
        XCTAssertEqual(store.latest?.input, "24")
        store.resetSession()
        XCTAssertTrue(store.history.isEmpty)
        XCTAssertNil(store.latest)
        XCTAssertEqual(store.text, "Ý đang nhập dở")
    }
    @MainActor func testSuggestionDoesNotOverwriteDraftOrHistory() {
        let store = SubtitleQuickStore()
        store.text = "Đang viết"
        store.present(.init(original: "Could you review this PR?", translation: "Bạn review PR giúp mình nhé?"), language: .english)
        XCTAssertEqual(store.text, "Đang viết")
        XCTAssertTrue(store.history.isEmpty)
        XCTAssertEqual(store.latest?.language, .english)
    }
    @MainActor func testSuccessfulSubmitClearsOnlyTheDraftThatWasSent() {
        let store = SubtitleQuickStore()
        store.text = "  Review this PR  "
        store.clearDraftIfUnchanged(since: "Review this PR")
        XCTAssertEqual(store.text, "")

        store.text = "Review this PR"
        store.text = "Review the API changes instead"
        store.clearDraftIfUnchanged(since: "Review this PR")
        XCTAssertEqual(store.text, "Review the API changes instead")
    }
    func testQuickComposerErrorsUseRelevantRetryGuidance() {
        let unauthorized = SubtitleQuickFailure.message(NSError(domain: "provider", code: 401))
        XCTAssertTrue(unauthorized.contains("khóa hoặc quyền truy cập"))
        XCTAssertTrue(unauthorized.contains("Cài đặt AI"))
        XCTAssertFalse(unauthorized.contains("tự cập nhật"))

        XCTAssertTrue(SubtitleQuickFailure.message(NSError(domain: "provider", code: 429))
            .contains("giới hạn lượt dùng"))
        XCTAssertTrue(SubtitleQuickFailure.message(URLError(.timedOut))
            .contains("Bản nháp vẫn được giữ"))
    }
    @MainActor func testPreemptedRequestCannotReleaseNewGate() throws {
        let store = MeetingAssistantDraftStore()
        let old = try XCTUnwrap(store.beginRequest(composing: false))
        var cancelled = false
        store.cancelCurrentRequest = { cancelled = true }
        store.preempt()
        let new = try XCTUnwrap(store.beginRequest(composing: true))
        store.finishRequest(old)
        XCTAssertTrue(cancelled)
        XCTAssertTrue(store.ownsRequest(new))
        XCTAssertTrue(store.draftBusy)
        store.finishRequest(new)
        XCTAssertFalse(store.draftBusy)
    }
}
