import XCTest
@testable import GinRummyApp

final class ProfileGameLogTests: XCTestCase {
    private let sampleJSON = """
    {
      "games": [
        {
          "game_id": "g1",
          "status": "completed",
          "created_at": "2026-07-01T00:00:00.000Z",
          "updated_at": "2026-07-01T01:00:00.000Z",
          "is_bot_game": false,
          "opponent_user_id": "u2",
          "opponent_display_name": "Charlie",
          "my_score": 125,
          "opponent_score": 80,
          "hands_played": 5,
          "i_won": true,
          "i_abandoned": null,
          "betting_raw": 264,
          "betting_bucket": 3
        },
        {
          "game_id": "g2",
          "status": "abandoned",
          "created_at": "2026-07-02T00:00:00Z",
          "updated_at": "2026-07-02T01:00:00Z",
          "is_bot_game": false,
          "opponent_user_id": "u3",
          "opponent_display_name": "Dana",
          "my_score": 40,
          "opponent_score": 10,
          "hands_played": 1,
          "i_won": null,
          "i_abandoned": false,
          "betting_raw": null,
          "betting_bucket": null
        }
      ],
      "totals": {
        "completed_games": 1,
        "wins": 1,
        "losses": 0,
        "net_buckets": 3,
        "hands_played": 5
      }
    }
    """

    func testDecodesGameLogResponse() throws {
        let response = try JSONDecoder().decode(
            AccountGameLogResponse.self,
            from: Data(sampleJSON.utf8)
        )

        XCTAssertEqual(response.games.count, 2)
        XCTAssertEqual(response.totals.wins, 1)
        XCTAssertEqual(response.totals.netBuckets, 3)

        let won = response.games[0]
        XCTAssertEqual(won.opponentDisplayName, "Charlie")
        XCTAssertEqual(won.iWon, true)
        XCTAssertEqual(won.signedTierLabel, "+3")

        let walked = response.games[1]
        XCTAssertNil(walked.iWon)
        XCTAssertNil(walked.signedTierLabel)
        XCTAssertEqual(walked.iAbandoned, false)
    }

    func testSignedTierLabelIsNegativeForLosses() throws {
        // Same game as the sample, but lost.
        let lossJSON = sampleJSON.replacingOccurrences(of: "\"i_won\": true", with: "\"i_won\": false")
        let loss = try JSONDecoder().decode(AccountGameLogResponse.self, from: Data(lossJSON.utf8)).games[0]
        XCTAssertEqual(loss.signedTierLabel, "-3")
    }

    func testParsesBothISO8601DateVariants() {
        XCTAssertNotNil(ProfileView.parseDate("2026-07-01T01:00:00.000Z"))
        XCTAssertNotNil(ProfileView.parseDate("2026-07-01T01:00:00Z"))
    }
}
