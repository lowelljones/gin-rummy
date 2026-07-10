import XCTest
@testable import GinRummyApp

final class ScorecardScoringTests: XCTestCase {
    // MARK: - Betting tier boundaries (0–149 → 1, 150–249 → 2, +1 per 100)

    func testBettingBucketBoundaries() {
        XCTAssertEqual(BettingSettlementBreakdown.bettingBucket(forRaw: 0), 1)
        XCTAssertEqual(BettingSettlementBreakdown.bettingBucket(forRaw: 149), 1)
        XCTAssertEqual(BettingSettlementBreakdown.bettingBucket(forRaw: 150), 2)
        XCTAssertEqual(BettingSettlementBreakdown.bettingBucket(forRaw: 249), 2)
        XCTAssertEqual(BettingSettlementBreakdown.bettingBucket(forRaw: 250), 3)
        XCTAssertEqual(BettingSettlementBreakdown.bettingBucket(forRaw: 349), 3)
        XCTAssertEqual(BettingSettlementBreakdown.bettingBucket(forRaw: 350), 4)
        XCTAssertEqual(BettingSettlementBreakdown.bettingBucket(forRaw: 449), 4)
        XCTAssertEqual(BettingSettlementBreakdown.bettingBucket(forRaw: 450), 5)
        XCTAssertEqual(BettingSettlementBreakdown.bettingBucket(forRaw: 549), 5)
        XCTAssertEqual(BettingSettlementBreakdown.bettingBucket(forRaw: 550), 6)
    }

    func testTierRangeLabelsMatchBucketBoundaries() {
        XCTAssertEqual(BettingSettlementBreakdown.tierRangeLabel(for: 1), "under 150")
        XCTAssertEqual(BettingSettlementBreakdown.tierRangeLabel(for: 2), "150–249")
        XCTAssertEqual(BettingSettlementBreakdown.tierRangeLabel(for: 3), "250–349")
        XCTAssertEqual(BettingSettlementBreakdown.tierRangeLabel(for: 5), "450–549")
    }

    // MARK: - Manual scorecard "Game Totals" row shows the per-game signed tier

    private func finishedGame(weHands: [(Int, Int)]) -> ManualScoreGame {
        var game = ManualScoreGame.fresh(number: 1, live: false)
        game.hands = weHands.map { ManualScoreHand(id: UUID(), wePoints: $0.0, theyPoints: $0.1) }
        return game
    }

    func testManualGameTotalsShowSignedTierNotNetHands() {
        // We 173–70, hands 3–1 → raw = 103 + 100 + 50 = 253 → tier 3.
        let game = finishedGame(weHands: [(0, 70), (2, 0), (97, 0), (74, 0)])
        XCTAssertEqual(game.bettingSettlement()?.raw, 253)
        XCTAssertEqual(ScorecardScoring.manualGameTierLabel(game, forWe: true), "+3")
        XCTAssertEqual(ScorecardScoring.manualGameTierLabel(game, forWe: false), "-3")
        // Net hands (+2) is a different number — the row must show the tier.
        XCTAssertEqual(game.netBoxes(), 2)
    }

    func testManualGameTierShutoutSweep() {
        // We 174–0, hands 4–0 → raw = 174 + 100 + 100 + 100 = 474 → tier 5.
        let game = finishedGame(weHands: [(42, 0), (3, 0), (57, 0), (72, 0)])
        XCTAssertEqual(game.bettingSettlement()?.raw, 474)
        XCTAssertEqual(ScorecardScoring.manualGameTierLabel(game, forWe: true), "+5")
        XCTAssertEqual(ScorecardScoring.manualGameTierLabel(game, forWe: false), "-5")
    }

    func testManualGameTierPlaceholdersForLiveAndEmptyGames() {
        let live = ManualScoreGame.fresh(number: 1, live: true)
        XCTAssertEqual(ScorecardScoring.manualGameTierLabel(live, forWe: true), "…")

        let emptyFinished = ManualScoreGame.fresh(number: 2, live: false)
        XCTAssertEqual(ScorecardScoring.manualGameTierLabel(emptyFinished, forWe: true), "—")
    }

    func testManualGameTierWhenTheyWin() {
        // They 130–20, hands 3–1 → raw = 110 + 100 + 50 = 260 → tier 3, negative for We.
        let game = finishedGame(weHands: [(20, 0), (0, 60), (0, 40), (0, 30)])
        XCTAssertEqual(ScorecardScoring.manualGameTierLabel(game, forWe: true), "-3")
        XCTAssertEqual(ScorecardScoring.manualGameTierLabel(game, forWe: false), "+3")
    }

    // MARK: - Live scorecard tier labels come straight from the per-match bucket

    func testGameBettingBucketLabelIsPerMatchNotCumulative() throws {
        let json = """
        [
          {
            "match_number": 1,
            "game_id": "g1",
            "status": "completed",
            "phase": "matchOver",
            "created_at": "2026-01-01T00:00:00Z",
            "updated_at": "2026-01-01T00:00:00Z",
            "race_target": 125,
            "scores": [174, 0],
            "hands_won": [4, 0],
            "winner_seat": 0,
            "betting_raw": 474,
            "betting_bucket": 5,
            "is_current": false,
            "hand_scores": []
          },
          {
            "match_number": 2,
            "game_id": "g2",
            "status": "completed",
            "phase": "matchOver",
            "created_at": "2026-01-01T00:00:00Z",
            "updated_at": "2026-01-01T00:00:00Z",
            "race_target": 125,
            "scores": [131, 73],
            "hands_won": [2, 1],
            "winner_seat": 0,
            "betting_raw": 183,
            "betting_bucket": 2,
            "is_current": false,
            "hand_scores": []
          }
        ]
        """
        let matches = try JSONDecoder().decode([SessionMatchRecapDTO].self, from: Data(json.utf8))

        XCTAssertEqual(ScorecardScoring.gameBettingBucketLabel(for: matches[0], seat: 0), "+5")
        XCTAssertEqual(ScorecardScoring.gameBettingBucketLabel(for: matches[1], seat: 0), "+2")
        XCTAssertEqual(ScorecardScoring.gameBettingBucketLabel(for: matches[1], seat: 1), "-2")
    }
}
