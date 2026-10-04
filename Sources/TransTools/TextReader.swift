import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct TextReaderView: View {
    @Binding var text: String
    @ObservedObject var model: MeetingModel
    @State private var preparing = false
    @State private var readingTask: Task<Void, Never>?
    @AppStorage("TextReaderPrepareNumericAI") private var prepareNumericAI = true
    @ObservedObject private var tts = TTSService.shared
    @ObservedObject private var externalModels = ExternalTTSModelManager.shared
    @ObservedObject private var local = LocalTTSModelManager.shared
    @State private var language: AppLanguage = .vietnamese
    @State private var playbackID = UUID()
    @State private var exportTask: Task<Void, Never>?
    @State private var exporting = false
    @State private var status = ""
    @State private var showVoiceSettings = false
    private var trimmed: String { text.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var canRead: Bool { !trimmed.isEmpty && trimmed.count <= 5000 }
    private var ownsPlayback: Bool { tts.isSpeaking && tts.currentlySpeakingCaptionID == playbackID }

    private var selectedEngine: LanguageVoiceEngine {
        let _ = externalModels.revision
        return LanguageVoicePreferences.resolved(for: language.speechLocale, localDefault: local.isNaturalVoiceEnabled, edgeDefault: tts.useEdgeNaturalVoice)
    }
    private var exportSupported: Bool {
        if let model = selectedEngine.externalModel { return model.isInstalled && model.languages.contains(LanguageVoicePreferences.code(language.speechLocale)) && externalModels.installing == nil }
        if selectedEngine == .local { return local.isInstalled && LocalNaturalTTSEngine.shared.supportedLanguages.contains(LanguageVoicePreferences.code(language.speechLocale)) && externalModels.installing == nil }
        return selectedEngine == .edge && EdgeTTSService.defaultVoice(for: language.speechLocale) != nil
    }
    private var exportInfo: String {
        if selectedEngine.isLocal { return exportSupported ? "Lưu WAV bằng đúng mô hình Local đang chọn; tạo từng đoạn để tiết kiệm bộ nhớ." : "Cần cài mô hình hỗ trợ ngôn ngữ này trước khi lưu audio." }
        if selectedEngine == .system { return "Giọng cơ bản chưa hỗ trợ lưu audio trong app." }
        return "Lưu MP3 bằng giọng trực tuyến đang chọn. Cần Internet để tạo audio chưa có trong cache."
    }

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
                    readText()
                } label: {
                    Label(ownsPlayback ? "Đọc lại" : "Đọc văn bản", systemImage: "play.fill")
                }.buttonStyle(TransToolsActionButtonStyle(prominent: true)).tint(TransToolsTheme.accent)
                    .disabled(!canRead || exporting || preparing)
                Button { stopOwnPlayback() } label: { Label("Dừng", systemImage: "stop.fill") }
                    .buttonStyle(TransToolsActionButtonStyle()).disabled(!ownsPlayback && !preparing)
                Button { exportAudio() } label: { Label(selectedEngine.isLocal ? "Lưu audio WAV" : "Lưu audio MP3", systemImage: "arrow.down.to.line") }
                    .buttonStyle(TransToolsActionButtonStyle()).disabled(!canRead || exporting || preparing || !exportSupported)
                    .help(exportInfo)
                if exporting {
                    ProgressView().controlSize(.small)
                    Button("Hủy") { exportTask?.cancel(); exporting = false; status = "Đã hủy tạo audio." }
                        .buttonStyle(TransToolsActionButtonStyle())
                }
                Spacer()
            }.controlSize(.large)
            if model.configuredAI != nil {
                Toggle("Chuẩn hóa cách đọc số bằng AI", isOn: $prepareNumericAI)
                    .toggleStyle(TrailingSettingsToggleStyle()).disabled(preparing || exporting)
                Text("Chỉ xử lý số La Mã, ngày tháng và tỷ lệ cho giọng đọc. Văn bản gốc giữ nguyên; đoạn không rõ nghĩa được giữ nguyên. Nội dung được gửi tới AI đã cấu hình.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if preparing { ProgressView("Đang chuẩn hóa cách đọc…").controlSize(.small) }
            if !status.isEmpty { Text(status).font(.callout).foregroundStyle(.secondary) }
            if ownsPlayback, let message = tts.voiceStatus {
                Text(message).font(.caption).foregroundStyle(.secondary)
            }
            Text(exportInfo)
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
        .sheet(isPresented: $showVoiceSettings) {
            VStack(alignment: .leading, spacing: 18) {
                HStack { Text("Giọng đọc & Phát âm").font(.title2.bold()); Spacer(); Button("Xong") { showVoiceSettings = false }.buttonStyle(TransToolsActionButtonStyle()) }
                ScrollView { SpeechSettingsView(language: language) }
            }.padding(24).frame(width: 640, height: 620)
        }
        .onChange(of: language) { _, _ in stopOwnPlayback() }
        .onDisappear { stopOwnPlayback(); exportTask?.cancel() }
    }

    private func stopOwnPlayback() {
        readingTask?.cancel(); readingTask = nil; preparing = false
        if tts.currentlySpeakingCaptionID == playbackID { tts.stop() }
    }

    @MainActor private func preparedText(_ snapshot: String, language: AppLanguage) async -> String {
        guard prepareNumericAI, let ai = model.configuredAI else { return snapshot }
        do { return try await SpeechReadingPreparation.prepare(snapshot, language: language, ai: ai) }
        catch {
            if !Task.isCancelled { status = "AI chưa chuẩn hóa được · dùng cách đọc văn bản gốc." }
            return snapshot
        }
    }
    private func readText() {
        guard canRead else { return }
        stopOwnPlayback(); status = ""
        let snapshot = trimmed, selectedLanguage = language
        preparing = true
        readingTask = Task { @MainActor in
            let speech = await preparedText(snapshot, language: selectedLanguage)
            guard !Task.isCancelled else { return }
            preparing = false
            guard trimmed == snapshot, language == selectedLanguage else { status = "Nội dung đã thay đổi · nhấn Đọc lại."; return }
            tts.speak(id: playbackID, text: speech, language: selectedLanguage)
        }
    }

    private func exportAudio() {
        guard canRead, exportSupported else { status = exportInfo; return }
        let snapshot = trimmed, selectedLanguage = language, locale = language.speechLocale
        let rate = tts.speechRate / 0.44
        let engine = selectedEngine
        let options = TTSOptions(rate: tts.speechRate, volume: tts.speechVolume)
        stopOwnPlayback(); tts.stop(); LanguagePronunciationService.shared.stop()
        exportTask?.cancel(); exporting = true; status = "Đang tạo audio…"
        exportTask = Task { @MainActor in
            do {
                let speech = await preparedText(snapshot, language: selectedLanguage)
                try Task.checkCancellation()
                let temporary: URL?
                let data: Data?
                if engine.isLocal {
                    temporary = try await TTSEngineRouter.shared.exportWAV(text: speech, language: locale, engine: engine, options: options)
                    data = nil
                } else {
                    temporary = nil
                    data = try await EdgeTTSService.shared.synthesize(text: speech, locale: locale, rateModifier: rate)
                }
                defer { if let temporary { try? FileManager.default.removeItem(at: temporary) } }
                try Task.checkCancellation()
                guard exportSupported, selectedEngine == engine else { exporting = false; status = "Giọng đọc đã thay đổi. Chưa lưu audio."; return }
                let panel = NSSavePanel()
                panel.allowedContentTypes = engine.isLocal ? [.wav] : [.mp3]
                panel.nameFieldStringValue = engine.isLocal ? "Trans Tools-audio.wav" : "Trans Tools-audio.mp3"
                panel.canCreateDirectories = true
                if panel.runModal() == .OK, let url = panel.url {
                    if let temporary {
                        let staged = url.deletingLastPathComponent().appendingPathComponent("." + UUID().uuidString + ".wav")
                        try FileManager.default.copyItem(at: temporary, to: staged)
                        defer { try? FileManager.default.removeItem(at: staged) }
                        if FileManager.default.fileExists(atPath: url.path) { _ = try FileManager.default.replaceItemAt(url, withItemAt: staged) }
                        else { try FileManager.default.moveItem(at: staged, to: url) }
                    }
                    else if let data { try data.write(to: url, options: .atomic) }
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
