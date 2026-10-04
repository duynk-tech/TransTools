import Foundation

/// Actor owners serialize access. Cost is the actual encoded byte count.
struct BoundedAudioCache {
    let limit: Int
    private(set) var byteCount = 0
    private var values: [String: Data] = [:]
    private var order: [String] = []
    mutating func value(for key: String) -> Data? {
        guard let value = values[key] else { return nil }
        order.removeAll { $0 == key }; order.append(key)
        return value
    }
    mutating func insert(_ value: Data, for key: String) {
        if let old = values.removeValue(forKey: key) { byteCount -= old.count }
        order.removeAll { $0 == key }
        guard value.count <= limit else { return }
        while byteCount + value.count > limit, let oldest = order.first {
            order.removeFirst()
            byteCount -= values.removeValue(forKey: oldest)?.count ?? 0
        }
        values[key] = value; order.append(key); byteCount += value.count
    }
    mutating func removeAll() {
        values.removeAll(keepingCapacity: false); order.removeAll(keepingCapacity: false); byteCount = 0
    }
}
