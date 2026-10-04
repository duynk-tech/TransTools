import Foundation
import CryptoKit
import LocalSpeechBackend

struct NativeVieNeuManifest: Codable, Equatable {
    struct File: Codable, Equatable { let path: String; let url: URL; let size: Int64; let sha256: String }
    let version: String
    let files: [File]
    static func load() throws -> Self {
        try JSONDecoder().decode(Self.self, from: Data(contentsOf: NativeVieNeu.resources.appendingPathComponent("vieneu-native-manifest.json")))
    }
    static func installed(at root: URL) -> Bool {
        guard let expected = try? load(), let data = try? Data(contentsOf: root.appendingPathComponent("native-installed.json")),
              let marker = try? JSONDecoder().decode(Self.self, from: data), marker == expected else { return false }
        return marker.files.allSatisfy {
            let attr = try? FileManager.default.attributesOfItem(atPath: root.appendingPathComponent($0.path).path)
            return (attr?[.type] as? FileAttributeType) == .typeRegular && (attr?[.size] as? NSNumber)?.int64Value == $0.size
        }
    }
    static func verify(_ file: File, at root: URL) throws {
        try LocalTTSModelStore.verify(root.appendingPathComponent(file.path), file: LocalTTSModelFile(path: file.path, size: file.size, sha256: file.sha256))
    }
}

actor NativeVieNeuInstaller {
    static let shared = NativeVieNeuInstaller()
    func install(progress: @escaping @Sendable (String) -> Void) async throws {
        let manifest = try NativeVieNeuManifest.load(), root = ExternalTTSModel.vieneu.directory, fm = FileManager.default
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        let config = URLSessionConfiguration.ephemeral; config.timeoutIntervalForResource = 1800
        let session = URLSession(configuration: config); defer { session.invalidateAndCancel() }
        for (index, file) in manifest.files.enumerated() {
            try Task.checkCancellation()
            progress("Đang chuẩn bị dữ liệu VieNeu · \(index+1)/\(manifest.files.count)")
            // Reuse only verified files from the old SDK installation.
            if (try? NativeVieNeuManifest.verify(file, at: root)) != nil { continue }
            let destination = root.appendingPathComponent(file.path)
            try fm.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
            let (download, response) = try await session.download(from: file.url)
            defer { try? fm.removeItem(at: download) }
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
            let dataFile = LocalTTSModelFile(path: file.path, size: file.size, sha256: file.sha256)
            try LocalTTSModelStore.verify(download, file: dataFile)
            try Task.checkCancellation()
            // Complete file replacement is atomic; a cancelled download cannot look installed.
            if fm.fileExists(atPath: destination.path) { _ = try fm.replaceItemAt(destination, withItemAt: download) }
            else { try fm.moveItem(at: download, to: destination) }
        }
        progress("Đang kiểm thử âm thanh VieNeu native…")
        let capture = NativeAudioCapture()
        try await VieNeuSession.shared.synthesize(text: "Xin chào, chúc bạn một ngày học tập hiệu quả.", voice: "Hải Đăng", directory: root, resources: NativeVieNeu.resources) { samples in
            guard samples.allSatisfy({ $0.isFinite }) else { throw URLError(.cannotDecodeContentData) }
            try capture.append(samples)
        }
        await VieNeuSession.shared.release()
        let output = capture.snapshot()
        guard output.total >= 4800, output.peak > 0.0001 else { throw URLError(.cannotDecodeContentData) }
        try Task.checkCancellation()
        try JSONEncoder().encode(manifest).write(to: root.appendingPathComponent("native-installed.json"), options: .atomic)
    }
}
