import SwiftUI
import Speech
import AVFoundation
import ScreenCaptureKit
import AppKit
import CoreGraphics
import UniformTypeIdentifiers
import Combine
#if canImport(Translation)
import Translation
#endif

struct Caption: Identifiable {
    let id: UUID
    let start: TimeInterval
    var end: TimeInterval
    var original: String
    var vietnamese = ""
}

var appVersionDisplay: String {
    if let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String, !version.isEmpty {
        return "v\(version)"
    }
    return "v1.3.1"
}

// MARK: - Meeting Session Notebook Records & Persistence

struct MeetingSession: Identifiable, Codable, Equatable {
    let id: UUID
    var title: String
    let createdAt: Date
    let durationSeconds: TimeInterval
    let audioSource: String
    var notes: String
    var captions: [CaptionRecord]

    init(
        id: UUID = UUID(),
        title: String,
        createdAt: Date = Date(),
        durationSeconds: TimeInterval,
        audioSource: String,
        notes: String = "",
        captions: [CaptionRecord]
    ) {
        self.id = id
        self.title = title
        self.createdAt = createdAt
        self.durationSeconds = durationSeconds
        self.audioSource = audioSource
        self.notes = notes
        self.captions = captions
    }
}

struct CaptionRecord: Identifiable, Codable, Equatable {
    let id: UUID
    let start: TimeInterval
    let end: TimeInterval
    let original: String
    let vietnamese: String
}

// MARK: - Chip Chip Mascot Idle Activities

public enum MascotIdleActivity: String, CaseIterable, Identifiable {
    case writing = "writing"
    case thinking = "thinking"
    case auto = "auto"                     // Tự chọn hoạt cảnh theo ngữ cảnh khi rảnh
    case fishing = "fishing"               // Ngồi câu cá thảnh thơi 🎣
    case sleeping = "sleeping"             // Nằm ngủ khò khò
    case strolling = "strolling"           // Đi dạo ngó nghiêng
    case catchingButterfly = "butterfly"   // Bắt bướm dập dờn
    case pickingFlowers = "flowers"        // Hái hoa ngát hương
    case listeningMusic = "music"          // Chill nhạc bồng bềnh
    case sippingTea = "tea"                // Nhâm nhi tách trà ấm

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .writing: return "Ghi chép vào sổ 📓"
        case .thinking: return "Đang suy nghĩ 💭"
        case .auto: return "Tự động thông minh ✨"
        case .fishing: return "Ngồi câu cá thảnh thơi 🎣"
        case .sleeping: return "Nằm ngủ khò khò 💤"
        case .strolling: return "Đi dạo ngắm nhìn 🚶‍♂️"
        case .catchingButterfly: return "Bắt bướm dập dờn 🦋"
        case .pickingFlowers: return "Hái hoa ngát hương 🌸"
        case .listeningMusic: return "Chill nhạc bồng bềnh 🎵"
        case .sippingTea: return "Nhâm nhi cà phê ☕️"
        }
    }

    public var shortTitle: String {
        switch self {
        case .writing: return "Ghi chép"
        case .thinking: return "Suy nghĩ"
        case .auto: return "Tự động"
        case .fishing: return "Câu cá"
        case .sleeping: return "Nằm ngủ"
        case .strolling: return "Đi dạo"
        case .catchingButterfly: return "Bắt bướm"
        case .pickingFlowers: return "Hái hoa"
        case .listeningMusic: return "Nghe nhạc"
        case .sippingTea: return "Cà phê"
        }
    }

    public var icon: String {
        switch self {
        case .writing: return "book.closed"
        case .thinking: return "thought.bubble"
        case .auto: return "sparkles"
        case .fishing: return "water.waves"
        case .sleeping: return "moon.zzz.fill"
        case .strolling: return "figure.walk"
        case .catchingButterfly: return "heart.fill"
        case .pickingFlowers: return "camera.macro"
        case .listeningMusic: return "headphones"
        case .sippingTea: return "cup.and.saucer.fill"
        }
    }
}

// MARK: - App Permissions Management

enum AppPermissionType {
    case screenCapture
    case microphone
    case speechRecognition
    case dictation

    var title: String {
        switch self {
        case .screenCapture: return "Ghi màn hình & Âm thanh hệ thống"
        case .microphone: return "Microphone"
        case .speechRecognition: return "Nhận diện giọng nói (Speech Recognition)"
        case .dictation: return "Siri & Đọc chính tả (Dictation)"
        }
    }

    var message: String {
        switch self {
        case .screenCapture:
            return "TransTools cần quyền 'Ghi màn hình & Âm thanh hệ thống' để thu và dịch âm thanh từ các cuộc họp (Teams, Zoom, Meet, trình duyệt).\n\nBạn có muốn mở Cài đặt hệ thống (System Settings) để cấp quyền ngay không?"
        case .microphone:
            return "TransTools cần quyền 'Microphone' để thu âm giọng nói của bạn.\n\nBạn có muốn mở Cài đặt hệ thống để cấp quyền ngay không?"
        case .speechRecognition:
            return "TransTools cần quyền 'Nhận diện giọng nói' (Speech Recognition) để chuyển giọng nói cuộc họp thành văn bản phụ đề.\n\nBạn có muốn mở Cài đặt hệ thống để cấp quyền ngay không?"
        case .dictation:
            return "Ngôn ngữ này cần bật Siri & Đọc chính tả (Dictation) trong Cài đặt Bàn phím.\n\nBạn có muốn mở Cài đặt Bàn phím ngay không?"
        }
    }

    var settingsURLString: String {
        switch self {
        case .screenCapture:
            return "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture"
        case .microphone:
            return "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone"
        case .speechRecognition:
            return "x-apple.systempreferences:com.apple.preference.security?Privacy_SpeechRecognition"
        case .dictation:
            return "x-apple.systempreferences:com.apple.Keyboard-Settings.extension"
        }
    }
}

@MainActor final class MeetingModel: ObservableObject {
    static weak var shared: MeetingModel?

    @Published var applications: [SCRunningApplication] = []
    @Published var source = ""
    @Published var provider: AIProvider = .apple
    @Published var modelName: String = "Tiêu chuẩn"
    @Published var availableModels: [String] = []
    @Published var isFetchingModels = false
    @Published var modelFetchMessage = ""
    @Published var key = ""

    // AI Meeting Co-Pilot (Phân tích ngữ cảnh & gợi ý câu trả lời tiếng Anh khi giao tiếp)
    @Published var coPilotProvider: AIProvider = .gemini
    @Published var coPilotModel: String = "gemini-1.5-flash"
    @Published var coPilotKey: String = ""
    @Published var availableCoPilotModels: [String] = []
    @Published var isFetchingCoPilotModels = false
    @Published var coPilotFetchMessage = ""

    @Published var showMascot: Bool = UserDefaults.standard.object(forKey: "ShowMascot") as? Bool ?? true {
        didSet {
            UserDefaults.standard.set(showMascot, forKey: "ShowMascot")
        }
    }
    @Published var mascotStyle: String = {
        let defaults = UserDefaults.standard
        let selected = defaults.string(forKey: "MascotStyle") == "pixel" ? "pixel" : "sprite"
        defaults.set(selected, forKey: "MascotStyle")
        return selected
    }() {
        didSet {
            UserDefaults.standard.set(mascotStyle, forKey: "MascotStyle")
        }
    }
    @Published var mascotIdleActivity: MascotIdleActivity = {
        let saved = UserDefaults.standard.string(forKey: "MascotIdleActivity") ?? "auto"
        return MascotIdleActivity(rawValue: saved) ?? .auto
    }() {
        didSet {
            UserDefaults.standard.set(mascotIdleActivity.rawValue, forKey: "MascotIdleActivity")
            if mascotIdleActivity == .strolling {
                if !isDockWalkEnabled {
                    isDockWalkEnabled = true
                }
            } else if isDockWalkEnabled && mascotIdleActivity != .auto {
                isDockWalkEnabled = false
            }
        }
    }

    // Domain Specialty for Prompt Customization (Developer, Business, etc.)
    @Published var domainSpecialty: DomainSpecialty = {
        let saved = UserDefaults.standard.string(forKey: "DomainSpecialty") ?? "developer"
        return DomainSpecialty(rawValue: saved) ?? .developer
    }() {
        didSet {
            UserDefaults.standard.set(domainSpecialty.rawValue, forKey: "DomainSpecialty")
        }
    }

    func hasKeyForProvider(_ p: AIProvider) -> Bool {
        let k = CredentialStore.read(for: p).trimmingCharacters(in: .whitespacesAndNewlines)
        return !k.isEmpty
    }

    @Published var running = false
    @Published var busy = false
    @Published var status = "Chọn nguồn âm thanh để bắt đầu."
    @Published var warning = ""
    @Published var captions: [Caption] = []
    @Published var sessions: [MeetingSession] = []
    @Published var selectedSessionID: UUID? = nil
    @Published var suggestedReplies: [ReplySuggestion] = []
    @Published var isGeneratingSuggestions = false
    @Published var lastAudio: Date?

    private var translatedOriginal: [UUID: String] = [:]
    private var sessionFinalizedWordsCount: Int = 0
    private var sessionFinalizedPrefix: String = ""
    private var immediateTranslationRequested: Bool = false
    private var lastRawRecognizedText: String = ""
    private var recognitionSessionStarted: Date = Date()

    // Multi-Language Support (EN, VI, ZH, JA, KO, FR, DE, ES)
    @Published var sourceLanguage: AppLanguage = {
        let saved = UserDefaults.standard.string(forKey: "SourceLanguage") ?? "en"
        return AppLanguage(rawValue: saved) ?? .english
    }() {
        didSet {
            UserDefaults.standard.set(sourceLanguage.rawValue, forKey: "SourceLanguage")
            translatedOriginal.removeAll()
            sessionFinalizedWordsCount = 0
            sessionFinalizedPrefix = ""
            immediateTranslationRequested = false
            lastRawRecognizedText = ""
        }
    }

    @Published var targetLanguage: AppLanguage = {
        let saved = UserDefaults.standard.string(forKey: "TargetLanguage") ?? "vi"
        return AppLanguage(rawValue: saved) ?? .vietnamese
    }() {
        didSet {
            UserDefaults.standard.set(targetLanguage.rawValue, forKey: "TargetLanguage")
            translatedOriginal.removeAll()
            if running && subtitleMode != .originalOnly {
                scheduleTranslation(id: currentID, text: "", immediate: true)
            }
        }
    }

    // Subtitle Display Mode (Bilingual / Original CC 0ms / Translation Only)
    @Published var subtitleMode: SubtitleDisplayMode = {
        let saved = UserDefaults.standard.string(forKey: "SubtitleDisplayMode") ?? "bilingual"
        return SubtitleDisplayMode(rawValue: saved) ?? .bilingual
    }() {
        didSet {
            UserDefaults.standard.set(subtitleMode.rawValue, forKey: "SubtitleDisplayMode")
            if subtitleMode != .originalOnly && running {
                scheduleTranslation(id: currentID, text: "", immediate: true)
            }
        }
    }

    func swapLanguages() {
        let temp = sourceLanguage
        sourceLanguage = targetLanguage
        targetLanguage = temp
    }

    func setLanguagePair(source: AppLanguage, target: AppLanguage) {
        sourceLanguage = source
        targetLanguage = target
    }

    func restartSpeechRecognition() async {
        guard running else { return }
        speech.stop()
        recognitionSessionStarted = Date()
        sessionFinalizedWordsCount = 0
        currentID = UUID()
        do {
            try speech.start(localeIdentifier: sourceLanguage.speechLocale)
            status = "Đang nhận diện [\(sourceLanguage.displayName)] ➔ Dịch sang [\(targetLanguage.displayName)]..."
        } catch {
            await fail(error)
        }
    }
    private var suggestionTask: Task<Void, Never>?
    private let capture = AudioCapture()
    private let speech = LiveSpeech()
    private(set) var currentID = UUID()
    private var started = Date()
    private var translationTask: Task<Void, Never>?
    private var rotationTask: Task<Void, Never>?
    private var session = UUID()
    private var activeKey = ""
    private var lastAudioUpdateTime: Date = .distantPast
    private var speechRotationTail = ""
    private var lastRecognitionUpdate = Date.distantPast
    private var overlay: NSWindow?

    @Published var selectedDashboardTab: Int = 0
    @Published var selectedNotebookTab: Int = 0
    @Published var showSettingsSheet: Bool = false
    @Published var showAboutSheet: Bool = false
    @Published var isOverlayVisible: Bool = false

    init() {
        // 1. Subtitle Translation Engine: Default to Apple Native (On-Device, 0 token, ~15ms)
        let savedProviderRaw = UserDefaults.standard.string(forKey: "AIProvider") ?? "apple"
        let initialProvider = AIProvider(rawValue: savedProviderRaw) ?? .apple
        self.provider = initialProvider
        self.key = CredentialStore.read(for: initialProvider)
        var savedModel = UserDefaults.standard.string(forKey: "AIModel_\(initialProvider.rawValue)") ?? initialProvider.defaultModel
        if initialProvider == .gemini && (savedModel.contains("2.5") || savedModel.isEmpty) {
            savedModel = "gemini-2.0-flash"
            UserDefaults.standard.set(savedModel, forKey: "AIModel_\(initialProvider.rawValue)")
        }
        self.modelName = savedModel
        self.availableModels = initialProvider.defaultModels

        // 2. AI Meeting Co-Pilot (Phân tích & gợi ý câu trả lời): Default to Gemini / Cloud AI
        let savedCoPilotRaw = UserDefaults.standard.string(forKey: "AICoPilotProvider") ?? "gemini"
        let initialCoPilot = AIProvider(rawValue: savedCoPilotRaw) ?? .gemini
        self.coPilotProvider = initialCoPilot
        self.coPilotKey = CredentialStore.read(for: initialCoPilot)
        var savedCoPilotModel = UserDefaults.standard.string(forKey: "AICoPilotModel_\(initialCoPilot.rawValue)") ?? initialCoPilot.defaultModel
        if initialCoPilot == .gemini && (savedCoPilotModel.contains("2.5") || savedCoPilotModel.isEmpty) {
            savedCoPilotModel = "gemini-2.0-flash"
            UserDefaults.standard.set(savedCoPilotModel, forKey: "AICoPilotModel_\(initialCoPilot.rawValue)")
        }
        self.coPilotModel = savedCoPilotModel
        self.availableCoPilotModels = initialCoPilot.defaultModels

        capture.onAudio = { [weak self] sample in
            guard let self else { return }
            self.speech.append(sample)
            let now = Date()
            if now.timeIntervalSince(self.lastAudioUpdateTime) > 0.25 {
                self.lastAudioUpdateTime = now
                Task { @MainActor [weak self] in self?.lastAudio = now }
            }
        }
        capture.onMicrophone = { [weak self] buffer in
            guard let self else { return }
            self.speech.append(buffer)
            let now = Date()
            if now.timeIntervalSince(self.lastAudioUpdateTime) > 0.25 {
                self.lastAudioUpdateTime = now
                Task { @MainActor [weak self] in self?.lastAudio = now }
            }
        }
        capture.onError = { [weak self] error in
            Task { @MainActor in await self?.fail(error) }
        }
        speech.onResult = { [weak self] text, final in
            Task { @MainActor in self?.receive(text, final: final) }
        }
        speech.onSessionEndedOrTimeout = { [weak self] in
            Task { @MainActor [weak self] in self?.handleSpeechSessionEndedOrTimeout() }
        }
        speech.onError = { [weak self] error in
            Task { @MainActor in await self?.fail(error) }
        }
        Task { [weak self] in
            await self?.refresh()
            let mascotEnabled = UserDefaults.standard.object(forKey: "FloatingMascotEnabled") as? Bool ?? true
            if mascotEnabled {
                self?.showFloatingMascot()
            }
        }
        loadSessions()

        MeetingModel.shared = self
        GlobalHotkeyManager.shared.registerHotkeys()

        // 3. Tự động kiểm tra bản cập nhật mới trên GitHub sau 3 giây khởi động
        Task { @MainActor in
            let autoCheck = UserDefaults.standard.object(forKey: "AutoCheckUpdates") as? Bool ?? true
            if autoCheck {
                try? await Task.sleep(nanoseconds: 3_000_000_000)
                AppUpdater.shared.checkForUpdates(userInitiated: false)
            }
        }
    }

    func restartApp() {
        let bundleURL = Bundle.main.bundleURL
        let config = NSWorkspace.OpenConfiguration()
        config.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(at: bundleURL, configuration: config) { _, _ in
            DispatchQueue.main.async {
                NSApp.terminate(nil)
            }
        }
    }

    func triggerScreenCapturePrompt() {
        CGRequestScreenCaptureAccess()
    }

    func promptPermissionSettings(for type: AppPermissionType) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            let alert = NSAlert()
            alert.alertStyle = .warning
            alert.messageText = "Cần cấp quyền: \(type.title)"
            alert.informativeText = type.message
            alert.addButton(withTitle: "Mở Cài đặt hệ thống")
            alert.addButton(withTitle: "Để sau")

            // Đảm bảo popup confirm LUÔN nổi trên ứng dụng, không bị nằm dưới App hiện có
            alert.window.level = .floating
            NSApp.activate(ignoringOtherApps: true)
            alert.window.center()

