import SwiftUI

/// Shared styling for the end-of-hand surfaces (reveal, knock chooser, layoff table).
enum HandEndStyle {
    /// Tint for cards the defender laid off onto the knocker's melds.
    static let layoffBlue = Color(red: 0.45, green: 0.72, blue: 1.0)
    /// "Other player is ready / waiting on you" banners.
    static let readyBlue = Color(red: 0.62, green: 0.80, blue: 1.0)
    /// Unmelded (deadwood) emphasis.
    static let deadwoodRed = Color(red: 0.86, green: 0.32, blue: 0.30)
}

// MARK: - One meld on the table

/// A single meld as a tight overlapped row of cards, in a felt "slot".
struct MeldGroupView: View {
    let meld: MeldDTO
    /// Cards tinted blue (laid off by the defender).
    var laidOffCards: Set<String> = []
    /// Glowing target state (defender picking where a card attaches).
    var highlighted: Bool = false
    var dimmed: Bool = false
    var onTap: (() -> Void)? = nil
    /// Tap a specific card inside the meld (used to undo a staged layoff).
    var onTapCard: ((String) -> Void)? = nil

    var body: some View {
        let cards = meld.type == "run" ? MeldSolver.rankSorted(meld.cards) : meld.cards
        HStack(spacing: -26) {
            ForEach(cards, id: \.self) { c in
                PlayingCardView(card: c, compact: true, onTap: onTapCard.map { tap in { tap(c) } })
                    .overlay(
                        RoundedRectangle(cornerRadius: 5)
                            .fill(laidOffCards.contains(c) ? HandEndStyle.layoffBlue.opacity(0.30) : Color.clear)
                            .allowsHitTesting(false)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 5)
                            .stroke(
                                laidOffCards.contains(c) ? HandEndStyle.layoffBlue : Color.clear,
                                lineWidth: laidOffCards.contains(c) ? 2 : 0
                            )
                            .allowsHitTesting(false)
                    )
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(highlighted ? HandEndStyle.layoffBlue.opacity(0.22) : Color.black.opacity(0.18))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(
                    highlighted ? HandEndStyle.layoffBlue : GinRummyPalette.gold.opacity(0.28),
                    lineWidth: highlighted ? 2.5 : 1
                )
        )
        .opacity(dimmed ? 0.55 : 1)
        .contentShape(RoundedRectangle(cornerRadius: 10))
        .onTapGesture { onTap?() }
    }
}

// MARK: - Meld composition on a half of the table

/// Up to three melds in the table composition: one higher-left, one higher-right,
/// and one centered a little lower. Extra melds (rare) wrap on a final row.
struct MeldTableArrangement: View {
    let melds: [MeldDTO]
    var laidOffCards: Set<String> = []
    /// Index of the meld currently glowing as a layoff target set.
    var highlightedIndices: Set<Int> = []
    var onTapMeld: ((Int) -> Void)? = nil
    var onTapCardInMeld: ((String, Int) -> Void)? = nil

