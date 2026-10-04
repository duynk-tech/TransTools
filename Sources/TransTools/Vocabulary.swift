import SwiftUI
import AppKit
import Carbon.HIToolbox
import AVFoundation

// MARK: - Vocabulary Item Model

public struct VocabularyItem: Identifiable, Codable, Equatable {
    public var id: UUID
    public var word: String
    public var meaning: String
    public var phonetic: String
    public var context: String
    public var sourceApp: String
    public var createdAt: Date
    public var isMastered: Bool

    // SRS Spaced Repetition & Language properties
    public var dueAt: Date?
    public var interval: Int
    public var repetition: Int
    public var easeFactor: Double
    public var lastReviewedAt: Date?
    public var language: String

    public init(
        id: UUID = UUID(),
        word: String,
        meaning: String,
        phonetic: String = "",
        context: String = "",
        sourceApp: String = "",
        createdAt: Date = Date(),
        isMastered: Bool = false,
        dueAt: Date? = nil,
        interval: Int = 1,
        repetition: Int = 0,
        easeFactor: Double = 2.5,
        lastReviewedAt: Date? = nil,
        language: String = "en"
    ) {
        self.id = id
        self.word = word
        self.meaning = meaning
        self.phonetic = phonetic
        self.context = context
        self.sourceApp = sourceApp
        self.createdAt = createdAt
        self.isMastered = isMastered
        self.dueAt = dueAt
        self.interval = interval
        self.repetition = repetition
        self.easeFactor = easeFactor
        self.lastReviewedAt = lastReviewedAt
        self.language = language
    }

    enum CodingKeys: String, CodingKey {
        case id, word, meaning, phonetic, context, sourceApp, createdAt, isMastered
        case dueAt, interval, repetition, easeFactor, lastReviewedAt, language
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        word = try container.decodeIfPresent(String.self, forKey: .word) ?? ""
        meaning = try container.decodeIfPresent(String.self, forKey: .meaning) ?? ""
        phonetic = try container.decodeIfPresent(String.self, forKey: .phonetic) ?? ""
        context = try container.decodeIfPresent(String.self, forKey: .context) ?? ""
        sourceApp = try container.decodeIfPresent(String.self, forKey: .sourceApp) ?? ""
        createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
        isMastered = try container.decodeIfPresent(Bool.self, forKey: .isMastered) ?? false
        dueAt = try container.decodeIfPresent(Date.self, forKey: .dueAt)
        interval = try container.decodeIfPresent(Int.self, forKey: .interval) ?? 1
        repetition = try container.decodeIfPresent(Int.self, forKey: .repetition) ?? 0
        easeFactor = try container.decodeIfPresent(Double.self, forKey: .easeFactor) ?? 2.5
        lastReviewedAt = try container.decodeIfPresent(Date.self, forKey: .lastReviewedAt)
        language = try container.decodeIfPresent(String.self, forKey: .language) ?? "en"
    }
}

// MARK: - Vocabulary Manager (Persistent Storage & Audio)

@MainActor
public final class VocabularyManager: ObservableObject {
    public static let shared = VocabularyManager()

    @Published public var items: [VocabularyItem] = []
    private let storageKey = "TransTools_SavedVocabulary_v1"

    private init() {
        loadItems()
    }

    public func loadItems() {
        if let data = UserDefaults.standard.data(forKey: storageKey),
           let decoded = try? JSONDecoder().decode([VocabularyItem].self, from: data) {
            self.items = decoded
        }
    }

    public func saveItems() {
        if let encoded = try? JSONEncoder().encode(items) {
            UserDefaults.standard.set(encoded, forKey: storageKey)
        }
    }

    public func add(word: String, meaning: String, phonetic: String = "", context: String = "", sourceApp: String = "", language: String = "en") {
        let trimmedWord = word.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedMeaning = meaning.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedPhonetic = phonetic.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedWord.isEmpty else { return }

        // If already exists, update meaning/phonetic and move to front
        if let idx = items.firstIndex(where: { $0.word.lowercased() == trimmedWord.lowercased() && $0.language == language }) {
            items[idx].meaning = trimmedMeaning
            if !trimmedPhonetic.isEmpty { items[idx].phonetic = trimmedPhonetic }
            if !context.isEmpty { items[idx].context = context }
            if !sourceApp.isEmpty { items[idx].sourceApp = sourceApp }
            let item = items.remove(at: idx)
            items.insert(item, at: 0)
        } else {
            let newItem = VocabularyItem(
                word: trimmedWord,
                meaning: trimmedMeaning,
                phonetic: trimmedPhonetic,
                context: context,
                sourceApp: sourceApp,
                language: language
            )
            items.insert(newItem, at: 0)
        }
        saveItems()
    }

    public func remove(id: UUID) {
        items.removeAll { $0.id == id }
        saveItems()
    }

    public func toggleMastered(id: UUID) {
        if let idx = items.firstIndex(where: { $0.id == id }) {
            items[idx].isMastered.toggle()
            saveItems()
        }
    }

    public func isSaved(word: String) -> Bool {
        let trimmed = word.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return items.contains { $0.word.lowercased() == trimmed }
    }

    // MARK: - Spaced Repetition (SRS)
    public enum SRSGrade: Int {
        case again = 0 // Quên
        case hard = 1  // Khó
        case good = 2  // Nhớ
        case easy = 3  // Dễ
    }

    public func review(itemId: UUID, grade: SRSGrade) {
        guard let idx = items.firstIndex(where: { $0.id == itemId }) else { return }
        var item = items[idx]
        let now = Date()
        item.lastReviewedAt = now

        switch grade {
        case .again:
            item.isMastered = false
            item.repetition = 0
            item.interval = 1
            item.easeFactor = max(1.3, item.easeFactor - 0.2)
            item.dueAt = Calendar.current.date(byAdding: .minute, value: 10, to: now)
        case .hard:
            item.repetition = max(1, item.repetition)
            item.interval = max(1, Int(Double(item.interval) * 1.2))
            item.easeFactor = max(1.3, item.easeFactor - 0.15)
            item.dueAt = Calendar.current.date(byAdding: .day, value: item.interval, to: now)
        case .good:
            if item.repetition == 0 {
                item.interval = 1
            } else if item.repetition == 1 {
                item.interval = 3
            } else {
                item.interval = max(item.interval + 1, Int(Double(item.interval) * item.easeFactor))
            }
            item.repetition += 1
            item.dueAt = Calendar.current.date(byAdding: .day, value: item.interval, to: now)
            if item.repetition >= 5 {
                item.isMastered = true
            }
        case .easy:
            if item.repetition == 0 {
                item.interval = 4
            } else {
                item.interval = max(item.interval + 2, Int(Double(item.interval) * (item.easeFactor + 0.5)))
            }
            item.repetition += 2
            item.easeFactor = min(3.0, item.easeFactor + 0.15)
            item.dueAt = Calendar.current.date(byAdding: .day, value: item.interval, to: now)
            if item.repetition >= 4 {
                item.isMastered = true
            }
        }

        items[idx] = item
        saveItems()
    }

    public var dueItemsCount: Int {
        let now = Date()
        return items.filter { item in
            guard let dueAt = item.dueAt else { return true }
            return dueAt <= now
        }.count
    }

