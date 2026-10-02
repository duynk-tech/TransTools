import Foundation
import Speech
import AVFoundation
import CryptoKit
import IOKit

#if canImport(Translation)
import Translation
#endif

// MARK: - Multi-Provider AI Architecture

enum AIProvider: String, CaseIterable, Identifiable {
    case apple = "apple"
    case free = "free"
    case gemini = "gemini"
    case openai = "openai"
    case deepseek = "deepseek"
    case claude = "claude"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .apple: return "Apple Translate (Miễn phí trên máy, Siêu tốc)"
        case .free: return "Google Dịch (Miễn phí web)"
        case .gemini: return "Google Gemini"
        case .openai: return "OpenAI (ChatGPT)"
        case .deepseek: return "DeepSeek"
        case .claude: return "Anthropic Claude"
        }
    }

    var shortName: String {
        switch self {
        case .apple: return "Apple Translate"
        case .free: return "Google Dịch"
        case .gemini: return "Gemini"
        case .openai: return "OpenAI"
        case .deepseek: return "DeepSeek"
        case .claude: return "Claude"
        }
    }

    var icon: String {
        switch self {
        case .apple: return "apple.logo"
        case .free: return "bolt.fill"
        case .gemini: return "sparkles"
        case .openai: return "cpu"
        case .deepseek: return "network"
        case .claude: return "brain"
        }
    }

    var apiKeyURL: String {
        switch self {
        case .apple, .free: return ""
        case .gemini: return "https://aistudio.google.com/apikey"
        case .openai: return "https://platform.openai.com/api-keys"
        case .deepseek: return "https://platform.deepseek.com/api_keys"
        case .claude: return "https://console.anthropic.com/settings/keys"
        }
    }

    var defaultModels: [String] {
        switch self {
        case .apple:
            return ["Apple Translate (Tích hợp trên máy)"]
        case .free:
            return ["Tiêu chuẩn (Standard)"]
        case .gemini:
            return ["gemini-2.0-flash", "gemini-1.5-flash", "gemini-1.5-pro"]
        case .openai:
            return ["gpt-4o-mini", "gpt-4o", "gpt-3.5-turbo"]
        case .deepseek:
            return ["deepseek-chat", "deepseek-reasoner"]
        case .claude:
            return ["claude-3-5-haiku-latest", "claude-3-5-sonnet-latest", "claude-3-haiku-20240307"]
        }
    }

    var defaultModel: String {
        defaultModels.first ?? ""
    }
}

enum CredentialStore {
    private static let appSalt = "TransTools.SecureStorage.Salt.v1"
    private static let fileName = "credentials.enc"

    private static var storageURL: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("TransTools", isDirectory: true)
        if !FileManager.default.fileExists(atPath: dir.path) {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        }
        return dir.appendingPathComponent(fileName)
    }

    private static func getHardwareUUID() -> String {
        let matching = IOServiceMatching("IOPlatformExpertDevice")
        let service = IOServiceGetMatchingService(kIOMainPortDefault, matching)
        if service != 0 {
            defer { IOObjectRelease(service) }
            if let prop = IORegistryEntryCreateCFProperty(service, "IOPlatformUUID" as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() as? String {
                return prop
            }
        }
        return NSHomeDirectory()
    }

    private static func deriveKey() -> SymmetricKey {
        let hwUUID = getHardwareUUID()
        let combined = "\(hwUUID):\(appSalt)"
        let digest = SHA256.hash(data: Data(combined.utf8))
        return SymmetricKey(data: digest)
    }

    private static func readAll() -> [String: String] {
        let url = storageURL
        guard let encryptedData = try? Data(contentsOf: url), !encryptedData.isEmpty else {
            return [:]
        }
        do {
            let key = deriveKey()
            let sealedBox = try AES.GCM.SealedBox(combined: encryptedData)
            let decryptedData = try AES.GCM.open(sealedBox, using: key)
            let dict = try JSONDecoder().decode([String: String].self, from: decryptedData)
            return dict
        } catch {
            return [:]
        }
    }

    private static func writeAll(_ dict: [String: String]) throws {
        let url = storageURL
        let plainData = try JSONEncoder().encode(dict)
        let key = deriveKey()
        let sealedBox = try AES.GCM.seal(plainData, using: key)
        guard let combined = sealedBox.combined else {
            throw NSError(domain: "CredentialStore", code: 1, userInfo: [NSLocalizedDescriptionKey: "Không thể đóng gói dữ liệu mã hóa."])
        }
        try combined.write(to: url, options: .atomic)
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }

    static func read(for provider: AIProvider = .gemini) -> String {
        if provider == .apple || provider == .free { return "" }
        let dict = readAll()
        return dict[provider.rawValue] ?? ""
    }

    static func save(_ key: String, for provider: AIProvider = .gemini) throws {
        var dict = readAll()
        dict[provider.rawValue] = key
        try writeAll(dict)
    }
}

// MARK: - Supported Translation & Speech Languages

public enum AppLanguage: String, CaseIterable, Identifiable, Codable {
    case english = "en"
    case englishIndia = "en_IN"
    case vietnamese = "vi"
    case chinese = "zh"
    case japanese = "ja"
    case korean = "ko"
    case french = "fr"
    case german = "de"
    case italian = "it"

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .english: return "Tiếng Anh (US/UK)"
        case .englishIndia: return "Tiếng Anh (Ấn Độ)"
        case .vietnamese: return "Tiếng Việt"
        case .chinese: return "Tiếng Trung"
        case .japanese: return "Tiếng Nhật"
        case .korean: return "Tiếng Hàn"
        case .french: return "Tiếng Pháp"
        case .german: return "Tiếng Đức"
        case .italian: return "Tiếng Ý"
        }
    }

    public var shortName: String {
        switch self {
        case .english: return "EN"
        case .englishIndia: return "EN-IN"
        case .vietnamese: return "VI"
        case .chinese: return "ZH"
        case .japanese: return "JA"
        case .korean: return "KO"
        case .french: return "FR"
        case .german: return "DE"
        case .italian: return "IT"
        }
    }

    public var flag: String {
        switch self {
        case .english: return "🇺🇸"
        case .englishIndia: return "🇮🇳"
        case .vietnamese: return "🇻🇳"
        case .chinese: return "🇨🇳"
        case .japanese: return "🇯🇵"
        case .korean: return "🇰🇷"
        case .french: return "🇫🇷"
        case .german: return "🇩🇪"
        case .italian: return "🇮🇹"
        }
    }

    public var speechLocale: String {
        switch self {
        case .english: return "en-US"
        case .englishIndia: return "en-IN"
        case .vietnamese: return "vi-VN"
        case .chinese: return "zh-CN"
        case .japanese: return "ja-JP"
        case .korean: return "ko-KR"
        case .french: return "fr-FR"
        case .german: return "de-DE"
        case .italian: return "it-IT"
        }
    }

    public var appleLanguageCode: String {
        switch self {
        case .english, .englishIndia: return "en"
        case .vietnamese: return "vi"
        case .chinese: return "zh-Hans"
        case .japanese: return "ja"
        case .korean: return "ko"
        case .french: return "fr"
        case .german: return "de"
        case .italian: return "it"
        }
    }

    public var googleLanguageCode: String {
        switch self {
        case .english, .englishIndia: return "en"
        case .vietnamese: return "vi"
        case .chinese: return "zh-CN"
        case .japanese: return "ja"
        case .korean: return "ko"
        case .french: return "fr"
        case .german: return "de"
        case .italian: return "it"
        }
    }
}

// MARK: - Subtitle Display Mode (Bilingual / CC Source Only / Translation Only)

public enum SubtitleDisplayMode: String, CaseIterable, Identifiable, Codable {
    case bilingual = "bilingual"              // Song ngữ (Gốc + Dịch)
    case originalOnly = "originalOnly"        // Chỉ tiếng gốc (CC - 0ms, không dịch)
    case translationOnly = "translationOnly"  // Chỉ bản dịch

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .bilingual: return "Song ngữ (Gốc + Dịch)"
        case .originalOnly: return "Chỉ tiếng gốc (CC)"
        case .translationOnly: return "Chỉ bản dịch"
        }
    }

    public var shortTitle: String {
        switch self {
        case .bilingual: return "Song ngữ"
        case .originalOnly: return "Tiếng gốc (CC)"
        case .translationOnly: return "Bản dịch"
        }
    }

    public var icon: String {
        switch self {
        case .bilingual: return "character.bubble"
        case .originalOnly: return "captions.bubble"
        case .translationOnly: return "text.bubble"
        }
    }
}

#if canImport(Translation)
@available(macOS 15.0, *)
@MainActor
enum AppleNativeTranslator {
    static var sessions: [String: Any] = [:]
    static var session: Any? = nil

    static func sessionKey(from source: AppLanguage, to target: AppLanguage) -> String {
        "\(source.appleLanguageCode)->\(target.appleLanguageCode)"
    }

    static func register(_ session: Any, from source: AppLanguage, to target: AppLanguage) {
        let key = sessionKey(from: source, to: target)
        sessions[key] = session
    }

    static func translate(_ text: String, from source: AppLanguage = .english, to target: AppLanguage = .vietnamese) async throws -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        return try await AITranslator.freeTranslate(trimmed, from: source, to: target)
    }

    static func viToEn(_ text: String) async throws -> String {
        try await translate(text, from: .vietnamese, to: .english)
    }
}
#endif

// MARK: - Specialized Domain for Accurate Translation (Developer, Business, etc.)

