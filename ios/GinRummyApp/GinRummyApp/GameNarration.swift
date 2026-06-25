import Foundation

/// Pure, view-independent text/narration helpers for the game table.
///
/// These were extracted out of the 2,900-line `GameView` so the "perspective →
/// human-readable line" logic — historically the source of most "wrong banner /
/// wrong label" bugs — can be unit-tested without standing up a SwiftUI view.
/// Every function here is a pure function of its arguments: no view state, no
/// side effects. `GameView` keeps thin wrappers that delegate here.
enum GameNarration {
    /// Human-readable card name, e.g. `"AS"` → `"Ace of Spades"`. Falls back to
    /// the raw string when it isn't a recognizable two-character card id.
    static func cardName(_ raw: String) -> String {
        let c = CardIdValidation.normalize(raw)
        guard c.count == 2 else { return raw }
        let r = c.first!
        let s = c.last!
        let rank: String = switch r {
        case "A": "Ace"
        case "K": "King"
        case "Q": "Queen"
        case "J": "Jack"
        case "T": "10"
        default: String(r)
        }
        let suit: String = switch s {
        case "S": "Spades"
        case "H": "Hearts"
        case "D": "Diamonds"
        case "C": "Clubs"
        default: String(s)
        }
        return "\(rank) of \(suit)"
    }

    static func turnLine(_ p: PlayerPerspective) -> String {
        if p.currentTurn == p.seat { return "Your turn" }
        return "Opponent’s turn"
    }

    static func cutStageTitle(_ p: PlayerPerspective) -> String {
        guard let c = p.cut else { return "High card wins the first deal" }
        return c.youMustPick ? "Your turn — tap the spread to cut" : "Opponent is cutting"
    }

    static func knockLayoffLine(_ p: PlayerPerspective, k: PlayerPerspective.KnockPerspective) -> String {
        let whose = k.layoffTurn == p.seat ? "Your" : "Opponent’s"
        return "Layoff · \(whose) turn"
    }

    /// Seat that has crossed the race target, if any.
    private static func matchWinnerSeat(_ p: PlayerPerspective) -> Int? {
        if p.scores[0] >= p.raceTarget { return 0 }
        if p.scores[1] >= p.raceTarget { return 1 }
        return nil
    }

    static func matchOutcomeSubtitle(_ p: PlayerPerspective) -> String {
        guard let w = matchWinnerSeat(p) else { return "Race to \(p.raceTarget)" }
        return w == p.seat ? "You reached \(p.raceTarget) first." : "Opponent reached \(p.raceTarget) first."
    }

    static func matchWinnerHeadline(_ p: PlayerPerspective) -> String {
        guard let w = matchWinnerSeat(p) else { return "Match complete" }
        return w == p.seat ? "You won the match" : "Opponent won the match"
    }
}
