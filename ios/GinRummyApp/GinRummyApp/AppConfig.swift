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

    /// Host/path prefix for HTTPS invite links — strips optional `http(s)://`; empty when unset / placeholder domain.
    private static func normalizedInviteWebAuthority() -> String {
        var s = inviteWebBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)
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

    /// When `true`, share/copy uses custom URL scheme links (`ginrummy://`).
    static var usesInviteCustomURLScheme: Bool {
        let auth = normalizedInviteWebAuthority().lowercased()
        return auth.isEmpty || auth.contains("example.com")
    }

    /// Link shared with friends; opens the installed app (`ginrummy://`) until you configure a hosted domain + Universal Links.
    static func inviteShareURL(forInviteCode inviteCode: String) -> URL {
        let auth = normalizedInviteWebAuthority().lowercased()
        if auth.isEmpty || auth.contains("example.com") {
            return URL(string: "ginrummy://join/\(inviteCode)")!
        }
        return URL(string: "https://\(auth)/join/\(inviteCode)")!
    }
}
