import Foundation
import Combine
import AppKit
import AVFoundation

@MainActor
protocol ModelAdapter: AnyObject {
    var modelID: String { get }
    var directory: URL { get }
    var installed: Bool { get }
    var operationState: AIModelInstallationState? { get }
    func install()
    func cancelAndWait() async
    func release() async
    func setDefault(language: String)
    func synthesize(_ text: String, language: String) async throws -> TTSAudioResult
}
@MainActor
final class SupertonicModelAdapter: ModelAdapter {
    let modelID = "supertonic-3"
    var directory: URL { LocalTTSModelStore.base }
    var installed: Bool { LocalTTSModelStore.installed() }
    var operationState: AIModelInstallationState? {
        switch LocalTTSModelManager.shared.state {
        case let .downloading(progress, _, _): return .downloading(progress)
        case .verifying: return .verifying
        case let .failed(error): return .failed(error)
        default: return nil
        }
    }
    func install() { LocalTTSModelManager.shared.downloadAndInstall() }
    func cancelAndWait() async { await LocalTTSModelManager.shared.cancelAndWait() }
    func release() async { await LocalTTSSession.shared.releaseAndWait() }
    func setDefault(language: String) { LanguageVoicePreferences.set(.local, for: language) }
    func synthesize(_ text: String, language: String) async throws -> TTSAudioResult {
        await ExternalTTSSession.shared.releaseAndWait()
        return try await LocalNaturalTTSEngine.shared.synthesize(text: text, language: language, options: .default)
    }
}
@MainActor
final class VieNeuModelAdapter: ModelAdapter {
    let modelID = "vieneu-v3-turbo"
    var directory: URL { ExternalTTSModel.vieneu.directory }
    var installed: Bool { ExternalTTSModel.vieneu.isInstalled }
    var operationState: AIModelInstallationState? { ExternalTTSModelManager.shared.installing == .vieneu ? .installing : ExternalTTSModelManager.shared.lastError.map { .failed($0) } }
    func install() { ExternalTTSModelManager.shared.install(.vieneu) }
    func cancelAndWait() async { await ExternalTTSModelManager.shared.cancelAndWait() }
    func release() async { await ExternalTTSSession.shared.releaseAndWait() }
    func setDefault(language: String) { LanguageVoicePreferences.set(.vieneu, for: language) }
    func synthesize(_ text: String, language: String) async throws -> TTSAudioResult {
        await LocalTTSSession.shared.releaseAndWait()
        return try await NativeVieNeu.shared.synthesize(text: text, voice: ExternalTTSModel.vieneu.selectedVoice(for: language), options: .default, onChunk: nil)
    }
}
struct ModelInventoryItem: Identifiable, Sendable {
    let descriptor: AIModelDescriptor
    let state: AIModelInstallationState
    let installedBytes: Int64
    let compatibility: ModelCompatibility
    var id: String { descriptor.id }
}
struct ModelRoutingRequirements: Sendable {
    var offline = true
    var voiceCloning = false
}
@MainActor
final class ModelManager: NSObject, ObservableObject, AVAudioPlayerDelegate {
    static let shared = ModelManager()
    @Published private(set) var items: [ModelInventoryItem] = []
    @Published private(set) var message = ""
    @Published private(set) var working = false
    @Published private(set) var updatingCatalog = false
    @Published private(set) var testingModel: String?
    @Published private(set) var previewPlaying = false
    let hardware = HardwareCapabilities.detect()
    private(set) var registry: ModelRegistry?
    private let adapters: [String: any ModelAdapter]
    private var subscriptions = Set<AnyCancellable>()
    private var refreshing = false
    private var needsRefresh = false
    private var player: AVAudioPlayer?
    private var synthesisTask: Task<TTSAudioResult, Error>?
    private var packTask: Task<Void, Never>?
    private var queued = Set<String>()
    private var paused = Set(UserDefaults.standard.stringArray(forKey: "ModelManager_PausedModels") ?? [])
    private override init() {
        let values: [any ModelAdapter] = [SupertonicModelAdapter(), VieNeuModelAdapter()]
        adapters = Dictionary(uniqueKeysWithValues: values.map { ($0.modelID, $0) })
        super.init()
        do { registry = try ModelRegistry.current() } catch { message = error.localizedDescription }
        Task { if let base = registry { registry = await RemoteModelCatalogStore.shared.cached(for: base); await refresh() } }
        LocalTTSModelManager.shared.$state.dropFirst().sink { [weak self] state in
            let scan: Bool
            if case .downloading = state { scan = false } else { scan = true }
            Task { @MainActor in await self?.refresh(scanStorage: scan) }
        }.store(in: &subscriptions)
        ExternalTTSModelManager.shared.$revision.dropFirst().sink { [weak self] _ in Task { @MainActor in await self?.refresh() } }.store(in: &subscriptions)
        ExternalTTSModelManager.shared.$installing.dropFirst().sink { [weak self] _ in Task { @MainActor in await self?.refresh() } }.store(in: &subscriptions)
    }
    var inUse: Bool {
        working || packTask != nil || testingModel != nil || previewPlaying || TTSService.shared.isSpeaking || TTSEngineRouter.shared.isProcessing || MenuBarManager.shared.meetingRunning || ConversationController.shared.active || PersonalVoiceManager.shared.processing || PersonalVoiceManager.shared.recording
    }
    var installing: Bool {
        adapters.values.contains { adapter in
            guard let state = adapter.operationState else { return false }
            if case .failed = state { return false }
            return true
        }
    }
    func refresh(scanStorage: Bool = true) async {
        guard !refreshing else { needsRefresh = true; return }
        refreshing = true
        repeat {
            needsRefresh = false
            let records = registry?.models ?? []
            let entries = records.compactMap { descriptor -> StorageEntry? in
                guard let adapter = adapters[descriptor.id] else { return nil }
                return StorageEntry(id: descriptor.id, title: descriptor.name, detail: "", url: adapter.directory, removable: true, model: true)
            }
            // Progress updates retain measured sizes instead of repeatedly enumerating model files.
            let sizes = scanStorage ? await Task.detached(priority: .utility) { StorageInventory.scan(entries) }.value : []
            // Files, not a saved UI flag, determine whether a model is installed.
            items = records.compactMap { model in
                guard let adapter = adapters[model.id] else { return nil }
                let compatibility = hardware.compatibility(model)
                let state: AIModelInstallationState
                if case let .incompatible(reason) = compatibility { state = .incompatible(reason) }
                else { state = adapter.operationState ?? (queued.contains(model.id) ? .queued : paused.contains(model.id) ? .paused : adapter.installed ? .installed : .notInstalled) }
                return ModelInventoryItem(descriptor: model, state: state, installedBytes: sizes.first { $0.id == model.id }?.bytes ?? items.first { $0.id == model.id }?.installedBytes ?? 0, compatibility: compatibility)
            }
        } while needsRefresh
        refreshing = false
    }
    func updateCatalog() async {
        guard !updatingCatalog, !inUse, !installing else { return }
        updatingCatalog = true; defer { updatingCatalog = false }
        do {
            let builtIn = try ModelRegistry.current()
            let (updated, revision) = try await RemoteModelCatalogStore.shared.update(builtIn)
            registry = updated
            message = "Đã cập nhật danh mục GitHub · phiên bản \(revision)."
            await refresh()
        } catch { message = "Chưa cập nhật được danh mục. Giữ bản hiện có. " + error.localizedDescription }
    }
    func install(_ id: String) {
        guard !inUse, !installing, let model = registry?.model(id), let adapter = adapters[id] else { message = ModelManagerError.inUse.localizedDescription; return }
        if case let .incompatible(reason) = hardware.compatibility(model) { message = reason; return }
        paused.remove(id); persistPaused()
        adapter.install(); Task { await refresh() }
    }
    func installPack(_ packID: String) {
        guard !inUse, !installing, let registry else { return }
        do {
            let order = try registry.installationOrder(for: packID).filter { adapters[$0]?.installed == false }
            for id in order {
                guard let model = registry.model(id), adapters[id] != nil else { throw ModelManagerError.unsupportedModel }
                if case .incompatible = hardware.compatibility(model) { throw ModelManagerError.unsupportedModel }
            }
            queued = Set(order)
            packTask = Task {
                defer { queued.removeAll(); packTask = nil; Task { await refresh() } }
                do {
                    for id in order {
                        try Task.checkCancellation()
                        guard let adapter = adapters[id] else { throw ModelManagerError.unsupportedModel }
                        queued.remove(id); paused.remove(id); persistPaused()
                        adapter.install(); await refresh()
                        while let state = adapter.operationState {
                            if case let .failed(reason) = state { throw NSError(domain: "ModelPack", code: 1, userInfo: [NSLocalizedDescriptionKey: reason]) }
                            try await Task.sleep(nanoseconds: 200_000_000)
                        }
                        guard adapter.installed else { throw ModelManagerError.missingFiles }
                    }
                    message = "Đã cài gói giọng đọc. Chọn mô hình mặc định theo ngôn ngữ khi cần."
                } catch { message = error is CancellationError ? "Đã dừng cài gói. Các mô hình đã cài được giữ lại." : error.localizedDescription }
            }
        } catch { message = error.localizedDescription }
    }
    func cancelPack() {
        packTask?.cancel()
        Task {
            for adapter in adapters.values { await adapter.cancelAndWait() }
            await refresh()
        }
    }
    var installingPack: Bool { packTask != nil }
    private func persistPaused() { UserDefaults.standard.set(Array(paused), forKey: "ModelManager_PausedModels") }
    func pause(_ id: String) { stopDownload(id, keepResume: true) }
    func cancel(_ id: String) { stopDownload(id, keepResume: false) }
    private func stopDownload(_ id: String, keepResume: Bool) {
        guard !working, let adapter = adapters[id] else { return }
        working = true
        if keepResume { paused.insert(id) } else { paused.remove(id) }
        persistPaused()
        Task {
            await adapter.cancelAndWait()
            if !keepResume, let model = registry?.model(id) { await ModelDownloadManager.shared.discardResume(for: model.requiredFiles) }
            working = false
            await refresh()
        }
    }
    func remove(_ id: String) async {
        guard !inUse, !installing, let adapter = adapters[id] else { message = ModelManagerError.inUse.localizedDescription; return }
        working = true; defer { working = false }
        await adapter.release()
        do {
            if FileManager.default.fileExists(atPath: adapter.directory.path) { try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                    NSWorkspace.shared.recycle([adapter.directory]) { _, error in
                        if let error { continuation.resume(throwing: error) } else { continuation.resume() }
                    }
                } }
            if let model = registry?.model(id) {
                for language in model.languages where selectedID(language) == id { LanguageVoicePreferences.set(.system, for: language) }
            }
            paused.remove(id); persistPaused()
            LocalTTSModelManager.shared.checkInstallation()
            message = "Đã chuyển mô hình vào Thùng rác. Bản thu cá nhân được giữ nguyên."
        } catch { message = error.localizedDescription }
        await refresh()
    }
    private func selectedID(_ language: String) -> String? {
        switch LanguageVoicePreferences.selection(for: language) { case .local: return "supertonic-3"; case .vieneu: return "vieneu-v3-turbo"; default: return nil }
    }
    func bestModel(for feature: AIModelFeature, language: String, requirements: ModelRoutingRequirements = .init()) -> AIModelDescriptor? {
        guard feature == .textToSpeech else { return nil }
        let code = LanguageVoicePreferences.code(language)
        let candidates = (registry?.models ?? []).filter { model in
            if case .incompatible = hardware.compatibility(model) { return false }
            return adapters[model.id]?.installed == true && model.languages.contains(code)
                && (!requirements.offline || model.capabilities.offline)
                && (!requirements.voiceCloning || model.capabilities.voiceCloning)
        }
        return candidates.first { $0.id == selectedID(code) } ?? candidates.first { $0.recommended } ?? candidates.first
    }
    /// Shared by playback, preview and export. Explicit online/system preferences remain explicit.
    func routedEngine(for language: String, localDefault: Bool, edgeDefault: Bool) -> LanguageVoiceEngine {
        let requested = LanguageVoicePreferences.resolved(for: language, localDefault: localDefault, edgeDefault: edgeDefault)
        let code = LanguageVoicePreferences.code(language)
        var available = Set<LanguageVoiceEngine>()
        for (id, engine) in [("supertonic-3", LanguageVoiceEngine.local), ("vieneu-v3-turbo", .vieneu)] {
            guard let descriptor = registry?.model(id), descriptor.languages.contains(code), adapters[id]?.installed == true else { continue }
            if case .incompatible = hardware.compatibility(descriptor) { continue }
            available.insert(engine)
        }
        return LanguageVoicePreferences.route(requested: requested, available: available)
    }

    func setDefault(_ id: String, language: String) {
        guard let model = registry?.model(id), model.languages.contains(LanguageVoicePreferences.code(language)), adapters[id]?.installed == true else { message = ModelManagerError.missingFiles.localizedDescription; return }
        adapters[id]?.setDefault(language: language); message = "Đã lưu giọng mặc định cho \(language)."
    }
    func test(_ id: String, text: String, language: String) async {
        guard !inUse, !installing, let model = registry?.model(id), model.languages.contains(LanguageVoicePreferences.code(language)), let adapter = adapters[id], adapter.installed else { message = ModelManagerError.inUse.localizedDescription; return }
        testingModel = id; defer { testingModel = nil; synthesisTask = nil }
        let start = ProcessInfo.processInfo.systemUptime
        do {
            player?.stop()
            let task = Task { try await adapter.synthesize(text, language: language) }
            synthesisTask = task
            let result = try await task.value
            if task.isCancelled { throw CancellationError() }
            guard result.duration > 0, !result.audioData.isEmpty else { throw ModelManagerError.invalidAudio }
            let elapsed = ProcessInfo.processInfo.systemUptime - start
            player = try AVAudioPlayer(data: result.audioData)
            player?.delegate = self
            guard player?.play() == true else { throw ModelManagerError.invalidAudio }
            previewPlaying = true
            message = String(format: "%@: tạo %.2f giây · audio %.2f giây · RTF %.2f", model.name, elapsed, result.duration, elapsed / result.duration)
        } catch { message = error is CancellationError ? "Đã dừng thử giọng." : error.localizedDescription }
    }
    func stopTesting() {
        synthesisTask?.cancel()
        player?.stop(); player = nil; previewPlaying = false
    }
    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor [weak self] in
            guard let self, self.player === player else { return }
            self.previewPlaying = false
            if !flag { self.message = "Phát audio chưa hoàn tất." }
        }
    }
    nonisolated func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {
        Task { @MainActor [weak self] in
            guard let self, self.player === player else { return }
            self.previewPlaying = false
            self.message = error?.localizedDescription ?? "Không đọc được audio."
        }
    }
}
