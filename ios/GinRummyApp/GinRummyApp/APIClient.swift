import Foundation

enum APIError: Error {
    case invalidURL
    case badStatus(Int, String)
    case decoding(Error)
}

final class APIClient {
    private let session: URLSession
    private let baseURL: String

    init(baseURL: String = AppConfig.apiBaseURL) {
        self.baseURL = baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        self.session = URLSession(configuration: config)
    }

    private func request<T: Decodable>(
        path: String,
        method: String = "GET",
        token: String?,
        body: Data? = nil
    ) async throws -> T {
        guard let url = URL(string: baseURL + path) else { throw APIError.invalidURL }
        var req = URLRequest(url: url)
        let upper = method.uppercased()
        req.httpMethod = method
        if let token {
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        // Fastify rejects POST with Content-Type: application/json and an empty body (FST_ERR_CTP_EMPTY_JSON_BODY).
        if upper == "GET" || upper == "HEAD" {
            req.httpBody = nil
        } else {
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = body ?? Data("{}".utf8)
        }

        let (data, resp) = try await session.data(for: req)
        let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
        if code < 200 || code >= 300 {
            let msg = String(data: data, encoding: .utf8) ?? ""
            throw APIError.badStatus(code, msg)
        }
        do {
            let dec = JSONDecoder()
            return try dec.decode(T.self, from: data)
        } catch {
            throw APIError.decoding(error)
        }
    }

    func signIn(email: String, password: String) async throws -> AuthTokenResponse {
        let urlStr = AppConfig.supabaseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/")) + "/auth/v1/token?grant_type=password"
        let body = try JSONSerialization.data(withJSONObject: ["email": email, "password": password])
        return try await postSupabaseAuth(url: urlStr, body: body)
    }

    /// Native Sign in with Apple — exchange the Apple identity token for a Supabase session.
    func signInWithApple(identityToken: String, nonce: String) async throws -> AuthTokenResponse {
        let urlStr = AppConfig.supabaseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/")) + "/auth/v1/token?grant_type=id_token"
        let body = try JSONSerialization.data(withJSONObject: [
            "provider": "apple",
            "id_token": identityToken,
            "nonce": nonce,
        ])
        return try await postSupabaseAuth(url: urlStr, body: body)
    }

    /// Exchange a refresh token for a new access token + (rotated) refresh token.
    /// AppModel calls this proactively in the background so a long game never lands the
    /// user back on the sign-in screen mid-hand.
    func refreshSession(refreshToken: String) async throws -> AuthTokenResponse {
        let urlStr = AppConfig.supabaseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/")) + "/auth/v1/token?grant_type=refresh_token"
        let body = try JSONSerialization.data(withJSONObject: ["refresh_token": refreshToken])
        return try await postSupabaseAuth(url: urlStr, body: body)
    }

    private func postSupabaseAuth(url urlStr: String, body: Data) async throws -> AuthTokenResponse {
        guard let url = URL(string: urlStr) else { throw APIError.invalidURL }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(AppConfig.supabaseAnonKey, forHTTPHeaderField: "apikey")
        req.httpBody = body

        let (data, resp) = try await session.data(for: req)
        let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
        if code < 200 || code >= 300 {
            let msg = String(data: data, encoding: .utf8) ?? ""
            throw APIError.badStatus(code, msg)
        }
        return try JSONDecoder().decode(AuthTokenResponse.self, from: data)
    }

    /// Sends a password-reset email via Supabase. Always succeeds from the caller's perspective
    /// when Supabase accepts the request (the API does not reveal whether the email exists).
    func requestPasswordReset(email: String) async throws {
        let urlStr = AppConfig.supabaseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/")) + "/auth/v1/recover"
        let body = try JSONSerialization.data(withJSONObject: [
            "email": email,
            "redirect_to": AppConfig.passwordResetRedirectURL,
        ])
        guard let url = URL(string: urlStr) else { throw APIError.invalidURL }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(AppConfig.supabaseAnonKey, forHTTPHeaderField: "apikey")
        req.httpBody = body

        let (data, resp) = try await session.data(for: req)
        let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
        if code < 200 || code >= 300 {
            let msg = String(data: data, encoding: .utf8) ?? ""
            throw APIError.badStatus(code, msg)
        }
    }

    /// Sets a new password using the short-lived recovery access token from the reset email link.
    func updatePassword(newPassword: String, accessToken: String) async throws {
        let urlStr = AppConfig.supabaseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/")) + "/auth/v1/user"
        guard let url = URL(string: urlStr) else { throw APIError.invalidURL }
        var req = URLRequest(url: url)
        req.httpMethod = "PUT"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(AppConfig.supabaseAnonKey, forHTTPHeaderField: "apikey")
        req.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        req.httpBody = try JSONSerialization.data(withJSONObject: ["password": newPassword])

        let (data, resp) = try await session.data(for: req)
        let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
        if code < 200 || code >= 300 {
            let msg = String(data: data, encoding: .utf8) ?? ""
            throw APIError.badStatus(code, msg)
        }
    }

    /// Returns the session when the Supabase project has email confirmation OFF (the response
    /// includes `access_token` immediately). When confirmation is ON, returns nil — the caller
    /// should ask the user to verify their email, then sign in.
    func signUp(email: String, password: String) async throws -> AuthTokenResponse? {
        let urlStr = AppConfig.supabaseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/")) + "/auth/v1/signup"
        guard let url = URL(string: urlStr) else { throw APIError.invalidURL }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(AppConfig.supabaseAnonKey, forHTTPHeaderField: "apikey")
        let body = try JSONSerialization.data(withJSONObject: ["email": email, "password": password])
        req.httpBody = body

        let (data, resp) = try await session.data(for: req)
        let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
        if code < 200 || code >= 300 {
            let msg = String(data: data, encoding: .utf8) ?? ""
            throw APIError.badStatus(code, msg)
        }
        if let tok = try? JSONDecoder().decode(AuthTokenResponse.self, from: data),
           !tok.access_token.isEmpty {
            return tok
        }
        return nil
    }

    func lobbyInvitePreview(inviteCode: String) async throws -> LobbyInvitePreviewResponse {
        let code = inviteCode.uppercased()
        return try await request(path: "/lobbies/\(code)/preview", method: "GET", token: nil)
    }

    func createLobby(token: String) async throws -> LobbyCreateResponse {
        let body = Data("{}".utf8)
        return try await request(path: "/lobbies", method: "POST", token: token, body: body)
    }

    func joinLobby(code: String, token: String) async throws {
        struct JoinResponse: Codable {
            let ok: Bool?
            let seat: Int?
        }
        let body = Data("{}".utf8)
        let _: JoinResponse = try await request(path: "/lobbies/\(code)/join", method: "POST", token: token, body: body)
    }

    /// Polled by both players while sitting in the waiting room; returns the latest player roster,
    /// per-seat ready flags, and a non-null `gameId` once both players have readied up.
    func lobbyStatus(code: String, token: String) async throws -> LobbyStatusResponse {
        try await request(path: "/lobbies/\(code)", method: "GET", token: token)
    }

    /// Leave a not-yet-started lobby from the waiting room. Host leaving closes the
    /// lobby; a guest leaving frees seat 1. Best-effort and idempotent on the server.
    func leaveLobby(code: String, token: String) async throws {
        struct LeaveResponse: Codable {
            let ok: Bool?
            let status: String?
        }
        let body = Data("{}".utf8)
        let _: LeaveResponse = try await request(path: "/lobbies/\(code)/leave", method: "POST", token: token, body: body)
    }

    /// Flip the caller's ready flag in the lobby waiting room. When both seats are
    /// ready the server auto-creates the game; the returned payload will then carry
    /// a non-null `gameId`, so a single round-trip can drop you straight onto the table.
    func setLobbyReady(code: String, token: String, ready: Bool) async throws -> LobbyStatusResponse {
        let body = try JSONSerialization.data(withJSONObject: ["ready": ready])
        return try await request(path: "/lobbies/\(code)/ready", method: "POST", token: token, body: body)
    }

    func startGame(code: String, token: String, testBot: Bool = false) async throws -> GameStartResponse {
        let payload: [String: Bool] = testBot ? ["bot": true] : [:]
        let body = try JSONSerialization.data(withJSONObject: payload)
        return try await request(path: "/lobbies/\(code)/start", method: "POST", token: token, body: body)
    }

    func gameState(gameId: String, token: String) async throws -> GameStateResponse {
        try await request(path: "/games/\(gameId)/state", method: "GET", token: token)
    }

    /// Chronological list of every match in the lobby sitting (scores, match tiers, winners).
    func sessionRecap(inviteCode: String, token: String) async throws -> SessionRecapResponse {
        let code = inviteCode.uppercased()
        return try await request(path: "/lobbies/\(code)/session", method: "GET", token: token)
    }

    /// Same payload as `sessionRecap`, keyed from the active game id.
    func sessionRecapForGame(gameId: String, token: String) async throws -> SessionRecapResponse {
        try await request(path: "/games/\(gameId)/session", method: "GET", token: token)
    }

    /// Leave (forfeit) an active game before it concludes. Idempotent on the server,
    /// so retries are safe.
    func leaveGame(gameId: String, token: String) async throws -> GameLeaveResponse {
        try await request(path: "/games/\(gameId)/leave", method: "POST", token: token)
    }

    func submitMove(gameId: String, token: String, intent: [String: Any]) async throws -> MoveResponse {
        let body = try JSONSerialization.data(withJSONObject: ["intent": intent])
        return try await request(path: "/games/\(gameId)/move", method: "POST", token: token, body: body)
    }

    func fetchGameChat(gameId: String, token: String, after: String?) async throws -> GameChatListResponse {
        guard var comp = URLComponents(string: "\(baseURL)/games/\(gameId)/chat") else { throw APIError.invalidURL }
        if let after {
            comp.queryItems = [URLQueryItem(name: "after", value: after)]
        }
        guard let url = comp.url else { throw APIError.invalidURL }
        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let (data, resp) = try await session.data(for: req)
        let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
        if code < 200 || code >= 300 {
            let msg = String(data: data, encoding: .utf8) ?? ""
            throw APIError.badStatus(code, msg)
        }
        do {
            return try JSONDecoder().decode(GameChatListResponse.self, from: data)
        } catch {
            throw APIError.decoding(error)
        }
    }

    func sendGameChat(gameId: String, token: String, text: String) async throws -> GameChatPostResponse {
        let body = try JSONSerialization.data(withJSONObject: ["text": text])
        return try await request(path: "/games/\(gameId)/chat", method: "POST", token: token, body: body)
    }

    func reportChatMessage(
        gameId: String,
        messageId: String,
        token: String,
        reason: String?
    ) async throws -> ChatReportResponse {
        var payload: [String: Any] = [:]
        if let reason, !reason.isEmpty {
            payload["reason"] = reason
        }
        let body = try JSONSerialization.data(withJSONObject: payload)
        return try await request(
            path: "/games/\(gameId)/chat/\(messageId)/report",
            method: "POST",
            token: token,
            body: body
        )
    }

    func fetchBlockedUsers(token: String) async throws -> BlockedUsersResponse {
        try await request(path: "/users/blocked", method: "GET", token: token)
    }

    func blockUser(userId: String, token: String) async throws {
        let _: OkResponse = try await request(path: "/users/\(userId)/block", method: "POST", token: token)
    }

    func unblockUser(userId: String, token: String) async throws {
        let _: OkResponse = try await request(path: "/users/\(userId)/block", method: "DELETE", token: token)
    }

    /// Permanently delete the signed-in user's account and all server-side data.
    func deleteAccount(token: String) async throws {
        struct DeleteResponse: Codable {
            let ok: Bool?
        }
        let _: DeleteResponse = try await request(path: "/account/delete", method: "POST", token: token)
    }

    func fetchAccountProfile(token: String) async throws -> AccountProfileResponse {
        try await request(path: "/account/profile", method: "GET", token: token)
    }

    /// Finished matches for the signed-in player (opponent, result, score, tier, hands).
    func fetchAccountGames(token: String) async throws -> AccountGameLogResponse {
        try await request(path: "/account/games", method: "GET", token: token)
    }

    func updateDisplayName(_ displayName: String, token: String) async throws -> DisplayNameUpdateResponse {
        let body = try JSONSerialization.data(withJSONObject: ["display_name": displayName])
        return try await request(path: "/account/display-name", method: "PATCH", token: token, body: body)
    }
}
