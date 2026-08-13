import Foundation

/// Locally persisted in-person score sheet (no server).
struct ManualScoreSession: Codable, Equatable {
    var id: UUID
    var weName: String
    var theyName: String
    var games: [ManualScoreGame]
    var updatedAt: Date

    static func fresh() -> ManualScoreSession {
        ManualScoreSession(
            id: UUID(),
            weName: "You",
            theyName: "Opponent",
            games: [ManualScoreGame.fresh(number: 1)],
            updatedAt: Date()
        )
    }
}

struct ManualScoreGame: Codable, Equatable, Identifiable {
    var id: UUID
    var number: Int
    var hands: [ManualScoreHand]
    /// Signed match tier result for the We player (+3, -2, …). Nil until entered.
    var weBox: Int?
    var theyBox: Int?
    var isLive: Bool

    static func fresh(number: Int, live: Bool = true) -> ManualScoreGame {
        ManualScoreGame(
            id: UUID(),
            number: number,
            hands: [ManualScoreHand.fresh()],
            weBox: nil,
            theyBox: nil,
            isLive: live
        )
    }

    /// First side to reach this score wins the game.
    static let raceTarget = 125

    /// True once a side has reached the race target — the only point at which
    /// the game is over and another one can start.
    var isComplete: Bool {
        totalWe() >= Self.raceTarget || totalThey() >= Self.raceTarget
    }

    /// A hand nobody scored was never played, so it shouldn't be left on the
    /// sheet when the game is closed out.
    mutating func dropTrailingBlankHands() {
        while let last = hands.last, last.isBlank {
            hands.removeLast()
        }
    }

    func totalWe() -> Int {
        hands.compactMap(\.wePoints).reduce(0, +)
    }

    func totalThey() -> Int {
        hands.compactMap(\.theyPoints).reduce(0, +)
    }

    /// A hand is won by whichever side scored more in it. Comparing the two
    /// sides rather than testing each against zero keeps a hand that somehow
    /// carries points on both sides from counting as a win for both.
    func weBoxesWon() -> Int { hands.filter { $0.winnerIsWe == true }.count }
    func theyBoxesWon() -> Int { hands.filter { $0.winnerIsWe == false }.count }
    /// Net hands won from the We player's perspective (+ means We are up).
    func netBoxes() -> Int { weBoxesWon() - theyBoxesWon() }
    /// True once at least one scored hand exists.
    var hasScoredHand: Bool { hands.contains(where: \.isScored) }

    /// Score margin + 25× net hands won (excludes win bonus and shutout).
    func interimNetForWe() -> Int? {
        guard hasScoredHand else { return nil }
        return BettingSettlementBreakdown.interimNet(
            myScore: totalWe(),
            oppScore: totalThey(),
            myHandsWon: weBoxesWon(),
            oppHandsWon: theyBoxesWon()
        )
    }

    /// Full match point settlement once the game is no longer live.
    func bettingSettlement() -> BettingSettlementBreakdown? {
        guard !isLive, hasScoredHand else { return nil }
        return BettingSettlementBreakdown.computeForFinalScores(
            scores: [totalWe(), totalThey()],
            handsWon: [weBoxesWon(), theyBoxesWon()]
        )
    }
}

struct ManualScoreHand: Codable, Equatable, Identifiable {
    var id: UUID
    var wePoints: Int?
    var theyPoints: Int?

    static func fresh() -> ManualScoreHand {
        ManualScoreHand(id: UUID(), wePoints: nil, theyPoints: nil)
    }

    /// True for a We win, false for a They win, nil when the hand was never
    /// played or carries no points for either side.
    var winnerIsWe: Bool? {
        let we = wePoints ?? 0
        let they = theyPoints ?? 0
        if we > they { return true }
        if they > we { return false }
        return nil
    }

    /// A hand somebody actually scored in. A row of zeroes is on the sheet but
    /// counts for nobody.
    var isScored: Bool { winnerIsWe != nil }

    /// Nothing has been typed into either side yet.
    var isBlank: Bool { wePoints == nil && theyPoints == nil }
}

/// Which half of a hand row a score belongs to.
enum ManualScoreSide {
    case we, they
}

/// Names of people you've played — online opponents (recorded when the profile
/// game log loads) plus names typed into the manual scorecard. Powers the
/// opponent suggestions when scoring an in-person game. Local only; not a
/// friend system.
enum KnownOpponentsStore {
    private static let storageKey = "gin.knownOpponents.v1"
    private static let maxNames = 30
    /// Placeholder names that would pollute the suggestions.
    private static let ignored: Set<String> = ["you", "opponent", "player", "practice bot"]

    static func all() -> [String] {
        UserDefaults.standard.stringArray(forKey: storageKey) ?? []
    }

    /// Most-recently-used first, case-insensitively deduped.
    static func remember(_ name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 2, !ignored.contains(trimmed.lowercased()) else { return }
        var names = all().filter { $0.lowercased() != trimmed.lowercased() }
        names.insert(trimmed, at: 0)
        if names.count > maxNames { names = Array(names.prefix(maxNames)) }
        UserDefaults.standard.set(names, forKey: storageKey)
    }

    static func remember(contentsOf newNames: [String]) {
        // Reverse so the first entry in `newNames` ends up most recent.
        for name in newNames.reversed() { remember(name) }
    }
}

