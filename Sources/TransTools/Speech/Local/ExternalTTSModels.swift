import Foundation
import SwiftUI
import CryptoKit
import Darwin

public enum ExternalTTSModel: String, CaseIterable, Identifiable, Sendable {
    case vieneu, qwen
    public var id: String { rawValue }
    var title: String { self == .vieneu ? "VieNeu-TTS v3 Turbo" : "Qwen3-TTS 0.6B" }
    var detail: String { self == .vieneu ? "Tiếng Việt · ONNX FP32 · giọng tự nhiên" : "Tiếng Trung và 9 ngôn ngữ · MLX 8-bit · CustomVoice" }
    var languages: [String] { self == .vieneu ? ["vi"] : ["zh", "en", "ja", "ko", "de", "fr", "ru", "pt", "es", "it"] }
    var recommendedLanguage: String { self == .vieneu ? "vi" : "zh" }
    var defaultVoice: String { self == .vieneu ? "Hải Đăng" : "Vivian" }
    var availableOnDevice: Bool {
        #if arch(arm64)
        return true
        #else
        return self == .vieneu
        #endif
    }
    static var root: URL { FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("TransTools/ExternalTTS") }
    var directory: URL { Self.root.appendingPathComponent("Models/" + rawValue) }
    var python: URL { Self.root.appendingPathComponent("Environments/" + rawValue + "/bin/python3") }
    var isInstalled: Bool {
        if self == .vieneu { return NativeVieNeuManifest.installed(at: directory) }
        return FileManager.default.isExecutableFile(atPath: python.path) && FileManager.default.fileExists(atPath: directory.appendingPathComponent("installed.json").path)
    }
    struct Voice: Codable, Identifiable {
        let id: String
        let title: String
        var displayTitle: String {
            ["vivian": "Vivian", "serena": "Serena", "uncle_fu": "Uncle Fu", "ryan": "Ryan", "aiden": "Aiden", "ono_anna": "Ono Anna", "sohee": "Sohee", "eric": "Eric · Tứ Xuyên", "dylan": "Dylan · Bắc Kinh"][id.lowercased()] ?? title
        }
    }
    var voices: [Voice] {
        if self == .vieneu {
            guard let data = try? Data(contentsOf: NativeVieNeu.resources.appendingPathComponent("voices_v3_turbo.json")),
                  let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any], let presets = object["presets"] as? [String: [String: Any]] else { return [] }
            return presets.keys.sorted().map { Voice(id: $0, title: $0 + " — " + (presets[$0]?["description"] as? String ?? "")) }
        }
        guard let data = try? Data(contentsOf: directory.appendingPathComponent("installed.json")),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let list = object["voices"], let encoded = try? JSONSerialization.data(withJSONObject: list) else { return [] }
        return (try? JSONDecoder().decode([Voice].self, from: encoded)) ?? []
    }
    func voices(for language: String) -> [Voice] {
        guard self == .qwen else { return voices }
        let native: [String: Set<String>] = ["zh": ["vivian", "serena", "uncle_fu"], "en": ["ryan", "aiden"], "ja": ["ono_anna"], "ko": ["sohee"]]
        guard let ids = native[LanguageVoicePreferences.code(language)] else { return voices }
        return voices.filter { ids.contains($0.id.lowercased()) }
    }
    func selectedVoice(for language: String) -> String {
        let code = LanguageVoicePreferences.code(language)
        let available = voices(for: language)
        let saved = UserDefaults.standard.string(forKey: "TTS_" + rawValue + "_Voice_" + code)
        if let saved, let voice = available.first(where: { $0.id.lowercased() == saved.lowercased() || $0.title == saved }) { return voice.id }
        let preferred = self == .qwen ? (["en": "ryan", "ja": "ono_anna", "ko": "sohee"][code] ?? "vivian") : defaultVoice
        return available.first(where: { $0.id.lowercased() == preferred.lowercased() })?.id ?? available.first?.id ?? preferred
    }

}

/// Owns only an install operation, never a synthesis process. Cancellation stops the process group.
final class TTSInstallOperation: @unchecked Sendable {
    private let lock = NSLock()
    private var process: Process?
    private var cancelled = false
    func cancel() { lock.lock(); cancelled = true; let p = process; lock.unlock(); if let p, p.isRunning { if kill(-p.processIdentifier, SIGTERM) != 0 { p.terminate() } } }
    func run(_ executable: URL, arguments: [String], log: URL) async throws {
        try await withTaskCancellationHandler(operation: {
            try await Task.detached(priority: .utility) { try self.runBlocking(executable, arguments: arguments, log: log) }.value
        }, onCancel: { self.cancel() })
    }
    private func runBlocking(_ executable: URL, arguments: [String], log: URL) throws {
                let p = Process(); p.executableURL = executable; p.arguments = arguments
                let pipe = Pipe(); p.standardOutput = pipe; p.standardError = pipe
                // Drain continuously to avoid a full stderr pipe blocking downloads.
                FileManager.default.createFile(atPath: log.path, contents: nil)
                let handle = try FileHandle(forWritingTo: log)
                pipe.fileHandleForReading.readabilityHandler = { input in
                    let data = input.availableData
                    if !data.isEmpty { try? handle.write(contentsOf: data) }
                }
                defer { pipe.fileHandleForReading.readabilityHandler = nil; try? handle.close() }
                self.lock.lock()
                guard !self.cancelled else { self.lock.unlock(); throw CancellationError() }
                self.process = p
                do { try p.run() } catch { self.process = nil; self.lock.unlock(); throw error }
                self.lock.unlock()
                p.waitUntilExit()
                self.lock.lock(); self.process = nil; let cancelled = self.cancelled; self.lock.unlock()
                if cancelled { throw CancellationError() }
                guard p.terminationStatus == 0 else {
                    throw NSError(domain: "TTSInstall", code: Int(p.terminationStatus), userInfo: [NSLocalizedDescriptionKey: "Cài đặt chưa hoàn tất. Xem nhật ký tải để kiểm tra kết nối hoặc dung lượng."])
                }
    }
}

