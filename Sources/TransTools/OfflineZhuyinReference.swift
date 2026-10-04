import SwiftUI

private struct ZhuyinRecording: Decodable, Identifiable {
    let id: String
    let symbol: String
    let file: String
}

private struct ZhuyinCatalog: Decodable {
    let entries: [ZhuyinRecording]
    static let bundled: [ZhuyinRecording] = {
        guard let url = Bundle.main.resourceURL?.appendingPathComponent("Pronunciation/Zhuyin/manifest.json"),
              let data = try? Data(contentsOf: url),
              let catalog = try? JSONDecoder().decode(Self.self, from: data),
              catalog.entries.count == 37,
              Set(catalog.entries.map(\.id)).count == 37,
              Set(catalog.entries.map(\.symbol)).count == 37,
              catalog.entries.allSatisfy({ !$0.file.contains("/") && !$0.file.contains("..") }) else { return [] }
        return catalog.entries
    }()
}

struct OfflineZhuyinReferenceView: View {
    @StateObject private var audio = OfflineIPAPlayer()
    @State private var expanded = false
    private let source = URL(string: "https://language.moe.gov.tw/001/Upload/files/SITE_CONTENT/M0001/deploy/index.html")!

    var body: some View {
        DisclosureGroup(isExpanded: $expanded) {
            VStack(alignment: .leading, spacing: 12) {
                Text("Bản ghi nguồn chính thức · phát offline").font(.subheadline.bold())
                Text("Chú âm dùng cho Mandarin Đài Loan. Đây là mẫu đọc ký hiệu Chú âm, khác với chữ Hán và pinyin; không dùng các file này thay cho âm của 12 chữ phía trên.")
                    .font(.caption).foregroundStyle(.secondary)
                if ZhuyinCatalog.bundled.isEmpty {
                    Text("Không tải được bộ bản ghi Chú âm. Hãy mở nguồn học bên dưới.").foregroundStyle(.red)
                } else {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 54))], spacing: 8) {
                        ForEach(ZhuyinCatalog.bundled) { entry in
                            Button { audio.playResource("Zhuyin/\(entry.file)", id: entry.id) } label: {
                                Text(entry.symbol).font(.system(size: 22)).frame(maxWidth: .infinity).padding(.vertical, 9)
                            }.buttonStyle(TransToolsActionButtonStyle())
                                .tint(audio.active == entry.id ? TransToolsTheme.accent : .secondary)
                                .accessibilityLabel("Nghe Chú âm \(entry.symbol)")
                        }
                    }
                }
                HStack {
                    Button("Dừng") { audio.stop() }.disabled(audio.active == nil)
                    Spacer()
                    Link("Bộ Giáo dục Đài Loan · 2017 · CC BY 4.0 ↗", destination: source)
                }.font(.caption)
                Text("Giữ nguyên audio và tốc độ gốc. Đã đối chiếu ký hiệu với trang nguồn; chưa có lượt nghe duyệt độc lập bởi giáo viên.")
                    .font(.caption).foregroundStyle(.secondary)
                if let error = audio.error { Text(error).font(.caption).foregroundStyle(.red) }
            }.padding(.top, 12)
        } label: { Label("Chú âm offline · 37 bản ghi · Đài Loan", systemImage: "waveform") }
        .padding(14).background(Color.secondary.opacity(0.05), in: RoundedRectangle(cornerRadius: 12))
        .onChange(of: expanded) { _, value in if !value { audio.stop() } }
        .onDisappear { audio.stop() }
    }
}
