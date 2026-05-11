import SwiftUI
import UIKit

// MARK: - Card model helpers (align with backend `cards.ts`)

enum PlayingCard {
    static let rankOrder: [Character: Int] = [
        "A": 1, "2": 2, "3": 3, "4": 4, "5": 5, "6": 6, "7": 7, "8": 8, "9": 9, "T": 10, "J": 11, "Q": 12, "K": 13,
    ]

    static func isValidId(_ s: String) -> Bool { CardIdValidation.isValidFormat(s) }

    static func knockLimitValue(_ card: String) -> Int? {
        let u = CardIdValidation.normalize(card)
        guard u.count == 2 else { return nil }
        let r = u.first!
        if r == "A" { return nil }
        if r == "T" || r == "J" || r == "Q" || r == "K" { return 10 }
        return rankOrder[r]
    }

    static func suitColor(_ card: String) -> Color {
        let u = CardIdValidation.normalize(card)
        guard u.count == 2 else { return GinRummyPalette.navy }
        return u.last == "H" || u.last == "D"
            ? Color(red: 0.62, green: 0.12, blue: 0.12)
            : GinRummyPalette.navy.opacity(0.93)
    }

    static func suitSymbol(_ card: String) -> String {
        let u = CardIdValidation.normalize(card)
        guard u.count == 2 else { return "?" }
        switch u.last {
        case "S": return "♠"
        case "H": return "♥"
        case "D": return "♦"
        case "C": return "♣"
        default: return "?"
        }
    }

    static func displayRank(_ card: String) -> String {
        let u = CardIdValidation.normalize(card)
        guard u.count == 2 else { return "?" }
        let r = u.first!
        if r == "T" { return "10" }
        return String(r)
    }

    static func sortHand(_ ids: [String]) -> [String] {
        ids.sorted { a, b in
            let na = CardIdValidation.normalize(a)
            let nb = CardIdValidation.normalize(b)
            if na.count < 2 { return true }
            if nb.count < 2 { return false }
            let sa = na.last!
            let sb = nb.last!
            if sa != sb { return sa < sb }
            return (rankOrder[na.first!] ?? 0) < (rankOrder[nb.first!] ?? 0)
        }
    }
}

// MARK: - Single card

struct PlayingCardView: View {
    let card: String
    var selected: Bool = false
    var faceDown: Bool = false
    var compact: Bool = false
    var onTap: (() -> Void)? = nil

    // Scale cards up for table readability.
    private var cw: CGFloat { compact ? 51 : 78 }
    private var ch: CGFloat { compact ? 75 : 114 }
    private var rankFont: Font { compact ? .caption : .headline }
    private var suitFont: Font { compact ? .body : .title2 }
    private var pad: CGFloat { compact ? 3 : 5 }

    private var cardBackGradient: LinearGradient {
        LinearGradient(
            colors: [GinRummyPalette.navy, GinRummyPalette.burgundy.opacity(0.9)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private var cardBackFiligree: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 4)
                .stroke(GinRummyPalette.gold.opacity(0.22), lineWidth: 1)
                .padding(3)
            Image(systemName: "suit.spade.fill")
                .font(compact ? .caption : .title3)
                .foregroundStyle(GinRummyPalette.gold.opacity(0.22))
        }
    }

    var body: some View {
        Group {
            if faceDown {
                RoundedRectangle(cornerRadius: 5)
                    .fill(cardBackGradient)
                    .overlay { cardBackFiligree.opacity(0.35) }
            } else {
                RoundedRectangle(cornerRadius: 5)
                    .fill(GinRummyPalette.cream.opacity(0.97))
                    .overlay(
                        VStack(spacing: 0) {
                            HStack {
                                VStack(alignment: .leading, spacing: compact ? 0 : 1) {
                                    Text(PlayingCard.displayRank(card))
                                        .font(rankFont)
                                        .fontWeight(.semibold)
                                    Text(PlayingCard.suitSymbol(card))
                                        .font(compact ? .caption2 : .subheadline)
                                }
                                Spacer()
                            }
                            Spacer()
                            Text(PlayingCard.suitSymbol(card))
                                .font(compact ? .title2 : .largeTitle)
                        }
                        .padding(pad)
                    )
                    .foregroundStyle(PlayingCard.suitColor(card))
            }
        }
        .frame(width: cw, height: ch)
        .overlay(
            RoundedRectangle(cornerRadius: 5)
                .stroke(
                    selected ? GinRummyPalette.burgundy : GinRummyPalette.gold.opacity(0.42),
                    lineWidth: selected ? 2.5 : 1
                )
        )
        .onTapGesture { onTap?() }
    }
}

