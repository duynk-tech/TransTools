import Foundation
import CryptoKit

/// Personal NHK downloads are stored outside the distributed app bundle.
enum LocalJapaneseRecordings {
    private struct Catalog: Decodable { let source: String; let entries: [Entry] }
    private struct Entry: Decodable { let id: String; let file: String; let sha256: String }
    static var directory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("TransTools/Pronunciation/NHKJapanese", isDirectory: true)
    }
    private static let files: [String: URL] = {
        let folder = directory
        guard let data = try? Data(contentsOf: folder.appendingPathComponent("manifest.json")),
              let catalog = try? JSONDecoder().decode(Catalog.self, from: data),
              catalog.source == "https://www3.nhk.or.jp/nhkworld/lesson/vi/letters/hiragana.html",
              catalog.entries.count == 104,
              Set(catalog.entries.map(\.id)).count == 104 else { return [:] }
        var result: [String: URL] = [:]
        for entry in catalog.entries {
            guard entry.id.range(of: "^[a-z0-9]+$", options: .regularExpression) != nil,
                  entry.file == entry.id + ".m4a" else { continue }
            let url = folder.appendingPathComponent(entry.file)
            guard let audio = try? Data(contentsOf: url),
                  SHA256.hash(data: audio).map({ String(format: "%02x", $0) }).joined() == entry.sha256 else { continue }
            result[entry.id] = url
        }
        return result
    }()
    static func file(for symbol: String) -> URL? {
        let items = (JapaneseNHKData.gojuonRows + JapaneseNHKData.dakuonRows + JapaneseNHKData.yoonRows).flatMap { $0.items }
        guard let item = items.first(where: { $0.hiragana == symbol || $0.katakana == symbol }) else { return nil }
        let sourceID = ["dji": "ji2", "dzu": "zu2"][item.id] ?? item.id
        return files[sourceID]
    }
}
