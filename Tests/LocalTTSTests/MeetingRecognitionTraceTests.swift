import XCTest
@testable import TransTools

final class MeetingRecognitionTraceTests: XCTestCase {
    private func event(_ phase: String) -> MeetingRecognitionTrace.Event {
        .init(phase: phase, generation: UUID(), currentID: UUID(), raw: "Synthetic speech", committed: "Synthetic",
              rotationTail: "", captionCount: 1, liveText: "speech", final: false)
    }
    func testWritesOrderedLocalEventsAndPrivateFile() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("trace.jsonl")
        let trace = MeetingRecognitionTrace(url: url)
        trace.record(event("before")); trace.record(event("after")); trace.flushForTesting()
        let rows = try String(contentsOf: url).split(separator: "\n").map {
            try JSONSerialization.jsonObject(with: Data($0.utf8)) as! [String: Any]
        }
        XCTAssertEqual(rows.count, 2)
        XCTAssertEqual(rows.compactMap { $0["sequence"] as? Int }, [1, 2])
        XCTAssertEqual((rows[1]["event"] as? [String: Any])?["phase"] as? String, "after")
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        XCTAssertEqual((attributes[.posixPermissions] as? NSNumber)?.intValue, 0o600)
    }
    func testDiskLimitNeverTruncatesExistingData() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: url) }
        let existing = Data("existing\n".utf8)
        try existing.write(to: url)
        let trace = MeetingRecognitionTrace(url: url, maximumBytes: existing.count)
        trace.record(event("before")); trace.flushForTesting()
        XCTAssertEqual(try Data(contentsOf: url), existing)
    }
}
