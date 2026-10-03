import SwiftUI
import AppKit

struct JapaneseNHKLearningView: View {
    @State private var isKatakana = false
    @State private var selectedCategory: JapaneseCategory = .gojuon
    @State private var selectedItem: NHKJapaneseItem = JapaneseNHKData.gojuonRows[0].items[0]

    // Canvas viết nét
    @State private var strokes: [[CGPoint]] = []
    @State private var currentStroke: [CGPoint] = []
    @State private var showGuide = true
    @State private var showArrowOverlay = false
    @State private var showStrokePopover = false
    @State private var strokeImage: NSImage? = nil

    @ObservedObject private var audio = LanguagePronunciationService.shared

    private var currentRows: [(name: String, items: [NHKJapaneseItem])] {
        switch selectedCategory {
        case .gojuon: return JapaneseNHKData.gojuonRows
        case .dakuon: return JapaneseNHKData.dakuonRows
        case .yoon: return JapaneseNHKData.yoonRows
        }
    }

    private var allCurrentItems: [NHKJapaneseItem] {
        currentRows.flatMap { $0.items }
    }

    var body: some View {
        VStack(spacing: 12) {
            // MARK: - Thanh điều khiển trên cùng (Gọn gàng, không khoảng trắng thừa)
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 16) {
                Text("Bảng chữ")
                    .frame(width: 80, alignment: .leading)
                    .lineLimit(1).fixedSize(horizontal: true, vertical: false)
                Picker("Bảng chữ", selection: $isKatakana) {
                    Text("Hiragana (あ)").tag(false)
                    Text("Katakana (ア)").tag(true)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 260)
                .controlSize(.large)
                Spacer()
                Text("Kana · nghe, nhận biết và luyện viết")
                    .font(.callout).foregroundStyle(.secondary)
                }

                HStack(spacing: 16) {
                Text("Nhóm âm")
                    .frame(width: 80, alignment: .leading)
                    .lineLimit(1).fixedSize(horizontal: true, vertical: false)
                Picker("Nhóm âm", selection: $selectedCategory) {
                    ForEach(JapaneseCategory.allCases) { cat in
                        Text(categoryTitle(cat)).tag(cat)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 390)
                .controlSize(.large)

                Spacer()

                // Nút Phát tất cả / Dừng
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
                        Label("Phát tất cả", systemImage: "play.fill")
                    }
                    .buttonStyle(.bordered)
                    .help("Tự động phát tuần tự toàn bộ bảng chữ cái đang xem")
                }

            }
            }
            .padding(16)
            .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 16))

            if let error = audio.error { Text(error).font(.caption).foregroundStyle(.red) }

            // MARK: - Hai cột: Bên trái scroll độc lập, Bên phải fit trọn vẹn
            GeometryReader { geo in
                HStack(alignment: .top, spacing: 18) {
                    // CỘT TRÁI: Bảng chữ cái cuộn lên xuống độc lập
                    ScrollView(.vertical, showsIndicators: true) {
                        VStack(alignment: .leading, spacing: 14) {
                            ForEach(currentRows, id: \.name) { row in
                                VStack(alignment: .leading, spacing: 6) {
                                    HStack {
                                        Text(row.name)
                                            .font(.system(size: 11, weight: .bold))
                                            .foregroundStyle(.secondary)
                                        Spacer()
                                        Button {
                                            playRow(row.items)
                                        } label: {
                                            Image(systemName: "speaker.wave.2")
                                                .font(.system(size: 12))
                                                .foregroundStyle(TransToolsTheme.accent)
                                        }
                                        .buttonStyle(.plain)
                                        .help("Phát toàn bộ hàng này")
                                    }

                                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 5), spacing: 6) {
                                        ForEach(row.items) { item in
                                            let isSel = selectedItem.id == item.id
                                            let isCurrentAudio = audio.currentText == item.displaySymbol(isKatakana: isKatakana)

                                            Button {
                                                selectedItem = item
                                                clearWriting()
                                                loadStrokeImage()
                                                audio.speak(text: item.displaySymbol(isKatakana: isKatakana), language: .japanese)
                                            } label: {
                                                VStack(spacing: 1) {
                                                    Text(item.displaySymbol(isKatakana: isKatakana))
                                                        .font(.system(size: 21, weight: .semibold))
                                                        .foregroundStyle(isCurrentAudio ? TransToolsTheme.accent : .primary)
                                                    Text(item.romaji)
                                                        .font(.system(size: 12))
                                                        .foregroundStyle(.secondary)
                                                }
                                                .frame(maxWidth: .infinity)
                                                .frame(height: 62)
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
                        .padding(.trailing, 8)
                    }
                    .frame(maxWidth: .infinity)

                    // CỘT PHẢI: Fit trọn vẹn toàn bộ nội dung để quan sát, không bị cắt
                    VStack(alignment: .leading, spacing: 10) {
                        // 1. Thẻ thông tin chữ cái & Nút phát âm
                        HStack(spacing: 12) {
                            Text(selectedItem.displaySymbol(isKatakana: isKatakana))
                                .font(.system(size: 36, weight: .bold))
                                .foregroundStyle(TransToolsTheme.accent)

                            VStack(alignment: .leading, spacing: 2) {
                                HStack(spacing: 6) {
                                    Text(selectedItem.romaji)
                                        .font(.title3.bold())
                                    Text("Romaji")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Text("Hàng \(selectedItem.rowGroup)")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }

                            Spacer()

                            Button {
                                audio.speak(text: selectedItem.displaySymbol(isKatakana: isKatakana), language: .japanese)
                            } label: {
                                HStack(spacing: 4) {
                                    Image(systemName: audio.isSpeaking && audio.currentText == selectedItem.displaySymbol(isKatakana: isKatakana) ? "speaker.wave.3.fill" : "speaker.wave.2.fill")
                                    Text("Nghe mẫu")
                                }
                                .font(.callout.bold())
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(TransToolsTheme.accent)
                        }
                        .padding(10)
                        .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))

                        // 2. Thẻ Từ vựng ví dụ chuẩn bài học NHK
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                HStack(spacing: 4) {
                                    Text("Từ minh họa:")
                                        .font(.caption.bold())
                                        .foregroundStyle(.secondary)
                                    Text(selectedItem.exampleWord)
                                        .font(.subheadline.bold())
                                    Text("(\(selectedItem.exampleReading))")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Text("→ \(selectedItem.exampleMeaning)")
                                    .font(.caption)
                                    .foregroundStyle(TransToolsTheme.accent)
                            }
                            Spacer()
                            Button {
                                audio.speak(text: selectedItem.exampleWord, language: .japanese)
                            } label: {
                                Image(systemName: "speaker.wave.2")
                                    .font(.caption)
                            }
                            .buttonStyle(.bordered)
                            .disabled(LocalJapaneseRecordings.file(for: selectedItem.exampleWord) == nil)
                            .help("Từ minh họa này chưa có bản ghi riêng")
                        }
                        .padding(8)
                        .background(TransToolsTheme.accent.opacity(0.05), in: RoundedRectangle(cornerRadius: 8))

                        // 3. Khung luyện viết nét & Hướng dẫn nét vẽ có mũi tên chuẩn NHK
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text("Luyện viết nét:")
                                    .font(.caption.bold())

                                Spacer()

                                // Nút Popup xem hướng dẫn nét vẽ có mũi tên chuẩn NHK
                                Button {
                                    showStrokePopover.toggle()
                                } label: {
                                    HStack(spacing: 4) {
                                        Image(systemName: "hand.point.up.left.and.text")
                                        Text("Thứ tự nét")
                                    }
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(TransToolsTheme.accent)
                                }
                                .buttonStyle(.borderless)
                                .popover(isPresented: $showStrokePopover, arrowEdge: .top) {
                                    nhkStrokeGuidePopoverContent
                                }

                                Toggle("Mẫu", isOn: $showGuide)
                                    .toggleStyle(.checkbox)
                                    .font(.caption)

                                Toggle("Mũi tên nền", isOn: $showArrowOverlay)
                                    .toggleStyle(.checkbox)
                                    .font(.caption)
                                    .help("Hiển thị ảnh nét vẽ có mũi tên làm nền trong ô viết")
                            }

                            // Canvas tập viết
                            ZStack {
                                Color(nsColor: .textBackgroundColor)

                                // Lưới chữ thập nét đứt chuẩn tập viết chữ Nhật
                                GeometryReader { cGeo in
                                    Path { path in
                                        let w = cGeo.size.width, h = cGeo.size.height
                                        path.move(to: CGPoint(x: w / 2, y: 0)); path.addLine(to: CGPoint(x: w / 2, y: h))
                                        path.move(to: CGPoint(x: 0, y: h / 2)); path.addLine(to: CGPoint(x: w, y: h / 2))
                                    }
                                    .stroke(Color.secondary.opacity(0.25), style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
                                }

                                // Mẫu nét vẽ có mũi tên NHK làm nền mờ (nếu bật)
                                if showArrowOverlay, let strokeImage {
                                    Image(nsImage: strokeImage)
                                        .resizable()
                                        .scaledToFit()
                                        .padding(12)
                                        .opacity(0.35)
                                } else if showGuide {
                                    // Mẫu chữ mờ thông thường
                                    Text(selectedItem.displaySymbol(isKatakana: isKatakana))
                                        .font(.system(size: 130, weight: .light))
                                        .foregroundStyle(Color.secondary.opacity(0.18))
                                }

                                // Canvas người dùng vẽ
                                GeometryReader { cGeo in
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
                                    .contentShape(Rectangle())
                                    .gesture(
                                        DragGesture(minimumDistance: 0)
                                            .onChanged { value in
                                                currentStroke.append(CGPoint(
                                                    x: min(1, max(0, value.location.x / cGeo.size.width)),
                                                    y: min(1, max(0, value.location.y / cGeo.size.height))
                                                ))
                                            }
                                            .onEnded { _ in
                                                if !currentStroke.isEmpty { strokes.append(currentStroke) }
                                                currentStroke = []
                                            }
                                    )
                                }
                            }
                            .frame(height: max(160, min(220, geo.size.height - 230)))
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                            .overlay(
                                RoundedRectangle(cornerRadius: 10)
                                    .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
                            )

                            // Thanh công cụ hoàn tác / viết lại
                            HStack {
                                Button("Hoàn tác nét") {
                                    if !strokes.isEmpty { strokes.removeLast() }
                                }
                                .disabled(strokes.isEmpty)

                                Button("Viết lại") {
                                    clearWriting()
                                }

                                Spacer()

                                Text(selectedItem.mnemonicTip)
                                    .font(.system(size: 12))
                                    .foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            .controlSize(.large)
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .onAppear {
            loadStrokeImage()
            updateCoach()
        }
        .sheet(isPresented: $audio.sourceRequired) { LearningSourceSheet(language: .japanese, japaneseKatakana: isKatakana) }
        .onChange(of: selectedItem) { _, _ in
            loadStrokeImage()
            updateCoach()
        }
        .onChange(of: isKatakana) { _, _ in
            audio.stop()
            clearWriting()
            loadStrokeImage()
            updateCoach()
        }
        .onChange(of: selectedCategory) { _, _ in
            audio.stop()
            if let first = currentRows.first?.items.first {
                selectedItem = first
                clearWriting()
                loadStrokeImage()
            }
        }
        .onDisappear {
            audio.stop()
        }
    }

    // MARK: - Popover hiển thị thứ tự nét & mũi tên chuẩn NHK
    @ViewBuilder
    private var nhkStrokeGuidePopoverContent: some View {
        VStack(spacing: 10) {
            HStack {
                Text("Thứ tự nét · \(selectedItem.displaySymbol(isKatakana: isKatakana))")
                    .font(.headline.bold())
                Spacer()
                Button("Đóng") {
                    showStrokePopover = false
                }
                .controlSize(.large)
            }

            if let img = strokeImage {
                Image(nsImage: img)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 260, height: 260)
                    .background(Color.white, in: RoundedRectangle(cornerRadius: 8))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.secondary.opacity(0.15), lineWidth: 1)
                    )
            } else {
                VStack(spacing: 8) {
                    ProgressView()
                    Text("Đang tải sơ đồ nét...")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(width: 260, height: 260)
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.right.circle.fill")
                        .foregroundStyle(.red)
                    Text("Số nét: \(selectedItem.strokeCount) nét. Viết theo thứ tự số và hướng mũi tên đỏ.")
                        .font(.caption.bold())
                }
                Text("Mẹo nhớ: \(selectedItem.mnemonicTip)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(8)
            .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 6))
        }
        .padding(14)
        .frame(width: 310)
    }

    private func categoryTitle(_ category: JapaneseCategory) -> String {
        switch category {
        case .gojuon: return "Âm cơ bản"
        case .dakuon: return "Âm đục · bán đục"
        case .yoon: return "Âm ghép"
        }
    }

    private func updateCoach() {
        let items = allCurrentItems
        let index = items.firstIndex(where: { $0.id == selectedItem.id }) ?? 0
        LearningCoach.shared.configure(symbol: selectedItem.displaySymbol(isKatakana: isKatakana),
            reading: "Romaji · " + selectedItem.romaji,
            detail: "\(selectedItem.exampleWord) · \(selectedItem.exampleReading) · \(selectedItem.exampleMeaning)\n\(selectedItem.mnemonicTip)",
            position: index + 1, total: items.count, language: .japanese,
            previous: { selectedItem = items[max(0, index - 1)]; clearWriting() },
            next: { selectedItem = items[min(items.count - 1, index + 1)]; clearWriting() },
            listen: { audio.speak(text: selectedItem.displaySymbol(isKatakana: isKatakana), language: .japanese) })
    }

    private func loadStrokeImage() {
        strokeImage = nil
        let requestedID = selectedItem.id
        let requestedKatakana = isKatakana
        NHKStrokeGuideService.shared.loadStrokeImage(for: requestedID, isKatakana: requestedKatakana) { img in
            guard selectedItem.id == requestedID, isKatakana == requestedKatakana else { return }
            self.strokeImage = img
        }
    }

    private func playAllLetters() {
        let symbols = allCurrentItems.map { $0.displaySymbol(isKatakana: isKatakana) }
        audio.playSequence(items: symbols, language: .japanese, onProgress: { idx in
            if idx < allCurrentItems.count {
                selectedItem = allCurrentItems[idx]
            }
        })
    }

    private func playRow(_ items: [NHKJapaneseItem]) {
        let symbols = items.map { $0.displaySymbol(isKatakana: isKatakana) }
        audio.playSequence(items: symbols, language: .japanese, onProgress: { idx in
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
