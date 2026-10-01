import SwiftUI
import AppKit
import Foundation
import Combine

// MARK: - GitHub Release API Models

struct GitHubRelease: Codable {
    let tagName: String
    let name: String?
    let body: String?
    let htmlUrl: String
    let assets: [GitHubAsset]
    let publishedAt: String?

    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case name
        case body
        case htmlUrl = "html_url"
        case assets
        case publishedAt = "published_at"
    }
}

struct GitHubAsset: Codable {
    let name: String
    let browserDownloadUrl: String
    let size: Int?

    enum CodingKeys: String, CodingKey {
        case name
        case browserDownloadUrl = "browser_download_url"
        case size
    }
}

// MARK: - App Updater State & Manager

@MainActor
final class AppUpdater: NSObject, ObservableObject, URLSessionDownloadDelegate {
    static let shared = AppUpdater()

    static let repoOwner = "duynk-tech"
    static let repoName = "TransTools"
    static let repoURLString = "https://github.com/duynk-tech/TransTools"
    static let releasesAPIURL = URL(string: "https://api.github.com/repos/\(repoOwner)/\(repoName)/releases/latest")!

    @Published var isChecking: Bool = false
    @Published var updateAvailable: Bool = false
    @Published var latestVersion: String = ""
    @Published var releaseTitle: String = ""
    @Published var releaseNotes: String = ""
    @Published var downloadURL: URL? = nil
    @Published var htmlURL: URL? = nil
    @Published var lastCheckedDate: Date? = nil

    // Download & Install Progress
    @Published var isDownloading: Bool = false
    @Published var downloadProgress: Double = 0.0
    @Published var installStatusMessage: String = ""
    @Published var hasError: Bool = false
    @Published var errorMessage: String = ""
    @Published var showUpdateSheet: Bool = false

    private var downloadTask: URLSessionDownloadTask?
    private var downloadContinuation: CheckedContinuation<URL, Error>?

