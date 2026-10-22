import XCTest
import CryptoKit
@testable import TransTools

final class ModelRegistryTests: XCTestCase {
    func testRegistryUsesExactExistingManifests() throws {
        let registry = try ModelRegistry.current()
        XCTAssertEqual(Set(registry.models.map(\.id)).count, registry.models.count)
        let supertonic = try XCTUnwrap(registry.model("supertonic-3"))
        XCTAssertEqual(supertonic.downloadBytes, LocalTTSModelManifest.default.totalSizeBytes)
        let vie = try XCTUnwrap(registry.model("vieneu-v3-turbo"))
        XCTAssertEqual(vie.downloadBytes, try NativeVieNeuManifest.load().files.reduce(0) { $0 + $1.size })
        XCTAssertTrue(vie.capabilities.voiceCloning)
        XCTAssertFalse(supertonic.capabilities.voiceCloning)
        for model in registry.models {
            for file in model.requiredFiles {
                XCTAssertTrue(ModelArtifact.safePath(file.path))
                XCTAssertEqual(file.sha256.count, 64)
                XCTAssertEqual(try file.source.url().scheme, "https")
                XCTAssertFalse(file.path.hasSuffix(".pth"))
                XCTAssertFalse(file.path.hasSuffix(".py"))
            }
        }
        XCTAssertTrue(registry.packs.flatMap(\.modelIDs).allSatisfy { registry.model($0) != nil })
    }
    func testTraversalAndInsecureSourcesAreRejected() throws {
        for path in ["../model", "/model", "a/../b", "a//b", "a\\b", "a/%2e%2e/b", "a\n/b", "a/./b", ""] { XCTAssertFalse(ModelArtifact.safePath(path), path) }
        XCTAssertThrowsError(try ModelSource.direct(URL(string: "http://example.com/model")!).url())
        XCTAssertThrowsError(try ModelSource.huggingFace(repository: "../bad", revision: "main", path: "model.onnx").url())
    }
    func testChecksumsDetectCorruptionAndMissingFiles() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let data = Data("verified".utf8), file = dir.appendingPathComponent("model")
        let hash = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        let descriptor = LocalTTSModelFile(path: "model", size: Int64(data.count), sha256: hash)
        XCTAssertThrowsError(try LocalTTSModelStore.verify(file, file: descriptor))
        try data.write(to: file)
        XCTAssertNoThrow(try LocalTTSModelStore.verify(file, file: descriptor))
        try Data("corrupt!".utf8).write(to: file)
        XCTAssertThrowsError(try LocalTTSModelStore.verify(file, file: descriptor))
    }
    func testHardwareCompatibilityDoesNotConfuseAdvisoryAndIncompatible() throws {
        let model = try XCTUnwrap(ModelRegistry.current().model("vieneu-v3-turbo"))
        let intel = HardwareCapabilities(appleSilicon: false, logicalCPUs: 4, ramBytes: 4_000_000_000, osMajor: 14, metalAvailable: false)
        XCTAssertEqual(intel.compatibility(model), .recommended)
        let oldOS = HardwareCapabilities(appleSilicon: true, logicalCPUs: 8, ramBytes: 16_000_000_000, osMajor: 13, metalAvailable: true)
        if case .incompatible = oldOS.compatibility(model) {} else { XCTFail("Old OS must be rejected") }
    }
}
