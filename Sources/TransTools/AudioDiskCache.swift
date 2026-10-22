import Foundation

/// Only generated audio in this directory is eligible for automatic eviction.
/// User recordings, lessons, model files and exports are never touched.
enum AudioDiskCache {
    static func trim(directory: URL, byteLimit: Int64 = 128 * 1024 * 1024, fileLimit: Int = 512) throws {
        let fm = FileManager.default
        let urls = try fm.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey, .contentModificationDateKey])
        var files: [(URL, Int64, Date)] = []
        for url in urls where url.pathExtension == "mp3" {
            let values = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey, .contentModificationDateKey])
            guard values.isRegularFile == true, values.isSymbolicLink != true else { continue }
            files.append((url, Int64(values.fileSize ?? 0), values.contentModificationDate ?? .distantPast))
        }
        files.sort { $0.2 < $1.2 }
        var bytes = files.reduce(Int64(0)) { $0 + $1.1 }, count = files.count
        for file in files {
            guard bytes > byteLimit || count > fileLimit else { break }
            try fm.removeItem(at: file.0); bytes -= file.1; count -= 1
        }
    }
    static func read(_ url: URL, maximumBytes: Int = 16 * 1024 * 1024) -> Data? {
        guard let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey]),
              values.isRegularFile == true, values.isSymbolicLink != true,
              let bytes = values.fileSize, bytes > 0, bytes <= maximumBytes,
              let data = try? Data(contentsOf: url), data.count <= maximumBytes else { return nil }
        try? FileManager.default.setAttributes([.modificationDate: Date()], ofItemAtPath: url.path)
        return data
    }
}