    var currentVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.2.0"
    }

    var currentVersionDisplay: String {
        "v\(currentVersion)"
    }

    override init() {
        super.init()
    }

    // MARK: - Semantic Version Comparison

    static func isVersion(_ newVer: String, greaterThan currentVer: String) -> Bool {
        func parseVersion(_ v: String) -> [Int] {
            let clean = v.trimmingCharacters(in: CharacterSet(charactersIn: "vV \t\n\r"))
            return clean.split(separator: ".").compactMap { Int($0) }
        }

        let newParts = parseVersion(newVer)
        let currentParts = parseVersion(currentVer)
        let maxLen = max(newParts.count, currentParts.count)

        for i in 0..<maxLen {
            let n = i < newParts.count ? newParts[i] : 0
            let c = i < currentParts.count ? currentParts[i] : 0
            if n > c { return true }
            if n < c { return false }
        }
        return false
    }

    // MARK: - Check For Updates

    func checkForUpdates(userInitiated: Bool = false) {
        guard !isChecking else { return }
        isChecking = true
        hasError = false
        errorMessage = ""

        if userInitiated {
            installStatusMessage = "Đang kiểm tra bản cập nhật mới từ GitHub..."
        }

        Task {
            do {
                var request = URLRequest(url: Self.releasesAPIURL)
                request.timeoutInterval = 15
                request.setValue("application/vnd.github.v3+json", forHTTPHeaderField: "Accept")
                request.setValue("TransTools-AppUpdater/\(currentVersion)", forHTTPHeaderField: "User-Agent")

                let (data, response) = try await URLSession.shared.data(for: request)

                guard let httpResponse = response as? HTTPURLResponse else {
                    throw NSError(domain: "AppUpdater", code: -1, userInfo: [NSLocalizedDescriptionKey: "Không nhận được phản hồi từ máy chủ."])
                }

                if httpResponse.statusCode == 404 {
                    // No release created yet on github
                    self.isChecking = false
                    self.updateAvailable = false
                    self.lastCheckedDate = Date()
                    if userInitiated {
                        self.installStatusMessage = "Hiện chưa có bản phát hành nào trên GitHub (\(Self.repoURLString)). Bạn đang ở bản mới nhất!"
                    }
                    return
                }

                guard httpResponse.statusCode == 200 else {
                    throw NSError(domain: "AppUpdater", code: httpResponse.statusCode, userInfo: [NSLocalizedDescriptionKey: "Máy chủ trả về mã lỗi HTTP \(httpResponse.statusCode)."])
                }

                let release = try JSONDecoder().decode(GitHubRelease.self, from: data)
                let tagClean = release.tagName.trimmingCharacters(in: CharacterSet(charactersIn: "vV \t\n\r"))
                self.lastCheckedDate = Date()

                if Self.isVersion(tagClean, greaterThan: self.currentVersion) {
                    self.updateAvailable = true
                    self.latestVersion = tagClean
                    self.releaseTitle = release.name ?? "TransTools v\(tagClean)"
                    self.releaseNotes = release.body ?? "Đã có phiên bản mới với nhiều cải tiến và sửa lỗi."
                    self.htmlURL = URL(string: release.htmlUrl)

                    // Find zip asset for macOS
                    if let zipAsset = release.assets.first(where: {
                        let name = $0.name.lowercased()
                        return name.hasSuffix(".zip") || name.contains("transtools") || name.hasSuffix(".dmg")
                    }) {
                        self.downloadURL = URL(string: zipAsset.browserDownloadUrl)
                    } else if let firstAsset = release.assets.first {
                        self.downloadURL = URL(string: firstAsset.browserDownloadUrl)
                    } else {
                        self.downloadURL = nil
                    }

                    self.installStatusMessage = "Đã có bản cập nhật mới v\(tagClean)!"
                    if userInitiated {
                        self.showUpdateSheet = true
                    }
                } else {
                    self.updateAvailable = false
                    self.installStatusMessage = "Bạn đang sử dụng phiên bản mới nhất (v\(self.currentVersion))."
                }

                self.isChecking = false
            } catch {
                self.isChecking = false
                if userInitiated {
                    self.hasError = true
                    self.errorMessage = "Không thể kiểm tra cập nhật: \(error.localizedDescription)"
                    self.installStatusMessage = self.errorMessage
                }
            }
        }
    }

    // MARK: - Download & Auto Install

    func downloadAndInstallUpdate() {
        guard let downloadURL = downloadURL else {
            // Fallback to browser
            if let htmlURL = htmlURL ?? URL(string: "\(Self.repoURLString)/releases") {
                NSWorkspace.shared.open(htmlURL)
            }
            return
        }

        guard !isDownloading else { return }
        isDownloading = true
        downloadProgress = 0.0
        hasError = false
        errorMessage = ""
        installStatusMessage = "Đang tải xuống bản cập nhật..."

        Task {
            do {
                let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("TransToolsUpdate-\(UUID().uuidString)")
                try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

                let destinationZip = tempDir.appendingPathComponent("TransTools-Update.zip")

                // Download with progress
                let downloadedURL = try await startDownloadWithProgress(from: downloadURL)
                try FileManager.default.moveItem(at: downloadedURL, to: destinationZip)

                self.installStatusMessage = "Đang giải nén và chuẩn bị cài đặt..."
                self.downloadProgress = 1.0

                // Unpack using ditto
                let extractedDir = tempDir.appendingPathComponent("Extracted")
                try FileManager.default.createDirectory(at: extractedDir, withIntermediateDirectories: true)

                let unzipProcess = Process()
                unzipProcess.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
                unzipProcess.arguments = ["-xk", destinationZip.path, extractedDir.path]
                try unzipProcess.run()
                unzipProcess.waitUntilExit()

                guard unzipProcess.terminationStatus == 0 else {
                    throw NSError(domain: "AppUpdater", code: -2, userInfo: [NSLocalizedDescriptionKey: "Lỗi giải nén tệp cập nhật."])
                }

                // Find .app inside extracted folder
                let fileManager = FileManager.default
                let extractedContents = try fileManager.contentsOfDirectory(atPath: extractedDir.path)
                guard let appFileName = extractedContents.first(where: { $0.hasSuffix(".app") }) else {
                    throw NSError(domain: "AppUpdater", code: -3, userInfo: [NSLocalizedDescriptionKey: "Không tìm thấy tệp TransTools.app trong bản cập nhật."])
                }

                let newAppPath = extractedDir.appendingPathComponent(appFileName).path
                let currentAppPath = Bundle.main.bundleURL.path

                self.installStatusMessage = "Đang cập nhật và khởi động lại TransTools..."

                // Spawn update script detached
                try launchUpdateScript(newAppPath: newAppPath, currentAppPath: currentAppPath, tempDir: tempDir.path)

            } catch {
                self.isDownloading = false
                self.hasError = true
                self.errorMessage = "Cài đặt thất bại: \(error.localizedDescription)"
                self.installStatusMessage = self.errorMessage
            }
        }
    }

    private func startDownloadWithProgress(from url: URL) async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            self.downloadContinuation = continuation
            let session = URLSession(configuration: .default, delegate: self, delegateQueue: nil)
            let task = session.downloadTask(with: url)
            self.downloadTask = task
            task.resume()
        }
    }

    // MARK: - URLSessionDownloadDelegate

    nonisolated func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        if totalBytesExpectedToWrite > 0 {
            let progress = Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)
            Task { @MainActor in
                self.downloadProgress = progress
                let percent = Int(progress * 100)
                let mbDownloaded = Double(totalBytesWritten) / 1_048_576.0
                let mbTotal = Double(totalBytesExpectedToWrite) / 1_048_576.0
                self.installStatusMessage = String(format: "Đang tải xuống: %d%% (%.1f / %.1f MB)", percent, mbDownloaded, mbTotal)
            }
        }
    }

    nonisolated func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        Task { @MainActor in
            if let continuation = self.downloadContinuation {
                self.downloadContinuation = nil
                continuation.resume(returning: location)
            }
        }
    }

    nonisolated func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error = error {
            Task { @MainActor in
                if let continuation = self.downloadContinuation {
                    self.downloadContinuation = nil
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    // MARK: - Execute Detached Update Script

    private func launchUpdateScript(newAppPath: String, currentAppPath: String, tempDir: String) throws {
        let pid = ProcessInfo.processInfo.processIdentifier

        let scriptContent = """
        #!/bin/bash
        TARGET_PID=\(pid)
        NEW_APP="\(newAppPath)"
        CURRENT_APP="\(currentAppPath)"
        TEMP_DIR="\(tempDir)"

        # Wait for old app process to terminate
        while kill -0 "$TARGET_PID" 2>/dev/null; do
            sleep 0.3
        done

        # Remove quarantine attribute from new binary
        /usr/bin/xattr -dr com.apple.quarantine "$NEW_APP" 2>/dev/null || true

        # Replace app bundle
        /bin/rm -rf "$CURRENT_APP"
        /usr/bin/ditto "$NEW_APP" "$CURRENT_APP"

        # Cleanup temporary files
        /bin/rm -rf "$TEMP_DIR"

        # Relaunch the new application
        /usr/bin/open "$CURRENT_APP"
        exit 0
        """

        let scriptFile = URL(fileURLWithPath: tempDir).appendingPathComponent("install_update.sh")
        try scriptContent.write(to: scriptFile, atomically: true, encoding: .utf8)

        // Set executable permissions
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scriptFile.path)

        // Execute background detached process
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = [scriptFile.path]
        try process.run()

        // Terminate current running application cleanly
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            NSApplication.shared.terminate(nil)
        }
    }
}

