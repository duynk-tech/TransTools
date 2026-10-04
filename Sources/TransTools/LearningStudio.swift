import SwiftUI
import AppKit

final class LearningCoach: ObservableObject {
    static let shared = LearningCoach()
    @Published var reactionAt = Date.distantPast
    @Published var symbol = "A"
    @Published var reading = ""
    @Published var detail = ""
    @Published var position = 1
    @Published var total = 26
    @Published var language: LearningLanguage = .english
    var previous: () -> Void = {}
    var next: () -> Void = {}
    var listen: () -> Void = {}

    func configure(symbol: String, reading: String, detail: String, position: Int, total: Int,
                   language: LearningLanguage, previous: @escaping () -> Void,
                   next: @escaping () -> Void, listen: @escaping () -> Void) {
        reactionAt = Date()
        self.symbol = symbol; self.reading = reading; self.detail = detail
        self.position = position; self.total = total; self.language = language
        self.previous = previous; self.next = next; self.listen = listen
    }
}

struct LearningStudioView<Content: View>: View {
    let language: LearningLanguage
    @ObservedObject var model: MeetingModel
    @ViewBuilder let content: () -> Content
    @State private var guided = false

    private var subtitle: String {
        switch language {
        case .english: return "Latin A–Z · tên chữ, phiên âm và luyện viết"
        case .japanese: return "Kana · Hiragana, Katakana và các nhóm âm"
        case .chinese: return "Pinyin · thanh mẫu, vận mẫu và thanh điệu"
        case .korean: return "Hangeul · phụ âm, nguyên âm và ghép âm tiết"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .center, spacing: 20) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("Nền tảng · \(language.displayName)").font(.system(size: 22, weight: .bold))
                    Text(subtitle).font(.callout).foregroundStyle(.secondary)
                }
                Spacer(minLength: 12)
                HStack(spacing: 4) {
                    modeButton("Tự học", icon: "square.grid.2x2", active: !guided) { LearningCoachWindow.shared.close(); guided = false }
                    modeButton("Cùng Chip Chip", icon: "graduationcap", active: guided) {
                        guided = true
                        LearningCoachWindow.shared.show(model: model, onClose: { guided = false })
                    }
                }
                .padding(4)
                .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 14))
            }
            content().frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .controlSize(.large)
        .onDisappear {
            // Release closures capturing a lesson after leaving the workspace.
            LearningCoachWindow.shared.close()
            LearningCoach.shared.previous = {}; LearningCoach.shared.next = {}; LearningCoach.shared.listen = {}
        }
    }

    private func modeButton(_ title: String, icon: String, active: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: icon).font(.system(size: 12, weight: .semibold))
                .padding(.horizontal, 14).padding(.vertical, 10)
                .background(active ? Color(nsColor: .controlBackgroundColor) : .clear, in: RoundedRectangle(cornerRadius: 10))
                .foregroundStyle(active ? TransToolsTheme.accent : .secondary)
        }.buttonStyle(.plain)
    }
}

struct LearningSourceSheet: View {
    let language: LearningLanguage
    var japaneseKatakana = false
    private var url: URL {
        switch language {
        case .english: return URL(string: "https://dictionary.cambridge.org/pronunciation/english/")!
        case .japanese: return japaneseKatakana ? JapaneseNHKData.nhkKatakanaURL : JapaneseNHKData.nhkHiraganaURL
        case .chinese: return ChinesePinyinData.zimPinyinURL
        case .korean: return URL(string: "https://nuri.iksi.or.kr/practice/learningKoreanPronunciation/kor/index.html")!
        }
    }
    var body: some View {
        PronunciationSourceView(url: url, title: "Nguồn học · \(language.displayName)",
            guidance: "Chưa có bản ghi offline cho âm này. Chọn đúng ký tự trên trang nguồn để nghe; app không dùng giọng hệ thống thay thế.")
    }
}