            let response = alert.runModal()
            if response == .alertFirstButtonReturn {
                self.openPermissionSettings(for: type)
            }
        }
    }

    func openPermissionSettings(for type: AppPermissionType) {
        if type == .screenCapture {
            triggerScreenCapturePrompt()
        }
        guard let url = URL(string: type.settingsURLString) else { return }

        let config = NSWorkspace.OpenConfiguration()
        config.activates = true
        NSWorkspace.shared.open(url, configuration: config) { app, error in
            DispatchQueue.main.async {
                // Đảm bảo cửa sổ Cài đặt hệ thống (System Settings) nổi lên TRÊN ứng dụng hiện có
                if let settingsApp = app ?? NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.systempreferences").first {
                    if #available(macOS 14.0, *) {
                        NSApp.yieldActivation(to: settingsApp)
                        settingsApp.activate()
                    } else {
                        settingsApp.activate(options: [.activateIgnoringOtherApps, .activateAllWindows])
                    }
                }
            }
        }

        // Kích hoạt bổ sung sau 0.25s để đảm bảo System Settings không bị ứng dụng hiện có đè lên
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            if let settingsApp = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.systempreferences").first {
                if #available(macOS 14.0, *) {
                    NSApp.yieldActivation(to: settingsApp)
                    settingsApp.activate()
                } else {
                    settingsApp.activate(options: [.activateIgnoringOtherApps, .activateAllWindows])
                }
            }
        }
    }

    func openScreenCaptureSettings() {
        openPermissionSettings(for: .screenCapture)
    }

    func refresh(userInitiated: Bool = false) async {
        let hasAccess = CGPreflightScreenCaptureAccess()
        if hasAccess {
            if warning.localizedCaseInsensitiveContains("TCC") || warning.localizedCaseInsensitiveContains("màn hình") {
                warning = ""
            }
        } else if userInitiated {
            warning = "Chưa cấp quyền Ghi màn hình & Âm thanh hệ thống. Hãy cấp quyền trong Cài đặt hệ thống."
            promptPermissionSettings(for: .screenCapture)
        }
        do {
            let apps = try await capture.applications()
            self.applications = apps
            if warning.localizedCaseInsensitiveContains("TCC") || warning.localizedCaseInsensitiveContains("màn hình") {
                warning = ""
            }
        } catch {
            let msg = error.localizedDescription
            if msg.localizedCaseInsensitiveContains("TCC") || msg.localizedCaseInsensitiveContains("declined") || !hasAccess {
                warning = "Chưa cấp quyền Ghi màn hình & Âm thanh hệ thống. Hãy cấp quyền trong Cài đặt hệ thống."
                if userInitiated {
                    promptPermissionSettings(for: .screenCapture)
                }
            } else {
                warning = "Không lấy được danh sách ứng dụng: \(msg)"
            }
        }
    }

    func setProvider(_ newProvider: AIProvider) {
        guard provider != newProvider else { return }
        provider = newProvider
        UserDefaults.standard.set(newProvider.rawValue, forKey: "AIProvider")
        key = CredentialStore.read(for: newProvider)
        activeKey = key.trimmingCharacters(in: .whitespacesAndNewlines)
        let savedModel = UserDefaults.standard.string(forKey: "AIModel_\(newProvider.rawValue)") ?? newProvider.defaultModel
        modelName = savedModel
        availableModels = newProvider.defaultModels
        modelFetchMessage = ""
        if running {
            status = (provider == .free || activeKey.isEmpty) ? "Đang nghe \(sourceLanguage.displayName) và dịch sang \(targetLanguage.displayName) (Google Dịch Miễn phí)" : "Đang nghe \(sourceLanguage.displayName) và dịch sang \(targetLanguage.displayName) (\(provider.shortName) • \(modelName))"
        }
    }

    func updateModelName(_ newModel: String, for targetProvider: AIProvider) {
        if provider == targetProvider {
            modelName = newModel
            UserDefaults.standard.set(newModel, forKey: "AIModel_\(targetProvider.rawValue)")
            if running {
                status = "Đang nghe \(sourceLanguage.displayName) và dịch sang \(targetLanguage.displayName) (\(provider.shortName) • \(modelName))"
            }
        } else {
            UserDefaults.standard.set(newModel, forKey: "AIModel_\(targetProvider.rawValue)")
        }
        if coPilotProvider == targetProvider {
            coPilotModel = newModel
            UserDefaults.standard.set(newModel, forKey: "AICoPilotModel_\(targetProvider.rawValue)")
        }
    }

    func fetchModels() async {
        let apiKey = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !apiKey.isEmpty else {
            modelFetchMessage = "Vui lòng nhập API Key trước khi lấy model."
            return
        }
        isFetchingModels = true
        modelFetchMessage = ""
        do {
            let list = try await AITranslator.fetchModels(for: provider, key: apiKey)
            if !list.isEmpty {
                availableModels = list
                if !list.contains(modelName) {
                    modelName = list.first ?? modelName
                }
                modelFetchMessage = "Đã tải \(list.count) model khả dụng từ \(provider.shortName)."
            } else {
                modelFetchMessage = "Không có model phù hợp."
            }
        } catch {
            modelFetchMessage = "Lỗi: \(error.localizedDescription)"
        }
        isFetchingModels = false
    }

    func saveSettings() {
        let trimmedKey = key.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            try CredentialStore.save(trimmedKey, for: provider)
            UserDefaults.standard.set(modelName, forKey: "AIModel_\(provider.rawValue)")
            UserDefaults.standard.set(provider.rawValue, forKey: "AIProvider")
            status = "Đã lưu thiết lập \(provider.displayName)."
        } catch {
            warning = "Không lưu được khóa mã hóa: \(error.localizedDescription)"
        }
    }

    func setCoPilotProvider(_ newProvider: AIProvider) {
        guard coPilotProvider != newProvider else { return }
        coPilotProvider = newProvider
        UserDefaults.standard.set(newProvider.rawValue, forKey: "AICoPilotProvider")
        coPilotKey = CredentialStore.read(for: newProvider)
        let savedModel = UserDefaults.standard.string(forKey: "AICoPilotModel_\(newProvider.rawValue)") ?? newProvider.defaultModel
        coPilotModel = savedModel
        availableCoPilotModels = newProvider.defaultModels
        coPilotFetchMessage = ""
        let apiKey = coPilotKey.trimmingCharacters(in: .whitespacesAndNewlines)
        if !apiKey.isEmpty {
            Task { await fetchCoPilotModels() }
        }
    }

    func fetchCoPilotModels() async {
        let apiKey = coPilotKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !apiKey.isEmpty else {
            coPilotFetchMessage = "Vui lòng nhập API Key trước khi lấy model."
            return
        }
        isFetchingCoPilotModels = true
        coPilotFetchMessage = ""
        do {
            let list = try await AITranslator.fetchModels(for: coPilotProvider, key: apiKey)
            if !list.isEmpty {
                availableCoPilotModels = list
                if !list.contains(coPilotModel) {
                    coPilotModel = list.first ?? coPilotModel
                }
                coPilotFetchMessage = "Đã tải \(list.count) model khả dụng từ \(coPilotProvider.shortName)."
            } else {
                coPilotFetchMessage = "Không có model phù hợp."
            }
        } catch {
            coPilotFetchMessage = "Lỗi: \(error.localizedDescription)"
        }
        isFetchingCoPilotModels = false
    }

    func saveCoPilotSettings() {
        let trimmedKey = coPilotKey.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            try CredentialStore.save(trimmedKey, for: coPilotProvider)
            UserDefaults.standard.set(coPilotModel, forKey: "AICoPilotModel_\(coPilotProvider.rawValue)")
            UserDefaults.standard.set(coPilotProvider.rawValue, forKey: "AICoPilotProvider")
        } catch {
            warning = "Không lưu được khóa mã hóa: \(error.localizedDescription)"
        }
    }

    func start() async {
        guard !busy, !running else { return }
        guard !source.isEmpty else {
            warning = "Hãy chọn nguồn âm thanh trước khi bắt đầu."
            showMainWindow()
            return
        }
        busy = true; warning = ""; defer { busy = false }
        if SFSpeechRecognizer.authorizationStatus() != .authorized {
            let authorized = await withCheckedContinuation { continuation in
                SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0 == .authorized) }
            }
            guard authorized else {
                warning = "Cần quyền Speech Recognition trong System Settings → Privacy & Security."
                promptPermissionSettings(for: .speechRecognition)
                return
            }
        }
        do {
            if source == "microphone" {
                if AVCaptureDevice.authorizationStatus(for: .audio) != .authorized {
                    let allowed = await AVCaptureDevice.requestAccess(for: .audio)
                    guard allowed else {
                        warning = "Cần cấp quyền Microphone."
                        promptPermissionSettings(for: .microphone)
                        return
                    }
                }
            } else if source.isEmpty {
                warning = "Hãy chọn nguồn âm thanh."
                return
            } else {
                let hasAccess = CGPreflightScreenCaptureAccess()
                if !hasAccess {
                    warning = "Chưa cấp quyền Ghi màn hình & Âm thanh hệ thống. Hãy cấp quyền trong Cài đặt hệ thống."
                    promptPermissionSettings(for: .screenCapture)
                    return
                }
            }
            activeKey = key.trimmingCharacters(in: .whitespacesAndNewlines)
            started = Date(); captions = []; translatedOriginal = [:]; currentID = UUID(); lastAudio = nil; session = UUID()
            lastRawRecognizedText = ""
            speechRotationTail = ""
            sessionFinalizedWordsCount = 0
            sessionFinalizedPrefix = ""
            immediateTranslationRequested = false
            recognitionSessionStarted = Date()
            running = true
            status = "Đang kết nối luồng âm thanh..."
            try speech.start(localeIdentifier: sourceLanguage.speechLocale)
            rotationTask?.cancel()
            rotationTask = Task { [weak self] in
                while !Task.isCancelled {
                    try? await Task.sleep(nanoseconds: 6_000_000_000)
                    guard let self, self.running else { break }
                    await MainActor.run {
                        self.rotateSpeechSessionIfNeeded()
                    }
                }
            }
            if source == "microphone" {
                try capture.startMicrophone()
            } else if source == "system" {
                try await capture.startSystemAudio()
            } else {
                do {
                    try await capture.start(applicationID: source)
                } catch {
                    print("[MeetingModel] Warning: start(applicationID: \(source)) failed with \(error), falling back to system audio capture")
                    try await capture.startSystemAudio()
                }
            }
            status = (provider == .free || activeKey.isEmpty) ? "Đang nghe \(sourceLanguage.displayName) và dịch sang \(targetLanguage.displayName) (Google Dịch Miễn phí)" : "Đang nghe \(sourceLanguage.displayName) và dịch sang \(targetLanguage.displayName) (\(provider.shortName) • \(modelName))"
        } catch { await fail(error) }
    }

    func stop() async {
        finalizeCurrentCaption(immediateTranslation: true)
        running = false; session = UUID()
        sessionFinalizedWordsCount = 0
        sessionFinalizedPrefix = ""
        immediateTranslationRequested = false
        lastRawRecognizedText = ""
        rotationTask?.cancel(); rotationTask = nil
        translationTask?.cancel(); translationTask = nil
        speech.stop()
        await capture.stop()
        TTSService.shared.stop()
        if !captions.isEmpty {
            saveCurrentSession()
            status = "Đã dừng. Toàn bộ cuộc họp đã được lưu vào Sổ tay."
        } else {
            status = "Đã dừng. Chọn nguồn âm thanh để bắt đầu phiên mới."
        }
    }
    private func fail(_ error: Error) async {
        guard running || busy else { return }
        await stop()
        let msg = error.localizedDescription
        if msg.localizedCaseInsensitiveContains("TCC") || msg.localizedCaseInsensitiveContains("declined") {
            warning = "Chưa cấp quyền Ghi màn hình & Âm thanh hệ thống. Hãy cấp quyền trong Cài đặt hệ thống."
            promptPermissionSettings(for: .screenCapture)
        } else {
            warning = msg
        }
    }

    private func handleSpeechSessionEndedOrTimeout() {
        guard running else { return }
        speechRotationTail = lastRawRecognizedText
        finalizeCurrentCaption(immediateTranslation: true)
        sessionFinalizedPrefix = ""
        sessionFinalizedWordsCount = 0
        currentID = UUID()
        recognitionSessionStarted = Date()
        do {
            try speech.start(localeIdentifier: sourceLanguage.speechLocale)
        } catch {
            Task { await self.fail(error) }
        }
    }

    private func rotateSpeechSessionIfNeeded() {
        guard running else { return }
        let elapsed = Date().timeIntervalSince(recognitionSessionStarted)
        // Rotate only when approaching the Apple 60s speech limit
        guard elapsed >= 50 else { return }

        // NEVER cut sentences off while the user is actively speaking!
        // Rotate only during a natural pause in speech (silence gap >= 1.5s or empty active card)
        let silenceGap = Date().timeIntervalSince(lastRecognitionUpdate)
        let hasActiveSpeech = silenceGap < 1.5 && (captions.last?.id == currentID && !(captions.last?.original.isEmpty ?? true))
        if hasActiveSpeech && elapsed < 58 {
            return
        }

        speechRotationTail = lastRawRecognizedText
        finalizeCurrentCaption(immediateTranslation: true)
        sessionFinalizedPrefix = ""
        sessionFinalizedWordsCount = 0
        currentID = UUID()
        recognitionSessionStarted = Date()
        do {
            try speech.start(localeIdentifier: sourceLanguage.speechLocale)
        } catch {
            Task { await self.fail(error) }
        }
    }

    private func receive(_ text: String, final: Bool) {
        guard running else { return }
        let raw = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedRaw = SpeechTextReconciler.removingOverlap(raw, after: speechRotationTail)
        guard !trimmedRaw.isEmpty else {
            if final { handleSpeechSessionEndedOrTimeout() }
            return
        }
        lastRecognitionUpdate = Date()
        let elapsed = Date().timeIntervalSince(started)

        let allWords = trimmedRaw.components(separatedBy: .whitespaces).filter { !$0.isEmpty }

        var currentText = trimmedRaw
        if !sessionFinalizedPrefix.isEmpty {
            if let remainder = SpeechTextReconciler.remainder(trimmedRaw, committed: sessionFinalizedPrefix) {
                currentText = remainder
            } else {
                // A fresh hypothesis must not overwrite or truncate the previous live paragraph.
                finalizeCurrentCaption(immediateTranslation: true)
                currentID = UUID()
                sessionFinalizedPrefix = ""
                sessionFinalizedWordsCount = 0
            }
        }

        guard !currentText.isEmpty else {
            if final { handleSpeechSessionEndedOrTimeout() }
            return
        }
        lastRawRecognizedText = trimmedRaw

        // Update or append current live caption
        if let index = captions.firstIndex(where: { $0.id == currentID }) {
            currentText = SpeechTextReconciler.keepLongerPartial(captions[index].original, incoming: currentText, final: final)
            captions[index].original = currentText
            captions[index].end = elapsed
        } else {
            if let last = captions.last, last.original == currentText {
                return
            }
            captions.append(Caption(id: currentID, start: elapsed, end: elapsed, original: currentText))
        }

        let activeWords = currentText.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
        let hasSentencePunctuation = currentText.hasSuffix(".") || currentText.hasSuffix("?") || currentText.hasSuffix("!") || currentText.hasSuffix("...")
        let isLongChunk = activeWords.count >= 22

        if final {
            // Utterance finalized by speech recognizer
            speechRotationTail = lastRawRecognizedText
            finalizeCurrentCaption(immediateTranslation: true)
            sessionFinalizedPrefix = ""
            sessionFinalizedWordsCount = 0
            currentID = UUID()
            recognitionSessionStarted = Date()
            if running {
                do {
                    try speech.start(localeIdentifier: sourceLanguage.speechLocale)
                } catch {
                    Task { await fail(error) }
                }
            }
        } else if hasSentencePunctuation && activeWords.count >= 4 {
            // Natural sentence boundary reached
            sessionFinalizedPrefix = trimmedRaw
            sessionFinalizedWordsCount = allWords.count
            finalizeCurrentCaption(immediateTranslation: true)
            currentID = UUID()
        } else if isLongChunk {
            // Natural comma boundary splitting for long speech chunks
            var splitIndex = 18
            for i in stride(from: min(activeWords.count - 2, 20), through: 13, by: -1) {
                let word = activeWords[i]
                if word.hasSuffix(",") || word.hasSuffix(";") || word.hasSuffix(":") {
                    splitIndex = i + 1
                    break
                }
            }
            let chunkToFinalize = activeWords.prefix(splitIndex).joined(separator: " ")
            if let index = captions.firstIndex(where: { $0.id == currentID }) {
                captions[index].original = chunkToFinalize
            }
            let wordsBeforeSplit = (allWords.count - activeWords.count) + splitIndex
            sessionFinalizedWordsCount = wordsBeforeSplit
            sessionFinalizedPrefix = allWords.prefix(wordsBeforeSplit).joined(separator: " ")
            finalizeCurrentCaption(immediateTranslation: true)
            currentID = UUID()

            let remainingWords = Array(activeWords.dropFirst(splitIndex))
            if !remainingWords.isEmpty {
                let remText = remainingWords.joined(separator: " ")
                captions.append(Caption(id: currentID, start: elapsed, end: elapsed, original: remText))
                scheduleTranslation(id: currentID, text: remText, immediate: false)
            }
        } else {
            // Live in-progress translation for the active card
            scheduleTranslation(id: currentID, text: currentText, immediate: false)
        }
    }

    private func finalizeCurrentCaption(immediateTranslation: Bool) {
        guard let row = captions.first(where: { $0.id == currentID }), !row.original.isEmpty else { return }
        immediateTranslationRequested = immediateTranslation
        scheduleTranslation(id: row.id, text: row.original, immediate: immediateTranslation)
        generateSuggestions(for: row.original)
        if subtitleMode == .originalOnly {
            TTSService.shared.enqueueAutoTTS(
                id: row.id,
                original: row.original,
                translation: "",
                sourceLang: sourceLanguage,
                targetLang: targetLanguage
            )
        }
    }

    func generateSuggestions(for customText: String? = nil) {
        let latestUtterance = customText ?? captions.last(where: { !$0.original.isEmpty })?.original ?? ""
        guard !latestUtterance.isEmpty else { return }

        suggestionTask?.cancel()
        let currentProvider = coPilotProvider
        let currentModel = coPilotModel
        let currentKey = coPilotKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let domain = domainSpecialty

        // Gather deep conversation context (last 8-10 captions with original & translation)
        let recentCaptions = captions.suffix(10).compactMap { caption -> String? in
            let orig = caption.original.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !orig.isEmpty else { return nil }
            let trans = caption.vietnamese.trimmingCharacters(in: .whitespacesAndNewlines)
            return trans.isEmpty ? orig : "\(orig) (Dịch: \(trans))"
        }

        suggestionTask = Task { @MainActor [weak self] in
            guard let self else { return }
            self.isGeneratingSuggestions = true
            defer { self.isGeneratingSuggestions = false }

            let results = await AITranslator.suggestReplies(
                recentContext: recentCaptions,
                latestUtterance: latestUtterance,
                domain: domain,
                provider: currentProvider,
                model: currentModel,
                key: currentKey
            )
            guard !Task.isCancelled else { return }
            self.suggestedReplies = results
        }
    }

    private func scheduleTranslation(id: UUID, text: String, immediate: Bool = false) {
        guard subtitleMode != .originalOnly else { return }
        if immediate {
            immediateTranslationRequested = true
        }
        guard translationTask == nil else { return }
        let token = session
        let currentProvider = provider
        let currentModel = modelName
        let currentKey = activeKey
        translationTask = Task { [weak self] in
            guard let self else { return }
            defer { self.translationTask = nil }
            while !Task.isCancelled, self.running, self.session == token, self.subtitleMode != .originalOnly {
                // Find next caption needing translation
                guard let row = self.captions.first(where: { self.translatedOriginal[$0.id] != $0.original && !$0.original.isEmpty }) else { break }

                let isCurrentLiveRow = (row.id == self.currentID)
                let shouldDebounce = isCurrentLiveRow && !self.immediateTranslationRequested
                if shouldDebounce {
                    let debounceMs = (currentProvider == .apple) ? 180 : ((currentProvider == .free || currentKey.isEmpty) ? 320 : 450)
                    try? await Task.sleep(for: .milliseconds(debounceMs))
                    guard !Task.isCancelled, self.session == token else { return }
                }
                self.immediateTranslationRequested = false

                do {
                    let textToTranslate = row.original
                    let translated = try await AITranslator.translate(
                        textToTranslate,
                        from: self.sourceLanguage,
                        to: self.targetLanguage,
                        domain: self.domainSpecialty,
                        provider: currentProvider,
                        model: currentModel,
                        key: currentKey
                    )
                    guard !Task.isCancelled, self.session == token else { return }
                    if let index = self.captions.firstIndex(where: { $0.id == row.id }) {
                        self.captions[index].vietnamese = translated
                        self.translatedOriginal[row.id] = textToTranslate
                        self.warning = ""
                        TTSService.shared.enqueueAutoTTS(
                            id: row.id,
                            original: textToTranslate,
                            translation: translated,
                            sourceLang: self.sourceLanguage,
                            targetLang: self.targetLanguage
                        )
                    }
                } catch {
                    guard !Task.isCancelled, self.session == token else { return }
                    self.warning = error.localizedDescription
                    try? await Task.sleep(for: .milliseconds(1000))
                    return
                }
            }
        }
    }

    func showOverlay() {
        if let overlay {
            overlay.orderFrontRegardless()
            isOverlayVisible = true
            return
        }

        var initialRect: NSRect
        let savedX = UserDefaults.standard.double(forKey: "OverlayWindowX")
        let savedY = UserDefaults.standard.double(forKey: "OverlayWindowY")
        let savedW = UserDefaults.standard.double(forKey: "OverlayWindowW")
        let savedH = UserDefaults.standard.double(forKey: "OverlayWindowH")

        // Wider and more comfortable default width (780pt) for dual-language subtitles
        let defaultW: CGFloat = 780
        let defaultH: CGFloat = 130
        let w: CGFloat = (savedW >= 500) ? savedW : defaultW
        let h: CGFloat = (savedH >= 90) ? savedH : defaultH

        if savedX > 50 && savedY > 50 {
            initialRect = NSRect(x: savedX, y: savedY, width: w, height: h)
        } else if let screen = NSScreen.main {
            let v = screen.visibleFrame
            initialRect = NSRect(x: v.midX - (w / 2), y: v.minY + 60, width: w, height: h)
        } else {
            initialRect = NSRect(x: 200, y: 120, width: w, height: h)
        }

        let panel = NSPanel(
            contentRect: initialRect,
            styleMask: [.borderless, .resizable],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.isMovableByWindowBackground = true
        panel.isReleasedWhenClosed = false
        panel.minSize = NSSize(width: 480, height: 86)
        panel.contentView = OverlayHostingView(rootView: OverlayView(model: self))

        NotificationCenter.default.addObserver(
            forName: NSWindow.didMoveNotification,
            object: panel,
            queue: .main
        ) { [weak panel] _ in
            guard let frame = panel?.frame else { return }
            UserDefaults.standard.set(Double(frame.origin.x), forKey: "OverlayWindowX")
            UserDefaults.standard.set(Double(frame.origin.y), forKey: "OverlayWindowY")
        }

        NotificationCenter.default.addObserver(
            forName: NSWindow.didResizeNotification,
            object: panel,
            queue: .main
        ) { [weak panel] _ in
            guard let frame = panel?.frame else { return }
            UserDefaults.standard.set(Double(frame.size.width), forKey: "OverlayWindowW")
            UserDefaults.standard.set(Double(frame.size.height), forKey: "OverlayWindowH")
        }

        overlay = panel
        panel.orderFrontRegardless()
        isOverlayVisible = true
    }

    func positionOverlay(atTop: Bool) {
        showOverlay()
        guard let overlay, let screen = overlay.screen ?? NSScreen.main else { return }
        let area = screen.visibleFrame
        var frame = overlay.frame
        frame.size.width = min(frame.width, area.width - 32)
        frame.origin.x = area.midX - frame.width / 2
        frame.origin.y = atTop ? area.maxY - frame.height - 20 : area.minY + 20
        overlay.setFrame(frame, display: true)
        UserDefaults.standard.set(atTop ? "top" : "bottom", forKey: "OverlayPlacement")
    }

    func hideOverlay() {
        overlay?.orderOut(nil)
        isOverlayVisible = false
    }

    func toggleOverlay() {
        if let overlay, overlay.isVisible {
            hideOverlay()
        } else {
            showOverlay()
        }
    }

    func clearCaptions() {
        captions.removeAll()
        translatedOriginal.removeAll()
        TTSService.shared.clearHistory()
    }

    func export(srt: Bool) {
        let panel = NSSavePanel(); panel.nameFieldStringValue = srt ? "TransTools.srt" : "TransTools.txt"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let content = captions.enumerated().map { index, row in
            if srt { return "\(index + 1)\n\(Self.timestamp(row.start)) --> \(Self.timestamp(max(row.end, row.start + 1)))\n\(row.original)\n\(row.vietnamese)\n" }
            return "[\(Self.timestamp(row.start))]\n\(row.original)\n\(row.vietnamese)\n"
        }.joined(separator: "\n")
        do { try content.write(to: url, atomically: true, encoding: .utf8) } catch { warning = error.localizedDescription }
    }
    static func timestamp(_ time: TimeInterval) -> String {
        let ms = Int(max(0, time) * 1000)
        return String(format: "%02d:%02d:%02d,%03d", ms / 3600000, (ms / 60000) % 60, (ms / 1000) % 60, ms % 1000)
    }

    // MARK: - Meeting Notebook Sessions & Persistence

    private var sessionsFileURL: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("TransTools", isDirectory: true)
        if !FileManager.default.fileExists(atPath: dir.path) {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir.appendingPathComponent("meeting_sessions.json")
    }

    func loadSessions() {
        let file = sessionsFileURL
        guard FileManager.default.fileExists(atPath: file.path) else { return }
        do {
            let data = try Data(contentsOf: file)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let loaded = try decoder.decode([MeetingSession].self, from: data)
            self.sessions = loaded.sorted(by: { $0.createdAt > $1.createdAt })
            if selectedSessionID == nil, let first = self.sessions.first {
                selectedSessionID = first.id
            }
        } catch {
            print("Failed to load meeting sessions: \(error)")
        }
    }

    func saveSessionsToDisk() {
        let file = sessionsFileURL
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted]
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(sessions)
            try data.write(to: file, options: .atomic)
        } catch {
            print("Failed to save meeting sessions: \(error)")
        }
    }

    func saveCurrentSession(customTitle: String? = nil, notes: String = "") {
        guard !captions.isEmpty else { return }
        let now = Date()
        let elapsed = max(1, now.timeIntervalSince(started))
        let records = captions.map { c in
            CaptionRecord(id: c.id, start: c.start, end: c.end, original: c.original, vietnamese: c.vietnamese)
        }

        let dateFormatter = DateFormatter()
        dateFormatter.locale = Locale(identifier: "vi_VN")
        dateFormatter.dateFormat = "HH:mm • dd/MM/yyyy"
        let dateString = dateFormatter.string(from: started)

        let appName = currentSourceName()
        let defaultTitle = customTitle ?? "Cuộc họp \(appName) (\(dateString))"

        let newSession = MeetingSession(
            title: defaultTitle,
            createdAt: started,
            durationSeconds: elapsed,
            audioSource: appName,
            notes: notes,
            captions: records
        )

        if let idx = sessions.firstIndex(where: { Calendar.current.isDate($0.createdAt, inSameDayAs: newSession.createdAt) && abs($0.createdAt.timeIntervalSince(newSession.createdAt)) < 5 && $0.audioSource == newSession.audioSource }) {
            sessions[idx] = newSession
        } else {
            sessions.insert(newSession, at: 0)
        }
        selectedSessionID = newSession.id
        saveSessionsToDisk()
        status = "Đã lưu cuộc họp vào Sổ tay."
    }

    func updateSessionTitle(id: UUID, title: String) {
        if let idx = sessions.firstIndex(where: { $0.id == id }) {
            sessions[idx].title = title
            saveSessionsToDisk()
        }
    }

    func updateSessionNotes(id: UUID, notes: String) {
        if let idx = sessions.firstIndex(where: { $0.id == id }) {
            sessions[idx].notes = notes
            saveSessionsToDisk()
        }
    }

    func deleteSession(id: UUID) {
        sessions.removeAll(where: { $0.id == id })
        if selectedSessionID == id {
            selectedSessionID = sessions.first?.id
        }
        saveSessionsToDisk()
    }

    func currentSourceName() -> String {
        switch source {
        case "system": return "Âm thanh hệ thống"
        case "microphone": return "Microphone"
        case "": return "Chưa chọn nguồn âm thanh"
        default:
            return applications.first(where: { $0.bundleIdentifier == source })?.applicationName ?? source
        }
    }

    func exportSessionToDocx(_ session: MeetingSession) {
        let panel = NSSavePanel()
        let sanitizedName = session.title.replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
            .replacingOccurrences(of: "\\", with: "-")
        panel.nameFieldStringValue = "\(sanitizedName).docx"
        panel.allowedContentTypes = [UTType(filenameExtension: "docx") ?? .data]
        panel.prompt = "Xuất file Word"

        guard panel.runModal() == .OK, let targetURL = panel.url else { return }

        let dateFormatter = DateFormatter()
        dateFormatter.locale = Locale(identifier: "vi_VN")
        dateFormatter.dateFormat = "HH:mm:ss, EEEE dd/MM/yyyy"
        let dateString = dateFormatter.string(from: session.createdAt)

        let minutes = Int(session.durationSeconds) / 60
        let seconds = Int(session.durationSeconds) % 60
        let durationString = minutes > 0 ? "\(minutes) phút \(seconds) giây" : "\(seconds) giây"

        var rowsHtml = ""
        for record in session.captions {
            let startTs = Self.timestamp(record.start)
            let orig = record.original.replacingOccurrences(of: "<", with: "&lt;").replacingOccurrences(of: ">", with: "&gt;")
            let viet = record.vietnamese.replacingOccurrences(of: "<", with: "&lt;").replacingOccurrences(of: ">", with: "&gt;")
            rowsHtml += """
            <tr>
              <td class="time">\(startTs)</td>
              <td class="en">\(orig)</td>
              <td class="vi">\(viet)</td>
            </tr>
            """
        }

        let notesHtml = session.notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "" : """
        <div class="notes-box">
          <div class="notes-header">📝 GHI CHÚ & HÀNH ĐỘNG (ACTION ITEMS)</div>
          <p style="white-space: pre-wrap; margin: 0; line-height: 1.5;">\(session.notes.replacingOccurrences(of: "<", with: "&lt;").replacingOccurrences(of: ">", with: "&gt;"))</p>
        </div>
        """

        let html = """
        <!DOCTYPE html>
        <html>
        <head>
        <meta charset="utf-8">
        <style>
          body { font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, Helvetica, Arial, sans-serif; margin: 30px; color: #1e293b; }
          h1 { color: #1e40af; font-size: 22px; border-bottom: 2px solid #3b82f6; padding-bottom: 8px; margin-bottom: 8px; }
          .meta { color: #64748b; font-size: 13px; line-height: 1.6; margin-bottom: 20px; }
          .notes-box { background-color: #f1f5f9; border-left: 4px solid #6366f1; padding: 12px 16px; margin-bottom: 24px; }
          .notes-header { font-weight: bold; color: #4338ca; margin-bottom: 6px; font-size: 13px; }
          h2 { font-size: 16px; color: #0f172a; margin-top: 24px; margin-bottom: 12px; }
          table { width: 100%; border-collapse: collapse; margin-top: 10px; font-size: 12px; }
          th { background-color: #e2e8f0; color: #1e293b; text-align: left; padding: 8px 10px; border: 1px solid #cbd5e1; }
          td { padding: 8px 10px; border: 1px solid #e2e8f0; vertical-align: top; }
          .time { color: #64748b; font-family: Menlo, monospace; font-size: 11px; width: 75px; white-space: nowrap; }
          .en { color: #0f172a; font-weight: 500; }
          .vi { color: #2563eb; }
        </style>
        </head>
        <body>
          <h1>\(session.title)</h1>
          <div class="meta">
            <strong>Thời gian:</strong> \(dateString)<br>
            <strong>Thời lượng:</strong> \(durationString)<br>
            <strong>Nguồn thu âm:</strong> \(session.audioSource)<br>
            <strong>Tổng số câu hội thoại:</strong> \(session.captions.count) đoạn
          </div>
          \(notesHtml)
          <h2>Nội dung hội thoại chi tiết (Song ngữ Anh - Việt)</h2>
          <table>
            <thead>
              <tr>
                <th style="width: 75px;">Thời gian</th>
                <th>Tiếng Anh (Original)</th>
                <th>Tiếng Việt (Bản dịch)</th>
              </tr>
            </thead>
            <tbody>
              \(rowsHtml)
            </tbody>
          </table>
        </body>
        </html>
        """

        let tempHTMLURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".html")
        do {
            try html.write(to: tempHTMLURL, atomically: true, encoding: .utf8)
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/textutil")
            process.arguments = ["-convert", "docx", tempHTMLURL.path, "-output", targetURL.path]
            try process.run()
            process.waitUntilExit()
            try? FileManager.default.removeItem(at: tempHTMLURL)
            if process.terminationStatus == 0 {
                NSWorkspace.shared.activateFileViewerSelecting([targetURL])
                status = "Đã xuất thành công file Word: \(targetURL.lastPathComponent)"
            } else {
                warning = "Không thể chuyển đổi sang Word docx (Mã lỗi \(process.terminationStatus))."
            }
        } catch {
            warning = "Lỗi khi xuất Word: \(error.localizedDescription)"
        }
    }

    func exportSessionToTxt(_ session: MeetingSession) {
        let panel = NSSavePanel()
        let sanitizedName = session.title.replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
            .replacingOccurrences(of: "\\", with: "-")
        panel.nameFieldStringValue = "\(sanitizedName).txt"
        panel.allowedContentTypes = [.plainText]
        panel.prompt = "Xuất file TXT"

        guard panel.runModal() == .OK, let targetURL = panel.url else { return }

        let dateFormatter = DateFormatter()
        dateFormatter.locale = Locale(identifier: "vi_VN")
        dateFormatter.dateFormat = "HH:mm:ss, dd/MM/yyyy"
        let dateString = dateFormatter.string(from: session.createdAt)

        var content = """
        ============================================================
        TRANSTOOLS - SỔ TAY CUỘC HỌP
        Tiêu đề: \(session.title)
        Thời gian: \(dateString)
        Nguồn âm thanh: \(session.audioSource)
        Số đoạn hội thoại: \(session.captions.count)
        ============================================================

        """

        if !session.notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            content += """
            [GHI CHÚ & HÀNH ĐỘNG]
            \(session.notes)

            ============================================================

            """
        }

        content += "[NỘI DUNG HỘI THOẠI SONG NGỮ]\n\n"
        for (idx, record) in session.captions.enumerated() {
            let time = Self.timestamp(record.start)
            content += "#\(idx + 1) [\(time)]\n"
            content += "EN: \(record.original)\n"
            content += "VI: \(record.vietnamese)\n\n"
        }

        do {
            try content.write(to: targetURL, atomically: true, encoding: .utf8)
            NSWorkspace.shared.activateFileViewerSelecting([targetURL])
            status = "Đã xuất file TXT thành công."
        } catch {
            warning = error.localizedDescription
        }
    }

    func exportCurrentDocx() {
        let tempSession = MeetingSession(
            title: "Cuộc họp TransTools (\(DateFormatter.localizedString(from: Date(), dateStyle: .short, timeStyle: .short)))",
            createdAt: started,
            durationSeconds: Date().timeIntervalSince(started),
            audioSource: currentSourceName(),
            captions: captions.map { CaptionRecord(id: $0.id, start: $0.start, end: $0.end, original: $0.original, vietnamese: $0.vietnamese) }
        )
        exportSessionToDocx(tempSession)
    }

    // MARK: - Floating Mascot Window Management
    @Published var isFloatingMascotVisible: Bool = false
    private let dockGarden = DockGardenController()
    var mascotWindow: NSWindow?

    // Chip Chip Speech Bubble Management
    var mascotBubbleWindow: NSWindow?
    var bubbleDismissTask: Task<Void, Never>?
    @Published var bubbleWord: String = ""
    @Published var bubbleMeaning: String = ""
    @Published var bubblePhonetic: String = ""
    @Published var bubbleContext: String = ""
    @Published var bubbleSourceApp: String = ""
    @Published var isBubbleLoading: Bool = false
    @Published var isBubbleVisible: Bool = false
    @Published var isBubbleHovered: Bool = false
    @Published var isMascotHovered: Bool = false
    @Published var bubbleCanReplace = false
    @Published var bubbleMode: String = "translate" // "translate" hoặc "grammar"

    // Dock Bar Patrol Walk Mode (Chỉ đi dạo khi rảnh rỗi, dừng tại chỗ khi tắt)
    @Published var isDockWalkEnabled: Bool = UserDefaults.standard.bool(forKey: "MascotDockWalkEnabled") {
        didSet {
            UserDefaults.standard.set(isDockWalkEnabled, forKey: "MascotDockWalkEnabled")
            if isDockWalkEnabled {
                mascotIdleActivity = .auto
                startDockWalking()
            } else {
                stopDockWalking()
            }
        }
    }
    var dockWalkDistance: CGFloat = 0
    var dockWalkLastTick: Date?
    var dockWalkTimer: Timer?
    var dockWalkDirection: CGFloat = 1.0 // 1: đi sang phải, -1: đi sang trái
    var dockWalkPauseUntil: Date? = nil
    var dockWalkCurrentX: CGFloat? = nil

    func convenientMascotRect() -> NSRect {
        let mascotWidth: CGFloat = 164
        let mascotHeight: CGFloat = 152

        // Pick active screen: window screen, mouse cursor screen, or main screen
        let targetScreen: NSScreen = {
            if let windowScreen = mainWindow?.screen, mainWindow?.isVisible == true {
                return windowScreen
            }
            let mouseLoc = NSEvent.mouseLocation
            if let screenWithMouse = NSScreen.screens.first(where: { NSMouseInRect(mouseLoc, $0.frame, false) }) {
                return screenWithMouse
            }
            return NSScreen.main ?? NSScreen.screens.first ?? NSScreen()
        }()

        let visible = targetScreen.visibleFrame
        // Place in bottom-right corner: 24pt from right edge, 36pt above bottom dock
        let x = visible.maxX - mascotWidth - 24
        let y = visible.minY + 36
        return NSRect(x: x, y: y, width: mascotWidth, height: mascotHeight)
    }

    func snapMascotToConvenientPosition() {
        let targetRect = convenientMascotRect()
        guard let window = mascotWindow else {
            showFloatingMascot()
            return
        }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.35
            window.animator().setFrame(targetRect, display: true)
        }
        UserDefaults.standard.set(Double(targetRect.origin.x), forKey: "FloatingMascotX")
        UserDefaults.standard.set(Double(targetRect.origin.y), forKey: "FloatingMascotY")
    }

    func showFloatingMascot() {
        let convenient = convenientMascotRect()

        if let mascotWindow {
            // Check if existing window is visible on any active screen
            let isVisibleOnScreen = NSScreen.screens.contains { screen in
                let intersection = screen.visibleFrame.intersection(mascotWindow.frame)
                return intersection.width >= 40 && intersection.height >= 40
            }
            if !isVisibleOnScreen || mascotWindow.frame.size.height < 150 || mascotWindow.frame.size.width < 160 {
                var f = mascotWindow.frame
                f.size = convenient.size
                mascotWindow.setFrame(f, display: true)
            }
            mascotWindow.orderFrontRegardless()
            isFloatingMascotVisible = true
            UserDefaults.standard.set(true, forKey: "FloatingMascotEnabled")
            if isDockWalkEnabled {
                startDockWalking()
            }
            return
        }

        var initialRect: NSRect = convenient
        let savedX = UserDefaults.standard.double(forKey: "FloatingMascotX")
        let savedY = UserDefaults.standard.double(forKey: "FloatingMascotY")

        if savedX > 0 && savedY > 0 {
            let candidateRect = NSRect(x: savedX, y: savedY, width: convenient.width, height: convenient.height)
            let isCandidateOnScreen = NSScreen.screens.contains { screen in
                let intersection = screen.visibleFrame.intersection(candidateRect)
                return intersection.width >= 40 && intersection.height >= 40
            }
            if isCandidateOnScreen {
                initialRect = candidateRect
            }
        }

        let panel = NSPanel(
            contentRect: initialRect,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.isMovableByWindowBackground = true
        panel.isReleasedWhenClosed = false
        panel.contentView = MascotHostingView(rootView: FloatingMascotView(model: self))

        NotificationCenter.default.addObserver(
            forName: NSWindow.didMoveNotification,
            object: panel,
            queue: .main
        ) { [weak self, weak panel] _ in
            MainActor.assumeIsolated {
                guard let self = self, let origin = panel?.frame.origin else { return }
                if !self.isDockWalkEnabled {
                    UserDefaults.standard.set(Double(origin.x), forKey: "FloatingMascotX")
                    UserDefaults.standard.set(Double(origin.y), forKey: "FloatingMascotY")
                }
                self.updateBubblePosition()
            }
        }

        mascotWindow = panel
        panel.orderFrontRegardless()
        isFloatingMascotVisible = true
        UserDefaults.standard.set(true, forKey: "FloatingMascotEnabled")
        if isDockWalkEnabled {
            startDockWalking()
        }
    }

    func hideFloatingMascot() {
        stopDockWalking()
        mascotWindow?.orderOut(nil)
        hideSpeechBubble()
        isFloatingMascotVisible = false
        UserDefaults.standard.set(false, forKey: "FloatingMascotEnabled")
    }

    func toggleFloatingMascot() {
        if isFloatingMascotVisible {
            hideFloatingMascot()
        } else {
            showFloatingMascot()
        }
    }

    func showBubbleLoading(word: String, sourceApp: String, mode: String = "translate") {
        bubbleDismissTask?.cancel()
        bubbleMode = mode
        bubbleWord = word
        bubbleCanReplace = false
        bubbleMeaning = (mode == "grammar") ? "Chip Chip đang sửa ngữ pháp..." : (mode == "viToEn" ? "Đang dịch VI → EN theo \(domainSpecialty.title)..." : "Chip Chip đang dịch...")
        bubblePhonetic = ""
        bubbleContext = ""
        bubbleSourceApp = sourceApp
        isBubbleLoading = true
        isBubbleVisible = true
        showFloatingMascot()
        presentBubbleWindow()
    }

    func showSpeechBubble(word: String, meaning: String, phonetic: String = "", context: String = "", sourceApp: String = "", mode: String = "translate", canReplace: Bool = false) {
        bubbleMode = mode
        bubbleWord = word
        bubbleMeaning = meaning
        bubbleCanReplace = canReplace
        bubblePhonetic = phonetic
        bubbleContext = context
        bubbleSourceApp = sourceApp
        isBubbleLoading = false
        isBubbleVisible = true
        showFloatingMascot()
        presentBubbleWindow()

        bubbleDismissTask?.cancel()
        if mode == "grammar" || mode == "viToEn" { return }
        bubbleDismissTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 10_000_000_000)
            guard let self = self else { return }
            if !self.isBubbleHovered && self.isBubbleVisible {
                self.hideSpeechBubble()
            }
        }
    }

    // MARK: - Dock Bar Patrol Movement Engine
    private func getDockScreen(for window: NSWindow?) -> NSScreen {
        if let win = window, let winScreen = win.screen {
            return winScreen
        }
        if let win = window {
            let center = NSPoint(x: win.frame.midX, y: win.frame.midY)
            if let screenWithWin = NSScreen.screens.first(where: { NSMouseInRect(center, $0.frame, false) }) {
                return screenWithWin
            }
        }
        let mouseLoc = NSEvent.mouseLocation
        if let screenWithMouse = NSScreen.screens.first(where: { NSMouseInRect(mouseLoc, $0.frame, false) }) {
            return screenWithMouse
        }
        if let dockScreen = NSScreen.screens.first(where: { $0.visibleFrame.minY > $0.frame.minY }) {
            return dockScreen
        }
        return NSScreen.main ?? NSScreen.screens.first ?? NSScreen()
    }

    func startDockWalking() {
        stopDockWalking()
        guard isFloatingMascotVisible, let window = mascotWindow else { return }

        let screen = getDockScreen(for: window)
        let visible = screen.visibleFrame
        var currentFrame = window.frame
        let targetDockY = max(visible.minY, screen.frame.minY) + 2

        let minX = visible.minX + 16
        let maxX = visible.maxX - window.frame.width - 16
        guard maxX > minX else { return }

        var targetX = currentFrame.origin.x
        if targetX < minX || targetX > maxX {
            targetX = max(minX, min(maxX, targetX))
        }

        // Nếu bắt đầu ở nửa bên phải màn hình: ưu tiên đi dạo sang trái trước
        // Nếu bắt đầu ở nửa bên trái: ưu tiên đi dạo sang phải trước
        let midX = (minX + maxX) / 2.0
        dockWalkDirection = (targetX > midX) ? -1.0 : 1.0

        dockWalkCurrentX = targetX
        currentFrame.origin = NSPoint(x: targetX, y: targetDockY)
        window.setFrameOrigin(currentFrame.origin)
        updateBubblePosition()

        dockWalkLastTick = Date()
        dockWalkPauseUntil = nil

        let timer = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.stepDockWalk()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        dockWalkTimer = timer
    }

    func stopDockWalking() {
        dockGarden.hide()
        dockWalkLastTick = nil
        dockWalkTimer?.invalidate()
        dockWalkTimer = nil
        dockWalkPauseUntil = nil
        dockWalkCurrentX = nil
        // Khi tắt: Dừng ngay tại vị trí hiện tại và lưu tọa độ
        if let origin = mascotWindow?.frame.origin {
            UserDefaults.standard.set(Double(origin.x), forKey: "FloatingMascotX")
            UserDefaults.standard.set(Double(origin.y), forKey: "FloatingMascotY")
        }
    }

    private func stepDockWalk() {
        let now = Date()
        let delta = min(0.04, max(0.001, now.timeIntervalSince(dockWalkLastTick ?? now)))
        dockWalkLastTick = now

        let shouldShowGarden = isFloatingMascotVisible && isDockWalkEnabled && mascotStyle == "sprite" &&
            !running && !busy && !isMascotHovered && !isBubbleHovered && !isBubbleVisible &&
            MascotIdlePolicy.systemIdleSeconds >= MascotIdlePolicy.idleThreshold && NSEvent.pressedMouseButtons == 0
        if let window = mascotWindow {
            dockGarden.update(screen: getDockScreen(for: window), mascot: window, visible: shouldShowGarden)
        } else { dockGarden.hide() }
        // Walk and scenery pause as soon as the user resumes interaction.
        guard !running, !busy, !isMascotHovered, !isBubbleHovered, !isBubbleVisible,
              MascotIdlePolicy.systemIdleSeconds >= MascotIdlePolicy.idleThreshold,
              NSEvent.pressedMouseButtons == 0, let window = mascotWindow else { return }

        // Nếu đang tạm dừng nghỉ chân quay người ở 2 mép màn hình
        if let pauseUntil = dockWalkPauseUntil {
            if now < pauseUntil {
                return
            } else {
                dockWalkPauseUntil = nil
            }
        }

        let screen = getDockScreen(for: window)
        let visible = screen.visibleFrame
        guard visible.width > 200 else { return }

        let minX = visible.minX + 16
        let maxX = visible.maxX - window.frame.width - 16
        guard maxX > minX else { return }

        // Nếu người dùng vừa kéo thả cửa sổ di chuyển đi nơi khác, đồng bộ lại tọa độ
        var currentX = dockWalkCurrentX ?? window.frame.origin.x
        if abs(currentX - window.frame.origin.x) > 24.0 {
            currentX = window.frame.origin.x
        }

        // Tốc độ bước chân tự nhiên: 42 pt/s, giảm tốc êm ái khi sát mép
        let edgeDistance = max(0, min(currentX - minX, maxX - currentX))
        let ramp = min(1.0, max(0.65, edgeDistance / 30.0))
        let stepSpeed = CGFloat(delta) * (42.0 * ramp)

        currentX += dockWalkDirection * stepSpeed

        // Kiểm tra chạm mép phải (chỉ khi đang đi sang phải)
        if currentX >= maxX && dockWalkDirection > 0 {
            currentX = maxX
            dockWalkDirection = -1.0
            dockWalkPauseUntil = Date().addingTimeInterval(1.2) // Dừng 1.2s ngắm nhìn chào trước khi quay lại
        }
        // Kiểm tra chạm mép trái (chỉ khi đang đi sang trái)
        else if currentX <= minX && dockWalkDirection < 0 {
            currentX = minX
            dockWalkDirection = 1.0
            dockWalkPauseUntil = Date().addingTimeInterval(1.2) // Dừng 1.2s ngắm nhìn chào trước khi quay lại
        }

        dockWalkDistance += abs(currentX - (dockWalkCurrentX ?? currentX))
        dockWalkCurrentX = currentX

        var origin = window.frame.origin
        origin.x = round(currentX)
        origin.y = max(visible.minY, screen.frame.minY) + 2 // Neo sát viền Dock
        window.setFrameOrigin(origin)

        if isBubbleVisible {
            updateBubblePosition()
        }
    }

    func hideSpeechBubble() {
        bubbleDismissTask?.cancel()
        bubbleDismissTask = nil
        isBubbleVisible = false
        isBubbleLoading = false
        mascotBubbleWindow?.orderOut(nil)
    }

    func updateBubblePosition() {
        guard let mascotWin = mascotWindow, let bubbleWin = mascotBubbleWindow, isBubbleVisible else { return }
        let mascotFrame = mascotWin.frame
        let targetScreen = mascotWin.screen ?? NSScreen.main ?? NSScreen()
        let visible = targetScreen.visibleFrame

        let bubbleW: CGFloat = 280
        let bubbleH: CGFloat = 135

        var bubbleX = mascotFrame.midX - (bubbleW / 2)
        bubbleX = max(visible.minX + 10, min(visible.maxX - bubbleW - 10, bubbleX))

        var bubbleY = mascotFrame.maxY - 22
        if bubbleY + bubbleH > visible.maxY - 10 {
            bubbleY = mascotFrame.minY - bubbleH - 2
        }

        bubbleWin.setFrame(NSRect(x: bubbleX, y: bubbleY, width: bubbleW, height: bubbleH), display: true)
    }

    func presentBubbleWindow() {
        guard let mascotWin = mascotWindow else { return }
        let mascotFrame = mascotWin.frame
        let targetScreen = mascotWin.screen ?? NSScreen.main ?? NSScreen()
        let visible = targetScreen.visibleFrame

        let bubbleW: CGFloat = 280
        let bubbleH: CGFloat = 135

        var bubbleX = mascotFrame.midX - (bubbleW / 2)
        bubbleX = max(visible.minX + 10, min(visible.maxX - bubbleW - 10, bubbleX))

        var bubbleY = mascotFrame.maxY - 22
        if bubbleY + bubbleH > visible.maxY - 10 {
            bubbleY = mascotFrame.minY - bubbleH - 2
        }

        let bubbleRect = NSRect(x: bubbleX, y: bubbleY, width: bubbleW, height: bubbleH)

        if let bubbleWin = mascotBubbleWindow {
            bubbleWin.setFrame(bubbleRect, display: true)
            bubbleWin.orderFrontRegardless()
        } else {
            let panel = NSPanel(
                contentRect: bubbleRect,
                styleMask: [.borderless, .nonactivatingPanel],
                backing: .buffered,
                defer: false
            )
            panel.isFloatingPanel = true
            panel.level = .floating
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            panel.backgroundColor = .clear
            panel.isOpaque = false
            panel.hasShadow = false
            panel.hidesOnDeactivate = false
            panel.isReleasedWhenClosed = false
            panel.contentView = MascotHostingView(rootView: MascotBubbleView(model: self))
            mascotBubbleWindow = panel
            panel.orderFrontRegardless()
        }
    }

    // Main Window lifecycle management
    weak var mainWindow: NSWindow?
    private let windowDelegate = MainWindowDelegate()

    func attachMainWindow(_ window: NSWindow) {
        self.mainWindow = window
        window.isReleasedWhenClosed = false
        window.delegate = windowDelegate
    }

    func showMainWindow() {
        NSApp.activate(ignoringOtherApps: true)
        if let mainWindow {
            mainWindow.makeKeyAndOrderFront(nil)
            return
        }
        if let window = NSApp.windows.first(where: { !($0 is NSPanel) && $0.title != "Phụ đề trực tiếp" }) {
            mainWindow = window
            window.isReleasedWhenClosed = false
            window.delegate = windowDelegate
            window.makeKeyAndOrderFront(nil)
        }
    }
}

// MARK: - Main Window Management & Lifecycle

final class MainWindowDelegate: NSObject, NSWindowDelegate {
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        sender.orderOut(nil)
        return false // Hide the window instead of destroying it
    }
}

