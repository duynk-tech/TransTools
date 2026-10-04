import SwiftUI

struct ChinesePinyinLearningView: View {
    @State private var selectedSubTab: PinyinSubTab = .initials
    @State private var selectedItem: PinyinItem = ChinesePinyinData.initialsGroups[0].items[0]

    // Canvas viết nét chữ Hán
    @State private var strokes: [[CGPoint]] = []
    @State private var currentStroke: [CGPoint] = []
    @State private var showGuide = true

    @ObservedObject private var audio = LanguagePronunciationService.shared

    private var activeGroupItems: [PinyinItem] {
        switch selectedSubTab {
        case .initials:
            return ChinesePinyinData.initialsGroups.flatMap { $0.items }
        case .finals:
            return ChinesePinyinData.finalsGroups.flatMap { $0.items }
        default:
            return []
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Thanh điều khiển tinh gọn & Nút Phát tất cả
            HStack(spacing: 12) {
                Picker("Phân mục", selection: $selectedSubTab) {
                    ForEach(PinyinSubTab.allCases) { tab in
                        Text(tabTitle(tab)).tag(tab)
                    }
                }
                .pickerStyle(.segmented)
                .controlSize(.large)
                .frame(minWidth: 430)

                Spacer()

                // Nút Phát tất cả (cho Thanh mẫu & Vận mẫu)
                if selectedSubTab == .initials || selectedSubTab == .finals {
                    if audio.isPlayingSequence {
                        Button {
                            audio.stop()
                        } label: {
                            Label("Dừng phát", systemImage: "stop.fill")
                        }
                        .buttonStyle(TransToolsActionButtonStyle(prominent: true))
                        .tint(.red)
                    } else {
                        Button {
                            playAllActiveItems()
                        } label: {
                            Label("Phát tất cả", systemImage: "play.fill")
                        }
                        .buttonStyle(TransToolsActionButtonStyle())
                        .help("Tự động phát tuần tự các âm Pinyin trong mục này")
                    }
                }


            }

            if let error = audio.error {
                Text(error).font(.caption).foregroundStyle(.red)
            }

            // Nội dung theo từng tab
            ScrollView {
            switch selectedSubTab {
            case .initials:
                renderInitialsAndFinals(groups: ChinesePinyinData.initialsGroups)
            case .finals:
                renderInitialsAndFinals(groups: ChinesePinyinData.finalsGroups)
            case .tones:
                renderTonesView()
            case .vocabulary:
                renderVocabularyView()
            }
            }
        }
        .onAppear { updateCoach() }
        .onChange(of: selectedItem) { _, _ in updateCoach() }

        .onChange(of: selectedSubTab) { _, newTab in
            audio.stop()
            if newTab == .initials {
                selectedItem = ChinesePinyinData.initialsGroups[0].items[0]
            } else if newTab == .finals {
                selectedItem = ChinesePinyinData.finalsGroups[0].items[0]
            }
            clearWriting()
            updateCoach()
        }
        .onDisappear {
            audio.stop()
        }
    }

    private func tabTitle(_ tab: PinyinSubTab) -> String {
        switch tab {
        case .initials: return "Thanh mẫu"
        case .finals: return "Vận mẫu"
        case .tones: return "Thanh điệu"
        case .vocabulary: return "Từ minh họa"
        }
    }

    private func updateCoach() {
        if selectedSubTab == .tones {
            LearningCoach.shared.configure(symbol: "ā á ǎ à", reading: "Bốn thanh điệu",
                detail: "Quan sát đường cao độ ở mục Thanh điệu. Mở nguồn để nghe mẫu; tập phân biệt từng thanh trước khi ghép vào từ.",
                position: 1, total: 1, language: .chinese,
                previous: {}, next: {}, listen: { audio.speak(text: "ā á ǎ à", language: .chinese) })
            return
        }
        let items = activeGroupItems
        let index = items.firstIndex(where: { $0.id == selectedItem.id }) ?? 0
        LearningCoach.shared.configure(symbol: selectedItem.pinyin, reading: selectedItem.articulationType,
            detail: "\(selectedItem.articulationGuide)\n\(selectedItem.exampleCharacter) · \(selectedItem.examplePinyin) · \(selectedItem.exampleMeaning)",
            position: index + 1, total: max(1, items.count), language: .chinese,
            previous: { if !items.isEmpty { selectedItem = items[max(0, index - 1)]; clearWriting() } },
            next: { if !items.isEmpty { selectedItem = items[min(items.count - 1, index + 1)]; clearWriting() } },
            listen: { audio.speak(text: selectedItem.pinyin, language: .chinese) })
    }

