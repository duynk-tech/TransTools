import SwiftUI
import Speech
import AVFoundation
import ScreenCaptureKit
import AppKit
import CoreGraphics
import UniformTypeIdentifiers
import Combine
import ServiceManagement
#if canImport(Translation)
import Translation
#endif

struct Caption: Identifiable, Equatable {
    let id: UUID
    let start: TimeInterval
    var end: TimeInterval
    var original: String
    var vietnamese = ""
    var sourceLanguage: String? = nil
    var targetLanguage: String? = nil
    var translationProvider: String? = nil
    var translationModel: String? = nil
    var translationSource: String? = nil
    var translationRevision: Int? = nil
    var sourceRevision = 0

    var record: CaptionRecord {
        CaptionRecord(id: id, start: start, end: end, original: original, vietnamese: vietnamese,
            sourceLanguage: sourceLanguage, targetLanguage: targetLanguage,
            translationProvider: translationProvider, translationModel: translationModel,
            sourceRevision: sourceRevision, translationSource: translationSource, translationRevision: translationRevision)
    }
}

var appVersionDisplay: String {
    if let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String, !version.isEmpty {
        return "v\(version)"
    }
    return "v1.3.1"
}

// MARK: - Meeting Session Notebook Records & Persistence

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

/// Keep the application icon centered in permission dialogs on macOS.
private final class CenteredPermissionAlert: NSAlert {
    override func layout() {
        super.layout()
        guard let content = window.contentView else { return }
        centerIcon(in: content, content: content)
    }

    private func centerIcon(in view: NSView, content: NSView) {
        for child in view.subviews {
            if let imageView = child as? NSImageView, imageView.image === icon,
               let parent = imageView.superview {
                let center = parent.convert(NSPoint(x: content.bounds.midX, y: 0), from: content)
                var frame = imageView.frame
                frame.origin.x = center.x - frame.width / 2
                imageView.frame = frame
            } else {
                centerIcon(in: child, content: content)
            }
        }
    }
}

enum AppPermissionType {
    case screenCapture
    case microphone
    case speechRecognition
    case dictation
    case accessibility

    var title: String {
        switch self {
        case .screenCapture: return "Ghi màn hình & Âm thanh hệ thống"
        case .microphone: return "Microphone"
        case .speechRecognition: return "Nhận diện giọng nói (Speech Recognition)"
        case .dictation: return "Siri & Đọc chính tả (Dictation)"
        case .accessibility: return "Trợ năng (Accessibility - Phím tắt)"
        }
    }

    var message: String {
        switch self {
        case .screenCapture:
            return "Trans Tools cần quyền 'Ghi màn hình & Âm thanh hệ thống' để thu và dịch âm thanh từ các cuộc họp (Teams, Zoom, Meet, trình duyệt).\n\nBạn có muốn mở Cài đặt hệ thống (System Settings) để cấp quyền ngay không?"
        case .microphone:
            return "Trans Tools cần quyền 'Microphone' để thu âm giọng nói của bạn.\n\nBạn có muốn mở Cài đặt hệ thống để cấp quyền ngay không?"
        case .speechRecognition:
            return "Trans Tools cần quyền 'Nhận diện giọng nói' (Speech Recognition) để chuyển giọng nói cuộc họp thành văn bản phụ đề.\n\nBạn có muốn mở Cài đặt hệ thống để cấp quyền ngay không?"
        case .dictation:
            return "Ngôn ngữ này cần bật Siri & Đọc chính tả (Dictation) trong Cài đặt Bàn phím.\n\nBạn có muốn mở Cài đặt Bàn phím ngay không?"
        case .accessibility:
            return "Trans Tools cần quyền Trợ năng để đọc văn bản bạn bôi đen khi bấm phím tắt Option + D / Option + F.\n\nBạn có muốn mở Cài đặt hệ thống để cấp quyền ngay không?"
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
        case .accessibility:
            return "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
        }
    }
}

@MainActor final class MeetingModel: ObservableObject {
    static weak var shared: MeetingModel?
    @Published var lastDeletedNotebookSession: MeetingSession?
    @Published var lastDeletedNotebookSessions: [MeetingSession] = []

    @Published var applications: [SCRunningApplication] = []
    @Published var source = "system"
    @Published var provider: AIProvider = .apple
    @Published var modelName: String = "Tiêu chuẩn"
    @Published var availableModels: [String] = []
    @Published var isFetchingModels = false
    @Published var modelFetchMessage = ""
    @Published var isTestingAI = false
    @Published var aiTestMessage = ""
    @Published var key = ""

    // AI Meeting Co-Pilot (Phân tích ngữ cảnh & gợi ý câu trả lời tiếng Anh khi giao tiếp)
    @Published var coPilotProvider: AIProvider = .gemini
    @Published var coPilotModel: String = AIProvider.gemini.defaultModel
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
        // Seedly is now the single 3D mascot identity throughout the app.
        defaults.set("sprite", forKey: "MascotStyle")
        return "sprite"
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

    /// Selected keyed AI first, then configured assistant, then another saved AI.
    var configuredAI: (provider: AIProvider, model: String, key: String)? {
        let candidates = [provider, coPilotProvider] + AIProvider.allCases
        for candidate in candidates where candidate != .apple && candidate != .free {
            let candidateKey = (candidate == provider ? key : candidate == coPilotProvider ? coPilotKey : CredentialStore.read(for: candidate)).trimmingCharacters(in: .whitespacesAndNewlines)
            if !candidateKey.isEmpty {
                let name = candidate == provider ? modelName : candidate == coPilotProvider ? coPilotModel : UserDefaults.standard.string(forKey: "AIModel_\(candidate.rawValue)") ?? candidate.defaultModel
                return (candidate, name, candidateKey)
            }
        }
        return nil
    }

    func preferConfiguredAIIfNeeded() {
        guard UserDefaults.standard.object(forKey: "TranslationProviderExplicitChoice") == nil,
              let ai = configuredAI else { return }
        setProvider(ai.provider)
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
    @Published var meetingSuggestionsEnabled = false {
        didSet {
            if !meetingSuggestionsEnabled { suggestionTask?.cancel(); suggestedReplies = [] }
        }
    }
    @Published var suggestedReplies: [ReplySuggestion] = []
    @Published var isGeneratingSuggestions = false
    // Sample arrival must not invalidate the entire dashboard four times a second.
    // Signal views read the timestamp on their own timeline; only first arrival
    // changes the waiting screen.
    var audioMeter: AudioLevelMeter { speech.audioMeter }
    var lastAudio: Date?
    @Published private(set) var hasReceivedAudio = false
    private func noteAudioArrival(_ date: Date) {
        lastAudio = date
        if !hasReceivedAudio { hasReceivedAudio = true }
    }

    private var translatedOriginal: [UUID: String] = [:]
    private var sessionFinalizedWordsCount: Int = 0
    private var sessionFinalizedPrefix: String = ""
    private var immediateTranslationRequested: Bool = false
    private var finishingMeeting = false
    private var checkpointTask: Task<Void, Never>?
    private var recordingSourceName = ""
    private var lastRawRecognizedText: String = ""
    private var captionCommitTask: Task<Void, Never>?
    private var recognitionSessionStarted: Date = Date()

    // Ergonomics & Health Assistant (Nhắc nhở nghỉ ngơi, uống nước khi họp kéo dài)
    @Published var healthReminderMinutes: Int = {
        let saved = UserDefaults.standard.object(forKey: "HealthReminderMinutes") as? Int
        return saved ?? 45
    }() {
        didSet {
            UserDefaults.standard.set(healthReminderMinutes, forKey: "HealthReminderMinutes")
        }
    }
    private var healthReminderFiredCount: Int = 0

    // Multi-Language Support (EN, VI, ZH, JA, KO, FR, DE, ES)
    @Published var sourceLanguage: AppLanguage = {
        let saved = UserDefaults.standard.string(forKey: "SourceLanguage") ?? "en"
        return AppLanguage(rawValue: saved) ?? .english
    }() {
        didSet {
            UserDefaults.standard.set(sourceLanguage.rawValue, forKey: "SourceLanguage")
            // Existing captions keep their language pair; restartSpeechRecognition
            // changes only the recognizer after it snapshots the live phrase.
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
        guard running, !finishingMeeting else { return }
        // `LiveSpeech.start` already rotates its recognition task while retaining
        // the recent audio ring and pending buffers. Calling `stop` here erased
        // that audio and made an in-progress phrase appear to vanish.
        preserveCaptionBeforeRecognitionRestart()
        recognitionSessionStarted = Date()
        sessionFinalizedWordsCount = 0
        sessionFinalizedPrefix = ""
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
    private var recordingSessionID = UUID()
    @Published var liveTranslationPacing: LiveTranslationPacing = LiveTranslationPacing(rawValue: UserDefaults.standard.string(forKey: "LiveTranslationPacing") ?? "balanced") ?? .balanced {
        didSet { UserDefaults.standard.set(liveTranslationPacing.rawValue, forKey: "LiveTranslationPacing") }
    }
    private var translationTask: Task<Void, Never>?

    func hasCurrentTranslation(for caption: Caption) -> Bool {
        translatedOriginal[caption.id] == caption.original && !caption.vietnamese.isEmpty
    }
    private var rotationTask: Task<Void, Never>?
    private var session = UUID()
    private var activeKey = ""
    private var lastAudioUpdateTime: Date = .distantPast
    private var speechRotationTail = ""
    private var speechContinuation = ""
    private var lastRecognitionUpdate = Date.distantPast
    private var overlay: NSWindow?

    @Published var storageError: String?
    @Published var pendingConversationID: UUID?
    @Published var selectedDashboardTab: Int = UserDefaults.standard.object(forKey: "SelectedDashboardTab") as? Int ?? 0 {
        didSet { UserDefaults.standard.set(selectedDashboardTab, forKey: "SelectedDashboardTab") }
    }
    @Published var selectedNotebookTab: Int = UserDefaults.standard.object(forKey: "SelectedNotebookTab") as? Int ?? 0 {
        didSet { UserDefaults.standard.set(selectedNotebookTab, forKey: "SelectedNotebookTab") }
    }
    @Published var selectedSettingsSection: Int = UserDefaults.standard.object(forKey: "SelectedSettingsSection") as? Int ?? 0 {
        didSet { UserDefaults.standard.set(selectedSettingsSection, forKey: "SelectedSettingsSection") }
    }
    @Published var showSettingsSheet: Bool = false
    @Published var showAboutSheet: Bool = false
    @Published var isOverlayVisible: Bool = false
    private var mascotInSubtitleHUD = false

    func setMascotInSubtitleHUD(_ visible: Bool) {
        guard mascotInSubtitleHUD != visible else { return }
        mascotInSubtitleHUD = visible
        if visible {
            stopDockWalking()
            mascotWindow?.orderOut(nil)
            mascotWindow?.contentView = nil
        } else if isFloatingMascotVisible {
            showFloatingMascot()
        }
    }

    // MARK: - System Permissions & Launch at Login Management
    @Published var hasScreenCapturePermission: Bool = CGPreflightScreenCaptureAccess()
    @Published var hasMicrophonePermission: Bool = (AVCaptureDevice.authorizationStatus(for: .audio) == .authorized)
    @Published var hasSpeechRecognitionPermission: Bool = (SFSpeechRecognizer.authorizationStatus() == .authorized)
    @Published var hasAccessibilityPermission: Bool = AXIsProcessTrusted()
    @Published var isLaunchAtLoginEnabled: Bool = false

    var hasAllEssentialPermissions: Bool {
        hasScreenCapturePermission && hasMicrophonePermission && hasSpeechRecognitionPermission
    }

    func checkAllPermissions() {
        hasScreenCapturePermission = CGPreflightScreenCaptureAccess()
        hasMicrophonePermission = (AVCaptureDevice.authorizationStatus(for: .audio) == .authorized)
        hasSpeechRecognitionPermission = (SFSpeechRecognizer.authorizationStatus() == .authorized)
        hasAccessibilityPermission = AXIsProcessTrusted()
        updateLaunchAtLoginStatus()
    }

    func updateLaunchAtLoginStatus() {
        if #available(macOS 13.0, *) {
            isLaunchAtLoginEnabled = (SMAppService.mainApp.status == .enabled)
        }
    }

    func setLaunchAtLogin(enabled: Bool) {
        if #available(macOS 13.0, *) {
            do {
                if enabled {
                    if SMAppService.mainApp.status == .enabled {
                        try? SMAppService.mainApp.unregister()
                    }
                    try SMAppService.mainApp.register()
                } else {
                    try SMAppService.mainApp.unregister()
                }
            } catch {
                print("Lỗi cấu hình Launch at Login: \(error)")
            }
            updateLaunchAtLoginStatus()
        }
    }

    func requestMicrophonePermission() {
        AVCaptureDevice.requestAccess(for: .audio) { [weak self] _ in
            DispatchQueue.main.async {
                self?.checkAllPermissions()
            }
        }
    }

    func requestSpeechRecognitionPermission() {
        SFSpeechRecognizer.requestAuthorization { [weak self] _ in
            DispatchQueue.main.async {
                self?.checkAllPermissions()
            }
        }
    }

    func requestScreenCapturePermission() {
        triggerScreenCapturePrompt()
        openPermissionSettings(for: .screenCapture)
    }

    func requestAccessibilityPermission() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
        openPermissionSettings(for: .accessibility)
    }

    init() {
        MascotResourceImages.preload()
        // Subtitle translation defaults to Apple; latency depends on model readiness and text length.
        let savedProviderRaw = UserDefaults.standard.string(forKey: "AIProvider") ?? "apple"
        let initialProvider = AIProvider(rawValue: savedProviderRaw) ?? .apple
        self.provider = initialProvider
        self.key = CredentialStore.read(for: initialProvider)
        var savedModel = UserDefaults.standard.string(forKey: "AIModel_\(initialProvider.rawValue)") ?? initialProvider.defaultModel
        if initialProvider == .gemini && (savedModel.isEmpty || savedModel == "gemini-1.5-flash") {
            savedModel = initialProvider.defaultModel
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
        if initialCoPilot == .gemini && (savedCoPilotModel.isEmpty || savedCoPilotModel == "gemini-1.5-flash") {
            savedCoPilotModel = initialCoPilot.defaultModel
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
                Task { @MainActor [weak self] in self?.noteAudioArrival(now) }
            }
        }
        capture.onMicrophone = { [weak self] buffer in
            guard let self else { return }
            self.speech.append(buffer)
            let now = Date()
            if now.timeIntervalSince(self.lastAudioUpdateTime) > 0.25 {
                self.lastAudioUpdateTime = now
                Task { @MainActor [weak self] in self?.noteAudioArrival(now) }
            }
        }
        capture.onError = { [weak self] error in
            Task { @MainActor in await self?.fail(error) }
        }
        speech.onTimedResult = { [weak self] text, final, words, generation in
            guard let self else { return }
            Task { @MainActor [weak self] in
                guard let self, self.speech.currentGeneration == generation else { return }
                self.receive(text, final: final, timedWords: words)
            }
        }
        speech.onSessionEndedOrTimeout = { [weak self] in
            guard let self else { return }
            let generation = self.speech.currentGeneration
            Task { @MainActor [weak self] in
                guard let self, self.speech.currentGeneration == generation else { return }
                self.handleSpeechSessionEndedOrTimeout()
            }
        }
        speech.onError = { [weak self] error in
            guard let self else { return }
            let generation = self.speech.currentGeneration
            Task { @MainActor [weak self] in
                guard let self, !self.finishingMeeting,
                      self.speech.currentGeneration == generation else { return }
                await self.fail(error)
            }
        }
        Task { [weak self] in
            await self?.refresh()
            // The mascot is the launch surface; the dashboard opens on demand.
            self?.showFloatingMascot()
        }
        loadSessions()
        preferConfiguredAIIfNeeded()

        MeetingModel.shared = self
        GlobalHotkeyManager.shared.registerHotkeys()
        checkAllPermissions()

        // 3. Tự động kiểm tra bản cập nhật mới sau 3 giây khởi động
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
            let alert = CenteredPermissionAlert()
            alert.icon = NSApp.applicationIconImage
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

    var subtitleEngineLabel: String {
        if provider == .apple { return "Translate · local" }
        if provider == .free || activeKey.isEmpty { return "Google Dịch · online" }
        return "\(provider.shortName) · online"
    }

    func setProvider(_ newProvider: AIProvider) {
        UserDefaults.standard.set(true, forKey: "TranslationProviderExplicitChoice")
        guard provider != newProvider else { return }
        provider = newProvider
        UserDefaults.standard.set(newProvider.rawValue, forKey: "AIProvider")
        key = CredentialStore.read(for: newProvider)
        activeKey = key.trimmingCharacters(in: .whitespacesAndNewlines)
        var savedModel = UserDefaults.standard.string(forKey: "AIModel_\(newProvider.rawValue)") ?? newProvider.defaultModel
        if newProvider == .gemini && (savedModel.isEmpty || savedModel == "gemini-1.5-flash") {
            savedModel = newProvider.defaultModel
            UserDefaults.standard.set(savedModel, forKey: "AIModel_\(newProvider.rawValue)")
        }
        modelName = savedModel
        availableModels = newProvider.defaultModels
        modelFetchMessage = ""
        if coPilotProvider == newProvider && coPilotKey.isEmpty {
            coPilotKey = activeKey
        }
        if !activeKey.isEmpty {
            Task { await fetchModels() }
        }
        if running {
            status = "Đang nghe \(sourceLanguage.displayName) và dịch sang \(targetLanguage.displayName) (\(subtitleEngineLabel))"
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
        guard !isFetchingModels else { return }
        let targetProvider = provider
        let apiKey = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !apiKey.isEmpty else {
            modelFetchMessage = "Vui lòng nhập API Key trước khi lấy model."
            return
        }
        isFetchingModels = true
        modelFetchMessage = ""
        do {
            let list = try await AITranslator.fetchModels(for: targetProvider, key: apiKey)
            guard provider == targetProvider, key.trimmingCharacters(in: .whitespacesAndNewlines) == apiKey else { isFetchingModels = false; return }
            if !list.isEmpty {
                availableModels = list
                if coPilotProvider == provider {
                    availableCoPilotModels = list
                }
                modelFetchMessage = list.contains(modelName)
                    ? "Đã tải \(list.count) model khả dụng từ \(provider.shortName)."
                    : "Model đã lưu không có trong danh sách mới. Hãy chọn model khả dụng."
            } else {
                modelFetchMessage = "Không có model phù hợp."
            }
        } catch {
            modelFetchMessage = "Lỗi: \(error.localizedDescription)"
        }
        isFetchingModels = false
    }

    func acceptResolvedModel(_ notification: Notification) {
        guard let raw = notification.userInfo?["provider"] as? String,
              let target = AIProvider(rawValue: raw),
              let previous = notification.userInfo?["previous"] as? String,
              let resolved = notification.userInfo?["model"] as? String else { return }
        if provider == target && modelName == previous { updateModelName(resolved, for: target) }
        if coPilotProvider == target && coPilotModel == previous {
            coPilotModel = resolved
            UserDefaults.standard.set(resolved, forKey: "AICoPilotModel_\(target.rawValue)")
        }
    }

    func testAIConnection() async {
        guard !isTestingAI else { return }
        guard let ai = configuredAI else { aiTestMessage = "Thêm API key trước khi kiểm tra."; return }
        isTestingAI = true; aiTestMessage = "Đang gọi thử AI…"
        defer { isTestingAI = false }
        do {
            _ = try await AITransport.complete(prompt: "Reply with exactly: Hello!", provider: ai.provider, model: ai.model, key: ai.key)
            let resolved = await AITransport.resolvedModel(provider: ai.provider, model: ai.model, key: ai.key)
            aiTestMessage = "Kết nối thành công · \(ai.provider.shortName) · \(resolved)"
        } catch { aiTestMessage = "Chưa kết nối được: \(error.localizedDescription)" }
    }

    func saveSettings() {
        let trimmedKey = key.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            try CredentialStore.save(trimmedKey, for: provider)
            UserDefaults.standard.set(modelName, forKey: "AIModel_\(provider.rawValue)")
            UserDefaults.standard.set(provider.rawValue, forKey: "AIProvider")
            activeKey = trimmedKey
            if coPilotProvider == provider {
                coPilotKey = trimmedKey
            }
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
        var savedModel = UserDefaults.standard.string(forKey: "AICoPilotModel_\(newProvider.rawValue)") ?? newProvider.defaultModel
        if newProvider == .gemini && (savedModel.isEmpty || savedModel == "gemini-1.5-flash") {
            savedModel = newProvider.defaultModel
            UserDefaults.standard.set(savedModel, forKey: "AICoPilotModel_\(newProvider.rawValue)")
        }
        coPilotModel = savedModel
        availableCoPilotModels = newProvider.defaultModels
        coPilotFetchMessage = ""
        if provider == newProvider && key.isEmpty {
            key = coPilotKey
            activeKey = coPilotKey.trimmingCharacters(in: .whitespacesAndNewlines)
        }
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
                if provider == coPilotProvider {
                    availableModels = list
                }
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
            if provider == coPilotProvider {
                key = trimmedKey
                activeKey = trimmedKey
                modelName = coPilotModel
                UserDefaults.standard.set(coPilotModel, forKey: "AIModel_\(provider.rawValue)")
            }
        } catch {
            warning = "Không lưu được khóa mã hóa: \(error.localizedDescription)"
        }
    }

    func saveKeyForProvider(_ newKey: String, for targetProvider: AIProvider) {
        let trimmedKey = newKey.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            try CredentialStore.save(trimmedKey, for: targetProvider)
            if provider == targetProvider {
                key = trimmedKey
                activeKey = trimmedKey
            }
            if coPilotProvider == targetProvider {
                coPilotKey = trimmedKey
            }
            if !trimmedKey.isEmpty {
                Task {
                    if let list = try? await AITranslator.fetchModels(for: targetProvider, key: trimmedKey), !list.isEmpty {
                        await MainActor.run {
                            if self.provider == targetProvider {
                                self.availableModels = list
                            }
                            if self.coPilotProvider == targetProvider {
                                self.availableCoPilotModels = list
                            }
                        }
                    }
                }
            }
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
            captionCommitTask?.cancel(); captionCommitTask = nil
            meetingAssistantDraft.resetSession()
            subtitleQuick.resetSession()
            miniTools.state.translation.resetSession()
            started = Date(); recordingSessionID = UUID(); captions = []; translatedOriginal = [:]; currentID = UUID(); lastAudio = nil; hasReceivedAudio = false; session = UUID()
            healthReminderFiredCount = 0
            lastRawRecognizedText = ""
            speechRotationTail = ""
        speechContinuation = ""
            sessionFinalizedWordsCount = 0
            sessionFinalizedPrefix = ""
            immediateTranslationRequested = false
            recognitionSessionStarted = Date()
            running = true
            recordingSourceName = currentSourceName()
            beginMeetingCheckpoints()
            status = "Đang kết nối luồng âm thanh..."
            try speech.start(localeIdentifier: sourceLanguage.speechLocale)
            rotationTask?.cancel()
            rotationTask = Task { [weak self] in
                while !Task.isCancelled {
                    do { try await Task.sleep(nanoseconds: 2_000_000_000) }
                    catch { return }
                    guard let self, self.running else { break }
                    await MainActor.run {
                        self.rotateSpeechSessionIfNeeded()
                        self.checkHealthReminder()
                    }
                }
            }
            if source == "microphone" {
                try capture.startMicrophone()
            } else if source == "system" {
                try await capture.startSystemAudio()
            } else {
                // A failed app-specific capture must never widen the selected
                // source: unrelated audio would contaminate captions and AI context.
                try await capture.start(applicationID: source)
            }
            status = "Đang nghe \(sourceLanguage.displayName) và dịch sang \(targetLanguage.displayName) (\(subtitleEngineLabel))"
        } catch { await fail(error) }
    }

