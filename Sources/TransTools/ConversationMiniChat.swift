import SwiftUI
import AppKit

enum ConversationMiniChatLayout {
    static let preferredSize = CGSize(width: 440, height: 720)

    static func frame(visibleFrame: CGRect, preferredSize: CGSize = preferredSize) -> CGRect {
        let width = min(preferredSize.width, visibleFrame.width)
        let height = min(preferredSize.height, visibleFrame.height)
        let origin = CGPoint(
            x: max(visibleFrame.minX, min(visibleFrame.maxX - width - 20, visibleFrame.maxX - width)),
            y: max(visibleFrame.minY, min(visibleFrame.minY + 40, visibleFrame.maxY - height)))
        return CGRect(origin: origin, size: CGSize(width: width, height: height))
    }
}

enum ConversationMiniChatStatus {
    static func title(active: Bool, usesMicrophone: Bool, waiting: Bool, speaking: Bool) -> String {
        guard active else { return "Đã kết thúc" }
        if speaking { return "Đang trả lời" }
        if waiting { return "Đang suy nghĩ" }
        return usesMicrophone ? "Đang lắng nghe" : "Nhắn tin · micro đang tắt"
    }

    static func footer(active: Bool, usesMicrophone: Bool) -> String {
        guard active else { return "Mở đầy đủ để tiếp tục trò chuyện" }
        return usesMicrophone ? "Micro đang hoạt động · Kết thúc để dừng" : "Micro đang tắt · Nhắn tin"
    }
}

