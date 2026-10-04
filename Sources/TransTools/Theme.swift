import SwiftUI
import AppKit

/// Shared mint, teal and navy palette; maintain contrast in macOS dark appearance.
enum TransToolsTheme {
    static let accent = adaptive(light: (40, 117, 104), dark: (112, 205, 182))
    static let navy = adaptive(light: (32, 52, 81), dark: (172, 198, 226))
    static let background = adaptive(light: (246, 248, 246), dark: (25, 32, 36))
    static let mint = adaptive(light: (225, 238, 230), dark: (38, 61, 54))

    private static func adaptive(light: (Double, Double, Double), dark: (Double, Double, Double)) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let rgb = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
            return NSColor(srgbRed: rgb.0 / 255, green: rgb.1 / 255, blue: rgb.2 / 255, alpha: 1)
        })
    }
}

/// Shared action controls: 40pt tall, with mint secondary and teal primary actions.
struct TransToolsActionButtonStyle: ButtonStyle {
    var prominent = false
    var tint: Color = TransToolsTheme.accent
    var height: CGFloat = 40
    @Environment(\.isEnabled) private var enabled
    func makeBody(configuration: Configuration) -> some View {
        Action(configuration: configuration, prominent: prominent, tint: tint, height: height, enabled: enabled)
    }
    private struct Action: View {
        let configuration: ButtonStyleConfiguration
        let prominent: Bool
        let tint: Color
        let height: CGFloat
        let enabled: Bool
        @State private var hovered = false
        private var color: Color { configuration.role == .destructive ? .red : tint }
        private var cornerRadius: CGFloat { height <= 26 ? 6 : (height <= 30 ? 8 : 10) }
        private var horizontalPadding: CGFloat { height <= 26 ? 10 : (height <= 30 ? 12 : 16) }
        var body: some View {
            configuration.label
                .font(.system(size: height <= 26 ? 12 : (height <= 30 ? 12 : 12.5), weight: height <= 26 ? .medium : .semibold))
                .symbolRenderingMode(.monochrome)
                .lineLimit(1)
                .padding(.horizontal, horizontalPadding)
                .frame(height: height)
                .foregroundStyle(prominent ? Color.white : color)
                .background(prominent ? (configuration.role == .destructive ? Color.red : Color(red: 40 / 255, green: 117 / 255, blue: 104 / 255)) : color.opacity(hovered ? 0.12 : 0.07), in: RoundedRectangle(cornerRadius: cornerRadius))
                .overlay(RoundedRectangle(cornerRadius: cornerRadius).stroke(color.opacity(prominent ? 0 : 0.18), lineWidth: 1))
                .contentShape(RoundedRectangle(cornerRadius: cornerRadius))
                .opacity(enabled ? (configuration.isPressed ? 0.75 : 1) : 0.4)
                .textSelection(.disabled)
                .transToolsButtonCursor()
                .onHover { hovered = $0 }
        }
    }
}

extension View {
    func transToolsPanel() -> some View {
        self.background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(TransToolsTheme.accent.opacity(0.14), lineWidth: 1))
    }
}

/// Reset an inherited I-beam when moving directly from a text field to a
/// custom SwiftUI button. Continuous hover also handles movement over labels.
private struct TransToolsButtonCursor: ViewModifier {
    @Environment(\.isEnabled) private var enabled
    func body(content: Content) -> some View {
        content.onContinuousHover { phase in
            switch phase {
            case .active: (enabled ? NSCursor.pointingHand : NSCursor.arrow).set()
            case .ended: NSCursor.arrow.set()
            }
        }
    }
}

extension View {
    func transToolsButtonCursor() -> some View {
        modifier(TransToolsButtonCursor())
    }
}