    var body: some View {
        VStack(spacing: 12) {
            if melds.isEmpty {
                Text("No melds")
                    .font(.caption.italic())
                    .foregroundStyle(GinRummyPalette.sage.opacity(0.9))
                    .padding(.vertical, 10)
            } else {
                HStack(alignment: .top, spacing: 8) {
                    if melds.count > 0 { group(0) }
                    if melds.count > 1 {
                        Spacer(minLength: 6)
                        group(1)
                    } else {
                        Spacer(minLength: 6)
                    }
                }
                if melds.count > 2 {
                    HStack {
                        Spacer(minLength: 0)
                        group(2)
                        Spacer(minLength: 0)
                    }
                }
                if melds.count > 3 {
                    HStack(spacing: 8) {
                        ForEach(3 ..< melds.count, id: \.self) { i in
                            group(i)
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func group(_ i: Int) -> some View {
        MeldGroupView(
            meld: melds[i],
            laidOffCards: laidOffCards,
            highlighted: highlightedIndices.contains(i),
            onTap: onTapMeld.map { tap in { tap(i) } },
            onTapCard: onTapCardInMeld.map { tap in { c in tap(c, i) } }
        )
    }
}

// MARK: - Unmelded cards with point badges

/// Unmelded cards, visually distinct (red border + per-card point badge) with a total chip.
struct DeadwoodRow: View {
    let cards: [String]
    let points: Int
    var label: String = "Unmelded"

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text(label.uppercased())
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(HandEndStyle.deadwoodRed.opacity(0.95))
                Text("\(points) pts")
                    .font(.caption.bold().monospacedDigit())
                    .foregroundStyle(GinRummyPalette.cream)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(HandEndStyle.deadwoodRed.opacity(0.55)))
            }
            if cards.isEmpty {
                Text("None — every card melded")
                    .font(.caption.italic())
                    .foregroundStyle(GinRummyPalette.sage.opacity(0.95))
            } else {
                HStack(spacing: 6) {
                    ForEach(MeldSolver.rankSorted(cards), id: \.self) { c in
                        VStack(spacing: 2) {
                            PlayingCardView(card: c, compact: true, onTap: nil)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 5)
                                        .stroke(HandEndStyle.deadwoodRed.opacity(0.9), lineWidth: 2)
                                )
                            Text("\(MeldSolver.deadwoodValue(c))")
                                .font(.caption2.bold().monospacedDigit())
                                .foregroundStyle(HandEndStyle.deadwoodRed.opacity(0.95))
                        }
                    }
                    Spacer(minLength: 0)
                }
            }
        }
    }
}

// MARK: - End-of-hand reveal

/// Full-table reveal after a hand ends: opponent's layout on the top half, yours on
/// the bottom, unmelded cards highlighted with their points. Plays a short sequence
/// (table → flashed points overlay → ready-up Continue with waiting banners).
struct HandRevealView: View {
    let p: PlayerPerspective
    let result: HandResultDTO
    let opponentName: String
    /// matchOver: Continue is local-only (no ready-up) and leads to the final summary.
    var isMatchOver: Bool = false
    /// Tapped Continue during handOver — sends the seat-scoped ack.
    var onContinue: () -> Void = {}
    /// matchOver only: proceed to the final match summary.
    var onShowFinalResults: () -> Void = {}

    private enum Stage { case table, flash, ready }

    @State private var stage: Stage = .table
    @State private var sequenceTask: Task<Void, Never>?
    @State private var youTappedContinue = false

    private var mySeat: Int { p.seat }
    private var oppSeat: Int { 1 - p.seat }
    private var mySide: HandResultDTO.Side? { result.side(forSeat: mySeat) }
    private var oppSide: HandResultDTO.Side? { result.side(forSeat: oppSeat) }
    private var laidOffSet: Set<String> { Set(result.layoffs.map(\.card)) }
    private var youWon: Bool { result.winner == mySeat }