    /// Open the compact meeting view only after capture starts successfully.
    func startFromMascot() async {
        guard !busy, !running else { return }
        if source.isEmpty { source = "system" }
        mascotQuickSubtitle.connect(self)
        mascotQuickSubtitle.showCompact()
        await start()
        guard running else {
            mascotQuickSubtitle.hideCompact()
            showMainWindow()
            return
        }
        mainWindow?.orderOut(nil)
    }

    func stop() async {
        guard !finishingMeeting else { return }
        finishingMeeting = true
        busy = true
        defer { finishingMeeting = false; busy = false }
        let checkpoint = checkpointTask
        checkpointTask?.cancel(); checkpointTask = nil
        await checkpoint?.value
        captionCommitTask?.cancel(); captionCommitTask = nil
        finalizeCurrentCaption(immediateTranslation: true)
        // Freeze recognition before draining translations. Keep the session token
        // valid so the final in-flight result can still reach its original row.
        rotationTask?.cancel(); rotationTask = nil
        speech.stop()
        await capture.stop()
        TTSService.shared.stop()
        currentID = UUID()
        let deadline = Date().addingTimeInterval(8)
        status = "Đang hoàn tất bản dịch và lưu cuộc họp…"
        while translationTask != nil, Date() < deadline, !Task.isCancelled {
            try? await Task.sleep(for: .milliseconds(100))
        }
        let pendingCount = subtitleMode == .originalOnly ? 0 : captions.filter {
            !$0.original.isEmpty && translatedOriginal[$0.id] != $0.original
        }.count
        running = false; session = UUID()
        sessionFinalizedWordsCount = 0
        sessionFinalizedPrefix = ""
        immediateTranslationRequested = false
        lastRawRecognizedText = ""
        rotationTask?.cancel(); rotationTask = nil
        translationTask?.cancel(); translationTask = nil
        if !captions.isEmpty {
            saveCurrentSession()
            if storageError == nil {
                do { try await MeetingCheckpointStore.shared.remove(sessionID: recordingSessionID, from: checkpointFileURL) }
                catch { warning = "Đã lưu Sổ tay; bản khôi phục vẫn được giữ lại." }
            }
            if storageError == nil {
                status = "Đã dừng. Cuộc họp đã được lưu vào Sổ tay."
                if pendingCount > 0 {
                    warning = "Đã giữ toàn bộ lời nhận diện. Còn \(pendingCount) đoạn chưa dịch xong; không xóa lời gốc."
                }
            }
            if storageError == nil, let ai = configuredAI,
               let savedID = sessions.first(where: { $0.id == recordingSessionID })?.id {
                let transcript = captions.map { "[\(Self.timestamp($0.start))] \($0.original)" }.joined(separator: "\n")
                let domain = domainSpecialty
                Task { [weak self] in
                    do {
                        let summary = try await AITranslator.summarizeMeeting(transcript, domain: domain, provider: ai.provider, model: ai.model, key: ai.key)
                        guard let self, let index = self.sessions.firstIndex(where: { $0.id == savedID }) else { return }
                        let existing = self.sessions[index].notes
                        self.updateSessionNotes(id: savedID, notes: existing + (existing.isEmpty ? "" : "\n\n") + "Tóm tắt cuộc họp\n" + summary)
                    } catch {
                        self?.warning = "Đã lưu phụ đề. Chưa thể tóm tắt cuộc họp: \(error.localizedDescription)"
                    }
                }
            }
        } else {
            status = "Đã dừng. Chọn nguồn âm thanh để bắt đầu phiên mới."
        }
    }
    func prepareForTermination() async -> Bool {
        // A user may quit while the HUD is already finalizing the meeting.
        while finishingMeeting { try? await Task.sleep(for: .milliseconds(100)) }
        if running { await stop() }
        return captions.isEmpty || storageError == nil
    }

    private func fail(_ error: Error) async {
        guard (running || busy), !finishingMeeting else { return }
        await stop()
        let msg = error.localizedDescription
        if msg.localizedCaseInsensitiveContains("TCC") || msg.localizedCaseInsensitiveContains("declined") {
            warning = "Chưa cấp quyền Ghi màn hình & Âm thanh hệ thống. Hãy cấp quyền trong Cài đặt hệ thống."
            promptPermissionSettings(for: .screenCapture)
        } else {
            warning = msg
        }
    }

    private func preserveCaptionBeforeRecognitionRestart() {
        captionCommitTask?.cancel()
        captionCommitTask = nil
        finalizeCurrentCaption(immediateTranslation: true)
        speechRotationTail = lastRawRecognizedText
        // A new recognition request owns a new live row. Completed rows must
        // never be revised by hypotheses from a different audio request.
        speechContinuation = ""
        currentID = UUID()
    }

    private func handleSpeechSessionEndedOrTimeout() {
        guard running, !finishingMeeting else { return }
        preserveCaptionBeforeRecognitionRestart()
        sessionFinalizedPrefix = ""
        sessionFinalizedWordsCount = 0
        recognitionSessionStarted = Date()
        do {
            try speech.start(localeIdentifier: sourceLanguage.speechLocale)
        } catch {
            Task { await self.fail(error) }
        }
    }

    private func rotateSpeechSessionIfNeeded() {
        guard running, !finishingMeeting else { return }
        if speech.recognitionStalled {
            print("[Meeting] Recognition stalled with voiced audio; recovering without clearing captions")
            preserveCaptionBeforeRecognitionRestart()
            sessionFinalizedPrefix = ""
            sessionFinalizedWordsCount = 0
            recognitionSessionStarted = Date()
            do { try speech.start(localeIdentifier: sourceLanguage.speechLocale, replayDuration: 16) }
            catch { Task { await self.fail(error) } }
            return
        }
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

        preserveCaptionBeforeRecognitionRestart()
        sessionFinalizedPrefix = ""
        sessionFinalizedWordsCount = 0
        recognitionSessionStarted = Date()
        do {
            try speech.start(localeIdentifier: sourceLanguage.speechLocale)
        } catch {
            Task { await self.fail(error) }
        }
    }

    private func checkHealthReminder() {
        guard running, healthReminderMinutes > 0 else { return }
        let elapsedMinutes = Int(Date().timeIntervalSince(started) / 60)
        let expectedCount = elapsedMinutes / healthReminderMinutes
        if expectedCount > healthReminderFiredCount {
            healthReminderFiredCount = expectedCount
            let mins = expectedCount * healthReminderMinutes
            showSpeechBubble(
                word: "Đến giờ giải lao rồi 🌱",
                meaning: "Bạn đã họp liên tục hơn \(mins) phút. Hãy uống một ngụm nước ấm, chớp mắt và thả lỏng vai một chút nhé!",
                phonetic: "",
                context: "⏰ Trợ lý sức khỏe công thái học",
                sourceApp: "Trans Tools Health"
            )
            mascotIdleActivity = .sippingTea
        }
    }

    private var recognitionTrace = MeetingRecognitionTrace.fromEnvironment()
    @Published private(set) var recognitionTraceURL: URL?
    var recognitionTraceEnabled: Bool { recognitionTrace != nil }

    func toggleRecognitionTrace() {
        if recognitionTrace != nil {
            recognitionTraceURL = recognitionTrace?.destination
            recognitionTrace = nil
            return
        }
        guard !running else { return }
        let alert = NSAlert()
        alert.messageText = "Bật nhật ký kiểm thử nhận dạng?"
        alert.informativeText = "Nhật ký chứa lời nói nhận dạng và thời gian từng từ, chỉ lưu trên máy (tối đa 10 MB). Hãy dùng audio mẫu, không dùng cuộc họp riêng. Nhật ký tự tắt khi thoát app."
        alert.addButton(withTitle: "Bật để kiểm thử")
        alert.addButton(withTitle: "Hủy")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("TransTools/Diagnostics", isDirectory: true)
        let url = directory.appendingPathComponent("recognition-\(UUID().uuidString).jsonl")
        recognitionTrace = MeetingRecognitionTrace(url: url)
        recognitionTraceURL = url
    }

