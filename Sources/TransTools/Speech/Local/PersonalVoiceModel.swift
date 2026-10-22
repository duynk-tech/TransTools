import Foundation

/// Only backends whose personal voice pipeline has been integrated and verified.
/// A source recording is reusable; its derived profile belongs to one backend.
enum PersonalVoiceModel: String, CaseIterable, Identifiable, Hashable {
    case vieneu
    var id: String { rawValue }
    var title: String { "VieNeu-TTS v3 Turbo" }
    var isInstalled: Bool { ExternalTTSModel.vieneu.isInstalled }
    func file(_ profile: PersonalVoiceProfile, root: URL) -> URL {
        root.appendingPathComponent(profile.id.uuidString).appendingPathComponent("Models/" + rawValue + "/voice.json")
    }
    func existingFile(_ profile: PersonalVoiceProfile, root: URL) -> URL? {
        let modern = file(profile, root: root)
        if FileManager.default.fileExists(atPath: modern.path) { return modern }
        let legacy = root.appendingPathComponent(profile.id.uuidString).appendingPathComponent("voice.json")
        return FileManager.default.fileExists(atPath: legacy.path) ? legacy : nil
    }
}
