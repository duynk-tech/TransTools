import SwiftUI

struct PersonalVoiceRecorderView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var manager = PersonalVoiceManager.shared
    @State private var name = ""
    @State private var leadIn: Int?
    @State private var startTask: Task<Void, Never>?
    @State private var guide = true
    private var locked: Bool { manager.processing || manager.checkingSpeech || manager.generatingScript }
    private var preparing: Bool { leadIn != nil }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Label("Thu giọng của tôi", systemImage: "mic.fill")
                    .font(.title2.bold()).foregroundStyle(TransToolsTheme.accent)
                Spacer()
                Button("Xong") { dismiss() }.buttonStyle(TransToolsActionButtonStyle()).disabled(locked)
            }
            Text("Đọc tự nhiên trong 3–8 giây, ở nơi yên tĩnh. Bản thu chỉ lưu trên thiết bị.")
                .font(.subheadline).foregroundStyle(.secondary)
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    HStack {
                        Text("Đoạn đọc mẫu").font(.headline)
                        Spacer()
                        Button { manager.generateScript() } label: {
                            Label(manager.generatingScript ? "Đang tạo…" : "AI tạo đoạn mới", systemImage: "sparkles")
                        }.buttonStyle(TransToolsActionButtonStyle())
                            .disabled(locked || manager.recording || preparing)
                    }
                    if manager.recording {
                        TimelineView(.periodic(from: manager.recordedAt ?? .now, by: 0.15)) { context in
                            let elapsed = context.date.timeIntervalSince(manager.recordedAt ?? context.date)
                            readingBoard(elapsed: elapsed)
                            ProgressView(value: min(8, max(0, elapsed)), total: 8).tint(TransToolsTheme.accent)
                            Text("Đang thu · \(min(8, Int(max(0, elapsed)))) / 8 giây").font(.caption.monospacedDigit())
                        }
                    } else {
                        readingBoard(elapsed: nil)
                    }
                    Toggle("Tô chữ dẫn nhịp đọc", isOn: $guide).tint(TransToolsTheme.accent)
                        .disabled(manager.recording || preparing)
                    Text("Chữ sáng theo nhịp gợi ý, không theo dõi chính xác giọng nói. Đọc liền mạch, không cần chạy theo từng chữ.")
                        .font(.caption).foregroundStyle(.secondary)
                    HStack(spacing: 12) {
                        Button {
                            if manager.recording { manager.stop() }
                            else if preparing { startTask?.cancel(); leadIn = nil }
                            else { beginRecording() }
                        } label: {
                            Label(manager.recording ? "Dừng thu" : preparing ? "Hủy đếm ngược" : manager.ready ? "Thu lại" : "Bắt đầu thu", systemImage: manager.recording ? "stop.fill" : "mic.fill")
                        }.buttonStyle(TransToolsActionButtonStyle(prominent: true)).disabled(locked)
                        if let leadIn { Text("Bắt đầu sau \(leadIn)…").font(.headline.monospacedDigit()).foregroundStyle(TransToolsTheme.accent) }
                        Spacer()
                        Button("Nghe bản thu") { manager.preview() }.buttonStyle(TransToolsActionButtonStyle())
                            .disabled(!manager.ready || manager.recording || preparing || locked)
                    }
                    if manager.ready && !manager.recording {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Text("Tên giọng").frame(width: 100, alignment: .leading)
                                TextField("Giọng của tôi", text: $name).textFieldStyle(.roundedBorder)
                            }
                            HStack {
                                Button("Kiểm tra lời đọc") { Task { await manager.checkWords() } }
                                    .buttonStyle(TransToolsActionButtonStyle()).disabled(locked || preparing)
                                Spacer()
                                Button("Lưu bản thu") { Task { await manager.create(name: name) } }
                                    .buttonStyle(TransToolsActionButtonStyle(prominent: true))
                                    .disabled(locked || preparing)
                            }
                        }.padding(14).transToolsPanel()
                    }
                    if locked { ProgressView().controlSize(.small) }
                    Text(manager.status).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    if !manager.transcript.isEmpty {
                        Text("Lời đọc nhận diện: " + manager.transcript).font(.callout).textSelection(.enabled)
                    }
                }.padding(2)
            }
            Divider()
            Text("AI chỉ tạo đoạn văn. Lưu bản thu gốc, sau đó chọn mô hình tương thích để tạo và đọc thử giọng cá nhân.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .padding(24).frame(width: 720, height: 660)
        .background(Color.white)
        .onAppear { if !manager.ready { manager.generateScript() } }
        .onDisappear { startTask?.cancel(); manager.cancelRecording() }
    }
    private func beginRecording() {
        startTask?.cancel()
        startTask = Task { @MainActor in
            for value in stride(from: 3, through: 1, by: -1) {
                leadIn = value
                do { try await Task.sleep(for: .seconds(1)) } catch { return }
            }
            leadIn = nil
            guard !Task.isCancelled else { return }
            await manager.start()
        }
    }
    private func readingBoard(elapsed: Double?) -> some View {
        let words = manager.prompt.split(whereSeparator: { $0.isWhitespace }).map(String.init)
        let index = elapsed.map { min(words.count - 1, max(0, Int(($0 / 7.5) * Double(words.count)))) }
        let text = words.enumerated().reduce(Text("")) { result, item in
            let active = guide && index == item.offset
            return result + Text(item.element + (item.offset == words.count - 1 ? "" : " "))
                .foregroundColor(active ? TransToolsTheme.accent : .primary)
                .fontWeight(.medium)
                .underline(active, color: TransToolsTheme.accent)
        }
        return text.font(.system(size: 27)).lineSpacing(10)
            .frame(maxWidth: .infinity, minHeight: 130, alignment: .leading)
            .padding(20).background(TransToolsTheme.mint.opacity(0.65), in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(TransToolsTheme.accent.opacity(0.45), lineWidth: 1.5))
    }
}
