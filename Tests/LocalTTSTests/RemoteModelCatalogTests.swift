import XCTest
@testable import TransTools

final class RemoteModelCatalogTests: XCTestCase {
    private func registry() -> ModelRegistry {
        let model = AIModelDescriptor(id: "fixture", name: "Original", summary: "Local", category: .tts,
            engineID: "native", version: "1", languages: ["vi"], requiredFiles: [], optionalFiles: [],
            runtime: .init(id: "onnx", name: "ONNX", minimumOSMajor: 14, appleSiliconOnly: false, recommendedRAMBytes: nil),
            capabilities: .init(offline: true, voiceCloning: false, streaming: false), license: "Fixture", recommended: false, dependencies: [])
        return .init(models: [model], packs: [])
    }
    func testMetadataUpdatePreservesRuntimeAndCapabilities() throws {
        let feed = RemoteModelCatalog(schemaVersion: 1, revision: 1, models: [.init(id: "fixture", engineID: "native", version: "1", name: "Updated", summary: "New description", recommended: true)])
        let result = try feed.applying(to: registry())
        XCTAssertEqual(result.models[0].name, "Updated")
        XCTAssertEqual(result.models[0].runtime.id, "onnx")
        XCTAssertFalse(result.models[0].capabilities.voiceCloning)
        XCTAssertEqual(result.models[0].languages, ["vi"])
    }
    func testUnsupportedAdapterVersionAndDuplicateRejected() {
        let entry = RemoteModelCatalog.Entry(id: "fixture", engineID: "native", version: "2", name: "Changed weights", summary: "", recommended: true)
        XCTAssertThrowsError(try RemoteModelCatalog(schemaVersion: 1, revision: 1, models: [entry]).applying(to: registry()))
        XCTAssertThrowsError(try RemoteModelCatalog(schemaVersion: 1, revision: 1, models: [entry, entry]).applying(to: registry()))
        XCTAssertThrowsError(try RemoteModelCatalog(schemaVersion: 2, revision: 1, models: []).applying(to: registry()))
    }
}
