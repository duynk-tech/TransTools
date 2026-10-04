import SwiftUI
import AppKit
import AVFoundation

// MARK: - Language Learning Models

public enum LearningLanguage: String, CaseIterable, Identifiable, Codable {
    case english = "en"
    case japanese = "ja"
    case chinese = "zh"
    case korean = "ko"

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .english: return "Tiếng Anh"
        case .japanese: return "Tiếng Nhật"
        case .chinese: return "Tiếng Trung"
        case .korean: return "Tiếng Hàn"
        }
    }

    public var flag: String {
        switch self {
        case .english: return "🇬🇧"
        case .japanese: return "🇯🇵"
        case .chinese: return "🇨🇳"
        case .korean: return "🇰🇷"
        }
    }

    public var greeting: String {
        switch self {
        case .english: return "Hello & Welcome"
        case .japanese: return "こんにちは (Konnichiwa)"
        case .chinese: return "你好 (Nǐ hǎo)"
        case .korean: return "안녕하세요 (Annyeonghaseyo)"
        }
    }

    public var voiceLocale: String {
        switch self {
        case .english: return "en-US"
        case .japanese: return "ja-JP"
        case .chinese: return "zh-CN"
        case .korean: return "ko-KR"
        }
    }

    public var phoneticLabel: String {
        switch self {
        case .english: return "Phiên âm IPA"
        case .japanese: return "Kana / Furigana"
        case .chinese: return "Pinyin & Thanh điệu"
        case .korean: return "Hangul & Phát âm"
        }
    }
}

public enum LearningLevel: String, CaseIterable, Identifiable, Codable {
    case beginner = "beginner"
    case intermediate = "intermediate"
    case advanced = "advanced"

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .beginner: return "Người mới bắt đầu (A1)"
        case .intermediate: return "Căn bản & Đi làm (A2–B1)"
        case .advanced: return "Nâng cao & Chuyên sâu (B2–C1)"
        }
    }

    public var description: String {
        switch self {
        case .beginner: return "Làm quen với mặt chữ, cách phát âm và các câu chào hỏi căn bản."
        case .intermediate: return "Tự tin theo kịp cuộc họp, viết email và trao đổi công việc hằng ngày."
        case .advanced: return "Trình bày quan điểm sắc bén, diễn đạt tự nhiên và nắm thuật ngữ chuyên ngành."
        }
    }
}

public enum LearningGoal: String, CaseIterable, Identifiable, Codable {
    case work = "work"
    case daily = "daily"
    case career = "career"

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .work: return "Cuộc họp & Công việc"
        case .daily: return "Giao tiếp đời sống"
        case .career: return "Phỏng vấn & Nghề nghiệp"
        }
    }

    public var icon: String {
        switch self {
        case .work: return "briefcase.fill"
        case .daily: return "bubble.left.and.bubble.right.fill"
        case .career: return "graduationcap.fill"
        }
    }

    public var description: String {
        switch self {
        case .work: return "Báo cáo tiến độ, xin làm rõ ý kiến, xác nhận công việc và viết email."
        case .daily: return "Chào hỏi, hỏi đường, mua sắm, gọi món và trò chuyện thân mật."
        case .career: return "Giới thiệu kinh nghiệm bản thân, trả lời phỏng vấn và thuyết trình tự tin."
        }
    }
}

// MARK: - Daily Sentence of the Day Model

public struct DailySentence: Identifiable {
    public var id: UUID = UUID()
    public var language: LearningLanguage
    public var originalText: String
    public var reading: String
    public var vietnameseMeaning: String
    public var contextNote: String
    public var keyWord: String
    public var keyWordMeaning: String
    public var keyWordReading: String = ""
}

// MARK: - Communication Scenario Dialogue Model

public struct ScenarioDialogue: Identifiable {
    public var id: UUID = UUID()
    public var speaker: String
    public var original: String
    public var reading: String
    public var translation: String
}

public struct CommunicationScenario: Identifiable {
    public var id: String
    public var language: LearningLanguage
    public var title: String
    public var category: String
    public var icon: String
    public var description: String
    public var dialogues: [ScenarioDialogue]
}

// MARK: - Language Learning Manager

@MainActor
public final class LanguageLearningManager: ObservableObject {
    public static let shared = LanguageLearningManager()

    // Preferences & Goals
    @Published public var selectedLanguage: LearningLanguage {
        didSet { UserDefaults.standard.set(selectedLanguage.rawValue, forKey: "LL_SelectedLanguage") }
    }
    @Published public var selectedLevel: LearningLevel {
        didSet { UserDefaults.standard.set(selectedLevel.rawValue, forKey: "LL_SelectedLevel") }
    }
    @Published public var selectedGoal: LearningGoal {
        didSet { UserDefaults.standard.set(selectedGoal.rawValue, forKey: "LL_SelectedGoal") }
    }
    @Published public var dailyMinutes: Int {
        didSet { UserDefaults.standard.set(dailyMinutes, forKey: "LL_DailyMinutes") }
    }
    @Published public var hasConfiguredGoal: Bool {
        didSet { UserDefaults.standard.set(hasConfiguredGoal, forKey: "LL_HasConfiguredGoal") }
    }

    // Daily tracking
    @Published public var completedReviewsTodayCount: Int = 0
    @Published public var lastActiveDateString: String = ""

    private init() {
        let langRaw = UserDefaults.standard.string(forKey: "LL_SelectedLanguage") ?? LearningLanguage.english.rawValue
        self.selectedLanguage = LearningLanguage(rawValue: langRaw) ?? .english

        let levelRaw = UserDefaults.standard.string(forKey: "LL_SelectedLevel") ?? LearningLevel.intermediate.rawValue
        self.selectedLevel = LearningLevel(rawValue: levelRaw) ?? .intermediate

        let goalRaw = UserDefaults.standard.string(forKey: "LL_SelectedGoal") ?? LearningGoal.work.rawValue
        self.selectedGoal = LearningGoal(rawValue: goalRaw) ?? .work

        let mins = UserDefaults.standard.integer(forKey: "LL_DailyMinutes")
        self.dailyMinutes = mins > 0 ? mins : 10

        self.hasConfiguredGoal = UserDefaults.standard.bool(forKey: "LL_HasConfiguredGoal")
        self.completedReviewsTodayCount = UserDefaults.standard.integer(forKey: "LL_TodayReviewsCount")
        self.lastActiveDateString = UserDefaults.standard.string(forKey: "LL_LastActiveDate") ?? ""

        checkDailyReset()
    }

    public var dueTodayCount: Int {
        VocabularyManager.shared.dueItems.filter { $0.language == selectedLanguage.rawValue }.count
    }

    public func markReviewCompleted(now: Date = Date()) {
        checkDailyReset(now: now)
        completedReviewsTodayCount += 1
        UserDefaults.standard.set(completedReviewsTodayCount, forKey: "LL_TodayReviewsCount")
    }

    public func checkDailyReset(now: Date = Date()) {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        let todayStr = formatter.string(from: now)

        if lastActiveDateString != todayStr {
            completedReviewsTodayCount = 0
            UserDefaults.standard.set(0, forKey: "LL_TodayReviewsCount")
            lastActiveDateString = todayStr
            UserDefaults.standard.set(todayStr, forKey: "LL_LastActiveDate")
        }
    }

