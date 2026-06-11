import SwiftUI
import UIKit

enum LobbyRoute: Hashable {
    case joinEnter
    /// Unified waiting room used by both the host and the joiner. The host gets the
    /// share panel because they own the invite code; both sides see player cards
    /// with display name + ready badge and a Ready Up button that auto-starts the
    /// game once both seats are ready.
    ///
    /// `isHost` is carried in the route so the waiting room can render the share
    /// panel and the "You" badge on the correct seat **before** the first
    /// `/lobbies/:code` poll lands (or in the worst case, before the backend has
    /// been redeployed with the player-roster fields). Without this, a freshly
    /// arrived host saw an empty card on seat 0 and no share/copy controls until
    /// polling caught up — and a guest never saw whose lobby they were in.
    case wait(code: String, isHost: Bool)
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
                    "Form melds (sets or runs). Reduce deadwood toward zero. Win the hand going gin (25 plus opponent’s unmelded count), EO (50 plus opponent’s unmelded), or by knocking after your unmelded total exactly matches the first up-card (face cards 10, ace 1)."
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

                Text("Gin · Knock · EO")
                    .font(.headline)
                    .foregroundStyle(GinRummyPalette.gold)
                ruleParagraph(
                    "Declare gin when discarding lets you arrange all melds plus zero deadwood. Knock when, after that discard, your unmelded points exactly equal the first up-card’s value. If that card is any ace, no one may knock for that hand — house rule, even if you have 1 deadwood."
                )

                Text("Match")
                    .font(.headline)
                    .foregroundStyle(GinRummyPalette.gold)
                ruleParagraph(
                    "Hands score toward a race: first player to reach 125 or more wins the match. After a hand, the prior hand’s winner deals."
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
            path.append(LobbyRoute.wait(code: code, isHost: false))
        } catch {
            message = UserFeedback.from(error)
            messageIsError = true
        }
    }
}

/// Unified lobby waiting room used by both the host and the joiner.
///
/// Behavior:
///   - Polls `/lobbies/:code` every 2s while we're waiting; when the response
///     comes back with a non-null `gameId` (i.e. both players have readied up
///     and the server has created the game), we fetch game state and flip
///     `app.activeGameId` so RootView swaps to the game table.
///   - Renders a player card per seat. Empty seat 1 shows "Waiting for player…".
///     Each filled seat shows the display name + "Ready" / "Not ready" badge.
///   - Shows the share panel (code + share/copy buttons) for the host so they
///     can hand off the invite. The guest already has the code and just sees
///     the lobby header.
///   - Bottom button toggles the caller's ready flag. Once both seats are
///     ready, the server-side handler atomically transitions the lobby to
///     in_game and creates the game; the optimistic response from this same
///     call includes the gameId, so the player who tapped Ready last lands
///     on the table immediately.
struct LobbyWaitingRoomView: View {
    @EnvironmentObject private var app: AppModel
    let inviteCode: String
    /// Carried in from `LobbyRoute.wait` so we can render the share panel and the
    /// "You" badge on the right seat immediately, without waiting for the first
    /// `/lobbies/:code` poll to land. The polled `players` array (when present)
    /// is the source of truth for the *opponent's* display name and the per-seat
    /// ready flags; the role itself never needs to come from the server.
    let isHost: Bool

    @State private var status: LobbyStatusResponse?
    @State private var pollTask: Task<Void, Never>?
    @State private var readyBusy = false
    @State private var feedback = ""
    @State private var feedbackIsError = true
    /// Optimistic "I tapped Ready and the call succeeded locally" flag. Used so
    /// the UI flips to "Ready" immediately instead of waiting for the next poll
    /// (which can be up to 2s away). Reset whenever a server payload arrives
    /// that disagrees with us.
    @State private var localReady = false
    /// Cached host display name fetched via `/lobbies/:code/preview`. Guests use
    /// this to render seat 0 with the host's name even before the new backend's
    /// `players` array is available (and on the very first frame after joining).
    @State private var previewHostName: String?
    /// Shown discreetly when polling repeatedly fails so the user understands
    /// why the roster isn't updating instead of staring at a placeholder card.
    @State private var pollErrorHint: String?
    /// Transient "Link copied" / "Code copied" feedback next to the copy buttons.
    @State private var copyConfirmation = ""
    @State private var copyConfirmationTask: Task<Void, Never>?

