import XCTest
@testable import TransTools

final class BoundedAudioCacheTests: XCTestCase {
    func testEvictionRespectsRecentUseAndByteLimit() {
        var cache = BoundedAudioCache(limit: 6)
        cache.insert(Data([1, 2, 3]), for: "a")
        cache.insert(Data([4, 5, 6]), for: "b")
        XCTAssertNotNil(cache.value(for: "a"))
        cache.insert(Data([7, 8, 9]), for: "c")
        XCTAssertNil(cache.value(for: "b"))
        XCTAssertNotNil(cache.value(for: "a"))
        XCTAssertEqual(cache.byteCount, 6)
        cache.insert(Data(repeating: 0, count: 7), for: "a")
        XCTAssertNil(cache.value(for: "a")); XCTAssertEqual(cache.byteCount, 3)
        cache.removeAll(); XCTAssertEqual(cache.byteCount, 0)
        XCTAssertNil(cache.value(for: "c"))
    }
}