    func revealRecognitionTrace() {
        guard let url = recognitionTrace?.destination ?? recognitionTraceURL,
              FileManager.default.fileExists(atPath: url.path) else { return }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    private func currentCaptionIndex() -> Int? {
        CaptionLookup.index(in: captions, id: currentID, identifier: { $0.id })
    }

    private var currentCaption: Caption? {
        currentCaptionIndex().map { captions[$0] }
    }

    private func traceRecognition(_ phase: String, text: String, final: Bool, timedWords: [(String, Double, Double)]) {
        guard let recognitionTrace else { return }
        recognitionTrace.record(.init(phase: phase, generation: speech.currentGeneration, currentID: currentID,
            raw: String(text.prefix(16_000)), committed: String(sessionFinalizedPrefix.prefix(16_000)),
            rotationTail: String(speechRotationTail.prefix(16_000)), captionCount: captions.count,
            liveText: String((currentCaption?.original ?? "").prefix(16_000)), final: final,
            elapsed: Date().timeIntervalSince(started),
            words: timedWords.suffix(512).map { .init(text: String($0.0.prefix(128)), start: $0.1, end: $0.2) }))
    }

    private func receive(_ text: String, final: Bool, timedWords: [(String, Double, Double)] = []) {
        guard running, !finishingMeeting else { return }
        traceRecognition("before", text: text, final: final, timedWords: timedWords)
        defer { traceRecognition("after", text: text, final: final, timedWords: timedWords) }
        let raw = text.trimmingCharacters(in: .whitespacesAndNewlines)
        // Partial word timestamps can move when recognition revises a sentence.
        // Never discard newly recognized text solely because those times overlap.
        let trimmedRaw = SpeechTextReconciler.removingOverlap(raw, after: speechRotationTail)
        guard !trimmedRaw.isEmpty else {
            if final { handleSpeechSessionEndedOrTimeout() }
            return
        }
        lastRecognitionUpdate = Date()
        let elapsed = Date().timeIntervalSince(started)

        var currentText = speechContinuation.isEmpty ? trimmedRaw : speechContinuation + " " + trimmedRaw
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
        if speechContinuation.isEmpty,
           let previous = currentCaption,
           let newTail = SpeechTextReconciler.replacementTail(previous.original, incoming: currentText) {
            finalizeCurrentCaption(immediateTranslation: true)
            currentID = UUID()
            currentText = newTail
            if let range = trimmedRaw.range(of: newTail, options: .backwards), range.upperBound == trimmedRaw.endIndex {
                sessionFinalizedPrefix = String(trimmedRaw[..<range.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
                sessionFinalizedWordsCount = SpeechTextReconciler.words(sessionFinalizedPrefix).count
            }
        }
        // Some recognition updates begin a fresh utterance without isFinal.
        // A later audio span must not replace the preceding live sentence.
        if speechContinuation.isEmpty,
           let previous = currentCaption,
           previous.original != currentText,
           !currentText.hasPrefix(previous.original), !previous.original.hasPrefix(currentText),
           SpeechTextReconciler.beginsNewUtterance(previous.original, incoming: currentText) {
            finalizeCurrentCaption(immediateTranslation: true)
            currentID = UUID()
        }
        lastRawRecognizedText = trimmedRaw

        // Update or append current live caption
        if let index = currentCaptionIndex() {
            let previousText = captions[index].original
            currentText = SpeechTextReconciler.keepLongerPartial(captions[index].original, incoming: currentText, final: final)
            // Identical partial hypotheses carry no new visible information.
            // Final results still run finalization and preserve end timing.
            if !final && captions[index].original == currentText { return }
            var updated = captions[index]
            updated.original = currentText
            if previousText != currentText { updated.sourceRevision += 1 }
            updated.end = elapsed
            // Keep the last visible translation while ASR revises the source.
            // Invalidate its source mapping so it is never treated as current,
            // but let the HUD retain it until the replacement is ready.
            if previousText != currentText,
               let translatedSource = translatedOriginal[currentID],
               !SpeechTextReconciler.canPublishTranslation(source: translatedSource, current: currentText) {
                translatedOriginal[currentID] = nil
            }
            captions[index] = updated
        } else {
            // Separate audio turns can legitimately repeat the same words.
            // Replay removal happens at the recognition boundary, not by
            // deleting a new row simply because its text matches the last one.
            captions.append(Caption(id: currentID, start: elapsed, end: elapsed, original: currentText, sourceLanguage: sourceLanguage.rawValue))
        }

        // Keep enough context for a natural phrase before forcing a safety split.
        // Smaller chunks over-segmented continuous speech and triggered extra
        // translation work, which made both captions and the HUD feel delayed.
        let chunks = CaptionSegmenter.chunks(currentText, raw: raw, segments: timedWords)
        // Commit complete sentences / bounded clauses, retaining the last live
        // fragment in the same recognition session instead of restarting audio.
        if chunks.count > 1 {
            let firstID = currentID
            let firstStart = captions.first(where: { $0.id == firstID })?.start ?? elapsed
            let duration = max(0, elapsed - firstStart)
            let totalCharacters = max(1, chunks.reduce(0) { $0 + $1.count })
            var consumedCharacters = 0
            for (offset, chunk) in chunks.enumerated() {
                if offset > 0 { currentID = UUID() }
                let start = firstStart + duration * Double(consumedCharacters) / Double(totalCharacters)
                consumedCharacters += chunk.count
                let end = firstStart + duration * Double(consumedCharacters) / Double(totalCharacters)
                if let index = currentCaptionIndex() {
                    if captions[index].original != chunk {
                        captions[index].original = chunk
                        captions[index].sourceRevision += 1
                        // The old translation is no longer considered current,
                        // but remains visible until this chunk's replacement arrives.
                        translatedOriginal[currentID] = nil
                    }
                    captions[index].end = end
                } else {
                    captions.append(Caption(id: currentID, start: start, end: end, original: chunk, sourceLanguage: sourceLanguage.rawValue))
                }
                if offset < chunks.count - 1 { finalizeCurrentCaption(immediateTranslation: true) }
            }
            if let remainder = chunks.last, let range = trimmedRaw.range(of: remainder, options: .backwards), range.upperBound == trimmedRaw.endIndex {
                sessionFinalizedPrefix = String(trimmedRaw[..<range.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
                sessionFinalizedWordsCount = SpeechTextReconciler.words(sessionFinalizedPrefix).count
                speechContinuation = ""
            }
        }

        if final {
            speechContinuation = ""
            speechRotationTail = lastRawRecognizedText
            finalizeCurrentCaption(immediateTranslation: true)
            sessionFinalizedPrefix = ""
            sessionFinalizedWordsCount = 0
            currentID = UUID()
            recognitionSessionStarted = Date()
            if running {
                do { try speech.start(localeIdentifier: sourceLanguage.speechLocale) }
                catch { Task { await fail(error) } }
            }
        } else if let row = currentCaption {
            scheduleTranslation(id: row.id, text: row.original, immediate: false)
            scheduleCaptionCommit(row)
        }
    }

    private func scheduleCaptionCommit(_ row: Caption) {
        captionCommitTask?.cancel()
        guard SpeechTextReconciler.words(row.original).count >= 2,
              let last = row.original.last, ".!?。！？".contains(last) else { return }
        captionCommitTask = Task { @MainActor [weak self] in
            do { try await Task.sleep(nanoseconds: 1_200_000_000) } catch { return }
            guard let self, self.running, self.currentID == row.id,
                  self.captions.first(where: { $0.id == row.id })?.original == row.original else { return }
            self.finalizeCurrentCaption(immediateTranslation: true)
            self.sessionFinalizedPrefix = self.lastRawRecognizedText
            self.sessionFinalizedWordsCount = SpeechTextReconciler.words(self.sessionFinalizedPrefix).count
            self.speechContinuation = ""
            self.currentID = UUID()
        }
    }

    private func finalizeCurrentCaption(immediateTranslation: Bool) {
        guard let row = currentCaption, !row.original.isEmpty else { return }
        immediateTranslationRequested = immediateTranslation
        scheduleTranslation(id: row.id, text: row.original, immediate: immediateTranslation)
        if meetingSuggestionsEnabled { generateSuggestions(for: row.original) }
        if subtitleMode != .originalOnly, translatedOriginal[row.id] == row.original, !row.vietnamese.isEmpty {
            TTSService.shared.enqueueAutoTTS(id: row.id, original: row.original,
                translation: row.vietnamese, sourceLang: sourceLanguage, targetLang: targetLanguage)
        }
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

    private var lastSuggestionRequest = Date.distantPast
    private var meetingAssistWindow: NSWindow?
    let meetingAssistantDraft = MeetingAssistantDraftStore()
    @Published var subtitleAssistantVisible = UserDefaults.standard.bool(forKey: "SubtitleAssistantVisible") {
        didSet { UserDefaults.standard.set(subtitleAssistantVisible, forKey: "SubtitleAssistantVisible") }
    }
    func showAssistantInSubtitles() {
        closeSeparateMeetingAssistant()
        showOverlay()
        subtitleAssistantVisible = true
        setSubtitleAssistantExpanded(true)
        overlay?.makeKeyAndOrderFront(nil)
    }
    @Published private(set) var meetingAssistantInSeparateWindow = false
    func separateMeetingAssistantDidClose() {
        meetingAssistantInSeparateWindow = false
    }
    func closeSeparateMeetingAssistant() {
        meetingAssistantInSeparateWindow = false
        meetingAssistWindow?.close()
    }
    func showMeetingAssistBoard() {
        meetingAssistantInSeparateWindow = true
        if let window = meetingAssistWindow { window.makeKeyAndOrderFront(nil); return }
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 700, height: 560), styleMask: [.titled, .closable, .resizable, .miniaturizable], backing: .buffered, defer: false)
        window.identifier = NSUserInterfaceItemIdentifier("meeting-assist-board")
        window.title = "Trợ giúp cuộc họp"
        window.contentView = NSHostingView(rootView: MeetingAssistBoard(model: self))
        window.isReleasedWhenClosed = false; window.minSize = NSSize(width: 560, height: 400)
        meetingAssistWindow = window; window.center(); window.makeKeyAndOrderFront(nil)
    }

    func generateSuggestions(for customText: String? = nil) {
        meetingSuggestionsEnabled = true
        let latestUtterance = customText ?? captions.last(where: { !$0.original.isEmpty })?.original ?? ""
        guard !latestUtterance.isEmpty, !isGeneratingSuggestions else { return }
        if customText != nil && Date().timeIntervalSince(lastSuggestionRequest) < 30 { return }
        guard !coPilotKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        lastSuggestionRequest = Date()

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
        translationTask = Task { [weak self] in
            guard let self else { return }
            // A cancelled meeting task can finish after the next session starts.
            // It must not erase that session's active translation task.
            defer { if self.session == token { self.translationTask = nil } }
            // A failed sentence must not block all later captions. Retry twice
            // per source revision; a later stream update can retry it again.
            var failedSources: [UUID: String] = [:]
            var attempts: [UUID: Int] = [:]
            while !Task.isCancelled, self.running, self.session == token, self.subtitleMode != .originalOnly {
                // Find next caption needing translation
                guard let row = self.captions.first(where: { self.translatedOriginal[$0.id] != $0.original && !$0.original.isEmpty && failedSources[$0.id] != $0.original }) else { break }

                let isCurrentLiveRow = (row.id == self.currentID)
                let shouldDebounce = isCurrentLiveRow && !self.immediateTranslationRequested
                if shouldDebounce {
                    let began = Date()
                    var sampledText = row.original
                    var changedAt = began
                    while !Task.isCancelled, self.session == token, row.id == self.currentID, !self.immediateTranslationRequested {
                        guard let latest = self.captions.first(where: { $0.id == row.id }) else { break }
                        let now = Date()
                        if latest.original != sampledText {
                            sampledText = latest.original
                            changedAt = now
                        }
                        if self.liveTranslationPacing.ready(text: sampledText,
                            quiet: now.timeIntervalSince(changedAt), elapsed: now.timeIntervalSince(began)) { break }
                        try? await Task.sleep(for: .milliseconds(50))
                    }
                    guard !Task.isCancelled, self.session == token else { return }
                }
                self.immediateTranslationRequested = false

                var attemptedSource = row.original
                do {
                    guard let latestRow = self.captions.first(where: { $0.id == row.id }) else { continue }
                    let textToTranslate = latestRow.original
                    let revisionToTranslate = latestRow.sourceRevision
                    attemptedSource = textToTranslate
                    let currentProvider = self.provider
                    let currentModel = self.modelName
                    let currentKey = self.activeKey
                    let sourceLanguage = latestRow.sourceLanguage.flatMap(AppLanguage.init(rawValue:)) ?? self.sourceLanguage
                    let targetLanguage = self.targetLanguage
                    let domain = self.domainSpecialty
                    let translated = try await AITranslator.translate(
                        textToTranslate,
                        from: sourceLanguage,
                        to: targetLanguage,
                        domain: domain,
                        provider: currentProvider,
                        model: currentModel,
                        key: currentKey,
                        allowNetworkFallback: currentProvider != .apple
                    )
                    guard !Task.isCancelled, self.session == token else { return }
                    // Settings may change while awaiting the provider. Never
                    // publish an old language/model result under the new settings.
                    guard self.provider == currentProvider, self.modelName == currentModel,
                          self.activeKey == currentKey,
                          self.targetLanguage == targetLanguage, self.domainSpecialty == domain else { continue }
                    guard !translated.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                        throw NSError(domain: "MeetingTranslation", code: 1,
                            userInfo: [NSLocalizedDescriptionKey: "Dịch vụ trả về bản dịch trống. Lời gốc vẫn được giữ lại."])
                    }
                    attempts[row.id] = nil
                    if let index = self.captions.firstIndex(where: { $0.id == row.id }) {
                        // Show a valid prefix while speech grows; corrected hypotheses still reject obsolete output.
                        let currentOriginal = self.captions[index].original
                        guard currentOriginal == textToTranslate || (row.id == self.currentID && SpeechTextReconciler.canPublishTranslation(source: textToTranslate, current: currentOriginal)) else { continue }
                        var translatedRow = self.captions[index]
                        translatedRow.vietnamese = translated
                        translatedRow.targetLanguage = targetLanguage.rawValue
                        translatedRow.translationProvider = currentProvider.rawValue
                        translatedRow.translationModel = currentModel
                        translatedRow.translationSource = textToTranslate
                        translatedRow.translationRevision = revisionToTranslate
                        self.captions[index] = translatedRow
                        self.translatedOriginal[row.id] = textToTranslate
                        self.warning = ""
                        // Live revisions must not repeatedly interrupt the spoken caption.
                        if row.id != self.currentID, !self.finishingMeeting {
                            TTSService.shared.enqueueAutoTTS(
                                id: row.id,
                                original: textToTranslate,
                                translation: translated,
                                sourceLang: self.sourceLanguage,
                                targetLang: self.targetLanguage
                            )
                        }
                    }
                } catch {
                    guard !Task.isCancelled, self.session == token else { return }
                    self.warning = error.localizedDescription
                    let count = (attempts[row.id] ?? 0) + 1
                    attempts[row.id] = count
                    if count >= 2 {
                        failedSources[row.id] = attemptedSource
                        attempts[row.id] = nil
                    }
                    do { try await Task.sleep(for: .milliseconds(500)) }
                    catch { return }
                }
            }
        }
    }

    private var subtitleFrameBeforeAssistant: NSRect?
    private var subtitleFrameWithAssistant: NSRect?
    func setSubtitleAssistantExpanded(_ expanded: Bool) {
        guard let panel = overlay else { return }
        if expanded {
            guard subtitleFrameBeforeAssistant == nil else { return }
            subtitleFrameBeforeAssistant = panel.frame
            let screen = panel.screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? panel.frame
            var frame = panel.frame
            frame.size.width = min(screen.width, max(frame.width + 340, 920))
            frame.size.height = min(screen.height, frame.height)
            frame.origin.x = min(max(screen.minX, frame.minX), screen.maxX - frame.width)
            frame.origin.y = min(max(screen.minY, frame.minY), screen.maxY - frame.height)
            subtitleFrameWithAssistant = frame
            panel.setFrame(frame, display: true, animate: false)
        } else if let previous = subtitleFrameBeforeAssistant {
            subtitleFrameBeforeAssistant = nil
            let screen = panel.screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? previous
            let resized = MeetingAssistantLayout.preservingResize(previous: previous, expanded: subtitleFrameWithAssistant ?? panel.frame, current: panel.frame)
            subtitleFrameWithAssistant = nil
            let restored = MeetingAssistantLayout.restoredFrame(previous: resized, current: panel.frame, screen: screen)
            panel.setFrame(restored, display: true, animate: false)
        }
    }

    func showOverlay() {
        miniTools.hide()
        if let overlay {
            overlay.orderFrontRegardless()
            isOverlayVisible = true
            if UserDefaults.standard.object(forKey: "SubtitleQuickInputVisible") as? Bool ?? true { ensureSubtitleComposerSpace() }
            return
        }

        var initialRect: NSRect
        let savedX = UserDefaults.standard.double(forKey: "OverlayWindowX")
        let savedY = UserDefaults.standard.double(forKey: "OverlayWindowY")
        let savedW = UserDefaults.standard.double(forKey: "OverlayWindowW")
        let savedH = UserDefaults.standard.double(forKey: "OverlayWindowH")

        // Wider and more comfortable default width (780pt) for dual-language subtitles
        let defaultW: CGFloat = 780
        let defaultH: CGFloat = 180
        let w: CGFloat = (savedW >= 500) ? savedW : defaultW
        let h: CGFloat = max(280, (savedH >= 90) ? savedH : defaultH)

        if savedX > 50 && savedY > 50 {
            initialRect = NSRect(x: savedX, y: savedY, width: w, height: h)
        } else if let screen = NSScreen.main {
            let v = screen.visibleFrame
            initialRect = NSRect(x: v.midX - (w / 2), y: v.minY + 60, width: w, height: h)
        } else {
            initialRect = NSRect(x: 200, y: 120, width: w, height: h)
        }

        let panel = FloatingSubtitlePanel(
            contentRect: initialRect,
            styleMask: [.borderless, .resizable, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.title = "Phụ đề trực tiếp"
        panel.identifier = NSUserInterfaceItemIdentifier("meeting-subtitle-hud")
        panel.becomesKeyOnlyIfNeeded = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.isMovableByWindowBackground = true
        panel.isReleasedWhenClosed = false
        panel.minSize = NSSize(width: 380, height: 150)
        panel.contentView = OverlayHostingView(rootView: FloatingSubtitleView(model: self))

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
        ) { [weak panel, weak self] _ in
            MainActor.assumeIsolated {
                guard let frame = panel?.frame else { return }
                var size = frame.size
                if let previous = self?.subtitleFrameBeforeAssistant, let expanded = self?.subtitleFrameWithAssistant {
                    size = MeetingAssistantLayout.preservingResize(previous: previous, expanded: expanded, current: frame).size
                }
                UserDefaults.standard.set(Double(size.width), forKey: "OverlayWindowW")
                UserDefaults.standard.set(Double(size.height), forKey: "OverlayWindowH")
            }
        }

        overlay = panel
        if subtitleAssistantVisible { setSubtitleAssistantExpanded(true) }
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
        frame.origin.y = atTop ? area.maxY - frame.height - 20 : area.minY + 80
        overlay.setFrame(frame, display: true)
        UserDefaults.standard.set(atTop ? "top" : "bottom", forKey: "OverlayPlacement")
    }

    func lockSubtitleHUD(_ locked: Bool) {
        overlay?.isMovableByWindowBackground = !locked
    }

    func resizeSubtitleHUD(side: Bool) {
        guard let overlay, let screen = overlay.screen ?? NSScreen.main else { return }
        let area = screen.visibleFrame
        let width = side ? min(440, area.width - 32) : min(900, area.width * 0.60)
        let height: CGFloat = side ? 300 : 180
        let x = side ? area.maxX - width - 20 : area.midX - width / 2
        overlay.setFrame(NSRect(x: x, y: area.minY + 80, width: width, height: height), display: true)
    }

    func ensureSubtitleComposerSpace() {
        guard let panel = overlay, panel.frame.height < 280 else { return }
        let screen = panel.screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? panel.frame
        var frame = panel.frame
        frame.size.height = min(280, screen.height)
        frame.origin.y = max(screen.minY, min(frame.minY, screen.maxY - frame.height))
        panel.setFrame(frame, display: true)
    }

    func hideOverlay() {
        subtitleQuick.cancel()
        overlay?.orderOut(nil)
        isOverlayVisible = false
        setMascotInSubtitleHUD(false)
        mascotQuickSubtitle.refresh()
    }

    func showMainWindowFromSubtitles() {
        // Dismiss compact first so hiding the full HUD cannot immediately reopen it.
        mascotQuickSubtitle.hideCompact()
        hideOverlay()
        showMainWindow()
    }

    func toggleOverlay() {
        mascotQuickSubtitle.connect(self)
        if mascotQuickSubtitle.isVisible {
            mascotQuickSubtitle.hideCompact()
        } else {
            mascotQuickSubtitle.showCompact()
        }
    }

    func clearCaptions() {
        guard !running, !finishingMeeting else {
            warning = "Dừng cuộc họp để lưu lời đã nhận trước khi xóa màn hình."
            return
        }
        captions.removeAll()
        subtitleQuick.resetSession()
        miniTools.state.translation.resetSession()
        meetingAssistantDraft.resetSession()
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
    nonisolated static func timestamp(_ time: TimeInterval) -> String {
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
        do {
            let snapshot = try SessionStore.load(from: sessionsFileURL)
            sessions = snapshot.sessions.sorted { $0.createdAt > $1.createdAt }
            if selectedSessionID == nil { selectedSessionID = sessions.first?.id }
            recoverMeetingCheckpoint()
            if snapshot.recovered {
                storageError = "Đã khôi phục sổ tay từ bản sao lưu. Bản sao có thể chưa chứa lần lưu gần nhất; file lỗi được giữ lại khi bạn lưu tiếp."
            }
        } catch {
            storageError = "Không đọc được sổ tay. App giữ nguyên file để tránh mất dữ liệu. \(error.localizedDescription)"
        }
    }

    private var checkpointFileURL: URL {
        sessionsFileURL.deletingLastPathComponent().appendingPathComponent("meeting-in-progress.json")
    }

    private func beginMeetingCheckpoints() {
        checkpointTask?.cancel()
        let token = session
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "vi_VN")
        formatter.dateFormat = "HH:mm • dd/MM/yyyy"
        let checkpointTitle = "Cuộc họp \(recordingSourceName) (\(formatter.string(from: started)))"
        checkpointTask = Task { [weak self] in
            var lastSaved: MeetingSession?
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(2)) } catch { return }
                guard let self, self.running, !self.finishingMeeting, self.session == token else { return }
                guard !self.captions.isEmpty else { continue }
                let snapshot = MeetingSession(id: self.recordingSessionID,
                    title: checkpointTitle,
                    createdAt: self.started,
                    durationSeconds: self.captions.reduce(1) { max($0, $1.end) },
                    audioSource: self.recordingSourceName, captions: self.captions.map(\.record))
                guard snapshot != lastSaved else { continue }
                do {
                    try await MeetingCheckpointStore.shared.write(snapshot, to: self.checkpointFileURL)
                    lastSaved = snapshot
                } catch {
                    self.storageError = "Chưa lưu được bản khôi phục cuộc họp: \(error.localizedDescription)"
                }
            }
        }
    }

    private func recoverMeetingCheckpoint() {
        do {
            guard let recovered = try MeetingCheckpointStore.load(from: checkpointFileURL) else { return }
            let merged = MeetingCheckpointStore.merging(recovered, into: sessions)
            try persistSessions(merged)
            selectedSessionID = recovered.id
            warning = "Đã khôi phục cuộc họp trước vào Sổ tay. Nội dung được giữ đến lần lưu tự động gần nhất."
            // Leave removal to the serialized writer so a pending write cannot
            // resurrect a completed checkpoint. Recovery is idempotent on launch.
            Task {
                do { try await MeetingCheckpointStore.shared.remove(sessionID: recovered.id, from: checkpointFileURL) }
                catch { /* Keep the recovery file; notebook is already persisted. */ }
            }
        } catch {
            storageError = "Không đọc được bản khôi phục. File được giữ nguyên: \(error.localizedDescription)"
        }
    }

    private func persistSessions(_ updated: [MeetingSession]) throws {
        try SessionStore.write(updated, to: sessionsFileURL)
        sessions = updated.sorted { $0.createdAt > $1.createdAt }
        storageError = nil
    }

    /// Write first, then publish; failed writes preserve the previous notebook.
    func saveConversationSession(_ session: MeetingSession) throws {
        var updated = sessions
        if let index = updated.firstIndex(where: { $0.id == session.id }) { updated[index] = session }
        else { updated.insert(session, at: 0) }
        try persistSessions(updated)
        selectedSessionID = session.id
    }

    func saveCurrentSession(customTitle: String? = nil, notes: String = "") {
        guard !captions.isEmpty else { return }
        let now = Date()
        let elapsed = max(1, now.timeIntervalSince(started))
        let records = captions.map(\.record)

        let dateFormatter = DateFormatter()
        dateFormatter.locale = Locale(identifier: "vi_VN")
        dateFormatter.dateFormat = "HH:mm • dd/MM/yyyy"
        let dateString = dateFormatter.string(from: started)

        let appName = recordingSourceName.isEmpty ? currentSourceName() : recordingSourceName
        let defaultTitle = customTitle ?? "Cuộc họp \(appName) (\(dateString))"

        let existing = sessions.first { $0.id == recordingSessionID }
        let newSession = MeetingSession(
            id: recordingSessionID,
            title: customTitle ?? existing?.title ?? defaultTitle,
            createdAt: started,
            durationSeconds: elapsed,
            audioSource: appName,
            notes: notes.isEmpty ? (existing?.notes ?? "") : notes,
            captions: records
        )

        var updated = sessions
        if let idx = updated.firstIndex(where: { $0.id == newSession.id }) {
            updated[idx] = newSession
        } else {
            updated.insert(newSession, at: 0)
        }
        do {
            try persistSessions(updated)
            selectedSessionID = newSession.id
            status = "Đã lưu cuộc họp vào Sổ tay."
        } catch { storageError = "Chưa lưu được cuộc họp: \(error.localizedDescription)"; status = "Chưa lưu được cuộc họp." }
    }

    func updateSessionTitle(id: UUID, title: String) {
        guard let index = sessions.firstIndex(where: { $0.id == id }) else { return }
        var updated = sessions; updated[index].title = title
        do { try persistSessions(updated) }
        catch { storageError = "Chưa đổi được tên: \(error.localizedDescription)" }
    }

    func updateSessionNotes(id: UUID, notes: String) {
        guard let index = sessions.firstIndex(where: { $0.id == id }) else { return }
        var updated = sessions; updated[index].notes = notes
        do { try persistSessions(updated) }
        catch { storageError = "Chưa lưu được ghi chú: \(error.localizedDescription)" }
    }

    func deleteConversationSession(id: UUID) throws {
        try persistSessions(sessions.filter { !($0.id == id && $0.audioSource == "Luyện nói với AI") })
        if selectedSessionID == id { selectedSessionID = sessions.first?.id }
    }

    func deleteSession(id: UUID) {
        do {
            let deleted = sessions.first { $0.id == id }
            try persistSessions(sessions.filter { $0.id != id })
            lastDeletedNotebookSession = deleted
            lastDeletedNotebookSessions = []
            if selectedSessionID == id { selectedSessionID = sessions.first?.id }
        } catch { storageError = "Chưa xóa được bản ghi: \(error.localizedDescription)" }
    }

    func undoNotebookDeletion() {
        if !lastDeletedNotebookSessions.isEmpty {
            let existingIDs = Set(sessions.map(\.id))
            let restored = lastDeletedNotebookSessions.filter { !existingIDs.contains($0.id) }
            do {
                try persistSessions((restored + sessions).sorted { $0.createdAt > $1.createdAt })
                selectedSessionID = restored.first?.id ?? selectedSessionID
                lastDeletedNotebookSessions = []
            } catch { storageError = "Chưa khôi phục được bản ghi: " + error.localizedDescription }
            return
        }
        guard let session = lastDeletedNotebookSession, !sessions.contains(where: { $0.id == session.id }) else { return }
        do {
            try persistSessions(([session] + sessions).sorted { $0.createdAt > $1.createdAt })
            selectedSessionID = session.id
            lastDeletedNotebookSession = nil
        } catch { storageError = "Chưa khôi phục được bản ghi: " + error.localizedDescription }
    }

    func deleteNotebookSessions(ids: Set<UUID>) {
        guard !running else {
            storageError = "Dừng và lưu cuộc họp trước khi xóa tất cả bản ghi."
            return
        }
        let deleted = sessions.filter { ids.contains($0.id) }
        guard !deleted.isEmpty else { return }
        do {
            try persistSessions(sessions.filter { !ids.contains($0.id) })
            lastDeletedNotebookSessions = deleted
            lastDeletedNotebookSession = nil
            if let selected = selectedSessionID, ids.contains(selected) { selectedSessionID = sessions.first?.id }
        } catch { storageError = "Chưa xóa được các bản ghi: " + error.localizedDescription }
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
            title: "Cuộc họp Trans Tools (\(DateFormatter.localizedString(from: Date(), dateStyle: .short, timeStyle: .short)))",
            createdAt: started,
            durationSeconds: Date().timeIntervalSince(started),
            audioSource: currentSourceName(),
            captions: captions.map { CaptionRecord(id: $0.id, start: $0.start, end: $0.end, original: $0.original, vietnamese: $0.vietnamese) }
        )
        exportSessionToDocx(tempSession)
    }

    // MARK: - Floating Mascot Window Management
    @Published var isChipChipLearning = false
    func beginChipChipLearning() {
        isChipChipLearning = true
        showFloatingMascot()
        stopDockWalking()
    }
    func endChipChipLearning(hideMascot: Bool) {
        isChipChipLearning = false
        if hideMascot { hideFloatingMascot() }
        else if isDockWalkEnabled { startDockWalking() }
    }

    @Published var isFloatingMascotVisible: Bool = false
    private let dockGarden = DockGardenController()
    var mascotWindow: NSWindow?

    // Chip Chip Speech Bubble Management
    var mascotBubbleWindow: NSWindow?
    var bubbleDismissTask: Task<Void, Never>?
    @Published var bubbleOnRight = true
    @Published var bubbleArrowY: CGFloat = 0.5
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
    @Published private(set) var isDockActuallyWalking = false
    var dockWalkDistance: CGFloat = 0
    var dockWalkLastTick: Date?
    var dockWalkTimer: Timer?
    private var dockWalkTimerInterval: TimeInterval = 0
    var dockWalkDirection: CGFloat = 1.0 // 1: đi sang phải, -1: đi sang trái
    var dockWalkPauseUntil: Date? = nil
    var dockWalkCurrentX: CGFloat? = nil

    func convenientMascotRect() -> NSRect {
        let mascotWidth: CGFloat = 190
        let mascotHeight: CGFloat = 186

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
        if mascotInSubtitleHUD {
            isFloatingMascotVisible = true
            UserDefaults.standard.set(true, forKey: "FloatingMascotEnabled")
            return
        }
        mascotQuickSubtitle.connect(self)
        let convenient = convenientMascotRect()

        if let mascotWindow {
            if mascotWindow.contentView == nil {
                mascotWindow.contentView = MascotHostingView(rootView: FloatingMascotView(model: self))
            }
            // Check if existing window is visible on any active screen
            let isVisibleOnScreen = NSScreen.screens.contains { screen in
                let intersection = screen.visibleFrame.intersection(mascotWindow.frame)
                return intersection.width >= 40 && intersection.height >= 40
            }
            if !isVisibleOnScreen || mascotWindow.frame.size.height < 180 || mascotWindow.frame.size.width < 180 {
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
        // orderOut hides the panel but retains SwiftUI's periodic clock.
        // Release the view tree and recreate it when the mascot returns.
        mascotWindow?.contentView = nil
        // Bounds are relative to FloatingMascotView's canvas. Discard them
        // with that view tree so a later presentation cannot anchor a bubble
        // using coordinates from the expanded orbit or an older layout.
        mascotHeadBounds = nil
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
        bubbleMeaning = (mode == "grammar") ? "\(MascotIdentity.name) đang sửa ngữ pháp..." : (mode == "viToEn" ? "Đang dịch VI → EN theo \(domainSpecialty.title)..." : "\(MascotIdentity.name) đang dịch...")
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

        scheduleDockWalk(interval: 1)
    }

    private func scheduleDockWalk(interval: TimeInterval) {
        guard dockWalkTimer == nil || dockWalkTimerInterval != interval else { return }
        dockWalkTimer?.invalidate()
        dockWalkTimerInterval = interval
        let timer = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.stepDockWalk() }
        }
        timer.tolerance = interval * 0.15
        RunLoop.main.add(timer, forMode: .common)
        dockWalkTimer = timer
    }

