import SwiftUI

struct LobbyView: View {
    @EnvironmentObject private var app: AppModel
    @State private var inviteCode = ""
    @State private var joinCode = ""
    @State private var testBotSolo = false
    @State private var busy = false
    @State private var message = ""
    @State private var messageIsError = true
    @State private var waitingForHostCode: String? = nil
    @State private var lobbyPollTask: Task<Void, Never>? = nil

    var body: some View {
        List {
            Section("Host") {
                Button(busy ? "Creating…" : "Create lobby") {
                    Task { await create() }
                }
                .disabled(busy || app.accessToken == nil)

                if !inviteCode.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Invite code: \(inviteCode)")
                            .font(.headline)
                        ShareLink(item: shareURL()) {
                            Label("Share invite link", systemImage: "square.and.arrow.up")
                        }
                        Text("Custom scheme: \(customSchemeURL())")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Section("Join") {
                TextField("Invite code", text: $joinCode)
                    .textInputAutocapitalization(.characters)
                Button(busy ? "Joining…" : "Join lobby") {
                    Task { await join() }
                }
                .disabled(busy || app.accessToken == nil || joinCode.count < 4)
            }

            Section("Start (host)") {
                Toggle("Solo: play vs test bot (auto draw/discard)", isOn: $testBotSolo)
                Text("No second player or join required. The bot is seat 1, passes on upcard, then draws and discards the card it picked.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button(busy ? "Starting…" : (testBotSolo ? "Start vs test bot" : "Start game")) {
                    Task { await start() }
                }
                .disabled(busy || app.accessToken == nil || inviteCode.isEmpty)
            }

            if !message.isEmpty {
                Section {
                    FeedbackLine(text: message, isError: messageIsError)
                }
            }
        }
        .navigationTitle("Lobby")
        .onAppear {
            if let p = app.consumePendingJoin() {
                joinCode = p
            }
        }
        .onDisappear {
            lobbyPollTask?.cancel()
            lobbyPollTask = nil
        }
    }

    private func shareURL() -> URL {
        let base = AppConfig.inviteWebBaseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        return URL(string: "\(base)/join/\(inviteCode)")!
    }

    private func customSchemeURL() -> String {
        "ginrummy://join/\(inviteCode)"
    }

    private func create() async {
        guard let token = app.accessToken else { return }
        busy = true
        message = ""
        messageIsError = true
        defer { busy = false }
        do {
            let res = try await app.api.createLobby(token: token)
            inviteCode = res.lobby.invite_code
            message = "Lobby created. Share the code or link to invite."
            messageIsError = false
        } catch {
            message = UserFeedback.from(error)
            messageIsError = true
        }
    }

    private func join() async {
        guard let token = app.accessToken else { return }
        busy = true
        message = ""
        messageIsError = true
        defer { busy = false }
        do {
            let code = joinCode.uppercased()
            try await app.api.joinLobby(code: code, token: token)
            message = "Joined lobby \(code). Waiting for host to start the game…"
            messageIsError = false
            startWaitingForHost(code: code)
        } catch {
            message = UserFeedback.from(error)
            messageIsError = true
        }
    }

    /// After a successful join, poll the lobby until the host starts; then fetch the
    /// initial perspective and transition to the game table via `app.activeGameId`.
    private func startWaitingForHost(code: String) {
        guard app.accessToken != nil else { return }
        lobbyPollTask?.cancel()
        waitingForHostCode = code
        lobbyPollTask = Task { @MainActor in
            while !Task.isCancelled, app.activeGameId == nil, waitingForHostCode == code {
                /* Re-read the access token each iteration so a background refresh propagates here. */
                guard let token = app.accessToken else {
                    try? await Task.sleep(nanoseconds: 2_000_000_000)
                    continue
                }
                do {
                    let s = try await app.api.lobbyStatus(code: code, token: token)
                    if let gid = s.gameId, s.lobby.status == "in_game" || s.lobby.status == "closed" {
                        let st = try await app.api.gameState(gameId: gid, token: token)
                        app.lastPerspective = st.perspective
                        app.lastBetting = st.betting
                        app.activeGameId = gid
                        waitingForHostCode = nil
                        message = "Game started. Going to the table…"
                        messageIsError = false
                        return
                    }
                } catch {
                    /* Transient errors during polling are non-fatal; just keep retrying. */
                }
                try? await Task.sleep(nanoseconds: 2_000_000_000)
            }
        }
    }

    private func start() async {
        guard let token = app.accessToken else { return }
        busy = true
        message = ""
        messageIsError = true
        defer { busy = false }
        do {
            let res = try await app.api.startGame(
                code: inviteCode.uppercased(),
                token: token,
                testBot: testBotSolo
            )
            app.activeGameId = res.gameId
            app.lastPerspective = res.perspective
            message = testBotSolo ? "Game started vs test bot. Going to the table…" : "Game started. Going to the table…"
            messageIsError = false
        } catch {
            message = UserFeedback.from(error)
            messageIsError = true
        }
    }
}