    public var dueItems: [VocabularyItem] {
        let now = Date()
        return items.filter { item in
            guard let dueAt = item.dueAt else { return true }
            return dueAt <= now
        }
    }

    public func speak(_ text: String, language: String = "en-US", rate: Float = 0.46) {
        let normalized = language.lowercased().replacingOccurrences(of: "_", with: "-")
        let selected = AppLanguage.allCases.first { $0.speechLocale.lowercased() == normalized }
            ?? AppLanguage.allCases.first { $0.rawValue == LanguageVoicePreferences.code(language) }
        guard let selected else { return }
        TTSService.shared.speak(text: text, language: selected, rateMultiplier: rate / 0.46)
    }

    public func fillMissingPhonetics() async {
        let missing = items.filter { $0.phonetic.isEmpty && $0.word.range(of: "^[A-Za-z'-]+$", options: .regularExpression) != nil }
        for item in missing {
            guard !Task.isCancelled else { return }
            let ipa = await Self.fetchPhonetic(for: item.word)
            if let index = items.firstIndex(where: { $0.id == item.id }), !ipa.isEmpty {
                items[index].phonetic = ipa; saveItems()
            }
        }
    }

    public func exportToCSV() -> URL? {
        var csv = "Word,Phonetic,Meaning,Context,Source App,Date,Mastered\n"
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd HH:mm:ss"

        for item in items {
            let safeWord = item.word.replacingOccurrences(of: "\"", with: "\"\"")
            let safePhonetic = item.phonetic.replacingOccurrences(of: "\"", with: "\"\"")
            let safeMeaning = item.meaning.replacingOccurrences(of: "\"", with: "\"\"")
            let safeContext = item.context.replacingOccurrences(of: "\"", with: "\"\"")
            let safeSource = item.sourceApp.replacingOccurrences(of: "\"", with: "\"\"")
            let dateStr = df.string(from: item.createdAt)
            let mastered = item.isMastered ? "Yes" : "No"

            csv += "\"\(safeWord)\",\"\(safePhonetic)\",\"\(safeMeaning)\",\"\(safeContext)\",\"\(safeSource)\",\"\(dateStr)\",\"\(mastered)\"\n"
        }

        let tempDir = FileManager.default.temporaryDirectory
        let fileURL = tempDir.appendingPathComponent("TransTools_Vocabulary_\(Int(Date().timeIntervalSince1970)).csv")
        do {
            try csv.write(to: fileURL, atomically: true, encoding: .utf8)
            return fileURL
        } catch {
            return nil
        }
    }

    public static func fetchPhonetic(for text: String) async -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let local = DictionaryService.localPhonetic(trimmed)
        if !local.isEmpty { return local }
        guard trimmed.components(separatedBy: .whitespaces).count <= 2,
              let cleanWord = trimmed.components(separatedBy: .whitespaces).first,
              let encoded = cleanWord.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
              let url = URL(string: "https://api.dictionaryapi.dev/api/v2/entries/en/\(encoded)") else {
            return ""
        }

        var req = URLRequest(url: url)
        req.timeoutInterval = 2.0
        guard let (data, resp) = try? await URLSession.shared.data(for: req),
              (resp as? HTTPURLResponse)?.statusCode == 200,
              let json = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]],
              let firstEntry = json.first else {
            return ""
        }

        if let p = firstEntry["phonetic"] as? String, !p.isEmpty {
            return p
        }

        if let phonetics = firstEntry["phonetics"] as? [[String: Any]] {
            for item in phonetics {
                if let text = item["text"] as? String, !text.isEmpty {
                    return text
                }
            }
        }
        return ""
    }
}

// MARK: - Global Hotkey Manager (Option + D & Carbon)

private var gGlobalHotKeyRef: EventHotKeyRef?
private var gGlobalHotKeyAltRef: EventHotKeyRef?
private var gGlobalHotKeyGrammarRef: EventHotKeyRef?
private var gGlobalHotKeyVIToENRef: EventHotKeyRef?
private var gGlobalHotKeyOCRRef: EventHotKeyRef?
private var gEventHandlerRef: EventHandlerRef?

private func carbonHotKeyCallback(
    nextHandler: EventHandlerCallRef?,
    event: EventRef?,
    userData: UnsafeMutableRawPointer?
) -> OSStatus {
    var hotKeyID = EventHotKeyID()
    let status = GetEventParameter(
        event,
        EventParamName(kEventParamDirectObject),
        EventParamType(typeEventHotKeyID),
        nil,
        MemoryLayout<EventHotKeyID>.size,
        nil,
        &hotKeyID
    )
    let hotKeyNumber = (status == noErr) ? hotKeyID.id : 1

    Task { @MainActor in
        if hotKeyNumber == 5 {
            ScreenOCRService.shared.triggerScreenOCRTranslation()
        } else if hotKeyNumber == 4 {
            await GlobalHotkeyManager.shared.triggerVietnameseToEnglish()
        } else if hotKeyNumber == 3 {
            GlobalHotkeyManager.shared.handleGrammarHotKeyTriggered()
        } else {
            GlobalHotkeyManager.shared.handleHotKeyTriggered()
        }
    }
    return noErr
}

@MainActor
public final class GlobalHotkeyManager: ObservableObject {
    public static let shared = GlobalHotkeyManager()

    @Published public var isRegistered: Bool = false
    @Published public var lastCapturedWord: String = ""
    @Published public var lastCapturedMeaning: String = ""
    @Published public var lastCapturedContext: String = ""
    @Published public var lastSourceApp: String = ""

    private var replacementApp: NSRunningApplication?

    private init() {}

    public func registerHotkeys() {
        guard !isRegistered else { return }

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )

        let status = InstallEventHandler(
            GetApplicationEventTarget(),
            carbonHotKeyCallback,
            1,
            &eventType,
            nil,
            &gEventHandlerRef
        )

