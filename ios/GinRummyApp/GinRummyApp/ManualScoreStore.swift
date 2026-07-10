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

    func totalWe() -> Int {
        hands.compactMap(\.wePoints).reduce(0, +)
    }

    func totalThey() -> Int {
        hands.compactMap(\.theyPoints).reduce(0, +)
    }

    /// A hand is won by whoever scored points in it.
    func weBoxesWon() -> Int { hands.filter { ($0.wePoints ?? 0) > 0 }.count }
    func theyBoxesWon() -> Int { hands.filter { ($0.theyPoints ?? 0) > 0 }.count }
    /// Net hands won from the We player's perspective (+ means We are up).
    func netBoxes() -> Int { weBoxesWon() - theyBoxesWon() }
    /// True once at least one scored hand exists.
    var hasScoredHand: Bool { weBoxesWon() + theyBoxesWon() > 0 }

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
        session.games[gi].hands.append(.fresh())
        touch()
    }

    func addGame() {
        for i in session.games.indices {
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
