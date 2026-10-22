import XCTest
@testable import TransTools

final class CaptionLookupTests: XCTestCase {
    func testLiveRowLookupDoesNotScanTenThousandRows() {
        let rows = (0..<10_000).map { _ in UUID() }
        var inspected = 0
        let index = CaptionLookup.index(in: rows, id: rows.last!) { inspected += 1; return $0 }
        XCTAssertEqual(index, 9_999)
        XCTAssertEqual(inspected, 1)
    }
    func testEarlierAndMissingRowsStillResolveCorrectly() {
        let rows = (0..<4).map { _ in UUID() }
        XCTAssertEqual(CaptionLookup.index(in: rows, id: rows[1], identifier: { $0 }), 1)
        XCTAssertNil(CaptionLookup.index(in: rows, id: UUID(), identifier: { $0 }))
        XCTAssertNil(CaptionLookup.index(in: [UUID](), id: UUID(), identifier: { $0 }))
    }
}