        if status == noErr {
            // Hotkey 1: Option + D (kVK_ANSI_D = 0x02) - Dịch tức thì
            let hotKeyID1 = EventHotKeyID(signature: OSType(0x5452414E), id: 1) // 'TRAN'
            RegisterEventHotKey(
                UInt32(kVK_ANSI_D),
                UInt32(optionKey),
                hotKeyID1,
                GetApplicationEventTarget(),
                0,
                &gGlobalHotKeyRef
            )

            // Hotkey 2: Option + T (kVK_ANSI_T = 0x11) - Dịch tức thì phụ
            let hotKeyID2 = EventHotKeyID(signature: OSType(0x5452414E), id: 2)
            RegisterEventHotKey(
                UInt32(kVK_ANSI_T),
                UInt32(optionKey),
                hotKeyID2,
                GetApplicationEventTarget(),
                0,
                &gGlobalHotKeyAltRef
            )

            // Hotkey 3: Option + F (kVK_ANSI_F = 0x03) - AI Fix Grammar & Polish English
            let hotKeyID3 = EventHotKeyID(signature: OSType(0x5452414E), id: 3)
            RegisterEventHotKey(
                UInt32(kVK_ANSI_F),
                UInt32(optionKey),
                hotKeyID3,
                GetApplicationEventTarget(),
                0,
                &gGlobalHotKeyGrammarRef
            )

            RegisterEventHotKey(UInt32(kVK_ANSI_E), UInt32(optionKey),
                EventHotKeyID(signature: OSType(0x5452414E), id: 4),
                GetApplicationEventTarget(), 0, &gGlobalHotKeyVIToENRef)

            // Hotkey 5: Option + S (kVK_ANSI_S = 0x01) - Dịch ảnh chụp màn hình OCR
            let hotKeyID5 = EventHotKeyID(signature: OSType(0x5452414E), id: 5)
            RegisterEventHotKey(
                UInt32(kVK_ANSI_S),
                UInt32(optionKey),
                hotKeyID5,
                GetApplicationEventTarget(),
                0,
                &gGlobalHotKeyOCRRef
            )

            isRegistered = true
        }
    }

    public func unregisterHotkeys() {
        if let ref = gGlobalHotKeyRef {
            UnregisterEventHotKey(ref)
            gGlobalHotKeyRef = nil
        }
        if let ref = gGlobalHotKeyAltRef {
            UnregisterEventHotKey(ref)
            gGlobalHotKeyAltRef = nil
        }
        if let ref = gGlobalHotKeyGrammarRef {
            UnregisterEventHotKey(ref)
            gGlobalHotKeyGrammarRef = nil
        }
        if let ref = gGlobalHotKeyVIToENRef {
            UnregisterEventHotKey(ref)
            gGlobalHotKeyVIToENRef = nil
        }
        if let ref = gGlobalHotKeyOCRRef {
            UnregisterEventHotKey(ref)
            gGlobalHotKeyOCRRef = nil
        }
        if let handler = gEventHandlerRef {
            RemoveEventHandler(handler)
            gEventHandlerRef = nil
        }
        isRegistered = false
    }

    public func handleHotKeyTriggered() {
        Task {
            await triggerSelectionTranslation()
        }
    }

    public func handleGrammarHotKeyTriggered() {
        Task {
            await triggerGrammarFixAndPolish()
        }
    }

    public func triggerSelectionTranslation() async {
        let activeApp = NSWorkspace.shared.frontmostApplication
        let appName = activeApp?.localizedName ?? ""

        let pasteboard = NSPasteboard.general
        let initialChangeCount = pasteboard.changeCount

        // Simulate ⌘C
        let source = CGEventSource(stateID: .hidSystemState)
        let cKeyCode: CGKeyCode = 0x08 // 'C' key

        if let cDown = CGEvent(keyboardEventSource: source, virtualKey: cKeyCode, keyDown: true),
           let cUp = CGEvent(keyboardEventSource: source, virtualKey: cKeyCode, keyDown: false) {
            cDown.flags = .maskCommand
            cUp.flags = .maskCommand
            cDown.post(tap: .cghidEventTap)
            cUp.post(tap: .cghidEventTap)
        }

        // Wait up to 220ms for pasteboard update
        for _ in 0..<9 {
            try? await Task.sleep(nanoseconds: 25_000_000)
            if pasteboard.changeCount != initialChangeCount {
                break
            }
        }

        guard let copiedText = pasteboard.string(forType: .string)?.trimmingCharacters(in: .whitespacesAndNewlines),
              pasteboard.changeCount != initialChangeCount, !copiedText.isEmpty else {
            // Prompt user
            MeetingModel.shared?.showSpeechBubble(
                word: "Mẹo nhỏ",
                meaning: "Hãy bôi đen một từ hoặc đoạn văn bản bất kỳ, sau đó bấm Option + D hoặc Option + T để Chip Chip dịch nhé!",
                context: "",
                sourceApp: appName
            )
            return
        }

        let cleanWord = copiedText
        replacementApp = activeApp
        self.lastCapturedWord = cleanWord
        self.lastSourceApp = appName

        // Wake up Chip Chip immediately with loading state
        MeetingModel.shared?.showBubbleLoading(word: cleanWord, sourceApp: appName)

        // Determine language
        let vietnameseChars = CharacterSet(charactersIn: "àáảãạăằắẳẵặâầấẩẫậèéẻẽẹêềếểễệìíỉĩịòóỏõọôồốổỗộơờớởỡợùúủũụưừứửữựỳýỷỹỵđĐ")
        let isVietnamese = cleanWord.rangeOfCharacter(from: vietnameseChars) != nil
        let sourceLang: AppLanguage = isVietnamese ? .vietnamese : .english
        let targetLang: AppLanguage = isVietnamese ? .english : .vietnamese

        // Translate & fetch phonetic in parallel
        do {
            async let phoneticTask: String = (!isVietnamese && cleanWord.components(separatedBy: .whitespaces).count <= 2)
                ? VocabularyManager.fetchPhonetic(for: cleanWord)
                : ""

            let translated = try await AITranslator.freeTranslate(cleanWord, from: sourceLang, to: targetLang)

            let phonetic = await phoneticTask

            self.lastCapturedMeaning = translated
            MeetingModel.shared?.showSpeechBubble(
                word: cleanWord,
                meaning: translated,
                phonetic: phonetic,
                context: cleanWord.count > 40 ? "" : cleanWord,
                sourceApp: appName
            )

            // Auto-pronounce single English words if enabled
            if !isVietnamese && cleanWord.components(separatedBy: .whitespaces).count <= 2 {
                let autoPronounce = UserDefaults.standard.object(forKey: "VocabularyAutoPronounce") as? Bool ?? true
                if autoPronounce {
                    VocabularyManager.shared.speak(cleanWord)
                }
            }

        } catch {
            MeetingModel.shared?.showSpeechBubble(
                word: cleanWord,
                meaning: "Không thể kết nối dịch thuật. Vui lòng kiểm tra lại mạng.",
                context: "",
                sourceApp: appName
            )
        }
    }

    // MARK: - Option + F: AI Grammar Correction & Polishing
    public func triggerGrammarFixAndPolish() async {
        let activeApp = NSWorkspace.shared.frontmostApplication
        let appName = activeApp?.localizedName ?? ""

        let pasteboard = NSPasteboard.general
        let initialChangeCount = pasteboard.changeCount

        // 1. Simulate ⌘C để copy đoạn text bôi đen
        let source = CGEventSource(stateID: .hidSystemState)
        let cKeyCode: CGKeyCode = 0x08 // 'C' key

        if let cDown = CGEvent(keyboardEventSource: source, virtualKey: cKeyCode, keyDown: true),
           let cUp = CGEvent(keyboardEventSource: source, virtualKey: cKeyCode, keyDown: false) {
            cDown.flags = .maskCommand
            cUp.flags = .maskCommand
            cDown.post(tap: .cghidEventTap)
            cUp.post(tap: .cghidEventTap)
        }

        // Wait up to 220ms for pasteboard update
        for _ in 0..<9 {
            try? await Task.sleep(nanoseconds: 25_000_000)
            if pasteboard.changeCount != initialChangeCount {
                break
            }
        }

        guard let copiedText = pasteboard.string(forType: .string)?.trimmingCharacters(in: .whitespacesAndNewlines),
              pasteboard.changeCount != initialChangeCount, !copiedText.isEmpty else {
            MeetingModel.shared?.showSpeechBubble(
                word: "Sửa lỗi tiếng Anh",
                meaning: "Hãy bôi đen câu tiếng Anh rồi bấm Option + F để Chip Chip sửa ngữ pháp.",
                context: "",
                sourceApp: appName,
                mode: "grammar"
            )
            return
        }

        let cleanWord = copiedText
        replacementApp = activeApp
        self.lastCapturedWord = cleanWord
        self.lastSourceApp = appName

        // Wake up Chip Chip with loading grammar mode
        MeetingModel.shared?.showBubbleLoading(word: cleanWord, sourceApp: appName, mode: "grammar")

        // 2. Call AI Engine để sửa ngữ pháp & hoàn thiện câu
        guard let model = MeetingModel.shared else { return }
        let currentProvider = model.provider
        let currentKey = CredentialStore.read(for: currentProvider)
        let currentModel = model.modelName
        let domain = model.domainSpecialty

        do {
            let polished = try await AITranslator.fixAndPolishEnglish(
                cleanWord,
                domain: domain,
                provider: currentProvider,
                model: currentModel,
                key: currentKey
            )

            replacementApp = activeApp
            self.lastCapturedMeaning = polished
            MeetingModel.shared?.showSpeechBubble(
                word: cleanWord,
                meaning: polished,
                phonetic: "",
                context: "AI Polished",
                sourceApp: appName,
                mode: "grammar", canReplace: true
            )
        } catch {
            MeetingModel.shared?.showSpeechBubble(
                word: cleanWord,
                meaning: "Lỗi kết nối AI để sửa câu. Vui lòng kiểm tra lại mạng hoặc API key.",
                context: "",
                sourceApp: appName,
                mode: "grammar"
            )
        }
    }

    public func triggerVietnameseToEnglish() async {
        guard let model = MeetingModel.shared else { return }
        let activeApp = NSWorkspace.shared.frontmostApplication
        let appName = activeApp?.localizedName ?? ""
        let pasteboard = NSPasteboard.general
        let initialChangeCount = pasteboard.changeCount
        let source = CGEventSource(stateID: .hidSystemState)
        for down in [true, false] {
            let event = CGEvent(keyboardEventSource: source, virtualKey: 0x08, keyDown: down)
            event?.flags = .maskCommand
            event?.post(tap: .cghidEventTap)
        }
        for _ in 0..<9 {
            try? await Task.sleep(nanoseconds: 25_000_000)
            if pasteboard.changeCount != initialChangeCount { break }
        }
        guard pasteboard.changeCount != initialChangeCount,
              let text = pasteboard.string(forType: .string)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !text.isEmpty else {
            model.showSpeechBubble(word: "Dịch VI → EN",
                meaning: "Bôi đen câu tiếng Việt rồi bấm Option + E để dịch sang tiếng Anh.",
                sourceApp: appName, mode: "viToEn")
            return
        }
        replacementApp = activeApp
        let domain = model.domainSpecialty
        let provider = model.provider
        let key = CredentialStore.read(for: provider)
        let modelName = model.modelName
        model.showBubbleLoading(word: text, sourceApp: appName, mode: "viToEn")
        do {
            let result = try await AITranslator.quickTranslateDetailed(text,
                from: .vietnamese, to: .english, domain: domain,
                provider: provider, model: modelName, key: key)
            let english = result.primary.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !english.isEmpty else { throw URLError(.cannotParseResponse) }
            replacementApp = activeApp
            model.showSpeechBubble(word: text, meaning: english,
                context: domain.title, sourceApp: appName, mode: "viToEn", canReplace: true)
        } catch {
            model.showSpeechBubble(word: text,
                meaning: "Không thể dịch. Kiểm tra mạng hoặc API key rồi thử lại.",
                sourceApp: appName, mode: "viToEn")
        }
    }

    // MARK: - Simulate ⌘V để paste kết quả đè lại vào ô chat của ứng dụng trước đó
    public func pasteReplacementText(_ text: String) {
        guard MeetingModel.shared?.bubbleCanReplace == true,
              let targetApp = replacementApp, !targetApp.isTerminated else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)

        guard targetApp.activate(options: []) else { return }
        MeetingModel.shared?.hideSpeechBubble()

        // Gửi phím ⌘V sau khi ứng dụng gốc nhận focus để ứng dụng chat tiếp nhận focus
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            guard NSWorkspace.shared.frontmostApplication?.processIdentifier == targetApp.processIdentifier else { return }
            let source = CGEventSource(stateID: .hidSystemState)
            let vKeyCode: CGKeyCode = 0x09 // 'V' key
            if let vDown = CGEvent(keyboardEventSource: source, virtualKey: vKeyCode, keyDown: true),
               let vUp = CGEvent(keyboardEventSource: source, virtualKey: vKeyCode, keyDown: false) {
                vDown.flags = .maskCommand
                vUp.flags = .maskCommand
                vDown.post(tap: .cghidEventTap)
                vUp.post(tap: .cghidEventTap)
            }
        }
    }
}

