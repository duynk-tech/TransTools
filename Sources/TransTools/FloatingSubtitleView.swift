import SwiftUI
import AppKit
import Combine
#if canImport(Translation)
import Translation
#endif

// MARK: - Native Draggable Subtitle Window Hosting View

final class FloatingSubtitlePanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

final class OverlayHostingView<Content: View>: NSHostingView<Content> {
    private var mouseDownLocation: NSPoint?

    override var mouseDownCanMoveWindow: Bool { true }

    override func mouseDown(with event: NSEvent) {
        mouseDownLocation = event.locationInWindow
        super.mouseDown(with: event)
    }

    override func mouseDragged(with event: NSEvent) {
        guard let window = self.window else {
            super.mouseDragged(with: event)
            return
        }
        if let start = mouseDownLocation {
            let dx = abs(event.locationInWindow.x - start.x)
            let dy = abs(event.locationInWindow.y - start.y)
            if dx > 2 || dy > 2 {
                window.performDrag(with: event)
                return
            }
        }
        super.mouseDragged(with: event)
    }
}

struct DraggableWindowArea: NSViewRepresentable {
    func makeNSView(context: Context) -> DraggableNSView {
        DraggableNSView()
    }
    func updateNSView(_ nsView: DraggableNSView, context: Context) {}
}

final class DraggableNSView: NSView {
    override var mouseDownCanMoveWindow: Bool { true }

    override func mouseDragged(with event: NSEvent) {
        window?.performDrag(with: event)
    }

    override func resetCursorRects() {
        super.resetCursorRects()
        addCursorRect(bounds, cursor: .openHand)
    }
}

// MARK: - Modern Floating Subtitle View (Paced & Smooth Rolling Subtitles)

private struct SubtitleContentSizeKey: PreferenceKey {
    static var defaultValue: CGSize = .zero
    static func reduce(value: inout CGSize, nextValue: () -> CGSize) {
        value = nextValue()
    }
}

private struct FullSubtitleBoardBackground: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 20, style: .continuous)
            .fill(Color.white)
            .overlay {
                MiniToolPaperGrid(light: true)
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .padding(2)
            }
            .overlay {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .strokeBorder(TransToolsTheme.accent.opacity(0.72), lineWidth: 2.4)
            }
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(TransToolsTheme.accent.opacity(0.12), lineWidth: 0.8)
                    .padding(4)
                    .allowsHitTesting(false)
            }
    }
}

struct FloatingSubtitleView: View {
    @ObservedObject var model: MeetingModel
    private var assistantVisible: Bool {
        get { model.subtitleAssistantVisible }
        nonmutating set { model.subtitleAssistantVisible = newValue }
    }
    @AppStorage("SubtitleQuickInputVisible") private var quickInputVisible = true
    @State private var hovered = false
    @State private var reviewing = false
    @State private var locked = false
    @State private var latestScrollRequest = UUID()
    @State private var followLatest = false
    @AppStorage("SubtitleHUDContext") private var showContext = true
    @AppStorage("SubtitleHUDMascot") private var showMascot = false

    // Appearance & Layout settings
    @AppStorage("SubtitleFontSize") private var fontSize = 18.0
    // The full subtitle board follows the white paper surface used by mini tools.
    // Keep this surface white regardless of the app's current appearance.
    private let light = true
    @AppStorage("SubtitleHUDOriginal") private var showOriginal = true
    @AppStorage("SubtitleHUDSide") private var side = false

    // Pacing & Rolling configuration
    @AppStorage("SubtitleRollingMode") private var rollingMode = true
    @AppStorage("LiveTranslationPacing") private var pacingMode = "balanced"

    // Hold time & presentation pacing state
    @State private var stableCaption: Caption? = nil
    @State private var holdUntil: Date = .distantPast
    @State private var holdTask: Task<Void, Never>? = nil

    private var ink: Color { light ? .primary : .white }

    init(model: MeetingModel) {
        self.model = model
    }

    // Calculate human-friendly hold time so eyes can easily finish reading
    private func holdDurationFor(caption: Caption) -> TimeInterval {
        let textCount = max(caption.original.count, caption.vietnamese.count)
        let baseMultiplier: Double
        let minHold: Double
        let maxHold: Double

        switch pacingMode {
        case "contextual":
            baseMultiplier = 16.0
            minHold = 3.6
            maxHold = 6.0
        case "fast":
            baseMultiplier = 24.0
            minHold = 1.6
            maxHold = 3.2
        default: // balanced
            baseMultiplier = 20.0
            minHold = 2.6
            maxHold = 4.8
        }
        let calculated = Double(textCount) / baseMultiplier + 1.2
        return min(maxHold, max(minHold, calculated))
    }