    // Curated Daily Sentences (Zero-AI Barrier)
    public func getSentenceOfTheDay() -> DailySentence {
        switch selectedLanguage {
        case .english:
            return DailySentence(
                language: .english,
                originalText: "Could you please clarify the action items from today's sync?",
                reading: "/kʊd juː pliːz ˈklær.ɪ.faɪ ðiː ˈæk.ʃən ˈaɪ.təmz frɒm təˈdeɪz sɪŋk/",
                vietnameseMeaning: "Bạn có thể làm rõ các việc cần làm sau buổi trao đổi hôm nay được không?",
                contextNote: "Dùng khi kết thúc cuộc họp để chốt người phụ trách và đầu việc cụ thể.",
                keyWord: "clarify",
                keyWordMeaning: "làm rõ, giải thích tường minh",
                keyWordReading: "/ˈklær.ɪ.faɪ/"
            )
        case .japanese:
            return DailySentence(
                language: .japanese,
                originalText: "本日の会議の決定事項を確認させていただけますでしょうか。",
                reading: "ほんじつ の かいぎ の けっていじこう を かくにん させて いただけますでしょうか (Honjitsu no kaigi no kettei jikou o kakunin sasete itadakemasu deshou ka)",
                vietnameseMeaning: "Tôi xin phép được xác nhận lại các điểm đã thống nhất trong cuộc họp hôm nay ạ.",
                contextNote: "Cách diễn đạt lịch sự chuẩn công sở (Keigo) với đối tác Nhật.",
                keyWord: "決定事項",
                keyWordMeaning: "các hạng mục đã quyết định",
                keyWordReading: "けっていじこう"
            )
        case .chinese:
            return DailySentence(
                language: .chinese,
                originalText: "我们先确认一下今天会议讨论的关键点和接下来的排期。",
                reading: "Wǒmen xiān quèrèn yíxià jīntiān huìyì tǎolùn de guānjiàndiǎn hé jiēxiàlái de páiqī.",
                vietnameseMeaning: "Trước tiên chúng ta hãy xác nhận lại các điểm mấu chốt và lịch trình tiếp theo.",
                contextNote: "Thường dùng trong các buổi họp tiến độ dự án (Sprint / Sync).",
                keyWord: "排期",
                keyWordMeaning: "lịch trình, kế hoạch triển khai",
                keyWordReading: "páiqī"
            )
        case .korean:
            return DailySentence(
                language: .korean,
                originalText: "오늘 회의에서 논의된 주요 결정 사항을 다시 한번 확인해 주시겠습니까?",
                reading: "Oneul hoe-ui-eseo non-uidwen juyo gyeoljeong sahang-eul dasi hanbeon hwag-inhae jusigessseumnikka?",
                vietnameseMeaning: "Bạn có thể xác nhận lại giúp tôi những điểm quyết định chính trong buổi họp hôm nay không ạ?",
                contextNote: "Câu hỏi lịch sự kính ngữ (-겠습니까) phổ biến nơi công sở Hàn Quốc.",
                keyWord: "결정 사항",
                keyWordMeaning: "các vấn đề đã được quyết định",
                keyWordReading: "gyeoljeong sahang"
            )
        }
    }

    // Curated Starter Cards for each language
    public func seedStarterVocabulary() {
        let vocab = VocabularyManager.shared
        switch selectedLanguage {
        case .english:
            vocab.add(word: "clarify", meaning: "làm rõ, giải thích chi tiết", phonetic: "/ˈklær.ɪ.faɪ/", context: "Could you clarify the requirements?", sourceApp: "Trans Tools", language: "en")
            vocab.add(word: "deadline", meaning: "hạn chót hoàn thành", phonetic: "/ˈded.laɪn/", context: "The deadline for this deliverable is Friday.", sourceApp: "Trans Tools", language: "en")
            vocab.add(word: "action item", meaning: "nhiệm vụ cần thực hiện", phonetic: "/ˈæk.ʃən ˈaɪ.təm/", context: "Let's summarize the key action items.", sourceApp: "Trans Tools", language: "en")
            vocab.add(word: "follow up", meaning: "tiếp tục theo dõi / phản hồi lại", phonetic: "/ˈfɒl.əʊ ʌp/", context: "I will follow up with the design team tomorrow.", sourceApp: "Trans Tools", language: "en")
            vocab.add(word: "schedule", meaning: "lên lịch, sắp xếp thời gian", phonetic: "/ˈʃedʒ.uːl/", context: "Can we schedule a quick call?", sourceApp: "Trans Tools", language: "en")

        case .japanese:
            vocab.add(word: "お疲れ様です", meaning: "Cảm ơn bạn đã vất vả (chào khi làm việc)", phonetic: "おつかれさまです (Otsukaresama desu)", context: "お疲れ様です。進捗のご確認です。", sourceApp: "Trans Tools", language: "ja")
            vocab.add(word: "よろしくお願いします", meaning: "Rất mong được giúp đỡ / Xin nhờ cậy", phonetic: "よろしくおねがいします (Yoroshiku onegaishimasu)", context: "今後ともよろしくお願いいたします。", sourceApp: "Trans Tools", language: "ja")
            vocab.add(word: "承知いたしました", meaning: "Tôi đã hiểu rõ / Đã tiếp nhận thông tin", phonetic: "しょうちいたしました (Shouchi itashimashita)", context: "ご指摘の件、承知いたしました。", sourceApp: "Trans Tools", language: "ja")
            vocab.add(word: "確認", meaning: "xác nhận, kiểm tra", phonetic: "かくにん (Kakunin)", context: "仕様の確認をお願いします。", sourceApp: "Trans Tools", language: "ja")
            vocab.add(word: "検討", meaning: "xem xét, cân nhắc kỹ lưỡng", phonetic: "けんとう (Kentou)", context: "社内で検討の上、ご連絡します。", sourceApp: "Trans Tools", language: "ja")

        case .chinese:
            vocab.add(word: "你好", meaning: "xin chào", phonetic: "Nǐ hǎo", context: "你好，很高兴和你合作。", sourceApp: "Trans Tools", language: "zh")
            vocab.add(word: "没问题", meaning: "không vấn đề gì / sẵn sàng làm", phonetic: "Méi wèntí", context: "这件事交给我，没问题！", sourceApp: "Trans Tools", language: "zh")
            vocab.add(word: "开会", meaning: "họp, mở cuộc họp", phonetic: "Kāihuì", context: "我们下午两点开会讨论方案。", sourceApp: "Trans Tools", language: "zh")
            vocab.add(word: "进度", meaning: "tiến độ công việc / dự án", phonetic: "Jìndù", context: "请同步一下当前的开发进度。", sourceApp: "Trans Tools", language: "zh")
            vocab.add(word: "合作", meaning: "hợp tác, cùng làm việc", phonetic: "Hézuò", context: "期待与贵团队的深入合作。", sourceApp: "Trans Tools", language: "zh")

        case .korean:
            vocab.add(word: "안녕하세요", meaning: "xin chào lịch sự", phonetic: "Annyeonghaseyo", context: "안녕하세요, 처음 뵙겠습니다.", sourceApp: "Trans Tools", language: "ko")
            vocab.add(word: "감사합니다", meaning: "cảm ơn chân thành", phonetic: "Gamsahamnida", context: "도와주셔서 진심으로 감사합니다.", sourceApp: "Trans Tools", language: "ko")
            vocab.add(word: "알겠습니다", meaning: "tôi đã hiểu rõ / vâng tôi biết rồi", phonetic: "Algesseumnida", context: "네, 전달해주신 내용 잘 알겠습니다.", sourceApp: "Trans Tools", language: "ko")
            vocab.add(word: "회의", meaning: "cuộc họp", phonetic: "Hoe-ui", context: "다음 주 회의 일정을 조율해 봅시다.", sourceApp: "Trans Tools", language: "ko")
            vocab.add(word: "확인", meaning: "xác nhận, kiểm tra", phonetic: "Hwag-in", context: "보내드린 메일 확인 부탁드립니다.", sourceApp: "Trans Tools", language: "ko")
        }
    }

