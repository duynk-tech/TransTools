import SwiftUI
import Combine

@MainActor final class MascotQuickSubtitleController {
    private weak var model: MeetingModel?
    private var panel: NSPanel?
    private var subscriptions = Set<AnyCancellable>()
    private var geometryObservers: [NSObjectProtocol] = []
    private var dismissed = false
    private var manuallyOpened = false
    private var suspendedForMascotMenu = false
    private var orbitResumeWorkItem: DispatchWorkItem?
    var isVisible: Bool { panel?.isVisible == true }

    func showCompact() {
        guard let model else { return }
        model.miniTools.hide()
        manuallyOpened = true; dismissed = false
        model.hideOverlay()
        model.showFloatingMascot()
        // A selection from the orbit arrives before AppKit finishes resizing
        // the mascot window. Keep the subtitle hidden until the settled-layout
        // work item scheduled when the orbit closes has run.
        guard !suspendedForMascotMenu else { return }
        orbitResumeWorkItem?.cancel(); orbitResumeWorkItem = nil
        refresh()
    }
    func hideCompact() {
        orbitResumeWorkItem?.cancel(); orbitResumeWorkItem = nil
        suspendedForMascotMenu = false
        manuallyOpened = false; dismissed = true; hidePanel()
    }
    func suspendForMascotMenu() {
        orbitResumeWorkItem?.cancel(); orbitResumeWorkItem = nil
        suspendedForMascotMenu = true
        hidePanel()
    }
    func resumeAfterMascotMenu() {
        orbitResumeWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.suspendedForMascotMenu else { return }
            self.suspendedForMascotMenu = false
            self.refresh()
        }
        orbitResumeWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.34, execute: work)
    }
    private func hidePanel() {
        if let panel { panel.parent?.removeChildWindow(panel); panel.orderOut(nil) }
    }
    private let content = MascotQuickSubtitleContent()

    func connect(_ model: MeetingModel) {
        guard self.model == nil else { return }
        self.model = model
        // Keep the mascot subtitle in step with the main HUD. A throttle here
        // added avoidable lag after caption or translation updates arrived.
        model.$captions.receive(on: RunLoop.main)
            .sink { [weak self] rows in self?.updateCaption(rows) }.store(in: &subscriptions)
        Publishers.MergeMany(model.$running.map { _ in () }.eraseToAnyPublisher(),
                            model.$busy.map { _ in () }.eraseToAnyPublisher(),
                            model.$isOverlayVisible.map { _ in () }.eraseToAnyPublisher(),
                            model.$isFloatingMascotVisible.map { _ in () }.eraseToAnyPublisher(),
                            model.$subtitleMode.map { _ in () }.eraseToAnyPublisher())
            .receive(on: RunLoop.main).sink { [weak self] in self?.refresh() }.store(in: &subscriptions)
        model.$running.dropFirst().sink { [weak self] running in if running { self?.dismissed = false; self?.content.caption = nil } }.store(in: &subscriptions)
        for notification in [NSWindow.didMoveNotification, NSWindow.didResizeNotification, NSWindow.didChangeScreenNotification] {
            geometryObservers.append(NotificationCenter.default.addObserver(forName: notification, object: nil, queue: .main) { [weak self] event in
                MainActor.assumeIsolated {
                    guard let self, self.isVisible, let window = event.object as? NSWindow,
                          window === self.model?.mascotWindow else { return }
                    self.position()
                }
            })
        }
    }

    private func updateCaption(_ rows: [Caption]) {
        guard let model else { return }
        guard let row = rows.last(where: { !$0.original.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) else {
            content.caption = nil; content.translationPending = false; refresh(); return
        }
        if content.caption?.id != row.id { content.caption = row }
        else if content.caption != row { content.caption = row }
        content.translationPending = model.running && model.subtitleMode != .originalOnly
            && !model.hasCurrentTranslation(for: row)
        refresh()
    }

    func refresh() {
        guard let model else { return }
        let enabled = UserDefaults.standard.object(forKey: "MascotQuickSubtitleEnabled") as? Bool ?? true
        guard !suspendedForMascotMenu, (enabled || manuallyOpened), !dismissed, (model.running || manuallyOpened), !model.isOverlayVisible,
              model.isFloatingMascotVisible, model.mascotWindow?.isVisible == true else {
            hidePanel()
            return
        }
        if content.running != model.running { content.running = model.running }
        let starting = model.busy && !model.running
        if content.starting != starting { content.starting = starting }
        if content.mode != model.subtitleMode { content.mode = model.subtitleMode }
        if let row = content.caption {
            content.translationPending = model.running && model.subtitleMode != .originalOnly
                && !model.hasCurrentTranslation(for: row)
        }
        if panel == nil {
            let window = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 480, height: 126),
                                 styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            window.title = "Phụ đề nhanh trên mascot"
            window.identifier = NSUserInterfaceItemIdentifier("mascot-quick-subtitle")
            window.level = .floating
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            window.isOpaque = false; window.backgroundColor = .clear
            window.hasShadow = false; window.hidesOnDeactivate = false
            window.isReleasedWhenClosed = false
            window.contentView = NSHostingView(rootView: MascotQuickSubtitleView(content: content, model: model,
                open: { [weak model] in model?.showOverlay() },
                stop: { [weak model] in Task {
                    guard let model else { return }
                    if model.running { await model.stop() } else { await model.startFromMascot() }
                } },
                hide: { [weak self] in self?.hideCompact() }))
            panel = window
        }
        if let panel, let mascot = model.mascotWindow, panel.parent !== mascot {
            panel.parent?.removeChildWindow(panel)
            mascot.addChildWindow(panel, ordered: .above)
        }
        position()
        if panel?.isVisible != true { panel?.orderFrontRegardless() }
    }

    private func position() {
        guard let panel, let mascot = model?.mascotWindow else { return }
        let placement = MascotSubtitlePlacement.resolve(
            mascotFrame: mascot.frame, headBounds: model?.mascotHeadBounds,
            screen: mascot.screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? mascot.frame)
        let frame = placement.frame
        if panel.frame != frame { panel.setFrame(frame, display: true) }
    }
}

