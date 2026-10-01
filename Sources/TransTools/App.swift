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
    return "v1.2.0"
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

@MainActor final class MeetingModel: ObservableObject {
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
    @Published var mascotStyle: String = UserDefaults.standard.string(forKey: "MascotStyle") ?? "3d" {
        didSet {
            UserDefaults.standard.set(mascotStyle, forKey: "MascotStyle")
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

    // Multi-Language Support (EN, VI, ZH, JA, KO, FR, DE, ES)
    @Published var sourceLanguage: AppLanguage = {
        let saved = UserDefaults.standard.string(forKey: "SourceLanguage") ?? "en"
        return AppLanguage(rawValue: saved) ?? .english
    }() {
        didSet {
            UserDefaults.standard.set(sourceLanguage.rawValue, forKey: "SourceLanguage")
        }
    }

    @Published var targetLanguage: AppLanguage = {
        let saved = UserDefaults.standard.string(forKey: "TargetLanguage") ?? "vi"
        return AppLanguage(rawValue: saved) ?? .vietnamese
    }() {
        didSet {
            UserDefaults.standard.set(targetLanguage.rawValue, forKey: "TargetLanguage")
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
    private var currentID = UUID()
    private var started = Date()
    private var translationTask: Task<Void, Never>?
    private var rotationTask: Task<Void, Never>?
    private var session = UUID()
    private var activeKey = ""
    private var overlay: NSWindow?

    @Published var selectedDashboardTab: Int = 0
    @Published var showSettingsSheet: Bool = false
    @Published var showAboutSheet: Bool = false
    @Published var isOverlayVisible: Bool = false

    init() {
        // 1. Subtitle Translation Engine: Default to Apple Native (On-Device, 0 token, ~15ms)
        let savedProviderRaw = UserDefaults.standard.string(forKey: "AIProvider") ?? "apple"
        let initialProvider = AIProvider(rawValue: savedProviderRaw) ?? .apple
        self.provider = initialProvider
        self.key = CredentialStore.read(for: initialProvider)
        let savedModel = UserDefaults.standard.string(forKey: "AIModel_\(initialProvider.rawValue)") ?? initialProvider.defaultModel
        self.modelName = savedModel
        self.availableModels = initialProvider.defaultModels

        // 2. AI Meeting Co-Pilot (Phân tích & gợi ý câu trả lời): Default to Gemini / Cloud AI
        let savedCoPilotRaw = UserDefaults.standard.string(forKey: "AICoPilotProvider") ?? "gemini"
        let initialCoPilot = AIProvider(rawValue: savedCoPilotRaw) ?? .gemini
        self.coPilotProvider = initialCoPilot
        self.coPilotKey = CredentialStore.read(for: initialCoPilot)
        self.coPilotModel = UserDefaults.standard.string(forKey: "AICoPilotModel_\(initialCoPilot.rawValue)") ?? initialCoPilot.defaultModel
        self.availableCoPilotModels = initialCoPilot.defaultModels

        capture.onAudio = { [weak self] sample in
            self?.speech.append(sample)
            Task { @MainActor [weak self] in self?.lastAudio = Date() }
        }
        capture.onMicrophone = { [weak self] buffer in
            self?.speech.append(buffer)
            Task { @MainActor [weak self] in self?.lastAudio = Date() }
        }
        capture.onError = { [weak self] error in
            Task { @MainActor in await self?.fail(error) }
        }
        speech.onResult = { [weak self] text, final in
            Task { @MainActor in self?.receive(text, final: final) }
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

    func openScreenCaptureSettings() {
        triggerScreenCapturePrompt()
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
            NSWorkspace.shared.open(url)
        }
        let appURL = Bundle.main.bundleURL
        NSWorkspace.shared.activateFileViewerSelecting([appURL])
    }

    func refresh() async {
        let hasAccess = CGPreflightScreenCaptureAccess()
        if hasAccess {
            if warning.localizedCaseInsensitiveContains("TCC") || warning.localizedCaseInsensitiveContains("màn hình") {
                warning = ""
            }
        }
        do {
            let apps = try await capture.applications()
            self.applications = apps
            if source.isEmpty {
                if let teams = apps.first(where: { $0.bundleIdentifier.localizedCaseInsensitiveContains("teams") }) {
                    source = teams.bundleIdentifier
                } else {
                    source = "system"
                }
            }
            if warning.localizedCaseInsensitiveContains("TCC") || warning.localizedCaseInsensitiveContains("màn hình") {
                warning = ""
            }
        } catch {
            let msg = error.localizedDescription
            if msg.localizedCaseInsensitiveContains("TCC") || msg.localizedCaseInsensitiveContains("declined") || !hasAccess {
                warning = "Chưa cấp quyền Ghi màn hình & Âm thanh hệ thống. Hãy cấp quyền trong Cài đặt hệ thống."
            } else {
                warning = "Không lấy được danh sách ứng dụng: \(msg)"
            }
            if source.isEmpty {
                source = "system"
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
            status = (provider == .free || activeKey.isEmpty) ? "Đang nghe \(sourceLanguage.displayName) và dịch sang \(targetLanguage.displayName) (Google Free • 0 token)" : "Đang nghe \(sourceLanguage.displayName) và dịch sang \(targetLanguage.displayName) (\(provider.shortName) • \(modelName))"
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
        busy = true; warning = ""; defer { busy = false }
        let authorized = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0 == .authorized) }
        }
        guard authorized else { warning = "Cần quyền Speech Recognition trong System Settings → Privacy & Security."; return }
        do {
            if source == "microphone" {
                let allowed = await AVCaptureDevice.requestAccess(for: .audio)
                guard allowed else { warning = "Cần cấp quyền Microphone."; return }
            } else if source.isEmpty { warning = "Hãy chọn nguồn âm thanh."; return }
            activeKey = key.trimmingCharacters(in: .whitespacesAndNewlines)
            started = Date(); captions = []; translatedOriginal = [:]; currentID = UUID(); lastAudio = nil; session = UUID()
            lastRawRecognizedText = ""
            sessionFinalizedWordsCount = 0
            recognitionSessionStarted = Date()
            try speech.start(localeIdentifier: sourceLanguage.speechLocale)
            running = true
            if source == "microphone" { try capture.startMicrophone() }
            else if source == "system" { try await capture.startSystemAudio() }
            else { try await capture.start(applicationID: source) }
            status = (provider == .free || activeKey.isEmpty) ? "Đang nghe \(sourceLanguage.displayName) và dịch sang \(targetLanguage.displayName) (Google Free • 0 token)" : "Đang nghe \(sourceLanguage.displayName) và dịch sang \(targetLanguage.displayName) (\(provider.shortName) • \(modelName))"
        } catch { await fail(error) }
    }

    func stop() async {
        running = false; session = UUID()
        sessionFinalizedWordsCount = 0
        lastRawRecognizedText = ""
        rotationTask?.cancel(); rotationTask = nil
        translationTask?.cancel(); translationTask = nil
        speech.stop()
        await capture.stop()
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
        } else {
            warning = msg
        }
    }

    private var sessionFinalizedWordsCount: Int = 0
    private var lastRawRecognizedText: String = ""
    private var recognitionSessionStarted: Date = Date()

    private func receive(_ text: String, final: Bool) {
        guard running else { return }
        let trimmedRaw = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedRaw.isEmpty else { return }
        let elapsed = Date().timeIntervalSince(started)

        let allWords = trimmedRaw.components(separatedBy: .whitespaces).filter { !$0.isEmpty }

        // 1. Detect if speech recognizer reset/flushed its internal buffer:
        if allWords.count < sessionFinalizedWordsCount {
            sessionFinalizedWordsCount = 0
        }

        // 2. Extract only the unfinalized words from the current cumulative stream:
        let activeWords = Array(allWords.dropFirst(min(sessionFinalizedWordsCount, allWords.count)))
        let currentText = activeWords.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !currentText.isEmpty else { return }

        lastRawRecognizedText = trimmedRaw

        // 3. Update or append the current live caption
        if let index = captions.firstIndex(where: { $0.id == currentID }) {
            captions[index].original = currentText
            captions[index].end = elapsed
        } else {
            // Guard against duplicate card: never append if previous caption already has the same text
            if let last = captions.last, last.original == currentText {
                return
            }
            captions.append(Caption(id: currentID, start: elapsed, end: elapsed, original: currentText))
        }

        // 4. Smart Sentence Splitting & Chunking:
        let hasSentencePunctuation = currentText.hasSuffix(".") || currentText.hasSuffix("?") || currentText.hasSuffix("!") || currentText.hasSuffix("...")
        let isLongChunk = activeWords.count >= 20

        if final {
            // Utterance finalized by speech recognizer
            finalizeCurrentCaption(immediateTranslation: true)
            sessionFinalizedWordsCount = 0
            currentID = UUID()
            if Date().timeIntervalSince(recognitionSessionStarted) > 55 {
                recognitionSessionStarted = Date()
                do { try speech.start(localeIdentifier: sourceLanguage.speechLocale) } catch { Task { await fail(error) } }
            }
        } else if hasSentencePunctuation && activeWords.count >= 5 {
            // Natural sentence boundary reached
            sessionFinalizedWordsCount += activeWords.count
            finalizeCurrentCaption(immediateTranslation: true)
            currentID = UUID()
        } else if isLongChunk {
            // Subtitle reached maximum comfortable reading length (~18-20 words).
            // Search backward for natural comma/pause to make the cut clean and grammatically sound.
            var splitIndex = 18
            for i in stride(from: min(activeWords.count - 2, 20), through: 12, by: -1) {
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
            sessionFinalizedWordsCount += splitIndex
            finalizeCurrentCaption(immediateTranslation: true)
            currentID = UUID()

            // Carry remaining words into the new live caption card immediately
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
        scheduleTranslation(id: row.id, text: row.original, immediate: immediateTranslation)
        generateSuggestions(for: row.original)
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
        if immediate {
            translationTask?.cancel()
            translationTask = nil
        }
        guard translationTask == nil else { return }
        let token = session
        let currentProvider = provider
        let currentModel = modelName
        let currentKey = activeKey
        translationTask = Task { [weak self] in
            guard let self else { return }
            defer { self.translationTask = nil }
            while !Task.isCancelled, self.running, self.session == token {
                // Find next caption needing translation
                guard let row = self.captions.first(where: { self.translatedOriginal[$0.id] != $0.original && !$0.original.isEmpty }) else { break }

                let isCurrentLiveRow = (row.id == self.currentID)
                if isCurrentLiveRow && !immediate {
                    let debounceMs = (currentProvider == .apple) ? 400 : ((currentProvider == .free || currentKey.isEmpty) ? 500 : 700)
                    try? await Task.sleep(for: .milliseconds(debounceMs))
                    guard !Task.isCancelled, self.session == token else { return }
                }

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
    private var translatedOriginal: [UUID: String] = [:]

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
        case "": return "Hệ thống"
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
    var mascotWindow: NSWindow?

    func convenientMascotRect() -> NSRect {
        let mascotWidth: CGFloat = 106
        let mascotHeight: CGFloat = 126

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
            if !isVisibleOnScreen {
                mascotWindow.setFrame(convenient, display: true)
            } else if mascotWindow.frame.size.height < 120 {
                var f = mascotWindow.frame
                f.size = convenient.size
                mascotWindow.setFrame(f, display: true)
            }
            mascotWindow.orderFrontRegardless()
            isFloatingMascotVisible = true
            UserDefaults.standard.set(true, forKey: "FloatingMascotEnabled")
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
        ) { [weak panel] _ in
            guard let origin = panel?.frame.origin else { return }
            UserDefaults.standard.set(Double(origin.x), forKey: "FloatingMascotX")
            UserDefaults.standard.set(Double(origin.y), forKey: "FloatingMascotY")
        }

        mascotWindow = panel
        panel.orderFrontRegardless()
        isFloatingMascotVisible = true
        UserDefaults.standard.set(true, forKey: "FloatingMascotEnabled")
    }

    func hideFloatingMascot() {
        mascotWindow?.orderOut(nil)
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
    @State private var config: TranslationSession.Configuration?

    var body: some View {
        content()
            .translationTask(config) { session in
                AppleNativeTranslator.session = session
            }
            .onAppear {
                updateConfig()
            }
            .onChange(of: source) { _ in updateConfig() }
            .onChange(of: target) { _ in updateConfig() }
    }

    private func updateConfig() {
        config = TranslationSession.Configuration(
            source: Locale.Language(identifier: source.appleLanguageCode),
            target: Locale.Language(identifier: target.appleLanguageCode)
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

                        Text("• \(model.provider.shortName)")
                            .font(.system(size: 9, weight: .medium))
                            .foregroundStyle(isDark ? Color.white.opacity(0.55) : Color.black.opacity(0.55))

                        Text("• \(model.domainSpecialty.shortName)")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(Color.accentColor)
                    }
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2.5)
                    .background(
                        Capsule()
                            .fill(isDark ? Color.white.opacity(0.08) : Color.black.opacity(0.06))
                    )

                    Spacer()

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
                        .foregroundStyle(Color.accentColor)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(
                            RoundedRectangle(cornerRadius: 4, style: .continuous)
                                .fill(Color.accentColor.opacity(0.12))
                        )
                    }
                    .buttonStyle(.plain)
                    .help("AI gợi ý câu trả lời tiếng Anh cho hội thoại này")

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

                    // Quick Copy Button
                    if let row = model.captions.last, !row.vietnamese.isEmpty {
                        Button {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(row.vietnamese, forType: .string)
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
                        .help("Sao chép bản dịch hiện tại")
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
                                // Previous sentence preview for reading continuity (dimmed)
                                if model.captions.count >= 2 {
                                    let prev = model.captions[model.captions.count - 2]
                                    if !prev.vietnamese.isEmpty || !prev.original.isEmpty {
                                        VStack(alignment: .leading, spacing: 1) {
                                            if !prev.original.isEmpty {
                                                Text(prev.original)
                                                    .font(.system(size: max(10, fontSize - 4), weight: .regular))
                                                    .foregroundStyle(isDark ? Color.white.opacity(0.38) : Color.black.opacity(0.38))
                                                    .fixedSize(horizontal: false, vertical: true)
                                            }
                                            Text(prev.vietnamese.isEmpty ? prev.original : prev.vietnamese)
                                                .font(.system(size: max(11, fontSize - 3), weight: .medium, design: .rounded))
                                                .foregroundStyle(isDark ? Color.white.opacity(0.52) : Color.black.opacity(0.50))
                                                .fixedSize(horizontal: false, vertical: true)
                                        }
                                        .padding(.bottom, 1)

                                        Divider()
                                            .opacity(isDark ? 0.15 : 0.12)
                                    }
                                }

                                // Active sentence: full multi-line wrapping without cutoffs
                                if let row = model.captions.last {
                                    VStack(alignment: .leading, spacing: 3) {
                                        // Original English text
                                        if !row.original.isEmpty {
                                            Text(row.original)
                                                .font(.system(size: max(11, fontSize - 3), weight: .regular))
                                                .foregroundStyle(isDark ? Color.white.opacity(0.72) : Color(red: 0.22, green: 0.25, blue: 0.32))
                                                .fixedSize(horizontal: false, vertical: true)
                                        }

                                        // Vietnamese translation (crystal-sharp adaptive gradient, NO text shadow)
                                        Text(row.vietnamese.isEmpty ? "Đang dịch…" : row.vietnamese)
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
                                    .padding(.vertical, 2)
                                    .overlay(alignment: .topTrailing) {
                                        if hoveredRowID == row.id {
                                            HStack(spacing: 3) {
                                                Button {
                                                    NSPasteboard.general.clearContents()
                                                    NSPasteboard.general.setString(row.vietnamese, forType: .string)
                                                    copiedReplyText = "VI"
                                                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { copiedReplyText = "" }
                                                } label: {
                                                    HStack(spacing: 2) {
                                                        Image(systemName: copiedReplyText == "VI" ? "checkmark" : "doc.on.doc")
                                                        Text("VI")
                                                    }
                                                    .font(.system(size: 8.5, weight: .bold))
                                                    .padding(.horizontal, 5)
                                                    .padding(.vertical, 2)
                                                    .background(isDark ? Color.black.opacity(0.8) : Color.white.opacity(0.9))
                                                    .clipShape(Capsule())
                                                }
                                                .buttonStyle(.plain)
                                                .help("Sao chép bản dịch tiếng Việt")

                                                Button {
                                                    NSPasteboard.general.clearContents()
                                                    NSPasteboard.general.setString(row.original, forType: .string)
                                                    copiedReplyText = "EN"
                                                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { copiedReplyText = "" }
                                                } label: {
                                                    HStack(spacing: 2) {
                                                        Image(systemName: copiedReplyText == "EN" ? "checkmark" : "doc.on.doc")
                                                        Text("EN")
                                                    }
                                                    .font(.system(size: 8.5, weight: .bold))
                                                    .padding(.horizontal, 5)
                                                    .padding(.vertical, 2)
                                                    .background(isDark ? Color.black.opacity(0.8) : Color.white.opacity(0.9))
                                                    .clipShape(Capsule())
                                                }
                                                .buttonStyle(.plain)
                                                .help("Sao chép câu tiếng Anh gốc")

                                                Button {
                                                    model.generateSuggestions(for: row.original)
                                                } label: {
                                                    HStack(spacing: 2) {
                                                        Image(systemName: "sparkles")
                                                        Text("Gợi ý")
                                                    }
                                                    .font(.system(size: 8.5, weight: .bold))
                                                    .foregroundStyle(Color.accentColor)
                                                    .padding(.horizontal, 5)
                                                    .padding(.vertical, 2)
                                                    .background(isDark ? Color.black.opacity(0.8) : Color.white.opacity(0.9))
                                                    .clipShape(Capsule())
                                                }
                                                .buttonStyle(.plain)
                                                .help("Gợi ý câu trả lời tiếng Anh cho câu này")
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
                                                .foregroundStyle(Color.accentColor)
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
                                                                .foregroundStyle(Color.accentColor)

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
                        .onChange(of: model.captions.count) { _ in
                            withAnimation(.easeOut(duration: 0.2)) {
                                proxy.scrollTo("BOTTOM", anchor: .bottom)
                            }
                        }
                        .onChange(of: model.captions.last?.vietnamese) { _ in
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
                            colors: [Color.blue, Color.purple],
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

    var body: some View {
        let w = size * (621.0 / 783.0)
        let h = size
        let eyeD = h * 0.165
        let leftEyeCenter = CGPoint(x: w * 0.362, y: h * 0.408)
        let rightEyeCenter = CGPoint(x: w * 0.638, y: h * 0.408)
        let leftCheekCenter = CGPoint(x: w * 0.245, y: h * 0.495)
        let rightCheekCenter = CGPoint(x: w * 0.755, y: h * 0.495)
        let cheekW = h * 0.13
        let cheekH = h * 0.055

        ZStack {
            // 1. Left Eye
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
                }
            }
            .position(leftEyeCenter)

            // 2. Right Eye
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
                }
            }
            .position(rightEyeCenter)

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

// MARK: - Mimo Companion Avatar View

struct MiniAvatarView: View {
    let size: CGFloat
    var style: String? = nil
    var isWorking: Bool = false
    var expression: MascotExpression? = nil
    var isHovered: Bool? = nil

    @State private var internalHovered = false
    @State private var internalExpression: MascotExpression = .winkLeft
    @AppStorage("MascotStyle") private var savedStyle: String = "3d"

    private var activeStyle: String {
        style ?? savedStyle
    }

    private var activeHovered: Bool {
        isHovered ?? internalHovered
    }

    private var activeExpression: MascotExpression {
        expression ?? internalExpression
    }

    private var showOverlay: Bool {
        (!isWorking && activeStyle != "pixel") && activeHovered
    }

    var body: some View {
        let isPixel = (activeStyle == "pixel")
        let preferredResource = isPixel ? "Mini" : (isWorking ? "MascotWriting" : "Mascot3D")
        let fallbackResource = isWorking ? "Mascot3D" : (isPixel ? "Mascot3D" : "Mini")

        ZStack {
            if let path = Bundle.main.path(forResource: preferredResource, ofType: "png") ?? Bundle.main.path(forResource: fallbackResource, ofType: "png"),
               let nsImage = NSImage(contentsOfFile: path) {
                Image(nsImage: nsImage)
                    .interpolation(isPixel ? .none : .high)
                    .resizable()
                    .scaledToFit()
                    .frame(height: size)
            } else {
                AppLogoView(size: size)
            }

            // Eye winking overlay khi rê chuột tương tác (KHÔNG chớp mắt tự động khi IDLE để hình luôn mượt mà, không giật)
            if showOverlay {
                MascotFacialExpressionOverlay(size: size, expression: activeExpression)
                    .transition(.opacity.combined(with: .scale(scale: 0.96)))
            }
        }
        .scaleEffect(activeHovered ? 1.05 : 1.0)
        .animation(.spring(response: 0.35, dampingFraction: 0.65), value: activeHovered)
        .onHover { hovering in
            if isHovered == nil {
                internalHovered = hovering
                if hovering && !isWorking {
                    let candidates: [MascotExpression] = [.winkLeft, .winkRight, .happySmile, .happySquint]
                    internalExpression = candidates.filter { $0 != internalExpression }.randomElement() ?? .winkLeft
                }
            }
        }
        .onChange(of: activeHovered) { isHov in
            if isHov && !isWorking {
                let candidates: [MascotExpression] = [.winkLeft, .winkRight, .happySmile, .happySquint]
                internalExpression = candidates.filter { $0 != internalExpression }.randomElement() ?? .winkLeft
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

// MARK: - Floating Mimo Assistant Widget

struct FloatingMascotView: View {
    @ObservedObject var model: MeetingModel
    @State private var isHovered = false
    @State private var showQuickMenu = false

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { context in
            let time = context.date.timeIntervalSinceReferenceDate
            let isHearingSpeech = (Date().timeIntervalSince(model.lastAudio ?? .distantPast) < 1.8)
            let speed: Double = isHearingSpeech ? 1.4 : 1.0

            // 1. Continuous handwriting stroke oscillation
            let strokeX: CGFloat = model.running ? CGFloat(sin(time * 10.0 * speed) * 3.5) : 0
            let strokeY: CGFloat = model.running ? CGFloat(cos(time * 10.0 * speed) * 1.8) : 0
            let penAngle: Double = model.running ? (sin(time * 10.0 * speed) * 14.0) : 0

            // 2. Gentle hopping when hovered (nhảy nhảy nhẹ nhàng, nhịp nhàng vui tươi khi rê chuột)
            let hopProgress: CGFloat = isHovered ? CGFloat(abs(sin(time * 6.0))) : 0
            let hopY: CGFloat = isHovered ? -hopProgress * 8.0 : 0
            let hopTilt: Double = isHovered ? (sin(time * 6.0) * 2.8) : 0
            let hoverSquashX: CGFloat = isHovered ? (1.0 + (1.0 - hopProgress) * 0.05 - hopProgress * 0.02) : 1.0
            let hoverSquashY: CGFloat = isHovered ? (1.0 - (1.0 - hopProgress) * 0.05 + hopProgress * 0.03) : 1.0

            // 3. Smooth, gentle ambient breathing & floating in IDLE (Hành động thở & bồng bềnh êm ái khi nghỉ ngơi, KHÔNG giật)
            // Chu kỳ thở chậm rãi ~4.2s, biên độ 1.8pt vừa phải để tạo cảm giác sống động nhưng thư thái
            let idleCycle = sin(time * 1.5)
            let idleFloatingY: CGFloat = CGFloat(idleCycle * 1.8)
            let idleTilt: Double = sin(time * 0.75) * 1.2
            let idleSquashX: CGFloat = CGFloat(1.0 - idleCycle * 0.012)
            let idleSquashY: CGFloat = CGFloat(1.0 + idleCycle * 0.018)

            // 4. Mascot subtle breathing and writing body sway khi làm việc
            let writingBobY: CGFloat = model.running ? CGFloat(sin(time * 4.5 * speed) * 1.2) : 0
            let writingTilt: Double = model.running ? (sin(time * 4.5 * speed) * 1.8) : 0

            let totalBobY: CGFloat = model.running ? writingBobY : (isHovered ? hopY : idleFloatingY)
            let totalTilt: Double = model.running ? writingTilt : (isHovered ? hopTilt : idleTilt)
            let totalSquashX: CGFloat = isHovered ? hoverSquashX : (model.running ? 1.0 : idleSquashX)
            let totalSquashY: CGFloat = isHovered ? hoverSquashY : (model.running ? 1.0 : idleSquashY)

            // Đổ bóng mềm mại thay đổi nhịp nhàng theo độ nổi
            let shadowRad: CGFloat = isHovered
                ? (3.5 + hopProgress * 3.5)
                : (model.running ? 3.0 : CGFloat(2.8 + (idleCycle + 1.0) * 0.5))
            let shadowOffsetY: CGFloat = isHovered
                ? (2.5 + hopProgress * 4.0)
                : (model.running ? 2.0 : CGFloat(2.0 + (idleCycle + 1.0) * 0.4))
            let shadowAlpha: Double = isHovered
                ? (0.30 - Double(hopProgress) * 0.10)
                : (model.running ? 0.22 : (0.22 - idleCycle * 0.03))

            // Floating note ink sparkles (2 alternating cycles)
            let sparkPhase1 = fmod(time * 1.3, 1.0)
            let sparkPhase2 = fmod((time * 1.3) + 0.5, 1.0)

            ZStack(alignment: .topTrailing) {
                ZStack(alignment: .bottomTrailing) {
                    // Mimo Companion Avatar: Switch to active note-taking with pen on paper
                    MiniAvatarView(
                        size: model.mascotStyle == "pixel" ? 64 : 80,
                        style: model.mascotStyle,
                        isWorking: model.running,
                        isHovered: isHovered
                    )
                    .scaleEffect(x: (isHovered ? 1.06 : 1.0) * totalSquashX, y: (isHovered ? 1.06 : 1.0) * totalSquashY, anchor: .bottom)
                    .offset(x: 0, y: totalBobY)
                    .rotationEffect(.degrees(totalTilt), anchor: .bottom)
                    .shadow(
                        color: Color.black.opacity(shadowAlpha),
                        radius: shadowRad,
                        y: shadowOffsetY
                    )
                    .animation(.spring(response: 0.35, dampingFraction: 0.65), value: isHovered)
                    .animation(.spring(response: 0.35, dampingFraction: 0.75), value: model.running)

                    // Lively Writing Pencil & Scribble Note Effects (Only when actively recording/translating)
                    if model.running {
                        // Notebook written ink lines on paper
                        VStack(alignment: .leading, spacing: 2.2) {
                            Capsule()
                                .fill(Color.accentColor.opacity(0.85))
                                .frame(width: max(4, min(14, 8 + strokeX * 1.2)), height: 1.8)
                            Capsule()
                                .fill(Color.accentColor.opacity(0.65))
                                .frame(width: max(3, min(16, 11 - strokeX * 0.9)), height: 1.8)
                        }
                        .offset(x: -12, y: -22)

                        // Stylus/Pen dipping and writing cursive strokes
                        Image(systemName: "pencil")
                            .font(.system(size: 13, weight: .black))
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
                            .rotationEffect(.degrees(-35 + penAngle), anchor: .bottomLeading)
                            .offset(x: -12 + strokeX, y: -25 + strokeY)
                            .shadow(color: Color.orange.opacity(0.55), radius: 2, y: 1)

                        // Floating ink sparkle 1
                        Image(systemName: "sparkle")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(Color(red: 0.20, green: 0.88, blue: 0.98))
                            .offset(x: -18 - CGFloat(sparkPhase1 * 8), y: -30 - CGFloat(sparkPhase1 * 18))
                            .opacity(sin(sparkPhase1 * .pi) * 0.9)
                            .scaleEffect(CGFloat(0.6 + sparkPhase1 * 0.5))

                        // Floating mini note dot 2
                        Circle()
                            .fill(Color(red: 1.0, green: 0.75, blue: 0.2))
                            .frame(width: 3.5, height: 3.5)
                            .offset(x: -8 - CGFloat(sparkPhase2 * 10), y: -28 - CGFloat(sparkPhase2 * 16))
                            .opacity(sin(sparkPhase2 * .pi) * 0.8)
                    }
                }
                .frame(width: 86, height: 104, alignment: .bottom)
                .padding(.top, 14) // Tăng view top để khi Mimo nhảy lên không bị cắt đỉnh đầu!

                // Mini Status Indicator Dot (Chỉ hiện khi có action Viết hoặc Suy nghĩ/Xử lý, ẩn khi bình thường)
                if model.running || model.busy {
                    ZStack {
                        Circle()
                            .fill(
                                model.busy
                                    ? LinearGradient(colors: [Color.purple, Color.cyan], startPoint: .topLeading, endPoint: .bottomTrailing)
                                    : LinearGradient(colors: [Color.green, Color.teal], startPoint: .topLeading, endPoint: .bottomTrailing)
                            )
                            .frame(width: 15, height: 15)
                            .overlay(Circle().stroke(Color.white, lineWidth: 1.8))
                            .shadow(color: (model.busy ? Color.purple : Color.green).opacity(0.65), radius: 3)

                        Image(systemName: model.busy ? "ellipsis" : "pencil.and.scribble")
                            .font(.system(size: model.busy ? 7 : 6.5, weight: .black))
                            .foregroundStyle(.white)
                    }
                    .offset(x: 2, y: 12)
                    .transition(.scale(scale: 0.5).combined(with: .opacity))
                    .animation(.spring(response: 0.35, dampingFraction: 0.7), value: model.busy)
                    .animation(.spring(response: 0.35, dampingFraction: 0.7), value: model.running)
                }
            }
            .frame(width: 100, height: 122, alignment: .bottom)
            .contentShape(Rectangle())
            .onHover { hovering in
                isHovered = hovering
            }
            .onTapGesture {
                showQuickMenu.toggle()
            }
            .popover(isPresented: $showQuickMenu, arrowEdge: .leading) {
                MascotQuickActionsPopover(model: model, isPresented: $showQuickMenu)
            }
            .contextMenu {
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

                Button {
                    model.snapMascotToConvenientPosition()
                } label: {
                    Label("Đưa Chip Chip về góc màn hình", systemImage: "arrow.down.forward.and.arrow.up.backward")
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
                    Label("Tạm biệt Chip Chip (Ẩn)", systemImage: "xmark")
                }
            }
            .help("Chip Chip: Bấm để trò chuyện & thao tác nhanh, kéo để dạo chơi trên màn hình!")
        }
    }
}

struct MascotQuickActionsPopover: View {
    @ObservedObject var model: MeetingModel
    @Binding var isPresented: Bool
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
        return mimoQuotes[tipIndex % mimoQuotes.count]
    }

    private func translateAndCopyQuickText() {
        let trimmed = quickViText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        isTranslatingQuick = true
        Task {
            do {
                let res = try await AITranslator.quickTranslateDetailed(
                    trimmed,
                    from: .vietnamese,
                    to: .english,
                    domain: model.domainSpecialty,
                    provider: model.provider,
                    model: model.modelName,
                    key: model.key
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
                                colors: [Color.blue.opacity(0.18), Color.purple.opacity(0.10)],
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
                        Text(model.mascotStyle == "pixel" ? "Pixel" : "3D AI")
                            .font(.system(size: 9.5, weight: .semibold))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1.5)
                            .background(Color.primary.opacity(0.06))
                            .foregroundStyle(.secondary)
                            .clipShape(Capsule())
                    }

                    HStack(spacing: 4) {
                        Circle()
                            .fill(model.running ? Color.green : Color.blue)
                            .frame(width: 6, height: 6)
                        Text(model.running ? "Đang lắng nghe • \(model.provider.shortName)" : "Sẵn sàng • Nghỉ ngơi")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(model.running ? Color.green : Color.secondary)
                    }
                }

                Spacer()

                Button {
                    withAnimation(.spring(response: 0.35)) {
                        model.mascotStyle = (model.mascotStyle == "3d") ? "pixel" : "3d"
                    }
                } label: {
                    Image(systemName: model.mascotStyle == "3d" ? "cube.transparent" : "checkerboard.rectangle")
                        .font(.system(size: 12, weight: .medium))
                        .padding(6)
                        .background(Color(nsColor: .controlBackgroundColor))
                        .foregroundStyle(Color.accentColor)
                        .clipShape(Circle())
                        .overlay(Circle().stroke(Color.primary.opacity(0.08), lineWidth: 0.8))
                }
                .buttonStyle(.plain)
                .help(model.mascotStyle == "3d" ? "Đổi sang kiểu Pixel Art" : "Đổi sang kiểu 3D Chibi")

                Button {
                    isPresented = false
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
                            LinearGradient(colors: [Color.blue, Color.cyan], startPoint: .topLeading, endPoint: .bottomTrailing)
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
                            Color.blue.opacity(0.08),
                            Color.cyan.opacity(0.05)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .stroke(Color.blue.opacity(0.18), lineWidth: 1)
                )
            }
            .buttonStyle(.plain)
            .help("Bấm vào để đổi câu chuyện với Chip Chip")

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
                        .onChange(of: quickViText) { newValue in
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
                                        : Color.accentColor
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
                                .background(quickCopied ? Color.green.opacity(0.2) : Color.accentColor)
                                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                            }
                            .buttonStyle(.plain)
                            .help("Copy lại câu dịch này")
                        }

                        // Hiển thị gợi ý các phương án khác nếu có
                        if !quickAlternatives.isEmpty {
                            Divider().opacity(0.3)
                            VStack(alignment: .leading, spacing: 4) {
                                ForEach(quickAlternatives) { alt in
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
                                }
                            }
                        }
                    }
                    .padding(8)
                    .background(Color.accentColor.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .stroke(Color.accentColor.opacity(0.20), lineWidth: 0.8)
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
                                    .background(Color.purple.opacity(0.15))
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
                            .padding(6)
                            .background(Color(nsColor: .controlBackgroundColor).opacity(0.65))
                            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .stroke(Color.primary.opacity(0.06), lineWidth: 0.8)
                            )
                        }
                        .buttonStyle(.plain)
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
                            .fill(model.isOverlayVisible ? Color.orange : Color.blue)
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
                            .fill(Color.purple)
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

            // 4. Snap to convenient corner
            Button {
                isPresented = false
                model.snapMascotToConvenientPosition()
            } label: {
                HStack(spacing: 9) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(Color(red: 0.15, green: 0.65, blue: 0.60))
                            .frame(width: 24, height: 24)

                        Image(systemName: "arrow.down.forward.and.arrow.up.backward")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(.white)
                    }

                    Text("Đưa Chip Chip về góc thuận tiện")
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
                        Text("Tạm biệt Chip Chip (Ẩn đi)")
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
    }
}

// MARK: - Main Application Navigation & View

struct MainDashboardView: View {
    @ObservedObject var model: MeetingModel

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

                    Text(appVersionDisplay)
                        .font(.system(size: 10, weight: .bold))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.secondary.opacity(0.12))
                        .clipShape(Capsule())

                    AutoUpdateNavBadge()
                }

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
                        }
                        .font(.system(size: 12, weight: .medium))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(model.isFloatingMascotVisible ? Color.accentColor.opacity(0.15) : Color.secondary.opacity(0.1))
                        .foregroundStyle(model.isFloatingMascotVisible ? Color.accentColor : Color.primary)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .help("Bật/Tắt trợ lý Chip Chip nổi trên màn hình để thao tác nhanh")

                    Button {
                        model.toggleOverlay()
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: model.isOverlayVisible ? "pip.exit" : "pip.enter")
                            Text("Phụ đề nổi")
                        }
                        .font(.system(size: 12, weight: .medium))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(model.isOverlayVisible ? Color.accentColor.opacity(0.15) : Color.secondary.opacity(0.1))
                        .foregroundStyle(model.isOverlayVisible ? Color.accentColor : Color.primary)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .help(model.isOverlayVisible ? "Tắt cửa sổ phụ đề nổi" : "Mở cửa sổ phụ đề nổi luôn hiển thị trên cùng")

                    Button {
                        model.showAboutSheet.toggle()
                    } label: {
                        Image(systemName: "info.circle")
                            .font(.system(size: 13))
                            .padding(7)
                            .background(model.showAboutSheet ? Color.accentColor.opacity(0.15) : Color.secondary.opacity(0.1))
                            .foregroundStyle(model.showAboutSheet ? Color.accentColor : Color.primary)
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
                    .sheet(isPresented: Binding(
                        get: { AppUpdater.shared.showUpdateSheet },
                        set: { AppUpdater.shared.showUpdateSheet = $0 }
                    )) {
                        UpdateSheetView()
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
            HStack(spacing: 7) {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .medium))

                Text(title)
                    .font(.system(size: 13, weight: isSelected ? .semibold : .regular))

                if let badge {
                    Text(badge)
                        .font(.system(size: 9, weight: .black))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(badgeColor.opacity(0.2))
                        .foregroundStyle(badgeColor)
                        .clipShape(Capsule())
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .background(isSelected ? Color(nsColor: .selectedControlColor).opacity(0.18) : Color.clear)
            .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
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
            HStack(spacing: 8) {
                // Icon badge box
                ZStack {
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(sourceColor.opacity(0.16))
                        .frame(width: 24, height: 24)

                    Image(systemName: sourceIcon)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(sourceColor)
                }

                // Clean single line title
                Text(sourceTitle)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                Spacer(minLength: 8)

                // Dropdown chevron
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 10)
            .frame(minWidth: 200, maxWidth: 300)
            .frame(height: 36)
            .background(Color(nsColor: .controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .stroke(Color.primary.opacity(0.08), lineWidth: 1)
            )
        }
        .menuStyle(.borderlessButton)
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
                    Image(systemName: "chevron.down")
                        .font(.system(size: 8, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
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
            .help("Chọn ngôn ngữ nguồn (nghe & nhận diện giọng nói)")

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
                        .fill(Color.accentColor.opacity(0.12))
                        .frame(width: 32, height: 36)
                        .overlay(
                            RoundedRectangle(cornerRadius: 9, style: .continuous)
                                .stroke(Color.accentColor.opacity(0.25), lineWidth: 1)
                        )

                    Image(systemName: "arrow.left.arrow.right")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(Color.accentColor)
                }
            }
            .buttonStyle(.plain)
            .help("Đổi chiều ngôn ngữ nhanh (⇄)")

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
                    Image(systemName: "chevron.down")
                        .font(.system(size: 8, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
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
            .help("Chọn ngôn ngữ dịch ra (phụ đề & ghi chú)")
        }
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

// MARK: - Tab 1: Meeting & Live Captions

struct MeetingView: View {
    @ObservedObject var model: MeetingModel

    var body: some View {
        VStack(spacing: 12) {
            // Control Hub Card
            VStack(spacing: 8) {
                HStack(spacing: 10) {
                    // Audio Source Selector - Spacious Modern Menu
                    AudioSourceSelectorMenu(model: model)

                    // Standalone Quick Refresh Button
                    Button {
                        Task { await model.refresh() }
                    } label: {
                        ZStack {
                            RoundedRectangle(cornerRadius: 9, style: .continuous)
                                .fill(Color(nsColor: .controlBackgroundColor))
                                .frame(width: 36, height: 36)
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
                    .help("Tải lại danh sách ứng dụng")
                    .disabled(model.running || model.busy)

                    // Language Pair Selector & Quick Swap
                    LanguagePairSelectorMenu(model: model)

                    Spacer()

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
                                : LinearGradient(colors: [Color.blue, Color.purple], startPoint: .topLeading, endPoint: .bottomTrailing)
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                        .shadow(
                            color: (model.running ? Color.red : Color.blue).opacity(0.25),
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
                                if let url = URL(string: "x-apple.systempreferences:com.apple.Keyboard-Settings.extension") {
                                    NSWorkspace.shared.open(url)
                                }
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
                        } else if model.warning.localizedCaseInsensitiveContains("màn hình") || model.warning.localizedCaseInsensitiveContains("Screen") || model.warning.localizedCaseInsensitiveContains("TCC") {
                            HStack(spacing: 8) {
                                Button {
                                    model.openScreenCaptureSettings()
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
                                    .background(Color.blue)
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

            // Subtitle Stream Section
            ZStack {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color(nsColor: .controlBackgroundColor).opacity(0.3))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(Color.primary.opacity(0.06), lineWidth: 1)
                    )

                if model.captions.isEmpty {
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
                } else {
                    ScrollViewReader { proxy in
                        ScrollView {
                            LazyVStack(spacing: 12) {
                                ForEach(model.captions) { row in
                                    CaptionCardView(caption: row)
                                        .id(row.id)
                                }
                            }
                            .padding(16)
                        }
                        .onChange(of: model.captions.last?.original) { _, _ in
                            if let id = model.captions.last?.id {
                                withAnimation(.easeOut(duration: 0.2)) {
                                    proxy.scrollTo(id, anchor: .bottom)
                                }
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

                    Text("đoạn phụ đề • English → Tiếng Việt")
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
                        .background(Color.purple.opacity(0.15))
                        .foregroundStyle(Color.purple)
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
                        .background(Color.blue.opacity(0.15))
                        .foregroundStyle(Color.blue)
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

                Spacer()

                // Copy Original Button
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(caption.original, forType: .string)
                    copiedOriginal = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { copiedOriginal = false }
                } label: {
                    HStack(spacing: 3) {
                        Image(systemName: copiedOriginal ? "checkmark" : "doc.on.doc")
                        Text("EN")
                    }
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(copiedOriginal ? .green : .secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(Color.secondary.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                }
                .buttonStyle(.plain)
                .help("Sao chép câu tiếng Anh gốc")

                // Copy Vietnamese Button
                if !caption.vietnamese.isEmpty {
                    Button {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(caption.vietnamese, forType: .string)
                        copiedVietnamese = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { copiedVietnamese = false }
                    } label: {
                        HStack(spacing: 3) {
                            Image(systemName: copiedVietnamese ? "checkmark" : "doc.on.doc")
                            Text("VI")
                        }
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(copiedVietnamese ? .green : .secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(Color.secondary.opacity(0.08))
                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .help("Sao chép bản dịch tiếng Việt")
                }
            }

            // Original English text
            HStack(alignment: .top, spacing: 8) {
                Text("EN")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.blue.opacity(0.8))
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(Color.blue.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                    .padding(.top, 1)

                Text(caption.original)
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            // Vietnamese Translation
            HStack(alignment: .top, spacing: 8) {
                Text("VI")
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
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.primary.opacity(0.06), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.03), radius: 4, y: 1)
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
                .foregroundStyle(Color.accentColor)
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

    var body: some View {
        VStack(spacing: 14) {
            // 1. Chuyên ngành dịch thuật Selector Bar (Dropdown Menu đồng bộ với Cài đặt)
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Image(systemName: "character.book.closed.fill")
                            .foregroundStyle(Color.accentColor)
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
                            .foregroundStyle(Color.accentColor)
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
                                        .foregroundStyle(Color.accentColor)
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

            // 3. Two-Pane Translation Studio
            HStack(spacing: 16) {
                // Left Panel: Source Input
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
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
                                    .font(.system(size: 13, weight: .semibold))

                                Image(systemName: "chevron.down")
                                    .font(.system(size: 8, weight: .semibold))
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .buttonStyle(.plain)

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
                            Text("Nhập câu hoặc đoạn văn bản (\(model.sourceLanguage.displayName))…\nBấm các gợi ý mẫu ở trên hoặc gõ nội dung cần dịch và bấm ⌘ + Enter")
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

                // Middle Translate & Swap Trigger Column
                VStack(spacing: 14) {
                    Spacer()

                    // Swap languages & texts
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
                                .frame(width: 36, height: 36)
                                .overlay(
                                    Circle()
                                        .stroke(Color.accentColor.opacity(0.25), lineWidth: 1)
                                )

                            Image(systemName: "arrow.left.arrow.right")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundStyle(Color.accentColor)
                        }
                    }
                    .buttonStyle(.plain)
                    .help("Đổi chiều ngôn ngữ & hoán đổi nội dung (⇄)")

                    // Translate button
                    Button {
                        translateNow()
                    } label: {
                        ZStack {
                            Circle()
                                .fill(
                                    LinearGradient(
                                        colors: [Color.blue, Color.purple],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                                .frame(width: 44, height: 44)
                                .shadow(color: .purple.opacity(0.35), radius: 8, y: 3)

                            if translating {
                                ProgressView()
                                    .controlSize(.small)
                                    .colorInvert()
                            } else {
                                Image(systemName: "arrow.right")
                                    .font(.system(size: 16, weight: .bold))
                                    .foregroundStyle(.white)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    .disabled(input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || translating)
                    .keyboardShortcut(.return, modifiers: .command)

                    Spacer()
                }

                // Right Panel: Target Output
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
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
                                    .background(Color.blue.opacity(0.15))
                                    .foregroundStyle(.blue)
                                    .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))

                                Text("\(model.targetLanguage.flag) \(model.targetLanguage.displayName)")
                                    .font(.system(size: 13, weight: .semibold))

                                Image(systemName: "chevron.down")
                                    .font(.system(size: 8, weight: .semibold))
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .buttonStyle(.plain)

                        Spacer()

                        if !output.isEmpty {
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
                                .foregroundStyle(copied ? .green : Color.accentColor)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(copied ? Color.green.opacity(0.12) : Color.accentColor.opacity(0.1))
                                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    ScrollView {
                        VStack(alignment: .leading, spacing: 12) {
                            if output.isEmpty {
                                Text(translating ? "Đang dịch câu của bạn theo chuyên ngành \(model.domainSpecialty.title)…" : "Kết quả bản dịch (\(model.targetLanguage.displayName)) sẽ xuất hiện tại đây.")
                                    .font(.system(size: 14))
                                    .foregroundStyle(.tertiary)
                                    .padding(12)
                            } else {
                                // Primary result
                                VStack(alignment: .leading, spacing: 5) {
                                    HStack {
                                        Text("BẢN DỊCH CHUẨN (\(model.domainSpecialty.shortName.uppercased()))")
                                            .font(.system(size: 9.5, weight: .bold))
                                            .foregroundStyle(Color.accentColor)
                                        Spacer()
                                    }

                                    Text(output)
                                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                                        .lineSpacing(4)
                                        .foregroundStyle(.primary)
                                        .textSelection(.enabled)
                                }
                                .padding(12)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(Color.accentColor.opacity(0.06))
                                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

                                // Alternatives / Gợi ý phương án diễn đạt khác
                                if !translationResult.alternatives.isEmpty {
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
                                    }
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
            }

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
                .background(Color.blue.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
        }
        .padding(20)
    }

    private func translateNow() {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        translating = true; error = ""; copied = false
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
}

// MARK: - Settings Popover View

struct SettingsPopoverView: View {
    @ObservedObject var model: MeetingModel
    @Binding var isPresented: Bool
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
                        .foregroundStyle(Color.accentColor)
                    Text("Cấu hình TransTools")
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                }

                Spacer()

                Button {
                    isPresented = false
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
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
                                        .foregroundStyle(Color.accentColor)
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

                        // 2. Động cơ miễn phí mặc định
                        VStack(alignment: .leading, spacing: 6) {
                            Text("ĐỘNG CƠ DỊCH MIỄN PHÍ (KHÔNG TỐN TOKEN)")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(.secondary)

                            // Card 1: Apple Native (Default)
                            Button {
                                model.setProvider(.apple)
                            } label: {
                                HStack(spacing: 12) {
                                    Image(systemName: "apple.logo")
                                        .font(.system(size: 20))
                                        .foregroundStyle(model.provider == .apple ? Color.accentColor : .primary)
                                        .frame(width: 22)

                                    VStack(alignment: .leading, spacing: 2) {
                                        HStack {
                                            Text("Apple Native (Mặc định)")
                                                .font(.system(size: 12, weight: .bold))
                                            Text("Khuyên dùng")
                                                .font(.system(size: 9, weight: .bold))
                                                .padding(.horizontal, 5)
                                                .padding(.vertical, 1)
                                                .background(Color.green.opacity(0.18))
                                                .foregroundStyle(.green)
                                                .clipShape(Capsule())
                                        }
                                        Text("0 Token • 100% Ngoại tuyến • Tốc độ tức thì ~15ms.")
                                            .font(.system(size: 10))
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Image(systemName: model.provider == .apple ? "checkmark.circle.fill" : "circle")
                                        .foregroundStyle(model.provider == .apple ? Color.accentColor : Color.secondary.opacity(0.4))
                                }
                                .padding(9)
                                .background(model.provider == .apple ? Color.accentColor.opacity(0.1) : Color(nsColor: .controlBackgroundColor))
                                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                                .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(model.provider == .apple ? Color.accentColor : Color.primary.opacity(0.08), lineWidth: 1.2))
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
                                        Text("Google Dịch Miễn Phí (Web)")
                                            .font(.system(size: 12, weight: .bold))
                                        Text("0 Token • Không cần API key • Giao thức web.")
                                            .font(.system(size: 10))
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Image(systemName: model.provider == .free ? "checkmark.circle.fill" : "circle")
                                        .foregroundStyle(model.provider == .free ? Color.accentColor : Color.secondary.opacity(0.4))
                                }
                                .padding(9)
                                .background(model.provider == .free ? Color.accentColor.opacity(0.1) : Color(nsColor: .controlBackgroundColor))
                                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                                .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(model.provider == .free ? Color.accentColor : Color.primary.opacity(0.08), lineWidth: 1.2))
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
                                            .foregroundStyle(isSelected ? Color.accentColor : (hasKey ? .primary : .secondary))
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

                                            Text(hasKey ? "Áp dụng prompt \(model.domainSpecialty.shortName) • Model: \(p.defaultModel)" : "Bấm để thêm API Key mở khóa trợ lý này")
                                                .font(.system(size: 10))
                                                .foregroundStyle(.secondary)
                                        }

                                        Spacer()

                                        if hasKey {
                                            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                                                .foregroundStyle(isSelected ? Color.accentColor : Color.secondary.opacity(0.4))
                                        } else {
                                            Text("Cài Key")
                                                .font(.system(size: 10, weight: .semibold))
                                                .foregroundStyle(Color.accentColor)
                                                .padding(.horizontal, 6)
                                                .padding(.vertical, 2)
                                                .background(Color.accentColor.opacity(0.12))
                                                .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                                        }
                                    }
                                    .padding(9)
                                    .background(isSelected ? Color.accentColor.opacity(0.1) : Color(nsColor: .controlBackgroundColor))
                                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                                    .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(isSelected ? Color.accentColor : Color.primary.opacity(0.08), lineWidth: 1.2))
                                }
                                .buttonStyle(.plain)
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
                        Text("Khi nghe đồng nghiệp nói, AI phân tích ý tứ và chuẩn bị sẵn 3 câu trả lời tiếng Anh (kèm sắc thái & nghĩa tiếng Việt). Phụ đề vẫn chạy miễn phí trên Apple Native, chỉ tốn token khi gợi ý câu trả lời.")
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
                                    .background(model.coPilotProvider == p ? Color.accentColor.opacity(0.14) : Color(nsColor: .controlBackgroundColor))
                                    .foregroundStyle(model.coPilotProvider == p ? Color.accentColor : Color.primary)
                                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                                            .stroke(model.coPilotProvider == p ? Color.accentColor : Color.primary.opacity(0.08), lineWidth: model.coPilotProvider == p ? 1.5 : 1)
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
                                                model.coPilotModel = m
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
                                                model.coPilotModel = m
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
                                            .fill(Color.accentColor.opacity(0.14))
                                            .frame(width: 32, height: 32)
                                        Image(systemName: model.coPilotProvider.icon)
                                            .font(.system(size: 14, weight: .semibold))
                                            .foregroundStyle(Color.accentColor)
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
                                                .foregroundStyle(Color.accentColor)
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
                                                model.coPilotModel = dm
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
                                                .background(isSel ? Color.accentColor.opacity(0.18) : Color(nsColor: .controlBackgroundColor))
                                                .foregroundStyle(isSel ? Color.accentColor : Color.secondary)
                                                .clipShape(Capsule())
                                                .overlay(
                                                    Capsule()
                                                        .stroke(isSel ? Color.accentColor.opacity(0.4) : Color.primary.opacity(0.1), lineWidth: 1)
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
                                    .foregroundStyle(Color.accentColor)
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
                                    : LinearGradient(colors: [Color.accentColor, Color.purple], startPoint: .topLeading, endPoint: .bottomTrailing)
                            )
                            .foregroundStyle(.white)
                            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                            .shadow(color: Color.accentColor.opacity(0.25), radius: 5, y: 2)
                        }
                        .buttonStyle(.plain)
                    }
                }
            } else {
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
                                .foregroundStyle(Color.accentColor)
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
                            Text("🤖 3D Chibi (Viết chép)").tag("3d")
                            Text("👾 Pixel Art").tag("pixel")
                        }
                        .pickerStyle(.segmented)
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
            return "Phản hồi chớp mắt & tiết kiệm token"
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
                        colors: [Color.accentColor, Color.accentColor.opacity(0.8), Color.blue],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                    .frame(width: 50, height: 50)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .shadow(color: Color.accentColor.opacity(0.35), radius: 6, y: 2)

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
                            .background(Color.accentColor.opacity(0.15))
                            .foregroundStyle(Color.accentColor)
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
                        .foregroundStyle(Color.accentColor)
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
                        .foregroundStyle(Color.accentColor)
                    }
                    .buttonStyle(.plain)
                    .help("Mở trang GitHub repository trong trình duyệt")

                    Spacer()
                }

                // Check updates button
                HStack {
                    Image(systemName: "arrow.triangle.2.circlepath.circle.fill")
                        .font(.system(size: 13))
                        .foregroundStyle(Color.accentColor)
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
                        .background(Color.accentColor.opacity(0.12))
                        .foregroundStyle(Color.accentColor)
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
            MainDashboardView(model: model)
                .background(WindowAccessor { window in
                    model.attachMainWindow(window)
                })
                .onAppear {
                    appDelegate.model = model
                    MenuBarManager.shared.setup(with: model)
                }
        }
        .defaultSize(width: 980, height: 720)
        .windowStyle(.hiddenTitleBar)
    }
}

