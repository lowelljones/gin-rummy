import Combine
import Foundation
import SwiftUI

struct InviteAcceptPresentation: Identifiable, Equatable {
    let inviteCode: String
    var id: String { inviteCode }
}

/// Recovery tokens from a password-reset email link; drives the set-new-password sheet.
struct PasswordResetPresentation: Identifiable, Equatable {
    let accessToken: String
    let refreshToken: String?
    let expiresIn: Int?
    var id: String { accessToken }
}

/// An invite that arrived while the user was mid-game. Surfaced as a banner at
/// the top of the table instead of the full-screen InviteAcceptView, since
/// accepting means forfeiting the game in progress.
struct InGameInvite: Equatable {
    let inviteCode: String
    var hostDisplayName: String?

    var hostLabel: String {
        let t = hostDisplayName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return t.isEmpty ? "Someone" : t
    }
}

@MainActor
final class AppModel: ObservableObject {
    /// Current bearer used for every authenticated API call. Kept in sync with `refreshToken` /
    /// `expiresAt` whenever a session is adopted or refreshed; views read it directly.
    @Published var accessToken: String?
    /// Email from the last adopted Supabase session; shown on the account screen.
    @Published var userEmail: String?
    /// Nickname friends see in lobbies and invites (from `/account/profile`).
    @Published var displayName: String = "Player"
    /// Non-nil after the user taps an invite link / universal link (`ginrummy://join/…` or `…/join/CODE`).
    @Published internal private(set) var deepLinkInviteCode: String?
    /// Presented over the main stack when signed in, not in-game, invite link captured.
    @Published var inviteAcceptPresentation: InviteAcceptPresentation?
    /// Presented when the user opens a password-reset link from email.
    @Published var passwordResetPresentation: PasswordResetPresentation?

    /// When the user joins from InviteAcceptView, LobbyView consumes this plus a nonce bump to start polling for start.
    @Published internal private(set) var lobbyInviteJoinHandoffNonce: UInt = 0
    private var lobbyInviteJoinHandoffCode: String?

    @Published var activeGameId: String?
    /// Invite link that landed while a game was active — drives the in-game banner.
    @Published var inGameInvite: InGameInvite?
    @Published var lastPerspective: PlayerPerspective?
    /// Display name for the other seat at the table (from API; defaults to "Opponent").
    @Published var opponentDisplayName: String = "Opponent"
    /// Final-match settlement. Server populates `{ raw, bucket }` only when phase == matchOver;
    /// reset to nil between hands and on signOut.
    @Published var lastBetting: BettingDTO?
    @Published var lastError: String?

    /// Players the signed-in user has blocked (synced from the API after sign-in).
    @Published private(set) var blockedUserIds: Set<String> = []

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

    func reconcileInviteAcceptPresentation() {
        if restoring {
            inviteAcceptPresentation = nil
            return
        }
        if let c = deepLinkInviteCode, accessToken != nil, activeGameId == nil {
            inviteAcceptPresentation = InviteAcceptPresentation(inviteCode: c)
        } else {
            inviteAcceptPresentation = nil
        }
    }

    func consumeLobbyInviteJoinHandoff() -> String? {
        let code = lobbyInviteJoinHandoffCode
        lobbyInviteJoinHandoffCode = nil
        return code?.uppercased()
    }

    /// Returns true when the URL was a password-reset callback and was handled.
    @discardableResult
    func handlePasswordResetURL(_ url: URL) -> Bool {
        guard let session = Self.parsePasswordResetSession(from: url) else { return false }
        passwordResetPresentation = PasswordResetPresentation(
            accessToken: session.accessToken,
            refreshToken: session.refreshToken,
            expiresIn: session.expiresIn
        )
        return true
    }

    func dismissPasswordReset() {
        passwordResetPresentation = nil
    }

    func finishPasswordReset(adopting resp: AuthTokenResponse) {
        passwordResetPresentation = nil
        adoptSession(resp)
    }