    // Communication Scenarios
    public func getScenarios() -> [CommunicationScenario] {
        switch selectedLanguage {
        case .english:
            return [
                CommunicationScenario(
                    id: "en_meeting",
                    language: .english,
                    title: "Phát biểu & Xin làm rõ trong cuộc họp",
                    category: "Cuộc họp",
                    icon: "waveform.badge.mic",
                    description: "Các mẫu câu tự nhiên để ngắt lời lịch sự, xin giải thích và chốt ý kiến.",
                    dialogues: [
                        ScenarioDialogue(speaker: "Bạn", original: "Sorry to jump in, but could we clarify the timeline for this feature?", reading: "/ˈsɒr.i tuː dʒʌmp ɪn/", translation: "Xin thứ lỗi đã chen ngang, nhưng chúng ta có thể làm rõ thời hạn tính năng này không?"),
                        ScenarioDialogue(speaker: "Đối tác", original: "Sure! We are aiming for next Tuesday's sprint release.", reading: "/ʃɔːr wiː ɑːr ˈeɪ.mɪŋ/", translation: "Chắc chắn rồi! Chúng tôi đang nhắm đến bản phát hành sprint thứ Ba tới."),
                        ScenarioDialogue(speaker: "Bạn", original: "Got it. I will align with QA to make sure tests are covered.", reading: "/ɡɒt ɪt/", translation: "Tôi hiểu rồi. Tôi sẽ phối hợp với bên QA để đảm bảo kiểm thử đầy đủ.")
                    ]
                ),
                CommunicationScenario(
                    id: "en_email",
                    language: .english,
                    title: "Viết email xin lịch hẹn & Trao đổi",
                    category: "Email công sở",
                    icon: "envelope.fill",
                    description: "Mẫu câu ngắn gọn, chuẩn chuyên nghiệp để hẹn gặp hoặc hỏi tiến độ.",
                    dialogues: [
                        ScenarioDialogue(speaker: "Bạn", original: "I hope this email finds you well. Would you be available for a brief sync tomorrow?", reading: "/aɪ həʊp ðɪs ˈiː.meɪl/", translation: "Hi vọng bạn vẫn khỏe. Bạn có rảnh cho một cuộc trao đổi ngắn vào ngày mai không?"),
                        ScenarioDialogue(speaker: "Đối tác", original: "Hi! Yes, 3:00 PM works perfectly on my end. I'll send an invite.", reading: "/jes θriː piː em/", translation: "Chào bạn! Vâng, 3 giờ chiều rất thuận tiện cho tôi. Tôi sẽ gửi thư mời.")
                    ]
                ),
                CommunicationScenario(
                    id: "en_intro",
                    language: .english,
                    title: "Tự giới thiệu bản thân với đồng nghiệp",
                    category: "Giao tiếp",
                    icon: "person.crop.circle.badge.plus",
                    description: "Giới thiệu vai trò, kinh nghiệm và bày tỏ sự hào hứng khi hợp tác.",
                    dialogues: [
                        ScenarioDialogue(speaker: "Bạn", original: "Hi everyone, I'm Duy. I've just joined as a software engineer. Excited to collaborate!", reading: "/haɪ ˈev.ri.wʌn/", translation: "Chào mọi người, mình là Duy. Mình vừa gia nhập với vai trò kỹ sư phần mềm. Rất hào hứng được cộng tác!"),
                        ScenarioDialogue(speaker: "Đồng nghiệp", original: "Welcome aboard Duy! Feel free to reach out if you need anything getting set up.", reading: "/ˈwel.kəm əˈbɔːd/", translation: "Chào mừng Duy đến với nhóm! Cứ thoải mái nhắn nếu bạn cần hỗ trợ gì khi cài đặt nhé.")
                    ]
                )
            ]
        case .japanese:
            return [
                CommunicationScenario(
                    id: "ja_meeting",
                    language: .japanese,
                    title: "Trao đổi tiến độ & Xin ý kiến (報連相)",
                    category: "Cuộc họp",
                    icon: "briefcase.fill",
                    description: "Báo cáo tiến độ chuẩn phong cách công sở Nhật Bản (Horenso).",
                    dialogues: [
                        ScenarioDialogue(speaker: "Bạn", original: "現在の進捗について共有させていただきます。", reading: "げんざい の しんちょく について きょうゆう させていただきます (Genzai no shinchoku ni tsuite kyouyuu sasete itadakimasu)", translation: "Tôi xin phép được chia sẻ về tiến độ công việc hiện tại ạ."),
                        ScenarioDialogue(speaker: "Quản lý", original: "はい、お願いします。課題などはありますか。", reading: "はい、おねがいします。かだい など は ありますか (Hai, onegaishimasu. Kadai nado wa arimasu ka)", translation: "Vâng, xin mời. Hiện có khó khăn hay vướng mắc gì không?"),
                        ScenarioDialogue(speaker: "Bạn", original: "スケジュール通り順調に進んでおり、問題ございません。", reading: "すけじゅーる どおり じゅんちょう に すすんで おり、もんだい ございません (Sukejuuru doori junchou ni susunde ori, mondai gozaimasen)", translation: "Mọi thứ vẫn đang tiến triển thuận lợi theo đúng lịch trình, không có vấn đề gì ạ.")
                    ]
                ),
                CommunicationScenario(
                    id: "ja_intro",
                    language: .japanese,
                    title: "Tự giới thiệu lần đầu gặp gỡ (自己紹介)",
                    category: "Chào hỏi",
                    icon: "person.wave.2.fill",
                    description: "Mẫu câu chuẩn mực khi ra mắt đối tác hoặc team mới.",
                    dialogues: [
                        ScenarioDialogue(speaker: "Bạn", original: "はじめまして、ドゥイと申します。どうぞよろしくお願いいたします。", reading: "はじめまして、ドゥイ と もうします。どうぞ よろしく おねがいいたします (Hajimemashite, Dui to moushimasu. Douzo yoroshiku onegaishimasu)", translation: "Rất hân hạnh được gặp anh/chị, tôi tên là Duy. Rất mong nhận được sự giúp đỡ ạ."),
                        ScenarioDialogue(speaker: "Đối tác", original: "こちらこそ、どうぞよろしくお願いいたします。", reading: "こちらこそ、どうぞ よろしく おねがいいたします (Kochira koso, douzo yoroshiku onegaishimasu)", translation: "Chính tôi mới là người cần nhờ anh giúp đỡ. Rất mong được hợp tác tốt đẹp.")
                    ]
                )
            ]
        case .chinese:
            return [
                CommunicationScenario(
                    id: "zh_sync",
                    language: .chinese,
                    title: "Đồng bộ tiến độ & Xác nhận yêu cầu",
                    category: "Công việc",
                    icon: "arrow.triangle.2.circlepath",
                    description: "Các câu nói ngắn gọn, trực diện trong team công nghệ nói tiếng Trung.",
                    dialogues: [
                        ScenarioDialogue(speaker: "Bạn", original: "大家早上好，我们同步一下这个需求的设计细节。", reading: "Dàjiā zǎoshang hǎo, wǒmen tóngbù yíxià zhège xūqiú de shèjì xìjié.", translation: "Chào buổi sáng cả nhà, chúng ta cùng đồng bộ lại chi tiết thiết kế cho tính năng này nhé."),
                        ScenarioDialogue(speaker: "Đối tác", original: "好的，接口文档已经更新了，你先看一下。", reading: "Hǎo de, jiēkǒu wéndàng yǐjīng gēngxīn le, nǐ xiān kàn yíxià.", translation: "Được rồi, tài liệu API đã được cập nhật rồi, bạn xem qua trước nhé."),
                        ScenarioDialogue(speaker: "Bạn", original: "没问题，我今天下午完成联调。", reading: "Méi wèntí, wǒ jīntiān xiàwǔ wánchéng liántiáo.", translation: "Không vấn đề gì, chiều nay tôi sẽ hoàn thành ghép nối API.")
                    ]
                )
            ]
        case .korean:
            return [
                CommunicationScenario(
                    id: "ko_meeting",
                    language: .korean,
                    title: "Bắt đầu cuộc họp & Báo cáo công việc",
                    category: "Cuộc họp",
                    icon: "person.3.fill",
                    description: "Mẫu câu trang trọng kính ngữ chuẩn môi trường văn phòng Hàn Quốc.",
                    dialogues: [
                        ScenarioDialogue(speaker: "Bạn", original: "오늘 회의를 시작하도록 하겠습니다. 모두 접속하셨나요?", reading: "Oneul hoe-ui-reul sijaghadorog hagesseumnida. Modu jeobsoghayeonnayo?", translation: "Sau đây chúng ta sẽ bắt đầu cuộc họp hôm nay. Mọi người đã vào đủ chưa ạ?"),
                        ScenarioDialogue(speaker: "Đối tác", original: "네, 모두 준비되었습니다. 발표 진행해 주세요.", reading: "Ne, modu junbidwo-eosseumnida. Balpyo jinhaenghae juseyo.", translation: "Vâng, tất cả đã sẵn sàng. Xin mời bạn tiến hành trình bày ạ.")
                    ]
                )
            ]
        }
    }
}

// MARK: - Main Language Learning Dashboard View

struct LanguageLearningDashboardView: View {
    @ObservedObject var model: MeetingModel
    @ObservedObject var manager = LanguageLearningManager.shared
    @ObservedObject var vocabManager = VocabularyManager.shared

    @Environment(\.scenePhase) private var scenePhase
    @State private var selectedSubTab: Int = 0 // 0: Hôm nay, 1: Từ vựng của tôi, 2: Luyện giao tiếp, 3: Tiến bộ, 4: Mục tiêu
    @State private var showSRSModal = false
    @State private var showGoalSettingsSheet = false

