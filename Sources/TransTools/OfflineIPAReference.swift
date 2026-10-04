import SwiftUI
import AVFoundation

@MainActor final class OfflineIPAPlayer: NSObject, ObservableObject, AVAudioPlayerDelegate {
    @Published var active: String?
    @Published var error: String?
    private var player: AVAudioPlayer?
    func play(_ symbol: String) {
        playResource("IPA/\(symbol).wav", id: symbol)
    }
    func playResource(_ path: String, id: String) {
        stop(); error = nil
        guard !path.contains(".."), !path.hasPrefix("/"),
              let url = Bundle.main.resourceURL?.appendingPathComponent("Pronunciation/\(path)"), FileManager.default.fileExists(atPath: url.path) else {
            error = "Chưa có bản ghi offline cho âm này."; return
        }
        playFile(url, id: id)
    }
    func playFile(_ url: URL, id: String) {
        stop(); error = nil
        guard url.isFileURL, FileManager.default.fileExists(atPath: url.path) else {
            error = "Chưa có file audio trên máy."; return
        }
        do {
            let audio = try AVAudioPlayer(contentsOf: url)
            audio.delegate = self
            audio.prepareToPlay()
            guard audio.play() else { throw NSError(domain: "OfflineIPA", code: 1) }
            player = audio; active = id
        } catch { self.error = "Không phát được bản ghi: \(error.localizedDescription)" }
    }
    func stop() { player?.stop(); player = nil; active = nil }
    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in if self.player === player { self.stop() } }
    }
}

struct OfflineIPAReferenceView: View {
    @StateObject private var audio = OfflineIPAPlayer()
    @State private var expanded = false
    private let sounds = "i e æ ɑ ɒ ɔ ʌ u b d f g h j k l m n ŋ p s t v w z θ ð ʃ ʒ ɻ".components(separatedBy: " ")
    var body: some View {
        DisclosureGroup(isExpanded: $expanded) {
            VStack(alignment: .leading, spacing: 12) {
                Text("Bản ghi người thật · phát offline").font(.subheadline.bold())
                Text("Âm IPA tham khảo, không phải tên chữ cái hay mẫu riêng cho giọng UK/US. Nghe ở tốc độ gốc; không ghép các file để tạo tên chữ.")
                    .font(.caption).foregroundStyle(.secondary)
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 54))], spacing: 8) {
                    ForEach(sounds, id: \.self) { sound in
                        Button { audio.play(sound) } label: {
                            Text("/\(sound)/").font(.system(size: 18)).frame(maxWidth: .infinity).padding(.vertical, 9)
                        }.buttonStyle(TransToolsActionButtonStyle()).tint(audio.active == sound ? TransToolsTheme.accent : .secondary)
                            .accessibilityLabel("Nghe bản ghi IPA \(sound)")
                    }
                }
                HStack {
                    Button("Dừng") { audio.stop() }.disabled(audio.active == nil)
                    Spacer()
                    Link("Nguồn · Ruben Schachtenhaufen · CC0 ↗", destination: URL(string: "https://github.com/NewDanishPhonetics/IPA-sound-files")!)
                }.font(.caption)
                if let error = audio.error { Text(error).font(.caption).foregroundStyle(.red) }
            }.padding(.top, 12)
        } label: { Label("Bản ghi âm IPA offline · 30 âm", systemImage: "waveform") }
        .padding(14).background(Color.secondary.opacity(0.05), in: RoundedRectangle(cornerRadius: 12))
        .onChange(of: expanded) { _, value in if !value { audio.stop() } }
        .onDisappear { audio.stop() }
    }
}
