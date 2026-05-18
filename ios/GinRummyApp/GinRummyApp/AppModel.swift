import Combine
import Foundation
import SwiftUI

struct InviteAcceptPresentation: Identifiable, Equatable {
    let inviteCode: String
    var id: String { inviteCode }
}

@MainActor
final class AppModel: ObservableObject {
    /// Current bearer used for every authenticated API call. Kept in sync with `refreshToken` /
    /// `expiresAt` whenever a session is adopted or refreshed; views read it directly.
    @Published var accessToken: String?
    /// Non-nil after the user taps an invite link / universal link (`ginrummy://join/…` or `…/join/CODE`).
    @Published internal private(set) var deepLinkInviteCode: String?
    /// Presented over the main stack when signed in, not in-game, invite link captured.
    @Published var inviteAcceptPresentation: InviteAcceptPresentation?

    /// When the user joins from InviteAcceptView, LobbyView consumes this plus a nonce bump to start polling for start.
    @Published internal private(set) var lobbyInviteJoinHandoffNonce: UInt = 0
    private var lobbyInviteJoinHandoffCode: String?

    @Published var activeGameId: String?
    @Published var lastPerspective: PlayerPerspective?
    /// Display name for the other seat at the table (from API; defaults to "Opponent").
    @Published var opponentDisplayName: String = "Opponent"
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

    func handleInviteURL(_ url: URL) {
        guard activeGameId == nil else { return }
        guard let code = Self.parseInviteCode(from: url), code.count >= 4 else { return }
        deepLinkInviteCode = code.uppercased()
        reconcileInviteAcceptPresentation()
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

    private static func parseInviteCode(from url: URL) -> String? {
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

    /// Apply a freshly-obtained Supabase session (sign-in or refresh). Replaces the in-memory
    /// tokens, re-arms expiry, and writes the new state to the Keychain.
    func adoptSession(_ resp: AuthTokenResponse) {
        accessToken = resp.access_token
        if let rt = resp.refresh_token { refreshToken = rt }
        if let exp = resp.expires_in {
            expiresAt = Date().addingTimeInterval(TimeInterval(exp))
        }
        persistSession()
        reconcileInviteAcceptPresentation()
    }

    /// Forget the user's tokens locally and clear active-game state.
    func signOut() {
        accessToken = nil
        refreshToken = nil
        expiresAt = nil
        activeGameId = nil
        lastPerspective = nil
        opponentDisplayName = "Opponent"
        lastBetting = nil
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
            reconcileInviteAcceptPresentation()
            return
        }
        /* Access token has expired (or is about to). Block the UI on a refresh attempt instead of
         * flashing the sign-in screen. If the refresh fails, signOut() drops us to AuthView. */
        restoring = true
        Task { @MainActor in
            await refreshIfExpiringSoon()
            restoring = false
            reconcileInviteAcceptPresentation()
        }
    }

    private func persistSession() {
        guard let access = accessToken, let refresh = refreshToken, let exp = expiresAt else {
            KeychainStore.clear()
            return
        }
        KeychainStore.saveSession(StoredSession(accessToken: access, refreshToken: refresh, expiresAt: exp))
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
