import AppKit

@MainActor enum MascotActivityImages {
    static let images: [String: NSImage] = {
        var result: [String: NSImage] = [:]
        for name in ["coffee", "writing", "thinking", "strolling", "flowers", "sleeping"] {
            let url = Bundle.main.resourceURL?.appendingPathComponent("MascotActivities/\(name).png") ?? URL(fileURLWithPath: "Resources/MascotActivities/\(name).png")
            if let data = try? Data(contentsOf: url), let image = NSImage(data: data) { result[name] = image }
        }
        return result
    }()
    static func hasAnimation(_ activity: MascotIdleActivity) -> Bool {
        imageName(activity).flatMap { images[$0] } != nil
    }
    private static func imageName(_ activity: MascotIdleActivity) -> String? {
        switch activity {
        case .sippingTea: return "coffee"
        case .writing: return "writing"
        case .thinking: return "thinking"
        case .pickingFlowers, .catchingButterfly: return "flowers"
        case .strolling: return "strolling"
        case .sleeping: return "sleeping"
        default: return nil
        }
    }
    static func image(activity: MascotIdleActivity, working: Bool, sleeping: Bool,
                      walking: Bool = false, time: Double? = nil, reduceMotion: Bool = false) -> NSImage? {
        let name = sleeping ? "sleeping" : (working ? "writing" : (walking ? "strolling" : imageName(activity)))
        return name.flatMap { images[$0] }
    }
}

// Eagerly load encoded image bytes once. NSImage no longer depends on a file URL
// when a view renders. Avoid decoding every animation to full-size bitmaps at
// startup: retaining all decoded frames would unnecessarily increase RSS.
@MainActor enum MascotResourceImages {
    static let images: [String: NSImage] = {
        var result: [String: NSImage] = [:]
        for name in ["AppIcon", "Mini", "Mascot3D", "MascotSeedling", "MascotBody", "MascotLegLeft",
                     "MascotLegRight", "MascotSleeping", "MascotWriting", "MascotBack", "MascotWalking"] {
            if let url = Bundle.main.url(forResource: name, withExtension: "png"),
               let data = try? Data(contentsOf: url), let image = NSImage(data: data) {
                result[name] = image
            }
        }
        return result
    }()
    static func preload() {
        _ = images
        _ = MascotActivityImages.images
        _ = MascotSpriteLibrary.angles
        _ = MascotSpriteLibrary.walkRight
        _ = MascotSpriteLibrary.walkLeft
    }
}