    init(model: MeetingModel) {
        self.model = model
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Top Secondary Sub-Navigation Bar
            subNavigationBar
                .padding(.horizontal, 24)
                .padding(.top, 14)
                .padding(.bottom, 12)
                .background(TransToolsTheme.background)

            Divider()

            // Chat and Letter Learning own their viewport layout so controls remain fully visible
            if selectedSubTab == 5 {
                AlphabetLearningView(model: model, manager: manager)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            } else {
                ScrollView {
                    VStack(spacing: 20) {
                        if selectedSubTab == 0 {
                            TodayRoutineView(
                                manager: manager,
                                vocabManager: vocabManager,
                                onStartSRS: { showSRSModal = true },
                                onOpenGoals: { selectedSubTab = 4 }
                            )
                        } else if selectedSubTab == 1 {
                            MyVocabularyLearningView(
                                manager: manager,
                                vocabManager: vocabManager,
                                onStartSRS: { showSRSModal = true }
                            )
                        } else if selectedSubTab == 2 {
                            CommunicationPracticeView(
                                manager: manager,
                                vocabManager: vocabManager
                            )
                        } else if selectedSubTab == 3 {
                            LearningProgressView(
                                manager: manager,
                                vocabManager: vocabManager,
                                onStartSRS: { showSRSModal = true }
                            )
                        } else {
                            GoalAndOnboardingView(
                                manager: manager,
                                vocabManager: vocabManager,
                                onCompleted: { selectedSubTab = 0 }
                            )
                        }
                    }
                    .padding(24)
                    .frame(maxWidth: 1160)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .onAppear { manager.checkDailyReset() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { manager.checkDailyReset() }
        }
        .sheet(isPresented: $showSRSModal) {
            SRSFlashcardModalView(
                vocabManager: vocabManager,
                learningManager: manager
            )
        }
    }

    // Secondary Sub-Navigation Bar
    private var subNavigationBar: some View {
        HStack(spacing: 12) {
            // Active Language Pill & Quick switch
            Menu {
                ForEach(LearningLanguage.allCases) { lang in
                    Button {
                        manager.selectedLanguage = lang
                    } label: {
                        HStack {
                            Text("\(lang.flag) \(lang.displayName)")
                            if manager.selectedLanguage == lang {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            } label: {
                Text("\(manager.selectedLanguage.flag)  \(manager.selectedLanguage.displayName)")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(TransToolsTheme.accent)
                    .lineLimit(1)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.visible)
            .fixedSize(horizontal: true, vertical: false)
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(TransToolsTheme.accent.opacity(0.06), in: RoundedRectangle(cornerRadius: 11))
            .overlay(RoundedRectangle(cornerRadius: 11).stroke(TransToolsTheme.accent.opacity(0.3), lineWidth: 1))
            .accessibilityLabel("Chọn ngôn ngữ: \(manager.selectedLanguage.displayName)")

            // Sub-tabs segment
            ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                subTabButton(index: 0, title: "Hôm nay", icon: "sun.max.fill", badge: manager.dueTodayCount > 0 ? "\(manager.dueTodayCount)" : nil)
                subTabButton(index: 5, title: "Chữ & Viết", icon: "pencil.tip", badge: nil)
                subTabButton(index: 1, title: "Từ vựng của tôi", icon: "character.book.closed.fill", badge: "\(vocabManager.items.filter { $0.language == manager.selectedLanguage.rawValue }.count)")
                subTabButton(index: 2, title: "Luyện giao tiếp", icon: "bubble.left.and.text.bubble.right.fill", badge: nil)
            }

            }
            Menu {
                Button("Tiến bộ", systemImage: "chart.line.uptrend.xyaxis") { selectedSubTab = 3 }
                Button("Mục tiêu", systemImage: "target") { selectedSubTab = 4 }
            } label: {
                Label("Thêm", systemImage: "ellipsis.circle")
                    .font(.system(size: 12, weight: .semibold))
                    .padding(.horizontal, 12).padding(.vertical, 9)
            }
            .menuStyle(.borderlessButton).fixedSize()
            Spacer(minLength: 0)

            // Daily Target Pill
            HStack(spacing: 5) {
                Image(systemName: "clock.badge.checkmark")
                    .font(.system(size: 11))
                    .foregroundStyle(TransToolsTheme.accent)
                Text("\(manager.dailyMinutes) phút/ngày")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(TransToolsTheme.accent.opacity(0.08))
            .clipShape(Capsule())
        }
    }

    private func subTabButton(index: Int, title: String, icon: String, badge: String?) -> some View {
        Button {
            withAnimation(.easeInOut(duration: 0.15)) {
                selectedSubTab = index
            }
        } label: {
            HStack(spacing: 7) {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .semibold))
                Text(title)
                    .font(.system(size: 13, weight: selectedSubTab == index ? .bold : .medium))

                if let badge = badge {
                    Text(badge)
                        .font(.system(size: 10, weight: .bold))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 1.5)
                        .background(selectedSubTab == index ? TransToolsTheme.accent : Color.secondary.opacity(0.18))
                        .foregroundStyle(selectedSubTab == index ? .white : .secondary)
                        .clipShape(Capsule())
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(selectedSubTab == index ? Color.primary.opacity(0.09) : Color.clear)
            .foregroundStyle(selectedSubTab == index ? Color.primary : Color.secondary)
            .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selectedSubTab == index ? .isSelected : [])
    }
}

// MARK: - 1. Hôm Nay (Today Routine View)

struct TodayRoutineView: View {
    @ObservedObject var manager: LanguageLearningManager
    @ObservedObject var vocabManager: VocabularyManager
    var onStartSRS: () -> Void
    var onOpenGoals: () -> Void

    @State private var sentenceSaved: Bool = false

    var body: some View {
        VStack(spacing: 18) {
            // Daily Welcome Banner
            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text("Mục tiêu hôm nay · \(manager.selectedLanguage.flag) \(manager.selectedLanguage.displayName)")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(TransToolsTheme.accent)

                        Text("• \(manager.selectedGoal.title)")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.secondary)
                    }

                    Text("Vòng học hằng ngày: Ôn từ đến hạn → Nghe 1 câu → Luyện 1 tình huống")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.primary)

                    Text("Học từ ngữ cảnh thật của bạn. Không cần key AI vẫn hoàn thành trọn vẹn vòng học.")
                        .font(.system(size: 11.5))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button {
                    onOpenGoals()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "slider.horizontal.3")
                        Text("Đổi mục tiêu")
                    }
                    .font(.system(size: 11, weight: .medium))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Color.primary.opacity(0.06))
                    .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(TransToolsTheme.mint.opacity(0.25))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(TransToolsTheme.accent.opacity(0.2), lineWidth: 1)
                    )
            )

            // Section 1: Spaced Repetition SRS Card
            srsCard

            // Section 2: Listening Sentence of the Day
            listeningCard

            // Section 3: Quick Scenario Challenge
            quickScenarioCard
        }
    }

    // SRS Spaced Repetition Card
    private var srsCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: "sparkles.rectangle.stack.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(TransToolsTheme.accent)
                    Text("Ôn tập cách quãng (Spaced Repetition)")
                        .font(.system(size: 14, weight: .bold))
                }

                Spacer()

                if manager.dueTodayCount > 0 {
                    Text("\(manager.dueTodayCount) từ đến hạn")
                        .font(.system(size: 11, weight: .bold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Color.orange.opacity(0.18))
                        .foregroundStyle(Color.orange)
                        .clipShape(Capsule())
                } else {
                    Text(vocabManager.items.isEmpty ? "Bắt đầu với từ đầu tiên" : "Đã ôn đủ hôm nay 🎉")
                        .font(.system(size: 11, weight: .bold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Color.green.opacity(0.18))
                        .foregroundStyle(Color.green)
                        .clipShape(Capsule())
                }
            }

            if vocabManager.items.isEmpty {
                // Empty state: offer to seed starter vocabulary
                VStack(spacing: 10) {
                    Text("Sổ từ vựng của bạn chưa có từ nào. Bạn có thể tự lưu từ khi dịch/họp hoặc bắt đầu ngay với bộ từ thiết yếu.")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    HStack {
                        Button {
                            manager.seedStarterVocabulary()
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "plus.circle.fill")
                                Text("Nạp bộ từ khởi đầu cho \(manager.selectedLanguage.displayName)")
                            }
                            .font(.system(size: 12, weight: .semibold))
                            .padding(.horizontal, 14)
                            .padding(.vertical, 7)
                            .background(TransToolsTheme.accent)
                            .foregroundStyle(.white)
                            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        }
                        .buttonStyle(.plain)

                        Spacer()
                    }
                }
            } else {
                HStack(spacing: 16) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Thẻ Flashcard tự nhớ lại")
                            .font(.system(size: 13, weight: .semibold))
                        Text(manager.dueTodayCount > 0
                             ? "Có \(manager.dueTodayCount) từ vựng cần bạn nhớ lại hôm nay để củng cố trí nhớ dài hạn."
                             : "Tuyệt vời! Toàn bộ từ vựng đã được ôn tập đúng hạn. Bạn có thể ôn lại bất kỳ lúc nào.")
                            .font(.system(size: 11.5))
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Button {
                        onStartSRS()
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "play.fill")
                                .font(.system(size: 11))
                            Text(manager.dueTodayCount > 0 ? "Ôn tập ngay (\(manager.dueTodayCount) thẻ)" : "Luyện thẻ tự do")
                                .font(.system(size: 12, weight: .bold))
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(TransToolsTheme.accent)
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(Color.primary.opacity(0.08), lineWidth: 1)
                )
        )
    }

    // Sentence of the Day Card
    private var listeningCard: some View {
        let sentence = manager.getSentenceOfTheDay()
        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: "ear.and.waveform")
                        .font(.system(size: 14))
                        .foregroundStyle(TransToolsTheme.navy)
                    Text("Nghe & Hiểu câu của ngày")
                        .font(.system(size: 14, weight: .bold))
                }

                Spacer()

                Text(manager.selectedLanguage.displayName)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 8) {
                // Original Sentence
                Text(sentence.originalText)
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)

                // Reading / Furigana / Pinyin
                if !sentence.reading.isEmpty {
                    Text(sentence.reading)
                        .font(.system(size: 12, weight: .medium, design: .monospaced))
                        .foregroundStyle(TransToolsTheme.navy)
                }

                // Vietnamese Translation
                Text("“\(sentence.vietnameseMeaning)”")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.secondary)

                // Note
                Text("💡 Ngữ cảnh: \(sentence.contextNote)")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary.opacity(0.85))
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.primary.opacity(0.03))
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

            // Action Buttons
            HStack(spacing: 12) {
                // Speak Normal Rate
                Button {
                    vocabManager.speak(sentence.originalText, language: sentence.language.voiceLocale, rate: 0.46)
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "speaker.wave.2.fill")
                        Text("Nghe chuẩn")
                    }
                    .font(.system(size: 11.5, weight: .semibold))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(TransToolsTheme.accent.opacity(0.12))
                    .foregroundStyle(TransToolsTheme.accent)
                    .clipShape(Capsule())
                }
                .buttonStyle(.plain)

                // Speak Slow Rate
                Button {
                    vocabManager.speak(sentence.originalText, language: sentence.language.voiceLocale, rate: 0.32)
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "tortoise.fill")
                        Text("Nghe chậm (0.7x)")
                    }
                    .font(.system(size: 11.5, weight: .medium))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color.secondary.opacity(0.1))
                    .foregroundStyle(.secondary)
                    .clipShape(Capsule())
                }
                .buttonStyle(.plain)

                Spacer()

                // Save Word to Vocabulary
                Button {
                    vocabManager.add(
                        word: sentence.keyWord,
                        meaning: sentence.keyWordMeaning,
                        phonetic: sentence.keyWordReading,
                        context: sentence.originalText,
                        sourceApp: "Trans Tools Daily",
                        language: sentence.language.rawValue
                    )
                    sentenceSaved = true
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: sentenceSaved ? "checkmark" : "bookmark.fill")
                        Text(sentenceSaved ? "Đã lưu từ “\(sentence.keyWord)”" : "Lưu từ “\(sentence.keyWord)”")
                    }
                    .font(.system(size: 11.5, weight: .semibold))
                    .padding(.horizontal, 11)
                    .padding(.vertical, 6)
                    .background(sentenceSaved ? Color.green.opacity(0.12) : Color.primary.opacity(0.06))
                    .foregroundStyle(sentenceSaved ? Color.green : Color.primary)
                    .clipShape(Capsule())
                }
                .buttonStyle(.plain)
                .disabled(sentenceSaved)
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(Color.primary.opacity(0.08), lineWidth: 1)
                )
        )
    }

    // Quick Scenario Challenge
    private var quickScenarioCard: some View {
        let scenarios = manager.getScenarios()
        let scenario = scenarios.first

        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: "bubble.left.and.bubble.right.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(Color.purple)
                    Text("Tình huống ứng dụng thực tế")
                        .font(.system(size: 14, weight: .bold))
                }

                Spacer()

                if let title = scenario?.category {
                    Text(title)
                        .font(.system(size: 11, weight: .bold))
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2)
                        .background(Color.purple.opacity(0.12))
                        .foregroundStyle(Color.purple)
                        .clipShape(Capsule())
                }
            }

            if let item = scenario {
                VStack(alignment: .leading, spacing: 8) {
                    Text(item.title)
                        .font(.system(size: 13, weight: .semibold))

                    Text(item.description)
                        .font(.system(size: 11.5))
                        .foregroundStyle(.secondary)

                    Divider().padding(.vertical, 2)

                    ForEach(item.dialogues) { dlg in
                        HStack(alignment: .top, spacing: 8) {
                            Text(dlg.speaker)
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(dlg.speaker == "Bạn" ? TransToolsTheme.accent : .secondary)
                                .frame(width: 50, alignment: .leading)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(dlg.original)
                                    .font(.system(size: 12, weight: .medium))

                                Text(dlg.translation)
                                    .font(.system(size: 11))
                                    .foregroundStyle(.secondary)
                            }

                            Spacer()

                            Button {
                                vocabManager.speak(dlg.original, language: item.language.voiceLocale)
                            } label: {
                                Image(systemName: "speaker.wave.2")
                                    .font(.system(size: 10))
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding(12)
                .background(Color.primary.opacity(0.02))
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(Color.primary.opacity(0.08), lineWidth: 1)
                )
        )
    }
}