    func stopDockWalking() {
        if isDockActuallyWalking { isDockActuallyWalking = false }
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
        let delta = min(0.10, max(0.001, now.timeIntervalSince(dockWalkLastTick ?? now)))
        dockWalkLastTick = now

        dockGarden.hide()
        // Walk and scenery pause as soon as the user resumes interaction.
        guard !running, !busy, !isMascotHovered, !isBubbleHovered, !isBubbleVisible,
              !ConversationController.shared.active,
              MascotIdlePolicy.systemIdleSeconds >= MascotIdlePolicy.idleThreshold,
              NSEvent.pressedMouseButtons == 0, let window = mascotWindow,
              window.isVisible, window.occlusionState.contains(.visible),
              !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else {
            if isDockActuallyWalking { isDockActuallyWalking = false }
            scheduleDockWalk(interval: 1)
            return
        }
        let conserving = ProcessInfo.processInfo.isLowPowerModeEnabled ||
            ProcessInfo.processInfo.thermalState == .serious || ProcessInfo.processInfo.thermalState == .critical
        scheduleDockWalk(interval: conserving ? 1.0 / 12 : 1.0 / 24)

        // Nếu đang tạm dừng nghỉ chân quay người ở 2 mép màn hình
        if let pauseUntil = dockWalkPauseUntil {
            if now < pauseUntil {
                if isDockActuallyWalking { isDockActuallyWalking = false }
                scheduleDockWalk(interval: min(1, max(0.1, pauseUntil.timeIntervalSince(now))))
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

        if !isDockActuallyWalking { isDockActuallyWalking = true }
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
        if window.frame.origin != origin { window.setFrameOrigin(origin) }

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

    var speechBubbleHeight: CGFloat {
        if isBubbleLoading { return 100 }
        func textHeight(_ text: String, size: CGFloat, weight: NSFont.Weight) -> CGFloat {
            ceil((text as NSString).boundingRect(
                with: NSSize(width: 320, height: CGFloat.greatestFiniteMagnitude),
                options: [.usesLineFragmentOrigin, .usesFontLeading],
                attributes: [.font: NSFont.systemFont(ofSize: size, weight: weight)]
            ).height)
        }
        var content = textHeight(bubbleMeaning, size: 12.5, weight: .bold)
        if bubbleMode == "translate" {
            content += 8 + textHeight(bubbleWord, size: 11, weight: .regular)
        } else if bubbleWord != bubbleMeaning {
            content += 5 + textHeight("Gốc: \"\(bubbleWord)\"", size: 10, weight: .regular)
        }
        return min(260, max(115, content + 88 + (bubblePhonetic.isEmpty ? 0 : 14)))
    }

    private func speechBubbleRect() -> NSRect? {
        guard let mascotWin = mascotWindow else { return nil }
        let visible = (mascotWin.screen ?? NSScreen.main ?? NSScreen()).visibleFrame
        let width = min(360, visible.width - 20)
        let height = min(speechBubbleHeight, visible.height - 20)
        let anchor = MascotMiniToolPlacement.visualAnchor(
            windowFrame: mascotWin.frame, localBounds: mascotHeadBounds)
        let bodyPoint = MascotMiniToolPlacement.bodyAnchor(
            windowFrame: mascotWin.frame, localBounds: mascotHeadBounds)
        let placement = MascotSpeechCardPlacement.resolve(
            anchor: anchor, target: bodyPoint, screen: visible,
            size: CGSize(width: width, height: height), gap: 8, margin: 10)
        bubbleOnRight = placement.onRight
        bubbleArrowY = placement.arrowY
        return placement.frame
    }

    func updateBubblePosition() {
        guard isBubbleVisible, let bubbleWin = mascotBubbleWindow, let rect = speechBubbleRect() else { return }
        bubbleWin.setFrame(rect, display: true)
    }

    func presentBubbleWindow() {
        guard let bubbleRect = speechBubbleRect() else { return }

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
    let miniTools = MascotMiniToolsController()
    var mascotHeadBounds: CGRect?
    func updateMascotHeadBounds(_ bounds: CGRect) {
        guard bounds.width > 0, bounds.height > 0 else { return }
        if let old = mascotHeadBounds,
           abs(old.minX - bounds.minX) < 3, abs(old.minY - bounds.minY) < 3,
           abs(old.width - bounds.width) < 3, abs(old.height - bounds.height) < 3 { return }
        mascotHeadBounds = bounds
        // Selection translation may have shown its card before SwiftUI's
        // geometry preference arrived. Re-anchor it as soon as fresh bounds
        // are available, especially after the mascot window is recreated.
        updateBubblePosition()
        mascotQuickSubtitle.refresh()
        miniTools.refreshPlacement()
    }
    let mascotQuickSubtitle = MascotQuickSubtitleController()
    let subtitleQuick = SubtitleQuickStore()
    func saveAssistantQuickNote(_ text: String) {
        guard !captions.isEmpty else { subtitleQuick.status = "Bắt đầu cuộc họp để lưu câu vào ghi chú."; return }
        let existing = sessions.first { $0.id == recordingSessionID }?.notes ?? ""
        saveCurrentSession(notes: existing + (existing.isEmpty ? "" : "\n\n") + "Trợ lý\n" + text)
        subtitleQuick.status = storageError == nil ? "Đã lưu vào ghi chú." : "Chưa lưu được ghi chú."
    }
    weak var mainWindow: NSWindow?
    private let windowDelegate = MainWindowDelegate()
    private var dashboardRequested = false

    func attachMainWindow(_ window: NSWindow) {
        // SwiftUI calls this again as live captions update. Register once so
        // updates cannot bring back a dashboard the user has closed.
        guard mainWindow !== window else { return }
        self.mainWindow = window
        if !UserDefaults.standard.bool(forKey: "DashboardCompactSizeV6"), let screen = window.screen ?? NSScreen.main {
            let area = screen.visibleFrame.insetBy(dx: 16, dy: 16)
            let width = min(area.width, 1160)
            let height = min(area.height, 740)
            window.setFrame(NSRect(x: area.midX - width / 2, y: area.midY - height / 2, width: width, height: height), display: true)
            UserDefaults.standard.set(true, forKey: "DashboardCompactSizeV6")
        }
        window.isReleasedWhenClosed = false
        window.delegate = windowDelegate
        if dashboardRequested {
            window.makeKeyAndOrderFront(nil)
        } else {
            window.orderOut(nil)
            // WindowGroup may order its initial window after the accessor runs.
            DispatchQueue.main.async { [weak self, weak window] in
                guard self?.dashboardRequested == false else { return }
                window?.orderOut(nil)
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { [weak self, weak window] in
                guard let self, !self.dashboardRequested else { return }
                window?.orderOut(nil)
                NSApp.setActivationPolicy(.accessory)
            }
        }
    }

    func prepareMascotFirstLaunch() {
        guard !dashboardRequested else { return }
        NSApp.setActivationPolicy(.accessory)
        showFloatingMascot()
        mainWindow?.orderOut(nil)
        DispatchQueue.main.async { [weak self] in
            guard let self, !self.dashboardRequested else { return }
            self.mainWindow?.orderOut(nil)
            NSApp.setActivationPolicy(.accessory)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { [weak self] in
            guard let self, !self.dashboardRequested else { return }
            self.mainWindow?.orderOut(nil)
            NSApp.setActivationPolicy(.accessory)
        }
    }

    func showMainWindow(preservingMiniReader: Bool = false) {
        mascotQuickSubtitle.hideCompact()
        hideOverlay()
        ConversationMiniChat.shared.hide()
        miniTools.hide(stopMiniReader: !preservingMiniReader)
        dashboardRequested = true
        NSApp.setActivationPolicy(.regular)
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

@MainActor
final class MainWindowDelegate: NSObject, NSWindowDelegate {
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        sender.orderOut(nil)
        NSApp.setActivationPolicy(.accessory)
        if let model = MeetingModel.shared, ConversationController.shared.active {
            model.miniTools.show(.conversation, model: model)
        }
        return false
    }
    func windowDidBecomeKey(_ notification: Notification) {
        ConversationMiniChat.shared.hide()
    }
}

struct WindowAccessor: NSViewRepresentable {
    let callback: (NSWindow) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = MainWindowAttachView()
        view.onWindowChange = callback
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        if let window = nsView.window {
            callback(window)
        }
    }
}

enum AppReopenPolicy {
    static func shouldOpenDashboard(now: Date, suppressUntil: Date?) -> Bool {
        guard let suppressUntil else { return true }
        return now >= suppressUntil
    }
}

private final class MainWindowAttachView: NSView {
    var onWindowChange: ((NSWindow) -> Void)?
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if let window { onWindowChange?(window) }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    var model: MeetingModel? {
        didSet {
            if let model {
                MenuBarManager.shared.setup(with: model)
                initializeStartupPresentationIfReady()
            }
        }
    }
    private var didFinishLaunching = false
    private var didInitializeStartupPresentation = false
    private var suppressReopenUntil: Date?

    func applicationWillFinishLaunching(_ notification: Notification) {
        // Start as a menu-bar/mascot utility. The dashboard switches to regular
        // activation only when the user explicitly opens it.
        NSApp.setActivationPolicy(.accessory)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        didFinishLaunching = true
        // Launch Services can send an immediate reopen event as part of app
        // launch. Let the mascot-first presentation settle before treating a
        // later Dock click as an explicit request for the dashboard.
        suppressReopenUntil = Date().addingTimeInterval(1.5)
        initializeStartupPresentationIfReady()
    }

    private func initializeStartupPresentationIfReady() {
        guard didFinishLaunching, !didInitializeStartupPresentation, let model else { return }
        didInitializeStartupPresentation = true
        DispatchQueue.main.async { [weak model] in
            guard let model else { return }
            model.checkAllPermissions()
            model.prepareMascotFirstLaunch()
        }
    }

    private var terminationPending = false

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let model, model.running else { return .terminateNow }
        guard !terminationPending else { return .terminateLater }
        terminationPending = true
        Task {
            let saved = await model.prepareForTermination()
            terminationPending = false
            if !saved { model.showMainWindow() }
            sender.reply(toApplicationShouldTerminate: saved)
        }
        return .terminateLater
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return false // Keep running in background with Menubar Tray Icon
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if AppReopenPolicy.shouldOpenDashboard(now: Date(), suppressUntil: suppressReopenUntil) {
            model?.showMainWindow()
        }
        return true
    }
}

// MARK: - Menu Bar Status Item (Tray Icon) Manager

@MainActor
final class MenuBarManager: NSObject, NSMenuDelegate {
    static let shared = MenuBarManager()
    private var statusItem: NSStatusItem?
    private weak var model: MeetingModel?
    var meetingRunning: Bool { model?.running == true }
    var voiceScriptAI: (provider: AIProvider, model: String, key: String)? { model?.configuredAI }
    private var cancellables = Set<AnyCancellable>()

    func setup(with model: MeetingModel) {
        self.model = model

        if statusItem == nil {
            let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
            if let button = item.button {
                button.imagePosition = .imageOnly
                button.toolTip = "Trans Tools - Phiên dịch cuộc họp & Trợ lý \(MascotIdentity.name)"
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
            if let liveImg = NSImage(systemSymbolName: "captions.bubble.fill", accessibilityDescription: "Trans Tools (Đang dịch)")?.withSymbolConfiguration(config) {
                liveImg.isTemplate = false
                button.image = liveImg
            } else {
                let img = NSImage(systemSymbolName: "captions.bubble.fill", accessibilityDescription: "Trans Tools (Đang dịch)")
                img?.isTemplate = true
                button.image = img
            }
            button.toolTip = "Trans Tools: Đang nghe & phiên dịch cuộc họp (LIVE) 🟢"
        } else {
            let img = NSImage(systemSymbolName: "captions.bubble", accessibilityDescription: "Trans Tools")
            img?.isTemplate = true
            button.image = img
            button.toolTip = "Trans Tools - Phiên dịch cuộc họp & Trợ lý \(MascotIdentity.name)"
        }
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        guard let model = self.model else { return }

        // 1. Header: Live Status
        let statusTitle = model.running ? "Trans Tools • Đang dịch trực tiếp" : "Trans Tools • Sẵn sàng"
        let headerItem = NSMenuItem(title: statusTitle, action: nil, keyEquivalent: "")
        if let icon = NSApp.applicationIconImage?.copy() as? NSImage {
            icon.size = NSSize(width: 20, height: 20)
            icon.isTemplate = false
            headerItem.image = icon
        }
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

        // 3b. Screen OCR Translate
        let ocrItem = NSMenuItem(title: "Chụp & Dịch màn hình (OCR) · Option + S", action: #selector(triggerOCRAction), keyEquivalent: "")
        ocrItem.target = self
        if let img = NSImage(systemSymbolName: "text.viewfinder", accessibilityDescription: nil) {
            ocrItem.image = img
        }
        menu.addItem(ocrItem)

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
        let mimoItem = NSMenuItem(title: "Trợ lý \(MascotIdentity.name)", action: #selector(toggleMimoAction), keyEquivalent: "")
        mimoItem.target = self
        mimoItem.state = isMimoOn ? .on : .off
        if let img = NSImage(systemSymbolName: "sparkles.tv", accessibilityDescription: nil) {
            mimoItem.image = img
        }
        menu.addItem(mimoItem)

        if isMimoOn {
            let snapItem = NSMenuItem(title: "   Đưa \(MascotIdentity.name) về góc màn hình", action: #selector(snapMimoAction), keyEquivalent: "")
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

        // 7b. Giọng đọc & Phát âm (TTS)
        let speechItem = NSMenuItem(title: "Giọng đọc & Phát âm (TTS)...", action: #selector(openSpeechSettingsAction), keyEquivalent: "")
        speechItem.target = self
        if let img = NSImage(systemSymbolName: "waveform", accessibilityDescription: nil) {
            speechItem.image = img
        }
        menu.addItem(speechItem)

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

        // 10. Câu dịch gần đây (Quick HUD)
        if !model.captions.isEmpty {
            let recentHeader = NSMenuItem(title: "Hội thoại gần đây:", action: nil, keyEquivalent: "")
            recentHeader.isEnabled = false
            menu.addItem(recentHeader)

            let recentCaps = Array(model.captions.suffix(3))
            for cap in recentCaps {
                let origText = cap.original.trimmingCharacters(in: .whitespacesAndNewlines)
                let transText = cap.vietnamese.trimmingCharacters(in: .whitespacesAndNewlines)
                let fullText = transText.isEmpty ? origText : "\(origText) → \(transText)"
                let truncated = fullText.count > 46 ? String(fullText.prefix(43)) + "..." : fullText
                let capItem = NSMenuItem(title: "   • \(truncated)", action: #selector(copyCaptionTextAction(_:)), keyEquivalent: "")
                capItem.representedObject = fullText
                capItem.target = self
                menu.addItem(capItem)
            }
            menu.addItem(NSMenuItem.separator())
        }

        // 11. Thoát ứng dụng
        let quitItem = NSMenuItem(title: "Thoát Trans Tools", action: #selector(quitAppAction), keyEquivalent: "q")
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
        model.selectedDashboardTab = 4
        model.showMainWindow()
    }

    @objc private func openSpeechSettingsAction() {
        guard let model else { return }
        model.selectedDashboardTab = 4
        model.selectedSettingsSection = 3
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

    @objc private func triggerOCRAction() {
        ScreenOCRService.shared.triggerScreenOCRTranslation()
    }

    @objc private func copyCaptionTextAction(_ sender: NSMenuItem) {
        if let text = sender.representedObject as? String {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
        }
    }

    @objc private func quitAppAction() {
        NSApp.terminate(nil)
    }
}

// MARK: - Native Draggable Subtitle Window Hosting View
// (Moved to FloatingSubtitleView.swift)

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
                await AppleNativeTranslator.host(session, from: source, to: target)
            }
            .translationTask(reverseConfig) { session in
                await AppleNativeTranslator.host(session, from: target, to: source)
            }
            .translationTask(viToEnConfig) { session in
                await AppleNativeTranslator.host(session, from: .vietnamese, to: .english)
            }
            .translationTask(enToViConfig) { session in
                await AppleNativeTranslator.host(session, from: .english, to: .vietnamese)
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
    func enableAppleTranslationSession(when enabled: Bool = true, source: AppLanguage = .english, target: AppLanguage = .vietnamese) -> some View {
        #if canImport(Translation)
        if enabled, #available(macOS 15.0, *) {
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
// (Moved to FloatingSubtitleView.swift)

// MARK: - Application Mascot Icon

struct AppLogoView: View {
    let size: CGFloat

    var body: some View {
        if let nsImage = MascotResourceImages.images["AppIcon"] {
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
                        .strokeBorder(
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
                .overlay(Circle().strokeBorder(Color.cyan.opacity(0.35), lineWidth: 0.8))

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
            if let legImg = MascotResourceImages.images["MascotLegLeft"] {
                Image(nsImage: legImg)
                    .resizable()
                    .scaledToFit()
                    .frame(width: legW, height: legH)
                    .rotationEffect(.degrees(leftAngle), anchor: UnitPoint(x: 0.65, y: 0.15))
                    .offset(x: leftLegOffsetX, y: legOffsetY - leftLift)
            }

            // 2. Right Leg
            if let legImg = MascotResourceImages.images["MascotLegRight"] {
                Image(nsImage: legImg)
                    .resizable()
                    .scaledToFit()
                    .frame(width: legW, height: legH)
                    .rotationEffect(.degrees(rightAngle), anchor: UnitPoint(x: 0.35, y: 0.15))
                    .offset(x: rightLegOffsetX, y: legOffsetY - rightLift)
            }

            // 3. Body (Torso, head, headphones)
            if let bodyImg = MascotResourceImages.images["MascotBody"] {
                Image(nsImage: bodyImg)
                    .resizable()
                    .scaledToFit()
                    .frame(width: w, height: h)
            } else if let fullImg = MascotResourceImages.images["Mascot3D"] {
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
    private var activeStyle: String {
        "sprite"
    }

    private var activeHovered: Bool {
        isHovered ?? internalHovered
    }

    var body: some View {
        ZStack {
            if activeStyle == "sprite", let image = MascotActivityImages.image(activity: activity, working: isWorking, sleeping: isSleeping, walking: isWalking, time: time, reduceMotion: reduceMascotMotion) {
                Image(nsImage: image).resizable().scaledToFit()
                    // Constrain both dimensions: a height-only resizable image
                    // can report the full launcher width despite drawing a
                    // narrow avatar, leaving speech pointers far from its edge.
                    .frame(width: size * image.size.width / max(image.size.height, 1), height: size)
            } else if let seedling = MascotResourceImages.images["MascotSeedling"] {
                Image(nsImage: seedling)
                    .interpolation(.high)
                    .resizable()
                    .scaledToFit()
                    .frame(width: size * seedling.size.width / max(seedling.size.height, 1), height: size)
            } else if isSleeping {
                if let nsImage = MascotResourceImages.images["MascotSleeping"] ?? MascotResourceImages.images["Mascot3D"] {
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
                if let nsImage = MascotResourceImages.images["MascotWriting"] ?? MascotResourceImages.images["Mascot3D"] {
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
                            .strokeBorder(Color(red: 0.92, green: 0.78, blue: 0.62).opacity(0.6), lineWidth: 0.8)
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

/// Custom cartoon thought cloud shape with soft rounded lobes
struct ThoughtCloudShape: InsettableShape {
    var insetAmount: CGFloat = 0

    func inset(by amount: CGFloat) -> some InsettableShape { insetted(by: amount) }

    func insetted(by amount: CGFloat) -> ThoughtCloudShape {
        var shape = self
        shape.insetAmount += amount
        return shape
    }

    func path(in inputRect: CGRect) -> Path {
        let rect = inputRect.insetBy(dx: insetAmount, dy: insetAmount)
        var path = Path()
        let cx = rect.midX
        let cy = rect.midY
        let rx = max(12, rect.width / 2 - 5)
        let ry = max(10, rect.height / 2 - 4)

        let lobeCount = 8
        let bumpFactors: [CGFloat] = [6.5, 5.0, 6.0, 7.5, 6.0, 4.5, 5.5, 6.5]

        var points: [CGPoint] = []
        var controls: [CGPoint] = []

        for i in 0..<lobeCount {
            let a = -CGFloat.pi / 2.0 + CGFloat(i) * 2.0 * CGFloat.pi / CGFloat(lobeCount)
            let x = cx + rx * cos(a)
            let y = cy + ry * sin(a)
            points.append(CGPoint(x: x, y: y))
        }

        for i in 0..<lobeCount {
            let midA = -CGFloat.pi / 2.0 + (CGFloat(i) + 0.5) * 2.0 * CGFloat.pi / CGFloat(lobeCount)
            let bump = bumpFactors[i]
            let ctrlX = cx + (rx + bump) * cos(midA)
            let ctrlY = cy + (ry + bump) * sin(midA)
            controls.append(CGPoint(x: ctrlX, y: ctrlY))
        }

        path.move(to: points[0])
        for i in 0..<lobeCount {
            let nextI = (i + 1) % lobeCount
            path.addQuadCurve(to: points[nextI], control: controls[i])
        }
        path.closeSubpath()
        return path
    }
}

private struct ChipChipThoughtItem {
    let main: String
    let sub: String?
}

struct MascotThinkingCloudEffect: View {
    let time: Double

    private let thoughts: [ChipChipThoughtItem] = [
        // 🇻🇳 Tiếng Việt
        ChipChipThoughtItem(main: "Hôm nay học từ\nmới chưa nè?", sub: nil),
        ChipChipThoughtItem(main: "Trà sữa hay\ncà phê ta?", sub: nil),
        ChipChipThoughtItem(main: "Giờ làm gì\nta nhỉ?", sub: nil),
        ChipChipThoughtItem(main: "Buồn ngủ ghê á…\nngủ xíu nha", sub: nil),
        ChipChipThoughtItem(main: "Cố lên nha!\nBạn làm được mà", sub: nil),
        ChipChipThoughtItem(main: "Ăn lẩu hay\ngà rán ta?", sub: nil),
        ChipChipThoughtItem(main: "\(MascotIdentity.name) đang\nsuy nghĩ…", sub: nil),

        // 🇬🇧 Tiếng Anh
        ChipChipThoughtItem(main: "What should I\ndo now?", sub: "Giờ làm gì ta?"),
        ChipChipThoughtItem(main: "Boba or coffee\ntoday?", sub: "Trà sữa hay cà phê?"),
        ChipChipThoughtItem(main: "Time to learn\nnew words!", sub: "Học từ mới thôi!"),
        ChipChipThoughtItem(main: "Keep going!\nYou got this!", sub: "Cố lên bạn ơi!"),
        ChipChipThoughtItem(main: "So sleepy…\nneed a nap", sub: "Buồn ngủ quá à"),
        ChipChipThoughtItem(main: "Nice weather\ntoday!", sub: "Trời hôm nay đẹp ghê!"),

        // 🇯🇵 Tiếng Nhật
        ChipChipThoughtItem(main: "何しようかな？", sub: "Giờ làm gì ta?"),
        ChipChipThoughtItem(main: "がんばってね！", sub: "Cố lên nhé bạn ơi!"),
        ChipChipThoughtItem(main: "タピオカ飲む？", sub: "Uống trà sữa hông?"),
        ChipChipThoughtItem(main: "単語覚えた？", sub: "Nhớ từ vựng chưa nè?"),
        ChipChipThoughtItem(main: "お腹すいたな〜", sub: "Đói bụng rồi nè~"),
        ChipChipThoughtItem(main: "今日もいい天気！", sub: "Hôm nay trời đẹp ghê!"),

        // 🇨🇳 Tiếng Trung
        ChipChipThoughtItem(main: "今天做什么呢？", sub: "Hôm nay làm gì nhỉ?"),
        ChipChipThoughtItem(main: "加油哦！你可以的", sub: "Cố lên! Bạn làm được mà"),
        ChipChipThoughtItem(main: "奶茶还是咖啡？", sub: "Trà sữa hay cà phê?"),
        ChipChipThoughtItem(main: "今天背单词了没？", sub: "Thuộc từ mới chưa nè?"),
        ChipChipThoughtItem(main: "好困呀…想睡觉", sub: "Buồn ngủ quá đi..."),
        ChipChipThoughtItem(main: "想吃好吃的啦！", sub: "Thèm ăn đồ ngon quá!")
    ]

    private var currentThoughtIndex: Int {
        // Luân phiên câu suy nghĩ mỗi 5.0 giây mượt mà
        let cycle = Int(time / 5.0)
        return abs(cycle) % thoughts.count
    }

    var body: some View {
        let thought = thoughts[currentThoughtIndex]
        let floatY = CGFloat(sin(time * 2.2) * 2.5)
        let popPhase = fmod(time, 5.0)
        let alpha = popPhase < 0.4 ? (popPhase / 0.4) : (popPhase > 4.5 ? (5.0 - popPhase) / 0.5 : 1.0)
        let scale = popPhase < 0.4 ? (0.75 + (popPhase / 0.4) * 0.25) : 1.0

        ZStack(alignment: .bottom) {
            // Little bubble 1 (gần đỉnh đầu Chip Chip)
            Circle()
                .fill(Color(nsColor: .windowBackgroundColor).opacity(0.96))
                .overlay(Circle().strokeBorder(TransToolsTheme.accent.opacity(0.25), lineWidth: 0.8))
                .frame(width: 4, height: 4)
                .shadow(color: Color.black.opacity(0.10), radius: 1.5, y: 1)
                .offset(x: 2, y: -65 + floatY * 0.2)

            // Little bubble 2 (giữa)
            Circle()
                .fill(Color(nsColor: .windowBackgroundColor).opacity(0.96))
                .overlay(Circle().strokeBorder(TransToolsTheme.accent.opacity(0.25), lineWidth: 0.8))
                .frame(width: 6.5, height: 6.5)
                .shadow(color: Color.black.opacity(0.10), radius: 1.5, y: 1)
                .offset(x: 3.5, y: -75 + floatY * 0.5)

            // Little bubble 3 (sát đáy đám mây)
            Circle()
                .fill(Color(nsColor: .windowBackgroundColor).opacity(0.96))
                .overlay(Circle().strokeBorder(TransToolsTheme.accent.opacity(0.25), lineWidth: 0.8))
                .frame(width: 9, height: 9)
                .shadow(color: Color.black.opacity(0.10), radius: 1.5, y: 1)
                .offset(x: 4.5, y: -86 + floatY * 0.8)

            // Đám mây suy nghĩ chính (Lobed Cartoon Cloud)
            VStack(spacing: 4) {
                Text(thought.main.replacingOccurrences(of: "\n", with: " "))
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .foregroundStyle(Color.primary)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                        .lineSpacing(1.2)
                        .frame(maxWidth: .infinity)
                if let sub = thought.sub {
                    Text("(\(sub))")
                        .font(.system(size: 9, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 11)
            .frame(width: thought.sub == nil ? 140 : 172)
            .background(
                ThoughtCloudShape()
                    .fill(Color(nsColor: .windowBackgroundColor).opacity(0.97))
                    .shadow(color: Color.black.opacity(0.18), radius: 6, y: 2.5)
            )
            .overlay(
                ThoughtCloudShape()
                    .strokeBorder(TransToolsTheme.accent.opacity(0.30), lineWidth: 1.2)
            )
            .scaleEffect(scale)
            .opacity(alpha)
            .offset(x: 2, y: -104 + floatY)
        }
        .allowsHitTesting(false)
    }
}

/// A soft, irregular meadow outline, shared by the turf and its shadow.
struct MascotMeadowShape: Shape {
    func path(in rect: CGRect) -> Path {
        func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: rect.minX + rect.width * x, y: rect.minY + rect.height * y)
        }
        var path = Path()
        path.move(to: point(0.02, 0.52))
        path.addCurve(to: point(0.22, 0.16), control1: point(-0.02, 0.25), control2: point(0.13, 0.04))
        path.addCurve(to: point(0.48, 0.10), control1: point(0.32, 0.30), control2: point(0.36, -0.05))
        path.addCurve(to: point(0.75, 0.18), control1: point(0.59, 0.27), control2: point(0.65, 0.02))
        path.addCurve(to: point(0.98, 0.48), control1: point(0.85, 0.35), control2: point(1.02, 0.18))
        path.addCurve(to: point(0.79, 0.86), control1: point(1.04, 0.79), control2: point(0.88, 1.02))
        path.addCurve(to: point(0.53, 0.91), control1: point(0.69, 0.68), control2: point(0.65, 1.04))
        path.addCurve(to: point(0.25, 0.87), control1: point(0.40, 0.77), control2: point(0.37, 1.05))
        path.addCurve(to: point(0.02, 0.52), control1: point(0.12, 0.69), control2: point(-0.02, 0.86))
        path.closeSubpath()
        return path
    }
}

/// Small garden island beneath the PNG poses.
struct MascotDefaultGround: View {
    private func flower(_ color: Color, height: CGFloat) -> some View {
        ZStack {
            Capsule().fill(Color(red: 0.37, green: 0.49, blue: 0.18))
                .frame(width: 1.3, height: height).offset(y: height / 2)
            Ellipse().fill(Color(red: 0.57, green: 0.68, blue: 0.28))
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
            MascotMeadowShape()
                .fill(Color.black.opacity(0.10))
                .frame(width: 72, height: 10)
                .blur(radius: 3)
                .offset(y: 4)
            MascotMeadowShape()
                .fill(LinearGradient(
                    colors: [Color(red: 0.65, green: 0.75, blue: 0.36),
                             Color(red: 0.35, green: 0.48, blue: 0.19)],
                    startPoint: .top, endPoint: .bottom))
                .overlay(MascotMeadowShape().stroke(Color(red: 0.79, green: 0.86, blue: 0.55).opacity(0.65), lineWidth: 0.6))
                .frame(width: 84, height: 16)
            // Keep plants at the edges so the mascot's feet remain visible.
            ForEach(0..<2) { side in
                let x: CGFloat = side == 0 ? -24 : 25
                ZStack {
                    ForEach(0..<3) { blade in
                        Capsule().fill(Color(red: 0.45, green: 0.59, blue: 0.23).opacity(0.90))
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
                        .strokeBorder(Color.green.opacity(0.25), lineWidth: 0.6)
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
                            .strokeBorder(Color.cyan.opacity(0.40), lineWidth: 0.8)
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
                                    .strokeBorder(Color.black.opacity(0.12), lineWidth: 0.5)
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
                                .strokeBorder(Color(red: 0.85, green: 0.75, blue: 0.5).opacity(0.6), lineWidth: 0.6)
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
            // The shared meadow supplies the ground; keep only walking effects here.
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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ObservedObject private var learningCoach = LearningCoach.shared
    @ObservedObject private var lessonAudio = LanguagePronunciationService.shared
    @ObservedObject private var conversation = ConversationController.shared
    @ObservedObject var model: MeetingModel
    @State private var isHovered = false
    @State private var showQuickMenu = false
    @State private var lastActiveDate = Date()
    @State private var spinStartTime: Date? = nil
    @State private var renderingVisible = true

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
            case .writing:
                m.expression = nil
                m.bobY = 0
                m.tilt = 0
            case .thinking:
                let thinkCycle = sin(time * 1.8)
                m.bobY = CGFloat(thinkCycle * 1.5)
                m.tilt = -4.5 + thinkCycle * 1.5 // Nghiêng nhẹ đầu suy nghĩ
                m.expression = .happySmile
                m.shadowRad = 3.2
                m.shadowOffsetY = 2.4
                m.shadowAlpha = 0.20
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
        let time = reduceMotion ? 0 : now.timeIntervalSinceReferenceDate
        let isHearingSpeech = (Date().timeIntervalSince(model.lastAudio ?? .distantPast) < 1.8)
        let speed: Double = isHearingSpeech ? 1.4 : 1.0

        let idleDuration = min(MascotIdlePolicy.systemIdleSeconds, max(0, now.timeIntervalSince(lastActiveDate)))
        let isIdle = !model.isChipChipLearning && !model.running && !conversation.active && !model.busy && !isHovered && !showQuickMenu &&
            !model.isBubbleVisible && !model.isBubbleHovered && idleDuration >= MascotIdlePolicy.idleThreshold

        let activeActivity: MascotIdleActivity = {
            if model.miniTools.mascotFacingTowardPanel != nil {
                return .auto
            } else if model.isDockWalkEnabled {
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

        // A meeting needs a clear writing pose, not perpetual breathing and sparkles.
        if model.running && !isHovered && !isSpinning {
            m = MascotMotionState()
        }

        if model.isChipChipLearning {
            let response = max(0, 1 - now.timeIntervalSince(learningCoach.reactionAt) / 0.8)
            m.bobY = CGFloat(sin(time * 1.7) * 1.5)
            m.tilt = lessonAudio.isSpeaking ? sin(time * 6) * 3 : sin(time * 1.3) * 1.5 + response * 5
            m.walkX = 0
            m.legSwing = 0
        }

        let isBackView = !model.isDockWalkEnabled && isIdle && activeActivity == .fishing
        let isSleeping = !model.isDockWalkEnabled && isIdle && activeActivity == .sleeping

        var isWalking = false
        var walkingTowardRight = true
        var walkingDistance: CGFloat? = nil
        var facingToUse: MascotFacing? = nil

        if model.isChipChipLearning {
            facingToUse = .frontLeft
        } else if isSpinning {
            facingToUse = MascotFacing.spin(elapsed: spinElapsed, duration: spinDuration)
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
        } else if conversation.active {
            facingToUse = .front
        } else if !model.running && !isBackView && !isSleeping {
            facingToUse = .front
        }

        if let panelFacing = model.miniTools.mascotFacingTowardPanel,
           !model.running && !conversation.active && !isSleeping && !isBackView {
            isWalking = false
            facingToUse = panelFacing
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
            // Keep one grassy base beneath every activity and facing direction.
            MascotDefaultGround()
                .offset(x: m.walkX)
                .allowsHitTesting(false)
            if model.mascotStyle == "sprite", rc.isIdle,
               model.isDockWalkEnabled || [.pickingFlowers, .catchingButterfly, .strolling, .fishing].contains(rc.activeActivity) {
                MascotOutdoorSky(time: time)
                    .offset(x: m.walkX)
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
                size: (model.mascotStyle == "pixel" ? 64 : 80) * 0.88,
                style: model.mascotStyle,
                isWorking: model.running || conversation.active,
                isHovered: false,
                hoverPoint: nil,
                isBackView: rc.isBackView,
                isSleeping: rc.isSleeping,
                isWalking: rc.isWalking,
                activity: rc.isIdle ? rc.activeActivity : .auto,
                walkingTowardRight: rc.walkingTowardRight,
                walkingDistance: rc.walkingDistance,
                facing: rc.facing,
                legSwing: m.legSwing,
                time: model.running ? 0 : time
            )
            .onHover { hovering in
                isHovered = hovering
                model.isMascotHovered = hovering || showQuickMenu
                if hovering { lastActiveDate = Date() }
            }
            .scaleEffect(x: m.squashX * m.scaleX, y: m.squashY, anchor: .bottom)
            .offset(x: m.walkX, y: m.bobY)
            .rotationEffect(.degrees(m.tilt), anchor: .bottom)
            .shadow(
                color: Color.black.opacity(m.shadowAlpha),
                radius: m.shadowRad,
                y: m.shadowOffsetY
            )
            // Measure after the avatar's motion transforms so the speech-card
            // pointer follows the rendered person, not its unshifted layout box.
            .background(GeometryReader { geometry in
                Color.clear.preference(key: MascotHeadBoundsKey.self,
                    value: geometry.frame(in: .named("mascotCanvas")))
            })
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

            if rc.isIdle && rc.activeActivity == .thinking {
                MascotThinkingCloudEffect(time: time)
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


                }
            }
        }
    }

    private var dynamicArrowEdge: Edge {
        guard let win = model.mascotWindow,
              let screen = win.screen ?? NSScreen.main else {
            return .trailing
        }
        let winFrame = win.frame
        let screenFrame = screen.visibleFrame

        // Khoảng trống xung quanh Chip Chip so với mép hiển thị của màn hình
        let spaceLeft = winFrame.minX - screenFrame.minX
        let spaceRight = screenFrame.maxX - winFrame.maxX
        let spaceTop = screenFrame.maxY - winFrame.maxY
        let spaceBottom = winFrame.minY - screenFrame.minY

        let popoverWidth: CGFloat = 370
        let popoverHeight: CGFloat = 460

        // 1. Khi sát mép phải màn hình: Hiện bên TRÁI, mũi tên ở cạnh phải (.trailing) trỏ về Chip Chip
        if spaceRight < popoverWidth && spaceLeft >= popoverWidth {
            return .trailing
        }

        // 2. Khi sát mép trái màn hình: Hiện bên PHẢI, mũi tên ở cạnh trái (.leading) trỏ về Chip Chip
        if spaceLeft < popoverWidth && spaceRight >= popoverWidth {
            return .leading
        }

        // 3. Nếu cả 2 bên đều có đủ diện tích: Ưu tiên bên có nhiều không gian hơn
        if spaceLeft >= popoverWidth && spaceRight >= popoverWidth {
            return spaceLeft >= spaceRight ? .trailing : .leading
        }

        // 4. Nếu không gian 2 bên bị bó hẹp: Ưu tiên theo chiều dọc
        if spaceTop >= popoverHeight {
            return .bottom // Popover ở phía trên, mũi tên ở đáy trỏ xuống Chip Chip
        }
        if spaceBottom >= popoverHeight {
            return .top // Popover ở phía dưới, mũi tên ở đỉnh trỏ lên Chip Chip
        }

        return spaceLeft >= spaceRight ? .trailing : .leading
    }

    private var renderInterval: TimeInterval {
        let conserving = ProcessInfo.processInfo.isLowPowerModeEnabled ||
            ProcessInfo.processInfo.thermalState == .serious || ProcessInfo.processInfo.thermalState == .critical
        if conserving { return 1.0 / 4 }
        if showQuickMenu ||
            (spinStartTime.map { Date().timeIntervalSince($0) < 0.72 } ?? false) { return 1.0 / 24 }
        if model.running || model.busy || model.isChipChipLearning || conversation.active { return 1.0 / 8 }
        if model.isDockActuallyWalking { return 1.0 / 12 }
        return 0 // Brief idle animation, separated by quiet resting periods.
    }
    var body: some View {
        ZStack {
            if showQuickMenu {
                MascotFeatureWheel(model: model, isPresented: $showQuickMenu)
                    .zIndex(1)
            }
            // Keep the same live mascot, pose, scenery and status when opening the orbit.
            companionBody
                .offset(y: showQuickMenu ? -45 : 0)
                .zIndex(2)
        }
        .frame(width: showQuickMenu ? 360 : 190, height: showQuickMenu ? 360 : 186)
        .coordinateSpace(name: "mascotCanvas")
        .onPreferenceChange(MascotHeadBoundsKey.self) { bounds in model.updateMascotHeadBounds(bounds) }
        .background(MascotOutsideClickMonitor(expanded: showQuickMenu) {
            showQuickMenu = false
        }.allowsHitTesting(false))
        .onDisappear { model.isMascotHovered = false }
        .onChange(of: showQuickMenu) { _, expanded in
            resizeLauncher(expanded: expanded)
            model.isMascotHovered = expanded || isHovered
            if expanded {
                model.mascotQuickSubtitle.suspendForMascotMenu()
            } else {
                model.mascotQuickSubtitle.resumeAfterMascotMenu()
            }
        }
    }

    private func resizeLauncher(expanded: Bool) {
        guard let window = model.mascotWindow else { return }
        let old = window.frame
        // The compact avatar sits near the bottom of its effects canvas.
        let center = NSPoint(x: old.midX, y: expanded ? old.minY + 48 : old.midY)
        let size: CGFloat = expanded ? 360 : 190
        var frame = NSRect(x: center.x - size / 2,
                           y: expanded ? center.y - 180 : center.y - 48,
                           width: size, height: expanded ? 360 : 186)
        if let screen = window.screen ?? NSScreen.main {
            let area = screen.visibleFrame.insetBy(dx: 8, dy: 8)
            frame.origin.x = max(area.minX, min(frame.minX, area.maxX - frame.width))
            frame.origin.y = max(area.minY, min(frame.minY, area.maxY - frame.height))
        }
        // Resize once without forcing a synchronous display during the tap event.
        window.setFrame(frame, display: false)
    }

    private var companionBody: some View {
        ZStack(alignment: .bottom) {
            if showQuickMenu || reduceMotion || !renderingVisible ||
                (model.running && !isHovered) {
                mascotContent(rc: makeRenderContext(now: Date()), time: 0)
            } else {
                TimelineView(MascotAnimationSchedule(interval: renderInterval)) { context in
                    mascotContent(rc: makeRenderContext(now: context.date), time: context.date.timeIntervalSinceReferenceDate)
                }
            }

            // Share the same compact status badge for conversation and meeting capture.
            if conversation.active || model.running {
                HStack(spacing: 5) {
                    Circle()
                        .fill(TransToolsTheme.accent)
                        .frame(width: 6, height: 6)

                    Image(systemName: conversation.active ? (conversation.waiting ? "brain.head.profile" : "waveform") : "note.text")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(TransToolsTheme.accent)

                    Text(conversation.active ? (conversation.waiting ? "AI đang trả lời..." : "Trò chuyện AI") : "Đang ghi chú cuộc họp")
                        .font(.system(size: 9.5, weight: .bold))
                        .foregroundStyle(.white)

                    Button {
                        if conversation.active {
                            conversation.stop()
                        } else {
                            Task { await model.stop() }
                        }
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(.white.opacity(0.85))
                    }
                    .buttonStyle(.plain)
                    .help(conversation.active ? "Tắt nhanh cuộc trò chuyện với \(MascotIdentity.name)" : "Dừng cuộc họp và lưu bản ghi")
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    Capsule()
                        .fill(Color.black.opacity(0.82))
                        .overlay(Capsule().strokeBorder(TransToolsTheme.accent.opacity(0.6), lineWidth: 1))
                )
                .shadow(color: Color.black.opacity(0.35), radius: 4, y: 2)
                .padding(.bottom, 92)
                .transition(.scale.combined(with: .opacity))
            }
        }
        .frame(width: 186, height: 182, alignment: .bottom)
        .padding(.bottom, 4)
        .contentShape(MascotCompanionHitShape(expanded: showQuickMenu))
        .onChange(of: showQuickMenu) { _, presented in
            model.isMascotHovered = presented || isHovered
        }
        .onAppear { renderingVisible = model.mascotWindow?.occlusionState.contains(.visible) ?? true }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didChangeOcclusionStateNotification)) { notification in
            guard let window = notification.object as? NSWindow, window === model.mascotWindow else { return }
            renderingVisible = window.occlusionState.contains(.visible)
        }
        .onReceive(NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.screensDidSleepNotification)) { _ in
            renderingVisible = false
        }
        .onReceive(NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.screensDidWakeNotification)) { _ in
            renderingVisible = model.mascotWindow?.occlusionState.contains(.visible) ?? true
        }
        .onTapGesture {
            lastActiveDate = Date()
            showQuickMenu.toggle()
        }
        .contextMenu {
            MascotContextMenuView(model: model)
        }
        .help("\(MascotIdentity.name): \(model.isDockWalkEnabled ? "Đang đi dạo thư giãn dọc Dock Bar" : (conversation.active ? "Đang trò chuyện AI với bạn" : (model.running ? "Đang ghi chép cuộc họp" : "Sẵn sàng hỗ trợ bạn")))")
    }
}

private struct MascotHeadBoundsKey: PreferenceKey {
    static let defaultValue: CGRect = .zero
    static func reduce(value: inout CGRect, nextValue: () -> CGRect) { value = nextValue() }
}

private struct MascotCompanionHitShape: Shape {
    var expanded: Bool
    func path(in rect: CGRect) -> Path {
        if !expanded { return Path(rect) }
        return Path(ellipseIn: CGRect(x: rect.midX - 52, y: rect.maxY - 100, width: 104, height: 100))
    }
}

// MARK: - Mascot Context Menu View

struct MascotContextMenuView: View {
    @ObservedObject var model: MeetingModel
    @ObservedObject private var conversation = ConversationController.shared

    var body: some View {
        if conversation.active {
            Button {
                conversation.stop()
            } label: {
                Label("Dừng trò chuyện với AI", systemImage: "stop.circle.fill")
            }

            Button {
                model.showMainWindow()
                model.selectedDashboardTab = 5
            } label: {
                Label("Mở cuộc trò chuyện", systemImage: "bubble.left.and.bubble.right.fill")
            }

            Divider()
        }

        Menu {
            Picker("Hoạt cảnh \(MascotIdentity.name)", selection: $model.mascotIdleActivity) {
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
            Label("Mở Trans Tools", systemImage: "macwindow")
        }

        Menu {
            Button("Dịch từ bôi đen · Option + D") {
                Task { await GlobalHotkeyManager.shared.triggerSelectionTranslation() }
            }
            Button("Chụp & Dịch màn hình · Option + S") {
                ScreenOCRService.shared.triggerScreenOCRTranslation()
            }
            Button("Dịch VI → EN · Option + E") {
                Task { await GlobalHotkeyManager.shared.triggerVietnameseToEnglish() }
            }
            Button("Sửa ngữ pháp · Option + F") {
                Task { await GlobalHotkeyManager.shared.triggerGrammarFixAndPolish() }
            }
            Button("Sổ từ vựng & Flashcards") {
                model.showMainWindow()
                model.selectedDashboardTab = 1
                model.selectedNotebookTab = 1
            }
            Divider()
            Button("Đưa \(MascotIdentity.name) về góc thuận tiện") {
                model.snapMascotToConvenientPosition()
            }
        } label: {
            Label("Tiện ích \(MascotIdentity.name)", systemImage: "square.grid.2x2")
        }

        Button {
            model.showMainWindow()
            model.showAboutSheet = true
        } label: {
            Label("Giới thiệu Trans Tools", systemImage: "info.circle")
        }

        Divider()
        Toggle(isOn: Binding(
            get: { UserDefaults.standard.object(forKey: "MascotQuickSubtitleEnabled") as? Bool ?? true },
            set: { UserDefaults.standard.set($0, forKey: "MascotQuickSubtitleEnabled"); model.mascotQuickSubtitle.refresh() }
        )) {
            Label("Phụ đề nhanh trên mascot", systemImage: "captions.bubble")
        }

        Button {
            model.hideFloatingMascot()
        } label: {
            Label("Tạm biệt \(MascotIdentity.name)", systemImage: "power")
        }
    }
}

struct MascotQuickActionsPopover: View {
    @ObservedObject var model: MeetingModel
    @ObservedObject private var tts = TTSService.shared
    @ObservedObject private var conversation = ConversationController.shared
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
            "\(MascotIdentity.name) sẵn sàng hỗ trợ bạn trong mọi cuộc họp!",
            "Mẹo: Bạn có thể kéo \(MascotIdentity.name) đến bất kỳ vị trí nào trên màn hình! 🎈",
            "Mẹo: Bật 'Phụ đề nổi' để vừa họp Teams vừa xem bản dịch song song! 🎧",
            "\(MascotIdentity.name) luôn dịch bằng AI thông minh (\(model.provider.shortName)) cực mượt! ⚡",
            "Có \(MascotIdentity.name) ở đây rồi, bạn cứ tự tin nghe họp nhé! 💪"
        ]
    }

    private var currentDialogue: String {
        if conversation.active {
            if conversation.waiting {
                return "\(MascotIdentity.name) đang suy nghĩ câu trả lời cho bạn nè... 💭"
            }
            if !conversation.draft.isEmpty {
                return "Đang nghe bạn nói: \"\(conversation.draft)\" 🎙️"
            }
            return "\(MascotIdentity.name) đang lắng nghe bạn nói... Bạn cứ thoải mái trò chuyện nha! 🎙️"
        }
        if model.running {
            return "\(MascotIdentity.name) đang chăm chú nghe & ghi chép bản dịch cuộc họp nè! 📝"
        }
        if model.isDockWalkEnabled {
            return "\(MascotIdentity.name) đang đi dạo thảnh thơi dọc thanh Dock Bar nè! 🚶‍♂️"
        }
        switch model.mascotIdleActivity {
        case .writing: return "\(MascotIdentity.name) đang ghi lại ý tưởng vào sổ 📓"
        case .thinking: return "Để \(MascotIdentity.name) suy nghĩ một chút nhé 💭"
        case .fishing:
            return "Ngồi buông cần câu cá thảnh thơi bên hồ nước trong xanh... Yên bình ghê! 🎣"
        case .sleeping:
            return "Khò khò... \(MascotIdentity.name) chợp mắt tí nha, khi nào bắt đầu họp cứ gọi tớ nhé! 💤"
        case .strolling:
            return "Đi dạo vài bước quanh màn hình cho thư giãn gân cốt nào! 🚶‍♂️"
        case .catchingButterfly:
            return "Oa, có chú bướm xinh dập dờn bay qua nè! Đẹp quá đi mất 🦋"
        case .pickingFlowers:
            return "Bông hoa này ngát hương thơm thật đó! Tặng bạn một ngày thật vui nha 🌸"
        case .listeningMusic:
            return "Giai điệu này chill quá! Đeo tai nghe nhún nhảy chuẩn bị họp nè 🎧"
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

                    MiniAvatarView(size: 32, style: model.mascotStyle, isWorking: model.running || conversation.active)
                }

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 5) {
                        Text("\(MascotIdentity.name)")
                            .font(.system(size: 13.5, weight: .bold, design: .rounded))
                            .lineLimit(1)
                            .fixedSize(horizontal: true, vertical: false)
                        Text("Seedly 3D")
                            .font(.system(size: 9.5, weight: .semibold))
                            .lineLimit(1)
                            .fixedSize(horizontal: true, vertical: false)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1.5)
                            .background(Color.primary.opacity(0.06))
                            .foregroundStyle(.secondary)
                            .clipShape(Capsule())
                    }

                    HStack(spacing: 4) {
                        Circle()
                            .fill(conversation.active || model.running ? TransToolsTheme.accent : TransToolsTheme.accent)
                            .frame(width: 6, height: 6)
                        Text(
                            conversation.active
                                ? (conversation.waiting ? "AI đang trả lời..." : "Đang trò chuyện • \(conversation.chatLanguage.displayName)")
                                : (model.running ? "Đang ghi chú cuộc họp" : "Sẵn sàng • Nghỉ ngơi")
                        )
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(conversation.active || model.running ? TransToolsTheme.accent : Color.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .layoutPriority(1)

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
                        .overlay(Circle().strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.8))
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
                HStack(alignment: .center, spacing: 7) {
                    Image(systemName: "bubble.left.and.bubble.right.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(
                            LinearGradient(colors: [TransToolsTheme.accent, Color.cyan], startPoint: .topLeading, endPoint: .bottomTrailing)
                        )

                    Text(currentDialogue)
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(.primary)
                        .lineSpacing(2)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, 9)
                .padding(.vertical, 7)
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
                        .strokeBorder(TransToolsTheme.accent.opacity(0.18), lineWidth: 1)
                )
            }
            .buttonStyle(.plain)
            .help("Bấm vào để đổi câu chuyện với \(MascotIdentity.name)")

            // Thẻ Trò chuyện AI đang hoạt động (cho phép tắt nhanh hoặc mở chat)
            if conversation.active {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        HStack(spacing: 5) {
                            Circle()
                                .fill(TransToolsTheme.accent)
                                .frame(width: 7, height: 7)
                            Text("ĐANG TRÒ CHUYỆN VỚI AI")
                                .font(.system(size: 9.5, weight: .bold))
                                .foregroundStyle(TransToolsTheme.accent)
                        }
                        Spacer()
                        Text(conversation.chatLanguage.displayName)
                            .font(.system(size: 9, weight: .bold))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1.5)
                            .background(TransToolsTheme.accent.opacity(0.12))
                            .foregroundStyle(TransToolsTheme.accent)
                            .clipShape(Capsule())
                    }

                    if !conversation.draft.isEmpty {
                        Text("Đang nghe: \"\(conversation.draft)\"")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                    } else {
                        Text(conversation.status)
                            .font(.system(size: 10.5))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }

                    HStack(spacing: 8) {
                        Button {
                            conversation.stop()
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "stop.fill")
                                Text("Dừng trò chuyện")
                            }
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 5)
                            .background(Color.red)
                            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                        }
                        .buttonStyle(.plain)

                        Button {
                            isPresented = false
                            model.showMainWindow()
                            model.selectedDashboardTab = 5
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "arrow.up.forward.app")
                                Text("Mở chat")
                            }
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.primary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 5)
                            .background(Color.secondary.opacity(0.12))
                            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(9)
                .background(TransToolsTheme.accent.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .strokeBorder(TransToolsTheme.accent.opacity(0.25), lineWidth: 1)
                )
            }

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
                            .foregroundStyle(model.isDockWalkEnabled ? TransToolsTheme.accent : Color.secondary)
                        Text(model.isDockWalkEnabled ? "Đi dạo: Bật" : "Đi dạo")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(model.isDockWalkEnabled ? TransToolsTheme.accent : Color.secondary)
                    }
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(model.isDockWalkEnabled ? TransToolsTheme.accent.opacity(0.14) : Color.secondary.opacity(0.10))
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                }
                .buttonStyle(.plain)
                .help("\(MascotIdentity.name) tự động đi dạo qua lại dọc theo thanh Dock Bar khi máy rảnh rỗi")
            }
            .padding(.horizontal, 2)

            // Mini Quick Chat (Khung Dịch nhanh sáng sủa, nền trắng tinh tế)
            VStack(alignment: .leading, spacing: 7) {
                HStack {
                    HStack(spacing: 4) {
                        Image(systemName: "bolt.fill")
                            .foregroundStyle(TransToolsTheme.accent)
                            .font(.system(size: 9.5))
                        Text("DỊCH NHANH VI → EN")
                            .font(.system(size: 9.5, weight: .bold))
                            .foregroundStyle(TransToolsTheme.accent)
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
                        .background(TransToolsTheme.accent.opacity(0.12))
                        .foregroundStyle(TransToolsTheme.accent)
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
                        .foregroundStyle(TransToolsTheme.accent)
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
                                            .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.8)
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
                                .strokeBorder(Color.primary.opacity(0.12), lineWidth: 1)
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
                                    Label(quickCopied ? "Đã copy" : "Copy", systemImage: quickCopied ? "checkmark" : "doc.on.doc")
                                        .font(.system(size: 10, weight: .bold))
                                        .foregroundStyle(quickCopied ? TransToolsTheme.accent : Color.white)
                                        .padding(.horizontal, 7)
                                        .padding(.vertical, 4)
                                        .background(quickCopied ? TransToolsTheme.accent.opacity(0.2) : TransToolsTheme.accent)
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
                                                    .foregroundStyle(copiedAltID == alt.id ? TransToolsTheme.accent : .secondary)
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
                            .strokeBorder(TransToolsTheme.accent.opacity(0.20), lineWidth: 0.8)
                    )
                }
            }
            .padding(9)
            .background(Color(nsColor: .controlBackgroundColor).opacity(0.75))
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
            )

            // AI Smart Suggestions Preview (nếu có)
            if model.meetingSuggestionsEnabled && !model.suggestedReplies.isEmpty {
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
                        MascotSuggestedReplyRow(reply: reply, copiedReplyID: $copiedReplyID, tts: tts)
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
                    else { await model.startFromMascot() }
                }
            } label: {
                HStack(spacing: 9) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(model.running ? Color.red : TransToolsTheme.accent)
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
                        .strokeBorder(model.running ? Color.red.opacity(0.25) : TransToolsTheme.accent.opacity(0.22), lineWidth: 1)
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
                            .fill(model.isOverlayVisible ? TransToolsTheme.accent : TransToolsTheme.accent)
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
                            .background(TransToolsTheme.accent.opacity(0.15))
                            .foregroundStyle(TransToolsTheme.accent)
                            .clipShape(Capsule())
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .background(
                    model.isOverlayVisible
                        ? TransToolsTheme.accent.opacity(0.08)
                        : Color(nsColor: .controlBackgroundColor).opacity(0.85)
                )
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(model.isOverlayVisible ? TransToolsTheme.accent.opacity(0.25) : TransToolsTheme.accent.opacity(0.22), lineWidth: 1)
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
                        .strokeBorder(TransToolsTheme.accent.opacity(0.22), lineWidth: 1)
                )
            }
            .buttonStyle(.plain)

            Menu {
                Menu("Dịch & chỉnh câu") {
                    Button("Dịch từ bôi đen · Option + D") {
                        isPresented = false
                        Task { await GlobalHotkeyManager.shared.triggerSelectionTranslation() }
                    }
                    Button("Chụp & Dịch màn hình · Option + S") {
                        isPresented = false
                        ScreenOCRService.shared.triggerScreenOCRTranslation()
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
                    Label("Đưa \(MascotIdentity.name) về góc thuận tiện", systemImage: "arrow.down.forward.and.arrow.up.backward")
                }
            } label: {
                Label("Tiện ích \(MascotIdentity.name)", systemImage: "square.grid.2x2")
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
                        Text("Tạm biệt \(MascotIdentity.name)")
                    }
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)

                Spacer()

                Text("Trans Tools")
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 4)
            .padding(.top, 1)
        }
        .padding(14)
        .frame(width: 368)
        .background(
            ConversationScenery(topic: .everyday)
                .overlay(TransToolsTheme.mint.opacity(0.28))
                .overlay(Color(nsColor: .windowBackgroundColor).opacity(0.35))
                .allowsHitTesting(false)
        )
        .enableAppleTranslationSession(source: .vietnamese, target: .english)
    }
}

// MARK: - Mascot Suggested Reply Row

struct MascotSuggestedReplyRow: View {
    let reply: ReplySuggestion
    @Binding var copiedReplyID: UUID?
    @ObservedObject var tts: TTSService

    var body: some View {
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
                .strokeBorder(Color.primary.opacity(0.06), lineWidth: 0.8)
        )
    }
}

// MARK: - Main Application Navigation & View

struct MainDashboardView: View {
    @ObservedObject private var ocr = ScreenOCRService.shared
    @ObservedObject var model: MeetingModel
    @ObservedObject private var updater = AppUpdater.shared

    private var headerTabs: some View {
        HStack(spacing: 3) {
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

            NavTabButton(title: "Đọc văn bản", icon: "speaker.wave.2", badge: nil, badgeColor: TransToolsTheme.accent, isSelected: model.selectedDashboardTab == 6) {
                withAnimation(.easeInOut(duration: 0.2)) { model.selectedDashboardTab = 6 }
            }

            NavTabButton(
                title: "Học ngôn ngữ",
                icon: "graduationcap.fill",
                badge: LanguageLearningManager.shared.dueTodayCount > 0 ? "\(LanguageLearningManager.shared.dueTodayCount)" : nil,
                badgeColor: .orange,
                isSelected: model.selectedDashboardTab == 3
            ) {
                withAnimation(.easeInOut(duration: 0.2)) { model.selectedDashboardTab = 3 }
            }

            NavTabButton(
                title: "Trò chuyện",
                icon: "bubble.left.and.bubble.right.fill",
                badge: nil,
                badgeColor: .gray,
                isSelected: model.selectedDashboardTab == 5
            ) {
                withAnimation(.easeInOut(duration: 0.2)) { model.selectedDashboardTab = 5 }
            }

            NavTabButton(
                title: "Cài đặt",
                icon: "gearshape.fill",
                badge: nil,
                badgeColor: .gray,
                isSelected: model.selectedDashboardTab == 4,
                iconOnly: true
            ) {
                withAnimation(.easeInOut(duration: 0.2)) { model.selectedDashboardTab = 4 }
            }
        }
        .fixedSize(horizontal: true, vertical: false)
        .padding(4)
        .background(Color.white.opacity(0.76))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(TransToolsTheme.accent.opacity(0.20), lineWidth: 1)
        )
    }

    private var headerActions: some View {
        HStack(spacing: 6) {
            DashboardAppearanceMenu()
            Button {
                model.toggleFloatingMascot()
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: model.isFloatingMascotVisible ? "sparkles.tv.fill" : "sparkles.tv")
                    Text("\(MascotIdentity.name)")
                        .lineLimit(1)
                }
                .font(.system(size: 12, weight: .semibold))
                .padding(.horizontal, 12)
                .frame(height: 36)
                .background(model.isFloatingMascotVisible ? TransToolsTheme.accent.opacity(0.17) : Color.white.opacity(0.76))
                .foregroundStyle(TransToolsTheme.accent)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(TransToolsTheme.accent.opacity(0.24), lineWidth: 1))
            }
            .buttonStyle(.plain)
            .fixedSize(horizontal: true, vertical: false)
            .help("Bật/Tắt trợ lý \(MascotIdentity.name) nổi trên màn hình")

            Button { model.toggleOverlay() } label: {
                HStack(spacing: 5) {
                    Image(systemName: model.isOverlayVisible ? "pip.exit" : "pip.enter")
                    Text("Phụ đề")
                        .lineLimit(1)
                }
                .font(.system(size: 12, weight: .semibold))
                .padding(.horizontal, 12)
                .frame(height: 36)
                .background(model.isOverlayVisible ? TransToolsTheme.accent.opacity(0.17) : Color.white.opacity(0.76))
                .foregroundStyle(TransToolsTheme.accent)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(TransToolsTheme.accent.opacity(0.24), lineWidth: 1))
            }
            .buttonStyle(.plain)
            .fixedSize(horizontal: true, vertical: false)
            .help("Mở/ẩn thanh phụ đề gọn trên mascot")
            .contextMenu {
                Button("Mở phụ đề đầy đủ") { model.showOverlay() }
                Button("Phụ đề đầy đủ phía trên") { model.positionOverlay(atTop: true) }
                Button("Phụ đề đầy đủ phía dưới") { model.positionOverlay(atTop: false) }
            }


        }
        .fixedSize(horizontal: true, vertical: false)
    }

    var body: some View {
        VStack(spacing: 0) {
            // Modern Clean Toolbar: Leading Navigation Tabs & Trailing Actions
            HStack(spacing: 12) {
                // Leading Navigation Tabs
                ScrollView(.horizontal, showsIndicators: false) { headerTabs }


                Spacer(minLength: 16)

                // Trailing Action Controls
                headerActions
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 18)
            .padding(.vertical, 8)
            .background(Color.white.opacity(0.20))
            .overlay(Rectangle().fill(TransToolsTheme.accent.opacity(0.10)).frame(height: 1), alignment: .bottom)

            // Body Content based on Tab (Dùng ZStack để bảo tồn nguyên trạng thái của từng tab khi chuyển qua lại)
            ZStack {
                MeetingView(model: model)
                    .opacity(model.selectedDashboardTab == 0 ? 1 : 0)
                    .allowsHitTesting(model.selectedDashboardTab == 0)

                MeetingNotebookView(model: model)
                    .opacity(model.selectedDashboardTab == 1 ? 1 : 0)
                    .allowsHitTesting(model.selectedDashboardTab == 1)

                QuickTranslateView(model: model)
                    .opacity(model.selectedDashboardTab == 2 ? 1 : 0)
                    .allowsHitTesting(model.selectedDashboardTab == 2)

                VStack(alignment: .leading, spacing: 16) {
                    Text("Đọc văn bản").font(.title2.bold())
                    Text("Nghe văn bản hoặc chọn truyện từ thư viện").font(.callout).foregroundStyle(.secondary)
                    SharedTextReaderView(model: model)
                }
                .padding(24)
                .opacity(model.selectedDashboardTab == 6 ? 1 : 0)
                .allowsHitTesting(model.selectedDashboardTab == 6)

                LanguageLearningDashboardView(model: model)
                    .opacity(model.selectedDashboardTab == 3 ? 1 : 0)
                    .allowsHitTesting(model.selectedDashboardTab == 3)

                AIConversationView(model: model, manager: LanguageLearningManager.shared)
                    .opacity(model.selectedDashboardTab == 5 ? 1 : 0)
                    .allowsHitTesting(model.selectedDashboardTab == 5)

                SettingsDashboardView(model: model)
                    .opacity(model.selectedDashboardTab == 4 ? 1 : 0)
                    .allowsHitTesting(model.selectedDashboardTab == 4)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .alert("Thông báo dữ liệu", isPresented: Binding(get: { model.storageError != nil }, set: { if !$0 { model.storageError = nil } })) {
            Button("Đóng", role: .cancel) { model.storageError = nil }
        } message: { Text(model.storageError ?? "") }
        .sheet(isPresented: $ocr.showReview) {
            ScreenOCRReviewView()
        }
        .sheet(isPresented: $model.showAboutSheet) {
            AboutAppPopoverView(isPresented: $model.showAboutSheet)
        }
        .frame(minWidth: min(1080, (NSScreen.main?.visibleFrame.width ?? 1160) - 32), minHeight: 600)
        .background {
            DashboardBackground()
        }
        .tint(TransToolsTheme.accent)
        .sheet(isPresented: $updater.showUpdateSheet) {
            UpdateSheetView(isPresented: $updater.showUpdateSheet)
        }
        .onReceive(NotificationCenter.default.publisher(for: AITransport.modelResolved)) { notification in
            model.acceptResolvedModel(notification)
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            Task {
                await model.refresh()
            }
        }
        .enableAppleTranslationSession(source: model.sourceLanguage, target: model.targetLanguage)
        .task(id: "\(model.provider.rawValue):\(model.sourceLanguage.rawValue):\(model.targetLanguage.rawValue)") {
            #if canImport(Translation)
            if model.provider == .apple, #available(macOS 15.0, *) {
                await AppleNativeTranslator.prepareInstalled(from: model.sourceLanguage, to: model.targetLanguage)
            }
            #endif
        }
    }
}

// MARK: - Navigation Tab Button

struct NavTabButton: View {
    let title: String
    let icon: String
    let badge: String?
    let badgeColor: Color
    let isSelected: Bool
    var iconOnly: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 7) {
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .medium))

                if !iconOnly {
                    Text(title)
                        .font(.system(size: 13.5, weight: .semibold))
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                }

                if let badge {
                    HStack(spacing: 3) {
                        if badge == "LIVE" {
                            Circle()
                                .fill(badgeColor)
                                .frame(width: 5, height: 5)
                        }
                        Text(badge)
                            .font(.system(size: 9, weight: .bold))
                            .lineLimit(1)
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(badgeColor.opacity(0.18))
                    .foregroundStyle(badgeColor)
                    .clipShape(Capsule())
                }
            }
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
            .padding(.horizontal, 11)
            .padding(.vertical, 8)
            .background(isSelected ? TransToolsTheme.accent.opacity(0.15) : Color.clear)
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(isSelected ? TransToolsTheme.accent.opacity(0.24) : Color.clear, lineWidth: 1))
            .foregroundStyle(isSelected ? TransToolsTheme.accent : Color.secondary)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
        .help(title)
        .accessibilityLabel(title)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
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
                    .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
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
                        .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
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
                                    .strokeBorder(TransToolsTheme.accent.opacity(0.25), lineWidth: 1)
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
                            .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
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
                    .strokeBorder(model.subtitleMode == .originalOnly ? Color.green.opacity(0.35) : Color.primary.opacity(0.08), lineWidth: 1)
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

