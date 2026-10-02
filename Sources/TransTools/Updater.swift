import SwiftUI
import AppKit
import Foundation
import Combine
import CryptoKit

// MARK: - App Updater State & Manager

@MainActor
final class AppUpdater: NSObject, ObservableObject, URLSessionDownloadDelegate {
    static let shared = AppUpdater()

    static let repoOwner = "duynk-tech"
    static let repoName = "TransTools"
    static let repoURLString = "https://github.com/duynk-tech/TransTools"
    static let releasesAPIURL = URL(string: "https://trans-tools.vercel.app/updates/latest.json")!
    static let releasesURLString = "https://trans-tools.vercel.app/releases"

    @Published var didCheckSuccessfully = false
    private var expectedZipSHA256 = ""
    @Published var isChecking: Bool = false
    @Published var updateAvailable: Bool = false
    @Published var latestVersion: String = ""
    @Published var releaseTitle: String = ""
    @Published var releaseNotes: String = ""
    @Published var downloadURL: URL? = nil
    @Published var htmlURL: URL? = nil
    @Published var lastCheckedDate: Date? = UserDefaults.standard.object(forKey: "UpdateLastCheckedDate") as? Date {
        didSet { UserDefaults.standard.set(lastCheckedDate, forKey: "UpdateLastCheckedDate") }
    }

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
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.3.1"
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
        guard !isChecking && !isDownloading else { return }
        isChecking = true
        didCheckSuccessfully = false
        updateAvailable = false
        downloadURL = nil
        hasError = false
        errorMessage = ""

        if userInitiated {
            installStatusMessage = "Đang kiểm tra bản cập nhật mới từ TransTools..."
        }

        Task {
            do {
                var request = URLRequest(url: Self.releasesAPIURL, cachePolicy: .reloadIgnoringLocalCacheData)
                request.timeoutInterval = 15
                request.setValue("application/json", forHTTPHeaderField: "Accept")
                request.setValue("TransTools-AppUpdater/\(currentVersion)", forHTTPHeaderField: "User-Agent")

                let (data, response) = try await URLSession.shared.data(for: request)

                guard let httpResponse = response as? HTTPURLResponse else {
                    throw NSError(domain: "AppUpdater", code: -1, userInfo: [NSLocalizedDescriptionKey: "Không nhận được phản hồi từ máy chủ."])
                }

                if httpResponse.statusCode == 404 {
                    throw NSError(domain: "AppUpdater", code: 404, userInfo: [NSLocalizedDescriptionKey:
                        "Nguồn cập nhật chưa có bản phát hành. Vui lòng thử lại sau."])
                }

                guard httpResponse.statusCode == 200 else {
                    throw NSError(domain: "AppUpdater", code: httpResponse.statusCode, userInfo: [NSLocalizedDescriptionKey: "Máy chủ trả về mã lỗi HTTP \(httpResponse.statusCode)."])
                }

                let release = try JSONDecoder().decode(UpdateManifest.self, from: data)
                try release.validate()
                let tagClean = release.version
                self.lastCheckedDate = Date()
                self.didCheckSuccessfully = true
                self.latestVersion = tagClean
                self.releaseTitle = release.title
                self.releaseNotes = release.notes
                self.htmlURL = release.releaseURL
                self.expectedZipSHA256 = release.zip.sha256.lowercased()

                if Self.isVersion(tagClean, greaterThan: self.currentVersion) {
                    self.updateAvailable = true
                    self.downloadURL = release.zip.url

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
                self.hasError = true
                self.errorMessage = "Không thể kiểm tra cập nhật: \(error.localizedDescription)"
                self.installStatusMessage = self.errorMessage
            }
        }
    }

    // MARK: - Download & Auto Install

