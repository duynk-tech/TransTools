import XCTest
@testable import TransTools

final class LanguageVoicePreferencesTests: XCTestCase {
    func testLanguageOverridesAreIndependentAndNormalizeRegions() {
        let suite = "TTS-test-" + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        LanguageVoicePreferences.set(.local, for: "vi-VN", defaults: defaults)
        LanguageVoicePreferences.set(.edge, for: "zh_CN", defaults: defaults)
        XCTAssertEqual(LanguageVoicePreferences.selection(for: "vi", defaults: defaults), .local)
        XCTAssertEqual(LanguageVoicePreferences.selection(for: "zh-TW", defaults: defaults), .edge)
        XCTAssertEqual(LanguageVoicePreferences.selection(for: "en-US", defaults: defaults), .automatic)
    }
    func testExplicitChoiceOverridesGlobalDefault() {
        XCTAssertEqual(LanguageVoicePreferences.resolve(.system, localDefault: true, edgeDefault: true), .system)
        XCTAssertEqual(LanguageVoicePreferences.resolve(.edge, localDefault: true, edgeDefault: false), .edge)
        XCTAssertEqual(LanguageVoicePreferences.resolve(.automatic, localDefault: true, edgeDefault: true), .local)
    }
    func testSpecializedModelsNeverRouteAnUnsupportedLanguage() {
        XCTAssertTrue(LanguageVoiceEngine.vieneu.supports("vi-VN"))
        XCTAssertFalse(LanguageVoiceEngine.vieneu.supports("en-US"))
        XCTAssertFalse(LanguageVoiceEngine.vieneu.supports("zh-CN"))
        XCTAssertEqual(LanguageVoiceEngine.vieneu.externalModel, .vieneu)
        XCTAssertEqual(LanguageVoiceEngine.qwen.externalModel, .qwen)
        XCTAssertTrue(LanguageVoiceEngine.qwen.isLocal)
        XCTAssertFalse(LanguageVoiceEngine.edge.isLocal)
    }
}