// MARK: - Chip Chip Speech Bubble View

public struct MascotBubbleView: View {
    @ObservedObject var model: MeetingModel
    @ObservedObject var vocabManager = VocabularyManager.shared

    private var isSaved: Bool {
        vocabManager.isSaved(word: model.bubbleWord)
    }

    public var body: some View {
        ZStack(alignment: model.bubbleOnRight ? .leading : .trailing) {
            // Main Bubble Card
            VStack(alignment: .leading, spacing: 7) {
                // Header: Word + Audio + Source + Close
                HStack(alignment: .center, spacing: 6) {
                    if !model.isBubbleLoading {
                        Button {
                            // Phát âm câu kết quả (nếu grammar mode thì phát âm câu đã sửa)
                            let textToSpeak = ((model.bubbleMode == "grammar" || model.bubbleMode == "viToEn") && !model.bubbleMeaning.isEmpty) ? model.bubbleMeaning : model.bubbleWord
                            vocabManager.speak(textToSpeak)
                        } label: {
                            Image(systemName: "speaker.wave.2.fill")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(TransToolsTheme.accent)
                                .frame(width: 20, height: 20)
                                .background(TransToolsTheme.accent.opacity(0.12))
                                .clipShape(Circle())
                        }
                        .buttonStyle(.plain)
                        .help("Phát âm câu hoàn chỉnh")
                    }

                    VStack(alignment: .leading, spacing: 1) {
                        HStack(spacing: 5) {
                            if (model.bubbleMode == "grammar" || model.bubbleMode == "viToEn") {
                                Label(model.bubbleMode == "viToEn" ? "Dịch VI → EN" : "Sửa ngữ pháp", systemImage: "sparkles")
                                    .font(.system(size: 11, weight: .bold, design: .rounded))
                                    .foregroundStyle(TransToolsTheme.navy)

                            }
                        }
                    }

                    if !model.bubbleSourceApp.isEmpty {
                        Text(model.bubbleSourceApp)
                            .font(.system(size: 9, weight: .medium))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1.5)
                            .background(Color.secondary.opacity(0.1))
                            .clipShape(Capsule())
                    }

                    Spacer()

                    Button {
                        model.hideSpeechBubble()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(.secondary)
                            .frame(width: 18, height: 18)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }

                Divider().opacity(0.35)

                // Translation / Grammar Content
                if model.isBubbleLoading {
                    HStack(spacing: 8) {
                        ProgressView()
                            .controlSize(.small)
                        Text(model.bubbleMeaning)
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 3)
                } else {
                    ScrollView {
                    VStack(alignment: .leading, spacing: 8) {
                    if (model.bubbleMode == "grammar" || model.bubbleMode == "viToEn") {
                        VStack(alignment: .leading, spacing: 5) {
                            Text(model.bubbleMeaning)
                                .font(.system(size: 12.5, weight: .bold, design: .rounded))
                                .foregroundStyle(Color.primary)
                                .fixedSize(horizontal: false, vertical: true)
                                .textSelection(.enabled)

                            if model.bubbleWord != model.bubbleMeaning {
                                Text("Gốc: \"\(model.bubbleWord)\"")
                                    .font(.system(size: 10, design: .rounded))
                                    .foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    } else {
                        Text(model.bubbleMeaning)
                            .font(.system(size: 12.5, weight: .semibold))
                            .foregroundStyle(.primary)
                            .fixedSize(horizontal: false, vertical: true)
                            .textSelection(.enabled)
                    }

                    if model.bubbleMode == "translate" {
                        Text(model.bubbleWord)
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                            .textSelection(.enabled)
                    }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                    // Footer actions
                    HStack(spacing: 7) {
                        if (model.bubbleMode == "grammar" || model.bubbleMode == "viToEn") {
                            // Nút Thay thế vào ô Chat (⌘V)
                            Button {
                                GlobalHotkeyManager.shared.pasteReplacementText(model.bubbleMeaning)
                            } label: {
                                HStack(spacing: 4) {
                                    Image(systemName: "arrow.turn.down.right")
                                        .font(.system(size: 9.5, weight: .bold))
                                    Text("Thay thế vào Chat")
                                        .font(.system(size: 10, weight: .bold))
                                }
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3.5)
                                .background(TransToolsTheme.navy.opacity(0.18))
                                .foregroundStyle(TransToolsTheme.navy)
                                .clipShape(Capsule())
                            }
                            .buttonStyle(.plain)
                            .disabled(!model.bubbleCanReplace)
                            .help("Thay câu bôi đen bằng kết quả tiếng Anh")

                            // Copy button
                            Button {
                                let pb = NSPasteboard.general
                                pb.clearContents()
                                pb.setString(model.bubbleMeaning, forType: .string)
                            } label: {
                                HStack(spacing: 3) {
                                    Image(systemName: "doc.on.doc")
                                        .font(.system(size: 9))
                                    Text("Copy")
                                        .font(.system(size: 9.5))
                                }
                                .padding(.horizontal, 6)
                                .padding(.vertical, 3.5)
                                .background(Color.secondary.opacity(0.1))
                                .foregroundStyle(.secondary)
                                .clipShape(Capsule())
                            }
                            .buttonStyle(.plain)

                        } else {
                            // Save to Vocabulary button
                            Button {
                                if isSaved {
                                    if let item = vocabManager.items.first(where: { $0.word.lowercased() == model.bubbleWord.lowercased() }) {
                                        vocabManager.remove(id: item.id)
                                    }
                                } else {
                                    vocabManager.add(
                                        word: model.bubbleWord,
                                        meaning: model.bubbleMeaning,
                                        phonetic: model.bubblePhonetic,
                                        context: model.bubbleContext,
                                        sourceApp: model.bubbleSourceApp
                                    )
                                }
                            } label: {
                                HStack(spacing: 4) {
                                    Image(systemName: isSaved ? "bookmark.fill" : "bookmark")
                                        .font(.system(size: 9.5))
                                    Text(isSaved ? "Đã lưu vào Sổ" : "Lưu từ vựng")
                                        .font(.system(size: 10, weight: .semibold))
                                }
                                .padding(.horizontal, 7)
                                .padding(.vertical, 3.5)
                                .background(isSaved ? Color.green.opacity(0.18) : TransToolsTheme.accent.opacity(0.12))
                                .foregroundStyle(isSaved ? Color.green : TransToolsTheme.accent)
                                .clipShape(Capsule())
                            }
                            .buttonStyle(.plain)

                            // Copy translation button
                            Button {
                                let pb = NSPasteboard.general
                                pb.clearContents()
                                pb.setString(model.bubbleMeaning, forType: .string)
                            } label: {
                                HStack(spacing: 3) {
                                    Image(systemName: "doc.on.doc")
                                        .font(.system(size: 9))
                                    Text("Copy")
                                        .font(.system(size: 9.5))
                                }
                                .padding(.horizontal, 6)
                                .padding(.vertical, 3.5)
                                .background(Color.secondary.opacity(0.1))
                                .foregroundStyle(.secondary)
                                .clipShape(Capsule())
                            }
                            .buttonStyle(.plain)
                        }

                        Spacer()
                    }
                    .padding(.top, 2)
                }
            }
            .padding(10)
            .padding(.horizontal, 10)
        }
        .frame(width: 360, height: model.speechBubbleHeight)
        .background {
            MascotBoardBubbleShape(tailOnLeft: model.bubbleOnRight)
                .fill(Color.white)
                .shadow(color: Color.black.opacity(0.14), radius: 8, y: 3)
        }
        .overlay {
            MascotBoardBubbleShape(tailOnLeft: model.bubbleOnRight)
                .stroke(TransToolsTheme.accent.opacity(0.58), lineWidth: 2.5)
                .allowsHitTesting(false)
        }
        .environment(\.colorScheme, .light)
        .onHover { hov in
            model.isBubbleHovered = hov
        }
    }
}

// One outline keeps the white board and its pointer joined without a border seam.
private struct MascotBoardBubbleShape: Shape {
    var tailOnLeft: Bool

    func path(in rect: CGRect) -> Path {
        let left = rect.minX + 10
        let right = rect.maxX - 10
        let top = rect.minY + 2
        let bottom = rect.maxY - 2
        let radius: CGFloat = 12
        let middle = rect.midY
        var path = Path()
        path.move(to: CGPoint(x: left + radius, y: top))
        path.addLine(to: CGPoint(x: right - radius, y: top))
        path.addQuadCurve(to: CGPoint(x: right, y: top + radius), control: CGPoint(x: right, y: top))
        if !tailOnLeft {
            path.addLine(to: CGPoint(x: right, y: middle - 8))
            path.addLine(to: CGPoint(x: rect.maxX - 2, y: middle))
            path.addLine(to: CGPoint(x: right, y: middle + 8))
        }
        path.addLine(to: CGPoint(x: right, y: bottom - radius))
        path.addQuadCurve(to: CGPoint(x: right - radius, y: bottom), control: CGPoint(x: right, y: bottom))
        path.addLine(to: CGPoint(x: left + radius, y: bottom))
        path.addQuadCurve(to: CGPoint(x: left, y: bottom - radius), control: CGPoint(x: left, y: bottom))
        if tailOnLeft {
            path.addLine(to: CGPoint(x: left, y: middle + 8))
            path.addLine(to: CGPoint(x: rect.minX + 2, y: middle))
            path.addLine(to: CGPoint(x: left, y: middle - 8))
        }
        path.addLine(to: CGPoint(x: left, y: top + radius))
        path.addQuadCurve(to: CGPoint(x: left + radius, y: top), control: CGPoint(x: left, y: top))
        path.closeSubpath()
        return path
    }
}

// MARK: - Vocabulary Flashcard Practice View

public struct VocabularyFlashcardModal: View {
    @ObservedObject var vocabManager = VocabularyManager.shared
    @Environment(\.dismiss) private var dismiss

    @State private var currentIndex: Int = 0
    @State private var isFlipped: Bool = false

    var activeItems: [VocabularyItem] {
        vocabManager.items
    }

    public var body: some View {
        VStack(spacing: 16) {
            // Header
            HStack {
                Text("Luyện tập Flashcard")
                    .font(.system(size: 15, weight: .bold, design: .rounded))

                Spacer()

                if !activeItems.isEmpty {
                    Text("\(currentIndex + 1) / \(activeItems.count)")
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .foregroundStyle(.secondary)
                }

                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Đóng (Esc)")
                .keyboardShortcut(.cancelAction)
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)

            if activeItems.isEmpty {
                VStack(spacing: 12) {
                    Spacer()
                    Image(systemName: "tray")
                        .font(.system(size: 40))
                        .foregroundStyle(.secondary.opacity(0.4))
                    Text("Chưa có từ vựng nào được lưu.")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.secondary)
                    Text("Bôi đen từ bất kỳ trên web hoặc tài liệu rồi bấm Option + D để Chip Chip dịch và lưu từ nhé!")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary.opacity(0.8))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 30)
                    Spacer()
                }
                .frame(height: 260)
            } else {
                let currentItem = activeItems[min(currentIndex, activeItems.count - 1)]

                // Flashcard Box
                ZStack {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(Color(nsColor: .controlBackgroundColor))
                        .shadow(color: Color.black.opacity(0.08), radius: 8, y: 3)
                        .overlay(
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .stroke(Color.primary.opacity(0.08), lineWidth: 1.2)
                        )

                    VStack(spacing: 12) {
                        if !isFlipped {
                            // Front of card (English Word)
                            Spacer()
                            Text(currentItem.word)
                                .font(.system(size: 26, weight: .bold, design: .rounded))
                                .foregroundStyle(.primary)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 20)

                            if !currentItem.phonetic.isEmpty {
                                Text(DictionaryService.primaryPhonetic(currentItem.phonetic))
                                    .font(.system(size: 14, weight: .medium, design: .monospaced))
                                    .foregroundStyle(TransToolsTheme.navy)
                            }

                            Button {
                                vocabManager.speak(currentItem.word)
                            } label: {
                                HStack(spacing: 5) {
                                    Image(systemName: "speaker.wave.2.fill")
                                        .font(.system(size: 11))
                                    Text("Nghe phát âm")
                                        .font(.system(size: 11, weight: .medium))
                                }
                                .padding(.horizontal, 10)
                                .padding(.vertical, 4)
                                .background(TransToolsTheme.accent.opacity(0.12))
                                .foregroundStyle(TransToolsTheme.accent)
                                .clipShape(Capsule())
                            }
                            .buttonStyle(.plain)

                            Spacer()

                            Text("Bấm vào thẻ để lật xem nghĩa")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundStyle(.secondary.opacity(0.7))
                                .padding(.bottom, 12)
                        } else {
                            // Keep pronunciation visible on both sides of the card.
                            Spacer()
                            Text(currentItem.word).font(.system(size: 16, weight: .semibold, design: .rounded))
                            if !currentItem.phonetic.isEmpty {
                                Text(DictionaryService.primaryPhonetic(currentItem.phonetic)).font(.system(size: 14, design: .monospaced)).foregroundStyle(TransToolsTheme.navy)
                            }
                            Text(currentItem.meaning)
                                .font(.system(size: 20, weight: .bold))
                                .foregroundStyle(TransToolsTheme.accent)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 20)

                            if !currentItem.context.isEmpty && currentItem.context != currentItem.word {
                                Text("\"\(currentItem.context)\"")
                                    .font(.system(size: 11, design: .serif))
                                    .italic()
                                    .foregroundStyle(.secondary)
                                    .multilineTextAlignment(.center)
                                    .padding(.horizontal, 24)
                            }

                            Spacer()

                            Text("Bấm để lật lại từ gốc")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundStyle(.secondary.opacity(0.7))
                                .padding(.bottom, 12)
                        }
                    }
                }
                .frame(height: 220)
                .padding(.horizontal, 20)
                .contentShape(Rectangle())
                .onTapGesture {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) {
                        isFlipped.toggle()
                    }
                }

