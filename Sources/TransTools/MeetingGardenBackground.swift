import SwiftUI
import AppKit

/// Static scenery refreshed only at time-of-day boundaries or when the app resumes.
struct MeetingGardenBackground: View {
    var timeOfDay: String = "auto"
    private enum Period {
        case morning, noon, afternoon, night
        static func current(_ date: Date = Date()) -> Period {
            switch Calendar.current.component(.hour, from: date) {
            case 5..<11: return .morning
            case 11..<15: return .noon
            case 15..<19: return .afternoon
            default: return .night
            }
        }
        var sky: [Color] {
            switch self {
            case .morning: return [Color(red: 0.94, green: 0.98, blue: 0.93), Color(red: 0.85, green: 0.94, blue: 0.89)]
            case .noon: return [Color(red: 0.88, green: 0.97, blue: 0.98), Color(red: 0.88, green: 0.96, blue: 0.89)]
            case .afternoon: return [Color(red: 0.99, green: 0.93, blue: 0.85), Color(red: 0.90, green: 0.94, blue: 0.88)]
            case .night: return [Color(red: 0.83, green: 0.88, blue: 0.95), Color(red: 0.86, green: 0.93, blue: 0.92)]
            }
        }
    }
    @State private var period = Period.current()

    private func nextBoundary() -> Date {
        let calendar = Calendar.current
        let now = Date()
        return [5, 11, 15, 19].compactMap {
            calendar.nextDate(after: now, matching: DateComponents(hour: $0, minute: 0, second: 0), matchingPolicy: .nextTime)
        }.min() ?? now.addingTimeInterval(3600)
    }