    var body: some View {
        ZStack {
            VStack(alignment: .leading, spacing: 14) {
                headline
                seatSection(
                    title: opponentName.uppercased(),
                    side: oppSide,
                    isCloser: result.closer == oppSeat
                )
                Divider()
                    .overlay(GinRummyPalette.gold.opacity(0.35))
                seatSection(
                    title: "YOU",
                    side: mySide,
                    isCloser: result.closer == mySeat
                )
                if !result.layoffs.isEmpty {
                    Label(
                        "Blue cards were laid off onto the knocker's melds.",
                        systemImage: "arrow.turn.right.up"
                    )
                    .font(.caption2)
                    .foregroundStyle(HandEndStyle.layoffBlue.opacity(0.95))
                }
                if stage == .ready {
                    readyArea
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .blur(radius: stage == .flash ? 2.5 : 0)

            if stage == .flash {
                flashOverlay
                    .transition(.scale(scale: 0.86).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.45, dampingFraction: 0.85), value: stage)
        .onAppear { runSequence() }
        .onDisappear { sequenceTask?.cancel() }
    }

    // MARK: pieces

    private var headline: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: headlineSymbol)
                .font(.title3.weight(.semibold))
                .foregroundStyle(GinRummyPalette.gold)
            VStack(alignment: .leading, spacing: 2) {
                Text(headlineTitle)
                    .font(.headline)
                    .foregroundStyle(GinRummyPalette.cream)
                Text("\(pointsLine) · Score \(p.scores[0]) – \(p.scores[1])")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(GinRummyPalette.sage.opacity(0.95))
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 12).fill(GinRummyPalette.bgPanel.opacity(0.7)))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(GinRummyPalette.gold.opacity(0.3)))
    }

    @ViewBuilder
    private func seatSection(title: String, side: HandResultDTO.Side?, isCloser: Bool) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text(title)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(GinRummyPalette.cream)
                if isCloser {
                    Text(closerBadgeText)
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(GinRummyPalette.navy)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(GinRummyPalette.gold.opacity(0.92)))
                }
                Spacer(minLength: 0)
            }
            if let side {
                MeldTableArrangement(
                    melds: side.melds,
                    laidOffCards: isCloser ? laidOffSet : []
                )
                DeadwoodRow(cards: side.deadwood, points: side.deadwoodPoints)
            }
        }
    }

    private var flashOverlay: some View {
        VStack(spacing: 10) {
            Text(flashTitle)
                .font(.system(size: 34, weight: .black, design: .serif))
                .foregroundStyle(GinRummyPalette.cream)
                .multilineTextAlignment(.center)
            Text(flashDetail)
                .font(.title3.weight(.semibold))
                .foregroundStyle(GinRummyPalette.gold)
                .multilineTextAlignment(.center)
            Text(pointsLine)
                .font(.headline.monospacedDigit())
                .foregroundStyle(youWon ? GinRummyPalette.cream : HandEndStyle.deadwoodRed)
        }
        .padding(.horizontal, 26)
        .padding(.vertical, 30)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(GinRummyPalette.bgDeep.opacity(0.94))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20)
                .stroke(GinRummyPalette.gold.opacity(0.55), lineWidth: 1.4)
        )
        .shadow(color: .black.opacity(0.45), radius: 18, y: 8)
        .padding(.horizontal, 16)
    }

    @ViewBuilder
    private var readyArea: some View {
        let acks = p.handOverAcks
        let youAcked = youTappedContinue || (acks.flatMap { $0.indices.contains(mySeat) ? $0[mySeat] : nil } ?? false)
        let oppAcked = acks.flatMap { $0.indices.contains(oppSeat) ? $0[oppSeat] : nil } ?? false

        VStack(spacing: 10) {
            if isMatchOver {
                Button("See final result") { onShowFinalResults() }
                    .buttonStyle(.borderedProminent)
                    .tint(GinRummyPalette.burgundy)
                    .controlSize(.large)
            } else {
                if oppAcked, !youAcked {
                    readyBanner(
                        symbol: "checkmark.circle.fill",
                        text: "\(opponentName) is ready for the next hand — they're waiting on you."
                    )
                }
                if !youAcked {
                    Button("Continue") {
                        youTappedContinue = true
                        onContinue()
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(GinRummyPalette.navy)
                    .controlSize(.large)
                } else if !oppAcked {
                    readyBanner(
                        symbol: "hourglass",
                        text: "You're ready. \(opponentName) may still be studying the hand…"
                    )
                } else {
                    readyBanner(symbol: "checkmark.circle.fill", text: "Both ready — dealing…")
                }
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func readyBanner(symbol: String, text: String) -> some View {
        Label(text, systemImage: symbol)
            .font(.subheadline.weight(.medium))
            .foregroundStyle(GinRummyPalette.navy)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 12).fill(HandEndStyle.readyBlue.opacity(0.85)))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(HandEndStyle.readyBlue, lineWidth: 1))
    }

    // MARK: copy

    private var closerBadgeText: String {
        switch result.kind {
        case "gin": return "GIN"
        case "bigGin": return "EO"
        default: return "KNOCKED"
        }
    }

    private var headlineSymbol: String {
        switch result.kind {
        case "gin", "bigGin": return "crown.fill"
        case "undercut": return "arrow.uturn.down"
        default: return "hand.raised.fill"
        }
    }

    private var headlineTitle: String {
        switch result.kind {
        case "gin": return result.closer == mySeat ? "You ginned" : "\(opponentName) ginned"
        case "bigGin": return result.closer == mySeat ? "You declared EO" : "\(opponentName) declared EO"
        case "undercut": return youWon ? "You undercut the knock" : "\(opponentName) undercut your knock"
        default: return result.closer == mySeat ? "You knocked" : "\(opponentName) knocked"
        }
    }

    private var flashTitle: String {
        switch result.kind {
        case "gin": return result.closer == mySeat ? "GIN!" : "\(opponentName) ginned"
        case "bigGin": return result.closer == mySeat ? "EO!" : "EO against you"
        case "undercut": return youWon ? "UNDERCUT!" : "Undercut!"
        default: return result.closer == mySeat ? "Knock holds" : "\(opponentName) knocked"
        }
    }

    private var flashDetail: String {
        let oppPts = oppSide?.deadwoodPoints ?? 0
        let myPts = mySide?.deadwoodPoints ?? 0
        switch result.kind {
        case "gin", "bigGin":
            return result.closer == mySeat
                ? "\(opponentName) had \(oppPts) unmelded point\(oppPts == 1 ? "" : "s")"
                : "You had \(myPts) unmelded point\(myPts == 1 ? "" : "s")"
        default:
            return "Your \(myPts) vs their \(oppPts) unmelded"
        }
    }

    private var pointsLine: String {
        youWon ? "+\(result.points) to you" : "+\(result.points) to \(opponentName)"
    }

    // MARK: sequence

    private func runSequence() {
        stage = .table
        sequenceTask?.cancel()
        sequenceTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 2_400_000_000)
            if Task.isCancelled { return }
            stage = .flash
            try? await Task.sleep(nanoseconds: 2_400_000_000)
            if Task.isCancelled { return }
            stage = .ready
        }
    }
}

