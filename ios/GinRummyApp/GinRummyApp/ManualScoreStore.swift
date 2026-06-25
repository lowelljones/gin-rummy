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
    /// Signed box result for the We player (+3, -2, …). Nil until entered.
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

    /// A hand is "won" (a box) by whoever scored points in it.
    func weBoxesWon() -> Int { hands.filter { ($0.wePoints ?? 0) > 0 }.count }
    func theyBoxesWon() -> Int { hands.filter { ($0.theyPoints ?? 0) > 0 }.count }
    /// Net boxes from the We player's perspective (+ means We are up).
    func netBoxes() -> Int { weBoxesWon() - theyBoxesWon() }
    /// True once at least one scored hand exists.
    var hasScoredHand: Bool { weBoxesWon() + theyBoxesWon() > 0 }

    /// Score margin + 25× net boxes (excludes win bonus and shutout).
    func interimNetForWe() -> Int? {
        guard hasScoredHand else { return nil }
        return BettingSettlementBreakdown.interimNet(
            myScore: totalWe(),
            oppScore: totalThey(),
            myHandsWon: weBoxesWon(),
            oppHandsWon: theyBoxesWon()
        )
    }

    /// Full betting settlement once the game is no longer live.
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

    func cumulativeBettingTotal(forWePlayer: Bool, throughGameIndex: Int) -> Int? {
        guard throughGameIndex >= 0, throughGameIndex < session.games.count else { return nil }
        if session.games[throughGameIndex].isLive { return nil }
        var total = 0
        var counted = false
        for i in 0 ... throughGameIndex {
            let game = session.games[i]
            guard !game.isLive, let settlement = game.bettingSettlement() else { continue }
            counted = true
            let weWon = settlement.winner == 0
            let delta = forWePlayer ? (weWon ? settlement.bucket : -settlement.bucket)
                                    : (weWon ? -settlement.bucket : settlement.bucket)
            total += delta
        }
        return counted ? total : nil
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
