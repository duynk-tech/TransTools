import SwiftUI

private struct LetterLesson: Identifiable {
    var symbol: String
    var reading: String
    var id: String { symbol }
}

struct AlphabetLearningView: View {
    @ObservedObject var model: MeetingModel
    @ObservedObject var manager: LanguageLearningManager
    @State private var selected = 0
    @State private var strokes: [[CGPoint]] = []
    @State private var currentStroke: [CGPoint] = []
    @State private var showGuide = true
    @State private var isBritish = false

    @ObservedObject private var audio = LanguagePronunciationService.shared

    private var englishLetters: [LetterLesson] {
        let symbols = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZ").map(String.init)
        let readings = (0..<symbols.count).map { "/" + EnglishLetterGuide.ipa($0, british: isBritish) + "/" }
        return zip(symbols, readings).map { LetterLesson(symbol: $0.0, reading: $0.1) }
    }

    private var koreanLetters: [LetterLesson] {
        let symbols = "ㄱ ㄴ ㄷ ㄹ ㅁ ㅂ ㅅ ㅇ ㅈ ㅊ ㅋ ㅌ ㅍ ㅎ ㅏ ㅑ ㅓ ㅕ ㅗ ㅛ ㅜ ㅠ ㅡ ㅣ".components(separatedBy: " ")
        let readings = "giyeok nieun digeut rieul mieum bieup siot ieung jieut chieut kieuk tieut pieup hieut a ya eo yeo o yo u yu eu i".components(separatedBy: " ")
        return zip(symbols, readings).map { LetterLesson(symbol: $0.0, reading: $0.1) }
    }

    private var activeLetters: [LetterLesson] {
        switch manager.selectedLanguage {
        case .korean: return koreanLetters
        default: return englishLetters
        }
    }

    private var currentLetter: LetterLesson {
        activeLetters[min(selected, activeLetters.count - 1)]
    }

