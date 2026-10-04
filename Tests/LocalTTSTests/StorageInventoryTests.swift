import XCTest
@testable import TransTools

final class StorageInventoryTests: XCTestCase {
    func testCountsHiddenFilesWithoutFollowingSymlinks() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let outside = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root); try? FileManager.default.removeItem(at: outside) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
        try Data(repeating: 1, count: 17).write(to: root.appendingPathComponent(".hidden"))
        try Data(repeating: 2, count: 1000).write(to: outside.appendingPathComponent("private"))
        try FileManager.default.createSymbolicLink(at: root.appendingPathComponent("link"), withDestinationURL: outside)
        let entry = StorageEntry(id: "test", title: "Test", detail: "", url: root, removable: true, model: false)
        let scan = StorageInventory.scan([entry])[0]
        XCTAssertEqual(scan.bytes, 17)
        XCTAssertEqual(scan.files, 1)
        XCTAssertNil(scan.scanError)
        let linked = StorageEntry(id: "link", title: "Link", detail: "", url: root.appendingPathComponent("link"), removable: true, model: false)
        XCTAssertNotNil(StorageInventory.scan([linked])[0].scanError)
    }
    func testMissingAndSingleFile() throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let entry = StorageEntry(id: "file", title: "File", detail: "", url: file, removable: false, model: false)
        XCTAssertFalse(StorageInventory.scan([entry])[0].exists)
        try Data(repeating: 0, count: 31).write(to: file)
        defer { try? FileManager.default.removeItem(at: file) }
        XCTAssertEqual(StorageInventory.scan([entry])[0].bytes, 31)
        XCTAssertEqual(StorageInventory.scan([entry])[0].files, 1)
    }
}
