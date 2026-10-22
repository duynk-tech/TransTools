import Foundation

enum CaptionLookup {
    /// Caption IDs are unique. Live updates normally target the last row.
    static func index<Row>(in rows: [Row], id target: UUID, identifier: (Row) -> UUID) -> Int? {
        if let last = rows.last, identifier(last) == target { return rows.count - 1 }
        return rows.firstIndex { identifier($0) == target }
    }
}