// MARK: - Opponent (may include HIDDEN)

struct OpponentHandRow: View {
    let cardIds: [String]

    var body: some View {
        handRows(cardIds: cardIds) { c in
            PlayingCardView(card: c, faceDown: c == "HIDDEN", compact: true, onTap: nil)
        }
    }
}

// MARK: - Tappable hand (order is local)

struct MyHandCardGrid: View {
    let displayOrder: [String]
    @Binding var selected: String?

    var body: some View {
        handRows(cardIds: displayOrder) { c in
            PlayingCardView(
                card: c,
                selected: selected == c,
                faceDown: c == "HIDDEN",
                compact: true,
                onTap: {
                    if c != "HIDDEN" { selected = selected == c ? nil : c }
                }
            )
        }
    }
}

/// Shared fan geometry: bottom-aligned fans that open *toward* the rest of the screen (pivot at bottom of each card).
private enum CardFanLayout {
    static func xStepMid(n: Int, width: CGFloat) -> (CGFloat, CGFloat) {
        let w = max(width, 1)
        let hPad: CGFloat = 4
        let baseW: CGFloat = 40
        let span = w - 2 * hPad - baseW
        let step: CGFloat = n > 1 ? min(18, span / CGFloat(n - 1)) : 0
        let mid = (CGFloat(n - 1) * step) / 2
        return (step, mid)
    }

    static func rotation(index i: Int, count n: Int) -> Double {
        (Double(i) - 0.5 * Double(max(n - 1, 0))) * 2.5
    }
}

/// Hand along the bottom of the row: same baseline, slight rotation, arc opens toward the table center.
/// Drag a card to rearrange the hand (no long-press). Small movements still allow tap to select.
struct FannedHandRow: View {
    let displayOrder: [String]
    @Binding var selected: String?
    var canReorder: Bool = false
    var onReorder: (([String]) -> Void)? = nil

    @State private var draggingId: String? = nil
    @State private var dragStartIndex: Int? = nil
    @State private var dragTranslation: CGSize = .zero
    @State private var liveOrder: [String]? = nil
    @State private var lastInsertionIndex: Int? = nil