    var body: some View {
        let period: Period = timeOfDay == "morning" ? .morning : timeOfDay == "noon" ? .noon : timeOfDay == "afternoon" ? .afternoon : timeOfDay == "night" ? .night : self.period
        LinearGradient(colors: period.sky, startPoint: .top, endPoint: .bottom)
            .overlay {
                Canvas { context, size in
                    let scale = min(size.width / 1000, size.height / 500)
                    func ellipse(_ rect: CGRect, _ color: Color) {
                        context.fill(Path(ellipseIn: rect), with: .color(color))
                    }
                    func cloud(_ x: CGFloat, _ y: CGFloat, _ width: CGFloat) {
                        func p(_ u: CGFloat, _ v: CGFloat) -> CGPoint {
                            CGPoint(x: x + width * u, y: y + width * v)
                        }
                        var cloud = Path()
                        cloud.move(to: p(0.08,0.30))
                        cloud.addCurve(to: p(0.18,0.15), control1: p(-0.03,0.26), control2: p(0.01,0.14))
                        cloud.addCurve(to: p(0.48,0.07), control1: p(0.17,-0.01), control2: p(0.40,-0.04))
                        cloud.addCurve(to: p(0.72,0.13), control1: p(0.56,0.00), control2: p(0.70,0.03))
                        cloud.addCurve(to: p(0.92,0.22), control1: p(0.82,0.09), control2: p(0.95,0.13))
                        cloud.addCurve(to: p(0.89,0.31), control1: p(1.03,0.25), control2: p(0.98,0.32))
                        cloud.addCurve(to: p(0.08,0.30), control1: p(0.66,0.35), control2: p(0.30,0.34))
                        cloud.closeSubpath()
                        context.fill(cloud, with: .linearGradient(
                            Gradient(colors: [.white.opacity(0.86), Color(red: 0.91, green: 0.95, blue: 0.96).opacity(0.65)]),
                            startPoint: p(0.4,0), endPoint: p(0.4,0.35)))

                    }
                    let celestial = CGPoint(x: size.width * (period == .morning ? 0.18 : 0.84), y: size.height * (period == .afternoon ? 0.40 : 0.33))
                    let radius = (period == .noon ? 29.0 : 25.0) * scale
                    if period == .night {
                        ellipse(CGRect(x: celestial.x - radius * 1.6, y: celestial.y - radius * 1.6, width: radius * 3.2, height: radius * 3.2), .white.opacity(0.12))
                        var moon = Path()
                        moon.move(to: CGPoint(x: celestial.x + radius * 0.35, y: celestial.y - radius))
                        moon.addCurve(to: CGPoint(x: celestial.x + radius * 0.35, y: celestial.y + radius), control1: CGPoint(x: celestial.x - radius * 1.5, y: celestial.y - radius), control2: CGPoint(x: celestial.x - radius * 1.5, y: celestial.y + radius))
                        moon.addCurve(to: CGPoint(x: celestial.x + radius * 0.35, y: celestial.y - radius), control1: CGPoint(x: celestial.x - radius * 0.5, y: celestial.y + radius * 0.6), control2: CGPoint(x: celestial.x - radius * 0.5, y: celestial.y - radius * 0.6))
                        moon.closeSubpath()
                        context.fill(moon, with: .color(Color(red: 1, green: 0.98, blue: 0.87)))
                        for i in 0..<15 {
                            let x = size.width * (0.07 + CGFloat((i * 7) % 19) * 0.047)
                            let y = size.height * (0.06 + CGFloat((i * 11) % 7) * 0.045)
                            let r = CGFloat(i % 3 + 1) * scale
                            ellipse(CGRect(x: x, y: y, width: r, height: r), .white.opacity(0.85))
                        }
                    } else {
                        ellipse(CGRect(x: celestial.x - radius * 1.65, y: celestial.y - radius * 1.65, width: radius * 3.3, height: radius * 3.3), Color.yellow.opacity(0.10))
                        let sunlight = period == .afternoon ? Color(red: 0.96, green: 0.67, blue: 0.38) : Color(red: 0.98, green: 0.82, blue: 0.43)
                        ellipse(CGRect(x: celestial.x - radius, y: celestial.y - radius, width: radius * 2, height: radius * 2), sunlight.opacity(0.70))
                        var rays = Path()
                        for index in 0..<12 {
                            let angle = Double(index) * .pi / 6
                            let dx = CGFloat(cos(angle)), dy = CGFloat(sin(angle))
                            rays.move(to: CGPoint(x: celestial.x + dx * radius * 1.28, y: celestial.y + dy * radius * 1.28))
                            rays.addLine(to: CGPoint(x: celestial.x + dx * radius * 1.72, y: celestial.y + dy * radius * 1.72))
                        }
                        context.stroke(rays, with: .color(sunlight.opacity(0.85)), style: StrokeStyle(lineWidth: max(1, 2 * scale), lineCap: .round))
                    }
                    cloud(size.width * (period == .morning ? 0.33 : 0.1), size.height * 0.30, 110 * scale)
                    cloud(size.width * 0.71, size.height * 0.41, 90 * scale)
                    // Small birds in flight; static silhouettes keep meeting rendering quiet.
                    for (u, v, span) in [(0.54, 0.24, 15.0), (0.60, 0.20, 11.0), (0.66, 0.27, 13.0)] {
                        let center = CGPoint(x: size.width * u, y: size.height * v)
                        let wing = CGFloat(span) * scale
                        var bird = Path()
                        bird.move(to: CGPoint(x: center.x - wing, y: center.y - wing * 0.22))
                        bird.addQuadCurve(to: center, control: CGPoint(x: center.x - wing * 0.40, y: center.y - wing * 0.60))
                        bird.addQuadCurve(to: CGPoint(x: center.x + wing, y: center.y - wing * 0.32), control: CGPoint(x: center.x + wing * 0.35, y: center.y - wing * 0.65))
                        context.stroke(bird, with: .color(Color(red: 0.29, green: 0.46, blue: 0.49).opacity(period == .night ? 0.30 : 0.55)), style: StrokeStyle(lineWidth: max(1, 1.7 * scale), lineCap: .round, lineJoin: .round))
                    }
                    // Low hills frame the edges, leaving the central reading area clear.
                    ellipse(CGRect(x: -size.width * 0.2, y: size.height * 0.81, width: size.width * 0.65, height: size.height * 0.4), Color(red: 0.57, green: 0.77, blue: 0.66).opacity(0.18))
                    ellipse(CGRect(x: size.width * 0.7, y: size.height * 0.83, width: size.width * 0.5, height: size.height * 0.35), Color(red: 0.47, green: 0.71, blue: 0.61).opacity(0.16))
                    // Distant mountains and a narrow river remain static during meetings.
                    func landscapePoint(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
                        CGPoint(x: size.width * x, y: size.height * y)
                    }
                    var distantMountains = Path()
                    distantMountains.move(to: landscapePoint(0, 0.83))
                    distantMountains.addCurve(to: landscapePoint(0.18, 0.70), control1: landscapePoint(0.05, 0.82), control2: landscapePoint(0.10, 0.67))
                    distantMountains.addCurve(to: landscapePoint(0.32, 0.63), control1: landscapePoint(0.25, 0.73), control2: landscapePoint(0.26, 0.61))
                    distantMountains.addCurve(to: landscapePoint(0.48, 0.76), control1: landscapePoint(0.38, 0.60), control2: landscapePoint(0.41, 0.76))
                    distantMountains.addCurve(to: landscapePoint(0.65, 0.68), control1: landscapePoint(0.55, 0.77), control2: landscapePoint(0.57, 0.67))
                    distantMountains.addCurve(to: landscapePoint(0.83, 0.65), control1: landscapePoint(0.73, 0.73), control2: landscapePoint(0.75, 0.61))
                    distantMountains.addCurve(to: landscapePoint(1, 0.81), control1: landscapePoint(0.90, 0.63), control2: landscapePoint(0.93, 0.79))
                    distantMountains.addLine(to: landscapePoint(1, 0.91))
                    distantMountains.addLine(to: landscapePoint(0, 0.91))
                    distantMountains.closeSubpath()
                    context.fill(distantMountains, with: .linearGradient(
                        Gradient(colors: [Color(red: 0.65, green: 0.78, blue: 0.80).opacity(0.30), Color(red: 0.67, green: 0.82, blue: 0.75).opacity(0.16)]),
                        startPoint: landscapePoint(0.5, 0.57), endPoint: landscapePoint(0.5, 0.91)))
                    var foothills = Path()
                    foothills.move(to: landscapePoint(0, 0.86))
                    foothills.addCurve(to: landscapePoint(0.30, 0.77), control1: landscapePoint(0.11, 0.83), control2: landscapePoint(0.15, 0.73))
                    foothills.addCurve(to: landscapePoint(0.58, 0.85), control1: landscapePoint(0.39, 0.78), control2: landscapePoint(0.47, 0.86))
                    foothills.addCurve(to: landscapePoint(1, 0.80), control1: landscapePoint(0.77, 0.85), control2: landscapePoint(0.85, 0.72))
                    foothills.addLine(to: landscapePoint(1, 1))
                    foothills.addLine(to: landscapePoint(0, 1))
                    foothills.closeSubpath()
                    context.fill(foothills, with: .color(Color(red: 0.59, green: 0.77, blue: 0.67).opacity(0.22)))
                    var river = Path()
                    river.move(to: landscapePoint(0.60, 0.79))
                    river.addCurve(to: landscapePoint(0.49, 0.86), control1: landscapePoint(0.58, 0.82), control2: landscapePoint(0.46, 0.82))
                    river.addCurve(to: landscapePoint(0.65, 0.94), control1: landscapePoint(0.51, 0.90), control2: landscapePoint(0.66, 0.90))
                    river.addLine(to: landscapePoint(0.70, 0.96))
                    river.addCurve(to: landscapePoint(0.52, 0.85), control1: landscapePoint(0.75, 0.89), control2: landscapePoint(0.56, 0.90))
                    river.addCurve(to: landscapePoint(0.61, 0.79), control1: landscapePoint(0.49, 0.82), control2: landscapePoint(0.60, 0.82))
                    river.closeSubpath()
                    context.fill(river, with: .linearGradient(
                        Gradient(colors: [period.sky[0], Color(red: 0.69, green: 0.86, blue: 0.94).opacity(0.85)]),
                        startPoint: landscapePoint(0.6, 0.79), endPoint: landscapePoint(0.6, 0.96)))
                    context.stroke(river, with: .color(.white.opacity(0.35)), style: StrokeStyle(lineWidth: max(1, scale)))
                    func tree(_ x: CGFloat, _ bottom: CGFloat, _ height: CGFloat) {
                        func point(_ u: CGFloat, _ v: CGFloat) -> CGPoint {
                            CGPoint(x: x + u * height, y: bottom - v * height)
                        }
                        // A single irregular silhouette keeps the canopy cohesive.
                        let outline: [(CGFloat, CGFloat)] = [
                            (-0.10,0.97),(-0.06,1.02),(0.02,1.00),(0.07,0.96),
                            (0.14,0.97),(0.18,0.92),(0.23,0.91),(0.25,0.85),
                            (0.31,0.84),(0.33,0.78),(0.38,0.75),(0.36,0.69),
                            (0.41,0.64),(0.38,0.59),(0.39,0.53),(0.33,0.49),
                            (0.30,0.44),(0.23,0.43),(0.17,0.40),(0.10,0.43),
                            (0.02,0.40),(-0.04,0.43),(-0.12,0.41),(-0.18,0.45),
                            (-0.26,0.44),(-0.31,0.49),(-0.38,0.51),(-0.37,0.58),
                            (-0.42,0.62),(-0.39,0.68),(-0.40,0.73),(-0.34,0.76),
                            (-0.33,0.83),(-0.27,0.85),(-0.24,0.91),(-0.18,0.91),
                            (-0.15,0.97)
                        ]
                        var canopy = Path()
                        let first = outline[0], last = outline[outline.count - 1]
                        canopy.move(to: point((first.0 + last.0) / 2, (first.1 + last.1) / 2))
                        for i in outline.indices {
                            let current = outline[i], next = outline[(i + 1) % outline.count]
                            canopy.addQuadCurve(to: point((current.0 + next.0) / 2, (current.1 + next.1) / 2), control: point(current.0, current.1))
                        }
                        canopy.closeSubpath()
                        context.fill(canopy, with: .linearGradient(
                            Gradient(colors: [Color(red: 0.60, green: 0.79, blue: 0.61), Color(red: 0.33, green: 0.62, blue: 0.48)]),
                            startPoint: point(-0.2,1), endPoint: point(0.25,0.4)))
                        var trunk = Path()
                        trunk.move(to: point(-0.045,0)); trunk.addLine(to: point(-0.025,0.52))
                        trunk.addQuadCurve(to: point(0.015,0.73), control: point(-0.04,0.65))
                        trunk.addLine(to: point(0.025,0.48)); trunk.addLine(to: point(0.045,0))
                        trunk.closeSubpath()
                        let bark = Color(red: 0.48, green: 0.52, blue: 0.38).opacity(0.65)
                        context.fill(trunk, with: .color(bark))
                        var branches = Path()
                        branches.move(to: point(0,0.39)); branches.addQuadCurve(to: point(-0.21,0.65), control: point(-0.09,0.53))
                        branches.move(to: point(0,0.48)); branches.addQuadCurve(to: point(0.22,0.72), control: point(0.12,0.56))
                        context.stroke(branches, with: .color(bark), style: StrokeStyle(lineWidth: height * 0.018, lineCap: .round))
                        // Small tapered leaves add texture without overlapping circles.
                        for i in 0..<22 {
                            let u = CGFloat((i * 7) % 13 - 6) * 0.043
                            let v = 0.55 + CGFloat((i * 11) % 9) * 0.043
                            var leaf = Path()
                            leaf.move(to: point(u - 0.025,v))
                            leaf.addQuadCurve(to: point(u + 0.035,v + 0.025), control: point(u - 0.015,v + 0.055))
                            leaf.addQuadCurve(to: point(u - 0.025,v), control: point(u + 0.02,v - 0.018))
                            context.fill(leaf, with: .color(Color.white.opacity(0.12)))
                        }

                    }
                    tree(size.width * 0.09, size.height * 0.88, 125 * scale)
                    tree(size.width * 0.91, size.height * 0.88, 100 * scale)
                    tree(size.width * 0.96, size.height * 0.89, 65 * scale)
                }
                .accessibilityHidden(true)
            }
            .allowsHitTesting(false)
            .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
                self.period = Period.current()
            }
            .task {
                while !Task.isCancelled {
                    self.period = Period.current()
                    let delay = max(1, nextBoundary().timeIntervalSinceNow)
                    do { try await Task.sleep(for: .seconds(delay)) }
                    catch { return }
                }
            }
    }
}