// MARK: - Match-end rematch ready-up

/// Dual ready-up on the match summary screen — mirrors the hand-over Continue flow.
struct RematchReadyFooter: View {
    let rematch: RematchStatusDTO
    let opponentName: String
    let youTappedPlayAgain: Bool
    let busy: Bool
    var onPlayAgain: () -> Void

    private var mySeat: Int? { rematch.players.first(where: { $0.isSelf })?.seat }
    private var youReady: Bool {
        youTappedPlayAgain || (rematch.players.first(where: { $0.isSelf })?.ready ?? false)
    }
    private var oppReady: Bool {
        if rematch.isBotGame { return true }
        guard let seat = mySeat else { return false }
        return rematch.players.first(where: { $0.seat == 1 - seat })?.ready ?? false
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Play again")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(GinRummyPalette.cream)

            if rematch.isBotGame {
                if !youReady {
                    Button(busy ? "Starting…" : "Play again") {
                        onPlayAgain()
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(GinRummyPalette.navy)
                    .controlSize(.large)
                    .disabled(busy)
                } else {
                    rematchBanner(
                        symbol: "hourglass",
                        text: "Starting a new match…"
                    )
                }
            } else if oppReady, !youReady {
                rematchBanner(
                    symbol: "checkmark.circle.fill",
                    text: "\(opponentName) is ready for a rematch — they're waiting on you."
                )
                Button("Play again") {
                    onPlayAgain()
                }
                .buttonStyle(.borderedProminent)
                .tint(GinRummyPalette.navy)
                .controlSize(.large)
                .disabled(busy)
            } else if !youReady {
                Button("Play again") {
                    onPlayAgain()
                }
                .buttonStyle(.borderedProminent)
                .tint(GinRummyPalette.navy)
                .controlSize(.large)
                .disabled(busy)
            } else if !oppReady {
                rematchBanner(
                    symbol: "hourglass",
                    text: "You're ready. \(opponentName) may still be reviewing the match…"
                )
            } else {
                rematchBanner(symbol: "checkmark.circle.fill", text: "Both ready — dealing…")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(HandEndStyle.readyBlue.opacity(0.12))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(HandEndStyle.readyBlue.opacity(0.35), lineWidth: 1)
        )
    }

    private func rematchBanner(symbol: String, text: String) -> some View {
        Label(text, systemImage: symbol)
            .font(.subheadline.weight(.medium))
            .foregroundStyle(GinRummyPalette.navy)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 12).fill(HandEndStyle.readyBlue.opacity(0.85)))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(HandEndStyle.readyBlue, lineWidth: 1))
    }
}

