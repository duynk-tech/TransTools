import XCTest
@testable import TransTools

final class ModelRoutingTests: XCTestCase {
    func testExplicitProviderAndLocalFallback() {
        XCTAssertEqual(LanguageVoicePreferences.route(requested: .vieneu, available: [.local, .vieneu]), .vieneu)
        XCTAssertEqual(LanguageVoicePreferences.route(requested: .local, available: [.local, .vieneu]), .local)
        XCTAssertEqual(LanguageVoicePreferences.route(requested: .vieneu, available: [.local]), .local)
        XCTAssertEqual(LanguageVoicePreferences.route(requested: .local, available: [.vieneu]), .vieneu)
        XCTAssertEqual(LanguageVoicePreferences.route(requested: .local, available: []), .system)
        XCTAssertEqual(LanguageVoicePreferences.route(requested: .edge, available: [.local]), .edge)
        XCTAssertEqual(LanguageVoicePreferences.route(requested: .system, available: [.vieneu]), .system)
    }
}