enum DomainSpecialty: String, CaseIterable, Identifiable {
    case developer = "developer"
    case business = "business"
    case daily = "daily"
    case finance = "finance"
    case medical = "medical"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .developer: return "Công nghệ & Lập trình (Developer)"
        case .business: return "Kinh doanh & Hội họp (Business)"
        case .daily: return "Giao tiếp thường nhật (Casual / Daily)"
        case .finance: return "Tài chính & Đầu tư (Finance)"
        case .medical: return "Y tế & Đời sống (Health / Medical)"
        }
    }

    var shortName: String {
        switch self {
        case .developer: return "Developer"
        case .business: return "Business"
        case .daily: return "Giao tiếp"
        case .finance: return "Tài chính"
        case .medical: return "Y tế"
        }
    }

    var icon: String {
        switch self {
        case .developer: return "laptopcomputer"
        case .business: return "briefcase.fill"
        case .daily: return "bubble.left.and.bubble.right.fill"
        case .finance: return "chart.line.uptrend.xyaxis"
        case .medical: return "cross.case.fill"
        }
    }

    func promptDescription(from source: AppLanguage, to target: AppLanguage) -> String {
        switch self {
        case .developer:
            return """
            You are an expert live meeting translator specializing in Software Engineering and Technology.
            Translate the following spoken \(source.displayName) transcript into natural, concise \(target.displayName).
            Rules:
            - Keep common software engineering terminology natural (e.g. PR, commit, deploy, pipeline, refactor, backend, frontend, microservices, bug, endpoint, sprint, release, CI/CD, staging, repo, merge, scale, database, payload).
            - Do not over-translate widely accepted technical English terms into unnatural phrases.
            - Ensure output matches spoken meeting flow: concise, accurate, and easy to read quickly on screen.
            - Output ONLY the translated \(target.displayName) text, with no notes, no quotes, and no explanations.
            """
        case .business:
            return """
            You are an executive live meeting translator specializing in Global Business, Management, and Corporate Operations.
            Translate the following spoken \(source.displayName) transcript into professional, polite, and executive-ready \(target.displayName).
            Rules:
            - Use formal and professional business language suitable for corporate meetings, negotiations, and stakeholder presentations.
            - Correctly handle business concepts (e.g. KPI, ROI, roadmap, deliverable, action items, stakeholder, milestone, quarterly review, sync up, bandwidth).
            - Keep the tone respectful, sharp, and easy to read as subtitles.
            - Output ONLY the translated \(target.displayName) text, with no notes, no quotes, and no explanations.
            """
        case .daily:
            return """
            You are a natural spoken-language translator.
            Translate the following spoken \(source.displayName) transcript into natural, fluent, conversational \(target.displayName).
            Rules:
            - Capture colloquial spoken nuances, friendly tone, and conversational flow naturally.
            - Output ONLY the translated \(target.displayName) text, with no notes, no quotes, and no explanations.
            """
        case .finance:
            return """
            You are a specialized live translator for Finance, Banking, and Investment.
            Translate the following spoken \(source.displayName) transcript into precise, standard financial \(target.displayName).
            Rules:
            - Maintain precision with financial, economic, and accounting terms (e.g. EBITDA, P&L, burn rate, cash flow, valuation, hedging, asset allocation, margin, revenue).
            - Output ONLY the translated \(target.displayName) text, with no notes, no quotes, and no explanations.
            """
        case .medical:
            return """
            You are a healthcare and medical translation specialist.
            Translate the following spoken \(source.displayName) transcript into accurate \(target.displayName).
            Rules:
            - Maintain medical accuracy and standard clinical terminology.
            - Output ONLY the translated \(target.displayName) text, with no notes, no quotes, and no explanations.
            """
        }
    }

    var quickPhrases: [String] {
        switch self {
        case .developer:
            return [
                "Nhờ bạn review PR này giúp mình nhé",
                "Mình đã deploy bản fix lên staging để kiểm thử",
                "API đang trả về mã lỗi 500 do thiếu tham số",
                "Cần họp sync lại về database schema và endpoint",
                "Tính năng này đã hoàn thành và sẵn sàng merge"
            ]
        case .business:
            return [
                "Chúng ta có thể lên lịch họp sync-up vào ngày mai không?",
                "Xin gửi bạn tài liệu tổng kết biên bản cuộc họp",
                "Dự án hiện tại đang triển khai đúng tiến độ",
                "Nhờ anh/chị xác nhận lại ngân sách và thời hạn",
                "Rất vui được hợp tác cùng quý đối tác"
            ]
        case .daily:
            return [
                "Cảm ơn bạn rất nhiều vì đã hỗ trợ nhiệt tình!",
                "Hôm nay công việc của bạn có thuận lợi không?",
                "Hẹn gặp lại bạn vào buổi họp tiếp theo nhé",
                "Tôi hoàn toàn đồng ý với ý kiến của bạn",
                "Cho mình xin lỗi vì đã phản hồi chậm trễ"
            ]
        case .finance:
            return [
                "Báo cáo doanh thu quý này ghi nhận mức tăng trưởng tốt",
                "Các khoản chi phí phát sinh cần được ban giám đốc duyệt",
                "Chỉ số ROI và dòng tiền của quý này đang rất khả quan",
                "Kế hoạch phân bổ ngân sách dự kiến cho quý sau"
            ]
        case .medical:
            return [
                "Bệnh nhân cần được kiểm tra các chỉ số sinh hiệu định kỳ",
                "Phác đồ điều trị này đã được hội đồng chuyên môn thông qua",
                "Xin lưu ý về tiền sử dị ứng thuốc của người bệnh"
            ]
        }
    }
}

// MARK: - Quick Translation Models with Smart Alternatives

struct QuickTranslationResult: Equatable {
    var primary: String = ""
    var alternatives: [TranslationAlternative] = []
}

struct TranslationAlternative: Identifiable, Equatable, Hashable {
    let id: UUID
    let tone: String
    let text: String

    init(id: UUID = UUID(), tone: String, text: String) {
        self.id = id
        self.tone = tone
        self.text = text
    }
}

// MARK: - Smart AI Meeting Reply Suggestion Model

struct ReplySuggestion: Identifiable, Equatable {
    let id: UUID
    let english: String
    let vietnamese: String
    let tone: String

    init(id: UUID = UUID(), english: String, vietnamese: String, tone: String) {
        self.id = id
        self.english = english
        self.vietnamese = vietnamese
        self.tone = tone
    }
}

// MARK: - AI Translator (Gemini, OpenAI, DeepSeek, Claude, Apple Native)

struct AITranslator {
    enum WritingStyle: String, CaseIterable, Identifiable {
        case developer = "Developer"
        case email = "Email"
        var id: String { rawValue }
        var label: String {
            switch self {
            case .developer: return "Developer — ngắn gọn, kỹ thuật"
            case .email: return "Email — trang trọng, chuyên nghiệp"
            }
        }
        func prompt(from source: AppLanguage = .vietnamese, to target: AppLanguage = .english) -> String {
            switch self {
            case .developer:
                return "You are a professional software translator. Translate the following \(source.displayName) text to \(target.displayName). Use concise, natural, and technical language suitable for developer communication (Slack, PR comments, technical docs). Keep it simple and clear. Output ONLY the translated text, nothing else."
            case .email:
                return "You are a professional translator. Translate the following \(source.displayName) text to \(target.displayName) in a formal, professional email style. Use polite, business-appropriate language suitable for work emails. Output ONLY the translated text, nothing else."
            }
        }
        var prompt: String {
            prompt(from: .vietnamese, to: .english)
        }
    }

