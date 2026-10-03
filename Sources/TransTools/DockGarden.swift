import AppKit
import SwiftUI

/// A separate, click-through scenery strip. The mascot remains draggable above it.
@MainActor final class DockGardenController {
    private var panel: NSPanel?

    func update(screen: NSScreen, mascot: NSWindow, visible: Bool) {
        hide()
    }

    func hide() {
        panel?.orderOut(nil)
        panel?.contentView = nil // Release the animation timeline while hidden.
        panel = nil
    }
}

struct DockGardenView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 24, paused: reduceMotion)) { tick in
            let time = reduceMotion ? 0 : tick.date.timeIntervalSinceReferenceDate
            ZStack(alignment: .topTrailing) {
                MascotOutdoorSky(time: time)
                    .offset(x: -18, y: 55)
            Canvas { context, size in
                let groundY = size.height - 18
                let ground = CGRect(x: 0, y: groundY - 5, width: size.width, height: 13)
                context.fill(Path(roundedRect: ground, cornerRadius: 7), with: .linearGradient(
                    Gradient(colors: [Color(red: 0.80, green: 0.94, blue: 0.86).opacity(0.82),
                                      Color(red: 0.37, green: 0.68, blue: 0.46).opacity(0.42)]),
                    startPoint: CGPoint(x: 0, y: groundY - 5), endPoint: CGPoint(x: 0, y: groundY + 8)))
                let patches = max(3, Int(size.width / 95))
                for i in 0..<patches {
                    let x = (CGFloat(i) + 0.5) * size.width / CGFloat(patches)
                    let sway = CGFloat(sin(time * 0.7 + Double(i))) * 1.5
                    for blade in 0..<4 {
                        let bx = x + CGFloat(blade - 2) * 3
                        var grass = Path();grass.move(to: CGPoint(x: bx, y: groundY))
                        grass.addQuadCurve(to: CGPoint(x: bx + CGFloat(blade - 2) + sway, y: groundY - CGFloat(6 + blade * 2)),
                                           control: CGPoint(x: bx, y: groundY - 5))
                        context.stroke(grass, with: .color(Color(red: 0.29, green: 0.57, blue: 0.34).opacity(0.85)), lineWidth: 1.2)
                    }
                    if i % 2 == 0 {
                        let bloom = CGPoint(x: x + 15 + sway, y: groundY - CGFloat(14 + i % 3 * 3))
                        var stem = Path();stem.move(to: CGPoint(x: x + 15, y: groundY));stem.addLine(to: bloom)
                        context.stroke(stem, with: .color(.green.opacity(0.65)), lineWidth: 1.2)
                        for petal in 0..<5 {
                            let angle = Double(petal) * .pi * 2 / 5
                            let rect = CGRect(x: bloom.x + CGFloat(cos(angle)) * 3 - 2.5,
                                              y: bloom.y + CGFloat(sin(angle)) * 3 - 2.5, width: 5, height: 5)
                            context.fill(Path(ellipseIn: rect), with: .color(i % 4 == 0 ? Color(red: 1, green: 0.66, blue: 0.78) : .white.opacity(0.95)))
                        }
                        context.fill(Path(ellipseIn: CGRect(x: bloom.x - 1.8, y: bloom.y - 1.8, width: 3.6, height: 3.6)), with: .color(.yellow))
                    }
                    if i % 4 == 1 {
                        let bx = x + CGFloat(sin(time * 0.45 + Double(i))) * 17
                        let by = groundY - 31 + CGFloat(sin(time * 0.8 + Double(i))) * 5
                        let wing = CGFloat(2.3 + abs(sin(time * 4)) * 2.5)
                        for side in [-1.0, 1.0] {
                            context.fill(Path(ellipseIn: CGRect(x: bx + CGFloat(side) * wing - wing / 2,
                                                               y: by - 4, width: wing, height: 8)),
                                         with: .color(side < 0 ? .cyan.opacity(0.85) : .purple.opacity(0.65)))
                        }
                        context.stroke(Path(CGRect(x: bx, y: by - 2, width: 0.8, height: 5)), with: .color(.indigo), lineWidth: 0.8)
                    }
                }
                // Two small birds follow bounded arcs along different parts of the strip.
                for i in 0..<2 {
                    let center = size.width * (i == 0 ? 0.28 : 0.74)
                    let x = center + CGFloat(sin(time * 0.19 + Double(i) * 2)) * min(65, size.width * 0.08)
                    let y = groundY - 48 + CGFloat(sin(time * 0.55 + Double(i))) * 4
                    context.draw(Text(Image(systemName: "bird.fill")).font(.system(size: 11))
                        .foregroundColor(Color(red: 0.44, green: 0.60, blue: 0.72).opacity(0.85)),
                                 at: CGPoint(x: x, y: y))
                }
            }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
