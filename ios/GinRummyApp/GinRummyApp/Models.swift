import Foundation

struct PlayerPerspective: Codable, Equatable {
    let seat: Int
    let hands: [[String]]
    let stockCount: Int
    let discard: [String]
    let phase: String
    let dealer: Int
    let nonDealer: Int
    let currentTurn: Int
    let scores: [Int]
    let handsWon: [Int]
    let raceTarget: Int
    let upcardOffer: UpcardOfferState?
    let knock: KnockPerspective?
    /// First upcard for this hand (knock value); fixed for the whole hand. Not the current discard top.
    let knockCheckCard: String?
    /// After first hand cut, both cut cards; cleared next hand. Used for a short "who won" banner.
    let lastCut: LastCutResult?
    let cut: CutState?

    struct LastCutResult: Codable, Equatable {
        let p0: String
        let p1: String
        let nonDealer: Int
    }

    /// Face-down high-card cut: pick by index into the 52 card spread; no card codes shown until you cut.
    struct CutState: Codable, Equatable {
        let faceDownRemaining: Int
        let activePicker: Int
        let youMustPick: Bool
        let yourCut: String?
        let opponentHasPicked: Bool
        let theirCut: String?
        /// Server chooses who cuts first; omitted in older games (treated as 0).
        let firstCutSeat: Int?
    }

    struct UpcardOfferState: Codable, Equatable {
        let stage: String
        let nonDealerPassed: Bool
    }

    struct KnockPerspective: Codable, Equatable {
        let knocker: Int
        let knockCard: String
        let knockerMelds: [MeldDTO]
        let knockerDeadwood: [String]
        let opponentOriginalHand: [String]?
        let opponentDeadwood: [String]
        let knockerMeldsAfterLayoff: [MeldDTO]?
        let layoffTurn: Int

        struct MeldDTO: Codable, Equatable {
            let type: String
            let cards: [String]
        }
    }
}

struct LobbyInvitePreviewResponse: Codable {
    let invite_code: String
    let status: String
    let host_display_name: String
}

struct LobbyCreateResponse: Codable {
    let lobby: LobbyDTO

    struct LobbyDTO: Codable {
        let id: String
        let invite_code: String
        let status: String
    }
}

struct LobbyPlayerDTO: Codable, Equatable, Identifiable {
    let seat: Int
    let userId: String
    let displayName: String
    let ready: Bool
    let isSelf: Bool

    var id: String { userId }

    enum CodingKeys: String, CodingKey {
        case seat
        case userId = "user_id"
        case displayName = "display_name"
        case ready
        case isSelf = "is_self"
    }
}

struct LobbyStatusResponse: Codable {
    let lobby: LobbyDTO
    let gameId: String?
    /// True when seat 1 has been claimed (guest joined). Legacy field kept for
    /// older clients; the new waiting room reads `players` directly instead.
    let guestJoined: Bool
    /// Which seat the requesting user occupies (0 = host, 1 = guest), or nil
    /// if they're not in `lobby_players` (e.g. the host before any insert race).
    let youSeat: Int?
    /// Every member of the lobby — used to render player cards with display name
    /// and per-seat ready badge in the unified waiting room.
    let players: [LobbyPlayerDTO]
    /// Convenience: server-computed both-seats-ready flag.
    let bothReady: Bool
    /// Populated when the server attempted to start the game (both seats ready)
    /// but the game-row insert was rejected. Lets the iOS waiting room surface
    /// a real diagnostic instead of sitting on "Both players ready — starting…"
    /// indefinitely while the GET self-heal retries.
    let startError: String?

    enum CodingKeys: String, CodingKey {
        case lobby
        case gameId
        case guestJoined = "guest_joined"
        case youSeat = "you_seat"
        case players
        case bothReady = "both_ready"
        case startError = "start_error"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        lobby = try container.decode(LobbyDTO.self, forKey: .lobby)
        gameId = try container.decodeIfPresent(String.self, forKey: .gameId)
        guestJoined = try container.decodeIfPresent(Bool.self, forKey: .guestJoined) ?? false
        youSeat = try container.decodeIfPresent(Int.self, forKey: .youSeat)
        players = try container.decodeIfPresent([LobbyPlayerDTO].self, forKey: .players) ?? []
        bothReady = try container.decodeIfPresent(Bool.self, forKey: .bothReady) ?? false
        startError = try container.decodeIfPresent(String.self, forKey: .startError)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(lobby, forKey: .lobby)
        try container.encodeIfPresent(gameId, forKey: .gameId)
        try container.encode(guestJoined, forKey: .guestJoined)
        try container.encodeIfPresent(youSeat, forKey: .youSeat)
        try container.encode(players, forKey: .players)
        try container.encode(bothReady, forKey: .bothReady)
        try container.encodeIfPresent(startError, forKey: .startError)
    }

