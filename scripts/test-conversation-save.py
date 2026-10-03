#!/usr/bin/env python3
"""Exercise production chat snapshot and notebook persistence in a temporary directory."""
from pathlib import Path
import subprocess, tempfile
root = Path(__file__).resolve().parent.parent
app = (root/'Sources/TransTools/App.swift').read_text()
chat = (root/'Sources/TransTools/AIConversation.swift').read_text()
learning = (root/'Sources/TransTools/LanguageLearning.swift').read_text()
languages = learning[learning.index('public enum LearningLanguage:'):learning.index('public enum LearningLevel:')]
restore = chat[chat.index('    func restore('):chat.index('    func refreshTranslations()')]
records = app[app.index('struct MeetingSession:'):app.index('// MARK: - Chip Chip Mascot')]
turn = chat[chat.index('private struct ConversationTurn:'):chat.index('@MainActor private final class')]
deletion = app[app.index('    func deleteConversationSession('):app.index('    func deleteSession(')]
persist = app[app.index('    private func persistSessions('):app.index('    func saveCurrentSession(')]
current = app[app.index('    func saveCurrentSession('):app.index('    func updateSessionTitle(')]
snapshot = chat[chat.index('    @discardableResult\n    func saveConversation('):chat.index('    func updateSavedConversation()')]
code = 'import Foundation\n' + records + (root/'Sources/TransTools/SessionStore.swift').read_text().replace('import Foundation', '') + turn + languages + '''
@MainActor class MeetingModel {
 var captions: [CaptionRecord] = []; var started = Date(); var recordingSessionID = UUID(); var status = ""
 func currentSourceName() -> String { "System" }
 var storageError: String?
 var configuredAI: String? = "test-provider"
 var sessions: [MeetingSession] = []
 var selectedSessionID: UUID?
 var sessionsFileURL: URL
 init(url: URL) { sessionsFileURL = url }
''' + persist + current + deletion + '''
}
@MainActor class LanguageLearningManager {
 struct Title { var title: String }
 var selectedLanguage = LearningLanguage.english
 var selectedLevel = Title(title: "A2")
 var selectedGoal = Title(title: "Giao tiếp công việc")
}
@MainActor private class Probe {
 var ai: String?
 var turns: [ConversationTurn] = []
 var sessionID = UUID()
 var sessionStarted = Date()
 var sessionEnded: Date?
 var hasSaved = false
 var saveStatus = ""
 var language = LearningLanguage.english
 var resumeLoaded = false
 var retainedTitle: String?
 var retainedNotes = ""
 var resumedAt: Date?
 var previousDuration: TimeInterval = 0
 var restoredOffsets: [UUID: TimeInterval] = [:]
 var suggestions: [String] = []
 var feedback = ""
 var status = ""
 var notebookModel: MeetingModel?
 func stop() {}
 func refreshTranslations() {}
 var level = "A2"
 var goal = "Giao tiếp công việc"
''' + snapshot + restore + '''
}
@main struct Main {
 @MainActor static func main() throws {
 let url = URL(fileURLWithPath: CommandLine.arguments[1]).appendingPathComponent("sessions.json")
 let model = MeetingModel(url: url), probe = Probe()
 precondition(!probe.saveConversation(model: model))
 probe.turns = [ConversationTurn(speaker: "Bạn", text: "Hello", translation: "Xin chào"), ConversationTurn(speaker: "AI", text: "How are you?", feedback: "Nhớ thêm chủ ngữ.", translation: "Bạn khỏe không?")]
 precondition(probe.saveConversation(model: model))
 let firstID = model.sessions[0].id
 precondition(model.sessions.count == 1 && model.sessions[0].captions.count == 2)
 precondition(model.sessions[0].captions[0].original == "[Bạn] Hello")
 precondition(model.sessions[0].captions[1].original == "[Chip Chip] How are you?")
 precondition(model.sessions[0].notes.contains("Nhớ thêm chủ ngữ."))
 probe.turns.append(ConversationTurn(speaker: "Bạn", text: "I'm fine."))
 precondition(probe.saveConversation(model: model))
 precondition(model.sessions.count == 1 && model.sessions[0].id == firstID && model.sessions[0].captions.count == 3)
 let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
 let disk = try decoder.decode([MeetingSession].self, from: Data(contentsOf: url))
 precondition(disk[0].captions == model.sessions[0].captions)
 precondition(disk[0].captions[0].vietnamese == "Xin chào")
 let saved = model.sessions[0]
 let restored = Probe()
 restored.restore(saved, model: model, manager: LanguageLearningManager())
 precondition(restored.turns.map { $0.id } == saved.captions.map { $0.id })
 precondition(restored.turns[0].speaker == "Bạn" && restored.turns[1].speaker == "AI")
 precondition(restored.turns[0].text == "Hello" && restored.turns[0].translation == "Xin chào")
 precondition(restored.ai == model.configuredAI)
 precondition(restored.resumeLoaded && restored.sessionID == saved.id && restored.hasSaved)
 restored.resumedAt = Date().addingTimeInterval(-0.2)
 restored.turns.append(ConversationTurn(speaker: "Bạn", text: "Let's continue."))
 precondition(restored.saveConversation(model: model))
 precondition(model.sessions.count == 1 && model.sessions[0].captions.count == 4)
 precondition(model.sessions[0].captions[0].start == saved.captions[0].start)
 precondition(model.sessions[0].createdAt == saved.createdAt)
 let old = model.sessions
 model.sessionsFileURL = url.appendingPathComponent("missing/file.json")
 precondition(!probe.saveConversation(model: model))
 precondition(model.sessions == old && probe.saveStatus.hasPrefix("Chưa lưu được"))
 model.sessionsFileURL = url
 let meeting = MeetingSession(title: "Meeting", durationSeconds: 1, audioSource: "System", notes: "", captions: [])
 try model.saveConversationSession(meeting)
 try model.deleteConversationSession(id: firstID)
 precondition(!model.sessions.contains { $0.id == firstID })
 precondition(model.sessions.contains { $0.id == meeting.id })
 let remaining = model.sessions
 model.sessionsFileURL = url.appendingPathComponent("missing/file.json")
 do { try model.deleteConversationSession(id: meeting.id); preconditionFailure("Expected write failure") }
 catch { precondition(model.sessions == remaining) }
 model.sessionsFileURL = url
 model.captions = [CaptionRecord(id: UUID(), start: 0, end: 1, original: "Hello", vietnamese: "Xin chào")]
 model.saveCurrentSession(customTitle: "Named", notes: "Kept")
 let recordingID = model.selectedSessionID
 model.saveCurrentSession()
 precondition(model.selectedSessionID == recordingID)
 precondition(model.sessions.first { $0.id == recordingID }?.title == "Named")
 precondition(model.sessions.first { $0.id == recordingID }?.notes == "Kept")
 model.recordingSessionID = UUID()
 model.saveCurrentSession()
 precondition(model.selectedSessionID != recordingID && model.sessions.filter { $0.audioSource == "System" }.count == 3)
 let backup = url.appendingPathExtension("backup")
 precondition(FileManager.default.fileExists(atPath: backup.path))
 try Data("broken json".utf8).write(to: url)
 let recovered = try SessionStore.load(from: url)
 precondition(recovered.recovered && !recovered.sessions.isEmpty)
 try SessionStore.write(recovered.sessions, to: url)
 let repaired = try SessionStore.load(from: url)
 precondition(!repaired.recovered)
 let isolated = url.deletingLastPathComponent().appendingPathComponent("isolated.json")
 try Data("broken".utf8).write(to: isolated)
 do { try SessionStore.write([], to: isolated); preconditionFailure("Must preserve corrupt file") }
 catch { let intact = try Data(contentsOf: isolated); precondition(intact == Data("broken".utf8)) }
 print("PASS: chat roles, translations, feedback, stable session ID, disk reload, and failed-write preservation")
 }
}
'''
with tempfile.TemporaryDirectory(prefix='conversation-save-') as directory:
    swift = Path(directory)/'test.swift'; swift.write_text(code)
    binary = Path(directory)/'test'
    subprocess.run(['swiftc', '-parse-as-library', str(swift), '-o', str(binary)], check=True)
    subprocess.run([str(binary), directory], check=True)
