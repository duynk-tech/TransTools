import AppKit
import SwiftUI

enum MascotFacing: String, CaseIterable {
    case front, frontRight = "front_right", right, backRight = "back_right"
    case back, backLeft = "back_left", left, frontLeft = "front_left"

    /// All 8 angles ordered clockwise starting from front
    static let clockwise: [MascotFacing] = [
        .front, .frontRight, .right, .backRight,
        .back, .backLeft, .left, .frontLeft
    ]

    /// Turn through the front with expressive timing curve
    static func turning(elapsed: TimeInterval, towardRight: Bool) -> MascotFacing {
        let t = max(0, min(1.2, elapsed))
        if towardRight {
            // Quay từ trái sang phải qua hướng nhìn thẳng
            if t < 0.20 { return .left }
            else if t < 0.45 { return .frontLeft }
            else if t < 0.85 { return .front }
            else if t < 1.05 { return .frontRight }
            else { return .right }
        } else {
            // Quay từ phải sang trái qua hướng nhìn thẳng
            if t < 0.20 { return .right }
            else if t < 0.45 { return .frontRight }
            else if t < 0.85 { return .front }
            else if t < 1.05 { return .frontLeft }
            else { return .left }
        }
    }

    /// Full 360-degree pirouette spin using all 8 angles
    static func spin(elapsed: TimeInterval, duration: TimeInterval = 0.72) -> MascotFacing {
        let count = clockwise.count
        let step = duration / Double(count)
        let index = min(count - 1, max(0, Int(elapsed / step) % count))
        return clockwise[index]
    }

    /// Turn smoothly from front to back (e.g. entering fishing activity)
    static func turningToBack(elapsed: TimeInterval, duration: TimeInterval = 0.8, fromRight: Bool = true) -> MascotFacing {
        let sequence: [MascotFacing] = fromRight
            ? [.front, .frontRight, .right, .backRight, .back]
            : [.front, .frontLeft, .left, .backLeft, .back]
        let step = duration / Double(sequence.count)
        let index = min(sequence.count - 1, max(0, Int(elapsed / step)))
        return sequence[index]
    }

    /// Turn smoothly from back to front (e.g. exiting fishing activity)
    static func turningFromBack(elapsed: TimeInterval, duration: TimeInterval = 0.8, toRight: Bool = false) -> MascotFacing {
        let sequence: [MascotFacing] = toRight
            ? [.back, .backRight, .right, .frontRight, .front]
            : [.back, .backLeft, .left, .frontLeft, .front]
        let step = duration / Double(sequence.count)
        let index = min(sequence.count - 1, max(0, Int(elapsed / step)))
        return sequence[index]
    }

    /// Idle look-around: glancing left, right, and returning to front naturally
    static func idleLookAround(time: Double) -> MascotFacing? {
        let cycle = time.truncatingRemainder(dividingBy: 24)
        // Mostly face the user; glance through three-quarter views, then return.
        if cycle >= 3 && cycle < 6 {
            let t = cycle - 3
            if t < 0.85 || t >= 1.45 { return .frontLeft }
            return .left
        }
        if cycle >= 14 && cycle < 17 {
            let t = cycle - 14
            if t < 0.85 || t >= 1.45 { return .frontRight }
            return .right
        }
        return nil
    }
}

@MainActor enum MascotSpriteLibrary {
    // Load each PNG once, not once per TimelineView update.
    static let angles: [MascotFacing: NSImage] = {
        var result: [MascotFacing: NSImage] = [:]
        for facing in MascotFacing.allCases {
            if let image = load("angle_\(facing.rawValue)", directory: "MascotSprites/angles") {
                result[facing] = image
            }
        }
        return result
    }()
    static let walkRight = walkFrames(direction: "right")
    static let walkLeft = walkFrames(direction: "left")

    private static func load(_ name: String, directory: String) -> NSImage? {
        if let url = Bundle.main.url(forResource: name, withExtension: "png", subdirectory: directory),
           let img = NSImage(contentsOf: url) {
            return img
        }
        if let resURL = Bundle.main.resourceURL?.appendingPathComponent("\(directory)/\(name).png"),
           FileManager.default.fileExists(atPath: resURL.path),
           let img = NSImage(contentsOf: resURL) {
            return img
        }
        let fallbackPath = "Resources/\(directory)/\(name).png"
        if FileManager.default.fileExists(atPath: fallbackPath),
           let img = NSImage(contentsOfFile: fallbackPath) {
            return img
        }
        return nil
    }
    private static func walkFrames(direction: String) -> [NSImage] {
        let frames = (0..<32).compactMap { load(String(format: "walk_%@_%02d", direction, $0), directory: "MascotSprites/walk_\(direction)") }
        // Do not run a partial cycle if the bundle is missing a frame.
        return frames.count == 32 ? frames : []
    }
}

struct MascotAngleView: View {
    let facing: MascotFacing
    let size: CGFloat

