import SwiftUI
import CryptoKit

struct AdaptiveLesson: Codable, Identifiable, Equatable {
    let id: String
    let language: String
    let goal: String
    let original: String
    let meaning: String
    let context: String
    static func make(language: String, goal: String, original: String, meaning: String, context: String) -> Self {
        let key = language + "|" + goal + "|" + original
        let id = SHA256.hash(data: Data(key.utf8)).map { String(format: "%02x", $0) }.joined()
        return .init(id: id, language: language, goal: goal, original: original, meaning: meaning, context: context)
    }
}
struct LessonProgress: Codable {
    var attempts = 0
    var successes = 0
    var successfulDays: [String] = []
    var difficulty = 1
    var due = Date.distantPast
    var lastAttempt: Date?
    mutating func record(correct: Bool, now: Date, calendar: Calendar = .current) {
        attempts += 1; lastAttempt = now
        if correct {
            successes += 1
            let day = String(calendar.startOfDay(for: now).timeIntervalSince1970)
            if !successfulDays.contains(day) { successfulDays.append(day) }
            // Repeated clicks in one session never count as sustained progress.
            if successfulDays.count >= 3 && successes * 5 >= attempts * 4 {
                difficulty = min(3, difficulty + 1); successfulDays = []
            }
        } else { successfulDays = []; difficulty = max(1, difficulty - 1) }
        due = calendar.date(byAdding: .day, value: correct ? (difficulty == 3 ? 7 : 2) : 1, to: now) ?? now
    }
}
struct LearningGenerationProfile {
    let practicedSentences: Int
    let accuracyPercent: Int?
    let sentencesNeedingReview: Int
    let advancedSentences: Int
    init(lessons: [AdaptiveLesson], progress: [String: LessonProgress], language: String, goal: String) {
        let ids = Set(lessons.filter { $0.language == language && $0.goal == goal }.map(\.id))
        let recent = ids.compactMap { progress[$0] }.filter { $0.attempts > 0 }.sorted {
            ($0.lastAttempt ?? .distantPast) > ($1.lastAttempt ?? .distantPast)
        }.prefix(20)
        practicedSentences = recent.count
        let attempts = recent.reduce(0) { $0 + max(0, $1.attempts) }
        let successes = recent.reduce(0) { $0 + min(max(0, $1.successes), max(0, $1.attempts)) }
        accuracyPercent = attempts > 0 ? Int((Double(successes) / Double(attempts) * 100).rounded()) : nil
        sentencesNeedingReview = recent.filter { $0.successes < $0.attempts }.count
        advancedSentences = recent.filter { $0.difficulty >= 3 }.count
    }
    var promptContext: String {
        guard let accuracyPercent else { return "No recorded practice for this language and goal. Begin at the selected level with useful everyday examples." }
        return "Recent practice summary: \(practicedSentences) sentences, \(accuracyPercent)% correct, \(sentencesNeedingReview) sentences with mistakes, \(advancedSentences) sentences at recall level. " +
            (accuracyPercent < 70 ? "Prioritize short, clear examples and reinforce foundations; do not increase difficulty yet." : "Use varied situations at the selected level; include a small stretch without jumping proficiency levels.")
    }
}
struct AdaptiveLearningArchive: Codable {
    var schemaVersion = 1
    var progress: [String: LessonProgress] = [:]
    var lessons: [AdaptiveLesson] = []
}
@MainActor
final class AdaptiveLearningStore: ObservableObject {
    static let shared = AdaptiveLearningStore()
    @Published private(set) var archive = AdaptiveLearningArchive()
    @Published private(set) var generating = false
    @Published private(set) var status = ""
    private let url = LocalTTSModelStore.base.deletingLastPathComponent().appendingPathComponent("Learning/adaptive-v1.json")
    private var canSave = true
    private init() {
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        do {
            let saved = try JSONDecoder().decode(AdaptiveLearningArchive.self, from: Data(contentsOf: url))
            guard saved.schemaVersion == 1 else { throw ModelManagerError.invalidArtifact }
            archive = saved
        } catch {
            canSave = false
            status = "Chưa đọc được dữ liệu tiến bộ. Dữ liệu cũ được giữ nguyên; kết quả mới chưa thể lưu."
        }
    }
    func record(_ lesson: AdaptiveLesson, correct: Bool) {
        guard canSave else { return }
        let previous = archive
        var progress = archive.progress[lesson.id] ?? LessonProgress()
        progress.record(correct: correct, now: Date()); archive.progress[lesson.id] = progress
        if !save() { archive = previous }
    }
    @discardableResult private func save() -> Bool {
        guard canSave else { return false }
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(archive).write(to: url, options: .atomic)
            return true
        } catch {
            status = "Chưa lưu được tiến bộ: " + error.localizedDescription
            return false
        }
    }
    func plan(_ manager: LanguageLearningManager, now: Date = Date()) -> [AdaptiveLesson] {
        let language = manager.selectedLanguage.rawValue, goal = manager.selectedGoal.rawValue
        let builtIn = manager.getScenarios().flatMap { scenario in scenario.dialogues.map {
            AdaptiveLesson.make(language: language, goal: goal, original: $0.original, meaning: $0.translation, context: scenario.title)
        } }
        let daily = manager.getSentenceOfTheDay()
        let fallback = builtIn + [.make(language: language, goal: goal, original: daily.originalText, meaning: daily.vietnameseMeaning, context: daily.contextNote)]
        let custom = archive.lessons.filter { $0.language == language && $0.goal == goal }
        // Curated fallback is identified separately: it is not claimed to cover every goal.
        var seen = Set<String>()
        let candidates = (custom + fallback).filter { seen.insert($0.id).inserted }
        return candidates.filter { (archive.progress[$0.id]?.due ?? .distantPast) <= now }.sorted {
            let left = archive.progress[$0.id], right = archive.progress[$1.id]
            let a = left.map { Double($0.successes) / Double(max(1, $0.attempts)) } ?? 0.5
            let b = right.map { Double($0.successes) / Double(max(1, $0.attempts)) } ?? 0.5
            if a != b { return a < b }
            let dateA = left?.lastAttempt ?? .distantPast, dateB = right?.lastAttempt ?? .distantPast
            return dateA != dateB ? dateA < dateB : $0.id < $1.id
        }.prefix(max(2, manager.dailyMinutes / 2)).map { $0 }
    }
    func importNotebook(_ session: MeetingSession, manager: LanguageLearningManager) {
        guard canSave else { return }
        let previous = archive
        let pairs = NotebookLearningPolicy.candidates(session.captions, language: manager.selectedLanguage.rawValue)
        var added = 0
        for pair in pairs.prefix(20) where archive.lessons.count < 500 {
            let lesson = AdaptiveLesson.make(language: manager.selectedLanguage.rawValue, goal: manager.selectedGoal.rawValue, original: pair.original, meaning: pair.vietnamese, context: "Câu từ Sổ tay")
            if !archive.lessons.contains(where: { $0.id == lesson.id }) { archive.lessons.append(lesson); added += 1 }
        }
        guard save() else { archive = previous; return }
        status = "Đã thêm \(added) câu từ Sổ tay. Không gửi dữ liệu lên AI."
    }
    func generate(_ manager: LanguageLearningManager) async {
        guard !generating else { return }
        guard canSave else {
            status = "Chưa đọc được dữ liệu tiến bộ. Hãy kiểm tra dữ liệu trước khi tạo bài mới; bài có sẵn vẫn dùng được."
            return
        }
        guard archive.lessons.count < 500 else { status = "Đã lưu 500 câu. Hãy luyện và ôn các câu hiện có trước."; return }
        guard let ai = MenuBarManager.shared.voiceScriptAI else { status = "Cấu hình AI để tạo bài theo mục tiêu. Bài có sẵn vẫn dùng được không cần mạng."; return }
        let language = manager.selectedLanguage, goal = manager.selectedGoal, level = manager.selectedLevel
        let curated = manager.getScenarios().flatMap { scenario in scenario.dialogues.map {
            AdaptiveLesson.make(language: language.rawValue, goal: goal.rawValue, original: $0.original, meaning: $0.translation, context: scenario.title)
        } }
        let profile = LearningGenerationProfile(lessons: archive.lessons + curated, progress: archive.progress, language: language.rawValue, goal: goal.rawValue)
        generating = true; defer { generating = false }
        status = "Đang chuẩn bị bài mới…"
        struct Response: Decodable { struct Row: Decodable { let original: String; let meaning: String; let context: String }; let lessons: [Row] }
        do {
            let prompt = """
            Create 6 distinct short language learning sentences in \(language.displayName), for goal \(goal.title), level \(level.title).
            \(profile.promptContext)
            Each sentence must express a complete useful idea. Give accurate Vietnamese meaning and a brief Vietnamese context.
            Vary grammar and situations across the six examples; use the summary to adjust complexity, not to invent personal facts.
            Avoid names, personal facts and markdown. Return ONLY JSON: {"lessons":[{"original":"...","meaning":"...","context":"..."}]}.
            """
            let text = try await AITransport.complete(prompt: prompt, provider: ai.provider, model: ai.model, key: ai.key, timeout: 30)
            try Task.checkCancellation()
            guard let data = text.data(using: .utf8), data.count < 32_000 else { throw ModelManagerError.invalidArtifact }
            let response = try JSONDecoder().decode(Response.self, from: data)
            guard (3...8).contains(response.lessons.count), response.lessons.allSatisfy({ !$0.original.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !$0.meaning.isEmpty && $0.original.count <= 300 && $0.meaning.count <= 500 && $0.context.count <= 500 }) else { throw ModelManagerError.invalidArtifact }
            let lessons = response.lessons.map { AdaptiveLesson.make(language: language.rawValue, goal: goal.rawValue, original: $0.original, meaning: $0.meaning, context: $0.context) }
            let previous = archive
            for lesson in lessons where archive.lessons.count < 500 && !archive.lessons.contains(where: { $0.id == lesson.id }) { archive.lessons.append(lesson) }
            guard save() else { archive = previous; return }
            status = "Đã có bài mới. Nội dung do AI tạo, có thể có sai sót."
        } catch { status = "Chưa tạo được bài mới. " + error.localizedDescription }
    }
}
struct AdaptiveLearningCard: View {
    @ObservedObject var manager: LanguageLearningManager
    @ObservedObject private var store = AdaptiveLearningStore.shared
    @State private var lesson: AdaptiveLesson?
    @State private var answer = ""
    @State private var exerciseDifficulty = 1
    @State private var feedback: String?
    @State private var revealed = false
    @State private var choices: [String] = []
    @State private var generationTask: Task<Void, Never>?
    private var difficulty: Int { exerciseDifficulty }
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Bài học theo tiến bộ của bạn").font(.headline)
                Spacer()
                Button(store.generating ? "Đang tạo…" : "Tạo bài theo mục tiêu") {
                    generationTask = Task { await store.generate(manager); load() }
                }.buttonStyle(TransToolsActionButtonStyle()).disabled(store.generating)
            }
            Text("\(manager.selectedGoal.title) · Ưu tiên câu cần ôn; tăng thử thách sau nhiều ngày làm tốt.").font(.caption).foregroundStyle(.secondary)
            if let lesson {
                if !store.archive.lessons.contains(where: { $0.id == lesson.id }) {
                    Text("Câu có sẵn · Chủ yếu về công việc. Tạo bài bằng AI để luyện sát mục tiêu hơn.").font(.caption).foregroundStyle(.secondary)
                }
                Text(difficulty == 1 ? "Hiểu câu" : difficulty == 2 ? "Nghe và hiểu" : "Nhớ và viết lại").font(.subheadline.bold()).foregroundStyle(TransToolsTheme.accent)
                if difficulty == 1 || revealed { Text(lesson.original).font(.title3).textSelection(.enabled) }
                Button("Nghe câu") { TTSService.shared.speak(text: lesson.original, language: AppLanguage(rawValue: lesson.language) ?? .english) }.buttonStyle(TransToolsActionButtonStyle())
                if difficulty < 3 {
                    Text("Chọn nghĩa phù hợp:")
                    ForEach(choices, id: \.self) { choice in
                        Button(choice) { grade(choice == lesson.meaning) }.buttonStyle(TransToolsActionButtonStyle()).disabled(feedback != nil)
                    }
                } else {
                    Text(lesson.meaning)
                    TextField("Viết lại câu đã nghe…", text: $answer).textFieldStyle(.roundedBorder)
                    Button("Kiểm tra câu mẫu") { grade(Self.normalized(answer) == Self.normalized(lesson.original)) }.buttonStyle(TransToolsActionButtonStyle()).disabled(feedback != nil || answer.trimmingCharacters(in: .whitespaces).isEmpty)
                    Text("Bài này kiểm tra khả năng nhớ câu mẫu, không chấm mọi cách diễn đạt đúng khác.").font(.caption).foregroundStyle(.secondary)
                }
                if let feedback {
                    Text(feedback).foregroundStyle(TransToolsTheme.accent)
                    Text(lesson.meaning + "\n" + lesson.context).font(.callout)
                    Button("Câu tiếp theo") { load() }.buttonStyle(TransToolsActionButtonStyle(prominent: true))
                } else {
                    Button("Xem gợi ý") { revealed = true }.buttonStyle(.plain)
                }
            } else { Text("Đã hoàn thành các câu đến lượt ôn. Bạn có thể ôn từ vựng hoặc tạo bài mới.").foregroundStyle(.secondary) }
            if !store.status.isEmpty { Text(store.status).font(.caption).foregroundStyle(.secondary) }
            Text("Không gửi bản thu hay nội dung Sổ tay khi tạo bài. AI nhận ngôn ngữ, trình độ, mục tiêu và thống kê luyện tập; không nhận các câu trong Sổ tay.").font(.caption).foregroundStyle(.secondary)
        }.padding(20).transToolsPanel()
        .onAppear { load() }
        .onChange(of: store.archive.lessons.count) { _, _ in if feedback == nil { load() } }
        .onChange(of: manager.selectedLanguage) { _, _ in load() }
        .onChange(of: manager.selectedGoal) { _, _ in load() }
        .onDisappear { generationTask?.cancel() }
    }
    private func load() {
        lesson = store.plan(manager).first; answer = ""; feedback = nil; revealed = false
        guard let lesson else { choices = []; return }
        exerciseDifficulty = store.archive.progress[lesson.id]?.difficulty ?? 1
        let alternatives = manager.getScenarios().flatMap(\.dialogues).map(\.translation) + store.archive.lessons.filter { $0.language == lesson.language }.map(\.meaning)
        choices = Array(Set(alternatives.filter { $0 != lesson.meaning })).prefix(2).map { $0 }
        choices.append(lesson.meaning); choices.shuffle()
    }
    private func grade(_ correct: Bool) {
        guard let lesson, feedback == nil else { return }
        let independent = correct && !revealed
        store.record(lesson, correct: independent); revealed = true
        feedback = independent ? "Đúng! Đã lưu kết quả và lịch ôn." : correct ? "Đúng sau gợi ý. Câu này sẽ được ôn lại." : "Chưa đúng. Cùng xem lại câu và ôn ở buổi sau."
    }
    static func normalized(_ text: String) -> String {
        text.lowercased().components(separatedBy: .punctuationCharacters).joined().split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
    }
}


