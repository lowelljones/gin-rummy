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
        if let urlError = error as? URLError {
            return message(for: urlError)
        }
        if case APIError.badStatus(let code, let body) = error {
            // Prefer a specific message the server (or Supabase) gave us.
            if let s = parseErrorField(from: body) { return s }
            return statusMessage(code: code, body: body)
        }
        if case APIError.decoding = error {
            return "We couldn’t read the server’s response. Please try again."
        }
        if case APIError.invalidURL = error {
            return "The app is pointed at an invalid server address. Check GIN_API_BASE_URL."
        }
        let ns = error as NSError
        if ns.domain == NSURLErrorDomain {
            return "Network problem. Check your connection and try again."
        }
        return "Something went wrong. Please try again."
    }

    /// Friendly, actionable copy for connectivity failures.
    private static func message(for error: URLError) -> String {
        switch error.code {
        case .notConnectedToInternet:
            return "You’re offline. Check your internet connection and try again."
        case .timedOut:
            return "The server took too long to respond. Check your connection and try again."
        case .cannotConnectToHost, .cannotFindHost, .dnsLookupFailed, .networkConnectionLost:
            return "Can’t reach the game server right now. Try again in a moment."
        case .secureConnectionFailed, .serverCertificateUntrusted:
            return "Secure connection to the server failed. Try again."
        default:
            return "Network problem. Check your connection and try again."
        }
    }

    /// Maps HTTP status codes to plain-language guidance when the body has no
    /// usable message.
    private static func statusMessage(code: Int, body: String) -> String {
        switch code {
        case 400:
            let trimmed = body.count > 200 ? String(body.prefix(200)) + "…" : body
            return trimmed.isEmpty
                ? "That request couldn’t be completed. Please try again."
                : "The server couldn’t do that. \(trimmed)"
        case 401:
            return "Your session has expired. Please sign in again."
        case 403:
            return "You’re not allowed to do that here."
        case 404:
            return "We couldn’t find that — it may have ended or expired."
        case 408:
            return "The request timed out. Please try again."
        case 409:
            return "That conflicts with the current game state. Refresh and try again."
        case 429:
            return "You’re going a bit fast — wait a moment and try again."
        case 500...599:
            return "The server hit a problem. Please try again in a moment."
        default:
            return "Something went wrong (error \(code)). Please try again."
        }
    }

    private static func parseErrorField(from body: String) -> String? {
        guard let data = body.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        // Map known Supabase/auth machine codes to friendly copy first.
        if let code = (obj["error_code"] as? String) ?? (obj["code"] as? String) ?? (obj["error"] as? String),
           let mapped = authMessage(for: code) {
            return mapped
        }
        if let d = obj["error_description"] as? String, !d.isEmpty { return d }
        if let m = obj["msg"] as? String, !m.isEmpty { return m }
        // Node API errors are human phrases (e.g. "Lobby not found"); show as-is.
        if let e = obj["error"] as? String, !e.isEmpty, !e.contains("_") { return e }
        if let m = obj["message"] as? String, !m.isEmpty, !m.contains("FST_ERR_") { return m }
        return nil
    }

    private static func authMessage(for code: String) -> String? {
        switch code.lowercased() {
        case "invalid_grant", "invalid_credentials":
            return "Incorrect email or password. Double-check them and try again."
        case "email_exists", "user_already_exists":
            return "That email already has an account. Try signing in instead."
        case "weak_password":
            return "That password is too weak — use at least 6 characters."
        case "over_email_send_rate_limit", "over_request_rate_limit":
            return "Too many attempts. Wait a minute and try again."
        case "email_not_confirmed":
            return "Confirm your email first — check your inbox for the link."
        case "signup_disabled":
            return "New sign-ups are currently disabled."
        case "validation_failed":
            return "Please enter a valid email and password."
        default:
            return nil
        }
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