// MARK: - Mid-hand void flash (redeal / deck played through)

enum HandVoidFlashKind: Equatable {
    case redeal
    case playedThrough
}

/// Full-screen flash when a hand is voided with no score change (mutual redeal or deck played through).
struct HandVoidFlashInterstitial: View {
    let kind: HandVoidFlashKind

    private var title: String {
        switch kind {
        case .redeal: "Hand redealt!"
        case .playedThrough: "Hand played through!"
        }
    }

    private var subtitle: String {
        switch kind {
        case .redeal: "Fresh cards · same hand score"
        case .playedThrough: "Deck exhausted · same hand score"
        }
    }

    var body: some View {
        ZStack {
            GinRummyPalette.bgDeep
                .ignoresSafeArea()
            LinearGradient(
                colors: [
                    GinRummyPalette.bgPanel.opacity(0.45),
                    GinRummyPalette.bgDeep.opacity(0.92),
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            VStack(spacing: 10) {
                Text(title)
                    .font(.system(size: 34, weight: .black, design: .serif))
                    .foregroundStyle(GinRummyPalette.cream)
                    .multilineTextAlignment(.center)
                Text(subtitle)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(GinRummyPalette.gold)
                    .multilineTextAlignment(.center)
                Label("New deal starting", systemImage: "arrow.triangle.2.circlepath")
                    .font(.headline)
                    .foregroundStyle(GinRummyPalette.sage.opacity(0.95))
            }
            .padding(.horizontal, 26)
            .padding(.vertical, 30)
            .background(
                RoundedRectangle(cornerRadius: 20)
                    .fill(GinRummyPalette.bgDeep.opacity(0.94))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 20)
                    .stroke(GinRummyPalette.gold.opacity(0.55), lineWidth: 1.4)
            )
            .shadow(color: .black.opacity(0.45), radius: 18, y: 8)
            .padding(.horizontal, 16)
            .transition(.scale(scale: 0.86).combined(with: .opacity))
        }
    }
}

/// Backward-compatible alias for mutual redeal flash.
struct RedealFlashInterstitial: View {
    var body: some View {
        HandVoidFlashInterstitial(kind: .redeal)
    }
}

// MARK: - Knocker layout chooser

/// When the knock has more than one valid meld arrangement (same unmelded total),
/// the knocker picks which melds hit the table — it changes what the other player
/// can lay off.
struct KnockLayoutChooserView: View {
    let options: [MeldSolver.PartitionOption]
    /// The card being discarded to knock (context line only).
    let knockCard: String
    var onConfirm: (MeldSolver.PartitionOption) -> Void
    var onCancel: () -> Void

