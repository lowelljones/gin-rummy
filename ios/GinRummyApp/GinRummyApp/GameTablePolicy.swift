import CoreGraphics
import Foundation

/// Vertical sizing for the fixed, scroll-free play table.
///
/// The table used to hard-code its furniture at sizes tuned for a modern
/// iPhone. Anything shorter overflowed the bottom of the window and clipped the
/// action bar — which is how 1.0 (9) was rejected: on iPadOS the app runs in a
/// 375 × 721 pt compatibility window, ~40 pt shorter than the layout needed.
/// iPhone SE (375 × 667) has the same problem.
///
/// Everything vertical is now derived from the height the table actually gets,
/// interpolating between a compact floor that fits a short window and the
/// original roomy sizing. The pinned action bar is reserved first and never
/// shrinks below tap-target size.
struct TableLayoutMetrics: Equatable {
    var rowSpacing: CGFloat
    var opponentFanHeight: CGFloat
    var handHeight: CGFloat
    var pileCardWidth: CGFloat
    var knockCardWidth: CGFloat
    var statusLogLineLimit: Int
    /// Hidden on the shortest canvases — the same value is already on the pile's
    /// face-up card, so it is the cheapest row to drop.
    var showsKnockLimitCard: Bool

    /// Table height the original design was drawn against (iPhone 15/16-class).
    static let referenceHeight: CGFloat = 780
    /// Everything still fits, tightly, at this height.
    static let compactHeight: CGFloat = 470
    /// Below this the knock-limit row is dropped rather than squeezed — it is the
    /// only row on the table that is informational rather than interactive.
    static let knockLimitCardMinimumHeight: CGFloat = 570

    static func fit(availableHeight: CGFloat) -> TableLayoutMetrics {
        let span = referenceHeight - compactHeight
        let t = min(max((availableHeight - compactHeight) / span, 0), 1)
        func lerp(_ lo: CGFloat, _ hi: CGFloat) -> CGFloat { (lo + (hi - lo) * t).rounded() }

        return TableLayoutMetrics(
            rowSpacing: lerp(4, 8),
            opponentFanHeight: lerp(38, 74),
            handHeight: lerp(92, 152),
            pileCardWidth: lerp(36, 58),
            knockCardWidth: lerp(28, 58),
            statusLogLineLimit: availableHeight >= 660 ? 3 : 2,
            showsKnockLimitCard: availableHeight >= knockLimitCardMinimumHeight
        )
    }
}

/// Pure table UI policy shared by GameView and unit tests.
enum GameTablePolicy {
    static func proposeRedealAllowed(phase: String) -> Bool {
        switch phase {
        case "upcardOffer", "play", "knockLayoff": true
        default: false
        }
    }

    static func isPendingRedeal(_ redeal: RedealStateDTO?) -> Bool {
        redeal?.status == "pending"
    }

    static func exitStateForAbandonment(leftBySeat: Int?, mySeat: Int) -> String {
        if let leftBy = leftBySeat, leftBy == mySeat {
            return "youLeft"
        }
        return "opponentLeft"
    }
}
