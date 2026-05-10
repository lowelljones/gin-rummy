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
        Bundle.main.object(forInfoDictionaryKey: "GIN_INVITE_WEB_BASE_URL") as? String ?? "https://example.com"
    }
}