    var body: some View {
        Group {
            if displayOrder.isEmpty {
                Text("—")
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, minHeight: 40, alignment: .center)
            } else {
                GeometryReader { geo in
                    let effective = liveOrder ?? displayOrder
                    let n = effective.count
                    let hPad: CGFloat = 4
                    let (step, mid) = CardFanLayout.xStepMid(n: n, width: geo.size.width)
                    ZStack(alignment: .bottom) {
                        ForEach(Array(effective.enumerated()), id: \.element) { pair in
                            cardCell(c: pair.element, i: pair.offset, n: n, hPad: hPad, step: step, mid: mid)
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                }
                .frame(height: 88)
            }
        }
        .onChange(of: displayOrder) { _, _ in
            if liveOrder != nil { resetDragState() }
        }
        .onDisappear { resetDragState() }
    }

    @ViewBuilder
    private func cardCell(c: String, i: Int, n: Int, hPad: CGFloat, step: CGFloat, mid: CGFloat) -> some View {
        let isDragging = (c == draggingId)
        let baseX = hPad + CGFloat(i) * step - mid
        let dragX: CGFloat = {
            guard isDragging, let from = dragStartIndex else { return 0 }
            return dragTranslation.width - CGFloat(i - from) * step
        }()
        let dragY: CGFloat = isDragging ? dragTranslation.height : 0
        let restRot = CardFanLayout.rotation(index: i, count: n)

        PlayingCardView(
            card: c,
            selected: selected == c,
            faceDown: c == "HIDDEN",
            compact: true,
            onTap: {
                if c != "HIDDEN" { selected = selected == c ? nil : c }
            }
        )
        .rotationEffect(.degrees(isDragging ? 0 : restRot), anchor: .bottom)
        .scaleEffect(isDragging ? 1.08 : 1.0, anchor: .center)
        .shadow(
            color: isDragging ? Color.black.opacity(0.28) : .clear,
            radius: isDragging ? 10 : 0,
            y: isDragging ? 6 : 0
        )
        .offset(x: baseX + dragX, y: dragY)
        .zIndex(isDragging ? 100 : Double(i))
        .gesture(
            makeReorderGesture(cardId: c, step: step),
            including: (canReorder && c != "HIDDEN") ? .all : .subviews
        )
    }

    private static let reorderDragMinimumDistance: CGFloat = 10

    private func makeReorderGesture(cardId: String, step: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: Self.reorderDragMinimumDistance)
            .onChanged { value in
                if draggingId == nil {
                    beginDrag(cardId: cardId)
                }
                updateDrag(translation: value.translation, step: step)
            }
            .onEnded { _ in
                commitDrag()
            }
    }

    private func beginDrag(cardId: String) {
        guard let from = displayOrder.firstIndex(of: cardId) else { return }
        dragTranslation = .zero
        lastInsertionIndex = from
        withAnimation(.spring(response: 0.25, dampingFraction: 0.78)) {
            draggingId = cardId
            dragStartIndex = from
            liveOrder = displayOrder
        }
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    }

    private func updateDrag(translation: CGSize, step: CGFloat) {
        guard draggingId != nil, let from = dragStartIndex else { return }
        dragTranslation = translation
        guard step > 0 else { return }
        let n = displayOrder.count
        let raw = Double(from) + Double(translation.width) / Double(step)
        let proposed = max(0, min(n - 1, Int(raw.rounded())))
        guard proposed != lastInsertionIndex else { return }
        lastInsertionIndex = proposed
        withAnimation(.interactiveSpring(response: 0.28, dampingFraction: 0.82)) {
            var arr = displayOrder
            let card = arr.remove(at: from)
            arr.insert(card, at: proposed)
            liveOrder = arr
        }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    private func commitDrag() {
        guard draggingId != nil else {
            resetDragState()
            return
        }
        let final = liveOrder
        withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) {
            if let final, final != displayOrder {
                onReorder?(final)
            }
            resetDragState()
        }
    }

    private func resetDragState() {
        draggingId = nil
        dragStartIndex = nil
        dragTranslation = .zero
        liveOrder = nil
        lastInsertionIndex = nil
    }
}

/// Opponent’s cards in the same fan as your hand, all backs.
struct FannedOpponentHandRow: View {
    let cardCount: Int

    var body: some View {
        Group {
            if cardCount == 0 {
                Text("—")
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, minHeight: 40, alignment: .center)
            } else {
                GeometryReader { geo in
                    let n = cardCount
                    let hPad: CGFloat = 4
                    let (step, mid) = CardFanLayout.xStepMid(n: n, width: geo.size.width)
                    ZStack(alignment: .bottom) {
                        ForEach(0 ..< n, id: \.self) { i in
                            let x = hPad + CGFloat(i) * step - mid
                            let rot = CardFanLayout.rotation(index: i, count: n)
                            PlayingCardView(
                                card: "AS",
                                faceDown: true,
                                compact: true,
                                onTap: nil
                            )
                            .rotationEffect(.degrees(rot), anchor: .bottom)
                            .offset(x: x, y: 0)
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                }
                .frame(height: 88)
            }
        }
    }
}

@ViewBuilder
private func handRows<C: View>(cardIds: [String], @ViewBuilder card: @escaping (String) -> C) -> some View {
    let n = cardIds.count
    let row1 = min(5, n)
    VStack(alignment: .center, spacing: 5) {
        HStack(spacing: 3) {
            ForEach(0..<row1, id: \.self) { i in
                card(cardIds[i])
            }
        }
        if n > 5 {
            HStack(spacing: 3) {
                ForEach(5..<n, id: \.self) { i in
                    card(cardIds[i])
                }
            }
        }
    }
    .frame(maxWidth: .infinity)
    .padding(.vertical, 4)
}

// MARK: - Seat + table

struct SeatInfoBar: View {
    let p: PlayerPerspective

