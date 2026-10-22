import SwiftUI
import AppKit

enum MascotMiniTool: Int, CaseIterable, Identifiable {
    case translation = 2, reader = 6, conversation = 5, notebook = 1, learning = 3, settings = 4
    var id: Int { rawValue }
    var title: String {
        switch self {
        case .translation: return "Dịch nhanh"
        case .reader: return "Đọc văn bản"
        case .conversation: return "Trò chuyện"
        case .notebook: return "Sổ tay"
        case .learning: return "Ôn nhanh"
        case .settings: return "Tùy chọn nhanh"
        }
    }
    var icon: String {
        switch self {
        case .translation: return "character.bubble"
        case .reader: return "speaker.wave.2"
        case .conversation: return "bubble.left.and.bubble.right"
        case .notebook: return "book.closed"
        case .learning: return "graduationcap"
        case .settings: return "gearshape"
        }
    }
    var defaultPanelSize: CGSize {
        CGSize(width: 440, height: self == .conversation ? 720 : 320)
    }
}

/// Keeps the taller conversation layout isolated from each user's normal mini-tool size.
struct MascotMiniToolSizeTransition {
    let size: CGSize
    let conversationRestoreHeight: CGFloat?

    static func applying(currentSize: CGSize, from previousTool: MascotMiniTool,
                         to nextTool: MascotMiniTool, restoreHeight: CGFloat?) -> Self {
        var size = currentSize
        var nextRestoreHeight = restoreHeight
        if previousTool != .conversation && nextTool == .conversation {
            nextRestoreHeight = currentSize.height
            size.height = max(currentSize.height, MascotMiniTool.conversation.defaultPanelSize.height)
        } else if previousTool == .conversation && nextTool != .conversation {
            if let restoreHeight { size.height = restoreHeight }
            nextRestoreHeight = nil
        }
        return Self(size: size, conversationRestoreHeight: nextRestoreHeight)
    }
}

@MainActor final class MascotMiniToolsState: ObservableObject {
    @Published var tool: MascotMiniTool = .translation
    let translation = SubtitleQuickStore()
    @Published var conversationInput = ""
    let readerPlaybackID = UUID()
    @Published var readerText = ""
    @Published var readerLanguage: AppLanguage = .vietnamese
    @Published var notebookSelection: UUID?
    @Published var arrowEdge: MascotMiniToolArrowEdge = .left
    @Published var arrowOffset: CGFloat = 175
}

enum MascotMiniToolArrowEdge { case top, bottom, left, right }

/// Quiet, consistent card and input chrome shared by every compact tool.
enum MiniToolSurfaceStyle {
    static func fill(light: Bool, emphasized: Bool = false) -> Color {
        TransToolsTheme.accent.opacity(emphasized ? (light ? 0.10 : 0.16) : (light ? 0.045 : 0.075))
    }
    static func border(light: Bool, emphasized: Bool = false) -> Color {
        TransToolsTheme.accent.opacity(emphasized ? (light ? 0.40 : 0.44) : (light ? 0.16 : 0.20))
    }
    static func inputBorder(light: Bool) -> Color {
        TransToolsTheme.accent.opacity(light ? 0.22 : 0.26)
    }
}