// MARK: - 2. Từ Vựng Của Tôi (My Vocabulary Learning View)

struct MyVocabularyLearningView: View {
    @ObservedObject var manager: LanguageLearningManager
    @ObservedObject var vocabManager: VocabularyManager
    var onStartSRS: () -> Void

    @State private var searchText = ""
    @State private var selectedFilter: Int = 0 // 0: Tất cả, 1: Cần ôn, 2: Đang học, 3: Đã thuộc
    @State private var showAddModal = false

    private var languageItems: [VocabularyItem] {
        vocabManager.items.filter { $0.language == manager.selectedLanguage.rawValue }
    }

    var filteredItems: [VocabularyItem] {
        var list = languageItems

        if selectedFilter == 1 {
            let now = Date()
            list = list.filter { ($0.dueAt == nil || $0.dueAt! <= now) }
        } else if selectedFilter == 2 {
            list = list.filter { !$0.isMastered }
        } else if selectedFilter == 3 {
            list = list.filter { $0.isMastered }
        }

        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if !query.isEmpty {
            list = list.filter {
                $0.word.lowercased().contains(query) ||
                $0.meaning.lowercased().contains(query) ||
                $0.phonetic.lowercased().contains(query) ||
                $0.context.lowercased().contains(query)
            }
        }
        return list
    }

    var body: some View {
        VStack(spacing: 16) {
            // Header Bar
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Kho từ vựng của bạn")
                        .font(.system(size: 16, weight: .bold))
                    Text("Lưu từ bản dịch, cuộc họp hoặc nhập thủ công kèm câu gốc ngữ cảnh.")
                        .font(.system(size: 11.5))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                // Practice SRS Flashcards Button
                Button {
                    onStartSRS()
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "sparkles.rectangle.stack.fill")
                        Text("Ôn Flashcard (\(manager.dueTodayCount))")
                    }
                    .font(.system(size: 11.5, weight: .bold))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(TransToolsTheme.accent)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
                .buttonStyle(.plain)

                // Add Word Button
                Button {
                    showAddModal = true
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "plus")
                        Text("Thêm từ mới")
                    }
                    .font(.system(size: 11.5, weight: .semibold))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color.primary.opacity(0.06))
                    .foregroundStyle(Color.primary)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
                .buttonStyle(.plain)
            }

            // Search and Filters Bar
            HStack(spacing: 12) {
                // Search Input
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    TextField("Tìm từ, nghĩa, phát âm...", text: $searchText)
                        .textFieldStyle(.plain)
                        .font(.system(size: 12))
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color(nsColor: .controlBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(Color.primary.opacity(0.08), lineWidth: 1)
                )

                // Filter Picker
                Picker("", selection: $selectedFilter) {
                    Text("Tất cả (\(languageItems.count))").tag(0)
                    Text("Cần ôn (\(manager.dueTodayCount))").tag(1)
                    Text("Đang học (\(languageItems.filter { !$0.isMastered }.count))").tag(2)
                    Text("Đã thuộc (\(languageItems.filter { $0.isMastered }.count))").tag(3)
                }
                .pickerStyle(.segmented)
                .frame(width: 380)
            }

            // Word List
            if filteredItems.isEmpty {
                VStack(spacing: 12) {
                    Spacer().frame(height: 30)
                    Image(systemName: "character.book.closed")
                        .font(.system(size: 40))
                        .foregroundStyle(.secondary.opacity(0.3))
                    Text("Không tìm thấy từ vựng phù hợp")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.secondary)
                    if vocabManager.items.isEmpty {
                        Button {
                            manager.seedStarterVocabulary()
                        } label: {
                            Text("Nạp 5 từ khởi đầu cho \(manager.selectedLanguage.displayName)")
                                .font(.system(size: 12, weight: .semibold))
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(TransToolsTheme.accent.opacity(0.15))
                                .foregroundStyle(TransToolsTheme.accent)
                                .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                    Spacer().frame(height: 30)
                }
            } else {
                VStack(spacing: 8) {
                    ForEach(filteredItems) { item in
                        VocabularyCardRow(item: item, vocabManager: vocabManager)
                    }
                }
            }
        }
        .sheet(isPresented: $showAddModal) {
            AddWordSheetView(vocabManager: vocabManager, defaultLanguage: manager.selectedLanguage.rawValue)
        }
    }
}

