import Foundation
import AppKit

struct MeetingActionItem: Identifiable, Codable, Equatable {
    let id: UUID
    var title: String
    var assignee: String
    var isCompleted: Bool

    init(id: UUID = UUID(), title: String, assignee: String = "", isCompleted: Bool = false) {
        self.id = id
        self.title = title
        self.assignee = assignee
        self.isCompleted = isCompleted
    }
}

@MainActor
final class MeetingTaskExtractorService: ObservableObject {
    static let shared = MeetingTaskExtractorService()

    @Published var isExtracting: Bool = false
    @Published var actionItems: [MeetingActionItem] = []
    @Published var lastNotice: String = ""

    private init() {}

    /// Trích xuất danh sách công việc cần làm từ transcript cuộc họp
    func extractActionItems(from session: MeetingSession, model: MeetingModel? = nil) async -> [MeetingActionItem] {
        isExtracting = true
        defer { isExtracting = false }

        let fullTranscript = session.captions.map {
            if !$0.vietnamese.isEmpty {
                return "\($0.original) (\($0.vietnamese))"
            }
            return $0.original
        }.joined(separator: "\n")

        guard !fullTranscript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return []
        }

        // 1. Thử dùng AI nếu người dùng đã cấu hình AI key
        if let ai = model?.configuredAI ?? MeetingModel.shared?.configuredAI {
            if let aiItems = await extractWithAI(transcript: fullTranscript, provider: ai.provider, model: ai.model, key: ai.key) {
                self.actionItems = aiItems
                return aiItems
            }
        }

        // 2. Phân tích tự động on-device thông minh qua từ khóa hành động
        let smartItems = extractWithSmartRules(session: session)
        self.actionItems = smartItems
        return smartItems
    }

    private func extractWithSmartRules(session: MeetingSession) -> [MeetingActionItem] {
        var items: [MeetingActionItem] = []
        let actionKeywords = [
            "cần ", "sẽ ", "phải ", "nhờ ", "gửi ", "kiểm tra", "chuẩn bị", "báo cáo", "review",
            "deadline", "update", "deploy", "fix", "follow up", "hạn chót", "ngày mai", "tuần sau",
            "will do", "need to", "must", "please", "action item", "todo", "assign"
        ]

        for cap in session.captions {
            let text = cap.vietnamese.isEmpty ? cap.original : cap.vietnamese
            let lower = text.lowercased()

            for kw in actionKeywords {
                if lower.contains(kw) && text.count > 10 && text.count < 150 {
                    let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !items.contains(where: { $0.title == cleaned }) {
                        items.append(MeetingActionItem(title: cleaned, assignee: "Nhóm họp"))
                    }
                    break
                }
            }
            if items.count >= 8 { break }
        }

        if items.isEmpty && !session.captions.isEmpty {
            items.append(MeetingActionItem(title: "Theo dõi và tổng hợp nội dung cuộc họp \"\(session.title)\"", assignee: "Tôi"))
        }

        return items
    }

    private func extractWithAI(transcript: String, provider: AIProvider, model: String, key: String) async -> [MeetingActionItem]? {
        let prompt = """
        Hãy phân tích biên bản cuộc họp sau và trích xuất danh sách các việc cần làm (action items, việc ai cần làm, deadline).
        Trả về DUY NHẤT một mảng JSON hợp lệ, không bọc markdown, theo định dạng:
        [{"title": "Nhiệm vụ cụ thể cần làm", "assignee": "Người phụ trách hoặc Không rõ"}]

        Biên bản cuộc họp:
        \(transcript.prefix(6000))
        """

        guard let response = try? await AITranslator.callAI(prompt: prompt, provider: provider, model: model, key: key) else {
            return nil
        }

        let cleaned = response.replacingOccurrences(of: "```json", with: "")
            .replacingOccurrences(of: "```", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard let data = cleaned.data(using: .utf8),
              let jsonArray = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            return nil
        }

        var results: [MeetingActionItem] = []
        for dict in jsonArray {
            if let title = dict["title"] as? String, !title.isEmpty {
                let assignee = dict["assignee"] as? String ?? ""
                results.append(MeetingActionItem(title: title, assignee: assignee))
            }
        }
        return results.isEmpty ? nil : results
    }

    /// Tự động thêm danh sách công việc vào ứng dụng Apple Reminders của macOS
    func exportToAppleReminders(items: [MeetingActionItem], sessionTitle: String) -> Bool {
        guard !items.isEmpty else { return false }

        var scriptLines = [
            "tell application \"Reminders\"",
            "    set listName to \"Việc cần làm TransTools\"",
            "    if not (exists list listName) then",
            "        make new list with properties {name:listName}",
            "    end if",
            "    set targetList to list listName"
        ]

        for item in items {
            let safeTitle = item.title.replacingOccurrences(of: "\"", with: "\\\"")
            let safeBody = "Trích xuất từ cuộc họp: \(sessionTitle)\(item.assignee.isEmpty ? "" : " • Phụ trách: \(item.assignee)")".replacingOccurrences(of: "\"", with: "\\\"")
            scriptLines.append("    make new reminder at end of targetList with properties {name:\"\(safeTitle)\", body:\"\(safeBody)\"}")
        }

        scriptLines.append("end tell")

        let fullScript = scriptLines.joined(separator: "\n")
        var errorDict: NSDictionary?
        if let script = NSAppleScript(source: fullScript) {
            script.executeAndReturnError(&errorDict)
            if errorDict == nil {
                lastNotice = "Đã thêm \(items.count) việc vào Apple Reminders thành công!"
                return true
            }
        }
        lastNotice = "Không thể thêm vào Reminders."
        return false
    }
}