    // MARK: - Giao diện Thanh Mẫu & Vận Mẫu
    @ViewBuilder
    private func renderInitialsAndFinals(groups: [(name: String, items: [PinyinItem])]) -> some View {
        HStack(alignment: .top, spacing: 18) {
            // Cột trái: Danh sách các âm Pinyin
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(groups, id: \.name) { group in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text(group.name)
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundStyle(.secondary)
                                Spacer()
                                Button {
                                    playGroup(group.items)
                                } label: {
                                    Image(systemName: "speaker.wave.2")
                                        .font(.system(size: 10))
                                }
                                .buttonStyle(.plain)
                                .help("Phát toàn bộ nhóm âm này")
                            }

                            LazyVGrid(columns: [GridItem(.adaptive(minimum: 54))], spacing: 6) {
                                ForEach(group.items) { item in
                                    let isSel = selectedItem.id == item.id
                                    let isCurrentAudio = audio.currentText == item.pinyin

                                    Button {
                                        selectedItem = item
                                        clearWriting()
                                        audio.speak(text: item.pinyin, language: .chinese)
                                    } label: {
                                        VStack(spacing: 1) {
                                            Text(item.pinyin)
                                                .font(.system(size: 19, weight: .bold))
                                                .foregroundStyle(isCurrentAudio ? TransToolsTheme.accent : .primary)
                                            Text(item.articulationType)
                                                .font(.system(size: 9))
                                                .foregroundStyle(.secondary)
                                                .lineLimit(1)
                                        }
                                        .frame(maxWidth: .infinity)
                                        .frame(height: 50)
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
                        }
                    }
                }
                .padding(.trailing, 6)
            }
            .frame(maxWidth: .infinity)

            // Cột phải: Khẩu hình chuẩn ZIM & Luyện viết chữ Hán (Ô Mễ tự cách)
            VStack(alignment: .leading, spacing: 12) {
                // Card chữ Pinyin & Nút phát âm
                HStack(spacing: 12) {
                    Text(selectedItem.pinyin)
                        .font(.system(size: 38, weight: .bold))
                        .foregroundStyle(TransToolsTheme.accent)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(selectedItem.group)
                            .font(.title3.bold())
                        Text(selectedItem.articulationType)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Button {
                        audio.speak(text: selectedItem.pinyin, language: .chinese)
                    } label: {
                        Image(systemName: audio.isSpeaking && audio.currentText == selectedItem.speechSample ? "speaker.wave.3.fill" : "speaker.wave.2.fill")
                            .font(.title3)
                    }
                    .buttonStyle(TransToolsActionButtonStyle(prominent: true))
                    .tint(TransToolsTheme.accent)
                    .help("Nghe phát âm chuẩn")
                }
                .padding(12)
                .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))

