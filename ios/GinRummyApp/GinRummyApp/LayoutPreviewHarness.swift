import Foundation

/// Debug-only screenshot harness for layout QA.
///
/// App Review rejected 1.0 (9) under Guideline 4 because the propose-redeal
/// footer was clipped off the bottom of the window on an iPad Air 11". The game
/// table is only reachable through a live two-player match, which makes it very
/// hard to eyeball at other window sizes. Launching with
/// `-ginLayoutPreview <surface>` seeds `AppModel` with a canned perspective and
/// suppresses networking, so any surface can be rendered on any simulator.
///
/// Surfaces: `cutForDeal`, `downCard`, `play`, `playWaiting`, `knockLayoff`,
/// `handOver`, `matchOver`, `redealPending`.
///
/// Compiled out of Release builds entirely — nothing here ships.
enum LayoutPreview {
    #if DEBUG
        static let surface: String? = {
            let args = ProcessInfo.processInfo.arguments
            guard let i = args.firstIndex(of: "-ginLayoutPreview"), i + 1 < args.count else { return nil }
            return args[i + 1]
        }()
    #else
        static let surface: String? = nil
    #endif

    static var isActive: Bool { surface != nil }

    #if DEBUG
        @MainActor
        static func seedIfRequested(_ app: AppModel) {
            guard let surface else { return }
            app.restoring = false
            // `lobby` signs in without a game so the home screen can be checked too.
            let p = surface == "lobby" ? nil : perspective(for: surface)
            guard surface == "lobby" || p != nil else { return }
            app.seedForLayoutPreview(perspective: p, opponentDisplayName: "Alexandra")
        }

        private static func perspective(for surface: String) -> PlayerPerspective? {
            guard let json = json(for: surface)?.data(using: .utf8) else { return nil }
            do {
                return try JSONDecoder().decode(PlayerPerspective.self, from: json)
            } catch {
                assertionFailure("LayoutPreview: bad canned perspective for \(surface): \(error)")
                return nil
            }
        }

        /// A ten-card hand with every rank width represented (T is the widest label).
        private static let myHand = #"["7C","QD","KD","4H","5H","7H","5S","9S","TS","KS"]"#
        private static let oppHand = #"["AC","2C","3C","4C","5C","6C","7C","8C","9C","TC"]"#