    // MARK: - Fetch Live Models from Provider API
    static func fetchModels(for provider: AIProvider, key: String) async throws -> [String] {
        switch provider {
        case .apple:
            return ["Apple Translate (Tích hợp trên máy)"]
        case .free:
            return ["Tiêu chuẩn (Standard)"]
        case .gemini:
            let endpoint = "https://generativelanguage.googleapis.com/v1beta/models?key=\(key)"
            guard let url = URL(string: endpoint) else { throw NSError(domain: "Gemini", code: 0, userInfo: [NSLocalizedDescriptionKey: "URL không hợp lệ"]) }
            var request = URLRequest(url: url)
            request.timeoutInterval = 10
            let (data, response) = try await URLSession.shared.data(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else {
                if let err = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let errorObj = err["error"] as? [String: Any],
                   let msg = errorObj["message"] as? String {
                    throw NSError(domain: "Gemini", code: 1, userInfo: [NSLocalizedDescriptionKey: msg])
                }
                throw NSError(domain: "Gemini", code: 1, userInfo: [NSLocalizedDescriptionKey: "Không thể lấy danh sách model Gemini. Kiểm tra lại API key."])
            }
            struct GeminiModelsResponse: Decodable {
                struct ModelItem: Decodable {
                    let name: String
                    let supportedGenerationMethods: [String]?
                }
                let models: [ModelItem]?
            }
            let decoded = try JSONDecoder().decode(GeminiModelsResponse.self, from: data)
            let models = (decoded.models ?? [])
                .filter { $0.supportedGenerationMethods?.contains("generateContent") == true }
                .map { $0.name.replacingOccurrences(of: "models/", with: "") }
                .filter { !$0.contains("embedding") && !$0.contains("aqa") }
            // Sort: prioritize 2.0 / 1.5, then flash
            return models.sorted { a, b in
                let aScore = a.contains("2.0") ? 4 : (a.contains("1.5") ? 3 : (a.contains("1.0") ? 1 : 2))
                let bScore = b.contains("2.0") ? 4 : (b.contains("1.5") ? 3 : (b.contains("1.0") ? 1 : 2))
                if aScore != bScore { return aScore > bScore }
                if a.contains("flash") && !b.contains("flash") { return true }
                if !a.contains("flash") && b.contains("flash") { return false }
                return a < b
            }

        case .openai:
            let endpoint = "https://api.openai.com/v1/models"
            guard let url = URL(string: endpoint) else { throw NSError(domain: "OpenAI", code: 0, userInfo: [NSLocalizedDescriptionKey: "URL không hợp lệ"]) }
            var request = URLRequest(url: url)
            request.timeoutInterval = 10
            request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
            let (data, response) = try await URLSession.shared.data(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else {
                throw NSError(domain: "OpenAI", code: 1, userInfo: [NSLocalizedDescriptionKey: "Không thể lấy danh sách model OpenAI. Kiểm tra lại API key."])
            }
            struct OpenAIModelsResponse: Decodable {
                struct Item: Decodable { let id: String }
                let data: [Item]?
            }
            let decoded = try JSONDecoder().decode(OpenAIModelsResponse.self, from: data)
            let models = (decoded.data ?? [])
                .map { $0.id }
                .filter { $0.hasPrefix("gpt-") || $0.hasPrefix("o1") || $0.hasPrefix("o3") }
                .sorted()
            return models.isEmpty ? provider.defaultModels : models

        case .deepseek:
            let endpoint = "https://api.deepseek.com/models"
            guard let url = URL(string: endpoint) else { throw NSError(domain: "DeepSeek", code: 0, userInfo: [NSLocalizedDescriptionKey: "URL không hợp lệ"]) }
            var request = URLRequest(url: url)
            request.timeoutInterval = 10
            request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
            let (data, response) = try await URLSession.shared.data(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else {
                return provider.defaultModels
            }
            struct DeepSeekModelsResponse: Decodable {
                struct Item: Decodable { let id: String }
                let data: [Item]?
            }
            let decoded = try? JSONDecoder().decode(DeepSeekModelsResponse.self, from: data)
            let models = (decoded?.data ?? []).map { $0.id }
            return models.isEmpty ? provider.defaultModels : models

        case .claude:
            return provider.defaultModels
        }
    }

    // MARK: - In-Memory Ultra-Fast Translation Cache
    private static let translationCache: NSCache<NSString, NSString> = {
        let cache = NSCache<NSString, NSString>()
        cache.countLimit = 500
        return cache
    }()

    // MARK: - Translation Endpoints
    static func translate(
        _ text: String,
        from source: AppLanguage = .english,
        to target: AppLanguage = .vietnamese,
        domain: DomainSpecialty = .developer,
        provider: AIProvider,
        model: String,
        key: String
    ) async throws -> String {
        let cleanText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanText.isEmpty else { return "" }

        let cacheKey = "\(source.rawValue)_\(target.rawValue)_\(domain.rawValue)_\(provider.rawValue)_\(cleanText.lowercased())" as NSString
        if let cached = translationCache.object(forKey: cacheKey) {
            return cached as String
        }

        var translated = ""
        if provider == .apple {
            #if canImport(Translation)
            if #available(macOS 15.0, *) {
                translated = try await AppleNativeTranslator.translate(cleanText, from: source, to: target)
            }
            #endif
            if translated.isEmpty || (source != target && translated.lowercased() == cleanText.lowercased()) {
                translated = try await freeTranslate(cleanText, from: source, to: target)
            }
        } else {
            let trimmedKey = key.trimmingCharacters(in: .whitespacesAndNewlines)
            if provider == .free || trimmedKey.isEmpty {
                translated = try await freeTranslate(cleanText, from: source, to: target)
            } else {
                let prompt = "\(domain.promptDescription(from: source, to: target))\n\nTranscript:\n\(cleanText)"
                translated = try await callAI(prompt: prompt, provider: provider, model: model, key: trimmedKey)
            }
        }

        let result = translated.trimmingCharacters(in: .whitespacesAndNewlines)
        if !result.isEmpty {
            translationCache.setObject(result as NSString, forKey: cacheKey)
        }
        return result
    }

    // MARK: - Quick Translation with Domain Specialty & Smart Alternatives
    static func quickTranslateDetailed(
        _ text: String,
        from source: AppLanguage,
        to target: AppLanguage,
        domain: DomainSpecialty = .developer,
        style: WritingStyle? = nil,
        provider: AIProvider,
        model: String,
        key: String
    ) async throws -> QuickTranslationResult {
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty else { return QuickTranslationResult() }

        let trimmedKey = key.trimmingCharacters(in: .whitespacesAndNewlines)
        if provider != .apple && provider != .free && !trimmedKey.isEmpty {
            let styleDirective = style != nil ? "Style constraint: \(style!.label)." : ""
            let prompt = """
            You are a senior bilingual translator specializing in \(domain.title).
            Translate the following \(source.displayName) text into \(target.displayName).

            Directives:
            - Context & Domain: \(domain.shortName) terminology and nuances.
            \(styleDirective)
            - Provide 3 distinct outputs:
              1. PRIMARY: The most natural, accurate, and professional translation matching \(domain.title).
              2. CONCISE: A short, punchy version perfect for rapid chat/Slack.
              3. FORMAL: A polite, diplomatic version perfect for email or executive communication.

            Input text:
            "\(trimmedText)"

            Output format (strictly 3 lines, nothing else):
            PRIMARY: <translation>
            CONCISE: <translation>
            FORMAL: <translation>
            """

            do {
                let aiResponse = try await callAI(prompt: prompt, provider: provider, model: model, key: trimmedKey)
                var primaryText = ""
                var alternatives: [TranslationAlternative] = []

                let lines = aiResponse.components(separatedBy: .newlines)
                for line in lines {
                    let trimmedLine = line.trimmingCharacters(in: .whitespaces)
                    if trimmedLine.uppercased().hasPrefix("PRIMARY:") {
                        let content = trimmedLine.dropFirst("PRIMARY:".count).trimmingCharacters(in: CharacterSet(charactersIn: " \"'`\t"))
                        primaryText = content
                    } else if trimmedLine.uppercased().hasPrefix("CONCISE:") {
                        let content = trimmedLine.dropFirst("CONCISE:".count).trimmingCharacters(in: CharacterSet(charactersIn: " \"'`\t"))
                        if !content.isEmpty {
                            alternatives.append(TranslationAlternative(tone: "Ngắn gọn (Chat/Slack)", text: content))
                        }
                    } else if trimmedLine.uppercased().hasPrefix("FORMAL:") {
                        let content = trimmedLine.dropFirst("FORMAL:".count).trimmingCharacters(in: CharacterSet(charactersIn: " \"'`\t"))
                        if !content.isEmpty {
                            alternatives.append(TranslationAlternative(tone: "Trang trọng (Email/Đối tác)", text: content))
                        }
                    }
                }

                if primaryText.isEmpty {
                    primaryText = aiResponse.trimmingCharacters(in: .whitespacesAndNewlines)
                }

                return QuickTranslationResult(primary: primaryText, alternatives: alternatives)
            } catch {
                #if canImport(Translation)
                if #available(macOS 15.0, *) {
                    if let appleResult = try? await AppleNativeTranslator.translate(trimmedText, from: source, to: target), !appleResult.isEmpty {
                        return QuickTranslationResult(primary: appleResult)
                    }
                }
                #endif
                if let freeResult = try? await freeTranslate(trimmedText, from: source, to: target), !freeResult.isEmpty {
                    return QuickTranslationResult(primary: freeResult)
                }
                let fallback = try await translate(trimmedText, from: source, to: target, domain: domain, provider: .free, model: "", key: "")
                return QuickTranslationResult(primary: fallback)
            }
        }

        // Apple Native or Free Google Translator
        let fallback = try await translate(trimmedText, from: source, to: target, domain: domain, provider: provider, model: model, key: trimmedKey)
        return QuickTranslationResult(primary: fallback)
    }

    static func quickTranslate(
        _ text: String,
        from source: AppLanguage,
        to target: AppLanguage,
        style: WritingStyle = .developer,
        domain: DomainSpecialty = .developer,
        provider: AIProvider,
        model: String,
        key: String
    ) async throws -> String {
        let res = try await quickTranslateDetailed(text, from: source, to: target, domain: domain, style: style, provider: provider, model: model, key: key)
        return res.primary
    }

    static func viToEn(
        _ text: String,
        style: WritingStyle = .developer,
        domain: DomainSpecialty = .developer,
        provider: AIProvider,
        model: String,
        key: String
    ) async throws -> QuickTranslationResult {
        try await quickTranslateDetailed(text, from: .vietnamese, to: .english, domain: domain, style: style, provider: provider, model: model, key: key)
    }

    // MARK: - AI Grammar Correction & Polish (Option + F & Studio)
    static func fixAndPolishLanguage(
        _ text: String,
        language: AppLanguage = .english,
        domain: DomainSpecialty = .developer,
        provider: AIProvider,
        model: String,
        key: String
    ) async throws -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }

        let trimmedKey = key.trimmingCharacters(in: .whitespacesAndNewlines)
        if provider != .apple && provider != .free && !trimmedKey.isEmpty {
            let prompt = """
            You are an elite bilingual language editor and communication coach specializing in \(domain.title).
            The user wants to fix any grammatical mistakes, typos, spelling, tense, punctuation, awkward word choices, and polish this text written in \(language.displayName) so it sounds completely natural, native, and professional for work/chat.

            Input text:
            "\(trimmed)"

            Instructions:
            - Fix all grammar, spelling, punctuation, and structural errors in \(language.displayName).
            - Keep the original intent and tone intact.
            - Make the phrasing smooth, clear, and native-sounding.
            - Output ONLY the polished \(language.displayName) text, with NO explanations, NO quotes, NO extra commentary.
            """

            do {
                let aiOutput = try await callAI(prompt: prompt, provider: provider, model: model, key: trimmedKey)
                let cleaned = aiOutput.trimmingCharacters(in: CharacterSet(charactersIn: " \"'`\n\r\t"))
                if !cleaned.isEmpty {
                    return cleaned
                }
            } catch {
                // Fallback to roundtrip
            }
        }

        // Free Fallback: Nếu là tiếng Anh thì roundtrip qua tiếng Việt và ngược lại
        do {
            if language == .english {
                let vi = try await freeEnToVi(trimmed)
                let enPolished = try await freeViToEn(vi)
                return enPolished.isEmpty ? trimmed : enPolished
            } else if language == .vietnamese {
                let en = try await freeViToEn(trimmed)
                let viPolished = try await freeEnToVi(en)
                return viPolished.isEmpty ? trimmed : viPolished
            }
            return trimmed
        } catch {
            return trimmed
        }
    }

    static func fixAndPolishEnglish(
        _ text: String,
        domain: DomainSpecialty = .developer,
        provider: AIProvider,
        model: String,
        key: String
    ) async throws -> String {
        try await fixAndPolishLanguage(text, language: .english, domain: domain, provider: provider, model: model, key: key)
    }

    // MARK: - Smart AI Meeting Reply Suggestions with Deep Context
    static func suggestReplies(
        recentContext: [String] = [],
        latestUtterance: String,
        domain: DomainSpecialty = .developer,
        provider: AIProvider,
        model: String,
        key: String
    ) async -> [ReplySuggestion] {
        let trimmedUtterance = latestUtterance.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedUtterance.isEmpty || !recentContext.isEmpty else { return [] }

        // If using Cloud AI (Gemini, OpenAI, DeepSeek, Claude) with a valid key:
        let trimmedKey = key.trimmingCharacters(in: .whitespacesAndNewlines)
        if provider != .apple && provider != .free && !trimmedKey.isEmpty {
            let contextBlock = recentContext.isEmpty ? trimmedUtterance : recentContext.joined(separator: "\n")
            let prompt = """
            You are an intelligent real-time meeting co-pilot for a \(domain.shortName) professional.
            Analyze the following ongoing meeting conversation context and the latest speaker utterance:

            --- RECENT MEETING CONTEXT ---
            \(contextBlock)
            --- LATEST UTTERANCE ---
            "\(trimmedUtterance)"
            -----------------------------

            Based on what was just discussed, generate exactly 3 natural, highly context-aware English responses that the user can immediately reply with in this live meeting.
            Ensure the replies are directly related to the actual topics discussed (not generic canned phrases).
            Provide 3 distinct angles:
            1. Confirm / Progress / Direct Answer (e.g. status, confirmation of the discussed item)
            2. Propose / Solution / Proactive Step (e.g. suggesting an approach, next milestone)
            3. Clarify / Request details / Timeline (e.g. asking for clarification or confirming expectation)

            Format each line strictly as:
            [Short Tone]: [English response] | [Vietnamese explanation]

            Example format:
            [Tiến độ]: I've already tested this locally and will deploy to staging shortly. | Tôi đã kiểm thử nội bộ xong và sẽ đưa lên staging sớm.
            [Đề xuất]: Let's sync with the backend team to align on the payload schema. | Hãy đồng bộ với team backend để chốt cấu trúc dữ liệu.
            [Làm rõ]: Could you clarify if this is blocked by the upcoming auth release? | Bạn có thể làm rõ xem việc này có bị phụ thuộc bản cập nhật xác thực không?

            Output ONLY the 3 lines formatted like above, nothing else.
            """

            if let output = try? await callAI(prompt: prompt, provider: provider, model: model, key: trimmedKey) {
                var suggestions: [ReplySuggestion] = []
                let lines = output.components(separatedBy: .newlines).filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
                for line in lines {
                    let parts = line.components(separatedBy: "|")
                    if parts.count >= 2 {
                        let left = parts[0].trimmingCharacters(in: .whitespaces)
                        let vi = parts[1].trimmingCharacters(in: .whitespaces)
                        var tone = "Trả lời"
                        var en = left
                        if let colonIdx = left.firstIndex(of: ":") {
                            tone = String(left[..<colonIdx]).replacingOccurrences(of: "[", with: "").replacingOccurrences(of: "]", with: "").trimmingCharacters(in: .whitespaces)
                            en = String(left[left.index(after: colonIdx)...]).trimmingCharacters(in: .whitespaces)
                        }
                        if !en.isEmpty {
                            suggestions.append(ReplySuggestion(english: en, vietnamese: vi, tone: tone))
                        }
                    }
                }
                if !suggestions.isEmpty {
                    return Array(suggestions.prefix(3))
                }
            }
        }

        // On-Device / Offline / Intelligent Rules Engine:
        return fallbackSuggestions(for: trimmedUtterance, domain: domain)
    }

    static func suggestReplies(for text: String, provider: AIProvider, model: String, key: String) async -> [ReplySuggestion] {
        await suggestReplies(recentContext: [], latestUtterance: text, domain: .developer, provider: provider, model: model, key: key)
    }

    private static func fallbackSuggestions(for text: String, domain: DomainSpecialty) -> [ReplySuggestion] {
        let lower = text.lowercased()
        if lower.contains("update") || lower.contains("status") || lower.contains("progress") || lower.contains("how is") {
            switch domain {
            case .developer:
                return [
                    ReplySuggestion(english: "Everything is on track. I'm wrapping up the final tests now.", vietnamese: "Mọi thứ đang đúng tiến độ. Tôi đang hoàn tất các kiểm thử cuối cùng.", tone: "Tiến độ"),
                    ReplySuggestion(english: "We encountered a minor blocker, but we're actively looking into it.", vietnamese: "Chúng tôi gặp một chút vướng mắc nhỏ nhưng đang tích cực xử lý.", tone: "Vấn đề"),
                    ReplySuggestion(english: "I will have a pull request ready for review by the end of today.", vietnamese: "Tôi sẽ có PR sẵn sàng để review vào cuối ngày hôm nay.", tone: "Cam kết")
                ]
            case .business:
                return [
                    ReplySuggestion(english: "The project is currently proceeding according to our roadmap.", vietnamese: "Dự án hiện đang tiến triển theo đúng lộ trình đã đề ra.", tone: "Lộ trình"),
                    ReplySuggestion(english: "We have met 90% of the milestone targets for this sprint.", vietnamese: "Chúng tôi đã đạt 90% mục tiêu cột mốc trong đợt này.", tone: "Chỉ số"),
                    ReplySuggestion(english: "I will share the comprehensive status report with stakeholders today.", vietnamese: "Tôi sẽ gửi báo cáo tiến độ chi tiết tới các bên liên quan hôm nay.", tone: "Báo cáo")
                ]
            default:
                return [
                    ReplySuggestion(english: "Things are moving forward smoothly, no major issues.", vietnamese: "Mọi việc đang tiến triển thuận lợi, không có vấn đề lớn.", tone: "Tiến độ"),
                    ReplySuggestion(english: "I'm working on it and will keep you posted.", vietnamese: "Tôi đang làm việc này và sẽ cập nhật thường xuyên.", tone: "Cập nhật"),
                    ReplySuggestion(english: "Almost finished, will have it done shortly.", vietnamese: "Sắp xong rồi, sẽ hoàn tất trong chốc lát.", tone: "Sắp xong")
                ]
            }
        } else if lower.contains("think") || lower.contains("opinion") || lower.contains("agree") || lower.contains("idea") {
            switch domain {
            case .developer:
                return [
                    ReplySuggestion(english: "I completely agree with this architecture, it scales well.", vietnamese: "Tôi hoàn toàn đồng ý với kiến trúc này, khả năng mở rộng tốt.", tone: "Đồng ý"),
                    ReplySuggestion(english: "I think that's a good direction, though we should keep edge cases in mind.", vietnamese: "Tôi nghĩ đây là hướng tốt, nhưng cần lưu ý các trường hợp biên.", tone: "Góp ý"),
                    ReplySuggestion(english: "Could we explore a lighter alternative before making a final decision?", vietnamese: "Liệu chúng ta có thể cân nhắc giải pháp nhẹ hơn trước khi chốt không?", tone: "Cân nhắc")
                ]
            case .business:
                return [
                    ReplySuggestion(english: "This proposal strongly aligns with our quarterly business goals.", vietnamese: "Đề xuất này hoàn toàn phù hợp với các mục tiêu kinh doanh quý này.", tone: "Đồng thuận"),
                    ReplySuggestion(english: "We should evaluate the cost-benefit ratio before committing resources.", vietnamese: "Chúng ta nên đánh giá tỷ suất chi phí - lợi ích trước khi phân bổ nguồn lực.", tone: "Phân tích"),
                    ReplySuggestion(english: "Let's run a pilot test with a smaller user segment first.", vietnamese: "Hãy chạy thử nghiệm với phân khúc người dùng nhỏ trước.", tone: "Thử nghiệm")
                ]
            default:
                return [
                    ReplySuggestion(english: "I completely agree with this approach, it makes a lot of sense.", vietnamese: "Tôi hoàn toàn đồng ý với hướng đi này, rất hợp lý.", tone: "Đồng ý"),
                    ReplySuggestion(english: "Sounds great, let's proceed with that plan.", vietnamese: "Nghe rất tuyệt, cứ triển khai theo kế hoạch đó nhé.", tone: "Ủng hộ"),
                    ReplySuggestion(english: "I have a slightly different thought, may I share it?", vietnamese: "Tôi có một góc nhìn hơi khác một chút, tôi xin phép chia sẻ nhé?", tone: "Góp ý")
                ]
            }
        } else if lower.contains("help") || lower.contains("need") || lower.contains("support") || lower.contains("assist") {
            return [
                ReplySuggestion(english: "Got it, I understand the requirement clearly.", vietnamese: "Tôi đã hiểu rõ yêu cầu rồi.", tone: "Đã hiểu"),
                ReplySuggestion(english: "Do you need any help with this task?", vietnamese: "Bạn có cần mình hỗ trợ gì về task này không?", tone: "Hỗ trợ"),
                ReplySuggestion(english: "Let me walk you through the implementation.", vietnamese: "Để tôi giải thích chi tiết giải pháp cho bạn.", tone: "Giải thích")
            ]
        } else if lower.contains("how") || lower.contains("why") || lower.contains("explain") || lower.contains("bug") || lower.contains("error") {
            return [
                ReplySuggestion(english: "First of all, let's check the system logs.", vietnamese: "Đầu tiên, chúng ta cần kiểm tra logs hệ thống.", tone: "Đầu tiên"),
                ReplySuggestion(english: "I'll investigate the root cause and update you shortly.", vietnamese: "Tôi sẽ tìm nguyên nhân gốc rễ và báo lại sớm.", tone: "Tìm lỗi"),
                ReplySuggestion(english: "Let me walk you through the logic step by step.", vietnamese: "Để tôi giải thích từng bước logic cho bạn.", tone: "Chi tiết")
            ]
        } else if lower.contains("when") || lower.contains("deadline") || lower.contains("eta") || lower.contains("timeline") {
            return [
                ReplySuggestion(english: "We're aiming to deliver this by tomorrow afternoon.", vietnamese: "Chúng tôi dự kiến bàn giao vào chiều mai.", tone: "Thời hạn"),
                ReplySuggestion(english: "I will follow up with an exact ETA after checking with the team.", vietnamese: "Tôi sẽ báo lại thời gian cụ thể sau khi kiểm tra với team.", tone: "Cập nhật sau"),
                ReplySuggestion(english: "It should be ready for deployment shortly.", vietnamese: "Nội dung sẽ sẵn sàng triển khai sớm thôi.", tone: "Sắp xong")
            ]
        } else {
            return [
                ReplySuggestion(english: "Got it, I understand. I'll take care of it.", vietnamese: "Tôi đã hiểu rõ rồi. Tôi sẽ phụ trách phần việc này.", tone: "Đã hiểu"),
                ReplySuggestion(english: "Do you need any help with that?", vietnamese: "Bạn có cần trợ giúp gì về phần này không?", tone: "Hỏi han"),
                ReplySuggestion(english: "First of all, let's align on the scope.", vietnamese: "Đầu tiên, hãy thống nhất về phạm vi công việc.", tone: "Đầu tiên")
            ]
        }
    }

    // MARK: - Free Web Translate (Fast, 0 tokens, no captcha block)
    static func freeTranslate(_ text: String, from source: AppLanguage = .english, to target: AppLanguage = .vietnamese) async throws -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        guard let encoded = trimmed.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else {
            throw NSError(domain: "Translate", code: 0, userInfo: [NSLocalizedDescriptionKey: "Lỗi mã hóa câu dịch."])
        }

        // Endpoint 1: Chrome Extension dictionary API (Fast, no rate-limit captcha block)
        if let url = URL(string: "https://clients5.google.com/translate_a/t?client=dict-chrome-ex&sl=\(source.googleLanguageCode)&tl=\(target.googleLanguageCode)&q=\(encoded)") {
            var request = URLRequest(url: url)
            request.timeoutInterval = 7
            request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko)", forHTTPHeaderField: "User-Agent")
            if let (data, response) = try? await URLSession.shared.data(for: request),
               (response as? HTTPURLResponse)?.statusCode == 200,
               let array = try? JSONSerialization.jsonObject(with: data) as? [String],
               let first = array.first, !first.isEmpty {
                return first.trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }

        // Endpoint 2: Standard gtx endpoint fallback
        if let url = URL(string: "https://translate.googleapis.com/translate_a/single?client=gtx&sl=\(source.googleLanguageCode)&tl=\(target.googleLanguageCode)&dt=t&q=\(encoded)") {
            var request = URLRequest(url: url)
            request.timeoutInterval = 7
            request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko)", forHTTPHeaderField: "User-Agent")
            if let (data, response) = try? await URLSession.shared.data(for: request),
               (response as? HTTPURLResponse)?.statusCode == 200,
               let json = try? JSONSerialization.jsonObject(with: data) as? [Any],
               let outer = json.first as? [Any] {
                var result = ""
                for item in outer {
                    if let pair = item as? [Any], let translated = pair.first as? String {
                        result += translated
                    }
                }
                let cleaned = result.trimmingCharacters(in: .whitespacesAndNewlines)
                if !cleaned.isEmpty { return cleaned }
            }
        }

        throw NSError(domain: "Translate", code: 1, userInfo: [NSLocalizedDescriptionKey: "Không thể kết nối đến dịch vụ dịch thuật."])
    }

    static func freeEnToVi(_ text: String) async throws -> String {
        try await freeTranslate(text, from: .english, to: .vietnamese)
    }

    static func freeViToEn(_ text: String) async throws -> String {
        try await freeTranslate(text, from: .vietnamese, to: .english)
    }

    // MARK: - Core Multi-Provider API Caller
    private static func callAI(prompt: String, provider: AIProvider, model: String, key: String) async throws -> String {
        let selectedModel = model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? provider.defaultModel : model.trimmingCharacters(in: .whitespacesAndNewlines)

        switch provider {
        case .apple:
            #if canImport(Translation)
            if #available(macOS 15.0, *) {
                return try await AppleNativeTranslator.translate(prompt)
            }
            #endif
            return try await freeEnToVi(prompt)
        case .free:
            return try await freeEnToVi(prompt)
        case .gemini:
            var modelPath = selectedModel
            if modelPath.contains("2.5") { modelPath = "gemini-2.0-flash" }
            if modelPath.hasPrefix("models/") { modelPath = String(modelPath.dropFirst(7)) }
            if modelPath.isEmpty { modelPath = "gemini-2.0-flash" }

            struct GeminiResp: Decodable {
                struct Candidate: Decodable {
                    struct Content: Decodable {
                        struct Part: Decodable { let text: String? }
                        let parts: [Part]?
                    }
                    let content: Content?
                }
                let candidates: [Candidate]?
            }

            func executeGemini(for targetModel: String) async throws -> String {
                let endpoint = "https://generativelanguage.googleapis.com/v1beta/models/\(targetModel):generateContent?key=\(key)"
                guard let url = URL(string: endpoint) else {
                    throw NSError(domain: "Gemini", code: 0, userInfo: [NSLocalizedDescriptionKey: "URL không hợp lệ. Kiểm tra API key."])
                }
                var request = URLRequest(url: url)
                request.httpMethod = "POST"
                request.timeoutInterval = 15
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                let body: [String: Any] = [
                    "contents": [["parts": [["text": prompt]]]],
                    "generationConfig": ["temperature": 0.1, "maxOutputTokens": 1024]
                ]
                request.httpBody = try JSONSerialization.data(withJSONObject: body)
                let (data, response) = try await URLSession.shared.data(for: request)
                let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
                if !(200...299).contains(statusCode) {
                    if let errJson = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                       let errorObj = errJson["error"] as? [String: Any],
                       let msg = errorObj["message"] as? String {
                        throw NSError(domain: "Gemini", code: statusCode, userInfo: [NSLocalizedDescriptionKey: "Gemini (HTTP \(statusCode)): \(msg)"])
                    }
                    throw NSError(domain: "Gemini", code: statusCode, userInfo: [NSLocalizedDescriptionKey: "Gemini dịch thất bại (HTTP \(statusCode)). Hãy thử đổi model khác trong Cài đặt."])
                }
                let decoded = try JSONDecoder().decode(GeminiResp.self, from: data)
                guard let translated = decoded.candidates?.first?.content?.parts?.first?.text?.trimmingCharacters(in: .whitespacesAndNewlines), !translated.isEmpty else {
                    throw NSError(domain: "Gemini", code: 0, userInfo: [NSLocalizedDescriptionKey: "Gemini không trả về kết quả dịch."])
                }
                return translated
            }

            do {
                return try await executeGemini(for: modelPath)
            } catch {
                // If model failed with 404 or deprecated, auto-fallback to official stable models
                if modelPath != "gemini-2.0-flash" {
                    if let fallback20 = try? await executeGemini(for: "gemini-2.0-flash") {
                        return fallback20
                    }
                }
                if modelPath != "gemini-1.5-flash" {
                    if let fallback15 = try? await executeGemini(for: "gemini-1.5-flash") {
                        return fallback15
                    }
                }
                throw error
            }

        case .openai, .deepseek:
            let endpoint = provider == .openai ? "https://api.openai.com/v1/chat/completions" : "https://api.deepseek.com/chat/completions"
            guard let url = URL(string: endpoint) else { throw NSError(domain: provider.rawValue, code: 0, userInfo: [NSLocalizedDescriptionKey: "URL không hợp lệ"]) }
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.timeoutInterval = 15
            request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            let body: [String: Any] = [
                "model": selectedModel,
                "messages": [["role": "user", "content": prompt]],
                "temperature": 0.1,
                "max_tokens": 1024
            ]
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
            let (data, response) = try await URLSession.shared.data(for: request)
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
            if !(200...299).contains(statusCode) {
                if let errJson = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let errorObj = errJson["error"] as? [String: Any],
                   let msg = errorObj["message"] as? String {
                    throw NSError(domain: provider.rawValue, code: statusCode, userInfo: [NSLocalizedDescriptionKey: "\(provider.shortName) (HTTP \(statusCode)): \(msg)"])
                }
                throw NSError(domain: provider.rawValue, code: statusCode, userInfo: [NSLocalizedDescriptionKey: "\(provider.shortName) dịch thất bại (HTTP \(statusCode))."])
            }
            struct ChatResp: Decodable {
                struct Choice: Decodable {
                    struct Message: Decodable { let content: String? }
                    let message: Message?
                }
                let choices: [Choice]?
            }
            let decoded = try JSONDecoder().decode(ChatResp.self, from: data)
            guard let translated = decoded.choices?.first?.message?.content?.trimmingCharacters(in: .whitespacesAndNewlines), !translated.isEmpty else {
                throw NSError(domain: provider.rawValue, code: 0, userInfo: [NSLocalizedDescriptionKey: "\(provider.shortName) không trả về kết quả dịch."])
            }
            return translated

        case .claude:
            let endpoint = "https://api.anthropic.com/v1/messages"
            guard let url = URL(string: endpoint) else { throw NSError(domain: "Claude", code: 0, userInfo: [NSLocalizedDescriptionKey: "URL không hợp lệ"]) }
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.timeoutInterval = 15
            request.setValue(key, forHTTPHeaderField: "x-api-key")
            request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            let body: [String: Any] = [
                "model": selectedModel,
                "max_tokens": 1024,
                "messages": [["role": "user", "content": prompt]]
            ]
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
            let (data, response) = try await URLSession.shared.data(for: request)
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
            if !(200...299).contains(statusCode) {
                if let errJson = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let errorObj = errJson["error"] as? [String: Any],
                   let msg = errorObj["message"] as? String {
                    throw NSError(domain: "Claude", code: statusCode, userInfo: [NSLocalizedDescriptionKey: "Claude (HTTP \(statusCode)): \(msg)"])
                }
                throw NSError(domain: "Claude", code: statusCode, userInfo: [NSLocalizedDescriptionKey: "Claude dịch thất bại (HTTP \(statusCode))."])
            }
            struct ClaudeResp: Decodable {
                struct Content: Decodable { let text: String? }
                let content: [Content]?
            }
            let decoded = try JSONDecoder().decode(ClaudeResp.self, from: data)
            guard let translated = decoded.content?.first?.text?.trimmingCharacters(in: .whitespacesAndNewlines), !translated.isEmpty else {
                throw NSError(domain: "Claude", code: 0, userInfo: [NSLocalizedDescriptionKey: "Claude không trả về kết quả dịch."])
            }
            return translated
        }
    }
}

