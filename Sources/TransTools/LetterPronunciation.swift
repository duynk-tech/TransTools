import SwiftUI

struct LetterPronunciationView: View {
    let symbol: String
    let reading: String
    let index: Int
    let language: LearningLanguage
    @State private var level = 0
    @State private var british = false
    @State private var showSource = false
    @StateObject private var audio = OfflineIPAPlayer()
    @ObservedObject private var voiceService = LanguagePronunciationService.shared

    private var localFile: URL? {
        language == .english && level == 0 ? LocalEnglishRecordings.file(for: symbol) : nil
    }

    private var referenceURL: URL {
        let address: String
        switch language {
        case .english:
            address = "https://dictionary.cambridge.org/pronunciation/english/" + (level == 1 ? example : symbol.lowercased())
        case .japanese:
            let katakana = symbol.unicodeScalars.contains { (0x30A0...0x30FF).contains($0.value) }
            address = katakana ? "https://www3.nhk.or.jp/nhkworld/lesson/vi/letters/katakana.html" : "https://www3.nhk.or.jp/nhkworld/lesson/vi/letters/hiragana.html"
        case .korean:
            address = "https://nuri.iksi.or.kr/practice/learningKoreanPronunciation/kor/index.html"
        case .chinese:
            address = "https://zim.vn/bang-phien-am-tieng-trung-pinyin"
        }
        return URL(string: address)!
    }

    private var sourceName: String {
        switch language {
        case .english: return "Cambridge Dictionary"
        case .japanese: return "NHK WORLD-JAPAN · Cùng nhau học tiếng Nhật"
        case .korean: return "King Sejong Institute"
        case .chinese: return "ZIM Academy · Bảng phiên âm tiếng Trung Pinyin"
        }
    }

    private var sourceGuidance: String {
        switch language {
        case .english: return "Nhấn biểu tượng loa \(british ? "UK" : "US") trên trang Cambridge để nghe \(level == 1 ? example : symbol). Chọn phần tên chữ khi đánh vần."
        case .japanese: return "Khóa học chính thức của NHK World-Japan. Bấm vào từng chữ để nghe phát âm và xem thứ tự nét vẽ."
        case .korean: return "Chọn bài nguyên âm/phụ âm phù hợp trên trang Viện King Sejong."
        case .chinese: return "Cẩm nang phiên âm Pinyin chuẩn của ZIM Academy phân tích đầy đủ thanh mẫu, vận mẫu, 4 thanh điệu và biến điệu."
        }
    }

    private var example: String {
        let words: [String]
        switch language {
        case .english:
            words = "apple book cat dog egg fish green house ice juice key lamp moon nose orange pen queen red sun tea umbrella violin water box yellow zoo".components(separatedBy: " ")
        case .japanese:
            words = "あめ いぬ うみ えき おと かさ きく くつ けさ こえ さかな しお すし せかい そら たこ ちず つき て とり なつ にく ぬの ねこ のり はな ひと ふね へや ほし まめ みみ むし め もり やま ゆき よる らくだ りんご るす れい ろく わに パンをたべます ほん".components(separatedBy: " ")
        case .chinese:
            words = "爸爸 跑 妈妈 饭 弟弟 她 你 来 哥哥 看 喝 家 去 谢谢 早 菜 三 中国 吃饭 水 热 一 我".components(separatedBy: " ")
        case .korean:
            words = "가 나 다 라 마 바 사 아 자 차 카 타 파 하 아 야 어 여 오 요 우 유 으 이".components(separatedBy: " ")
        }
        return words[min(index, words.count - 1)]
    }

    private var baseReading: String {
        switch language {
        case .english: return EnglishLetterGuide.name(index, british: british)
        case .korean:
            let names = "기역 니은 디귿 리을 미음 비읍 시옷 이응 지읒 치읓 키읔 티읕 피읖 히읗 아 야 어 여 오 요 우 유 으 이".components(separatedBy: " ")
            return names[min(index, names.count - 1)]
        default: return symbol
        }
    }

    private var context: String {
        switch language {
        case .english: return "Practice the word \(example)."
        case .japanese: return "「\(example)」といいます。"
        case .chinese: return "请读：\(example)。"
        case .korean: return "따라 읽어 보세요. \(example)."
        }
    }

    private var sample: String { level == 0 ? baseReading : level == 1 ? example : context }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Luyện đọc từng bước", systemImage: "speaker.wave.2.fill").font(.headline)

