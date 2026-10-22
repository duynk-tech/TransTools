import XCTest
@testable import TransTools

final class NotebookSubtitleExportTests: XCTestCase {
    func testBilingualSubtitlePreservesTextAndValidTiming() {
        let records = [CaptionRecord(id: UUID(), start: 1.25, end: 2.5, original: "Hello!", vietnamese: "Xin chào!"),
                       CaptionRecord(id: UUID(), start: 3, end: 3, original: "Goodbye.", vietnamese: "")]
        let result = NotebookSubtitleExport.content(captions: records, mode: 0)
        XCTAssertTrue(result.contains("1\n00:00:01,250 --> 00:00:02,500\nHello!\nXin chào!\n\n2\n"))
        XCTAssertTrue(result.contains("00:00:03,000 --> 00:00:03,100"))
    }
    func testTranslationOnlyFallsBackWhenTranslationMissing() {
        let records = [CaptionRecord(id: UUID(), start: 0, end: 1, original: "Hello!", vietnamese: "Xin chào!"),
                       CaptionRecord(id: UUID(), start: 1, end: 2, original: "Goodbye.", vietnamese: "")]
        let result = NotebookSubtitleExport.content(captions: records, mode: 2)
        XCTAssertFalse(result.contains("Hello!"))
        XCTAssertTrue(result.contains("Xin chào!"))
        XCTAssertTrue(result.contains("Goodbye."))
    }
}
