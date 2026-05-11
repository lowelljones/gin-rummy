import SwiftUI
import UIKit

enum LobbyRoute: Hashable {
    case joinEnter
    case hostWait(String)
    case joinWait(String)
    case instructions
}

struct InstructionsView: View {
    private var mutedInstructions: Color { GinRummyPalette.sage.opacity(0.92) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("Objective")
                    .font(.headline)
                    .foregroundStyle(GinRummyPalette.gold)
                ruleParagraph(
                    "Form melds (sets or runs). Reduce deadwood toward zero. Win the hand going gin (no deadwood) or by knocking."
                )

                Text("Deal & turn")
                    .font(.headline)
                    .foregroundStyle(GinRummyPalette.gold)
                ruleParagraph(
                    "Each player is dealt 10 cards. The remainder is stock; one card turns up as the discard. On your turn, draw from stock or accept the discard, then discard to end your turn unless you gin or knock with a legal layout."
                )

                Text("Down card phase")
                    .font(.headline)
                    .foregroundStyle(GinRummyPalette.gold)
                ruleParagraph(
                    "The non-dealer may take or pass the first up-card, then the dealer may take or pass. If both pass, the non-dealer leads from stock."
                )

                Text("Gin · Knock · Big gin")
                    .font(.headline)
                    .foregroundStyle(GinRummyPalette.gold)
                ruleParagraph(
                    "Declare gin when discarding lets you arrange all melds plus zero deadwood. Knock when your deadwood is at or below the value of the first up-card (Ace turns off knocking for that hand)."
                )

                Text("Match")
                    .font(.headline)
                    .foregroundStyle(GinRummyPalette.gold)
                ruleParagraph(
                    "Hands award points toward a race score. Reach the race target before your opponent wins the match."
                )
            }
            .foregroundStyle(GinRummyPalette.cream)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(20)
            .padding(.bottom, 32)
        }
        .navigationTitle("How to play")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func ruleParagraph(_ text: String) -> some View {
        Text(text)
            .font(.subheadline)
            .foregroundStyle(mutedInstructions)
            .fixedSize(horizontal: false, vertical: true)
    }
}

struct JoinLobbyEnterCodeView: View {
    @EnvironmentObject private var app: AppModel
    @Binding var path: NavigationPath

    @State private var joinCode = ""
    @State private var busy = false
    @State private var message = ""
    @State private var messageIsError = true

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                Text("Enter your host’s lobby code.")
                    .font(.subheadline)
                    .foregroundStyle(GinRummyPalette.gold.opacity(0.85))
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)

                TextField("", text: $joinCode)
                    .textInputAutocapitalization(.characters)
                    .font(.title3.bold().monospaced())
                    .multilineTextAlignment(.center)
                    .ginOutlinedField()

                Button(busy ? "Joining…" : "Join lobby") {
                    Task { await join() }
                }
                .buttonStyle(GinPrimaryButtonStyle())
                .disabled(busy || app.accessToken == nil || joinCode.count < 4)

                if !message.isEmpty {
                    FeedbackLine(text: message, isError: messageIsError, privateClubStyle: true)
                }

                inviteHint
            }
            .padding(.horizontal, 24)
            .padding(.top, 28)
        }
        .navigationTitle("Join lobby")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") { resignFirstResponder() }
            }
        }
    }

    private func resignFirstResponder() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }

    private var inviteHint: some View {
        Group {
            if AppConfig.usesInviteCustomURLScheme {
                Text("Links look like ginrummy://join/… — tap one on your phone to open the app.")
                    .font(.caption)
                    .foregroundStyle(GinRummyPalette.sage.opacity(0.85))
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text("Hosts can share HTTPS links once Universal Links are configured.")
                    .font(.caption)
                    .foregroundStyle(GinRummyPalette.sage.opacity(0.85))
            }
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
            messageIsError = false
            message = "Joined \(code)."
            path.append(LobbyRoute.joinWait(code))
        } catch {
            message = UserFeedback.from(error)
            messageIsError = true
        }
    }
}

struct JoinWaitingForHostView: View {
    @EnvironmentObject private var app: AppModel
    let joinCode: String

    @State private var lobbyPollTask: Task<Void, Never>?
    @State private var message = "Waiting for the host to start the game."

    private var muted: Color { GinRummyPalette.cream.opacity(0.76) }

    var body: some View {
        VStack(spacing: 28) {
            ProgressView()
                .scaleEffect(1.2)
                .tint(GinRummyPalette.gold)

            Text("Lobby \(joinCode)")
                .font(.title3.bold().monospaced())
                .foregroundStyle(GinRummyPalette.gold)

            Text("When the host starts, you’ll go to the table automatically.")
                .font(.subheadline)
                .foregroundStyle(muted)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            FeedbackLine(text: message, isError: false, privateClubStyle: true)

            Spacer()
        }
        .padding(24)
        .navigationTitle("Waiting")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { startPolling() }
        .onDisappear {
            lobbyPollTask?.cancel()
            lobbyPollTask = nil
        }
    }

