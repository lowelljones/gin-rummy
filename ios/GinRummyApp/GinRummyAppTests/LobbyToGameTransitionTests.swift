import XCTest
@testable import GinRummyApp

/// Guards the "both players readied up → land on the game table immediately"
/// flow. The original bug: the game would start server-side but the waiting
/// room stayed on screen, and the player had to swipe left-to-right (pop the
/// nav stack) to reach the table. These tests pin down the two pieces of logic
/// that flow depends on:
///
///   1. `LobbyStatusResponse.gameIdToEnter` — when the waiting room decides the
///      game has started (used by both the 2s poll loop and the optimistic
///      ready-up response).
///   2. `RootScreen.resolve` — once `activeGameId` flips, the *root* branch
///      must be `.game`, which replaces the entire lobby NavigationStack
///      (waiting room included). No pushed lobby screen can survive, so there
///      is nothing left to swipe back from.
final class LobbyToGameTransitionTests: XCTestCase {

    // MARK: - Helpers

    private func lobbyStatusJSON(
        status: String,
        gameId: String?,
        hostReady: Bool = false,
        guestReady: Bool = false
    ) -> Data {
        let gameIdField = gameId.map { "\"\($0)\"" } ?? "null"
        let json = """
        {
          "lobby": { "id": "lobby-1", "invite_code": "ABCD", "status": "\(status)" },
          "gameId": \(gameIdField),
          "guest_joined": true,
          "you_seat": 0,
          "both_ready": \(hostReady && guestReady),
          "players": [
            { "seat": 0, "user_id": "host-1", "display_name": "Host", "ready": \(hostReady), "is_self": true },
            { "seat": 1, "user_id": "guest-1", "display_name": "Guest", "ready": \(guestReady), "is_self": false }
          ]
        }
        """
        return Data(json.utf8)
    }

    private func decodeStatus(_ data: Data) throws -> LobbyStatusResponse {
        try JSONDecoder().decode(LobbyStatusResponse.self, from: data)
    }

    // MARK: - Waiting room gate: when do we enter the game?

    func testBothPlayersReadyAndGameCreatedEntersGame() throws {
        let status = try decodeStatus(
            lobbyStatusJSON(status: "in_game", gameId: "game-42", hostReady: true, guestReady: true)
        )
        XCTAssertEqual(status.gameIdToEnter, "game-42",
                       "Once both seats are ready and the server created the game, the waiting room must transition immediately.")
    }

    func testClosedLobbyWithGameDoesNotEnterGame() throws {
        let status = try decodeStatus(
            lobbyStatusJSON(status: "closed", gameId: "game-42", hostReady: true, guestReady: true)
        )
        XCTAssertNil(status.gameIdToEnter,
                       "A closed lobby must not bounce players onto a completed table.")
    }

    func testOpenLobbyWithoutGameDoesNotEnterGame() throws {
        let status = try decodeStatus(
            lobbyStatusJSON(status: "open", gameId: nil, hostReady: true, guestReady: false)
        )
        XCTAssertNil(status.gameIdToEnter,
                     "Only one player is ready and no game exists — the waiting room must stay put.")
    }

    func testOpenLobbyWithStrayGameIdDoesNotEnterGame() throws {
        // Defensive: a gameId without the lobby actually flipping to in_game
        // (mid-transaction read) must not bounce the player onto a dead table.
        let status = try decodeStatus(
            lobbyStatusJSON(status: "open", gameId: "game-42", hostReady: true, guestReady: true)
        )
        XCTAssertNil(status.gameIdToEnter)
    }

    // MARK: - Root screen swap: the game replaces the lobby stack

    func testRootShowsLobbyWhileWaitingForOpponent() {
        let screen = RootScreen.resolve(restoring: false, hasSession: true, activeGameId: nil)
        XCTAssertEqual(screen, .lobby)
    }

    func testRootSwapsToGameTheMomentActiveGameIdFlips() {
        let screen = RootScreen.resolve(restoring: false, hasSession: true, activeGameId: "game-42")
        XCTAssertEqual(screen, .game,
                       "With an active game the root branch must be the game table — the lobby NavigationStack (and the ready-up page pushed onto it) is torn down, so no left-to-right swipe is ever needed.")
    }

    func testRootReturnsToLobbyWhenGameEnds() {
        let screen = RootScreen.resolve(restoring: false, hasSession: true, activeGameId: nil)
        XCTAssertEqual(screen, .lobby)
    }

    func testRootPrefersAuthAndRestoreOverGame() {
        XCTAssertEqual(RootScreen.resolve(restoring: true, hasSession: true, activeGameId: "game-42"), .restoringSession)
        XCTAssertEqual(RootScreen.resolve(restoring: false, hasSession: false, activeGameId: "game-42"), .auth)
    }

    // MARK: - End-to-end: ready-up payload drives the root swap

    @MainActor
    func testReadyUpPayloadFlipsRootStraightToGame() throws {
        let app = AppModel()
        app.accessToken = "token"

        // In the waiting room: lobby still open, no game yet.
        XCTAssertEqual(
            RootScreen.resolve(restoring: app.restoring, hasSession: app.accessToken != nil, activeGameId: app.activeGameId),
            .lobby
        )

        // Second player taps Ready — the server response carries the new game.
        let status = try decodeStatus(
            lobbyStatusJSON(status: "in_game", gameId: "game-42", hostReady: true, guestReady: true)
        )
        if let gid = status.gameIdToEnter {
            app.activeGameId = gid // what LobbyWaitingRoomView.transitionToGame does
        }

        XCTAssertEqual(app.activeGameId, "game-42")
        XCTAssertEqual(
            RootScreen.resolve(restoring: app.restoring, hasSession: app.accessToken != nil, activeGameId: app.activeGameId),
            .game,
            "Both players readied up: the very next root resolution must be the game screen, with the ready-up page gone."
        )
    }
}
