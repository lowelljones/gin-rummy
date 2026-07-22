import AudioToolbox
import SwiftUI

struct GameView: View {
    @EnvironmentObject private var app: AppModel
    @State private var pollTask: Task<Void, Never>?
    @State private var feedbackText = ""
    @State private var feedbackIsError = false
    @State private var selectedHandCard: String?
    @State private var voidFlashKind: HandVoidFlashKind? = nil
    @State private var cutReveal: CutRevealModel?
    /// Identity of the cut we've already shown, so polling re-renders / reconnects don't replay it.
    @State private var revealedCutKey: String?
    @State private var bottomLogText: String = ""
    @State private var handDisplayOrder: [String] = []
    @State private var cardFlight: CardFlightModel?
    @State private var cardFlightClearTask: Task<Void, Never>?
    @State private var messageTask: Task<Void, Never>?
    @State private var downCardStatusMessage: String?
    @State private var cutRevealTask: Task<Void, Never>?
    @State private var redealFlashTask: Task<Void, Never>?
    @State private var lastYouPickup: PickupSource? = nil
    @State private var lastOpponentPickup: PickupSource? = nil
    /// Stock size right after our discard completes, before the opponent picks up — used when a poll skips their 10→11 draw step.
    @State private var stockCountAfterOurDiscardEndsTurn: Int? = nil
    @State private var youAcceptedDownCardPendingDiscard = false
    @State private var opponentAcceptedDownCardPendingDiscard = false
    /// `seq` of the most recent server-reported action we've already logged (0 = none yet).
    @State private var lastSeenServerActionSeq = 0

    /// Realtime subscription to `player_game_snapshots` (RLS-filtered per user).
    @State private var signalSocket: GameSignalSocket?

    /// Measured frames of the table zones (stock, discard, hands) so flight and
    /// deal animations land exactly on the real views.
    @State private var tableAnchorFrames: [String: CGRect] = [:]
    /// Card dropped on the table via drag-to-discard, consumed by `DiscardHelper`.
    @State private var dragDiscardRequest: String?
    /// Card the player just drag-discarded: shown on the pile (and hidden from the fan) immediately,
    /// while the discard request is in flight, so releasing feels instant instead of waiting on the server.
    @State private var pendingDiscardCard: String?
    /// The next server-confirmed discard whose flight we've already played optimistically — skip re-animating it.
    @State private var suppressDiscardFlightFor: String?
    /// Card just drawn into your hand — briefly glows gold in the fan.
    @State private var recentlyDrawnCard: String?
    @State private var drawnHighlightClearTask: Task<Void, Never>?
    /// Non-nil while the start-of-hand deal flourish is playing.
    @State private var dealAnimationToken: UUID?

    /// Terminal/transition states for leaving an unfinished game (yours or the opponent's).
    private enum GameExitState: Equatable {
        /// The leave API call is in flight — brief "leaving the table" visual.
        case leavingInProgress
        /// You left voluntarily — confirmation screen with a back-to-lobby button.
        case youLeft
        /// The opponent abandoned the game — notice + back-to-lobby button.
        case opponentLeft
    }

    @State private var exitState: GameExitState?
    @State private var showLeaveConfirm = false
    @State private var showAcceptInviteConfirm = false

    /// matchOver: the end-of-hand reveal shows first; this flips when the player
    /// taps through to the final match summary.
    @State private var showMatchSummaryAfterReveal = false

    /// Lobby rematch ready-up on the match summary screen (from `/state` rematch payload).
    @State private var rematchStatus: RematchStatusDTO?
    @State private var rematchLocalReady = false
    @State private var rematchBusy = false

    /// Linked lobby invite code — used for session recap across rematches.
    @State private var sessionLobbyCode: String?
    @State private var showScorecard = false

    @State private var showChatSheet = false
    @State private var chatMessages: [GameChatMessageDTO] = []
    @State private var chatOpponentUserId: String?
    @State private var chatWatermarkIso: String?
    @State private var chatBaselineLoaded = false
    @State private var chatToasts: [ChatToastItem] = []
    @State private var chatUnreadCount = 0
    @State private var chatComposeError: String?
    @State private var chatBaselineTask: Task<Void, Never>?

    private struct ChatToastItem: Identifiable, Equatable {
        let id: String
        /// Single-line banner copy: "Name: message…"
        let text: String
    }

    private static let chatEpochIso = "1970-01-01T00:00:00.000Z"

    private var chatUnreadBadgeLabel: String {
        if chatUnreadCount > 99 { return "99+" }
        return "\(chatUnreadCount)"
    }

    private var chatToolbarAccessibilityLabel: String {
        switch chatUnreadCount {
        case 0: return "Open chat"
        case 1: return "Open chat, 1 unread message"
        default: return "Open chat, \(chatUnreadCount) unread messages"
        }
    }

    private enum PickupSource: Equatable {
        case deck
        case discard(card: String)
        case downCard
    }

    private struct CardFlightModel: Equatable {
        let id = UUID()
        let route: CardFlightAnimationOverlay.Route
        let card: String
    }

    /// Derived presentation segment: one active surface at a time so controls and chrome stay isolated.
    private enum GamePlaySurface: Equatable {
        case cutForDeal
        case postCutReveal
        case downCard
        case play
        case knockLayoff
        case handOver
        case matchOver

        var accent: Color {
            switch self {
            case .cutForDeal: GinRummyPalette.phaseCutDeal
            case .postCutReveal: GinRummyPalette.phaseReveal
            case .downCard: GinRummyPalette.phaseDownCard
            case .play: GinRummyPalette.phasePlay
            case .knockLayoff: GinRummyPalette.phaseKnockLayoff
            case .handOver: GinRummyPalette.phaseHandOver
            case .matchOver: GinRummyPalette.phaseMatchOver
            }
        }

        var symbolName: String {
            switch self {
            case .cutForDeal: "square.split.2x1"
            case .postCutReveal: "sparkles.rectangle.stack"
            case .downCard: "rectangle.portrait.bottomhalf.inset.filled"
            case .play: "suit.spade.fill"
            case .knockLayoff: "arrow.triangle.merge"
            case .handOver: "list.number"
            case .matchOver: "flag.checkered"
            }
        }
    }

    private func gamePlaySurface(for p: PlayerPerspective) -> GamePlaySurface {
        if p.phase == "cutForDeal", p.cut != nil { return .cutForDeal }
        // The post-cut reveal only bridges the start of a hand (cut → first
        // draw). End-of-hand phases must never be hidden behind a stale local
        // interstitial/cutHold flag, or the defender's knock-layoff arrangement
        // (and the hand/match results) silently never render for that player.
        let isEndOfHandPhase = p.phase == "knockLayoff" || p.phase == "handOver" || p.phase == "matchOver"
        if isPostCutSequenceActive(), !isEndOfHandPhase { return .postCutReveal }
        switch p.phase {
        case "upcardOffer": return .downCard
        case "play": return .play
        case "knockLayoff": return .knockLayoff
        case "handOver": return .handOver
        case "matchOver": return .matchOver
        default: return .play
        }
    }

    private func showsScoreRail(_ surface: GamePlaySurface) -> Bool {
        switch surface {
        case .cutForDeal, .postCutReveal: false
        case .downCard, .play, .knockLayoff, .handOver, .matchOver: true
        }
    }

    private func showsTurnRibbon(_ surface: GamePlaySurface) -> Bool {
        switch surface {
        case .downCard, .play: true
        default: false
        }
    }

    /// The fanned "YOU" hand row. Hidden during knock layoff (the arrangement view
    /// renders your cards grouped by meld) and during the end-of-hand reveal.
    private func showsYouHand(_ surface: GamePlaySurface, p: PlayerPerspective) -> Bool {
        guard showsScoreRail(surface) else { return false }
        if surface == .knockLayoff { return false }
        if (surface == .handOver || surface == .matchOver), p.handResult != nil { return false }
        return true
    }

    /// True when the dedicated end-of-hand reveal should own the table.
    private func showsHandReveal(_ surface: GamePlaySurface, p: PlayerPerspective) -> Bool {
        guard p.handResult != nil else { return false }
        if surface == .handOver { return true }
        if surface == .matchOver, !showMatchSummaryAfterReveal { return true }
        return false
    }

    private func canReorderHand(for surface: GamePlaySurface) -> Bool {
        surface == .play || surface == .downCard
    }

    /// Drag-to-discard is live exactly when a discard is: your turn in play with 11 cards.
    private func canDragDiscard(surface: GamePlaySurface, p: PlayerPerspective) -> Bool {
        pendingDiscardCard == nil
            && surface == .play && p.currentTurn == p.seat && p.hands[p.seat].count == 11
    }

    private struct CutRevealModel: Equatable {
        var last: PlayerPerspective.LastCutResult
        var youAreSeat: Int
        /// Opponent's card starts hidden when the local player cut first.
        var staged: Bool
        /// Defer the "opponent declined the down card" hint until the reveal finishes.
        var deferDealerDeclineHint: Bool
    }

    private func cutKey(_ l: PlayerPerspective.LastCutResult) -> String {
        "\(l.p0)-\(l.p1)-\(l.nonDealer)"
    }

    /// Single Equatable snapshot so `gameContent` uses one `onChange` (avoids chained-modifier warnings).
    private struct GameContentObservation: Equatable {
        let phase: String
        let hand: [String]
        let hasLastCut: Bool
    }

    private func gameContentObservation(_ p: PlayerPerspective) -> GameContentObservation {
        GameContentObservation(
            phase: p.phase,
            hand: p.hands[p.seat],
            hasLastCut: p.lastCut != nil
        )
    }