typealias GeminiTranslator = AITranslator

final class LiveSpeech {
    private var recognizer: SFSpeechRecognizer?
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private let lock = NSLock()
    private var generation = UUID()
    private var pendingCMSamples: [CMSampleBuffer] = []
    private var pendingPCMBuffers: [AVAudioPCMBuffer] = []
    private var recentSamples: [(Date, CMSampleBuffer)] = []
    private var recentPCM: [(Date, AVAudioPCMBuffer)] = []
    private let maxPendingBuffers = 200 // ~1.5 - 2s buffer queue for seamless rotation

    var onResult: ((String, Bool) -> Void)?
    var onError: ((Error) -> Void)?
    var onSessionEndedOrTimeout: (() -> Void)?

    func start(localeIdentifier: String = "en-US") throws {
        let rec = SFSpeechRecognizer(locale: Locale(identifier: localeIdentifier))
        guard let rec else {
            throw NSError(domain: "Speech", code: 1, userInfo: [NSLocalizedDescriptionKey: "Không khởi tạo được bộ nhận diện giọng nói cho mã ngôn ngữ \(localeIdentifier)."])
        }
        guard rec.isAvailable else {
            throw NSError(domain: "Speech", code: 2, userInfo: [NSLocalizedDescriptionKey: "Apple Speech chưa sẵn sàng cho \(localeIdentifier). Vui lòng vào Cài đặt hệ thống (System Settings) → Bàn phím (Keyboard) → Bật 'Đọc chính tả' (Dictation)."])
        }
        self.recognizer = rec

        lock.lock()
        // Invalidate generation immediately so any cancellation callbacks from the previous task are ignored
        generation = UUID()
        // Gracefully end previous request without purging buffer queue
        request?.endAudio()
        task?.cancel()
        task = nil

        let next = SFSpeechAudioBufferRecognitionRequest()
        next.shouldReportPartialResults = true
        next.taskHint = .dictation
        next.addsPunctuation = true
        if rec.supportsOnDeviceRecognition {
            next.requiresOnDeviceRecognition = true
        } else {
            next.requiresOnDeviceRecognition = false
        }

        // Replay the last two seconds across request boundaries, including audio not yet recognized.
        let cutoff = Date().addingTimeInterval(-2)
        recentSamples.removeAll { $0.0 < cutoff }
        recentPCM.removeAll { $0.0 < cutoff }
        for (_, sample) in recentSamples { next.appendAudioSampleBuffer(sample) }
        for (_, pcm) in recentPCM { next.append(pcm) }

        // Drain any pending buffered audio samples into the new request so no audio is lost during rotation
        for sample in pendingCMSamples {
            next.appendAudioSampleBuffer(sample)
        }
        pendingCMSamples.removeAll()
        for pcm in pendingPCMBuffers {
            next.append(pcm)
        }
        pendingPCMBuffers.removeAll()

        let token = UUID()
        request = next
        generation = token
        lock.unlock()

        task = rec.recognitionTask(with: next) { [weak self] result, error in
            guard let self else { return }
            self.lock.lock()
            let current = (self.generation == token)
            self.lock.unlock()
            guard current else { return }

            if let result {
                self.onResult?(result.bestTranscription.formattedString, result.isFinal)
            }

            if let error, result?.isFinal != true {
                let nsErr = error as NSError
                let desc = error.localizedDescription

                // Cancellation codes (216: finished/cancelled, 301: request cancelled) happen when we rotate or stop
                // and MUST NOT trigger recursive session restarts.
                let isCancelled = (nsErr.code == 216 || nsErr.code == 301)
                let isTransient = !isCancelled && (nsErr.domain.contains("Assistant") || nsErr.domain.contains("Speech")) &&
                    (nsErr.code == 203 || nsErr.code == 1110 || nsErr.code == 209)

                if isTransient {
                    self.onSessionEndedOrTimeout?()
                } else if desc.localizedCaseInsensitiveContains("Siri") || desc.localizedCaseInsensitiveContains("Dictation") || nsErr.code == 1700 || nsErr.code == 1107 {
                    let friendly = NSError(
                        domain: "Speech",
                        code: 1700,
                        userInfo: [NSLocalizedDescriptionKey: "Siri & Dictation đang bị tắt cho ngôn ngữ \(localeIdentifier). Hãy vào Cài đặt hệ thống (System Settings) → Bàn phím (Keyboard) → Bật 'Đọc chính tả' (Dictation)."]
                    )
                    self.onError?(friendly)
                } else {
                    self.onError?(error)
                }
            }
        }
    }