// Vocabulary Row
struct VocabularyCardRow: View {
    let item: VocabularyItem
    @ObservedObject var vocabManager: VocabularyManager

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            // Word and Reading
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    Text(item.word)
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundStyle(.primary)

                    if !item.phonetic.isEmpty {
                        Text(item.phonetic)
                            .font(.system(size: 12, weight: .medium, design: .monospaced))
                            .foregroundStyle(TransToolsTheme.navy)
                    }

                    if item.isMastered {
                        Text("Đã thuộc")
                            .font(.system(size: 9.5, weight: .bold))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1.5)
                            .background(Color.green.opacity(0.15))
                            .foregroundStyle(Color.green)
                            .clipShape(Capsule())
                    }
                }

                Text(item.meaning)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(TransToolsTheme.accent)

                if !item.context.isEmpty && item.context != item.word {
                    Text("“\(item.context)”")
                        .font(.system(size: 11, design: .serif))
                        .italic()
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }

            Spacer()

            // SRS Info
            VStack(alignment: .trailing, spacing: 2) {
                Text("Khoảng ôn: \(item.interval) ngày")
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(.secondary)
                Text("Lần ôn: \(item.repetition)")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary.opacity(0.8))
            }

            // Speak Button
            Button {
                vocabManager.speak(item.word, language: item.language)
            } label: {
                Image(systemName: "speaker.wave.2.fill")
                    .font(.system(size: 12))
                    .frame(width: 28, height: 28)
                    .background(Color.primary.opacity(0.06))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)

            // Mastered Toggle Button
            Button {
                vocabManager.toggleMastered(id: item.id)
            } label: {
                Image(systemName: item.isMastered ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 14))
                    .foregroundStyle(item.isMastered ? .green : .secondary)
            }
            .buttonStyle(.plain)

            // Delete Button
            Button {
                vocabManager.remove(id: item.id)
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary.opacity(0.6))
            }
            .buttonStyle(.plain)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(Color.primary.opacity(0.06), lineWidth: 1)
                )
        )
    }
}

// Add Word Modal
struct AddWordSheetView: View {
    @ObservedObject var vocabManager: VocabularyManager
    var defaultLanguage: String
    @Environment(\.dismiss) private var dismiss

    @State private var word = ""
    @State private var meaning = ""
    @State private var phonetic = ""
    @State private var context = ""

    var body: some View {
        VStack(spacing: 16) {
            Text("Thêm từ vựng mới")
                .font(.system(size: 15, weight: .bold))

            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Từ hoặc cụm từ:")
                        .font(.system(size: 11.5, weight: .medium))
                    TextField("Ví dụ: action item, 承知いたしました", text: $word)
                        .textFieldStyle(.roundedBorder)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("Nghĩa tiếng Việt:")
                        .font(.system(size: 11.5, weight: .medium))
                    TextField("Ví dụ: việc cần làm, tôi đã rõ", text: $meaning)
                        .textFieldStyle(.roundedBorder)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("Phiên âm / Cách đọc (tùy chọn):")
                        .font(.system(size: 11.5, weight: .medium))
                    TextField("Ví dụ: /.../, furigana, pinyin", text: $phonetic)
                        .textFieldStyle(.roundedBorder)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("Câu ví dụ ngữ cảnh (tùy chọn):")
                        .font(.system(size: 11.5, weight: .medium))
                    TextField("Câu trong cuộc họp hoặc bản dịch", text: $context)
                        .textFieldStyle(.roundedBorder)
                }
            }

            HStack {
                Button("Hủy") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Spacer()

                Button("Lưu từ") {
                    vocabManager.add(
                        word: word,
                        meaning: meaning,
                        phonetic: phonetic,
                        context: context,
                        sourceApp: "Trans Tools",
                        language: defaultLanguage
                    )
                    dismiss()
                }
                .buttonStyle(TransToolsActionButtonStyle(prominent: true))
                .keyboardShortcut(.defaultAction)
                .disabled(word.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || meaning.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(20)
        .frame(width: 380)
    }
}

// MARK: - 3. Luyện Giao Tiếp (Communication Practice View)

struct CommunicationPracticeView: View {
    @ObservedObject var manager: LanguageLearningManager
    @ObservedObject var vocabManager: VocabularyManager

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            // Header
            VStack(alignment: .leading, spacing: 4) {
                Text("Luyện giao tiếp theo nhiệm vụ (Task-based)")
                    .font(.system(size: 16, weight: .bold))
                Text("Thực hành theo CEFR: Giới thiệu bản thân, phát biểu trong cuộc họp, viết email hoặc trao đổi công việc.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }

            // Scenarios List
            ForEach(manager.getScenarios()) { scenario in
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 8) {
                        Image(systemName: scenario.icon)
                            .font(.system(size: 14))
                            .foregroundStyle(TransToolsTheme.accent)
                        Text(scenario.title)
                            .font(.system(size: 14, weight: .bold))
                        Spacer()
                        Text(scenario.category)
                            .font(.system(size: 11, weight: .bold))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(TransToolsTheme.accent.opacity(0.12))
                            .foregroundStyle(TransToolsTheme.accent)
                            .clipShape(Capsule())
                    }

                    Text(scenario.description)
                        .font(.system(size: 11.5))
                        .foregroundStyle(.secondary)

                    VStack(spacing: 8) {
                        ForEach(scenario.dialogues) { dlg in
                            HStack(alignment: .top, spacing: 10) {
                                Text(dlg.speaker)
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundStyle(dlg.speaker == "Bạn" ? TransToolsTheme.accent : .secondary)
                                    .frame(width: 55, alignment: .leading)

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(dlg.original)
                                        .font(.system(size: 13, weight: .medium))

                                    if !dlg.reading.isEmpty {
                                        Text(dlg.reading)
                                            .font(.system(size: 11, design: .monospaced))
                                            .foregroundStyle(TransToolsTheme.navy)
                                    }

                                    Text(dlg.translation)
                                        .font(.system(size: 11.5))
                                        .foregroundStyle(.secondary)
                                }

                                Spacer()

                                Button {
                                    vocabManager.speak(dlg.original, language: scenario.language.voiceLocale)
                                } label: {
                                    HStack(spacing: 4) {
                                        Image(systemName: "speaker.wave.2")
                                        Text("Nghe")
                                    }
                                    .font(.system(size: 10.5, weight: .medium))
                                    .padding(.horizontal, 7)
                                    .padding(.vertical, 3)
                                    .background(Color.primary.opacity(0.06))
                                    .clipShape(Capsule())
                                }
                                .buttonStyle(.plain)

                                Button {
                                    vocabManager.add(
                                        word: dlg.original,
                                        meaning: dlg.translation,
                                        phonetic: dlg.reading,
                                        context: scenario.title,
                                        sourceApp: "Luyện giao tiếp",
                                        language: scenario.language.rawValue
                                    )
                                } label: {
                                    Image(systemName: "bookmark")
                                        .font(.system(size: 10.5))
                                        .foregroundStyle(TransToolsTheme.accent)
                                }
                                .buttonStyle(.plain)
                                .help("Lưu câu này vào Sổ từ vựng")
                            }
                            .padding(10)
                            .background(Color.primary.opacity(0.025))
                            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        }
                    }
                }
                .padding(16)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Color(nsColor: .controlBackgroundColor))
                        .overlay(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
                        )
                )
            }
        }
    }
}

// MARK: - 4. Tiến Bộ (Learning Progress View)

struct LearningProgressView: View {
    @ObservedObject var manager: LanguageLearningManager
    @ObservedObject var vocabManager: VocabularyManager
    var onStartSRS: () -> Void

    private var languageItems: [VocabularyItem] {
        vocabManager.items.filter { $0.language == manager.selectedLanguage.rawValue }
    }

    var masteredCount: Int {
        languageItems.filter { $0.isMastered }.count
    }

    var learningCount: Int {
        languageItems.filter { !$0.isMastered }.count
    }

