import XCTest
@testable import TransTools

final class NotebookLearningPolicyTests: XCTestCase {
    func testMixedLanguageNotebookSelectsOnlyMatchingCompletedPairs() {
        let good = CaptionRecord(id: UUID(), start: 0, end: 1, original: "Hello", vietnamese: "Xin chào",
            sourceLanguage: "en", targetLanguage: "vi", translationSource: "Hello")
        let other = CaptionRecord(id: UUID(), start: 1, end: 2, original: "Bonjour", vietnamese: "Xin chào",
            sourceLanguage: "fr", targetLanguage: "vi")
        let prefix = CaptionRecord(id: UUID(), start: 2, end: 3, original: "Hello again", vietnamese: "Xin chào",
            sourceLanguage: "en", targetLanguage: "vi", translationSource: "Hello")
        let wrongTarget = CaptionRecord(id: UUID(), start: 3, end: 4, original: "Hello", vietnamese: "Bonjour",
            sourceLanguage: "en", targetLanguage: "fr")
        XCTAssertEqual(NotebookLearningPolicy.candidates([good, other, prefix, wrongTarget], language: "en"), [good])
    }
    func testLegacyRecordsRemainAvailableForManualConfirmation() {
        let legacy = CaptionRecord(id: UUID(), start: 0, end: 1, original: "Hello", vietnamese: "Xin chào")
        XCTAssertEqual(NotebookLearningPolicy.candidates([legacy], language: "en"), [legacy])
    }
}