    // Resolves the most appropriate completed caption to display as the main stable row
    private func updatePacedCaptions() {
        if model.captions.isEmpty {
            holdTask?.cancel()
            stableCaption = nil
            holdUntil = .distantPast
            return
        }
        guard !reviewing else { holdTask?.cancel(); return }
        let candidate: Caption?
        if model.subtitleMode == .originalOnly {
            candidate = model.captions.last
        } else {
            // Advance the reader only to completed translations. When ASR revises
            // the live row its old translation is detached; keep the last finished
            // sentence on screen until the replacement is ready.
            candidate = CaptionPresentationPolicy.nextIndex(in: model.captions,
                currentID: followLatest ? nil : stableCaption?.id,
                id: { $0.id }, ready: { model.hasCurrentTranslation(for: $0) })
                .map { index in
                    let row = model.captions[index]
                    return row.id == stableCaption?.id && !model.hasCurrentTranslation(for: row) ? (stableCaption ?? row) : row
                }
        }

        guard let next = candidate else {
            if model.captions.isEmpty {
                stableCaption = nil
                holdUntil = .distantPast
            }
            return
        }

        if followLatest {
            holdTask?.cancel()
            stableCaption = next
            holdUntil = .distantPast
            return
        }

        // First caption
        if stableCaption == nil {
            stableCaption = next
            holdUntil = Date().addingTimeInterval(holdDurationFor(caption: next))
            return
        }

        // Same caption updated (e.g. translation just arrived or text grew)
        if stableCaption?.id == next.id {
            let wasIncomplete = (stableCaption?.vietnamese.isEmpty ?? true) && !next.vietnamese.isEmpty
            stableCaption = next
            if wasIncomplete {
                // Fresh translation arrived: guarantee reader has full hold time to digest it!
                holdUntil = Date().addingTimeInterval(holdDurationFor(caption: next))
            }
            return
        }

        // A new caption is ready to replace the current one
        let now = Date()
        if now >= holdUntil {
            // Old caption has been held long enough: smoothly advance!
            withAnimation(.easeInOut(duration: 0.22)) {
                stableCaption = next
            }
            holdUntil = now.addingTimeInterval(holdDurationFor(caption: next))
        } else {
            // Old caption is still within hold time: schedule advance when hold time elapses
            let remaining = holdUntil.timeIntervalSince(now)
            holdTask?.cancel()
            holdTask = Task { @MainActor in
                try? await Task.sleep(nanoseconds: UInt64(remaining * 1_000_000_000))
                guard !Task.isCancelled else { return }
                withAnimation(.easeInOut(duration: 0.22)) {
                    self.updatePacedCaptions()
                }
            }
        }
    }

    // Caption currently in-flight (being spoken or being translated)
    private var liveIncomingCaption: Caption? {
        guard let latest = model.captions.last else { return nil }
        guard let stable = stableCaption else { return nil }
        // ASR often revises the same live row ID. Surface its changing source as
        // the secondary line without replacing the reader's completed sentence.
        if latest.id != stable.id || latest.original != stable.original {
            return latest
        }
        return nil
    }

    private func closeAssistant() {
        assistantVisible = false
        model.setSubtitleAssistantExpanded(false)
    }