    private var normalizedCode: String { inviteCode.uppercased() }

    private var panelFill: Color { GinRummyPalette.bgPanel.opacity(0.72) }
    private var shareLinkMuted: Color { GinRummyPalette.gold.opacity(0.92) }
    private var hintColor: Color { GinRummyPalette.sage.opacity(0.82) }
    private var mutedCream: Color { GinRummyPalette.cream.opacity(0.76) }

    private var seat0Player: LobbyPlayerDTO? {
        status?.players.first { $0.seat == 0 }
    }

    private var seat1Player: LobbyPlayerDTO? {
        status?.players.first { $0.seat == 1 }
    }

    private var youPlayer: LobbyPlayerDTO? {
        status?.players.first { $0.isSelf }
    }

    /// True when the guest has actually claimed seat 1. Prefers the polled
    /// player list (so we know their *name*), but falls back to the legacy
    /// `guest_joined` flag — that way the host's UI still flips to "Guest
    /// joined" even on a deployed backend that hasn't shipped the new
    /// `players` array yet.
    private var guestPresent: Bool {
        if seat1Player != nil { return true }
        if !isHost { return true } // I am the guest; seat 1 is occupied by me.
        return status?.guestJoined == true
    }

    private var iAmReady: Bool {
        if let me = youPlayer { return me.ready }
        return localReady
    }

    private var canToggleReady: Bool {
        guard guestPresent else { return false }
        // Treat unknown status as "still loading, don't gate" so the button
        // isn't permanently disabled when the poll is slow or has only ever
        // returned the legacy payload. The server is the final arbiter.
        let s = status?.lobby.status ?? "open"
        return s == "open"
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 22) {
                lobbyHeader

                playerRoster

                if isHost {
                    sharePanel
                }

                readyButton

                if !guestPresent {
                    Text("Ready up is available once the other player joins.")
                        .font(.caption)
                        .foregroundStyle(hintColor)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 8)
                }

                if let hint = pollErrorHint {
                    FeedbackLine(text: hint, isError: true, privateClubStyle: true)
                }

                if let startError = status?.startError, !startError.isEmpty {
                    // Surfaced when the server tried to flip the lobby to in_game
                    // but the games-row insert was rejected (DB constraint, missing
                    // column, etc.). Without this the player would just stare at
                    // "Both players ready — starting…" forever while the GET poll
                    // self-heal retries silently.
                    FeedbackLine(
                        text: "Couldn't start the game: \(startError)",
                        isError: true,
                        privateClubStyle: true
                    )
                }

