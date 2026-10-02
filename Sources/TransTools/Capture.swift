import Foundation
import ScreenCaptureKit
import AVFoundation

final class AudioCapture: NSObject, SCStreamOutput, SCStreamDelegate {
    private var stream: SCStream?
    private var engine: AVAudioEngine?
    var onAudio: ((CMSampleBuffer) -> Void)?
    var onMicrophone: ((AVAudioPCMBuffer) -> Void)?
    var onError: ((Error) -> Void)?
    private let queue = DispatchQueue(label: "TransTools.audio")

    func applications() async throws -> [SCRunningApplication] {
        let content = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: false)
        let myPID = ProcessInfo.processInfo.processIdentifier

        var seenBundleIDs = Set<String>()
        var seenNames = Set<String>()
        var uniqueApps: [SCRunningApplication] = []

        for app in content.applications {
            guard app.processID != myPID else { continue }
            let name = app.applicationName.trimmingCharacters(in: .whitespacesAndNewlines)
            let bundleID = app.bundleIdentifier.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty, !bundleID.isEmpty else { continue }

            // Skip internal system helper extensions that aren't user apps
            if bundleID.contains("WebKit.WebContent") || bundleID.contains("loginwindow") || bundleID.contains("WindowManager") || bundleID.hasPrefix("com.apple.coreservices") {
                continue
            }

            let normalizedName = name.lowercased()
            if !seenBundleIDs.contains(bundleID) && !seenNames.contains(normalizedName) {
                seenBundleIDs.insert(bundleID)
                seenNames.insert(normalizedName)
                uniqueApps.append(app)
            }
        }