                // Bottom Controls
                HStack(spacing: 16) {
                    Button {
                        vocabManager.toggleMastered(id: currentItem.id)
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: currentItem.isMastered ? "checkmark.circle.fill" : "circle")
                            Text(currentItem.isMastered ? "Đã thuộc" : "Đánh dấu đã thuộc")
                                .font(.system(size: 11, weight: .medium))
                        }
                        .foregroundStyle(currentItem.isMastered ? .green : .secondary)
                    }
                    .buttonStyle(.plain)

                    Spacer()

                    Button {
                        if currentIndex > 0 {
                            currentIndex -= 1
                            isFlipped = false
                        }
                    } label: {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 12, weight: .bold))
                            .frame(width: 32, height: 32)
                            .background(Color.secondary.opacity(0.1))
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .disabled(currentIndex == 0)

                    Button {
                        if currentIndex < activeItems.count - 1 {
                            currentIndex += 1
                            isFlipped = false
                        }
                    } label: {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 12, weight: .bold))
                            .frame(width: 32, height: 32)
                            .background(TransToolsTheme.accent)
                            .foregroundStyle(.white)
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .disabled(currentIndex >= activeItems.count - 1)
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 16)
            }
        }
        .frame(width: 440)
        .task { await vocabManager.fillMissingPhonetics() }
    }
}