struct MascotSubtitlePlacement {
    let frame: CGRect
    let arrowBelow: Bool
    let arrowX: CGFloat

    static func resolve(mascotFrame: CGRect, headBounds: CGRect?, screen: CGRect) -> Self {
        let width = min(480, max(240, screen.width - 16)), height: CGFloat = 126
        let headX = mascotFrame.minX + (headBounds?.midX ?? mascotFrame.width / 2)
        let headY = headBounds.map { mascotFrame.maxY - $0.minY } ?? (mascotFrame.minY + 84)
        let feetY = headBounds.map { mascotFrame.maxY - $0.maxY } ?? mascotFrame.minY
        let above = headY + 4
        let below = above + height > screen.maxY - 8
        let y = below ? feetY - height - 4 : above
        let preferredX = headX - width / 2
        let safeMinX = screen.minX + 8
        let safeMaxX = screen.maxX - width - 8
        let arrowAlignedMinX = max(safeMinX, headX - (width - 24))
        let arrowAlignedMaxX = min(safeMaxX, headX - 24)
        let frameX = arrowAlignedMinX <= arrowAlignedMaxX
            ? min(max(preferredX, arrowAlignedMinX), arrowAlignedMaxX)
            : max(safeMinX, min(preferredX, safeMaxX))
        let frame = CGRect(x: frameX,
                           y: max(screen.minY + 8, min(y, screen.maxY - height - 8)), width: width, height: height)
        return Self(frame: frame, arrowBelow: !below, arrowX: headX - frame.minX)
    }
}

@MainActor final class MascotQuickSubtitleContent: ObservableObject {
    @Published var running = false
    @Published var starting = false
    @Published var caption: Caption?
    @Published var translationPending = false
    @Published var mode: SubtitleDisplayMode = .bilingual
}