/// A whiteboard attached to the existing desktop mascot, active only during learning.
private struct LearningBoardDragHandle: NSViewRepresentable {
    final class HandleView: NSView {
        override func mouseDown(with event: NSEvent) {
            window?.performDrag(with: event)
        }
        override func resetCursorRects() {
            addCursorRect(bounds, cursor: .openHand)
        }
    }
    func makeNSView(context: Context) -> HandleView { HandleView() }
    func updateNSView(_ nsView: HandleView, context: Context) {}
}

private final class LearningBoardPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

@MainActor
final class LearningCoachWindow: NSObject, NSWindowDelegate {
    static let shared = LearningCoachWindow()
    private var panel: NSPanel?
    private weak var model: MeetingModel?
    private var mascotWasVisible = false
    private var mainWasVisible = false
    private var onClose: (() -> Void)?
    private var observers: [NSObjectProtocol] = []

    func show(model: MeetingModel, onClose: @escaping () -> Void) {
        if let panel { panel.makeKeyAndOrderFront(nil); return }
        self.model = model
        self.onClose = onClose
        mainWasVisible = model.mainWindow?.isVisible == true
        mascotWasVisible = model.isFloatingMascotVisible
        model.beginChipChipLearning()
        let window = LearningBoardPanel(contentRect: NSRect(x: 0, y: 0, width: 660, height: 540),
            styleMask: [.borderless], backing: .buffered, defer: false)
        window.title = "Cùng Chip Chip"
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = true
        window.level = .floating
        window.hidesOnDeactivate = false
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.contentView = NSHostingView(rootView: ChipChipWhiteboard(onClose: { self.close() }))
        panel = window
        positionBoard()
        if let mascot = model.mascotWindow {
            for name in [NSWindow.didMoveNotification, NSWindow.didResizeNotification] {
                observers.append(NotificationCenter.default.addObserver(forName: name, object: mascot, queue: .main) { [weak self] _ in
                    MainActor.assumeIsolated { self?.positionBoard() }
                })
            }
        }
        window.makeKeyAndOrderFront(nil)
        model.mainWindow?.orderOut(nil)
    }

    private func positionBoard() {
        guard let panel, let mascot = model?.mascotWindow else { return }
        let screen = mascot.screen ?? NSScreen.main
        guard let visible = screen?.visibleFrame else { return }
        let rect = mascot.frame
        let width = panel.frame.width, height = panel.frame.height
        let right = rect.maxX + 12
        let x = right + width <= visible.maxX ? right : rect.minX - width - 12
        panel.setFrameOrigin(NSPoint(x: max(visible.minX + 8, min(x, visible.maxX - width - 8)),
            y: max(visible.minY + 8, min(visible.midY - height / 2 + 30, visible.maxY - height - 8))))
    }
    func close() {
        guard let panel else { return }
        panel.close()
    }
    func windowWillClose(_ notification: Notification) {
        for observer in observers { NotificationCenter.default.removeObserver(observer) }
        observers = []
        panel = nil
        model?.endChipChipLearning(hideMascot: !mascotWasVisible)
        if mainWasVisible { model?.showMainWindow() }
        mainWasVisible = false
        model = nil
        let callback = onClose; onClose = nil
        callback?()
        LanguagePronunciationService.shared.stop()
    }
}

