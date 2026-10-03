import Foundation

public enum SpeechEmotion: String, CaseIterable, Codable, Sendable {
    case neutral = "neutral"
    case question = "question"
    case statement = "statement"
    case correction = "correction"
    case confirmation = "confirmation"
    case excitement = "excitement"
    case hesitation = "hesitation"
    case gentleResponse = "gentleResponse"

    public var displayName: String {
        switch self {
        case .neutral: return "Bình thường"
        case .question: return "Hỏi"
        case .statement: return "Trần thuật"
        case .correction: return "Đính chính / Phản hồi"
        case .confirmation: return "Xác nhận / Đồng ý"
        case .excitement: return "Hào hứng / Nhấn mạnh"
        case .hesitation: return "Ngập ngừng / Suy nghĩ"
        case .gentleResponse: return "Nhẹ nhàng / An ủi"
        }
    }
}