    struct LobbyDTO: Codable {
        let id: String
        let invite_code: String
        let status: String
    }
}

struct GameStartResponse: Codable {
    let gameId: String
    let perspective: PlayerPerspective
    let testBot: Bool?
}

struct BettingDTO: Codable, Equatable {
    let raw: Int?
    let bucket: Int?
}

struct GameStateResponse: Codable {
    let perspective: PlayerPerspective
    let moveSeq: Int
    let status: String
    let betting: BettingDTO?
}

struct MoveResponse: Codable {
    let perspective: PlayerPerspective
    let moveSeq: Int
    let betting: BettingDTO?
}

struct GameChatMessageDTO: Codable, Equatable, Identifiable {
    let id: String
    let userId: String
    let displayName: String
    let body: String
    let createdAt: String
    let fromSelf: Bool
}

struct GameChatListResponse: Codable {
    let messages: [GameChatMessageDTO]
}

struct GameChatPostResponse: Codable {
    let message: GameChatMessageDTO
}

struct AuthTokenResponse: Codable {
    let access_token: String
    /// Supabase rotates the refresh token on every refresh; persist whichever one we last received.
    let refresh_token: String?
    /// Seconds-until-expiry from the auth server. Combine with the local clock to compute `expiresAt`.
    let expires_in: Int?
    let token_type: String?
    let user: AuthUser?

    struct AuthUser: Codable {
        let id: String
        let email: String?
    }
}

/// Swift port of the subset of `backend/rules/src/melds.ts` needed for client-side
/// previews — specifically `bestDeadwood`, `isBigGin11`, and `upcardKnockValue`.
/// The server is still authoritative; this just lets the iOS UI gate the Knock /
/// Gin / Declare-EO buttons so players don't tap them and bounce off a 400.
///
/// Cards are 2-character strings: rank first ("A","2"…"9","T","J","Q","K") then
/// suit ("S","H","D","C"). All inputs are assumed to be valid card ids; malformed
/// inputs are treated conservatively (no melds available).
enum MeldSolver {
    enum MeldType { case set, run }

    struct Meld {
        let type: MeldType
        let cards: [String]
    }

    struct Partition {
        let melds: [Meld]
        let deadwood: [String]
    }

    struct Result {
        let sum: Int
        let partition: Partition
    }

    private static let rankIndex: [Character: Int] = [
        "A": 1, "2": 2, "3": 3, "4": 4, "5": 5,
        "6": 6, "7": 7, "8": 8, "9": 9, "T": 10,
        "J": 11, "Q": 12, "K": 13,
    ]

    private static func parseRank(_ card: String) -> Character {
        card.first ?? " "
    }

    private static func parseSuit(_ card: String) -> Character {
        card.last ?? " "
    }

    private static func rankOrderLow(_ card: String) -> Int {
        rankIndex[parseRank(card)] ?? 0
    }

    static func deadwoodValue(_ card: String) -> Int {
        let r = parseRank(card)
        if r == "T" || r == "J" || r == "Q" || r == "K" { return 10 }
        if r == "A" { return 1 }
        return rankIndex[r] ?? 0
    }

    /// Returns the knock-card value (2…10) or nil for an Ace upcard, matching
    /// `upcardKnockValue` in `backend/rules/src/cards.ts`.
    static func upcardKnockValue(_ card: String?) -> Int? {
        guard let card, !card.isEmpty else { return nil }
        if parseRank(card) == "A" { return nil }
        return deadwoodValue(card)
    }

    private static func isValidSet(_ cards: [String]) -> Bool {
        if cards.count < 3 || cards.count > 4 { return false }
        let ranks = Set(cards.map(parseRank))
        if ranks.count != 1 { return false }
        let suits = cards.map(parseSuit)
        if Set(suits).count != suits.count { return false }
        return true
    }

    private static func isValidRun(_ cards: [String]) -> Bool {
        if cards.count < 3 { return false }
        guard let first = cards.first else { return false }
        let suit = parseSuit(first)
        if !cards.allSatisfy({ parseSuit($0) == suit }) { return false }
        let ordersSet = Set(cards.map(rankOrderLow))
        if ordersSet.count != cards.count { return false }
        let orders = ordersSet.sorted()
        for i in 1 ..< orders.count where orders[i] != orders[i - 1] + 1 {
            return false
        }
        return true
    }

    private static func isValidMeld(_ meld: Meld) -> Bool {
        switch meld.type {
        case .set: return isValidSet(meld.cards)
        case .run: return isValidRun(meld.cards)
        }
    }

    private static func deadwoodSum(_ cards: [String]) -> Int {
        cards.reduce(0) { $0 + deadwoodValue($1) }
    }

