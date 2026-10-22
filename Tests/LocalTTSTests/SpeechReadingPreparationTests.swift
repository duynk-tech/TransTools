import XCTest
@testable import TransTools
final class SpeechReadingPreparationTests: XCTestCase {
    func testOnlyTokenRangesChange() throws {
        let source = "Chương IV: ngày 20/10/2026, tỷ lệ 1:2 đạt 50%. Giữ nguyên câu này!"
        let tokens = SpeechReadingPreparation.tokens(in: source)
        XCTAssertEqual(tokens.map(\.text), ["IV", "20/10/2026", "1:2", "50%"])
        let readings = [SpeechReadingPreparation.Reading(id: 0, spoken: "bốn"), .init(id: 3, spoken: "năm mươi phần trăm")]
        XCTAssertEqual(try SpeechReadingPreparation.apply(readings, tokens: tokens, to: source), "Chương bốn: ngày 20/10/2026, tỷ lệ 1:2 đạt năm mươi phần trăm. Giữ nguyên câu này!")
    }
    func testRejectsUnknownOrDuplicateIDs() {
        let source = "50%", tokens = SpeechReadingPreparation.tokens(in: source)
        XCTAssertThrowsError(try SpeechReadingPreparation.apply([.init(id: 4, spoken: "khác")], tokens: tokens, to: source))
        XCTAssertThrowsError(try SpeechReadingPreparation.apply([.init(id: 0, spoken: "năm mươi phần trăm"), .init(id: 0, spoken: "khác")], tokens: tokens, to: source))
    }
    func testUnitsAndAcronymsPreserveSurroundingWords() throws {
        let source = "CPU 80%, RAM 16GB lúc 8:30. Không đổi câu gốc."
        let tokens = SpeechReadingPreparation.tokens(in: source)
        XCTAssertEqual(tokens.map(\.text), ["CPU", "80%", "RAM", "16GB", "8:30"])
        let result = try SpeechReadingPreparation.apply([.init(id: 3, spoken: "mười sáu gigabyte")], tokens: tokens, to: source)
        XCTAssertEqual(result, "CPU 80%, RAM mười sáu gigabyte lúc 8:30. Không đổi câu gốc.")
    }
    func testReaderPausesAtParagraphBoundary() {
        let parts = SpeechReadingPlan.parts("Xin chào. Hẹn gặp lại!\nMột đoạn khác.", sentencePause: 0.4, paragraphPause: 1)
        XCTAssertEqual(parts.count, 3)
        XCTAssertEqual(parts.map(\.pause), [0.4, 1, 1])
    }
}