        // Priority meeting & communication apps first
        let priorityKeywords = ["teams", "zoom", "meet", "webex", "chrome", "safari", "slack", "discord", "skype"]
        return uniqueApps.sorted { a, b in
            let aName = a.applicationName.lowercased()
            let bName = b.applicationName.lowercased()
            let aPriority = priorityKeywords.firstIndex(where: { aName.contains($0) }) ?? 999
            let bPriority = priorityKeywords.firstIndex(where: { bName.contains($0) }) ?? 999
            if aPriority != bPriority {
                return aPriority < bPriority
            }
            return a.applicationName.localizedCaseInsensitiveCompare(b.applicationName) == .orderedAscending
        }
    }

    private func isTargetApp(_ app: SCRunningApplication, targetID: String, targetApp: SCRunningApplication?) -> Bool {
        let appBundleID = app.bundleIdentifier.trimmingCharacters(in: .whitespacesAndNewlines)
        if appBundleID.isEmpty { return false }

        // 1. Exact bundle ID or PID match
        if appBundleID == targetID { return true }
        if let targetPID = targetApp?.processID, app.processID == targetPID { return true }

        // 2. PWA match (Chrome / Edge / Chromium Web Apps)
        // E.g. targetID = "com.microsoft.edgemac.app.cinhimbnkkaeohfgghhklpknlkffjgod"
        // Host browser = "com.microsoft.edgemac"
        if targetID.contains(".app.") {
            let hostPrefix = targetID.components(separatedBy: ".app.").first ?? ""
            if !hostPrefix.isEmpty {
                if appBundleID == hostPrefix || appBundleID.hasPrefix(hostPrefix + ".") || appBundleID.hasPrefix(hostPrefix) {
                    return true
                }
            }
        }

        // Reverse PWA relationship: target is host browser, app is its PWA or helper
        if appBundleID.contains(".app.") && appBundleID.hasPrefix(targetID) {
            return true
        }

        // 3. Helper processes or suite processes with same bundle prefix
        // E.g. com.google.Chrome & com.google.Chrome.helper, com.microsoft.teams2 & com.microsoft.teams2.helper
        if appBundleID.hasPrefix(targetID + ".") || targetID.hasPrefix(appBundleID + ".") {
            return true
        }

        let targetComponents = targetID.components(separatedBy: ".")
        if targetComponents.count >= 3 {
            let basePrefix = targetComponents.prefix(3).joined(separator: ".")
            if appBundleID.hasPrefix(basePrefix) {
                return true
            }
        }

        // 4. Safari / WebKit WebContent
        if targetID.localizedCaseInsensitiveContains("safari") {
            if appBundleID.localizedCaseInsensitiveContains("webkit") || appBundleID.localizedCaseInsensitiveContains("safari") {
                return true
            }
        }

        // 5. Match by application name
        if let targetName = targetApp?.applicationName.trimmingCharacters(in: .whitespacesAndNewlines), !targetName.isEmpty {
            let appName = app.applicationName.trimmingCharacters(in: .whitespacesAndNewlines)
            if !appName.isEmpty {
                if appName.localizedCaseInsensitiveCompare(targetName) == .orderedSame {
                    return true
                }
                if appName.localizedCaseInsensitiveContains(targetName) || targetName.localizedCaseInsensitiveContains(appName) {
                    return true
                }
            }
        }

        return false
    }

    func start(applicationID: String) async throws {
        let content = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: false)
        guard let display = content.displays.first else {
            throw NSError(domain: "Capture", code: 2, userInfo: [NSLocalizedDescriptionKey: "Không tìm thấy màn hình. Kiểm tra quyền Screen & System Audio Recording."])
        }

        let targetApp = content.applications.first(where: { $0.bundleIdentifier == applicationID })
            ?? content.applications.first(where: { isTargetApp($0, targetID: applicationID, targetApp: nil) })

        guard let foundTarget = targetApp else {
            throw NSError(domain: "Capture", code: 1, userInfo: [NSLocalizedDescriptionKey: "Không tìm thấy ứng dụng đã chọn. Hãy mở lại ứng dụng và tải lại danh sách."])
        }

        // In macOS, multi-process apps (Edge, Chrome, Teams, PWAs) render audio in helper or host processes.
        // Capturing via display filter with excludingApplications ensures all audio engines of the target app
        // (including audio renderers and helper processes) are captured, while TransTools and all other unrelated apps are muted.
        let myPID = ProcessInfo.processInfo.processIdentifier
        let excludedApps = content.applications.filter { app in
            if app.processID == myPID { return true }
            return !isTargetApp(app, targetID: applicationID, targetApp: foundTarget)
        }

        let filter = SCContentFilter(display: display, excludingApplications: excludedApps, exceptingWindows: [])
        let config = SCStreamConfiguration()
        config.capturesAudio = true
        config.excludesCurrentProcessAudio = true
        config.sampleRate = 16000
        config.channelCount = 1
        config.width = 16
        config.height = 16
        config.minimumFrameInterval = CMTime(value: 1, timescale: 1)
        let newStream = SCStream(filter: filter, configuration: config, delegate: self)
        try newStream.addStreamOutput(self, type: .audio, sampleHandlerQueue: queue)
        stream = newStream
        do { try await newStream.startCapture() }
        catch { stream = nil; throw error }
    }

    func startSystemAudio() async throws {
        let content = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: false)
        guard let display = content.displays.first else {
            throw NSError(domain: "Capture", code: 2, userInfo: [NSLocalizedDescriptionKey: "Không tìm thấy màn hình. Kiểm tra quyền Screen & System Audio Recording."])
        }
        // Capture entire display audio (all apps) but exclude our own process
        let ownApp = content.applications.first(where: { $0.processID == ProcessInfo.processInfo.processIdentifier })
        let excludedApps = ownApp.map { [$0] } ?? []
        let filter = SCContentFilter(display: display, excludingApplications: excludedApps, exceptingWindows: [])
        let config = SCStreamConfiguration()
        config.capturesAudio = true
        config.excludesCurrentProcessAudio = true
        config.sampleRate = 16000
        config.channelCount = 1
        config.width = 16
        config.height = 16
        config.minimumFrameInterval = CMTime(value: 1, timescale: 1)
        let newStream = SCStream(filter: filter, configuration: config, delegate: self)
        try newStream.addStreamOutput(self, type: .audio, sampleHandlerQueue: queue)
        stream = newStream
        do { try await newStream.startCapture() }
        catch { stream = nil; throw error }
    }

    func startMicrophone() throws {
        let newEngine = AVAudioEngine()
        let input = newEngine.inputNode
        input.installTap(onBus: 0, bufferSize: 1024, format: input.outputFormat(forBus: 0)) { [weak self] buffer, _ in
            self?.onMicrophone?(buffer)
        }
        do { try newEngine.start(); engine = newEngine }
        catch { input.removeTap(onBus: 0); throw error }
    }

    func stop() async {
        engine?.stop()
        engine?.inputNode.removeTap(onBus: 0)
        engine = nil
        let old = stream
        stream = nil
        try? await old?.stopCapture()
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        if type == .audio, sampleBuffer.isValid { onAudio?(sampleBuffer) }
    }
    func stream(_ stream: SCStream, didStopWithError error: Error) { onError?(error) }
}
