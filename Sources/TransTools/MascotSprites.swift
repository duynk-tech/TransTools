import AppKit
import SwiftUI

enum MascotFacing: String, CaseIterable {
    case front, frontRight = "front_right", right, backRight = "back_right"
    case back, backLeft = "back_left", left, frontLeft = "front_left"

    /// Turn through the front while pausing at a screen edge.
    static func turning(elapsed: TimeInterval, towardRight: Bool) -> MascotFacing {
        let sequence: [MascotFacing] = towardRight
            ? [.left, .frontLeft, .front, .frontRight, .right]
            : [.right, .frontRight, .front, .frontLeft, .left]
        let index = min(sequence.count - 1, max(0, Int(elapsed / 0.28)))
        return sequence[index]
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
        let frames = (0..<8).compactMap { load(String(format: "walk_%@_%02d", direction, $0), directory: "MascotSprites/walk_\(direction)") }
        // Do not run a partial cycle if the bundle is missing a frame.
        return frames.count == 8 ? frames : []
    }
}

struct MascotAngleView: View {
    let facing: MascotFacing
    let size: CGFloat

    var body: some View {
        Group {
            if let image = MascotSpriteLibrary.angles[facing] {
                Image(nsImage: image).resizable().interpolation(.high).scaledToFit()
            } else if let image = MascotSpriteLibrary.angles[.front] {
                Image(nsImage: image).resizable().interpolation(.high).scaledToFit()
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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var cycleStart = Date()

    var body: some View {
        TimelineView(.animation(minimumInterval: 0.1, paused: reduceMotion)) { context in
            let frames = towardRight ? MascotSpriteLibrary.walkRight : MascotSpriteLibrary.walkLeft
            let elapsed = max(0, context.date.timeIntervalSince(cycleStart))
            if !reduceMotion, frames.count == 8 {
                let index = Int(elapsed * 10) % frames.count
                Image(nsImage: frames[index])
                    .resizable().interpolation(.high).scaledToFit()
                    .frame(width: size * (621.0 / 783.0), height: size)
            } else {
                MascotAngleView(facing: towardRight ? .right : .left, size: size)
            }
        }
        .accessibilityLabel(towardRight ? "Mascot đi sang phải" : "Mascot đi sang trái")
    }
}

struct MascotSpritePreviewView: View {
    @State private var dark = true
    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            HStack {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Bộ chuyển động mascot").font(.title.bold())
                    Text("8 góc nhìn · 16 frame đi bộ · 10 frame/giây").foregroundStyle(.secondary)
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
        .padding(30).frame(minWidth: 960, minHeight: 590)
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