    var body: some View {
        LearningStudioView(language: manager.selectedLanguage, model: model) {
        Group {
            switch manager.selectedLanguage {
            case .japanese:
                // Theo chuẩn NHK WORLD-JAPAN (Hiragana, Katakana, Gojūon, Dakuon, Yōon)
                JapaneseNHKLearningView()

            case .chinese:
                // Theo chuẩn ZIM Academy (Thanh mẫu, Vận mẫu, 4 Thanh điệu, Biến điệu)
                ChinesePinyinLearningView()

            case .english, .korean:
                // Bảng chữ cái tiếng Anh (Latin A-Z) & tiếng Hàn (Hangeul)
                VStack(alignment: .leading, spacing: 14) {
                    // Header điều khiển tinh gọn
                    HStack(spacing: 12) {
                        Text(manager.selectedLanguage == .english ? "Bảng chữ cái tiếng Anh (26 chữ cái)" : "Bảng chữ cái tiếng Hàn (Hangeul)")
                            .font(.title3.bold())

                        if manager.selectedLanguage == .english {
                            Picker("Phiên âm", selection: $isBritish) {
                                Text("Mỹ (US)").tag(false)
                                Text("Anh (UK)").tag(true)
                            }
                            .pickerStyle(.segmented)
                            .labelsHidden()
                            .frame(width: 210)
                            .fixedSize(horizontal: false, vertical: true)
                        }

                        Spacer()

                        // Nút Phát tất cả A-Z / Dừng
                        if audio.isPlayingSequence {
                            Button {
                                audio.stop()
                            } label: {
                                Label("Dừng phát", systemImage: "stop.fill")
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(.red)
                        } else {
                            Button {
                                playAllLetters()
                            } label: {
                                Label(manager.selectedLanguage == .english ? "Phát tất cả" : "Nghe tại nguồn", systemImage: manager.selectedLanguage == .english ? "play.fill" : "arrow.up.right.square")
                            }
                            .buttonStyle(.bordered)
                            .help("Tự động phát tuần tự toàn bộ bảng chữ cái")
                        }
                    }

                    HStack(alignment: .top, spacing: 18) {
                        // Cột trái: Lưới chữ cái (bấm vào là nghe ngay)
                        ScrollView {
                        VStack(alignment: .leading, spacing: 10) {
                            if manager.selectedLanguage == .korean {
                                Text("14 phụ âm cơ bản · 10 nguyên âm cơ bản").font(.callout.weight(.semibold))
                            }
                            LazyVGrid(columns: [GridItem(.adaptive(minimum: 50))], spacing: 6) {
                                ForEach(Array(activeLetters.enumerated()), id: \.element.id) { index, item in
                                    let isSel = selected == index
                                    let isCurrentAudio = audio.currentText == item.symbol

                                    Button {
                                        selected = index
                                        clearWriting()
                                        speakSingle(item.symbol)
                                    } label: {
                                        VStack(spacing: 1) {
                                            Text(item.symbol)
                                                .font(.system(size: 20, weight: .bold))
                                                .foregroundStyle(isCurrentAudio ? TransToolsTheme.accent : .primary)
                                            Text(item.reading)
                                                .font(.system(size: 11))
                                                .foregroundStyle(.secondary)
                                                .lineLimit(1)
                                        }
                                        .frame(maxWidth: .infinity)
                                        .frame(height: 64)
                                        .background(
                                            isCurrentAudio ? TransToolsTheme.accent.opacity(0.28) :
                                            (isSel ? TransToolsTheme.accent.opacity(0.16) : Color.secondary.opacity(0.06))
                                        )
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 8)
                                                .stroke(isSel ? TransToolsTheme.accent : Color.clear, lineWidth: 1.5)
                                        )
                                        .clipShape(RoundedRectangle(cornerRadius: 8))
                                    }
                                    .buttonStyle(.plain)
                                }
                            }

                            if manager.selectedLanguage == .english {
                                Text("AudioLang · A–Z offline · bản ghi giữ tốc độ gốc; chưa phân loại giọng UK/US.")
                                    .font(.caption).foregroundStyle(.secondary)
                            } else {
                                Text("Phụ âm và nguyên âm Hangeul · nghe tại nguồn King Sejong khi chưa có bản ghi offline.")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        }
                        .frame(maxWidth: .infinity)

                        // Cột phải: Luyện đọc & Luyện viết nét
                        VStack(alignment: .leading, spacing: 12) {
                            // Card chữ đang chọn & Nút nghe
                            HStack(spacing: 12) {
                                Text(currentLetter.symbol)
                                    .font(.system(size: 38, weight: .bold))
                                    .foregroundStyle(TransToolsTheme.accent)

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(currentLetter.reading)
                                        .font(.title3.bold())
                                    Text(manager.selectedLanguage == .english ? (isBritish ? "Phiên âm UK" : "Phiên âm US") : "Tiếng Hàn (King Sejong)")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }

                                Spacer()

                                Button {
                                    speakSingle(currentLetter.symbol)
                                } label: {
                                    Image(systemName: audio.isSpeaking && audio.currentText == currentLetter.symbol ? "speaker.wave.3.fill" : "speaker.wave.2.fill")
                                        .font(.title3)
                                }
                                .buttonStyle(.borderedProminent)
                                .tint(TransToolsTheme.accent)
                                .help("Nghe phát âm chữ này")
                            }
                            .padding(12)
                            .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))

                            // Canvas vẽ tập viết
                            VStack(alignment: .leading, spacing: 6) {
                                HStack {
                                    Text("Luyện viết chữ:")
                                        .font(.caption.bold())
                                    Spacer()
                                    Toggle("Hiện mẫu", isOn: $showGuide)
                                        .toggleStyle(.checkbox)
                                        .font(.caption)
                                }

                                GeometryReader { geometry in
                                    ZStack {
                                        Color(nsColor: .textBackgroundColor)

                                        // Đường lưới kẻ ô
                                        Path { path in
                                            let w = geometry.size.width, h = geometry.size.height
                                            if manager.selectedLanguage == .english {
                                                for fraction in [0.25, 0.5, 0.75] {
                                                    path.move(to: CGPoint(x: 0, y: h * fraction))
                                                    path.addLine(to: CGPoint(x: w, y: h * fraction))
                                                }
                                            } else {
                                                path.move(to: CGPoint(x: w / 2, y: 0)); path.addLine(to: CGPoint(x: w / 2, y: h))
                                                path.move(to: CGPoint(x: 0, y: h / 2)); path.addLine(to: CGPoint(x: w, y: h / 2))
                                            }
                                        }.stroke(Color.secondary.opacity(0.25), style: StrokeStyle(lineWidth: 1, dash: [4, 4]))

                                        if showGuide {
                                            Text(currentLetter.symbol)
                                                .font(.system(size: 110, weight: .light))
                                                .foregroundStyle(Color.secondary.opacity(0.18))
                                        }

                                        Canvas { context, size in
                                            for points in strokes + [currentStroke] where !points.isEmpty {
                                                var path = Path()
                                                path.move(to: CGPoint(x: points[0].x * size.width, y: points[0].y * size.height))
                                                for point in points.dropFirst() {
                                                    path.addLine(to: CGPoint(x: point.x * size.width, y: point.y * size.height))
                                                }
                                                context.stroke(path, with: .color(TransToolsTheme.accent), style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round))
                                            }
                                        }
                                    }
                                    .contentShape(Rectangle())
                                    .gesture(
                                        DragGesture(minimumDistance: 0)
                                            .onChanged { value in
                                                currentStroke.append(CGPoint(
                                                    x: min(1, max(0, value.location.x / geometry.size.width)),
                                                    y: min(1, max(0, value.location.y / geometry.size.height))
                                                ))
                                            }
                                            .onEnded { _ in
                                                if !currentStroke.isEmpty { strokes.append(currentStroke) }
                                                currentStroke = []
                                            }
                                    )
                                }
                                .frame(height: 160)
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 10)
                                        .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
                                    )

                                HStack {
                                    Button("Hoàn tác") {
                                        if !strokes.isEmpty { strokes.removeLast() }
                                    }
                                    .disabled(strokes.isEmpty)

                                    Button("Viết lại") {
                                        clearWriting()
                                    }

                                    Spacer()
                                }
                                .controlSize(.large)
                            }
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
            }
        }
        }
        .onAppear { updateCoach() }
        .onChange(of: selected) { _, _ in updateCoach() }
        .onChange(of: isBritish) { _, _ in updateCoach() }
        .sheet(isPresented: Binding(get: { audio.sourceRequired && (manager.selectedLanguage == .english || manager.selectedLanguage == .korean) }, set: { audio.sourceRequired = $0 })) {
            LearningSourceSheet(language: manager.selectedLanguage)
        }
        .onChange(of: manager.selectedLanguage) { _, _ in
            audio.stop()
            selected = 0
            clearWriting()
            updateCoach()
        }
        .onDisappear {
            audio.stop()
        }
    }

    private func updateCoach() {
        guard manager.selectedLanguage == .english || manager.selectedLanguage == .korean else { return }
        let letters = activeLetters
        LearningCoach.shared.configure(symbol: currentLetter.symbol, reading: currentLetter.reading,
            detail: manager.selectedLanguage == .english ? "Tên chữ khác với âm của chữ trong từ. Nghe mẫu, dừng rồi tự nhắc lại." : "Hangeul ghép phụ âm và nguyên âm thành khối âm tiết. Học từng ký tự trước khi ghép chữ.",
            position: selected + 1, total: letters.count, language: manager.selectedLanguage,
            previous: { selected = max(0, selected - 1); clearWriting() },
            next: { selected = min(letters.count - 1, selected + 1); clearWriting() },
            listen: { speakSingle(currentLetter.symbol) })
    }

    private func speakSingle(_ symbol: String) {
        audio.speak(text: symbol, language: manager.selectedLanguage, british: isBritish)
    }

    private func playAllLetters() {
        let symbols = activeLetters.map(\.symbol)
        audio.playSequence(items: symbols, language: manager.selectedLanguage, british: isBritish, onProgress: { idx in
            if idx < activeLetters.count {
                selected = idx
            }
        })
    }

    private func clearWriting() {
        strokes = []
        currentStroke = []
    }
}