private final class MascotToolPanel: NSPanel {
    var onClose: (() -> Void)?
    override func close() { onClose?(); orderOut(nil) }
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

@MainActor final class MascotMiniToolsController {
    let state = MascotMiniToolsState()
    private var panel: NSPanel?
    private weak var model: MeetingModel?
    private var geometryObservers: [NSObjectProtocol] = []
    private var placementRefreshWorkItem: DispatchWorkItem?
    private var placementStableAfter = Date.distantPast
    private var panelTool: MascotMiniTool?
    private var heightBeforeConversation: CGFloat?
    private var preferredPanelSize: CGSize?
    private var applyingProgrammaticFrame = false
    private var lastProgrammaticFrameSize: CGSize?
    var mascotFacingTowardPanel: MascotFacing? {
        guard panel?.isVisible == true else { return nil }
        switch state.arrowEdge {
        case .left: return .frontRight
        case .right: return .frontLeft
        case .top, .bottom: return .front
        }
    }
    func show(_ tool: MascotMiniTool, model: MeetingModel) {
        observeMascotGeometry(for: model)
        self.model = model
        state.translation.cancel()
        state.tool = tool
        model.mascotQuickSubtitle.hideCompact()
        model.hideOverlay()
        ConversationMiniChat.shared.hide()
        model.mainWindow?.orderOut(nil)
        if panel == nil {
            preferredPanelSize = tool.defaultPanelSize
            let placement = MascotMiniToolPlacement.resolve(
                mascotFrame: placementAnchor(for: model),
                screen: model.mascotWindow?.screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? .zero,
                preferredSize: preferredPanelSize ?? tool.defaultPanelSize, gap: 12, showArrow: false)
            let window = MascotToolPanel(contentRect: placement.frame,
                styleMask: [.titled, .closable, .resizable, .utilityWindow, .fullSizeContentView], backing: .buffered, defer: false)
            window.onClose = { [weak self] in self?.hide() }
            window.title = "Công cụ nhanh · \(MascotIdentity.name)"
            window.titleVisibility = .hidden
            window.titlebarAppearsTransparent = true
            window.isMovableByWindowBackground = true
            window.isOpaque = false
            window.backgroundColor = .clear
            window.hasShadow = false
            window.titlebarSeparatorStyle = .none
            window.standardWindowButton(.closeButton)?.isHidden = true
            window.standardWindowButton(.miniaturizeButton)?.isHidden = true
            window.standardWindowButton(.zoomButton)?.isHidden = true
            window.identifier = NSUserInterfaceItemIdentifier("mascot-mini-tools")
            window.isReleasedWhenClosed = false; window.hidesOnDeactivate = false
            window.level = .floating
            window.minSize = NSSize(width: min(380, placement.frame.width), height: min(280, placement.frame.height))
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            window.contentView = NSHostingView(rootView: MascotMiniToolsView(model: model, state: state,
                hide: { [weak self] in self?.hide() },
                openFull: { [weak self] in self?.openFull() }))
            panel = window
            panelTool = tool
            if tool == .conversation { heightBeforeConversation = 300 }
        }
        // Apply the selected tool's preferred height before revealing a reused
        // panel. Waiting for SwiftUI's onChange can briefly show the previous
        // tool's size, especially when switching from the taller conversation.
        updatePanelSize(for: tool)
        // Selecting a tool closes the orbit and resizes the transparent mascot
        // window. Ignore intermediate geometry notifications until SwiftUI has
        // committed the compact layout, then place the panel once against the
        // settled mascot bounds. This prevents the panel jumping vertically.
        placementStableAfter = Date().addingTimeInterval(0.42)
        updatePlacement(display: false)
        panel?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        schedulePlacementRefresh(after: 0.42)
    }
    func updatePanelSize(for tool: MascotMiniTool) {
        guard let panel, let model, let mascot = model.mascotWindow,
              let screen = mascot.screen ?? NSScreen.main else {
            panelTool = tool
            return
        }
        let previousTool = panelTool ?? tool
        let transition = MascotMiniToolSizeTransition.applying(
            currentSize: panel.frame.size, from: previousTool, to: tool,
            restoreHeight: heightBeforeConversation)
        let size: CGSize
        if previousTool == tool {
            size = preferredPanelSize ?? panel.frame.size
        } else {
            size = transition.size
            preferredPanelSize = size
        }
        heightBeforeConversation = transition.conversationRestoreHeight
        panelTool = tool
        guard size != panel.frame.size else { return }
        let placement = MascotMiniToolPlacement.resolve(
            mascotFrame: placementAnchor(for: model), screen: screen.visibleFrame,
            preferredSize: size, gap: 12, showArrow: false)
        state.arrowEdge = placement.arrowEdge
        state.arrowOffset = placement.arrowOffset
        applyProgrammaticFrame(placement.frame, display: true)
    }
    private func observeMascotGeometry(for model: MeetingModel) {
        guard self.model !== model || geometryObservers.isEmpty else { return }
        geometryObservers.forEach(NotificationCenter.default.removeObserver)
        geometryObservers.removeAll()
        for name in [NSWindow.didMoveNotification, NSWindow.didResizeNotification, NSWindow.didChangeScreenNotification] {
            geometryObservers.append(NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self, weak model] event in
                MainActor.assumeIsolated {
                    guard let self, let movedWindow = event.object as? NSWindow else { return }
                    if movedWindow === self.panel {
                        guard event.name == NSWindow.didResizeNotification else { return }
                        let size = movedWindow.frame.size
                        if self.applyingProgrammaticFrame || size == self.lastProgrammaticFrameSize {
                            if size == self.lastProgrammaticFrameSize { self.lastProgrammaticFrameSize = nil }
                            return
                        }
                        self.preferredPanelSize = movedWindow.frame.size
                        self.lastProgrammaticFrameSize = nil
                        return
                    }
                    guard let model, let mascot = model.mascotWindow,
                          movedWindow === mascot, self.panel?.isVisible == true else { return }
                    self.refreshPlacement()
                }
            })
        }
    }
    private func updatePlacement(display: Bool) {
        guard let panel, let mascot = model?.mascotWindow,
              let screen = mascot.screen ?? NSScreen.main else { return }
        let placement = MascotMiniToolPlacement.resolve(
            mascotFrame: placementAnchor(for: model), screen: screen.visibleFrame,
            preferredSize: preferredPanelSize ?? panel.frame.size, gap: 12, showArrow: false)
        state.arrowEdge = placement.arrowEdge
        state.arrowOffset = placement.arrowOffset
        if panel.frame != placement.frame { applyProgrammaticFrame(placement.frame, display: display) }
    }
    private func applyProgrammaticFrame(_ frame: CGRect, display: Bool) {
        guard let panel else { return }
        lastProgrammaticFrameSize = frame.size
        applyingProgrammaticFrame = true
        defer { applyingProgrammaticFrame = false }
        panel.setFrame(frame, display: display)
    }
    func refreshPlacement() {
        guard panel?.isVisible == true else { return }
        schedulePlacementRefresh(after: 0.06)
    }
    private func schedulePlacementRefresh(after delay: TimeInterval) {
        placementRefreshWorkItem?.cancel()
        let stableDelay = max(0, placementStableAfter.timeIntervalSinceNow)
        let scheduledDelay = max(delay, stableDelay)
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.panel?.isVisible == true else { return }
            self.updatePlacement(display: true)
        }
        placementRefreshWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + scheduledDelay, execute: work)
    }
    private func placementAnchor(for model: MeetingModel?) -> CGRect {
        guard let model, let mascot = model.mascotWindow else { return .zero }
        return MascotMiniToolPlacement.visualAnchor(windowFrame: mascot.frame, localBounds: model.mascotHeadBounds)
    }
    func hide(stopMiniReader: Bool = true) {
        placementRefreshWorkItem?.cancel()
        placementRefreshWorkItem = nil
        state.translation.cancel()
        if stopMiniReader, TTSService.shared.currentlySpeakingCaptionID == state.readerPlaybackID { TTSService.shared.stop() }
        panel?.orderOut(nil)
    }
    func openFull() {
        guard let model else { return }
        let selected = state.tool
        model.selectedDashboardTab = selected.rawValue
        if selected == .notebook, let id = state.notebookSelection { model.selectedSessionID = id }
        model.showMainWindow(preservingMiniReader: selected == .reader)
    }
}

struct MascotMiniToolPlacement {
    let frame: CGRect
    let arrowEdge: MascotMiniToolArrowEdge
    /// Distance from the lower-left corner for vertical edges, or from the left for horizontal edges.
    let arrowOffset: CGFloat

