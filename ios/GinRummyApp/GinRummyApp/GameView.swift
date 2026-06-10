import AudioToolbox
import SwiftUI

struct GameView: View {
    @EnvironmentObject private var app: AppModel
    @State private var pollTask: Task<Void, Never>?
    @State private var feedbackText = ""
    @State private var feedbackIsError = false
    @State private var selectedHandCard: String?
    @State private var showPostCutInterstitial = false
    @State private var cutHold: CutHoldState?
    @State private var pendingDealerDeclineAfterCutSequence = false
    @State private var bottomLogText: String = ""
    @State private var handDisplayOrder: [String] = []
    @State private var cardFlight: CardFlightModel?
    @State private var cardFlightClearTask: Task<Void, Never>?
    @State private var messageTask: Task<Void, Never>?
    @State private var downCardStatusMessage: String?
    @State private var postCutTask: Task<Void, Never>?
    @State private var lastYouPickup: PickupSource? = nil
    @State private var lastOpponentPickup: PickupSource? = nil
    /// Stock size right after our discard completes, before the opponent picks up — used when a poll skips their 10→11 draw step.
    @State private var stockCountAfterOurDiscardEndsTurn: Int? = nil
    @State private var youAcceptedDownCardPendingDiscard = false
    @State private var opponentAcceptedDownCardPendingDiscard = false
    /// `seq` of the most recent server-reported action we've already logged (0 = none yet).
    @State private var lastSeenServerActionSeq = 0

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

    @State private var showChatSheet = false
    @State private var chatMessages: [GameChatMessageDTO] = []
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
        if isPostCutSequenceActive() { return .postCutReveal }
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

    private struct CutHoldState: Equatable {
        var last: PlayerPerspective.LastCutResult
        var mode: PostCutRevealMode
        var youAreSeat: Int