    func downloadAndInstallUpdate() {
        guard let downloadURL = downloadURL else {
            // Fallback to browser
            if let htmlURL = htmlURL ?? URL(string: Self.releasesURLString) {
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

                let digest = SHA256.hash(data: try Data(contentsOf: destinationZip))
                    .map { String(format: "%02x", $0) }.joined()
                guard digest == self.expectedZipSHA256 else {
                    throw NSError(domain: "AppUpdater", code: -2, userInfo: [NSLocalizedDescriptionKey:
                        "Bộ cài không khớp SHA256. Đã dừng cập nhật; hãy tải lại."])
                }
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

                // Find .app inside extracted folder (recursively in case archive has a root folder)
                let fileManager = FileManager.default
                var foundAppPath: String? = nil
                if let subpaths = try? fileManager.subpathsOfDirectory(atPath: extractedDir.path) {
                    for path in subpaths {
                        if path.hasSuffix(".app") {
                            foundAppPath = extractedDir.appendingPathComponent(path).path
                            break
                        }
                    }
                }

                guard let newAppPath = foundAppPath else {
                    throw NSError(domain: "AppUpdater", code: -3, userInfo: [NSLocalizedDescriptionKey: "Không tìm thấy tệp TransTools.app trong bản cập nhật đã giải nén."])
                }

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

    func cancelDownload() {
        downloadTask?.cancel()
        downloadTask = nil
        if let continuation = downloadContinuation {
            downloadContinuation = nil
            continuation.resume(throwing: CancellationError())
        }
        isDownloading = false
        installStatusMessage = "Đã hủy tải xuống."
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
        let result: Result<URL, Error>
        do {
            guard let response = downloadTask.response as? HTTPURLResponse, response.statusCode == 200 else {
                throw URLError(.badServerResponse)
            }
            let retained = FileManager.default.temporaryDirectory.appendingPathComponent("TransToolsDownload-\(UUID().uuidString).zip")
            try FileManager.default.moveItem(at: location, to: retained)
            result = .success(retained)
        } catch { result = .failure(error) }
        Task { @MainActor in
            if let continuation = self.downloadContinuation {
                self.downloadContinuation = nil
                continuation.resume(with: result)
            } else if case .success(let url) = result { try? FileManager.default.removeItem(at: url) }
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
        let scriptPath = "/tmp/transtools_relaunch_\(pid).sh"

        let scriptContent = """
        #!/bin/bash
        TARGET_PID=\(pid)
        NEW_APP="\(newAppPath)"
        CURRENT_APP="\(currentAppPath)"
        TEMP_DIR="\(tempDir)"
        SCRIPT_PATH="\(scriptPath)"

        # 1. Chờ ứng dụng cũ thoát hoàn toàn (tối đa 3 giây, nếu quá thì buộc đóng tiến trình)
        COUNT=0
        while kill -0 "$TARGET_PID" 2>/dev/null; do
            sleep 0.2
            COUNT=$((COUNT + 1))
            if [ "$COUNT" -ge 10 ]; then
                kill -15 "$TARGET_PID" 2>/dev/null || true
            fi
            if [ "$COUNT" -ge 18 ]; then
                kill -9 "$TARGET_PID" 2>/dev/null || true
                break
            fi
        done
        sleep 0.4

        # 2. Gỡ bỏ thuộc tính hạn chế kiểm duyệt khỏi bản cập nhật mới
        /usr/bin/xattr -dr com.apple.quarantine "$NEW_APP" 2>/dev/null || true

        # 3. Thay thế tệp ứng dụng an toàn
        /bin/rm -rf "$CURRENT_APP"
        /usr/bin/ditto "$NEW_APP" "$CURRENT_APP"

        # 4. Gỡ bỏ mọi quarantine và làm sạch thuộc tính mở rộng trên app vừa cài đặt
        /usr/bin/xattr -cr "$CURRENT_APP" 2>/dev/null || true

        # 5. Cập nhật lại cơ sở dữ liệu LaunchServices của macOS
        /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$CURRENT_APP" 2>/dev/null || true

        # 6. Đồng bộ hóa dữ liệu xuống đĩa
        /bin/sync
        sleep 0.4

        # 7. Tự động Re-Open / Khởi động lại phiên bản mới
        /usr/bin/open -n "$CURRENT_APP" || /usr/bin/open "$CURRENT_APP"

        # 8. Dọn dẹp tệp tạm thời
        /bin/rm -rf "$TEMP_DIR" 2>/dev/null || true
        /bin/rm -f "$SCRIPT_PATH" 2>/dev/null || true
        exit 0
        """

        try scriptContent.write(toFile: scriptPath, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scriptPath)

        // Thực thi script ngầm độc lập với tiến trình hiện tại
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = [scriptPath]
        try process.run()

        // Thoát ứng dụng hiện tại để script thực hiện thay thế và Re-Open
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            NSApplication.shared.terminate(nil)
            // Đảm bảo đóng ứng dụng hoàn toàn nếu NSApp.terminate bị hoãn
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                exit(0)
            }
        }
    }
}

// MARK: - Auto Update Popover & Settings UI View

struct UpdateSheetView: View {
    @ObservedObject var updater = AppUpdater.shared
    @Environment(\.dismiss) private var dismiss
    var isPresented: Binding<Bool>? = nil

    private func closeSheet() {
        if updater.isDownloading {
            updater.cancelDownload()
        }
        updater.showUpdateSheet = false
        isPresented?.wrappedValue = false
        dismiss()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Header
            HStack(spacing: 10) {
                ZStack {
                    LinearGradient(
                        colors: [TransToolsTheme.accent, TransToolsTheme.accent],
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
                    closeSheet()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Đóng (Esc)")
                .keyboardShortcut(.cancelAction)
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
                    VStack(alignment: .leading, spacing: 8) {
                        ProgressView(value: updater.downloadProgress)
                            .progressViewStyle(.linear)

                        HStack {
                            Text(updater.installStatusMessage)
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                            Spacer()
                            Button("Hủy") {
                                closeSheet()
                            }
                            .buttonStyle(.plain)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.red)
                        }
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
                            .background(TransToolsTheme.accent)
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

                        Button {
                            closeSheet()
                        } label: {
                            Text("Để sau")
                                .font(.system(size: 11, weight: .medium))
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(Color.secondary.opacity(0.12))
                                .foregroundStyle(.secondary)
                                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }
                }
            } else {
                VStack(spacing: 12) {
                    HStack(spacing: 8) {
                        Image(systemName: updater.hasError ? "exclamationmark.triangle.fill" : (updater.didCheckSuccessfully ? "checkmark.seal.fill" : "arrow.clockwise"))
                            .font(.system(size: 24))
                            .foregroundStyle(updater.hasError ? Color.red : Color.secondary)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(updater.hasError ? "Chưa kiểm tra được bản cập nhật" : (updater.didCheckSuccessfully ? "Bạn đang dùng phiên bản mới nhất" : "Đang kiểm tra bản cập nhật"))
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

                        Button {
                            closeSheet()
                        } label: {
                            Text("Đóng")
                                .font(.system(size: 11, weight: .medium))
                                .padding(.horizontal, 14)
                                .padding(.vertical, 6)
                                .background(TransToolsTheme.accent.opacity(0.15))
                                .foregroundStyle(TransToolsTheme.accent)
                                .clipShape(RoundedRectangle(cornerRadius: 6))
                        }
                        .buttonStyle(.plain)
                        .keyboardShortcut(.defaultAction)

                        if let htmlURL = URL(string: AppUpdater.releasesURLString) {
                            Button {
                                NSWorkspace.shared.open(htmlURL)
                            } label: {
                                HStack(spacing: 4) {
                                    Text("Lịch sử")
                                    Image(systemName: "arrow.up.right.square")
                                }
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
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
        .frame(width: 400)
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
        }
    }
}

// MARK: - Settings Tab View for Auto Updates

struct SettingsUpdateTabView: View {
    @ObservedObject var updater = AppUpdater.shared
    @AppStorage("AutoCheckUpdates") private var autoCheckUpdates = true

    private var lastChecked: String {
        guard let date = updater.lastCheckedDate else { return "Kiểm tra lần cuối: Chưa kiểm tra" }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "vi_VN")
        formatter.dateFormat = "HH:mm d 'tháng' M, yyyy"
        return "Kiểm tra lần cuối: \(formatter.string(from: date))"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Cập nhật phần mềm")
                .font(.system(size: 12, weight: .semibold)).foregroundStyle(.secondary)
                .padding(.leading, 12)
            VStack(alignment: .leading, spacing: 10) {
                Text(lastChecked).font(.system(size: 12)).foregroundStyle(.secondary)
                Toggle("Tự động kiểm tra bản cập nhật", isOn: $autoCheckUpdates)
                    .help("Kiểm tra bản phát hành TransTools khi mở app.")
                Toggle("Tự động tải bản cập nhật và cài đặt khi thoát TransTools", isOn: .constant(false))
                    .disabled(true)
                    .help("Chưa bật chức năng tự động cài đặt khi thoát.")
                HStack(spacing: 8) {
                    Button(updater.isChecking ? "Đang kiểm tra…" : "Kiểm tra bản cập nhật…") {
                        updater.checkForUpdates(userInitiated: true)
                    }.disabled(updater.isChecking || updater.isDownloading)
                    Button("Lịch sử phiên bản") {
                        if let url = URL(string: AppUpdater.releasesURLString) { NSWorkspace.shared.open(url) }
                    }
                }.buttonStyle(.bordered).controlSize(.small)
                if updater.isDownloading {
                    ProgressView(value: updater.downloadProgress)
                }
                if updater.hasError {
                    Text(updater.errorMessage).foregroundStyle(.red)
                } else if !updater.installStatusMessage.isEmpty {
                    Text(updater.installStatusMessage).foregroundStyle(.secondary)
                }
                if updater.updateAvailable && !updater.isDownloading {
                    Button("Cập nhật ngay lên v\(updater.latestVersion)") { updater.downloadAndInstallUpdate() }
                        .buttonStyle(.bordered).controlSize(.small)
                }
            }
            .font(.system(size: 12))
            .toggleStyle(.switch).controlSize(.mini)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(Color(nsColor: .controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.secondary.opacity(0.12), lineWidth: 1))
            Text("TransTools \(updater.currentVersionDisplay)")
                .font(.system(size: 11)).foregroundStyle(.tertiary).padding(.leading, 12)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
