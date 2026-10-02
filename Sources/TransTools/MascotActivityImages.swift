import AppKit

@MainActor enum MascotActivityImages {
    static let images: [String: NSImage] = {
        var result: [String: NSImage] = [:]
        for name in ["coffee", "writing", "thinking", "strolling", "flowers", "sleeping"] {
            let url = Bundle.main.resourceURL?.appendingPathComponent("MascotActivities/\(name).png") ?? URL(fileURLWithPath: "Resources/MascotActivities/\(name).png")
            if let image = NSImage(contentsOf: url) { result[name] = image }
        }
        return result
    }()
    private struct Clip {
        let frames: [NSImage]
        let fps: Double
    }
    private static let clips: [String: Clip] = {
        let base = Bundle.main.resourceURL?.appendingPathComponent("MascotActivities/animations")
            ?? URL(fileURLWithPath: "Resources/MascotActivities/animations")
        guard let data = try? Data(contentsOf: base.appendingPathComponent("manifest.json")),
              let manifest = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let entries = manifest["clips"] as? [String: [String: Any]] else { return [:] }
        var result: [String: Clip] = [:]
        for (name, entry) in entries {
            guard let files = entry["frames"] as? [String], !files.isEmpty,
                  let fps = entry["fps"] as? Double, fps.isFinite, fps > 0 else { continue }
            let frames = files.compactMap { NSImage(contentsOf: base.appendingPathComponent($0)) }
            if frames.count == files.count { result[name] = Clip(frames: frames, fps: fps) }
        }
        return result
    }()
    private static func clipName(_ activity: MascotIdleActivity) -> String? {
        switch activity {
        case .pickingFlowers: return "flowers"
        case .catchingButterfly: return "butterfly"
        case .writing: return "writing"
        case .sleeping: return "sleeping"
        default: return nil
        }
    }
    static func hasAnimation(_ activity: MascotIdleActivity) -> Bool {
        clipName(activity).flatMap { clips[$0] } != nil
    }
    static func image(activity: MascotIdleActivity, working: Bool, sleeping: Bool,
                      time: Double? = nil, reduceMotion: Bool = false) -> NSImage? {
        let name = sleeping ? "sleeping" : (working ? "writing" : clipName(activity))
        if let name, let clip = clips[name] {
            let elapsed = time ?? Date().timeIntervalSinceReferenceDate
            let phase = elapsed.isFinite ? max(0, elapsed.truncatingRemainder(dividingBy: Double(clip.frames.count) / clip.fps)) : 0
            let index = reduceMotion ? 0 : min(clip.frames.count - 1, Int(phase * clip.fps))
            return clip.frames[index]
        }
        if sleeping { return images["sleeping"] }
        if working { return images["writing"] }
        switch activity {
        case .sippingTea: return images["coffee"]
        case .writing: return images["writing"]
        case .thinking: return images["thinking"]
        case .pickingFlowers, .catchingButterfly: return images["flowers"]
        default: return nil // Keep animated walk and existing fallback poses.
        }
    }
}