    func append(_ sample: CMSampleBuffer) {
        lock.lock()
        defer { lock.unlock() }
        if let req = request {
            recentSamples.append((Date(), sample))
            recentSamples.removeAll { $0.0 < Date().addingTimeInterval(-2) }
            req.appendAudioSampleBuffer(sample)
        } else {
            pendingCMSamples.append(sample)
            if pendingCMSamples.count > maxPendingBuffers {
                pendingCMSamples.removeFirst()
            }
        }
    }

    func append(_ buffer: AVAudioPCMBuffer) {
        lock.lock()
        defer { lock.unlock() }
        if let req = request {
            // Audio-engine callback buffers are reused; the replay ring owns a deep copy.
            if let copy = AVAudioPCMBuffer(pcmFormat: buffer.format, frameCapacity: buffer.frameLength) {
                copy.frameLength = buffer.frameLength
                let source = UnsafeMutableAudioBufferListPointer(buffer.mutableAudioBufferList)
                let destination = UnsafeMutableAudioBufferListPointer(copy.mutableAudioBufferList)
                for index in 0..<source.count {
                    if let from = source[index].mData, let to = destination[index].mData {
                        memcpy(to, from, Int(source[index].mDataByteSize))
                    }
                }
                recentPCM.append((Date(), copy))
                recentPCM.removeAll { $0.0 < Date().addingTimeInterval(-2) }
            }
            req.append(buffer)
        } else {
            pendingPCMBuffers.append(buffer)
            if pendingPCMBuffers.count > maxPendingBuffers {
                pendingPCMBuffers.removeFirst()
            }
        }
    }

