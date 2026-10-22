import XCTest
import CryptoKit
@testable import TransTools

final class ModelDownloadManagerTests: XCTestCase {
    func testVerifiedAtomicReplacementAndCorruptSourcePreservesInstalledFile() async throws {
        let root = URL(fileURLWithPath: "/private/tmp").appendingPathComponent("model-download-test-" + UUID().uuidString)
        let resources = root.appendingPathComponent("Fixture.bundle/Contents/Resources")
        let fm = FileManager.default
        try fm.createDirectory(at: resources, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }
        let plist: [String: Any] = ["CFBundleIdentifier": "test.trans-tools.model", "CFBundleVersion": "1", "CFBundlePackageType": "BNDL"]
        try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0).write(to: resources.deletingLastPathComponent().appendingPathComponent("Info.plist"))
        let bundle = try XCTUnwrap(Bundle(url: root.appendingPathComponent("Fixture.bundle")))
        let source = resources.appendingPathComponent("model.bin")
        let data = Data(repeating: 41, count: 4096)
        try data.write(to: source)
        let sha = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        let artifact = ModelArtifact(path: "model.bin", source: .bundled(path: "model.bin"), bytes: Int64(data.count), sha256: sha)
        let destination = root.appendingPathComponent("installed/model.bin")
        let cache = root.appendingPathComponent("cache")
        let downloader = ModelDownloadManager()
        try await downloader.fetch(artifact, destination: destination, bundle: bundle, cacheDirectory: cache)
        XCTAssertEqual(try Data(contentsOf: destination), data)
        // A different trusted artifact/version has a corrupt payload. The installed version survives.
        let expected = Data(repeating: 42, count: 4096)
        let nextSHA = SHA256.hash(data: expected).map { String(format: "%02x", $0) }.joined()
        let next = ModelArtifact(path: "model.bin", source: .bundled(path: "model.bin"), bytes: Int64(data.count), sha256: nextSHA)
        do { try await downloader.fetch(next, destination: destination, bundle: bundle, cacheDirectory: cache); XCTFail("Must reject corruption") }
        catch { XCTAssertEqual(try Data(contentsOf: destination), data) }
        try expected.write(to: source)
        try await downloader.fetch(next, destination: destination, bundle: bundle, cacheDirectory: cache)
        XCTAssertEqual(try Data(contentsOf: destination), expected)
        XCTAssertTrue(((try? fm.contentsOfDirectory(atPath: cache.path)) ?? []).isEmpty)
    }
    func testRejectsSymlinkDestination() async throws {
        let root = URL(fileURLWithPath: "/private/tmp").appendingPathComponent("model-symlink-test-" + UUID().uuidString)
        let fm = FileManager.default
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }
        let target = root.appendingPathComponent("existing")
        let original = Data("preserve".utf8)
        try original.write(to: target)
        let link = root.appendingPathComponent("link")
        try fm.createSymbolicLink(at: link, withDestinationURL: target)
        let artifact = ModelArtifact(path: "model", source: .direct(URL(string: "https://example.com/model")!), bytes: 1, sha256: String(repeating: "0", count: 64))
        do { try await ModelDownloadManager().fetch(artifact, destination: link); XCTFail("Must reject symlink before downloading") }
        catch { XCTAssertEqual(try Data(contentsOf: target), original) }
    }
}
