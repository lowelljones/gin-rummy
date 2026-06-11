import XCTest
@testable import GinRummyApp

final class BettingSettlementBreakdownTests: XCTestCase {
    func testUserExampleRaw250Bucket3() {
        let b = BettingSettlementBreakdown.compute(scores: [125, 25], handsWon: [3, 1], raceTarget: 125)
        XCTAssertNotNil(b)
        XCTAssertEqual(b?.raw, 250)
        XCTAssertEqual(b?.bucket, 3)
        XCTAssertEqual(b?.winBonus, 100)
        XCTAssertEqual(b?.scoreDiff, 100)
        XCTAssertEqual(b?.shutoutBonus, 0)
        XCTAssertEqual(b?.handsBonus, 50)
    }

    func testShutoutAddsBlitzBonus() {
        let b = BettingSettlementBreakdown.compute(scores: [130, 0], handsWon: [5, 0], raceTarget: 125)
        XCTAssertEqual(b?.raw, 455)
        XCTAssertEqual(b?.bucket, 5)
        XCTAssertEqual(b?.shutoutBonus, 100)
    }

    func testBucketRangeLabels() {
        XCTAssertEqual(BettingSettlementBreakdown.bucketRangeLabel(for: 1), "under 150")
        XCTAssertEqual(BettingSettlementBreakdown.bucketRangeLabel(for: 3), "250–349")
        XCTAssertEqual(BettingSettlementBreakdown.bucketRangeLabel(for: 4), "350–449")
    }
}