    func stop() {
        lock.lock()
        generation = UUID()
        request?.endAudio()
        request = nil
        pendingCMSamples.removeAll()
        pendingPCMBuffers.removeAll()
        recentSamples.removeAll()
        recentPCM.removeAll()
        lock.unlock()
        task?.cancel()
        task = nil
    }
}

// MARK: - Text-to-Speech (TTS) Earphone Interpreter & Pronunciation Service

public enum VoiceTone: String, CaseIterable, Identifiable {
    case natural = "natural"       // Tự nhiên & Chuẩn mực
    case warm = "warm"             // Ấm áp & Truyền cảm
    case energetic = "energetic"   // Tươi sáng & Năng động
    case articulate = "articulate" // Rõ ràng & Từng chữ (Luyện nghe)

    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .natural: return "Tự nhiên & Chuẩn mực (Khuyên dùng)"
        case .warm: return "Ấm áp & Truyền cảm"
        case .energetic: return "Tươi sáng & Năng động"
        case .articulate: return "Rõ ràng & Từng chữ (Học tập)"
        }
    }
    public var icon: String {
        switch self {
        case .natural: return "sparkles"
        case .warm: return "heart.fill"
        case .energetic: return "sun.max.fill"
        case .articulate: return "character.book.closed.fill"
        }
    }
    public var pitchMultiplier: Float {
        switch self {
        case .natural: return 1.03
        case .warm: return 0.96
        case .energetic: return 1.08
        case .articulate: return 1.00
        }
    }
    public var rateModifier: Float {
        switch self {
        case .natural: return 0.0
        case .warm: return -0.02
        case .energetic: return 0.02
        case .articulate: return -0.05
        }
    }
    public var postDelay: TimeInterval {
        switch self {
        case .natural: return 0.18
        case .warm: return 0.20
        case .energetic: return 0.15
        case .articulate: return 0.28
        }
    }
}

public struct TTSVoiceOption: Identifiable, Hashable {
    public let id: String
    public let name: String
    public let language: String
    public let quality: AVSpeechSynthesisVoiceQuality
    public let isNeural: Bool
    public let displayName: String

    public init(voice: AVSpeechSynthesisVoice) {
        self.id = voice.identifier
        self.name = voice.name
        self.language = voice.language
        self.quality = voice.quality

        let idLower = voice.identifier.lowercased()
        let isHighQ = voice.quality == .premium || voice.quality == .enhanced || idLower.contains("neural") || idLower.contains("siri")
        self.isNeural = isHighQ

        if idLower.contains("gryphon-neural_vi-vn-a") {
            self.displayName = "Siri Nữ Bắc (Truyền cảm - AI)"
        } else if idLower.contains("gryphon-neural_vi-vn-c") {
            self.displayName = "Siri Nữ Nam (Ấm áp - AI)"
        } else if idLower.contains("siri.natural.nora") {
            self.displayName = "Nora (Siri Mỹ - AI)"
        } else if idLower.contains("siri.natural.simone") {
            self.displayName = "Simone (Siri Mỹ - AI)"
        } else if voice.name.lowercased().contains("linh") {
            self.displayName = isHighQ ? "Linh (Nâng cao - AI)" : "Linh (Tiêu chuẩn)"
        } else if voice.name.lowercased().contains("samantha") {
            self.displayName = isHighQ ? "Samantha (Nâng cao - AI)" : "Samantha (Tiêu chuẩn)"
        } else if voice.name.lowercased().contains("daniel") {
            self.displayName = "Daniel (Anh - UK chuẩn)"
        } else {
            let qualityTag = isHighQ ? " (AI)" : ""
            self.displayName = "\(voice.name)\(qualityTag)"
        }
    }
}

@MainActor
public final class TTSService: NSObject, ObservableObject, AVSpeechSynthesizerDelegate {
    public static let shared = TTSService()

    public enum AutoSpeakTarget: String, CaseIterable, Identifiable {
        case translation = "translation" // Đọc bản dịch (Phiên dịch viên tai nghe)
        case original = "original"       // Đọc câu gốc (Luyện nghe ngoại ngữ)

        public var id: String { rawValue }
        public var title: String {
            switch self {
            case .translation: return "Đọc bản dịch (Phiên dịch viên)"
            case .original: return "Đọc câu gốc (Luyện nghe)"
            }
        }
        public var shortTitle: String {
            switch self {
            case .translation: return "Bản dịch"
            case .original: return "Câu gốc"
            }
        }
    }

    private let synthesizer = AVSpeechSynthesizer()
    @Published public private(set) var isSpeaking = false
    @Published public private(set) var currentlySpeakingCaptionID: UUID?
    @Published public private(set) var currentlySpeakingText: String?

    // Auto-TTS for Live Meetings
    @Published public var isAutoTTSEnabled: Bool = {
        UserDefaults.standard.bool(forKey: "TTS_AutoEnabled")
    }() {
        didSet {
            UserDefaults.standard.set(isAutoTTSEnabled, forKey: "TTS_AutoEnabled")
            if !isAutoTTSEnabled {
                stop()
            }
        }
    }

    @Published public var autoTarget: AutoSpeakTarget = {
        let raw = UserDefaults.standard.string(forKey: "TTS_AutoTarget") ?? "translation"
        return AutoSpeakTarget(rawValue: raw) ?? .translation
    }() {
        didSet {
            UserDefaults.standard.set(autoTarget.rawValue, forKey: "TTS_AutoTarget")
        }
    }

    @Published public var voiceTone: VoiceTone = {
        let raw = UserDefaults.standard.string(forKey: "TTS_VoiceTone") ?? "natural"
        return VoiceTone(rawValue: raw) ?? .natural
    }() {
        didSet {
            UserDefaults.standard.set(voiceTone.rawValue, forKey: "TTS_VoiceTone")
        }
    }

    @Published public var selectedVoiceID: String? = {
        UserDefaults.standard.string(forKey: "TTS_SelectedVoiceID")
    }() {
        didSet {
            UserDefaults.standard.set(selectedVoiceID, forKey: "TTS_SelectedVoiceID")
        }
    }

    @Published public var speechRate: Float = {
        let val = UserDefaults.standard.float(forKey: "TTS_Rate")
        return (val >= 0.3 && val <= 0.8) ? val : 0.46 // Standard natural speaking rate
    }() {
        didSet {
            UserDefaults.standard.set(speechRate, forKey: "TTS_Rate")
        }
    }

    @Published public var speechVolume: Float = {
        let val = UserDefaults.standard.float(forKey: "TTS_Volume")
        return (val > 0) ? val : 1.0
    }() {
        didSet {
            UserDefaults.standard.set(speechVolume, forKey: "TTS_Volume")
        }
    }

    // Queue for meeting subtitle playback
    private var speechQueue: [(id: UUID, text: String, language: AppLanguage)] = []
    private var spokenCaptionIDs = Set<UUID>()

    override private init() {
        super.init()
        synthesizer.delegate = self
    }

