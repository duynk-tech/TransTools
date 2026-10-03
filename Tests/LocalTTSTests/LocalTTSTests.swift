import XCTest
import AVFoundation
import CryptoKit
@testable import TransTools
import LocalSpeechBackend

final class LocalTTSTests: XCTestCase {
    func testSemanticVietnameseCorrection() {
        let text = "Không, ý mình không phải như vậy."
        let value = RuleBasedProsodyProcessor().process(text: text, context: ConversationContext(currentUtterance: text, detectedLanguage: "vi"))
        XCTAssertEqual(value.emotion, .correction)
        XCTAssertLessThan(value.rate, 0.44)
        XCTAssertTrue(value.pauses.contains { $0.offset <= 7 && $0.duration >= 0.3 })
        XCTAssertTrue(value.emphasis.contains { $0.matchedText == "không phải" })
    }
    func testQuestionAndBoundedContext() {
        let history = (0..<100).map { _ in UtteranceItem(text: String(repeating: "a", count: 2000)) }
        let context = ConversationContext(currentUtterance: "Bạn khỏe không?", detectedLanguage: "vi", recentUtterances: history)
        XCTAssertEqual(context.recentUtterances.count, 4)
        XCTAssertTrue(context.recentUtterances.allSatisfy { $0.text.count <= 512 })
        XCTAssertEqual(RuleBasedProsodyProcessor().process(text: context.currentUtterance, context: context).emotion, .question)
    }
    func testLanguageRouting() {
        let router = LanguageRouter.shared
        XCTAssertEqual(router.resolveEngine(for: "vi-VN", preference: .localNatural, isModelInstalled: true, localSupportedLanguages: ["vi", "en", "ja", "ko"]), .localNatural)
        XCTAssertEqual(router.resolveEngine(for: "zh-CN", preference: .localNatural, isModelInstalled: true, localSupportedLanguages: ["vi", "en", "ja", "ko"]), .system(reason: "unsupportedLocalLanguage"))
        XCTAssertEqual(router.resolveEngine(for: "en-US", preference: .localNatural, isModelInstalled: false, localSupportedLanguages: ["en"]), .system(reason: "modelNotInstalled"))
        XCTAssertEqual(router.resolveEngine(for: "en-US", preference: .system, isModelInstalled: true, localSupportedLanguages: ["en"]), .system(reason: "userSelectedSystemVoice"))
    }
    func testChecksumsAndTraversal() throws {
        let path = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: path) }
        let bytes = Data("valid model bytes".utf8)
        try bytes.write(to: path)
        let hash = SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
        try LocalTTSModelStore.verify(path, file: LocalTTSModelFile(path: "onnx/model.onnx", size: Int64(bytes.count), sha256: hash))
        XCTAssertThrowsError(try LocalTTSModelStore.verify(path, file: LocalTTSModelFile(path: "onnx/model.onnx", size: Int64(bytes.count), sha256: String(repeating: "0", count: 64))))
        XCTAssertThrowsError(try LocalTTSModelStore.verify(path, file: LocalTTSModelFile(path: "../escape.onnx", size: Int64(bytes.count), sha256: hash)))
        try Data("corrupted".utf8).write(to: path)
        XCTAssertThrowsError(try LocalTTSModelStore.verify(path, file: LocalTTSModelFile(path: "onnx/model.onnx", size: Int64(bytes.count), sha256: hash)))
    }
    func testSegmentProtection() {
        let input = "Dr. Smith paid 3.14 dollars. See https://example.com/test. Thanks!"
        let chunks = LocalNaturalTTSEngine.segmentIntoChunks(input)
        XCTAssertTrue(chunks.contains { $0.contains("Dr. Smith") && $0.contains("3.14") })
        XCTAssertTrue(chunks.contains { $0.contains("https://example.com/test.") })
    }
    func testRealModelAndAtomicInstallation() async throws {
        guard let fixture = ProcessInfo.processInfo.environment["LOCAL_TTS_FIXTURE"] else { throw XCTSkip("Set LOCAL_TTS_FIXTURE to the verified official model directory") }
        let base = FileManager.default.temporaryDirectory.appendingPathComponent("tts-tests-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: base) }
        XCTAssertFalse(LocalTTSModelStore.installed(in: base))
        let source = URL(fileURLWithPath: fixture)
        try await LocalTTSModelStore.shared.install(manifest: .default, base: base, sourceDirectory: source) { _, _, _ in }
        XCTAssertTrue(LocalTTSModelStore.installed(in: base))
        let original = LocalTTSModelStore.activeDirectory(in: base)
        let broken = base.appendingPathComponent("bad-fixture")
        try FileManager.default.createDirectory(at: broken, withIntermediateDirectories: true)
        do {
            try await LocalTTSModelStore.shared.install(manifest: .default, base: base, sourceDirectory: broken) { _, _, _ in }
            XCTFail("Incomplete model must fail")
        } catch {}
        XCTAssertEqual(LocalTTSModelStore.activeDirectory(in: base), original)
        XCTAssertTrue(LocalTTSModelStore.installed(in: base))
        let cancelled = Task {
            try await LocalTTSModelStore.shared.install(manifest: .default, base: base, sourceDirectory: source) { _, _, _ in }
        }
        cancelled.cancel()
        do { try await cancelled.value; XCTFail("Expected cancellation") } catch {}
        XCTAssertEqual(LocalTTSModelStore.activeDirectory(in: base), original)
        try await LocalTTSModelStore.shared.remove(base: base)
        XCTAssertFalse(LocalTTSModelStore.installed(in: base))
    }
    func testRealONNXSpeechInFourLanguages() async throws {
        guard let fixture = ProcessInfo.processInfo.environment["LOCAL_TTS_FIXTURE"] else { throw XCTSkip("No model fixture") }
        let output = URL(fileURLWithPath: "/tmp/transtools-natural-voice-samples", isDirectory: true)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let cases = [("vi", "Không, ý mình không phải như vậy. Chúng ta cùng thử lại nhé."),
                     ("en", "Hello! Let's practice speaking English together."),
                     ("ja", "こんにちは。一緒に日本語を勉強しましょう。"),
                     ("ko", "안녕하세요. 함께 한국어를 공부해요.")]
        for (language, text) in cases {
            let start = Date()
            let result = try await SupertonicSession.shared.synthesize(text: text, language: language, directory: URL(fileURLWithPath: fixture), speed: 1.0)
            XCTAssertGreaterThan(result.samples.count, result.sampleRate)
            XCTAssertTrue(result.samples.allSatisfy { $0.isFinite })
            XCTAssertGreaterThan(result.samples.map { abs($0) }.max() ?? 0, 0.01)
            let format = AVAudioFormat(standardFormatWithSampleRate: Double(result.sampleRate), channels: 1)!
            let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(result.samples.count))!
            buffer.frameLength = AVAudioFrameCount(result.samples.count)
            result.samples.withUnsafeBufferPointer { buffer.floatChannelData![0].update(from: $0.baseAddress!, count: $0.count) }
            let data = try XCTUnwrap(SystemTTSEngine.bufferToWav(buffer))
            try data.write(to: output.appendingPathComponent(language + ".wav"))
            print("[TTS test] \(language): \(Int(Date().timeIntervalSince(start) * 1000))ms, \(result.samples.count / result.sampleRate)s audio")
        }
        await SupertonicSession.shared.release()
    }
    func testRealNetworkDownload() async throws {
        guard ProcessInfo.processInfo.environment["LOCAL_TTS_NETWORK_TEST"] == "1" else { throw XCTSkip("Opt-in 399 MB integration download") }
        let base = FileManager.default.temporaryDirectory.appendingPathComponent("tts-download-test-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: base) }
        try await LocalTTSModelStore.shared.install(manifest: .default, base: base) { _, _, _ in }
        XCTAssertTrue(LocalTTSModelStore.installed(in: base))
    }
    func testActualSystemSynthesis() async throws {
        let result = try await SystemTTSEngine.shared.synthesize(text: "Hello, this is a system voice fallback test.", language: "en-US")
        XCTAssertGreaterThan(result.audioData.count, 44)
        XCTAssertGreaterThan(result.duration, 0)
    }
    @MainActor func testQueueCompletionAndCancelledPlayback() async throws {
        let format = AVAudioFormat(standardFormatWithSampleRate: 24000, channels: 1)!
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 2400)!
        buffer.frameLength = 2400
        buffer.floatChannelData![0].initialize(repeating: 0, count: 2400)
        let result = TTSAudioResult(audioData: try XCTUnwrap(SystemTTSEngine.bufferToWav(buffer)), duration: 0.1, engineType: "Test")
        let player = TTSAudioPlayer.shared
        defer { player.stop() }
        let first = expectation(description: "first completed once")
        let second = expectation(description: "second completed once")
        first.assertForOverFulfill = true; second.assertForOverFulfill = true
        try player.play(result: result, overridePolicy: .interruptCurrent, onComplete: { first.fulfill() })
        try player.play(result: result, overridePolicy: .queueSpeech, onComplete: { second.fulfill() })
        await fulfillment(of: [first, second], timeout: 3)
        XCTAssertFalse(player.isPlaying)
        let cancelled = expectation(description: "interrupted playback must not complete")
        cancelled.isInverted = true
        let replacement = expectation(description: "replacement completed")
        try player.play(result: result, overridePolicy: .interruptCurrent, onComplete: { cancelled.fulfill() })
        try player.play(result: result, overridePolicy: .interruptCurrent, onComplete: { replacement.fulfill() })
        await fulfillment(of: [replacement, cancelled], timeout: 0.5)
        XCTAssertFalse(player.isPlaying)
    }
    @MainActor func testPlayerQueueAndInterrupt() async throws {
        let format = AVAudioFormat(standardFormatWithSampleRate: 24000, channels: 1)!
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 24000)!
        buffer.frameLength = 24000
        buffer.floatChannelData![0].initialize(repeating: 0, count: 24000)
        let result = TTSAudioResult(audioData: try XCTUnwrap(SystemTTSEngine.bufferToWav(buffer)), duration: 1, engineType: "Test")
        let player = TTSAudioPlayer.shared
        defer { player.stop() }
        let first = UUID(), second = UUID(), third = UUID()
        try player.play(result: result, utteranceID: first, overridePolicy: .interruptCurrent)
        try player.play(result: result, utteranceID: second, overridePolicy: .queueSpeech)
        XCTAssertEqual(player.currentUtteranceID, first)
        try player.play(result: result, utteranceID: third, overridePolicy: .interruptCurrent)
        XCTAssertEqual(player.currentUtteranceID, third)
        player.stop()
        XCTAssertFalse(player.isPlaying)
        XCTAssertNil(player.currentUtteranceID)
    }
}