    private static func subsetsOfSize(_ arr: [String], k: Int) -> [[String]] {
        var res: [[String]] = []
        var chosen: [String] = []
        func rec(_ start: Int) {
            if chosen.count == k {
                res.append(chosen)
                return
            }
            for i in start ..< arr.count {
                chosen.append(arr[i])
                rec(i + 1)
                chosen.removeLast()
            }
        }
        rec(0)
        return res
    }

    /// Enumerate meld partitions; return minimum deadwood sum and one optimal partition.
    /// Mirrors `bestDeadwood` in `melds.ts`.
    static func bestDeadwood(_ hand: [String]) -> Result {
        if Set(hand).count != hand.count {
            return Result(sum: deadwoodSum(hand), partition: Partition(melds: [], deadwood: hand))
        }
        let cards = hand.sorted()
        var bestSum = Int.max
        var bestPartition = Partition(melds: [], deadwood: hand)

        func dfs(_ remaining: [String], _ meldsSoFar: [Meld]) {
            if remaining.isEmpty {
                if 0 < bestSum {
                    bestSum = 0
                    bestPartition = Partition(melds: meldsSoFar, deadwood: [])
                }
                return
            }

            if remaining.count < 3 {
                let s = deadwoodSum(remaining)
                if s < bestSum {
                    bestSum = s
                    bestPartition = Partition(melds: meldsSoFar, deadwood: remaining)
                }
                return
            }

            for len in stride(from: min(4, remaining.count), through: 3, by: -1) {
                for combo in subsetsOfSize(remaining, k: len) {
                    let sortedCombo = combo.sorted()
                    let setM = Meld(type: .set, cards: sortedCombo)
                    let runM = Meld(type: .run, cards: sortedCombo)
                    for meld in [setM, runM] {
                        if !isValidMeld(meld) { continue }
                        let used = Set(meld.cards)
                        let rest = remaining.filter { !used.contains($0) }
                        dfs(rest, meldsSoFar + [meld])
                    }
                }
            }

            let s = deadwoodSum(remaining)
            if s < bestSum {
                bestSum = s
                bestPartition = Partition(melds: meldsSoFar, deadwood: remaining)
            }
        }

        dfs(cards, [])
        if bestSum == .max {
            return Result(sum: deadwoodSum(cards), partition: Partition(melds: [], deadwood: cards))
        }
        return Result(sum: bestSum, partition: bestPartition)
    }

    /// Per-card eligibility for the player's 11-card hand. For each potential discard
    /// we run `bestDeadwood` on the remaining 10 cards and bucket the discard:
    /// - `plain`    — the remaining 10 have deadwood > 0, plain Discard is legal.
    /// - `ginable`  — the remaining 10 have deadwood == 0, Gin is legal.
    /// - `knockable`— the remaining 10 have deadwood exactly equal to knockValue (first
    ///   upcard; not an Ace), Knock is legal. Gin (deadwood 0) is separate.
    /// ~11 calls to `bestDeadwood(10 cards)` per hand snapshot; well under 100ms in practice.
    struct DiscardEligibility {
        var plain: Set<String> = []
        var ginable: Set<String> = []
        var knockable: Set<String> = []
    }

    static func eligibility(forHand11 hand: [String], knockCheckCard: String?) -> DiscardEligibility {
        guard hand.count == 11, Set(hand).count == 11 else { return DiscardEligibility() }
        let knockVal = upcardKnockValue(knockCheckCard)
        var e = DiscardEligibility()
        for c in hand {
            let hand10 = hand.filter { $0 != c }
            let best = bestDeadwood(hand10).sum
            if best > 0 { e.plain.insert(c) }
            if best == 0 { e.ginable.insert(c) }
            if let kv = knockVal, best > 0, best == kv { e.knockable.insert(c) }
        }
        return e
    }

    /// True iff all 11 cards can be partitioned into valid melds (Big Gin / "EO").
    /// Mirrors `isBigGin11` in `melds.ts`.
    static func isBigGin11(_ hand: [String]) -> Bool {
        if hand.count != 11 { return false }

        func canPartition(_ remaining: [String]) -> Bool {
            if remaining.isEmpty { return true }
            if remaining.count < 3 { return false }
            for len in stride(from: min(remaining.count, 4), through: 3, by: -1) {
                for combo in subsetsOfSize(remaining, k: len) {
                    let sortedCombo = combo.sorted()
                    let setM = Meld(type: .set, cards: sortedCombo)
                    let runM = Meld(type: .run, cards: sortedCombo)
                    for meld in [setM, runM] {
                        if !isValidMeld(meld) { continue }
                        let used = Set(meld.cards)
                        let rest = remaining.filter { !used.contains($0) }
                        if canPartition(rest) { return true }
                    }
                }
            }
            return false
        }

        return canPartition(hand)
    }
}