    @ObservedObject private var localModels = LocalTTSModelManager.shared
    @ObservedObject private var externalModels = ExternalTTSModelManager.shared
    @State private var showVoiceSettings = false
    private var activeEngine: LanguageVoiceEngine {
        let _ = externalModels.revision
        return ModelManager.shared.routedEngine(for: activeLocale, localDefault: localModels.isNaturalVoiceEnabled, edgeDefault: tts.useEdgeNaturalVoice)
    }
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
                    Label(tts.isSpeaking ? "Đang phát thử..." : "Nghe thử giọng đọc", systemImage: "speaker.wave.2")
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

            if activeEngine == .system || activeEngine == .local {
            Section("Phong cách giọng đọc (Tone & Cảm xúc)") {
                ForEach(VoiceTone.allCases) { tone in
                    Button {
                        tts.voiceTone = tone
                    } label: {
                        HStack {
                            Text(tone.title)
                            if tts.voiceTone == tone {
                                Spacer()
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            }

            Divider()

            }
            if let speechModel = activeEngine.externalModel {
                Section(speechModel.title) {
                    ForEach(speechModel.voices(for: activeLocale)) { voice in
                        Button {
                            UserDefaults.standard.set(voice.id, forKey: "TTS_" + speechModel.rawValue + "_Voice_" + LanguageVoicePreferences.code(activeLocale))
                            externalModels.refresh()
                        } label: {
                            HStack { Text(voice.displayTitle); if speechModel.selectedVoice(for: activeLocale) == voice.id { Image(systemName: "checkmark") } }
                        }
                    }
                }
            } else {
            Section("Giọng đọc (\(tts.autoTarget == .translation ? model.targetLanguage.shortName : model.sourceLanguage.shortName))") {
                Button {
                    tts.selectedVoiceID = nil
                } label: {
                    HStack {
                        Text(activeEngine.isLocal ? "Tự động · Giọng dự phòng" : "Tự động chọn giọng")
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

            }
            Section("Tốc độ giọng đọc") {
                ForEach([Float(0.40), 0.44, 0.46, 0.52, 0.58], id: \.self) { rate in
                    Button {
                        tts.speechRate = rate
                    } label: {
                        HStack {
                            Text(rate == 0.40 ? "Rất chậm - Luyện nghe (0.40x)" :
                                 rate == 0.44 ? "Chậm rãi - Rõ từng chữ (0.44x)" :
                                 rate == 0.46 ? "Chuẩn tự nhiên - Khuyên dùng (0.46x)" :
                                 rate == 0.52 ? "Nhanh - Tốc độ họp (0.52x)" : "Rất nhanh (0.58x)")
                            if abs(tts.speechRate - rate) < 0.001 {
                                Spacer()
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
                if ![Float(0.40), 0.44, 0.46, 0.52, 0.58].contains(where: { abs(tts.speechRate - $0) < 0.001 }) {
                    Label("Tùy chỉnh (\(String(format: "%.2f", tts.speechRate))x)", systemImage: "checkmark")
                }
            }

            Divider()

            Button("Cấu hình giọng theo ngôn ngữ…") { showVoiceSettings = true }

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
                    .strokeBorder(tts.isAutoTTSEnabled ? TransToolsTheme.navy.opacity(0.35) : Color.primary.opacity(0.08), lineWidth: 1)
            )
        }
        .sheet(isPresented: $showVoiceSettings) {
            VStack(alignment: .leading, spacing: 18) {
                HStack { Text("Giọng đọc & Phát âm").font(.title2.bold()); Spacer(); Button("Xong") { showVoiceSettings = false }.buttonStyle(TransToolsActionButtonStyle()) }
                ScrollView { SpeechSettingsView(language: tts.autoTarget == .translation ? model.targetLanguage : model.sourceLanguage) }
            }.padding(24).frame(width: 640, height: 620)
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
                                        .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
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
                                    IsolatedAudioMeterView(meter: model.audioMeter)
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
                                .strokeBorder(Color.primary.opacity(0.06), lineWidth: 1)
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
                    .strokeBorder(Color.primary.opacity(0.06), lineWidth: 1)
            )

            // Permanent Keyboard Shortcut & Developer Phrases Guide on Main Dashboard
            KeyboardShortcutGuideCard()

            // Subtitle Stream Section
            ZStack {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color(nsColor: .controlBackgroundColor).opacity(model.captions.isEmpty && !model.running ? 0 : 0.3))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .strokeBorder(Color.primary.opacity(0.06), lineWidth: 1)
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

                                Text(model.hasReceivedAudio
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
                            Image(systemName: "waveform.badge.mic")
                                .font(.system(size: 46))
                                .foregroundStyle(TransToolsTheme.accent)
                                .padding(.bottom, 4)

                            VStack(spacing: 6) {
                                Text("Sẵn sàng nghe & phiên dịch")
                                    .font(.system(size: 17, weight: .bold, design: .rounded))

                                Text("Chọn nguồn âm để bắt đầu")
                                    .font(.system(size: 13))
                                    .foregroundStyle(.secondary)
                                    .multilineTextAlignment(.center)
                                    .frame(maxWidth: 420)
                            }

                            // Feature badges
                            HStack(spacing: 12) {
                                FeatureBadge(icon: "lock.shield", text: "Nhận diện tiếng Anh offline")
                                FeatureBadge(icon: "sparkles", text: "Translate Tiếng Việt")
                                FeatureBadge(icon: "speaker.wave.3", text: "Thu mọi âm thanh hệ thống")
                            }
                            .padding(.top, 4)
                        }
                        .padding(32)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)


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
                                        targetLanguage: model.targetLanguage,
                                        translationEngineLabel: model.subtitleEngineLabel
                                    )
                                    .equatable()
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
                        .onChange(of: model.captions.count) { _, _ in
                            withAnimation(.easeOut(duration: 0.25)) {
                                proxy.scrollTo("SCROLL_BOTTOM_ANCHOR", anchor: .bottom)
                            }
                        }
                    }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

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
                    Button(role: .destructive) {
                        model.clearCaptions()
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "trash")
                            Text("Xóa bảng ghi")
                        }
                    }
                    .buttonStyle(TransToolsActionButtonStyle())
                }

                HStack(spacing: 8) {
                    Button {
                        model.saveCurrentSession()
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: "book.closed.fill")
                            Text("Lưu Sổ tay")
                        }
                    }
                    .buttonStyle(TransToolsActionButtonStyle())
                    .disabled(model.captions.isEmpty)
                    .help("Lưu toàn bộ hội thoại cuộc họp vào Sổ tay để xem lại bất cứ lúc nào")

                    Button {
                        model.exportCurrentDocx()
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: "doc.richtext.fill")
                            Text("Xuất Word")
                        }
                    }
                    .buttonStyle(TransToolsActionButtonStyle())
                    .disabled(model.captions.isEmpty || model.running)
                    .help("Xuất biên bản cuộc họp và bảng hội thoại song ngữ sang Microsoft Word (.docx)")