        private static func json(for surface: String) -> String? {
            switch surface {
            case "cutForDeal":
                return """
                {
                  "seat": 0, "hands": [[], []], "stockCount": 52, "discard": [],
                  "phase": "cutForDeal", "dealer": 0, "nonDealer": 1, "currentTurn": 0,
                  "scores": [0, 0], "handsWon": [0, 0], "raceTarget": 125,
                  "cut": {
                    "faceDownRemaining": 52, "activePicker": 0, "youMustPick": true,
                    "opponentHasPicked": false, "firstCutSeat": 0
                  }
                }
                """
            case "downCard":
                // The exact surface in the rejection screenshot: Take / Pass /
                // Propose redeal all live at the bottom at once.
                return """
                {
                  "seat": 0, "hands": [\(myHand), \(oppHand)], "stockCount": 31,
                  "discard": ["3C"], "phase": "upcardOffer", "dealer": 1, "nonDealer": 0,
                  "currentTurn": 0, "scores": [0, 0], "handsWon": [0, 0], "raceTarget": 125,
                  "knockCheckCard": "3C",
                  "upcardOffer": { "stage": "nonDealer", "nonDealerPassed": false }
                }
                """
            case "play":
                return """
                {
                  "seat": 0, "hands": [\(myHand), \(oppHand)], "stockCount": 24,
                  "discard": ["3C", "8D", "2H"], "phase": "play", "dealer": 1, "nonDealer": 0,
                  "currentTurn": 0, "scores": [64, 41], "handsWon": [3, 2], "raceTarget": 125,
                  "knockCheckCard": "3C"
                }
                """
            case "playDiscard":
                // Tallest bottom bar in the app: Discard / Gin / Knock, the drag
                // hint, and Propose redeal, all in one pinned bar.
                return """
                {
                  "seat": 0,
                  "hands": [["7C","QD","KD","4H","5H","7H","5S","9S","TS","KS","2D"], \(oppHand)],
                  "stockCount": 22,
                  "discard": ["3C", "8D"], "phase": "play", "dealer": 1, "nonDealer": 0,
                  "currentTurn": 0, "scores": [64, 41], "handsWon": [3, 2], "raceTarget": 125,
                  "knockCheckCard": "3C"
                }
                """
            case "playWaiting":
                return """
                {
                  "seat": 0, "hands": [\(myHand), \(oppHand)], "stockCount": 24,
                  "discard": ["3C", "8D", "2H"], "phase": "play", "dealer": 1, "nonDealer": 0,
                  "currentTurn": 1, "scores": [64, 41], "handsWon": [3, 2], "raceTarget": 125,
                  "knockCheckCard": "3C"
                }
                """
            case "redealPending":
                return """
                {
                  "seat": 0, "hands": [\(myHand), \(oppHand)], "stockCount": 24,
                  "discard": ["3C", "8D"], "phase": "play", "dealer": 1, "nonDealer": 0,
                  "currentTurn": 0, "scores": [64, 41], "handsWon": [3, 2], "raceTarget": 125,
                  "knockCheckCard": "3C",
                  "redeal": { "fromSeat": 1, "status": "pending" }
                }
                """
            case "knockLayoff":
                // Defender's arrangement screen — the densest layout in the app.
                return """
                {
                  "seat": 0,
                  "hands": [["7C","QD","KD","4H","5H","6H","5S","9S","TS","KS"], \(oppHand)],
                  "stockCount": 18, "discard": ["3C","8D"], "phase": "knockLayoff",
                  "dealer": 1, "nonDealer": 0, "currentTurn": 1,
                  "scores": [64, 41], "handsWon": [3, 2], "raceTarget": 125,
                  "knockCheckCard": "3C",
                  "knock": {
                    "knocker": 1, "knockCard": "3C",
                    "knockerMelds": [
                      { "type": "run", "cards": ["3C","4C","5C"] },
                      { "type": "run", "cards": ["7C","8C","9C"] }
                    ],
                    "knockerDeadwood": ["AC","2C"],
                    "opponentDeadwood": ["7C","QD","KD","4H","5H","6H","5S","9S","TS","KS"],
                    "layoffTurn": 0
                  }
                }
                """
            case "handOver", "matchOver":
                let phase = surface == "handOver" ? "handOver" : "matchOver"
                let scores = surface == "handOver" ? "[64, 41]" : "[131, 41]"
                return """
                {
                  "seat": 0,
                  "hands": [["7C","QD","KD","4H","5H","6H","5S","9S","TS","KS"], \(oppHand)],
                  "stockCount": 18, "discard": ["3C","8D"], "phase": "\(phase)",
                  "dealer": 1, "nonDealer": 0, "currentTurn": 1,
                  "scores": \(scores), "handsWon": [3, 3], "raceTarget": 125,
                  "knockCheckCard": "3C",
                  "handOverAcks": [false, false],
                  "handResult": {
                    "kind": "knock", "winner": 1, "points": 23, "closer": 1,
                    "sides": [
                      {
                        "melds": [
                          { "type": "run", "cards": ["4H","5H","6H"] },
                          { "type": "set", "cards": ["KD","KS","KC"] }
                        ],
                        "deadwood": ["7C","5S","9S","TS"],
                        "deadwoodPoints": 31
                      },
                      {
                        "melds": [
                          { "type": "run", "cards": ["3C","4C","5C"] },
                          { "type": "run", "cards": ["7C","8C","9C"] },
                          { "type": "set", "cards": ["TC","TD","TH"] }
                        ],
                        "deadwood": ["AC"],
                        "deadwoodPoints": 8
                      }
                    ],
                    "layoffs": []
                  }
                }
                """
            default:
                return nil
            }
        }
    #else
        @MainActor
        static func seedIfRequested(_: AppModel) {}
    #endif
}
