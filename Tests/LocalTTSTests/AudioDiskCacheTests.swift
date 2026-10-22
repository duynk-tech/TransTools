import XCTest
@testable import TransTools
final class AudioDiskCacheTests: XCTestCase {
    func testEvictsOldAudioAndPreservesUnrelatedFilesAndSymlinks() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let outside = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? fm.removeItem(at: root); try? fm.removeItem(at: outside) }
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        try Data(repeating: 2, count: 10).write(to: outside)
        for index in 0..<3 {
            let file = root.appendingPathComponent("\(index).mp3")
            try Data(repeating: 1, count: 10).write(to: file)
            try fm.setAttributes([.modificationDate: Date(timeIntervalSince1970: Double(index))], ofItemAtPath: file.path)
        }
        let notes = root.appendingPathComponent("notes.json")
        try Data(repeating: 1, count: 100).write(to: notes)
        let link = root.appendingPathComponent("link.mp3")
        try fm.createSymbolicLink(at: link, withDestinationURL: outside)
        try AudioDiskCache.trim(directory: root, byteLimit: 20, fileLimit: 2)
        XCTAssertFalse(fm.fileExists(atPath: root.appendingPathComponent("0.mp3").path))
        XCTAssertTrue(fm.fileExists(atPath: notes.path)); XCTAssertTrue(fm.fileExists(atPath: outside.path))
        XCTAssertNil(AudioDiskCache.read(link))
        XCTAssertNil(AudioDiskCache.read(root.appendingPathComponent("1.mp3"), maximumBytes: 5))
        XCTAssertEqual(AudioDiskCache.read(root.appendingPathComponent("2.mp3"))?.count, 10)
    }
}
