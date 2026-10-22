import SwiftUI

/// Static, topic-specific accents: no timers or animation render loop.
struct ConversationScenery: View {
    let topic: ConversationTopic
    private var accents: [String] {
        switch topic {
        case .everyday: return ["cat.fill", "leaf.fill", "bird.fill"]
        case .work, .interview: return ["building.2.fill", "leaf.fill", "sun.max.fill"]
        case .travel: return ["airplane", "mountain.2.fill", "bird.fill"]
        case .technology: return ["desktopcomputer", "network", "building.2.fill", "leaf.fill"]
        case .study: return ["books.vertical.fill", "pencil", "bird.fill", "leaf.fill"]
        case .custom: return ["leaf.fill", "bird.fill", "cat.fill", "sun.max.fill"]
        }
    }
    var body: some View {
        MeetingGardenBackground()
            .overlay {
                GeometryReader { geometry in
                    ForEach(Array(accents.enumerated()), id: \.offset) { index, symbol in
                        Image(systemName: symbol)
                            .font(.system(size: index == 2 ? 38 : 28, weight: .regular))
                            .foregroundStyle(TransToolsTheme.accent.opacity(0.18))
                            .position(x: geometry.size.width * [0.08, 0.91, 0.88, 0.14][index],
                                      y: geometry.size.height * [0.76, 0.57, 0.87, 0.25][index])
                    }
                    // Small flowers occupy only the edges; the reading area stays clear.
                    ForEach(0..<6) { index in
                        Image(systemName: "camera.macro")
                            .font(.system(size: 16))
                            .foregroundStyle(Color(red: 0.77, green: 0.48, blue: 0.59).opacity(0.28))
                            .position(x: geometry.size.width * (index < 3 ? 0.04 + Double(index) * 0.025 : 0.91 + Double(index - 3) * 0.025), y: geometry.size.height * 0.93)
                    }
                }
            }
            .overlay(Color.white.opacity(0.30))
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}
