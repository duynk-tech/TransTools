import Foundation

/// Preserves the last decodable snapshot before replacing the live notebook.
enum SessionStore {
    struct Snapshot {
        let sessions: [MeetingSession]
        let recovered: Bool
    }

    private static func decode(_ url: URL) throws -> [MeetingSession] {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode([MeetingSession].self, from: Data(contentsOf: url))
    }

    static func load(from url: URL) throws -> Snapshot {
        let backup = url.appendingPathExtension("backup")
        if !FileManager.default.fileExists(atPath: url.path) {
            if FileManager.default.fileExists(atPath: backup.path) {
                return Snapshot(sessions: try decode(backup), recovered: true)
            }
            return Snapshot(sessions: [], recovered: false)
        }
        do { return Snapshot(sessions: try decode(url), recovered: false) }
        catch {
            guard FileManager.default.fileExists(atPath: backup.path) else { throw error }
            return Snapshot(sessions: try decode(backup), recovered: true)
        }
    }

    static func write(_ sessions: [MeetingSession], to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(sessions)
        if FileManager.default.fileExists(atPath: url.path) {
            let old = try Data(contentsOf: url)
            if (try? decode(url)) != nil {
                try old.write(to: url.appendingPathExtension("backup"), options: .atomic)
            } else {
                // Never overwrite an unreadable notebook without a valid recovery snapshot.
                _ = try decode(url.appendingPathExtension("backup"))
                let quarantine = url.deletingLastPathComponent().appendingPathComponent("sessions-corrupt-\(UUID().uuidString).json")
                try old.write(to: quarantine, options: .atomic)
            }
        }
        try data.write(to: url, options: .atomic)
    }
}