struct WindowAccessor: NSViewRepresentable {
    let callback: (NSWindow) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            if let window = view.window {
                callback(window)
            }
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        if let window = nsView.window {
            callback(window)
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    var model: MeetingModel? {
        didSet {
            if let model {
                MenuBarManager.shared.setup(with: model)
            }
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return false // Keep running in background with Menubar Tray Icon
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        model?.showMainWindow()
        return true
    }
}

// MARK: - Menu Bar Status Item (Tray Icon) Manager

@MainActor
final class MenuBarManager: NSObject, NSMenuDelegate {
    static let shared = MenuBarManager()
    private var statusItem: NSStatusItem?
    private weak var model: MeetingModel?
    private var cancellables = Set<AnyCancellable>()

    func setup(with model: MeetingModel) {
        self.model = model

        if statusItem == nil {
            let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
            if let button = item.button {
                button.imagePosition = .imageOnly
                button.toolTip = "TransTools - Phiên dịch cuộc họp & Trợ lý Chip Chip"
            }
            let menu = NSMenu()
            menu.delegate = self
            item.menu = menu
            self.statusItem = item
        }

        cancellables.removeAll()
        model.$running
            .receive(on: RunLoop.main)
            .sink { [weak self] isRunning in
                self?.updateStatusIcon(isRunning: isRunning)
            }
            .store(in: &cancellables)

        updateStatusIcon(isRunning: model.running)
    }

    func updateStatusIcon(isRunning: Bool) {
        guard let button = statusItem?.button else { return }
        if isRunning {
            let config = NSImage.SymbolConfiguration(paletteColors: [NSColor.systemGreen])
            if let liveImg = NSImage(systemSymbolName: "captions.bubble.fill", accessibilityDescription: "TransTools (Đang dịch)")?.withSymbolConfiguration(config) {
                liveImg.isTemplate = false
                button.image = liveImg
            } else {
                let img = NSImage(systemSymbolName: "captions.bubble.fill", accessibilityDescription: "TransTools (Đang dịch)")
                img?.isTemplate = true
                button.image = img
            }
            button.toolTip = "TransTools: Đang nghe & phiên dịch cuộc họp (LIVE) 🟢"
        } else {
            let img = NSImage(systemSymbolName: "captions.bubble", accessibilityDescription: "TransTools")
            img?.isTemplate = true
            button.image = img
            button.toolTip = "TransTools - Phiên dịch cuộc họp & Trợ lý Chip Chip"
        }
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        guard let model = self.model else { return }

        // 1. Header: Live Status
        let statusTitle = model.running ? "🟢 TransTools • Đang dịch trực tiếp" : "⚪ TransTools • Sẵn sàng"
        let headerItem = NSMenuItem(title: statusTitle, action: nil, keyEquivalent: "")
        headerItem.isEnabled = false
        menu.addItem(headerItem)

        if model.running {
            let sourceDesc = "   Nguồn: \(model.currentSourceName())"
            let sourceItem = NSMenuItem(title: sourceDesc, action: nil, keyEquivalent: "")
            sourceItem.isEnabled = false
            menu.addItem(sourceItem)
        }

        menu.addItem(NSMenuItem.separator())

        // 2. Open / Hide Main Window
        let isWindowVisible = model.mainWindow?.isVisible ?? false
        let windowTitle = isWindowVisible ? "Ẩn bảng điều khiển chính" : "Mở bảng điều khiển chính"
        let windowItem = NSMenuItem(title: windowTitle, action: #selector(toggleMainWindowAction), keyEquivalent: "m")
        windowItem.target = self
        if let img = NSImage(systemSymbolName: "macwindow", accessibilityDescription: nil) {
            windowItem.image = img
        }
        menu.addItem(windowItem)

        menu.addItem(NSMenuItem.separator())

        // 3. Start / Stop Recording & Translation
        let runTitle = model.running ? "Tạm dừng phiên dịch" : "Bắt đầu phiên dịch"
        let runIconName = model.running ? "stop.circle.fill" : "play.circle.fill"
        let runItem = NSMenuItem(title: runTitle, action: #selector(toggleRunningAction), keyEquivalent: "r")
        runItem.target = self
        if let img = NSImage(systemSymbolName: runIconName, accessibilityDescription: nil) {
            runItem.image = img
        }
        menu.addItem(runItem)

        // 4. Subtitle Overlay HUD toggle
        let isOverlayOn = model.isOverlayVisible
        let overlayItem = NSMenuItem(title: "Phụ đề nổi (HUD)", action: #selector(toggleOverlayAction), keyEquivalent: "h")
        overlayItem.target = self
        overlayItem.state = isOverlayOn ? .on : .off
        if let img = NSImage(systemSymbolName: "pip.enter", accessibilityDescription: nil) {
            overlayItem.image = img
        }
        menu.addItem(overlayItem)

        // 4b. Chế độ hiển thị phụ đề (Song ngữ, Gốc CC 0ms, Bản dịch)
        let modeMenu = NSMenu(title: "Chế độ phụ đề")
        for mode in SubtitleDisplayMode.allCases {
            let item = NSMenuItem(title: mode.title, action: #selector(setSubtitleModeAction(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = mode
            item.state = (model.subtitleMode == mode) ? .on : .off
            if let img = NSImage(systemSymbolName: mode.icon, accessibilityDescription: nil) {
                item.image = img
            }
            modeMenu.addItem(item)
        }
        let modeItem = NSMenuItem(title: "Chế độ: \(model.subtitleMode.shortTitle)", action: nil, keyEquivalent: "")
        modeItem.submenu = modeMenu
        if let img = NSImage(systemSymbolName: model.subtitleMode.icon, accessibilityDescription: nil) {
            modeItem.image = img
        }
        menu.addItem(modeItem)

        // 5. Chip Chip Companion toggle
        let isMimoOn = model.isFloatingMascotVisible
        let mimoItem = NSMenuItem(title: "Trợ lý Chip Chip", action: #selector(toggleMimoAction), keyEquivalent: "")
        mimoItem.target = self
        mimoItem.state = isMimoOn ? .on : .off
        if let img = NSImage(systemSymbolName: "sparkles.tv", accessibilityDescription: nil) {
            mimoItem.image = img
        }
        menu.addItem(mimoItem)

        if isMimoOn {
            let snapItem = NSMenuItem(title: "   Đưa Chip Chip về góc màn hình", action: #selector(snapMimoAction), keyEquivalent: "")
            snapItem.target = self
            if let img = NSImage(systemSymbolName: "arrow.down.forward.and.arrow.up.backward", accessibilityDescription: nil) {
                snapItem.image = img
            }
            menu.addItem(snapItem)
        }

        menu.addItem(NSMenuItem.separator())

        // 6. Sổ tay / Lịch sử cuộc họp
        let sessionCount = model.sessions.count
        let notebookTitle = sessionCount > 0 ? "Sổ tay cuộc họp (\(sessionCount) phiên)" : "Sổ tay cuộc họp"
        let notebookItem = NSMenuItem(title: notebookTitle, action: #selector(openNotebookAction), keyEquivalent: "n")
        notebookItem.target = self
        if let img = NSImage(systemSymbolName: "book.closed", accessibilityDescription: nil) {
            notebookItem.image = img
        }
        menu.addItem(notebookItem)

        // 7. Cài đặt & Cấu hình AI
        let settingsItem = NSMenuItem(title: "Cài đặt & Cấu hình AI...", action: #selector(openSettingsAction), keyEquivalent: ",")
        settingsItem.target = self
        if let img = NSImage(systemSymbolName: "gearshape", accessibilityDescription: nil) {
            settingsItem.image = img
        }
        menu.addItem(settingsItem)

        // 8. Kiểm tra bản cập nhật mới
        let updateItem = NSMenuItem(title: "Kiểm tra bản cập nhật mới...", action: #selector(checkForUpdatesAction), keyEquivalent: "u")
        updateItem.target = self
        if let img = NSImage(systemSymbolName: "arrow.triangle.2.circlepath", accessibilityDescription: nil) {
            updateItem.image = img
        }
        menu.addItem(updateItem)

        // 9. Giới thiệu TransTools
        let aboutItem = NSMenuItem(title: "Giới thiệu TransTools...", action: #selector(openAboutAction), keyEquivalent: "")
        aboutItem.target = self
        if let img = NSImage(systemSymbolName: "info.circle", accessibilityDescription: nil) {
            aboutItem.image = img
        }
        menu.addItem(aboutItem)

        menu.addItem(NSMenuItem.separator())

        // 9. Thoát ứng dụng
        let quitItem = NSMenuItem(title: "Thoát TransTools", action: #selector(quitAppAction), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)
    }

    @objc private func toggleMainWindowAction() {
        guard let model else { return }
        if let win = model.mainWindow, win.isVisible {
            win.orderOut(nil)
        } else {
            model.showMainWindow()
        }
    }

    @objc private func toggleRunningAction() {
        guard let model else { return }
        Task { @MainActor in
            if model.running {
                await model.stop()
            } else {
                await model.start()
            }
        }
    }

    @objc private func toggleOverlayAction() {
        model?.toggleOverlay()
    }

    @objc private func setSubtitleModeAction(_ sender: NSMenuItem) {
        guard let mode = sender.representedObject as? SubtitleDisplayMode else { return }
        model?.subtitleMode = mode
    }

    @objc private func toggleMimoAction() {
        model?.toggleFloatingMascot()
    }

    @objc private func snapMimoAction() {
        model?.snapMascotToConvenientPosition()
    }

    @objc private func openNotebookAction() {
        guard let model else { return }
        model.selectedDashboardTab = 1
        model.showMainWindow()
    }

    @objc private func openSettingsAction() {
        guard let model else { return }
        model.showSettingsSheet = true
        model.showMainWindow()
    }

    @objc private func openAboutAction() {
        guard let model else { return }
        model.showAboutSheet = true
        model.showMainWindow()
    }

    @objc private func checkForUpdatesAction() {
        AppUpdater.shared.showUpdateSheet = true
        AppUpdater.shared.checkForUpdates(userInitiated: true)
        model?.showMainWindow()
    }

    @objc private func quitAppAction() {
        NSApp.terminate(nil)
    }
}

// MARK: - Native Draggable Subtitle Window Hosting View

final class OverlayHostingView<Content: View>: NSHostingView<Content> {
    private var mouseDownLocation: NSPoint?

    override var mouseDownCanMoveWindow: Bool { true }

    override func mouseDown(with event: NSEvent) {
        mouseDownLocation = event.locationInWindow
        super.mouseDown(with: event)
    }

    override func mouseDragged(with event: NSEvent) {
        guard let window = self.window else {
            super.mouseDragged(with: event)
            return
        }
        if let start = mouseDownLocation {
            let dx = abs(event.locationInWindow.x - start.x)
            let dy = abs(event.locationInWindow.y - start.y)
            if dx > 2 || dy > 2 {
                window.performDrag(with: event)
                return
            }
        }
        super.mouseDragged(with: event)
    }
}

struct DraggableWindowArea: NSViewRepresentable {
    func makeNSView(context: Context) -> DraggableNSView {
        DraggableNSView()
    }
    func updateNSView(_ nsView: DraggableNSView, context: Context) {}
}

final class DraggableNSView: NSView {
    override var mouseDownCanMoveWindow: Bool { true }

    override func mouseDragged(with event: NSEvent) {
        window?.performDrag(with: event)
    }

    override func resetCursorRects() {
        super.resetCursorRects()
        addCursorRect(bounds, cursor: .openHand)
    }
}

#if canImport(Translation)
@available(macOS 15.0, *)
private struct AppleTranslationContainer<Content: View>: View {
    let source: AppLanguage
    let target: AppLanguage
    @ViewBuilder let content: () -> Content

    @State private var forwardConfig: TranslationSession.Configuration?
    @State private var reverseConfig: TranslationSession.Configuration?
    @State private var viToEnConfig: TranslationSession.Configuration?
    @State private var enToViConfig: TranslationSession.Configuration?

    var body: some View {
        content()
            .translationTask(forwardConfig) { session in
                AppleNativeTranslator.register(session, from: source, to: target)
                AppleNativeTranslator.session = session
            }
            .translationTask(reverseConfig) { session in
                AppleNativeTranslator.register(session, from: target, to: source)
            }
            .translationTask(viToEnConfig) { session in
                AppleNativeTranslator.register(session, from: .vietnamese, to: .english)
            }
            .translationTask(enToViConfig) { session in
                AppleNativeTranslator.register(session, from: .english, to: .vietnamese)
            }
            .onAppear {
                updateConfig()
            }
            .onChange(of: source) { _, _ in updateConfig() }
            .onChange(of: target) { _, _ in updateConfig() }
    }

    private func updateConfig() {
        forwardConfig = TranslationSession.Configuration(
            source: Locale.Language(identifier: source.appleLanguageCode),
            target: Locale.Language(identifier: target.appleLanguageCode)
        )
        reverseConfig = TranslationSession.Configuration(
            source: Locale.Language(identifier: target.appleLanguageCode),
            target: Locale.Language(identifier: source.appleLanguageCode)
        )
        viToEnConfig = TranslationSession.Configuration(
            source: Locale.Language(identifier: AppLanguage.vietnamese.appleLanguageCode),
            target: Locale.Language(identifier: AppLanguage.english.appleLanguageCode)
        )
        enToViConfig = TranslationSession.Configuration(
            source: Locale.Language(identifier: AppLanguage.english.appleLanguageCode),
            target: Locale.Language(identifier: AppLanguage.vietnamese.appleLanguageCode)
        )
    }
}
#endif

extension View {
    @ViewBuilder
    func enableAppleTranslationSession(source: AppLanguage = .english, target: AppLanguage = .vietnamese) -> some View {
        #if canImport(Translation)
        if #available(macOS 15.0, *) {
            AppleTranslationContainer(source: source, target: target) { self }
        } else {
            self
        }
        #else
        self
        #endif
    }
}

// MARK: - Modern Subtitle Overlay (Floating HUD - Adaptive Dark/Light & Compact)

struct OverlayView: View {
    @ObservedObject var model: MeetingModel
    @ObservedObject private var tts = TTSService.shared
    @Environment(\.colorScheme) private var colorScheme
    @State private var copiedEffect = false
    @State private var hoveredRowID: UUID?
    @State private var copiedReplyText = ""
    @AppStorage("SubtitleFontSize") private var fontSize: Double = 15.0

    private var isDark: Bool {
        colorScheme == .dark
    }

    private let availableFontSizes: [Double] = [13.0, 15.0, 18.0, 21.0]

    private func cycleFontSize() {
        if let idx = availableFontSizes.firstIndex(of: fontSize) {
            let nextIdx = (idx + 1) % availableFontSizes.count
            fontSize = availableFontSizes[nextIdx]
        } else {
            fontSize = 15.0
        }
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            // Adaptive Frosted Glass Background (Obsidian in Dark, Pearl White in Light)
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(
                    isDark
                        ? Color(red: 0.10, green: 0.12, blue: 0.16).opacity(0.88)
                        : Color.white.opacity(0.88)
                )
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(.ultraThinMaterial)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(
                            LinearGradient(
                                colors: isDark
                                    ? [Color.white.opacity(0.20), Color.white.opacity(0.05)]
                                    : [Color.black.opacity(0.12), Color.black.opacity(0.04)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1
                        )
                )
                .shadow(color: .clear, radius: 0)
                // Background enables full-surface native drag
                .background(DraggableWindowArea())

            VStack(alignment: .leading, spacing: 5) {
                // Top HUD Bar: Status Badge + Drag Pill + Quick Actions
                HStack(spacing: 7) {
                    // Live Status Dot & Provider
                    HStack(spacing: 5) {
                        Circle()
                            .fill(model.running ? Color.green : Color.orange)
                            .frame(width: 6, height: 6)

                        Text(model.running ? "TRỰC TIẾP" : "TẠM DỪNG")
                            .font(.system(size: 9, weight: .bold, design: .rounded))
                            .foregroundStyle(
                                model.running
                                    ? (isDark ? Color.green : Color(red: 0.05, green: 0.55, blue: 0.25))
                                    : Color.orange
                            )

                        let engineText = (model.provider == .apple || model.provider == .free)
                            ? model.provider.shortName
                            : "\(model.provider.shortName) (\(model.modelName))"
                        Text("• \(engineText)")
                            .font(.system(size: 9, weight: .medium))
                            .foregroundStyle(isDark ? Color.white.opacity(0.55) : Color.black.opacity(0.55))

                        Text("• \(model.domainSpecialty.shortName)")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(TransToolsTheme.accent)
                    }
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2.5)
                    .background(
                        Capsule()
                            .fill(isDark ? Color.white.opacity(0.08) : Color.black.opacity(0.06))
                    )

                    Spacer()

                    Menu {
                        Button("Phía trên (Top)") { model.positionOverlay(atTop: true) }
                        Button("Phía dưới (Bottom)") { model.positionOverlay(atTop: false) }
                    } label: { Image(systemName: "arrow.up.arrow.down") }
                    .menuStyle(.borderlessButton).fixedSize().help("Vị trí phụ đề nổi")

                    // Center Drag Indicator Pill with native drag handler
                    ZStack {
                        DraggableWindowArea()
                            .frame(width: 44, height: 16)

                        Capsule()
                            .fill(isDark ? Color.white.opacity(0.28) : Color.black.opacity(0.22))
                            .frame(width: 28, height: 3.5)
                    }
                    .help("Kéo bất kỳ đâu trên thanh để di chuyển vị trí phụ đề")

                    Spacer()

                    // AI Suggest Reply Toggle / Refresh Button
                    Button {
                        model.generateSuggestions()
                    } label: {
                        HStack(spacing: 3) {
                            Image(systemName: model.isGeneratingSuggestions ? "sparkle.magnifyingglass" : "sparkles")
                                .font(.system(size: 9, weight: .bold))
                            if !model.suggestedReplies.isEmpty {
                                Text("\(model.suggestedReplies.count)")
                                    .font(.system(size: 8, weight: .bold))
                            }
                        }
                        .foregroundStyle(TransToolsTheme.accent)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(
                            RoundedRectangle(cornerRadius: 4, style: .continuous)
                                .fill(TransToolsTheme.accent.opacity(0.12))
                        )
                    }
                    .buttonStyle(.plain)
                    .help("AI gợi ý câu trả lời tiếng Anh cho hội thoại này")

                    // Subtitle Mode Cycle Button (Song ngữ ⇄ CC 0ms ⇄ Bản dịch)
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            switch model.subtitleMode {
                            case .bilingual:
                                model.subtitleMode = .originalOnly
                            case .originalOnly:
                                model.subtitleMode = .translationOnly
                            case .translationOnly:
                                model.subtitleMode = .bilingual
                            }
                        }
                    } label: {
                        HStack(spacing: 3) {
                            Image(systemName: model.subtitleMode.icon)
                                .font(.system(size: 9, weight: .bold))
                            Text(model.subtitleMode.shortTitle)
                                .font(.system(size: 8.5, weight: .bold))
                        }
                        .foregroundStyle(model.subtitleMode == .originalOnly ? Color.green : (isDark ? Color.white.opacity(0.85) : Color.black.opacity(0.75)))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(
                            RoundedRectangle(cornerRadius: 4, style: .continuous)
                                .fill(model.subtitleMode == .originalOnly ? Color.green.opacity(0.15) : (isDark ? Color.white.opacity(0.08) : Color.black.opacity(0.06)))
                        )
                    }
                    .buttonStyle(.plain)
                    .help("Chuyển chế độ: Song ngữ ➔ Chỉ tiếng gốc (CC) ➔ Chỉ bản dịch")

                    // Earphone TTS Toggle Button
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            tts.isAutoTTSEnabled.toggle()
                        }
                    } label: {
                        HStack(spacing: 3) {
                            Image(systemName: tts.isAutoTTSEnabled ? "headphones" : "headphones")
                                .font(.system(size: 9, weight: .bold))
                            if tts.isAutoTTSEnabled {
                                Circle()
                                    .fill(Color.green)
                                    .frame(width: 4, height: 4)
                            }
                        }
                        .foregroundStyle(tts.isAutoTTSEnabled ? TransToolsTheme.accent : (isDark ? Color.white.opacity(0.70) : Color.black.opacity(0.60)))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(
                            RoundedRectangle(cornerRadius: 4, style: .continuous)
                                .fill(tts.isAutoTTSEnabled ? TransToolsTheme.accent.opacity(0.15) : (isDark ? Color.white.opacity(0.08) : Color.black.opacity(0.06)))
                        )
                    }
                    .buttonStyle(.plain)
                    .help(tts.isAutoTTSEnabled ? "Tai nghe: Đang BẬT phiên dịch viên trực tiếp (\(tts.autoTarget.shortTitle))" : "Bật phát âm qua tai nghe (Phiên dịch viên trực tiếp)")

                    // Font Size Cycle Button
                    Button {
                        cycleFontSize()
                    } label: {
                        HStack(spacing: 1.5) {
                            Text("A")
                                .font(.system(size: 11, weight: .bold))
                            Text("\(Int(fontSize))")
                                .font(.system(size: 8, weight: .semibold, design: .monospaced))
                        }
                        .foregroundStyle(isDark ? Color.white.opacity(0.70) : Color.black.opacity(0.60))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(
                            RoundedRectangle(cornerRadius: 4, style: .continuous)
                                .fill(isDark ? Color.white.opacity(0.08) : Color.black.opacity(0.06))
                        )
                    }
                    .buttonStyle(.plain)
                    .help("Đổi cỡ chữ phụ đề (13, 15, 18, 21)")

                    // Quick Speak Button (Nghe câu đang hiển thị)
                    if let row = model.captions.last, (!row.vietnamese.isEmpty || !row.original.isEmpty) {
                        let textToSpeak = (model.subtitleMode == .originalOnly || row.vietnamese.isEmpty) ? row.original : row.vietnamese
                        let langToSpeak = (model.subtitleMode == .originalOnly || row.vietnamese.isEmpty) ? model.sourceLanguage : model.targetLanguage
                        let isSpeakingThis = tts.isSpeaking && tts.currentlySpeakingText == textToSpeak

                        Button {
                            if isSpeakingThis {
                                tts.stop()
                            } else {
                                tts.speak(id: row.id, text: textToSpeak, language: langToSpeak)
                            }
                        } label: {
                            Image(systemName: isSpeakingThis ? "speaker.wave.3.fill" : "speaker.wave.2")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(isSpeakingThis ? TransToolsTheme.accent : (isDark ? Color.white.opacity(0.7) : Color.black.opacity(0.65)))
                        }
                        .buttonStyle(.plain)
                        .help(isSpeakingThis ? "Dừng đọc" : "Phát âm thanh câu này")
                    }

                    // Quick Copy Button
                    if let row = model.captions.last, (!row.vietnamese.isEmpty || !row.original.isEmpty) {
                        Button {
                            let textToCopy = (model.subtitleMode == .originalOnly || row.vietnamese.isEmpty) ? row.original : row.vietnamese
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(textToCopy, forType: .string)
                            copiedEffect = true
                            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                                copiedEffect = false
                            }
                        } label: {
                            Image(systemName: copiedEffect ? "checkmark" : "doc.on.doc")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(copiedEffect ? Color.green : (isDark ? Color.white.opacity(0.7) : Color.black.opacity(0.65)))
                        }
                        .buttonStyle(.plain)
                        .help(model.subtitleMode == .originalOnly ? "Sao chép câu gốc" : "Sao chép bản dịch hiện tại")
                    }

                    // Clear Subtitles Button
                    if !model.captions.isEmpty {
                        Button {
                            model.captions.removeAll()
                        } label: {
                            Image(systemName: "trash")
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundStyle(isDark ? Color.white.opacity(0.50) : Color.black.opacity(0.45))
                        }
                        .buttonStyle(.plain)
                        .help("Xóa phụ đề trên màn hình")
                    }

                    // Quick Pause / Play Button
                    Button {
                        Task {
                            if model.running { await model.stop() }
                            else { await model.start() }
                        }
                    } label: {
                        Image(systemName: model.running ? "pause.fill" : "play.fill")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(isDark ? Color.white.opacity(0.75) : Color.black.opacity(0.65))
                    }
                    .buttonStyle(.plain)
                    .help(model.running ? "Tạm dừng" : "Tiếp tục lắng nghe")

                    // Close Subtitle HUD
                    Button {
                        model.hideOverlay()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 12))
                            .foregroundStyle(isDark ? Color.white.opacity(0.50) : Color.black.opacity(0.40))
                    }
                    .buttonStyle(.plain)
                    .help("Ẩn phụ đề nổi")
                }

                // Subtitle Content: Auto-scrolling, multi-line, no text cutting off
                if model.captions.isEmpty {
                    HStack(spacing: 6) {
                        HStack(spacing: 2.5) {
                            ForEach(0..<4) { i in
                                RoundedRectangle(cornerRadius: 1)
                                    .fill(model.running ? Color.green : Color.secondary)
                                    .frame(width: 2.5, height: model.running ? CGFloat(6 + (i % 2) * 5) : 5)
                                    .animation(.easeInOut(duration: 0.4).repeatForever().delay(Double(i) * 0.1), value: model.running)
                            }
                        }
                        Text(model.running ? "Đang lắng nghe âm thanh cuộc họp…" : "Nhấn Bắt đầu trong ứng dụng để nghe.")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(isDark ? Color.white.opacity(0.60) : Color.black.opacity(0.55))
                    }
                    .padding(.vertical, 4)

                    Spacer(minLength: 0)
                } else {
                    ScrollViewReader { proxy in
                        ScrollView(.vertical, showsIndicators: false) {
                            VStack(alignment: .leading, spacing: 5) {
                                // Active sentence: in-flight spoken sentence or most recent sentence
                                let activeRow = (model.running ? model.captions.first(where: { $0.id == model.currentID }) : nil) ?? model.captions.last
                                // Recent completed sentences strictly excluding activeRow to eliminate duplicate rendering & text jump
                                let completedCaptions = Array(model.captions.filter { $0.id != activeRow?.id }.suffix(2))
                                ForEach(completedCaptions) { prev in
                                    VStack(alignment: .leading, spacing: 2) {
                                        if model.subtitleMode != .translationOnly && !prev.original.isEmpty {
                                            Text(prev.original)
                                                .font(.system(size: max(10, fontSize - 4), weight: .regular))
                                                .foregroundStyle(isDark ? Color.white.opacity(0.45) : Color.black.opacity(0.40))
                                                .fixedSize(horizontal: false, vertical: true)
                                        }
                                        if model.subtitleMode != .originalOnly && (!prev.vietnamese.isEmpty || !prev.original.isEmpty) {
                                            Text(prev.vietnamese.isEmpty ? prev.original : prev.vietnamese)
                                                .font(.system(size: max(11, fontSize - 3), weight: .medium, design: .rounded))
                                                .foregroundStyle(isDark ? Color.white.opacity(0.65) : Color.black.opacity(0.60))
                                                .fixedSize(horizontal: false, vertical: true)
                                        }
                                    }
                                    .padding(.bottom, 2)

                                    Divider()
                                        .opacity(isDark ? 0.15 : 0.12)
                                }

                                // Active sentence: full multi-line wrapping without cutoffs
                                if let row = activeRow {
                                    VStack(alignment: .leading, spacing: 3) {
                                        if model.subtitleMode == .originalOnly {
                                            // Real-time Closed Caption (CC - 0ms): Prominent font & primary gradient
                                            if !row.original.isEmpty {
                                                Text(row.original)
                                                    .font(.system(size: fontSize, weight: .bold, design: .rounded))
                                                    .foregroundStyle(
                                                        isDark
                                                            ? LinearGradient(
                                                                colors: [
                                                                    Color(red: 0.35, green: 0.96, blue: 0.85),
                                                                    Color(red: 0.20, green: 0.88, blue: 0.98)
                                                                ],
                                                                startPoint: .topLeading,
                                                                endPoint: .bottomTrailing
                                                            )
                                                            : LinearGradient(
                                                                colors: [
                                                                    Color(red: 0.03, green: 0.50, blue: 0.45),
                                                                    Color(red: 0.02, green: 0.40, blue: 0.68)
                                                                ],
                                                                startPoint: .topLeading,
                                                                endPoint: .bottomTrailing
                                                            )
                                                    )
                                                    .fixedSize(horizontal: false, vertical: true)
                                            }
                                        } else if model.subtitleMode == .translationOnly {
                                            // Translation only
                                            if !row.vietnamese.isEmpty {
                                                Text(row.vietnamese)
                                                    .font(.system(size: fontSize, weight: .bold, design: .rounded))
                                                    .foregroundStyle(
                                                        isDark
                                                            ? LinearGradient(
                                                                colors: [
                                                                    Color(red: 0.35, green: 0.96, blue: 0.85),
                                                                    Color(red: 0.20, green: 0.88, blue: 0.98)
                                                                ],
                                                                startPoint: .topLeading,
                                                                endPoint: .bottomTrailing
                                                            )
                                                            : LinearGradient(
                                                                colors: [
                                                                    Color(red: 0.03, green: 0.50, blue: 0.45),
                                                                    Color(red: 0.02, green: 0.40, blue: 0.68)
                                                                ],
                                                                startPoint: .topLeading,
                                                                endPoint: .bottomTrailing
                                                            )
                                                    )
                                                    .fixedSize(horizontal: false, vertical: true)
                                            } else if !row.original.isEmpty {
                                                HStack(spacing: 5) {
                                                    Text(row.original)
                                                        .font(.system(size: max(11, fontSize - 2), weight: .medium, design: .rounded))
                                                        .italic()
                                                        .foregroundStyle(isDark ? Color.white.opacity(0.65) : Color.black.opacity(0.60))
                                                        .fixedSize(horizontal: false, vertical: true)
                                                    Circle()
                                                        .fill(Color.teal)
                                                        .frame(width: 4, height: 4)
                                                }
                                            }
                                        } else {
                                            // Bilingual: Original (dimmed) + Translation (crystal gradient)
                                            if !row.original.isEmpty {
                                                Text(row.original)
                                                    .font(.system(size: max(11, fontSize - 3), weight: .regular))
                                                    .foregroundStyle(isDark ? Color.white.opacity(0.72) : Color(red: 0.22, green: 0.25, blue: 0.32))
                                                    .fixedSize(horizontal: false, vertical: true)
                                            }

                                            if !row.vietnamese.isEmpty {
                                                Text(row.vietnamese)
                                                    .font(.system(size: fontSize, weight: .bold, design: .rounded))
                                                    .foregroundStyle(
                                                        isDark
                                                            ? LinearGradient(
                                                                colors: [
                                                                    Color(red: 0.35, green: 0.96, blue: 0.85),
                                                                    Color(red: 0.20, green: 0.88, blue: 0.98)
                                                                ],
                                                                startPoint: .topLeading,
                                                                endPoint: .bottomTrailing
                                                            )
                                                            : LinearGradient(
                                                                colors: [
                                                                    Color(red: 0.03, green: 0.50, blue: 0.45),
                                                                    Color(red: 0.02, green: 0.40, blue: 0.68)
                                                                ],
                                                                startPoint: .topLeading,
                                                                endPoint: .bottomTrailing
                                                            )
                                                    )
                                                    .fixedSize(horizontal: false, vertical: true)
                                            } else if !row.original.isEmpty {
                                                HStack(spacing: 5) {
                                                    Circle()
                                                        .fill(Color.teal.opacity(0.8))
                                                        .frame(width: 4, height: 4)
                                                    Text("Đang dịch câu mới…")
                                                        .font(.system(size: max(10, fontSize - 4), weight: .medium, design: .rounded))
                                                        .foregroundStyle(isDark ? Color.white.opacity(0.40) : Color.black.opacity(0.35))
                                                }
                                                .padding(.top, 1)
                                            }
                                        }
                                    }
                                    .padding(.vertical, 2)
                                    .overlay(alignment: .topTrailing) {
                                        if hoveredRowID == row.id {
                                            HStack(spacing: 3) {
                                                if model.subtitleMode != .originalOnly && !row.vietnamese.isEmpty {
                                                    Button {
                                                        NSPasteboard.general.clearContents()
                                                        NSPasteboard.general.setString(row.vietnamese, forType: .string)
                                                        copiedReplyText = "VI"
                                                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { copiedReplyText = "" }
                                                    } label: {
                                                        HStack(spacing: 2) {
                                                            Image(systemName: copiedReplyText == "VI" ? "checkmark" : "doc.on.doc")
                                                            Text(model.targetLanguage.shortName.uppercased())
                                                        }
                                                        .font(.system(size: 8.5, weight: .bold))
                                                        .padding(.horizontal, 5)
                                                        .padding(.vertical, 2)
                                                        .background(isDark ? Color.black.opacity(0.8) : Color.white.opacity(0.9))
                                                        .clipShape(Capsule())
                                                    }
                                                    .buttonStyle(.plain)
                                                    .help("Sao chép bản dịch")
                                                }

                                                if model.subtitleMode != .translationOnly && !row.original.isEmpty {
                                                    Button {
                                                        NSPasteboard.general.clearContents()
                                                        NSPasteboard.general.setString(row.original, forType: .string)
                                                        copiedReplyText = "ORIG"
                                                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { copiedReplyText = "" }
                                                    } label: {
                                                        HStack(spacing: 2) {
                                                            Image(systemName: copiedReplyText == "ORIG" ? "checkmark" : "doc.on.doc")
                                                            Text(model.sourceLanguage.shortName.uppercased())
                                                        }
                                                        .font(.system(size: 8.5, weight: .bold))
                                                        .padding(.horizontal, 5)
                                                        .padding(.vertical, 2)
                                                        .background(isDark ? Color.black.opacity(0.8) : Color.white.opacity(0.9))
                                                        .clipShape(Capsule())
                                                    }
                                                    .buttonStyle(.plain)
                                                    .help("Sao chép câu tiếng gốc")
                                                }

                                                Button {
                                                    model.generateSuggestions(for: row.original)
                                                } label: {
                                                    HStack(spacing: 2) {
                                                        Image(systemName: "sparkles")
                                                        Text("Gợi ý")
                                                    }
                                                    .font(.system(size: 8.5, weight: .bold))
                                                    .foregroundStyle(TransToolsTheme.accent)
                                                    .padding(.horizontal, 5)
                                                    .padding(.vertical, 2)
                                                    .background(isDark ? Color.black.opacity(0.8) : Color.white.opacity(0.9))
                                                    .clipShape(Capsule())
                                                }
                                                .buttonStyle(.plain)
                                                .help("Gợi ý câu trả lời AI cho câu này")
                                            }
                                            .offset(y: -6)
                                        }
                                    }
                                    .onHover { isHover in
                                        hoveredRowID = isHover ? row.id : nil
                                    }
                                }

                                // AI Smart Reply Suggestions Drawer
                                if !model.suggestedReplies.isEmpty {
                                    VStack(alignment: .leading, spacing: 3) {
                                        HStack(spacing: 4) {
                                            Image(systemName: "sparkles")
                                                .font(.system(size: 8, weight: .bold))
                                                .foregroundStyle(TransToolsTheme.accent)
                                            Text("GỢI Ý PHẢN HỒI (BẤM ĐỂ CHÉP):")
                                                .font(.system(size: 8, weight: .bold))
                                                .foregroundStyle(isDark ? Color.white.opacity(0.42) : Color.black.opacity(0.42))
                                            Spacer()
                                        }

                                        ScrollView(.horizontal, showsIndicators: false) {
                                            HStack(spacing: 6) {
                                                ForEach(model.suggestedReplies) { reply in
                                                    Button {
                                                        NSPasteboard.general.clearContents()
                                                        NSPasteboard.general.setString(reply.english, forType: .string)
                                                        copiedReplyText = reply.english
                                                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                                                            if copiedReplyText == reply.english { copiedReplyText = "" }
                                                        }
                                                    } label: {
                                                        HStack(spacing: 4) {
                                                            Text(reply.tone)
                                                                .font(.system(size: 8.5, weight: .bold))
                                                                .foregroundStyle(TransToolsTheme.accent)

                                                            Text(copiedReplyText == reply.english ? "✓ Đã chép!" : reply.english)
                                                                .font(.system(size: 11, weight: .medium))
                                                                .foregroundStyle(isDark ? Color.white.opacity(0.9) : Color.black.opacity(0.85))
                                                                .lineLimit(1)
                                                        }
                                                        .padding(.horizontal, 7)
                                                        .padding(.vertical, 3)
                                                        .background(
                                                            Capsule()
                                                                .fill(isDark ? Color.white.opacity(0.12) : Color.black.opacity(0.06))
                                                        )
                                                    }
                                                    .buttonStyle(.plain)
                                                    .help("\(reply.english) — \(reply.vietnamese)")
                                                }
                                            }
                                        }
                                    }
                                    .padding(.top, 2)
                                }

                                // Invisible bottom anchor to maintain auto-scroll
                                Color.clear
                                    .frame(height: 1)
                                    .id("BOTTOM")
                            }
                            .padding(.horizontal, 1)
                        }
                        .onChange(of: model.captions.count) { _, _ in
                            withAnimation(.easeOut(duration: 0.2)) {
                                proxy.scrollTo("BOTTOM", anchor: .bottom)
                            }
                        }
                        .onChange(of: model.captions.last?.vietnamese) { _, _ in
                            proxy.scrollTo("BOTTOM", anchor: .bottom)
                        }
                    }
                }
            }
            .padding(.horizontal, 13)
            .padding(.vertical, 7)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

            // Subtle corner resize grip indicator
            VStack {
                Spacer()
                HStack {
                    Spacer()
                    Image(systemName: "arrow.up.left.and.arrow.down.right")
                        .font(.system(size: 7, weight: .bold))
                        .foregroundStyle(isDark ? Color.white.opacity(0.20) : Color.black.opacity(0.18))
                        .padding(5)
                        .allowsHitTesting(false)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(4)
        .enableAppleTranslationSession(source: model.sourceLanguage, target: model.targetLanguage)
    }
}

// MARK: - Application Mascot Icon

struct AppLogoView: View {
    let size: CGFloat

    var body: some View {
        if let path = Bundle.main.path(forResource: "AppIcon", ofType: "png"),
           let nsImage = NSImage(contentsOfFile: path) {
            Image(nsImage: nsImage)
                .resizable()
                .scaledToFit()
                .frame(width: size, height: size)
                .shadow(color: .blue.opacity(0.3), radius: size > 40 ? 12 : 4, y: size > 40 ? 6 : 1)
        } else {
            ZStack {
                RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [TransToolsTheme.accent, TransToolsTheme.navy],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: size, height: size)

                Image(systemName: "waveform.badge.mic")
                    .font(.system(size: size * 0.5, weight: .semibold))
                    .foregroundStyle(.white)
            }
        }
    }
}

// MARK: - Mimo Eye Expressions & Winking/Blinking Animations

enum MascotExpression: Int, CaseIterable {
    case winkLeft = 0          // > ‿ •
    case winkRight             // • ‿ <
    case happySmile            // ^ ‿ ^
    case happySquint           // > ‿ <
    case sleeping              // u ‿ u (nhắm ngủ say)
    case loveHeart             // ♥ ‿ ♥ (mắt trái tim ngắm hoa / bướm)
}

struct EyeClosedArc: View {
    let size: CGFloat

    var body: some View {
        Path { path in
            let w = size
            let h = size
            path.move(to: CGPoint(x: w * 0.12, y: h * 0.66))
            path.addQuadCurve(
                to: CGPoint(x: w * 0.88, y: h * 0.66),
                control: CGPoint(x: w * 0.5, y: h * 0.12)
            )
        }
        .stroke(
            LinearGradient(
                colors: [Color(red: 0.4, green: 0.95, blue: 1.0), Color.white],
                startPoint: .leading,
                endPoint: .trailing
            ),
            style: StrokeStyle(lineWidth: max(2.0, size * 0.20), lineCap: .round)
        )
        .shadow(color: Color.cyan.opacity(0.85), radius: 2)
    }
}

struct SleepingEyeView: View {
    let size: CGFloat
    let isLeft: Bool

    var body: some View {
        let w = size * 1.25
        let h = size * 1.22

        ZStack {
            // 1. Pearl-white 3D robotic eyelid that matches Chip Chip's shell and 100% covers the blue eye
            Ellipse()
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0.81, green: 0.84, blue: 0.90), // Top socket depth shadow
                            Color(red: 0.95, green: 0.96, blue: 0.98), // Pearl-white robotic eyelid center
                            Color(red: 0.87, green: 0.90, blue: 0.94)  // Lower eyelid soft shading
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .frame(width: w, height: h)
                .overlay(
                    Ellipse()
                        .stroke(
                            Color(red: 0.72, green: 0.76, blue: 0.84).opacity(0.55),
                            lineWidth: 0.9
                        )
                )
                .shadow(color: Color(red: 0.3, green: 0.35, blue: 0.45).opacity(0.18), radius: 1.5, y: 1)

            // 2. Delicate upper eyelid crease / fold (depth effect)
            Path { path in
                path.move(to: CGPoint(x: w * 0.22, y: h * 0.30))
                path.addQuadCurve(
                    to: CGPoint(x: w * 0.78, y: h * 0.30),
                    control: CGPoint(x: w * 0.50, y: h * 0.22)
                )
            }
            .stroke(
                Color(red: 0.60, green: 0.65, blue: 0.75).opacity(0.35),
                style: StrokeStyle(lineWidth: 1.0, lineCap: .round)
            )

            // 3. Natural soft dark closed eye seam: serene curved seam line (︶)
            Path { path in
                let startY = h * 0.52
                let ctrlY = h * 0.70 // Soft natural resting downward curve (︶)
                path.move(to: CGPoint(x: w * 0.16, y: startY))
                path.addQuadCurve(
                    to: CGPoint(x: w * 0.84, y: startY),
                    control: CGPoint(x: w * 0.50, y: ctrlY)
                )

                // Delicate soft eyelashes at outer corner
                if isLeft {
                    path.move(to: CGPoint(x: w * 0.24, y: startY + 0.8))
                    path.addLine(to: CGPoint(x: w * 0.10, y: startY - 2.8))
                    path.move(to: CGPoint(x: w * 0.30, y: startY + 2.0))
                    path.addLine(to: CGPoint(x: w * 0.18, y: startY - 1.2))
                } else {
                    path.move(to: CGPoint(x: w * 0.76, y: startY + 0.8))
                    path.addLine(to: CGPoint(x: w * 0.90, y: startY - 2.8))
                    path.move(to: CGPoint(x: w * 0.70, y: startY + 2.0))
                    path.addLine(to: CGPoint(x: w * 0.82, y: startY - 1.2))
                }
            }
            .stroke(
                LinearGradient(
                    colors: [
                        Color(red: 0.22, green: 0.25, blue: 0.34),
                        Color(red: 0.28, green: 0.32, blue: 0.42)
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                ),
                style: StrokeStyle(lineWidth: max(1.8, size * 0.15), lineCap: .round, lineJoin: .round)
            )

            // 4. Soft gentle blush beneath the closed eyelid
            Ellipse()
                .fill(
                    RadialGradient(
                        colors: [
                            Color(red: 1.0, green: 0.45, blue: 0.60).opacity(0.40),
                            Color.clear
                        ],
                        center: .center,
                        startRadius: 0,
                        endRadius: w * 0.3
                    )
                )
                .frame(width: w * 0.65, height: h * 0.30)
                .offset(y: h * 0.30)
        }
        .frame(width: w, height: h)
    }
}

struct EyeHeartTwinkle: View {
    let size: CGFloat

    var body: some View {
        Image(systemName: "heart.fill")
            .font(.system(size: size * 0.70, weight: .bold))
            .foregroundStyle(
                LinearGradient(colors: [Color(red: 1.0, green: 0.4, blue: 0.7), Color.white], startPoint: .top, endPoint: .bottom)
            )
            .shadow(color: Color.pink.opacity(0.85), radius: 2)
    }
}

struct EyeSquintAngle: View {
    let size: CGFloat
    let isLeft: Bool

    var body: some View {
        Path { path in
            let w = size
            let h = size
            if isLeft {
                path.move(to: CGPoint(x: w * 0.2, y: h * 0.25))
                path.addLine(to: CGPoint(x: w * 0.8, y: h * 0.50))
                path.addLine(to: CGPoint(x: w * 0.2, y: h * 0.75))
            } else {
                path.move(to: CGPoint(x: w * 0.8, y: h * 0.25))
                path.addLine(to: CGPoint(x: w * 0.2, y: h * 0.50))
                path.addLine(to: CGPoint(x: w * 0.8, y: h * 0.75))
            }
        }
        .stroke(
            LinearGradient(
                colors: [Color(red: 0.4, green: 0.95, blue: 1.0), Color.white],
                startPoint: .top,
                endPoint: .bottom
            ),
            style: StrokeStyle(lineWidth: max(2.0, size * 0.20), lineCap: .round, lineJoin: .round)
        )
        .shadow(color: Color.cyan.opacity(0.85), radius: 2)
    }
}

struct EyeOpenTwinkle: View {
    let size: CGFloat

    var body: some View {
        ZStack {
            Image(systemName: "sparkle")
                .font(.system(size: size * 0.65, weight: .black))
                .foregroundStyle(
                    LinearGradient(colors: [Color.white, Color(red: 0.6, green: 0.95, blue: 1.0)], startPoint: .top, endPoint: .bottom)
                )
                .shadow(color: Color.cyan, radius: 2)
        }
    }
}

private struct EyeContainer<Content: View>: View {
    let size: CGFloat
    @ViewBuilder let content: () -> Content

    var body: some View {
        ZStack {
            Circle()
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0.10, green: 0.15, blue: 0.28),
                            Color(red: 0.05, green: 0.09, blue: 0.18)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .overlay(Circle().stroke(Color.cyan.opacity(0.35), lineWidth: 0.8))

            content()
        }
        .frame(width: size, height: size)
    }
}

struct MascotFacialExpressionOverlay: View {
    let size: CGFloat
    let expression: MascotExpression
    var gazeOffset: CGSize = .zero

    var body: some View {
        let w = size * (621.0 / 783.0)
        let h = size
        let eyeD = h * 0.165
        let leftEyeCenter = CGPoint(x: w * 0.362 + gazeOffset.width, y: h * 0.408 + gazeOffset.height)
        let rightEyeCenter = CGPoint(x: w * 0.638 + gazeOffset.width, y: h * 0.408 + gazeOffset.height)
        let leftCheekCenter = CGPoint(x: w * 0.245, y: h * 0.495)
        let rightCheekCenter = CGPoint(x: w * 0.755, y: h * 0.495)
        let cheekW = h * 0.13
        let cheekH = h * 0.055

        ZStack {
            // 1. Left Eye
            if expression == .sleeping {
                SleepingEyeView(size: eyeD, isLeft: true)
                    .position(leftEyeCenter)
            } else {
                EyeContainer(size: eyeD) {
                    switch expression {
                    case .happySmile:
                        EyeClosedArc(size: eyeD)
                    case .winkLeft:
                        EyeClosedArc(size: eyeD)
                    case .winkRight:
                        EyeOpenTwinkle(size: eyeD)
                    case .happySquint:
                        EyeSquintAngle(size: eyeD, isLeft: true)
                    case .sleeping:
                        EmptyView()
                    case .loveHeart:
                        EyeHeartTwinkle(size: eyeD)
                    }
                }
                .position(leftEyeCenter)
            }

            // 2. Right Eye
            if expression == .sleeping {
                SleepingEyeView(size: eyeD, isLeft: false)
                    .position(rightEyeCenter)
            } else {
                EyeContainer(size: eyeD) {
                    switch expression {
                    case .happySmile:
                        EyeClosedArc(size: eyeD)
                    case .winkLeft:
                        EyeOpenTwinkle(size: eyeD)
                    case .winkRight:
                        EyeClosedArc(size: eyeD)
                    case .happySquint:
                        EyeSquintAngle(size: eyeD, isLeft: false)
                    case .sleeping:
                        EmptyView()
                    case .loveHeart:
                        EyeHeartTwinkle(size: eyeD)
                    }
                }
                .position(rightEyeCenter)
            }

            // 3. Cheeks (Soft cute blush)
            Ellipse()
                .fill(RadialGradient(colors: [Color(red: 1.0, green: 0.4, blue: 0.6).opacity(0.55), Color.clear], center: .center, startRadius: 0, endRadius: cheekW * 0.5))
                .frame(width: cheekW, height: cheekH)
                .position(leftCheekCenter)

            Ellipse()
                .fill(RadialGradient(colors: [Color(red: 1.0, green: 0.4, blue: 0.6).opacity(0.55), Color.clear], center: .center, startRadius: 0, endRadius: cheekW * 0.5))
                .frame(width: cheekW, height: cheekH)
                .position(rightCheekCenter)
        }
        .frame(width: w, height: h)
    }
}

struct AnimatedMascot3DView: View {
    let size: CGFloat
    let legSwing: Double

    var body: some View {
        let w = size * (621.0 / 783.0)
        let h = size
        let legW = size * (110.0 / 783.0)
        let legH = size * (125.0 / 783.0)
        let leftLegOffsetX = size * (-65.5 / 783.0)
        let rightLegOffsetX = size * (67.5 / 783.0)
        let legOffsetY = size * (319.0 / 783.0)

        let leftAngle = legSwing
        let rightAngle = -legSwing

        let leftLift = (leftAngle > 0 ? CGFloat(abs(sin(leftAngle * .pi / 180.0))) * (size * 0.038) : 0)
        let rightLift = (rightAngle > 0 ? CGFloat(abs(sin(rightAngle * .pi / 180.0))) * (size * 0.038) : 0)

        ZStack {
            // 1. Left Leg (behind hip)
            if let legPath = Bundle.main.path(forResource: "MascotLegLeft", ofType: "png"),
               let legImg = NSImage(contentsOfFile: legPath) {
                Image(nsImage: legImg)
                    .resizable()
                    .scaledToFit()
                    .frame(width: legW, height: legH)
                    .rotationEffect(.degrees(leftAngle), anchor: UnitPoint(x: 0.65, y: 0.15))
                    .offset(x: leftLegOffsetX, y: legOffsetY - leftLift)
            }

            // 2. Right Leg
            if let legPath = Bundle.main.path(forResource: "MascotLegRight", ofType: "png"),
               let legImg = NSImage(contentsOfFile: legPath) {
                Image(nsImage: legImg)
                    .resizable()
                    .scaledToFit()
                    .frame(width: legW, height: legH)
                    .rotationEffect(.degrees(rightAngle), anchor: UnitPoint(x: 0.35, y: 0.15))
                    .offset(x: rightLegOffsetX, y: legOffsetY - rightLift)
            }

            // 3. Body (Torso, head, headphones)
            if let bodyPath = Bundle.main.path(forResource: "MascotBody", ofType: "png"),
               let bodyImg = NSImage(contentsOfFile: bodyPath) {
                Image(nsImage: bodyImg)
                    .resizable()
                    .scaledToFit()
                    .frame(width: w, height: h)
            } else if let fullPath = Bundle.main.path(forResource: "Mascot3D", ofType: "png"),
                      let fullImg = NSImage(contentsOfFile: fullPath) {
                Image(nsImage: fullImg)
                    .resizable()
                    .scaledToFit()
                    .frame(width: w, height: h)
            }
        }
        .frame(width: w, height: h)
    }
}

// MARK: - Mimo Companion Avatar View

struct MiniAvatarView: View {
    let size: CGFloat
    var style: String? = nil
    var isWorking: Bool = false
    var isHovered: Bool? = nil
    var hoverPoint: CGPoint? = nil
    var isBackView: Bool = false
    var isSleeping: Bool = false
    var isWalking: Bool = false
    var activity: MascotIdleActivity = .auto
    var walkingTowardRight: Bool = true
    var walkingDistance: CGFloat? = nil
    var facing: MascotFacing? = nil
    var legSwing: Double = 0.0
    var time: Double? = nil

    @State private var internalHovered = false
    @Environment(\.accessibilityReduceMotion) private var reduceMascotMotion
    @AppStorage("MascotStyle") private var savedStyle: String = "sprite"

    private var activeStyle: String {
        (style ?? savedStyle) == "pixel" ? "pixel" : "sprite"
    }

    private var activeHovered: Bool {
        isHovered ?? internalHovered
    }

    var body: some View {
        let isPixel = (activeStyle == "pixel")

        ZStack {
            if isPixel {
                if let path = Bundle.main.path(forResource: "Mini", ofType: "png"),
                   let nsImage = NSImage(contentsOfFile: path) {
                    Image(nsImage: nsImage)
                        .interpolation(.none)
                        .resizable()
                        .scaledToFit()
                        .frame(height: size)
                } else {
                    AppLogoView(size: size)
                }
            } else if activeStyle == "sprite", let image = MascotActivityImages.image(activity: activity, working: isWorking, sleeping: isSleeping, time: time, reduceMotion: reduceMascotMotion) {
                Image(nsImage: image).resizable().scaledToFit().frame(height: size)
            } else if isSleeping {
                if let path = Bundle.main.path(forResource: "MascotSleeping", ofType: "png") ?? Bundle.main.path(forResource: "Mascot3D", ofType: "png"),
                   let nsImage = NSImage(contentsOfFile: path) {
                    Image(nsImage: nsImage)
                        .interpolation(.high)
                        .resizable()
                        .scaledToFit()
                        .frame(height: size * 0.90)
                } else {
                    AppLogoView(size: size)
                }
            } else if isBackView {
                MascotAngleView(facing: .back, size: size)
            } else if isWalking {
                MascotWalkSpriteView(size: size, towardRight: walkingTowardRight, distance: walkingDistance, time: time)
            } else if let facing {
                MascotAngleView(facing: facing, size: size)
            } else if isWorking {
                if let path = Bundle.main.path(forResource: "MascotWriting", ofType: "png") ?? Bundle.main.path(forResource: "Mascot3D", ofType: "png"),
                   let nsImage = NSImage(contentsOfFile: path) {
                    Image(nsImage: nsImage)
                        .interpolation(.high)
                        .resizable()
                        .scaledToFit()
                        .frame(height: size)
                } else {
                    MascotAngleView(facing: .front, size: size)
                }
            } else {
                MascotAngleView(facing: .front, size: size)
            }
        }
        .scaleEffect(activeHovered ? 1.05 : 1.0)
        .animation(.spring(response: 0.35, dampingFraction: 0.65), value: activeHovered)
        .onHover { hovering in
            if isHovered == nil {
                internalHovered = hovering
            }
        }
    }
}

// MARK: - Native Draggable Mascot Window Hosting View

final class MascotHostingView<Content: View>: NSHostingView<Content> {
    private var mouseDownLocation: NSPoint?

    override func resetCursorRects() {
        super.resetCursorRects()
        addCursorRect(bounds, cursor: .openHand)
    }

    override func mouseDown(with event: NSEvent) {
        mouseDownLocation = event.locationInWindow
        super.mouseDown(with: event)
    }

    override func mouseDragged(with event: NSEvent) {
        guard let window = self.window else {
            super.mouseDragged(with: event)
            return
        }
        if let start = mouseDownLocation {
            let dx = abs(event.locationInWindow.x - start.x)
            let dy = abs(event.locationInWindow.y - start.y)
            if dx > 3 || dy > 3 {
                NSCursor.closedHand.push()
                window.performDrag(with: event)
                NSCursor.pop()
                return
            }
        }
        super.mouseDragged(with: event)
    }
}

// MARK: - Chip Chip Idle Activities Accessories & Visual Effects

struct MascotSleepingDeskBase: View {
    var body: some View {
        ZStack(alignment: .bottom) {
            // Shadow beneath desk
            Ellipse()
                .fill(Color.black.opacity(0.18))
                .frame(width: 96, height: 14)
                .offset(y: 5)

            // Wooden Desk surface where Chip Chip rests peacefully
            ZStack {
                // Table top wood plank
                RoundedRectangle(cornerRadius: 3.5, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(red: 0.82, green: 0.65, blue: 0.48),
                                Color(red: 0.65, green: 0.48, blue: 0.32)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .frame(width: 88, height: 8)
                    .overlay(
                        RoundedRectangle(cornerRadius: 3.5, style: .continuous)
                            .stroke(Color(red: 0.92, green: 0.78, blue: 0.62).opacity(0.6), lineWidth: 0.8)
                    )

                // Table edge trim
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(Color(red: 0.52, green: 0.36, blue: 0.22))
                    .frame(width: 86, height: 3)
                    .offset(y: 4)
            }
            .offset(y: 2)

            // Cozy warm night cup on the right side of the desk
            HStack {
                Spacer()
                ZStack {
                    RoundedRectangle(cornerRadius: 1.5)
                        .fill(Color(red: 0.95, green: 0.85, blue: 0.75))
                        .frame(width: 7, height: 8)
                    Circle()
                        .fill(Color.yellow.opacity(0.6))
                        .frame(width: 5, height: 2)
                        .offset(y: -3)
                }
                .offset(x: -8, y: -2)
            }
            .frame(width: 88)
        }
    }
}

struct MascotSleepingEffects: View {
    let time: Double

    var body: some View {
        ZStack {
            // Floating Zzz letters softly ascending from sleeping Chip Chip
            ForEach(0..<3) { i in
                let offsetPhase = fmod(time * 0.40 + Double(i) * 0.33, 1.0)
                let zX = CGFloat(8 + sin(offsetPhase * .pi * 2) * 6 + Double(i) * 6)
                let zY = CGFloat(-36 - offsetPhase * 32)
                let zScale = CGFloat(0.55 + offsetPhase * 0.65)
                let zAlpha = sin(offsetPhase * .pi) * 0.95

                Text(i == 0 ? "Z" : (i == 1 ? "z" : "z"))
                    .font(.system(size: 11, weight: .black, design: .rounded))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [Color(red: 0.4, green: 0.85, blue: 1.0), Color(red: 0.7, green: 0.5, blue: 1.0)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .shadow(color: TransToolsTheme.navy.opacity(0.45), radius: 2)
                    .scaleEffect(zScale)
                    .opacity(zAlpha)
                    .offset(x: zX, y: zY)
            }
        }
    }
}

struct MascotMusicEffects: View {
    let time: Double

    var body: some View {
        ZStack {
            headphoneWaves
            floatingNotes
            beatSparkles
        }
    }

    private var headphoneWaves: some View {
            // Sound wave pulses radiating directly from Chip Chip's built-in headphones
            ForEach(0..<2) { i in
                let pulsePhase = fmod(time * 1.8 + Double(i) * 0.5, 1.0)
                let waveScale = CGFloat(0.7 + pulsePhase * 0.9)
                let waveAlpha = (1.0 - pulsePhase) * 0.75

                // Left ear sound wave
                Circle()
                    .stroke(
                        LinearGradient(colors: [Color.cyan.opacity(0.85), TransToolsTheme.navy.opacity(0.4)], startPoint: .top, endPoint: .bottom),
                        lineWidth: 1.5
                    )
                    .frame(width: 18, height: 18)
                    .scaleEffect(waveScale)
                    .opacity(waveAlpha)
                    .offset(x: -26, y: -22)

                // Right ear sound wave
                Circle()
                    .stroke(
                        LinearGradient(colors: [TransToolsTheme.navy.opacity(0.85), Color.pink.opacity(0.4)], startPoint: .top, endPoint: .bottom),
                        lineWidth: 1.5
                    )
                    .frame(width: 18, height: 18)
                    .scaleEffect(waveScale)
                    .opacity(waveAlpha)
                    .offset(x: 26, y: -22)
            }

    }

    private var floatingNotes: some View {
            // Dancing colorful musical notes floating around
            ForEach(0..<4) { i in
                let phase = fmod(time * 0.65 + Double(i) * 0.25, 1.0)
                let noteIcons = ["music.note", "music.quarternote.3", "music.note.list", "music.mic"]
                let isLeft = (i % 2 == 0)
                let horizontalDrift: Double = sin(phase * Double.pi * 2.0 + Double(i)) * 8.0
                let horizontalDistance: Double = 16.0 + horizontalDrift + Double(i) * 4.0
                let nX: CGFloat = CGFloat(isLeft ? -horizontalDistance : horizontalDistance)
                let nY = CGFloat(-38 - phase * 32)
                let nScale = CGFloat(0.65 + phase * 0.45)
                let nRot = sin(time * 3.5 + Double(i)) * 22.0
                let nAlpha = sin(phase * .pi) * 0.95

                Image(systemName: noteIcons[i % noteIcons.count])
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(
                        LinearGradient(
                            colors: isLeft
                                ? [Color(red: 0.35, green: 0.85, blue: 1.0), Color(red: 0.75, green: 0.45, blue: 1.0)]
                                : [Color(red: 1.0, green: 0.40, blue: 0.75), Color(red: 1.0, green: 0.75, blue: 0.25)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .shadow(color: isLeft ? Color.cyan.opacity(0.6) : Color.pink.opacity(0.6), radius: 3)
                    .rotationEffect(.degrees(nRot))
                    .scaleEffect(nScale)
                    .opacity(nAlpha)
                    .offset(x: nX, y: nY)
            }

    }

    private var beatSparkles: some View {
            // Sparkle beats on rhythm
            ForEach(0..<2) { i in
                let spPhase = fmod(time * 1.4 + Double(i) * 0.5, 1.0)
                Image(systemName: "sparkle")
                    .font(.system(size: 7))
                    .foregroundStyle(Color.yellow)
                    .offset(x: (i == 0 ? -18 : 18) + CGFloat(sin(spPhase * 4) * 4), y: -48 - CGFloat(spPhase * 10))
                    .opacity(sin(spPhase * .pi) * 0.8)
                    .scaleEffect(CGFloat(0.5 + spPhase * 0.5))
            }
    }
}

struct MascotButterflyEffects: View {
    let time: Double

    var body: some View {
        let bx = CGFloat(sin(time * 1.6) * 26)
        let by = CGFloat(-40 + cos(time * 2.2) * 16)
        let wingFlap = abs(sin(time * 16.0))
        let flightAngle = cos(time * 1.6) * 25.0

        ZStack {
            // Sparkle pollen trail behind butterfly
            ForEach(0..<2) { i in
                let trailPhase = fmod(time * 1.5 + Double(i) * 0.5, 1.0)
                let trailAlpha = sin(trailPhase * .pi) * 0.8
                Circle()
                    .fill(Color(red: 1.0, green: 0.85, blue: 0.3))
                    .frame(width: 2.5, height: 2.5)
                    .shadow(color: Color.yellow, radius: 2)
                    .offset(x: bx - CGFloat(sin(time * 1.6) * 4) - CGFloat(trailPhase * 6),
                            y: by + CGFloat(cos(time * 2.2) * 4) + CGFloat(trailPhase * 6))
                    .opacity(trailAlpha)
            }

            // The animated flapping butterfly
            ZStack {
                HStack(spacing: 0.5) {
                    Image(systemName: "heart.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(
                            LinearGradient(colors: [Color.cyan, TransToolsTheme.navy], startPoint: .topLeading, endPoint: .bottomTrailing)
                        )
                        .rotationEffect(.degrees(-70))
                        .scaleEffect(x: CGFloat(0.3 + wingFlap * 0.7), y: 1.0, anchor: .trailing)

                    Image(systemName: "heart.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(
                            LinearGradient(colors: [Color.pink, Color.orange], startPoint: .topTrailing, endPoint: .bottomLeading)
                        )
                        .rotationEffect(.degrees(70))
                        .scaleEffect(x: CGFloat(0.3 + wingFlap * 0.7), y: 1.0, anchor: .leading)
                }

                Capsule()
                    .fill(Color(white: 0.15))
                    .frame(width: 2, height: 7)
            }
            .rotationEffect(.degrees(flightAngle))
            .shadow(color: Color.cyan.opacity(0.65), radius: 3)
            .offset(x: bx, y: by)
        }
    }
}

struct MascotFlowerPlant: View {
    var body: some View {
        VStack(spacing: -3) {
            // Flower blossom
            Image(systemName: "camera.macro")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(
                    LinearGradient(
                        colors: [Color.pink, Color.orange, Color.yellow],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .shadow(color: Color.pink.opacity(0.65), radius: 2.5)

            // Stem with attached leaves
            ZStack {
                // Stem
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(red: 0.35, green: 0.82, blue: 0.40),
                                Color(red: 0.20, green: 0.65, blue: 0.28)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .frame(width: 2.4, height: 16)

                // Left leaf firmly attached to the stem
                Image(systemName: "leaf.fill")
                    .font(.system(size: 7))
                    .foregroundStyle(Color(red: 0.28, green: 0.74, blue: 0.35))
                    .rotationEffect(.degrees(-45))
                    .offset(x: -4.5, y: 1)

                // Right small leaf
                Image(systemName: "leaf.fill")
                    .font(.system(size: 5.5))
                    .foregroundStyle(Color(red: 0.35, green: 0.80, blue: 0.42))
                    .rotationEffect(.degrees(40))
                    .offset(x: 4, y: -2.5)
            }
            .frame(width: 14, height: 16)
        }
    }
}

/// Small garden island beneath the default PNG pose.
struct MascotDefaultGround: View {
    private func flower(_ color: Color, height: CGFloat) -> some View {
        ZStack {
            Capsule().fill(Color(red: 0.31, green: 0.62, blue: 0.39))
                .frame(width: 1.3, height: height).offset(y: height / 2)
            Ellipse().fill(Color(red: 0.42, green: 0.73, blue: 0.45))
                .frame(width: 5, height: 2.5).rotationEffect(.degrees(-30))
                .offset(x: -2.3, y: height * 0.55)
            ForEach(0..<5) { petal in
                Circle().fill(color).frame(width: 4.2, height: 4.2)
                    .offset(y: -2.7).rotationEffect(.degrees(Double(petal) * 72))
            }
            Circle().fill(Color(red: 1, green: 0.78, blue: 0.30))
                .frame(width: 3, height: 3)
        }
        .frame(width: 11, height: 11)
    }

    var body: some View {
        ZStack {
            Ellipse()
                .fill(Color.black.opacity(0.10))
                .frame(width: 72, height: 10)
                .blur(radius: 3)
                .offset(y: 4)
            Ellipse()
                .fill(LinearGradient(
                    colors: [Color(red: 0.83, green: 0.96, blue: 0.92).opacity(0.88),
                             Color(red: 0.56, green: 0.81, blue: 0.75).opacity(0.50)],
                    startPoint: .top, endPoint: .bottom))
                .overlay(Ellipse().stroke(Color.white.opacity(0.55), lineWidth: 0.6))
                .frame(width: 80, height: 12)
            // Keep plants at the edges so the mascot's feet remain visible.
            ForEach(0..<2) { side in
                let x: CGFloat = side == 0 ? -24 : 25
                ZStack {
                    ForEach(0..<3) { blade in
                        Capsule().fill(Color(red: 0.35, green: 0.65, blue: 0.43).opacity(0.85))
                            .frame(width: 1.3, height: CGFloat(5 + blade * 2))
                            .rotationEffect(.degrees(Double(blade - 1) * 23), anchor: .bottom)
                            .offset(x: CGFloat(blade - 1) * 2, y: -2)
                    }
                }
                .offset(x: x, y: -1)
            }
            flower(Color(red: 1, green: 0.68, blue: 0.78), height: 10)
                .offset(x: -34, y: -9)
            flower(Color(red: 0.97, green: 0.98, blue: 1), height: 7)
                .scaleEffect(0.85).offset(x: 34, y: -6)
        }
        .frame(width: 80, height: 12)
        .offset(y: 3)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

struct MascotOutdoorSky: View {
    let time: Double
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private func cloud(width: CGFloat) -> some View {
        ZStack(alignment: .bottom) {
            Capsule().frame(width: width, height: width * 0.28)
            Circle().frame(width: width * 0.43, height: width * 0.43).offset(x: -width * 0.14, y: -width * 0.06)
            Circle().frame(width: width * 0.34, height: width * 0.34).offset(x: width * 0.17, y: -width * 0.04)
        }
        .foregroundStyle(Color.white.opacity(0.82))
        .shadow(color: Color.cyan.opacity(0.12), radius: 2, y: 1)
    }

    var body: some View {
        // Keep the clock live even when Reduce Motion freezes cloud animation.
        TimelineView(.periodic(from: .now, by: 60)) { tick in
            let hour = Double(Calendar.current.component(.hour, from: tick.date))
                + Double(Calendar.current.component(.minute, from: tick.date)) / 60
            let daylight = hour >= 6 && hour < 18
            let warm = hour < 8 || hour >= 16
            let drift = reduceMotion ? 0 : sin(time * 0.18) * 3
            let sky = daylight
                ? (warm ? Color(red: 1, green: 0.73, blue: 0.55) : Color(red: 0.52, green: 0.80, blue: 0.98))
                : Color(red: 0.34, green: 0.38, blue: 0.72)
            ZStack {
                Ellipse()
                    .fill(LinearGradient(colors: [sky.opacity(0.30), sky.opacity(0.14), .clear],
                                         startPoint: .top, endPoint: .bottom))
                    .blur(radius: 4)
                if daylight {
                    let progress = (hour - 6) / 12
                    ZStack {
                        Image(systemName: "sun.max.fill")
                            .font(.system(size: 27)).foregroundStyle(warm ? .orange.opacity(0.75) : .yellow.opacity(0.85))
                        Circle().fill(Color(red: 1, green: 0.88, blue: 0.46)).frame(width: 17, height: 17)
                        HStack(spacing: 4) {
                            Circle().frame(width: 1.5, height: 1.5)
                            Circle().frame(width: 1.5, height: 1.5)
                        }.foregroundStyle(Color.brown.opacity(0.7)).offset(y: -1)
                        Path { path in
                            path.move(to: CGPoint(x: 10, y: 15))
                            path.addQuadCurve(to: CGPoint(x: 16, y: 15), control: CGPoint(x: 13, y: 19))
                        }.stroke(Color.brown.opacity(0.7), style: StrokeStyle(lineWidth: 0.8, lineCap: .round))
                    }
                    .frame(width: 27, height: 27)
                    .shadow(color: .orange.opacity(0.2), radius: 5)
                    .offset(x: -42 + progress * 84, y: -9 - sin(progress * .pi) * 14)
                } else {
                    Image(systemName: "moon.stars.fill")
                        .font(.system(size: 19)).foregroundStyle(Color(red: 1, green: 0.94, blue: 0.72).opacity(0.85))
                        .offset(x: 20, y: -20)
                }
                cloud(width: 29).opacity(daylight ? 1 : 0.45).offset(x: -32 + drift, y: -4)
                cloud(width: 22).opacity(daylight ? 0.75 : 0.35).offset(x: 33 - drift * 0.7, y: -8)
            }
            .frame(width: 126, height: 64)
        }
        .frame(width: 126, height: 64)
        .offset(y: -55)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

struct MascotFlowerEffects: View {
    let time: Double

    var body: some View {
        let sway = sin(time * 2.0) * 4.0
        ZStack {
            // Grassy base diorama (Tiểu cảnh cỏ tròn xinh dưới chân)
            Capsule()
                .fill(
                    LinearGradient(
                        colors: [
                            Color.green.opacity(0.30),
                            Color.green.opacity(0.12)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .frame(width: 84, height: 7)
                .overlay(
                    Capsule()
                        .stroke(Color.green.opacity(0.25), lineWidth: 0.6)
                )
                .offset(y: 3)

            // Tiny grass blades on the patch
            HStack(spacing: 8) {
                Image(systemName: "leaf.fill")
                    .font(.system(size: 5.5))
                    .foregroundStyle(Color.green.opacity(0.55))
                    .rotationEffect(.degrees(-20))
                Spacer()
                Image(systemName: "leaf.fill")
                    .font(.system(size: 5))
                    .foregroundStyle(Color.green.opacity(0.50))
                    .rotationEffect(.degrees(15))
            }
            .frame(width: 50)
            .offset(y: 1.5)

            // Small yellow side bud on the left to balance the scene
            VStack(spacing: -2) {
                Image(systemName: "camera.macro")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(
                        LinearGradient(colors: [Color.yellow, Color.orange], startPoint: .top, endPoint: .bottom)
                    )
                Capsule()
                    .fill(Color(red: 0.25, green: 0.70, blue: 0.32))
                    .frame(width: 1.8, height: 8)
            }
            .rotationEffect(.degrees(-sway * 0.7), anchor: .bottom)
            .offset(x: -24, y: 0)

            // Main Blooming Flower at lower right corner with stem, leaves, and gentle wind sway
            MascotFlowerPlant()
                .rotationEffect(.degrees(sway), anchor: .bottom)
                .offset(x: 24, y: -2)

            // Floral sparkles
            ForEach(0..<2) { i in
                let pPhase = fmod(time * 0.7 + Double(i) * 0.5, 1.0)
                Image(systemName: "sparkle")
                    .font(.system(size: 7))
                    .foregroundStyle(Color(red: 1.0, green: 0.6, blue: 0.8))
                    .offset(x: 23 - CGFloat(pPhase * 8), y: -16 - CGFloat(pPhase * 14))
                    .opacity(sin(pPhase * .pi) * 0.85)
                    .scaleEffect(CGFloat(0.5 + pPhase * 0.5))
            }
        }
    }
}

struct MascotTeaEffects: View {
    let time: Double

    var body: some View {
        ZStack {
            // Rising fragrant coffee steam curls above the coffee mug held by Chip Chip
            ForEach(0..<2) { i in
                let sPhase = fmod(time * 0.8 + Double(i) * 0.5, 1.0)
                Path { path in
                    path.move(to: CGPoint(x: 0, y: 12))
                    path.addCurve(to: CGPoint(x: 2, y: 0), control1: CGPoint(x: -3, y: 8), control2: CGPoint(x: 3, y: 4))
                }
                .stroke(Color.white.opacity(0.65), style: StrokeStyle(lineWidth: 1.2, lineCap: .round))
                .frame(width: 6, height: 14)
                .offset(x: CGFloat((i == 0 ? -2.5 : 2.5) + sin(sPhase * 4.0) * 1.5), y: CGFloat(-32 - sPhase * 11))
                .opacity(sin(sPhase * .pi) * 0.75)
            }
        }
    }
}


// MARK: - Fishing Activity Diorama (Tiểu cảnh câu cá trọn vẹn)

struct MascotBambooRodShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX, y: rect.minY),
            control: CGPoint(x: rect.minX + rect.width * 0.42, y: rect.minY + 2.0)
        )
        return path
    }
}

struct MascotFishingLineShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        return path
    }
}

struct MascotFishingBase: View {
    let time: Double

    var body: some View {
        ZStack(alignment: .bottom) {
            // 1. Soft island drop shadow
            Ellipse()
                .fill(Color.black.opacity(0.18))
                .frame(width: 108, height: 16)
                .offset(y: 4)

            // 2. Clear Blue Curved Pond on the right
            ZStack {
                // Pond water basin
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(red: 0.15, green: 0.75, blue: 0.92).opacity(0.40),
                                Color(red: 0.08, green: 0.45, blue: 0.78).opacity(0.25)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .frame(width: 58, height: 14)
                    .overlay(
                        RoundedRectangle(cornerRadius: 11, style: .continuous)
                            .stroke(Color.cyan.opacity(0.40), lineWidth: 0.8)
                    )
                    .offset(x: 20, y: 1)

                // Expanding water ripples under the bobber
                ForEach(0..<2) { i in
                    let rPhase = fmod(time * 0.85 + Double(i) * 0.5, 1.0)
                    Ellipse()
                        .stroke(Color.white.opacity(Double(1.0 - rPhase) * 0.45), lineWidth: 0.8)
                        .frame(width: CGFloat(8 + rPhase * 16), height: CGFloat(3.5 + rPhase * 6))
                        .offset(x: 34, y: 1)
                }

                // Tiny water lily leaf & flower
                ZStack {
                    Circle()
                        .fill(Color(red: 0.25, green: 0.78, blue: 0.45).opacity(0.85))
                        .frame(width: 7.5, height: 5.5)
                    Circle()
                        .fill(Color.pink.opacity(0.9))
                        .frame(width: 2.8, height: 2.8)
                        .offset(y: -1)
                }
                .offset(x: 13, y: 0)
            }

            // 3. Wooden Pier / Dock on the left (Where Chip Chip sits facing the pond)
            ZStack {
                HStack(spacing: 1.5) {
                    ForEach(0..<5) { plank in
                        RoundedRectangle(cornerRadius: 1.5)
                            .fill(
                                LinearGradient(
                                    colors: [
                                        Color(red: 0.74, green: 0.54, blue: 0.36),
                                        Color(red: 0.56, green: 0.38, blue: 0.22)
                                    ],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                            .frame(width: 8.5, height: 6)
                            .overlay(
                                RoundedRectangle(cornerRadius: 1.5)
                                    .stroke(Color.black.opacity(0.12), lineWidth: 0.5)
                            )
                    }
                }
                .offset(x: -20, y: 1)

                // Dock pier wooden piles into the water
                HStack(spacing: 24) {
                    RoundedRectangle(cornerRadius: 1)
                        .fill(Color(red: 0.45, green: 0.30, blue: 0.18))
                        .frame(width: 3.5, height: 7)
                    RoundedRectangle(cornerRadius: 1)
                        .fill(Color(red: 0.45, green: 0.30, blue: 0.18))
                        .frame(width: 3.5, height: 7)
                }
                .offset(x: -20, y: 5)

                // Cute wooden bait bucket sitting behind Chip Chip on the dock
                ZStack {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(
                            LinearGradient(
                                colors: [Color(red: 0.65, green: 0.45, blue: 0.28), Color(red: 0.42, green: 0.28, blue: 0.16)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .frame(width: 8, height: 7.5)
                        .overlay(
                            RoundedRectangle(cornerRadius: 2)
                                .stroke(Color(red: 0.85, green: 0.75, blue: 0.5).opacity(0.6), lineWidth: 0.6)
                        )

                    // Water shimmer inside bucket
                    Ellipse()
                        .fill(Color.cyan.opacity(0.7))
                        .frame(width: 6.5, height: 2.2)
                        .offset(y: -2.8)

                    // Tiny metal wire handle (properly bounded Ellipse)
                    Ellipse()
                        .stroke(Color.gray.opacity(0.75), lineWidth: 0.8)
                        .frame(width: 7, height: 5)
                        .offset(y: -4.5)
                }
                .offset(x: -37, y: -1)
            }
        }
    }
}

struct MascotFishingOverlay: View {
    let time: Double
    var walkX: CGFloat = -13.0
    var bobY: CGFloat = 4.0
    var tilt: Double = 3.0

    var body: some View {
        let bobberY = sin(time * 3.0) * 1.8
        let isNibbling = sin(time * 0.9) > 0.65
        let extraNibbleDip: CGFloat = isNibbling ? CGFloat(abs(sin(time * 12.0)) * 2.5) : 0

        // Chip Chip sits on the dock (walkX = -13, bobY = 4).
        // From this rear angle, the rod is held in front of Chip Chip's lap and emerges naturally from the right flank toward the pond.
        let rodBaseX: CGFloat = walkX + 13.5 // ~ 0.5 pt (right side of waist, in front of body)
        let rodBaseY: CGFloat = bobY - 12.0  // ~ -8.0 pt (waist/lap level, well below head/ears)

        // Rod tip flexing gracefully over the pond
        let rodTipX: CGFloat = 27.5 + CGFloat(sin(time * 2.5) * 0.8)
        let rodTipY: CGFloat = -22.5 + CGFloat(sin(time * 2.5) * 1.0) - extraNibbleDip

        let rodW = max(2.0, rodTipX - rodBaseX)
        let rodH = max(2.0, rodBaseY - rodTipY)
        let rodCenterX = (rodBaseX + rodTipX) / 2.0
        let rodCenterY = (rodBaseY + rodTipY) / 2.0

        let lineTargetX: CGFloat = 34.0
        let lineTargetY: CGFloat = 1.0 + bobberY + extraNibbleDip

        let lineW = max(1.0, lineTargetX - rodTipX)
        let lineH = max(2.0, lineTargetY - rodTipY)
        let lineCenterX = (rodTipX + lineTargetX) / 2.0
        let lineCenterY = (rodTipY + lineTargetY) / 2.0

        ZStack {
            // Flexible bamboo fishing rod extending naturally from in front of Chip Chip's lap out over the pond
            MascotBambooRodShape()
                .stroke(
                    LinearGradient(
                        colors: [
                            Color(red: 0.70, green: 0.48, blue: 0.25), // Bamboo handle
                            Color(red: 0.88, green: 0.68, blue: 0.38), // Golden bamboo shaft
                            Color(red: 1.00, green: 0.90, blue: 0.58)  // Light flexible tip
                        ],
                        startPoint: .bottomLeading,
                        endPoint: .topTrailing
                    ),
                    style: StrokeStyle(lineWidth: 1.8, lineCap: .round, lineJoin: .round)
                )
                .frame(width: rodW, height: rodH)
                .offset(x: rodCenterX, y: rodCenterY)

            // Fishing line from rod tip down to the bobber with bounded frame
            MascotFishingLineShape()
                .stroke(Color.white.opacity(0.85), style: StrokeStyle(lineWidth: 0.75, lineCap: .round))
                .frame(width: lineW, height: lineH)
                .offset(x: lineCenterX, y: lineCenterY)

            // Two-tone Red & White Fishing Bobber (Phao câu)
            ZStack {
                Circle()
                    .fill(Color.white)
                    .frame(width: 5.5, height: 5.5)
                Circle()
                    .fill(Color.red)
                    .frame(width: 5.5, height: 5.5)
                    .mask(
                        Rectangle()
                            .frame(width: 6, height: 3)
                            .offset(y: -1.5)
                    )
            }
            .shadow(color: Color.red.opacity(0.4), radius: 1.5)
            .offset(x: lineTargetX, y: lineTargetY)

            // Playful jumping fish leaping out of water
            let fishCycle = fmod(time * 0.35, 1.0)
            if fishCycle > 0.65 {
                let jumpProgress = (fishCycle - 0.65) / 0.35
                let fishX = CGFloat(18 + jumpProgress * 24)
                let fishY = CGFloat(-sin(jumpProgress * .pi) * 16)
                let fishRot = (jumpProgress - 0.5) * 80.0

                Image(systemName: "fish.fill")
                    .font(.system(size: 7.5, weight: .bold))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [Color.orange, Color.yellow],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .rotationEffect(.degrees(fishRot))
                    .offset(x: fishX, y: fishY)
                    .shadow(color: Color.orange.opacity(0.5), radius: 2)

                // Water splash droplets
                ForEach(0..<2) { d in
                    Circle()
                        .fill(Color.cyan.opacity(0.85))
                        .frame(width: 2, height: 2)
                        .offset(x: fishX + CGFloat((d == 0 ? -3 : 4)), y: fishY + 3)
                        .opacity(sin(jumpProgress * .pi))
                }
            }
        }
    }
}

struct MascotStrollingEffects: View {
    let time: Double
    let walkX: CGFloat

    var body: some View {
        ZStack {
            // Self-contained Park Lawn Island (Tiểu cảnh công viên bo tròn trọn vẹn)
            ZStack(alignment: .bottom) {
                // Soft ground shadow
                Ellipse()
                    .fill(Color.black.opacity(0.18))
                    .frame(width: 98, height: 14)
                    .offset(y: 4)

                // Rounded park lawn island
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(red: 0.40, green: 0.82, blue: 0.46).opacity(0.35),
                                Color(red: 0.22, green: 0.62, blue: 0.32).opacity(0.15)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .frame(width: 92, height: 8)
                    .overlay(
                        Capsule()
                            .stroke(Color.green.opacity(0.30), lineWidth: 0.8)
                    )
                    .offset(y: 2)

                // Stepping stones & clover flowers along the path
                HStack(spacing: 12) {
                    Circle()
                        .fill(Color.secondary.opacity(0.20))
                        .frame(width: 4, height: 2.5)
                    Image(systemName: "leaf.fill")
                        .font(.system(size: 6.5))
                        .foregroundStyle(Color.green.opacity(0.65))
                        .rotationEffect(.degrees(-15))
                    Image(systemName: "camera.macro")
                        .font(.system(size: 6.5))
                        .foregroundStyle(Color.pink.opacity(0.55))
                    Circle()
                        .fill(Color.secondary.opacity(0.20))
                        .frame(width: 4, height: 2.5)
                    Image(systemName: "leaf.fill")
                        .font(.system(size: 6.5))
                        .foregroundStyle(Color.green.opacity(0.65))
                        .rotationEffect(.degrees(20))
                }
                .offset(y: 0.5)
            }

            // Step dust puffs under Chip Chip's feet
            ForEach(0..<2) { i in
                let dustPhase = fmod(time * 2.4 + Double(i) * 0.5, 1.0)
                Circle()
                    .fill(Color.primary.opacity(0.12))
                    .frame(width: 4 * (1 - dustPhase), height: 2.5 * (1 - dustPhase))
                    .offset(x: walkX + (i == 0 ? -6 : 6), y: 3 + dustPhase * 2.5)
                    .opacity(sin(dustPhase * .pi) * 0.6)
            }

            // Drifting park leaves staying within the diorama
            ForEach(0..<2) { i in
                let leafPhase = fmod(time * 0.8 + Double(i) * 0.5, 1.0)
                let lX = CGFloat(-22 + leafPhase * 44)
                let lY = CGFloat(-8 - sin(leafPhase * .pi) * 12)
                let lRot = leafPhase * 360.0

                Image(systemName: i == 0 ? "leaf.fill" : "sparkle")
                    .font(.system(size: i == 0 ? 6.5 : 5.5))
                    .foregroundStyle(i == 0 ? Color(red: 0.5, green: 0.85, blue: 0.4).opacity(0.7) : Color.yellow.opacity(0.6))
                    .rotationEffect(.degrees(lRot))
                    .offset(x: lX, y: lY)
                    .opacity(sin(leafPhase * .pi) * 0.8)
            }
        }
    }
}

// MARK: - Floating Mimo Assistant Widget

struct FloatingMascotView: View {
    @ObservedObject var model: MeetingModel
    @State private var isHovered = false
    @State private var showQuickMenu = false
    @State private var lastActiveDate = Date()
    @State private var spinStartTime: Date? = nil
    @State private var hoverPoint: CGPoint? = nil

    private struct MascotMotionState {
        var bobY: CGFloat = 0
        var tilt: Double = 0
        var squashX: CGFloat = 1.0
        var squashY: CGFloat = 1.0
        var scaleX: CGFloat = 1.0
        var walkX: CGFloat = 0
        var expression: MascotExpression? = nil
        var strokeX: CGFloat = 0
        var strokeY: CGFloat = 0
        var penAngle: Double = 0
        var shadowRad: CGFloat = 3.2
        var shadowOffsetY: CGFloat = 2.5
        var shadowAlpha: Double = 0.20
        var legSwing: Double = 0.0
        var turnY: Double = 0.0
    }

    private func computeMotion(time: Double, speed: Double, isIdle: Bool, activeActivity: MascotIdleActivity, isSpinning: Bool, spinElapsed: TimeInterval) -> MascotMotionState {
        var m = MascotMotionState()
        if isSpinning {
            let spinDuration: Double = 0.72
            let p = min(1.0, max(0.0, spinElapsed / spinDuration))
            m.bobY = -CGFloat(sin(p * .pi) * 8.0)
            m.tilt = sin(p * .pi * 2.0) * 3.5
            m.scaleX = 1.0
            m.expression = .happySmile
            m.shadowRad = 4.2
            m.shadowOffsetY = 3.5
            m.shadowAlpha = 0.16
            return m
        }
        if model.running {
            m.strokeX = CGFloat(sin(time * 10.0 * speed) * 3.5)
            m.strokeY = CGFloat(cos(time * 10.0 * speed) * 1.8)
            m.penAngle = sin(time * 10.0 * speed) * 14.0
            m.bobY = CGFloat(sin(time * 4.5 * speed) * 1.2)
            m.tilt = sin(time * 4.5 * speed) * 1.8
            m.shadowRad = 3.0
            m.shadowOffsetY = 2.0
            m.shadowAlpha = 0.22
            m.legSwing = 0.0
            m.turnY = 0.0
            return m
        }
        if isHovered {
            if let pt = hoverPoint {
                let dx = pt.x - 80.0
                let dy = pt.y - 78.0
                // Nghiêng nhẹ đầu theo hướng chuột (-5.5° đến +5.5°)
                m.tilt = max(-5.5, min(5.5, Double(dx / 70.0) * 4.5))
                // Ngước nhìn lên khi chuột ở phía trên đầu, cúi nhìn khi chuột ở phía dưới
                if dy < -16 {
                    m.bobY = -2.5 - CGFloat(min(1.0, abs(dy) / 60.0)) * 2.0
                    m.squashY = 1.025
                    m.squashX = 0.98
                } else if dy > 24 {
                    m.bobY = 1.6
                    m.squashY = 0.985
                    m.squashX = 1.015
                } else {
                    m.bobY = -1.5
                }
            } else {
                m.bobY = -2.0
                m.tilt = 0.0
            }
            m.scaleX = 1.0
            m.shadowRad = 3.6
            m.shadowOffsetY = 2.5
            m.shadowAlpha = 0.24
            m.legSwing = 0.0
            m.expression = nil
            m.turnY = 0.0
            return m
        }
        // Khi bật chế độ đi dạo Dock Bar và máy đang rảnh
        if model.isDockWalkEnabled && !model.running && isIdle {
            let isPaused = model.dockWalkPauseUntil != nil
            if isPaused {
                // Đang tạm dừng quay người chuyển hướng ở mép màn hình: giữ dáng đứng thẳng tự nhiên
                m.bobY = 0.0
                m.tilt = 0.0
                m.turnY = 0.0
                m.scaleX = model.mascotStyle == "pixel" && model.dockWalkDirection < 0 ? -1.0 : 1.0
                m.squashX = 1.0
                m.squashY = 1.0
                m.expression = nil
                m.legSwing = 0.0
            } else {
                if model.mascotStyle == "pixel" {
                    let stepBounce = abs(sin(time * 5.2))
                    m.bobY = -CGFloat(stepBounce * 3.8)
                    m.scaleX = model.dockWalkDirection < 0 ? -1.0 : 1.0
                    m.tilt = (model.dockWalkDirection >= 0 ? 3.5 : -3.5)
                } else {
                    // Dáng bước đi nhấp nhô trọng tâm tự nhiên đồng bộ với 32-frame walk cycle
                    let strideLength: Double = 26.0
                    let stepPhase = fmod(Double(model.dockWalkDistance / strideLength), 1.0)
                    let bob = sin(stepPhase * .pi * 2.0)
                    m.bobY = -CGFloat(abs(bob) * 1.8) // Nhấp nhô nhẹ 1.8pt theo từng bước chân
                    m.tilt = bob * (model.dockWalkDirection >= 0 ? 1.4 : -1.4) // Nghiêng người tự nhiên
                    m.scaleX = 1.0
                    m.turnY = 0.0
                    m.squashX = 1.0
                    m.squashY = 1.0
                    m.legSwing = 0.0
                }
                m.expression = nil
            }
            m.shadowRad = 3.5
            m.shadowOffsetY = 2.0
            m.shadowAlpha = 0.20
            return m
        }
        if isIdle {
            switch activeActivity {
            case .fishing:
                let fishBreath = sin(time * 1.5)
                m.walkX = -13.0
                m.bobY = 4.0 + CGFloat(fishBreath * 0.8)
                m.tilt = 3.0 + sin(time * 1.0) * 0.8
                m.expression = nil
                m.shadowRad = 3.5
                m.shadowOffsetY = 2.0
                m.shadowAlpha = 0.22
                m.legSwing = 0.0
            case .sleeping:
                let sleepBreath = sin(time * 1.2)
                m.walkX = -4.0
                m.bobY = 3.0 + CGFloat(sleepBreath * 1.0)
                m.tilt = sin(time * 1.2) * 0.6
                m.squashX = CGFloat(1.02 - sleepBreath * 0.015)
                m.squashY = CGFloat(0.98 + sleepBreath * 0.02)
                m.expression = nil
                m.shadowRad = 3.5
                m.shadowOffsetY = 2.0
                m.shadowAlpha = 0.20
                m.legSwing = 0.0
            case .strolling:
                let strollCycle = sin(time * 0.75) // Nhịp dạo bước êm ái, chu kỳ ~8.4s
                m.walkX = CGFloat(strollCycle * 24.0) // Biên độ bước 48pt
                let strollSpeed = cos(time * 0.75)
                if abs(strollSpeed) > 0.25 {
                    let stepBounce = abs(sin(time * 3.5))
                    m.bobY = -CGFloat(stepBounce * 1.8)
                    m.tilt = sin(time * 3.5) * (strollSpeed > 0 ? 1.5 : -1.5)
                } else {
                    m.bobY = 0.0
                    m.tilt = 0.0
                }
                m.scaleX = 1.0
                m.squashX = 1.0
                m.squashY = 1.0
                m.legSwing = 0.0
                m.expression = nil
                m.shadowRad = 3.2
                m.shadowOffsetY = 2.5
                m.shadowAlpha = 0.22
            case .catchingButterfly:
                let bx = sin(time * 1.6) * 26.0
                m.tilt = (bx / 26.0) * 8.0
                let reachHop = max(0, sin(time * 3.2))
                m.bobY = -CGFloat(reachHop * 3.5)
                m.expression = nil
                m.shadowRad = 3.2
                m.shadowOffsetY = 2.6
                m.shadowAlpha = 0.22
                m.legSwing = Double(reachHop * 10.0)
            case .pickingFlowers:
                let flowerCycle = sin(time * 1.8)
                m.tilt = 10.0 + flowerCycle * 2.0
                m.bobY = 3.5 + CGFloat(flowerCycle * 1.5)
                m.expression = nil
                m.shadowRad = 3.0
                m.shadowOffsetY = 2.2
                m.shadowAlpha = 0.20
                m.legSwing = 0.0
            case .listeningMusic:
                let groovePulse = abs(sin(time * 6.5))
                m.bobY = -CGFloat(groovePulse * 5.0)
                m.tilt = sin(time * 3.25) * 4.5
                m.squashX = CGFloat(1.0 + groovePulse * 0.03)
                m.squashY = CGFloat(1.0 - groovePulse * 0.04)
                m.expression = nil
                m.shadowRad = 3.5
                m.shadowOffsetY = 2.8
                m.shadowAlpha = 0.25
                // Foot tapping to music beat
                m.legSwing = max(0, sin(time * 6.5)) * 14.0
            case .writing, .thinking:
                m.expression = nil
                m.bobY = 0
                m.tilt = 0
            case .sippingTea:
                let sipCycle = sin(time * 1.6)
                m.bobY = 1.0 + CGFloat(sipCycle * 1.2)
                m.tilt = sin(time * 0.8) * 1.5
                m.expression = nil
                m.shadowRad = 3.0
                m.shadowOffsetY = 2.3
                m.shadowAlpha = 0.20
            case .auto:
                let idleCycle = sin(time * 1.5)
                m.bobY = CGFloat(idleCycle * 1.8)
                m.tilt = sin(time * 0.75) * 1.2
                m.squashX = CGFloat(1.0 - idleCycle * 0.012)
                m.squashY = CGFloat(1.0 + idleCycle * 0.018)
                m.shadowRad = 3.2
                m.shadowOffsetY = 2.5
                m.shadowAlpha = 0.20
            }
        } else {
            let idleCycle = sin(time * 1.5)
            m.bobY = CGFloat(idleCycle * 1.8)
            m.tilt = sin(time * 0.75) * 1.2
            m.squashX = CGFloat(1.0 - idleCycle * 0.012)
            m.squashY = CGFloat(1.0 + idleCycle * 0.018)
            m.shadowRad = 3.2
            m.shadowOffsetY = 2.5
            m.shadowAlpha = 0.20
        }
        return m
    }

    private struct MascotRenderContext {
        let motion: MascotMotionState
        let activeActivity: MascotIdleActivity
        let isIdle: Bool
        let isBackView: Bool
        let isSleeping: Bool
        let isWalking: Bool
        let walkingTowardRight: Bool
        let walkingDistance: CGFloat?
        let facing: MascotFacing?
        let sparkPhase1: Double
        let sparkPhase2: Double
    }

    private func makeRenderContext(now: Date) -> MascotRenderContext {
        let time = now.timeIntervalSinceReferenceDate
        let isHearingSpeech = (Date().timeIntervalSince(model.lastAudio ?? .distantPast) < 1.8)
        let speed: Double = isHearingSpeech ? 1.4 : 1.0

        let idleDuration = min(MascotIdlePolicy.systemIdleSeconds, max(0, now.timeIntervalSince(lastActiveDate)))
        let isIdle = !model.running && !model.busy && !isHovered && !showQuickMenu &&
            !model.isBubbleVisible && !model.isBubbleHovered && idleDuration >= MascotIdlePolicy.idleThreshold

        let activeActivity: MascotIdleActivity = {
            if model.isDockWalkEnabled {
                return .auto
            } else if !isIdle {
                return .auto
            } else if model.mascotIdleActivity != .auto {
                return model.mascotIdleActivity
            } else {
                return MascotIdlePolicy.activity(
                    idleSeconds: idleDuration,
                    hour: Calendar.current.component(.hour, from: now),
                    foregroundBundle: NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? "",
                    conservingEnergy: ProcessInfo.processInfo.isLowPowerModeEnabled ||
                        ProcessInfo.processInfo.thermalState == .serious || ProcessInfo.processInfo.thermalState == .critical,
                    heardAudioRecently: now.timeIntervalSince(model.lastAudio ?? .distantPast) < 120)

            }
        }()

        let spinDuration: TimeInterval = 0.72
        let spinElapsed = spinStartTime.map { now.timeIntervalSince($0) } ?? 0.0
        let isSpinning = spinStartTime != nil && spinElapsed >= 0 && spinElapsed < spinDuration

        var m = computeMotion(time: time, speed: speed, isIdle: isIdle, activeActivity: activeActivity, isSpinning: isSpinning, spinElapsed: spinElapsed)

        let isBackView = !model.isDockWalkEnabled && isIdle && activeActivity == .fishing
        let isSleeping = !model.isDockWalkEnabled && isIdle && activeActivity == .sleeping

        var isWalking = false
        var walkingTowardRight = true
        var walkingDistance: CGFloat? = nil
        var facingToUse: MascotFacing? = nil

        if isSpinning {
            facingToUse = MascotFacing.spin(elapsed: spinElapsed, duration: spinDuration)
        } else if isHovered {
            if let pt = hoverPoint {
                let dx = pt.x - 80.0
                if dx < -38 {
                    facingToUse = .left
                } else if dx < -12 {
                    facingToUse = .frontLeft
                } else if dx <= 12 {
                    facingToUse = .front
                } else if dx <= 38 {
                    facingToUse = .frontRight
                } else {
                    facingToUse = .right
                }
            } else {
                facingToUse = .front
            }
        } else if model.isDockWalkEnabled && !model.running && isIdle {
            if let pauseUntil = model.dockWalkPauseUntil {
                let pauseElapsed = max(0, 1.2 - pauseUntil.timeIntervalSince(now))
                facingToUse = MascotFacing.turning(elapsed: pauseElapsed, towardRight: model.dockWalkDirection >= 0)
            } else {
                isWalking = true
                walkingTowardRight = model.dockWalkDirection >= 0
                walkingDistance = model.dockWalkDistance
            }
        } else if isIdle && activeActivity == .strolling {
            if model.mascotStyle == "pixel" {
                // Pixel mode handled by 2D sprite
            } else {
                let strollCos = cos(time * 0.75)
                if strollCos > 0.25 {
                    isWalking = true
                    walkingTowardRight = true
                    walkingDistance = CGFloat((sin(time * 0.75) + 1.0) * 24.0)
                } else if strollCos < -0.25 {
                    isWalking = true
                    walkingTowardRight = false
                    walkingDistance = CGFloat((1.0 - sin(time * 0.75)) * 24.0)
                } else {
                    // Nhịp quay đầu mượt qua các góc nhìn trước
                    let strollSin = sin(time * 0.75)
                    if strollCos >= 0 {
                        if strollSin > 0.12 { facingToUse = .frontRight }
                        else if strollSin < -0.12 { facingToUse = .frontLeft }
                        else { facingToUse = .front }
                    } else {
                        if strollSin > 0.12 { facingToUse = .frontLeft }
                        else if strollSin < -0.12 { facingToUse = .frontRight }
                        else { facingToUse = .front }
                    }
                }
            }
        } else if !model.running && !isBackView && !isSleeping {
            facingToUse = MascotFacing.idleLookAround(time: time) ?? .front
        }

        if model.mascotStyle == "sprite",
           (model.running && MascotActivityImages.hasAnimation(.writing)) ||
           (isIdle && MascotActivityImages.hasAnimation(activeActivity)) {
            m.tilt = 0
            m.bobY = 0
            m.squashX = 1
            m.squashY = 1
            m.legSwing = 0
        }

        return MascotRenderContext(
            motion: m,
            activeActivity: activeActivity,
            isIdle: isIdle,
            isBackView: isBackView,
            isSleeping: isSleeping,
            isWalking: isWalking,
            walkingTowardRight: walkingTowardRight,
            walkingDistance: walkingDistance,
            facing: facingToUse,
            sparkPhase1: fmod(time * 1.3, 1.0),
            sparkPhase2: fmod((time * 1.3) + 0.5, 1.0)
        )
    }

    @ViewBuilder
    private func mascotContent(rc: MascotRenderContext, time: Double) -> some View {
        let m = rc.motion
        ZStack(alignment: .bottom) {
            if model.mascotStyle == "sprite", !model.running, !rc.isWalking,
               (!model.isDockWalkEnabled || !rc.isIdle), rc.activeActivity == .auto {
                MascotDefaultGround()
            }
            if model.mascotStyle == "sprite", !model.isDockWalkEnabled, rc.isIdle,
               [.pickingFlowers, .catchingButterfly, .strolling, .fishing].contains(rc.activeActivity) {
                MascotOutdoorSky(time: time)
            }
            // Background Dioramas (Tiểu cảnh trọn vẹn bo tròn) - chỉ hiện khi không bật đi dạo Dock:
            if !model.isDockWalkEnabled && rc.isIdle && rc.activeActivity == .fishing {
                MascotFishingBase(time: time)
            }

            if !model.isDockWalkEnabled && rc.isIdle && rc.activeActivity == .sleeping && model.mascotStyle != "sprite" {
                MascotSleepingDeskBase()
            }

            if !model.isDockWalkEnabled && rc.isIdle && rc.activeActivity == .strolling {
                MascotStrollingEffects(time: time, walkX: m.walkX)
            }

            if !model.isDockWalkEnabled && rc.isIdle && rc.activeActivity == .pickingFlowers {
                MascotFlowerEffects(time: time)
            }

            // Mimo Companion Avatar
            MiniAvatarView(
                size: model.mascotStyle == "pixel" ? 64 : 80,
                style: model.mascotStyle,
                isWorking: model.running,
                isHovered: isHovered,
                hoverPoint: hoverPoint,
                isBackView: rc.isBackView,
                isSleeping: rc.isSleeping,
                isWalking: rc.isWalking,
                activity: rc.isIdle ? rc.activeActivity : .auto,
                walkingTowardRight: rc.walkingTowardRight,
                walkingDistance: rc.walkingDistance,
                facing: rc.facing,
                legSwing: m.legSwing,
                time: time
            )
            .scaleEffect(x: (isHovered ? 1.06 : 1.0) * m.squashX * m.scaleX, y: (isHovered ? 1.06 : 1.0) * m.squashY, anchor: .bottom)
            .offset(x: m.walkX, y: m.bobY)
            .rotationEffect(.degrees(m.tilt), anchor: .bottom)
            .shadow(
                color: Color.black.opacity(m.shadowAlpha),
                radius: m.shadowRad,
                y: m.shadowOffsetY
            )
            .animation(.spring(response: 0.35, dampingFraction: 0.70), value: m.scaleX)
            .animation(.spring(response: 0.35, dampingFraction: 0.65), value: isHovered)
            .animation(.spring(response: 0.35, dampingFraction: 0.75), value: model.running)

            // Foreground Activity Overlays - chỉ hiện khi không bật đi dạo Dock:
            if !model.isDockWalkEnabled && rc.isIdle && rc.activeActivity == .fishing {
                MascotFishingOverlay(time: time, walkX: m.walkX, bobY: m.bobY, tilt: m.tilt)
            }

            if !model.isDockWalkEnabled && rc.isIdle && rc.activeActivity == .sleeping {
                MascotSleepingEffects(time: time)
                    .offset(x: m.walkX, y: m.bobY)
            }

            if !model.isDockWalkEnabled && rc.isIdle && rc.activeActivity == .listeningMusic {
                MascotMusicEffects(time: time)
                    .offset(x: m.walkX, y: m.bobY)
            }

            if !model.isDockWalkEnabled && rc.isIdle && rc.activeActivity == .catchingButterfly && !(model.mascotStyle == "sprite" && MascotActivityImages.hasAnimation(.catchingButterfly)) {
                MascotButterflyEffects(time: time)
            }

            if !model.isDockWalkEnabled && rc.isIdle && rc.activeActivity == .sippingTea {
                MascotTeaEffects(time: time)
                    .offset(x: m.walkX, y: m.bobY)
            }

            // PNG writing clips already contain the pencil and marks on the page.
            if model.running && !(model.mascotStyle == "sprite" && MascotActivityImages.hasAnimation(.writing)) {
                Group {
                    VStack(alignment: .leading, spacing: 2.0) {
                        Capsule()
                            .fill(Color(red: 0.12, green: 0.52, blue: 0.92).opacity(0.85))
                            .frame(width: max(3.5, min(10.5, 6.5 + m.strokeX * 0.9)), height: 1.5)
                        Capsule()
                            .fill(Color(red: 0.12, green: 0.52, blue: 0.92).opacity(0.65))
                            .frame(width: max(2.5, min(9.0, 7.5 - m.strokeX * 0.7)), height: 1.5)
                    }
                    .rotationEffect(.degrees(-10))
                    .offset(x: 10 + m.walkX, y: -20 + m.bobY)

                    Image(systemName: "pencil")
                        .font(.system(size: 11, weight: .black))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [
                                    Color(red: 1.0, green: 0.82, blue: 0.25),
                                    Color(red: 1.0, green: 0.45, blue: 0.15)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .rotationEffect(.degrees(-35 + m.penAngle), anchor: .bottomLeading)
                        .offset(x: 10 + m.strokeX + m.walkX, y: -21 + m.strokeY + m.bobY)
                        .shadow(color: Color.orange.opacity(0.55), radius: 2, y: 1)

                    Image(systemName: "sparkle")
                        .font(.system(size: 7, weight: .bold))
                        .foregroundStyle(Color(red: 0.20, green: 0.88, blue: 0.98))
                        .offset(x: 15 + CGFloat(rc.sparkPhase1 * 6) + m.walkX, y: -26 - CGFloat(rc.sparkPhase1 * 12) + m.bobY)
                        .opacity(sin(rc.sparkPhase1 * .pi) * 0.85)
                        .scaleEffect(CGFloat(0.6 + rc.sparkPhase1 * 0.4))

                    Circle()
                        .fill(Color(red: 1.0, green: 0.75, blue: 0.2))
                        .frame(width: 3, height: 3)
                        .offset(x: 7 - CGFloat(rc.sparkPhase2 * 6) + m.walkX, y: -23 - CGFloat(rc.sparkPhase2 * 10) + m.bobY)
                        .opacity(sin(rc.sparkPhase2 * .pi) * 0.75)
                }
            }
        }
    }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60.0)) { context in
            mascotContent(rc: makeRenderContext(now: context.date), time: context.date.timeIntervalSinceReferenceDate)
        }
        .frame(width: 140, height: 120, alignment: .bottom)
        .padding(.top, 14)
        .padding(.bottom, 12)
        .frame(width: 160, height: 148, alignment: .bottom)
        .contentShape(Rectangle())
        .onHover { hovering in
            isHovered = hovering
            model.isMascotHovered = hovering
            if hovering {
                lastActiveDate = Date()
            } else {
                hoverPoint = nil
            }
        }
        .onContinuousHover { phase in
            switch phase {
            case .active(let location):
                hoverPoint = location
            case .ended:
                hoverPoint = nil
            }
        }
        .onTapGesture {
            lastActiveDate = Date()
            spinStartTime = Date()
            showQuickMenu.toggle()
        }
            .popover(isPresented: $showQuickMenu, arrowEdge: .leading) {
                MascotQuickActionsPopover(model: model, isPresented: $showQuickMenu)
            }
            .contextMenu {
                // Submenu: Chọn hoạt cảnh Chip Chip
                Menu {
                    Picker("Hoạt cảnh Chip Chip", selection: $model.mascotIdleActivity) {
                        ForEach(MascotIdleActivity.allCases) { act in
                            HStack {
                                Image(systemName: act.icon)
                                Text(act.title)
                            }
                            .tag(act)
                        }
                    }
                } label: {
                    Label("Hoạt cảnh khi rảnh: \(model.mascotIdleActivity.shortTitle)", systemImage: model.mascotIdleActivity.icon)
                }

                // Toggle Đi dạo dưới Dock Bar (chỉ đi dạo khi rảnh rỗi)
                Button {
                    model.isDockWalkEnabled.toggle()
                } label: {
                    Label(
                        model.isDockWalkEnabled ? "Đi dạo dọc Dock Bar: Đang BẬT" : "Đi dạo dọc Dock Bar: Đang TẮT",
                        systemImage: model.isDockWalkEnabled ? "checkmark.circle.fill" : "figure.walk"
                    )
                }

                Divider()

                Button {
                    Task {
                        if model.running { await model.stop() }
                        else { await model.start() }
                    }
                } label: {
                    Label(model.running ? "Tạm dừng dịch" : "Bắt đầu dịch", systemImage: model.running ? "stop.fill" : "play.fill")
                }

                Button {
                    model.toggleOverlay()
                } label: {
                    Label(model.isOverlayVisible ? "Tắt phụ đề nổi" : "Bật phụ đề nổi", systemImage: model.isOverlayVisible ? "pip.exit" : "pip.enter")
                }

                Button {
                    model.showMainWindow()
                } label: {
                    Label("Mở TransTools", systemImage: "macwindow")
                }

                Menu {
                    Menu("Dịch & chỉnh câu") {
                        Button("Dịch từ bôi đen · Option + D") {
                            Task { await GlobalHotkeyManager.shared.triggerSelectionTranslation() }
                        }
                        Button("Dịch VI → EN · Option + E") {
                            Task { await GlobalHotkeyManager.shared.triggerVietnameseToEnglish() }
                        }
                        Button("Sửa ngữ pháp · Option + F") {
                            Task { await GlobalHotkeyManager.shared.triggerGrammarFixAndPolish() }
                        }
                    }
                    Button("Sổ từ vựng & Flashcards") {
                        model.showMainWindow()
                        model.selectedDashboardTab = 1
                        model.selectedNotebookTab = 1
                    }
                    Divider()
                    Button("Đưa Chip Chip về góc thuận tiện") {
                        model.snapMascotToConvenientPosition()
                    }
                } label: {
                    Label("Tiện ích Chip Chip", systemImage: "square.grid.2x2")
                }

                Button {
                    model.showMainWindow()
                    model.showAboutSheet = true
                } label: {
                    Label("Giới thiệu TransTools", systemImage: "info.circle")
                }

                Divider()

                Button {
                    model.hideFloatingMascot()
                } label: {
                    Label("Tạm biệt Chip Chip", systemImage: "xmark")
                }
            }
            .help("Chip Chip: \(model.isDockWalkEnabled ? "Đang đi dạo thư giãn dọc Dock Bar" : (model.running ? "Đang ghi chép cuộc họp" : "Sẵn sàng hỗ trợ bạn"))")
    }
}

struct MascotQuickActionsPopover: View {
    @ObservedObject var model: MeetingModel
    @ObservedObject private var tts = TTSService.shared
    @Binding var isPresented: Bool
    @Environment(\.dismiss) private var dismiss
    @State private var tipIndex = 0
    @State private var quickViText = ""
    @State private var quickEnResult = ""
    @State private var quickAlternatives: [TranslationAlternative] = []
    @State private var isTranslatingQuick = false
    @State private var quickCopied = false
    @State private var copiedReplyID: UUID? = nil
    @State private var copiedAltID: UUID? = nil

    private var mimoQuotes: [String] {
        [
            "Chip Chip sẵn sàng hỗ trợ bạn trong mọi cuộc họp! ✨",
            "Mẹo: Bạn có thể kéo Chip Chip đến bất kỳ vị trí nào trên màn hình đó nha! 🎈",
            "Mẹo: Bật 'Phụ đề nổi' để vừa họp Teams vừa xem bản dịch song song! 🎧",
            "Chip Chip luôn dịch bằng AI thông minh (\(model.provider.shortName)) cực mượt! ⚡",
            "Có Chip Chip ở đây rồi, bạn cứ tự tin nghe họp nhé! 💪"
        ]
    }

    private var currentDialogue: String {
        if model.running {
            return "Chip Chip đang chăm chú nghe & ghi chép bản dịch cuộc họp nè! 📝🎧"
        }
        if model.isDockWalkEnabled {
            return "Chip Chip đang đi dạo thảnh thơi dọc thanh Dock Bar nè! Bạn làm việc vui vẻ nha 🚶‍♂️✨"
        }
        switch model.mascotIdleActivity {
        case .writing: return "Chip Chip đang ghi lại ý tưởng vào sổ 📓"
        case .thinking: return "Để Chip Chip suy nghĩ một chút nhé 💭"
        case .fishing:
            return "Ngồi buông cần câu cá thảnh thơi bên hồ nước trong xanh... Yên bình ghê! 🎣🐟"
        case .sleeping:
            return "Khò khò... Chip Chip chợp mắt tí nha, khi nào bắt đầu họp cứ gọi tớ nhé! zZz 💤"
        case .strolling:
            return "Đi dạo vài bước quanh màn hình cho thư giãn gân cốt nào! 🚶‍♂️✨"
        case .catchingButterfly:
            return "Oa, có chú bướm xinh dập dờn bay qua nè! Đẹp quá đi mất 🦋✨"
        case .pickingFlowers:
            return "Bông hoa này ngát hương thơm thật đó! Tặng bạn một ngày làm việc thật vui nha 🌸"
        case .listeningMusic:
            return "Giai điệu này chill quá! Đeo tai nghe nhún nhảy chuẩn bị họp nè 🎧🎵"
        case .sippingTea:
            return "Nhâm nhi tách trà ấm thơm lừng cho tỉnh táo làm việc nhé bạn ơi! ☕️"
        case .auto:
            return mimoQuotes[tipIndex % mimoQuotes.count]
        }
    }

    private func translateAndCopyQuickText() {
        let trimmed = quickViText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        isTranslatingQuick = true

        var providerToUse = model.provider
        var keyToUse = model.key.trimmingCharacters(in: .whitespacesAndNewlines)
        var modelNameToUse = model.modelName

        if keyToUse.isEmpty && !model.coPilotKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && model.coPilotProvider != .apple && model.coPilotProvider != .free {
            providerToUse = model.coPilotProvider
            keyToUse = model.coPilotKey.trimmingCharacters(in: .whitespacesAndNewlines)
            modelNameToUse = model.coPilotModel
        }

        Task {
            do {
                let res = try await AITranslator.quickTranslateDetailed(
                    trimmed,
                    from: .vietnamese,
                    to: .english,
                    domain: model.domainSpecialty,
                    provider: providerToUse,
                    model: modelNameToUse,
                    key: keyToUse
                )
                await MainActor.run {
                    self.quickEnResult = res.primary
                    self.quickAlternatives = res.alternatives
                    self.isTranslatingQuick = false
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(res.primary, forType: .string)
                    self.quickCopied = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                        self.quickCopied = false
                    }
                }
            } catch {
                await MainActor.run {
                    self.quickEnResult = "Lỗi dịch: \(error.localizedDescription)"
                    self.quickAlternatives = []
                    self.isTranslatingQuick = false
                }
            }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Companion Header
            HStack(spacing: 9) {
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [TransToolsTheme.accent.opacity(0.18), TransToolsTheme.navy.opacity(0.10)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 36, height: 36)

                    MiniAvatarView(size: 32, style: model.mascotStyle, isWorking: model.running)
                }

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 5) {
                        Text("Chip Chip")
                            .font(.system(size: 13.5, weight: .bold, design: .rounded))
                        Text(model.mascotStyle == "pixel" ? "Pixel" : "Mascot ảnh")
                            .font(.system(size: 9.5, weight: .semibold))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1.5)
                            .background(Color.primary.opacity(0.06))
                            .foregroundStyle(.secondary)
                            .clipShape(Capsule())
                    }

                    HStack(spacing: 4) {
                        Circle()
                            .fill(model.running ? Color.green : TransToolsTheme.accent)
                            .frame(width: 6, height: 6)
                        Text(model.running ? "Đang lắng nghe • \(model.provider.shortName)" : "Sẵn sàng • Nghỉ ngơi")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(model.running ? Color.green : Color.secondary)
                    }
                }

                Spacer()

                Button {
                    withAnimation(.spring(response: 0.35)) {
                        model.mascotStyle = model.mascotStyle == "sprite" ? "pixel" : "sprite"
                    }
                } label: {
                    Image(systemName: model.mascotStyle == "sprite" ? "photo" : "checkerboard.rectangle")
                        .font(.system(size: 12, weight: .medium))
                        .padding(6)
                        .background(Color(nsColor: .controlBackgroundColor))
                        .foregroundStyle(TransToolsTheme.accent)
                        .clipShape(Circle())
                        .overlay(Circle().stroke(Color.primary.opacity(0.08), lineWidth: 0.8))
                }
                .buttonStyle(.plain)
                .help("Đổi tạo hình: Mascot ảnh ↔ Pixel Art")

                Button {
                    isPresented = false
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .bold))
                        .padding(6)
                        .background(Color(nsColor: .controlBackgroundColor))
                        .foregroundStyle(.secondary)
                        .clipShape(Circle())
                        .overlay(Circle().stroke(Color.primary.opacity(0.08), lineWidth: 0.8))
                }
                .buttonStyle(.plain)
                .help("Đóng (Esc)")
                .keyboardShortcut(.cancelAction)
            }

            // Mini Speech Bubble (Bong bóng lời thoại trò chuyện tươi sáng)
            Button {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                    tipIndex += 1
                }
            } label: {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "bubble.left.and.bubble.right.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(
                            LinearGradient(colors: [TransToolsTheme.accent, Color.cyan], startPoint: .topLeading, endPoint: .bottomTrailing)
                        )
                        .padding(.top, 1)

                    Text(currentDialogue)
                        .font(.system(size: 11.5, weight: .medium, design: .rounded))
                        .foregroundStyle(.primary)
                        .lineSpacing(2)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(9)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    LinearGradient(
                        colors: [
                            TransToolsTheme.accent.opacity(0.08),
                            Color.cyan.opacity(0.05)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .stroke(TransToolsTheme.accent.opacity(0.18), lineWidth: 1)
                )
            }
            .buttonStyle(.plain)
            .help("Bấm vào để đổi câu chuyện với Chip Chip")

            // Bộ chọn hoạt cảnh giải trí khi rảnh
            HStack(spacing: 6) {
                HStack(spacing: 4) {
                    Image(systemName: model.mascotIdleActivity.icon)
                        .foregroundStyle(TransToolsTheme.accent)
                        .font(.system(size: 10))
                    Text("Hoạt cảnh:")
                        .font(.system(size: 10.5, weight: .semibold))
                        .foregroundStyle(.secondary)
                }

                Menu {
                    Picker("Hoạt cảnh khi rảnh", selection: $model.mascotIdleActivity) {
                        ForEach(MascotIdleActivity.allCases) { act in
                            HStack {
                                Image(systemName: act.icon)
                                Text(act.title)
                            }
                            .tag(act)
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Text(model.mascotIdleActivity.shortTitle)
                            .font(.system(size: 10.5, weight: .bold))
                            .lineLimit(1)
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.system(size: 8))
                    }
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(Color.secondary.opacity(0.12))
                    .foregroundStyle(.primary)
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                }
                .menuStyle(.borderlessButton)

                Spacer()

                // Nút bật/tắt Đi dạo dọc Dock Bar
                Button {
                    model.isDockWalkEnabled.toggle()
                    if model.isDockWalkEnabled {
                        isPresented = false
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: model.isDockWalkEnabled ? "figure.walk.circle.fill" : "figure.walk")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(model.isDockWalkEnabled ? Color.green : Color.secondary)
                        Text(model.isDockWalkEnabled ? "Đi dạo: Bật" : "Đi dạo")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(model.isDockWalkEnabled ? Color.green : Color.secondary)
                    }
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(model.isDockWalkEnabled ? Color.green.opacity(0.14) : Color.secondary.opacity(0.10))
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                }
                .buttonStyle(.plain)
                .help("Chip Chip tự động đi dạo qua lại dọc theo thanh Dock Bar khi máy rảnh rỗi")
            }
            .padding(.horizontal, 2)

            // Mini Quick Chat (Khung Dịch nhanh sáng sủa, nền trắng tinh tế)
            VStack(alignment: .leading, spacing: 7) {
                HStack {
                    HStack(spacing: 4) {
                        Image(systemName: "bolt.fill")
                            .foregroundStyle(.orange)
                            .font(.system(size: 9.5))
                        Text("DỊCH NHANH VI → EN")
                            .font(.system(size: 9.5, weight: .bold))
                            .foregroundStyle(Color.orange)
                    }

                    Spacer()

                    // Menu chọn nhanh chuyên ngành dịch thuật
                    Menu {
                        ForEach(DomainSpecialty.allCases) { d in
                            Button {
                                model.domainSpecialty = d
                            } label: {
                                HStack {
                                    Image(systemName: d.icon)
                                    Text(d.title)
                                    if model.domainSpecialty == d {
                                        Image(systemName: "checkmark")
                                    }
                                }
                            }
                        }
                    } label: {
                        HStack(spacing: 3) {
                            Image(systemName: model.domainSpecialty.icon)
                                .font(.system(size: 8.5))
                            Text(model.domainSpecialty.shortName)
                                .font(.system(size: 9, weight: .bold))
                            Image(systemName: "chevron.down")
                                .font(.system(size: 7, weight: .bold))
                        }
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2.5)
                        .background(Color.orange.opacity(0.12))
                        .foregroundStyle(Color.orange)
                        .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .help("Chọn chuyên ngành: \(model.domainSpecialty.title)")

                    if quickCopied {
                        HStack(spacing: 3) {
                            Image(systemName: "checkmark.circle.fill")
                            Text("Đã copy")
                        }
                        .font(.system(size: 9.5, weight: .bold))
                        .foregroundStyle(Color.green)
                    }
                }

                // Gợi ý câu mẫu nhanh theo chuyên ngành đang chọn
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 5) {
                        ForEach(model.domainSpecialty.quickPhrases.prefix(5), id: \.self) { phrase in
                            Button {
                                quickViText = phrase
                                translateAndCopyQuickText()
                            } label: {
                                Text(phrase)
                                    .font(.system(size: 9))
                                    .lineLimit(1)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 3)
                                    .background(Color(nsColor: .textBackgroundColor).opacity(0.9))
                                    .foregroundStyle(.primary)
                                    .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                                            .stroke(Color.primary.opacity(0.08), lineWidth: 0.8)
                                    )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                HStack(alignment: .bottom, spacing: 6) {
                    TextField("Gõ tiếng Việt, Enter để copy...", text: $quickViText, axis: .vertical)
                        .textFieldStyle(.plain)
                        .font(.system(size: 11.5))
                        .lineLimit(2...5)
                        .frame(minHeight: 36, alignment: .topLeading)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 7)
                        .background(Color(nsColor: .textBackgroundColor))
                        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .stroke(Color.primary.opacity(0.12), lineWidth: 1)
                        )
                        .onSubmit {
                            translateAndCopyQuickText()
                        }
                        .onChange(of: quickViText) { _, newValue in
                            if newValue.hasSuffix("\n") && !isTranslatingQuick {
                                quickViText = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
                                translateAndCopyQuickText()
                            }
                        }

                    Button {
                        translateAndCopyQuickText()
                    } label: {
                        if isTranslatingQuick {
                            ProgressView()
                                .controlSize(.mini)
                                .frame(width: 26, height: 26)
                        } else {
                            Image(systemName: "arrow.up.circle.fill")
                                .font(.system(size: 22))
                                .foregroundStyle(
                                    quickViText.trimmingCharacters(in: .whitespaces).isEmpty
                                        ? Color.secondary.opacity(0.35)
                                        : TransToolsTheme.accent
                                )
                        }
                    }
                    .buttonStyle(.plain)
                    .disabled(quickViText.trimmingCharacters(in: .whitespaces).isEmpty || isTranslatingQuick)
                    .padding(.bottom, 5)
                }

                if !quickEnResult.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(alignment: .top, spacing: 8) {
                            Text(quickEnResult)
                                .font(.system(size: 11, weight: .medium, design: .rounded))
                                .foregroundStyle(.primary)
                                .lineLimit(nil)
                                .fixedSize(horizontal: false, vertical: true)
                                .frame(maxWidth: .infinity, alignment: .leading)

                            HStack(spacing: 4) {
                                let isSpeakingQuick = tts.isSpeaking && tts.currentlySpeakingText == quickEnResult
                                Button {
                                    if isSpeakingQuick {
                                        tts.stop()
                                    } else {
                                        tts.speak(text: quickEnResult, language: .english)
                                    }
                                } label: {
                                    Image(systemName: isSpeakingQuick ? "speaker.wave.3.fill" : "speaker.wave.2")
                                        .font(.system(size: 10, weight: .bold))
                                        .foregroundStyle(isSpeakingQuick ? TransToolsTheme.accent : Color.secondary)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 4)
                                        .background(Color.secondary.opacity(0.12))
                                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                                }
                                .buttonStyle(.plain)
                                .help(isSpeakingQuick ? "Dừng đọc" : "Phát âm câu dịch tiếng Anh")

                                Button {
                                    NSPasteboard.general.clearContents()
                                    NSPasteboard.general.setString(quickEnResult, forType: .string)
                                    quickCopied = true
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { quickCopied = false }
                                } label: {
                                    HStack(spacing: 3) {
                                        Image(systemName: quickCopied ? "checkmark" : "doc.on.doc")
                                        Text(quickCopied ? "Đã copy" : "Copy")
                                    }
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundStyle(quickCopied ? Color.green : Color.white)
                                    .padding(.horizontal, 7)
                                    .padding(.vertical, 4)
                                    .background(quickCopied ? Color.green.opacity(0.2) : TransToolsTheme.accent)
                                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                                }
                                .buttonStyle(.plain)
                                .help("Copy lại câu dịch này")
                            }
                        }

                        // Hiển thị gợi ý các phương án khác nếu có
                        if !quickAlternatives.isEmpty {
                            Divider().opacity(0.3)
                            VStack(alignment: .leading, spacing: 4) {
                                ForEach(quickAlternatives) { alt in
                                    HStack(spacing: 6) {
                                        Button {
                                            NSPasteboard.general.clearContents()
                                            NSPasteboard.general.setString(alt.text, forType: .string)
                                            copiedAltID = alt.id
                                            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { copiedAltID = nil }
                                        } label: {
                                            HStack(spacing: 6) {
                                                Text(alt.tone)
                                                    .font(.system(size: 8.5, weight: .bold))
                                                    .padding(.horizontal, 4)
                                                    .padding(.vertical, 1.5)
                                                    .background(Color.secondary.opacity(0.12))
                                                    .clipShape(Capsule())

                                                Text(alt.text)
                                                    .font(.system(size: 10))
                                                    .lineLimit(1)
                                                    .foregroundStyle(.secondary)

                                                Spacer()

                                                Image(systemName: copiedAltID == alt.id ? "checkmark" : "doc.on.doc")
                                                    .font(.system(size: 9))
                                                    .foregroundStyle(copiedAltID == alt.id ? Color.green : .secondary)
                                            }
                                        }
                                        .buttonStyle(.plain)

                                        let isSpeakingAlt = tts.isSpeaking && tts.currentlySpeakingText == alt.text
                                        Button {
                                            if isSpeakingAlt {
                                                tts.stop()
                                            } else {
                                                tts.speak(text: alt.text, language: .english)
                                            }
                                        } label: {
                                            Image(systemName: isSpeakingAlt ? "speaker.wave.3.fill" : "speaker.wave.2")
                                                .font(.system(size: 9))
                                                .foregroundStyle(isSpeakingAlt ? TransToolsTheme.accent : .secondary)
                                        }
                                        .buttonStyle(.plain)
                                        .help("Nghe phát âm")
                                    }
                                }
                            }
                        }
                    }
                    .padding(8)
                    .background(TransToolsTheme.accent.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .stroke(TransToolsTheme.accent.opacity(0.20), lineWidth: 0.8)
                    )
                }
            }
            .padding(9)
            .background(Color(nsColor: .controlBackgroundColor).opacity(0.75))
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(Color.primary.opacity(0.08), lineWidth: 1)
            )

            // AI Smart Suggestions Preview (nếu có)
            if !model.suggestedReplies.isEmpty {
                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 4) {
                        Image(systemName: "sparkles")
                            .foregroundStyle(.purple)
                            .font(.system(size: 9.5))
                        Text("GỢI Ý PHẢN HỒI CUỘC HỌP")
                            .font(.system(size: 9.5, weight: .bold))
                            .foregroundStyle(.purple)
                    }

                    ForEach(model.suggestedReplies.prefix(2)) { reply in
                        HStack(spacing: 4) {
                            Button {
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString(reply.english, forType: .string)
                                copiedReplyID = reply.id
                                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { copiedReplyID = nil }
                            } label: {
                                HStack(alignment: .top, spacing: 6) {
                                    Text(reply.tone)
                                        .font(.system(size: 8.5, weight: .bold))
                                        .padding(.horizontal, 5)
                                        .padding(.vertical, 1.5)
                                        .background(TransToolsTheme.navy.opacity(0.15))
                                        .foregroundStyle(.purple)
                                        .clipShape(Capsule())

                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(reply.english)
                                            .font(.system(size: 10.5, weight: .semibold))
                                            .foregroundStyle(.primary)
                                            .lineLimit(1)
                                        Text(reply.vietnamese)
                                            .font(.system(size: 9.5))
                                            .foregroundStyle(.secondary)
                                            .lineLimit(1)
                                    }

                                    Spacer()

                                    Image(systemName: copiedReplyID == reply.id ? "checkmark.circle.fill" : "doc.on.doc")
                                        .font(.system(size: 10))
                                        .foregroundStyle(copiedReplyID == reply.id ? Color.green : .secondary)
                                }
                            }
                            .buttonStyle(.plain)

                            let isSpeakingRep = tts.isSpeaking && tts.currentlySpeakingText == reply.english
                            Button {
                                if isSpeakingRep {
                                    tts.stop()
                                } else {
                                    tts.speak(text: reply.english, language: .english)
                                }
                            } label: {
                                Image(systemName: isSpeakingRep ? "speaker.wave.3.fill" : "speaker.wave.2")
                                    .font(.system(size: 9.5))
                                    .foregroundStyle(isSpeakingRep ? TransToolsTheme.navy : .secondary)
                                    .padding(4)
                            }
                            .buttonStyle(.plain)
                            .help("Phát âm câu trả lời này")
                        }
                        .padding(6)
                        .background(Color(nsColor: .controlBackgroundColor).opacity(0.65))
                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .stroke(Color.primary.opacity(0.06), lineWidth: 0.8)
                        )
                    }
                }
            }

            Divider()
                .opacity(0.5)

            // 1. Play / Stop Action
            Button {
                isPresented = false
                Task {
                    if model.running { await model.stop() }
                    else { await model.start() }
                }
            } label: {
                HStack(spacing: 9) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(model.running ? Color.red : Color.green)
                            .frame(width: 24, height: 24)

                        Image(systemName: model.running ? "stop.fill" : "play.fill")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(.white)
                    }

                    Text(model.running ? "Tạm dừng phiên dịch" : "Bắt đầu dịch cuộc họp")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(model.running ? Color.red : Color.primary)

                    Spacer()
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .background(
                    model.running
                        ? Color.red.opacity(0.09)
                        : Color(nsColor: .controlBackgroundColor).opacity(0.85)
                )
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(model.running ? Color.red.opacity(0.25) : Color.primary.opacity(0.07), lineWidth: 1)
                )
            }
            .buttonStyle(.plain)

            // 2. Overlay Subtitles Toggle
            Button {
                isPresented = false
                model.toggleOverlay()
            } label: {
                HStack(spacing: 9) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(model.isOverlayVisible ? Color.orange : TransToolsTheme.accent)
                            .frame(width: 24, height: 24)

                        Image(systemName: model.isOverlayVisible ? "pip.exit" : "pip.enter")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(.white)
                    }

                    Text(model.isOverlayVisible ? "Tắt phụ đề nổi (HUD)" : "Bật phụ đề nổi (HUD)")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.primary)

                    Spacer()

                    if model.isOverlayVisible {
                        Text("Đang bật")
                            .font(.system(size: 9.5, weight: .bold))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1.5)
                            .background(Color.orange.opacity(0.15))
                            .foregroundStyle(Color.orange)
                            .clipShape(Capsule())
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .background(
                    model.isOverlayVisible
                        ? Color.orange.opacity(0.08)
                        : Color(nsColor: .controlBackgroundColor).opacity(0.85)
                )
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(model.isOverlayVisible ? Color.orange.opacity(0.25) : Color.primary.opacity(0.07), lineWidth: 1)
                )
            }
            .buttonStyle(.plain)

            // 3. Open Main Window
            Button {
                isPresented = false
                model.showMainWindow()
            } label: {
                HStack(spacing: 9) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(TransToolsTheme.navy)
                            .frame(width: 24, height: 24)

                        Image(systemName: "macwindow")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(.white)
                    }

                    Text("Mở bảng điều khiển chính")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.primary)

                    Spacer()
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .background(Color(nsColor: .controlBackgroundColor).opacity(0.85))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(Color.primary.opacity(0.07), lineWidth: 1)
                )
            }
            .buttonStyle(.plain)

            Menu {
                Menu("Dịch & chỉnh câu") {
                    Button("Dịch từ bôi đen · Option + D") {
                        isPresented = false
                        Task { await GlobalHotkeyManager.shared.triggerSelectionTranslation() }
                    }
                    Button("Dịch VI → EN · Option + E") {
                        isPresented = false
                        Task { await GlobalHotkeyManager.shared.triggerVietnameseToEnglish() }
                    }
                    Button("Sửa ngữ pháp · Option + F") {
                        isPresented = false
                        Task { await GlobalHotkeyManager.shared.triggerGrammarFixAndPolish() }
                    }
                }
                Button {
                    isPresented = false
                    model.showMainWindow()
                    model.selectedDashboardTab = 1
                    model.selectedNotebookTab = 1
                } label: {
                    Label("Sổ từ vựng & Flashcards", systemImage: "character.book.closed.fill")
                }
                Divider()
                Button {
                    isPresented = false
                    model.snapMascotToConvenientPosition()
                } label: {
                    Label("Đưa Chip Chip về góc thuận tiện", systemImage: "arrow.down.forward.and.arrow.up.backward")
                }
            } label: {
                Label("Tiện ích Chip Chip", systemImage: "square.grid.2x2")
                    .font(.system(size: 12, weight: .medium))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
            }
            .menuStyle(.borderlessButton)

            Divider()
                .opacity(0.5)

            // 5. Hide Mascot
            HStack {
                Button {
                    isPresented = false
                    model.hideFloatingMascot()
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "eye.slash")
                        Text("Tạm biệt Chip Chip")
                    }
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)

                Spacer()

                Text("TransTools")
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 4)
            .padding(.top, 1)
        }
        .padding(14)
        .frame(width: 334)
        .background(
            ZStack {
                Color(nsColor: .windowBackgroundColor)
                    .opacity(0.96)

                LinearGradient(
                    colors: [
                        Color.white.opacity(0.35),
                        Color.white.opacity(0.05)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            }
        )
        .enableAppleTranslationSession(source: .vietnamese, target: .english)
    }
}

