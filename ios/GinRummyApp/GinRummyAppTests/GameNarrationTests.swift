import XCTest
@testable import GinRummyApp

final class GameNarrationTests: XCTestCase {
    /// Builds a `PlayerPerspective` by decoding minimal JSON, so tests exercise the
    /// real Codable shape and only specify the fields they care about.
    private func perspective(
        seat: Int = 0,
        currentTurn: Int = 0,
        scores: [Int] = [0, 0],
        raceTarget: Int = 125,
        phase: String = "play",
        cut: [String: Any]? = nil,
        knock: [String: Any]? = nil
    ) -> PlayerPerspective {
        var dict: [String: Any] = [
            "seat": seat,
            "hands": [[String](), [String]()],
            "stockCount": 31,
            "discard": [String](),
            "phase": phase,
            "dealer": 0,
            "nonDealer": 1,
            "currentTurn": currentTurn,
            "scores": scores,
            "handsWon": [0, 0],
            "raceTarget": raceTarget,
        ]
        if let cut { dict["cut"] = cut }
        if let knock { dict["knock"] = knock }
        let data = try! JSONSerialization.data(withJSONObject: dict)
        return try! JSONDecoder().decode(PlayerPerspective.self, from: data)
    }

    // MARK: - cardName

    func testCardNameFormatsRanksAndSuits() {
        XCTAssertEqual(GameNarration.cardName("AS"), "Ace of Spades")
        XCTAssertEqual(GameNarration.cardName("TD"), "10 of Diamonds")
        XCTAssertEqual(GameNarration.cardName("7C"), "7 of Clubs")
        XCTAssertEqual(GameNarration.cardName("QH"), "Queen of Hearts")
        XCTAssertEqual(GameNarration.cardName("JS"), "Jack of Spades")
    }

    func testCardNameNormalizesInput() {
        XCTAssertEqual(GameNarration.cardName("kh"), "King of Hearts")
        XCTAssertEqual(GameNarration.cardName("  ad  "), "Ace of Diamonds")
    }

    func testCardNameFallsBackForJunk() {
        XCTAssertEqual(GameNarration.cardName("???"), "???")
        XCTAssertEqual(GameNarration.cardName(""), "")
    }

    // MARK: - turnLine

    func testTurnLine() {
        XCTAssertEqual(GameNarration.turnLine(perspective(seat: 0, currentTurn: 0)), "Your turn")
        XCTAssertEqual(GameNarration.turnLine(perspective(seat: 0, currentTurn: 1)), "Opponent’s turn")
        XCTAssertEqual(GameNarration.turnLine(perspective(seat: 1, currentTurn: 1)), "Your turn")
    }

    // MARK: - cutStageTitle

    func testCutStageTitleNoCut() {
        XCTAssertEqual(GameNarration.cutStageTitle(perspective()), "High card wins the first deal")
    }

    func testCutStageTitleYoursVsTheirs() {
        let mine = perspective(cut: [
            "faceDownRemaining": 52, "activePicker": 0, "youMustPick": true, "opponentHasPicked": false,
        ])
        XCTAssertEqual(GameNarration.cutStageTitle(mine), "Your turn — tap the spread to cut")

        let theirs = perspective(cut: [
            "faceDownRemaining": 52, "activePicker": 1, "youMustPick": false, "opponentHasPicked": false,
        ])
        XCTAssertEqual(GameNarration.cutStageTitle(theirs), "Opponent is cutting")
    }

    // MARK: - match outcome / headline

    func testMatchOutcomeInProgress() {
        let inProgress = perspective(seat: 0, scores: [40, 60], raceTarget: 125)
        XCTAssertEqual(GameNarration.matchOutcomeSubtitle(inProgress), "Race to 125")
        XCTAssertEqual(GameNarration.matchWinnerHeadline(inProgress), "Match complete")
    }

    func testMatchOutcomeYouWon() {
        let youWon = perspective(seat: 0, scores: [130, 60], raceTarget: 125)
        XCTAssertEqual(GameNarration.matchOutcomeSubtitle(youWon), "You reached 125 first.")
        XCTAssertEqual(GameNarration.matchWinnerHeadline(youWon), "You won the match")
    }

    func testMatchOutcomeOpponentWonFromSeat0Perspective() {
        let oppWon = perspective(seat: 0, scores: [60, 130], raceTarget: 125)
        XCTAssertEqual(GameNarration.matchOutcomeSubtitle(oppWon), "Opponent reached 125 first.")
        XCTAssertEqual(GameNarration.matchWinnerHeadline(oppWon), "Opponent won the match")
    }

    func testMatchOutcomeIsSeatRelative() {
        // Same scoreboard, seat 1's perspective: seat 1 is the winner.
        let fromWinnerSeat = perspective(seat: 1, scores: [60, 130], raceTarget: 125)
        XCTAssertEqual(GameNarration.matchWinnerHeadline(fromWinnerSeat), "You won the match")
    }

    // MARK: - knockLayoffLine

    func testKnockLayoffLine() {
        let yourTurn = perspective(seat: 0, knock: [
            "knocker": 0, "knockCard": "5C", "knockerMelds": [Any](), "knockerDeadwood": [String](),
            "opponentDeadwood": [String](), "layoffTurn": 0,
        ])
        XCTAssertEqual(GameNarration.knockLayoffLine(yourTurn, k: yourTurn.knock!), "Layoff · Your turn")

        let oppTurn = perspective(seat: 0, knock: [
            "knocker": 0, "knockCard": "5C", "knockerMelds": [Any](), "knockerDeadwood": [String](),
            "opponentDeadwood": [String](), "layoffTurn": 1,
        ])
        XCTAssertEqual(GameNarration.knockLayoffLine(oppTurn, k: oppTurn.knock!), "Layoff · Opponent’s turn")
    }
}
