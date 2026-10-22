import Foundation
import CryptoKit

private final class ModelFileProgress: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    let update: @Sendable (Double) -> Void
    private var last = 0.0
    init(update: @escaping @Sendable (Double) -> Void) { self.update = update }
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {}
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(request.url?.scheme == "https" ? request : nil)
    }
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        let now = ProcessInfo.processInfo.systemUptime
        guard now - last > 0.2 else { return }; last = now
        if totalBytesExpectedToWrite > 0 { update(min(1, Double(totalBytesWritten) / Double(totalBytesExpectedToWrite))) }
    }
}

/// File-level recovery is independent of any inference runtime. No repository scripts execute.
actor ModelDownloadManager {
    static let shared = ModelDownloadManager()
    nonisolated static var cacheRoot: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("TransTools/Models/Downloads")
    }
    private var active: Set<String> = []
    func discardResume(for artifacts: [ModelArtifact]) {
        for artifact in artifacts {
            guard let source = try? artifact.source.url() else { continue }
            let key = SHA256.hash(data: Data((source.absoluteString + artifact.sha256).utf8)).map { String(format: "%02x", $0) }.joined()
            guard !active.contains(key) else { continue }
            try? FileManager.default.removeItem(at: Self.cacheRoot.appendingPathComponent(key + ".resume"))
            try? FileManager.default.removeItem(at: Self.cacheRoot.appendingPathComponent(key + ".part"))
        }
    }
    func fetch(_ artifact: ModelArtifact, destination: URL, bundle: Bundle = .main, cacheDirectory: URL? = nil, progress: @escaping @Sendable (Double) -> Void = { _ in }) async throws {
        guard ModelArtifact.safePath(artifact.path), artifact.bytes > 0,
              artifact.sha256.count == 64, artifact.sha256.allSatisfy({ $0.isHexDigit }) else { throw ModelManagerError.invalidArtifact }
        let source = try artifact.source.url(bundle: bundle)
        let cache = cacheDirectory ?? Self.cacheRoot
        let key = SHA256.hash(data: Data((source.absoluteString + artifact.sha256).utf8)).map { String(format: "%02x", $0) }.joined()
        guard active.insert(key).inserted else { throw ModelManagerError.inUse }
        defer { active.remove(key) }
        let fm = FileManager.default
        try fm.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        // Reject symlink parents as well as a symlink destination; never follow a model's links.
        var parent = destination
        while parent.path != "/" {
            if (try? parent.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) == true { throw ModelManagerError.invalidArtifact }
            parent.deleteLastPathComponent()
        }
        let descriptor = LocalTTSModelFile(path: artifact.path, size: artifact.bytes, sha256: artifact.sha256)
        if (try? LocalTTSModelStore.verify(destination, file: descriptor)) != nil { progress(1); return }
        try fm.createDirectory(at: cache, withIntermediateDirectories: true)
        let capacity = try destination.deletingLastPathComponent().resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]).volumeAvailableCapacityForImportantUsage ?? 0
        guard artifact.bytes <= Int64.max / 2, capacity >= artifact.bytes * 2 else { throw ModelManagerError.insufficientSpace }
        let resume = cache.appendingPathComponent(key + ".resume")
        let partial = cache.appendingPathComponent(key + ".part")
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 60; config.timeoutIntervalForResource = 3600
        let session = URLSession(configuration: config)
        defer { session.invalidateAndCancel() }
        let delegate = ModelFileProgress(update: progress)
        let temporary: URL
        if source.isFileURL {
            try? fm.removeItem(at: partial)
            try fm.copyItem(at: source, to: partial); temporary = partial
        } else {
            do {
                let result: (URL, URLResponse)
                if let data = try? Data(contentsOf: resume) {
                    do { result = try await session.download(resumeFrom: data, delegate: delegate) }
                    catch {
                        // Keep newly supplied resume data on cancellation, rather than restarting.
                        if (error as NSError).code == NSURLErrorCancelled || Task.isCancelled { throw error }
                        try? fm.removeItem(at: resume)
                        result = try await session.download(from: source, delegate: delegate)
                    }
                } else { result = try await session.download(from: source, delegate: delegate) }
                guard let response = result.1 as? HTTPURLResponse, [200, 206].contains(response.statusCode), response.url?.scheme == "https" else { throw URLError(.badServerResponse) }
                try? fm.removeItem(at: partial)
                try fm.moveItem(at: result.0, to: partial); temporary = partial
            } catch {
                if let data = (error as NSError).userInfo["NSURLSessionDownloadTaskResumeData"] as? Data { try data.write(to: resume, options: .atomic) }
                throw error
            }
        }
        do {
            try LocalTTSModelStore.verify(temporary, file: descriptor)
            try Task.checkCancellation()
            if fm.fileExists(atPath: destination.path) { _ = try fm.replaceItemAt(destination, withItemAt: temporary) }
            else { try fm.moveItem(at: temporary, to: destination) }
            try? fm.removeItem(at: resume); progress(1)
        } catch {
            // Failed validation is not a resumable model. Preserve the last installed file.
            try? fm.removeItem(at: partial)
            throw error
        }
    }
}