                    Button {
                        model.export(srt: false)
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: "doc.text")
                            Text("Xuất TXT")
                        }
                    }
                    .buttonStyle(TransToolsActionButtonStyle())
                    .disabled(model.captions.isEmpty || model.running)

                    Button {
                        model.export(srt: true)
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: "captions.bubble.fill")
                            Text("Xuất SRT")
                        }
                    }
                    .buttonStyle(TransToolsActionButtonStyle())
                    .disabled(model.captions.isEmpty || model.running)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(Color.white.opacity(0.94), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(TransToolsTheme.accent.opacity(0.18), lineWidth: 1))
        }
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .padding(.bottom, 14)
    }
}

// MARK: - Caption Card View

struct CaptionCardView: View, Equatable {
    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.caption == rhs.caption && lhs.isLive == rhs.isLive &&
        lhs.mode == rhs.mode && lhs.sourceLanguage == rhs.sourceLanguage &&
        lhs.targetLanguage == rhs.targetLanguage &&
        lhs.translationEngineLabel == rhs.translationEngineLabel
    }
    let caption: Caption
    var isLive: Bool = false
    var mode: SubtitleDisplayMode = .bilingual
    var sourceLanguage: AppLanguage = .english
    var targetLanguage: AppLanguage = .vietnamese
    var translationEngineLabel: String = ""
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
                    }
                    .buttonStyle(TransToolsActionButtonStyle(height: 26))
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
                    }
                    .buttonStyle(TransToolsActionButtonStyle(height: 26))
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
                    }
                    .buttonStyle(TransToolsActionButtonStyle(height: 26))
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
                    }
                    .buttonStyle(TransToolsActionButtonStyle(height: 26))
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
                            Text("Đang dịch...")
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
                .strokeBorder(isLive ? TransToolsTheme.accent.opacity(0.35) : Color.primary.opacity(0.06), lineWidth: isLive ? 1.5 : 1)
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
        .overlay(Capsule().strokeBorder(Color.primary.opacity(0.06), lineWidth: 1))
    }
}