// MARK: - Vocabulary Notebook Section View (Integrated in Notebook.swift)

public struct VocabularyNotebookSectionView: View {
    @ObservedObject var vocabManager = VocabularyManager.shared
    @State private var searchText = ""
    @State private var selectedFilter: Int = 0 // 0: All, 1: Learning, 2: Mastered
    @State private var showFlashcards = false
    @State private var showDictionary = false

    var filteredItems: [VocabularyItem] {
        var list = vocabManager.items
        if selectedFilter == 1 {
            list = list.filter { !$0.isMastered }
        } else if selectedFilter == 2 {
            list = list.filter { $0.isMastered }
        }

        let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if q.isEmpty { return list }
        return list.filter {
            $0.word.lowercased().contains(q) ||
            $0.meaning.lowercased().contains(q) ||
            $0.context.lowercased().contains(q)
        }
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Top Toolbar: Search + Filter + Actions
            HStack(spacing: 10) {
                // Search field
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    TextField("Tìm từ vựng, nghĩa...", text: $searchText)
                        .textFieldStyle(.plain)
                        .font(.system(size: 12))
                    if !searchText.isEmpty {
                        Button { searchText = "" } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 9)
                .padding(.vertical, 5)
                .background(Color(nsColor: .textBackgroundColor).opacity(0.8))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(Color.primary.opacity(0.08), lineWidth: 1))

                // Filter Picker
                Picker("", selection: $selectedFilter) {
                    Text("Tất cả (\(vocabManager.items.count))").tag(0)
                    Text("Đang học (\(vocabManager.items.filter { !$0.isMastered }.count))").tag(1)
                    Text("Đã thuộc (\(vocabManager.items.filter { $0.isMastered }.count))").tag(2)
                }
                .pickerStyle(.segmented)
                .frame(width: 260)

                Spacer()

                Button("Siêu từ điển") { showDictionary = true }
                    .buttonStyle(TransToolsActionButtonStyle()).controlSize(.small)

                // Practice Flashcards Button
                Button {
                    showFlashcards = true
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "rectangle.portrait.on.rectangle.portrait.angled")
                            .font(.system(size: 11))
                        Text("Luyện Flashcard")
                            .font(.system(size: 11.5, weight: .semibold))
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(TransToolsTheme.accent)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
                .buttonStyle(.plain)
                .disabled(vocabManager.items.isEmpty)
                .help("Mở chế độ lật thẻ Flashcard ôn tập")

                // Export CSV
                Button {
                    if let fileURL = vocabManager.exportToCSV() {
                        NSWorkspace.shared.activateFileViewerSelecting([fileURL])
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "square.and.arrow.up")
                            .font(.system(size: 10))
                        Text("Xuất CSV")
                            .font(.system(size: 11))
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(Color.secondary.opacity(0.12))
                    .foregroundStyle(.primary)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
                .buttonStyle(.plain)
                .disabled(vocabManager.items.isEmpty)
                .help("Xuất danh sách từ vựng ra file CSV")
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))