                // Hướng dẫn khẩu hình chuẩn ZIM
                VStack(alignment: .leading, spacing: 6) {
                    Text("Khẩu hình:")
                        .font(.caption.bold())
                    Text(selectedItem.articulationGuide)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    Divider().padding(.vertical, 2)

                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Ví dụ: \(selectedItem.exampleCharacter) (/\(selectedItem.examplePinyin)/)")
                                .font(.subheadline.bold())
                            Text("Nghĩa: \(selectedItem.exampleMeaning)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button {
                            audio.speak(text: selectedItem.exampleCharacter, language: .chinese)
                        } label: {
                            Image(systemName: "speaker.wave.2")
                        }
                        .buttonStyle(TransToolsActionButtonStyle())
                        .help("Nghe từ ví dụ")
                    }
                }
                .padding(10)
                .background(TransToolsTheme.accent.opacity(0.05), in: RoundedRectangle(cornerRadius: 8))

                // Luyện viết chữ Hán ví dụ (Ô Mễ tự cách 米字格)
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Tập viết chữ Hán (\(selectedItem.exampleCharacter)):")
                            .font(.caption.bold())
                        Spacer()
                        Toggle("Hiện mẫu", isOn: $showGuide)
                            .toggleStyle(.checkbox)
                            .font(.caption)
                    }

                    GeometryReader { geometry in
                        ZStack {
                            Color(nsColor: .textBackgroundColor)

                            // Lưới Mễ tự cách (米字格) chuẩn luyện chữ Hán
                            Path { path in
                                let w = geometry.size.width, h = geometry.size.height
                                path.move(to: CGPoint(x: w / 2, y: 0)); path.addLine(to: CGPoint(x: w / 2, y: h))
                                path.move(to: CGPoint(x: 0, y: h / 2)); path.addLine(to: CGPoint(x: w, y: h / 2))
                                path.move(to: CGPoint(x: 0, y: 0)); path.addLine(to: CGPoint(x: w, y: h))
                                path.move(to: CGPoint(x: w, y: 0)); path.addLine(to: CGPoint(x: 0, y: h))
                            }
                            .stroke(Color.secondary.opacity(0.2), style: StrokeStyle(lineWidth: 1, dash: [4, 4]))

                            if showGuide {
                                Text(selectedItem.exampleCharacter)
                                    .font(.system(size: 70, weight: .light))
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
                    .frame(height: 150)
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

                        Text("Nghe mẫu · Nhắc lại · Luyện viết")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                    }
                    .controlSize(.small)
                }
            }
            .frame(maxWidth: .infinity)
        }
    }

    // MARK: - Giao diện Thanh Điệu & Biến Điệu
    @ViewBuilder
    private func renderTonesView() -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("4 Thanh điệu chính & Khinh thanh trong tiếng Trung")
                    .font(.headline.bold())

                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                    ForEach(ChinesePinyinData.tonesInfo, id: \.name) { tone in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(tone.name)
                                        .font(.subheadline.bold())
                                    Text(tone.symbol)
                                        .font(.caption.bold())
                                        .foregroundStyle(TransToolsTheme.accent)
                                }
                                Spacer()
                                Button {
                                    let sample = String(tone.example.prefix(2))
                                    audio.speak(text: sample, language: .chinese)
                                } label: {
                                    Image(systemName: "speaker.wave.2.fill")
                                }
                                .buttonStyle(TransToolsActionButtonStyle())
                            }
                            Text(tone.desc)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text("Ví dụ: \(tone.example)")
                                .font(.caption.bold())
                                .foregroundStyle(TransToolsTheme.accent)
                        }
                        .padding(10)
                        .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
                    }
                }

                Divider()

                Text("3 Quy tắc biến điệu quan trọng")
                    .font(.headline.bold())

                ForEach(ChinesePinyinData.toneSandhiRules, id: \.rule) { item in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(item.rule)
                            .font(.subheadline.bold())
                            .foregroundStyle(TransToolsTheme.accent)
                        Text(item.content)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(item.example)
                            .font(.caption.monospaced())
                            .padding(6)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 6))
                    }
                    .padding(10)
                    .background(TransToolsTheme.accent.opacity(0.04), in: RoundedRectangle(cornerRadius: 8))
                }
            }
        }
    }

    // MARK: - Giao diện Từ Vựng Cốt Lõi Pinyin
    @ViewBuilder
    private func renderVocabularyView() -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("Từ vựng giao tiếp cốt lõi minh họa theo Pinyin")
                    .font(.headline.bold())

                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                    ForEach(ChinesePinyinData.coreVocabulary, id: \.word) { item in
                        HStack(spacing: 10) {
                            VStack(alignment: .leading, spacing: 1) {
                                HStack(spacing: 6) {
                                    Text(item.word)
                                        .font(.title3.bold())
                                    Text("/\(item.pinyin)/")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Text("\(item.vi) (\(item.en))")
                                    .font(.caption)
                                    .foregroundStyle(TransToolsTheme.accent)
                            }
                            Spacer()
                            Button {
                                audio.speak(text: item.word, language: .chinese)
                            } label: {
                                Image(systemName: "speaker.wave.2.fill")
                            }
                            .buttonStyle(TransToolsActionButtonStyle())
                        }
                        .padding(10)
                        .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
                    }
                }
            }
        }
    }

    private func playAllActiveItems() {
        let symbols = activeGroupItems.map(\.pinyin)
        audio.playSequence(items: symbols, language: .chinese, onProgress: { idx in
            if idx < activeGroupItems.count {
                selectedItem = activeGroupItems[idx]
            }
        })
    }

    private func playGroup(_ items: [PinyinItem]) {
        let symbols = items.map(\.pinyin)
        audio.playSequence(items: symbols, language: .chinese, onProgress: { idx in
            if idx < items.count {
                selectedItem = items[idx]
            }
        })
    }

    private func clearWriting() {
        strokes = []
        currentStroke = []
    }
}