@MainActor
final class ExternalTTSModelManager: ObservableObject {
    static let shared = ExternalTTSModelManager()
    @Published private(set) var installing: ExternalTTSModel?
    @Published private(set) var status = ""
    @Published private(set) var revision = 0
    private var task: Task<Void, Never>?
    private var operation: TTSInstallOperation?
    private init() {}
    nonisolated static var resources: URL? { Bundle.main.resourceURL?.appendingPathComponent("SpeechRuntime") }
    func install(_ model: ExternalTTSModel) {
        guard installing == nil, !TTSEngineRouter.shared.isProcessing, !TTSService.shared.isSpeaking, model.availableOnDevice else { return }
        installing = model; status = model == .vieneu ? "Đang chuẩn bị VieNeu native…" : "Đang chuẩn bị môi trường riêng…"
        let operation = TTSInstallOperation(); self.operation = operation
        task = Task {
            do {
                await LocalTTSSession.shared.releaseAndWait()
                await ExternalTTSSession.shared.releaseAndWait()
                let root = ExternalTTSModel.root
                try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
                let logs = root.appendingPathComponent("Logs")
                try FileManager.default.createDirectory(at: logs, withIntermediateDirectories: true)
                let log = logs.appendingPathComponent("install-" + model.rawValue + ".log")
                if model == .vieneu {
                    try await NativeVieNeuInstaller.shared.install { text in
                        Task { @MainActor in self.status = text }
                    }
                } else {
                let python = try await ensurePython(operation, log: log)
                try Task.checkCancellation()
                guard let resources = Self.resources else { throw URLError(.fileDoesNotExist) }
                status = "Đang cài SDK, tải mô hình và kiểm thử âm thanh…"
                try await operation.run(python, arguments: [resources.appendingPathComponent("install.py").path,
                    "--root", root.path, "--engine", model.rawValue, "--resources", resources.path], log: log)
                }
                try Task.checkCancellation()
                guard model.isInstalled else { throw URLError(.cannotDecodeContentData) }
                status = "Đã cài và kiểm thử " + model.title
                revision += 1
            } catch is CancellationError { status = "Đã hủy. Dữ liệu tải dở có thể tiếp tục tải hoặc dọn trong Lưu trữ." }
            catch { status = error.localizedDescription }
            installing = nil; self.operation = nil; task = nil
        }
    }
    func cancel() { task?.cancel(); operation?.cancel() }
    func refresh() { revision += 1 }
    private func ensurePython(_ operation: TTSInstallOperation, log: URL) async throws -> URL {
        let base = ExternalTTSModel.root.appendingPathComponent("Python")
        let python = base.appendingPathComponent("python/bin/python3")
        if FileManager.default.isExecutableFile(atPath: python.path) { return python }
        #if arch(arm64)
        let architecture = "aarch64"
        let expected = "ad8d0c637c0a36b967b310e2c07254f4d2ca8cabaa7699e55ed6290aceb481a2"
        #else
        let architecture = "x86_64"
        let expected = "562c30864ece2cb1d3e0ad66a1acd498611a47e5a10ce81b99158bef1ccbd355"
        #endif
        let url = URL(string: "https://github.com/astral-sh/python-build-standalone/releases/download/20261003/cpython-3.12.15%2B20261003-" + architecture + "-apple-darwin-install_only_stripped.tar.gz")!
        let (download, response) = try await URLSession.shared.download(from: url)
        defer { try? FileManager.default.removeItem(at: download) }
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
        let checksum = try await Task.detached(priority: .utility) { () throws -> String in
            let file = try FileHandle(forReadingFrom: download); defer { try? file.close() }
            var hash = SHA256()
            while let block = try file.read(upToCount: 1024 * 1024), !block.isEmpty { hash.update(data: block) }
            return hash.finalize().map { String(format: "%02x", $0) }.joined()
        }.value
        guard checksum == expected else { throw URLError(.cannotDecodeContentData) }
        try Task.checkCancellation()
        let staging = ExternalTTSModel.root.appendingPathComponent("Runtime-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: staging) }
        try await operation.run(URL(fileURLWithPath: "/usr/bin/tar"), arguments: ["-xzf", download.path, "-C", staging.path], log: log)
        try Task.checkCancellation()
        guard FileManager.default.isExecutableFile(atPath: staging.appendingPathComponent("python/bin/python3").path) else { throw URLError(.fileDoesNotExist) }
        if FileManager.default.fileExists(atPath: base.path) { try FileManager.default.removeItem(at: base) }
        try FileManager.default.moveItem(at: staging, to: base)
        return python
    }
}
