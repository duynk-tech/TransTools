import SwiftUI
import AVFoundation

struct SpeechSettingsView: View {
    @ObservedObject private var localModel = LocalTTSModelManager.shared
    @ObservedObject private var externalModels = ExternalTTSModelManager.shared
    @ObservedObject private var tts = TTSService.shared
    @State private var modelVoices: [ExternalTTSModel.Voice] = []
    @State private var routingRevision = 0
    @State private var language: AppLanguage = .vietnamese

    @State private var draftRate: Float = 0.44
    @State private var draftVolume: Float = 1
    @State private var currentVoice: AVSpeechSynthesisVoice?
    @State private var voices: [TTSVoiceOption] = []
    private var voiceSelection: Binding<String> {
        Binding(get: {
            voices.contains(where: { $0.id == tts.selectedVoiceID }) ? tts.selectedVoiceID ?? "" : ""
        }, set: { tts.selectedVoiceID = $0.isEmpty ? nil : $0 })
    }

    private func settingsRow<Content: View>(_ label: String, @ViewBuilder content: () -> Content) -> some View {
        HStack(alignment: .center, spacing: 16) {
            Text(label).frame(width: 140, alignment: .leading).fixedSize(horizontal: false, vertical: true)
            content().frame(maxWidth: .infinity, alignment: .leading)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }

    private var configuredEngine: LanguageVoiceEngine {
        let _ = routingRevision; let _ = externalModels.revision
        return LanguageVoicePreferences.resolved(for: language.speechLocale, localDefault: localModel.isNaturalVoiceEnabled, edgeDefault: tts.useEdgeNaturalVoice)
    }
    init(language: AppLanguage = .vietnamese) { _language = State(initialValue: language) }
    private func refreshModelVoices() { modelVoices = configuredEngine.externalModel?.voices(for: language.speechLocale) ?? [] }
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            LocalTTSSettingSectionView()
            ExternalTTSModelSettingsView()

            Divider()
                .padding(.vertical, 4)

            Text("Tùy chỉnh & Nghe thử").font(.headline)
            settingsRow("Ngôn ngữ nghe thử") {
                Picker("Ngôn ngữ nghe thử", selection: $language) {
                    ForEach(AppLanguage.allCases) { lang in Text(lang.displayName).tag(lang) }
                }.labelsHidden().controlSize(.large)
            }
            settingsRow("Công cụ ngôn ngữ") {
                Picker("Công cụ ngôn ngữ", selection: Binding(
                    get: { let _ = routingRevision; return LanguageVoicePreferences.selection(for: language.speechLocale) },
                    set: { LanguageVoicePreferences.set($0, for: language.speechLocale); routingRevision += 1; refreshModelVoices() }
                )) {
                    ForEach(LanguageVoiceEngine.allCases.filter { $0.supports(language.speechLocale) }) { engine in
                        Text(engine.title + (engine.externalModel.map { $0.isInstalled ? "" : " · Chưa cài" } ?? "")).tag(engine)
                    }
                }.labelsHidden().controlSize(.large)
            }
            Text("Lựa chọn lưu riêng cho từng ngôn ngữ. Mô hình Local chỉ nạp khi đọc, tự giải phóng sau 2 phút không dùng hoặc khi thiếu bộ nhớ. Khi chưa hỗ trợ sẽ dùng giọng cơ bản.")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            if let model = configuredEngine.externalModel {
                settingsRow("Giọng mô hình") {
                    Picker("Giọng mô hình", selection: Binding(
                        get: { model.selectedVoice(for: language.speechLocale) },
                        set: { UserDefaults.standard.set($0, forKey: "TTS_" + model.rawValue + "_Voice_" + LanguageVoicePreferences.code(language.speechLocale)); routingRevision += 1 }
                    )) {
                        if modelVoices.isEmpty { Text("Chưa tải mô hình").tag(model.defaultVoice) }
                        ForEach(modelVoices) { voice in Text(voice.displayTitle).tag(voice.id) }
                    }.labelsHidden().controlSize(.large).disabled(!model.isInstalled)
                }
                Text("Giọng theo mô hình đang chọn. Tốc độ được xử lý giữ cao độ; phong cách đi theo giọng gốc, không thêm từ hoặc hiệu ứng vào nội dung học.")
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            if localModel.isNaturalVoiceEnabled {
                Text("Tốc độ và âm lượng áp dụng cho giọng tự nhiên Local; giọng cơ bản bên dưới dùng khi cần dự phòng. Phong cách chỉ điều chỉnh nhịp đọc, không mô phỏng đầy đủ cảm xúc.")
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            settingsRow(configuredEngine == .system ? "Giọng" : "Giọng dự phòng") {
                Picker("Giọng", selection: voiceSelection) {
                    Text("Tự động chọn giọng phù hợp").tag("")
                    ForEach(voices) { voice in Text(voice.displayName).tag(voice.id) }
                }.labelsHidden().controlSize(.large)
            }
            if configuredEngine == .system || configuredEngine == .local {
            settingsRow("Phong cách") {
                Picker("Phong cách", selection: $tts.voiceTone) {
                    ForEach(VoiceTone.allCases) { tone in Text(tone.title).tag(tone) }
                }.labelsHidden().controlSize(.large)
            }
            }
            settingsRow("Tốc độ đọc") {
                VStack(spacing: 4) {
                    MintSpeechSlider(value: $draftRate, range: 0.3...0.75, step: 0.01, label: "Tốc độ đọc") { tts.speechRate = draftRate }
                    HStack { Text("Chậm"); Spacer(); Text("Nhanh") }.font(.caption).foregroundStyle(.secondary)
                }
            }
            settingsRow("Âm lượng") {
                MintSpeechSlider(value: $draftVolume, range: 0.05...1, step: 0.01, label: "Âm lượng") { tts.speechVolume = draftVolume }
            }
            HStack(spacing: 12) {
                Button {
                    let samples: [String: String] = ["vi": "Xin chào, cùng học ngôn ngữ với Trans Tools nhé.", "en": "Hello, let's learn a language together.", "en_IN": "Hello, let's learn a language together.", "ja": "こんにちは。一緒に勉強しましょう。", "zh": "你好，我们一起学习吧。", "ko": "안녕하세요. 함께 공부해요.", "fr": "Bonjour, apprenons une langue ensemble.", "de": "Hallo, lernen wir gemeinsam eine Sprache.", "it": "Ciao, impariamo una lingua insieme."]
                    tts.preview(text: samples[language.rawValue] ?? language.displayName, language: language)
                } label: {
                    Label(tts.isSpeaking ? "Nghe lại" : "Nghe thử", systemImage: "play.fill")
                }
                .buttonStyle(SpeechSettingsButtonStyle(prominent: true))

                Button { tts.stop() } label: { Label("Dừng", systemImage: "stop.fill") }
                Button("Giọng rõ, dễ nghe") {
                    tts.stop(); tts.useClearVoicePreset()
                    draftRate = tts.speechRate; draftVolume = tts.speechVolume
                }
            }
            .buttonStyle(SpeechSettingsButtonStyle())
            Text("Thiết lập chỉ áp dụng trong Trans Tools, không thay đổi giọng hệ thống. Tốc độ và âm lượng lưu khi thả thanh kéo. Giọng đã chọn dùng cho ngôn ngữ tương ứng; ngôn ngữ khác chọn tự động. Nút nghe chậm vẫn đọc chậm hơn tốc độ bạn chọn.")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            if let voice = currentVoice, configuredEngine == .system {
                Text("Giọng đang dùng: \(voice.name) · \(voice.language)").font(.caption).foregroundStyle(.secondary)
                if voice.quality == .default {
                    Text("Máy hiện dùng giọng tiêu chuẩn. Tải giọng Nâng cao hoặc Cao cấp trong Cài đặt hệ thống để nghe tự nhiên hơn.")
                        .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
            }
            if voices.isEmpty {
                Text("Chưa có giọng cho ngôn ngữ này trên máy. Bạn có thể tải thêm giọng trong Cài đặt hệ thống → Trợ năng → Nội dung được đọc.").font(.caption)
            }
            Divider().padding(.vertical, 4)
            SpeechPlaybackSettingsView()

        }
        .onChange(of: language) { _, _ in refreshModelVoices() }
        .onChange(of: externalModels.revision) { _, _ in refreshModelVoices() }
        .onAppear {
            refreshModelVoices()
            draftRate = tts.speechRate; draftVolume = tts.speechVolume
            voices = tts.availableVoices(for: language.speechLocale)
            currentVoice = tts.bestVoice(for: language.speechLocale)
        }
        .onChange(of: language) { _ in
            tts.stopPreview()
            voices = tts.availableVoices(for: language.speechLocale)
            currentVoice = tts.bestVoice(for: language.speechLocale)
        }
        .onChange(of: tts.selectedVoiceID) { _ in
            tts.stopPreview()
            currentVoice = tts.bestVoice(for: language.speechLocale)
        }
        .onDisappear { tts.stopPreview() }
    }
}

/// Keeps dragging local to the view; persists only when dragging ends.
private struct MintSpeechSlider: View {
    @Binding var value: Float
    let range: ClosedRange<Float>
    let step: Float
    let label: String
    let commit: () -> Void
    private var fraction: CGFloat { CGFloat(min(1, max(0, (value - range.lowerBound) / (range.upperBound - range.lowerBound)))) }
    private func update(_ x: CGFloat, width: CGFloat) {
        let ratio = Float(min(1, max(0, (x - 11) / max(1, width - 22))))
        let raw = range.lowerBound + ratio * (range.upperBound - range.lowerBound)
        value = min(range.upperBound, max(range.lowerBound, (raw / step).rounded() * step))
    }
    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule().fill(TransToolsTheme.accent.opacity(0.12)).frame(height: 5).padding(.horizontal, 11)
                Capsule().fill(TransToolsTheme.accent).frame(width: max(0, (geometry.size.width - 22) * fraction), height: 5).offset(x: 11)
                Circle().fill(TransToolsTheme.mint)
                    .overlay(Circle().stroke(TransToolsTheme.accent, lineWidth: 2))
                    .shadow(color: .black.opacity(0.10), radius: 2, y: 1)
                    .frame(width: 22, height: 22).offset(x: max(0, geometry.size.width - 22) * fraction)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0)
                .onChanged { update($0.location.x, width: geometry.size.width) }
                .onEnded { update($0.location.x, width: geometry.size.width); commit() })
        }
        .frame(height: 32)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityValue("\(Int(fraction * 100)) phần trăm")
        .accessibilityAdjustableAction { direction in
            let increment: Float = direction == .increment ? step : -step
            value = min(range.upperBound, max(range.lowerBound, value + increment)); commit()
        }
    }
}