    static func resolve(mascotFrame: CGRect, screen: CGRect,
                        preferredSize: CGSize = CGSize(width: 400, height: 300),
                        gap: CGFloat = 0, margin: CGFloat = 12, showArrow: Bool = true) -> Self {
        let area = screen.insetBy(dx: margin, dy: margin)
        let size = CGSize(width: min(preferredSize.width, area.width),
                          height: min(preferredSize.height, area.height))
        guard area.width > 0, area.height > 0, !mascotFrame.isEmpty else {
            return Self(frame: CGRect(origin: screen.origin, size: size), arrowEdge: .left, arrowOffset: size.height / 2)
        }

        func clamped(_ origin: CGPoint) -> CGRect {
            CGRect(x: min(max(origin.x, area.minX), area.maxX - size.width),
                   y: min(max(origin.y, area.minY), area.maxY - size.height),
                   width: size.width, height: size.height)
        }
        let right = clamped(CGPoint(x: mascotFrame.maxX + gap, y: mascotFrame.midY - size.height / 2))
        let left = clamped(CGPoint(x: mascotFrame.minX - size.width - gap, y: mascotFrame.midY - size.height / 2))
        let above = clamped(CGPoint(x: mascotFrame.midX - size.width / 2, y: mascotFrame.maxY + gap))
        let below = clamped(CGPoint(x: mascotFrame.midX - size.width / 2, y: mascotFrame.minY - size.height - gap))

        let preferLeft = mascotFrame.midX > screen.midX
        let rawCandidates: [(frame: CGRect, edge: MascotMiniToolArrowEdge)] = preferLeft
            ? [(left, .right), (right, .left), (above, .bottom), (below, .top)]
            : [(right, .left), (left, .right), (above, .bottom), (below, .top)]
        func alignedFrame(_ frame: CGRect, edge: MascotMiniToolArrowEdge) -> CGRect {
            // If the panel was clamped to a screen edge, shift it along its
            // mascot-facing edge so the tail can still point at the artwork.
            let clearance: CGFloat = 27
            switch edge {
            case .left, .right:
                let minY = max(area.minY, mascotFrame.midY - (size.height - clearance))
                let maxY = min(area.maxY - size.height, mascotFrame.midY - clearance)
                guard minY <= maxY else { return frame }
                return frame.offsetBy(dx: 0, dy: min(max(frame.minY, minY), maxY) - frame.minY)
            case .top, .bottom:
                let minX = max(area.minX, mascotFrame.midX - (size.width - clearance))
                let maxX = min(area.maxX - size.width, mascotFrame.midX - clearance)
                guard minX <= maxX else { return frame }
                return frame.offsetBy(dx: min(max(frame.minX, minX), maxX) - frame.minX, dy: 0)
            }
        }
        let candidates = rawCandidates.map {
            (frame: showArrow ? alignedFrame($0.frame, edge: $0.edge) : $0.frame, edge: $0.edge)
        }
        func overlapArea(_ frame: CGRect) -> CGFloat {
            let intersection = frame.intersection(mascotFrame)
            return max(0, intersection.width) * max(0, intersection.height)
        }
        func edgeDistance(_ frame: CGRect) -> CGFloat {
            let dx = max(0, mascotFrame.minX - frame.maxX, frame.minX - mascotFrame.maxX)
            let dy = max(0, mascotFrame.minY - frame.maxY, frame.minY - mascotFrame.maxY)
            return hypot(dx, dy)
        }
        func arrowOffset(for edge: MascotMiniToolArrowEdge, frame: CGRect) -> CGFloat {
            switch edge {
            case .top, .bottom:
                return max(27, min(size.width - 27, mascotFrame.midX - frame.minX))
            case .left, .right:
                return max(27, min(size.height - 27, mascotFrame.midY - frame.minY))
            }
        }
        func targetPoint(for edge: MascotMiniToolArrowEdge) -> CGPoint {
            switch edge {
            case .left: return CGPoint(x: mascotFrame.maxX, y: mascotFrame.midY)
            case .right: return CGPoint(x: mascotFrame.minX, y: mascotFrame.midY)
            case .top: return CGPoint(x: mascotFrame.midX, y: mascotFrame.minY)
            case .bottom: return CGPoint(x: mascotFrame.midX, y: mascotFrame.maxY)
            }
        }
        func tipDistance(_ candidate: (frame: CGRect, edge: MascotMiniToolArrowEdge)) -> CGFloat {
            let tip = arrowTip(frame: candidate.frame, edge: candidate.edge,
                               offset: arrowOffset(for: candidate.edge, frame: candidate.frame))
            let target = targetPoint(for: candidate.edge)
            return hypot(tip.x - target.x, tip.y - target.y)
        }
        let selected = candidates.min { lhs, rhs in
            let lhsOverlap = overlapArea(lhs.frame)
            let rhsOverlap = overlapArea(rhs.frame)
            if abs(lhsOverlap - rhsOverlap) > 0.5 { return lhsOverlap < rhsOverlap }
            let lhsTipDistance = tipDistance(lhs)
            let rhsTipDistance = tipDistance(rhs)
            if abs(lhsTipDistance - rhsTipDistance) > 0.5 { return lhsTipDistance < rhsTipDistance }
            let lhsDistance = edgeDistance(lhs.frame)
            let rhsDistance = edgeDistance(rhs.frame)
            if abs(lhsDistance - rhsDistance) > 0.5 { return lhsDistance < rhsDistance }
            // Keep the panel beside the mascot when several placements are equally close.
            let lhsIsSide = lhs.edge == .left || lhs.edge == .right
            let rhsIsSide = rhs.edge == .left || rhs.edge == .right
            if lhsIsSide != rhsIsSide { return lhsIsSide }
            return lhsDistance < rhsDistance
        } ?? (right, .left)

        let offset = arrowOffset(for: selected.edge, frame: selected.frame)
        return Self(frame: selected.frame, arrowEdge: selected.edge, arrowOffset: offset)
    }

    static func arrowTip(frame: CGRect, edge: MascotMiniToolArrowEdge, offset: CGFloat) -> CGPoint {
        switch edge {
        case .left: return CGPoint(x: frame.minX, y: frame.minY + offset)
        case .right: return CGPoint(x: frame.maxX, y: frame.minY + offset)
        case .top: return CGPoint(x: frame.minX + offset, y: frame.maxY)
        case .bottom: return CGPoint(x: frame.minX + offset, y: frame.minY)
        }
    }

    /// Convert the avatar's SwiftUI bounds (origin at the top-left of its canvas)
    /// into AppKit screen coordinates. The whole transparent mascot window is a
    /// poor anchor because it includes substantial empty space around the artwork.
    static func visualAnchor(windowFrame: CGRect, localBounds: CGRect?) -> CGRect {
        guard let bounds = localBounds, !bounds.isEmpty else { return windowFrame }
        return CGRect(x: windowFrame.minX + bounds.minX,
                      y: windowFrame.maxY - bounds.maxY,
                      width: bounds.width, height: bounds.height)
    }

    /// Anchor in the lower part of the artwork, below its leaves/transparent
    /// upper area. Use the same lower anchor before measured bounds arrive.
    static func bodyAnchor(windowFrame: CGRect, localBounds: CGRect?, verticalFraction: CGFloat = 0.76) -> CGPoint {
        let artwork = visualAnchor(windowFrame: windowFrame, localBounds: localBounds)
        let fraction = min(max(verticalFraction, 0), 1)
        return CGPoint(x: artwork.midX,
                       y: artwork.maxY - artwork.height * fraction)
    }

}