    var body: some View {
        Text(dealerLine)
            .font(.caption)
            .foregroundStyle(GinRummyPalette.sage.opacity(0.92))
    }

    private var dealerLine: String {
        p.seat == p.dealer ? "You dealt" : "Opponent dealt"
    }
}

struct TableStateStrip: View {
    let p: PlayerPerspective
    var compact: Bool = false

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            if let kc = p.knockCheckCard, !kc.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Hand knock (first upcard)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    PlayingCardView(card: kc, compact: true, onTap: nil)
                    if !compact {
                        if let v = PlayingCard.knockLimitValue(kc) {
                            Text("Equality knock: deadwood \(v)")
                                .font(.caption2)
                        } else {
                            Text("That card is an ace: no equality knock this hand")
                                .font(.caption2)
                        }
                        Text("This card never changes for the hand— even if you take it into your hand, it is still the knock value.")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text("Discard pile top")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let t = p.discard.last, !p.discard.isEmpty {
                    PlayingCardView(card: t, compact: true, onTap: nil)
                } else {
                    Text("—")
                        .font(.title2)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

/// Center table: draw pile (with count) + discard, reference-style.
struct StockAndDiscardPiles: View {
    let stockCount: Int
    let discardTop: String?
    /// When set, tapping the face-up discard takes that card (play: your turn, 10 cards).
    var discardOnTap: (() -> Void)? = nil
    /// When set, tapping the stock draws (play or upcard dealer draw).
    var stockOnTap: (() -> Void)? = nil

    var body: some View {
        HStack(alignment: .center, spacing: 24) {
            VStack(spacing: 6) {
                Button {
                    stockOnTap?()
                } label: {
                    ZStack {
                        RoundedRectangle(cornerRadius: 5)
                            .fill(
                                LinearGradient(
                                    colors: [GinRummyPalette.navy, GinRummyPalette.burgundy.opacity(0.78)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 42, height: 62)
                        Image(systemName: "suit.spade.fill")
                            .font(.caption)
                            .foregroundStyle(GinRummyPalette.gold.opacity(0.28))
                        Text("\(max(0, stockCount))")
                            .font(.caption.weight(.bold))
                            .monospacedDigit()
                            .foregroundStyle(GinRummyPalette.cream)
                    }
                }
                .buttonStyle(.plain)
                .disabled(stockOnTap == nil || stockCount <= 0)
                .opacity(stockOnTap == nil || stockCount <= 0 ? 0.55 : 1)
                Text("Deck")
                    .font(.caption2)
                    .foregroundStyle(GinRummyPalette.sage.opacity(0.92))
            }
            VStack(spacing: 6) {
                if let d = discardTop, !d.isEmpty {
                    PlayingCardView(card: d, compact: true, onTap: discardOnTap)
                        .overlay(
                            RoundedRectangle(cornerRadius: 5)
                                .stroke(discardOnTap == nil ? Color.clear : GinRummyPalette.gold.opacity(0.72), lineWidth: discardOnTap == nil ? 0 : 2)
                        )
                } else {
                    RoundedRectangle(cornerRadius: 5)
                        .fill(GinRummyPalette.bgPanel.opacity(0.82))
                        .frame(width: 51, height: 75)
                        .overlay { Text("—").foregroundStyle(GinRummyPalette.sage.opacity(0.85)) }
                }
                Text("Discard")
                    .font(.caption2)
                    .foregroundStyle(GinRummyPalette.sage.opacity(0.92))
            }
        }
    }
}

struct OpponentActionBanner: View {
    let text: String
    var card: String?

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: "arrow.triangle.2.circlepath")
                .foregroundStyle(.orange)
            Text(text)
                .font(.subheadline.weight(.semibold))
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
            if let c = card, !c.isEmpty {
                PlayingCardView(card: c, compact: true, onTap: nil)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.orange.opacity(0.12))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.orange.opacity(0.3))
        )
    }
}

// MARK: - Cut phase: card flies from spread toward a zone, then the zone shows the result

struct CutCardFlyAnimationOverlay: View {
    enum Target { case you, opponent }
    let target: Target
    var onArrived: () -> Void = {}