// MARK: - Main Application Navigation & View

struct MainDashboardView: View {
    @ObservedObject var model: MeetingModel
    @ObservedObject private var updater = AppUpdater.shared

    var body: some View {
        VStack(spacing: 0) {
            // Modern Top Navigation Bar
            HStack(spacing: 16) {
                // App Brand with Chip Chip Avatar
                HStack(spacing: 8) {
                    MiniAvatarView(size: 26, style: model.mascotStyle, isWorking: model.running)
                        .help("Trợ lý Chip Chip")

                    Text("TransTools")
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .lineLimit(1)

                    Text(appVersionDisplay)
                        .font(.system(size: 10, weight: .bold))
                        .lineLimit(1)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.secondary.opacity(0.12))
                        .clipShape(Capsule())

                    AutoUpdateNavBadge()
                }
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)

                Spacer()

                // Custom Segmented Tab Control
                HStack(spacing: 4) {
                    NavTabButton(
                        title: "Cuộc họp",
                        icon: "waveform",
                        badge: model.running ? "LIVE" : nil,
                        badgeColor: .green,
                        isSelected: model.selectedDashboardTab == 0
                    ) {
                        withAnimation(.easeInOut(duration: 0.2)) { model.selectedDashboardTab = 0 }
                    }

                    NavTabButton(
                        title: "Sổ tay",
                        icon: "book.closed.fill",
                        badge: model.sessions.isEmpty ? nil : "\(model.sessions.count)",
                        badgeColor: .purple,
                        isSelected: model.selectedDashboardTab == 1
                    ) {
                        withAnimation(.easeInOut(duration: 0.2)) { model.selectedDashboardTab = 1 }
                    }

                    NavTabButton(
                        title: "Dịch nhanh",
                        icon: "character.bubble.fill",
                        badge: nil,
                        badgeColor: .blue,
                        isSelected: model.selectedDashboardTab == 2
                    ) {
                        withAnimation(.easeInOut(duration: 0.2)) { model.selectedDashboardTab = 2 }
                    }
                }
                .fixedSize(horizontal: true, vertical: false)
                .padding(4)
                .background(Color(nsColor: .controlBackgroundColor).opacity(0.8))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(Color.primary.opacity(0.06), lineWidth: 1)
                )

