import Foundation

enum AppConfig {
    /// Set in Xcode: Target → Info → Custom iOS Target Properties (or build settings user-defined).
    static var supabaseURL: String {
        Bundle.main.object(forInfoDictionaryKey: "SUPABASE_URL") as? String ?? ""
    }

    static var supabaseAnonKey: String {
        Bundle.main.object(forInfoDictionaryKey: "SUPABASE_ANON_KEY") as? String ?? ""
    }

    static var apiBaseURL: String {
        Bundle.main.object(forInfoDictionaryKey: "GIN_API_BASE_URL") as? String ?? "http://127.0.0.1:8787"
    }

    static var inviteWebBaseURL: String {
        Bundle.main.object(forInfoDictionaryKey: "GIN_INVITE_WEB_BASE_URL") as? String ?? ""
    }

    /// Strips optional `http(s)://` and trailing slashes from a base URL string; "" when unusable.
    private static func normalizedAuthority(_ raw: String) -> String {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        while s.last == "/" { s.removeLast() }
        let lower = s.lowercased()
        if lower.hasPrefix("https://") {
            return String(s.dropFirst("https://".count)).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        }
        if lower.hasPrefix("http://") {
            return String(s.dropFirst("http://".count)).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        }
        return s.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }

    /// Domain that hosts the `/join/:code` invite landing page. Prefers the
    /// explicit `GIN_INVITE_WEB_BASE_URL`, then falls back to the API's own
    /// domain (the backend serves `GET /join/:code` itself). Only a local-dev
    /// API (localhost / LAN IP) leaves this empty.
    private static func inviteLinkAuthority() -> String {
        let explicit = normalizedAuthority(inviteWebBaseURL)
        if !explicit.isEmpty, !explicit.lowercased().contains("example.com") {
            return explicit
        }
        // The API serves the invite landing page, so its public domain works too.
        if apiBaseURL.lowercased().hasPrefix("https://") {
            return normalizedAuthority(apiBaseURL)
        }
        return ""
    }

    /// When `true`, share/copy falls back to custom URL scheme links (`ginrummy://`) — local dev only.
    static var usesInviteCustomURLScheme: Bool {
        inviteLinkAuthority().isEmpty
    }

    /// Link shared with friends. HTTPS links are tappable in Messages and land
    /// on the backend's invite page, which bounces into the app. The raw
    /// `ginrummy://` scheme is only used when no public HTTPS domain exists.
    static func inviteShareURL(forInviteCode inviteCode: String) -> URL {
        let auth = inviteLinkAuthority()
        if auth.isEmpty {
            return URL(string: "ginrummy://join/\(inviteCode)")!
        }
        return URL(string: "https://\(auth)/join/\(inviteCode)")!
    }
}
