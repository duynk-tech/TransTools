import XCTest
@testable import TransTools

final class NotebookSearchTests: XCTestCase {
    func testFilteredTranscriptRetainsOriginalPositions() {
        let captions = (0..<5).map { CaptionRecord(id: UUID(), start: Double($0), end: Double($0 + 1), original: "Câu \($0)", vietnamese: "") }
        XCTAssertEqual(NotebookSearch.captionIndices(in: captions, matching: [captions[1].id, captions[4].id]), [1, 4])
        XCTAssertEqual(NotebookSearch.captionIndices(in: captions, matching: nil), [0, 1, 2, 3, 4])
        XCTAssertEqual(NotebookSearch.captionIndices(in: captions, matching: []), [])
    }
    func testTranscriptSearchMatchesBilingualTermsWithinSameCaption() async throws {
        let found = CaptionRecord(id: UUID(), start: 0, end: 1, original: "Review the PR", vietnamese: "Kiểm tra tiến độ")
        let other = CaptionRecord(id: UUID(), start: 1, end: 2, original: "Deployment", vietnamese: "Triển khai")
        let ids = try await NotebookSearch.captionIDs(for: .init(text: "PR tien do", sessionID: UUID(), captions: [found, other]))
        XCTAssertEqual(ids, [found.id])
        let missing = try await NotebookSearch.captionIDs(for: .init(text: "review trien khai", sessionID: UUID(), captions: [found, other]))
        XCTAssertTrue(missing.isEmpty)
    }

    @MainActor func testCancelledTranscriptSearchDoesNotReturnResults() async {
        let task = Task { try await NotebookSearch.captionIDs(for: .init(text: "test", sessionID: UUID(), captions: [])) }
        task.cancel()
        do { _ = try await task.value; XCTFail("Cancelled transcript search must not return results") }
        catch { XCTAssertTrue(error is CancellationError) }
    }

    func testBackgroundSearchMatchesNotesAndReturnsOnlyMatchingIDs() async throws {
        let found = MeetingSession(title: "Cuộc họp", durationSeconds: 1, audioSource: "System", notes: "Tiến độ dự án", captions: [])
        let other = MeetingSession(title: "Khác", durationSeconds: 1, audioSource: "System", captions: [])
        let ids = try await NotebookSearch.sessionIDs(for: .init(text: "tien do", sessions: [found, other]))
        XCTAssertEqual(ids, [found.id])
    }

    @MainActor func testCancelledSearchDoesNotPublishResults() async {
        let task = Task {
            try await NotebookSearch.sessionIDs(for: .init(text: "test", sessions: []))
        }
        task.cancel()
        do { _ = try await task.value; XCTFail("Cancelled search must not return results") }
        catch { XCTAssertTrue(error is CancellationError) }
    }
    func testLargeTranscriptNoMatchTiming() {
        let lines = (0..<10_000).map { "Câu \($0): Chúng ta cần kiểm tra tiến độ dự án và xác minh phản hồi API trước khi phát hành." }
        let started = ContinuousClock.now
        XCTAssertFalse(NotebookSearch.Query("khongton tai").matches(fields: lines))
        let elapsed = started.duration(to: .now).components
        print("Notebook no-match 10,000 lines: \(Double(elapsed.seconds) * 1000 + Double(elapsed.attoseconds) / 1e15) ms")
    }
    func testTitleMatchDoesNotReadLongTranscript() {
        var inspected = 0
        let transcript = (0..<10_000).lazy.map { _ in inspected += 1; return "Lời thoại dài" }
        XCTAssertTrue(NotebookSearch.Query("tien do").matches(fields: transcript, leading: ["Tiến độ dự án"]))
        XCTAssertEqual(inspected, 0)
        XCTAssertTrue(NotebookSearch.Query("du an loi").matches(fields: transcript, leading: ["Dự án"]))
        XCTAssertEqual(inspected, 1)
    }
    func testVietnameseAccentsAndDStroke() {
        XCTAssertTrue(NotebookSearch.matches("tien do du an", fields: ["Tiến độ dự án"] ))
        XCTAssertTrue(NotebookSearch.matches("DANG", fields: ["đang triển khai"] ))
    }
    func testTermsCanMatchDifferentFieldsInAnyOrder() {
        XCTAssertTrue(NotebookSearch.matches("staging review", fields: ["Review PR", "Đã deploy lên staging"] ))
        XCTAssertFalse(NotebookSearch.matches("staging production", fields: ["Review PR", "Đã deploy lên staging"] ))
    }
    func testWhitespaceAndEmptySearch() {
        XCTAssertTrue(NotebookSearch.matches("  \n ", fields: []))
        XCTAssertTrue(NotebookSearch.matches("  du   an  ", fields: ["Dự án"] ))
        XCTAssertFalse(NotebookSearch.matches("missing", fields: []))
    }
}
