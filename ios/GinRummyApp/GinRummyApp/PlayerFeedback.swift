import Foundation
import SwiftUI

// MARK: - Card id (e.g. AD = Ace of Diamonds, 7H = 7 of Hearts)

enum CardIdValidation {
    private static let rankChars = "A23456789TJQK"
    private static let suitChars = "SHDC"

    static func normalize(_ raw: String) -> String {
        raw.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
    }

    /// Two letters: rank (A,2-9,T,J,Q,K) + suit (S,H,D,C).
    static func isValidFormat(_ s: String) -> Bool {
        let u = normalize(s)
        guard u.count == 2 else { return false }
        let r = u.first!
        let su = u.last!
        return rankChars.contains(r) && suitChars.contains(su)
    }

    static var formatHint: String {
        "Use two characters: rank then suit. Ranks: A,2,3,4,5,6,7,8,9,T,J,Q,K. Suits: S (spades), H (hearts), D (diamonds), C (clubs). Example: AD = Ace of Diamonds, 7H = 7 of hearts."
    }

    static func formatProblem(in raw: String) -> String? {
        let u = normalize(raw)
        if u.isEmpty { return "Enter a card, e.g. AD." }
        if u.count != 2 { return "A card is exactly two characters (e.g. AD). You entered \(u.count)." }
        let r = u.first!
        let s = u.last!
        if !rankChars.contains(r) { return "“\(r)” isn’t a valid rank. Use A,2-9,T,J,Q, or K." }
        if !suitChars.contains(s) { return "“\(s)” isn’t a valid suit. Use S, H, D, or C (e.g. AD for Ace of Diamonds)." }
        return nil
    }

    /// Returns nil if the card is in `hand` (or hand uses HIDDEN placeholders — then skip local check and let the server respond).
    static func notInHandMessage(card: String, hand: [String]) -> String? {
        let c = normalize(card)
        if hand.contains("HIDDEN") { return nil }
        if !hand.contains(c) {
            return "You don’t have \(c) in your hand. It isn’t in the list above."
        }
        return nil
    }
}

// MARK: - API errors → short copy

enum UserFeedback {
    static func from(_ error: Error) -> String {
        if case APIError.badStatus(let code, let body) = error {
            if let s = parseErrorField(from: body) { return s }
            if code == 400 { return "The server couldn’t do that. \(body.count > 200 ? String(body.prefix(200)) + "…" : body)" }
        }
        if case APIError.decoding(let e) = error { return "Couldn’t read response: \(e.localizedDescription)" }
        if case APIError.invalidURL = error { return "Invalid server URL. Check GIN_API_BASE_URL." }
        return String(describing: error)
    }

    private static func parseErrorField(from body: String) -> String? {
        guard let data = body.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        if let e = obj["error"] as? String, !e.isEmpty { return e }
        if let m = obj["message"] as? String, !m.isEmpty, !m.contains("FST_ERR_") { return m }
        return nil
    }
}

// MARK: - In-game feedback line

struct FeedbackLine: View {
    let text: String
    let isError: Bool
    /// Matches Private Club chrome (cream / sage / burgundy) instead of system red/green.
    var privateClubStyle = false

    var body: some View {
        if !text.isEmpty {
            Text(text)
                .font(.subheadline)
                .foregroundStyle(privateClubStyle ? GinRummyPalette.cream : Color.primary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10)
                .background(feedbackFill)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(feedbackStroke, lineWidth: 1)
                )
        }
    }

    private var feedbackFill: Color {
        if privateClubStyle {
            return isError ? GinRummyPalette.burgundy.opacity(0.22) : GinRummyPalette.bgPanel.opacity(0.55)
        }
        return isError ? Color.red.opacity(0.12) : Color.green.opacity(0.12)
    }

    private var feedbackStroke: Color {
        if privateClubStyle {
            return isError ? GinRummyPalette.burgundy.opacity(0.85) : GinRummyPalette.gold.opacity(0.42)
        }
        return isError ? Color.red.opacity(0.35) : Color.green.opacity(0.35)
    }
}
