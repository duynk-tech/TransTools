import Foundation
import CryptoKit
import Combine

public enum ModelDownloadState: Equatable, Sendable {
    case notInstalled
    case downloading(progress: Double, bytesWritten: Int64, totalBytes: Int64)
    case verifying
    case installed(version: String, diskUsageBytes: Int64)
    case failed(error: String)
}

private final class TTSDownloadProgress: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    private var lastEmission: TimeInterval = 0
    let callback: @Sendable (Int64) -> Void
    init(_ callback: @escaping @Sendable (Int64) -> Void) { self.callback = callback }
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {}
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(request.url?.scheme == "https" ? request : nil)
    }
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        // Coalesce network chunks before enqueueing any MainActor work.
        let now = ProcessInfo.processInfo.systemUptime
        guard now - lastEmission >= 0.15 else { return }
        lastEmission = now
        callback(totalBytesWritten)
    }
}

/// All large file operations are serialized away from MainActor.
actor LocalTTSModelStore {
    static let shared = LocalTTSModelStore()
    nonisolated static var base: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("TransTools/Models/TTS", isDirectory: true)
    }
    nonisolated static func activeDirectory(in base: URL = base) -> URL {
        guard let data = try? Data(contentsOf: base.appendingPathComponent("current.json")),
              let name = try? JSONDecoder().decode(String.self, from: data),
              name.hasPrefix("model-"), UUID(uuidString: String(name.dropFirst(6))) != nil else {
            return base.appendingPathComponent("uninstalled")
        }
        return base.appendingPathComponent(name, isDirectory: true)
    }
    nonisolated static func installed(in base: URL = base) -> Bool {
        let directory = activeDirectory(in: base)
        guard let data = try? Data(contentsOf: directory.appendingPathComponent("manifest.json")),
              let manifest = try? JSONDecoder().decode(LocalTTSModelManifest.self, from: data), manifest == .default else { return false }
        return manifest.files.allSatisfy { file in
            let attr = try? FileManager.default.attributesOfItem(atPath: directory.appendingPathComponent(file.path).path)
            return (attr?[.type] as? FileAttributeType) == .typeRegular && (attr?[.size] as? NSNumber)?.int64Value == file.size
        }
    }
    nonisolated static func verify(_ url: URL, file: LocalTTSModelFile) throws {
        guard !file.path.hasPrefix("/"), !file.path.split(separator: "/").contains(".."), file.sha256.count == 64 else {
            throw NSError(domain: "LocalTTS", code: 10, userInfo: [NSLocalizedDescriptionKey: "Metadata mô hình không hợp lệ."])
        }
        let attr = try FileManager.default.attributesOfItem(atPath: url.path)
        guard (attr[.size] as? NSNumber)?.int64Value == file.size else {
            throw NSError(domain: "LocalTTS", code: 11, userInfo: [NSLocalizedDescriptionKey: "Dung lượng tệp mô hình không đúng."])
        }
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hash = SHA256()
        while let data = try handle.read(upToCount: 1_048_576), !data.isEmpty {
            try Task.checkCancellation()
            hash.update(data: data)
        }
        let actual = hash.finalize().map { String(format: "%02x", $0) }.joined()
        guard actual == file.sha256 else {
            throw NSError(domain: "LocalTTS", code: 12, userInfo: [NSLocalizedDescriptionKey: "Checksum mô hình không khớp: \(file.path)"])
        }
    }
    func install(manifest: LocalTTSModelManifest, base: URL = base, sourceDirectory: URL? = nil, progress: @escaping @Sendable (Int64, Int64, Bool) -> Void) async throws {
        guard manifest == .default, manifest.downloadURL.scheme == "https" else { throw URLError(.badURL) }
        let fm = FileManager.default
        try fm.createDirectory(at: base, withIntermediateDirectories: true)
        let capacity = try base.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]).volumeAvailableCapacityForImportantUsage ?? 0
        guard capacity >= manifest.totalSizeBytes * 2 else {
            throw NSError(domain: "LocalTTS", code: 13, userInfo: [NSLocalizedDescriptionKey: "Cần khoảng \(ByteCountFormatter.string(fromByteCount: manifest.totalSizeBytes * 2, countStyle: .file)) trống để cài đặt an toàn."])
        }
        let staging = base.appendingPathComponent("staging-" + UUID().uuidString)
        try fm.createDirectory(at: staging, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: staging) }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 60
        configuration.timeoutIntervalForResource = 1800
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        var completed: Int64 = 0
        for file in manifest.files {
            try Task.checkCancellation()
            let destination = staging.appendingPathComponent(file.path)
            try fm.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
            let offset = completed
            let delegate = TTSDownloadProgress { count in progress(offset + min(count, file.size), manifest.totalSizeBytes, false) }
            let temporary: URL
            if let sourceDirectory {
                temporary = staging.appendingPathComponent(UUID().uuidString)
                try fm.copyItem(at: sourceDirectory.appendingPathComponent(file.path), to: temporary)
            } else {
                let (downloaded, response) = try await session.download(from: manifest.downloadURL.appendingPathComponent(file.path), delegate: delegate)
                guard let http = response as? HTTPURLResponse, http.statusCode == 200, response.url?.scheme == "https" else { throw URLError(.badServerResponse) }
                temporary = downloaded
            }
            defer { try? fm.removeItem(at: temporary) }
            // Keep the download view stable while each file is verified.
            // Switching to an indeterminate view for every file causes layout jumps.
            progress(completed + file.size, manifest.totalSizeBytes, false)
            try Self.verify(temporary, file: file)
            try Task.checkCancellation()
            try fm.moveItem(at: temporary, to: destination)
            completed += file.size
            progress(completed, manifest.totalSizeBytes, false)
        }
        progress(completed, manifest.totalSizeBytes, true)
        try JSONEncoder().encode(manifest).write(to: staging.appendingPathComponent("manifest.json"), options: .atomic)
        try Task.checkCancellation()
        let name = "model-" + UUID().uuidString
        let destination = base.appendingPathComponent(name)
        try fm.moveItem(at: staging, to: destination)
        do {
            // Atomic pointer commit: the existing model remains usable until this write succeeds.
            try Task.checkCancellation()
            try JSONEncoder().encode(name).write(to: base.appendingPathComponent("current.json"), options: .atomic)
        } catch { try? fm.removeItem(at: destination); throw error }
        // Keep the previous version until next removal; an in-flight session may still use it.
    }
    func diskUsage(base: URL = base) -> Int64 {
        guard let enumerator = FileManager.default.enumerator(at: base, includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey]) else { return 0 }
        return enumerator.reduce(Int64(0)) { total, item in
            guard let url = item as? URL, let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey]), values.isRegularFile == true else { return total }
            return total + Int64(values.fileSize ?? 0)
        }
    }
    func remove(base: URL = base) throws {
        let fm = FileManager.default
        if fm.fileExists(atPath: base.path) { try fm.removeItem(at: base) }
    }
}