    private func startPolling() {
        let code = joinCode.uppercased()
        lobbyPollTask?.cancel()
        lobbyPollTask = Task { @MainActor in
            while !Task.isCancelled, app.activeGameId == nil {
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
                        message = "Game starting…"
                        return
                    }
                } catch {}
                try? await Task.sleep(nanoseconds: 2_000_000_000)
            }
        }
    }
}

struct HostWaitingRoomView: View {
    @EnvironmentObject private var app: AppModel
    let inviteCode: String

    private var panelFill: Color { GinRummyPalette.bgPanel.opacity(0.72) }

    private var shareLinkMuted: Color { GinRummyPalette.gold.opacity(0.92) }

    private var hintColor: Color { GinRummyPalette.sage.opacity(0.82) }

    @State private var guestJoined = false
    @State private var startBusy = false
    @State private var pollTask: Task<Void, Never>?
    @State private var feedback = ""
    @State private var feedbackIsError = true

    var body: some View {
        ScrollView {
            VStack(spacing: 28) {
                if !guestJoined {
                    ProgressView()
                        .scaleEffect(1.2)
                        .tint(GinRummyPalette.gold)
                    Text("Waiting on another player")
                        .font(.headline)
                        .foregroundStyle(GinRummyPalette.gold)

                    Text("Share the invite code or copy the link so your friend can join.")
                        .font(.subheadline)
                        .foregroundStyle(GinRummyPalette.cream.opacity(0.76))
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    Image(systemName: "person.2.fill")
                        .font(.system(size: 36))
                        .foregroundStyle(GinRummyPalette.sage.opacity(1.06))
                        .padding(.bottom, 4)
                    Text("Guest joined · start when you're ready.")
                        .font(.headline)
                        .foregroundStyle(GinRummyPalette.gold)
                        .multilineTextAlignment(.center)

                    Button(startBusy ? "Starting…" : "Start game") {
                        Task { await startVsHuman() }
                    }
                    .buttonStyle(GinPrimaryButtonStyle())
                    .disabled(startBusy || app.accessToken == nil)
                }

                sharePanel

                if !feedback.isEmpty {
                    FeedbackLine(text: feedback, isError: feedbackIsError, privateClubStyle: true)
                }
            }
            .padding(24)
        }
        .navigationTitle("Lobby")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            startGuestPolling()
        }
        .onDisappear {
            pollTask?.cancel()
            pollTask = nil
        }
    }

    private var sharePanel: some View {
        VStack(spacing: 12) {
            Text(inviteCode.uppercased())
                .font(.system(size: 32, weight: .bold, design: .rounded))
                .monospaced()
                .foregroundStyle(GinRummyPalette.gold)

            HStack(spacing: 12) {
                ShareLink(item: inviteShareLinkURL()) {
                    Label("Share link", systemImage: "square.and.arrow.up")
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(shareLinkMuted)

                Button("Copy link") {
                    UIPasteboard.general.string = inviteShareLinkURL().absoluteString
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(GinRummyPalette.cream.opacity(0.85))

                Button("Copy code") {
                    UIPasteboard.general.string = inviteCode.uppercased()
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(GinRummyPalette.cream.opacity(0.85))
            }

            Text(inviteShareLinkHint())
                .font(.caption2)
                .foregroundStyle(hintColor)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(18)
        .frame(maxWidth: .infinity)
        .background(panelFill)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .ginGoldBorder(cornerRadius: 14)
    }

    private func inviteShareLinkURL() -> URL {
        AppConfig.inviteShareURL(forInviteCode: inviteCode)
    }

    private func inviteShareLinkHint() -> String {
        if AppConfig.usesInviteCustomURLScheme {
            return "Invite links open this app directly (ginrummy://join/…)."
        }
        return "Hosted invite links open the app when Universal Links are configured."
    }

    private func startGuestPolling() {
        let code = inviteCode.uppercased()
        pollTask?.cancel()
        pollTask = Task { @MainActor in
            while !Task.isCancelled, !guestJoined {
                guard let token = app.accessToken else {
                    try? await Task.sleep(nanoseconds: 2_000_000_000)
                    continue
                }
                do {
                    let s = try await app.api.lobbyStatus(code: code, token: token)
                    if s.guestJoined {
                        guestJoined = true
                        return
                    }
                } catch {}
                try? await Task.sleep(nanoseconds: 2_000_000_000)
            }
        }
    }

    private func startVsHuman() async {
        guard let token = app.accessToken else { return }
        startBusy = true
        feedback = ""
        defer { startBusy = false }
        do {
            let res = try await app.api.startGame(code: inviteCode.uppercased(), token: token, testBot: false)
            app.activeGameId = res.gameId
            app.lastPerspective = res.perspective
            app.lastBetting = nil
        } catch {
            feedback = UserFeedback.from(error)
            feedbackIsError = true
        }
    }
}
