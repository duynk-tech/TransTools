import Foundation

enum NotebookSearch {
    /// Keep positions in the original transcript when search hides intervening rows.
    static func captionIndices(in captions: [CaptionRecord], matching ids: Set<UUID>?) -> [Int] {
        guard let ids else { return Array(captions.indices) }
        return captions.indices.filter { ids.contains(captions[$0].id) }
    }
    struct Request: Equatable {
        let text: String
        let sessions: [MeetingSession]
    }
    struct TranscriptRequest: Equatable {
        let text: String
        let sessionID: UUID
        let captions: [CaptionRecord]
    }

    static func captionIDs(for request: TranscriptRequest) async throws -> Set<UUID> {
        try Task.checkCancellation()
        let worker = Task.detached(priority: .userInitiated) {
            let query = Query(request.text)
            var ids = Set<UUID>()
            for caption in request.captions {
                try Task.checkCancellation()
                if query.matches(fields: [caption.original, caption.vietnamese]) { ids.insert(caption.id) }
            }
            try Task.checkCancellation()
            return ids
        }
        return try await withTaskCancellationHandler { try await worker.value }
            onCancel: { worker.cancel() }
    }

    static func sessionIDs(for request: Request) async throws -> Set<UUID> {
        try Task.checkCancellation()
        let worker = Task.detached(priority: .userInitiated) {
            let query = Query(request.text)
            var ids = Set<UUID>()
            for session in request.sessions {
                try Task.checkCancellation()
                if query.matches(fields: session.captions.lazy.flatMap { [$0.original, $0.vietnamese] },
                    leading: [session.title, session.audioSource, session.notes]) {
                    ids.insert(session.id)
                }
            }
            try Task.checkCancellation()
            return ids
        }
        return try await withTaskCancellationHandler {
            try await worker.value
        } onCancel: {
            worker.cancel()
        }
    }

    static func matches(_ query: String, fields: [String]) -> Bool {
        Query(query).matches(fields: fields)
    }

    struct Query {
        private let terms: Set<String>
        init(_ text: String) {
            terms = Set(normalize(text).split(whereSeparator: { $0.isWhitespace }).map(String.init))
        }
        func matches<Fields: Sequence>(fields: Fields, leading: [String] = []) -> Bool where Fields.Element == String {
            var remaining = terms
            guard !remaining.isEmpty else { return true }
            for field in leading {
                let searchable = normalize(field)
                remaining = remaining.filter { !searchable.contains($0) }
                if remaining.isEmpty { return true }
            }
            for field in fields {
                let searchable = normalize(field)
                remaining = remaining.filter { !searchable.contains($0) }
                if remaining.isEmpty { return true }
            }
            return false
        }
    }

    private static func normalize(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "vi_VN"))
            .replacingOccurrences(of: "đ", with: "d")
    }
}
