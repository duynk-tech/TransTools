import XCTest
@testable import TransTools
final class AdaptiveLearningTests: XCTestCase {
    func testSameDayPracticeDoesNotPromote() {
        var state = LessonProgress()
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        for _ in 0..<8 { state.record(correct: true, now: now) }
        XCTAssertEqual(state.difficulty, 1)
        XCTAssertEqual(state.successfulDays.count, 1)
        XCTAssertGreaterThan(state.due, now)
    }
    func testSustainedSuccessAndMistakeChangeDifficulty() throws {
        var state = LessonProgress()
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        for day in 0..<3 { state.record(correct: true, now: now.addingTimeInterval(Double(day) * 86400)) }
        XCTAssertEqual(state.difficulty, 2)
        state.record(correct: false, now: now.addingTimeInterval(4 * 86400))
        XCTAssertEqual(state.difficulty, 1)
        XCTAssertTrue(state.successfulDays.isEmpty)
        let data = try JSONEncoder().encode(state)
        XCTAssertEqual(try JSONDecoder().decode(LessonProgress.self, from: data).attempts, 4)
    }
    func testStableLessonIdentityAndLanguageIsolation() {
        let a = AdaptiveLesson.make(language: "en", goal: "work", original: "Hello", meaning: "Xin chào", context: "Greeting")
        let b = AdaptiveLesson.make(language: "en", goal: "work", original: "Hello", meaning: "Xin chào", context: "Greeting")
        let c = AdaptiveLesson.make(language: "ja", goal: "work", original: "Hello", meaning: "Xin chào", context: "Greeting")
        XCTAssertEqual(a.id, b.id); XCTAssertNotEqual(a.id, c.id)
    }
    func testGenerationProfileIsolatesLanguageAndGoalWithoutSendingText() {
        let lesson = AdaptiveLesson.make(language: "en", goal: "work", original: "Private notebook content", meaning: "Nội dung riêng", context: "Câu từ Sổ tay")
        let other = AdaptiveLesson.make(language: "ja", goal: "work", original: "Other", meaning: "Khác", context: "")
        let progress = [lesson.id: LessonProgress(attempts: 4, successes: 1), other.id: LessonProgress(attempts: 100, successes: 100)]
        let profile = LearningGenerationProfile(lessons: [lesson, lesson, other], progress: progress, language: "en", goal: "work")
        XCTAssertEqual(profile.practicedSentences, 1)
        XCTAssertEqual(profile.accuracyPercent, 25)
        XCTAssertEqual(profile.sentencesNeedingReview, 1)
        XCTAssertFalse(profile.promptContext.contains(lesson.original))
        XCTAssertTrue(profile.promptContext.contains("do not increase difficulty"))
        let empty = LearningGenerationProfile(lessons: [lesson], progress: progress, language: "en", goal: "travel")
        XCTAssertNil(empty.accuracyPercent)
        XCTAssertEqual(empty.practicedSentences, 0)
    }
}
