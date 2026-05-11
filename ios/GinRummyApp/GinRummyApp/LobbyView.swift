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
                    case .joinEnter:
                        JoinLobbyEnterCodeView(path: $path)
                            .environmentObject(app)
                    case let .hostWait(code):
                        HostWaitingRoomView(inviteCode: code)
                            .environmentObject(app)
                    case let .joinWait(code):
                        JoinWaitingForHostView(joinCode: code)
                            .environmentObject(app)
                    }
                }
        }
        .onChange(of: app.lobbyInviteJoinHandoffNonce) {
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

    /// After accepting an invite sheet, navigate to waiting-for-host and poll like a normal join.
    private func applyLobbyInviteJoinHandoffIfNeeded() {
        guard let code = app.consumeLobbyInviteJoinHandoff() else { return }
        path = NavigationPath()
        toast = ""
        path.append(LobbyRoute.joinWait(code))
    }

    private func createLobbyAndWait() async {
        guard let token = app.accessToken else { return }
        busy = true
        toast = ""
        defer { busy = false }
        do {
            let res = try await app.api.createLobby(token: token)
            let code = res.lobby.invite_code
            path.append(LobbyRoute.hostWait(code))
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
                app.lastPerspective = started.perspective
            }
        } catch {
            toast = UserFeedback.from(error)
            toastIsError = true
        }
    }
}