    var body: some View {
        VStack(spacing: 18) {
            // Stats Grid
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 14) {
                statBox(title: "Tổng từ vựng", value: "\(languageItems.count)", icon: "character.book.closed.fill", color: TransToolsTheme.navy)
                statBox(title: "Cần ôn hôm nay", value: "\(manager.dueTodayCount)", icon: "sparkles.rectangle.stack.fill", color: .orange)
                statBox(title: "Đang củng cố", value: "\(learningCount)", icon: "hourglass", color: .blue)
                statBox(title: "Đã nhớ vững", value: "\(masteredCount)", icon: "checkmark.circle.fill", color: .green)
            }

            // Memory Retention Breakdown
            VStack(alignment: .leading, spacing: 12) {
                Text("Phân bổ trạng thái ghi nhớ")
                    .font(.system(size: 14, weight: .bold))

                VStack(spacing: 8) {
                    progressRow(title: "Từ đã nhớ sâu (khoảng ôn > 14 ngày)", count: languageItems.filter { $0.interval >= 14 }.count, total: max(1, languageItems.count), color: .green)
                    progressRow(title: "Từ đang củng cố (khoảng ôn 3–13 ngày)", count: languageItems.filter { $0.interval >= 3 && $0.interval < 14 }.count, total: max(1, languageItems.count), color: .blue)
                    progressRow(title: "Từ mới nạp (khoảng ôn 1–2 ngày)", count: languageItems.filter { $0.interval < 3 }.count, total: max(1, languageItems.count), color: .orange)
                }
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color(nsColor: .controlBackgroundColor))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(Color.primary.opacity(0.08), lineWidth: 1)
                    )
            )

            // Scientific Note Banner
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "lightbulb.fill")
                    .font(.system(size: 16))
                    .foregroundStyle(.yellow)

                VStack(alignment: .leading, spacing: 4) {
                    Text("Cơ sở khoa học về việc ghi nhớ")
                        .font(.system(size: 13, weight: .bold))
                    Text("Theo phân tích của Kim & Webb (2022) và The Learning Scientists: não bộ chỉ củng cố liên kết thần kinh mạnh nhất khi bạn nỗ lực tự nhớ lại (Retrieval Practice) trước khi lật xem kết quả. Giữ khoảng cách ôn cách quãng đều đặn 5–10 phút mỗi ngày mang lại hiệu quả bền vững hơn học dồn một lần.")
                        .font(.system(size: 11.5))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(14)
            .background(TransToolsTheme.mint.opacity(0.18))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }

    private func statBox(title: String, value: String, icon: String, color: Color) -> some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 18))
                .foregroundStyle(color)

            Text(value)
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .foregroundStyle(.primary)

            Text(title)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(Color.primary.opacity(0.08), lineWidth: 1)
                )
        )
    }

    private func progressRow(title: String, count: Int, total: Int, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title)
                    .font(.system(size: 11.5, weight: .medium))
                Spacer()
                Text("\(count) từ (\(Int(Double(count) / Double(total) * 100))%)")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.secondary)
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.secondary.opacity(0.15))
                        .frame(height: 6)

                    Capsule()
                        .fill(color)
                        .frame(width: max(4, geo.size.width * CGFloat(Double(count) / Double(total))), height: 6)
                }
            }
            .frame(height: 6)
        }
    }
}

// MARK: - 5. Mục Tiêu & Bắt Đầu (Goal & Onboarding View)