    var body: some View {
        Group {
            if let image = MascotSpriteLibrary.angles[facing] ?? MascotSpriteLibrary.angles[.front] {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
            } else {
                AnimatedMascot3DView(size: size, legSwing: 0)
            }
        }
        .frame(width: size * (621.0 / 783.0), height: size)
        .accessibilityLabel("Mascot \(facing.rawValue)")
    }
}

struct MascotWalkSpriteView: View {
    let size: CGFloat
    let towardRight: Bool
    var distance: CGFloat? = nil
    var time: Double? = nil
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var cycleStart = Date()

    var body: some View {
        // Parent-driven walk already supplies time/distance; do not create a
        // second display refresh loop for the same animation.
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: reduceMotion || time != nil || distance != nil)) { context in
            let frames = towardRight ? MascotSpriteLibrary.walkRight : MascotSpriteLibrary.walkLeft
            if !reduceMotion, !frames.isEmpty {
                let count = frames.count
                let frameIndex: Int = {
                    if let dist = distance {
                        let strideLength = max(1.0, size * 0.325)
                        let progress = fmod(Double(dist / strideLength), 1.0)
                        let normalized = progress < 0 ? (progress + 1.0) : progress
                        return Int(normalized * Double(count)) % count
                    } else {
                        let t = time ?? max(0, context.date.timeIntervalSince(cycleStart))
                        let strideFreq = 0.82 // Nhịp bước chân tự nhiên dễ thương (~1.6 bước/s)
                        let progress = fmod(t * strideFreq, 1.0)
                        let normalized = progress < 0 ? (progress + 1.0) : progress
                        return Int(normalized * Double(count)) % count
                    }
                }()
                Image(nsImage: frames[frameIndex])
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
                    .frame(width: size * (621.0 / 783.0), height: size)
            } else {
                MascotAngleView(facing: towardRight ? .right : .left, size: size)
            }
        }
        .accessibilityLabel(towardRight ? "Mascot đi sang phải" : "Mascot đi sang trái")
    }
}

struct MascotSpritePreviewView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var dark = true
    @State private var previewActivity = "tea"
    var body: some View {
        ScrollView {
        VStack(alignment: .leading, spacing: 24) {
            HStack {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Bộ chuyển động mascot").font(.title.bold())
                    Text("8 góc nhìn · 64 frame đi bộ · chuyển động theo quãng đường").foregroundStyle(.secondary)
                }
                Spacer()
                Toggle("Nền tối", isOn: $dark).toggleStyle(.switch)
            }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 8), spacing: 12) {
                ForEach(MascotFacing.allCases, id: \.self) { angle in
                    VStack(spacing: 8) {
                        MascotAngleView(facing: angle, size: 110)
                        Text(angle.rawValue).font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            Divider()
            HStack {
                RealtimeMascotView(reduceMotion: reduceMotion).frame(width: 165, height: 210)
                RealtimeMascotView(walking: true, towardRight: false, reduceMotion: reduceMotion).frame(width: 165, height: 210)
                RealtimeMascotView(walking: true, reduceMotion: reduceMotion).frame(width: 165, height: 210)
                Text("RealityKit · hình học 3D và khớp chân trực tiếp")
            }
            HStack {
                RealtimeMascotView(reduceMotion: reduceMotion, activity: previewActivity)
                    .frame(width: 210, height: 265)
                VStack(alignment: .leading) {
                    Text("Hoạt động 3D").font(.headline)
                    Picker("Dáng", selection: $previewActivity) {
                        Text("Cà phê").tag("tea")
                        Text("Ghi chép").tag("writing")
                        Text("Suy nghĩ").tag("thinking")
                        Text("Hái hoa").tag("flowers")
                        Text("Bắt bướm").tag("butterfly")
                        Text("Nằm ngủ").tag("sleeping")
                    }.frame(width: 220)
                }
            }
            HStack(spacing: 80) {
                Spacer()
                VStack(spacing: 12) {
                    MascotWalkSpriteView(size: 210, towardRight: false)
                    Text("Đi sang trái")
                }
                VStack(spacing: 12) {
                    MascotWalkSpriteView(size: 210, towardRight: true)
                    Text("Đi sang phải")
                }
                Spacer()
            }
            Text("Bộ này dùng trong chế độ Đi dạo Dock. Khi bật Giảm chuyển động của macOS, chu kỳ bước chân hiển thị thành dáng đứng.")
                .font(.callout).foregroundStyle(.secondary)
        }
        .padding(30)
        }
        .frame(minWidth: 960, minHeight: 590)
        .background(dark ? Color(red: 0.07, green: 0.12, blue: 0.18) : Color(red: 0.95, green: 0.97, blue: 0.99))
        .environment(\.colorScheme, dark ? .dark : .light)
    }
}

struct MascotSpriteCommands: Commands {
    @Environment(\.openWindow) private var openWindow
    var body: some Commands {
        CommandGroup(after: .windowArrangement) {
            Button("Xem bộ chuyển động mascot") { openWindow(id: "mascot-sprites") }
        }
    }
}
