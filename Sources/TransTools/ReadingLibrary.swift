import SwiftUI
import AppKit

struct ReadingLibraryItem: Identifiable {
    let id: String
    let title: String
    let language: AppLanguage
    let source: String
    let page: URL
    let textURL: URL
    let wiki: Bool
    static let catalog: [Self] = [
        .init(id: "tam-cam", title: "Tấm Cám", language: .vietnamese, source: "Wikisource", page: URL(string: "https://vi.wikisource.org/wiki/T%E1%BA%A5m_C%C3%A1m")!, textURL: URL(string: "https://vi.wikisource.org/w/api.php?action=parse&page=T%E1%BA%A5m_C%C3%A1m&prop=text&format=json")!, wiki: true),
        .init(id: "grimm", title: "Grimms’ Fairy Tales", language: .english, source: "Project Gutenberg", page: URL(string: "https://www.gutenberg.org/ebooks/2591")!, textURL: URL(string: "https://www.gutenberg.org/ebooks/2591.txt.utf-8")!, wiki: false),
        .init(id: "andersen", title: "Andersen’s Fairy Tales", language: .english, source: "Project Gutenberg", page: URL(string: "https://www.gutenberg.org/ebooks/1597")!, textURL: URL(string: "https://www.gutenberg.org/ebooks/1597.txt.utf-8")!, wiki: false),
        .init(id: "aesop", title: "Aesop’s Fables", language: .english, source: "Project Gutenberg", page: URL(string: "https://www.gutenberg.org/ebooks/11339")!, textURL: URL(string: "https://www.gutenberg.org/ebooks/11339.txt.utf-8")!, wiki: false)
    ]
}