struct ChipChipWhiteboard: View {
    @ObservedObject private var coach = LearningCoach.shared
    @ObservedObject private var audio = LanguagePronunciationService.shared
    let onClose: () -> Void
    var body: some View {
        VStack(spacing: 14) {
            HStack {
                Label("Cùng Chip Chip", systemImage: "graduationcap.fill")
                    .font(.headline).foregroundStyle(TransToolsTheme.accent)
                Spacer()
                Text("\(coach.position) / \(coach.total)")
                    .font(.caption.weight(.semibold)).monospacedDigit()
                    .padding(.horizontal, 10).padding(.vertical, 5)
                    .background(TransToolsTheme.accent.opacity(0.08), in: Capsule())
            }
            .overlay(LearningBoardDragHandle().accessibilityLabel("Kéo để di chuyển bảng"))
            HStack {
                Text(coach.language.displayName).font(.caption.weight(.semibold)).foregroundStyle(TransToolsTheme.accent)
                Spacer()
                Text(audio.isSpeaking ? "Đang nghe mẫu…" : "Nghe · Nhắc lại · Viết").font(.caption).foregroundStyle(.secondary)
            }
            ProgressView(value: Double(coach.position), total: Double(max(1, coach.total)))
                .tint(TransToolsTheme.accent).accessibilityLabel("Tiến trình bài học")
            ScrollView {
                VStack(spacing: 16) {
                    Text(coach.symbol)
                        .font(.system(size: coach.symbol.count > 3 ? 54 : 84, weight: .medium))
                        .frame(maxWidth: .infinity, minHeight: 120)
                        .accessibilityLabel("Chữ đang học: \(coach.symbol)")
                    Text(coach.reading).font(.title3.weight(.medium))
                        .foregroundStyle(TransToolsTheme.accent)
                        .fixedSize(horizontal: false, vertical: true)
                    VStack(alignment: .leading, spacing: 8) {
                        Label("Gợi ý luyện tập", systemImage: "lightbulb")
                            .font(.caption.weight(.semibold)).foregroundStyle(TransToolsTheme.accent)
                        Text(coach.detail).font(.callout).lineSpacing(4)
                            .fixedSize(horizontal: false, vertical: true)
                    }.frame(maxWidth: .infinity, alignment: .leading).padding(12)
                }.frame(maxWidth: .infinity).padding(.bottom, 8)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .layoutPriority(1)
            .id(coach.position)
            Divider()
            HStack(spacing: 10) {
                Button(action: coach.previous) { Image(systemName: "chevron.left") }.disabled(coach.position <= 1).help("Chữ trước")
                Button(action: coach.listen) { Label("Nghe mẫu", systemImage: "speaker.wave.2.fill") }
                    .buttonStyle(TransToolsActionButtonStyle(prominent: true)).tint(TransToolsTheme.accent)
                Button { audio.stop() } label: { Image(systemName: "stop.fill") }.disabled(!audio.isSpeaking && !audio.isPlayingSequence).help("Dừng")
                Button(action: coach.next) { Image(systemName: "chevron.right") }.disabled(coach.position >= coach.total).help("Chữ tiếp")
                Spacer()
                Button("Kết thúc", action: onClose)
            }.controlSize(.large).fixedSize(horizontal: false, vertical: true)
            if let error = audio.error { Text(error).font(.caption).foregroundStyle(.red) }
        }.padding(28)
        .background {
            ZStack {
                Color(nsColor: .textBackgroundColor)
                Canvas { context, size in
                    var grid = Path()
                    for x in stride(from: CGFloat(0), through: size.width, by: 24) {
                        grid.move(to: CGPoint(x: x, y: 0)); grid.addLine(to: CGPoint(x: x, y: size.height))
                    }
                    for y in stride(from: CGFloat(0), through: size.height, by: 24) {
                        grid.move(to: CGPoint(x: 0, y: y)); grid.addLine(to: CGPoint(x: size.width, y: y))
                    }
                    context.stroke(grid, with: .color(TransToolsTheme.accent.opacity(0.1)), lineWidth: 0.6)
                }.accessibilityHidden(true)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .overlay {
            RoundedRectangle(cornerRadius: 20).strokeBorder(
                LinearGradient(colors: [Color(red: 0.66, green: 0.79, blue: 0.75), Color(red: 0.32, green: 0.53, blue: 0.49)], startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 8)
                .allowsHitTesting(false)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 14).inset(by: 8)
                .stroke(Color.black.opacity(0.12), lineWidth: 1).allowsHitTesting(false)
        }
    }
}