    func handleInviteURL(_ url: URL) {
        guard let code = Self.parseInviteCode(from: url), code.count >= 4 else { return }
        let normalized = code.uppercased()
        if activeGameId != nil {
            /* Mid-game: surface a banner over the table instead of the full-screen
             * invite sheet. Host name is fetched async; banner shows immediately. */
            inGameInvite = InGameInvite(inviteCode: normalized, hostDisplayName: nil)
            Task { @MainActor in
                if let preview = try? await api.lobbyInvitePreview(inviteCode: normalized),
                   inGameInvite?.inviteCode == normalized {
                    inGameInvite?.hostDisplayName = preview.host_display_name
                }
            }
            return
        }
        deepLinkInviteCode = normalized
        reconcileInviteAcceptPresentation()
    }

    func dismissInGameInvite() {
        inGameInvite = nil
    }

    /// Tear down all per-game state. Used when the player leaves mid-game, when the
    /// opponent abandons, and when returning to the lobby after match end.
    func clearActiveGame() {
        activeGameId = nil
        lastPerspective = nil
        lastBetting = nil
        opponentDisplayName = "Opponent"
        /* An invite that arrived mid-game but was never answered follows the player
         * back to the lobby as the regular full-screen invite sheet. */
        if let invite = inGameInvite {
            inGameInvite = nil
            deepLinkInviteCode = invite.inviteCode
        }
        reconcileInviteAcceptPresentation()
    }

    /// Accepting an in-game invite: the current game has already been forfeited by the
    /// caller; clear the table and hand the lobby code to LobbyView so the player lands
    /// in the new game's waiting room.
    func finishInGameInviteAccepted() {
        guard let invite = inGameInvite else { return }
        inGameInvite = nil
        clearActiveGame()
        lobbyInviteJoinHandoffCode = invite.inviteCode
        lobbyInviteJoinHandoffNonce += 1
    }

    func rejectInviteFromDeepLink() {
        deepLinkInviteCode = nil
        inviteAcceptPresentation = nil
    }

    func finishInviteAcceptedJoin(inviteCode: String) {
        let normalized = inviteCode.uppercased()
        deepLinkInviteCode = nil
        inviteAcceptPresentation = nil
        lobbyInviteJoinHandoffCode = normalized
        lobbyInviteJoinHandoffNonce += 1
    }

    /// Internal (not private) so tests can pin the share-link → tapped-link →
    /// code round trip for both URL forms.
    static func parseInviteCode(from url: URL) -> String? {
        if url.scheme?.lowercased() == "ginrummy", url.host?.lowercased() == "join" {
            let code = url.pathComponents.dropFirst().first ?? ""
            return code.isEmpty ? nil : code
        }
        if url.path.contains("/join/") {
            let parts = url.path.split(separator: "/")
            if let idx = parts.firstIndex(of: "join"), idx + 1 < parts.endIndex {
                return String(parts[idx + 1])
            }
        }
        return nil
    }

    /// Parses recovery tokens Supabase appends to the redirect URL fragment after the user
    /// taps the reset link in email (`#access_token=…&type=recovery&…`).
    static func parsePasswordResetSession(from url: URL) -> (
        accessToken: String,
        refreshToken: String?,
        expiresIn: Int?
    )? {
        guard isPasswordResetURL(url) else { return nil }
        guard let fragment = url.fragment, !fragment.isEmpty else { return nil }
        let params = parseURLFragment(fragment)
        guard let token = params["access_token"], !token.isEmpty else { return nil }
        let refresh = params["refresh_token"]
        let expires = params["expires_in"].flatMap { Int($0) }
        return (token, refresh, expires)
    }

    static func isPasswordResetURL(_ url: URL) -> Bool {
        if url.scheme?.lowercased() == "ginrummy", url.host?.lowercased() == "reset-password" {
            return true
        }
        let path = url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        return path == "reset-password"
    }

    private static func parseURLFragment(_ fragment: String) -> [String: String] {
        var params: [String: String] = [:]
        for pair in fragment.split(separator: "&") {
            let kv = pair.split(separator: "=", maxSplits: 1)
            guard kv.count == 2 else { continue }
            let key = String(kv[0])
            let raw = String(kv[1])
            params[key] = raw.removingPercentEncoding ?? raw
        }
        return params
    }