            if language == .english {
                Picker("Giọng tiếng Anh", selection: $british) {
                    Text("Anh–Mỹ · US").tag(false)
                    Text("Anh–Anh · UK").tag(true)
                }.pickerStyle(.segmented)
            }

            Picker("Cấp luyện đọc", selection: $level) {
                Text(language == .english ? "1 · Tên chữ" : "1 · Chữ").tag(0)
                Text(language == .korean ? "2 · Âm tiết" : "2 · Từ").tag(1)
                Text("3 · Trong câu").tag(2)
            }.pickerStyle(.segmented)

            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(level == 0 ? language == .english ? "\(symbol) · /\(EnglishLetterGuide.ipa(index, british: british))/" : "\(symbol) · \(reading)" : sample)
                        .font(.title3.bold())
                        .textSelection(.enabled)
                    Text(level == 0 ? "Nghe tên chữ / cách đọc chuẩn." : "Nghe ngữ cảnh rồi đọc theo; chú ý âm trước và sau.")
                        .font(.caption).foregroundStyle(.secondary)
                }

                Spacer()

                // Nút phát âm trực tiếp chuẩn bản xứ
                Button {
                    if let localFile {
                        audio.playFile(localFile, id: symbol)
                    } else {
                        voiceService.speak(text: sample, language: language)
                    }
                } label: {
                    Label(voiceService.isSpeaking ? "Đang phát..." : "Phát âm ngay", systemImage: voiceService.isSpeaking ? "speaker.wave.3.fill" : "speaker.wave.2")
                }
                .buttonStyle(.borderedProminent)
                .tint(TransToolsTheme.accent)

                // Nút mở nguồn tham khảo
                Button {
                    showSource = true
                } label: {
                    Image(systemName: "safari")
                }
                .buttonStyle(.bordered)
                .help("Mở bài học tại nguồn (\(sourceName))")
            }
            .controlSize(.large)

            if localFile != nil {
                HStack {
                    Text("AudioLang · file đã lưu trên máy").font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Button("Dừng") { audio.stop() }.disabled(audio.active == nil)
                }
            }

            Text("Nguồn học liệu: \(sourceName). Nhấn 'Phát âm ngay' để nghe âm chuẩn; biểu tượng Safari để mở trang bài học gốc.")
                .font(.caption).foregroundStyle(.secondary)

            DisclosureGroup("Cách luyện & Ghi chú nguồn") {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Quy trình học: Nghe → Dừng → Nhắc lại 3 lần → Luyện viết nét theo ô kẻ.")
                    if language == .english {
                        Text(EnglishLetterGuide.note(index))
                        Link("Cambridge · Phát âm UK/US ↗", destination: URL(string: "https://dictionary.cambridge.org/pronunciation/english/" + symbol.lowercased())!)
                        Link("British Council · Sounds Right ↗", destination: URL(string: "https://learnenglish.britishcouncil.org/apps/learnenglish-sounds-right")!)
                    } else if language == .japanese {
                        Link("Khóa học Hiragana · NHK WORLD-JAPAN ↗", destination: JapaneseNHKData.nhkHiraganaURL)
                        Link("Khóa học Katakana · NHK WORLD-JAPAN ↗", destination: JapaneseNHKData.nhkKatakanaURL)
                    } else if language == .chinese {
                        Link("Cẩm nang phiên âm Pinyin · ZIM Academy ↗", destination: ChinesePinyinData.zimPinyinURL)
                    }
                }
                .font(.caption).foregroundStyle(.secondary).padding(.top, 6)
            }
            .font(.caption)
        }
        .padding(16)
        .background(TransToolsTheme.accent.opacity(0.06), in: RoundedRectangle(cornerRadius: 14))
        .sheet(isPresented: $showSource) {
            PronunciationSourceView(url: referenceURL, title: sourceName, guidance: sourceGuidance)
        }
        .onChange(of: symbol) { _, _ in
            audio.stop()
            voiceService.stop()
            level = 0
        }
        .onChange(of: language) { _, _ in
            audio.stop()
            voiceService.stop()
            level = 0
        }
        .onChange(of: level) { _, _ in
            audio.stop()
            voiceService.stop()
        }
        .onChange(of: british) { _, _ in
            audio.stop()
            voiceService.stop()
        }
        .onDisappear {
            audio.stop()
            voiceService.stop()
        }
    }
}
