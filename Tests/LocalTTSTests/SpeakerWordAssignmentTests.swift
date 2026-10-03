import XCTest
@testable import TransTools

final class SpeakerWordAssignmentTests: XCTestCase {
    func testDominantCoverageInsteadOfMidpoint() {
        let spans = [SpeakerInterval(start: 0, end: 0.8, speaker: 1), SpeakerInterval(start: 0.48, end: 0.55, speaker: 2)]
        XCTAssertEqual(SpeakerWordAssignment.speaker(start: 0, end: 1, intervals: spans), 1)
    }
    func testOverlapAndSilenceRemainUnknown() {
        let overlap = [SpeakerInterval(start: 0, end: 1, speaker: 1), SpeakerInterval(start: 0, end: 1, speaker: 2)]
        XCTAssertNil(SpeakerWordAssignment.speaker(start: 0, end: 1, intervals: overlap))
        XCTAssertNil(SpeakerWordAssignment.speaker(start: 2, end: 3, intervals: overlap))
    }
    func testRepeatedIntervalsDoNotInflateConfidence() {
        let spans = [SpeakerInterval(start: 0, end: 0.35, speaker: 1), SpeakerInterval(start: 0, end: 0.35, speaker: 1)]
        XCTAssertNil(SpeakerWordAssignment.speaker(start: 0, end: 1, intervals: spans))
    }
    func testBoundaryAndInvalidTiming() {
        let spans = [SpeakerInterval(start: 0, end: 1, speaker: 1), SpeakerInterval(start: 1, end: 2, speaker: 2)]
        XCTAssertEqual(SpeakerWordAssignment.speaker(start: 1.1, end: 1.8, intervals: spans), 2)
        XCTAssertNil(SpeakerWordAssignment.speaker(start: 1, end: 1, intervals: spans))
    }
}

import AVFoundation
import FluidAudio

final class SpeakerStreamingTests: XCTestCase {
    func testBufferedStartupAndOverlappingWindows() async throws {
        guard let first = ProcessInfo.processInfo.environment["SPEAKER_TEST_AUDIO"],
              let second = ProcessInfo.processInfo.environment["SPEAKER_SECOND_AUDIO"] else {
            throw XCTSkip("Two local speech recordings required")
        }
        let converter = AudioConverter()
        let a = Array(try converter.resampleAudioFile(URL(fileURLWithPath: first)).prefix(128000))
        let b = Array(try converter.resampleAudioFile(URL(fileURLWithPath: second)).prefix(128000))
        let audio = a + [Float](repeating: 0, count: 16000) + b
        let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16000, channels: 1, interleaved: false)!
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(audio.count))!
        buffer.frameLength = AVAudioFrameCount(audio.count)
        audio.withUnsafeBufferPointer { source in buffer.floatChannelData![0].update(from: source.baseAddress!, count: audio.count) }
        let engine = SpeakerDiarization()
        let ready = expectation(description: "Model ready")
        let final = expectation(description: "Complete audio timeline")
        let lock = NSLock()
        var output: [SpeakerInterval] = []
        var didFinish = false
        let duration = Double(audio.count) / 16000
        engine.onStatus = { _, status in
            if status.hasPrefix("Tách giọng trên máy") { ready.fulfill() }
        }
        engine.onIntervals = { _, intervals, through in
            lock.lock(); defer { lock.unlock() }
            output.append(contentsOf: intervals)
            if through >= duration - 0.01, !didFinish { didFinish = true; final.fulfill() }
        }
        engine.start(token: UUID(), at: Date())
        // Feed audio while models are loading. The old implementation discarded it.
        engine.append(buffer)
        await fulfillment(of: [ready], timeout: 120)
        engine.stop()
        await fulfillment(of: [final], timeout: 120)
        XCTAssertFalse(output.isEmpty)
        XCTAssertTrue(output.contains { $0.start < 3 }, "Audio at startup must survive model loading")
        XCTAssertTrue(output.allSatisfy { $0.start >= 0 && $0.end <= duration + 0.01 && $0.end > $0.start })
        XCTAssertGreaterThanOrEqual(Set(output.compactMap(\.speaker)).count, 2)
    }
}