struct LearningApplicationCard: View {
    @ObservedObject var model: MeetingModel
    @ObservedObject var manager: LanguageLearningManager
    @ObservedObject private var store = AdaptiveLearningStore.shared
    @State private var showConversation = false
    @State private var showNotebook = false
    @State private var selectedSession: UUID?
    @State private var confirmedLanguage = false
    private var selected: MeetingSession? { model.sessions.first { $0.id == selectedSession } }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Áp dụng vào tình huống thật").font(.headline)
            Text("Luyện hội thoại theo mục tiêu hoặc ôn câu đã lưu trong Sổ tay.").foregroundStyle(.secondary)
            HStack {
                Button("Luyện hội thoại theo mục tiêu") {
                    let conversation = ConversationController.shared
                    if !conversation.active && conversation.turns.isEmpty {
                        conversation.chatLanguage = AppLanguage(rawValue: manager.selectedLanguage.rawValue) ?? .english
                        conversation.topicProfile.topic = manager.selectedGoal == .work ? .work : manager.selectedGoal == .career ? .interview : .everyday
                        conversation.topicProfile.customPrompt = ""
                    }
                    showConversation = true
                }.buttonStyle(TransToolsActionButtonStyle(prominent: true))
                Button("Chọn câu từ Sổ tay") { showNotebook = true }.buttonStyle(TransToolsActionButtonStyle())
            }
            Text("Hội thoại đang có được giữ nguyên. Bấm Bắt đầu trong màn hình hội thoại khi bạn sẵn sàng.").font(.caption).foregroundStyle(.secondary)
        }.padding(20).transToolsPanel()
        .sheet(isPresented: $showConversation) {
            VStack {
                HStack { Text("Luyện hội thoại").font(.headline); Spacer(); Button("Xong") { ConversationController.shared.stop(); showConversation = false }.buttonStyle(TransToolsActionButtonStyle()) }
                AIConversationView(model: model, manager: manager)
            }.padding(20).frame(minWidth: 800, minHeight: 650)
                .onDisappear { ConversationController.shared.stop() }
        }
        .sheet(isPresented: $showNotebook) {
            VStack(alignment: .leading, spacing: 16) {
                HStack { Text("Học từ Sổ tay").font(.title2.bold()); Spacer(); Button("Xong") { showNotebook = false }.buttonStyle(TransToolsActionButtonStyle()) }
                Text("Chọn bản ghi có tiếng gốc là \(manager.selectedLanguage.displayName) và bản dịch tiếng Việt. Chỉ thêm tối đa 20 câu ngắn, không gửi lên AI.")
                Picker("Bản ghi", selection: $selectedSession) {
                    Text("Chọn bản ghi…").tag(Optional<UUID>.none)
                    ForEach(model.sessions) { session in Text(session.title).tag(Optional(session.id)) }
                }
                if let selected {
                    ScrollView { VStack(alignment: .leading, spacing: 12) {
                        ForEach(Array(NotebookLearningPolicy.candidates(selected.captions, language: manager.selectedLanguage.rawValue).prefix(20))) { pair in
                            VStack(alignment: .leading) { Text(pair.original); Text(pair.vietnamese).foregroundStyle(TransToolsTheme.accent) }
                            Divider()
                        }
                    } }.frame(maxHeight: 280)
                    Toggle("Tiếng gốc là \(manager.selectedLanguage.displayName); tôi đã kiểm tra các câu và bản dịch", isOn: $confirmedLanguage).tint(TransToolsTheme.accent)
                    Button("Thêm vào bài học") { store.importNotebook(selected, manager: manager); showNotebook = false }.buttonStyle(TransToolsActionButtonStyle(prominent: true)).disabled(!confirmedLanguage || NotebookLearningPolicy.candidates(selected.captions, language: manager.selectedLanguage.rawValue).isEmpty)
                }
                Text("Bản ghi gốc được giữ nguyên. Câu dài, khác ngôn ngữ hoặc chưa dịch đủ sẽ được bỏ qua.").font(.caption).foregroundStyle(.secondary)
            }.padding(24).frame(width: 720)
                .onChange(of: selectedSession) { _, _ in confirmedLanguage = false }
        }
    }
}