    public var body: some View {
        GeometryReader { geometry in
            let mascotVisible = showMascot && geometry.size.width >= 560
            let wide = geometry.size.width >= 880
            HStack(spacing: 0) {
              HStack(spacing: 0) {
                if mascotVisible {
                    MiniAvatarView(size: 76, style: model.mascotStyle,
                        isWorking: model.running, isHovered: false, activity: .writing, time: 0)
                        .accessibilityLabel(MascotIdentity.name)
                        .frame(width: 88)
                    Rectangle().fill(TransToolsTheme.accent.opacity(0.35)).frame(width: 1)
                }
                VStack(spacing: 0) {
                    if assistantVisible && !wide {
                        HStack {
                            Button("Phụ đề") { assistantVisible = false; model.setSubtitleAssistantExpanded(false) }
                            Text("Gợi ý").font(.caption.bold())
                            Spacer()
                            Button {
                                Task { if model.running { await model.stop() } else { await model.start() } }
                            } label: { Image(systemName: model.running ? "pause.fill" : "play.fill").frame(width: 28, height: 28) }
                            .disabled(model.busy).help(model.running ? "Dừng thu và lưu cuộc họp" : "Bắt đầu cuộc họp")
                            Button { model.hideOverlay() } label: { Image(systemName: "xmark").frame(width: 28, height: 28) }.help("Ẩn phụ đề nổi")
                        }.padding(8)
                        MeetingAssistBoard(model: model, embedded: true, isShown: model.isOverlayVisible, onClose: { closeAssistant() })
                    } else {
                        subtitleContent
                    }
                    Divider().overlay(TransToolsTheme.accent.opacity(0.25))
                    if quickInputVisible { SubtitleQuickComposer(model: model, store: model.subtitleQuick) }
                }
              }.frame(maxWidth: .infinity, maxHeight: .infinity)
              if assistantVisible && wide {
                Rectangle().fill(TransToolsTheme.accent.opacity(0.4)).frame(width: 1)
                MeetingAssistBoard(model: model, embedded: true, isShown: model.isOverlayVisible, onClose: { closeAssistant() })
                    .environment(\.colorScheme, light ? .light : .dark)
                    .frame(width: 340)
              }
            }
            .environment(\.colorScheme, light ? .light : .dark)
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .background { FullSubtitleBoardBackground() }
            .onAppear { model.setMascotInSubtitleHUD(mascotVisible && model.isOverlayVisible) }
            .onChange(of: mascotVisible) { _, value in
                model.setMascotInSubtitleHUD(value && model.isOverlayVisible)
            }
            .onChange(of: model.isOverlayVisible) { _, value in
                model.setMascotInSubtitleHUD(mascotVisible && value)
            }
            .onChange(of: model.meetingAssistantInSeparateWindow) { _, value in
                if value { closeAssistant() }
            }
        }
        .onDisappear { model.setMascotInSubtitleHUD(false) }
    }

    private var subtitleContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Top Toolbar: Live / Review indicator, Pacing badge & Controls
            HStack(spacing: 8) {
                Label(
                    reviewing ? "Xem lại" : (model.running ? "Theo dõi cuộc họp" : (model.captions.isEmpty ? "Chưa bắt đầu" : "Đã dừng")),
                    systemImage: reviewing ? "clock.arrow.circlepath" : (model.running ? "waveform" : "stop.circle")
                )
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(light ? TransToolsTheme.accent : Color(red: 0.65, green: 0.88, blue: 0.79))
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(TransToolsTheme.accent.opacity(light ? 0.10 : 0.25), in: Capsule())

                if !reviewing && model.running {
                    Text(followLatest ? "Câu mới nhất" : pacingBadgeTitle)
                        .font(.system(size: 9, weight: .medium))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(TransToolsTheme.accent.opacity(0.14))
                        .foregroundStyle(TransToolsTheme.accent)
                        .clipShape(Capsule())
                }

                Spacer()

                Button {
                    Task {
                        if model.running { await model.stop() }
                        else { await model.start() }
                    }
                } label: {
                    Label(model.running ? "Dừng" : "Bắt đầu", systemImage: model.running ? "stop.fill" : "play.fill")
                        .font(.system(size: 10, weight: .semibold))
                        .padding(.horizontal, 8)
                        .frame(height: 24)
                        .foregroundStyle(light ? TransToolsTheme.accent : Color(red: 0.65, green: 0.88, blue: 0.79))
                        .background(TransToolsTheme.accent.opacity(light ? 0.10 : 0.25), in: RoundedRectangle(cornerRadius: 6))
                        .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(TransToolsTheme.accent.opacity(0.35)))
                }
                .buttonStyle(.plain)
                .disabled(model.busy)

                .help(model.running ? "Dừng thu âm và dịch cuộc họp" : "Bắt đầu cuộc họp mới với nguồn đang chọn")