private final class ConversationMiniChatPanel: NSPanel {
    var onClose: (() -> Void)?
    override func close() { onClose?(); orderOut(nil) }
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

@MainActor
final class ConversationMiniChat {
    static let shared = ConversationMiniChat()
    private var panel: NSPanel?
    private weak var mainWindow: NSWindow?
    func show(mainWindow: NSWindow) {
        guard ConversationController.shared.active else { return }
        self.mainWindow = mainWindow
        if panel == nil {
            let visibleFrame = mainWindow.screen?.visibleFrame ?? NSScreen.main?.visibleFrame
            let frame = visibleFrame.map { ConversationMiniChatLayout.frame(visibleFrame: $0) }
                ?? CGRect(origin: .zero, size: ConversationMiniChatLayout.preferredSize)
            let window = ConversationMiniChatPanel(contentRect: frame, styleMask: [.titled, .closable, .resizable, .utilityWindow, .fullSizeContentView], backing: .buffered, defer: false)
            window.onClose = { [weak self] in self?.hide() }
            window.title = "Trò chuyện nhỏ · \(MascotIdentity.name)"
            window.titleVisibility = .hidden
            window.titlebarAppearsTransparent = true
            window.titlebarSeparatorStyle = .none
            window.isMovableByWindowBackground = true
            window.isOpaque = false
            window.backgroundColor = .clear
            window.hasShadow = false
            window.standardWindowButton(.closeButton)?.isHidden = true
            window.standardWindowButton(.miniaturizeButton)?.isHidden = true
            window.standardWindowButton(.zoomButton)?.isHidden = true
            window.isReleasedWhenClosed = false
            window.level = .floating
            window.hidesOnDeactivate = false
            window.minSize = NSSize(width: min(360, frame.width), height: min(300, frame.height))
            window.contentView = NSHostingView(rootView: ConversationMiniChatView(
                openMain: { [weak self] in self?.openMain() },
                close: { [weak self] in self?.hide() }))
            panel = window
        }
        panel?.makeKeyAndOrderFront(nil)
    }
    func hide() { panel?.orderOut(nil) }
    private func openMain() {
        hide()
        mainWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

private struct ConversationMiniChatView: View {
    @ObservedObject private var conversation = ConversationController.shared
    @ObservedObject private var tts = TTSService.shared
    @AppStorage("MiniChat_ShowTranslation") private var showTranslation = true
    let openMain: () -> Void
    let close: () -> Void
    private var stateLabel: String {
        ConversationMiniChatStatus.title(active: conversation.active,
            usesMicrophone: conversation.usesMicrophone, waiting: conversation.waiting,
            speaking: tts.isSpeaking)
    }
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                MiniAvatarView(size: 28, style: "sprite", time: 0)
                    .frame(width: 38, height: 38).background(TransToolsTheme.mint, in: Circle())
                VStack(alignment: .leading, spacing: 3) {
                    Text(MascotIdentity.name).font(.system(size: 14, weight: .semibold))
                    HStack(spacing: 5) {
                        Circle().fill(conversation.active ? TransToolsTheme.accent : .secondary).frame(width: 5, height: 5)
                        Text(stateLabel).font(.system(size: 11)).foregroundStyle(.secondary)
                    }
                }
                Spacer()
                Button { showTranslation.toggle() } label: { Image(systemName: "captions.bubble") }
                    .buttonStyle(TransToolsActionButtonStyle(height: 30))
                    .help(showTranslation ? "Ẩn bản dịch" : "Hiện bản dịch")
                    .accessibilityLabel(showTranslation ? "Ẩn bản dịch" : "Hiện bản dịch")
                Button(action: openMain) { Image(systemName: "arrow.up.left.and.arrow.down.right") }
                    .buttonStyle(TransToolsActionButtonStyle(height: 30)).help("Mở đầy đủ").accessibilityLabel("Mở đầy đủ")
                Button(action: close) { Image(systemName: "xmark").frame(width: 30, height: 30) }
                    .buttonStyle(ConversationMiniCloseButtonStyle())
                    .help("Thu gọn Trò chuyện").accessibilityLabel("Thu gọn Trò chuyện")
            }.padding(12).background(TransToolsTheme.background)
            Divider().overlay(TransToolsTheme.accent.opacity(0.15))
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 10) {
                        ForEach(conversation.turns.suffix(6)) { turn in bubble(turn) }
                        if !conversation.draft.isEmpty {
                            HStack {
                                Spacer(minLength: 36)
                                Text(conversation.draft).font(.system(size: 13)).foregroundStyle(.secondary)
                                    .padding(10).background(TransToolsTheme.mint, in: RoundedRectangle(cornerRadius: 12))
                            }
                        }
                        if conversation.waiting && !tts.isSpeaking { Text("Đang chuẩn bị câu trả lời…").font(.caption).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading) }
                        Color.clear.frame(height: 1).id("bottom")
                    }.padding(12)
                }
                .onAppear { proxy.scrollTo("bottom", anchor: .bottom) }
                .onChange(of: conversation.turns.count) { _, _ in proxy.scrollTo("bottom", anchor: .bottom) }
                .onChange(of: conversation.draft) { _, _ in proxy.scrollTo("bottom", anchor: .bottom) }
                .onChange(of: conversation.turns.compactMap(\.translation)) { _, _ in proxy.scrollTo("bottom", anchor: .bottom) }
            }.background(TransToolsTheme.mint.opacity(0.45))
            Divider()
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    if conversation.active {
                        if !conversation.waiting {
                            Button("Gửi") { conversation.submit() }.buttonStyle(TransToolsActionButtonStyle(height: 32)).disabled(conversation.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        } else if tts.isSpeaking {
                            Button("Nói tiếp") { conversation.interruptReply() }.buttonStyle(TransToolsActionButtonStyle(height: 32))
                        }
                        Spacer()
                        Button("Kết thúc", role: .destructive) { conversation.stop() }.buttonStyle(TransToolsActionButtonStyle(height: 32))
                    } else { Text("Buổi trò chuyện đã dừng.").font(.caption).foregroundStyle(.secondary); Spacer() }
                }
                Text(ConversationMiniChatStatus.footer(active: conversation.active,
                    usesMicrophone: conversation.usesMicrophone))
                    .font(.system(size: 10)).foregroundStyle(.secondary)
            }.padding(12).background(TransToolsTheme.background)
        }
        .background(TransToolsTheme.background)
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
            .strokeBorder(TransToolsTheme.accent.opacity(0.22), lineWidth: 1)
            .allowsHitTesting(false))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
    private func bubble(_ turn: ConversationTurn) -> some View {
        let user = turn.speaker == "Bạn"
        return HStack(alignment: .top, spacing: 0) {
            if user { Spacer(minLength: 36) }
            VStack(alignment: .leading, spacing: 6) {
                Text(user ? "Bạn" : MascotIdentity.name).font(.system(size: 10, weight: .semibold)).foregroundStyle(TransToolsTheme.accent)
                Text(turn.text).font(.system(size: 13)).lineSpacing(3).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                if showTranslation, let translation = turn.translation, !translation.isEmpty {
                    Divider().overlay(TransToolsTheme.accent.opacity(0.12))
                    Text(translation).font(.system(size: 11)).lineSpacing(2).foregroundStyle(.secondary).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                }
            }.padding(11).background(user ? TransToolsTheme.mint : Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 14))
                .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(TransToolsTheme.accent.opacity(user ? 0.20 : 0.10), lineWidth: 1))
            if !user { Spacer(minLength: 36) }
        }
    }
}

private struct ConversationMiniCloseButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var enabled
    @State private var hovered = false

    func makeBody(configuration: Configuration) -> some View {
        let red = Color(red: 0.91, green: 0.27, blue: 0.30)
        return configuration.label
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(red)
            .background(Color.white.opacity(hovered ? 1 : 0.94), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(red.opacity(hovered ? 0.70 : 0.42), lineWidth: 1))
            .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .opacity(enabled ? (configuration.isPressed ? 0.72 : 1) : 0.45)
            .transToolsButtonCursor()
            .onHover { hovered = $0 }
    }
}