/// Places short translation/lookup cards beside the visible mascot artwork,
/// rather than beside its larger transparent launcher window.
struct MascotSpeechCardPlacement {
    let frame: CGRect
    let onRight: Bool
    /// Vertical pointer position in SwiftUI's top-down unit coordinates.
    let arrowY: CGFloat

    static func resolve(anchor: CGRect, target: CGPoint? = nil, screen: CGRect, size: CGSize, gap: CGFloat = 8,
                        margin: CGFloat = 10) -> Self {
        let targetY = target?.y ?? anchor.midY

        // Place the pointer just outside the measured artwork edge. The body
        // target controls vertical alignment only; using its horizontal center
        // would place the speech card over the mascot.
        let bodyRight = anchor.maxX
        let bodyLeft = anchor.minX
        let rightSpace = screen.maxX - bodyRight
        let leftSpace = bodyLeft - screen.minX
        let onRight = rightSpace >= size.width + gap || rightSpace >= leftSpace
        let proposedX = onRight ? bodyRight + gap : bodyLeft - size.width - gap
        let x = min(max(proposedX, screen.minX + margin), screen.maxX - size.width - margin)
        let proposedY = targetY - size.height / 2
        let y = min(max(proposedY, screen.minY + margin), screen.maxY - size.height - margin)
        let frame = CGRect(origin: CGPoint(x: x, y: y), size: size)
        let arrowY = min(max((frame.maxY - targetY) / max(size.height, 1), 0.08), 0.92)
        return Self(frame: frame, onRight: onRight, arrowY: arrowY)
    }
}

struct MascotMiniToolBubble: InsettableShape {
    let edge: MascotMiniToolArrowEdge
    var offset: CGFloat
    var insetAmount: CGFloat = 0

    func inset(by amount: CGFloat) -> some InsettableShape {
        insetted(by: amount)
    }

    func insetted(by amount: CGFloat) -> MascotMiniToolBubble {
        var shape = self
        shape.insetAmount += amount
        // `offset` is measured from the lower-left/left edge. Move the value
        // with the inset so the stroked tail stays centered on the fill tail.
        shape.offset = max(0, shape.offset - amount)
        return shape
    }

    func tailTip(in inputRect: CGRect) -> CGPoint {
        let rect = inputRect.insetBy(dx: insetAmount, dy: insetAmount)
        let clearance: CGFloat = 27
        let distance = min(max(offset, clearance),
                           (edge == .top || edge == .bottom ? rect.width : rect.height) - clearance)
        switch edge {
        case .left: return CGPoint(x: rect.minX, y: rect.minY + rect.height - distance)
        case .right: return CGPoint(x: rect.maxX, y: rect.minY + rect.height - distance)
        case .top: return CGPoint(x: rect.minX + distance, y: rect.minY)
        case .bottom: return CGPoint(x: rect.minX + distance, y: rect.maxY)
        }
    }

    func path(in inputRect: CGRect) -> Path {
        let rect = inputRect.insetBy(dx: insetAmount, dy: insetAmount)
        let depth: CGFloat = 10
        let radius: CGFloat = 14
        let horizontalArrow = edge == .top || edge == .bottom
        let body = rect.insetBy(dx: horizontalArrow ? 0 : depth,
                                dy: horizontalArrow ? depth : 0)
        let half: CGFloat = 9
        // Keep the curved tail shoulders tangent to the straight body edge.
        // The complete outline is one path, so there is no doubled stroke or seam.
        let tailBaseClearance: CGFloat = 4
        let x = rect.minX + min(max(offset, radius + half + tailBaseClearance),
                                rect.width - radius - half - tailBaseClearance)
        let y = rect.minY + rect.height - offset
        var path = Path()
        path.move(to: CGPoint(x: body.minX + radius, y: body.minY))

        if edge == .top {
            let leftBase = CGPoint(x: x - half - 4, y: body.minY)
            let rightBase = CGPoint(x: x + half + 4, y: body.minY)
            path.addLine(to: leftBase)
            path.addCurve(to: CGPoint(x: x, y: rect.minY),
                          control1: CGPoint(x: leftBase.x + 7, y: leftBase.y),
                          control2: CGPoint(x: x - 3, y: rect.minY + 4))
            path.addCurve(to: rightBase,
                          control1: CGPoint(x: x + 3, y: rect.minY + 4),
                          control2: CGPoint(x: rightBase.x - 7, y: rightBase.y))
            path.addLine(to: CGPoint(x: body.maxX - radius, y: body.minY))
        } else {
            path.addLine(to: CGPoint(x: body.maxX - radius, y: body.minY))
        }
        path.addQuadCurve(to: CGPoint(x: body.maxX, y: body.minY + radius), control: CGPoint(x: body.maxX, y: body.minY))
        if edge == .right {
            let upperBase = CGPoint(x: body.maxX, y: y - half - 4)
            let lowerBase = CGPoint(x: body.maxX, y: y + half + 4)
            path.addLine(to: upperBase)
            path.addCurve(to: CGPoint(x: rect.maxX, y: y),
                          control1: CGPoint(x: upperBase.x, y: upperBase.y + 7),
                          control2: CGPoint(x: rect.maxX - 4, y: y - 3))
            path.addCurve(to: lowerBase,
                          control1: CGPoint(x: rect.maxX - 4, y: y + 3),
                          control2: CGPoint(x: lowerBase.x, y: lowerBase.y - 7))
            path.addLine(to: CGPoint(x: body.maxX, y: body.maxY - radius))
        } else {
            path.addLine(to: CGPoint(x: body.maxX, y: body.maxY - radius))
        }
        path.addQuadCurve(to: CGPoint(x: body.maxX - radius, y: body.maxY), control: CGPoint(x: body.maxX, y: body.maxY))
        if edge == .bottom {
            let rightBase = CGPoint(x: x + half + 4, y: body.maxY)
            let leftBase = CGPoint(x: x - half - 4, y: body.maxY)
            path.addLine(to: rightBase)
            path.addCurve(to: CGPoint(x: x, y: rect.maxY),
                          control1: CGPoint(x: rightBase.x - 7, y: rightBase.y),
                          control2: CGPoint(x: x + 3, y: rect.maxY - 4))
            path.addCurve(to: leftBase,
                          control1: CGPoint(x: x - 3, y: rect.maxY - 4),
                          control2: CGPoint(x: leftBase.x + 7, y: leftBase.y))
            path.addLine(to: CGPoint(x: body.minX + radius, y: body.maxY))
        } else {
            path.addLine(to: CGPoint(x: body.minX + radius, y: body.maxY))
        }
        path.addQuadCurve(to: CGPoint(x: body.minX, y: body.maxY - radius), control: CGPoint(x: body.minX, y: body.maxY))
        if edge == .left {
            let lowerBase = CGPoint(x: body.minX, y: y + half + 4)
            let upperBase = CGPoint(x: body.minX, y: y - half - 4)
            path.addLine(to: lowerBase)
            path.addCurve(to: CGPoint(x: rect.minX, y: y),
                          control1: CGPoint(x: lowerBase.x, y: lowerBase.y - 7),
                          control2: CGPoint(x: rect.minX + 4, y: y + 3))
            path.addCurve(to: upperBase,
                          control1: CGPoint(x: rect.minX + 4, y: y - 3),
                          control2: CGPoint(x: upperBase.x, y: upperBase.y + 7))
            path.addLine(to: CGPoint(x: body.minX, y: body.minY + radius))
        } else {
            path.addLine(to: CGPoint(x: body.minX, y: body.minY + radius))
        }
        path.addQuadCurve(to: CGPoint(x: body.minX + radius, y: body.minY), control: CGPoint(x: body.minX, y: body.minY))
        path.closeSubpath()
        return path
    }
}

