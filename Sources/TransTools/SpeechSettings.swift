import SwiftUI
import AVFoundation

struct SpeechSettingsView: View {
    @ObservedObject private var localModel = LocalTTSModelManager.shared
    @ObservedObject private var tts = TTSService.shared
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

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            LocalTTSSettingSectionView()

            Divider()
                .padding(.vertical, 4)

            Text("Tùy chỉnh & Nghe thử").font(.headline)
            Picker("Ngôn ngữ nghe thử", selection: $language) {
                ForEach(AppLanguage.allCases) { lang in
                    Text(lang.displayName).tag(lang)
                }
            }
            .controlSize(.large)
            if localModel.isNaturalVoiceEnabled {
                Text("Tốc độ và âm lượng áp dụng cho giọng tự nhiên Local; giọng cơ bản bên dưới dùng khi cần dự phòng. Phong cách chỉ điều chỉnh nhịp đọc, không mô phỏng đầy đủ cảm xúc.")
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            Picker(localModel.isNaturalVoiceEnabled ? "Giọng dự phòng" : "Giọng", selection: voiceSelection) {
                Text("Tự động chọn giọng phù hợp").tag("")
                ForEach(voices) { voice in Text(voice.displayName).tag(voice.id) }
            }
            .controlSize(.large)
            Picker("Phong cách", selection: $tts.voiceTone) {
                ForEach(VoiceTone.allCases) { tone in Text(tone.title).tag(tone) }
            }
            .controlSize(.large)
            Text("Tốc độ đọc")
            Slider(value: $draftRate, in: 0.3...0.75, step: 0.01, onEditingChanged: { editing in
                if !editing { tts.speechRate = draftRate }
            })
            HStack { Text("Chậm"); Spacer(); Text("Nhanh") }.font(.caption).foregroundStyle(.secondary)
            Text("Âm lượng")
            Slider(value: $draftVolume, in: 0.05...1, onEditingChanged: { editing in
                if !editing { tts.speechVolume = draftVolume }
            })
            HStack(spacing: 12) {
                Button {
                    let samples: [String: String] = ["vi": "Xin chào, cùng học ngôn ngữ với TransTools nhé.", "en": "Hello, let's learn a language together.", "ja": "こんにちは。一緒に勉強しましょう。", "zh": "你好，我们一起学习吧。", "ko": "안녕하세요. 함께 공부해요."]
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
            Text("Thiết lập chỉ áp dụng trong TransTools, không thay đổi giọng hệ thống. Tốc độ và âm lượng lưu khi thả thanh kéo. Giọng đã chọn dùng cho ngôn ngữ tương ứng; ngôn ngữ khác chọn tự động. Nút nghe chậm vẫn đọc chậm hơn tốc độ bạn chọn.")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            if let voice = currentVoice {
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
        .onAppear {
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
