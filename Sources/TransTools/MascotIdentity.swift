import Foundation
import Observation

@Observable
final class MascotIdentity {
    static let shared = MascotIdentity()
    static let defaultName = "Chip Chip"
    var customName: String {
        didSet {
            let cleaned = Self.clean(customName)
            if cleaned != customName { customName = cleaned }
            UserDefaults.standard.set(cleaned, forKey: "Mascot_CustomName")
        }
    }
    static func clean(_ value: String) -> String {
        String(value.filter { !$0.isNewline && $0 != "[" && $0 != "]" && !$0.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) }.prefix(24))
    }
    static var name: String {
        let value = shared.customName.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? defaultName : value
    }
    private init() {
        customName = Self.clean(UserDefaults.standard.string(forKey: "Mascot_CustomName") ?? "")
    }
}
