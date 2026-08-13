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

    // MARK: - Manual sheet game lifecycle

    @MainActor
    private func freshStore() -> ManualScoreStore {
        let store = ManualScoreStore()
        store.resetSession()
        return store
    }

    @MainActor
    private func liveGame(_ store: ManualScoreStore) throws -> ManualScoreGame {
        try XCTUnwrap(store.session.games.first(where: \.isLive))
    }

    @MainActor
    func testNewGameBlockedUntilARaceTargetIsReached() throws {
        let store = freshStore()
        let game = try liveGame(store)
        let hand = game.hands[0].id

        store.setHandPoints(gameId: game.id, handId: hand, we: 124, they: 0)
        XCTAssertFalse(store.canAddGame())

        store.setHandPoints(gameId: game.id, handId: hand, we: 125, they: 0)
        XCTAssertTrue(store.canAddGame())
    }

    @MainActor
    func testRaceTargetCountsEitherSide() throws {
        let store = freshStore()
        let game = try liveGame(store)
        store.setHandPoints(gameId: game.id, handId: game.hands[0].id, we: 0, they: 130)
        XCTAssertTrue(store.canAddGame())
    }

    @MainActor
    func testAddGameIsIgnoredBeforeTheRaceTarget() throws {
        let store = freshStore()
        let game = try liveGame(store)
        store.setHandPoints(gameId: game.id, handId: game.hands[0].id, we: 100, they: 0)

        store.addGame()

        XCTAssertEqual(store.session.games.count, 1)
    }

    /// Hitting "Next" instead of "Done" leaves an unplayed row behind; closing the
    /// game out should drop it rather than carry it into the finished sheet.
    @MainActor
    func testNewGameDropsAnUnscoredTrailingHand() throws {
        let store = freshStore()
        let first = try liveGame(store)
        store.setHandPoints(gameId: first.id, handId: first.hands[0].id, we: 130, they: 0)
        store.addHand(to: first.id)
        XCTAssertEqual(try liveGame(store).hands.count, 2)

        store.addGame()

        let closed = try XCTUnwrap(store.session.games.first { $0.number == 1 })
        XCTAssertEqual(closed.hands.count, 1)
        XCTAssertEqual(closed.totalWe(), 130)
        XCTAssertFalse(closed.isLive)
        XCTAssertEqual(store.session.games.count, 2)
    }

    @MainActor
    func testAddHandWontStackBlankRows() throws {
        let store = freshStore()
        let game = try liveGame(store)
        XCTAssertEqual(game.hands.count, 1)

        store.addHand(to: game.id)
        XCTAssertEqual(try liveGame(store).hands.count, 1)

        store.setHandPoints(gameId: game.id, handId: game.hands[0].id, we: 10, they: 0)
        store.addHand(to: game.id)
        XCTAssertEqual(try liveGame(store).hands.count, 2)
    }

    // MARK: - Per-side hand entry

    /// Tapping into the losing side's `0` cell and leaving it alone (the buffer
    /// preloads that 0 and commits it back) must not wipe the winner's points —
    /// that silently dropped the hand from both the total and the net-hands count.
    @MainActor
    func testCommittingAZeroLeavesTheOtherSideAlone() throws {
        let store = freshStore()
        let game = try liveGame(store)
        let hand = game.hands[0].id

        store.setHandScore(gameId: game.id, handId: hand, side: .we, value: 57)
        store.setHandScore(gameId: game.id, handId: hand, side: .they, value: 0)

        let live = try liveGame(store)
        XCTAssertEqual(live.totalWe(), 57)
        XCTAssertEqual(live.netBoxes(), 1)
    }

    /// Scoring a side is still a claim that it won the hand, so a correction
    /// typed into the other cell moves the win across instead of doubling it.
    @MainActor
    func testScoringTheOtherSideMovesTheHandWin() throws {
        let store = freshStore()
        let game = try liveGame(store)
        let hand = game.hands[0].id

        store.setHandScore(gameId: game.id, handId: hand, side: .we, value: 57)
        store.setHandScore(gameId: game.id, handId: hand, side: .they, value: 12)

        let live = try liveGame(store)
        XCTAssertEqual(live.totalWe(), 0)
        XCTAssertEqual(live.totalThey(), 12)
        XCTAssertEqual(live.netBoxes(), -1)
    }

    /// Clearing one cell of a one-sided hand blanks the row (so the trailing-row
    /// cleanup can drop it) without touching any other hand.
    @MainActor
    func testClearingOneSideBlanksAOneSidedHand() throws {
        let store = freshStore()
        let game = try liveGame(store)
        store.setHandScore(gameId: game.id, handId: game.hands[0].id, side: .we, value: 40)
        store.addHand(to: game.id)
        let second = try XCTUnwrap(try liveGame(store).hands.last?.id)
        store.setHandScore(gameId: game.id, handId: second, side: .they, value: 30)

        store.clearHandScore(gameId: game.id, handId: second, side: .they)

        let live = try liveGame(store)
        let lastHand = try XCTUnwrap(live.hands.last)
        XCTAssertTrue(lastHand.isBlank)
        XCTAssertEqual(live.totalWe(), 40)
        XCTAssertEqual(live.netBoxes(), 1)
        XCTAssertFalse(store.canAddHand(to: game.id))
    }

    /// A row of zeroes is on the sheet but nobody won it.
    func testAllZeroHandCountsForNeitherSide() {
        let game = finishedGame(weHands: [(130, 0), (0, 0)])
        XCTAssertEqual(game.weBoxesWon(), 1)
        XCTAssertEqual(game.theyBoxesWon(), 0)
        XCTAssertEqual(game.netBoxes(), 1)
    }

    /// Points on both sides of a row belong to whoever scored more, not to both.
    func testHandWithPointsOnBothSidesCountsOnce() {
        let game = finishedGame(weHands: [(30, 10), (0, 95)])
        XCTAssertEqual(game.weBoxesWon(), 1)
        XCTAssertEqual(game.theyBoxesWon(), 1)
        XCTAssertEqual(game.netBoxes(), 0)
    }

    /// A new game starts clean — the previous game's rows don't carry over.
    @MainActor
    func testNewGameStartsWithItsOwnSingleBlankHand() throws {
        let store = freshStore()
        let first = try liveGame(store)
        store.setHandPoints(gameId: first.id, handId: first.hands[0].id, we: 130, they: 0)
        store.addHand(to: first.id)
        store.setHandPoints(
            gameId: first.id,
            handId: try liveGame(store).hands[1].id,
            we: 0,
            they: 15
        )

        store.addGame()

        let second = try liveGame(store)
        XCTAssertEqual(second.number, 2)
        XCTAssertEqual(second.hands.count, 1)
        XCTAssertEqual(second.totalWe(), 0)
        XCTAssertFalse(store.canAddGame())
    }
}