@MainActor struct ReadingLibraryView: View {
    let select: (ReadingLibraryItem, String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var filter = "all"
    @State private var query = ""
    @State private var selected: ReadingLibraryItem?
    @State private var parts: [String] = []
    @State private var part = 0
    @State private var loading = false
    @State private var error = ""
    @State private var download: Task<Void, Never>?
    @State private var onlineItems: [ReadingLibraryItem]? = nil
    @State private var searching = false
    @State private var searchTask: Task<Void, Never>?
    private var items: [ReadingLibraryItem] {
        (onlineItems ?? ReadingLibraryItem.catalog).filter { (filter == "all" || $0.language.rawValue == filter) && (onlineItems != nil || query.isEmpty || $0.title.localizedCaseInsensitiveContains(query)) }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack { Text("Thư viện truyện").font(.title2.bold()); Spacer(); Button("Đóng") { dismiss() }.buttonStyle(TransToolsActionButtonStyle()) }
            HStack {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass").foregroundStyle(TransToolsTheme.accent)
                    TextField("Tìm tên truyện…", text: $query).textFieldStyle(.plain)
                        .onSubmit { searchOnline() }
                }
                .padding(.horizontal, 12).frame(height: 40)
                .background(.white, in: RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(TransToolsTheme.accent.opacity(0.35)))
                Menu {
                    Button("Tất cả") { filter = "all" }
                    Button("Tiếng Việt") { filter = "vi" }
                    Button("Tiếng Anh") { filter = "en" }
                } label: {
                    HStack { Text(filter == "vi" ? "Tiếng Việt" : filter == "en" ? "Tiếng Anh" : "Tất cả ngôn ngữ"); Spacer(); Image(systemName: "chevron.down") }
                }.buttonStyle(TransToolsActionButtonStyle(height: 40)).frame(width: 170)
            }
            HStack {
                Button("Tìm trực tuyến") { searchOnline() }
                    .buttonStyle(TransToolsActionButtonStyle(height: 40)).disabled(searching || query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                if searching { ProgressView().controlSize(.small) }
                if onlineItems != nil {
                    Text("Kết quả từ Wikisource").font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Button("Truyện gợi ý") { searchTask?.cancel(); searching = false; onlineItems = nil; query = ""; error = "" }
                        .buttonStyle(TransToolsActionButtonStyle(height: 40))
                }
            }
            ScrollView {
                VStack(spacing: 12) {
                    ForEach(items) { item in
                        HStack {
                            VStack(alignment: .leading, spacing: 6) { Text(item.title).font(.headline); Text("\(item.language.displayName) · \(item.source)").font(.caption).foregroundStyle(.secondary) }
                            Spacer()
                            Link("Xem nguồn", destination: item.page)
                            Button("Chọn truyện") { load(item) }.buttonStyle(SettingsActionButtonStyle()).disabled(loading)
                        }.padding(16).background(.white, in: RoundedRectangle(cornerRadius: 12)).overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(TransToolsTheme.accent.opacity(0.3)))
                    }
                    if items.isEmpty { Text("Không tìm thấy nội dung phù hợp.").foregroundStyle(.secondary).padding(20) }
                }
            }
            if loading { ProgressView("Đang tải nội dung…") }
            if !error.isEmpty { Text(error).foregroundStyle(.red).fixedSize(horizontal: false, vertical: true) }
            if let selected, !parts.isEmpty {
                Divider()
                HStack { Text(selected.title).font(.headline); Spacer(); Picker("Phần đọc", selection: $part) { ForEach(parts.indices, id: \.self) { Text("Phần \($0 + 1) / \(parts.count)").tag($0) } }.frame(width: 240) }
                ScrollView { Text(parts[part]).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading).padding(12) }.frame(height: 150).background(.white, in: RoundedRectangle(cornerRadius: 10))
                HStack { Text("Nội dung được thay vào ô đọc khi bạn bấm Dùng phần này.").font(.caption).foregroundStyle(.secondary); Spacer(); Button("Dùng phần này") { select(selected, parts[part]); dismiss() }.buttonStyle(TransToolsActionButtonStyle(prominent: true)) }
            }
            Text("Tải truyện cần Internet. Tên và link nguồn luôn được giữ để bạn xem bản gốc.").font(.caption).foregroundStyle(.secondary)
        }.padding(24).frame(width: 760, height: 650).background(Color(nsColor: .windowBackgroundColor))
        .onDisappear { download?.cancel(); searchTask?.cancel() }
    }
    private func searchOnline() {
        let term = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !term.isEmpty else { return }
        searchTask?.cancel(); searching = true; error = ""
        let languages: [AppLanguage] = filter == "vi" ? [.vietnamese] : filter == "en" ? [.english] : [.vietnamese, .english]
        searchTask = Task {
            do {
                var found: [ReadingLibraryItem] = []
                for language in languages {
                    let host = language == .vietnamese ? "vi.wikisource.org" : "en.wikisource.org"
                    var components = URLComponents(string: "https://\(host)/w/api.php")!
                    components.queryItems = [URLQueryItem(name: "action", value: "query"), URLQueryItem(name: "list", value: "search"), URLQueryItem(name: "srsearch", value: term), URLQueryItem(name: "srnamespace", value: "0"), URLQueryItem(name: "srlimit", value: "20"), URLQueryItem(name: "format", value: "json")]
                    var request = URLRequest(url: components.url!); request.timeoutInterval = 20
                    let (data, response) = try await URLSession.shared.data(for: request)
                    try Task.checkCancellation()
                    guard (response as? HTTPURLResponse)?.statusCode == 200, data.count < 2_000_000,
                          let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                          let result = json["query"] as? [String: Any], let rows = result["search"] as? [[String: Any]] else { throw URLError(.badServerResponse) }
                    for row in rows {
                        guard let title = row["title"] as? String, let id = row["pageid"] as? Int else { continue }
                        var page = URLComponents(string: "https://\(host)/w/index.php")!
                        page.queryItems = [URLQueryItem(name: "curid", value: String(id))]
                        var text = URLComponents(string: "https://\(host)/w/api.php")!
                        text.queryItems = [URLQueryItem(name: "action", value: "parse"), URLQueryItem(name: "pageid", value: String(id)), URLQueryItem(name: "prop", value: "text"), URLQueryItem(name: "format", value: "json")]
                        found.append(.init(id: "\(host)-\(id)", title: title, language: language, source: "Wikisource", page: page.url!, textURL: text.url!, wiki: true))
                    }
                }
                try Task.checkCancellation()
                onlineItems = found; searching = false
            } catch { if !Task.isCancelled { searching = false; self.error = "Chưa tìm trực tuyến được. Bạn có thể thử lại hoặc chọn truyện gợi ý." } }
        }
    }
    private func load(_ item: ReadingLibraryItem) {
        download?.cancel(); loading = true; error = ""; parts = []; selected = nil; part = 0
        download = Task {
            defer { loading = false }
            do {
                var request = URLRequest(url: item.textURL); request.timeoutInterval = 25
                let (data, response) = try await URLSession.shared.data(for: request)
                try Task.checkCancellation()
                guard let response = response as? HTTPURLResponse, response.statusCode == 200, data.count <= 4_000_000 else { throw URLError(.badServerResponse) }
                var content: String
                if item.wiki {
                    let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
                    guard let parse = json?["parse"] as? [String: Any], let body = parse["text"] as? [String: String], let html = body["*"] else { throw URLError(.cannotParseResponse) }
                    let expression = try NSRegularExpression(pattern: "<p(?:\\s[^>]*)?>[\\s\\S]*?</p>", options: .caseInsensitive)
                    let paragraphs = expression.matches(in: html, range: NSRange(html.startIndex..., in: html)).compactMap { Range($0.range, in: html).map { String(html[$0]) } }.joined(separator: "\n")
                    guard let encoded = paragraphs.data(using: .utf8) else { throw URLError(.cannotDecodeContentData) }
                    content = try NSAttributedString(data: encoded, options: [.documentType: NSAttributedString.DocumentType.html, .characterEncoding: String.Encoding.utf8.rawValue], documentAttributes: nil).string
                } else {
                    guard let decoded = String(data: data, encoding: .utf8) else { throw URLError(.cannotDecodeContentData) }
                    content = decoded
                    // Remove distribution boilerplate from the reading copy; source link retains the original edition.
                    if let marker = content.range(of: "*** START OF"), let end = content[marker.lowerBound...].range(of: "***", range: content.index(marker.lowerBound, offsetBy: 3)..<content.endIndex) { content = String(content[end.upperBound...]) }
                    if let end = content.range(of: "*** END OF") { content = String(content[..<end.lowerBound]) }
                }
                content = content.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !content.isEmpty else { throw URLError(.cannotParseResponse) }
                var remaining = content[...]; var chunks: [String] = []
                while !remaining.isEmpty {
                    let limit = remaining.index(remaining.startIndex, offsetBy: min(4500, remaining.count))
                    var boundary = limit
                    if limit != remaining.endIndex, let pause = remaining[..<limit].lastIndex(where: { $0 == "\n" }), remaining.distance(from: remaining.startIndex, to: pause) > 2000 { boundary = remaining.index(after: pause) }
                    chunks.append(String(remaining[..<boundary])); remaining = remaining[boundary...]
                }
                try Task.checkCancellation(); selected = item; parts = chunks
            } catch is CancellationError {} catch { if !Task.isCancelled { self.error = "Chưa tải được truyện. Bạn có thể mở link nguồn hoặc thử lại. " + error.localizedDescription } }
        }
    }
}
