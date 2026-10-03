import Foundation

public protocol ProsodyProcessing: Sendable {
    func process(
        text: String,
        context: ConversationContext
    ) -> ProsodyResult
}

public final class RuleBasedProsodyProcessor: ProsodyProcessing {
    public static let shared = RuleBasedProsodyProcessor()

    public init() {}

    public func process(
        text: String,
        context: ConversationContext
    ) -> ProsodyResult {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return ProsodyResult(text: "", emotion: .neutral, rate: 0.44)
        }

        let lang = context.detectedLanguage.lowercased()
        let isVietnamese = lang.hasPrefix("vi")
        let isEnglish = lang.hasPrefix("en")
        let isJapanese = lang.hasPrefix("ja")
        let isChinese = lang.hasPrefix("zh")
        let isKorean = lang.hasPrefix("ko")

        // 1. Detect Semantic Emotion
        var emotion: SpeechEmotion = .statement
        var rateAdjustment: Float = 0.0

        let lower = trimmed.lowercased()

        // Check for Correction / Disagreement / Clarification
        let isCorrection: Bool
        if isVietnamese {
            isCorrection = lower.hasPrefix("không,") ||
                lower.hasPrefix("không ") ||
                lower.hasPrefix("không phải") ||
                lower.hasPrefix("sai rồi") ||
                lower.hasPrefix("nhầm rồi") ||
                lower.hasPrefix("chưa đúng") ||
                lower.hasPrefix("đâu phải") ||
                lower.contains("không phải như") ||
                lower.contains("không phải là")
        } else if isEnglish {
            isCorrection = lower.hasPrefix("no,") ||
                lower.hasPrefix("actually,") ||
                lower.hasPrefix("not really") ||
                lower.hasPrefix("that's not") ||
                lower.hasPrefix("i didn't mean")
        } else if isJapanese {
            isCorrection = lower.hasPrefix("いいえ") || lower.hasPrefix("ちがいます") || lower.hasPrefix("違います")
        } else if isChinese {
            isCorrection = lower.hasPrefix("不是") || lower.hasPrefix("不对") || lower.hasPrefix("没有")
        } else if isKorean {
            isCorrection = lower.hasPrefix("아니요") || lower.hasPrefix("아닙니다") || lower.hasPrefix("틀렸")
        } else {
            isCorrection = lower.hasPrefix("no")
        }

        // Check Contextual cues: if partner asked a question and speaker replies negatively
        let partnerAskedQuestion = context.recentUtterances.last?.text.contains("?") ?? false

        if isCorrection || (partnerAskedQuestion && (lower.hasPrefix("không") || lower.hasPrefix("no"))) {
            emotion = .correction
            rateAdjustment = -0.04 // slightly slower, deliberative pace (~0.91x - 0.92x)
        } else if trimmed.hasSuffix("?") || lower.contains("phải không") || lower.contains("đúng không") || lower.contains("sao?") {
            emotion = .question
            rateAdjustment = 0.01
        } else if trimmed.hasSuffix("!") || lower.contains("tuyệt vời") || lower.contains("hay quá") || lower.contains("wow") || lower.contains("awesome") {
            emotion = .excitement
            rateAdjustment = 0.04
        } else if lower.hasPrefix("đúng rồi") || lower.hasPrefix("chính xác") || lower.hasPrefix("vâng") || lower.hasPrefix("dạ") || lower.hasPrefix("yes") || lower.hasPrefix("exactly") {
            emotion = .confirmation
            rateAdjustment = 0.0
        } else if lower.contains("...") || lower.hasPrefix("ừm") || lower.hasPrefix("à,") || lower.hasPrefix("well,") || lower.hasPrefix("um,") {
            emotion = .hesitation
            rateAdjustment = -0.06
        } else if lower.contains("đừng lo") || lower.contains("không sao đâu") || lower.contains("cứ từ từ") || lower.contains("don't worry") || lower.contains("no problem") {
            emotion = .gentleResponse
            rateAdjustment = -0.03
        } else {
            emotion = .statement
            rateAdjustment = 0.0
        }

        let baseRate: Float = 0.44
        let finalRate = max(0.35, min(0.65, baseRate + rateAdjustment))

        // 2. Identify Semantic Emphasis Ranges (Never just uppercase)
        var emphasisRanges: [TextRange] = []
        let emphasisKeywords: [String]
        if isVietnamese {
            emphasisKeywords = ["không phải", "rất quan trọng", "nhất định", "tuyệt đối", "đặc biệt", "chính là", "thực sự", "cực kỳ"]
        } else if isEnglish {
            emphasisKeywords = ["not", "never", "definitely", "crucial", "especially", "absolutely", "important"]
        } else if isJapanese {
            emphasisKeywords = ["絶対に", "特に", "本当に", "重要"]
        } else if isChinese {
            emphasisKeywords = ["不是", "非常", "特别", "一定", "绝对"]
        } else if isKorean {
            emphasisKeywords = ["아닙니다", "정말로", "반드시", "특별히"]
        } else {
            emphasisKeywords = ["not", "crucial", "important"]
        }

        for keyword in emphasisKeywords {
            var searchRange = trimmed.startIndex..<trimmed.endIndex
            while let range = trimmed.range(of: keyword, options: .caseInsensitive, range: searchRange) {
                let location = trimmed.distance(from: trimmed.startIndex, to: range.lowerBound)
                let length = trimmed.distance(from: range.lowerBound, to: range.upperBound)
                let matchedText = String(trimmed[range])
                let intensity: Float = (emotion == .correction && keyword.contains("không")) ? 0.70 : 0.60
                emphasisRanges.append(TextRange(location: location, length: length, intensity: intensity, matchedText: matchedText))
                searchRange = range.upperBound..<trimmed.endIndex
            }
        }

        // 3. Compute Speech Pauses
        var pauses: [SpeechPause] = []
        let punctuationPauseMap: [Character: (TimeInterval, String)] = [
            ",": (0.35, "comma_boundary"),
            ";": (0.30, "semicolon_boundary"),
            ":": (0.30, "colon_boundary"),
            ".": (0.45, "sentence_period"),
            "!": (0.45, "sentence_exclamation"),
            "?": (0.45, "sentence_question"),
            "—": (0.35, "em_dash_boundary"),
            "-": (0.25, "dash_boundary")
        ]

        var charIndex = 0
        for char in trimmed {
            charIndex += 1
            if let (pauseDuration, reason) = punctuationPauseMap[char] {
                // If it's a comma right after a discourse particle like "Không,", ensure duration is natural
                let effectiveDuration: TimeInterval
                if char == "," && charIndex <= 10 && (lower.hasPrefix("không") || lower.hasPrefix("no")) {
                    effectiveDuration = 0.35
                } else {
                    effectiveDuration = pauseDuration
                }
                pauses.append(SpeechPause(offset: charIndex, duration: effectiveDuration, reason: reason))
            }
        }

        return ProsodyResult(
            text: trimmed,
            emotion: emotion,
            rate: finalRate,
            emphasis: emphasisRanges,
            pauses: pauses
        )
    }
}
