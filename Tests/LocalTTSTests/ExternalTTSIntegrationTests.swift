import XCTest
@testable import TransTools

/// Opt-in real model tests; never download models or change user preferences.
final class ExternalTTSIntegrationTests: XCTestCase {
    func testRealWorkerStreamingSwitchCancellationAndRecovery() async throws {
        guard ProcessInfo.processInfo.environment["TRANSTOOLS_TEST_INSTALLED_TTS"] == "1" else {
            throw XCTSkip("Set TRANSTOOLS_TEST_INSTALLED_TTS=1 after installing VieNeu and Qwen")
        }
        let resources = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Resources/SpeechRuntime")
        let chineseVoices = ExternalTTSModel.qwen.voices(for: "zh-CN")
        XCTAssertEqual(Set(chineseVoices.map(\.id)), ["vivian", "serena", "uncle_fu"])
        for language in ["zh", "en", "ja", "ko"] {
            XCTAssertTrue(ExternalTTSModel.qwen.voices(for: language).contains { $0.id == ExternalTTSModel.qwen.selectedVoice(for: language) })
        }
        let session = ExternalTTSSession(resources: resources)
        let sink = PacketSink()
        let options = TTSOptions(rate: 0.44, pitch: 1, volume: 0.8)
        let vi = try await session.synthesize(model: .vieneu, text: "Xin chào, chúng ta cùng luyện phát âm tiếng Việt mỗi ngày nhé.", language: "vi", options: options, onChunk: { try await sink.add($0) })
        XCTAssertGreaterThan(vi.duration, 0)
        let packetCount = await sink.count
        XCTAssertGreaterThan(packetCount, 1)
        let zh = try await session.synthesize(model: .qwen, text: "你好，我们一起学习吧。", language: "zh", options: options)
        XCTAssertEqual(try PCM16Wave.read(zh.audioData).sampleRate, 24000)
        let task = Task { try await session.synthesize(model: .qwen, text: String(repeating: "你好，我们一起学习吧。", count: 20), language: "zh", options: options) }
        try await Task.sleep(nanoseconds: 200_000_000)
        task.cancel()
        do { _ = try await task.value; XCTFail("Cancelled speech returned audio") } catch {}
        let recovered = try await session.synthesize(model: .vieneu, text: "Cùng học nhé.", language: "vi", options: options)
        XCTAssertEqual(try PCM16Wave.read(recovered.audioData).sampleRate, 48000)
        await session.releaseAndWait()
    }
}
private actor PacketSink {
    var count = 0
    func add(_ result: TTSAudioResult) throws {
        let parsed = try PCM16Wave.read(result.audioData)
        guard !parsed.samples.isEmpty else { throw URLError(.cannotDecodeContentData) }
        count += 1
    }
}