// MARK: - Auto Update Popover & Settings UI View

struct UpdateSheetView: View {
    @ObservedObject var updater = AppUpdater.shared
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Header
            HStack(spacing: 10) {
                ZStack {
                    LinearGradient(
                        colors: [Color.blue, Color.accentColor],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                    .frame(width: 40, height: 40)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

                    Image(systemName: "arrow.triangle.2.circlepath.circle.fill")
                        .font(.system(size: 22, weight: .bold))
                        .foregroundStyle(.white)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(updater.updateAvailable ? "Có bản cập nhật mới!" : "Cập nhật TransTools")
                        .font(.system(size: 15, weight: .bold, design: .rounded))

                    HStack(spacing: 6) {
                        Text("Hiện tại: \(updater.currentVersionDisplay)")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)

                        if updater.updateAvailable {
                            Image(systemName: "arrow.right")
                                .font(.system(size: 9))
                                .foregroundStyle(.secondary)
                            Text("v\(updater.latestVersion)")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(Color.green)
                        }
                    }
                }

                Spacer()

                Button {
                    updater.showUpdateSheet = false
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }

            Divider()

            if updater.updateAvailable {
                VStack(alignment: .leading, spacing: 8) {
                    Text(updater.releaseTitle.isEmpty ? "TransTools v\(updater.latestVersion)" : updater.releaseTitle)
                        .font(.system(size: 13, weight: .semibold))

                    ScrollView {
                        Text(updater.releaseNotes)
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(8)
                    }
                    .frame(maxHeight: 120)
                    .background(Color(nsColor: .controlBackgroundColor).opacity(0.6))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }

                if updater.isDownloading {
                    VStack(alignment: .leading, spacing: 6) {
                        ProgressView(value: updater.downloadProgress)
                            .progressViewStyle(.linear)

                        Text(updater.installStatusMessage)
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                    .padding(.top, 4)
                } else {
                    HStack(spacing: 10) {
                        Button {
                            updater.downloadAndInstallUpdate()
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "arrow.down.circle.fill")
                                Text("Cập nhật & Khởi động lại")
                            }
                            .font(.system(size: 12, weight: .semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                            .background(Color.accentColor)
                            .foregroundStyle(.white)
                            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        }
                        .buttonStyle(.plain)

                        if let htmlURL = updater.htmlURL {
                            Button {
                                NSWorkspace.shared.open(htmlURL)
                            } label: {
                                HStack(spacing: 4) {
                                    Text("Xem Release")
                                    Image(systemName: "arrow.up.right.square")
                                }
                                .font(.system(size: 11, weight: .medium))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 8)
                                .background(Color.secondary.opacity(0.12))
                                .foregroundStyle(.primary)
                                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            } else {
                VStack(spacing: 12) {
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.seal.fill")
                            .font(.system(size: 24))
                            .foregroundStyle(.green)

                        VStack(alignment: .leading, spacing: 2) {
                            Text("Bạn đang dùng phiên bản mới nhất")
                                .font(.system(size: 13, weight: .semibold))
                            Text("Phiên bản hiện tại \(updater.currentVersionDisplay)")
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                    .padding(10)
                    .background(Color.green.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

                    HStack {
                        Button {
                            updater.checkForUpdates(userInitiated: true)
                        } label: {
                            HStack(spacing: 6) {
                                if updater.isChecking {
                                    ProgressView()
                                        .controlSize(.small)
                                } else {
                                    Image(systemName: "arrow.clockwise")
                                }
                                Text(updater.isChecking ? "Đang kiểm tra..." : "Kiểm tra lại")
                            }
                            .font(.system(size: 11, weight: .medium))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(Color.secondary.opacity(0.12))
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                        }
                        .buttonStyle(.plain)
                        .disabled(updater.isChecking)

                        Spacer()

                        if let htmlURL = URL(string: "\(AppUpdater.repoURLString)/releases") {
                            Button {
                                NSWorkspace.shared.open(htmlURL)
                            } label: {
                                HStack(spacing: 4) {
                                    Text("Lịch sử cập nhật trên GitHub")
                                    Image(systemName: "arrow.up.right.square")
                                }
                                .font(.system(size: 11))
                                .foregroundStyle(Color.accentColor)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }

            if updater.hasError {
                Text(updater.errorMessage)
                    .font(.system(size: 11))
                    .foregroundStyle(.red)
                    .padding(.top, 2)
            }
        }
        .padding(16)
        .frame(width: 380)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

// MARK: - Auto Update Navigation Badge

struct AutoUpdateNavBadge: View {
    @ObservedObject var updater = AppUpdater.shared

    var body: some View {
        if updater.updateAvailable {
            Button {
                updater.showUpdateSheet = true
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.up.circle.fill")
                    Text("Cập nhật v\(updater.latestVersion)")
                }
                .font(.system(size: 10, weight: .bold))
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.green.opacity(0.18))
                .foregroundStyle(Color.green)
                .clipShape(Capsule())
            }
            .buttonStyle(.plain)
            .help("Đã có bản cập nhật mới v\(updater.latestVersion)! Nhấn để nâng cấp ngay.")
            .popover(isPresented: $updater.showUpdateSheet) {
                UpdateSheetView()
            }
        }
    }
}

// MARK: - Settings Tab View for Auto Updates

struct SettingsUpdateTabView: View {
    @ObservedObject var updater = AppUpdater.shared
    @AppStorage("AutoCheckUpdates") private var autoCheckUpdates: Bool = true

    var body: some View {
        ScrollView(.vertical, showsIndicators: true) {
            VStack(alignment: .leading, spacing: 14) {
                // 1. Current App Info Card
                HStack(spacing: 12) {
                    MiniAvatarView(size: 38)
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text("TransTools")
                                .font(.system(size: 14, weight: .bold, design: .rounded))
                            Text(updater.currentVersionDisplay)
                                .font(.system(size: 10, weight: .bold))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.secondary.opacity(0.12))
                                .clipShape(Capsule())
                        }
                        Text("Phát triển bởi DuyNK-Tech • GitHub: duynk-tech/TransTools")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                .padding(10)
                .background(Color(nsColor: .controlBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

                // 2. Auto Check Toggle
                VStack(alignment: .leading, spacing: 6) {
                    Text("TỰ ĐỘNG CẬP NHẬT TỪ GITHUB")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.secondary)

                    Toggle("Tự động kiểm tra bản phát hành mới khi mở ứng dụng", isOn: $autoCheckUpdates)
                        .font(.system(size: 12, weight: .medium))

                    Text("Khi có release mới trên github.com/duynk-tech/TransTools, ứng dụng sẽ thông báo và cho phép tự động tải về cài đặt.")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineSpacing(2)
                }
                .padding(10)
                .background(Color(nsColor: .controlBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

                // 3. Status & Action Card
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("TRẠNG THÁI PHIÊN BẢN")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(.secondary)
                        Spacer()
                        if let date = updater.lastCheckedDate {
                            Text("Kiểm tra lần cuối: \(date.formatted(date: .omitted, time: .shortened))")
                                .font(.system(size: 10))
                                .foregroundStyle(.tertiary)
                        }
                    }

                    if updater.updateAvailable {
                        HStack(spacing: 10) {
                            Image(systemName: "arrow.up.circle.fill")
                                .font(.system(size: 22))
                                .foregroundStyle(Color.green)

                            VStack(alignment: .leading, spacing: 2) {
                                Text("Đã có bản cập nhật mới: v\(updater.latestVersion)!")
                                    .font(.system(size: 13, weight: .bold))
                                    .foregroundStyle(Color.green)
                                Text(updater.releaseTitle.isEmpty ? "Khuyến nghị nâng cấp để nhận các tính năng mới." : updater.releaseTitle)
                                    .font(.system(size: 11))
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                        }
                        .padding(10)
                        .background(Color.green.opacity(0.1))
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

                        if updater.isDownloading {
                            VStack(alignment: .leading, spacing: 6) {
                                ProgressView(value: updater.downloadProgress)
                                    .progressViewStyle(.linear)
                                Text(updater.installStatusMessage)
                                    .font(.system(size: 11))
                                    .foregroundStyle(.secondary)
                            }
                        } else {
                            HStack(spacing: 8) {
                                Button {
                                    updater.downloadAndInstallUpdate()
                                } label: {
                                    HStack(spacing: 6) {
                                        Image(systemName: "arrow.down.circle.fill")
                                        Text("Nâng cấp & Khởi động lại ngay")
                                    }
                                    .font(.system(size: 12, weight: .semibold))
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 7)
                                    .background(Color.accentColor)
                                    .foregroundStyle(.white)
                                    .clipShape(RoundedRectangle(cornerRadius: 6))
                                }
                                .buttonStyle(.plain)

                                if let htmlURL = updater.htmlURL {
                                    Button {
                                        NSWorkspace.shared.open(htmlURL)
                                    } label: {
                                        HStack(spacing: 4) {
                                            Text("Xem Release")
                                            Image(systemName: "arrow.up.right.square")
                                        }
                                        .font(.system(size: 11))
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 7)
                                        .background(Color.secondary.opacity(0.12))
                                        .clipShape(RoundedRectangle(cornerRadius: 6))
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                    } else {
                        HStack(spacing: 10) {
                            Image(systemName: "checkmark.seal.fill")
                                .font(.system(size: 20))
                                .foregroundStyle(Color.green)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(updater.installStatusMessage.isEmpty ? "TransTools đang ở phiên bản mới nhất (\(updater.currentVersionDisplay))" : updater.installStatusMessage)
                                    .font(.system(size: 12, weight: .medium))
                            }
                            Spacer()
                        }
                        .padding(10)
                        .background(Color.secondary.opacity(0.06))
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

                        HStack {
                            Button {
                                updater.checkForUpdates(userInitiated: true)
                            } label: {
                                HStack(spacing: 6) {
                                    if updater.isChecking {
                                        ProgressView().controlSize(.small)
                                    } else {
                                        Image(systemName: "arrow.clockwise")
                                    }
                                    Text(updater.isChecking ? "Đang kiểm tra từ GitHub..." : "Kiểm tra bản cập nhật mới")
                                }
                                .font(.system(size: 12, weight: .medium))
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(Color.accentColor.opacity(0.12))
                                .foregroundStyle(Color.accentColor)
                                .clipShape(RoundedRectangle(cornerRadius: 6))
                            }
                            .buttonStyle(.plain)
                            .disabled(updater.isChecking)

                            Spacer()

                            if let url = URL(string: "\(AppUpdater.repoURLString)/releases") {
                                Button {
                                    NSWorkspace.shared.open(url)
                                } label: {
                                    HStack(spacing: 4) {
                                        Text("Releases trên GitHub")
                                        Image(systemName: "arrow.up.right.square")
                                    }
                                    .font(.system(size: 11))
                                    .foregroundStyle(Color.accentColor)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }

                    if updater.hasError {
                        Text(updater.errorMessage)
                            .font(.system(size: 11))
                            .foregroundStyle(.red)
                    }
                }
                .padding(10)
                .background(Color(nsColor: .controlBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
            .padding(.trailing, 2)
        }
        .frame(height: 380)
    }
}

