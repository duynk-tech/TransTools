import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct TextReaderView: View {
    @Binding var text: String
    @ObservedObject var model: MeetingModel
    @AppStorage("TextReaderSentencePause") private var sentencePause = 0.1
    @AppStorage("TextReaderParagraphPause") private var paragraphPause = 0.8
    @AppStorage("TextReaderShortPauseMigration") private var shortPauseMigrated = false
    @State private var preparing = false
    @State private var readingActive = false
    @State private var readingGeneration = UUID()
    @State private var readingTask: Task<Void, Never>?
    @AppStorage("TextReaderPrepareNumericAI") private var prepareNumericAI = true
    @ObservedObject private var tts = TTSService.shared
    @ObservedObject private var externalModels = ExternalTTSModelManager.shared
    @ObservedObject private var local = LocalTTSModelManager.shared
    @Binding var language: AppLanguage
    let playbackID: UUID
    @State private var exportTask: Task<Void, Never>?
    @State private var exporting = false
    @ObservedObject private var mp3Installer = MP3EncoderInstaller.shared
    @State private var status = ""
    @State private var showVoiceSettings = false
    @State private var showReadingLibrary = false
    @State private var readingSource: ReadingLibraryItem?
    private var trimmed: String { text.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var canRead: Bool { !trimmed.isEmpty && trimmed.count <= 5000 }
    private var ownsPlayback: Bool { readingActive || (tts.isSpeaking && tts.currentlySpeakingCaptionID == playbackID) }

    private var selectedEngine: LanguageVoiceEngine {
        let _ = externalModels.revision
        return ModelManager.shared.routedEngine(for: language.speechLocale, localDefault: local.isNaturalVoiceEnabled, edgeDefault: tts.useEdgeNaturalVoice)
    }
    private var exportSupported: Bool {
        if let model = selectedEngine.externalModel { return model.isInstalled && model.languages.contains(LanguageVoicePreferences.code(language.speechLocale)) && externalModels.installing == nil }
        if selectedEngine == .local { return local.isInstalled && LocalNaturalTTSEngine.shared.supportedLanguages.contains(LanguageVoicePreferences.code(language.speechLocale)) && externalModels.installing == nil }
        return selectedEngine == .edge && EdgeTTSService.defaultVoice(for: language.speechLocale) != nil
    }
    private var exportInfo: String {
        if selectedEngine.isLocal {
            guard exportSupported else { return "Cần cài mô hình hỗ trợ ngôn ngữ này trước khi lưu audio." }
            return MP3AudioExporter.encoder != nil
                ? "Lưu MP3 hoặc WAV bằng giọng Offline đang chọn. Chuyển MP3 ngay trên máy."
                : "Lưu WAV bằng giọng Offline đang chọn. Lưu MP3 cần bộ mã hóa FFmpeg trên máy."
        }
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
                Button { showReadingLibrary = true } label: { Label("Thư viện truyện", systemImage: "books.vertical") }.buttonStyle(SettingsActionButtonStyle()).disabled(exporting || preparing)
                Button { showVoiceSettings = true } label: {
                    Label("Tùy chỉnh đọc", systemImage: "slider.horizontal.3")
                }.buttonStyle(SettingsActionButtonStyle())
            }
            if let readingSource {
                HStack { Text(readingSource.title).font(.subheadline.bold()); Spacer(); Link("Nguồn: \(readingSource.source)", destination: readingSource.page) }.font(.caption)
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
                }.frame(maxWidth: .infinity, minHeight: 220, maxHeight: .infinity).layoutPriority(1)
                HStack {
                    Text("\(trimmed.count)/5.000 ký tự")
                        .foregroundStyle(trimmed.count > 5000 ? Color.red : Color.secondary)
                    Spacer()
                    Text("Chọn truyện hoặc nhập nội dung của bạn").foregroundStyle(.secondary)
                }.font(.caption)
            }
            .padding(20).background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 18))
            .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(Color.primary.opacity(0.08)))
            HStack(spacing: 12) {
                Button {
                    readText()
                } label: {
                    Label(ownsPlayback ? "Đọc lại" : "Đọc văn bản", systemImage: "play.fill")
                }.buttonStyle(TransToolsActionButtonStyle(prominent: true)).tint(TransToolsTheme.accent)
                    .disabled(!canRead || exporting || preparing)
                Button { stopOwnPlayback() } label: { Label("Dừng", systemImage: "stop.fill") }
                    .buttonStyle(TransToolsActionButtonStyle()).disabled(!ownsPlayback && !preparing)
                Menu {
                    Button("Lưu MP3") { exportAudio(mp3: true) }
                        .disabled(selectedEngine.isLocal && MP3AudioExporter.encoder == nil)
                    if selectedEngine.isLocal { Button("Lưu WAV") { exportAudio(mp3: false) } }
                    if selectedEngine.isLocal && !mp3Installer.available {
                        Divider()
                        Button("Cài bộ mã hóa MP3…") { mp3Installer.showSetup = true }
                    }
                } label: { Label("Lưu audio", systemImage: "arrow.down.to.line") }
                    .buttonStyle(TransToolsActionButtonStyle()).disabled(!canRead || exporting || preparing || !exportSupported)
                    .help(exportInfo)
                if exporting {
                    ProgressView().controlSize(.small)
                    Button("Hủy") { exportTask?.cancel(); exporting = false; status = "Đã hủy tạo audio." }
                        .buttonStyle(TransToolsActionButtonStyle())
                }
                Spacer()
            }.controlSize(.large)
            if selectedEngine.isLocal && !mp3Installer.available {
                HStack {
                    Label(mp3Installer.installing ? "Đang cài bộ mã hóa MP3…" : "Lưu MP3 cần cài thêm bộ mã hóa.", systemImage: "waveform")
                        .font(.caption).foregroundStyle(.secondary)
                    Button(mp3Installer.installing ? "Xem trạng thái" : "Cài để lưu MP3") { mp3Installer.showSetup = true }
                        .buttonStyle(TransToolsActionButtonStyle())
                }
            }
            if preparing { ProgressView("Đang chuẩn hóa cách đọc…").controlSize(.small) }
            if !status.isEmpty { Text(status).font(.callout).foregroundStyle(.secondary) }
            if ownsPlayback, let message = tts.voiceStatus {
                Text(message).font(.caption).foregroundStyle(.secondary)
            }
        }
        .sheet(isPresented: $mp3Installer.showSetup) {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Label("Cài bộ mã hóa MP3", systemImage: "waveform").font(.title2.bold())
                    Spacer()
                    Button("Đóng") { mp3Installer.showSetup = false }.buttonStyle(TransToolsActionButtonStyle())
                }
                Text("FFmpeg giúp chuyển giọng Offline thành file MP3 ngay trên máy. Homebrew sẽ tải FFmpeg và các thành phần cần thiết; không gửi văn bản hoặc audio của bạn đi.")
                    .fixedSize(horizontal: false, vertical: true)
                if MP3EncoderInstaller.homebrew == nil {
                    Text("Máy chưa có Homebrew. Cài Homebrew từ trang chính thức trước, rồi quay lại đây.").foregroundStyle(.secondary)
                    Link("Mở trang cài Homebrew", destination: URL(string: "https://brew.sh")!)
                }
                if !mp3Installer.message.isEmpty { Text(mp3Installer.message).font(.callout).foregroundStyle(.secondary) }
                HStack {
                    if mp3Installer.installing { ProgressView().controlSize(.small) }
                    if MP3EncoderInstaller.homebrew != nil && !mp3Installer.available {
                        Button("Cài FFmpeg qua Homebrew") { mp3Installer.install() }
                            .buttonStyle(TransToolsActionButtonStyle(prominent: true)).disabled(mp3Installer.installing)
                    }
                    Button("Kiểm tra lại") { mp3Installer.refresh() }
                        .buttonStyle(TransToolsActionButtonStyle()).disabled(mp3Installer.installing)
                    if mp3Installer.available { Label("Đã sẵn sàng", systemImage: "checkmark.circle.fill").foregroundStyle(TransToolsTheme.accent) }
                }
            }.padding(24).frame(width: 600)
        }
        .sheet(isPresented: $showReadingLibrary) {
            ReadingLibraryView { item, content in stopOwnPlayback(); language = item.language; text = content; readingSource = item; status = "Đã chọn \(item.title)." }
        }
        .sheet(isPresented: $showVoiceSettings) {
            VStack(alignment: .leading, spacing: 18) {
                HStack { Text("Tùy chỉnh đọc").font(.title2.bold()); Spacer(); Button("Đóng") { showVoiceSettings = false }.buttonStyle(TransToolsActionButtonStyle()) }
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
            VStack(spacing: 10) {
                HStack { Text("Tốc độ đọc").frame(width: 150, alignment: .leading); Slider(value: $tts.speechRate, in: 0.25...0.65); Text(String(format: "%.1f×", tts.speechRate / 0.44)).monospacedDigit().frame(width: 52) }
                HStack { Text("Nghỉ giữa câu").frame(width: 150, alignment: .leading); Slider(value: $sentencePause, in: 0...2, step: 0.1); Text(String(format: "%.1f s", sentencePause)).monospacedDigit().frame(width: 52) }
                HStack { Text("Nghỉ giữa đoạn").frame(width: 150, alignment: .leading); Slider(value: $paragraphPause, in: 0...4, step: 0.1); Text(String(format: "%.1f s", paragraphPause)).monospacedDigit().frame(width: 52) }
            }.tint(TransToolsTheme.accent).disabled(preparing || exporting || ownsPlayback)
            Text("Khoảng nghỉ thêm sau nhịp tự nhiên của giọng. Nếu dấu chấm dừng lâu, giảm Nghỉ giữa câu về 0–0,1 giây.")
                .font(.caption).foregroundStyle(.secondary)
            Text("Thời gian nghỉ áp dụng khi nghe tại đây. File audio hiện dùng nhịp nghỉ của bộ giọng.").font(.caption).foregroundStyle(.secondary)
            if model.configuredAI != nil {
                Toggle("Chuẩn hóa cách đọc bằng AI", isOn: $prepareNumericAI)
                    .toggleStyle(TrailingSettingsToggleStyle()).disabled(preparing || exporting)
                Text("Chỉ chuẩn hóa số, giờ, ngày tháng, đơn vị, ký hiệu và cách đọc viết tắt. Văn bản gốc giữ nguyên; đoạn không rõ nghĩa được giữ nguyên. Nội dung được gửi tới AI đã cấu hình.")
                    .font(.caption).foregroundStyle(.secondary)
            }
                        Text(exportInfo).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                        Divider()
                        DisclosureGroup("Chọn giọng & Phát âm") { SpeechSettingsView(language: language).padding(.top, 12) }
                    }.padding(1)
                }
            }.padding(24).frame(width: 640, height: 620)
        }
        .onChange(of: language) { _, _ in stopOwnPlayback() }
        .onChange(of: model.selectedDashboardTab) { _, tab in
            if tab != 6 { stopOwnPlayback(); exportTask?.cancel() }
        }
        .onAppear {
            mp3Installer.refresh()
            if !shortPauseMigrated {
                // Replace only the old default; preserve deliberately chosen pauses.
                if abs(sentencePause - 0.35) < 0.001 { sentencePause = 0.1 }
                shortPauseMigrated = true
            }
        }
        .onDisappear { stopOwnPlayback(); exportTask?.cancel() }
    }

    private func stopOwnPlayback() {
        readingGeneration = UUID(); readingTask?.cancel(); readingTask = nil; preparing = false; readingActive = false
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
        let generation = readingGeneration
        preparing = true; readingActive = true
        readingTask = Task { @MainActor in
            defer { if generation == readingGeneration { readingActive = false; preparing = false } }
            let speech = await preparedText(snapshot, language: selectedLanguage)
            guard !Task.isCancelled else { return }
            preparing = false
            guard trimmed == snapshot, language == selectedLanguage else { status = "Nội dung đã thay đổi · nhấn Đọc lại."; return }
            let parts = SpeechReadingPlan.parts(speech, sentencePause: sentencePause, paragraphPause: paragraphPause)
            for (index, part) in parts.enumerated() {
                guard !Task.isCancelled else { return }
                tts.speak(id: playbackID, text: part.text, language: selectedLanguage)
                while tts.isSpeaking && !Task.isCancelled {
                    do { try await Task.sleep(for: .milliseconds(80)) } catch { return }
                }
                guard !Task.isCancelled else { return }
                if index < parts.count - 1 {
                    do { try await Task.sleep(for: .seconds(part.pause)) } catch { return }
                }
            }
        }
    }

    private func exportAudio(mp3: Bool) {
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
                var temporary: URL?
                var encoded: URL?
                let data: Data?
                defer {
                    if let temporary { try? FileManager.default.removeItem(at: temporary) }
                    if let encoded { try? FileManager.default.removeItem(at: encoded) }
                }
                if engine.isLocal {
                    temporary = try await TTSEngineRouter.shared.exportWAV(text: speech, language: locale, engine: engine, options: options)
                    if mp3, let temporary { encoded = try await MP3AudioExporter.convert(temporary) }
                    data = nil
                } else {
                    temporary = nil
                    data = try await EdgeTTSService.shared.synthesize(text: speech, locale: locale, rateModifier: rate)
                }
                try Task.checkCancellation()
                guard exportSupported, selectedEngine == engine else { exporting = false; status = "Giọng đọc đã thay đổi. Chưa lưu audio."; return }
                let panel = NSSavePanel()
                let isMP3 = mp3 || !engine.isLocal
                panel.allowedContentTypes = isMP3 ? [.mp3] : [.wav]
                panel.nameFieldStringValue = isMP3 ? "Trans Tools-audio.mp3" : "Trans Tools-audio.wav"
                panel.canCreateDirectories = true
                if panel.runModal() == .OK, let url = panel.url {
                    if let temporary = encoded ?? temporary {
                        let staged = url.deletingLastPathComponent().appendingPathComponent("." + UUID().uuidString + (isMP3 ? ".mp3" : ".wav"))
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
