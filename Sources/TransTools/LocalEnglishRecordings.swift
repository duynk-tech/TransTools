import Foundation
import CryptoKit

/// User-downloaded learning files, deliberately separate from distributed app resources.
enum LocalEnglishRecordings {
    private struct Catalog: Decodable { let source: String; let entries: [Entry] }
    private struct Entry: Decodable { let symbol: String; let file: String; let sha256: String }
    static var directory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("TransTools/Pronunciation/AudioLangEnglish", isDirectory: true)
    }
    private static let files: [String: URL] = {
        let folder = directory
        guard let data = try? Data(contentsOf: folder.appendingPathComponent("manifest.json")),
              let catalog = try? JSONDecoder().decode(Catalog.self, from: data),
              catalog.source == "http://audiolang.info/vi/english-alphabet/",
              catalog.entries.count == 26,
              Set(catalog.entries.map(\.symbol)) == Set(Array("ABCDEFGHIJKLMNOPQRSTUVWXYZ").map(String.init)) else { return [:] }
        var result: [String: URL] = [:]
        for entry in catalog.entries {
            guard entry.file == entry.symbol.lowercased() + ".mp3" else { continue }
            let url = folder.appendingPathComponent(entry.file)
            guard let audio = try? Data(contentsOf: url),
                  SHA256.hash(data: audio).map({ String(format: "%02x", $0) }).joined() == entry.sha256 else { continue }
            result[entry.symbol] = url
        }
        return result
    }()
    static func file(for symbol: String) -> URL? { files[symbol.uppercased()] }
}