    @State private var selectedId: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text("Choose which melds go down. Your unmelded total is the same either way, but the melds you table decide what your opponent can lay off.")
                        .font(.subheadline)
                        .foregroundStyle(GinRummyPalette.sage)
                        .fixedSize(horizontal: false, vertical: true)
                    ForEach(options) { opt in
                        optionCard(opt)
                    }
                }
                .padding(14)
            }
            .background(GinRummyPalette.feltGradient.ignoresSafeArea())
            .navigationTitle("Knock — pick your melds")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { onCancel() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Knock") {
                        if let opt = options.first(where: { $0.id == selectedId }) {
                            onConfirm(opt)
                        }
                    }
                    .disabled(selectedId == nil)
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    @ViewBuilder
    private func optionCard(_ opt: MeldSolver.PartitionOption) -> some View {
        let isSelected = selectedId == opt.id
        VStack(alignment: .leading, spacing: 10) {
            MeldTableArrangement(melds: opt.melds.map { MeldDTO(type: $0.dtoType, cards: $0.cards) })
            DeadwoodRow(cards: opt.deadwood, points: opt.deadwoodPoints, label: "Stays in hand")
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(isSelected ? GinRummyPalette.gold.opacity(0.18) : GinRummyPalette.bgPanel.opacity(0.6))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(isSelected ? GinRummyPalette.gold : GinRummyPalette.gold.opacity(0.25), lineWidth: isSelected ? 2 : 1)
        )
        .contentShape(RoundedRectangle(cornerRadius: 14))
        .onTapGesture { selectedId = opt.id }
    }
}

// MARK: - Defender layoff table

/// The defender's turn after a knock: the knocker's melds are on the table, the
/// defender picks their own melds (suggestions offered), then taps unmelded cards
/// onto glowing knocker melds to lay off. Nothing is auto-optimized — Done locks it in.
struct LayoffArrangementView: View {
    let p: PlayerPerspective
    let knock: PlayerPerspective.KnockPerspective
    let opponentName: String
    var onSubmit: (_ ownMelds: [MeldSolver.Meld], _ layoffs: [(card: String, meldIndex: Int)]) -> Void

    struct StagedLayoff: Equatable {
        let card: String
        let meldIndex: Int
    }

    @State private var suggestions: [MeldSolver.PartitionOption] = []
    @State private var chosenOptionId: String?
    @State private var stagedLayoffs: [StagedLayoff] = []
    @State private var selectedCard: String?
    @State private var submitting = false

    private var hand: [String] { p.hands[p.seat] }

    private var chosenOption: MeldSolver.PartitionOption? {
        suggestions.first(where: { $0.id == chosenOptionId }) ?? suggestions.first
    }

    private var ownMeldedCards: Set<String> {
        Set(chosenOption?.melds.flatMap(\.cards) ?? [])
    }

    private var stagedCards: Set<String> { Set(stagedLayoffs.map(\.card)) }

    /// Knocker melds with staged layoffs applied, for display and eligibility checks.
    private var effectiveKnockerMelds: [MeldDTO] {
        var melds = knock.knockerMelds
        for lo in stagedLayoffs {
            guard lo.meldIndex < melds.count else { continue }
            let m = melds[lo.meldIndex]
            melds[lo.meldIndex] = MeldDTO(type: m.type, cards: m.cards + [lo.card])
        }
        return melds
    }

    /// Your cards that are neither in your melds nor staged as layoffs.
    private var remainingCards: [String] {
        MeldSolver.rankSorted(hand.filter { !ownMeldedCards.contains($0) && !stagedCards.contains($0) })
    }

    private var remainingPoints: Int {
        remainingCards.reduce(0) { $0 + MeldSolver.deadwoodValue($1) }
    }

    private var knockerDeadwoodPoints: Int {
        knock.knockerDeadwood.reduce(0) { $0 + MeldSolver.deadwoodValue($1) }
    }