private struct MascotMiniToolsView: View {
    @ObservedObject var model: MeetingModel
    @ObservedObject var state: MascotMiniToolsState
    let hide: () -> Void
    let openFull: () -> Void
    private let light = true
    private var surface: Color { Color(red: 0.995, green: 1.0, blue: 0.995) }
    private var ink: Color { Color(red: 0.13, green: 0.17, blue: 0.16) }
    private var softMint: Color { TransToolsTheme.accent }
    private var panelOutline: LinearGradient {
        LinearGradient(
            colors: [
                Color(red: 0.67, green: 0.80, blue: 0.76),
                TransToolsTheme.accent.opacity(0.92),
                Color(red: 0.57, green: 0.73, blue: 0.68)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
    private let contentLeadingInset: CGFloat = 16
    private let contentTrailingInset: CGFloat = 16
    private let contentTopInset: CGFloat = 14
    private let contentBottomInset: CGFloat = 14
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: state.tool.icon).foregroundStyle(softMint)
                Text(state.tool.title).font(.headline).foregroundStyle(ink)
                Spacer()
                Button(action: openFull) { Image(systemName: "arrow.up.left.and.arrow.down.right").frame(width: 28, height: 28) }
                    .buttonStyle(MiniToolHUDIconButtonStyle(light: light))
                    .help("Mở đầy đủ, giữ nội dung đang nhập").accessibilityLabel("Mở đầy đủ")
                Button(action: hide) { Image(systemName: "xmark").frame(width: 28, height: 28) }
                    .buttonStyle(MiniToolHUDIconButtonStyle(light: light, close: true))
                    .help("Thu gọn về mascot").accessibilityLabel("Thu gọn về mascot")
            }
            .padding(.leading, contentLeadingInset).padding(.trailing, contentTrailingInset)
            .padding(.top, 6).padding(.bottom, 10)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(MascotMiniTool.allCases) { tool in
                        Button {
                            state.translation.cancel(); state.tool = tool
                        } label: {
                            Image(systemName: tool.icon).frame(width: 34, height: 30)
                                .background(state.tool == tool ? MiniToolSurfaceStyle.fill(light: light, emphasized: true) : Color.clear, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                                .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(MiniToolSurfaceStyle.border(light: light, emphasized: state.tool == tool), lineWidth: 1))
                        }.buttonStyle(.plain).foregroundStyle(softMint).help(tool.title).accessibilityLabel(tool.title)
                    }
                    Button {
                        hide(); model.toggleOverlay()
                    } label: { Image(systemName: "captions.bubble").frame(width: 34, height: 30) }
                        .buttonStyle(MiniToolHUDIconButtonStyle(light: light)).help("Phụ đề gọn")
                }.padding(.leading, contentLeadingInset).padding(.trailing, contentTrailingInset)
            }.padding(.bottom, 8)
            Divider().overlay(TransToolsTheme.accent.opacity(0.20))
            Group {
                switch state.tool {
                case .translation:
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Nhập câu để dịch, soạn lời trả lời hoặc hỏi cuộc họp.")
                            .font(.caption).foregroundStyle(.secondary)
                        if state.translation.latest == nil {
                            Spacer(minLength: 8)
                            VStack(spacing: 8) {
                                Image(systemName: "text.bubble")
                                    .font(.system(size: 22, weight: .regular))
                                    .foregroundStyle(softMint.opacity(0.68))
                                Text("Kết quả sẽ hiện ở đây")
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundStyle(softMint.opacity(0.72))
                            }
                            .frame(maxWidth: .infinity)
                            Spacer(minLength: 8)
                        }
                        SubtitleQuickComposer(model: model, store: state.translation)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                case .reader: MiniReader(model: model, state: state)
                case .conversation: MiniConversation(model: model, state: state)
                case .notebook: MiniNotebook(model: model, state: state, openFull: openFull)
                case .learning: MiniVocabularyReview()
                case .settings: MiniToolSettings(model: model)
                }
            }.frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.leading, contentLeadingInset).padding(.trailing, contentTrailingInset)
                .padding(.top, contentTopInset).padding(.bottom, contentBottomInset)
        }
        .padding(.bottom, 1)
        .background { MiniToolPanelBackground() }
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .foregroundStyle(ink).tint(TransToolsTheme.accent)
        .environment(\.colorScheme, .light)
        .buttonStyle(.plain)
        .ignoresSafeArea(.container, edges: .top)
        .onChange(of: model.isOverlayVisible) { _, visible in if visible { hide() } }
        .onChange(of: state.tool) { previous, tool in
            if previous == .reader, TTSService.shared.currentlySpeakingCaptionID == state.readerPlaybackID {
                TTSService.shared.stop()
            }
            model.miniTools.updatePanelSize(for: tool)
        }
    }
}

struct MiniToolPaperGrid: View {
    var light = true
    var body: some View {
        Canvas { context, size in
            let spacing: CGFloat = 26
            var path = Path()
            stride(from: CGFloat(0), through: size.width, by: spacing).forEach { x in
                path.move(to: CGPoint(x: x, y: 0)); path.addLine(to: CGPoint(x: x, y: size.height))
            }
            stride(from: CGFloat(0), through: size.height, by: spacing).forEach { y in
                path.move(to: CGPoint(x: 0, y: y)); path.addLine(to: CGPoint(x: size.width, y: y))
            }
            context.stroke(path, with: .color(TransToolsTheme.accent.opacity(light ? 0.075 : 0.14)), lineWidth: 0.7)
        }
        .accessibilityHidden(true)
        .allowsHitTesting(false)
    }
}