struct GoalAndOnboardingView: View {
    @ObservedObject var manager: LanguageLearningManager
    @ObservedObject var vocabManager: VocabularyManager
    var onCompleted: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Title
            VStack(alignment: .leading, spacing: 4) {
                Text("Bắt đầu: Thiết lập mục tiêu học tập")
                    .font(.system(size: 18, weight: .bold))
                Text("Chọn ngôn ngữ, trình độ và thời gian mỗi ngày để Trans Tools điều chỉnh bài học phù hợp với bạn.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }

            // 1. Target Language
            VStack(alignment: .leading, spacing: 10) {
                Text("1. Chọn ngôn ngữ muốn học:")
                    .font(.system(size: 13, weight: .bold))

                HStack(spacing: 12) {
                    ForEach(LearningLanguage.allCases) { lang in
                        Button {
                            manager.selectedLanguage = lang
                        } label: {
                            VStack(spacing: 6) {
                                Text(lang.flag)
                                    .font(.system(size: 26))
                                Text(lang.displayName)
                                    .font(.system(size: 12, weight: .bold))
                                Text(lang.greeting)
                                    .font(.system(size: 9.5))
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(manager.selectedLanguage == lang ? TransToolsTheme.accent.opacity(0.12) : Color(nsColor: .controlBackgroundColor))
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .stroke(manager.selectedLanguage == lang ? TransToolsTheme.accent : Color.primary.opacity(0.08), lineWidth: manager.selectedLanguage == lang ? 2 : 1)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            // 2. Current Level
            VStack(alignment: .leading, spacing: 10) {
                Text("2. Trình độ hiện tại:")
                    .font(.system(size: 13, weight: .bold))

                VStack(spacing: 8) {
                    ForEach(LearningLevel.allCases) { lvl in
                        Button {
                            manager.selectedLevel = lvl
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: manager.selectedLevel == lvl ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(manager.selectedLevel == lvl ? TransToolsTheme.accent : .secondary)

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(lvl.title)
                                        .font(.system(size: 13, weight: .semibold))
                                    Text(lvl.description)
                                        .font(.system(size: 11))
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                            }
                            .padding(12)
                            .background(manager.selectedLevel == lvl ? TransToolsTheme.mint.opacity(0.18) : Color(nsColor: .controlBackgroundColor))
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .stroke(manager.selectedLevel == lvl ? TransToolsTheme.accent : Color.primary.opacity(0.08), lineWidth: 1)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            // 3. Goal
            VStack(alignment: .leading, spacing: 10) {
                Text("3. Mục tiêu chính:")
                    .font(.system(size: 13, weight: .bold))

                HStack(spacing: 12) {
                    ForEach(LearningGoal.allCases) { goal in
                        Button {
                            manager.selectedGoal = goal
                        } label: {
                            VStack(alignment: .leading, spacing: 6) {
                                Image(systemName: goal.icon)
                                    .font(.system(size: 16))
                                    .foregroundStyle(TransToolsTheme.accent)

                                Text(goal.title)
                                    .font(.system(size: 12.5, weight: .bold))

                                Text(goal.description)
                                    .font(.system(size: 10.5))
                                    .foregroundStyle(.secondary)
                                    .lineLimit(2)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(12)
                            .background(manager.selectedGoal == goal ? TransToolsTheme.accent.opacity(0.12) : Color(nsColor: .controlBackgroundColor))
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .stroke(manager.selectedGoal == goal ? TransToolsTheme.accent : Color.primary.opacity(0.08), lineWidth: manager.selectedGoal == goal ? 2 : 1)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            // 4. Daily Commitment
            VStack(alignment: .leading, spacing: 10) {
                Text("4. Thời gian học mỗi ngày:")
                    .font(.system(size: 13, weight: .bold))

                HStack(spacing: 14) {
                    dailyTimeOption(mins: 5, label: "5 phút (Nhẹ nhàng)")
                    dailyTimeOption(mins: 10, label: "10 phút (Khuyến nghị)")
                    dailyTimeOption(mins: 15, label: "15 phút (Chuyên sâu)")
                }
            }

            Text("Giọng đọc dùng cấu hình riêng của ngôn ngữ đã chọn. Bạn có thể chọn mô hình và nghe thử trong Cài đặt → Giọng đọc & Phát âm. Bài học chữ cơ bản dùng bản ghi phát âm.")
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            // Save & Start Button
            HStack {
                Spacer()
                Button {
                    manager.hasConfiguredGoal = true
                    onCompleted()
                } label: {
                    HStack(spacing: 6) {
                        Text("Lưu mục tiêu & Bắt đầu học")
                        Image(systemName: "arrow.right")
                    }
                    .font(.system(size: 13, weight: .bold))
                    .padding(.horizontal, 22)
                    .padding(.vertical, 10)
                    .background(TransToolsTheme.accent)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
                .buttonStyle(.plain)
                Spacer()
            }
            .padding(.top, 10)
        }
    }

    private func dailyTimeOption(mins: Int, label: String) -> some View {
        Button {
            manager.dailyMinutes = mins
        } label: {
            HStack(spacing: 6) {
                Image(systemName: manager.dailyMinutes == mins ? "largecircle.fill.circle" : "circle")
                    .foregroundStyle(manager.dailyMinutes == mins ? TransToolsTheme.accent : .secondary)
                Text(label)
                    .font(.system(size: 12, weight: manager.dailyMinutes == mins ? .bold : .medium))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(manager.dailyMinutes == mins ? TransToolsTheme.accent.opacity(0.1) : Color(nsColor: .controlBackgroundColor))
            .clipShape(Capsule())
            .overlay(
                Capsule().stroke(manager.dailyMinutes == mins ? TransToolsTheme.accent : Color.primary.opacity(0.1), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Interactive SRS Flashcard Modal View

struct SRSFlashcardModalView: View {
    @ObservedObject var vocabManager: VocabularyManager
    @ObservedObject var learningManager: LanguageLearningManager
    @Environment(\.dismiss) private var dismiss

    @State private var isFreePractice = false
    @State private var sessionCards: [VocabularyItem] = []
    @State private var currentIndex: Int = 0
    @State private var isFlipped: Bool = false
    @State private var isFinished: Bool = false
    @State private var reviewedCountInSession: Int = 0

    public var body: some View {
        VStack(spacing: 16) {
            // Header
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: "sparkles.rectangle.stack.fill")
                        .foregroundStyle(TransToolsTheme.accent)
                    Text(isFreePractice ? "Luyện thẻ tự do" : "Ôn tập Flashcard")
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                }

                Spacer()

                if !sessionCards.isEmpty && !isFinished {
                    Text("\(currentIndex + 1) / \(sessionCards.count)")
                        .font(.system(size: 12, weight: .bold, design: .monospaced))
                        .foregroundStyle(.secondary)
                }

                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 18))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.cancelAction)
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)

            if isFinished {
                // Completed Session Celebration
                VStack(spacing: 14) {
                    Spacer()
                    Image(systemName: "checkmark.seal.fill")
                        .font(.system(size: 54))
                        .foregroundStyle(.green)

                    Text("Hoàn thành phiên ôn tập!")
                        .font(.system(size: 18, weight: .bold))

                    Text("Bạn đã củng cố thành công \(reviewedCountInSession) thẻ từ vựng hôm nay.")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)

                    Button {
                        dismiss()
                    } label: {
                        Text("Quay lại Hôm nay")
                            .font(.system(size: 13, weight: .bold))
                            .padding(.horizontal, 20)
                            .padding(.vertical, 8)
                            .background(TransToolsTheme.accent)
                            .foregroundStyle(.white)
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 8)
                    Spacer()
                }
                .frame(height: 280)
            } else if sessionCards.isEmpty {
                VStack(spacing: 12) {
                    Spacer()
                    Image(systemName: "tray")
                        .font(.system(size: 40))
                        .foregroundStyle(.secondary.opacity(0.4))
                    Text("Không có thẻ nào cần ôn vào lúc này.")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .frame(height: 280)
            } else {
                let currentItem = sessionCards[currentIndex]

                // Main Flashcard Box
                ZStack {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(Color(nsColor: .controlBackgroundColor))
                        .shadow(color: Color.black.opacity(0.08), radius: 10, y: 3)
                        .overlay(
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .stroke(Color.primary.opacity(0.08), lineWidth: 1.2)
                        )

                    VStack(spacing: 14) {
                        if !isFlipped {
                            // Front Side
                            Spacer()
                            Text(currentItem.word)
                                .font(.system(size: 28, weight: .bold, design: .rounded))
                                .foregroundStyle(.primary)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 20)

                            if !currentItem.phonetic.isEmpty {
                                Text(currentItem.phonetic)
                                    .font(.system(size: 14, weight: .medium, design: .monospaced))
                                    .foregroundStyle(TransToolsTheme.navy)
                            }

                            HStack(spacing: 10) {
                                Button {
                                    vocabManager.speak(currentItem.word, language: currentItem.language, rate: 0.46)
                                } label: {
                                    HStack(spacing: 5) {
                                        Image(systemName: "speaker.wave.2.fill")
                                        Text("Phát âm")
                                    }
                                    .font(.system(size: 11, weight: .semibold))
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 4)
                                    .background(TransToolsTheme.accent.opacity(0.12))
                                    .foregroundStyle(TransToolsTheme.accent)
                                    .clipShape(Capsule())
                                }
                                .buttonStyle(.plain)

                                Button {
                                    vocabManager.speak(currentItem.word, language: currentItem.language, rate: 0.32)
                                } label: {
                                    HStack(spacing: 4) {
                                        Image(systemName: "tortoise.fill")
                                        Text("Chậm")
                                    }
                                    .font(.system(size: 11, weight: .medium))
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(Color.secondary.opacity(0.1))
                                    .foregroundStyle(.secondary)
                                    .clipShape(Capsule())
                                }
                                .buttonStyle(.plain)
                            }

                            if !currentItem.context.isEmpty && currentItem.context != currentItem.word {
                                Text("“\(currentItem.context)”")
                                    .font(.system(size: 11.5, design: .serif))
                                    .italic()
                                    .foregroundStyle(.secondary)
                                    .multilineTextAlignment(.center)
                                    .padding(.horizontal, 24)
                            }

                            Spacer()

                            Text("Bấm vào thẻ hoặc nhấn Phím Cách để lật xem đáp án")
                                .font(.system(size: 10.5, weight: .medium))
                                .foregroundStyle(.secondary.opacity(0.7))
                                .padding(.bottom, 12)
                        } else {
                            // Back Side
                            Spacer()
                            Text(currentItem.word)
                                .font(.system(size: 16, weight: .semibold, design: .rounded))
                                .foregroundStyle(.secondary)

                            if !currentItem.phonetic.isEmpty {
                                Text(currentItem.phonetic)
                                    .font(.system(size: 13, design: .monospaced))
                                    .foregroundStyle(TransToolsTheme.navy)
                            }

                            Text(currentItem.meaning)
                                .font(.system(size: 22, weight: .bold))
                                .foregroundStyle(TransToolsTheme.accent)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 20)

                            if !currentItem.context.isEmpty && currentItem.context != currentItem.word {
                                Text("“\(currentItem.context)”")
                                    .font(.system(size: 12, design: .serif))
                                    .italic()
                                    .foregroundStyle(.secondary)
                                    .multilineTextAlignment(.center)
                                    .padding(.horizontal, 24)
                            }

                            Spacer()

                            Text("Tự đánh giá mức độ nhớ của bạn bên dưới:")
                                .font(.system(size: 10.5, weight: .medium))
                                .foregroundStyle(.secondary.opacity(0.8))
                                .padding(.bottom, 4)
                        }
                    }
                }
                .frame(height: 250)
                .padding(.horizontal, 20)
                .contentShape(Rectangle())
                .onTapGesture {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) {
                        isFlipped.toggle()
                    }
                }

                // Bottom SRS Evaluation Buttons (Only when flipped)
                if isFlipped {
                    HStack(spacing: 8) {
                        srsGradeButton(title: "Quên", subtitle: isFreePractice ? "Tự đánh giá" : "10 phút", color: .red, grade: .again)
                        srsGradeButton(title: "Khó", subtitle: isFreePractice ? "Tự đánh giá" : "Giãn chậm", color: .orange, grade: .hard)
                        srsGradeButton(title: "Nhớ", subtitle: isFreePractice ? "Tự đánh giá" : "Theo lịch ôn", color: .green, grade: .good)
                        srsGradeButton(title: "Dễ", subtitle: isFreePractice ? "Tự đánh giá" : "Giãn lâu hơn", color: .blue, grade: .easy)
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 14)
                } else {
                    // Quick Flip Prompt Button
                    Button {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) {
                            isFlipped = true
                        }
                    } label: {
                        Text("Lật xem đáp án")
                            .font(.system(size: 12, weight: .bold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                            .background(TransToolsTheme.accent.opacity(0.12))
                            .foregroundStyle(TransToolsTheme.accent)
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 14)
                }
            }
        }
        .frame(width: 480)
        .onAppear {
            setupCards()
        }
    }

    private func setupCards() {
        let due = vocabManager.dueItems.filter { $0.language == learningManager.selectedLanguage.rawValue }
        isFreePractice = due.isEmpty
        if !due.isEmpty {
            sessionCards = due
        } else {
            sessionCards = Array(vocabManager.items.filter { $0.language == learningManager.selectedLanguage.rawValue }.prefix(10))
        }
        currentIndex = 0
        isFlipped = false
        isFinished = sessionCards.isEmpty
    }

    private func srsGradeButton(title: String, subtitle: String, color: Color, grade: VocabularyManager.SRSGrade) -> some View {
        Button {
            let currentItem = sessionCards[currentIndex]
            if !isFreePractice {
                vocabManager.review(itemId: currentItem.id, grade: grade)
            }
            learningManager.markReviewCompleted()
            reviewedCountInSession += 1

            if currentIndex < sessionCards.count - 1 {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
                    currentIndex += 1
                    isFlipped = false
                }
            } else {
                withAnimation {
                    isFinished = true
                }
            }
        } label: {
            VStack(spacing: 2) {
                Text(title)
                    .font(.system(size: 12, weight: .bold))
                Text(subtitle)
                    .font(.system(size: 9.5))
                    .opacity(0.85)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background(color.opacity(0.15))
            .foregroundStyle(color)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(color.opacity(0.3), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}