                if !feedback.isEmpty {
                    FeedbackLine(text: feedback, isError: feedbackIsError, privateClubStyle: true)
                }
            }
            .padding(24)
            .animation(.easeInOut(duration: 0.22), value: status?.players)
            .animation(.easeInOut(duration: 0.22), value: status?.gameId)
        }
        .navigationTitle("Lobby")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            startPolling()
            if !isHost { Task { await loadHostPreviewIfNeeded() } }
        }
        .onDisappear {
            pollTask?.cancel()
            pollTask = nil
        }
        .onChange(of: guestPresent) { _, joined in
            if joined { notify(.light) }
        }
        .onChange(of: opponent?.ready ?? false) { _, ready in
            if ready { notify(.medium) }
        }
        .onChange(of: status?.gameId) { _, gid in
            if gid != nil { notify(.success) }
        }
    }

    private enum Haptic { case light, medium, success }

    private func notify(_ kind: Haptic) {
        switch kind {
        case .light:
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        case .medium:
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        case .success:
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        }
    }

    // MARK: - Header / roster

    private var lobbyHeader: some View {
        VStack(spacing: 6) {
            Text("Lobby")
                .font(.caption.weight(.semibold))
                .tracking(2)
                .foregroundStyle(GinRummyPalette.sage)

            Text(normalizedCode)
                .font(.system(size: 30, weight: .bold, design: .rounded))
                .monospaced()
                .foregroundStyle(GinRummyPalette.gold)

            Text(headlineMessage)
                .font(.subheadline)
                .foregroundStyle(mutedCream)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 8)
        }
    }

    private var headlineMessage: String {
        if status?.gameId != nil { return "Game starting…" }
        let s0 = seatDisplay(forSeat: 0)
        let s1 = seatDisplay(forSeat: 1)
        if s0.filled, s1.filled {
            if s0.ready, s1.ready { return "Both players ready — starting…" }
            if iAmReady { return "Waiting on \(opponentName())." }
            let oppName = oppNameFromSeats(mySeat: isHost ? 0 : 1)
            if let oppReady = (isHost ? s1 : s0).readyKnown, oppReady {
                return "\(oppName) is ready — tap Ready when you are."
            }
            return "Tap Ready when you're both set."
        }
        if isHost {
            return "Share the code or link — waiting for another player to join."
        }
        let host = previewHostName ?? seat0Player?.displayName ?? "the host"
        return "You're in \(host)'s lobby. Waiting for the other seat to fill up."
    }

    private var opponent: LobbyPlayerDTO? {
        guard let me = youPlayer else { return nil }
        return status?.players.first { $0.userId != me.userId }
    }

    private func opponentName() -> String {
        if let opp = opponent { return opp.displayName }
        if isHost { return seat1Player?.displayName ?? "the other player" }
        return previewHostName ?? seat0Player?.displayName ?? "the host"
    }

    private func oppNameFromSeats(mySeat: Int) -> String {
        let opp = seatDisplay(forSeat: mySeat == 0 ? 1 : 0)
        return opp.displayName
    }

    /// Local presentation model for a seat in the waiting room. Built from the
    /// polled `players` array when available, otherwise synthesized from what
    /// we already know locally (you're the host, the guest's `guest_joined`
    /// flag, the host name we fetched from `/preview`). This is what lets the
    /// roster look right *before* the new backend has redeployed and started
    /// returning `players` / `is_self` / `display_name`.
    private struct SeatDisplay {
        let displayName: String
        let isSelf: Bool
        let ready: Bool
        let readyKnown: Bool?
        let filled: Bool
        let seat: Int
    }

    private func seatDisplay(forSeat seat: Int) -> SeatDisplay {
        let polled = status?.players.first { $0.seat == seat }
        if let p = polled {
            return SeatDisplay(
                displayName: p.displayName,
                isSelf: p.isSelf,
                ready: p.ready,
                readyKnown: p.ready,
                filled: true,
                seat: seat
            )
        }
        let mineSeat = isHost ? 0 : 1
        if seat == mineSeat {
            return SeatDisplay(
                displayName: "You",
                isSelf: true,
                ready: localReady,
                readyKnown: nil,
                filled: true,
                seat: seat
            )
        }
        if seat == 0 {
            if let host = previewHostName {
                return SeatDisplay(
                    displayName: host,
                    isSelf: false,
                    ready: false,
                    readyKnown: nil,
                    filled: true,
                    seat: 0
                )
            }
            return SeatDisplay(
                displayName: "Host",
                isSelf: false,
                ready: false,
                readyKnown: nil,
                filled: false,
                seat: 0
            )
        }
        if status?.guestJoined == true {
            return SeatDisplay(
                displayName: "Guest",
                isSelf: false,
                ready: false,
                readyKnown: nil,
                filled: true,
                seat: 1
            )
        }
        return SeatDisplay(
            displayName: "Waiting for player…",
            isSelf: false,
            ready: false,
            readyKnown: nil,
            filled: false,
            seat: 1
        )
    }

    private var playerRoster: some View {
        VStack(spacing: 10) {
            playerCard(seatDisplay(forSeat: 0))
            playerCard(seatDisplay(forSeat: 1))
        }
    }

    @ViewBuilder
    private func playerCard(_ slot: SeatDisplay) -> some View {
        let filled = slot.filled
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(filled ? GinRummyPalette.bgPanel.opacity(0.85) : GinRummyPalette.bgPanel.opacity(0.45))
                    .frame(width: 44, height: 44)
                Image(systemName: filled ? (slot.seat == 0 ? "crown.fill" : "person.fill") : "person.fill.questionmark")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(filled ? GinRummyPalette.gold : GinRummyPalette.sage.opacity(0.85))
            }
            .overlay(
                Circle()
                    .stroke(GinRummyPalette.gold.opacity(filled ? 0.5 : 0.25), lineWidth: 1)
            )

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    Text(slot.displayName)
                        .font(.headline)
                        .foregroundStyle(filled ? GinRummyPalette.cream : mutedCream)
                        .lineLimit(1)

                    if filled, slot.isSelf {
                        Text("You")
                            .font(.caption2.weight(.bold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(GinRummyPalette.gold.opacity(0.22))
                            .foregroundStyle(GinRummyPalette.gold)
                            .clipShape(Capsule())
                    }
                }
                Text(slot.seat == 0 ? "Host" : "Guest")
                    .font(.caption)
                    .foregroundStyle(GinRummyPalette.sage)
            }

            Spacer(minLength: 8)

            readyBadge(for: slot)
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 14)
        .background(panelFill)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(
                    slot.ready
                        ? GinRummyPalette.sage.opacity(0.8)
                        : GinRummyPalette.gold.opacity(filled ? 0.32 : 0.18),
                    lineWidth: 1
                )
        )
    }

    @ViewBuilder
    private func readyBadge(for slot: SeatDisplay) -> some View {
        if slot.filled, slot.readyKnown != nil {
            HStack(spacing: 6) {
                Image(systemName: slot.ready ? "checkmark.seal.fill" : "hourglass")
                    .font(.system(size: 13, weight: .semibold))
                Text(slot.ready ? "Ready" : "Not ready")
                    .font(.caption.weight(.semibold))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                slot.ready
                    ? GinRummyPalette.sage.opacity(0.22)
                    : GinRummyPalette.bgPanel.opacity(0.85)
            )
            .foregroundStyle(
                slot.ready ? GinRummyPalette.cream : GinRummyPalette.sage
            )
            .clipShape(Capsule())
            .overlay(
                Capsule()
                    .stroke(
                        slot.ready ? GinRummyPalette.sage.opacity(0.75) : GinRummyPalette.gold.opacity(0.28),
                        lineWidth: 1
                    )
            )
        } else {
            Text("—")
                .font(.caption.weight(.semibold))
                .foregroundStyle(GinRummyPalette.sage.opacity(0.6))
        }
    }

    // MARK: - Share + ready button

    private var sharePanel: some View {
        VStack(spacing: 12) {
            // Visible invite link with the system share sheet (recents +
            // apps) right next to it. Copying stays a separate action below.
            HStack(spacing: 10) {
                Text(inviteShareLinkURL().absoluteString)
                    .font(.caption.monospaced())
                    .foregroundStyle(GinRummyPalette.cream.opacity(0.9))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 9)
                    .background(GinRummyPalette.bgDeep.opacity(0.55))
                    .clipShape(RoundedRectangle(cornerRadius: 9))
                    .overlay(
                        RoundedRectangle(cornerRadius: 9)
                            .stroke(GinRummyPalette.gold.opacity(0.3), lineWidth: 1)
                    )

                ShareLink(
                    item: inviteShareLinkURL(),
                    subject: Text("Gin Rummy invite"),
                    message: Text("Join my Gin Rummy game! Code \(normalizedCode)"),
                    preview: SharePreview("Gin Rummy invite — code \(normalizedCode)")
                ) {
                    Image(systemName: "square.and.arrow.up")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(GinRummyPalette.bgDeep)
                        .frame(width: 38, height: 36)
                        .background(GinRummyPalette.gold)
                        .clipShape(RoundedRectangle(cornerRadius: 9))
                }
                .accessibilityLabel("Share invite link")
            }

            HStack(spacing: 14) {
                Button {
                    UIPasteboard.general.string = inviteShareLinkURL().absoluteString
                    flashCopyConfirmation("Link copied")
                } label: {
                    Label("Copy link", systemImage: "doc.on.doc")
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(GinRummyPalette.cream.opacity(0.85))

                Button {
                    UIPasteboard.general.string = normalizedCode
                    flashCopyConfirmation("Code copied")
                } label: {
                    Label("Copy code", systemImage: "number")
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(GinRummyPalette.cream.opacity(0.85))

                Spacer()

                if !copyConfirmation.isEmpty {
                    Text(copyConfirmation)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(GinRummyPalette.sage)
                        .transition(.opacity)
                }
            }

            Text(inviteShareLinkHint())
                .font(.caption2)
                .foregroundStyle(hintColor)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .frame(maxWidth: .infinity)
        .background(panelFill)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .ginGoldBorder(cornerRadius: 14)
    }

    private func flashCopyConfirmation(_ text: String) {
        withAnimation(.easeIn(duration: 0.12)) { copyConfirmation = text }
        copyConfirmationTask?.cancel()
        copyConfirmationTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_600_000_000)
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.25)) { copyConfirmation = "" }
        }
    }

    private var readyButton: some View {
        Group {
            if iAmReady {
                Button(readyBusy ? "Working…" : "Cancel ready") {
                    Task { await toggleReady(target: false) }
                }
                .buttonStyle(GinGhostButtonStyle())
                .disabled(readyBusy || !canToggleReady || app.accessToken == nil)
            } else {
                Button(readyBusy ? "Readying…" : "Ready up") {
                    Task { await toggleReady(target: true) }
                }
                .buttonStyle(GinPrimaryButtonStyle())
                .disabled(readyBusy || !canToggleReady || app.accessToken == nil)
            }
        }
    }

    private func inviteShareLinkURL() -> URL {
        AppConfig.inviteShareURL(forInviteCode: normalizedCode)
    }

    private func inviteShareLinkHint() -> String {
        if AppConfig.usesInviteCustomURLScheme {
            return "Local dev: links use ginrummy://join/… and only open on a device with the app installed."
        }
        return "Friends can tap this link in Messages — it opens a page that jumps straight into the app."
    }

    // MARK: - Polling + ready action

    private func startPolling() {
        pollTask?.cancel()
        pollTask = Task { @MainActor in
            var consecutiveFailures = 0
            while !Task.isCancelled, app.activeGameId == nil {
                guard let token = app.accessToken else {
                    try? await Task.sleep(nanoseconds: 2_000_000_000)
                    continue
                }
                do {
                    let s = try await app.api.lobbyStatus(code: normalizedCode, token: token)
                    status = s
                    consecutiveFailures = 0
                    pollErrorHint = nil
                    // Server is authoritative for the ready flag — once it
                    // confirms our seat, drop the optimistic local flag so
                    // the two never disagree if the server-side toggle was
                    // rejected (e.g. lobby was closed under us).
                    if let me = s.players.first(where: { $0.isSelf }) {
                        localReady = me.ready
                    }
                    if let gid = s.gameIdToEnter {
                        await transitionToGame(gameId: gid, token: token)
                        return
                    }
                } catch {
                    consecutiveFailures += 1
                    // First couple of hiccups are usually a transient blip
                    // (auth refresh, network jitter); only nag the user once
                    // it's clear the lobby state isn't going to refresh.
                    if consecutiveFailures >= 3 {
                        pollErrorHint = "Can't refresh the lobby — \(UserFeedback.from(error))"
                    }
                }
                try? await Task.sleep(nanoseconds: 2_000_000_000)
            }
        }
    }

    /// One-shot fetch of the host's display name for guests so seat 0 doesn't
    /// look empty before the polling loop catches up (or in case the deployed
    /// backend hasn't shipped the new `players` array yet — `/preview` has
    /// always returned `host_display_name`). Idempotent: only runs once per
    /// view appearance and silently no-ops on failure.
    private func loadHostPreviewIfNeeded() async {
        guard previewHostName == nil else { return }
        do {
            let preview = try await app.api.lobbyInvitePreview(inviteCode: normalizedCode)
            if !preview.host_display_name.isEmpty {
                previewHostName = preview.host_display_name
            }
        } catch {}
    }

    private func transitionToGame(gameId: String, token: String) async {
        do {
            let st = try await app.api.gameState(gameId: gameId, token: token)
            app.applyGameTableState(
                perspective: st.perspective,
                betting: st.betting,
                opponentDisplayName: st.opponentDisplayName
            )
            app.activeGameId = gameId
        } catch {
            // If the state call hiccups (auth refresh mid-poll), still flip the
            // gameId — GameView will retry the state fetch on its own.
            app.activeGameId = gameId
        }
    }

    private func toggleReady(target: Bool) async {
        guard let token = app.accessToken else { return }
        readyBusy = true
        feedback = ""
        defer { readyBusy = false }
        // Flip the optimistic flag immediately so the local seat card shows
        // "Ready" without waiting for the next poll tick.
        localReady = target
        do {
            let s = try await app.api.setLobbyReady(code: normalizedCode, token: token, ready: target)
            status = s
            if let me = s.players.first(where: { $0.isSelf }) {
                localReady = me.ready
            }
            if let gid = s.gameIdToEnter {
                await transitionToGame(gameId: gid, token: token)
            }
        } catch {
            // Roll the optimistic flag back so the UI matches the server.
            localReady = !target
            feedback = UserFeedback.from(error)
            feedbackIsError = true
        }
    }
}