@MainActor
public final class LocalTTSModelManager: ObservableObject {
    public static let shared = LocalTTSModelManager()
    @Published public private(set) var state: ModelDownloadState = .notInstalled
    @Published public private(set) var activeManifest: LocalTTSModelManifest?
    @Published public private(set) var diskUsageFormatted = "0 MB"
    @Published public private(set) var isInstalled = false
    @Published public private(set) var lastErrorMessage: String?
    @Published public var isNaturalVoiceEnabled = (UserDefaults.standard.object(forKey: "TTS_LocalNaturalEnabled") == nil ? true : UserDefaults.standard.bool(forKey: "TTS_LocalNaturalEnabled")) {
        didSet {
            UserDefaults.standard.set(isNaturalVoiceEnabled, forKey: "TTS_LocalNaturalEnabled")
            if !isNaturalVoiceEnabled { LocalTTSSession.shared.releaseResources() }
            // Models load lazily on the first utterance.
        }
    }
    private var task: Task<Void, Never>?
    private var generation = UUID()
    public nonisolated static var defaultActiveModelDirectory: URL { LocalTTSModelStore.activeDirectory() }
    public nonisolated static var defaultInstalledModelFilePath: URL { defaultActiveModelDirectory.appendingPathComponent(LocalTTSModelManifest.default.modelFileName) }
    public nonisolated static var defaultInstalledConfigFilePath: URL { defaultActiveModelDirectory.appendingPathComponent(LocalTTSModelManifest.default.configFileName) }
    public nonisolated static func isModelFileInstalled() -> Bool { LocalTTSModelStore.installed() }
    private init() {
        checkInstallation()

    }
    public func checkInstallation() {
        isInstalled = Self.isModelFileInstalled()
        activeManifest = isInstalled ? .default : nil
        if isInstalled {
            let bytes = LocalTTSModelManifest.default.totalSizeBytes
            diskUsageFormatted = ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
            state = .installed(version: LocalTTSModelManifest.default.version, diskUsageBytes: bytes)
            let token = generation
            Task {
                let usage = await LocalTTSModelStore.shared.diskUsage()
                guard generation == token, isInstalled else { return }
                diskUsageFormatted = ByteCountFormatter.string(fromByteCount: usage, countStyle: .file)
                if case .installed = state { state = .installed(version: LocalTTSModelManifest.default.version, diskUsageBytes: usage) }
            }
        } else { diskUsageFormatted = "0 MB"; state = .notInstalled }
    }
    public func downloadAndInstall(manifest: LocalTTSModelManifest = .default) {
        guard task == nil else { return }
        let token = UUID(); generation = token
        lastErrorMessage = nil
        state = .downloading(progress: 0, bytesWritten: 0, totalBytes: manifest.totalSizeBytes)
        task = Task {
            do {
                try await LocalTTSModelStore.shared.install(manifest: manifest) { written, total, verifying in
                    Task { @MainActor [weak self] in
                        guard let self, self.generation == token, !Task.isCancelled, self.task != nil else { return }
                        self.state = verifying ? .verifying : .downloading(progress: Double(written) / Double(total), bytesWritten: written, totalBytes: total)
                    }
                }
                guard generation == token, !Task.isCancelled else { return }
                LocalTTSSession.shared.releaseResources()
                checkInstallation()
                isNaturalVoiceEnabled = true
            } catch {
                guard generation == token else { return }
                checkInstallation()
                if !(error is CancellationError) && (error as NSError).code != NSURLErrorCancelled {
                    lastErrorMessage = error.localizedDescription
                    state = .failed(error: error.localizedDescription)
                }
            }
            if generation == token { task = nil }
        }
    }
    public func cancelDownload() {
        generation = UUID(); task?.cancel(); task = nil; checkInstallation()
    }
    public func removeModel() {
        cancelDownload(); isNaturalVoiceEnabled = false
        task = Task {
            do { try await LocalTTSModelStore.shared.remove(); checkInstallation() }
            catch { lastErrorMessage = error.localizedDescription; state = .failed(error: error.localizedDescription) }
            task = nil
        }
    }
    public func checkForUpdate() async -> Bool {
        // Pinned catalog; updates are shipped after compatibility tests, never arbitrary remote code.
        return activeManifest.map { $0.revision != LocalTTSModelManifest.default.revision } ?? false
    }
}