struct MiniToolPanelBackground: View {
    var light = true
    private var surface: Color {
        light ? Color(red: 0.995, green: 1.0, blue: 0.995) : Color(red: 0.055, green: 0.10, blue: 0.095)
    }
    private var outline: LinearGradient {
        LinearGradient(colors: light
                       ? [Color(red: 0.67, green: 0.80, blue: 0.76), TransToolsTheme.accent.opacity(0.92), Color(red: 0.57, green: 0.73, blue: 0.68)]
                       : [TransToolsTheme.accent.opacity(0.72), TransToolsTheme.accent.opacity(0.96), TransToolsTheme.accent.opacity(0.62)],
                       startPoint: .topLeading, endPoint: .bottomTrailing)
    }
    var body: some View {
        RoundedRectangle(cornerRadius: 20, style: .continuous).fill(surface)
            .overlay {
                MiniToolPaperGrid(light: light)
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .padding(2)
            }
            .overlay {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .strokeBorder(outline, lineWidth: 2.4)
            }
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(Color(red: 0.36, green: 0.52, blue: 0.48).opacity(0.12), lineWidth: 0.8)
                    .padding(4)
                    .allowsHitTesting(false)
            }
    }
}

struct MiniToolHUDIconButtonStyle: ButtonStyle {
    var light = false
    var close = false
    @Environment(\.isEnabled) private var enabled
    @State private var hovered = false
    func makeBody(configuration: Configuration) -> some View {
        let tint = close ? Color(red: 0.96, green: 0.43, blue: 0.43) : TransToolsTheme.accent
        return configuration.label
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(close ? tint : (light ? TransToolsTheme.accent : Color(red: 0.65, green: 0.88, blue: 0.79)))
            .background(close
                ? Color.white.opacity(hovered ? 1 : 0.94)
                : tint.opacity(hovered ? (light ? 0.12 : 0.20) : (light ? 0.05 : 0.09)),
                in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(
                close ? tint.opacity(hovered ? 0.70 : 0.42) : tint.opacity(hovered ? 0.50 : 0.22), lineWidth: 1))
            .opacity(enabled ? (configuration.isPressed ? 0.72 : 1) : 0.45)
            .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .transToolsButtonCursor()
            .onHover { hovered = $0 }
    }
}

private struct MiniReader: View {
    @ObservedObject var model: MeetingModel
    @ObservedObject var state: MascotMiniToolsState
    @ObservedObject private var tts = TTSService.shared
    @AppStorage("SubtitleHUDLight") private var light = false
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Picker("Ngôn ngữ", selection: $state.readerLanguage) {
                ForEach(AppLanguage.allCases) { Text($0.displayName).tag($0) }
            }.controlSize(.large)
            Text("Nhập hoặc dán văn bản để nghe. Mở đầy đủ để chọn truyện và lưu audio.").font(.caption).foregroundStyle(.secondary)
            ZStack(alignment: .topLeading) {
                TextEditor(text: $state.readerText).font(.system(size: 15))
                    .scrollContentBackground(.hidden).padding(8)
                    .accessibilityLabel("Văn bản đọc nhanh")
                if state.readerText.isEmpty {
                    Text("Nhập hoặc dán văn bản cần đọc…")
                        .font(.system(size: 14))
                        .foregroundStyle(.secondary.opacity(0.8))
                        .padding(.leading, 13).padding(.top, 15)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
            }
            .background(light ? Color.white.opacity(0.88) : Color.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(MiniToolSurfaceStyle.inputBorder(light: light), lineWidth: 1))
            HStack {
                Text(state.readerText.count > 5000
                    ? "\(state.readerText.count)/5.000 · Hãy rút gọn văn bản"
                    : "\(state.readerText.count)/5.000 ký tự")
                    .font(.caption)
                    .foregroundStyle(state.readerText.count > 5000 ? Color.red : Color.secondary)
                Spacer()
                Button { if tts.currentlySpeakingCaptionID == state.readerPlaybackID { tts.stop() } } label: { Label("Dừng", systemImage: "stop.fill") }
                    .disabled(!tts.isSpeaking || tts.currentlySpeakingCaptionID != state.readerPlaybackID)
                Button {
                    tts.speak(id: state.readerPlaybackID, text: state.readerText, language: state.readerLanguage)
                } label: { Label("Đọc", systemImage: "play.fill") }
                    .disabled(state.readerText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || state.readerText.count > 5000)
            }.buttonStyle(TransToolsActionButtonStyle(tint: light ? TransToolsTheme.accent : Color(red: 0.65, green: 0.88, blue: 0.79), height: 32))
        }
    }
}