                Spacer()

                // Quick Action Buttons
                HStack(spacing: 8) {
                    Button {
                        model.toggleFloatingMascot()
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: model.isFloatingMascotVisible ? "sparkles.tv.fill" : "sparkles.tv")
                            Text("Trợ lý Chip Chip")
                                .lineLimit(1)
                                .fixedSize(horizontal: true, vertical: false)
                        }
                        .font(.system(size: 12, weight: .medium))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(model.isFloatingMascotVisible ? TransToolsTheme.accent.opacity(0.15) : Color.secondary.opacity(0.1))
                        .foregroundStyle(model.isFloatingMascotVisible ? TransToolsTheme.accent : Color.primary)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .fixedSize(horizontal: true, vertical: false)
                    .help("Bật/Tắt trợ lý Chip Chip nổi trên màn hình để thao tác nhanh")

                    Menu {
                        Button("Bật ở phía trên (Top)") { model.positionOverlay(atTop: true) }
                        Button("Bật ở phía dưới (Bottom)") { model.positionOverlay(atTop: false) }
                        Button(model.isOverlayVisible ? "Ẩn phụ đề nổi" : "Hiện vị trí đã lưu") { model.toggleOverlay() }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: model.isOverlayVisible ? "pip.exit" : "pip.enter")
                            Text("Phụ đề nổi")
                                .lineLimit(1)
                                .fixedSize(horizontal: true, vertical: false)
                        }
                        .font(.system(size: 12, weight: .medium))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(model.isOverlayVisible ? TransToolsTheme.accent.opacity(0.15) : Color.secondary.opacity(0.1))
                        .foregroundStyle(model.isOverlayVisible ? TransToolsTheme.accent : Color.primary)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .fixedSize(horizontal: true, vertical: false)
                    .help(model.isOverlayVisible ? "Tắt cửa sổ phụ đề nổi" : "Mở cửa sổ phụ đề nổi luôn hiển thị trên cùng")

                    Button {
                        model.showAboutSheet.toggle()
                    } label: {
                        Image(systemName: "info.circle")
                            .font(.system(size: 13))
                            .padding(7)
                            .background(model.showAboutSheet ? TransToolsTheme.accent.opacity(0.15) : Color.secondary.opacity(0.1))
                            .foregroundStyle(model.showAboutSheet ? TransToolsTheme.accent : Color.primary)
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .help("Giới thiệu ứng dụng & Tác giả DuyNK-Tech")
                    .popover(isPresented: $model.showAboutSheet) {
                        AboutAppPopoverView(isPresented: $model.showAboutSheet)
                    }

                    Button {
                        model.showSettingsSheet.toggle()
                    } label: {
                        Image(systemName: "gearshape.fill")
                            .font(.system(size: 13))
                            .padding(7)
                            .background(model.key.isEmpty ? Color.orange.opacity(0.15) : Color.secondary.opacity(0.1))
                            .foregroundStyle(model.key.isEmpty ? Color.orange : Color.primary)
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .help("Cài đặt AI & Model")
                    .popover(isPresented: $model.showSettingsSheet) {
                        SettingsPopoverView(model: model, isPresented: $model.showSettingsSheet)
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
            .background(Color(nsColor: .windowBackgroundColor))
            .overlay(
                Divider()
                    .opacity(0.5),
                alignment: .bottom
            )

            // Body Content based on Tab
            Group {
                if model.selectedDashboardTab == 0 {
                    MeetingView(model: model)
                } else if model.selectedDashboardTab == 1 {
                    MeetingNotebookView(model: model)
                } else {
                    QuickTranslateView(model: model)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(minWidth: 860, minHeight: 640)
        .background(TransToolsTheme.background)
        .tint(TransToolsTheme.accent)
        .sheet(isPresented: $updater.showUpdateSheet) {
            UpdateSheetView(isPresented: $updater.showUpdateSheet)
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            Task {
                await model.refresh()
            }
        }
        .enableAppleTranslationSession(source: model.sourceLanguage, target: model.targetLanguage)
    }
}

// MARK: - Navigation Tab Button

struct NavTabButton: View {
    let title: String
    let icon: String
    let badge: String?
    let badgeColor: Color
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .medium))

                Text(title)
                    .font(.system(size: 13, weight: isSelected ? .semibold : .regular))
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)

                if let badge {
                    HStack(spacing: 3) {
                        if badge == "LIVE" {
                            Circle()
                                .fill(badgeColor)
                                .frame(width: 5, height: 5)
                        }
                        Text(badge)
                            .font(.system(size: 8.5, weight: .bold))
                            .lineLimit(1)
                    }
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1.5)
                    .background(badgeColor.opacity(0.18))
                    .foregroundStyle(badgeColor)
                    .clipShape(Capsule())
                }
            }
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
            .padding(.horizontal, 11)
            .padding(.vertical, 6)
            .background(isSelected ? Color(nsColor: .selectedControlColor).opacity(0.18) : Color.clear)
            .foregroundStyle(isSelected ? TransToolsTheme.accent : Color.secondary)
            .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Audio Source Selector Menu

