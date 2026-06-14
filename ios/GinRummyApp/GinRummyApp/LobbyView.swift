import SwiftUI

struct LobbyView: View {
    @EnvironmentObject private var app: AppModel
    @State private var path = NavigationPath()
    @State private var busy = false
    @State private var toast = ""
    @State private var toastIsError = false

    var body: some View {
        NavigationStack(path: $path) {
            homeScreen
                .navigationTitle("Lobby")
                .navigationBarTitleDisplayMode(.inline)
                .navigationDestination(for: LobbyRoute.self) { route in
                    switch route {
                    case .instructions:
                        InstructionsView()
                    case .manualScore:
                        ManualScorecardView()
                    case .joinEnter:
                        JoinLobbyEnterCodeView(path: $path)
                            .environmentObject(app)
                    case let .wait(code, isHost):
                        LobbyWaitingRoomView(inviteCode: code, isHost: isHost)
                            .environmentObject(app)
                    }
                }
        }
        .onChange(of: app.lobbyInviteJoinHandoffNonce) {
            applyLobbyInviteJoinHandoffIfNeeded()
        }
        .onAppear {
            /* Handoff can be staged before LobbyView mounts (accepting an invite
             * mid-game tears down the table first), so onChange alone would miss it. */
            applyLobbyInviteJoinHandoffIfNeeded()
        }
    }

    private var homeScreen: some View {
        ScrollView {
            VStack(spacing: 32) {
                GinRummyLogoBlock()
                    .padding(.top, 12)

                if !toast.isEmpty {
                    FeedbackLine(text: toast, isError: toastIsError, privateClubStyle: true)
                        .padding(.horizontal, 8)
                }

                VStack(spacing: 14) {
                    Button(busy ? "Creating…" : "Create lobby") {
                        Task { await createLobbyAndWait() }
                    }
                    .buttonStyle(GinPrimaryButtonStyle())
                    .disabled(busy || app.accessToken == nil)

                    Button("Join lobby") {
                        path.append(LobbyRoute.joinEnter)
                    }
                    .buttonStyle(GinGhostButtonStyle())
                    .disabled(busy || app.accessToken == nil)

                    Button(busy ? "Starting…" : "Play bot") {
                        Task { await playAgainstBot() }
                    }
                    .buttonStyle(GinGhostButtonStyle())
                    .disabled(busy || app.accessToken == nil)

                    Button("Score a game") {
                        path.append(LobbyRoute.manualScore)
                    }
                    .buttonStyle(GinGhostButtonStyle())

                    Button("How to play") {
                        path.append(LobbyRoute.instructions)
                    }
                    .buttonStyle(GinGhostButtonStyle())

                    Button("Sign out", role: .destructive) {
                        app.signOut()
                    }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(GinRummyPalette.sage)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 8)
                }
                .padding(.horizontal, 28)

                Spacer(minLength: 24)
            }
        }
    }

    /// After accepting an invite sheet, drop into the unified waiting room so the
    /// guest can see the host's name and ready up.
    private func applyLobbyInviteJoinHandoffIfNeeded() {
        guard let code = app.consumeLobbyInviteJoinHandoff() else { return }
        path = NavigationPath()
        toast = ""
        path.append(LobbyRoute.wait(code: code, isHost: false))
    }

    private func createLobbyAndWait() async {
        guard let token = app.accessToken else { return }
        busy = true
        toast = ""
        defer { busy = false }
        do {
            let res = try await app.api.createLobby(token: token)
            let code = res.lobby.invite_code
            path.append(LobbyRoute.wait(code: code, isHost: true))
        } catch {
            toast = UserFeedback.from(error)
            toastIsError = true
        }
    }

    /// Create a fresh lobby and start instantly against the test bot (host-only seat).
    private func playAgainstBot() async {
        guard let token = app.accessToken else { return }
        busy = true
        toast = ""
        defer { busy = false }
        do {
            let res = try await app.api.createLobby(token: token)
            let code = res.lobby.invite_code.uppercased()
            let started = try await app.api.startGame(code: code, token: token, testBot: true)
            await MainActor.run {
                app.activeGameId = started.gameId
                app.applyGameTableState(
                    perspective: started.perspective,
                    betting: nil,
                    opponentDisplayName: started.opponentDisplayName
                )
            }
        } catch {
            toast = UserFeedback.from(error)
            toastIsError = true
        }
    }
}
