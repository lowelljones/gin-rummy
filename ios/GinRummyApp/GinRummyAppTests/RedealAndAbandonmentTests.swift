import XCTest
@testable import GinRummyApp

/// Pins the client-side policy and JSON contracts for redeal + abandonment flows.
final class RedealAndAbandonmentTests: XCTestCase {

    // MARK: - GameTablePolicy

    func testProposeRedealAllowedDuringDownCardPlayAndLayoff() {
        XCTAssertTrue(GameTablePolicy.proposeRedealAllowed(phase: "upcardOffer"))
        XCTAssertTrue(GameTablePolicy.proposeRedealAllowed(phase: "play"))
        XCTAssertTrue(GameTablePolicy.proposeRedealAllowed(phase: "knockLayoff"))
    }

    func testProposeRedealDisallowedDuringHandOverAndMatchOver() {
        XCTAssertFalse(GameTablePolicy.proposeRedealAllowed(phase: "handOver"))
        XCTAssertFalse(GameTablePolicy.proposeRedealAllowed(phase: "matchOver"))
        XCTAssertFalse(GameTablePolicy.proposeRedealAllowed(phase: "cutForDeal"))
    }

    func testPendingRedealDetection() {
        XCTAssertFalse(GameTablePolicy.isPendingRedeal(nil))
        XCTAssertFalse(GameTablePolicy.isPendingRedeal(RedealStateDTO(fromSeat: 0, status: "declined")))
        XCTAssertTrue(GameTablePolicy.isPendingRedeal(RedealStateDTO(fromSeat: 1, status: "pending")))
    }

    func testAbandonmentExitStateMapping() {
        XCTAssertEqual(GameTablePolicy.exitStateForAbandonment(leftBySeat: 0, mySeat: 0), "youLeft")
        XCTAssertEqual(GameTablePolicy.exitStateForAbandonment(leftBySeat: 0, mySeat: 1), "opponentLeft")
        XCTAssertEqual(GameTablePolicy.exitStateForAbandonment(leftBySeat: nil, mySeat: 0), "opponentLeft")
    }

    // MARK: - JSON decoding

    func testGameStateAbandonedDecodesLeftBySeat() throws {
        let json = """
        {
          "perspective": {
            "seat": 1,
            "hands": [[], []],
            "stockCount": 0,
            "discard": [],
            "phase": "play",
            "dealer": 0,
            "nonDealer": 1,
            "currentTurn": 0,
            "scores": [10, 20],
            "handsWon": [1, 1],
            "raceTarget": 125,
            "upcardOffer": null,
            "knock": null,
            "knockCheckCard": null,
            "lastCut": null,
            "cut": null,
            "redeal": null,
            "voidFlash": null,
            "handResult": null,
            "handOverAcks": null,
            "lastAction": null
          },
          "moveSeq": 42,
          "status": "abandoned",
          "leftBySeat": 0,
          "betting": null,
          "opponentDisplayName": "Alex",
          "rematch": null,
          "lobbyInviteCode": null
        }
        """
        let state = try JSONDecoder().decode(GameStateResponse.self, from: Data(json.utf8))
        XCTAssertEqual(state.status, "abandoned")
        XCTAssertEqual(state.leftBySeat, 0)
        XCTAssertEqual(GameTablePolicy.exitStateForAbandonment(leftBySeat: state.leftBySeat, mySeat: 1), "opponentLeft")
    }

    func testPerspectivePendingRedealDecodesForBothClients() throws {
        let json = """
        {
          "seat": 0,
          "hands": [["AS"], ["HIDDEN"]],
          "stockCount": 30,
          "discard": ["JS"],
          "phase": "upcardOffer",
          "dealer": 0,
          "nonDealer": 1,
          "currentTurn": 1,
          "scores": [34, 0],
          "handsWon": [1, 0],
          "raceTarget": 125,
          "upcardOffer": { "stage": "nonDealer", "nonDealerPassed": false },
          "knock": null,
          "knockCheckCard": "JS",
          "lastCut": null,
          "cut": null,
          "redeal": { "fromSeat": 1, "status": "pending" },
          "voidFlash": null,
          "handResult": null,
          "handOverAcks": null,
          "lastAction": null
        }
        """
        let p = try JSONDecoder().decode(PlayerPerspective.self, from: Data(json.utf8))
        XCTAssertTrue(GameTablePolicy.isPendingRedeal(p.redeal))
        XCTAssertEqual(p.redeal?.fromSeat, 1)
        XCTAssertEqual(p.phase, "upcardOffer")
        XCTAssertTrue(GameTablePolicy.proposeRedealAllowed(phase: p.phase))
    }

    func testMoveResponseWithoutStatusStillUpdatesPerspective() throws {
        let json = """
        {
          "perspective": {
            "seat": 0,
            "hands": [["AS"], ["HIDDEN"]],
            "stockCount": 30,
            "discard": ["JS"],
            "phase": "upcardOffer",
            "dealer": 0,
            "nonDealer": 1,
            "currentTurn": 1,
            "scores": [34, 0],
            "handsWon": [1, 0],
            "raceTarget": 125,
            "upcardOffer": { "stage": "nonDealer", "nonDealerPassed": false },
            "knock": null,
            "knockCheckCard": "JS",
            "lastCut": null,
            "cut": null,
            "redeal": { "fromSeat": 0, "status": "pending" },
            "voidFlash": null,
            "handResult": null,
            "handOverAcks": null,
            "lastAction": null
          },
          "moveSeq": 7,
          "betting": null,
          "opponentDisplayName": "Sam"
        }
        """
        let move = try JSONDecoder().decode(MoveResponse.self, from: Data(json.utf8))
        XCTAssertTrue(GameTablePolicy.isPendingRedeal(move.perspective.redeal))
        XCTAssertEqual(move.perspective.redeal?.fromSeat, 0)
    }

    func testGameLeaveResponseDecodesAbandonedSeat() throws {
        let json = """
        { "ok": true, "status": "abandoned", "leftBySeat": 1 }
        """
        let leave = try JSONDecoder().decode(GameLeaveResponse.self, from: Data(json.utf8))
        XCTAssertTrue(leave.ok)
        XCTAssertEqual(leave.status, "abandoned")
        XCTAssertEqual(leave.leftBySeat, 1)
    }
}