private struct MiniConversation: View {
    @ObservedObject var model: MeetingModel
    @ObservedObject private var conversation = ConversationController.shared
    @ObservedObject var state: MascotMiniToolsState
    @AppStorage("SubtitleHUDLight") private var light = false
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Picker("Ngôn ngữ", selection: $conversation.chatLanguage) { ForEach(AppLanguage.allCases) { Text($0.displayName).tag($0) } }
                    .disabled(conversation.active)
                if !conversation.active {
                    Button("Bật micro") { Task { await conversation.start(model: model, manager: .shared, selectedLanguage: conversation.chatLanguage) } }
                        .buttonStyle(TransToolsActionButtonStyle(prominent: true, height: 30))
                        .disabled(model.running)
                } else {
                    Button {
                        Task {
                            if conversation.usesMicrophone { await conversation.disableMicrophone() }
                            else { await conversation.enableMicrophone(model: model) }
                        }
                    } label: {
                        Image(systemName: conversation.usesMicrophone ? "mic.slash" : "mic")
                            .frame(width: 28, height: 28)
                    }
                    .buttonStyle(MiniToolHUDIconButtonStyle(light: light))
                    .help(conversation.usesMicrophone ? "Tắt micro, tiếp tục nhắn tin" : "Bật micro cho buổi trò chuyện")
                    .accessibilityLabel(conversation.usesMicrophone ? "Tắt micro" : "Bật micro")
                    .disabled(conversation.changingMicrophone || (!conversation.usesMicrophone &&
                        !ConversationMicrophonePolicy.canEnable(active: conversation.active,
                            usesMicrophone: conversation.usesMicrophone, waiting: conversation.waiting,
                            changingMicrophone: conversation.changingMicrophone, meetingRunning: model.running)))
                    Button("Kết thúc") { conversation.stop() }
                        .buttonStyle(TransToolsActionButtonStyle(height: 30))
                }
            }
            if conversation.active || conversation.status != ConversationController.idleStatus {
                Label(conversation.status, systemImage: conversation.active ? "waveform" : "info.circle")
                    .font(.caption).foregroundStyle(.secondary)
                    .lineLimit(2).minimumScaleFactor(0.85)
            }
            if conversation.turns.isEmpty && conversation.draft.isEmpty {
                VStack(spacing: 7) {
                    Spacer(minLength: 0)
                    Image(systemName: conversation.active ? "waveform" : "bubble.left.and.bubble.right")
                        .font(.system(size: 23, weight: .medium))
                        .foregroundStyle(TransToolsTheme.accent.opacity(0.78))
                    Text(conversation.active ? "Đang trò chuyện" : "Bắt đầu trò chuyện")
                        .font(.subheadline.weight(.semibold)).foregroundStyle(TransToolsTheme.accent)
                        .multilineTextAlignment(.center)
                    if !conversation.active {
                        Text(conversation.status == ConversationController.idleStatus
                             ? "Bật micro hoặc nhập tin nhắn bên dưới để bắt đầu."
                             : "Xem thông báo phía trên, hoặc thử lại sau khi khắc phục.")
                            .font(.caption).foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.horizontal, 14)
            } else {
                if conversation.turns.count > 12 {
                    Label("Hiển thị 12 lượt gần nhất · Mở đầy đủ để xem toàn bộ", systemImage: "ellipsis.bubble")
                        .font(.caption2).foregroundStyle(.secondary)
                        .lineLimit(1).minimumScaleFactor(0.8)
                }
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 10) {
                            ForEach(conversation.turns.suffix(12)) { turn in
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(turn.speaker == "Bạn" ? "Bạn" : MascotIdentity.name).font(.caption.bold()).foregroundStyle(TransToolsTheme.accent)
                                    Text(turn.text).textSelection(.enabled)
                                    if conversation.bilingual, let meaning = turn.translation { Text(meaning).font(.caption).foregroundStyle(.secondary) }
                                }.padding(10).frame(maxWidth: .infinity, alignment: .leading)
                                    .background(MiniToolSurfaceStyle.fill(light: light, emphasized: true), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                                    .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
                                        .strokeBorder(MiniToolSurfaceStyle.border(light: light), lineWidth: 1))
                            }
                            if !conversation.draft.isEmpty { Text(conversation.draft).foregroundStyle(.secondary) }
                            Color.clear.frame(height: 1).id("latest")
                        }
                    }
                    .onAppear { proxy.scrollTo("latest", anchor: .bottom) }
                    .onChange(of: conversation.turns.count) { _, _ in proxy.scrollTo("latest", anchor: .bottom) }
                    .onChange(of: conversation.draft) { _, _ in proxy.scrollTo("latest", anchor: .bottom) }
                    .onChange(of: conversation.turns.compactMap(\.translation)) { _, _ in proxy.scrollTo("latest", anchor: .bottom) }
                }
            }
            MiniConversationInput(model: model, state: state)
            if model.running { Text("Dừng cuộc họp trước khi bật micro trò chuyện.").font(.caption).foregroundStyle(.secondary) }
        }
    }
}

struct MiniConversationInput: View {
    @ObservedObject var model: MeetingModel
    @State private var sending = false
    @ObservedObject var state: MascotMiniToolsState
    @ObservedObject private var conversation = ConversationController.shared
    @AppStorage("SubtitleHUDLight") private var light = false
    var body: some View {
        HStack {
            TextField("", text: $state.conversationInput,
                      prompt: Text("Nhập câu để nói chuyện…")
                        .foregroundColor(light ? Color.secondary : Color.white.opacity(0.62)))
                .textFieldStyle(.plain)
                .foregroundStyle(light ? Color.primary : Color.white.opacity(0.94))
                .padding(.horizontal, 10).frame(height: 34)
                .background(MiniToolSurfaceStyle.fill(light: light), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).strokeBorder(MiniToolSurfaceStyle.inputBorder(light: light), lineWidth: 1))
                .onSubmit { send() }
            Button { send() } label: { Image(systemName: "arrow.up").frame(width: 28, height: 28) }
                .buttonStyle(MiniToolHUDIconButtonStyle(light: light))
                .disabled(sending || conversation.waiting || state.conversationInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .help("Gửi câu đã nhập").accessibilityLabel("Gửi câu đã nhập")
        }
    }
    private func send() {
        let snapshot = state.conversationInput
        guard !sending, !conversation.waiting,
              !snapshot.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        sending = true
        Task { @MainActor in
            defer { sending = false }
            if !conversation.active {
                await conversation.start(model: model, manager: .shared,
                    selectedLanguage: conversation.chatLanguage, microphone: false, opening: false)
            }
            guard conversation.active, !conversation.waiting else { return }
            conversation.draft = snapshot
            conversation.submit()
            if state.conversationInput == snapshot { state.conversationInput = "" }
        }
    }
}

