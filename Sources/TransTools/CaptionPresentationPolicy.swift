import Foundation

enum CaptionPresentationPolicy {
    struct Entry {
        let id: UUID
        let ready: Bool
    }

    /// Keep recent completed sentences in order without accumulating unbounded
    /// display delay. Older rows remain available in transcript/review mode.
    static func nextIndex(in entries: [Entry], currentID: UUID?, maximumBacklog: Int = 3) -> Int? {
        nextIndex(in: entries, currentID: currentID, maximumBacklog: maximumBacklog, id: { $0.id }, ready: { $0.ready })
    }

    static func nextIndex<Row>(in rows: [Row], currentID: UUID?, maximumBacklog: Int = 3,
                               id: (Row) -> UUID, ready: (Row) -> Bool) -> Int? {
        guard !rows.isEmpty else { return nil }
        guard let currentID, let current = rows.firstIndex(where: { id($0) == currentID }) else {
            return rows.lastIndex(where: ready) ?? rows.indices.last
        }
        var candidate = current
        var found = 0
        for index in rows.indices.reversed() {
            guard index > current else { break }
            if ready(rows[index]) {
                candidate = index
                found += 1
                if found >= max(1, maximumBacklog) { break }
            }
        }
        return candidate
    }
}
