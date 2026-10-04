import XCTest
@testable import TransTools

final class PCM16WaveTests: XCTestCase {
    func testRoundTripPreservesAudioFormatAndSamples() throws {
        let samples = Data([1, 0, 255, 127, 0, 128, 0, 0])
        let wav = PCM16Wave.header(bytes: UInt32(samples.count), sampleRate: 24000, channels: 1) + samples
        let parsed = try PCM16Wave.read(wav)
        XCTAssertEqual(parsed.sampleRate, 24000)
        XCTAssertEqual(parsed.channels, 1)
        XCTAssertEqual(parsed.samples, samples)
    }
    func testMetadataBeforeAudioAndOddPaddingAreSupported() throws {
        var wav = PCM16Wave.header(bytes: 2, sampleRate: 16000, channels: 1)
        wav.insert(contentsOf: Data([74, 85, 78, 75, 1, 0, 0, 0, 88, 0]), at: 36)
        wav.append(contentsOf: [0, 0])
        XCTAssertEqual(try PCM16Wave.read(wav).samples.count, 2)
    }
    func testTruncatedAudioAndUnsupportedSampleEncodingAreRejected() {
        var wav = PCM16Wave.header(bytes: 8, sampleRate: 24000, channels: 1)
        XCTAssertThrowsError(try PCM16Wave.read(wav))
        wav.append(contentsOf: [0, 0, 0, 0, 0, 0, 0, 0])
        wav[34] = 32
        XCTAssertThrowsError(try PCM16Wave.read(wav))
    }
}
