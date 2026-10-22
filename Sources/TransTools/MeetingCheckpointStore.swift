import Foundation

/// One small, atomic file for the active meeting; never rewrites the entire
/// notebook on recognition updates. Actor serialization orders write/removal.
actor MeetingCheckpointStore {
    static let shared = MeetingCheckpointStore()
    private var lastWritten: [URL: MeetingSession] = [:]
    private struct Delta: Codable {
        let session: MeetingSession
        let changedRows: [CaptionRecord]
    }

    private nonisolated static func journalURL(_ url: URL) -> URL { url.appendingPathExtension("journal") }

    func write(_ snapshot: MeetingSession, to url: URL) throws {
        guard !snapshot.captions.isEmpty else { return }
        // A recovery from an earlier meeting must not be silently overwritten.
        let previous = try lastWritten[url] ?? Self.load(from: url)
        if let previous, previous.id != snapshot.id {
            throw NSError(domain: "MeetingCheckpoint", code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Bản khôi phục cuộc họp trước chưa được lưu vào Sổ tay."])
        }
        if let previous {
            let oldRows = Dictionary(previous.captions.map { ($0.id, $0) }, uniquingKeysWith: { _, latest in latest })
            let changed = snapshot.captions.filter { oldRows[$0.id] != $0 }
            guard snapshot != previous else { return }
            var header = snapshot; header.captions = []
            var data = try JSONEncoder().encode(Delta(session: header, changedRows: changed))
            data.append(0x0A)
            let journal = Self.journalURL(url)
            if !FileManager.default.fileExists(atPath: journal.path) {
                try Data().write(to: journal, options: .atomic)
            }
            // After a crash a trailing partial append is not a committed event.
            // Repair it only after load has validated every complete event.
            if lastWritten[url] == nil {
                let existing = try Data(contentsOf: journal)
                if !existing.isEmpty, existing.last != 0x0A {
                    let count = existing.lastIndex(of: 0x0A).map { $0 + 1 } ?? 0
                    try existing.prefix(count).write(to: journal, options: .atomic)
                }
            }
            let handle = try FileHandle(forWritingTo: journal)
            defer { try? handle.close() }
            do {
                try handle.seekToEnd()
                try handle.write(contentsOf: data)
                try handle.synchronize()
            } catch {
                lastWritten[url] = nil
                throw error
            }
        } else {
            try SessionStore.write([snapshot], to: url)
            // Keep a validated base backup. Later writes append changed rows
            // only, so long meetings do not rewrite growing snapshots every 2s.
            try SessionStore.write([snapshot], to: url)
        }
        lastWritten[url] = snapshot
    }

    nonisolated static func load(from url: URL) throws -> MeetingSession? {
        guard FileManager.default.fileExists(atPath: url.path)
                || FileManager.default.fileExists(atPath: url.appendingPathExtension("backup").path) else {
            if FileManager.default.fileExists(atPath: journalURL(url).path) {
                throw NSError(domain: "MeetingCheckpoint", code: 4,
                    userInfo: [NSLocalizedDescriptionKey: "Nhật ký khôi phục thiếu bản lưu gốc; file được giữ nguyên."])
            }
            return nil
        }
        let records = try SessionStore.load(from: url).sessions
        guard records.count == 1, let snapshot = records.first, !snapshot.captions.isEmpty else {
            throw NSError(domain: "MeetingCheckpoint", code: 2,
                userInfo: [NSLocalizedDescriptionKey: "Bản khôi phục không hợp lệ."])
        }
        let journal = journalURL(url)
        guard FileManager.default.fileExists(atPath: journal.path) else { return snapshot }
        let data = try Data(contentsOf: journal)
        var recovered = snapshot
        var rows = Dictionary(snapshot.captions.map { ($0.id, $0) }, uniquingKeysWith: { _, latest in latest })
        // Only newline-terminated events are committed. A malformed complete
        // event is an error; never silently discard the remainder of a journal.
        var start = data.startIndex
        for boundary in data.indices where data[boundary] == 0x0A {
            let delta = try JSONDecoder().decode(Delta.self, from: data[start..<boundary])
            guard delta.session.id == snapshot.id else {
                throw NSError(domain: "MeetingCheckpoint", code: 3,
                    userInfo: [NSLocalizedDescriptionKey: "Nhật ký khôi phục thuộc cuộc họp khác."])
            }
            for row in delta.changedRows { rows[row.id] = row }
            recovered = delta.session
            start = boundary + 1
        }
        recovered.captions = rows.values.sorted { $0.start < $1.start }
        return recovered
    }

    func remove(sessionID: UUID, from url: URL) throws {
        guard let saved = try Self.load(from: url), saved.id == sessionID else { return }
        // Remove backup first: a crash between removals still leaves the latest
        // primary snapshot, rather than resurrecting an older backup.
        for candidate in [Self.journalURL(url), url.appendingPathExtension("backup"), url] {
            if FileManager.default.fileExists(atPath: candidate.path) {
                try FileManager.default.removeItem(at: candidate)
            }
        }
        lastWritten[url] = nil
    }

    nonisolated static func merging(_ checkpoint: MeetingSession, into sessions: [MeetingSession]) -> [MeetingSession] {
        var updated = sessions
        guard let index = updated.firstIndex(where: { $0.id == checkpoint.id }) else {
            updated.append(checkpoint)
            return updated
        }
        // A manual save may precede the last checkpoint. Preserve edited title,
        // notes and any already-translated rows when recovery adds later speech.
        var existing = updated[index]
        var rows = existing.captions
        for incoming in checkpoint.captions {
            if let row = rows.firstIndex(where: { $0.id == incoming.id }) {
                let previous = rows[row]
                let oldRevision = previous.sourceRevision ?? 0
                let newRevision = incoming.sourceRevision ?? 0
                if newRevision > oldRevision || (newRevision == oldRevision && incoming.end > previous.end) {
                    if incoming.original == previous.original, incoming.vietnamese.isEmpty, !previous.vietnamese.isEmpty {
                        let combined = CaptionRecord(id: incoming.id, start: incoming.start, end: incoming.end,
                            original: incoming.original, vietnamese: previous.vietnamese,
                            sourceLanguage: incoming.sourceLanguage ?? previous.sourceLanguage,
                            targetLanguage: previous.targetLanguage, translationProvider: previous.translationProvider,
                            translationModel: previous.translationModel, sourceRevision: incoming.sourceRevision,
                            translationSource: previous.translationSource, translationRevision: previous.translationRevision)
                        rows[row] = combined
                    } else { rows[row] = incoming }
                } else if newRevision == oldRevision, incoming.original == previous.original,
                          previous.vietnamese.isEmpty, !incoming.vietnamese.isEmpty {
                    rows[row] = incoming
                }
            } else { rows.append(incoming) }
        }
        rows.sort { $0.start < $1.start }
        existing.captions = rows
        updated[index] = MeetingSession(id: existing.id, title: existing.title,
            createdAt: existing.createdAt, durationSeconds: max(existing.durationSeconds, checkpoint.durationSeconds),
            audioSource: existing.audioSource, notes: existing.notes, captions: rows,
            conversationProfile: existing.conversationProfile)
        return updated
    }
}
