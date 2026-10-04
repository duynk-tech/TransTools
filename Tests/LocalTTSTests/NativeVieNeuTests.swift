import XCTest
@testable import TransTools
@testable import LocalSpeechBackend

final class NativeVieNeuTests: XCTestCase {
    private var root: URL { ExternalTTSModel.vieneu.directory }
    func testTokenizerAndPhonemizerMatchOfficialSDK() throws {
        struct Golden: Decodable { let text: String; let phonemes: String; let tokens: [Int] }
        let goldenURL = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("vieneu-sdk-golden.json")
        let golden = try JSONDecoder().decode([Golden].self, from: Data(contentsOf: goldenURL))
        let dictionary = root.appendingPathComponent("sea_g2p.bin")
        guard FileManager.default.fileExists(atPath: dictionary.path) else { throw XCTSkip("Native pronunciation dictionary is not installed") }
        let tokenizer = try VieNeuTokenizer(url: root.appendingPathComponent("assets/VieNeu-TTS-v3-Turbo/onnx_update/tokenizer.json"))
        let phonemizer = try VieNeuPhonemizer(libraryURL: NativeVieNeu.resources.appendingPathComponent("libsea_g2p_rs.dylib"), dictionary: dictionary)
        for item in golden {
            XCTAssertEqual(try phonemizer.phonemes(item.text), item.phonemes, item.text)
            XCTAssertEqual(tokenizer.encode(item.phonemes), item.tokens, item.text)
        }
    }
    func testNativeInstallStreamingExportAndCancellation() async throws {
        guard ProcessInfo.processInfo.environment["TRANSTOOLS_TEST_INSTALLED_TTS"] == "1" else { throw XCTSkip("Opt-in real installed model test") }
        try await NativeVieNeuInstaller.shared.install { _ in }
        XCTAssertTrue(ExternalTTSModel.vieneu.isInstalled)
        let sink = NativeSink()
        let streamed = try await NativeVieNeu.shared.synthesize(text: "Xin chào, chúng ta cùng luyện phát âm tiếng Việt mỗi ngày nhé.", voice: "Hải Đăng", options: TTSOptions(rate: 0.44), onChunk: { try await sink.add($0) })
        XCTAssertEqual(streamed.engineType, "VieNeuNative")
        let count = await sink.packetCount()
        XCTAssertGreaterThan(count, 1)
        let full = try await NativeVieNeu.shared.synthesize(text: "Xin chào, chúc bạn một ngày học tập hiệu quả.", voice: "Hải Đăng", options: TTSOptions(rate: 0.37), onChunk: nil)
        let payload = try PCM16Wave.read(full.audioData)
        XCTAssertEqual(payload.sampleRate, 48000)
        XCTAssertGreaterThan(payload.samples.count, 4800*2)
        try full.audioData.write(to: URL(fileURLWithPath: "/tmp/trans-tools-vieneu-native.wav"))
        let task = Task { try await NativeVieNeu.shared.synthesize(text: String(repeating: "Chúng ta cùng luyện tập mỗi ngày. ", count: 8), voice: "Hải Đăng", options: .default, onChunk: nil) }
        try await Task.sleep(nanoseconds: 50_000_000); task.cancel()
        do { _ = try await task.value; XCTFail("Cancelled native request returned audio") } catch is CancellationError {} catch { XCTFail("Unexpected cancellation error: \(error)") }
        let recovered = try await NativeVieNeu.shared.synthesize(text: "Cùng học nhé.", voice: "Hải Đăng", options: TTSOptions(rate: 0.44), onChunk: nil)
        XCTAssertGreaterThan(recovered.duration, 0.1)
        await VieNeuSession.shared.release()
    }
}
private actor NativeSink {
    var count = 0
    func add(_ result: TTSAudioResult) throws { XCTAssertFalse(try PCM16Wave.read(result.audioData).samples.isEmpty); count += 1 }
    func packetCount() -> Int { count }
}
