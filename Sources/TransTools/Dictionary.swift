import SwiftUI
import Foundation
import CoreServices

enum DictionaryMode: String, CaseIterable, Identifiable {
    case englishEnglish = "Anh – Anh", englishVietnamese = "Anh – Việt", vietnameseEnglish = "Việt – Anh"
    var id: String { rawValue }
}

struct DictionaryEntry: Decodable {
    struct Phonetic: Decodable { let text: String? }
    struct Meaning: Decodable {
        struct Definition: Decodable { let definition: String; let example: String? }
        let partOfSpeech: String
        let definitions: [Definition]
        let synonyms: [String]?
        let antonyms: [String]?
    }
    let word: String
    let phonetic: String?
    let phonetics: [Phonetic]
    let meanings: [Meaning]
    let sourceUrls: [String]?
    var ipa: String { phonetic ?? phonetics.compactMap(\.text).first ?? "" }
}

enum DictionaryService {
    static func offlineDefinition(_ word: String) -> String {
        DCSCopyTextDefinition(nil, word as CFString, CFRange(location: 0, length: word.utf16.count))?.takeRetainedValue() as String? ?? ""
    }
    static func localPhonetic(_ word: String) -> String {
        let text = offlineDefinition(word)
        let parts = text.components(separatedBy: "|")
        guard parts.count >= 3 else { return "" }
        let value = parts[1].trimmingCharacters(in: .whitespacesAndNewlines)
        return primaryPhonetic(value)
    }
    /// Show one pronunciation instead of repeating regional variants in compact cards.
    static func primaryPhonetic(_ value: String) -> String {
        let clean = value.trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "/[]"))
        let first = clean.components(separatedBy: ",").first?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return first.isEmpty ? "" : "/" + first.trimmingCharacters(in: CharacterSet(charactersIn: "/[]")) + "/"
    }
    static func entry(_ word: String) async throws -> DictionaryEntry {
        let url = URL(string: "https://api.dictionaryapi.dev/api/v2/entries/en/")!.appendingPathComponent(word)
        var request = URLRequest(url: url); request.timeoutInterval = 12
        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200,
              let entry = try JSONDecoder().decode([DictionaryEntry].self, from: data).first else {
            throw NSError(domain: "Dictionary", code: 404, userInfo: [NSLocalizedDescriptionKey: "Chưa tìm thấy mục từ. Hãy thử một từ đơn hoặc một cách viết khác."])
        }
        return entry
    }
    static func translate(_ text: String, vietnameseToEnglish: Bool = false) async throws -> String {
        try await AITranslator.translate(text, from: vietnameseToEnglish ? .vietnamese : .english,
            to: vietnameseToEnglish ? .english : .vietnamese, provider: .free, model: "", key: "")
    }
}

