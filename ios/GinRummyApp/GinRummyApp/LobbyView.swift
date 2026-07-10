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
                .navigationTitle("")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar(.hidden, for: .navigationBar)
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
                    case .profile:
                        ProfileView()
                            .environmentObject(app)
                    case .account:
                        AccountSettingsView()
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

    // MARK: - Home

    private var homeScreen: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 44)

            GinRummyLogoBlock()

            if !toast.isEmpty {
                FeedbackLine(text: toast, isError: toastIsError, privateClubStyle: true)
                    .padding(.horizontal, 24)
                    .padding(.top, 20)
            }

            Spacer(minLength: 34)

            VStack(alignment: .leading, spacing: 12) {
                sectionLabel("Play a match")

                Button(busy ? "Creating…" : "Create a table") {
                    Task { await createLobbyAndWait() }
                }
                .buttonStyle(GinPrimaryButtonStyle())
                .disabled(busy || app.accessToken == nil)

                HStack(spacing: 12) {
                    Button("Join with code") {
                        path.append(LobbyRoute.joinEnter)
                    }
                    .buttonStyle(GinGhostButtonStyle())
                    .disabled(busy || app.accessToken == nil)

                    Button(busy ? "Starting…" : "Play bot") {
                        Task { await playAgainstBot() }
                    }
                    .buttonStyle(GinGhostButtonStyle())
                    .disabled(busy || app.accessToken == nil)
                }
            }
            .padding(.horizontal, 24)

            Spacer(minLength: 24)

            VStack(alignment: .leading, spacing: 12) {
                sectionLabel("Keeping score in person")

                Button {
                    path.append(LobbyRoute.manualScore)
                } label: {
                    scoreByHandCard
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 24)

            Spacer(minLength: 32)

            HStack(spacing: 12) {
                homeTile(title: "How to play", systemImage: "questionmark.circle") {
                    path.append(LobbyRoute.instructions)
                }
                homeTile(title: "Profile", systemImage: "person.crop.circle") {
                    path.append(LobbyRoute.profile)
                }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 42)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.caption2.weight(.bold))
            .tracking(2)
            .foregroundStyle(GinRummyPalette.sage)
    }

    private var scoreByHandCard: some View {
        HStack(spacing: 15) {
            miniScoreSheet
            VStack(alignment: .leading, spacing: 3) {
                Text("Score a game by hand")
                    .font(.headline)
                    .foregroundStyle(GinRummyPalette.cream)
                Text("Keep the sheet for an in-person match")
                    .font(.caption)
                    .foregroundStyle(GinRummyPalette.sage)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(GinRummyPalette.goldAccentSoft)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(red: 0.031, green: 0.051, blue: 0.039))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(GinRummyPalette.goldAccent.opacity(0.3), lineWidth: 1)
        )
    }

    private var miniScoreSheet: some View {
        VStack(spacing: 0) {
            miniScoreRow(left: "25", right: "")
            miniScoreRow(left: "", right: "19")
            miniScoreRow(left: "18", right: "")
        }
        .padding(5)
        .frame(width: 46, height: 58)
        .background(RoundedRectangle(cornerRadius: 6).fill(Color.black.opacity(0.55)))
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(GinRummyPalette.cream.opacity(0.32), lineWidth: 1))
    }

    private func miniScoreRow(left: String, right: String) -> some View {
        HStack(spacing: 0) {
            Text(left)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .foregroundStyle(GinRummyPalette.goldAccentSoft)
            Rectangle()
                .fill(GinRummyPalette.cream.opacity(0.22))
                .frame(width: 1)
            Text(right)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .foregroundStyle(Color(red: 0.86, green: 0.4, blue: 0.36))
        }
        .font(.system(size: 9, weight: .bold, design: .rounded))
        .overlay(
            Rectangle()
                .fill(GinRummyPalette.cream.opacity(0.16))
                .frame(height: 1),
            alignment: .bottom
        )
    }

    private func homeTile(title: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: systemImage)
                    .foregroundStyle(GinRummyPalette.goldAccentSoft)
                Text(title)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(GinRummyPalette.cream)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(GinRummyPalette.cream.opacity(0.14), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Navigation + networking

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
