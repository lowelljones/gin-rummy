import Foundation

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