// MARK: - Tab 2: Quick Translate (Đa chuyên ngành & Gợi ý thông minh)

struct QuickTranslateView: View {
    @ObservedObject var model: MeetingModel
    @ObservedObject private var quickDraft: SubtitleQuickStore
    private var input: String {
        get { quickDraft.text }
        nonmutating set { quickDraft.text = newValue }
    }
    init(model: MeetingModel) { self.model = model; self.quickDraft = model.miniTools.state.translation }
    @FocusState private var sourceEditorFocused: Bool
    @AppStorage("QuickTranslateTextSize") private var editorTextSize: Double = 15
    @State private var showContext = false
    @State private var adoptedMiniResultID: UUID?
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
        VStack(spacing: 16) {
            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Dịch nhanh").font(.title2.bold())
                    Text("Dịch, sửa ngữ pháp và chọn cách diễn đạt phù hợp")
                        .font(.callout).foregroundStyle(.secondary)
                }
                Spacer()
                translationActions
                Button { showContext.toggle() } label: {
                    Label(showContext ? "Thu gọn" : "Ngữ cảnh & Mẫu câu", systemImage: "slider.horizontal.3")
                }.buttonStyle(SettingsActionButtonStyle())
            }
            if showContext {
                specialtyBar
                suggestionBar
            }
            HStack(spacing: 16) {
                languageActionBar
                Label(model.domainSpecialty.title, systemImage: model.domainSpecialty.icon)
                    .font(.callout).foregroundStyle(.secondary).lineLimit(1)
            }
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
        .padding(24)
        .enableAppleTranslationSession(source: model.sourceLanguage, target: model.targetLanguage)
        .onAppear { adoptMiniTranslation() }
        .onChange(of: quickDraft.latest?.id) { _, _ in adoptMiniTranslation() }
        .onChange(of: model.selectedDashboardTab) { _, tab in if tab == 2 { adoptMiniTranslation() } }
    }

    private func adoptMiniTranslation() {
        guard let entry = quickDraft.latest, entry.mode == .translate,
              entry.id != adoptedMiniResultID, entry.language == model.targetLanguage,
              entry.input == input.trimmingCharacters(in: .whitespacesAndNewlines) else { return }
        adoptedMiniResultID = entry.id
        output = entry.output
        translationResult = QuickTranslationResult(primary: entry.output)
        lastActionWasPolish = false
        error = ""
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
                            .strokeBorder(Color.primary.opacity(0.12), lineWidth: 1)
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
                    .strokeBorder(Color.primary.opacity(0.06), lineWidth: 1)
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
                                        .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.8)
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
                    .frame(height: 40)
                    .background(Color(nsColor: .controlBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .strokeBorder(Color.primary.opacity(0.12), lineWidth: 1)
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
                                    .strokeBorder(TransToolsTheme.accent.opacity(0.25), lineWidth: 1)
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
                    .frame(height: 40)
                    .background(Color(nsColor: .controlBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .strokeBorder(Color.primary.opacity(0.12), lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)

                Spacer()

            }

    }

    private var translationActions: some View {
        HStack(spacing: 10) {
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
                        .frame(height: 40)
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
                            .frame(width: 28, height: 40)
                    }
                    .menuStyle(.borderlessButton)
                    .menuIndicator(.hidden)
                    .fixedSize()
                }
                .fixedSize(horizontal: true, vertical: false)
                .foregroundStyle(TransToolsTheme.accent)
                .background(TransToolsTheme.navy.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(TransToolsTheme.navy.opacity(0.28), lineWidth: 1)
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
                }
                .buttonStyle(TransToolsActionButtonStyle(prominent: true))
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
                        Label("Văn bản gốc · \(model.sourceLanguage.shortName.uppercased())", systemImage: "square.and.pencil")
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
                            Text("Nhập hoặc dán văn bản…")
                                .font(.system(size: editorTextSize))
                                .foregroundStyle(.secondary.opacity(0.65))
                                .padding(.horizontal, 20)
                                .padding(.vertical, 18)
                        }

                        TextEditor(text: $quickDraft.text)
                            .font(.system(size: editorTextSize))
                            .scrollContentBackground(.hidden)
                            .padding(16)
                            .lineSpacing(6)
                            .focused($sourceEditorFocused)
                            .accessibilityLabel("Văn bản cần dịch")
                    }
                    .frame(maxWidth: .infinity, minHeight: 220, maxHeight: .infinity)
                    .background(Color(nsColor: .controlBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(TransToolsTheme.accent.opacity(sourceEditorFocused ? 0.65 : 0.22), lineWidth: sourceEditorFocused ? 1.5 : 1)
                    )

                    // Footer of Left Panel
                    HStack {
                        Text("\(input.count) ký tự")
                            .font(.system(size: 11))
                            .foregroundStyle(.tertiary)

                        Spacer()

                        HStack(spacing: 8) {
                            Button { editorTextSize = max(12, editorTextSize - 1) } label: {
                                Image(systemName: "textformat.size.smaller")
                            }
                            .help("Giảm cỡ chữ")
                            Text("\(Int(editorTextSize))")
                                .monospacedDigit()
                            Button { editorTextSize = min(22, editorTextSize + 1) } label: {
                                Image(systemName: "textformat.size.larger")
                            }
                            .help("Tăng cỡ chữ")
                        }
                        .font(.system(size: 11))
                        .foregroundStyle(TransToolsTheme.accent)
                        .buttonStyle(.plain)
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
                            Text("Bản dịch · \(model.targetLanguage.shortName.uppercased())")
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
                                Text(translating ? "Đang dịch câu của bạn theo chuyên ngành \(model.domainSpecialty.title)…" : (polishing ? "Đang sửa ngữ pháp theo \(polishedLanguage.displayName)…" : "Bản dịch sẽ hiện tại đây."))
                                    .font(.system(size: editorTextSize))
                                    .foregroundStyle(.tertiary)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            } else {
                                primaryTranslation
                                // Alternatives / Gợi ý phương án diễn đạt khác (khi dịch)
                                if !lastActionWasPolish && !translationResult.alternatives.isEmpty {
                                    alternativeTranslations
                                }
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(20)
                    }
                    .frame(maxWidth: .infinity, minHeight: 220, maxHeight: .infinity)
                    .background(Color(nsColor: .controlBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(TransToolsTheme.accent.opacity(0.22), lineWidth: 1)
                    )

    }


    private var primaryTranslation: some View {
                                // Primary result (Đã bỏ label "BẢN DỊCH CHUẨN" theo yêu cầu người dùng)
                                Text(output)
                                    .font(.system(size: editorTextSize, weight: .regular))
                                    .lineSpacing(6)
                                    .foregroundStyle(.primary)
                                    .textSelection(.enabled)
                                    .frame(maxWidth: .infinity, alignment: .leading)

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
                                                    .strokeBorder(Color.primary.opacity(0.06), lineWidth: 0.8)
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
                            let engineInfo = model.provider == .apple
                                ? "Translate • Trên thiết bị"
                                : model.provider == .free || model.key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                ? "Google Dịch • Miễn phí"
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
        let currentProvider = model.provider
        let currentModel = model.modelName
        let currentKey = model.key.trimmingCharacters(in: .whitespacesAndNewlines)
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
    @State private var editingKeyForProvider: AIProvider? = nil
    @State private var tempKeyInput: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Header
            HStack {
                HStack(spacing: 8) {
                    Image(systemName: "gearshape.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(TransToolsTheme.accent)
                    Text("Cấu hình Trans Tools")
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

            // Custom Spacious Tab Bar
            HStack(spacing: 4) {
                settingsTabButton(title: "Phụ đề", icon: "captions.bubble", tag: 0)
                settingsTabButton(title: "AI Trợ lý", icon: "sparkles", tag: 1)
                settingsTabButton(title: "Hệ thống & UI", icon: "macwindow.and.cursor", tag: 2)
                settingsTabButton(title: "Cập nhật", icon: "arrow.triangle.2.circlepath", tag: 3)
                settingsTabButton(title: "Giọng đọc", icon: "waveform", tag: 4)
            }
            .padding(4)
            .background(Color.primary.opacity(0.05))
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

            // Standardized Uniform Tab Content Area (Fixed Height)
            ScrollView(.vertical, showsIndicators: true) {
                VStack(alignment: .leading, spacing: 14) {
                    if selectedTab == 0 {
                        // Tab 0: Dịch phụ đề cuộc họp & Chuyên ngành
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
                                .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(Color.primary.opacity(0.12), lineWidth: 1))
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

                            // Card 1: Translate (Default)
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
                                            Text("Translate (Mặc định)")
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
                                .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(model.provider == .apple ? TransToolsTheme.accent : Color.primary.opacity(0.08), lineWidth: 1.2))
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
                                .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(model.provider == .free ? TransToolsTheme.accent : Color.primary.opacity(0.08), lineWidth: 1.2))
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
                                let activeModelList = (model.provider == p && !model.availableModels.isEmpty) ? model.availableModels : p.defaultModels

                                VStack(alignment: .leading, spacing: 6) {
                                    Button {
                                        if hasKey {
                                            model.setProvider(p)
                                        } else {
                                            tempKeyInput = ""
                                            withAnimation(.easeInOut(duration: 0.2)) {
                                                editingKeyForProvider = p
                                            }
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

                                                        Button {
                                                            tempKeyInput = CredentialStore.read(for: p)
                                                            withAnimation(.easeInOut(duration: 0.2)) {
                                                                editingKeyForProvider = (editingKeyForProvider == p ? nil : p)
                                                            }
                                                        } label: {
                                                            Text(editingKeyForProvider == p ? "Đóng" : "Đổi Key")
                                                                .font(.system(size: 9.5, weight: .semibold))
                                                                .foregroundStyle(TransToolsTheme.accent)
                                                        }
                                                        .buttonStyle(.plain)
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
                                                Button {
                                                    tempKeyInput = ""
                                                    withAnimation(.easeInOut(duration: 0.2)) {
                                                        editingKeyForProvider = p
                                                    }
                                                } label: {
                                                    Text("Cài Key")
                                                        .font(.system(size: 10, weight: .semibold))
                                                        .foregroundStyle(TransToolsTheme.accent)
                                                        .padding(.horizontal, 6)
                                                        .padding(.vertical, 2)
                                                        .background(TransToolsTheme.accent.opacity(0.12))
                                                        .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                                                }
                                                .buttonStyle(.plain)
                                            }
                                        }
                                        .padding(9)
                                        .background(isSelected ? TransToolsTheme.accent.opacity(0.1) : Color(nsColor: .controlBackgroundColor))
                                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                                        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(isSelected ? TransToolsTheme.accent : Color.primary.opacity(0.08), lineWidth: 1.2))
                                    }
                                    .buttonStyle(.plain)

                                    // Inline Key Input Form if user clicked "Đổi Key" or "Cài Key"
                                    if editingKeyForProvider == p {
                                        VStack(alignment: .leading, spacing: 6) {
                                            HStack {
                                                Text("API Key cho \(p.displayName):")
                                                    .font(.system(size: 10.5, weight: .bold))
                                                    .foregroundStyle(.secondary)
                                                Spacer()
                                                if let url = URL(string: p.apiKeyURL), !p.apiKeyURL.isEmpty {
                                                    Link("Lấy API Key ↗", destination: url)
                                                        .font(.system(size: 10, weight: .medium))
                                                        .foregroundStyle(TransToolsTheme.accent)
                                                }
                                            }

                                            HStack(spacing: 6) {
                                                SecureField("Dán API Key vào đây...", text: $tempKeyInput)
                                                    .textFieldStyle(.roundedBorder)
                                                    .font(.system(size: 11, design: .monospaced))

                                                Button("Lưu Key") {
                                                    model.saveKeyForProvider(tempKeyInput, for: p)
                                                    withAnimation(.easeInOut(duration: 0.2)) {
                                                        editingKeyForProvider = nil
                                                    }
                                                }
                                                .buttonStyle(TransToolsActionButtonStyle(prominent: true))
                                                .controlSize(.small)
                                                .disabled(tempKeyInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                                                Button("Hủy") {
                                                    withAnimation(.easeInOut(duration: 0.2)) {
                                                        editingKeyForProvider = nil
                                                    }
                                                }
                                                .buttonStyle(TransToolsActionButtonStyle())
                                                .controlSize(.small)
                                            }
                                        }
                                        .padding(10)
                                        .background(Color(nsColor: .controlBackgroundColor))
                                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                                        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(TransToolsTheme.accent.opacity(0.3), lineWidth: 1))
                                        .padding(.leading, 34)
                                    }

                                    // Inline Model Picker & Chips for the selected provider
                                    if isSelected && hasKey {
                                        VStack(alignment: .leading, spacing: 6) {
                                            HStack(spacing: 6) {
                                                Text("Model phụ đề:")
                                                    .font(.system(size: 10, weight: .semibold))
                                                    .foregroundStyle(.secondary)

                                                Menu {
                                                    ForEach(activeModelList, id: \.self) { dm in
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
                                                    .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(Color.primary.opacity(0.12), lineWidth: 1))
                                                }
                                                .menuStyle(.borderlessButton)

                                                Button {
                                                    Task { await model.fetchModels() }
                                                } label: {
                                                    HStack(spacing: 3) {
                                                        if model.isFetchingModels {
                                                            ProgressView().controlSize(.mini)
                                                        } else {
                                                            Image(systemName: "arrow.clockwise")
                                                                .font(.system(size: 9))
                                                        }
                                                        Text(model.isFetchingModels ? "Đang tải..." : "Làm mới API")
                                                            .font(.system(size: 9, weight: .semibold))
                                                    }
                                                    .padding(.horizontal, 6)
                                                    .padding(.vertical, 3)
                                                    .background(Color.primary.opacity(0.06))
                                                    .clipShape(Capsule())
                                                }
                                                .buttonStyle(.plain)
                                                .disabled(model.isFetchingModels)
                                                .help("Tải danh sách model mới nhất từ API của \(p.displayName)")
                                                Button(model.isTestingAI ? "Đang kiểm tra…" : "Kiểm tra kết nối") {
                                                    Task { await model.testAIConnection() }
                                                }.controlSize(.small).disabled(model.isTestingAI)
                                                Spacer()
                                            }

                                            if !model.aiTestMessage.isEmpty {
                                                Text(model.aiTestMessage).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                                            }
                                            if !model.modelFetchMessage.isEmpty {
                                                Text(model.modelFetchMessage).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                                            }
                                            // Quick Model Chips
                                            ScrollView(.horizontal, showsIndicators: false) {
                                                HStack(spacing: 5) {
                                                    ForEach(activeModelList, id: \.self) { dm in
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
                                                            .overlay(Capsule().strokeBorder(isCurModel ? TransToolsTheme.accent.opacity(0.4) : Color.primary.opacity(0.08), lineWidth: 1))
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
                                            .strokeBorder(model.coPilotProvider == p ? TransToolsTheme.accent : Color.primary.opacity(0.08), lineWidth: model.coPilotProvider == p ? 1.5 : 1)
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
                                        .strokeBorder(Color.primary.opacity(0.12), lineWidth: 1)
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
                                                .strokeBorder(Color.primary.opacity(0.12), lineWidth: 1)
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
                                                        .strokeBorder(isSel ? TransToolsTheme.accent.opacity(0.4) : Color.primary.opacity(0.1), lineWidth: 1)
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
                        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(Color.primary.opacity(0.12), lineWidth: 1))
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
                        }
                        .buttonStyle(TransToolsActionButtonStyle(prominent: true))
                    }
                }
            } else if selectedTab == 2 {
                // Tab 2: System, Permissions, Launch at Login & UI
                VStack(alignment: .leading, spacing: 14) {
                    // 1. Khởi động cùng máy Mac & Quyền hệ thống
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("KHỞI ĐỘNG CÙNG MÁY MAC & QUYỀN HỆ THỐNG")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(.secondary)
                            Spacer()
                            Button {
                                model.checkAllPermissions()
                            } label: {
                                HStack(spacing: 3) {
                                    Image(systemName: "arrow.clockwise")
                                        .font(.system(size: 9))
                                    Text("Làm mới")
                                        .font(.system(size: 9.5, weight: .medium))
                                }
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(TransToolsTheme.accent)
                        }

                        // Launch at Login Toggle Card
                        VStack(alignment: .leading, spacing: 6) {
                            HStack(spacing: 10) {
                                ZStack {
                                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                                        .fill(Color.blue.opacity(0.12))
                                        .frame(width: 32, height: 32)
                                    Image(systemName: "power")
                                        .font(.system(size: 14, weight: .bold))
                                        .foregroundStyle(Color.blue)
                                }

                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Khởi động cùng máy Mac (Launch at Login)")
                                        .font(.system(size: 12, weight: .semibold))
                                    Text("Tự động mở sẵn màn hình chính (Main Dashboard) khi đăng nhập vào máy tính.")
                                        .font(.system(size: 10.5))
                                        .foregroundStyle(.secondary)
                                        .fixedSize(horizontal: false, vertical: true)
                                }

                                Spacer()

                                Toggle("", isOn: Binding(
                                    get: { model.isLaunchAtLoginEnabled },
                                    set: { model.setLaunchAtLogin(enabled: $0) }
                                ))
                                .toggleStyle(.switch)
                                .disabled(!model.hasAllEssentialPermissions)
                            }

                            if !model.hasAllEssentialPermissions {
                                HStack(spacing: 5) {
                                    Image(systemName: "exclamationmark.triangle.fill")
                                        .font(.system(size: 10))
                                        .foregroundStyle(Color.orange)
                                    Text("Cần cấp đủ 3 quyền thiết yếu bên dưới để cho phép chạy khi khởi động.")
                                        .font(.system(size: 10, weight: .medium))
                                        .foregroundStyle(Color.orange)
                                }
                                .padding(.top, 2)
                            } else {
                                HStack(spacing: 5) {
                                    Image(systemName: "checkmark.seal.fill")
                                        .font(.system(size: 10))
                                        .foregroundStyle(Color.green)
                                    Text("Đã cấp đủ quyền. Sẵn sàng khởi động tự động vào màn hình chính.")
                                        .font(.system(size: 10, weight: .medium))
                                        .foregroundStyle(Color.green)
                                }
                                .padding(.top, 2)
                            }
                        }
                        .padding(10)
                        .background(Color(nsColor: .controlBackgroundColor))
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(Color.primary.opacity(0.08), lineWidth: 1))

                        // Danh sách quyền truy cập (Permissions Checklist)
                        VStack(spacing: 5) {
                            permissionRow(
                                title: "Ghi màn hình & Âm thanh",
                                subtitle: "Thu và dịch âm thanh họp từ Zoom, Teams, Chrome",
                                icon: "display",
                                isGranted: model.hasScreenCapturePermission,
                                onRequest: { model.requestScreenCapturePermission() }
                            )

                            permissionRow(
                                title: "Microphone",
                                subtitle: "Thu âm thanh từ micro khi dịch giọng nói của bạn",
                                icon: "mic.fill",
                                isGranted: model.hasMicrophonePermission,
                                onRequest: { model.requestMicrophonePermission() }
                            )

                            permissionRow(
                                title: "Nhận diện giọng nói (Speech)",
                                subtitle: "Chuyển giọng nói cuộc họp thành phụ đề văn bản",
                                icon: "waveform.and.mic",
                                isGranted: model.hasSpeechRecognitionPermission,
                                onRequest: { model.requestSpeechRecognitionPermission() }
                            )

                            permissionRow(
                                title: "Trợ năng (Accessibility)",
                                subtitle: "Bắt phím tắt Option + D / Option + F để dịch từ bôi đen",
                                icon: "hand.raised.fill",
                                isGranted: model.hasAccessibilityPermission,
                                onRequest: { model.requestAccessibilityPermission() }
                            )
                        }
                    }

                    Divider()

                    // 2. Giao diện & Trợ lý Chip Chip
                    VStack(alignment: .leading, spacing: 10) {
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
                                Text("Trợ lý \(MascotIdentity.name) nổi trên màn hình (Thao tác & Quick Chat)")
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
                                    Text("Đưa \(MascotIdentity.name) về góc màn hình")
                                }
                                .font(.system(size: 11))
                            }
                            .buttonStyle(TransToolsActionButtonStyle())
                            .controlSize(.small)
                            .padding(.leading, 26)
                        }

                        Toggle(isOn: $model.showMascot.animation(.spring())) {
                            HStack(spacing: 8) {
                                Image(systemName: "face.smiling.fill")
                                    .font(.system(size: 13))
                                    .foregroundStyle(.orange)
                                Text("Hiển thị \(MascotIdentity.name) ở màn hình dashboard")
                                    .font(.system(size: 12))
                            }
                        }
                        .toggleStyle(.switch)

                        VStack(alignment: .leading, spacing: 4) {
                            Text("Tạo hình \(MascotIdentity.name)")
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)

                            Label("Seedly 3D · Mascot mới", systemImage: "leaf.fill")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(TransToolsTheme.accent)
                        }

                        // Nhắc nhở sức khỏe công thái học (Pomodoro Ergonomics)
                        HStack(spacing: 8) {
                            Image(systemName: "cup.and.saucer.fill")
                                .font(.system(size: 13))
                                .foregroundStyle(.teal)
                            Text("Nhắc nhở nghỉ ngơi, uống nước khi họp dài:")
                                .font(.system(size: 12))

                            Spacer()

                            Picker("", selection: $model.healthReminderMinutes) {
                                Text("Mỗi 30 phút").tag(30)
                                Text("Mỗi 45 phút (Khuyên dùng)").tag(45)
                                Text("Mỗi 60 phút").tag(60)
                                Text("Tắt nhắc nhở").tag(0)
                            }
                            .frame(width: 175)
                        }
                    }

                    Divider()

                    // 3. Dịch nhanh từ vựng toàn hệ thống
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

                                Text("Bôi đen chữ bất kỳ rồi bấm Option + D. \(MascotIdentity.name) sẽ hiện bóng thoại dịch nghĩa trên đầu và cho phép lưu vào Sổ từ vựng.")
                                    .font(.system(size: 10.5))
                                    .foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        .padding(9)
                        .background(Color(nsColor: .controlBackgroundColor))
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(Color.primary.opacity(0.08), lineWidth: 1))
                    }
                }
            } else if selectedTab == 3 {
                SettingsUpdateTabView()
            } else if selectedTab == 4 {
                SpeechSettingsView()
            }
        }
        .padding(.trailing, 2)
    }
    .frame(height: 380)
}
.padding(20)
        .frame(width: 480)
        .onAppear {
            model.checkAllPermissions()
            let key = model.coPilotKey.trimmingCharacters(in: .whitespacesAndNewlines)
            if !key.isEmpty && model.availableCoPilotModels.count <= 3 {
                Task { await model.fetchCoPilotModels() }
            }
        }
    }

    private func permissionRow(title: String, subtitle: String, icon: String, isGranted: Bool, onRequest: @escaping () -> Void) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 12))
                .foregroundStyle(isGranted ? Color.green : Color.orange)
                .frame(width: 18)

            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(size: 11, weight: .semibold))
                Text(subtitle)
                    .font(.system(size: 9.5))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            if isGranted {
                HStack(spacing: 3) {
                    Image(systemName: "checkmark.circle.fill")
                    Text("Đã cấp")
                }
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(Color.green)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.green.opacity(0.12))
                .clipShape(Capsule())
            } else {
                Button("Cấp quyền") {
                    onRequest()
                }
                .buttonStyle(TransToolsActionButtonStyle(prominent: true))
                .controlSize(.mini)
                .tint(TransToolsTheme.accent)
            }
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.6))
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
    }

    private func settingsTabButton(title: String, icon: String, tag: Int) -> some View {
        Button {
            withAnimation(.easeInOut(duration: 0.15)) {
                selectedTab = tag
            }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .medium))
                Text(title)
                    .font(.system(size: 12, weight: selectedTab == tag ? .bold : .medium))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 7)
            .background(selectedTab == tag ? TransToolsTheme.accent : Color.clear)
            .foregroundStyle(selectedTab == tag ? Color.white : Color.primary)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .shadow(color: selectedTab == tag ? TransToolsTheme.accent.opacity(0.25) : Color.clear, radius: 2, y: 1)
        }
        .buttonStyle(.plain)
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
        if lower.contains("2.5-flash") {
            return "Thế hệ mới nhất • Siêu tốc độ & thông minh"
        } else if lower.contains("2.5-pro") {
            return "Mạnh nhất của Google • Phân tích ngữ cảnh sâu"
        } else if lower.contains("2.0-flash-lite") {
            return "Cực nhẹ, tốc độ cao & tối ưu chi phí"
        } else if lower.contains("2.0-flash") {
            return "Tốc độ cao & phản xạ thông minh"
        } else if lower.contains("1.5-flash") {
            return "Bản cũ (Legacy) • Ổn định & nhẹ"
        } else if lower.contains("1.5-pro") {
            return "Bản cũ (Legacy) • Ngữ cảnh lớn"
        } else if lower.contains("4o-mini") {
            return "Tốc độ cao & chi phí tối ưu nhất"
        } else if lower.contains("4o") {
            return "Mô hình đa phương thức hàng đầu OpenAI"
        } else if lower.contains("o3-mini") {
            return "Mô hình suy luận tốc độ cao của OpenAI"
        } else if lower.contains("deepseek-chat") {
            return "Văn phong tự nhiên & chi phí cực rẻ"
        } else if lower.contains("deepseek-reasoner") {
            return "Mô hình lý luận chuyên sâu (DeepSeek-R1)"
        } else if lower.contains("3-7-sonnet") {
            return "Thế hệ mới nhất của Claude • Hybrid reasoning"
        } else if lower.contains("3-5-sonnet") {
            return "Văn phong sắc sảo, tự nhiên nhất"
        } else if lower.contains("haiku") {
            return "Phản hồi chớp mắt & siêu nhanh"
        }
        return "Mô hình ngôn ngữ AI thế hệ mới"
    }

    private func isModelRecommended(_ name: String) -> Bool {
        let lower = name.lowercased()
        return lower.contains("2.5-flash") || lower.contains("2.0-flash") || lower.contains("4o-mini") || lower.contains("deepseek-chat") || lower.contains("haiku") || lower.contains("3-7-sonnet")
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
                        Text("Trans Tools")
                            .font(.system(size: 18, weight: .bold, design: .rounded))
                        Text(appVersionDisplay)
                            .font(.system(size: 10, weight: .semibold, design: .monospaced))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(TransToolsTheme.accent.opacity(0.15))
                            .foregroundStyle(TransToolsTheme.accent)
                            .clipShape(Capsule())
                    }

                    Text("Hiểu nhau dễ hơn. Học ngôn ngữ mỗi ngày.")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }

            Text("Trans Tools đồng hành cùng bạn trong cuộc họp, đọc văn bản và luyện ngoại ngữ. Nghe và xem bản dịch, lưu điều quan trọng, rồi tiếp tục học từ những cuộc trò chuyện hằng ngày.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .lineSpacing(2)

            Divider()

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], alignment: .leading, spacing: 12) {
                aboutFeature("Cuộc họp & Phụ đề", detail: "Theo dõi hội thoại song ngữ, lưu bản ghi và việc cần làm.", icon: "waveform")
                aboutFeature("Dịch nhanh", detail: "Dịch văn bản, chỉnh ngữ pháp theo ngữ cảnh của bạn.", icon: "character.bubble")
                aboutFeature("Đọc & Học ngôn ngữ", detail: "Nghe văn bản, khám phá truyện và luyện tập mỗi ngày.", icon: "book")
                aboutFeature("Trò chuyện & Trợ lý", detail: "Luyện giao tiếp cùng AI và trợ lý cá nhân trên màn hình.", icon: "bubble.left.and.bubble.right")
            }

            DisclosureGroup("Học liệu & Nguồn phát âm") {
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        VStack(alignment: .leading, spacing: 5) {
                            Text("Tiếng Anh · AudioLang").font(.subheadline.weight(.semibold)).foregroundStyle(.primary)
                            Text("26 bản ghi tên chữ A–Z, tải riêng để nghe offline; giữ tốc độ gốc. Chưa phân loại giọng Anh–Anh / Anh–Mỹ. Chọn US/UK chỉ thay phiên âm, không thay bản ghi.")
                            Link("Nguồn gốc: Bảng chữ cái tiếng Anh ↗", destination: URL(string: "http://audiolang.info/vi/english-alphabet/")!)
                        }
                        Divider()
                        VStack(alignment: .leading, spacing: 5) {
                            Text("Tiếng Nhật · NHK WORLD-JAPAN").font(.subheadline.weight(.semibold)).foregroundStyle(.primary)
                            Text("104 bản ghi âm Kana và 208 ảnh hướng dẫn thứ tự nét tải riêng trên máy. Hiragana/Katakana dùng chung âm tương ứng; ảnh nét riêng cho mỗi bảng chữ. Bản ghi từ minh họa còn thiếu sẽ không được thay bằng giọng hệ thống.")
                            Link("Nguồn gốc: Hiragana · âm đọc và nét viết ↗", destination: JapaneseNHKData.nhkHiraganaURL)
                            Link("Nguồn gốc: Katakana · âm đọc và nét viết ↗", destination: JapaneseNHKData.nhkKatakanaURL)
                        }
                        Divider()
                        VStack(alignment: .leading, spacing: 5) {
                            Text("Tiếng Trung · ZIM Academy").font(.subheadline.weight(.semibold)).foregroundStyle(.primary)
                            Text("Hướng dẫn khẩu hình, Pinyin và ví dụ tham khảo từ bài gốc. Đã tải 123 mục MP3 thanh mẫu, vận mẫu và từ minh họa để nghe offline, giữ nguyên file nguồn. Có bản ghi cho 44/46 âm trong bảng hiện tại; y/w, một số ví dụ và thanh điệu chưa đủ dữ liệu.")
                            Link("Nguồn gốc: Bảng phiên âm Pinyin và cách phát âm ↗", destination: ChinesePinyinData.zimPinyinURL)
                        }
                        Divider()
                        Text("Các file tải riêng trên máy không kèm trong bản phát hành. Nguồn và tác quyền thuộc đơn vị cung cấp; bản ghi chưa được giáo viên thẩm định độc lập trong TransTools.")
                    }.font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                }.frame(maxHeight: 320).padding(.top, 8)
            }

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
                Label("Offline & AI trực tuyến", systemImage: "sparkles")
                Label("Trợ lý \(MascotIdentity.name)", systemImage: "face.smiling.fill")
                Label("Phụ đề nổi", systemImage: "pip.fill")
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
                .buttonStyle(TransToolsActionButtonStyle(height: 36))
            }
        }
        .padding(24)
        .frame(width: 600)
        .background(TransToolsTheme.mint)
    }

    private func aboutFeature(_ title: String, detail: String, icon: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(title, systemImage: icon).font(.system(size: 12, weight: .semibold)).foregroundStyle(TransToolsTheme.accent)
            Text(detail).font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }.frame(maxWidth: .infinity, minHeight: 66, alignment: .topLeading).padding(12).transToolsPanel()
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
                }
            }
        }
        .defaultSize(width: 1160, height: 740)
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandGroup(replacing: .appInfo) {
                Button("Giới thiệu Trans Tools") { model.showMainWindow(); model.showAboutSheet = true }
            }
            MascotSpriteCommands()
            CommandMenu("Cuộc họp") {
                Button("Mở trợ lý trong phụ đề") { model.showAssistantInSubtitles() }
                    .keyboardShortcut("u", modifiers: [.command, .shift])
                Button("Mở bảng trợ giúp cuộc họp") { model.showMeetingAssistBoard() }
                    .keyboardShortcut("j", modifiers: [.command, .shift])
                Divider()
                Button(model.recognitionTraceEnabled ? "Tắt nhật ký kiểm thử nhận dạng" : "Bật nhật ký kiểm thử nhận dạng…") {
                    model.toggleRecognitionTrace()
                }
                .disabled(model.running && !model.recognitionTraceEnabled)
                Button("Xem file nhật ký kiểm thử") { model.revealRecognitionTrace() }
                    .disabled(!model.recognitionTraceEnabled && model.recognitionTraceURL == nil)
            }
            CommandMenu("Dịch & chỉnh câu") {
                Button("Dịch từ bôi đen · Option + D") {
                    Task { await GlobalHotkeyManager.shared.triggerSelectionTranslation() }
                }
                Button("Chụp & Dịch màn hình (OCR) · Option + S") {
                    ScreenOCRService.shared.triggerScreenOCRTranslation()
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

// A hover-only greeting keeps the dashboard still while nobody interacts.
private struct HoverGreetingMascotView: View {
    let style: String
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hovered = false

    var body: some View {
        MiniAvatarView(size: 110, style: style)
            .rotationEffect(.degrees(hovered && !reduceMotion ? 5 : 0), anchor: .bottom)
            .offset(y: hovered && !reduceMotion ? -5 : 0)
            .scaleEffect(hovered && !reduceMotion ? 1.04 : 1)
            .animation(hovered && !reduceMotion
                ? .easeInOut(duration: 0.65).repeatForever(autoreverses: true)
                : .easeOut(duration: 0.2), value: hovered)
            .contentShape(Rectangle())
            .onHover { hovered = $0 }
            .onDisappear { hovered = false }
            .accessibilityLabel("\(MascotIdentity.name)")
    }
}