private struct MiniNotebook: View {
    @ObservedObject var model: MeetingModel
    @ObservedObject var state: MascotMiniToolsState
    let openFull: () -> Void
    @State private var query = ""
    @AppStorage("SubtitleHUDLight") private var light = false
    private var matchingSessions: [MeetingSession] {
        model.sessions
            .filter { query.isEmpty || $0.title.localizedCaseInsensitiveContains(query) }
            .sorted { $0.createdAt > $1.createdAt }
            .prefix(15)
            .map { $0 }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").font(.system(size: 12)).foregroundStyle(.secondary)
                TextField("Tìm tên bản ghi…", text: $query).textFieldStyle(.plain)
                if !query.isEmpty {
                    Button { query = "" } label: { Image(systemName: "xmark.circle.fill").frame(width: 22, height: 22) }
                        .buttonStyle(.plain).foregroundStyle(.secondary)
                        .help("Xóa tìm kiếm").accessibilityLabel("Xóa tìm kiếm")
                }
            }
            .padding(.horizontal, 10).frame(height: 34)
            .background(MiniToolSurfaceStyle.fill(light: light), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).strokeBorder(MiniToolSurfaceStyle.inputBorder(light: light), lineWidth: 1))
            ScrollView {
                if matchingSessions.isEmpty {
                    VStack(spacing: 7) {
                        Image(systemName: model.sessions.isEmpty ? "book.closed" : "magnifyingglass")
                            .font(.title3).foregroundStyle(TransToolsTheme.accent.opacity(0.75))
                        Text(model.sessions.isEmpty ? "Chưa có bản ghi" : "Không tìm thấy bản ghi")
                            .font(.subheadline.weight(.semibold)).foregroundStyle(TransToolsTheme.accent)
                        Text(model.sessions.isEmpty ? "Các cuộc họp và cuộc trò chuyện đã lưu sẽ xuất hiện ở đây." : "Thử từ khóa khác hoặc xóa nội dung tìm kiếm.")
                            .font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(16)
                } else {
                    LazyVStack(alignment: .leading, spacing: 8) {
                        ForEach(matchingSessions) { session in
                            Button { state.notebookSelection = session.id } label: {
                                VStack(alignment: .leading, spacing: 5) {
                                    Text(session.title).font(.subheadline.bold()).lineLimit(2)
                                    Text("\(session.captions.count) đoạn · \(durationLabel(session.durationSeconds))")
                                        .font(.caption).foregroundStyle(.secondary)
                                }.padding(10).frame(maxWidth: .infinity, alignment: .leading)
                                    .background(MiniToolSurfaceStyle.fill(light: light, emphasized: state.notebookSelection == session.id), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                                    .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(MiniToolSurfaceStyle.border(light: light, emphasized: state.notebookSelection == session.id), lineWidth: 1))
                            }.buttonStyle(.plain)
                        }
                    }
                }
            }
            if let selected = matchingSessions.first(where: { $0.id == state.notebookSelection }) {
                Text(selected.notes.isEmpty ? "\(selected.captions.count) câu · Mở đầy đủ để xem bản ghi và ghi chú." : selected.notes)
                    .lineLimit(4).font(.caption)
                Button("Mở bản ghi đầy đủ", action: openFull).buttonStyle(TransToolsActionButtonStyle(height: 32))
            }
        }
    }
    private func durationLabel(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds))
        return total < 60 ? "\(total) giây" : "\(total / 60) phút"
    }
}

private struct MiniVocabularyReview: View {
    @ObservedObject private var vocabulary = VocabularyManager.shared
    @ObservedObject private var learning = LanguageLearningManager.shared
    @State private var revealed = false
    @AppStorage("SubtitleHUDLight") private var light = false
    private var selectedLanguageItems: [VocabularyItem] {
        vocabulary.items.filter { $0.language == learning.selectedLanguage.rawValue }
    }
    private var item: VocabularyItem? { vocabulary.dueItems.first { $0.language == learning.selectedLanguage.rawValue } }
    var body: some View {
        VStack(spacing: 12) {
            if let item {
                VStack(spacing: 8) {
                    Label("Ôn từ đến hạn", systemImage: "sparkles.rectangle.stack.fill")
                        .font(.caption.weight(.semibold)).foregroundStyle(TransToolsTheme.accent)
                    Text(item.word).font(.title2.bold()).multilineTextAlignment(.center)
                    if revealed { Text(item.meaning).font(.body).multilineTextAlignment(.center).foregroundStyle(.secondary) }
                }
                .frame(maxWidth: .infinity)
                .padding(16)
                .background(MiniToolSurfaceStyle.fill(light: light), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(MiniToolSurfaceStyle.border(light: light), lineWidth: 1))
                Button { TTSService.shared.speak(text: item.word, language: AppLanguage(rawValue: item.language) ?? .english) } label: { Label("Nghe", systemImage: "speaker.wave.2") }
                    .buttonStyle(TransToolsActionButtonStyle(height: 32))
                if revealed {
                    HStack {
                        Button("Chưa nhớ") { grade(item, .again) }
                        Button("Đã nhớ") { grade(item, .good) }
                    }.buttonStyle(TransToolsActionButtonStyle(height: 32))
                } else {
                    Button("Hiện nghĩa") { revealed = true }.buttonStyle(TransToolsActionButtonStyle(height: 32))
                }
            } else {
                Spacer(minLength: 0)
                VStack(spacing: 8) {
                    Image(systemName: "checkmark.seal.fill").font(.title2).foregroundStyle(TransToolsTheme.accent)
                    Text(selectedLanguageItems.isEmpty ? "Chưa có từ để ôn" : "Đã ôn xong").font(.headline)
                    Text(selectedLanguageItems.isEmpty
                         ? "Lưu từ mới từ Dịch nhanh hoặc mở Sổ tay để bắt đầu học."
                         : "Chưa có từ đến hạn. Mở đầy đủ để học bài mới.")
                        .font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(16)
                .background(MiniToolSurfaceStyle.fill(light: light), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(MiniToolSurfaceStyle.border(light: light), lineWidth: 1))
            }
            Spacer(minLength: 0)
        }
    }
    private func grade(_ item: VocabularyItem, _ grade: VocabularyManager.SRSGrade) { vocabulary.review(itemId: item.id, grade: grade); revealed = false }
}

private struct MiniToolSettings: View {
    @ObservedObject var model: MeetingModel
    @AppStorage("SubtitleHUDLight") private var light = false
    @AppStorage("MascotQuickSubtitleEnabled") private var quickSubtitle = true
    @AppStorage("SubtitleHUDMascot") private var hudMascot = false
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 12) {
                Toggle("Phụ đề gọn trên mascot khi họp", isOn: $quickSubtitle)
                    .onChange(of: quickSubtitle) { _, _ in model.mascotQuickSubtitle.refresh() }
                Toggle("Phụ đề nền sáng", isOn: $light)
                Toggle("Mascot trong phụ đề đầy đủ", isOn: $hudMascot)
                Toggle("Đi dạo khi rảnh", isOn: $model.isDockWalkEnabled)
            }
            .padding(14)
            .background(MiniToolSurfaceStyle.fill(light: light), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(MiniToolSurfaceStyle.border(light: light), lineWidth: 1))
            Text("Mở đầy đủ để quản lý mô hình, giọng đọc, kết nối AI và phím tắt.").font(.caption).foregroundStyle(.secondary)
            Spacer()
        }
    }
}

struct SharedTextReaderView: View {
    @ObservedObject var model: MeetingModel
    @ObservedObject var state: MascotMiniToolsState
    init(model: MeetingModel) { self.model = model; self.state = model.miniTools.state }
    var body: some View { TextReaderView(text: $state.readerText, model: model, language: $state.readerLanguage, playbackID: state.readerPlaybackID) }
}