struct DictionaryView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var mode: DictionaryMode = .englishVietnamese
    @State private var entry: DictionaryEntry?
    @State private var translation = ""
    @State private var translatedDefinitions: [String: String] = [:]
    @State private var message = ""
    @State private var offlineDefinition = ""
    @State private var loading = false
    @State private var lookupTask: Task<Void, Never>?
    @State private var resultMode: DictionaryMode = .englishVietnamese
    @State private var resultQuery = ""
    @State private var englishWord = ""
    @AppStorage("DictionaryRecentWords") private var recentWordsJSON = "[]"
    private var recentWords: [String] { (try? JSONDecoder().decode([String].self, from: Data(recentWordsJSON.utf8))) ?? [] }
    private var pronunciation: String { entry?.ipa.isEmpty == false ? entry!.ipa : DictionaryService.localPhonetic(englishWord) }
    private var hasResult: Bool { entry != nil || !offlineDefinition.isEmpty || !translation.isEmpty }
    private func remember(_ word: String) {
        var words = recentWords.filter { $0.caseInsensitiveCompare(word) != .orderedSame }
        words.insert(word, at: 0)
        if let data = try? JSONEncoder().encode(Array(words.prefix(12))), let value = String(data: data, encoding: .utf8) { recentWordsJSON = value }
    }

    private func lookup() {
        let word = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !word.isEmpty else { return }
        lookupTask?.cancel(); entry = nil; translation = ""; translatedDefinitions = [:]; message = ""; loading = true
        let selectedMode = mode
        resultQuery = word; resultMode = selectedMode; englishWord = selectedMode == .vietnameseEnglish ? "" : word
        remember(word)
        offlineDefinition = selectedMode == .vietnameseEnglish ? "" : DictionaryService.offlineDefinition(word)
        lookupTask = Task { @MainActor in
            defer { if !Task.isCancelled { loading = false } }
            do {
                let english = selectedMode == .vietnameseEnglish ? try await DictionaryService.translate(word, vietnameseToEnglish: true) : word
                try Task.checkCancellation()
                englishWord = english
                if selectedMode == .vietnameseEnglish { offlineDefinition = DictionaryService.offlineDefinition(english) }
                if selectedMode != .englishEnglish {
                    translation = selectedMode == .vietnameseEnglish ? english : try await DictionaryService.translate(word)
                }
                let found = try await DictionaryService.entry(english)
                try Task.checkCancellation(); entry = found
                if selectedMode == .englishVietnamese {
                    for definition in found.meanings.flatMap(\.definitions).prefix(8) {
                        let translated = try await DictionaryService.translate(definition.definition)
                        try Task.checkCancellation(); translatedDefinitions[definition.definition] = translated
                    }
                }
            } catch is CancellationError {} catch {
                if !Task.isCancelled {
                    let timeout = (error as NSError).code == NSURLErrorTimedOut
                    message = timeout ? "Không kết nối được dịch vụ từ điển. Kiểm tra mạng và bấm Tra từ để thử lại." : error.localizedDescription
                }
            }
        }
    }

    private func saveWord() {
        VocabularyManager.shared.add(word: englishWord.isEmpty ? resultQuery : englishWord,
            meaning: translation.isEmpty ? entry?.meanings.first?.definitions.first?.definition ?? offlineDefinition : translation,
            phonetic: pronunciation, context: resultMode == .vietnameseEnglish ? resultQuery : "", sourceApp: "Siêu từ điển")
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Image(systemName: "books.vertical.fill").font(.title2).foregroundStyle(TransToolsTheme.accent)
                    .frame(width: 44, height: 44).background(TransToolsTheme.mint).clipShape(RoundedRectangle(cornerRadius: 13))
                VStack(alignment: .leading, spacing: 3) {
                    Text("Siêu từ điển").font(.system(size: 22, weight: .bold, design: .rounded))
                    Text("Hiểu nghĩa · Đọc đúng · Ghi nhớ lâu").font(.system(size: 11)).foregroundStyle(.secondary)
                }
                Spacer()
                Button { dismiss() } label: { Image(systemName: "xmark").padding(8) }
                    .buttonStyle(.plain).background(Color.secondary.opacity(0.08)).clipShape(Circle())
                    .help("Đóng từ điển").keyboardShortcut(.cancelAction)
            }.padding(22)
            Divider()
            HStack(alignment: .top, spacing: 0) {
                VStack(alignment: .leading, spacing: 20) {
                    VStack(alignment: .leading, spacing: 8) {
                        sidebarLabel("CHỌN TỪ ĐIỂN")
                        ForEach(DictionaryMode.allCases) { item in
                            Button { mode = item } label: {
                                HStack { Text(item.rawValue); Spacer(); if mode == item { Image(systemName: "checkmark.circle.fill") } }
                                    .font(.system(size: 13, weight: mode == item ? .semibold : .regular))
                                    .padding(12).background(mode == item ? TransToolsTheme.mint : .clear)
                                    .foregroundStyle(mode == item ? TransToolsTheme.accent : .primary)
                                    .clipShape(RoundedRectangle(cornerRadius: 10))
                            }.buttonStyle(.plain)
                        }
                    }
                    VStack(alignment: .leading, spacing: 10) {
                        sidebarLabel("TRA GẦN ĐÂY")
                        if recentWords.isEmpty { Text("Các từ bạn tra sẽ ở đây.").font(.caption).foregroundStyle(.secondary) }
                        ForEach(recentWords.prefix(8), id: \.self) { word in
                            Button { query = word; lookup() } label: {
                                HStack { Image(systemName: "clock").font(.caption); Text(word).lineLimit(1); Spacer() }
                            }.buttonStyle(.plain).font(.system(size: 12)).foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    VStack(alignment: .leading, spacing: 5) {
                        Label("Học thêm mỗi ngày", systemImage: "leaf.fill").font(.caption.bold()).foregroundStyle(TransToolsTheme.accent)
                        Text("Lưu từ vào sổ rồi ôn lại bằng Flashcard.").font(.caption).foregroundStyle(.secondary).lineSpacing(3)
                    }.padding(12).background(TransToolsTheme.mint.opacity(0.5)).clipShape(RoundedRectangle(cornerRadius: 12))
                }.padding(18).frame(width: 205).frame(maxHeight: .infinity)
                Divider()
                VStack(alignment: .leading, spacing: 16) {
                    HStack(spacing: 10) {
                        Image(systemName: "magnifyingglass").foregroundStyle(TransToolsTheme.accent)
                        TextField(mode == .vietnameseEnglish ? "Tra một từ hoặc cụm tiếng Việt…" : "Tra một từ tiếng Anh…", text: $query)
                            .textFieldStyle(.plain).font(.system(size: 15)).onSubmit(lookup)
                        if !query.isEmpty { Button { query = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary) }.buttonStyle(.plain) }
                        Button("Tra từ", action: lookup).buttonStyle(.borderedProminent)
                            .disabled(query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }.padding(12).background(Color(nsColor: .textBackgroundColor)).clipShape(RoundedRectangle(cornerRadius: 13))
                        .overlay(RoundedRectangle(cornerRadius: 13).stroke(TransToolsTheme.accent.opacity(0.2)))
                    ScrollView {
                        VStack(alignment: .leading, spacing: 18) {
                            if hasResult {
                                HStack(alignment: .top) {
                                    VStack(alignment: .leading, spacing: 9) {
                                        Text(resultMode.rawValue.uppercased()).font(.system(size: 9, weight: .bold)).tracking(1.5).foregroundStyle(TransToolsTheme.accent)
                                        Text(englishWord.isEmpty ? resultQuery : englishWord).font(.system(size: 34, weight: .bold, design: .rounded)).textSelection(.enabled)
                                        if !pronunciation.isEmpty { Text(pronunciation).font(.system(size: 17, design: .monospaced)).foregroundStyle(TransToolsTheme.navy).textSelection(.enabled) }
                                        Button { VocabularyManager.shared.speak(englishWord) } label: { Label("Nghe phát âm", systemImage: "speaker.wave.2.fill") }.buttonStyle(.bordered).controlSize(.small)
                                    }
                                    Spacer()
                                    Button(action: saveWord) { Label("Lưu từ", systemImage: "bookmark") }.buttonStyle(.bordered).controlSize(.small)
                                }
                                if !translation.isEmpty {
                                    VStack(alignment: .leading, spacing: 6) {
                                        sidebarLabel(resultMode == .vietnameseEnglish ? "TỪ TIẾNG VIỆT: " + resultQuery : "NGHĨA TIẾNG VIỆT")
                                        Text(translation).font(.system(size: 20, weight: .semibold)).foregroundStyle(TransToolsTheme.accent).textSelection(.enabled)
                                    }.padding(16).frame(maxWidth: .infinity, alignment: .leading).background(TransToolsTheme.mint.opacity(0.6)).clipShape(RoundedRectangle(cornerRadius: 13))
                                }
                                if let entry {
                                    ForEach(Array(entry.meanings.enumerated()), id: \.offset) { _, meaning in
                                        VStack(alignment: .leading, spacing: 14) {
                                            Text(meaning.partOfSpeech).font(.system(size: 12, weight: .semibold)).foregroundStyle(TransToolsTheme.accent)
                                                .padding(.horizontal, 10).padding(.vertical, 5).background(TransToolsTheme.mint).clipShape(Capsule())
                                            ForEach(Array(meaning.definitions.enumerated()), id: \.offset) { index, definition in
                                                HStack(alignment: .top, spacing: 12) {
                                                    Text("\(index + 1)").font(.caption.bold()).foregroundStyle(TransToolsTheme.accent).frame(width: 23, height: 23).background(TransToolsTheme.mint.opacity(0.6)).clipShape(Circle())
                                                    VStack(alignment: .leading, spacing: 8) {
                                                        Text(definition.definition).font(.system(size: 14)).lineSpacing(4)
                                                        if let translated = translatedDefinitions[definition.definition] { Text(translated).font(.system(size: 13)).foregroundStyle(.secondary).lineSpacing(3) }
                                                        if let example = definition.example { Text("“\(example)”").font(.system(size: 13, design: .serif)).italic().foregroundStyle(.secondary).padding(10).frame(maxWidth: .infinity, alignment: .leading).background(TransToolsTheme.background).clipShape(RoundedRectangle(cornerRadius: 8)) }
                                                    }.textSelection(.enabled)
                                                }
                                            }
                                            relatedWords("Đồng nghĩa", words: meaning.synonyms ?? [])
                                            relatedWords("Trái nghĩa", words: meaning.antonyms ?? [])
                                        }.padding(18).frame(maxWidth: .infinity, alignment: .leading).background(Color(nsColor: .textBackgroundColor)).clipShape(RoundedRectangle(cornerRadius: 14))
                                    }
                                    ForEach(entry.sourceUrls ?? [], id: \.self) { source in
                                        if let url = URL(string: source), url.scheme == "https" { Link("Nguồn: \(url.host ?? "Từ điển") ↗", destination: url).font(.caption) }
                                    }
                                } else if !offlineDefinition.isEmpty {
                                    VStack(alignment: .leading, spacing: 12) {
                                        Label("Định nghĩa trên máy", systemImage: "book.closed").font(.headline)
                                        Text(offlineDefinition).font(.system(size: 14, design: .serif)).lineSpacing(7).textSelection(.enabled)
                                        Text("Apple Dictionary · Bộ từ điển đã cài trên Mac").font(.caption).foregroundStyle(.secondary)
                                    }.padding(18).frame(maxWidth: .infinity, alignment: .leading).background(Color(nsColor: .textBackgroundColor)).clipShape(RoundedRectangle(cornerRadius: 14))
                                }
                            }
                            if loading { HStack(spacing: 10) { ProgressView().controlSize(.small); Text("Đang bổ sung nghĩa và ví dụ…").font(.caption).foregroundStyle(.secondary) }.padding(12) }
                            if !message.isEmpty {
                                HStack(alignment: .top, spacing: 10) {
                                    Image(systemName: "wifi.exclamationmark").foregroundStyle(.orange)
                                    Text(message).font(.caption).foregroundStyle(.secondary)
                                    Spacer(); Button("Thử lại", action: lookup).controlSize(.small)
                                }.padding(12).background(Color.orange.opacity(0.07)).clipShape(RoundedRectangle(cornerRadius: 10))
                            }
                            if !hasResult && !loading && message.isEmpty {
                                VStack(spacing: 18) {
                                    Image(systemName: "character.book.closed.fill").font(.system(size: 46)).foregroundStyle(TransToolsTheme.accent)
                                    Text("Mỗi từ mở ra một câu chuyện.").font(.system(size: 22, weight: .semibold, design: .rounded))
                                    Text("Tra nghĩa, khám phá cách dùng và giữ lại những từ bạn muốn nhớ.").font(.system(size: 13)).foregroundStyle(.secondary).multilineTextAlignment(.center)
                                    HStack { ForEach(["inspire", "curiosity", "serendipity"], id: \.self) { word in Button(word) { query = word; mode = .englishEnglish; lookup() }.buttonStyle(.bordered) } }
                                }.padding(.vertical, 75).frame(maxWidth: .infinity)
                            }
                        }.frame(maxWidth: .infinity, alignment: .leading).padding(.bottom, 20)
                    }
                    Text("Free Dictionary API / Apple Dictionary · Nghĩa dịch: Google Dịch. Từ tương đương phụ thuộc ngữ cảnh.").font(.system(size: 10)).foregroundStyle(.secondary)
                }.padding(22).frame(maxWidth: .infinity)
            }
        }.frame(width: 920, height: 690).background(TransToolsTheme.background).tint(TransToolsTheme.accent)
            .onDisappear { lookupTask?.cancel() }
    }
    private func sidebarLabel(_ text: String) -> some View { Text(text).font(.system(size: 9, weight: .bold)).tracking(1).foregroundStyle(.secondary) }
    @ViewBuilder private func relatedWords(_ title: String, words: [String]) -> some View {
        if !words.isEmpty {
            VStack(alignment: .leading, spacing: 7) {
                Text(title).font(.caption.bold()).foregroundStyle(.secondary)
                ScrollView(.horizontal, showsIndicators: false) { HStack { ForEach(Array(words.prefix(15)), id: \.self) { word in Button(word) { query = word; lookup() }.buttonStyle(.bordered).controlSize(.small) } } }
            }
        }
    }
}
