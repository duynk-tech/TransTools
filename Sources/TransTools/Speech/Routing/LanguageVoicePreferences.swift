import Foundation

/// Overrides are keyed by the language of the utterance, not the UI language.
public enum LanguageVoiceEngine: String, CaseIterable, Identifiable {
    case automatic, local, vieneu, qwen, system, edge
    public var id: String { rawValue }
    var isLocal: Bool { self == .local || self == .vieneu || self == .qwen }
    var externalModel: ExternalTTSModel? { self == .vieneu ? .vieneu : self == .qwen ? .qwen : nil }
    func supports(_ language: String) -> Bool {
        guard let externalModel else { return true }
        return externalModel.availableOnDevice && externalModel.languages.contains(LanguageVoicePreferences.code(language))
    }
    var title: String {
        switch self {
        case .automatic: return "Theo cấu hình mặc định"
        case .local: return "Supertonic 3 · Offline"
        case .vieneu: return "VieNeu-TTS v3 Turbo · Offline"
        case .qwen: return "Qwen3-TTS 0.6B · Offline"
        case .system: return "Giọng cơ bản · Offline"
        case .edge: return "Giọng AI trực tuyến · Edge"
        }
    }
}

enum LanguageVoicePreferences {
    static func code(_ locale: String) -> String {
        locale.lowercased().replacingOccurrences(of: "_", with: "-").split(separator: "-").first.map(String.init) ?? locale
    }
    static func selection(for locale: String, defaults: UserDefaults = .standard) -> LanguageVoiceEngine {
        LanguageVoiceEngine(rawValue: defaults.string(forKey: "TTS_LanguageEngine_" + code(locale)) ?? "") ?? .automatic
    }
    static func set(_ engine: LanguageVoiceEngine, for locale: String, defaults: UserDefaults = .standard) {
        defaults.set(engine.rawValue, forKey: "TTS_LanguageEngine_" + code(locale))
    }
    static func resolve(_ selection: LanguageVoiceEngine, localDefault: Bool, edgeDefault: Bool) -> LanguageVoiceEngine {
        selection == .automatic ? (localDefault ? .local : edgeDefault ? .edge : .system) : selection
    }
    /// Offline fallback is deterministic and never starts an installation or a network request.
    static func route(requested: LanguageVoiceEngine, available: Set<LanguageVoiceEngine>) -> LanguageVoiceEngine {
        guard requested == .local || requested == .vieneu else { return requested }
        if available.contains(requested) { return requested }
        if available.contains(.vieneu) { return .vieneu }
        if available.contains(.local) { return .local }
        return .system
    }
    static func resolved(for locale: String, localDefault: Bool, edgeDefault: Bool) -> LanguageVoiceEngine {
        resolve(selection(for: locale), localDefault: localDefault, edgeDefault: edgeDefault)
    }
}