@MainActor
final class ManualScoreStore: ObservableObject {
    @Published private(set) var session: ManualScoreSession

    private static let storageKey = "gin.manualScoreSession.v1"

    init() {
        if let data = UserDefaults.standard.data(forKey: Self.storageKey),
           let loaded = try? JSONDecoder().decode(ManualScoreSession.self, from: data) {
            session = loaded
        } else {
            session = .fresh()
            persist()
        }
    }

    func resetSession() {
        session = .fresh()
        persist()
    }

    func updateNames(we: String, they: String) {
        session.weName = we.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "You" : we
        session.theyName = they.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Opponent" : they
        KnownOpponentsStore.remember(session.theyName)
        touch()
    }

    func addHand(to gameId: UUID) {
        guard let gi = session.games.firstIndex(where: { $0.id == gameId }) else { return }
        // Keep at most one blank trailing hand per game: never stack empty rows
        // ahead of what's actually been scored. This is per-game so a new game
        // starts fresh without inheriting the previous game's extra rows.
        if let last = session.games[gi].hands.last, last.isBlank {
            return
        }
        session.games[gi].hands.append(.fresh())
        touch()
    }

    /// Whether a fresh blank hand can be appended to this game (i.e. the last
    /// hand already carries a score). Drives the "Add hand" button state.
    func canAddHand(to gameId: UUID) -> Bool {
        guard let gi = session.games.firstIndex(where: { $0.id == gameId }) else { return false }
        guard let last = session.games[gi].hands.last else { return true }
        return !last.isBlank
    }

    /// Another game only makes sense once the current one has been won.
    func canAddGame() -> Bool {
        guard let game = session.games.first(where: \.isLive) ?? session.games.last else { return true }
        return game.isComplete
    }

    func addGame() {
        guard canAddGame() else { return }
        for i in session.games.indices {
            session.games[i].dropTrailingBlankHands()
            session.games[i].isLive = false
        }
        let n = (session.games.map(\.number).max() ?? 0) + 1
        session.games.append(.fresh(number: n, live: true))
        touch()
    }

    func setHandPoints(gameId: UUID, handId: UUID, we: Int?, they: Int?) {
        guard let gi = session.games.firstIndex(where: { $0.id == gameId }),
              let hi = session.games[gi].hands.firstIndex(where: { $0.id == handId }) else { return }
        session.games[gi].hands[hi].wePoints = we
        session.games[gi].hands[hi].theyPoints = they
        touch()
    }

    /// Writes one half of a hand row.
    ///
    /// Scoring points on a side is a claim that that side won the hand, so the
    /// other side is zeroed. A 0 is not such a claim: it only fills in the
    /// side that didn't score, and must leave the opponent's points alone —
    /// otherwise merely tabbing through the loser's `0` cell of an already
    /// scored hand would erase the winner's points, dropping the hand out of
    /// the net-hands count and out of the game total.
    func setHandScore(gameId: UUID, handId: UUID, side: ManualScoreSide, value: Int) {
        guard let gi = session.games.firstIndex(where: { $0.id == gameId }),
              let hi = session.games[gi].hands.firstIndex(where: { $0.id == handId }) else { return }
        switch side {
        case .we:
            session.games[gi].hands[hi].wePoints = value
            if value > 0 { session.games[gi].hands[hi].theyPoints = 0 }
        case .they:
            session.games[gi].hands[hi].theyPoints = value
            if value > 0 { session.games[gi].hands[hi].wePoints = 0 }
        }
        touch()
    }

    /// Clears one half of a hand row. A hand whose only remaining value is the
    /// auto-filled 0 was never really scored, so it goes back to fully blank
    /// and the trailing-row cleanup can drop it.
    func clearHandScore(gameId: UUID, handId: UUID, side: ManualScoreSide) {
        guard let gi = session.games.firstIndex(where: { $0.id == gameId }),
              let hi = session.games[gi].hands.firstIndex(where: { $0.id == handId }) else { return }
        switch side {
        case .we:
            session.games[gi].hands[hi].wePoints = nil
            if (session.games[gi].hands[hi].theyPoints ?? 0) == 0 {
                session.games[gi].hands[hi].theyPoints = nil
            }
        case .they:
            session.games[gi].hands[hi].theyPoints = nil
            if (session.games[gi].hands[hi].wePoints ?? 0) == 0 {
                session.games[gi].hands[hi].wePoints = nil
            }
        }
        touch()
    }

    func setBox(gameId: UUID, we: Int?, they: Int?) {
        guard let gi = session.games.firstIndex(where: { $0.id == gameId }) else { return }
        session.games[gi].weBox = we
        session.games[gi].theyBox = they
        touch()
    }

    func netBox(forWePlayer: Bool) -> Int {
        session.games.reduce(0) { sum, game in
            sum + (forWePlayer ? game.netBoxes() : -game.netBoxes())
        }
    }

    func maxHandRows() -> Int {
        max(session.games.map(\.hands.count).max() ?? 1, 1)
    }

    private func touch() {
        session.updatedAt = Date()
        persist()
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(session) else { return }
        UserDefaults.standard.set(data, forKey: Self.storageKey)
    }
}