    private var eligibleMeldIndices: Set<Int> {
        guard let card = selectedCard else { return [] }
        var out: Set<Int> = []
        for (i, m) in effectiveKnockerMelds.enumerated() {
            if MeldSolver.canExtend(meldType: m.type, cards: m.cards, with: card) {
                out.insert(i)
            }
        }
        return out
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            knockerSection
            Divider().overlay(GinRummyPalette.gold.opacity(0.35))
            yourSection
            footer
        }
        .onAppear { computeSuggestionsIfNeeded() }
        .onChange(of: hand) { _, _ in
            suggestions = []
            chosenOptionId = nil
            stagedLayoffs = []
            selectedCard = nil
            computeSuggestionsIfNeeded()
        }
    }

    // MARK: sections

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("\(opponentName) knocked")
                .font(.headline)
                .foregroundStyle(GinRummyPalette.cream)
            Text("Pick your melds, then tap an unmelded card and a glowing meld to lay it off. Whatever is left counts against you — Done locks it in.")
                .font(.caption)
                .foregroundStyle(GinRummyPalette.sage.opacity(0.95))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12).fill(GinRummyPalette.phaseKnockLayoff.opacity(0.16)))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(GinRummyPalette.phaseKnockLayoff.opacity(0.4)))
    }

    private var knockerSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text("\(opponentName.uppercased())'S MELDS")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(GinRummyPalette.cream)
                Text("their unmelded: \(knockerDeadwoodPoints)")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(GinRummyPalette.sage.opacity(0.95))
                Spacer(minLength: 0)
            }
            MeldTableArrangement(
                melds: effectiveKnockerMelds,
                laidOffCards: stagedCards,
                highlightedIndices: eligibleMeldIndices,
                onTapMeld: { i in attachSelectedCard(to: i) },
                onTapCardInMeld: { card, _ in unstage(card: card) }
            )
            if selectedCard != nil, eligibleMeldIndices.isEmpty {
                Text("That card doesn't fit any of their melds.")
                    .font(.caption.italic())
                    .foregroundStyle(GinRummyPalette.sage.opacity(0.95))
            }
        }
    }

    private var yourSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("YOUR MELDS")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(GinRummyPalette.cream)
                Spacer(minLength: 0)
            }
            if suggestions.count > 1 {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(Array(suggestions.enumerated()), id: \.element.id) { pair in
                            suggestionChip(index: pair.offset, option: pair.element)
                        }
                    }
                }
            }
            MeldTableArrangement(
                melds: (chosenOption?.melds ?? []).map { MeldDTO(type: $0.dtoType, cards: $0.cards) }
            )
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Text("YOUR REMAINING CARDS")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(HandEndStyle.deadwoodRed.opacity(0.95))
                    Text("\(remainingPoints) pts")
                        .font(.caption.bold().monospacedDigit())
                        .foregroundStyle(GinRummyPalette.cream)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(HandEndStyle.deadwoodRed.opacity(0.55)))
                    Spacer(minLength: 0)
                }
                if remainingCards.isEmpty {
                    Text("Nothing left unmelded.")
                        .font(.caption.italic())
                        .foregroundStyle(GinRummyPalette.sage.opacity(0.95))
                } else {
                    HStack(spacing: 6) {
                        ForEach(remainingCards, id: \.self) { c in
                            VStack(spacing: 2) {
                                PlayingCardView(
                                    card: c,
                                    selected: selectedCard == c,
                                    compact: true,
                                    onTap: { selectedCard = selectedCard == c ? nil : c }
                                )
                                Text("\(MeldSolver.deadwoodValue(c))")
                                    .font(.caption2.bold().monospacedDigit())
                                    .foregroundStyle(HandEndStyle.deadwoodRed.opacity(0.95))
                            }
                        }
                        Spacer(minLength: 0)
                    }
                }
            }
        }
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Button("Done — lock it in") {
                    guard let opt = chosenOption else { return }
                    submitting = true
                    onSubmit(opt.melds, stagedLayoffs.map { (card: $0.card, meldIndex: $0.meldIndex) })
                }
                .buttonStyle(.borderedProminent)
                .tint(GinRummyPalette.navy)
                .disabled(submitting || chosenOption == nil)

                if !stagedLayoffs.isEmpty {
                    Button("Reset layoffs") {
                        stagedLayoffs = []
                        selectedCard = nil
                    }
                    .buttonStyle(.bordered)
                    .tint(GinRummyPalette.gold)
                    .disabled(submitting)
                }
                Spacer(minLength: 0)
            }
            Text("You'll score \(remainingPoints) unmelded vs their \(knockerDeadwoodPoints). Tie or lower undercuts the knock for a 25-point bonus.")
                .font(.caption2)
                .foregroundStyle(GinRummyPalette.sage.opacity(0.9))
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    private func suggestionChip(index: Int, option: MeldSolver.PartitionOption) -> some View {
        let isOn = (chosenOption?.id == option.id)
        Button {
            chosenOptionId = option.id
            stagedLayoffs = []
            selectedCard = nil
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text("Melds \(index + 1)")
                    .font(.caption.weight(.semibold))
                Text(option.melds.isEmpty ? "No melds" : "\(option.melds.count) meld\(option.melds.count == 1 ? "" : "s") · \(option.deadwoodPoints) left")
                    .font(.caption2.monospacedDigit())
            }
            .foregroundStyle(isOn ? GinRummyPalette.navy : GinRummyPalette.cream)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(isOn ? GinRummyPalette.gold.opacity(0.92) : GinRummyPalette.bgPanel.opacity(0.72))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(GinRummyPalette.gold.opacity(isOn ? 1 : 0.3), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: actions

    private func computeSuggestionsIfNeeded() {
        guard suggestions.isEmpty, !hand.isEmpty else { return }
        suggestions = MeldSolver.allMaximalPartitions(hand)
        chosenOptionId = suggestions.first?.id
    }

    private func attachSelectedCard(to meldIndex: Int) {
        guard let card = selectedCard, eligibleMeldIndices.contains(meldIndex) else { return }
        stagedLayoffs.append(StagedLayoff(card: card, meldIndex: meldIndex))
        selectedCard = nil
    }

    /// Undo a staged layoff. Later layoffs that depended on the removed card
    /// (run extensions) are re-validated in order and dropped if now illegal.
    private func unstage(card: String) {
        guard stagedCards.contains(card) else { return }
        let kept = stagedLayoffs.filter { $0.card != card }
        var melds = knock.knockerMelds
        var revalidated: [StagedLayoff] = []
        for lo in kept {
            guard lo.meldIndex < melds.count else { continue }
            let m = melds[lo.meldIndex]
            if MeldSolver.canExtend(meldType: m.type, cards: m.cards, with: lo.card) {
                melds[lo.meldIndex] = MeldDTO(type: m.type, cards: m.cards + [lo.card])
                revalidated.append(lo)
            }
        }
        stagedLayoffs = revalidated
    }
}

// MARK: - Knocker waiting view (defender is arranging)

struct KnockerWaitingView: View {
    let knock: PlayerPerspective.KnockPerspective
    let opponentName: String

    private var knockerDeadwoodPoints: Int {
        knock.knockerDeadwood.reduce(0) { $0 + MeldSolver.deadwoodValue($1) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                ProgressView()
                    .tint(GinRummyPalette.gold)
                VStack(alignment: .leading, spacing: 2) {
                    Text("You knocked")
                        .font(.headline)
                        .foregroundStyle(GinRummyPalette.cream)
                    Text("\(opponentName) is choosing their melds and layoffs…")
                        .font(.caption)
                        .foregroundStyle(GinRummyPalette.sage.opacity(0.95))
                }
                Spacer(minLength: 0)
            }
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 12).fill(GinRummyPalette.phaseKnockLayoff.opacity(0.16)))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(GinRummyPalette.phaseKnockLayoff.opacity(0.4)))

            Text("YOUR MELDS")
                .font(.caption.weight(.bold))
                .foregroundStyle(GinRummyPalette.cream)
            MeldTableArrangement(melds: knock.knockerMeldsAfterLayoff ?? knock.knockerMelds)
            DeadwoodRow(
                cards: knock.knockerDeadwood,
                points: knockerDeadwoodPoints,
                label: "Your unmelded"
            )
        }
    }
}