    /// Apply a freshly-obtained Supabase session (sign-in or refresh). Replaces the in-memory
    /// tokens, re-arms expiry, and writes the new state to the Keychain.
    func adoptSession(_ resp: AuthTokenResponse) {
        accessToken = resp.access_token
        if let email = resp.user?.email { userEmail = email }
        if let rt = resp.refresh_token { refreshToken = rt }
        if let exp = resp.expires_in {
            expiresAt = Date().addingTimeInterval(TimeInterval(exp))
        }
        persistSession()
        reconcileInviteAcceptPresentation()
        Task { await refreshProfile() }
        Task { await syncBlockedUsers() }
    }

    func isBlocked(_ userId: String) -> Bool {
        blockedUserIds.contains(userId)
    }

    func syncBlockedUsers() async {
        guard let token = accessToken else {
            blockedUserIds = []
            return
        }
        do {
            let r = try await api.fetchBlockedUsers(token: token)
            blockedUserIds = Set(r.users.map(\.userId))
        } catch {
            /* Non-fatal — keep the last known block list if the fetch fails. */
        }
    }

    func blockUser(_ userId: String) async throws {
        guard let token = accessToken else { return }
        try await api.blockUser(userId: userId, token: token)
        blockedUserIds.insert(userId)
    }

    func unblockUser(_ userId: String) async throws {
        guard let token = accessToken else { return }
        try await api.unblockUser(userId: userId, token: token)
        blockedUserIds.remove(userId)
    }

    /// Load the server-side profile (display name) for the signed-in user.
    func refreshProfile() async {
        guard let token = accessToken else { return }
        do {
            let profile = try await api.fetchAccountProfile(token: token)
            let trimmed = profile.display_name.trimmingCharacters(in: .whitespacesAndNewlines)
            displayName = trimmed.isEmpty ? "Player" : trimmed
            if userEmail == nil, let email = profile.email {
                userEmail = email
            }
        } catch {
            /* Non-fatal — lobby APIs still resolve names; account screen retries on appear. */
        }
    }

    /// Persist a new display name and update local state on success.
    func saveDisplayName(_ raw: String) async throws {
        guard let token = accessToken else { return }
        let resp = try await api.updateDisplayName(raw, token: token)
        let trimmed = resp.display_name.trimmingCharacters(in: .whitespacesAndNewlines)
        displayName = trimmed.isEmpty ? "Player" : trimmed
    }

    /// Forget the user's tokens locally and clear active-game state.
    func signOut() {
        accessToken = nil
        userEmail = nil
        displayName = "Player"
        refreshToken = nil
        expiresAt = nil
        activeGameId = nil
        inGameInvite = nil
        lastPerspective = nil
        opponentDisplayName = "Opponent"
        lastBetting = nil
        blockedUserIds = []
        KeychainStore.clear()
        reconcileInviteAcceptPresentation()
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
            if error is URLError {
                /* Transient connectivity — keep the session and retry later instead
                 * of dumping the user back to the sign-in screen while offline. */
                lastError = UserFeedback.from(error)
                return
            }
            /* Token revoked / invalid — drop the session and tell the user why. */
            lastError = "Your session expired, so you’ve been signed out. Please sign in again."
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
            userEmail = saved.userEmail
            reconcileInviteAcceptPresentation()
            Task {
                await refreshProfile()
                await syncBlockedUsers()
            }
            return
        }
        /* Access token has expired (or is about to). Block the UI on a refresh attempt instead of
         * flashing the sign-in screen. If the refresh fails, signOut() drops us to AuthView. */
        restoring = true
        Task { @MainActor in
            await refreshIfExpiringSoon()
            await refreshProfile()
            restoring = false
            reconcileInviteAcceptPresentation()
        }
    }

    private func persistSession() {
        guard let access = accessToken, let refresh = refreshToken, let exp = expiresAt else {
            KeychainStore.clear()
            return
        }
        KeychainStore.saveSession(
            StoredSession(accessToken: access, refreshToken: refresh, expiresAt: exp, userEmail: userEmail)
        )
    }

    /// Updates table snapshots from `/state`, `/move`, or bot start payloads.
    func applyGameTableState(perspective: PlayerPerspective, betting: BettingDTO?, opponentDisplayName: String? = nil) {
        lastPerspective = perspective
        lastBetting = betting
        if let raw = opponentDisplayName {
            let t = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            self.opponentDisplayName = t.isEmpty ? "Opponent" : t
        }
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
