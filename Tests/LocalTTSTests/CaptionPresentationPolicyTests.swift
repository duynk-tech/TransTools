import XCTest
@testable import TransTools

final class CaptionPresentationPolicyTests: XCTestCase {
    func testLongMeetingInspectsOnlyRecentReadyTranslations() {
        let rows = entries(Array(repeating: true, count: 10_000))
        var inspected = 0
        let next = CaptionPresentationPolicy.nextIndex(in: rows, currentID: rows[0].id,
            id: { $0.id }, ready: { inspected += 1; return $0.ready })
        XCTAssertEqual(next, 9997)
        XCTAssertEqual(inspected, 3)
    }

    private func entries(_ ready: [Bool]) -> [CaptionPresentationPolicy.Entry] {
        ready.map { .init(id: UUID(), ready: $0) }
    }
    func testCompletedRowsAdvanceInOrder() {
        let rows = entries([true, true, true, false])
        XCTAssertEqual(CaptionPresentationPolicy.nextIndex(in: rows, currentID: rows[0].id), 1)
        XCTAssertEqual(CaptionPresentationPolicy.nextIndex(in: rows, currentID: rows[1].id), 2)
    }
    func testLateOlderTranslationDoesNotMoveReaderBackwards() {
        let rows = entries([true, true, false])
        XCTAssertEqual(CaptionPresentationPolicy.nextIndex(in: rows, currentID: rows[1].id), 1)
    }
    func testDisplayBacklogIsBounded() {
        let rows = entries([true, true, true, true, true, true, false])
        XCTAssertEqual(CaptionPresentationPolicy.nextIndex(in: rows, currentID: rows[0].id, maximumBacklog: 3), 3)
    }
    func testReopeningGoesToLatestCompletedSentence() {
        let rows = entries([true, true, false])
        XCTAssertEqual(CaptionPresentationPolicy.nextIndex(in: rows, currentID: nil), 1)
    }
    func testNewMeetingCannotDisplayPreviousSessionID() {
        let rows = entries([false, false])
        XCTAssertEqual(CaptionPresentationPolicy.nextIndex(in: rows, currentID: UUID()), 1)
        XCTAssertNil(CaptionPresentationPolicy.nextIndex(in: [], currentID: UUID()))
    }
}
