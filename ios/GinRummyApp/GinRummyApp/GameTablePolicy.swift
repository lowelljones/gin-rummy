import Foundation

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