            Divider().opacity(0.5)

            // Content List
            if vocabManager.items.isEmpty {
                VStack(spacing: 12) {
                    Spacer()
                    Image(systemName: "character.book.closed")
                        .font(.system(size: 40))
                        .foregroundStyle(.secondary.opacity(0.35))
                    Text("Sổ từ vựng đang trống")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(.secondary)
                    Text("Hãy bôi đen từ bất kỳ rồi bấm Option + D.\nChip Chip sẽ dịch tức thì và bạn có thể bấm 'Lưu từ vựng' để ôn tập tại đây!")
                        .font(.system(size: 11.5))
                        .foregroundStyle(.secondary.opacity(0.8))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 40)
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if filteredItems.isEmpty {
                VStack(spacing: 8) {
                    Spacer()
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 26))
                        .foregroundStyle(.secondary.opacity(0.35))
                    Text("Không tìm thấy từ vựng phù hợp")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(filteredItems) { item in
                            VocabularyRowCard(item: item, vocabManager: vocabManager)
                        }
                    }
                    .padding(14)
                }
            }
        }
        .sheet(isPresented: $showDictionary) { DictionaryView() }
        .task { await vocabManager.fillMissingPhonetics() }
        .sheet(isPresented: $showFlashcards) {
            VocabularyFlashcardModal(vocabManager: vocabManager)
        }
    }
}

// Single vocabulary card row
private struct VocabularyRowCard: View {
    let item: VocabularyItem
    @ObservedObject var vocabManager: VocabularyManager
    @State private var isHovered = false

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            // Mastered Star Button
            Button {
                vocabManager.toggleMastered(id: item.id)
            } label: {
                Image(systemName: item.isMastered ? "star.fill" : "star")
                    .font(.system(size: 14))
                    .foregroundStyle(item.isMastered ? Color.yellow : Color.secondary.opacity(0.4))
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(.plain)
            .help(item.isMastered ? "Đã thuộc (Bấm để đổi)" : "Chưa thuộc (Bấm để đánh dấu đã thuộc)")
            .padding(.top, 2)

            // Word Info
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(item.word)
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundStyle(.primary)

                    if !item.phonetic.isEmpty {
                        Text(DictionaryService.primaryPhonetic(item.phonetic))
                            .font(.system(size: 11, weight: .medium, design: .monospaced))
                            .foregroundStyle(TransToolsTheme.navy)
                    }

                    Button {
                        vocabManager.speak(item.word)
                    } label: {
                        Image(systemName: "speaker.wave.2.fill")
                            .font(.system(size: 10))
                            .foregroundStyle(TransToolsTheme.accent)
                            .frame(width: 18, height: 18)
                            .background(TransToolsTheme.accent.opacity(0.1))
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .help("Nghe phát âm")

                    if !item.sourceApp.isEmpty {
                        Text(item.sourceApp)
                            .font(.system(size: 9, weight: .medium))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(Color.secondary.opacity(0.1))
                            .clipShape(Capsule())
                    }

                    Spacer()

                    // Created Date
                    Text(item.createdAt.formatted(date: .abbreviated, time: .shortened))
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)

                    // Delete button
                    Button {
                        vocabManager.remove(id: item.id)
                    } label: {
                        Image(systemName: "trash")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .opacity(isHovered ? 0.8 : 0.0)
                    }
                    .buttonStyle(.plain)
                    .help("Xóa từ này khỏi sổ")
                }

                // Vietnamese Meaning
                Text(item.meaning)
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(Color.primary.opacity(0.9))

                // Context (if available)
                if !item.context.isEmpty && item.context != item.word {
                    Text("\"\(item.context)\"")
                        .font(.system(size: 11, design: .serif))
                        .italic()
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .padding(.top, 1)
                }
            }
        }
        .padding(10)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(item.isMastered ? Color.green.opacity(0.25) : Color.primary.opacity(0.06), lineWidth: 1)
        )
        .onHover { hov in isHovered = hov }
    }
}

// MARK: - Developer Communication Phrases & Specialized Disciplines

public struct CommunicationPhrase: Identifiable, Equatable {
    public var id = UUID()
    public var category: String
    public var english: String
    public var vietnamese: String
    public var icon: String

    public init(category: String, english: String, vietnamese: String, icon: String = "quote.bubble.fill") {
        self.category = category
        self.english = english
        self.vietnamese = vietnamese
        self.icon = icon
    }
}