        var yourCard: String { youAreSeat == 0 ? last.p0 : last.p1 }
        var oppCard: String { youAreSeat == 0 ? last.p1 : last.p0 }
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
        .navigationTitle("Table")
        .toolbar {
            if app.activeGameId != nil {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        showLeaveConfirm = true
                    } label: {
                        Label("Leave", systemImage: "rectangle.portrait.and.arrow.right")
                            .labelStyle(.titleAndIcon)
                            .foregroundStyle(GinRummyPalette.cream.opacity(0.85))
                    }
                    .disabled(exitState != nil || app.lastPerspective?.phase == "matchOver")
                    .accessibilityLabel("Leave game")
                }
                ToolbarItem(placement: .topBarTrailing) {
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
            }
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
            postCutTask?.cancel()
            cardFlightClearTask?.cancel()
            messageTask?.cancel()
            chatBaselineTask?.cancel()
        }
    }

    private func setFeedback(_ text: String, error: Bool) {
        feedbackText = text
        feedbackIsError = error
    }

    private func isPostCutSequenceActive() -> Bool {
        cutHold != nil || showPostCutInterstitial
    }

    private func handleAfterPerspectiveUpdate(before: PlayerPerspective?, after: PlayerPerspective) {
        if willStartPostCutSequence(before: before, after: after) {
            detectCutCompletion(before: before, after: after)
            return
        }
        detectCutCompletion(before: before, after: after)
        detectDownCardStateForDealer(before: before, after: after)
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
            scheduleCardFlight(
                route: .discardFromHand(isOpponent: false),
                card: CardIdValidation.normalize(newTop)
            )
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
            if !yourDiscardNorm.isEmpty {
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

    private func matchOutcomeSubtitle(_ p: PlayerPerspective) -> String {
        let winner: Int?
        if p.scores[0] >= p.raceTarget { winner = 0 }
        else if p.scores[1] >= p.raceTarget { winner = 1 }
        else { winner = nil }
        guard let w = winner else { return "Race to \(p.raceTarget)" }
        return w == p.seat ? "You reached \(p.raceTarget) first." : "Opponent reached \(p.raceTarget) first."
    }

    private func matchWinnerHeadline(_ p: PlayerPerspective) -> String {
        let winner: Int?
        if p.scores[0] >= p.raceTarget { winner = 0 }
        else if p.scores[1] >= p.raceTarget { winner = 1 }
        else { winner = nil }
        guard let w = winner else { return "Match complete" }
        return w == p.seat ? "You won the match" : "Opponent won the match"
    }

    @ViewBuilder
    private func matchSummaryPanel(p: PlayerPerspective) -> some View {
        VStack(alignment: .leading, spacing: 8) {
                Text(matchWinnerHeadline(p))
                    .font(.title3.bold())
                    .foregroundStyle(GinRummyPalette.cream)
            Text("Final score · \(p.scores[0]) – \(p.scores[1])")
                .font(.headline.monospacedDigit())
                .foregroundStyle(GinRummyPalette.cream)
            Text("Hands won · \(p.handsWon[0]) – \(p.handsWon[1])")
                .font(.subheadline)
                .foregroundStyle(GinRummyPalette.sage.opacity(0.95))
            if let b = app.lastBetting, let raw = b.raw, let bucket = b.bucket {
                Divider().padding(.vertical, 2)
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text("Betting bucket")
                        .font(.subheadline.weight(.semibold))
                    Text("\(bucket)")
                        .font(.title3.bold().monospacedDigit())
                        .foregroundStyle(GamePlaySurface.matchOver.accent)
                }
                Text("Raw points · \(raw)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(GinRummyPalette.sage.opacity(0.95))
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
    private func cutProminentTitle(surface: GamePlaySurface, p: PlayerPerspective) -> some View {
        if surface == .cutForDeal, p.cut != nil {
            Text(cutStageTitle(p))
                .font(.title2.bold())
                .foregroundStyle(GinRummyPalette.cream)
                .frame(maxWidth: .infinity, alignment: .center)
                .multilineTextAlignment(.center)
                .contentTransition(.opacity)
        } else {
            EmptyView()
        }
    }

    @ViewBuilder
    private func scoreRail(surface: GamePlaySurface, p: PlayerPerspective) -> some View {
        if showsScoreRail(surface) {
            HStack(alignment: .firstTextBaseline) {
                Spacer(minLength: 0)
                VStack(alignment: .trailing, spacing: 0) {
                    Text("\(p.scores[0]) – \(p.scores[1])")
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
    private func postCutStrip(p: PlayerPerspective) -> some View {
        if let hold = cutHold {
            VStack(alignment: .leading, spacing: 10) {
                Text("Match · Cut reveal")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(GinRummyPalette.sage.opacity(0.95))
                HStack(alignment: .top, spacing: 8) {
                    VStack(alignment: .center, spacing: 6) {
                        Text("Your Card")
                            .font(.caption2)
                            .foregroundStyle(GinRummyPalette.sage.opacity(0.95))
                        PlayingCardView(card: hold.yourCard, compact: true, onTap: nil)
                    }
                    .frame(maxWidth: .infinity)

                    VStack(alignment: .center, spacing: 6) {
                        Text("Opponent Card")
                            .font(.caption2)
                            .foregroundStyle(GinRummyPalette.sage.opacity(0.95))
                        if hold.mode == .both {
                            PlayingCardView(card: hold.oppCard, compact: true, onTap: nil)
                        } else {
                            RoundedRectangle(cornerRadius: 6)
                                .fill(Color.orange.opacity(0.2))
                                .frame(width: 51, height: 75)
                                .overlay { ProgressView() }
                        }
                        if hold.mode == .yourOnly {
                            Text("Opponent drawing…")
                                .font(.caption.italic())
                                .foregroundStyle(GinRummyPalette.sage.opacity(0.95))
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity)
            .background(RoundedRectangle(cornerRadius: 12).fill(GinRummyPalette.bgPanel.opacity(0.72)))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(GinRummyPalette.gold.opacity(0.2)))
        } else {
            EmptyView()
        }
    }

    @ViewBuilder
    private func centerTableForSurface(gameId: String, surface: GamePlaySurface, p: PlayerPerspective) -> some View {
        switch surface {
        case .cutForDeal:
            if p.cut != nil {
                CutForDealView(
                    gameId: gameId,
                    p: p,
                    token: app.accessToken,
                    onAfterCutPick: handleAfterCutPick(before:after:),
                    feedbackText: $feedbackText,
                    feedbackIsError: $feedbackIsError
                )
            } else {
                EmptyView()
            }
        case .postCutReveal:
            EmptyView()
        case .downCard, .play:
            VStack(alignment: .leading, spacing: 8) {
                if surface == .play, p.currentTurn != p.seat {
                    Label("Opponent’s turn", systemImage: "hourglass")
                        .font(.caption)
                        .foregroundStyle(GinRummyPalette.sage.opacity(0.95))
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
                        discardTop: p.discard.last,
                        discardOnTap: takeDiscardActionIfEnabled(gameId: gameId, p: p),
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
            } else if showPostCutInterstitial, let lc = p.lastCut {
                PostCutInterstitial(last: lc, youAreSeat: p.seat)
                    .id("\(lc.p0)-\(lc.p1)-\(lc.nonDealer)-interstitial")
                    .zIndex(200)
                    .transition(.opacity)
            } else {
                GinRummyTableChrome {
                    ZStack(alignment: .top) {
                        phaseBackdrop(surface: surface)
                        ScrollView {
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
                                .padding(8)
                            } else {
                            VStack(alignment: .leading, spacing: 10) {
                                phaseRibbon(surface: surface, p: p)
                                cutProminentTitle(surface: surface, p: p)
                                scoreRail(surface: surface, p: p)
                                postCutStrip(p: p)
                                centerTableForSurface(gameId: gameId, surface: surface, p: p)

                                if surface == .matchOver {
                                    matchSummaryPanel(p: p)
                                }

                                if surface == .handOver, p.handResult == nil {
                                    handOverPanel(p: p)
                                }

                                if surface == .knockLayoff, let k = p.knock {
                                    if k.layoffTurn == p.seat, k.knocker != p.seat {
                                        LayoffArrangementView(
                                            p: p,
                                            knock: k,
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
                                        KnockerWaitingView(knock: k, opponentName: app.opponentDisplayName)
                                    }
                                }

                                if showsYouHand(surface, p: p) {
                                    youHandBlock(surface: surface, p: p, selectedHandCard: $selectedHandCard)
                                }

                                if showsTurnRibbon(surface) {
                                    turnBanner(p: p)
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
        .animation(.easeInOut(duration: 0.28), value: showPostCutInterstitial)
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
        .overlay {
            if let cf = cardFlight, surface == .play || surface == .downCard {
                CardFlightAnimationOverlay(route: cf.route, card: cf.card)
                    .id(cf.id)
                    .allowsHitTesting(false)
                    .transition(.opacity)
            }
        }
        .onAppear {
            mergeHandOrder(with: p.hands[p.seat])
            chatMessages = []
            chatWatermarkIso = nil
            chatBaselineLoaded = false
            chatToasts = []
            chatUnreadCount = 0
            chatBaselineTask?.cancel()
            chatBaselineTask = nil
            pollTask?.cancel()
            pollTask = Task { await pollLoop(gameId: gameId) }
        }
        .onChange(of: gameContentObservation(p)) { old, new in
            if old.hand != new.hand {
                if let s = selectedHandCard, !new.hand.contains(s) { selectedHandCard = nil }
                mergeHandOrder(with: new.hand)
            }
            if old.hasLastCut, !new.hasLastCut {
                postCutTask?.cancel()
                cutHold = nil
                showPostCutInterstitial = false
                pendingDealerDeclineAfterCutSequence = false
            }
            if old.phase != new.phase, new.phase != "matchOver" {
                showMatchSummaryAfterReveal = false
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

    private func cardName(_ raw: String) -> String {
        let c = CardIdValidation.normalize(raw)
        guard c.count == 2 else { return raw }
        let r = c.first!
        let s = c.last!
        let rank: String = switch r {
        case "A": "Ace"
        case "K": "King"
        case "Q": "Queen"
        case "J": "Jack"
        case "T": "10"
        default: String(r)
        }
        let suit: String = switch s {
        case "S": "Spades"
        case "H": "Hearts"
        case "D": "Diamonds"
        case "C": "Clubs"
        default: String(s)
        }
        return "\(rank) of \(suit)"
    }

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

    private func detectCutCompletion(before: PlayerPerspective?, after: PlayerPerspective) {
        guard willStartPostCutSequence(before: before, after: after),
              let b = before,
              let last = after.lastCut
        else { return }

        let userPickedFirst = b.cut?.theirCut == nil
        postCutTask?.cancel()
        showPostCutInterstitial = false
        cutHold = CutHoldState(last: last, mode: userPickedFirst ? .yourOnly : .both, youAreSeat: after.seat)
        pendingDealerDeclineAfterCutSequence = shouldDeferDealerDeclineHint(after: after)

        postCutTask = Task { @MainActor in
            if userPickedFirst {
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                if cutHold != nil { cutHold?.mode = .both }
            }
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            cutHold = nil
            try? await Task.sleep(nanoseconds: 200_000_000)
            showPostCutInterstitial = true
            try? await Task.sleep(nanoseconds: 5_500_000_000)
            showPostCutInterstitial = false
            if pendingDealerDeclineAfterCutSequence {
                pendingDealerDeclineAfterCutSequence = false
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

    private func turnLine(_ p: PlayerPerspective) -> String {
        if p.currentTurn == p.seat { return "Your turn" }
        return "Opponent’s turn"
    }

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

    private func cutStageTitle(_ p: PlayerPerspective) -> String {
        guard let c = p.cut else { return "High card wins the first deal" }
        return c.youMustPick ? "Your turn — tap the spread to cut" : "Opponent is cutting"
    }

    private func knockLayoffLine(_ p: PlayerPerspective, k: PlayerPerspective.KnockPerspective) -> String {
        let whose = k.layoffTurn == p.seat ? "Your" : "Opponent’s"
        return "Layoff · \(whose) turn"
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

    /// Play: take top discard on your turn with 10 cards (same as tap-to-take).
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

    private func drawStockActionIfEnabled(gameId: String, p: PlayerPerspective) -> (() -> Void)? {
        if p.phase == "play",
           p.currentTurn == p.seat,
           p.hands[p.seat].count == 10 {
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
                chatMessages = r.messages.sorted { $0.createdAt < $1.createdAt }
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
                let gameWasAbandoned = await MainActor.run { () -> Bool in
                    guard app.activeGameId == gameId else { return true }
                    guard s.status == "abandoned" else { return false }
                    if exitState == nil {
                        if let leftBy = s.leftBySeat, leftBy == s.perspective.seat {
                            /* Our own leave (e.g. from another device / a retried request). */
                            exitState = .youLeft
                        } else {
                            exitState = .opponentLeft
                        }
                    }
                    return true
                }
                if gameWasAbandoned { return }
                await MainActor.run {
                    guard app.activeGameId == gameId else { return }
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
                await fetchAndMergeChatFromPoll(gameId: gameId, token: token)
            } catch {
                await MainActor.run { setFeedback(UserFeedback.from(error), error: true) }
            }
            try? await Task.sleep(nanoseconds: 2_000_000_000)
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

    private func handDisplayFor(hand: [String]) -> [String] {
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
                    Button("Return to lobby") {
                        pollTask?.cancel()
                        postCutTask?.cancel()
                        cardFlightClearTask?.cancel()
                        messageTask?.cancel()
                        app.clearActiveGame()
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(GinRummyPalette.burgundy)
                    .controlSize(.large)
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
                    .buttonStyle(.borderedProminent)
                    .tint(GinRummyPalette.navy)
                }
            }
            if proposeRedealSurface(surface) {
                proposeRedealFooter(
                    gameId: gameId,
                    p: p,
                    feedbackText: feedbackText,
                    feedbackIsError: feedbackIsError
                )
            }
        }
    }

    private func proposeRedealSurface(_ surface: GamePlaySurface) -> Bool {
        switch surface {
        case .downCard, .play, .knockLayoff: true
        default: false
        }
    }

    @ViewBuilder
    private func proposeRedealFooter(
        gameId: String,
        p: PlayerPerspective,
        feedbackText: Binding<String>,
        feedbackIsError: Binding<Bool>
    ) -> some View {
        let pending = p.redeal?.status == "pending"
        VStack(alignment: .leading, spacing: 6) {
            Divider().opacity(0.35)
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
            .buttonStyle(.bordered)
            .tint(GinRummyPalette.gold)
            .disabled(pending)
            if pending, p.redeal?.fromSeat == p.seat {
                Text("Waiting on \(app.opponentDisplayName)…")
                    .font(.caption)
                    .foregroundStyle(GinRummyPalette.sage.opacity(0.95))
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
        if let r = p.redeal {
            let opp = app.opponentDisplayName
            VStack(alignment: .leading, spacing: 10) {
                if r.status == "pending", r.fromSeat == p.seat {
                    Label("Redeal proposed", systemImage: "arrow.triangle.2.circlepath")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(GinRummyPalette.cream)
                    Text("Waiting for \(opp) to confirm…")
                        .font(.caption)
                        .foregroundStyle(GinRummyPalette.sage.opacity(0.95))
                } else if r.status == "pending" {
                    Text("\(opp) proposed a redeal")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(GinRummyPalette.cream)
                    HStack(spacing: 14) {
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
                            Image(systemName: "checkmark.circle.fill")
                                .font(.title2)
                                .foregroundStyle(.green.opacity(0.95))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Accept redeal")

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
                            Image(systemName: "xmark.circle.fill")
                                .font(.title2)
                                .foregroundStyle(.red.opacity(0.92))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Decline redeal")

                        Spacer(minLength: 0)
                    }
                } else if r.status == "declined", r.fromSeat == p.seat {
                    Label("\(opp) declined the redeal", systemImage: "xmark.circle")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(GinRummyPalette.cream)
                    Text("Keep playing — or propose again after your next move.")
                        .font(.caption2)
                        .foregroundStyle(GinRummyPalette.sage.opacity(0.9))
                } else if r.status == "declined" {
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
                .buttonStyle(.borderedProminent)
                .tint(GinRummyPalette.burgundy)
                .controlSize(.large)
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
                .buttonStyle(.borderedProminent)
                .tint(GinRummyPalette.burgundy)
                .controlSize(.large)
                .padding(.top, 8)
            }
            Spacer(minLength: 24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(GinRummyPalette.bgDeep.opacity(0.97))
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
            /* Brief pause so the "leaving the table" visual registers instead of flashing. */
            try? await Task.sleep(nanoseconds: 900_000_000)
            await MainActor.run {
                if invite != nil {
                    app.finishInGameInviteAccepted()
                } else {
                    exitState = .youLeft
                }
            }
        } catch {
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
        VStack(alignment: .leading, spacing: 8) {
            Text(downCardStageTitle(p))
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(GinRummyPalette.cream)
            Text(turnLine(p))
                .font(.headline.weight(.semibold))
                .foregroundStyle(GinRummyPalette.gold.opacity(0.95))
            if downCardStatusMessage == Self.opponentDeclinedDownCardMessage {
                Text("Take or pass the up-card.")
                    .font(.caption)
                    .foregroundStyle(GinRummyPalette.sage.opacity(0.95))
            }

            HStack(spacing: 10) {
                Button("Take") {
                    downCardStatusMessage = "You Drew Down Card"
                    Task {
                        await send(
                            gameId: gameId,
                            token: token,
                            intent: ["type": "upcardTake"],
                            success: "You Drew Down Card",
                            feedbackText: feedbackText,
                            feedbackIsError: feedbackIsError
                        )
                    }
                }
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
            }
            .buttonStyle(.bordered)
            .tint(GinRummyPalette.gold)
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
            if p.hands[p.seat].count == 11 {
                let canEO = MeldSolver.isBigGin11(p.hands[p.seat])
                Button("Declare EO") {
                    Task { await send(gameId: gameId, token: token, intent: ["type": "declareBigGin"], success: "Declared EO (big gin).", feedbackText: feedbackText, feedbackIsError: feedbackIsError) }
                }
                .disabled(!canEO)
                .buttonStyle(.borderedProminent)
                .tint(GinRummyPalette.navy)
                DiscardHelper(
                    gameId: gameId,
                    hand: p.hands[p.seat],
                    knockCheckCard: p.knockCheckCard,
                    token: token,
                    feedbackText: feedbackText,
                    feedbackIsError: feedbackIsError,
                    selectedCard: selectedHandCard,
                    onAfterSuccessfulMove: { before, after in
                        if let b = before {
                            handleAfterPerspectiveUpdate(before: b, after: after)
                        }
                    },
                    onAfterSuccessfulDiscard: nil
                )
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
        return VStack(alignment: .leading, spacing: 10) {
            if let cut = p.cut, cut.youMustPick {
                HStack {
                    Spacer()
                    if cut.faceDownRemaining > 0 {
                        Button("Random card") {
                            let m = cut.faceDownRemaining
                            highlightIndex = Int.random(in: 0 ..< m)
                        }
                        .font(.caption)
                    }
                    Spacer()
                    Button("Select") {
                        if let h = highlightIndex { submitIndex(h) }
                    }
                    .font(.headline)
                    .buttonStyle(.borderedProminent)
                    .disabled(highlightIndex == nil || busy)
                    Spacer()
                }
            }
            CutForDealTable(
                p: p,
                highlightIndex: $highlightIndex,
                busy: $busy
            )
            .frame(maxWidth: .infinity, minHeight: 200, alignment: .topLeading)
        }
        .onChange(of: p.cut?.youMustPick ?? false) { _, new in
            if new { highlightIndex = nil }
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
    var onAfterSuccessfulMove: ((PlayerPerspective?, PlayerPerspective) -> Void)? = nil
    var onAfterSuccessfulDiscard: ((String, PlayerPerspective?, PlayerPerspective) -> Void)? = nil

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

        return VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Button("Discard") { Task { await submit(plain: true) } }
                    .disabled(!canPlain)
                Button("Gin") { Task { await submit(plain: false, gin: true) } }
                    .disabled(!canGin)
                Button("Knock") { Task { await submit(plain: false, knock: true) } }
                    .disabled(!canKnock)
            }
            .buttonStyle(.bordered)
            .tint(GinRummyPalette.gold)

            if haveSelection, let hint = inlineHint(canPlain: canPlain, canGin: canGin, canKnock: canKnock) {
                Text(hint)
                    .font(.caption)
                    .foregroundStyle(GinRummyPalette.sage.opacity(0.95))
            }
        }
        .onAppear { recomputeIfNeeded() }
        .onChange(of: hand) { _, _ in recomputeIfNeeded() }
        .onChange(of: knockCheckCard) { _, _ in recomputeIfNeeded() }
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

    private func inlineHint(canPlain: Bool, canGin: Bool, canKnock: Bool) -> String? {
        if canGin { return "Gin available — declare for the bonus, or Discard to keep playing (e.g. for EO)." }
        if canPlain, !canKnock {
            if MeldSolver.upcardKnockValue(knockCheckCard) == nil {
                return "Knock disabled — first upcard is an Ace (no knock this hand, even with 1 deadwood)."
            }
            if let kv = MeldSolver.upcardKnockValue(knockCheckCard) {
                return "Knock needs deadwood exactly \(kv) after this discard (first upcard)."
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
            if let kv = MeldSolver.upcardKnockValue(knockCheckCard) {
                let options = MeldSolver.allMaximalPartitions(hand10).filter { $0.deadwoodPoints == kv }
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
                feedbackText = UserFeedback.from(error)
                feedbackIsError = true
            }
        }
    }
}