                HStack(spacing: 10) {
                    Button {
                        reviewing.toggle()
                    } label: {
                        Image(systemName: "clock.arrow.circlepath")
                    }
                    .help(reviewing ? "Trở lại phụ đề trực tiếp" : "Xem lại 30 câu gần nhất; cuộc họp vẫn tiếp tục thu")

                    Button {
                        if !assistantVisible { model.closeSeparateMeetingAssistant() }
                        assistantVisible.toggle()
                        model.setSubtitleAssistantExpanded(assistantVisible)
                    } label: {
                        AIActivitySymbol(store: model.meetingAssistantDraft, size: 14)
                            .frame(width: 28, height: 28)
                            .background(assistantVisible ? TransToolsTheme.accent.opacity(0.22) : Color.clear, in: RoundedRectangle(cornerRadius: 7))
                    }
                    .help(assistantVisible ? "Thu gọn trợ lý cuộc họp" : "Mở trợ lý ngay trong phụ đề")

                    Button {
                        quickInputVisible.toggle()
                        if quickInputVisible { model.ensureSubtitleComposerSpace() }
                    } label: { Image(systemName: "keyboard").frame(width: 28, height: 28) }
                    .help(quickInputVisible ? "Ẩn ô nhập nhanh" : "Mở ô nhập nhanh")

                    // Settings & Pacing menu
                    Menu {
                        Section("Nhịp độ hiển thị") {
                            Button {
                                setPacing("contextual")
                            } label: {
                                HStack {
                                    Text("Thong thả (Khuyên dùng)")
                                    if pacingMode == "contextual" { Image(systemName: "checkmark") }
                                }
                            }
                            Button {
                                setPacing("balanced")
                            } label: {
                                HStack {
                                    Text("Cân bằng (Mặc định)")
                                    if pacingMode == "balanced" { Image(systemName: "checkmark") }
                                }
                            }
                            Button {
                                setPacing("fast")
                            } label: {
                                HStack {
                                    Text("Nhanh (Bám sát)")
                                    if pacingMode == "fast" { Image(systemName: "checkmark") }
                                }
                            }
                        }

                        Section("Ngôn ngữ") {
                            Picker("Tiếng gốc", selection: $model.sourceLanguage) { ForEach(AppLanguage.allCases) { Text($0.displayName).tag($0) } }
                            Picker("Bản dịch", selection: $model.targetLanguage) { ForEach(AppLanguage.allCases) { Text($0.displayName).tag($0) } }
                            Picker("Hiển thị", selection: $model.subtitleMode) {
                                Text("Song ngữ").tag(SubtitleDisplayMode.bilingual)
                                Text("Tiếng gốc").tag(SubtitleDisplayMode.originalOnly)
                                Text("Bản dịch").tag(SubtitleDisplayMode.translationOnly)
                            }
                        }
                        Section("Bố cục & Hiển thị") {
                            Toggle("Mascot trong phụ đề", isOn: $showMascot)
                            Toggle("Hiện câu tiếp theo", isOn: $rollingMode)
                            Toggle("Hiện câu trước để giữ ngữ cảnh", isOn: $showContext)
                            Toggle("Hiện tiếng gốc", isOn: $showOriginal)
                            Label("Nền trắng như mini tool", systemImage: "sun.max.fill")
                            Button(side ? "Chuyển thành dải ngang" : "Chuyển thành khung bên cạnh") {
                                side.toggle()
                                model.resizeSubtitleHUD(side: side)
                            }
                            Button("Đặt phía trên màn hình") { model.positionOverlay(atTop: true) }
                            Button("Đặt phía dưới màn hình") { model.positionOverlay(atTop: false) }
                            Button(locked ? "Mở khóa vị trí" : "Khóa vị trí kéo thả") {
                                locked.toggle()
                                model.lockSubtitleHUD(locked)
                            }
                        }

                        Section("Cỡ chữ phụ đề") {
                            ForEach([15.0, 18.0, 21.0, 24.0], id: \.self) { size in
                                Button("Cỡ chữ \(Int(size)) pt") { fontSize = size }
                            }
                        }
                    } label: {
                        Image(systemName: "slider.horizontal.3")
                            .foregroundStyle(light ? TransToolsTheme.accent : Color(red: 0.55, green: 0.90, blue: 0.80))
                            .frame(width: 28, height: 28)
                            .background(TransToolsTheme.accent.opacity(0.18), in: RoundedRectangle(cornerRadius: 5))
                    }
                    .menuStyle(.borderlessButton)
                    .tint(TransToolsTheme.accent)
                    .environment(\.colorScheme, light ? .light : .dark)
                    .fixedSize()
                    .help("Cài đặt nhịp độ, cỡ chữ và vị trí")

                    Button { model.showMainWindowFromSubtitles() } label: { Image(systemName: "macwindow") }
                        .help("Mở cửa sổ chính")
                    Button { model.hideOverlay() } label: { Image(systemName: "xmark") }
                        .help("Ẩn phụ đề nổi")
                }
                .font(.system(size: 12))
                .buttonStyle(.plain)
                .foregroundStyle(ink.opacity(0.85))

            }
            .frame(height: 28)

            Divider().overlay(TransToolsTheme.accent.opacity(0.15))

            if reviewing {
                // REVIEW MODE: 30 past captions with comfortable manual scrolling
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        ForEach(Array(model.captions.suffix(30))) { row in
                            VStack(alignment: .leading, spacing: 4) {
                                if showOriginal || row.vietnamese.isEmpty {
                                    Text(row.original)
                                        .font(.system(size: max(12, fontSize - 3)))
                                        .foregroundStyle(ink.opacity(0.65))
                                }
                                if !row.vietnamese.isEmpty {
                                    Text(row.vietnamese)
                                        .font(.system(size: fontSize, weight: .medium))
                                        .foregroundStyle(ink)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            Divider().overlay(TransToolsTheme.accent.opacity(0.15))
                        }
                    }
                    .textSelection(.enabled)
                }
            } else {
                // PACED LIVE SUBTITLES
                ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 10) {
                        if let stable = stableCaption {
                            if showContext, let index = model.captions.firstIndex(where: { $0.id == stable.id }), index > 0 {
                                let previous = model.captions[index - 1]
                                Text(model.subtitleMode == .originalOnly || previous.vietnamese.isEmpty ? previous.original : previous.vietnamese)
                                    .font(.system(size: max(11, fontSize - 4)))
                                    .foregroundStyle(ink.opacity(0.55))
                                    .lineSpacing(3)
                                Divider().overlay(TransToolsTheme.accent.opacity(0.15))
                            }
                            // Primary Stable Sentence (Strictly paired original & translation)
                            VStack(alignment: .leading, spacing: 4) {
                                if showOriginal && model.subtitleMode != .translationOnly && model.subtitleMode != .originalOnly && !stable.original.isEmpty {
                                    Text(stable.original)
                                        .font(.system(size: max(12, fontSize - 3.5)))
                                        .foregroundStyle(ink.opacity(0.65))
                                        .lineSpacing(2)
                                }

                                if model.subtitleMode == .originalOnly {
                                    Text(stable.original)
                                        .font(.system(size: fontSize, weight: .medium))
                                        .foregroundStyle(ink)
                                        .lineSpacing(4)
                                } else if !stable.vietnamese.isEmpty {
                                    Text(stable.vietnamese)
                                        .font(.system(size: fontSize, weight: .medium))
                                        .foregroundStyle(ink)
                                        .lineSpacing(4)
                                } else {
                                    // Pending translation for first sentence
                                    HStack(spacing: 6) {
                                        Text(stable.original)
                                            .font(.system(size: fontSize, weight: .medium))
                                            .foregroundStyle(ink)
                                        ProgressView()
                                            .controlSize(.mini)
                                    }
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .transition(.opacity)

                            // Secondary Live Row: Next incoming sentence (Rolling mode)
                            if rollingMode, let live = liveIncomingCaption {
                                Divider()
                                    .overlay(TransToolsTheme.accent.opacity(0.20))
                                    .padding(.vertical, 1)

                                VStack(alignment: .leading, spacing: 3) {
                                    HStack(spacing: 5) {
                                        Circle()
                                            .fill(TransToolsTheme.accent)
                                            .frame(width: 5, height: 5)
                                        Text("Tiếp theo:")
                                            .font(.system(size: 9.5, weight: .bold))
                                            .foregroundStyle(TransToolsTheme.accent)
                                        Spacer()
                                    }

                                    if showOriginal && !live.original.isEmpty {
                                        Text(live.original)
                                            .font(.system(size: max(11, fontSize - 4.5)))
                                            .foregroundStyle(ink.opacity(0.70))
                                            .fixedSize(horizontal: false, vertical: true)
                                    }

                                    if !live.vietnamese.isEmpty {
                                        HStack(alignment: .firstTextBaseline, spacing: 5) {
                                            Text(live.vietnamese)
                                                .font(.system(size: max(13, fontSize - 2), weight: .medium))
                                                .foregroundStyle(TransToolsTheme.accent)
                                                .fixedSize(horizontal: false, vertical: true)
                                            if !model.hasCurrentTranslation(for: live) {
                                                ProgressView().controlSize(.mini).scaleEffect(0.65)
                                                    .help("Đang cập nhật bản dịch")
                                            }
                                        }
                                        .fixedSize(horizontal: false, vertical: true)
                                    } else {
                                        Text("Đang dịch…")
                                            .font(.system(size: 10, weight: .regular))
                                            .foregroundStyle(ink.opacity(0.45))
                                    }
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .transition(.opacity)
                            }
                        } else {
                            // Empty state
                            HStack(spacing: 8) {
                                if model.running {
                                    ProgressView()
                                        .controlSize(.small)
                                    Text("Đang lắng nghe cuộc họp…")
                                        .font(.system(size: 14, weight: .medium))
                                        .foregroundStyle(ink.opacity(0.70))
                                } else {
                                    Image(systemName: "captions.bubble")
                                        .font(.system(size: 16))
                                        .foregroundStyle(TransToolsTheme.accent)
                                    Text("Phụ đề sẽ hiển thị khi cuộc họp bắt đầu")
                                        .font(.system(size: 13.5))
                                        .foregroundStyle(ink.opacity(0.65))
                                }
                            }
                            .padding(.vertical, 8)
                        }
                        Color.clear.frame(height: 1).id("HUD_LATEST_CAPTION")
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .background(GeometryReader { content in
                        Color.clear.preference(key: SubtitleContentSizeKey.self, value: content.size)
                    })
                }
                .onPreferenceChange(SubtitleContentSizeKey.self) { _ in
                    // Text wrapping and late translations change the document height
                    // after the caption update. Follow the measured layout, not a timer.
                    guard !reviewing else { return }
                    DispatchQueue.main.async {
                        proxy.scrollTo("HUD_LATEST_CAPTION", anchor: .bottom)
                    }
                }
                .background(GeometryReader { viewport in
                    Color.clear.onChange(of: viewport.size) { _, _ in
                        latestScrollRequest = UUID()
                    }
                })
                .onAppear { latestScrollRequest = UUID() }
                .task(id: latestScrollRequest) {
                    // scrollTo during onChange can see the previous AppKit layout.
                    // Cancel outdated requests and wait one layout pass for new text height.
                    do { try await Task.sleep(for: .milliseconds(30)) }
                    catch { return }
                    guard !Task.isCancelled, !reviewing else { return }
                    proxy.scrollTo("HUD_LATEST_CAPTION", anchor: .bottom)
                }
                .onChange(of: stableCaption) { _, _ in
                    latestScrollRequest = UUID()
                }
                .onChange(of: liveIncomingCaption) { _, _ in
                    latestScrollRequest = UUID()
                }
                }
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

        .onHover { hovered = $0 }
        .animation(nil, value: hovered)
        .padding(4)
        .enableAppleTranslationSession(source: model.sourceLanguage, target: model.targetLanguage)
        .onAppear {
            setPacing(pacingMode)
            updatePacedCaptions()
        }
        .onChange(of: model.captions) { _, _ in
            // Translations can finish for a row before the latest live row.
            updatePacedCaptions()
        }
        .onChange(of: reviewing) { _, value in
            if value { holdTask?.cancel() }
            else { returnToLive() }
        }
        .onDisappear { holdTask?.cancel() }

    }

    private func returnToLive() {
        reviewing = false
        followLatest = true
        holdTask?.cancel()
        stableCaption = nil
        holdUntil = .distantPast
        updatePacedCaptions()
        latestScrollRequest = UUID()
    }

    private var pacingBadgeTitle: String {
        switch pacingMode {
        case "contextual": return "Nhịp thong thả 🌱"
        case "fast": return "Nhịp nhanh ⚡️"
        default: return "Nhịp cân bằng ⚖️"
        }
    }

    private func setPacing(_ mode: String) {
        followLatest = false
        pacingMode = mode
        switch mode {
        case "contextual":
            model.liveTranslationPacing = .contextual
        case "fast":
            model.liveTranslationPacing = .fast
        default:
            model.liveTranslationPacing = .balanced
        }
    }
}

// Backward-compatibility alias
typealias OverlayView = FloatingSubtitleView
