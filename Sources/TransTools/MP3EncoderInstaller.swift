import Foundation
import Combine
import AppKit

@MainActor final class MP3EncoderInstaller: ObservableObject {
    static let shared = MP3EncoderInstaller()
    @Published private(set) var available = MP3AudioExporter.encoder != nil
    @Published private(set) var installing = false
    @Published private(set) var message = ""
    @Published var showSetup = false

    static var homebrew: URL? {
        ["/opt/homebrew/bin/brew", "/usr/local/bin/brew"].map { URL(fileURLWithPath: $0) }
            .first { FileManager.default.isExecutableFile(atPath: $0.path) }
    }
    func refresh() { available = MP3AudioExporter.encoder != nil }
    func install() {
        refresh()
        guard !available, !installing, let brew = Self.homebrew else { return }
        installing = true
        message = "Đang tải và cài bộ mã hóa MP3 qua Homebrew…"
        Task {
            do {
                try await Self.runInstall(brew)
                refresh()
                message = available ? "Đã sẵn sàng lưu MP3." : "Cài đặt kết thúc nhưng chưa tìm thấy FFmpeg. Hãy kiểm tra lại."
            } catch { message = error.localizedDescription }
            installing = false
        }
    }
    nonisolated private static func runInstall(_ brew: URL) async throws {
        try await Task.detached(priority: .utility) {
            let process = Process()
            process.executableURL = brew
            process.arguments = ["install", "ffmpeg"]
            var environment = ProcessInfo.processInfo.environment
            environment["HOMEBREW_NO_AUTO_UPDATE"] = "1"
            environment["HOMEBREW_NO_ANALYTICS"] = "1"
            environment["PATH"] = brew.deletingLastPathComponent().path + ":/usr/bin:/bin:/usr/sbin:/sbin"
            process.environment = environment
            process.standardInput = FileHandle.nullDevice
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            try process.run()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else {
                throw NSError(domain: "MP3Setup", code: Int(process.terminationStatus), userInfo: [NSLocalizedDescriptionKey: "Chưa cài được FFmpeg qua Homebrew. Kiểm tra Internet và quyền thư mục Homebrew, sau đó thử lại. Bạn vẫn có thể lưu WAV."])
            }
        }.value
    }
}
