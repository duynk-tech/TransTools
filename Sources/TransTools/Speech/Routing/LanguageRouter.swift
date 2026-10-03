import Foundation
import os.log

public enum EngineRoutingDecision: Equatable, Sendable {
    case localNatural
    case system(reason: String)
}

public struct TTSDiagnosticsLog: Sendable {
    public let timestamp: Date
    public let language: String
    public let engine: String
    public let prosodyEmotion: String?
    public let latencyMs: Int
    public let reason: String?
    public let privacyNote: String

    public var formattedSummary: String {
        var lines = [
            "[TTS]",
            "Language: \(language)",
            "Engine: \(engine)"
        ]
        if let prosody = prosodyEmotion {
            lines.append("Prosody: \(prosody)")
        }
        if let reason = reason {
            lines.append("Reason: \(reason)")
        }
        lines.append("Latency: \(latencyMs) ms")
        lines.append("Privacy: \(privacyNote)")
        return lines.joined(separator: "\n")
    }
}

public final class LanguageRouter: @unchecked Sendable {
    public static let shared = LanguageRouter()

    private let logger = Logger(subsystem: "local.mactools.transtools", category: "TTS")

    private init() {}

    /// Determine optimal TTS engine based on user preference, model availability, and language support
    public func resolveEngine(
        for language: String,
        preference: TTSEnginePreference,
        isModelInstalled: Bool,
        localSupportedLanguages: [String]
    ) -> EngineRoutingDecision {
        guard preference == .localNatural else {
            return .system(reason: "userSelectedSystemVoice")
        }

        guard isModelInstalled else {
            return .system(reason: "modelNotInstalled")
        }

        let normalized = language.lowercased()
        let isSupported = localSupportedLanguages.contains { supported in
            let sNorm = supported.lowercased()
            return sNorm.split(separator: "-").first == normalized.split(separator: "-").first
        }

        guard isSupported else {
            return .system(reason: "unsupportedLocalLanguage")
        }

        return .localNatural
    }

    /// Logs diagnostic information without exposing private user conversation text
    public func logExecution(
        language: String,
        engine: String,
        prosodyEmotion: String?,
        latencyMs: Int,
        reason: String? = nil,
        isLocal: Bool
    ) {
        let privacyNote = isLocal ? "Processed on this Mac (100% on-device)" : "System Speech Engine"
        let logEntry = TTSDiagnosticsLog(
            timestamp: Date(),
            language: language,
            engine: engine,
            prosodyEmotion: prosodyEmotion,
            latencyMs: latencyMs,
            reason: reason,
            privacyNote: privacyNote
        )

        #if DEBUG
        // Print structured log as required by specification
        print(logEntry.formattedSummary)

        // OSLog structured entry for Console.app
        logger.info("\(logEntry.formattedSummary, privacy: .public)")
        #endif
    }
}