private struct MascotQuickSubtitleView: View {
    @ObservedObject var content: MascotQuickSubtitleContent
    @ObservedObject var model: MeetingModel
    let open: () -> Void
    let stop: () -> Void
    let hide: () -> Void
    @State private var hovered = false
    private var ink: Color { Color(red: 0.12, green: 0.18, blue: 0.17) }
    private let mintInk = TransToolsTheme.accent
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "captions.bubble")
                    .font(.system(size: 14, weight: .semibold)).foregroundStyle(mintInk)
                Text("Phụ đề nhanh").font(.system(size: 14, weight: .semibold)).foregroundStyle(ink)
                Text(content.starting ? "Đang kết nối…" : (content.running ? "Đang nghe" : (content.caption == nil ? "Chưa bắt đầu" : "Đã dừng")))
                    .font(.system(size: 10, weight: .medium)).foregroundStyle(mintInk.opacity(0.82))
                Spacer()
                HStack(spacing: 2) {
                    Button(action: stop) { Image(systemName: content.running ? "stop.fill" : "play.fill").frame(width: 28, height: 28) }
                        .buttonStyle(MiniToolHUDIconButtonStyle(light: true))
                        .disabled(content.starting)
                        .help(content.running ? "Dừng cuộc họp và lưu bản ghi" : "Bắt đầu cuộc họp")
                    Button(action: open) { Image(systemName: "arrow.up.left.and.arrow.down.right").frame(width: 28, height: 28) }
                        .buttonStyle(MiniToolHUDIconButtonStyle(light: true)).help("Mở phụ đề đầy đủ")
                    Button(action: hide) { Image(systemName: "xmark").frame(width: 28, height: 28) }
                        .buttonStyle(MiniToolHUDIconButtonStyle(light: true, close: true))
                        .help("Ẩn thanh phụ đề trong phiên này").accessibilityLabel("Ẩn phụ đề nhanh")
                }
            }
            .frame(height: 28)
            .padding(.leading, 16).padding(.trailing, 16)
            .padding(.top, 6).padding(.bottom, 8)
            Divider().overlay(mintInk.opacity(0.20))
            if let row = content.caption {
                ScrollView(.vertical) {
                    VStack(alignment: .leading, spacing: 4) {
                        if content.mode != .translationOnly {
                            Text(row.original).font(.system(size: content.mode == .bilingual ? 12 : 16, weight: .medium))
                                .foregroundStyle(ink.opacity(content.mode == .bilingual ? 0.65 : 1))
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        if content.mode != .originalOnly {
                            if row.vietnamese.isEmpty {
                                Text(content.running ? "Đang dịch…" : "Chưa có bản dịch")
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundStyle(mintInk.opacity(0.68))
                            } else {
                                HStack(alignment: .firstTextBaseline, spacing: 5) {
                                    Text(row.vietnamese)
                                        .font(.system(size: 16, weight: .semibold))
                                        .foregroundStyle(mintInk)
                                        .fixedSize(horizontal: false, vertical: true)
                                    if content.translationPending {
                                        ProgressView().controlSize(.mini).scaleEffect(0.65)
                                            .help("Đang cập nhật bản dịch")
                                    }
                                }
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16).padding(.vertical, 8)
                    .contentShape(Rectangle()).onTapGesture(perform: open)
                }
                .scrollIndicators(.visible)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                Text(content.starting ? "Đang kết nối nguồn âm thanh…" : (content.running ? "Đang chờ lời nói…" : "Bấm Bắt đầu để hiện phụ đề"))
                    .font(.system(size: 12, weight: .medium)).foregroundStyle(ink.opacity(0.65))
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                    .padding(.horizontal, 16).padding(.vertical, 9)
            }
        }
        .background { MiniToolPanelBackground() }
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .environment(\.colorScheme, .light)
        .buttonStyle(.plain)
        .foregroundStyle(mintInk)
        .contentShape(Rectangle())
        .onHover { hovered = $0 }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Phụ đề nhanh trên mascot")
        .enableAppleTranslationSession(
            // Keep Apple's native session mounted while this mini HUD is idle.
            // Mascot-started meetings hide the dashboard, so waiting until
            // `running` becomes true can make the first live captions pay the
            // TranslationSession setup cost on the critical path.
            when: model.provider == .apple,
            source: model.sourceLanguage,
            target: model.targetLanguage
        )
    }
}

struct MascotSubtitleBubble: InsettableShape {
    var arrowX: CGFloat
    let arrowBelow: Bool
    var insetAmount: CGFloat = 0

    func inset(by amount: CGFloat) -> some InsettableShape { insetted(by: amount) }

    func insetted(by amount: CGFloat) -> MascotSubtitleBubble {
        var shape = self
        shape.insetAmount += amount
        shape.arrowX = max(0, shape.arrowX - amount)
        return shape
    }

    func tailTip(in inputRect: CGRect) -> CGPoint {
        let rect = inputRect.insetBy(dx: insetAmount, dy: insetAmount)
        let x = rect.minX + min(max(arrowX, 24), rect.width - 24)
        return CGPoint(x: x, y: arrowBelow ? rect.maxY : rect.minY)
    }

    func path(in rect: CGRect) -> Path {
        let rect = rect.insetBy(dx: insetAmount, dy: insetAmount)
        let r: CGFloat = 12, bodyBottom = rect.maxY - 10
        let left = rect.minX, right = rect.maxX, top = rect.minY
        let x = rect.minX + min(max(arrowX, 24), rect.width - 24)
        var p = Path()
        p.move(to: CGPoint(x: left + r, y: top))
        p.addLine(to: CGPoint(x: right - r, y: top))
        p.addQuadCurve(to: CGPoint(x: right, y: top + r), control: CGPoint(x: right, y: top))
        p.addLine(to: CGPoint(x: right, y: bodyBottom - r))
        p.addQuadCurve(to: CGPoint(x: right - r, y: bodyBottom), control: CGPoint(x: right, y: bodyBottom))
        p.addLine(to: CGPoint(x: x + 9, y: bodyBottom))
        p.addLine(to: CGPoint(x: x, y: rect.maxY))
        p.addLine(to: CGPoint(x: x - 9, y: bodyBottom))
        p.addLine(to: CGPoint(x: left + r, y: bodyBottom))
        p.addQuadCurve(to: CGPoint(x: left, y: bodyBottom - r), control: CGPoint(x: left, y: bodyBottom))
        p.addLine(to: CGPoint(x: left, y: top + r))
        p.addQuadCurve(to: CGPoint(x: left + r, y: top), control: CGPoint(x: left, y: top))
        p.closeSubpath()
        return arrowBelow ? p : p.applying(CGAffineTransform(a: 1, b: 0, c: 0, d: -1, tx: 0, ty: rect.minY + rect.maxY))
    }
}