struct AudioSourceSelectorMenu: View {
    @ObservedObject var model: MeetingModel

    var body: some View {
        Menu {
            Section("Nguồn toàn hệ thống") {
                Button {
                    model.source = "system"
                } label: {
                    Label("Âm thanh hệ thống (Toàn bộ app)", systemImage: model.source == "system" ? "checkmark" : "speaker.wave.3.fill")
                }
            }

            Section("Thử nghiệm") {
                Button {
                    model.source = "microphone"
                } label: {
                    Label("Microphone (Kiểm tra giọng nói)", systemImage: model.source == "microphone" ? "checkmark" : "mic.fill")
                }
            }

            if !model.applications.isEmpty {
                Section("Ứng dụng cụ thể") {
                    ForEach(model.applications, id: \.bundleIdentifier) { app in
                        Button {
                            model.source = app.bundleIdentifier
                        } label: {
                            Label(app.applicationName, systemImage: model.source == app.bundleIdentifier ? "checkmark" : "app.fill")
                        }
                    }
                }
            }

            Divider()

            Button {
                Task { await model.refresh() }
            } label: {
                Label("Tải lại danh sách ứng dụng", systemImage: "arrow.clockwise")
            }
        } label: {
            HStack(spacing: 7) {
                // Icon badge box
                ZStack {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(sourceColor.opacity(0.16))
                        .frame(width: 22, height: 22)

                    Image(systemName: sourceIcon)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(sourceColor)
                }

                // Clean single line title with tail truncation
                Text(sourceTitle)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .truncationMode(.tail)

                Spacer(minLength: 4)

                // Dropdown chevron
                Image(systemName: "chevron.down")
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .lineLimit(1)
            .padding(.horizontal, 10)
            .frame(minWidth: 150, maxWidth: 210)
            .frame(height: 36)
            .background(Color(nsColor: .controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .stroke(Color.primary.opacity(0.08), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .disabled(model.running || model.busy)
        .help("Chọn nguồn âm thanh cần nhận diện và dịch")
    }

    private var sourceTitle: String {
        switch model.source {
        case "system": return "Âm thanh hệ thống"
        case "microphone": return "Microphone máy"
        case "": return "Chọn nguồn âm thanh"
        default:
            return model.applications.first(where: { $0.bundleIdentifier == model.source })?.applicationName ?? model.source
        }
    }

    private var sourceSubtitle: String {
        switch model.source {
        case "system": return "Toàn bộ ứng dụng (Teams, Trình duyệt, Nhạc...)"
        case "microphone": return "Thử nghiệm nhận diện giọng nói"
        case "": return "Bấm để chọn nguồn âm thanh cần thu"
        default:
            return "Chỉ thu âm thanh từ ứng dụng này"
        }
    }

    private var sourceIcon: String {
        switch model.source {
        case "system": return "speaker.wave.3.fill"
        case "microphone": return "mic.fill"
        case "": return "waveform.badge.plus"
        default: return "app.fill"
        }
    }

    private var sourceColor: Color {
        switch model.source {
        case "system": return .blue
        case "microphone": return .green
        case "": return .secondary
        default: return .purple
        }
    }
}

// MARK: - Language Pair Selector & Quick Swap Menu

struct LanguagePairSelectorMenu: View {
    @ObservedObject var model: MeetingModel

    var body: some View {
        HStack(spacing: 4) {
            // Source Language Menu
            Menu {
                Section("Ngôn ngữ nguồn (Giọng nói/Micro)") {
                    ForEach(AppLanguage.allCases) { lang in
                        Button {
                            guard model.sourceLanguage != lang else { return }
                            model.sourceLanguage = lang
                            if model.running {
                                Task { await model.restartSpeechRecognition() }
                            }
                        } label: {
                            HStack {
                                Text("\(lang.flag) \(lang.displayName)")
                                if model.sourceLanguage == lang {
                                    Spacer()
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                }
            } label: {
                HStack(spacing: 5) {
                    Text(model.sourceLanguage.flag)
                        .font(.system(size: 13))
                    Text(model.sourceLanguage.shortName)
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 8, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
                .padding(.horizontal, 8)
                .frame(height: 36)
                .background(Color(nsColor: .controlBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .stroke(Color.primary.opacity(0.08), lineWidth: 1)
                )
            }
            .buttonStyle(.plain)
            .fixedSize(horizontal: true, vertical: false)
            .help("Chọn ngôn ngữ nguồn (nghe & nhận diện giọng nói)")

            // Quick Swap & Target Language Menu (Hidden when in Original Only mode)
            if model.subtitleMode != .originalOnly {
                // Quick Swap Button (⇄)
                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                        model.swapLanguages()
                    }
                    if model.running {
                        Task { await model.restartSpeechRecognition() }
                    }
                } label: {
                    ZStack {
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .fill(TransToolsTheme.accent.opacity(0.12))
                            .frame(width: 32, height: 36)
                            .overlay(
                                RoundedRectangle(cornerRadius: 9, style: .continuous)
                                    .stroke(TransToolsTheme.accent.opacity(0.25), lineWidth: 1)
                            )

                        Image(systemName: "arrow.left.arrow.right")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(TransToolsTheme.accent)
                    }
                }
                .buttonStyle(.plain)
                .fixedSize(horizontal: true, vertical: false)
                .help("Đổi chiều ngôn ngữ nhanh (⇄)")
                .transition(.scale(scale: 0.8).combined(with: .opacity))

                // Target Language Menu
                Menu {
                    Section("Ngôn ngữ đích (Phụ đề/Bản dịch)") {
                        ForEach(AppLanguage.allCases) { lang in
                            Button {
                                model.targetLanguage = lang
                            } label: {
                                HStack {
                                    Text("\(lang.flag) \(lang.displayName)")
                                    if model.targetLanguage == lang {
                                        Spacer()
                                        Image(systemName: "checkmark")
                                    }
                                }
                            }
                        }
                    }

                    Divider()

                    Section("Cặp ngôn ngữ thông dụng") {
                        presetButton(title: "🇺🇸 Tiếng Anh ⇄ 🇻🇳 Tiếng Việt", src: .english, dst: .vietnamese)
                        presetButton(title: "🇮🇳 Tiếng Anh (Ấn Độ) ➔ 🇻🇳 Tiếng Việt", src: .englishIndia, dst: .vietnamese)
                        presetButton(title: "🇮🇹 Tiếng Ý ⇄ 🇻🇳 Tiếng Việt", src: .italian, dst: .vietnamese)
                        presetButton(title: "🇻🇳 Tiếng Việt ⇄ 🇺🇸 Tiếng Anh", src: .vietnamese, dst: .english)
                        presetButton(title: "🇨🇳 Tiếng Trung ⇄ 🇻🇳 Tiếng Việt", src: .chinese, dst: .vietnamese)
                        presetButton(title: "🇻🇳 Tiếng Việt ⇄ 🇨🇳 Tiếng Trung", src: .vietnamese, dst: .chinese)
                        presetButton(title: "🇯🇵 Tiếng Nhật ⇄ 🇻🇳 Tiếng Việt", src: .japanese, dst: .vietnamese)
                        presetButton(title: "🇰🇷 Tiếng Hàn ⇄ 🇻🇳 Tiếng Việt", src: .korean, dst: .vietnamese)
                    }
                } label: {
                    HStack(spacing: 5) {
                        Text(model.targetLanguage.flag)
                            .font(.system(size: 13))
                        Text(model.targetLanguage.shortName)
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                        Image(systemName: "chevron.down")
                            .font(.system(size: 8, weight: .semibold))
                            .foregroundStyle(.secondary)
                    }
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                    .padding(.horizontal, 8)
                    .frame(height: 36)
                    .background(Color(nsColor: .controlBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .stroke(Color.primary.opacity(0.08), lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
                .fixedSize(horizontal: true, vertical: false)
                .help("Chọn ngôn ngữ dịch ra (phụ đề & ghi chú)")
                .transition(.scale(scale: 0.8).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.75), value: model.subtitleMode)
        .lineLimit(1)
        .fixedSize(horizontal: true, vertical: false)
    }

    private func presetButton(title: String, src: AppLanguage, dst: AppLanguage) -> some View {
        Button(title) {
            model.setLanguagePair(source: src, target: dst)
            if model.running {
                Task { await model.restartSpeechRecognition() }
            }
        }
    }
}

// MARK: - Subtitle Display Mode Selector Menu

struct SubtitleModeSelectorMenu: View {
    @ObservedObject var model: MeetingModel

    var body: some View {
        Menu {
            Section("Chế độ hiển thị phụ đề") {
                ForEach(SubtitleDisplayMode.allCases) { mode in
                    Button {
                        model.subtitleMode = mode
                    } label: {
                        HStack {
                            Label(mode.title, systemImage: mode.icon)
                            if model.subtitleMode == mode {
                                Spacer()
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: model.subtitleMode.icon)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(model.subtitleMode == .originalOnly ? Color.green : TransToolsTheme.accent)
                Text(model.subtitleMode.shortTitle)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Image(systemName: "chevron.down")
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
            .padding(.horizontal, 8)
            .frame(height: 36)
            .background(Color(nsColor: .controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .stroke(model.subtitleMode == .originalOnly ? Color.green.opacity(0.35) : Color.primary.opacity(0.08), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .fixedSize(horizontal: true, vertical: false)
        .help("Chế độ phụ đề: Song ngữ, Chỉ tiếng gốc (CC), hoặc Chỉ bản dịch")
    }
}

// MARK: - Earphone Text-to-Speech (TTS) Control Menu

struct EarphoneTTSControlMenu: View {
    @ObservedObject var model: MeetingModel
    @ObservedObject var tts = TTSService.shared

    private var activeLocale: String {
        tts.autoTarget == .translation ? model.targetLanguage.speechLocale : model.sourceLanguage.speechLocale
    }

    private var availableVoices: [TTSVoiceOption] {
        tts.availableVoices(for: activeLocale)
    }

    var body: some View {
        Menu {
            Section("Tai nghe & Đọc trực tiếp (TTS)") {
                Button {
                    tts.isAutoTTSEnabled.toggle()
                } label: {
                    HStack {
                        Label(tts.isAutoTTSEnabled ? "Tắt tự động đọc tai nghe" : "Bật tự động đọc tai nghe", systemImage: tts.isAutoTTSEnabled ? "headphones" : "headphones")
                        if tts.isAutoTTSEnabled {
                            Spacer()
                            Image(systemName: "checkmark")
                        }
                    }
                }

                Button {
                    let lang = (tts.autoTarget == .translation ? model.targetLanguage : model.sourceLanguage)
                    tts.preview(language: lang)
                } label: {
                    Label(tts.isSpeaking ? "Đang phát thử..." : "🔊 Nghe thử giọng đọc", systemImage: "speaker.wave.2")
                }

                if tts.isSpeaking {
                    Button(role: .destructive) {
                        tts.stop()
                    } label: {
                        Label("Dừng đọc ngay lập tức", systemImage: "stop.circle")
                    }
                }
            }

            Divider()

            Section("Nội dung đọc vào tai nghe") {
                ForEach(TTSService.AutoSpeakTarget.allCases) { target in
                    Button {
                        tts.autoTarget = target
                    } label: {
                        HStack {
                            Text(target.title)
                            if tts.autoTarget == target {
                                Spacer()
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            }

            Divider()

            Section("Phong cách giọng đọc (Tone & Cảm xúc)") {
                ForEach(VoiceTone.allCases) { tone in
                    Button {
                        tts.voiceTone = tone
                    } label: {
                        HStack {
                            Label(tone.title, systemImage: tone.icon)
                            if tts.voiceTone == tone {
                                Spacer()
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            }

            Divider()

            Section("Giọng đọc (\(tts.autoTarget == .translation ? model.targetLanguage.shortName : model.sourceLanguage.shortName))") {
                Button {
                    tts.selectedVoiceID = nil
                } label: {
                    HStack {
                        Text("✨ Tự động (Ưu tiên giọng AI tự nhiên nhất)")
                        if tts.selectedVoiceID == nil {
                            Spacer()
                            Image(systemName: "checkmark")
                        }
                    }
                }

                ForEach(availableVoices) { voice in
                    Button {
                        tts.selectedVoiceID = voice.id
                    } label: {
                        HStack {
                            Text(voice.displayName)
                            if tts.selectedVoiceID == voice.id {
                                Spacer()
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            }

            Divider()

            Section("Tốc độ giọng đọc") {
                Button("Rất chậm - Luyện nghe (0.40x)") { tts.speechRate = 0.40 }
                Button("Chậm rãi - Rõ từng chữ (0.44x)") { tts.speechRate = 0.44 }
                Button("Chuẩn tự nhiên - Khuyên dùng (0.46x)") { tts.speechRate = 0.46 }
                Button("Nhanh - Tốc độ họp (0.52x)") { tts.speechRate = 0.52 }
                Button("Rất nhanh (0.58x)") { tts.speechRate = 0.58 }
            }

            Divider()

            Section("Hệ thống") {
                Button {
                    if let url = URL(string: "x-apple.systempreferences:com.apple.Accessibility-Settings.extension?SpokenContent") {
                        NSWorkspace.shared.open(url)
                    }
                } label: {
                    Label("Mở Cài đặt Giọng nói máy Mac...", systemImage: "gearshape")
                }
            }
        } label: {
            HStack(spacing: 5) {
                ZStack {
                    Image(systemName: tts.isAutoTTSEnabled ? "headphones.circle.fill" : "headphones")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(tts.isAutoTTSEnabled ? TransToolsTheme.navy : Color.secondary)

                    if tts.isSpeaking {
                        Circle()
                            .fill(Color.green)
                            .frame(width: 5, height: 5)
                            .offset(x: 5, y: -5)
                    }
                }

                Text(tts.isAutoTTSEnabled ? "Tai nghe: BẬT" : "Tai nghe")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(tts.isAutoTTSEnabled ? TransToolsTheme.navy : Color.primary)
                    .lineLimit(1)

                Image(systemName: "chevron.down")
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
            .padding(.horizontal, 8)
            .frame(height: 36)
            .background(Color(nsColor: .controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .stroke(tts.isAutoTTSEnabled ? TransToolsTheme.navy.opacity(0.35) : Color.primary.opacity(0.08), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .fixedSize(horizontal: true, vertical: false)
        .help("Text to Speech (TTS) phát trực tiếp qua tai nghe: Tự động phiên dịch giọng nói thì thầm vào tai nghe hoặc nghe phát âm")
    }
}

// MARK: - Tab 1: Meeting & Live Captions

struct MeetingView: View {
    @ObservedObject var model: MeetingModel

    var body: some View {
        VStack(spacing: 12) {
            // Control Hub Card
            VStack(spacing: 8) {
                HStack(spacing: 8) {
                    // Audio Source Selector - Spacious Modern Menu
                    AudioSourceSelectorMenu(model: model)

                    // Standalone Quick Refresh Button
                    Button {
                        Task { await model.refresh(userInitiated: true) }
                    } label: {
                        ZStack {
                            RoundedRectangle(cornerRadius: 9, style: .continuous)
                                .fill(Color(nsColor: .controlBackgroundColor))
                                .frame(width: 32, height: 36)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                                        .stroke(Color.primary.opacity(0.08), lineWidth: 1)
                                )

                            Image(systemName: "arrow.clockwise")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .buttonStyle(.plain)
                    .fixedSize(horizontal: true, vertical: false)
                    .help("Tải lại danh sách ứng dụng")
                    .disabled(model.running || model.busy)

                    // Language Pair Selector & Quick Swap
                    LanguagePairSelectorMenu(model: model)
                        .layoutPriority(1)

                    // Subtitle Display Mode Selector
                    SubtitleModeSelectorMenu(model: model)
                        .layoutPriority(1)

                    // Earphone Text-to-Speech (TTS) Mode
                    EarphoneTTSControlMenu(model: model)
                        .layoutPriority(1)

                    Spacer(minLength: 8)

                    // Live Signal & Audio Monitor Pill
                    TimelineView(.periodic(from: .now, by: 1)) { context in
                        HStack(spacing: 6) {
                            Circle()
                                .fill(model.running ? Color.green : Color.gray.opacity(0.7))
                                .frame(width: 7, height: 7)
                                .shadow(color: model.running ? .green.opacity(0.8) : .clear, radius: 3)

                            if model.running {
                                let hasSignal = model.lastAudio.map { context.date.timeIntervalSince($0) < 3 } ?? false
                                HStack(spacing: 5) {
                                    Image(systemName: hasSignal ? "waveform" : "waveform.slash")
                                        .font(.system(size: 10))
                                    Text(hasSignal ? "Đang thu tín hiệu" : "Chờ âm thanh...")
                                        .font(.system(size: 11, weight: .semibold))
                                }
                                .foregroundStyle(hasSignal ? .green : .secondary)
                            } else {
                                Text("Sẵn sàng")
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(.horizontal, 12)
                        .frame(height: 36)
                        .background(Color(nsColor: .controlBackgroundColor))
                        .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 9, style: .continuous)
                                .stroke(Color.primary.opacity(0.06), lineWidth: 1)
                        )
                    }

                    // Prominent Start / Stop Button
                    Button {
                        Task {
                            if model.running {
                                await model.stop()
                            } else {
                                await model.start()
                            }
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: model.running ? "stop.fill" : "play.fill")
                                .font(.system(size: 11, weight: .bold))

                            Text(model.running ? "Dừng phiên" : "Bắt đầu")
                                .font(.system(size: 12, weight: .bold))
                        }
                        .padding(.horizontal, 16)
                        .frame(height: 36)
                        .foregroundStyle(.white)
                        .background(
                            model.running
                                ? LinearGradient(colors: [Color.red, Color(red: 0.85, green: 0.2, blue: 0.2)], startPoint: .topLeading, endPoint: .bottomTrailing)
                                : LinearGradient(colors: [TransToolsTheme.accent, TransToolsTheme.navy], startPoint: .topLeading, endPoint: .bottomTrailing)
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                        .shadow(
                            color: (model.running ? Color.red : TransToolsTheme.accent).opacity(0.25),
                            radius: 6,
                            y: 2
                        )
                    }
                    .buttonStyle(.plain)
                    .disabled(model.busy)
                }

                // Status or Warning Banner
                if !model.warning.isEmpty {
                    HStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                        Text(model.warning)
                            .font(.system(size: 12))
                            .foregroundStyle(.orange)

                        Spacer()

                        if model.warning.localizedCaseInsensitiveContains("Dictation") || model.warning.localizedCaseInsensitiveContains("Siri") {
                            Button {
                                model.promptPermissionSettings(for: .dictation)
                            } label: {
                                HStack(spacing: 4) {
                                    Image(systemName: "keyboard")
                                    Text("Mở Cài đặt Bàn phím")
                                }
                                .font(.system(size: 11, weight: .bold))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(Color.orange)
                                .foregroundStyle(.white)
                                .clipShape(Capsule())
                            }
                            .buttonStyle(.plain)
                        } else if model.warning.localizedCaseInsensitiveContains("Microphone") {
                            Button {
                                model.promptPermissionSettings(for: .microphone)
                            } label: {
                                HStack(spacing: 4) {
                                    Image(systemName: "mic.fill")
                                    Text("Cấp quyền Microphone")
                                }
                                .font(.system(size: 11, weight: .bold))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(Color.orange)
                                .foregroundStyle(.white)
                                .clipShape(Capsule())
                            }
                            .buttonStyle(.plain)
                        } else if model.warning.localizedCaseInsensitiveContains("Speech Recognition") {
                            Button {
                                model.promptPermissionSettings(for: .speechRecognition)
                            } label: {
                                HStack(spacing: 4) {
                                    Image(systemName: "waveform.and.mic")
                                    Text("Cấp quyền Nhận diện giọng nói")
                                }
                                .font(.system(size: 11, weight: .bold))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(Color.orange)
                                .foregroundStyle(.white)
                                .clipShape(Capsule())
                            }
                            .buttonStyle(.plain)
                        } else if model.warning.localizedCaseInsensitiveContains("màn hình") || model.warning.localizedCaseInsensitiveContains("Screen") || model.warning.localizedCaseInsensitiveContains("TCC") {
                            HStack(spacing: 8) {
                                Button {
                                    model.promptPermissionSettings(for: .screenCapture)
                                } label: {
                                    HStack(spacing: 4) {
                                        Image(systemName: "lock.shield.fill")
                                        Text("Cấp quyền trong Cài đặt")
                                    }
                                    .font(.system(size: 11, weight: .bold))
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 5)
                                    .background(Color.orange)
                                    .foregroundStyle(.white)
                                    .clipShape(Capsule())
                                }
                                .buttonStyle(.plain)

                                Button {
                                    model.restartApp()
                                } label: {
                                    HStack(spacing: 4) {
                                        Image(systemName: "arrow.clockwise.circle.fill")
                                        Text("Khởi động lại App để áp dụng")
                                    }
                                    .font(.system(size: 11, weight: .bold))
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 5)
                                    .background(TransToolsTheme.accent)
                                    .foregroundStyle(.white)
                                    .clipShape(Capsule())
                                }
                                .buttonStyle(.plain)
                                .help("macOS yêu cầu khởi động lại ứng dụng sau khi bật quyền Screen & System Audio")
                            }
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color.orange.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color(nsColor: .controlBackgroundColor).opacity(0.6))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Color.primary.opacity(0.06), lineWidth: 1)
            )

            // Permanent Keyboard Shortcut & Developer Phrases Guide on Main Dashboard
            KeyboardShortcutGuideCard()

            // Subtitle Stream Section
            ZStack {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color(nsColor: .controlBackgroundColor).opacity(0.3))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(Color.primary.opacity(0.06), lineWidth: 1)
                    )

                if model.captions.isEmpty {
                    if model.running {
                        VStack(spacing: 16) {
                            if model.showMascot {
                                MiniAvatarView(size: 100, style: model.mascotStyle, isWorking: true)
                                    .padding(.bottom, 2)
                            } else {
                                HStack(spacing: 4) {
                                    ForEach(0..<5) { i in
                                        RoundedRectangle(cornerRadius: 1.5)
                                            .fill(LinearGradient(colors: [.green, .teal], startPoint: .top, endPoint: .bottom))
                                            .frame(width: 3.5, height: CGFloat(10 + (i % 3) * 8))
                                    }
                                }
                                .padding(.bottom, 4)
                            }

                            VStack(spacing: 6) {
                                Text("Đang lắng nghe âm thanh...")
                                    .font(.system(size: 16, weight: .bold, design: .rounded))

                                Text(model.lastAudio != nil
                                    ? "Đã kết nối luồng âm thanh! Phụ đề đang hiển thị theo thời gian thực khi có người nói..."
                                    : "Đang chờ phát hiện giọng nói từ nguồn âm thanh đã chọn...")
                                    .font(.system(size: 13))
                                    .foregroundStyle(.secondary)
                                    .multilineTextAlignment(.center)
                                    .frame(maxWidth: 420)
                            }
                        }
                        .padding(32)
                        .transition(.opacity)
                    } else {
                        VStack(spacing: 16) {
                            if model.showMascot {
                                MiniAvatarView(size: 110, style: model.mascotStyle)
                                    .padding(.bottom, 4)
                            } else {
                                Image(systemName: "waveform.badge.mic")
                                    .font(.system(size: 46))
                                    .foregroundStyle(LinearGradient(colors: [.blue, .purple], startPoint: .topLeading, endPoint: .bottomTrailing))
                                    .padding(.bottom, 4)
                            }

                            VStack(spacing: 6) {
                                Text("Sẵn sàng nghe & phiên dịch")
                                    .font(.system(size: 17, weight: .bold, design: .rounded))

                                Text("Chọn nguồn âm thanh (Âm thanh hệ thống hoặc Teams) rồi bấm Bắt đầu.")
                                    .font(.system(size: 13))
                                    .foregroundStyle(.secondary)
                                    .multilineTextAlignment(.center)
                                    .frame(maxWidth: 420)
                            }

                            // Feature badges
                            HStack(spacing: 12) {
                                FeatureBadge(icon: "lock.shield", text: "Nhận diện tiếng Anh offline")
                                FeatureBadge(icon: "sparkles", text: "\(model.provider.shortName) dịch tiếng Việt")
                                FeatureBadge(icon: "speaker.wave.3", text: "Thu mọi âm thanh hệ thống")
                            }
                            .padding(.top, 4)
                        }
                        .padding(32)
                    }
                } else {
                    ScrollViewReader { proxy in
                        ScrollView {
                            LazyVStack(spacing: 12) {
                                ForEach(model.captions) { row in
                                    CaptionCardView(
                                        caption: row,
                                        isLive: (row.id == model.currentID && model.running),
                                        mode: model.subtitleMode,
                                        sourceLanguage: model.sourceLanguage,
                                        targetLanguage: model.targetLanguage
                                    )
                                    .id(row.id)
                                }

                                // Khoảng hở dưới đáy giúp card cuối không bị dính sát mép dưới container
                                Color.clear
                                    .frame(height: 38)
                                    .id("SCROLL_BOTTOM_ANCHOR")
                            }
                            .padding(.horizontal, 16)
                            .padding(.top, 16)
                            .padding(.bottom, 8)
                        }
                        .onChange(of: model.captions.last?.original) { _, _ in
                            proxy.scrollTo("SCROLL_BOTTOM_ANCHOR", anchor: .bottom)
                        }
                        .onChange(of: model.captions.count) { _, _ in
                            withAnimation(.easeOut(duration: 0.25)) {
                                proxy.scrollTo("SCROLL_BOTTOM_ANCHOR", anchor: .bottom)
                            }
                        }
                    }
                }
            }

            // Bottom Toolbar / Status & Export Bar
            HStack(spacing: 12) {
                HStack(spacing: 6) {
                    Text("\(model.captions.count)")
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.secondary.opacity(0.15))
                        .clipShape(Capsule())

                    Text("đoạn phụ đề • \(model.sourceLanguage.shortName) → \(model.targetLanguage.shortName) • \(model.subtitleMode.shortTitle)")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if !model.captions.isEmpty && !model.running {
                    Button {
                        model.clearCaptions()
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "trash")
                            Text("Xóa bảng ghi")
                        }
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color.secondary.opacity(0.1))
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }

                HStack(spacing: 8) {
                    Button {
                        model.saveCurrentSession()
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: "book.closed.fill")
                            Text("Lưu Sổ tay")
                        }
                        .font(.system(size: 12, weight: .semibold))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(TransToolsTheme.navy.opacity(0.15))
                        .foregroundStyle(TransToolsTheme.navy)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .disabled(model.captions.isEmpty)
                    .help("Lưu toàn bộ hội thoại cuộc họp vào Sổ tay để xem lại bất cứ lúc nào")

                    Button {
                        model.exportCurrentDocx()
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: "doc.richtext.fill")
                            Text("Xuất Word")
                        }
                        .font(.system(size: 12, weight: .medium))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(TransToolsTheme.accent.opacity(0.15))
                        .foregroundStyle(TransToolsTheme.accent)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .disabled(model.captions.isEmpty || model.running)
                    .help("Xuất biên bản cuộc họp và bảng hội thoại song ngữ sang Microsoft Word (.docx)")

                    Button {
                        model.export(srt: false)
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: "doc.text")
                            Text("Xuất TXT")
                        }
                        .font(.system(size: 12, weight: .medium))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color.secondary.opacity(0.1))
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .disabled(model.captions.isEmpty || model.running)

                    Button {
                        model.export(srt: true)
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: "captions.bubble.fill")
                            Text("Xuất SRT")
                        }
                        .font(.system(size: 12, weight: .medium))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color.secondary.opacity(0.1))
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .disabled(model.captions.isEmpty || model.running)
                }
            }
            .padding(.horizontal, 4)
        }
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .padding(.bottom, 14)
    }
}

// MARK: - Caption Card View

struct CaptionCardView: View {
    let caption: Caption
    var isLive: Bool = false
    var mode: SubtitleDisplayMode = .bilingual
    var sourceLanguage: AppLanguage = .english
    var targetLanguage: AppLanguage = .vietnamese
    @ObservedObject private var tts = TTSService.shared
    @State private var copiedOriginal = false
    @State private var copiedVietnamese = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header Row: Timestamp + Actions
            HStack(spacing: 8) {
                HStack(spacing: 4) {
                    Image(systemName: "clock")
                        .font(.system(size: 10))
                    Text(MeetingModel.timestamp(caption.start))
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                }
                .foregroundStyle(.secondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Color.secondary.opacity(0.1))
                .clipShape(Capsule())

                if isLive {
                    HStack(spacing: 4) {
                        Circle()
                            .fill(Color.green)
                            .frame(width: 6, height: 6)
                        Text("Đang nói…")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(Color.green)
                    }
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2.5)
                    .background(Color.green.opacity(0.12))
                    .clipShape(Capsule())
                }

                if tts.isSpeaking && (tts.currentlySpeakingCaptionID == caption.id || tts.currentlySpeakingText == caption.original || tts.currentlySpeakingText == caption.vietnamese) {
                    HStack(spacing: 3) {
                        Image(systemName: "headphones")
                        Image(systemName: "waveform")
                    }
                    .font(.system(size: 9.5, weight: .bold))
                    .foregroundStyle(TransToolsTheme.navy)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2.5)
                    .background(TransToolsTheme.navy.opacity(0.12))
                    .clipShape(Capsule())
                }

                Spacer()

                // Speak Original Button
                if mode != .translationOnly && !caption.original.isEmpty {
                    let isSpeakingOrig = tts.isSpeaking && tts.currentlySpeakingText == caption.original
                    Button {
                        if isSpeakingOrig {
                            tts.stop()
                        } else {
                            tts.speak(id: caption.id, text: caption.original, language: sourceLanguage)
                        }
                    } label: {
                        HStack(spacing: 3) {
                            Image(systemName: isSpeakingOrig ? "speaker.wave.3.fill" : "speaker.wave.2")
                            Text("Đọc")
                        }
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(isSpeakingOrig ? TransToolsTheme.accent : .secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(isSpeakingOrig ? TransToolsTheme.accent.opacity(0.15) : Color.secondary.opacity(0.08))
                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .help("Nghe phát âm tiếng gốc (\(sourceLanguage.displayName))")
                }

                // Copy Original Button
                if mode != .translationOnly && !caption.original.isEmpty {
                    Button {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(caption.original, forType: .string)
                        copiedOriginal = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { copiedOriginal = false }
                    } label: {
                        HStack(spacing: 3) {
                            Image(systemName: copiedOriginal ? "checkmark" : "doc.on.doc")
                            Text(sourceLanguage.shortName.uppercased())
                        }
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(copiedOriginal ? .green : .secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(Color.secondary.opacity(0.08))
                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .help("Sao chép câu tiếng gốc")
                }

                // Speak Translation Button
                if mode != .originalOnly && !caption.vietnamese.isEmpty {
                    let isSpeakingTrans = tts.isSpeaking && tts.currentlySpeakingText == caption.vietnamese
                    Button {
                        if isSpeakingTrans {
                            tts.stop()
                        } else {
                            tts.speak(id: caption.id, text: caption.vietnamese, language: targetLanguage)
                        }
                    } label: {
                        HStack(spacing: 3) {
                            Image(systemName: isSpeakingTrans ? "speaker.wave.3.fill" : "speaker.wave.2")
                            Text("Dịch")
                        }
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(isSpeakingTrans ? Color.green : .secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(isSpeakingTrans ? Color.green.opacity(0.15) : Color.secondary.opacity(0.08))
                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .help("Nghe bản dịch (\(targetLanguage.displayName))")
                }

                // Copy Translation Button
                if mode != .originalOnly && !caption.vietnamese.isEmpty {
                    Button {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(caption.vietnamese, forType: .string)
                        copiedVietnamese = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { copiedVietnamese = false }
                    } label: {
                        HStack(spacing: 3) {
                            Image(systemName: copiedVietnamese ? "checkmark" : "doc.on.doc")
                            Text(targetLanguage.shortName.uppercased())
                        }
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(copiedVietnamese ? .green : .secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(Color.secondary.opacity(0.08))
                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .help("Sao chép bản dịch")
                }
            }

            // Original Source Text
            if mode != .translationOnly {
                HStack(alignment: .top, spacing: 8) {
                    Text(sourceLanguage.shortName.uppercased())
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.blue.opacity(0.8))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(TransToolsTheme.accent.opacity(0.12))
                        .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                        .padding(.top, 1)

                    Text(caption.original)
                        .font(.system(size: mode == .originalOnly ? 15 : 14, weight: mode == .originalOnly ? .semibold : .regular))
                        .foregroundStyle(mode == .originalOnly ? .primary : .secondary)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }

            // Translation Text
            if mode != .originalOnly {
                HStack(alignment: .top, spacing: 8) {
                    Text(targetLanguage.shortName.uppercased())
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.green.opacity(0.9))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(Color.green.opacity(0.12))
                        .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                        .padding(.top, 2)

                    if caption.vietnamese.isEmpty {
                        HStack(spacing: 6) {
                            ProgressView().controlSize(.small)
                            Text("Đang dịch AI…")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundStyle(.secondary)
                        }
                    } else {
                        Text(caption.vietnamese)
                            .font(.system(size: 15, weight: .semibold, design: .rounded))
                            .foregroundStyle(.primary)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(isLive ? TransToolsTheme.accent.opacity(0.35) : Color.primary.opacity(0.06), lineWidth: isLive ? 1.5 : 1)
        )
        .shadow(color: isLive ? TransToolsTheme.accent.opacity(0.08) : Color.black.opacity(0.03), radius: isLive ? 8 : 4, y: isLive ? 2 : 1)
        .animation(.easeInOut(duration: 0.25), value: isLive)
    }
}

// MARK: - Feature Badge Pill

struct FeatureBadge: View {
    let icon: String
    let text: String

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: icon)
                .font(.system(size: 11))
                .foregroundStyle(TransToolsTheme.accent)
            Text(text)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(Capsule())
        .overlay(Capsule().stroke(Color.primary.opacity(0.06), lineWidth: 1))
    }
}

// MARK: - Tab 2: Quick Translate (Đa chuyên ngành & Gợi ý thông minh)

struct QuickTranslateView: View {
    @ObservedObject var model: MeetingModel
    @State private var input = ""
    @State private var output = ""
    @State private var translationResult = QuickTranslationResult()
    @State private var translating = false
    @State private var error = ""
    @State private var copied = false
    @State private var copiedAltID: UUID? = nil
    @State private var polishing = false
    @State private var lastActionWasPolish = false
    @State private var polishedLanguage: AppLanguage = .english

    var body: some View {
        VStack(spacing: 14) {
            specialtyBar

            suggestionBar

            languageActionBar

            translationStudio

            if model.key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && model.provider != .free && model.provider != .apple {
                HStack(spacing: 8) {
                    Image(systemName: "info.circle.fill")
                        .foregroundStyle(.blue)
                    Text("Đang dùng bộ dịch nhanh Google Free (miễn phí). Nhập \(model.provider.displayName) API Key trong Cài đặt nếu bạn muốn nhận đầy đủ gợi ý và phong cách dịch AI chuẩn.")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(TransToolsTheme.accent.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
        }
        .padding(20)
        .enableAppleTranslationSession(source: model.sourceLanguage, target: model.targetLanguage)
    }


    private var specialtyBar: some View {
            // 1. Chuyên ngành dịch thuật Selector Bar (Dropdown Menu đồng bộ với Cài đặt)
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Image(systemName: "character.book.closed.fill")
                            .foregroundStyle(TransToolsTheme.accent)
                            .font(.system(size: 13))
                        Text("Chuyên ngành dịch thuật:")
                            .font(.system(size: 13, weight: .bold))
                    }
                    Text("AI tự động tối ưu hóa ngữ cảnh và thuật ngữ theo từng lĩnh vực")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Menu {
                    ForEach(DomainSpecialty.allCases) { d in
                        Button {
                            withAnimation(.easeInOut(duration: 0.15)) {
                                model.domainSpecialty = d
                            }
                        } label: {
                            if model.domainSpecialty == d {
                                Label(d.title + " (Đang chọn)", systemImage: "checkmark")
                            } else {
                                Label(d.title, systemImage: d.icon)
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: model.domainSpecialty.icon)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(TransToolsTheme.accent)
                            .frame(width: 18)

                        Text(model.domainSpecialty.title)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.primary)

                        Image(systemName: "chevron.up.chevron.down")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 12)
                    .frame(height: 34)
                    .background(Color(nsColor: .controlBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(Color.primary.opacity(0.12), lineWidth: 1)
                    )
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color(nsColor: .controlBackgroundColor).opacity(0.6))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Color.primary.opacity(0.06), lineWidth: 1)
            )

    }

    private var suggestionBar: some View {
            // 2. Gợi ý mẫu câu nhanh theo chuyên ngành (Interactive Suggestion Chips)
            HStack(spacing: 8) {
                HStack(spacing: 4) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 11))
                        .foregroundStyle(.purple)
                    Text("Gợi ý mẫu:")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.purple)
                }

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(model.domainSpecialty.quickPhrases, id: \.self) { phrase in
                            Button {
                                input = phrase
                                translateNow()
                            } label: {
                                HStack(spacing: 4) {
                                    Image(systemName: "plus.circle.fill")
                                        .font(.system(size: 9))
                                        .foregroundStyle(TransToolsTheme.accent)
                                    Text(phrase)
                                        .font(.system(size: 11))
                                        .lineLimit(1)
                                }
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color(nsColor: .controlBackgroundColor))
                                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                                        .stroke(Color.primary.opacity(0.08), lineWidth: 0.8)
                                )
                            }
                            .buttonStyle(.plain)
                            .help("Bấm để chèn và dịch ngay câu này")
                        }
                    }
                }
            }
            .padding(.horizontal, 4)

    }

    private var languageActionBar: some View {
            // 3. Language Selector Bar (Nút chuyển đổi ngôn ngữ nằm ở phía trên ngang hàng ngôn ngữ) & Action Buttons
            HStack(spacing: 10) {
                // Ngôn ngữ nguồn
                Menu {
                    ForEach(AppLanguage.allCases) { lang in
                        Button {
                            model.sourceLanguage = lang
                        } label: {
                            HStack {
                                Text("\(lang.flag) \(lang.displayName)")
                                if model.sourceLanguage == lang {
                                    Spacer()
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 6) {
                        Text(model.sourceLanguage.shortName)
                            .font(.system(size: 10, weight: .bold))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(Color.green.opacity(0.15))
                            .foregroundStyle(.green)
                            .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))

                        Text("\(model.sourceLanguage.flag) \(model.sourceLanguage.displayName)")
                            .font(.system(size: 12.5, weight: .semibold))

                        Image(systemName: "chevron.down")
                            .font(.system(size: 8, weight: .semibold))
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 10)
                    .frame(height: 32)
                    .background(Color(nsColor: .controlBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(Color.primary.opacity(0.12), lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)

                // Nút Swap ⇄ (Nằm ngang hàng với 2 ngôn ngữ phía trên)
                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                        model.swapLanguages()
                        let oldOutput = output
                        if !oldOutput.isEmpty {
                            output = input
                            input = oldOutput
                            translationResult = QuickTranslationResult(primary: output)
                        }
                    }
                } label: {
                    ZStack {
                        Circle()
                            .fill(Color(nsColor: .controlBackgroundColor))
                            .frame(width: 32, height: 32)
                            .overlay(
                                Circle()
                                    .stroke(TransToolsTheme.accent.opacity(0.25), lineWidth: 1)
                            )

                        Image(systemName: "arrow.left.arrow.right")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(TransToolsTheme.accent)
                    }
                }
                .buttonStyle(.plain)
                .help("Đổi chiều ngôn ngữ & hoán đổi nội dung (⇄)")

                // Ngôn ngữ đích
                Menu {
                    ForEach(AppLanguage.allCases) { lang in
                        Button {
                            model.targetLanguage = lang
                        } label: {
                            HStack {
                                Text("\(lang.flag) \(lang.displayName)")
                                if model.targetLanguage == lang {
                                    Spacer()
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 6) {
                        Text(model.targetLanguage.shortName)
                            .font(.system(size: 10, weight: .bold))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(TransToolsTheme.accent.opacity(0.15))
                            .foregroundStyle(.blue)
                            .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))

                        Text("\(model.targetLanguage.flag) \(model.targetLanguage.displayName)")
                            .font(.system(size: 12.5, weight: .semibold))

                        Image(systemName: "chevron.down")
                            .font(.system(size: 8, weight: .semibold))
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 10)
                    .frame(height: 32)
                    .background(Color(nsColor: .controlBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(Color.primary.opacity(0.12), lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)

                Spacer()

                // Nút Sửa lỗi & Làm mượt theo ngôn ngữ chọn (Fix & Polish)
                HStack(spacing: 0) {
                    Button {
                        polishLanguageNow(lang: model.sourceLanguage)
                    } label: {
                        HStack(spacing: 5) {
                            if polishing {
                                ProgressView()
                                    .controlSize(.small)
                            } else {
                                Image(systemName: "sparkles")
                                    .font(.system(size: 11, weight: .semibold))
                            }
                            Text("Sửa ngữ pháp (\(model.sourceLanguage.shortName))")
                                .font(.system(size: 12, weight: .semibold))
                        }
                        .padding(.leading, 10)
                        .padding(.trailing, 6)
                        .frame(height: 32)
                    }
                    .buttonStyle(.plain)

                    Menu {
                        Button {
                            polishLanguageNow(lang: model.sourceLanguage)
                        } label: {
                            Label("Sửa ngữ pháp theo \(model.sourceLanguage.displayName) (Nguồn)", systemImage: "checkmark")
                        }
                        Button {
                            polishLanguageNow(lang: model.targetLanguage)
                        } label: {
                            Text("Sửa ngữ pháp theo \(model.targetLanguage.displayName) (Đích)")
                        }
                        Divider()
                        ForEach(AppLanguage.allCases.filter { $0 != model.sourceLanguage && $0 != model.targetLanguage }) { lang in
                            Button {
                                polishLanguageNow(lang: lang)
                            } label: {
                                Text("\(lang.flag) \(lang.displayName)")
                            }
                        }
                    } label: {
                        Image(systemName: "chevron.down")
                            .font(.system(size: 8, weight: .bold))
                            .frame(width: 18, height: 32)
                    }
                    .menuStyle(.borderlessButton)
                }
                .foregroundStyle(.purple)
                .background(TransToolsTheme.navy.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(TransToolsTheme.navy.opacity(0.28), lineWidth: 1)
                )
                .disabled(input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || polishing || translating)
                .help("Sửa ngữ pháp và chính tả theo \(model.sourceLanguage.displayName) (hoặc chọn ngôn ngữ khác)")

                // Nút Dịch ngay
                Button {
                    translateNow()
                } label: {
                    HStack(spacing: 6) {
                        if translating {
                            ProgressView()
                                .controlSize(.small)
                                .colorInvert()
                        } else {
                            Image(systemName: "arrow.right.circle.fill")
                                .font(.system(size: 12, weight: .bold))
                        }
                        Text("Dịch ngay")
                            .font(.system(size: 12, weight: .bold))
                    }
                    .padding(.horizontal, 14)
                    .frame(height: 32)
                    .foregroundStyle(.white)
                    .background(
                        LinearGradient(
                            colors: [TransToolsTheme.accent, TransToolsTheme.navy],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .shadow(color: .purple.opacity(0.25), radius: 3, y: 1)
                }
                .buttonStyle(.plain)
                .disabled(input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || translating || polishing)
                .keyboardShortcut(.return, modifiers: .command)
                .help("Dịch sang \(model.targetLanguage.displayName) (⌘ + Enter)")
            }

    }

    private var translationStudio: some View {
            // 4. Two-Pane Translation & Polish Studio (Trái: Nhập liệu, Phải: Kết quả)
            HStack(spacing: 14) {
                sourcePanel
                resultPanel
            }

    }

    private var sourcePanel: some View {
                // Left Panel: Source Input
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("VĂN BẢN GỐC (\(model.sourceLanguage.shortName.uppercased()))")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(.secondary)

                        Spacer()

                        if !input.isEmpty {
                            Button {
                                input = ""
                                output = ""
                                translationResult = QuickTranslationResult()
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.system(size: 13))
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                            .help("Xóa văn bản")
                        }
                    }

                    ZStack(alignment: .topLeading) {
                        if input.isEmpty {
                            Text("Nhập câu hoặc đoạn văn bản (\(model.sourceLanguage.displayName))…\nBấm các gợi ý mẫu ở trên hoặc gõ nội dung và bấm ⌘ + Enter")
                                .font(.system(size: 14))
                                .foregroundStyle(.tertiary)
                                .padding(12)
                        }

                        TextEditor(text: $input)
                            .font(.system(size: 14))
                            .scrollContentBackground(.hidden)
                            .padding(8)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color(nsColor: .controlBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(Color.primary.opacity(0.08), lineWidth: 1)
                    )

                    // Footer of Left Panel
                    HStack {
                        Text("\(input.count) ký tự")
                            .font(.system(size: 11))
                            .foregroundStyle(.tertiary)

                        Spacer()

                        Text("Phím tắt: ⌘ + Enter")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                }

    }

    private var resultPanel: some View {
                // Right Panel: Output & Polish Result
                VStack(alignment: .leading, spacing: 10) {
                    resultHeader
                    resultContent
                    resultFooter
                }
    }


    private var resultHeader: some View {
                    HStack {
                        if lastActionWasPolish {
                            HStack(spacing: 4) {
                                Image(systemName: "sparkles")
                                    .foregroundStyle(.purple)
                                Text("ĐÃ SỬA NGỮ PHÁP (\(polishedLanguage.shortName.uppercased()))")
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundStyle(.purple)
                            }
                        } else {
                            Text("KẾT QUẢ DỊCH (\(model.targetLanguage.shortName.uppercased()))")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        if !output.isEmpty {
                            HStack(spacing: 8) {
                                if lastActionWasPolish {
                                    Button {
                                        input = output
                                    } label: {
                                        HStack(spacing: 4) {
                                            Image(systemName: "arrow.turn.down.left")
                                            Text("Dùng bản này")
                                        }
                                        .font(.system(size: 11, weight: .medium))
                                        .foregroundStyle(.purple)
                                        .padding(.horizontal, 9)
                                        .padding(.vertical, 4)
                                        .background(TransToolsTheme.navy.opacity(0.12))
                                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                                    }
                                    .buttonStyle(.plain)
                                    .help("Gán nội dung đã sửa lỗi vào ô nhập liệu bên trái")
                                }

                                Button {
                                    NSPasteboard.general.clearContents()
                                    NSPasteboard.general.setString(output, forType: .string)
                                    copied = true
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { copied = false }
                                } label: {
                                    HStack(spacing: 4) {
                                        Image(systemName: copied ? "checkmark" : "doc.on.doc")
                                        Text(copied ? "Đã sao chép!" : "Sao chép")
                                    }
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundStyle(copied ? Color.green : TransToolsTheme.accent)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 4)
                                    .background(copied ? Color.green.opacity(0.12) : TransToolsTheme.accent.opacity(0.1))
                                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }

    }

    private var resultContent: some View {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 12) {
                            if output.isEmpty {
                                Text(translating ? "Đang dịch câu của bạn theo chuyên ngành \(model.domainSpecialty.title)…" : (polishing ? "Đang sửa ngữ pháp theo \(polishedLanguage.displayName)…" : "Kết quả bản dịch (\(model.targetLanguage.displayName)) hoặc sửa lỗi sẽ xuất hiện tại đây."))
                                    .font(.system(size: 14))
                                    .foregroundStyle(.tertiary)
                                    .padding(12)
                            } else {
                                primaryTranslation
                                // Alternatives / Gợi ý phương án diễn đạt khác (khi dịch)
                                if !lastActionWasPolish && !translationResult.alternatives.isEmpty {
                                    alternativeTranslations
                                }
                            }
                        }
                        .padding(10)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color(nsColor: .controlBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(Color.primary.opacity(0.08), lineWidth: 1)
                    )

    }


    private var primaryTranslation: some View {
                                // Primary result (Đã bỏ label "BẢN DỊCH CHUẨN" theo yêu cầu người dùng)
                                Text(output)
                                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                                    .lineSpacing(4)
                                    .foregroundStyle(.primary)
                                    .textSelection(.enabled)
                                    .padding(12)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .background(lastActionWasPolish ? TransToolsTheme.navy.opacity(0.06) : TransToolsTheme.accent.opacity(0.06))
                                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

    }

    private var alternativeTranslations: some View {
                                    VStack(alignment: .leading, spacing: 8) {
                                        HStack(spacing: 5) {
                                            Image(systemName: "sparkles")
                                                .font(.system(size: 10))
                                                .foregroundStyle(.purple)
                                            Text("GỢI Ý PHƯƠNG ÁN DIỄN ĐẠT KHÁC")
                                                .font(.system(size: 10, weight: .bold))
                                                .foregroundStyle(.purple)
                                        }
                                        .padding(.top, 4)

                                        ForEach(translationResult.alternatives) { alt in
                                            alternativeRow(alt)
                                        }
                                    }
    }

    private func alternativeRow(_ alt: TranslationAlternative) -> some View {
                                            HStack(alignment: .top, spacing: 10) {
                                                VStack(alignment: .leading, spacing: 2) {
                                                    Text(alt.tone)
                                                        .font(.system(size: 10, weight: .bold))
                                                        .foregroundStyle(.secondary)
                                                    Text(alt.text)
                                                        .font(.system(size: 13, weight: .medium))
                                                        .foregroundStyle(.primary)
                                                        .textSelection(.enabled)
                                                }

                                                Spacer()

                                                Button {
                                                    NSPasteboard.general.clearContents()
                                                    NSPasteboard.general.setString(alt.text, forType: .string)
                                                    copiedAltID = alt.id
                                                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                                                        copiedAltID = nil
                                                    }
                                                } label: {
                                                    HStack(spacing: 3) {
                                                        Image(systemName: copiedAltID == alt.id ? "checkmark" : "doc.on.doc")
                                                        Text(copiedAltID == alt.id ? "Đã chép" : "Chép")
                                                    }
                                                    .font(.system(size: 10, weight: .semibold))
                                                    .padding(.horizontal, 7)
                                                    .padding(.vertical, 3)
                                                    .background(copiedAltID == alt.id ? Color.green.opacity(0.18) : Color.secondary.opacity(0.12))
                                                    .foregroundStyle(copiedAltID == alt.id ? Color.green : Color.primary)
                                                    .clipShape(RoundedRectangle(cornerRadius: 5))
                                                }
                                                .buttonStyle(.plain)
                                            }
                                            .padding(10)
                                            .background(Color(nsColor: .windowBackgroundColor).opacity(0.6))
                                            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                                            .overlay(
                                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                                    .stroke(Color.primary.opacity(0.06), lineWidth: 0.8)
                                            )
    }

    private var resultFooter: some View {
                    // Footer of Right Panel
                    HStack {
                        if !error.isEmpty {
                            Text(error)
                                .font(.system(size: 11))
                                .foregroundStyle(.red)
                                .lineLimit(1)
                        } else {
                            let engineInfo = model.key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                ? "Google Free • Miễn phí"
                                : "\(model.provider.displayName) • \(model.modelName)"
                            Text("\(engineInfo) • \(model.domainSpecialty.title)")
                                .font(.system(size: 11))
                                .foregroundStyle(.tertiary)
                        }
                        Spacer()
                    }
    }
    private func translateNow() {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        translating = true; error = ""; copied = false; lastActionWasPolish = false
        let domain = model.domainSpecialty
        var currentProvider = model.provider
        var currentModel = model.modelName
        var currentKey = model.key.trimmingCharacters(in: .whitespacesAndNewlines)
        if currentKey.isEmpty && !model.coPilotKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && model.coPilotProvider != .apple && model.coPilotProvider != .free {
            currentProvider = model.coPilotProvider
            currentModel = model.coPilotModel
            currentKey = model.coPilotKey.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        let src = model.sourceLanguage
        let dst = model.targetLanguage
        Task {
            do {
                let result = try await AITranslator.quickTranslateDetailed(
                    text,
                    from: src,
                    to: dst,
                    domain: domain,
                    provider: currentProvider,
                    model: currentModel,
                    key: currentKey
                )
                output = result.primary
                translationResult = result
                error = ""
            } catch {
                self.error = error.localizedDescription
            }
            translating = false
        }
    }

    private func polishLanguageNow(lang: AppLanguage? = nil) {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        polishing = true; error = ""; copied = false; lastActionWasPolish = true
        let targetLang = lang ?? model.sourceLanguage
        polishedLanguage = targetLang
        let domain = model.domainSpecialty
        var currentProvider = model.provider
        var currentModel = model.modelName
        var currentKey = model.key.trimmingCharacters(in: .whitespacesAndNewlines)
        if currentKey.isEmpty && !model.coPilotKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && model.coPilotProvider != .apple && model.coPilotProvider != .free {
            currentProvider = model.coPilotProvider
            currentModel = model.coPilotModel
            currentKey = model.coPilotKey.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        Task {
            do {
                let polished = try await AITranslator.fixAndPolishLanguage(
                    text,
                    language: targetLang,
                    domain: domain,
                    provider: currentProvider,
                    model: currentModel,
                    key: currentKey
                )
                output = polished
                translationResult = QuickTranslationResult(primary: polished)
                error = ""
            } catch {
                self.error = error.localizedDescription
            }
            polishing = false
        }
    }
}

// MARK: - Settings Popover View

struct SettingsPopoverView: View {
    @ObservedObject var model: MeetingModel
    @Binding var isPresented: Bool
    @Environment(\.dismiss) private var dismiss
    @State private var selectedTab = 0
    @State private var showCoPilotKey = false
    @State private var savedNotice = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Header
            HStack {
                HStack(spacing: 8) {
                    Image(systemName: "gearshape.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(TransToolsTheme.accent)
                    Text("Cấu hình TransTools")
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                }

                Spacer()

                Button {
                    isPresented = false
                    dismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Đóng (Esc)")
                .keyboardShortcut(.cancelAction)
            }

            // Tab Switcher
            Picker("", selection: $selectedTab) {
                Text("Phụ đề").tag(0)
                Text("AI Trợ lý").tag(1)
                Text("Giao diện").tag(2)
                Text("Cập nhật").tag(3)
            }
            .pickerStyle(.segmented)

            if selectedTab == 0 {
                // Tab 0: Dịch phụ đề cuộc họp & Chuyên ngành
                ScrollView(.vertical, showsIndicators: true) {
                    VStack(alignment: .leading, spacing: 14) {
                        // 1. Chuyên ngành dịch thuật (Prompt customization)
                        VStack(alignment: .leading, spacing: 6) {
                            Text("CHUYÊN NGÀNH DỊCH THUẬT & GỢI Ý")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(.secondary)

                            Menu {
                                ForEach(DomainSpecialty.allCases) { domain in
                                    Button {
                                        model.domainSpecialty = domain
                                    } label: {
                                        Label(domain.title, systemImage: domain.icon)
                                    }
                                }
                            } label: {
                                HStack(spacing: 8) {
                                    Image(systemName: model.domainSpecialty.icon)
                                        .font(.system(size: 13))
                                        .foregroundStyle(TransToolsTheme.accent)
                                        .frame(width: 16)
                                    Text(model.domainSpecialty.title)
                                        .font(.system(size: 12, weight: .medium))
                                    Spacer()
                                    Image(systemName: "chevron.up.chevron.down")
                                        .font(.system(size: 10))
                                        .foregroundStyle(.secondary)
                                }
                                .padding(.horizontal, 10)
                                .frame(height: 32)
                                .background(Color(nsColor: .controlBackgroundColor))
                                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                                .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(Color.primary.opacity(0.12), lineWidth: 1))
                            }
                            .menuStyle(.borderlessButton)

                            Text("Prompt chuyên sâu sẽ hướng dẫn AI dịch chính xác thuật ngữ (VD: Developer giữ PR, commit, deploy...; Business dùng văn phong họp chuẩn mực).")
                                .font(.system(size: 10))
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }

                        Divider()

                        // 2. Bộ dịch miễn phí tích hợp
                        VStack(alignment: .leading, spacing: 6) {
                            Text("BỘ DỊCH MIỄN PHÍ TÍCH HỢP")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(.secondary)

                            // Card 1: Apple Translate (Default)
                            Button {
                                model.setProvider(.apple)
                            } label: {
                                HStack(spacing: 12) {
                                    Image(systemName: "apple.logo")
                                        .font(.system(size: 20))
                                        .foregroundStyle(model.provider == .apple ? TransToolsTheme.accent : .primary)
                                        .frame(width: 22)

                                    VStack(alignment: .leading, spacing: 2) {
                                        HStack {
                                            Text("Apple Translate (Mặc định)")
                                                .font(.system(size: 12, weight: .bold))
                                            Text("Khuyên dùng")
                                                .font(.system(size: 9, weight: .bold))
                                                .padding(.horizontal, 5)
                                                .padding(.vertical, 1)
                                                .background(Color.green.opacity(0.18))
                                                .foregroundStyle(.green)
                                                .clipShape(Capsule())
                                        }
                                        Text("Miễn phí • Tích hợp trên máy • Tốc độ siêu tốc")
                                            .font(.system(size: 10))
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Image(systemName: model.provider == .apple ? "checkmark.circle.fill" : "circle")
                                        .foregroundStyle(model.provider == .apple ? TransToolsTheme.accent : Color.secondary.opacity(0.4))
                                }
                                .padding(9)
                                .background(model.provider == .apple ? TransToolsTheme.accent.opacity(0.1) : Color(nsColor: .controlBackgroundColor))
                                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                                .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(model.provider == .apple ? TransToolsTheme.accent : Color.primary.opacity(0.08), lineWidth: 1.2))
                            }
                            .buttonStyle(.plain)

                            // Card 2: Google Free
                            Button {
                                model.setProvider(.free)
                            } label: {
                                HStack(spacing: 12) {
                                    Image(systemName: "bolt.fill")
                                        .font(.system(size: 18))
                                        .foregroundStyle(model.provider == .free ? Color.orange : .secondary)
                                        .frame(width: 22)

                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("Google Dịch (Miễn phí)")
                                            .font(.system(size: 12, weight: .bold))
                                        Text("Miễn phí • Không cần thiết lập")
                                            .font(.system(size: 10))
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Image(systemName: model.provider == .free ? "checkmark.circle.fill" : "circle")
                                        .foregroundStyle(model.provider == .free ? TransToolsTheme.accent : Color.secondary.opacity(0.4))
                                }
                                .padding(9)
                                .background(model.provider == .free ? TransToolsTheme.accent.opacity(0.1) : Color(nsColor: .controlBackgroundColor))
                                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                                .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(model.provider == .free ? TransToolsTheme.accent : Color.primary.opacity(0.08), lineWidth: 1.2))
                            }
                            .buttonStyle(.plain)
                        }

                        Divider()

                        // 3. Động cơ dịch bằng AI Trợ lý (Mở khóa khi có Key)
                        VStack(alignment: .leading, spacing: 6) {
                            Text("DỊCH PHỤ ĐỀ BẰNG AI TRỢ LÝ (ÁP DỤNG PROMPT CHUYÊN NGÀNH)")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(.secondary)

                            ForEach([AIProvider.gemini, .openai, .deepseek, .claude]) { p in
                                let hasKey = model.hasKeyForProvider(p)
                                let isSelected = (model.provider == p)

                                VStack(alignment: .leading, spacing: 4) {
                                    Button {
                                        if hasKey {
                                            model.setProvider(p)
                                        } else {
                                            model.coPilotProvider = p
                                            selectedTab = 1
                                        }
                                    } label: {
                                        HStack(spacing: 12) {
                                            Image(systemName: p.icon)
                                                .font(.system(size: 17))
                                                .foregroundStyle(isSelected ? TransToolsTheme.accent : (hasKey ? .primary : .secondary))
                                                .frame(width: 22)

                                            VStack(alignment: .leading, spacing: 2) {
                                                HStack(spacing: 6) {
                                                    Text(p.displayName)
                                                        .font(.system(size: 12, weight: .bold))

                                                    if hasKey {
                                                        Text("Đã có Key")
                                                            .font(.system(size: 9, weight: .bold))
                                                            .padding(.horizontal, 5)
                                                            .padding(.vertical, 1)
                                                            .background(Color.green.opacity(0.18))
                                                            .foregroundStyle(.green)
                                                            .clipShape(Capsule())
                                                    } else {
                                                        Text("Chưa cài Key")
                                                            .font(.system(size: 9, weight: .medium))
                                                            .padding(.horizontal, 5)
                                                            .padding(.vertical, 1)
                                                            .background(Color.secondary.opacity(0.15))
                                                            .foregroundStyle(.secondary)
                                                            .clipShape(Capsule())
                                                    }
                                                }

                                                let activeModelForP = isSelected ? model.modelName : (UserDefaults.standard.string(forKey: "AIModel_\(p.rawValue)") ?? p.defaultModel)
                                                Text(hasKey ? "Áp dụng prompt \(model.domainSpecialty.shortName) • Model: \(activeModelForP)" : "Bấm để thêm API Key mở khóa trợ lý này")
                                                    .font(.system(size: 10))
                                                    .foregroundStyle(.secondary)
                                            }

                                            Spacer()

                                            if hasKey {
                                                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                                                    .foregroundStyle(isSelected ? TransToolsTheme.accent : Color.secondary.opacity(0.4))
                                            } else {
                                                Text("Cài Key")
                                                    .font(.system(size: 10, weight: .semibold))
                                                    .foregroundStyle(TransToolsTheme.accent)
                                                    .padding(.horizontal, 6)
                                                    .padding(.vertical, 2)
                                                    .background(TransToolsTheme.accent.opacity(0.12))
                                                    .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                                            }
                                        }
                                        .padding(9)
                                        .background(isSelected ? TransToolsTheme.accent.opacity(0.1) : Color(nsColor: .controlBackgroundColor))
                                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                                        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(isSelected ? TransToolsTheme.accent : Color.primary.opacity(0.08), lineWidth: 1.2))
                                    }
                                    .buttonStyle(.plain)

                                    // Inline Model Picker & Chips for the selected provider
                                    if isSelected && hasKey {
                                        VStack(alignment: .leading, spacing: 6) {
                                            HStack(spacing: 6) {
                                                Text("Model phụ đề:")
                                                    .font(.system(size: 10, weight: .semibold))
                                                    .foregroundStyle(.secondary)

                                                Menu {
                                                    ForEach(p.defaultModels, id: \.self) { dm in
                                                        Button {
                                                            model.updateModelName(dm, for: p)
                                                        } label: {
                                                            HStack {
                                                                Text(dm)
                                                                if model.modelName == dm {
                                                                    Spacer()
                                                                    Image(systemName: "checkmark")
                                                                }
                                                            }
                                                        }
                                                    }
                                                } label: {
                                                    HStack(spacing: 4) {
                                                        Text(model.modelName)
                                                            .font(.system(size: 10.5, weight: .bold, design: .monospaced))
                                                        Image(systemName: "chevron.up.chevron.down")
                                                            .font(.system(size: 8))
                                                            .foregroundStyle(.secondary)
                                                    }
                                                    .padding(.horizontal, 8)
                                                    .padding(.vertical, 3)
                                                    .background(Color(nsColor: .controlBackgroundColor))
                                                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                                                    .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).stroke(Color.primary.opacity(0.12), lineWidth: 1))
                                                }
                                                .menuStyle(.borderlessButton)

                                                Spacer()
                                            }

                                            // Quick Model Chips
                                            ScrollView(.horizontal, showsIndicators: false) {
                                                HStack(spacing: 5) {
                                                    ForEach(p.defaultModels, id: \.self) { dm in
                                                        let isCurModel = (model.modelName == dm)
                                                        Button {
                                                            model.updateModelName(dm, for: p)
                                                        } label: {
                                                            HStack(spacing: 3) {
                                                                if isCurModel {
                                                                    Image(systemName: "checkmark")
                                                                        .font(.system(size: 7, weight: .bold))
                                                                }
                                                                Text(dm)
                                                                    .font(.system(size: 9.5, weight: isCurModel ? .bold : .medium, design: .monospaced))
                                                            }
                                                            .padding(.horizontal, 7)
                                                            .padding(.vertical, 3)
                                                            .background(isCurModel ? TransToolsTheme.accent.opacity(0.18) : Color(nsColor: .controlBackgroundColor))
                                                            .foregroundStyle(isCurModel ? TransToolsTheme.accent : Color.secondary)
                                                            .clipShape(Capsule())
                                                            .overlay(Capsule().stroke(isCurModel ? TransToolsTheme.accent.opacity(0.4) : Color.primary.opacity(0.08), lineWidth: 1))
                                                        }
                                                        .buttonStyle(.plain)
                                                    }
                                                }
                                                .padding(.vertical, 1)
                                            }
                                        }
                                        .padding(.leading, 34)
                                        .padding(.vertical, 3)
                                    }
                                }
                            }
                        }
                    }
                    .padding(.trailing, 4)
                }
                .frame(maxHeight: 380)
            } else if selectedTab == 1 {
                // Tab 1: AI Co-Pilot for Smart Reply Suggestions
                VStack(alignment: .leading, spacing: 14) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("TRỢ LÝ AI GỢI Ý CÂU TRẢ LỜI GIAO TIẾP")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(.secondary)
                        Text("Khi nghe đồng nghiệp nói, AI phân tích ý tứ và chuẩn bị sẵn 3 câu trả lời tiếng Anh (kèm sắc thái & nghĩa tiếng Việt). Phụ đề cuộc họp luôn dịch miễn phí ngay trên máy của bạn.")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }

                    // Provider picker
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Mô hình AI phân tích")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.secondary)

                        HStack(spacing: 8) {
                            ForEach([AIProvider.gemini, .openai, .deepseek, .claude]) { p in
                                Button {
                                    model.setCoPilotProvider(p)
                                } label: {
                                    HStack(spacing: 6) {
                                        Image(systemName: p.icon)
                                            .font(.system(size: 11, weight: .semibold))
                                        Text(p.shortName)
                                            .font(.system(size: 11, weight: model.coPilotProvider == p ? .bold : .medium))
                                    }
                                    .frame(maxWidth: .infinity)
                                    .frame(height: 32)
                                    .background(model.coPilotProvider == p ? TransToolsTheme.accent.opacity(0.14) : Color(nsColor: .controlBackgroundColor))
                                    .foregroundStyle(model.coPilotProvider == p ? TransToolsTheme.accent : Color.primary)
                                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                                            .stroke(model.coPilotProvider == p ? TransToolsTheme.accent : Color.primary.opacity(0.08), lineWidth: model.coPilotProvider == p ? 1.5 : 1)
                                    )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }

                    // Model Dropdown & Fetch
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Mô hình xử lý (Model)")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(.secondary)
                            Spacer()
                            if model.isFetchingCoPilotModels {
                                HStack(spacing: 4) {
                                    ProgressView().controlSize(.mini)
                                    Text("Đang tải model từ API...")
                                        .font(.system(size: 10))
                                        .foregroundStyle(.secondary)
                                }
                            } else if !model.availableCoPilotModels.isEmpty {
                                HStack(spacing: 4) {
                                    Circle()
                                        .fill(Color.green)
                                        .frame(width: 5, height: 5)
                                    Text("\(model.availableCoPilotModels.count) model khả dụng")
                                        .font(.system(size: 10))
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }

                        HStack(spacing: 8) {
                            Menu {
                                let allModels = model.availableCoPilotModels.isEmpty ? model.coPilotProvider.defaultModels : model.availableCoPilotModels
                                let recommended = allModels.filter { isModelRecommended($0) }
                                let others = allModels.filter { !isModelRecommended($0) }

                                if !recommended.isEmpty {
                                    Section("Mô hình khuyên dùng") {
                                        ForEach(recommended, id: \.self) { m in
                                            Button {
                                                model.updateModelName(m, for: model.coPilotProvider)
                                            } label: {
                                                if model.coPilotModel == m {
                                                    Label(m + " (Đang chọn)", systemImage: "checkmark")
                                                } else {
                                                    Label(m, systemImage: "sparkles")
                                                }
                                            }
                                        }
                                    }
                                }

                                if !others.isEmpty {
                                    Section("Tất cả mô hình (\(others.count))") {
                                        ForEach(others, id: \.self) { m in
                                            Button {
                                                model.updateModelName(m, for: model.coPilotProvider)
                                            } label: {
                                                if model.coPilotModel == m {
                                                    Label(m + " (Đang chọn)", systemImage: "checkmark")
                                                } else {
                                                    Text(m)
                                                }
                                            }
                                        }
                                    }
                                }
                            } label: {
                                HStack(spacing: 10) {
                                    // Icon badge
                                    ZStack {
                                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                                            .fill(TransToolsTheme.accent.opacity(0.14))
                                            .frame(width: 32, height: 32)
                                        Image(systemName: model.coPilotProvider.icon)
                                            .font(.system(size: 14, weight: .semibold))
                                            .foregroundStyle(TransToolsTheme.accent)
                                    }

                                    // Title and description
                                    VStack(alignment: .leading, spacing: 2) {
                                        HStack(spacing: 6) {
                                            Text(model.coPilotModel.isEmpty ? "Chọn model..." : model.coPilotModel)
                                                .font(.system(size: 12, weight: .bold, design: .monospaced))
                                                .foregroundStyle(.primary)

                                            if isModelRecommended(model.coPilotModel) {
                                                Text("Khuyên dùng")
                                                    .font(.system(size: 8, weight: .bold))
                                                    .padding(.horizontal, 5)
                                                    .padding(.vertical, 1)
                                                    .background(Color.green.opacity(0.18))
                                                    .foregroundStyle(.green)
                                                    .clipShape(Capsule())
                                            }
                                        }

                                        Text(modelSubtitle(for: model.coPilotModel))
                                            .font(.system(size: 10))
                                            .foregroundStyle(.secondary)
                                            .lineLimit(1)
                                    }

                                    Spacer()

                                    // Chevron
                                    ZStack {
                                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                                            .fill(Color.primary.opacity(0.06))
                                            .frame(width: 22, height: 22)
                                        Image(systemName: "chevron.up.chevron.down")
                                            .font(.system(size: 9, weight: .bold))
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                .padding(.horizontal, 10)
                                .frame(height: 44)
                                .background(Color(nsColor: .controlBackgroundColor))
                                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                                        .stroke(Color.primary.opacity(0.12), lineWidth: 1)
                                )
                            }
                            .menuStyle(.borderlessButton)

                            Button {
                                Task { await model.fetchCoPilotModels() }
                            } label: {
                                ZStack {
                                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                                        .fill(Color(nsColor: .controlBackgroundColor))
                                        .frame(width: 44, height: 44)
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                                .stroke(Color.primary.opacity(0.12), lineWidth: 1)
                                        )

                                    if model.isFetchingCoPilotModels {
                                        ProgressView().controlSize(.small)
                                    } else {
                                        VStack(spacing: 2) {
                                            Image(systemName: "arrow.clockwise")
                                                .font(.system(size: 12, weight: .semibold))
                                                .foregroundStyle(TransToolsTheme.accent)
                                            Text("Cập nhật")
                                                .font(.system(size: 7, weight: .bold))
                                                .foregroundStyle(.secondary)
                                        }
                                    }
                                }
                            }
                            .buttonStyle(.plain)
                            .disabled(model.isFetchingCoPilotModels || model.coPilotKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                            .help(model.coPilotKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Vui lòng nhập API Key trước khi lấy model" : "Lấy danh sách model mới nhất từ API \(model.coPilotProvider.shortName)")
                        }

                        // Quick Model Suggestion Chips
                        if !model.coPilotProvider.defaultModels.isEmpty {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Gợi ý chọn nhanh:")
                                    .font(.system(size: 10))
                                    .foregroundStyle(.secondary)

                                ScrollView(.horizontal, showsIndicators: false) {
                                    HStack(spacing: 6) {
                                        ForEach(model.coPilotProvider.defaultModels, id: \.self) { dm in
                                            let isSel = (model.coPilotModel == dm)
                                            Button {
                                                model.updateModelName(dm, for: model.coPilotProvider)
                                            } label: {
                                                HStack(spacing: 4) {
                                                    if isSel {
                                                        Image(systemName: "checkmark")
                                                            .font(.system(size: 8, weight: .bold))
                                                    }
                                                    Text(dm)
                                                        .font(.system(size: 10, weight: isSel ? .bold : .medium, design: .monospaced))
                                                }
                                                .padding(.horizontal, 8)
                                                .padding(.vertical, 4)
                                                .background(isSel ? TransToolsTheme.accent.opacity(0.18) : Color(nsColor: .controlBackgroundColor))
                                                .foregroundStyle(isSel ? TransToolsTheme.accent : Color.secondary)
                                                .clipShape(Capsule())
                                                .overlay(
                                                    Capsule()
                                                        .stroke(isSel ? TransToolsTheme.accent.opacity(0.4) : Color.primary.opacity(0.1), lineWidth: 1)
                                                )
                                            }
                                            .buttonStyle(.plain)
                                        }
                                    }
                                    .padding(.vertical, 1)
                                }
                            }
                        }

                        if !model.coPilotFetchMessage.isEmpty {
                            let isErr = model.coPilotFetchMessage.contains("Lỗi") || model.coPilotFetchMessage.contains("Vui lòng")
                            HStack(spacing: 6) {
                                Image(systemName: isErr ? "exclamationmark.circle.fill" : "checkmark.circle.fill")
                                    .font(.system(size: 11))
                                    .foregroundStyle(isErr ? Color.red : Color.green)
                                Text(model.coPilotFetchMessage)
                                    .font(.system(size: 10, weight: .medium))
                                    .foregroundStyle(isErr ? Color.red : Color.green)
                                Spacer()
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(isErr ? Color.red.opacity(0.08) : Color.green.opacity(0.08))
                            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                            .transition(.opacity)
                        }
                    }

                    // API Key Field
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("\(model.coPilotProvider.displayName) API Key")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(.secondary)
                            Spacer()
                            if let url = URL(string: model.coPilotProvider.apiKeyURL), !model.coPilotProvider.apiKeyURL.isEmpty {
                                Link("Lấy API Key ↗", destination: url)
                                    .font(.system(size: 10, weight: .medium))
                                    .foregroundStyle(TransToolsTheme.accent)
                            }
                        }

                        HStack(spacing: 8) {
                            if showCoPilotKey {
                                TextField("Nhập API Key...", text: $model.coPilotKey)
                                    .textFieldStyle(.plain)
                                    .font(.system(size: 12, design: .monospaced))
                            } else {
                                SecureField("Nhập API Key...", text: $model.coPilotKey)
                                    .textFieldStyle(.plain)
                                    .font(.system(size: 12, design: .monospaced))
                            }

                            Button {
                                showCoPilotKey.toggle()
                            } label: {
                                Image(systemName: showCoPilotKey ? "eye.slash" : "eye")
                                    .font(.system(size: 12))
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.horizontal, 10)
                        .frame(height: 34)
                        .background(Color(nsColor: .controlBackgroundColor))
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(Color.primary.opacity(0.12), lineWidth: 1))
                    }

                    // Save Button
                    HStack {
                        Spacer()
                        Button {
                            model.saveCoPilotSettings()
                            withAnimation(.spring(response: 0.3)) {
                                savedNotice = true
                            }
                            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                                withAnimation { savedNotice = false }
                            }
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: savedNotice ? "checkmark" : "square.and.arrow.down.fill")
                                    .font(.system(size: 11, weight: .bold))
                                Text(savedNotice ? "Đã lưu!" : "Lưu cấu hình")
                                    .font(.system(size: 12, weight: .bold))
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background(
                                savedNotice
                                    ? LinearGradient(colors: [Color.green, Color(red: 0.1, green: 0.7, blue: 0.3)], startPoint: .topLeading, endPoint: .bottomTrailing)
                                    : LinearGradient(colors: [TransToolsTheme.accent, TransToolsTheme.navy], startPoint: .topLeading, endPoint: .bottomTrailing)
                            )
                            .foregroundStyle(.white)
                            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                            .shadow(color: TransToolsTheme.accent.opacity(0.25), radius: 5, y: 2)
                        }
                        .buttonStyle(.plain)
                    }
                }
            } else if selectedTab == 2 {
                // Tab 2: Interface & Mascot
                VStack(alignment: .leading, spacing: 12) {
                    Text("GIAO DIỆN & TRỢ LÝ CHIP CHIP")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.secondary)

                    Toggle(isOn: Binding(
                        get: { model.isFloatingMascotVisible },
                        set: { _ in model.toggleFloatingMascot() }
                    )) {
                        HStack(spacing: 8) {
                            Image(systemName: "sparkles.tv.fill")
                                .font(.system(size: 13))
                                .foregroundStyle(TransToolsTheme.accent)
                            Text("Trợ lý Chip Chip nổi trên màn hình (Thao tác & Quick Chat)")
                                .font(.system(size: 12))
                        }
                    }
                    .toggleStyle(.switch)

                    if model.isFloatingMascotVisible {
                        Button {
                            model.snapMascotToConvenientPosition()
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "arrow.down.forward.and.arrow.up.backward")
                                Text("Đưa Chip Chip về góc màn hình")
                            }
                            .font(.system(size: 11))
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .padding(.leading, 26)
                    }

                    Toggle(isOn: $model.showMascot.animation(.spring())) {
                        HStack(spacing: 8) {
                            Image(systemName: "face.smiling.fill")
                                .font(.system(size: 13))
                                .foregroundStyle(.orange)
                            Text("Hiển thị Chip Chip ở màn hình dashboard")
                                .font(.system(size: 12))
                        }
                    }
                    .toggleStyle(.switch)

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Tạo hình Chip Chip")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)

                        Picker("Tạo hình Chip Chip", selection: $model.mascotStyle) {
                            Text("🖼 Mascot ảnh").tag("sprite")
                            Text("👾 Pixel Art").tag("pixel")
                        }
                        .pickerStyle(.segmented)
                    }

                    Divider()

                    // Dịch nhanh từ vựng toàn hệ thống
                    VStack(alignment: .leading, spacing: 6) {
                        Text("DỊCH NHANH TỪ VỰNG TOÀN HỆ THỐNG")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(.secondary)

                        HStack(spacing: 10) {
                            ZStack {
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .fill(TransToolsTheme.accent.opacity(0.12))
                                    .frame(width: 32, height: 32)
                                Image(systemName: "command.circle.fill")
                                    .font(.system(size: 16))
                                    .foregroundStyle(TransToolsTheme.accent)
                            }

                            VStack(alignment: .leading, spacing: 2) {
                                HStack {
                                    Text("Phím tắt dịch từ bôi đen:")
                                        .font(.system(size: 11.5, weight: .semibold))
                                    Text("Option + D")
                                        .font(.system(size: 10, weight: .bold, design: .rounded))
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(TransToolsTheme.accent.opacity(0.15))
                                        .foregroundStyle(TransToolsTheme.accent)
                                        .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                                    Text("hoặc")
                                        .font(.system(size: 10))
                                        .foregroundStyle(.secondary)
                                    Text("Option + T")
                                        .font(.system(size: 10, weight: .bold, design: .rounded))
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(Color.secondary.opacity(0.12))
                                        .foregroundStyle(.secondary)
                                        .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                                }

                                Text("Bôi đen chữ bất kỳ rồi bấm Option + D. Chip Chip sẽ hiện bóng thoại dịch nghĩa trên đầu và cho phép lưu vào Sổ từ vựng.")
                                    .font(.system(size: 10.5))
                                    .foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        .padding(9)
                        .background(Color(nsColor: .controlBackgroundColor))
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(Color.primary.opacity(0.08), lineWidth: 1))
                    }
                }
            }

            if selectedTab == 3 {
                SettingsUpdateTabView()
            }
        }
        .padding(18)
        .frame(width: 440)
        .onAppear {
            let key = model.coPilotKey.trimmingCharacters(in: .whitespacesAndNewlines)
            if !key.isEmpty && model.availableCoPilotModels.count <= 3 {
                Task { await model.fetchCoPilotModels() }
            }
        }
    }

    private func keyPlaceholder(for provider: AIProvider) -> String {
        switch provider {
        case .apple, .free: return ""
        case .gemini: return "AIzaSy..."
        case .openai: return "sk-proj-..."
        case .deepseek: return "sk-..."
        case .claude: return "sk-ant-..."
        }
    }

    private func modelSubtitle(for name: String) -> String {
        let lower = name.lowercased()
        if lower.contains("2.0-flash") {
            return "Siêu tốc độ & phản xạ thông minh nhất"
        } else if lower.contains("1.5-flash") {
            return "Nhanh nhẹ, ổn định & tối ưu chi phí"
        } else if lower.contains("1.5-pro") {
            return "Tư duy ngữ cảnh sâu & phân tích phức tạp"
        } else if lower.contains("4o-mini") {
            return "Tốc độ cao & chi phí tối ưu nhất"
        } else if lower.contains("4o") {
            return "Mô hình đa phương thức hàng đầu OpenAI"
        } else if lower.contains("deepseek-chat") {
            return "Văn phong tự nhiên & chi phí cực rẻ"
        } else if lower.contains("deepseek-reasoner") {
            return "Mô hình lý luận chuyên sâu (DeepSeek-R1)"
        } else if lower.contains("haiku") {
            return "Phản hồi chớp mắt & siêu nhanh"
        } else if lower.contains("sonnet") {
            return "Văn phong sắc sảo, tự nhiên nhất"
        }
        return "Mô hình ngôn ngữ AI thế hệ mới"
    }

    private func isModelRecommended(_ name: String) -> Bool {
        let lower = name.lowercased()
        return lower.contains("2.0-flash") || lower.contains("4o-mini") || lower.contains("deepseek-chat") || lower.contains("haiku")
    }
}

// MARK: - About App Popover View

struct AboutAppPopoverView: View {
    @Binding var isPresented: Bool
    @State private var copiedEmail = false

    var body: some View {
        VStack(spacing: 16) {
            // Header: Logo & Name
            HStack(spacing: 14) {
                ZStack {
                    LinearGradient(
                        colors: [TransToolsTheme.accent, TransToolsTheme.accent.opacity(0.8), TransToolsTheme.accent],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                    .frame(width: 50, height: 50)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .shadow(color: TransToolsTheme.accent.opacity(0.35), radius: 6, y: 2)

                    MiniAvatarView(size: 40)
                }

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text("TransTools")
                            .font(.system(size: 18, weight: .bold, design: .rounded))
                        Text(appVersionDisplay)
                            .font(.system(size: 10, weight: .semibold, design: .monospaced))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(TransToolsTheme.accent.opacity(0.15))
                            .foregroundStyle(TransToolsTheme.accent)
                            .clipShape(Capsule())
                    }

                    Text("Live Meeting Subtitles & AI Translation")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }

            Text("Bộ công cụ dịch thuật trực tiếp âm thanh cuộc họp, tạo phụ đề nổi song ngữ và trợ lý AI thông minh trên macOS.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .lineSpacing(2)

            Divider()

            // Info rows
            VStack(spacing: 10) {
                // Developer
                HStack(spacing: 10) {
                    Image(systemName: "person.crop.circle.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(TransToolsTheme.accent)
                        .frame(width: 20)

                    Text("Tác giả:")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)

                    Text("DuyNK-Tech")
                        .font(.system(size: 12, weight: .bold))

                    Spacer()
                }

                // Email
                HStack(spacing: 10) {
                    Image(systemName: "envelope.fill")
                        .font(.system(size: 13))
                        .foregroundStyle(.orange)
                        .frame(width: 20)

                    Text("Email:")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)

                    Button {
                        if let url = URL(string: "mailto:khacduy90@gmail.com") {
                            NSWorkspace.shared.open(url)
                        }
                    } label: {
                        Text("khacduy90@gmail.com")
                            .font(.system(size: 12, weight: .medium, design: .monospaced))
                            .foregroundStyle(Color.primary)
                    }
                    .buttonStyle(.plain)
                    .help("Bấm để mở ứng dụng Mail")

                    Spacer()

                    Button {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString("khacduy90@gmail.com", forType: .string)
                        copiedEmail = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                            copiedEmail = false
                        }
                    } label: {
                        HStack(spacing: 3) {
                            Image(systemName: copiedEmail ? "checkmark" : "doc.on.doc")
                            Text(copiedEmail ? "Đã chép" : "Chép")
                        }
                        .font(.system(size: 10, weight: .medium))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(copiedEmail ? Color.green.opacity(0.15) : Color.secondary.opacity(0.12))
                        .foregroundStyle(copiedEmail ? Color.green : Color.primary)
                        .clipShape(RoundedRectangle(cornerRadius: 5))
                    }
                    .buttonStyle(.plain)
                    .help("Sao chép địa chỉ email")
                }

                // GitHub
                HStack(spacing: 10) {
                    Image(systemName: "link.circle.fill")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.purple)
                        .frame(width: 20)

                    Text("Git:")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)

                    Button {
                        if let url = URL(string: "https://github.com/duynk-tech/TransTools") {
                            NSWorkspace.shared.open(url)
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Text("github.com/duynk-tech/TransTools")
                                .font(.system(size: 12, weight: .medium))
                                .underline()
                            Image(systemName: "arrow.up.right.square")
                                .font(.system(size: 10))
                        }
                        .foregroundStyle(TransToolsTheme.accent)
                    }
                    .buttonStyle(.plain)
                    .help("Mở trang GitHub repository trong trình duyệt")

                    Spacer()
                }

                // Check updates button
                HStack {
                    Image(systemName: "arrow.triangle.2.circlepath.circle.fill")
                        .font(.system(size: 13))
                        .foregroundStyle(TransToolsTheme.accent)
                        .frame(width: 20)

                    Text("Cập nhật:")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)

                    Button {
                        isPresented = false
                        AppUpdater.shared.showUpdateSheet = true
                        AppUpdater.shared.checkForUpdates(userInitiated: true)
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: "arrow.triangle.2.circlepath")
                            Text("Kiểm tra phiên bản mới")
                        }
                        .font(.system(size: 11, weight: .medium))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(TransToolsTheme.accent.opacity(0.12))
                        .foregroundStyle(TransToolsTheme.accent)
                        .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)

                    Spacer()
                }
            }
            .padding(12)
            .background(Color.secondary.opacity(0.06))
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

            // Highlight Tags
            HStack(spacing: 12) {
                Label("Apple & Cloud AI", systemImage: "sparkles")
                Label("Trợ lý Chip Chip", systemImage: "face.smiling.fill")
                Label("Phụ đề HUD", systemImage: "pip.fill")
            }
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(.secondary)

            Divider()

            // Footer Copyright
            HStack {
                Text("© 2026 DuyNK-Tech. All rights reserved.")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary.opacity(0.8))

                Spacer()

                Button("Đóng") {
                    isPresented = false
                }
                .font(.system(size: 11, weight: .medium))
                .controlSize(.small)
            }
        }
        .padding(18)
        .frame(width: 390)
    }
}

// MARK: - App Entry Point

@main struct TransToolsApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var model = MeetingModel()

    var body: some Scene {
        WindowGroup {
            if ProcessInfo.processInfo.arguments.contains("--mascot-preview") {
                MascotSpritePreviewView()
            } else {
            MainDashboardView(model: model)
                .tint(TransToolsTheme.accent)
                .background(WindowAccessor { window in
                    model.attachMainWindow(window)
                })
                .onAppear {
                    appDelegate.model = model
                    MenuBarManager.shared.setup(with: model)
                }
            }
        }
        .defaultSize(width: 980, height: 720)
        .windowStyle(.hiddenTitleBar)
        .commands {
            MascotSpriteCommands()
            CommandMenu("Dịch & chỉnh câu") {
                Button("Dịch từ bôi đen · Option + D") {
                    Task { await GlobalHotkeyManager.shared.triggerSelectionTranslation() }
                }
                Button("Sửa ngữ pháp · Option + F") {
                    Task { await GlobalHotkeyManager.shared.triggerGrammarFixAndPolish() }
                }
                Button("Dịch VI → EN · Option + E") {
                    Task { await GlobalHotkeyManager.shared.triggerVietnameseToEnglish() }
                }
            }
        }
        Window("Bộ chuyển động mascot", id: "mascot-sprites") {
            MascotSpritePreviewView()
        }
        .defaultSize(width: 980, height: 640)
    }
}
