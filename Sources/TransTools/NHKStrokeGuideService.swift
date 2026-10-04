import Foundation
import AppKit

final class NHKStrokeGuideService: ObservableObject {
    static let shared = NHKStrokeGuideService()

    private var memoryCache = NSCache<NSString, NSImage>()
    private let fileManager = FileManager.default

    private var cacheDirectory: URL {
        let dir = fileManager.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("TransTools/NHKStrokes", isDirectory: true)
        if !fileManager.fileExists(atPath: dir.path) {
            try? fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }

    private init() { memoryCache.countLimit = 24 }

    func clearMemoryCache() { memoryCache.removeAllObjects() }

    func imageURL(for id: String, isKatakana: Bool) -> URL {
        let folder = isKatakana ? "kana" : "hira"
        return URL(string: "https://www3.nhk.or.jp/nhkworld/lesson/assets/images/letters/detail/\(folder)/\(sourceID(id)).png")!
    }

    private func sourceID(_ id: String) -> String { ["dji": "ji2", "dzu": "zu2"][id] ?? id }

    func loadStrokeImage(for id: String, isKatakana: Bool, completion: @escaping (NSImage?) -> Void) {
        let cacheKey = "\(isKatakana ? "kata" : "hira")_\(id)" as NSString

        if let cached = memoryCache.object(forKey: cacheKey) {
            completion(cached)
            return
        }

        let personalFile = LocalJapaneseRecordings.directory.appendingPathComponent("Strokes")
            .appendingPathComponent("\(isKatakana ? "kana" : "hira")_\(sourceID(id)).png")
        if let data = try? Data(contentsOf: personalFile), let image = NSImage(data: data) {
            memoryCache.setObject(image, forKey: cacheKey)
            completion(image)
            return
        }

        let localFile = cacheDirectory.appendingPathComponent("\(cacheKey).png")
        if let localData = try? Data(contentsOf: localFile), let img = NSImage(data: localData) {
            memoryCache.setObject(img, forKey: cacheKey)
            completion(img)
            return
        }

        let url = imageURL(for: id, isKatakana: isKatakana)
        var request = URLRequest(url: url)
        request.setValue("https://www3.nhk.or.jp/nhkworld/lesson/vi/letters/hiragana.html", forHTTPHeaderField: "Referer")
        request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36", forHTTPHeaderField: "User-Agent")

        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            guard let data = data, let img = NSImage(data: data) else {
                DispatchQueue.main.async { completion(nil) }
                return
            }
            try? data.write(to: localFile)
            self?.memoryCache.setObject(img, forKey: cacheKey)
            DispatchQueue.main.async {
                completion(img)
            }
        }.resume()
    }
}
