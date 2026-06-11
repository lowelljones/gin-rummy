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

    func testNetHandsUsesWinnerMinusLoserNotTotalHandsWon() {
        // Winner took 4 hands, loser took 2 → net 2 boxes, not 4.
        let b = BettingSettlementBreakdown.compute(scores: [130, 40], handsWon: [4, 2], raceTarget: 125)
        XCTAssertEqual(b?.netHands, 2)
        XCTAssertEqual(b?.handsBonus, 50)
        XCTAssertEqual(b?.raw, 130 - 40 + 100 + 50)
    }

    func testBucketRangeLabels() {
        XCTAssertEqual(BettingSettlementBreakdown.bucketRangeLabel(for: 1), "under 150")
        XCTAssertEqual(BettingSettlementBreakdown.bucketRangeLabel(for: 3), "250–349")
        XCTAssertEqual(BettingSettlementBreakdown.bucketRangeLabel(for: 4), "350–449")
    }
}