    @State private var progress: CGFloat = 0

    var body: some View {
        GeometryReader { g in
            let w = g.size.width
            let h = g.size.height
            let from = CGPoint(x: w * 0.5, y: h * 0.88)
            let to: CGPoint = target == .you
                ? CGPoint(x: w * 0.2, y: h * 0.18)
                : CGPoint(x: w * 0.8, y: h * 0.18)
            let x = from.x + (to.x - from.x) * progress
            let y = from.y + (to.y - from.y) * progress
            PlayingCardView(
                card: "AS",
                faceDown: true,
                compact: true,
                onTap: nil
            )
            .position(x: x, y: y)
            .rotationEffect(.degrees(Double(1 - progress) * 18 * (target == .you ? -1 : 1)))
        }
        .allowsHitTesting(false)
        .onAppear {
            progress = 0
            withAnimation(.easeInOut(duration: 0.55)) {
                progress = 1
            }
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 550_000_000)
                onArrived()
            }
        }
    }
}

// MARK: - Cut spread (overlapping slivers)

struct CutSpreadPicker: View {
    let cardCount: Int
    @Binding var highlightIndex: Int?

    var body: some View {
        GeometryReader { geo in
            let n = max(0, cardCount)
            if n == 0 {
                Color.clear
            } else {
                let sliverW: CGFloat = 10
                let step: CGFloat = n > 1
                    ? min(8, (geo.size.width - sliverW) / CGFloat(n - 1))
                    : 0
                ZStack(alignment: .leading) {
                    ForEach(0..<n, id: \.self) { i in
                        RoundedRectangle(cornerRadius: 3)
                            .fill(
                                LinearGradient(
                                    colors: [Color.indigo, Color.purple],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: sliverW, height: 46)
                            .overlay(
                                RoundedRectangle(cornerRadius: 3)
                                    .stroke(highlightIndex == i ? Color.yellow : Color.white.opacity(0.25), lineWidth: highlightIndex == i ? 2 : 0.5)
                            )
                            .offset(x: CGFloat(i) * step)
                            .onTapGesture { highlightIndex = i }
                            .accessibilityLabel("Card position \(i) of \(n)")
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            }
        }
        .frame(height: 52)
    }
}

// MARK: - Cut: zones + spread

struct CutForDealTable: View {
    let p: PlayerPerspective
    @Binding var highlightIndex: Int?
    @Binding var busy: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let c = p.cut {
                turnHeader(c: c, seat: p.seat)
                HStack(alignment: .top, spacing: 8) {
                    youZone(c: c)
                    opponentZone(c: c)
                }
                if c.opponentHasPicked, c.youMustPick {
                    Text("Their card is out of the spread. Choose a position, then Select.")
                        .font(.caption.italic())
                        .foregroundStyle(.secondary)
                }
                if c.youMustPick, !busy {
                    CutSpreadPicker(cardCount: c.faceDownRemaining, highlightIndex: $highlightIndex)
                } else if !c.youMustPick, c.yourCut != nil, !c.opponentHasPicked {
                    HStack {
                        Image(systemName: "hourglass")
                        Text("Waiting for opponent to draw…")
                    }
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                } else if p.seat != c.activePicker, c.yourCut == nil, !c.youMustPick {
                    HStack {
                        Image(systemName: "hourglass")
                        Text("Waiting for opponent to draw…")
                    }
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                }
            }
        }
    }

    @ViewBuilder
    private func youZone(c: PlayerPerspective.CutState) -> some View {
        VStack(alignment: .center, spacing: 4) {
            Text("Your Card").font(.caption2).foregroundStyle(.secondary)
            if let y = c.yourCut, !y.isEmpty {
                PlayingCardView(card: y, compact: true, onTap: nil)
                    .transition(.scale.combined(with: .opacity))
            } else {
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.clear)
                    .frame(width: 51, height: 75)
                    .overlay { Text("—").foregroundStyle(.tertiary) }
            }
            Text(c.youMustPick ? "Pick below" : (c.yourCut == nil ? "—" : "In your zone"))
                .font(.caption2)
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private func opponentZone(c: PlayerPerspective.CutState) -> some View {
        VStack(alignment: .center, spacing: 4) {
            Text("Opponent Card")
                .font(.caption2)
                .foregroundStyle(.secondary)
            if let t = c.theirCut, !t.isEmpty {
                PlayingCardView(card: t, compact: true, onTap: nil)
                    .transition(.scale.combined(with: .opacity))
            } else if c.yourCut != nil, !c.opponentHasPicked {
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.orange.opacity(0.2))
                    .frame(width: 51, height: 75)
                    .overlay { ProgressView() }
            } else {
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.clear)
                    .frame(width: 51, height: 75)
                    .overlay { Text("—").foregroundStyle(.tertiary) }
            }
            Text(
                (c.theirCut != nil && !(c.theirCut?.isEmpty ?? true))
                    ? "Their draw"
                    : (c.yourCut != nil && !c.opponentHasPicked ? "Drawing…" : "—")
            )
            .font(.caption2)
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private func turnHeader(c: PlayerPerspective.CutState, seat: Int) -> some View {
        if c.youMustPick {
            Text("Highlight a position, tap Select, or use Random card.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        } else if seat != c.activePicker, c.yourCut == nil {
            Text("Opponent draws first.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Staggered cut result

struct StaggeredCutResultBanner: View {
    let last: PlayerPerspective.LastCutResult
    let youAreSeat: Int
    /// Large typography and cards for a full-screen interstitial.
    var prominent: Bool = false
    @State private var step = 0
    @State private var doneTask: Task<Void, Never>?

    var body: some View {
        VStack(alignment: .leading, spacing: prominent ? 20 : 10) {
            Text("Cut")
                .font(prominent ? .title2.weight(.semibold) : .headline)
            if step >= 1 {
                HStack(alignment: .top, spacing: 16) {
                    VStack(alignment: .leading) {
                        Text(labelYou(0)).font(prominent ? .headline : .caption2)
                        PlayingCardView(
                            card: last.p0,
                            compact: !prominent,
                            onTap: nil
                        )
                    }
                    if step >= 2 {
                        VStack(alignment: .leading) {
                            Text(labelYou(1)).font(prominent ? .headline : .caption2)
                            PlayingCardView(
                                card: last.p1,
                                compact: !prominent,
                                onTap: nil
                            )
                        }
                        .transition(.move(edge: .trailing).combined(with: .opacity))
                    }
                }
            }
            if step >= 3 {
                Text(winnerText)
                    .font(prominent ? .title3 : .subheadline)
                    .fixedSize(horizontal: false, vertical: true)
                    .transition(.opacity)
            }
        }
        .padding(prominent ? 24 : 16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: prominent ? 16 : 12).fill(Color.accentColor.opacity(0.12)))
        .overlay(RoundedRectangle(cornerRadius: prominent ? 16 : 12).stroke(Color.accentColor.opacity(0.3)))
        .onAppear { runSequence() }
        .onDisappear { doneTask?.cancel() }
    }

    private var winnerText: String {
        // nonDealer had the higher cut; dealer is the other seat.
        youAreSeat == last.nonDealer ? "Opponent deals." : "You deal."
    }

    private func labelYou(_ seat: Int) -> String {
        youAreSeat == seat ? "You" : "Opponent"
    }

    private func runSequence() {
        step = 0
        doneTask?.cancel()
        doneTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 400_000_000)
            withAnimation { step = 1 }
            try? await Task.sleep(nanoseconds: 1_200_000_000)
            withAnimation { step = 2 }
            try? await Task.sleep(nanoseconds: 1_200_000_000)
            withAnimation { step = 3 }
        }
    }
}

// MARK: - Draw / discard flight (table → hand or hand → discard)

/// Full-screen overlay: a card moves along a curved path with spin between canonical table zones.
struct CardFlightAnimationOverlay: View {
    enum Route: Equatable {
        case drawFromStock(toOpponent: Bool)
        case drawFromDiscard(toOpponent: Bool)
        case discardFromHand(isOpponent: Bool)
    }

    let route: Route
    let card: String

    @State private var progress: CGFloat = 0

    private var faceDown: Bool {
        switch route {
        case .drawFromStock(let opp), .drawFromDiscard(let opp): return opp
        case .discardFromHand: return false
        }
    }

    private var displayCard: String {
        if faceDown { return "AS" }
        let n = CardIdValidation.normalize(card)
        return CardIdValidation.isValidFormat(n) ? n : "AS"
    }

    var body: some View {
        GeometryReader { g in
            let w = g.size.width
            let h = g.size.height
            let from = point(fromAnchor: fromAnchor, width: w, height: h)
            let to = point(fromAnchor: toAnchor, width: w, height: h)
            let arcX = sin(.pi * progress) * min(w, h) * 0.05
            let cx = from.x + (to.x - from.x) * progress + arcX
            let cy = from.y + (to.y - from.y) * progress
            let spin = Double(progress) * 420
            let wobble = Double(1 - progress) * 22 * (routeDiscardsToRight ? 1 : -1)

            PlayingCardView(
                card: displayCard,
                faceDown: faceDown,
                compact: true,
                onTap: nil
            )
            .position(x: cx, y: cy)
            .rotationEffect(.degrees(wobble + spin))
            .scaleEffect(1 + 0.1 * sin(.pi * Double(progress)))
            .shadow(color: Color.black.opacity(0.22), radius: progress > 0.1 ? 8 : 2, y: 5)
        }
        .allowsHitTesting(false)
        .onAppear {
            progress = 0
            withAnimation(.timingCurve(0.33, 0.0, 0.2, 1.0, duration: 0.62)) {
                progress = 1
            }
        }
    }

    private var routeDiscardsToRight: Bool {
        switch route {
        case .discardFromHand: return true
        case .drawFromStock, .drawFromDiscard: return false
        }
    }

    private enum Anchor {
        case stock, discardPile, myHand, opponentHand
    }

    private var fromAnchor: Anchor {
        switch route {
        case .drawFromStock:
            return .stock
        case .drawFromDiscard:
            return .discardPile
        case .discardFromHand(let isOpponent):
            return isOpponent ? .opponentHand : .myHand
        }
    }

    private var toAnchor: Anchor {
        switch route {
        case .drawFromStock(let toOpponent), .drawFromDiscard(let toOpponent):
            return toOpponent ? .opponentHand : .myHand
        case .discardFromHand:
            return .discardPile
        }
    }

    /// Normalized layout tuned for portrait table: stock left-of-center, discard right-of-center, hands top/bottom.
    private func point(fromAnchor a: Anchor, width: CGFloat, height: CGFloat) -> CGPoint {
        switch a {
        case .stock:
            return CGPoint(x: width * 0.36, y: height * 0.46)
        case .discardPile:
            return CGPoint(x: width * 0.64, y: height * 0.46)
        case .myHand:
            return CGPoint(x: width * 0.44, y: height * 0.88)
        case .opponentHand:
            return CGPoint(x: width * 0.44, y: height * 0.23)
        }
    }
}