    // MARK: - Smart Normalization for Natural Speech Prosody
    public static func normalizeForSpeech(_ text: String, languageLocale: String) -> String {
        var s = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !s.isEmpty else { return "" }

        // Remove markdown formatting
        s = s.replacingOccurrences(of: "\\*\\*(.*?)\\*\\*", with: "$1", options: .regularExpression)
        s = s.replacingOccurrences(of: "\\*(.*?)\\*", with: "$1", options: .regularExpression)
        s = s.replacingOccurrences(of: "`([^`]+)`", with: "$1", options: .regularExpression)
        s = s.replacingOccurrences(of: "~~(.*?)~~", with: "$1", options: .regularExpression)

        // Remove sound effect and noise subtitle tags: [laughter], (cười), [applause], [tiếng nhạc], v.v.
        s = s.replacingOccurrences(of: "\\[[^\\]]*\\]", with: "", options: .regularExpression)
        s = s.replacingOccurrences(of: "\\((cười|tiếng cười|vỗ tay|tiếng vỗ tay|nhạc|tiếng nhạc|ho|thở dài|laughter|applause|music|sigh|cough)[^\\)]*\\)", with: "", options: [.regularExpression, .caseInsensitive])

        // Remove URLs and web paths
        s = s.replacingOccurrences(of: "https?://\\S+", with: languageLocale.hasPrefix("vi") ? "đường dẫn liên kết" : "link", options: .regularExpression)
        s = s.replacingOccurrences(of: "www\\.\\S+", with: languageLocale.hasPrefix("vi") ? "đường dẫn liên kết" : "link", options: .regularExpression)

        // Clean punctuation artifacts
        s = s.replacingOccurrences(of: "\\.{2,}", with: ".", options: .regularExpression)
        s = s.replacingOccurrences(of: "\\?{2,}", with: "?", options: .regularExpression)
        s = s.replacingOccurrences(of: "!{2,}", with: "!", options: .regularExpression)
        s = s.replacingOccurrences(of: "\\s*--+\\s*", with: ", ", options: .regularExpression)
        s = s.replacingOccurrences(of: "\\s*—\\s*", with: ", ", options: .regularExpression)
        s = s.replacingOccurrences(of: "[\"“”'‘’]", with: "", options: .regularExpression)

        if languageLocale.hasPrefix("vi") {
            // Conversational & Acronym Replacements for Vietnamese Speech
            let replacements: [(String, String)] = [
                ("\\bAI\\b", "A.I"),
                ("\\bAPI\\b", "A P I"),
                ("\\bUI/UX\\b", "U I, U X"),
                ("\\bUI\\b", "U I"),
                ("\\bUX\\b", "U X"),
                ("\\bPR\\b", "P R"),
                ("\\bQA\\b", "Q A"),
                ("\\bQC\\b", "Q C"),
                ("\\bPM\\b", "P M"),
                ("\\bIT\\b", "I T"),
                ("\\bCEO\\b", "C E O"),
                ("\\bCTO\\b", "C T O"),
                ("\\bCFO\\b", "C F O"),
                ("\\bHR\\b", "H R"),
                ("\\biOS\\b", "i O S"),
                ("\\bmacOS\\b", "mác O S"),
                ("\\bOK\\b", "Ok"),
                ("\\bok\\b", "Ok"),
                ("\\bID\\b", "I D"),
                ("\\bURL\\b", "U R L"),
                ("\\bSQL\\b", "S Q L"),
                ("\\bvs\\b", "với"),
                ("\\betc\\.?\\b", "vân vân"),
                ("\\be\\.g\\.?\\b", "ví dụ như"),
                ("\\bi\\.e\\.?\\b", "tức là"),
                ("%", " phần trăm "),
                ("\\$", " đô la "),
                ("€", " ơ-rô "),
                ("¥", " yên "),
                ("₫", " đồng "),
                ("\\bVND\\b", " đồng "),
                ("&", " và "),
                ("\\s*/\\s*", " hoặc ")
            ]
            for (pattern, repl) in replacements {
                s = s.replacingOccurrences(of: pattern, with: repl, options: .regularExpression)
            }

            // Insert prosodic breathing commas before conjunctions in long sentences
            let conjunctions = ["tuy nhiên", "mặt khác", "đồng thời", "do đó", "vì vậy", "ngoài ra", "hơn nữa", "thực ra", "nói cách khác"]
            for conj in conjunctions {
                s = s.replacingOccurrences(of: " (?<!, )" + conj, with: ", " + conj, options: [.regularExpression, .caseInsensitive])
            }
        } else if languageLocale.hasPrefix("en") {
            let replacements: [(String, String)] = [
                ("%", " percent "),
                ("\\$", " dollars "),
                ("€", " euros "),
                ("¥", " yen "),
                ("&", " and "),
                ("\\betc\\.?\\b", "etcetera"),
                ("\\be\\.g\\.?\\b", "for example"),
                ("\\bi\\.e\\.?\\b", "that is"),
                ("\\s*/\\s*", " or ")
            ]
            for (pattern, repl) in replacements {
                s = s.replacingOccurrences(of: pattern, with: repl, options: .regularExpression)
            }
        }

        // Collapse multiple spaces
        s = s.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        return s.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // Manual playback of a specific caption/text
    public func speak(id: UUID? = nil, text: String, language: AppLanguage) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        // If already speaking this exact caption or text, toggle pause/stop
        if isSpeaking && (currentlySpeakingText == trimmed || (currentlySpeakingCaptionID == id && id != nil)) {
            stop()
            return
        }

        stop()
        currentlySpeakingCaptionID = id
        currentlySpeakingText = trimmed
        playUtterance(text: trimmed, language: language)
    }

    // Quick Voice & Tone Preview
    public func preview(text: String? = nil, language: AppLanguage = .vietnamese) {
        let sampleText: String
        if let text = text, !text.isEmpty {
            sampleText = text
        } else {
            switch language {
            case .vietnamese:
                sampleText = "Xin chào! Đây là trợ lý dịch thuật TransTools. Giọng đọc tự nhiên, rõ ràng và chuẩn ngữ cảnh."
            case .english, .englishIndia:
                sampleText = "Hello! This is TransTools live earphone interpreter. Speaking clearly and naturally."
            default:
                sampleText = "Xin chào! Đây là trợ lý dịch thuật TransTools."
            }
        }
        stop()
        playUtterance(text: sampleText, language: language)
    }

    // Called automatically by MeetingModel when a caption is finalized and translated
    public func enqueueAutoTTS(id: UUID, original: String, translation: String, sourceLang: AppLanguage, targetLang: AppLanguage) {
        guard isAutoTTSEnabled else { return }
        guard !spokenCaptionIDs.contains(id) else { return }

        let textToSpeak: String
        let langToUse: AppLanguage
        switch autoTarget {
        case .translation:
            let trans = translation.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trans.isEmpty else { return }
            textToSpeak = trans
            langToUse = targetLang
        case .original:
            let orig = original.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !orig.isEmpty else { return }
            textToSpeak = orig
            langToUse = sourceLang
        }

        spokenCaptionIDs.insert(id)

        // Keep real-time queue short so we never lag behind the speaker
        if speechQueue.count >= 2 {
            speechQueue.removeFirst()
        }
        speechQueue.append((id: id, text: textToSpeak, language: langToUse))

        if !isSpeaking {
            processNextInQueue()
        }
    }

    private func processNextInQueue() {
        guard !speechQueue.isEmpty else {
            isSpeaking = false
            currentlySpeakingCaptionID = nil
            currentlySpeakingText = nil
            return
        }
        let item = speechQueue.removeFirst()
        currentlySpeakingCaptionID = item.id
        currentlySpeakingText = item.text
        playUtterance(text: item.text, language: item.language)
    }

    private func playUtterance(text: String, language: AppLanguage) {
        let cleaned = Self.normalizeForSpeech(text, languageLocale: language.speechLocale)
        guard !cleaned.isEmpty else {
            processNextInQueue()
            return
        }

        let utterance = AVSpeechUtterance(string: cleaned)
        let effectiveRate = max(0.25, min(0.75, speechRate + voiceTone.rateModifier))
        utterance.rate = effectiveRate
        utterance.volume = speechVolume
        utterance.pitchMultiplier = voiceTone.pitchMultiplier
        utterance.preUtteranceDelay = 0.06
        utterance.postUtteranceDelay = voiceTone.postDelay

        // Select best or user-chosen voice for the locale
        if let voice = bestVoice(for: language.speechLocale) {
            utterance.voice = voice
        } else if let fallbackVoice = AVSpeechSynthesisVoice(language: language.speechLocale) {
            utterance.voice = fallbackVoice
        }

        isSpeaking = true
        synthesizer.speak(utterance)
    }

    public func stop() {
        speechQueue.removeAll()
        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }
        isSpeaking = false
        currentlySpeakingCaptionID = nil
        currentlySpeakingText = nil
    }

    public func clearHistory() {
        spokenCaptionIDs.removeAll()
        speechQueue.removeAll()
        stop()
    }

    // Available voices for a specific locale
    public func availableVoices(for locale: String) -> [TTSVoiceOption] {
        let prefix = String(locale.prefix(2)).lowercased()
        let allVoices = AVSpeechSynthesisVoice.speechVoices().filter {
            $0.language.lowercased() == locale.lowercased() || $0.language.lowercased().starts(with: prefix)
        }

        var seen = Set<String>()
        var options: [TTSVoiceOption] = []

        let sorted = allVoices.sorted { v1, v2 in
            let q1 = (v1.quality == .premium ? 3 : (v1.quality == .enhanced ? 2 : 1))
            let q2 = (v2.quality == .premium ? 3 : (v2.quality == .enhanced ? 2 : 1))
            if q1 != q2 { return q1 > q2 }
            return v1.name < v2.name
        }

        for v in sorted {
            let key = "\(v.name)_\(v.quality.rawValue)"
            if !seen.contains(key) {
                seen.insert(key)
                options.append(TTSVoiceOption(voice: v))
            }
        }
        return options
    }

    // Best voice picker (Prioritizes Siri Neural / Premium / Enhanced voices)
    public func bestVoice(for locale: String) -> AVSpeechSynthesisVoice? {
        // If user manually chose a voice and it matches the locale, respect it
        if let customID = selectedVoiceID, !customID.isEmpty,
           let chosenVoice = AVSpeechSynthesisVoice(identifier: customID),
           (chosenVoice.language.lowercased() == locale.lowercased() || chosenVoice.language.lowercased().starts(with: locale.prefix(2).lowercased())) {
            return chosenVoice
        }

        let prefix = String(locale.prefix(2)).lowercased()
        let voices = AVSpeechSynthesisVoice.speechVoices().filter {
            $0.language.lowercased() == locale.lowercased() || $0.language.lowercased().starts(with: prefix)
        }

        // 1. Check for Neural / Siri voices (e.g. gryphon-neural or siri.natural)
        if let neural = voices.first(where: {
            let id = $0.identifier.lowercased()
            return (id.contains("gryphon-neural") || id.contains("siri.natural")) && $0.quality != .default
        }) {
            return neural
        }

        // 2. Check for Premium quality
        if let premium = voices.first(where: { $0.quality == .premium }) {
            return premium
        }

        // 3. Check for Enhanced quality
        if let enhanced = voices.first(where: { $0.quality == .enhanced }) {
            return enhanced
        }

        // 4. Fallback to standard
        return voices.first ?? AVSpeechSynthesisVoice(language: locale)
    }

    // AVSpeechSynthesizerDelegate
    nonisolated public func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor in
            self.processNextInQueue()
        }
    }

    nonisolated public func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        Task { @MainActor in
            self.isSpeaking = false
            self.currentlySpeakingCaptionID = nil
            self.currentlySpeakingText = nil
        }
    }
}
