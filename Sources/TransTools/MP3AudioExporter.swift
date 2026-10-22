import Foundation

/// Encode locally; never upload generated speech to a conversion service.
enum MP3AudioExporter {
    static var encoder: URL? {
        [Bundle.main.url(forResource: "ffmpeg", withExtension: nil),
         URL(fileURLWithPath: "/opt/homebrew/bin/ffmpeg"),
         URL(fileURLWithPath: "/usr/local/bin/ffmpeg")]
            .compactMap { $0 }.first { FileManager.default.isExecutableFile(atPath: $0.path) }
    }
    static func convert(_ source: URL) async throws -> URL {
        guard let encoder else {
            throw NSError(domain: "AudioExport", code: 1, userInfo: [NSLocalizedDescriptionKey: "Chưa có bộ mã hóa MP3 trên máy. Bạn vẫn có thể lưu WAV."])
        }
        let worker = Task.detached(priority: .userInitiated) {
            let destination = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".mp3")
            let process = Process()
            process.executableURL = encoder
            process.arguments = ["-nostdin", "-hide_banner", "-loglevel", "error", "-i", source.path, "-vn", "-codec:a", "libmp3lame", "-q:a", "2", destination.path]
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            do {
                try Task.checkCancellation()
                try process.run()
                while process.isRunning {
                    if Task.isCancelled { process.terminate(); process.waitUntilExit(); throw CancellationError() }
                    Thread.sleep(forTimeInterval: 0.05)
                }
                try Task.checkCancellation()
                guard process.terminationStatus == 0,
                      (try destination.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0) > 0 else {
                    throw NSError(domain: "AudioExport", code: 2, userInfo: [NSLocalizedDescriptionKey: "Chưa chuyển được audio sang MP3. Hãy thử lưu WAV."])
                }
                return destination
            } catch {
                try? FileManager.default.removeItem(at: destination)
                throw error
            }
        }
        return try await withTaskCancellationHandler { try await worker.value }
            onCancel: { worker.cancel() }
    }
}