    var body: some View {
        Group {
            if let gid = app.activeGameId, let p = app.lastPerspective {
                gameContent(gameId: gid, p: p)
            } else {
                ContentUnavailableView("No active game", systemImage: "rectangle.stack")
                    .foregroundStyle(GinRummyPalette.cream)
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .sheet(isPresented: $showScorecard) {
            ScorecardView(
                inviteCode: sessionLobbyCode,
                gameId: app.activeGameId
            )
            .environmentObject(app)
        }
        .confirmationDialog(
            "Leave this game?",
            isPresented: $showLeaveConfirm,
            titleVisibility: .visible
        ) {
            Button("Leave game", role: .destructive) {
                Task { await leaveCurrentGame(acceptingInvite: nil) }
            }
            Button("Keep playing", role: .cancel) {}
        } message: {
            Text("\(app.opponentDisplayName) will be told you left, and this match will end without a result.")
        }
        .confirmationDialog(
            "Join \(app.inGameInvite?.hostLabel ?? "their") game?",
            isPresented: $showAcceptInviteConfirm,
            titleVisibility: .visible
        ) {
            Button("Leave & join new game", role: .destructive) {
                Task { await leaveCurrentGame(acceptingInvite: app.inGameInvite) }
            }
            Button("Keep playing", role: .cancel) {}
        } message: {
            Text("Accepting forfeits your current game with \(app.opponentDisplayName) — they'll be notified that you left.")
        }
        .sheet(isPresented: $showChatSheet) {
            Group {
                if let gid = app.activeGameId {
                    GameChatSheet(
                        gameId: gid,
                        opponentDisplayName: app.opponentDisplayName,
                        opponentUserId: $chatOpponentUserId,
                        messages: $chatMessages,
                        chatWatermarkIso: $chatWatermarkIso,
                        composeError: $chatComposeError
                    )
                    .environmentObject(app)
                }
            }
        }
        .onDisappear {
            pollTask?.cancel()
            cutRevealTask?.cancel()
            redealFlashTask?.cancel()
            cardFlightClearTask?.cancel()
            messageTask?.cancel()
            chatBaselineTask?.cancel()
            drawnHighlightClearTask?.cancel()
            disconnectGameSignals()
        }
    }

    private func setFeedback(_ text: String, error: Bool) {
        feedbackText = text
        feedbackIsError = error
    }

    private func isPostCutSequenceActive() -> Bool {
        cutReveal != nil
    }

    /// Same duration as `HandRevealView`'s flash stage.
    private static let redealFlashDurationNs: UInt64 = 2_400_000_000
    /// Safety-poll cadence. When realtime is configured the socket delivers
    /// opponent moves within ~tens of ms, so we poll slowly (12s) purely as a
    /// backstop; without realtime we fall back to the old ~1s cadence.
    private static var pollIntervalNs: UInt64 {
        GameSignalSocket.isConfigured ? 12_000_000_000 : 1_000_000_000
    }

    @MainActor
    private func connectGameSignals(gameId: String) {
        signalSocket?.disconnect()
        guard let token = app.accessToken else { return }
        let socket = GameSignalSocket(gameId: gameId, accessToken: token) { state in
            if applyAbandonmentIfNeeded(state, gameId: gameId) { return }
            applyRemoteGameState(state, gameId: gameId)
        }
        signalSocket = socket
        socket.connect()
    }

    @MainActor
    private func disconnectGameSignals() {
        signalSocket?.disconnect()
        signalSocket = nil
    }

    @MainActor
    private func applyRemoteGameState(_ s: GameStateResponse, gameId: String) {
        guard app.activeGameId == gameId else { return }
        guard exitState == nil else { return }

        if let rematch = s.rematch {
            rematchStatus = rematch
            sessionLobbyCode = rematch.lobbyInviteCode
            if let me = rematch.players.first(where: { $0.isSelf }) {
                rematchLocalReady = me.ready
            }
            if let nextId = rematch.nextGameId, nextId != gameId, let token = app.accessToken {
                Task { await transitionToRematchGame(gameId: nextId, token: token) }
            }
        } else if let code = s.lobbyInviteCode {
            sessionLobbyCode = code
            if s.perspective.phase != "matchOver" {
                rematchStatus = nil
                rematchLocalReady = false
            }
        } else if s.perspective.phase != "matchOver" {
            rematchStatus = nil
            rematchLocalReady = false
            sessionLobbyCode = nil
        }

        scheduleChatBaselineLoadOnce(gameId: gameId)

        let before = app.lastPerspective
        let snapshotChanged =
            before == nil
            || before != s.perspective
            || app.lastBetting != s.betting

        if snapshotChanged {
            app.applyGameTableState(
                perspective: s.perspective,
                betting: s.betting,
                opponentDisplayName: s.opponentDisplayName
            )
            let a = s.perspective
            handleAfterPerspectiveUpdate(before: before, after: a)
            if let b = before {
                let o = 1 - a.seat
                let bOpp = b.hands[o], aOpp = a.hands[o]
                if aOpp.count == bOpp.count + 1,
                   b.phase == "upcardOffer",
                   a.discard.count < b.discard.count
                {
                    downCardStatusMessage = "Opponent Drew Down Card"
                    messageTask?.cancel()
                    messageTask = Task {
                        try? await Task.sleep(nanoseconds: 5_500_000_000)
                        await MainActor.run {
                            if downCardStatusMessage == "Opponent Drew Down Card" {
                                downCardStatusMessage = nil
                            }
                        }
                    }
                }
            }
        }
    }

    private func proposeRedealAllowed(for p: PlayerPerspective) -> Bool {
        GameTablePolicy.proposeRedealAllowed(phase: p.phase)
    }

    private func isPendingRedeal(_ p: PlayerPerspective) -> Bool {
        GameTablePolicy.isPendingRedeal(p.redeal)
    }

    @MainActor
    private func applyAbandonmentIfNeeded(_ s: GameStateResponse, gameId: String) -> Bool {
        guard app.activeGameId == gameId else { return true }
        guard s.status == "abandoned" else { return false }
        pollTask?.cancel()
        switch exitState {
        case nil, .leavingInProgress:
            exitState = exitStateForAbandonment(
                leftBySeat: s.leftBySeat,
                mySeat: s.perspective.seat
            )
        case .youLeft, .opponentLeft:
            break
        }
        return true
    }

    private func handleAfterPerspectiveUpdate(before: PlayerPerspective?, after: PlayerPerspective) {
        /* Server cleared the one-shot void flag — don't keep the local flash overlay blocking play. */
        if voidFlashKind != nil, after.voidFlash == nil {
            redealFlashTask?.cancel()
            voidFlashKind = nil
        }
        if maybeBeginCutReveal(before: before, after: after) {
            return
        }
        detectNewDeal(before: before, after: after)
        detectYourTurnBuzz(before: before, after: after)
        detectMyDraw(before: before, after: after)
        detectRedealCompletion(before: before, after: after)
        detectPlayedThroughVoid(before: before, after: after)
        detectDownCardStateForDealer(before: before, after: after)
        // Server confirmed our optimistic discard (the card has left our hand) — hand over to the real snapshot.
        if let pending = pendingDiscardCard, !after.hands[after.seat].contains(pending) {
            clearPendingDiscard()
        }
        updateCardFlights(before: before, after: after)
        if let line = serverActionStatusLine(after) {
            setBottomLog(line)
        } else if let b = before {
            // Legacy servers (no lastAction in the perspective): fall back to the
            // snapshot-diff heuristics. Never mix the two on the same game — the
            // heuristics can mis-attribute a deck draw as a discard-pile pickup
            // when polls collapse multiple moves.
            if after.lastAction == nil, let msg = consolidatedStatusLine(before: b, after: after) {
                setBottomLog(msg)
            }
        } else if after.phase == "upcardOffer" {
            setBottomLog(
                after.currentTurn == after.seat
                    ? "This hand · Down card — your turn"
                    : "This hand · Down card — opponent’s turn"
            )
        }
    }

    /// Gently buzz the phone the moment control passes to us, so a player who set
    /// their phone down knows it's their move. Only fires on the actual turn flip
    /// (never on the initial load) and only in phases where we need to act.
    private func detectYourTurnBuzz(before: PlayerPerspective?, after: PlayerPerspective) {
        guard let b = before else { return }
        let actionable = after.phase == "play" || after.phase == "upcardOffer"
        guard actionable else { return }
        guard after.currentTurn == after.seat, b.currentTurn != after.currentTurn else { return }
        let generator = UIImpactFeedbackGenerator(style: .light)
        generator.impactOccurred()
    }

    /// Builds the bottom-log line from the server-reported `lastAction` — the single
    /// source of truth both clients share, so the two players always see the same
    /// (correct) story about what was picked up and discarded.
    private func serverActionStatusLine(_ a: PlayerPerspective) -> String? {
        guard let act = a.lastAction else { return nil }
        defer { lastSeenServerActionSeq = act.seq }
        guard act.seq != lastSeenServerActionSeq else { return nil }

        let who = act.seat == a.seat ? "You" : "Opponent"
        switch act.type {
        case "passUpcard":
            if act.seat == a.nonDealer {
                let chooser = a.dealer == a.seat ? "You choose" : "Opponent chooses"
                return "This hand · \(who) passed the down card — \(chooser) next"
            }
            let leader = a.nonDealer == a.seat ? "You lead" : "Opponent leads"
            return "This hand · \(who) passed — \(leader) from the deck"
        case "passStock":
            return "This hand · \(who) passed — deck played through"
        case "takeDownCard":
            return "This hand · \(who) took the down card"
        case "discard":
            guard let d = act.card, !d.isEmpty else { return nil }
            let base = "This hand · \(who) discarded \(cardName(d))"
            switch act.pickup?.type {
            case "drawStock":
                return base + " after drawing from the deck"
            case "takeDiscard":
                if let c = act.pickup?.card, !c.isEmpty {
                    return base + " after taking \(cardName(c)) from the discard pile"
                }
                return base + " after drawing from the discard pile"
            case "takeDownCard":
                return base + " after taking the down card"
            default:
                return base
            }
        default:
            // drawStock / takeDiscard mid-turn: summarized when the discard lands.
            return nil
        }
    }

    private func setBottomLog(_ text: String) {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return }
        bottomLogText = t
    }

    private func scheduleCardFlight(route: CardFlightAnimationOverlay.Route, card: String) {
        scheduleCardFlightSequence([(route, card)])
    }

    /// Instant feedback for a legal drag-discard: hide the card from the fan, drop it on the pile,
    /// and fly it there right away — before the server round-trip. `updateCardFlights` then skips
    /// re-animating the same discard once the server snapshot confirms it.
    private func beginOptimisticDiscard(_ card: String) {
        let c = CardIdValidation.normalize(card)
        guard !c.isEmpty else { return }
        withAnimation(.easeOut(duration: 0.18)) {
            pendingDiscardCard = c
        }
        suppressDiscardFlightFor = c
        scheduleCardFlight(route: .discardFromHand(isOpponent: false), card: c)
    }

    /// Discard request resolved — drop the optimistic overlay so the server snapshot is the source of truth.
    private func clearPendingDiscard() {
        guard pendingDiscardCard != nil else { return }
        withAnimation(.easeOut(duration: 0.15)) {
            pendingDiscardCard = nil
        }
    }

    /// Plays one or more card flights in order with a small gap between them, so a single
    /// "collapsed" snapshot can still surface multi-step actions (e.g. your discard → opp
    /// draw → opp discard when the bot turn round-trips inside one /move response).
    private func scheduleCardFlightSequence(
        _ steps: [(route: CardFlightAnimationOverlay.Route, card: String)]
    ) {
        cardFlightClearTask?.cancel()
        guard let first = steps.first else {
            cardFlight = nil
            return
        }
        cardFlight = CardFlightModel(route: first.route, card: first.card)
        cardFlightClearTask = Task { @MainActor in
            for i in 1 ..< steps.count {
                try? await Task.sleep(nanoseconds: 680_000_000)
                if Task.isCancelled { return }
                cardFlight = CardFlightModel(route: steps[i].route, card: steps[i].card)
            }
            try? await Task.sleep(nanoseconds: 680_000_000)
            if Task.isCancelled { return }
            cardFlight = nil
        }
    }

    /// One bounded arc animation per server snapshot: draw → hand or hand → discard.
    private func updateCardFlights(before b: PlayerPerspective?, after a: PlayerPerspective) {
        guard let b = b else { return }
        let my = a.seat
        let opp = 1 - my

        let drawPhases =
            (b.phase == "play" || b.phase == "upcardOffer")
            && (a.phase == "play" || a.phase == "upcardOffer")

        if drawPhases {
            for seat in [my, opp] {
                let toOpponent = seat == opp
                if b.hands[seat].count == 10, a.hands[seat].count == 11 {
                    let added = a.hands[seat].first { !b.hands[seat].contains($0) } ?? ""
                    let n = CardIdValidation.normalize(added)
                    let display = CardIdValidation.isValidFormat(n) ? n : "AS"

                    if b.stockCount > a.stockCount {
                        scheduleCardFlight(route: .drawFromStock(toOpponent: toOpponent), card: display)
                        return
                    }
                    if a.discard.count < b.discard.count {
                        scheduleCardFlight(route: .drawFromDiscard(toOpponent: toOpponent), card: display)
                        return
                    }
                }
            }
        }

        guard b.phase == "play", a.phase == "play" else { return }

        if b.currentTurn == my, a.currentTurn == opp,
           b.hands[my].count == 11, a.hands[my].count == 10,
           let newTop = a.discard.last, !newTop.isEmpty, newTop != b.discard.last
        {
            let normTop = CardIdValidation.normalize(newTop)
            // We already flew this discard optimistically on release — don't replay it.
            if suppressDiscardFlightFor == normTop {
                suppressDiscardFlightFor = nil
                return
            }
            scheduleCardFlight(route: .discardFromHand(isOpponent: false), card: normTop)
            return
        }

        // Opponent's turn ended with the discard the client saw mid-draw (opp had 11 last poll, now 10).
        if b.currentTurn == opp, a.currentTurn == my,
           b.hands[opp].count == 11, a.hands[opp].count == 10,
           let newTop = a.discard.last, !newTop.isEmpty, newTop != b.discard.last
        {
            scheduleCardFlight(
                route: .discardFromHand(isOpponent: true),
                card: CardIdValidation.normalize(newTop)
            )
            return
        }

        // Collapsed opponent turn (poll missed the 11-card mid-state): show pickup, then discard.
        if b.currentTurn == opp, a.currentTurn == my,
           b.hands[opp].count == 10, a.hands[opp].count == 10,
           let newTop = a.discard.last, !newTop.isEmpty, newTop != b.discard.last
        {
            let oppDrewFromStock = a.stockCount < b.stockCount
            var steps: [(route: CardFlightAnimationOverlay.Route, card: String)] = []
            if oppDrewFromStock {
                steps.append((.drawFromStock(toOpponent: true), "AS"))
            } else {
                let pickedUp = b.discard.last ?? ""
                let pickedUpNorm = CardIdValidation.normalize(pickedUp)
                steps.append((.drawFromDiscard(toOpponent: true), pickedUpNorm))
            }
            steps.append((.discardFromHand(isOpponent: true), CardIdValidation.normalize(newTop)))
            scheduleCardFlightSequence(steps)
            return
        }

        // Collapsed bot-game case: your discard + opp draw + opp discard all rolled into one
        // /move response. Play the full sequence so the opponent's pickup is visible alongside
        // your own discard, mirroring the feedback you get on your own turn.
        if b.currentTurn == my, a.currentTurn == my,
           b.hands[my].count == 11, a.hands[my].count == 10,
           let discarded = a.discard.last, !discarded.isEmpty, discarded != b.discard.last
        {
            let yourDiscardRaw = b.hands[my].first { !a.hands[my].contains($0) } ?? ""
            let yourDiscardNorm = CardIdValidation.normalize(yourDiscardRaw)
            let oppDrewFromStock = a.stockCount < b.stockCount

            var steps: [(route: CardFlightAnimationOverlay.Route, card: String)] = []
            // Skip your discard's flight if we already played it optimistically on release.
            if suppressDiscardFlightFor == yourDiscardNorm {
                suppressDiscardFlightFor = nil
            } else if !yourDiscardNorm.isEmpty {
                steps.append((.discardFromHand(isOpponent: false), yourDiscardNorm))
            }
            if oppDrewFromStock {
                steps.append((.drawFromStock(toOpponent: true), "AS"))
            } else {
                // Opp drew from discard: the only face-up card they could have taken is the one
                // you just placed there (your discard is the new top before opp acts).
                steps.append((.drawFromDiscard(toOpponent: true), yourDiscardNorm))
            }
            steps.append((.discardFromHand(isOpponent: true), CardIdValidation.normalize(discarded)))
            scheduleCardFlightSequence(steps)
        }
    }

    private func handleAfterCutPick(before: PlayerPerspective, after: PlayerPerspective) {
        handleAfterPerspectiveUpdate(before: before, after: after)
    }

    private func phaseRibbonTitle(_ surface: GamePlaySurface, p: PlayerPerspective) -> String {
        switch surface {
        case .cutForDeal: return "Match · Cut for deal"
        case .postCutReveal: return "Match · Cut result"
        case .downCard: return "This hand · Down card"
        case .play: return "This hand · Play"
        case .knockLayoff: return "This hand · Layoff"
        case .handOver: return "This hand · End of hand"
        case .matchOver: return "Match · Final scores"
        }
    }

    private func phaseRibbonSubtitle(_ surface: GamePlaySurface, p: PlayerPerspective) -> String {
        switch surface {
        case .cutForDeal: return cutStageTitle(p)
        case .postCutReveal: return "Dealing the first hand…"
        case .downCard: return downCardStageTitle(p)
        case .play: return turnLine(p)
        case .knockLayoff:
            if let k = p.knock { return knockLayoffLine(p, k: k) }
            return "Layoffs"
        case .handOver: return "Continue when ready."
        case .matchOver: return matchOutcomeSubtitle(p)
        }
    }

    private func matchOutcomeSubtitle(_ p: PlayerPerspective) -> String { GameNarration.matchOutcomeSubtitle(p) }

    private func matchWinnerHeadline(_ p: PlayerPerspective) -> String { GameNarration.matchWinnerHeadline(p) }

    @ViewBuilder
    private func matchSummaryPanel(p: PlayerPerspective) -> some View {
        VStack(alignment: .leading, spacing: 8) {
                Text(matchWinnerHeadline(p))
                    .font(.title3.bold())
                    .foregroundStyle(GinRummyPalette.cream)
            Text("Final score · \(p.myScore) – \(p.opponentScore)")
                .font(.headline.monospacedDigit())
                .foregroundStyle(GinRummyPalette.cream)
            Text("Hands won · \(p.myHandsWon) – \(p.opponentHandsWon)")
                .font(.subheadline)
                .foregroundStyle(GinRummyPalette.sage.opacity(0.95))
            if let b = app.lastBetting, let bucket = b.bucket,
               let breakdown = BettingSettlementBreakdown.compute(
                   scores: p.scores,
                   handsWon: p.handsWon,
                   raceTarget: p.raceTarget
               ) {
                Divider().padding(.vertical, 2)
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text("Match tier")
                        .font(.subheadline.weight(.semibold))
                    Spacer(minLength: 8)
                    Text("\(bucket)")
                        .font(.title3.bold().monospacedDigit())
                        .foregroundStyle(GamePlaySurface.matchOver.accent)
                }
                VStack(alignment: .leading, spacing: 4) {
                    matchBreakdownRow(label: "Win bonus", value: breakdown.winBonus)
                    matchBreakdownRow(
                        label: "Score margin (\(breakdown.winnerScore) − \(breakdown.loserScore))",
                        value: breakdown.scoreDiff
                    )
                    if breakdown.shutoutBonus > 0 {
                        matchBreakdownRow(label: "Blitz shutout", value: breakdown.shutoutBonus)
                    }
                    if breakdown.netHands != 0 {
                        matchBreakdownRow(
                            label: "Net hands (25 × \(breakdown.netHands))",
                            value: breakdown.handsBonus
                        )
                    } else {
                        matchBreakdownRow(label: "Net hands (25 × 0)", value: 0)
                    }
                    Divider().padding(.vertical, 2)
                    matchBreakdownRow(label: "Match points", value: breakdown.raw, emphasized: true)
                    Text("\(breakdown.raw) match pts → tier \(bucket) (\(BettingSettlementBreakdown.tierRangeLabel(for: bucket)))")
                        .font(.caption2)
                        .foregroundStyle(GinRummyPalette.sage.opacity(0.9))
                }
                .padding(.top, 2)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(GamePlaySurface.matchOver.accent.opacity(0.16))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(GamePlaySurface.matchOver.accent.opacity(0.35), lineWidth: 1)
        )
        .contentTransition(.opacity)
    }

    @ViewBuilder
    private func matchBreakdownRow(label: String, value: Int, emphasized: Bool = false) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(label)
                .font(emphasized ? .caption.weight(.semibold) : .caption)
                .foregroundStyle(GinRummyPalette.sage.opacity(emphasized ? 1 : 0.95))
            Spacer(minLength: 8)
            Text(matchSignedPoints(value))
                .font(emphasized ? .caption.weight(.semibold).monospacedDigit() : .caption.monospacedDigit())
                .foregroundStyle(GinRummyPalette.cream.opacity(emphasized ? 1 : 0.95))
        }
    }

    private func matchSignedPoints(_ value: Int) -> String {
        if value > 0 { return "+\(value)" }
        if value < 0 { return "\(value)" }
        return "0"
    }

    @ViewBuilder
    private func handOverPanel(p: PlayerPerspective) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Scores are updated for this hand.")
                .font(.subheadline.weight(.medium))
            Text("Tap Continue for the next deal (or match end).")
                .font(.caption)
                .foregroundStyle(GinRummyPalette.sage.opacity(0.95))
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(GamePlaySurface.handOver.accent.opacity(0.14))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(GamePlaySurface.handOver.accent.opacity(0.32), lineWidth: 1)
        )
        .contentTransition(.opacity)
    }

    @ViewBuilder
    private func turnBanner(p: PlayerPerspective) -> some View {
        HStack {
            Spacer(minLength: 0)
            Label(
                p.currentTurn == p.seat ? "YOUR TURN" : "OPPONENT’S TURN",
                systemImage: p.currentTurn == p.seat ? "hand.raised.fill" : "hourglass"
            )
            .font(.headline.weight(.heavy))
            .foregroundStyle(GinRummyPalette.cream)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill((p.currentTurn == p.seat ? GinRummyPalette.sage : GinRummyPalette.navy).opacity(0.24))
            )
            Spacer(minLength: 0)
        }
        .contentTransition(.opacity)
    }

    @ViewBuilder
    private func bottomActivityLog() -> some View {
        Text(bottomLogText.isEmpty ? " " : bottomLogText)
            .font(.subheadline.weight(.medium))
            .foregroundStyle(GinRummyPalette.cream)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 12).fill(GinRummyPalette.bgPanel.opacity(0.55))
            )
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(GinRummyPalette.gold.opacity(0.22)))
    }

    // MARK: - Redesigned table chrome

    /// Slim top strip that replaces the navigation bar: leave, opponent name,
    /// scorecard, and chat — consistent with the lobby/scorecard look.
    @ViewBuilder
    private func tableTopBar(p: PlayerPerspective) -> some View {
        HStack(spacing: 14) {
            Button {
                showLeaveConfirm = true
            } label: {
                Image(systemName: "rectangle.portrait.and.arrow.right")
                    .font(.title3)
                    .foregroundStyle(GinRummyPalette.cream.opacity(0.85))
            }
            .disabled(exitState != nil || p.phase == "matchOver")
            .accessibilityLabel("Leave game")

            Spacer(minLength: 0)

            HStack(spacing: 6) {
                Image(systemName: "person.crop.circle.fill")
                    .foregroundStyle(GinRummyPalette.gold.opacity(0.9))
                    .symbolRenderingMode(.hierarchical)
                Text(app.opponentDisplayName)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(GinRummyPalette.cream)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)

            if sessionLobbyCode != nil {
                Button {
                    showScorecard = true
                } label: {
                    Image(systemName: "tablecells")
                        .font(.title3)
                        .foregroundStyle(GinRummyPalette.gold)
                }
                .accessibilityLabel("Scorecard")
            }
            Button {
                showChatSheet = true
                chatUnreadCount = 0
                chatComposeError = nil
                if let gid = app.activeGameId {
                    scheduleChatBaselineLoadOnce(gameId: gid)
                }
            } label: {
                ZStack(alignment: .topTrailing) {
                    Image(systemName: "bubble.left.and.bubble.right.fill")
                        .font(.title3)
                        .foregroundStyle(GinRummyPalette.gold)
                    if chatUnreadCount > 0 {
                        Text(chatUnreadBadgeLabel)
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, chatUnreadCount > 9 ? 5 : 0)
                            .frame(minWidth: 17, minHeight: 17)
                            .background(Color.red, in: Capsule())
                            .offset(x: 9, y: -7)
                            .accessibilityHidden(true)
                    }
                }
            }
            .accessibilityLabel(chatToolbarAccessibilityLabel)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }

    /// Compact score + turn pills, replacing the tall phase ribbon + score rail
    /// during play and the down-card offer.
    @ViewBuilder
    private func compactStatusRow(surface: GamePlaySurface, p: PlayerPerspective) -> some View {
        let yourTurn = p.currentTurn == p.seat
        HStack(spacing: 8) {
            GinStatusPill(
                text: "\(p.myScore) – \(p.opponentScore)",
                systemImage: "rosette",
                tint: GinRummyPalette.gold
            )
            GinStatusPill(
                text: p.seat == p.dealer ? "You dealt" : "Opp dealt",
                tint: GinRummyPalette.sage
            )
            Spacer(minLength: 0)
            GinStatusPill(
                text: yourTurn ? "Your turn" : "Their turn",
                systemImage: yourTurn ? "hand.raised.fill" : "hourglass",
                tint: yourTurn ? GinRummyPalette.sage : GinRummyPalette.navy
            )
        }
        .padding(.horizontal, 14)
    }

    /// Fixed, single-screen cut-for-deal layout — no scrolling, on-brand with
    /// the rest of the table. Header, the two cut zones + face-down fan, and a
    /// pinned action bar.
    @ViewBuilder
    private func cutForDealScreen(gameId: String, p: PlayerPerspective) -> some View {
        VStack(spacing: 0) {
            VStack(spacing: 6) {
                Text("CUT FOR THE DEAL")
                    .font(.caption.weight(.bold))
                    .tracking(3)
                    .foregroundStyle(GinRummyPalette.gold.opacity(0.95))
                Text(cutStageTitle(p))
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(GinRummyPalette.cream)
                    .multilineTextAlignment(.center)
                HStack(spacing: 10) {
                    GinStatusPill(text: "\(p.myScore) – \(p.opponentScore)", systemImage: "rosette")
                    GinStatusPill(text: "Game to \(p.raceTarget)", tint: GinRummyPalette.sage)
                }
                .padding(.top, 2)
            }
            .padding(.top, 18)
            .padding(.horizontal, 20)

            Spacer(minLength: 0)

            if p.cut != nil {
                CutForDealView(
                    gameId: gameId,
                    p: p,
                    token: app.accessToken,
                    onAfterCutPick: handleAfterCutPick(before:after:),
                    feedbackText: $feedbackText,
                    feedbackIsError: $feedbackIsError
                )
                .padding(.horizontal, 18)
            }

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// Fixed, scroll-free single-screen layout for the play and down-card surfaces.
    private func playingTable(gameId: String, surface: GamePlaySurface, p: PlayerPerspective) -> some View {
        VStack(spacing: 8) {
            compactStatusRow(surface: surface, p: p)

            Spacer(minLength: 0)

            FannedOpponentHandRow(cardCount: p.hands[1 - p.seat].count)
                .frame(height: 74)
                .padding(.horizontal, 4)
                .tableFlightAnchor(.opponentHand)

            Spacer(minLength: 0)

            centerTableForSurface(gameId: gameId, surface: surface, p: p)
                .padding(.horizontal, 14)

            if !bottomLogText.isEmpty {
                Text(bottomLogText)
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(GinRummyPalette.sage)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 14)
            }

            Spacer(minLength: 0)

            // Full-bleed hand: no horizontal padding so cards reach both edges.
            FannedHandRow(
                displayOrder: handDisplayFor(hand: p.hands[p.seat]),
                selected: $selectedHandCard,
                canReorder: canReorderHand(for: surface),
                onReorder: { handDisplayOrder = $0 },
                onDragDiscard: canDragDiscard(surface: surface, p: p)
                    ? { dragDiscardRequest = $0 }
                    : nil,
                recentlyDrawn: recentlyDrawnCard
            )
            .frame(height: 152)
            .tableFlightAnchor(.myHand)

            tableActionBar(gameId: gameId, surface: surface, p: p)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// Full-width knock/layoff surface — cards scale to the device width instead of
    /// overflowing horizontally inside the generic scroll column.
    @ViewBuilder
    private func knockLayoffScreen(
        gameId: String,
        p: PlayerPerspective,
        knock: PlayerPerspective.KnockPerspective,
        feedbackText: Binding<String>,
        feedbackIsError: Binding<Bool>
    ) -> some View {
        VStack(spacing: 0) {
            phaseRibbon(surface: .knockLayoff, p: p)
                .padding(.horizontal, 8)
                .padding(.top, 6)

            if knock.layoffTurn == p.seat, knock.knocker != p.seat {
                LayoffArrangementView(
                    p: p,
                    knock: knock,
                    opponentName: app.opponentDisplayName,
                    onSubmit: { melds, layoffs in
                        Task {
                            await submitLayoffResolve(
                                gameId: gameId,
                                ownMelds: melds,
                                layoffs: layoffs
                            )
                        }
                    }
                )
            } else {
                ScrollView {
                    KnockerWaitingView(knock: knock, opponentName: app.opponentDisplayName)
                        .padding(.top, 8)
                }
            }

            if GameTablePolicy.proposeRedealAllowed(phase: p.phase) {
                proposeRedealFooter(
                    gameId: gameId,
                    p: p,
                    feedbackText: feedbackText,
                    feedbackIsError: feedbackIsError
                )
                .padding(.horizontal, 14)
                .padding(.bottom, 8)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    /// Pinned bottom action bar — context buttons for the current surface, always
    /// on screen so the player never has to scroll to act.
    @ViewBuilder
    private func tableActionBar(gameId: String, surface: GamePlaySurface, p: PlayerPerspective) -> some View {
        VStack(spacing: 8) {
            if feedbackIsError, !feedbackText.isEmpty {
                FeedbackLine(text: feedbackText, isError: true, privateClubStyle: true)
            }
            switch surface {
            case .downCard:
                upcardButtons(
                    gameId: gameId,
                    p: p,
                    token: app.accessToken,
                    feedbackText: $feedbackText,
                    feedbackIsError: $feedbackIsError
                )
            case .play:
                if p.currentTurn == p.seat {
                    playButtons(
                        gameId: gameId,
                        p: p,
                        token: app.accessToken,
                        feedbackText: $feedbackText,
                        feedbackIsError: $feedbackIsError,
                        selectedHandCard: $selectedHandCard
                    )
                } else {
                    Label("Waiting for \(app.opponentDisplayName)…", systemImage: "hourglass")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(GinRummyPalette.sage)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                }
            default:
                EmptyView()
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 14)
        .padding(.top, 10)
        .padding(.bottom, 6)
        .background(
            GinRummyPalette.bgDeep.opacity(0.65)
                .overlay(alignment: .top) {
                    Rectangle()
                        .fill(GinRummyPalette.gold.opacity(0.18))
                        .frame(height: 1)
                }
        )
    }

    @ViewBuilder
    private func phaseRibbon(surface: GamePlaySurface, p: PlayerPerspective) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: surface.symbolName)
                .font(.title3.weight(.semibold))
                .foregroundStyle(surface.accent)
                .frame(width: 28, alignment: .center)
            VStack(alignment: .leading, spacing: 2) {
                Text(phaseRibbonTitle(surface, p: p))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(GinRummyPalette.cream)
                Text(phaseRibbonSubtitle(surface, p: p))
                    .font(.caption)
                    .foregroundStyle(GinRummyPalette.sage.opacity(0.95))
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(surface.accent.opacity(0.14))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(surface.accent.opacity(0.28), lineWidth: 1)
        )
        .contentTransition(.opacity)
    }

    @ViewBuilder
    private func phaseBackdrop(surface _: GamePlaySurface) -> some View {
        GinRummyPalette.bgDeep.opacity(0.35)
            .frame(maxWidth: .infinity)
            .frame(minHeight: 220, alignment: .top)
            .allowsHitTesting(false)
            .contentTransition(.opacity)
    }

    @ViewBuilder
    private func scoreRail(surface: GamePlaySurface, p: PlayerPerspective) -> some View {
        if showsScoreRail(surface) {
            HStack(alignment: .firstTextBaseline) {
                Spacer(minLength: 0)
                VStack(alignment: .trailing, spacing: 0) {
                    Text("\(p.myScore) – \(p.opponentScore)")
                        .font(.headline.monospacedDigit())
                        .foregroundStyle(GinRummyPalette.cream)
                    Text("Race \(p.raceTarget)")
                        .font(.caption2)
                        .foregroundStyle(GinRummyPalette.sage.opacity(0.95))
                }
            }
            SeatInfoBar(p: p)
            opponentPresenceStrip(p: p)
        } else {
            EmptyView()
        }
    }

    @ViewBuilder
    private func centerTableForSurface(gameId: String, surface: GamePlaySurface, p: PlayerPerspective) -> some View {
        switch surface {
        case .cutForDeal:
            // Handled by the dedicated, non-scrolling `cutForDealScreen`.
            EmptyView()
        case .postCutReveal:
            EmptyView()
        case .downCard, .play:
            VStack(alignment: .leading, spacing: 8) {
                if surface == .play {
                    if p.currentTurn == p.seat {
                        Label("Your turn", systemImage: "hand.raised.fill")
                            .font(.caption)
                            .foregroundStyle(GinRummyPalette.goldAccent)
                    } else {
                        Label("Opponent’s turn", systemImage: "hourglass")
                            .font(.caption)
                            .foregroundStyle(GinRummyPalette.sage.opacity(0.95))
                    }
                }
                if let kc = p.knockCheckCard, !kc.isEmpty {
                    HStack(alignment: .center, spacing: 8) {
                        Text("Knock limit card")
                            .font(.caption)
                            .foregroundStyle(GinRummyPalette.sage.opacity(0.95))
                        PlayingCardView(card: kc, compact: true, onTap: nil)
                    }
                }
                HStack {
                    Spacer(minLength: 0)
                    StockAndDiscardPiles(
                        stockCount: p.stockCount,
                        discard: pendingDiscardCard.map { p.discard + [$0] } ?? p.discard,
                        discardOnTap: discardTapActionIfEnabled(gameId: gameId, p: p),
                        stockOnTap: drawStockActionIfEnabled(gameId: gameId, p: p)
                    )
                    Spacer(minLength: 0)
                }
            }
            .contentTransition(.opacity)
        case .knockLayoff, .handOver, .matchOver:
            EmptyView()
        }
    }

    private func gameContent(gameId: String, p: PlayerPerspective) -> some View {
        let surface = gamePlaySurface(for: p)
        return ZStack {
            if let exit = exitState {
                gameExitScreen(exit)
                    .zIndex(300)
                    .transition(.opacity)
            } else if let flash = voidFlashKind {
                HandVoidFlashInterstitial(kind: flash)
                    .zIndex(200)
                    .transition(.scale(scale: 0.86).combined(with: .opacity))
            } else if let reveal = cutReveal {
                CutRevealView(
                    last: reveal.last,
                    youAreSeat: reveal.youAreSeat,
                    staged: reveal.staged,
                    onFinished: { finishCutReveal() }
                )
                .id(cutKey(reveal.last))
                .zIndex(200)
                .transition(.opacity)
            } else {
                GinRummyTableChrome {
                    ZStack(alignment: .top) {
                        phaseBackdrop(surface: surface)
                        VStack(spacing: 0) {
                            tableTopBar(p: p)
                            if showsHandReveal(surface, p: p), let hr = p.handResult {
                                HandRevealView(
                                    p: p,
                                    result: hr,
                                    opponentName: app.opponentDisplayName,
                                    isMatchOver: surface == .matchOver,
                                    onContinue: {
                                        Task {
                                            await send(
                                                gameId: gameId,
                                                token: app.accessToken,
                                                intent: ["type": "ackHandOver"],
                                                success: "Ready for the next hand.",
                                                feedbackText: $feedbackText,
                                                feedbackIsError: $feedbackIsError
                                            )
                                        }
                                    },
                                    onShowFinalResults: { showMatchSummaryAfterReveal = true }
                                )
                                .id(handRevealIdentity(hr))
                            } else if surface == .cutForDeal {
                                // Fixed single-screen cut layout — never scrolls.
                                cutForDealScreen(gameId: gameId, p: p)
                            } else if surface == .play || surface == .downCard {
                                // Fixed single-screen table — never scrolls during a turn.
                                playingTable(gameId: gameId, surface: surface, p: p)
                            } else if surface == .knockLayoff, let k = p.knock {
                                knockLayoffScreen(
                                    gameId: gameId,
                                    p: p,
                                    knock: k,
                                    feedbackText: $feedbackText,
                                    feedbackIsError: $feedbackIsError
                                )
                            } else {
                                ScrollView {
                                    VStack(alignment: .leading, spacing: 10) {
                                        phaseRibbon(surface: surface, p: p)
                                        scoreRail(surface: surface, p: p)
                                        centerTableForSurface(gameId: gameId, surface: surface, p: p)

                                        if surface == .matchOver {
                                            matchSummaryPanel(p: p)
                                        }

                                        if surface == .handOver, p.handResult == nil {
                                            handOverPanel(p: p)
                                        }

                                        if showsYouHand(surface, p: p) {
                                            youHandBlock(surface: surface, p: p, selectedHandCard: $selectedHandCard)
                                        }

                                        if showsYouHand(surface, p: p) {
                                            bottomActivityLog()
                                        }

                                        moveButtons(
                                            gameId: gameId,
                                            surface: surface,
                                            p: p,
                                            feedbackText: $feedbackText,
                                            feedbackIsError: $feedbackIsError,
                                            selectedHandCard: $selectedHandCard
                                        )
                                    }
                                    .padding(8)
                                }
                            }
                        }
                    }
                }
            }

            if exitState == nil, voidFlashKind == nil, isPendingRedeal(p) {
                pendingRedealOverlay(
                    gameId: gameId,
                    p: p,
                    feedbackText: $feedbackText,
                    feedbackIsError: $feedbackIsError
                )
                .zIndex(250)
                .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.28), value: voidFlashKind)
        .animation(.easeInOut(duration: 0.28), value: cutReveal)
        .animation(.easeInOut(duration: 0.28), value: surface)
        .animation(.easeInOut(duration: 0.28), value: exitState)
        .animation(.spring(response: 0.42, dampingFraction: 0.86), value: p.redeal?.status)
        .animation(.spring(response: 0.42, dampingFraction: 0.86), value: p.redeal?.fromSeat)
        .animation(.spring(response: 0.42, dampingFraction: 0.86), value: app.inGameInvite)
        .overlay(alignment: .top) {
            VStack(spacing: 8) {
                if exitState == nil {
                    inGameInviteBanner()
                }
                redealProposalBanner(
                    gameId: gameId,
                    p: p,
                    feedbackText: $feedbackText,
                    feedbackIsError: $feedbackIsError
                )
            }
            .padding(.horizontal, 10)
            .padding(.top, 6)
        }
        .overlay(alignment: .topTrailing) {
            chatToastStack()
                .padding(.top, 6)
                .padding(.trailing, 6)
                .allowsHitTesting(false)
        }
        .coordinateSpace(name: "gameTable")
        .onPreferenceChange(TableAnchorFramesKey.self) { tableAnchorFrames = $0 }
        .overlay {
            if let cf = cardFlight, surface == .play || surface == .downCard {
                CardFlightAnimationOverlay(route: cf.route, card: cf.card, anchorFrames: tableAnchorFrames)
                    .id(cf.id)
                    .allowsHitTesting(false)
                    .transition(.opacity)
            }
        }
        .overlay {
            if let token = dealAnimationToken,
               exitState == nil, cutReveal == nil, voidFlashKind == nil,
               surface == .downCard || surface == .play
            {
                DealAnimationOverlay(anchorFrames: tableAnchorFrames) {
                    dealAnimationToken = nil
                }
                .id(token)
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if exitState == nil,
               voidFlashKind == nil,
               cutReveal == nil,
               (surface == .play || surface == .downCard),
               !isPendingRedeal(p),
               proposeRedealAllowed(for: p)
            {
                proposeRedealFooter(
                    gameId: gameId,
                    p: p,
                    feedbackText: $feedbackText,
                    feedbackIsError: $feedbackIsError
                )
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(GinRummyPalette.bgDeep.opacity(0.96))
            }
        }
        .onAppear {
            mergeHandOrder(with: p.hands[p.seat])
            chatMessages = []
            chatOpponentUserId = nil
            chatWatermarkIso = nil
            chatBaselineLoaded = false
            chatToasts = []
            chatUnreadCount = 0
            chatBaselineTask?.cancel()
            chatBaselineTask = nil
            /* Don't restart polling while leaving or on the post-leave screen — a
             * perspective refresh during that window was dropping the overlay and
             * letting the player keep acting on a game they had already forfeited. */
            guard exitState == nil else { return }
            pollTask?.cancel()
            pollTask = Task { await pollLoop(gameId: gameId) }
            connectGameSignals(gameId: gameId)
        }
        .onChange(of: gameContentObservation(p)) { old, new in
            if old.hand != new.hand {
                if let s = selectedHandCard, !new.hand.contains(s) { selectedHandCard = nil }
                mergeHandOrder(with: new.hand)
            }
            if old.hasLastCut, !new.hasLastCut {
                cutRevealTask?.cancel()
                cutReveal = nil
            }
            if old.phase != new.phase {
                // Entering an end-of-hand phase: any lingering cut reveal is stale
                // and would otherwise hide the knock-layoff and result surfaces.
                if new.phase == "knockLayoff" || new.phase == "handOver" || new.phase == "matchOver" {
                    cutRevealTask?.cancel()
                    cutReveal = nil
                }
                if new.phase != "matchOver" {
                    showMatchSummaryAfterReveal = false
                    rematchStatus = nil
                    rematchLocalReady = false
                }
            }
        }
    }

    /// Stable identity for one hand's reveal so polling re-renders don't restart the sequence.
    private func handRevealIdentity(_ hr: HandResultDTO) -> String {
        let cards = hr.sides.flatMap { $0.melds.flatMap(\.cards) + $0.deadwood }.joined(separator: ",")
        return "\(hr.kind)-\(hr.winner)-\(hr.points)-\(cards)"
    }

    private func submitLayoffResolve(
        gameId: String,
        ownMelds: [MeldSolver.Meld],
        layoffs: [(card: String, meldIndex: Int)]
    ) async {
        let intent: [String: Any] = [
            "type": "layoffResolve",
            "ownMelds": ownMelds.map { ["type": $0.dtoType, "cards": $0.cards] },
            "layoffs": layoffs.map { ["card": $0.card, "meldIndex": $0.meldIndex] },
        ]
        await send(
            gameId: gameId,
            token: app.accessToken,
            intent: intent,
            success: "Layoffs locked in.",
            feedbackText: $feedbackText,
            feedbackIsError: $feedbackIsError
        )
    }

    private func cardName(_ raw: String) -> String { GameNarration.cardName(raw) }

    private static let opponentDeclinedDownCardMessage = "Opponent declined the down card."

    private func willStartPostCutSequence(before: PlayerPerspective?, after: PlayerPerspective) -> Bool {
        guard let b = before else { return false }
        return b.cut != nil && after.cut == nil && after.lastCut != nil && b.lastCut == nil
    }

    private func shouldDeferDealerDeclineHint(after: PlayerPerspective) -> Bool {
        after.phase == "upcardOffer"
            && after.upcardOffer?.stage == "dealer"
            && after.upcardOffer?.nonDealerPassed == true
            && after.seat == after.dealer
            && after.currentTurn == after.seat
    }

    /// Starts the full-screen cut reveal the moment the cut resolves. Returns
    /// `true` if it began one (so the caller skips the per-frame flight/status
    /// diffing). The reveal owns the screen until it finishes, so the down-card
    /// stage can never flash underneath.
    @discardableResult
    private func maybeBeginCutReveal(before: PlayerPerspective?, after: PlayerPerspective) -> Bool {
        guard let last = after.lastCut else { return false }
        let key = cutKey(last)
        guard revealedCutKey != key else { return false }
        // Only fire on the transition into "cut just resolved": a prior snapshot
        // existed and had no cut result yet. This avoids replaying the reveal
        // when a player reconnects mid first-hand (where `before` is nil).
        guard let b = before, b.lastCut == nil else { return false }

        let youPickedFirst = b.cut != nil && b.cut?.theirCut == nil
        cutRevealTask?.cancel()
        cutReveal = CutRevealModel(
            last: last,
            youAreSeat: after.seat,
            staged: youPickedFirst,
            deferDealerDeclineHint: shouldDeferDealerDeclineHint(after: after)
        )
        return true
    }

    /// Called by `CutRevealView` once its staged animation completes (or the
    /// player taps to continue). Releases the screen to the down-card stage.
    private func finishCutReveal() {
        guard let model = cutReveal else { return }
        cutRevealTask?.cancel()
        revealedCutKey = cutKey(model.last)
        withAnimation(.easeInOut(duration: 0.3)) { cutReveal = nil }
        // First hand of the match: the deal flourish plays once the cut clears.
        if app.lastPerspective?.phase == "upcardOffer" {
            dealAnimationToken = UUID()
        }
        if model.deferDealerDeclineHint {
            downCardStatusMessage = Self.opponentDeclinedDownCardMessage
            messageTask?.cancel()
            messageTask = Task { @MainActor in
                try? await Task.sleep(nanoseconds: 5_500_000_000)
                if downCardStatusMessage == Self.opponentDeclinedDownCardMessage {
                    downCardStatusMessage = nil
                }
            }
        }
    }

    /// A fresh 10-card deal just landed (next hand or redeal) — play the deal flourish.
    /// Reconnects (`before == nil`) never animate.
    private func detectNewDeal(before: PlayerPerspective?, after: PlayerPerspective) {
        guard let b = before else { return }
        guard after.phase == "upcardOffer", b.phase != "upcardOffer" else { return }
        dealAnimationToken = UUID()
    }

    /// Track the card that just entered your hand so the fan can glow it briefly.
    private func detectMyDraw(before: PlayerPerspective?, after: PlayerPerspective) {
        guard let b = before else { return }
        let my = after.seat
        if b.hands[my].count == 10, after.hands[my].count == 11,
           let added = after.hands[my].first(where: { !b.hands[my].contains($0) })
        {
            let n = CardIdValidation.normalize(added)
            guard CardIdValidation.isValidFormat(n) else { return }
            recentlyDrawnCard = added
            drawnHighlightClearTask?.cancel()
            drawnHighlightClearTask = Task { @MainActor in
                try? await Task.sleep(nanoseconds: 3_500_000_000)
                if !Task.isCancelled, recentlyDrawnCard == added {
                    withAnimation(.easeOut(duration: 0.3)) { recentlyDrawnCard = nil }
                }
            }
        } else if after.hands[my].count != 11 {
            recentlyDrawnCard = nil
        }
    }

    private func detectRedealCompletion(before: PlayerPerspective?, after: PlayerPerspective) {
        guard let b = before else { return }
        guard b.redeal?.status == "pending" else { return }
        guard after.redeal == nil else { return }
        guard after.phase == "upcardOffer" else { return }
        guard b.phase != "handOver" else { return }
        triggerVoidFlash(.redeal)
    }

    private func detectPlayedThroughVoid(before: PlayerPerspective?, after: PlayerPerspective) {
        guard after.voidFlash == "playedThrough" else { return }
        guard before?.voidFlash != "playedThrough" else { return }
        guard after.phase == "upcardOffer" else { return }
        triggerVoidFlash(.playedThrough)
    }

    private func triggerVoidFlash(_ kind: HandVoidFlashKind) {
        redealFlashTask?.cancel()
        voidFlashKind = kind
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        redealFlashTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: Self.redealFlashDurationNs)
            if Task.isCancelled { return }
            voidFlashKind = nil
        }
    }

    private func triggerRedealFlash() {
        triggerVoidFlash(.redeal)
    }

    private func detectDownCardStateForDealer(before: PlayerPerspective?, after: PlayerPerspective) {
        if willStartPostCutSequence(before: before, after: after) { return }
        guard let b = before else { return }
        guard after.phase == "upcardOffer",
              after.upcardOffer?.stage == "dealer",
              after.upcardOffer?.nonDealerPassed == true,
              after.seat == after.dealer,
              after.currentTurn == after.seat
        else { return }
        let enteredDealerStage = b.phase != "upcardOffer" || b.upcardOffer?.stage != "dealer"
        guard enteredDealerStage else { return }
        downCardStatusMessage = Self.opponentDeclinedDownCardMessage
        messageTask?.cancel()
        messageTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 5_500_000_000)
            if downCardStatusMessage == Self.opponentDeclinedDownCardMessage {
                downCardStatusMessage = nil
            }
        }
    }

    private func consolidatedStatusLine(before b: PlayerPerspective, after a: PlayerPerspective) -> String? {
        let my = a.seat
        let opp = 1 - my

        func who(_ seat: Int) -> String { seat == my ? "You" : "Opponent" }
        func actionBackTo(_ seat: Int) -> String { seat == my ? "You" : "Opponent" }

        func opponentDiscardedPickupLine(for discarded: String) -> String {
            defer {
                lastOpponentPickup = nil
                stockCountAfterOurDiscardEndsTurn = nil
            }

            switch lastOpponentPickup {
            case .deck:
                return "This hand · Opponent discarded \(cardName(discarded)) after drawing from the deck"
            case let .discard(c):
                let what = c.isEmpty ? "from the discard pile" : "\(cardName(c)) from the discard pile"
                return "This hand · Opponent discarded \(cardName(discarded)) after drawing \(what)"
            case .downCard:
                return "This hand · Opponent discarded \(cardName(discarded)) after taking the down card"
            case .none:
                break
            }

            // Poll often skips the opponent’s 10→11 draw transition; comparing only (before,after) stock
            // mid-turn falsely looks like “no deck draw”. Baseline was captured when they became active.
            if let baseline = stockCountAfterOurDiscardEndsTurn {
                if b.stockCount < baseline {
                    return "This hand · Opponent discarded \(cardName(discarded)) after drawing from the deck"
                }
                // Stock never dipped vs our post-discard snapshot ⇒ they lifted the face-up discard. We skipped
                // their 10→11 poll, so naming the lifted card isn't reliable (discard top mid-turn differs).
                return "This hand · Opponent discarded \(cardName(discarded)) after drawing from the discard pile"
            }

            // Legacy heuristic (baseline missing): stock drop across the snapshots we happened to observe.
            if b.stockCount > a.stockCount {
                return "This hand · Opponent discarded \(cardName(discarded)) after drawing from the deck"
            }
            let drawn = b.discard.last ?? ""
            if drawn.isEmpty {
                return "This hand · Opponent discarded \(cardName(discarded)) after drawing from the discard pile"
            }
            return "This hand · Opponent discarded \(cardName(discarded)) after drawing \(cardName(drawn)) from the discard pile"
        }

        // --- Down card phase ---
        if b.phase != "upcardOffer", a.phase == "upcardOffer" {
            return a.currentTurn == my
                ? "This hand · Down card — your turn"
                : "This hand · Down card — opponent’s turn"
        }

        // First chooser rejects -> option passes to other.
        if b.phase == "upcardOffer", a.phase == "upcardOffer",
           b.upcardOffer?.stage == "nonDealer",
           a.upcardOffer?.stage == "dealer",
           b.currentTurn != a.currentTurn
        {
            let decliner = b.currentTurn == my ? "You" : "Opponent"
            let other = a.currentTurn == my ? "You" : "Opponent"
            return "This hand · \(decliner) passed the down card — \(other) chooses next"
        }

        // Second chooser rejects -> action back to first chooser (draw from deck).
        if b.phase == "upcardOffer", a.phase == "play",
           b.upcardOffer?.stage == "dealer",
           b.upcardOffer?.nonDealerPassed == true,
           a.currentTurn == a.nonDealer
        {
            let decliner = b.currentTurn == my ? "You" : "Opponent"
            return "This hand · \(decliner) passed — \(actionBackTo(a.currentTurn)) leads from the deck"
        }

        // Someone accepts down card -> enter play, same player to discard.
        if b.phase == "upcardOffer", a.phase == "play",
           b.currentTurn == a.currentTurn
        {
            let accepterSeat = a.currentTurn
            // Accepting the down card removes the up-card from the discard pile.
            if a.discard.count < b.discard.count {
                if accepterSeat == my {
                    lastYouPickup = .downCard
                    youAcceptedDownCardPendingDiscard = true
                } else {
                    lastOpponentPickup = .downCard
                    opponentAcceptedDownCardPendingDiscard = true
                }
                return "This hand · \(who(accepterSeat)) took the down card"
            }
            // If the discard pile didn't shrink, then this wasn't an "accept" — it's the non-dealer drawing from stock
            // after both players passed. Track that as a deck pickup for the upcoming discard.
            if b.stockCount > a.stockCount {
                if accepterSeat == my { lastYouPickup = .deck } else { lastOpponentPickup = .deck }
            }
            youAcceptedDownCardPendingDiscard = false
            opponentAcceptedDownCardPendingDiscard = false
            return nil
        }

        // --- Track draws in normal play (used later when summarizing discards) ---
        if b.phase == "play", a.phase == "play" {
            // You drew (10 -> 11)
            if b.currentTurn == my, a.currentTurn == my,
               b.hands[my].count == 10, a.hands[my].count == 11
            {
                if b.stockCount > a.stockCount {
                    lastYouPickup = .deck
                } else if a.discard.count < b.discard.count {
                    let top = b.discard.last ?? ""
                    lastYouPickup = top.isEmpty ? .discard(card: "") : .discard(card: top)
                }
            }
            // Opponent drew (10 -> 11)
            if b.currentTurn == opp, a.currentTurn == opp,
               b.hands[opp].count == 10, a.hands[opp].count == 11
            {
                if b.stockCount > a.stockCount {
                    lastOpponentPickup = .deck
                } else if a.discard.count < b.discard.count {
                    let top = b.discard.last ?? ""
                    lastOpponentPickup = top.isEmpty ? .discard(card: "") : .discard(card: top)
                }
            }
        }

        // --- Your discard (end of your turn) ---
        if b.phase == "play", a.phase == "play",
           b.currentTurn == my, a.currentTurn == opp,
           b.hands[my].count == 11, a.hands[my].count == 10,
           let discarded = a.discard.last, !discarded.isEmpty, discarded != b.discard.last
        {
            // Beginning a fresh opponent turn: stale pickup state would mis-attribute this turn.
            lastOpponentPickup = nil
            // Stockpile size after our discard resolves; opponent deck draw lowers this vs this baseline mid-turn.
            stockCountAfterOurDiscardEndsTurn = a.stockCount

            if youAcceptedDownCardPendingDiscard {
                youAcceptedDownCardPendingDiscard = false
                lastYouPickup = nil
                return "This hand · You discarded \(cardName(discarded)) after taking the down card"
            }
            let src = lastYouPickup
            lastYouPickup = nil
            switch src {
            case .deck:
                return "This hand · You discarded \(cardName(discarded)) after drawing from the deck"
            case .discard(let c):
                let what = c.isEmpty ? "the discard pile" : cardName(c)
                return "This hand · You discarded \(cardName(discarded)) after taking \(what) from the discard pile"
            case .downCard:
                return "This hand · You discarded \(cardName(discarded)) after taking the down card"
            case .none:
                return "This hand · You discarded \(cardName(discarded))"
            }
        }

        // --- Opponent discard (end of opponent turn) ---
        // Normal case: turn flips from other seat -> you.
        //
        // Collapsed case (common vs server-side bot): your discard API returns only after the opponent has already
        // drawn + discarded, so `before` can still show YOUR turn (11 cards) and `after` YOUR turn (10 cards).
        // Then `before.currentTurn == opponent` never appears on the client — detect via hand size + discard depth.

        if b.phase == "play", a.phase == "play",
           b.currentTurn == my, a.currentTurn == my,
           b.hands[my].count == 11, a.hands[my].count == 10,
           let discarded = a.discard.last, !discarded.isEmpty
        {
            // Prefer accurate pickup info when we actually saw opponent 10→11; do not use stock baseline alone here
            // (baseline can linger across unrelated transitions when both snapshots still look like "your" turn).
            if lastOpponentPickup != nil {
                return opponentDiscardedPickupLine(for: discarded)
            }
            let dc = a.discard.count - b.discard.count
            // After your discard only: +1. Opponent draws from stock then discards: +2 vs snapshot before you discarded.
            // Opponent takes discard then discards: net +1 vs that snapshot.
            if b.stockCount > a.stockCount || dc >= 2 {
                lastOpponentPickup = nil
                stockCountAfterOurDiscardEndsTurn = nil
                return "This hand · Opponent discarded \(cardName(discarded)) after drawing from the deck"
            }
            lastOpponentPickup = nil
            stockCountAfterOurDiscardEndsTurn = nil
            return "This hand · Opponent discarded \(cardName(discarded)) after drawing from the discard pile"
        }

        if b.phase == "play", a.phase == "play",
           b.currentTurn != my, a.currentTurn == my,
           let discarded = a.discard.last, !discarded.isEmpty
        {
            return opponentDiscardedPickupLine(for: discarded)
        }

        return nil
    }

    private func scheduleOpponentTurnBanner(text _: String, card _: String?) {}

    private func turnLine(_ p: PlayerPerspective) -> String { GameNarration.turnLine(p) }

    private func downCardStageTitle(_ p: PlayerPerspective) -> String {
        if downCardStatusMessage == Self.opponentDeclinedDownCardMessage {
            return p.currentTurn == p.seat
                ? "Your turn — take or pass the up card"
                : "Waiting on opponent (down card)"
        }
        return p.currentTurn == p.seat
            ? "Your turn — take or pass the up card"
            : "Waiting on opponent (down card)"
    }

    private func cutStageTitle(_ p: PlayerPerspective) -> String { GameNarration.cutStageTitle(p) }

    private func knockLayoffLine(_ p: PlayerPerspective, k: PlayerPerspective.KnockPerspective) -> String {
        GameNarration.knockLayoffLine(p, k: k)
    }

    /// Scoreboard strip only — opponent hand is hidden during play (count only).
    @ViewBuilder
    private func opponentPresenceStrip(p: PlayerPerspective) -> some View {
        let oppSeat = 1 - p.seat
        HStack(spacing: 14) {
            Image(systemName: "person.crop.circle.fill")
                .font(.title2)
                .foregroundStyle(GinRummyPalette.gold.opacity(0.9))
                .symbolRenderingMode(.hierarchical)
            VStack(alignment: .leading, spacing: 4) {
                Text("Opponent")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(GinRummyPalette.cream)
                HStack(spacing: 8) {
                    Text("Cards")
                        .font(.caption2)
                        .foregroundStyle(GinRummyPalette.sage.opacity(0.9))
                    Text("\(p.hands[oppSeat].count)")
                        .font(.caption.bold().monospacedDigit())
                        .foregroundStyle(GinRummyPalette.gold)
                    Text("· Points \(p.scores[oppSeat])")
                        .font(.caption2)
                        .foregroundStyle(GinRummyPalette.sage.opacity(0.9))
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func youHandBlock(
        surface: GamePlaySurface,
        p: PlayerPerspective,
        selectedHandCard: Binding<String?>
    ) -> some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Image(systemName: "person.fill")
                        .foregroundStyle(GinRummyPalette.gold)
                    Text("YOU")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(GinRummyPalette.cream)
                }
                FannedHandRow(
                    displayOrder: handDisplayFor(hand: p.hands[p.seat]),
                    selected: selectedHandCard,
                    canReorder: canReorderHand(for: surface),
                    onReorder: { handDisplayOrder = $0 }
                )
            }
            Spacer(minLength: 0)
        }
    }

    /// Play or down-card: tap the face-up discard when take is legal.
    private func discardTapActionIfEnabled(gameId: String, p: PlayerPerspective) -> (() -> Void)? {
        takeDiscardActionIfEnabled(gameId: gameId, p: p)
            ?? takeUpcardActionIfEnabled(gameId: gameId, p: p)
    }

    /// Play: take top discard on your turn with 10 cards.
    private func takeDiscardActionIfEnabled(gameId: String, p: PlayerPerspective) -> (() -> Void)? {
        guard p.phase == "play",
              p.currentTurn == p.seat,
              p.hands[p.seat].count == 10,
              let top = p.discard.last, !top.isEmpty
        else { return nil }
        return {
            Task {
                await send(
                    gameId: gameId,
                    token: app.accessToken,
                    intent: ["type": "takeDiscard"],
                    success: "Took discard.",
                    feedbackText: $feedbackText,
                    feedbackIsError: $feedbackIsError
                )
            }
        }
    }

    /// Down card: take the up-card on your turn (same as the Take button).
    private func takeUpcardActionIfEnabled(gameId: String, p: PlayerPerspective) -> (() -> Void)? {
        guard p.phase == "upcardOffer",
              p.currentTurn == p.seat,
              let top = p.discard.last, !top.isEmpty
        else { return nil }
        return { performUpcardTake(gameId: gameId) }
    }

    private func performUpcardTake(gameId: String) {
        downCardStatusMessage = "You Drew Down Card"
        Task {
            await send(
                gameId: gameId,
                token: app.accessToken,
                intent: ["type": "upcardTake"],
                success: "You Drew Down Card",
                feedbackText: $feedbackText,
                feedbackIsError: $feedbackIsError
            )
        }
    }

    private func drawStockActionIfEnabled(gameId: String, p: PlayerPerspective) -> (() -> Void)? {
        if p.phase == "play",
           p.currentTurn == p.seat,
           p.hands[p.seat].count == 10,
           p.stockCount > 1 {
            return {
                Task {
                    await send(
                        gameId: gameId,
                        token: app.accessToken,
                        intent: ["type": "drawStock"],
                        success: "Drew from Deck.",
                        feedbackText: $feedbackText,
                        feedbackIsError: $feedbackIsError
                    )
                }
            }
        }
        // While the dealer is deciding on the down card it is not the non-dealer's
        // turn — the server rejects early deck draws, so no button is offered here.
        return nil
    }

    @ViewBuilder
    private func chatToastStack() -> some View {
        VStack(alignment: .trailing, spacing: 8) {
            ForEach(chatToasts) { toast in
                Text(toast.text)
                    .font(.subheadline.weight(.medium))
                    .multilineTextAlignment(.trailing)
                    .lineLimit(3)
                    .foregroundStyle(.primary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10))
                    .shadow(color: .black.opacity(0.12), radius: 5, y: 2)
                    .transition(.asymmetric(
                        insertion: .move(edge: .trailing).combined(with: .opacity),
                        removal: .opacity
                    ))
            }
        }
        .animation(.spring(response: 0.38, dampingFraction: 0.82), value: chatToasts.map(\.id))
    }

    private func scheduleChatBaselineLoadOnce(gameId: String) {
        guard !chatBaselineLoaded else { return }
        guard chatBaselineTask == nil else { return }
        chatBaselineTask = Task { await loadChatBaseline(gameId: gameId) }
    }

    private func loadChatBaseline(gameId: String) async {
        guard let token = await MainActor.run(body: { app.accessToken }) else { return }
        do {
            let r = try await app.api.fetchGameChat(gameId: gameId, token: token, after: nil)
            await MainActor.run {
                if let opp = r.messages.first(where: { !$0.fromSelf }) {
                    chatOpponentUserId = opp.userId
                }
                chatMessages = r.messages
                    .filter { !app.isBlocked($0.userId) }
                    .sorted { $0.createdAt < $1.createdAt }
                chatWatermarkIso = chatMessages.map(\.createdAt).max() ?? Self.chatEpochIso
                chatBaselineLoaded = true
            }
        } catch {
            await MainActor.run {
                chatBaselineLoaded = true
                chatWatermarkIso = Self.chatEpochIso
            }
        }
    }

    private func fetchAndMergeChatFromPoll(gameId: String, token: String) async {
        let loaded = await MainActor.run { chatBaselineLoaded }
        guard loaded else { return }
        let after = await MainActor.run { chatWatermarkIso } ?? Self.chatEpochIso
        let sheetOpen = await MainActor.run { showChatSheet }
        do {
            let r = try await app.api.fetchGameChat(gameId: gameId, token: token, after: after)
            await MainActor.run {
                var known = Set(chatMessages.map(\.id))
                var receivedIncoming = false
                for m in r.messages {
                    guard !known.contains(m.id) else { continue }
                    if !m.fromSelf, chatOpponentUserId == nil {
                        chatOpponentUserId = m.userId
                    }
                    guard !app.isBlocked(m.userId) else { continue }
                    known.insert(m.id)
                    chatMessages.append(m)
                    if !m.fromSelf {
                        receivedIncoming = true
                        if !sheetOpen {
                            chatUnreadCount += 1
                            enqueueChatToast(for: m)
                        }
                    }
                }
                chatMessages.sort { $0.createdAt < $1.createdAt }
                chatWatermarkIso = chatMessages.map(\.createdAt).max() ?? Self.chatEpochIso
                if receivedIncoming {
                    // Full device vibration (like an incoming text), once per poll batch.
                    AudioServicesPlaySystemSound(kSystemSoundID_Vibrate)
                }
            }
        } catch {}
    }

    private func enqueueChatToast(for message: GameChatMessageDTO) {
        let snippet =
            message.body.count > 100 ? String(message.body.prefix(100)) + "…" : message.body
        let item = ChatToastItem(
            id: message.id,
            text: "\(message.displayName): \(snippet)"
        )
        withAnimation {
            chatToasts.append(item)
        }
        Task {
            try? await Task.sleep(nanoseconds: 3_200_000_000)
            await MainActor.run {
                withAnimation {
                    chatToasts.removeAll { $0.id == message.id }
                }
            }
        }
    }

    private func exitStateForAbandonment(leftBySeat: Int?, mySeat: Int) -> GameExitState {
        switch GameTablePolicy.exitStateForAbandonment(leftBySeat: leftBySeat, mySeat: mySeat) {
        case "youLeft": return .youLeft
        default: return .opponentLeft
        }
    }

    private func toggleRematchReady(code: String) async {
        guard let token = app.accessToken else { return }
        await MainActor.run {
            rematchBusy = true
            rematchLocalReady = true
        }
        defer { Task { @MainActor in rematchBusy = false } }
        do {
            let status = try await app.api.setLobbyReady(code: code.uppercased(), token: token, ready: true)
            await MainActor.run {
                if let me = status.players.first(where: { $0.isSelf }) {
                    rematchLocalReady = me.ready
                }
            }
            if let nextId = status.gameIdToEnter {
                await transitionToRematchGame(gameId: nextId, token: token)
            }
        } catch {
            await MainActor.run {
                rematchLocalReady = false
                setFeedback(UserFeedback.from(error), error: true)
            }
        }
    }

    private func transitionToRematchGame(gameId: String, token: String) async {
        let stillOnCompleted = await MainActor.run { app.activeGameId != nil }
        guard stillOnCompleted else { return }
        do {
            let st = try await app.api.gameState(gameId: gameId, token: token)
            await MainActor.run {
                pollTask?.cancel()
                cutRevealTask?.cancel()
                cardFlightClearTask?.cancel()
                messageTask?.cancel()
                showMatchSummaryAfterReveal = false
                rematchStatus = nil
                rematchLocalReady = false
                rematchBusy = false
                sessionLobbyCode = nil
                selectedHandCard = nil
                handDisplayOrder = []
                chatMessages = []
                chatOpponentUserId = nil
                chatWatermarkIso = nil
                chatBaselineLoaded = false
                chatToasts = []
                chatUnreadCount = 0
                app.applyGameTableState(
                    perspective: st.perspective,
                    betting: st.betting,
                    opponentDisplayName: st.opponentDisplayName
                )
                app.activeGameId = gameId
            }
            await MainActor.run {
                pollTask = Task { await pollLoop(gameId: gameId) }
                connectGameSignals(gameId: gameId)
            }
        } catch {
            await MainActor.run {
                app.activeGameId = gameId
                pollTask?.cancel()
                pollTask = Task { await pollLoop(gameId: gameId) }
                connectGameSignals(gameId: gameId)
            }
        }
    }

    private func pollLoop(gameId: String) async {
        while !Task.isCancelled {
            /* Re-read the token each iteration so a background refresh's new access_token
             * is picked up automatically; otherwise the loop would hold a stale token. */
            guard let token = app.accessToken else {
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                continue
            }
            /* Correct-game guard: if the active game changed under this loop (player
             * left for another table), stop applying stale snapshots immediately. */
            guard await MainActor.run(body: { app.activeGameId == gameId }) else { return }
            do {
                let s = try await app.api.gameState(gameId: gameId, token: token)
                let gameWasAbandoned = await MainActor.run {
                    applyAbandonmentIfNeeded(s, gameId: gameId)
                }
                if gameWasAbandoned { return }
                await MainActor.run {
                    applyRemoteGameState(s, gameId: gameId)
                }
                await fetchAndMergeChatFromPoll(gameId: gameId, token: token)
            } catch {
                if let recoveryToken = app.accessToken,
                   let s = try? await app.api.gameState(gameId: gameId, token: recoveryToken)
                {
                    let abandoned = await MainActor.run {
                        applyAbandonmentIfNeeded(s, gameId: gameId)
                    }
                    if abandoned { return }
                }
                await MainActor.run { setFeedback(UserFeedback.from(error), error: true) }
            }
            try? await Task.sleep(nanoseconds: Self.pollIntervalNs)
        }
    }

    private func mergeHandOrder(with newHand: [String]) {
        if newHand.isEmpty { handDisplayOrder = []; return }
        if handDisplayOrder.isEmpty {
            handDisplayOrder = PlayingCard.sortHand(newHand)
            return
        }
        var merged = handDisplayOrder.filter { newHand.contains($0) }
        for c in newHand where !merged.contains(c) { merged.append(c) }
        if merged.count != newHand.count || Set(merged) != Set(newHand) {
            handDisplayOrder = PlayingCard.sortHand(newHand)
            return
        }
        handDisplayOrder = merged
    }

    private func handDisplayFor(hand rawHand: [String]) -> [String] {
        // Drop the optimistically-discarded card so the fan reflects the discard the instant it's released.
        let hand = pendingDiscardCard.map { pending in rawHand.filter { $0 != pending } } ?? rawHand
        if hand.isEmpty { return [] }
        if handDisplayOrder.isEmpty { return PlayingCard.sortHand(hand) }
        if hand.count == handDisplayOrder.count, Set(hand) == Set(handDisplayOrder) { return handDisplayOrder }
        return handDisplayOrder.filter { hand.contains($0) } + hand.filter { !handDisplayOrder.contains($0) }
    }

    @ViewBuilder
    private func moveButtons(
        gameId: String,
        surface: GamePlaySurface,
        p: PlayerPerspective,
        feedbackText: Binding<String>,
        feedbackIsError: Binding<Bool>,
        selectedHandCard: Binding<String?>
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Group {
                switch surface {
                case .postCutReveal:
                    EmptyView()
                case .matchOver:
                    if showMatchSummaryAfterReveal, let rematch = rematchStatus {
                        RematchReadyFooter(
                            rematch: rematch,
                            opponentName: app.opponentDisplayName,
                            youTappedPlayAgain: rematchLocalReady,
                            busy: rematchBusy,
                            onPlayAgain: {
                                Task { await toggleRematchReady(code: rematch.lobbyInviteCode) }
                            }
                        )
                    }
                    if sessionLobbyCode != nil {
                        Button("Scorecard") {
                            showScorecard = true
                        }
                        .buttonStyle(GinActionButtonStyle(filled: false, tint: GinRummyPalette.gold))
                    }
                    Button("Return to lobby") {
                        pollTask?.cancel()
                        cutRevealTask?.cancel()
                        cardFlightClearTask?.cancel()
                        messageTask?.cancel()
                        app.clearActiveGame()
                    }
                    .buttonStyle(GinActionButtonStyle(filled: true))
                case .cutForDeal:
                    // Cut actions live in CutForDealView (center table).
                    EmptyView()
                case .downCard:
                    upcardButtons(
                        gameId: gameId,
                        p: p,
                        token: app.accessToken,
                        feedbackText: feedbackText,
                        feedbackIsError: feedbackIsError
                    )
                case .play:
                    if p.currentTurn == p.seat {
                        playButtons(
                            gameId: gameId,
                            p: p,
                            token: app.accessToken,
                            feedbackText: feedbackText,
                            feedbackIsError: feedbackIsError,
                            selectedHandCard: selectedHandCard
                        )
                    } else {
                        EmptyView()
                    }
                case .knockLayoff:
                    /* Done lives inside LayoffArrangementView — only the redeal footer renders here. */
                    EmptyView()
                case .handOver:
                    Button("Continue") {
                        Task {
                            await send(
                                gameId: gameId,
                                token: app.accessToken,
                                intent: ["type": "ackHandOver"],
                                success: "Hand acknowledged.",
                                feedbackText: feedbackText,
                                feedbackIsError: feedbackIsError
                            )
                        }
                    }
                    .buttonStyle(GinActionButtonStyle(filled: true, tint: GinRummyPalette.navy))
                }
            }
        }
    }

    @ViewBuilder
    private func proposeRedealFooter(
        gameId: String,
        p: PlayerPerspective,
        feedbackText: Binding<String>,
        feedbackIsError: Binding<Bool>
    ) -> some View {
        Button("Propose redeal") {
            Task {
                await send(
                    gameId: gameId,
                    token: app.accessToken,
                    intent: ["type": "proposeRedeal"],
                    success: "Redeal proposed — waiting on opponent.",
                    feedbackText: feedbackText,
                    feedbackIsError: feedbackIsError
                )
            }
        }
        .buttonStyle(GinActionButtonStyle(filled: false, tint: GinRummyPalette.gold))
    }

    @ViewBuilder
    private func pendingRedealOverlay(
        gameId: String,
        p: PlayerPerspective,
        feedbackText: Binding<String>,
        feedbackIsError: Binding<Bool>
    ) -> some View {
        if let r = p.redeal, r.status == "pending" {
            let opp = app.opponentDisplayName
            let youProposed = r.fromSeat == p.seat
            ZStack {
            Color.black.opacity(0.55)
                .ignoresSafeArea()
            VStack(spacing: 18) {
                Image(systemName: "arrow.triangle.2.circlepath")
                    .font(.system(size: 44))
                    .foregroundStyle(GinRummyPalette.gold)
                Text(youProposed ? "Redeal proposed" : "\(opp) proposed a redeal")
                    .font(.title3.weight(.bold))
                    .foregroundStyle(GinRummyPalette.cream)
                    .multilineTextAlignment(.center)
                Text(
                    youProposed
                        ? "Waiting for \(opp) to accept or decline. You can cancel if you changed your mind."
                        : "Accept to shuffle and re-deal this hand with the same score, or decline to keep playing."
                )
                .font(.subheadline)
                .foregroundStyle(GinRummyPalette.sage.opacity(0.95))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 8)

                if youProposed {
                    Button("Cancel proposal") {
                        Task {
                            await send(
                                gameId: gameId,
                                token: app.accessToken,
                                intent: ["type": "cancelRedeal"],
                                success: "Redeal proposal withdrawn.",
                                feedbackText: feedbackText,
                                feedbackIsError: feedbackIsError
                            )
                        }
                    }
                    .buttonStyle(GinActionButtonStyle(filled: true, tint: GinRummyPalette.burgundy))
                } else {
                    HStack(spacing: 12) {
                        Button {
                            Task {
                                await send(
                                    gameId: gameId,
                                    token: app.accessToken,
                                    intent: ["type": "respondRedeal", "accept": true],
                                    success: "Redeal accepted.",
                                    feedbackText: feedbackText,
                                    feedbackIsError: feedbackIsError
                                )
                            }
                        } label: {
                            Label("Accept", systemImage: "checkmark.circle.fill")
                        }
                        .buttonStyle(GinActionButtonStyle(filled: true, tint: Color(red: 0.18, green: 0.5, blue: 0.3)))

                        Button {
                            Task {
                                await send(
                                    gameId: gameId,
                                    token: app.accessToken,
                                    intent: ["type": "respondRedeal", "accept": false],
                                    success: "Redeal declined.",
                                    feedbackText: feedbackText,
                                    feedbackIsError: feedbackIsError
                                )
                            }
                        } label: {
                            Label("Decline", systemImage: "xmark.circle.fill")
                        }
                        .buttonStyle(GinActionButtonStyle(filled: false, tint: GinRummyPalette.gold))
                    }
                }
            }
            .padding(24)
            .frame(maxWidth: 360)
            .background(
                RoundedRectangle(cornerRadius: 20)
                    .fill(GinRummyPalette.navy.opacity(0.96))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 20)
                    .stroke(GinRummyPalette.gold.opacity(0.45), lineWidth: 1.2)
            )
            .shadow(color: .black.opacity(0.4), radius: 20, y: 10)
            .padding(.horizontal, 20)
            }
        }
    }

    @ViewBuilder
    private func redealProposalBanner(
        gameId: String,
        p: PlayerPerspective,
        feedbackText: Binding<String>,
        feedbackIsError: Binding<Bool>
    ) -> some View {
        if let r = p.redeal, r.status == "declined" {
            let opp = app.opponentDisplayName
            VStack(alignment: .leading, spacing: 10) {
                if r.fromSeat == p.seat {
                    Label("\(opp) declined the redeal", systemImage: "xmark.circle")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(GinRummyPalette.cream)
                    Text("Keep playing — or propose again after your next move.")
                        .font(.caption2)
                        .foregroundStyle(GinRummyPalette.sage.opacity(0.9))
                } else {
                    Label("You declined the redeal", systemImage: "hand.thumbsdown.fill")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(GinRummyPalette.cream)
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(GinRummyPalette.navy.opacity(0.92))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(GinRummyPalette.gold.opacity(0.35), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.25), radius: 10, y: 4)
            .transition(.move(edge: .top).combined(with: .opacity))
        }
    }

    /// Banner shown over the table when an invite link arrives mid-game.
    /// Accept (after confirmation) forfeits this game and joins the new lobby;
    /// deny just dismisses the banner.
    @ViewBuilder
    private func inGameInviteBanner() -> some View {
        if let invite = app.inGameInvite {
            VStack(alignment: .leading, spacing: 10) {
                Label("\(invite.hostLabel) invited you to a new game", systemImage: "envelope.badge.fill")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(GinRummyPalette.cream)
                Text("Accepting will end your current game.")
                    .font(.caption)
                    .foregroundStyle(GinRummyPalette.sage.opacity(0.95))
                HStack(spacing: 14) {
                    Button {
                        showAcceptInviteConfirm = true
                    } label: {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.title2)
                            .foregroundStyle(.green.opacity(0.95))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Accept invite")

                    Button {
                        app.dismissInGameInvite()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title2)
                            .foregroundStyle(.red.opacity(0.92))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Deny invite")

                    Spacer(minLength: 0)
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(GinRummyPalette.burgundy.opacity(0.94))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(GinRummyPalette.gold.opacity(0.4), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.25), radius: 10, y: 4)
            .transition(.move(edge: .top).combined(with: .opacity))
        }
    }

    /// Full-table screen shown while leaving, after you left, or after the
    /// opponent abandoned the game.
    @ViewBuilder
    private func gameExitScreen(_ state: GameExitState) -> some View {
        VStack(spacing: 18) {
            Spacer(minLength: 24)
            switch state {
            case .leavingInProgress:
                ProgressView()
                    .controlSize(.large)
                    .tint(GinRummyPalette.gold)
                Text("Leaving the table…")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(GinRummyPalette.cream)
                Text("Letting \(app.opponentDisplayName) know you've left.")
                    .font(.subheadline)
                    .foregroundStyle(GinRummyPalette.sage.opacity(0.95))
                    .multilineTextAlignment(.center)
            case .youLeft:
                Image(systemName: "rectangle.portrait.and.arrow.right")
                    .font(.system(size: 52))
                    .foregroundStyle(GinRummyPalette.gold)
                Text("You left the game")
                    .font(.title2.bold())
                    .foregroundStyle(GinRummyPalette.cream)
                Text("\(app.opponentDisplayName) has been notified. The match ended without a result.")
                    .font(.subheadline)
                    .foregroundStyle(GinRummyPalette.sage.opacity(0.95))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
                Button("Back to main lobby") {
                    app.clearActiveGame()
                }
                .buttonStyle(GinActionButtonStyle(filled: true))
                .padding(.horizontal, 40)
                .padding(.top, 8)
            case .opponentLeft:
                Image(systemName: "figure.walk.departure")
                    .font(.system(size: 52))
                    .foregroundStyle(GinRummyPalette.gold)
                Text("\(app.opponentDisplayName) left the game")
                    .font(.title2.bold())
                    .foregroundStyle(GinRummyPalette.cream)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
                Text("Your opponent walked away from the table, so this match has ended.")
                    .font(.subheadline)
                    .foregroundStyle(GinRummyPalette.sage.opacity(0.95))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
                Button("Back to main lobby") {
                    app.clearActiveGame()
                }
                .buttonStyle(GinActionButtonStyle(filled: true))
                .padding(.horizontal, 40)
                .padding(.top, 8)
            }
            Spacer(minLength: 24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(GinRummyPalette.bgDeep.opacity(0.97))
    }

    private func finishLeaveSuccess(acceptingInvite invite: InGameInvite?) async {
        /* Brief pause so the "leaving the table" visual registers instead of flashing. */
        try? await Task.sleep(nanoseconds: 900_000_000)
        await MainActor.run {
            if invite != nil {
                app.finishInGameInviteAccepted()
            } else {
                exitState = .youLeft
            }
        }
    }

    /// Forfeit the current game. When `acceptingInvite` is non-nil, the new lobby is
    /// joined *first* (so a full/closed lobby never costs you your game), then the
    /// current game is abandoned and the player is handed off to the new waiting room.
    private func leaveCurrentGame(acceptingInvite invite: InGameInvite?) async {
        guard let gid = app.activeGameId, let token = app.accessToken else { return }
        await MainActor.run {
            pollTask?.cancel()
            exitState = .leavingInProgress
        }
        do {
            if let invite {
                try await app.api.joinLobby(code: invite.inviteCode, token: token)
            }
            _ = try await app.api.leaveGame(gameId: gid, token: token)
            await finishLeaveSuccess(acceptingInvite: invite)
        } catch {
            if Task.isCancelled { return }
            /* The leave call is idempotent — a flaky connection may fail after the
             * server already marked the game abandoned. Confirm before reopening play. */
            if let recoveryToken = app.accessToken,
               let s = try? await app.api.gameState(gameId: gid, token: recoveryToken),
               s.status == "abandoned"
            {
                await finishLeaveSuccess(acceptingInvite: invite)
                return
            }
            await MainActor.run {
                exitState = nil
                setFeedback(UserFeedback.from(error), error: true)
                if let activeGid = app.activeGameId {
                    pollTask?.cancel()
                    pollTask = Task { await pollLoop(gameId: activeGid) }
                }
            }
        }
    }

    private func upcardButtons(
        gameId: String,
        p: PlayerPerspective,
        token: String?,
        feedbackText: Binding<String>,
        feedbackIsError: Binding<Bool>
    ) -> some View {
        VStack(spacing: 8) {
            if p.currentTurn == p.seat {
                Text("Take the down card, or pass.")
                    .font(.footnote)
                    .foregroundStyle(GinRummyPalette.sage.opacity(0.95))
                    .frame(maxWidth: .infinity, alignment: .center)

                HStack(spacing: 10) {
                    Button("Take") {
                        performUpcardTake(gameId: gameId)
                    }
                    .buttonStyle(GinActionButtonStyle(filled: true, tint: GinRummyPalette.burgundy))
                    Button("Pass") {
                        downCardStatusMessage = "You Declined Down Card"
                        Task {
                            await send(
                                gameId: gameId,
                                token: token,
                                intent: ["type": "upcardPass"],
                                success: "You Declined Down Card",
                                feedbackText: feedbackText,
                                feedbackIsError: feedbackIsError
                            )
                        }
                    }
                    .buttonStyle(GinActionButtonStyle(filled: false, tint: GinRummyPalette.gold))
                }
            } else {
                Label("Waiting for \(app.opponentDisplayName) on the down card…", systemImage: "hourglass")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(GinRummyPalette.sage)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
            }
        }
    }

    private func playButtons(
        gameId: String,
        p: PlayerPerspective,
        token: String?,
        feedbackText: Binding<String>,
        feedbackIsError: Binding<Bool>,
        selectedHandCard: Binding<String?>
    ) -> some View {
        Group {
            if p.hands[p.seat].count == 10, p.stockCount == 1 {
                VStack(spacing: 8) {
                    Text("One card left in the deck — take the discard or pass.")
                        .font(.footnote)
                        .foregroundStyle(GinRummyPalette.sage.opacity(0.95))
                        .frame(maxWidth: .infinity, alignment: .center)
                    Button("Pass (deck played through)") {
                        Task {
                            await send(
                                gameId: gameId,
                                token: token,
                                intent: ["type": "passStock"],
                                success: "Hand played through — re-dealing.",
                                feedbackText: feedbackText,
                                feedbackIsError: feedbackIsError
                            )
                        }
                    }
                    .buttonStyle(GinActionButtonStyle(filled: true, tint: GinRummyPalette.burgundy))
                }
            } else if p.hands[p.seat].count == 11 {
                let canEO = MeldSolver.isBigGin11(p.hands[p.seat])
                VStack(spacing: 8) {
                if canEO {
                    Button("Declare EO") {
                        Task { await send(gameId: gameId, token: token, intent: ["type": "declareBigGin"], success: "Declared EO.", feedbackText: feedbackText, feedbackIsError: feedbackIsError) }
                    }
                    .buttonStyle(GinActionButtonStyle(filled: true, tint: GinRummyPalette.navy))
                }
                DiscardHelper(
                    gameId: gameId,
                    hand: p.hands[p.seat],
                    knockCheckCard: p.knockCheckCard,
                    token: token,
                    feedbackText: feedbackText,
                    feedbackIsError: feedbackIsError,
                    selectedCard: selectedHandCard,
                    dragDiscardRequest: $dragDiscardRequest,
                    onAfterSuccessfulMove: { before, after in
                        if let b = before {
                            handleAfterPerspectiveUpdate(before: b, after: after)
                        }
                    },
                    onAfterSuccessfulDiscard: nil,
                    onOptimisticDiscard: { beginOptimisticDiscard($0) },
                    onDiscardFailed: {
                        suppressDiscardFlightFor = nil
                        clearPendingDiscard()
                    }
                )
                }
            }
        }
    }

    private func send(
        gameId: String,
        token: String?,
        intent: [String: Any],
        success: String = "Move applied.",
        feedbackText: Binding<String>,
        feedbackIsError: Binding<Bool>
    ) async {
        guard let token else { return }
        let stillInGame = await MainActor.run { exitState == nil }
        guard stillInGame else { return }
        do {
            let r = try await app.api.submitMove(gameId: gameId, token: token, intent: intent)
            await MainActor.run {
                let before = app.lastPerspective
                app.applyGameTableState(
                    perspective: r.perspective,
                    betting: r.betting,
                    opponentDisplayName: r.opponentDisplayName
                )
                let after = r.perspective
                handleAfterPerspectiveUpdate(before: before, after: after)
                feedbackText.wrappedValue = success
                feedbackIsError.wrappedValue = false
            }
        } catch {
            if let recoveryToken = app.accessToken,
               let s = try? await app.api.gameState(gameId: gameId, token: recoveryToken),
               await MainActor.run(body: { applyAbandonmentIfNeeded(s, gameId: gameId) })
            {
                return
            }
            await MainActor.run {
                feedbackText.wrappedValue = UserFeedback.from(error)
                feedbackIsError.wrappedValue = true
            }
        }
    }
}

private struct CutForDealView: View {
    let gameId: String
    let p: PlayerPerspective
    let token: String?
    var onAfterCutPick: ((PlayerPerspective, PlayerPerspective) -> Void)? = nil
    @EnvironmentObject private var app: AppModel
    @Binding var feedbackText: String
    @Binding var feedbackIsError: Bool
    @State private var highlightIndex: Int?
    @State private var busy = false

    var body: some View {
        return VStack(spacing: 20) {
            CutForDealTable(
                p: p,
                highlightIndex: $highlightIndex,
                busy: $busy
            )

            if let cut = p.cut, cut.youMustPick, !busy {
                actionBar(cut: cut)
            }
        }
        .frame(maxWidth: .infinity)
        .onChange(of: p.cut?.youMustPick ?? false) { _, new in
            if new { highlightIndex = nil }
        }
    }

    @ViewBuilder
    private func actionBar(cut: PlayerPerspective.CutState) -> some View {
        VStack(spacing: 12) {
            Text(highlightIndex == nil
                ? "Drag across the fan or tap to choose your cut"
                : "Card \(highlightIndex! + 1) of \(cut.faceDownRemaining) selected")
                .font(.footnote)
                .foregroundStyle(GinRummyPalette.sage.opacity(0.95))
                .animation(.none, value: highlightIndex)

            HStack(spacing: 12) {
                if cut.faceDownRemaining > 0 {
                    Button {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                            highlightIndex = Int.random(in: 0 ..< cut.faceDownRemaining)
                        }
                    } label: {
                        Label("Random", systemImage: "dice")
                    }
                    .buttonStyle(GinActionButtonStyle(filled: false, tint: GinRummyPalette.gold))
                }
                Button {
                    if let h = highlightIndex { submitIndex(h) }
                } label: {
                    Text("Cut here")
                }
                .buttonStyle(GinActionButtonStyle(filled: true))
                .disabled(highlightIndex == nil || busy)
            }
        }
    }

    private func submitIndex(_ i: Int) {
        Task {
            guard let token, let cut = p.cut else { return }
            if busy { return }
            if i < 0 || i >= cut.faceDownRemaining {
                await MainActor.run {
                    feedbackText = "Position \(i) is not valid. Choose 0 through \(max(0, cut.faceDownRemaining - 1)) only."
                    feedbackIsError = true
                }
                return
            }
            busy = true
            do {
                let beforePick = await MainActor.run { app.lastPerspective }
                let r = try await app.api.submitMove(
                    gameId: gameId,
                    token: token,
                    intent: ["type": "cutPick", "index": i]
                )
                await MainActor.run {
                    app.applyGameTableState(
                        perspective: r.perspective,
                        betting: r.betting,
                        opponentDisplayName: r.opponentDisplayName
                    )
                    if let b = beforePick {
                        onAfterCutPick?(b, r.perspective)
                    }
                    feedbackText = ""
                    feedbackIsError = false
                    highlightIndex = nil
                }
            } catch {
                await MainActor.run {
                    feedbackText = UserFeedback.from(error)
                    feedbackIsError = true
                }
            }
            await MainActor.run { busy = false }
        }
    }
}

private struct DiscardHelper: View {
    let gameId: String
    let hand: [String]
    /// First upcard for this hand (knock limit). nil/Ace ⇒ Knock disallowed for the whole hand.
    let knockCheckCard: String?
    let token: String?
    @EnvironmentObject private var app: AppModel
    @Binding var feedbackText: String
    @Binding var feedbackIsError: Bool
    @Binding var selectedCard: String?
    /// Card dropped via drag-to-discard in the fan; consumed (set back to nil) here.
    @Binding var dragDiscardRequest: String?
    var onAfterSuccessfulMove: ((PlayerPerspective?, PlayerPerspective) -> Void)? = nil
    var onAfterSuccessfulDiscard: ((String, PlayerPerspective?, PlayerPerspective) -> Void)? = nil
    /// Called the instant a legal drag-discard is released, so the parent can show it optimistically.
    var onOptimisticDiscard: ((String) -> Void)? = nil
    /// Called if a discard request fails, so the parent can roll back any optimistic UI.
    var onDiscardFailed: (() -> Void)? = nil

    /// Cached per-discard-candidate eligibility, recomputed only when the 11-card hand changes
    /// or the knock card changes. Computed by running the same DFS the server uses, just locally.
    @State private var eligibility = MeldSolver.DiscardEligibility()
    @State private var lastEvaluatedHand: [String] = []
    @State private var lastEvaluatedKnockCard: String? = nil

    /// Presented when a knock has more than one valid meld arrangement: the knocker
    /// chooses which melds hit the table before the knock goes through.
    private struct KnockChooserModel: Identifiable {
        let id = UUID()
        let discard: String
        let options: [MeldSolver.PartitionOption]
    }

    @State private var knockChooser: KnockChooserModel?

    var body: some View {
        let s = selectedCard
        let haveSelection = !(s?.isEmpty ?? true)
        let canPlain = haveSelection && eligibility.plain.contains(s!)
        let canGin = haveSelection && eligibility.ginable.contains(s!)
        let canKnock = haveSelection && eligibility.knockable.contains(s!)

        return VStack(spacing: 6) {
            HStack(spacing: 8) {
                Button("Discard") { Task { await submit(plain: true) } }
                    .buttonStyle(GinActionButtonStyle(filled: true, tint: GinRummyPalette.burgundy))
                    .disabled(!canPlain)
                Button("Gin") { Task { await submit(plain: false, gin: true) } }
                    .buttonStyle(GinActionButtonStyle(filled: true, tint: GinRummyPalette.navy))
                    .disabled(!canGin)
                Button("Knock") { Task { await submit(plain: false, knock: true) } }
                    .buttonStyle(GinActionButtonStyle(filled: false, tint: GinRummyPalette.gold))
                    .disabled(!canKnock)
            }

            if !haveSelection {
                Text("Drag a card up to discard it, or tap to select for knock / gin.")
                    .font(.footnote)
                    .foregroundStyle(GinRummyPalette.sage.opacity(0.95))
                    .frame(maxWidth: .infinity, alignment: .center)
            } else if let hint = inlineHint(canPlain: canPlain, canGin: canGin, canKnock: canKnock) {
                Text(hint)
                    .font(.footnote)
                    .foregroundStyle(GinRummyPalette.sage.opacity(0.95))
                    .frame(maxWidth: .infinity, alignment: .center)
            }
        }
        .onAppear {
            recomputeIfNeeded()
            if let dropped = dragDiscardRequest {
                dragDiscardRequest = nil
                handleDragDiscard(dropped)
            }
        }
        .onChange(of: hand) { _, _ in recomputeIfNeeded() }
        .onChange(of: knockCheckCard) { _, _ in recomputeIfNeeded() }
        .onChange(of: dragDiscardRequest) { _, new in
            guard let dropped = new else { return }
            dragDiscardRequest = nil
            handleDragDiscard(dropped)
        }
        .sheet(item: $knockChooser) { model in
            KnockLayoutChooserView(
                options: model.options,
                knockCard: model.discard,
                onConfirm: { option in
                    knockChooser = nil
                    Task { await submitKnock(discard: model.discard, layout: option) }
                },
                onCancel: { knockChooser = nil }
            )
        }
    }

    private func recomputeIfNeeded() {
        if hand == lastEvaluatedHand, knockCheckCard == lastEvaluatedKnockCard { return }
        lastEvaluatedHand = hand
        lastEvaluatedKnockCard = knockCheckCard
        eligibility = MeldSolver.eligibility(forHand11: hand, knockCheckCard: knockCheckCard)
    }

    /// Drag-to-discard: submit the plain discard directly when it's legal;
    /// otherwise select the card so the inline hint explains why it isn't.
    private func handleDragDiscard(_ dropped: String) {
        recomputeIfNeeded()
        let c = CardIdValidation.normalize(dropped)
        selectedCard = c
        if eligibility.plain.contains(c) {
            onOptimisticDiscard?(c)
            Task { await submit(plain: true) }
        }
    }

    private func inlineHint(canPlain: Bool, canGin: Bool, canKnock: Bool) -> String? {
        if canGin { return "Gin available" }
        if canPlain, !canKnock {
            if MeldSolver.upcardKnockValue(knockCheckCard) == nil {
                return "Knock disabled — first upcard is an Ace (no knock this hand, even with 1 deadwood)."
            }
            if let kv = MeldSolver.upcardKnockValue(knockCheckCard) {
                return "Knock needs unmelded points ≤ knock card (\(kv))."
            }
        }
        if !canPlain, !canGin, !canKnock {
            return "This discard isn't legal — pick another card."
        }
        return nil
    }

    private func submit(plain: Bool, gin: Bool = false, knock: Bool = false) async {
        let raw = selectedCard ?? ""
        if let fmt = CardIdValidation.formatProblem(in: raw) {
            await MainActor.run {
                feedbackText = fmt
                feedbackIsError = true
            }
            return
        }
        let c = CardIdValidation.normalize(raw)
        if let notIn = CardIdValidation.notInHandMessage(card: c, hand: hand) {
            await MainActor.run {
                feedbackText = notIn
                feedbackIsError = true
            }
            return
        }

        if knock, !plain {
            /* Knock layouts with the same unmelded total can still differ in which melds
             * hit the table (and therefore what the opponent can lay off). When there's a
             * genuine choice, the knocker picks; with a single layout we submit directly. */
            let hand10 = hand.filter { $0 != c }
            if MeldSolver.upcardKnockValue(knockCheckCard) != nil {
                let bestSum = MeldSolver.bestDeadwood(hand10).sum
                let options = MeldSolver.allMaximalPartitions(hand10).filter { $0.deadwoodPoints == bestSum }
                if options.count > 1 {
                    await MainActor.run {
                        knockChooser = KnockChooserModel(discard: c, options: options)
                    }
                    return
                }
                if let only = options.first {
                    await submitKnock(discard: c, layout: only)
                    return
                }
            }
        }

        await performSubmit(card: c, plain: plain, gin: gin, knock: knock, layout: nil)
    }

    private func submitKnock(discard: String, layout: MeldSolver.PartitionOption) async {
        await performSubmit(card: discard, plain: false, gin: false, knock: true, layout: layout)
    }

    private func performSubmit(
        card c: String,
        plain: Bool,
        gin: Bool,
        knock: Bool,
        layout: MeldSolver.PartitionOption?
    ) async {
        guard let token else { return }
        var intent: [String: Any] = [
            "type": "discard",
            "card": c,
            "knock": knock,
            "gin": gin,
        ]
        if let layout {
            intent["layout"] = [
                "melds": layout.melds.map { ["type": $0.dtoType, "cards": $0.cards] },
                "deadwood": layout.deadwood,
            ]
        }
        if plain {
            intent["knock"] = false
            intent["gin"] = false
        }
        do {
            let r = try await app.api.submitMove(gameId: gameId, token: token, intent: intent)
            await MainActor.run {
                let before = app.lastPerspective
                app.applyGameTableState(
                    perspective: r.perspective,
                    betting: r.betting,
                    opponentDisplayName: r.opponentDisplayName
                )
                onAfterSuccessfulMove?(before, r.perspective)
                if plain, !knock, !gin {
                    onAfterSuccessfulDiscard?(c, before, r.perspective)
                }
                if knock {
                    feedbackText = "Knock sent."
                } else if gin {
                    feedbackText = "Gin move sent."
                } else {
                    feedbackText = "Discard sent."
                }
                feedbackIsError = false
                selectedCard = nil
            }
        } catch {
            await MainActor.run {
                onDiscardFailed?()
                feedbackText = UserFeedback.from(error)
                feedbackIsError = true
            }
        }
    }
}

