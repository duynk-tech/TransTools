import Foundation
import CryptoKit

/// Personal downloads remain outside the distributed application.
enum LocalChineseRecordings {
    private struct Catalog: Decodable { let source: String; let entries: [Entry] }
    private struct Entry: Decodable { let text: String; let file: String; let sha256: String }
    private static let files: [String: URL] = {
        let folder = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("TransTools/Pronunciation/ZIMChinese", isDirectory: true)
        guard let data = try? Data(contentsOf: folder.appendingPathComponent("manifest.json")),
              let catalog = try? JSONDecoder().decode(Catalog.self, from: data),
              catalog.source == "https://zim.vn/bang-phien-am-tieng-trung-pinyin" else { return [:] }
        var result: [String: URL] = [:]
        for entry in catalog.entries {
            guard entry.file.range(of: "^[a-f0-9]{20}\\.mp3$", options: .regularExpression) != nil else { continue }
            let url = folder.appendingPathComponent(entry.file)
            guard let audio = try? Data(contentsOf: url),
                  SHA256.hash(data: audio).map({ String(format: "%02x", $0) }).joined() == entry.sha256 else { continue }
            result[entry.text] = url
        }
        return result
    }()
    static func file(for text: String) -> URL? {
        let normalized = ["y (i)": "y", "w (u)": "w", "iou": "iu", "uei": "ui", "uen": "un"][text] ?? text
        return files[normalized]
    }
}
