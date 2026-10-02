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
