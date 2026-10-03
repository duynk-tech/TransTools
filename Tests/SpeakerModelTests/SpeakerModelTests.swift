import XCTest
import FluidAudio

final class SpeakerModelTests: XCTestCase {
    func testActualCoreMLSpeechInference() async throws {
        guard let path = ProcessInfo.processInfo.environment["SPEAKER_TEST_AUDIO"] else {
            throw XCTSkip("Set SPEAKER_TEST_AUDIO to a local speech fixture to run model inference")
        }
        let models = try await DiarizerModels.downloadIfNeeded()
        let manager = DiarizerManager()
        manager.initialize(models: models)
        let audio = try AudioConverter().resampleAudioFile(URL(fileURLWithPath: path))
        let result = try manager.performCompleteDiarization(audio)
        XCTAssertFalse(result.segments.isEmpty, "Speech should produce timed segments")
        XCTAssertTrue(result.segments.contains { !$0.speakerId.isEmpty && $0.qualityScore > 0.01 })
        XCTAssertTrue(result.segments.allSatisfy { $0.startTimeSeconds >= 0 && $0.endTimeSeconds > $0.startTimeSeconds })
        print("Actual speech segments: \(result.segments.count), tracked voices: \(Set(result.segments.map(\.speakerId)).count)")
    }
    func testDifferentVoiceAudio() async throws {
        guard let second = ProcessInfo.processInfo.environment["SPEAKER_SECOND_AUDIO"],
              let first = ProcessInfo.processInfo.environment["SPEAKER_TEST_AUDIO"] else { throw XCTSkip("Two local fixtures required") }
        let models = try await DiarizerModels.downloadIfNeeded()
        let manager = DiarizerManager(); manager.initialize(models: models)
        let converter = AudioConverter()
        let a = try converter.resampleAudioFile(URL(fileURLWithPath: first))
        let b = try converter.resampleAudioFile(URL(fileURLWithPath: second))
        let audio = a + [Float](repeating: 0, count: 16000) + b
        let result = try manager.performCompleteDiarization(audio)
        let voices = Set(result.segments.filter { !$0.speakerId.isEmpty }.map(\.speakerId))
        print("Different-voice fixture: \(voices.count) tracked voices")
        XCTAssertGreaterThanOrEqual(voices.count, 2)
    }

}
