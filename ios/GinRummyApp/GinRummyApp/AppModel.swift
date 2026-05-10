import Combine
import Foundation
import Security
import SwiftUI

@MainActor
final class AppModel: ObservableObject {
    /// Current bearer used for every authenticated API call. Kept in sync with `refreshToken` /
    /// `expiresAt` whenever a session is adopted or refreshed; views read it directly.
    @Published var accessToken: String?
    @Published var pendingJoinCode: String?
    @Published var activeGameId: String?
    @Published var lastPerspective: PlayerPerspective?
    /// Final-match settlement. Server populates `{ raw, bucket }` only when phase == matchOver;
    /// reset to nil between hands and on signOut.
    @Published var lastBetting: BettingDTO?
    @Published var lastError: String?

    /// While true, RootView shows a brief "Restoring session…" spinner instead of bouncing the
    /// user to AuthView during the access-token refresh that happens at app launch.
    @Published var restoring = false

    private var refreshToken: String?
    private var expiresAt: Date?
    private var refreshTimerTask: Task<Void, Never>?
    private var refreshInFlight = false

    let api = APIClient()

    init() {
        restoreFromKeychain()
        startBackgroundRefreshLoop()
    }

    func consumePendingJoin() -> String? {
        let c = pendingJoinCode
        pendingJoinCode = nil
        return c?.uppercased()
    }

    func handleInviteURL(_ url: URL) {
        if url.scheme?.lowercased() == "ginrummy", url.host?.lowercased() == "join" {
            let code = url.pathComponents.dropFirst().first ?? ""
            if !code.isEmpty { pendingJoinCode = code.uppercased() }
            return
        }
        if url.path.contains("/join/") {
            let parts = url.path.split(separator: "/")
            if let idx = parts.firstIndex(of: "join"), idx + 1 < parts.endIndex {
                pendingJoinCode = String(parts[idx + 1]).uppercased()
            }
        }
    }

    /// Apply a freshly-obtained Supabase session (sign-in or refresh). Replaces the in-memory
    /// tokens, re-arms expiry, and writes the new state to the Keychain.
    func adoptSession(_ resp: AuthTokenResponse) {
        accessToken = resp.access_token
        if let rt = resp.refresh_token { refreshToken = rt }
        if let exp = resp.expires_in {
            expiresAt = Date().addingTimeInterval(TimeInterval(exp))
        }
        persistSession()
    }

    /// Forget the user's tokens locally and clear active-game state.
    func signOut() {
        accessToken = nil
        refreshToken = nil
        expiresAt = nil
        activeGameId = nil
        lastPerspective = nil
        lastBetting = nil
        KeychainStore.clear()
    }

    /// Refresh the access token if it expires within the next two minutes. No-ops when there's
    /// no session, when it's still fresh, or when a refresh is already in flight.
    func refreshIfExpiringSoon() async {
        if refreshInFlight { return }
        guard let rt = refreshToken else { return }
        if let exp = expiresAt, exp.timeIntervalSinceNow > 120 { return }

        refreshInFlight = true
        defer { refreshInFlight = false }

        do {
            let resp = try await api.refreshSession(refreshToken: rt)
            adoptSession(resp)
        } catch {
            /* Refresh failed (token revoked / network down) — drop the session so AuthView can show. */
            signOut()
        }
    }

    private func restoreFromKeychain() {
        guard let saved = KeychainStore.loadSession() else { return }
        refreshToken = saved.refreshToken
        expiresAt = saved.expiresAt
        if saved.expiresAt.timeIntervalSinceNow > 30 {
            /* Stored access token is still good — use it directly, refresher will take over later. */
            accessToken = saved.accessToken
            return
        }
        /* Access token has expired (or is about to). Block the UI on a refresh attempt instead of
         * flashing the sign-in screen. If the refresh fails, signOut() drops us to AuthView. */
        restoring = true
        Task { @MainActor in
            await refreshIfExpiringSoon()
            restoring = false
        }
    }

    private func persistSession() {
        guard let access = accessToken, let refresh = refreshToken, let exp = expiresAt else {
            KeychainStore.clear()
            return
        }
        KeychainStore.saveSession(StoredSession(accessToken: access, refreshToken: refresh, expiresAt: exp))
    }

    private func startBackgroundRefreshLoop() {
        refreshTimerTask?.cancel()
        refreshTimerTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 30_000_000_000) /* 30s cadence */
                await self?.refreshIfExpiringSoon()
            }
        }
    }
}

/// What we persist in the iOS Keychain. Refresh tokens are essentially passwords, so we don't
/// keep them in UserDefaults (plaintext on-disk).
struct StoredSession: Codable {
    let accessToken: String
    let refreshToken: String
    let expiresAt: Date
}

enum KeychainStore {
    private static let service = "com.lowelljones.GinRummyApp"
    private static let account = "supabase-session"

    static func saveSession(_ s: StoredSession) {
        guard let data = try? JSONEncoder().encode(s) else { return }
        let base: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(base as CFDictionary)
        var add = base
        add[kSecValueData as String] = data
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        SecItemAdd(add as CFDictionary, nil)
    }

    static func loadSession() -> StoredSession? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data else { return nil }
        return try? JSONDecoder().decode(StoredSession.self, from: data)
    }

    static func clear() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
    }
}
