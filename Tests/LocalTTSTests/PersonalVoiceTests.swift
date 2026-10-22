import XCTest
@testable import LocalSpeechBackend
@testable import TransTools

final class PersonalVoiceTests: XCTestCase {
    func testFrontEndMatchesKaldiReference() throws {
        let samples = (0..<48000).map { i -> Float in
            let t = Double(i) / 16000
            return Float((0.1 * sin(2 * .pi * 220 * t) + 0.04 * sin(2 * .pi * 731 * t)) * (0.6 + 0.4 * sin(2 * .pi * 3 * t)))
        }
        let actual = try VieNeuSpeakerEncoder.features(samples)
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("personal-voice-fbank.bin")
        let data = try Data(contentsOf: url)
        let expected = data.withUnsafeBytes { Array($0.bindMemory(to: Float.self)) }
        XCTAssertEqual(actual.count, expected.count)
        let error = zip(actual, expected).map { abs($0-$1) }.max() ?? 0
        XCTAssertLessThan(error, 0.025)
    }
    func testRealReferenceMatchesEncoderAndSynthesizes() async throws {
        guard ProcessInfo.processInfo.environment["TRANSTOOLS_TEST_PERSONAL_VOICE"] == "1" else { throw XCTSkip("Requires temporary official sample and installed VieNeu") }
        let input = try Data(contentsOf: URL(fileURLWithPath: "/tmp/trans-tools-reference-voice.f32"))
        let samples = input.withUnsafeBytes { Array($0.bindMemory(to: Float.self)) }
        let features = try VieNeuSpeakerEncoder.features(samples)
        try features.withUnsafeBytes { Data($0) }.write(to: URL(fileURLWithPath: "/tmp/trans-tools-swift-fbank.f32"))
        let actual = try VieNeuSpeakerEncoder.extract(samples: samples, encoder: URL(fileURLWithPath: "/tmp/trans-tools-speaker_encoder.onnx"))
        try actual.withUnsafeBytes { Data($0) }.write(to: URL(fileURLWithPath: "/tmp/trans-tools-swift-embedding.f32"))
        let golden = try Data(contentsOf: URL(fileURLWithPath: "/tmp/trans-tools-reference-embedding.f32")).withUnsafeBytes { Array($0.bindMemory(to: Float.self)) }
        let dot = zip(actual,golden).reduce(Float(0)) { $0 + $1.0*$1.1 }
        let norm = sqrt(actual.reduce(Float(0)) { $0+$1*$1 } * golden.reduce(Float(0)) { $0+$1*$1 })
        XCTAssertGreaterThan(dot/norm, 0.999)
        let id = UUID()
        let profile = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("TransTools/PersonalVoices/" + id.uuidString)
        try FileManager.default.createDirectory(at: profile, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: profile) }
        let derived = profile.appendingPathComponent("Models/vieneu")
        try FileManager.default.createDirectory(at: derived, withIntermediateDirectories: true)
        try JSONSerialization.data(withJSONObject: ["speaker_emb": actual]).write(to: derived.appendingPathComponent("voice.json"))
        let root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("TransTools/ExternalTTS/Models/vieneu")
        var audio: [Float] = []
        let capture = TestVoiceCapture()
        try await VieNeuSession.shared.synthesize(text: "Xin chào, tôi đang thử giọng cá nhân.", voice: "personal:" + id.uuidString, directory: root, resources: NativeVieNeu.resources) { part in await capture.append(part) }
        audio = await capture.samples
        XCTAssertGreaterThan(audio.count, 4800)
        XCTAssertTrue(audio.allSatisfy { $0.isFinite })
        XCTAssertGreaterThan(audio.map(abs).max() ?? 0, 0.0001)
        await VieNeuSession.shared.release()
    }
    func testLegacyRecordingAndModelIsolation() throws {
        let id = UUID()
        let metadata = try JSONSerialization.data(withJSONObject: ["id": id.uuidString, "name": "Giọng cũ", "created": 0, "duration": 6])
        let profile = try JSONDecoder().decode(PersonalVoiceProfile.self, from: metadata)
        XCTAssertNil(profile.referenceText)
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("personal-voice-layout-" + UUID().uuidString)
        let folder = root.appendingPathComponent(id.uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let original = folder.appendingPathComponent("reference.wav")
        try Data([1, 2, 3]).write(to: original)
        XCTAssertNil(PersonalVoiceModel.vieneu.existingFile(profile, root: root))
        let legacy = folder.appendingPathComponent("voice.json")
        try Data("{}".utf8).write(to: legacy)
        XCTAssertEqual(PersonalVoiceModel.vieneu.existingFile(profile, root: root), legacy)
        let modern = PersonalVoiceModel.vieneu.file(profile, root: root)
        try FileManager.default.createDirectory(at: modern.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("{}".utf8).write(to: modern)
        XCTAssertEqual(PersonalVoiceModel.vieneu.existingFile(profile, root: root), modern)
        try FileManager.default.removeItem(at: modern)
        try FileManager.default.removeItem(at: legacy)
        XCTAssertNil(PersonalVoiceModel.vieneu.existingFile(profile, root: root))
        XCTAssertEqual(try Data(contentsOf: original), Data([1, 2, 3]))
    }
    func testRejectsShortAndNonfiniteAudio() {
        XCTAssertThrowsError(try VieNeuSpeakerEncoder.features([Float](repeating: 0, count: 100)))
        XCTAssertThrowsError(try VieNeuSpeakerEncoder.features([Float](repeating: .nan, count: 48000)))
    }
}

private actor TestVoiceCapture { var samples: [Float] = []; func append(_ values: [Float]) { samples += values } }
