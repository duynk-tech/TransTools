import XCTest
import AVFoundation
@testable import TransTools

final class MP3AudioExporterTests: XCTestCase {
    func testOfflineWAVBecomesPlayableMP3() async throws {
        guard MP3AudioExporter.encoder != nil else { throw XCTSkip("MP3 encoder not installed") }
        let input = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".wav")
        defer { try? FileManager.default.removeItem(at: input) }
        let format = AVAudioFormat(standardFormatWithSampleRate: 24000, channels: 1)!
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 24000)!
        buffer.frameLength = 24000
        buffer.floatChannelData![0].initialize(repeating: 0, count: 24000)
        try XCTUnwrap(SystemTTSEngine.bufferToWav(buffer)).write(to: input)
        let output = try await MP3AudioExporter.convert(input)
        defer { try? FileManager.default.removeItem(at: output) }
        XCTAssertEqual(output.pathExtension, "mp3")
        let asset = AVURLAsset(url: output)
        let duration = try await asset.load(.duration)
        XCTAssertGreaterThan(duration.seconds, 0.9)
        XCTAssertLessThan(duration.seconds, 1.2)
    }
}
