import AppKit
import CoreGraphics

/// Local context only: never reads keyboard content or sends activity data.
enum MascotIdlePolicy {
    static let idleThreshold: TimeInterval = 45

    static var systemIdleSeconds: TimeInterval {
        let seconds = CGEventSource.secondsSinceLastEventType(
            .combinedSessionState, eventType: CGEventType(rawValue: UInt32.max)!)
        return seconds.isFinite ? max(0, seconds) : 0
    }

    static func activity(idleSeconds: TimeInterval, hour: Int,
                         foregroundBundle: String, conservingEnergy: Bool,
                         heardAudioRecently: Bool) -> MascotIdleActivity {
        guard idleSeconds >= idleThreshold else { return .auto }
        let night = hour >= 22 || hour < 7
        if !heardAudioRecently && idleSeconds >= 180 && night { return .sleeping }
        if conservingEnergy { return idleSeconds >= 300 && !heardAudioRecently ? .sleeping : .thinking }
        // Long dwell times avoid abruptly cycling through unrelated scenes.
        let slot = Int(max(0, idleSeconds - idleThreshold) / 75)
        let bundle = foregroundBundle.lowercased()
        let isReadingOrWriting = ["notes", "word", "pages", "code", "xcode", "excel", "antigravity", "mail"].contains { bundle.contains($0) }
        let activities: [MascotIdleActivity]
        if heardAudioRecently {
            activities = [.thinking, .writing]
        } else if night {
            activities = [.thinking, .sippingTea]
        } else if isReadingOrWriting {
            activities = [.writing, .thinking, .sippingTea, .strolling]
        } else if (7..<10).contains(hour) || (14..<16).contains(hour) {
            activities = [.sippingTea, .pickingFlowers, .catchingButterfly, .strolling]
        } else if idleSeconds >= 600 {
            activities = [.fishing, .strolling, .pickingFlowers, .catchingButterfly]
        } else {
            activities = [.pickingFlowers, .catchingButterfly, .strolling, .thinking]
        }
        return activities[slot % activities.count]
    }
}