public struct DeveloperPhrasesData {
    public static let standardPhrases: [CommunicationPhrase] = [
        // Category 1: Kỹ thuật & Lập trình
        CommunicationPhrase(
            category: "Kỹ thuật",
            english: "Got it, I understand the requirement clearly.",
            vietnamese: "Tôi đã hiểu rõ yêu cầu rồi.",
            icon: "checkmark.seal.fill"
        ),
        CommunicationPhrase(
            category: "Kỹ thuật",
            english: "Do you need any help with this task?",
            vietnamese: "Bạn có cần mình hỗ trợ gì về task này không?",
            icon: "hand.raised.fill"
        ),
        CommunicationPhrase(
            category: "Kỹ thuật",
            english: "Let me walk you through the logic and implementation.",
            vietnamese: "Để tôi giải thích chi tiết logic và cách triển khai cho bạn.",
            icon: "arrow.triangle.branch"
        ),
        CommunicationPhrase(
            category: "Kỹ thuật",
            english: "First of all, let's check the system logs and error metrics.",
            vietnamese: "Đầu tiên, chúng ta cần kiểm tra logs và chỉ số lỗi hệ thống.",
            icon: "1.circle.fill"
        ),
        CommunicationPhrase(
            category: "Kỹ thuật",
            english: "I'll investigate the root cause and update you shortly.",
            vietnamese: "Tôi sẽ tìm nguyên nhân gốc rễ (root cause) và báo lại sớm.",
            icon: "magnifyingglass.circle.fill"
        ),
        CommunicationPhrase(
            category: "Kỹ thuật",
            english: "Could you push your latest commit to the branch?",
            vietnamese: "Bạn push commit mới nhất lên branch giúp mình nhé.",
            icon: "arrow.up.circle.fill"
        ),
        CommunicationPhrase(
            category: "Kỹ thuật",
            english: "The build succeeded, I'm deploying to staging now.",
            vietnamese: "Build thành công rồi, tôi đang deploy lên môi trường staging.",
            icon: "bolt.badge.checkmark.fill"
        ),
        CommunicationPhrase(
            category: "Kỹ thuật",
            english: "Let's take this discussion offline to save everyone's time.",
            vietnamese: "Chúng ta trao đổi riêng việc này sau buổi họp nhé.",
            icon: "person.2.badge.gearshape.fill"
        ),
        CommunicationPhrase(
            category: "Kỹ thuật",
            english: "I've created a pull request, please review when you have time.",
            vietnamese: "Tôi đã tạo PR rồi, lúc nào tiện bạn review giúp tôi nhé.",
            icon: "doc.badge.plus"
        ),

        // Category 2: Họp Scrum & Tiến độ
        CommunicationPhrase(
            category: "Họp Scrum",
            english: "Everything is on track according to the sprint roadmap.",
            vietnamese: "Mọi thứ đang tiến triển đúng theo kế hoạch sprint.",
            icon: "chart.line.uptrend.xyaxis"
        ),
        CommunicationPhrase(
            category: "Họp Scrum",
            english: "We encountered a minor blocker, but we're actively fixing it.",
            vietnamese: "Chúng tôi gặp một vướng mắc nhỏ nhưng đang tích cực xử lý.",
            icon: "exclamationmark.triangle.fill"
        ),
        CommunicationPhrase(
            category: "Họp Scrum",
            english: "I will have a pull request ready for review by end of day.",
            vietnamese: "Tôi sẽ tạo PR sẵn sàng review vào cuối ngày hôm nay.",
            icon: "checkmark.circle.fill"
        ),
        CommunicationPhrase(
            category: "Họp Scrum",
            english: "I'll follow up with an exact ETA after syncing with the team.",
            vietnamese: "Tôi sẽ báo lại thời gian cụ thể sau khi trao đổi với team.",
            icon: "clock.badge.checkmark.fill"
        ),

        // Category 3: Chuyên ngành & Thảo luận
        CommunicationPhrase(
            category: "Chuyên ngành",
            english: "Let's align on the acceptance criteria and delivery scope.",
            vietnamese: "Hãy thống nhất về tiêu chí nghiệm thu và phạm vi bàn giao.",
            icon: "target"
        ),
        CommunicationPhrase(
            category: "Chuyên ngành",
            english: "Let's review the user flow and edge cases before deciding.",
            vietnamese: "Hãy xem lại luồng người dùng và các trường hợp biên trước.",
            icon: "point.3.connected.trianglepath.dotted"
        ),
        CommunicationPhrase(
            category: "Chuyên ngành",
            english: "Could you clarify that point a bit more for me?",
            vietnamese: "Bạn có thể giải thích rõ hơn điểm đó giúp tôi được không?",
            icon: "questionmark.circle.fill"
        ),
        CommunicationPhrase(
            category: "Chuyên ngành",
            english: "I completely agree with this approach, it makes a lot of sense.",
            vietnamese: "Tôi hoàn toàn đồng ý với hướng tiếp cận này, rất hợp lý.",
            icon: "hand.thumbsup.fill"
        )
    ]
}

// MARK: - Keyboard Shortcut Guide Card (Main Content)

public struct KeyboardShortcutGuideCard: View {
    public init() {}

    public var body: some View {
        HStack(spacing: 12) {
            // Icon
            HStack(spacing: 5) {
                Image(systemName: "keyboard.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(TransToolsTheme.accent)
                Text("PHÍM NÓNG TIỆN ÍCH")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(TransToolsTheme.accent)
            }

            Divider().frame(height: 12).opacity(0.3)

            // Shortcut 1: Option + D
            HStack(spacing: 5) {
                Text("Option + D")
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(TransToolsTheme.accent.opacity(0.12))
                    .foregroundStyle(TransToolsTheme.accent)
                    .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))

                Text("Bôi đen chữ bất kỳ để Chip Chip dịch & lưu từ")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.primary)
            }

            // Shortcut 2: Option + T
            HStack(spacing: 5) {
                Text("Option + T")
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(TransToolsTheme.navy.opacity(0.12))
                    .foregroundStyle(TransToolsTheme.navy)
                    .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))

                Text("Dịch nhanh song ngữ")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.65))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color.primary.opacity(0.06), lineWidth: 1)
        )
    }
}

// Compact horizontal/vertical list of Developer Phrases
public struct DeveloperPhrasesCompactList: View {
    @State private var selectedCategory = "Kỹ thuật"
    @State private var copiedID: UUID? = nil

    private let categories = ["Kỹ thuật", "Họp Scrum", "Chuyên ngành"]

    var phrases: [CommunicationPhrase] {
        DeveloperPhrasesData.standardPhrases.filter { $0.category == selectedCategory }
    }

    public init() {}

    public var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Category Tabs
            HStack(spacing: 6) {
                ForEach(categories, id: \.self) { cat in
                    Button {
                        selectedCategory = cat
                    } label: {
                        Text(cat == "Kỹ thuật" ? "💻 Kỹ thuật & Dev" : (cat == "Họp Scrum" ? "📊 Họp Scrum / Tiến độ" : "🤝 Chuyên ngành & Thảo luận"))
                            .font(.system(size: 10, weight: selectedCategory == cat ? .bold : .medium))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 2.5)
                            .background(selectedCategory == cat ? TransToolsTheme.accent : Color.secondary.opacity(0.08))
                            .foregroundStyle(selectedCategory == cat ? .white : .primary)
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
                Spacer()
                Text("Bấm vào câu để sao chép nhanh")
                    .font(.system(size: 9.5))
                    .foregroundStyle(.secondary)
            }
            .padding(.top, 2)

            // Phrase Grid (2 columns)
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 6) {
                ForEach(phrases) { phrase in
                    Button {
                        let pb = NSPasteboard.general
                        pb.clearContents()
                        pb.setString(phrase.english, forType: .string)
                        copiedID = phrase.id
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                            if copiedID == phrase.id { copiedID = nil }
                        }
                    } label: {
                        HStack(alignment: .top, spacing: 6) {
                            Image(systemName: phrase.icon)
                                .font(.system(size: 10))
                                .foregroundStyle(TransToolsTheme.accent)
                                .frame(width: 14)
                                .padding(.top, 1)

                            VStack(alignment: .leading, spacing: 1) {
                                Text(copiedID == phrase.id ? "✓ Đã copy vào bộ nhớ tạm!" : phrase.english)
                                    .font(.system(size: 10.5, weight: .semibold))
                                    .foregroundStyle(copiedID == phrase.id ? Color.green : Color.primary)
                                    .lineLimit(1)

                                Text(phrase.vietnamese)
                                    .font(.system(size: 9.5))
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }

                            Spacer()

                            Button {
                                VocabularyManager.shared.speak(phrase.english)
                            } label: {
                                Image(systemName: "speaker.wave.2")
                                    .font(.system(size: 9))
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                            .help("Nghe phát âm")
                        }
                        .padding(6)
                        .background(Color(nsColor: .controlBackgroundColor))
                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .stroke(Color.primary.opacity(0.06), lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(.vertical, 4)
    }
}



