import XCTest
@testable import TransTools

final class MeetingCheckpointTests: XCTestCase {
    private func session(id: UUID = UUID(), rows: [CaptionRecord]? = nil) -> MeetingSession {
        MeetingSession(id: id, title: "Meeting", createdAt: Date(timeIntervalSince1970: 1_700_000_000), durationSeconds: 20, audioSource: "System",
            captions: rows ?? [CaptionRecord(id: UUID(), start: 0, end: 2, original: "Hello", vietnamese: "Xin chào")])
    }
    private func temporaryURL() throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try FileManager.default.removeItem(at: directory) }
        return directory.appendingPathComponent("checkpoint.json")
    }

    func testOldRecordsDecodeWithoutInventedLanguage() throws {
        let json = "{\"id\":\"\(UUID())\",\"start\":0,\"end\":1,\"original\":\"Hello\",\"vietnamese\":\"Xin chào\"}"
        let row = try JSONDecoder().decode(CaptionRecord.self, from: Data(json.utf8))
        XCTAssertNil(row.sourceLanguage)
        XCTAssertNil(row.translationRevision)
    }

    func testMetadataRoundTrip() throws {
        let row = CaptionRecord(id: UUID(), start: 0, end: 3, original: "Hello again", vietnamese: "Xin chào",
            sourceLanguage: "en", targetLanguage: "vi", translationProvider: "google", translationModel: "test",
            sourceRevision: 3, translationSource: "Hello", translationRevision: 2)
        XCTAssertEqual(try JSONDecoder().decode(CaptionRecord.self, from: JSONEncoder().encode(row)), row)
    }

    func testCheckpointSurvivesRestartAndRemovalIsSessionScoped() async throws {
        let url = try temporaryURL(), original = session()
        let store = MeetingCheckpointStore()
        try await store.write(original, to: url)
        XCTAssertEqual(try MeetingCheckpointStore.load(from: url), original)
        try await store.remove(sessionID: UUID(), from: url)
        XCTAssertEqual(try MeetingCheckpointStore.load(from: url), original)
        try await store.remove(sessionID: original.id, from: url)
        XCTAssertNil(try MeetingCheckpointStore.load(from: url))
    }

    func testAnotherMeetingCannotOverwriteUnrecoveredData() async throws {
        let url = try temporaryURL(), original = session()
        let store = MeetingCheckpointStore()
        try await store.write(original, to: url)
        do { try await store.write(session(), to: url); XCTFail("Overwrote another meeting") }
        catch { XCTAssertEqual(try MeetingCheckpointStore.load(from: url), original) }
    }

    func testDamagedPrimaryRecoversLastValidCheckpoint() async throws {
        let url = try temporaryURL(), original = session()
        let store = MeetingCheckpointStore()
        try await store.write(original, to: url)
        var second = original; second.title = "Second snapshot"
        try await store.write(second, to: url)
        try Data("invalid".utf8).write(to: url)
        XCTAssertEqual(try MeetingCheckpointStore.load(from: url), second)
    }

    func testRecoveryPreservesManualEditsAndAddsNewRowsIdempotently() {
        var saved = session(); saved.title = "My title"; saved.notes = "My notes"
        let newRow = CaptionRecord(id: UUID(), start: 5, end: 7, original: "Next sentence", vietnamese: "")
        let checkpoint = session(id: saved.id, rows: saved.captions + [newRow])
        let result = MeetingCheckpointStore.merging(checkpoint, into: [saved])
        XCTAssertEqual(result.first?.title, "My title")
        XCTAssertEqual(result.first?.notes, "My notes")
        XCTAssertEqual(result.first?.captions.count, 2)
        XCTAssertEqual(MeetingCheckpointStore.merging(checkpoint, into: result), result)
    }

    func testOlderCheckpointCannotReplaceCorrectedSentence() {
        let id = UUID()
        let newer = CaptionRecord(id: id, start: 0, end: 3, original: "We meet tomorrow", vietnamese: "Ngày mai gặp",
            sourceRevision: 3)
        let stale = CaptionRecord(id: id, start: 0, end: 2, original: "We meet today", vietnamese: "", sourceRevision: 2)
        let saved = session(rows: [newer])
        XCTAssertEqual(MeetingCheckpointStore.merging(session(id: saved.id, rows: [stale]), into: [saved])[0].captions, [newer])
    }

    func testNewTimingDoesNotEraseCompletedTranslation() {
        let id = UUID()
        let savedRow = CaptionRecord(id: id, start: 0, end: 2, original: "Hello", vietnamese: "Xin chào", sourceRevision: 1)
        let incoming = CaptionRecord(id: id, start: 0, end: 3, original: "Hello", vietnamese: "", sourceRevision: 1)
        let saved = session(rows: [savedRow])
        let result = MeetingCheckpointStore.merging(session(id: saved.id, rows: [incoming]), into: [saved])
        XCTAssertEqual(result[0].captions[0].vietnamese, "Xin chào")
        XCTAssertEqual(result[0].captions[0].end, 3)
    }

    func testJournalWritesChangedRowsWithoutRewritingBase() async throws {
        let url = try temporaryURL(), original = session()
        let store = MeetingCheckpointStore()
        try await store.write(original, to: url)
        let base = try Data(contentsOf: url)
        var updated = original
        updated.captions.append(CaptionRecord(id: UUID(), start: 4, end: 6, original: "Next", vietnamese: "Tiếp theo"))
        try await store.write(updated, to: url)
        XCTAssertEqual(try Data(contentsOf: url), base)
        XCTAssertEqual(try MeetingCheckpointStore.load(from: url), updated)
    }

    func testPartialLastJournalEventRetainsCommittedRowsAndCanResumeWriting() async throws {
        let url = try temporaryURL(), original = session()
        let store = MeetingCheckpointStore()
        try await store.write(original, to: url)
        let journal = url.appendingPathExtension("journal")
        try Data("{partial".utf8).write(to: journal)
        XCTAssertEqual(try MeetingCheckpointStore.load(from: url), original)
        var next = original
        next.captions.append(CaptionRecord(id: UUID(), start: 4, end: 5, original: "Next", vietnamese: ""))
        try await MeetingCheckpointStore().write(next, to: url)
        XCTAssertEqual(try MeetingCheckpointStore.load(from: url), next)
    }

    func testMalformedCommittedJournalCannotBeOverwritten() async throws {
        let url = try temporaryURL(), original = session()
        try await MeetingCheckpointStore().write(original, to: url)
        let journal = url.appendingPathExtension("journal")
        let damaged = Data("invalid\n".utf8)
        try damaged.write(to: journal)
        XCTAssertThrowsError(try MeetingCheckpointStore.load(from: url))
        do { try await MeetingCheckpointStore().write(original, to: url); XCTFail("Replaced damaged journal") }
        catch { XCTAssertEqual(try Data(contentsOf: journal), damaged) }
    }
}
