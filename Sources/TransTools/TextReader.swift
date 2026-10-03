import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct TextReaderView: View {
    @Binding var text: String
    @ObservedObject private var tts = TTSService.shared
    @State private var language: AppLanguage = .vietnamese
    @State private var playbackID = UUID()
    @State private var exportTask: Task<Void, Never>?
    @State private var exporting = false
    @State private var status = ""
    @State private var showVoiceSettings = false
    private var trimmed: String { text.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var canRead: Bool { !trimmed.isEmpty && trimmed.count <= 5000 }
    private var ownsPlayback: Bool { tts.isSpeaking && tts.currentlySpeakingCaptionID == playbackID }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 16) {
                Picker("Ngôn ngữ đọc", selection: $language) {
                    ForEach(AppLanguage.allCases) { value in
                        Text("\(value.flag) \(value.displayName)").tag(value)
                    }
                }.controlSize(.large).frame(maxWidth: 340).disabled(exporting)
                Spacer()
                Button { showVoiceSettings = true } label: {
                    Label("Giọng & Tốc độ", systemImage: "slider.horizontal.3")
                }.buttonStyle(SettingsActionButtonStyle())
            }
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Label("Văn bản cần đọc", systemImage: "text.alignleft").font(.headline)
                    Spacer()
                    Button { stopOwnPlayback(); text = "" } label: { Label("Xóa", systemImage: "xmark") }
                        .buttonStyle(.plain).disabled(trimmed.isEmpty || exporting)
                }
                ZStack(alignment: .topLeading) {
                    if text.isEmpty {
                        Text("Nhập hoặc dán đoạn văn ở đây…\nChọn ngôn ngữ đúng với nội dung để nghe phát âm.")
                            .foregroundStyle(.tertiary).padding(16)
                    }
                    TextEditor(text: $text).font(.system(size: 17)).lineSpacing(7)
                        .scrollContentBackground(.hidden).padding(10)
                        .accessibilityLabel("Đoạn văn cần đọc thành audio")
                        .disabled(exporting)
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
                HStack {
                    Text("\(trimmed.count)/5.000 ký tự")
                        .foregroundStyle(trimmed.count > 5000 ? Color.red : Color.secondary)
                    Spacer()
                    Text("Nội dung dùng chung với ô Dịch nhanh").foregroundStyle(.secondary)
                }.font(.caption)
            }
            .padding(20).background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 18))
            .overlay(RoundedRectangle(cornerRadius: 18).stroke(Color.primary.opacity(0.08)))
            HStack(spacing: 12) {
                Button {
                    status = ""
                    stopOwnPlayback()
                    tts.speak(id: playbackID, text: trimmed, language: language)
                } label: {
                    Label(ownsPlayback ? "Đọc lại" : "Đọc văn bản", systemImage: "play.fill")
                }.buttonStyle(.borderedProminent).tint(TransToolsTheme.accent)
                    .disabled(!canRead || exporting)
                Button { stopOwnPlayback() } label: { Label("Dừng", systemImage: "stop.fill") }
                    .buttonStyle(.bordered).disabled(!ownsPlayback)
                Button { exportAudio() } label: { Label("Lưu audio MP3", systemImage: "arrow.down.to.line") }
                    .buttonStyle(.bordered).disabled(!canRead || exporting)
                if exporting {
                    ProgressView().controlSize(.small)
                    Button("Hủy") { exportTask?.cancel(); exporting = false; status = "Đã hủy tạo audio." }
                        .buttonStyle(.bordered)
                }
                Spacer()
            }.controlSize(.large)
            if !status.isEmpty { Text(status).font(.callout).foregroundStyle(.secondary) }
            if ownsPlayback, let message = tts.voiceStatus {
                Text(message).font(.caption).foregroundStyle(.secondary)
            }
            Text("Phát theo cấu hình giọng đọc hiện có. Lưu audio MP3 dùng Edge Neural và cần kết nối mạng. Nếu giọng mạng không khả dụng, phát sẽ dùng giọng cơ bản.")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
        .sheet(isPresented: $showVoiceSettings) {
            VStack(alignment: .leading, spacing: 18) {
                HStack { Text("Giọng đọc & Phát âm").font(.title2.bold()); Spacer(); Button("Xong") { showVoiceSettings = false } }
                ScrollView { SpeechSettingsView() }
            }.padding(24).frame(width: 640, height: 620)
        }
        .onChange(of: language) { _, _ in stopOwnPlayback() }
        .onDisappear { stopOwnPlayback(); exportTask?.cancel() }
    }

    private func stopOwnPlayback() {
        if tts.currentlySpeakingCaptionID == playbackID { tts.stop() }
    }

    private func exportAudio() {
        guard canRead else { return }
        let snapshot = trimmed, locale = language.speechLocale
        let rate = tts.speechRate / 0.44
        stopOwnPlayback()
        exportTask?.cancel(); exporting = true; status = "Đang tạo audio…"
        exportTask = Task { @MainActor in
            do {
                let data = try await EdgeTTSService.shared.synthesize(text: snapshot, locale: locale, rateModifier: rate)
                try Task.checkCancellation()
                let panel = NSSavePanel()
                panel.allowedContentTypes = [.mp3]
                panel.nameFieldStringValue = "TransTools-audio.mp3"
                panel.canCreateDirectories = true
                if panel.runModal() == .OK, let url = panel.url {
                    try data.write(to: url, options: .atomic)
                    status = "Đã lưu audio: \(url.lastPathComponent)"
                } else { status = "Chưa lưu audio." }
                exporting = false
            } catch {
                guard !Task.isCancelled else { return }
                exporting = false; status = "Chưa tạo được audio: \(error.localizedDescription)"
            }
        }
    }
}
