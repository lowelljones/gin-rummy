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
        inkColor(card)
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

// MARK: - Card metrics (single source of truth for card sizing)

/// Central place for card dimensions so sizes scale from the screen width
/// instead of being hardcoded in views.
enum CardMetrics {
    /// Standard playing-card aspect (height / width).
    static let aspect: CGFloat = 75.0 / 51.0

    /// Default compact card width (piles, table, reveals).
    static let compactWidth: CGFloat = 58
    /// Default full-size card width.
    static let fullWidth: CGFloat = 86

    static func height(for width: CGFloat) -> CGFloat { (width * aspect).rounded() }

    /// Width of each card in the player's full-bleed fanned hand. Cards overlap
    /// so the fan reaches both screen edges; bigger hands pack tighter.
    static func handCardWidth(availableWidth: CGFloat, count: Int) -> CGFloat {
        let w = max(availableWidth, 1)
        let n = max(count, 1)
        // Allow overlap so the fan spans edge-to-edge regardless of count.
        let target = w / (CGFloat(n) * 0.60 + 0.40)
        return min(104, max(64, target))
    }

    // MARK: Hand-end / knock-layoff layout

    /// Fraction of card width consumed by overlap in a meld row (~45% hidden per step).
    static let meldOverlapFraction: CGFloat = 0.45

    /// Horizontal padding inside a meld slot, scaled with card width.
    static func meldSlotPadding(for cardWidth: CGFloat) -> CGFloat { max(6, cardWidth * 0.12) }

    /// Width of an overlapped meld row at a given card size.
    static func meldRowWidth(cardWidth: CGFloat, cardCount: Int) -> CGFloat {
        guard cardCount > 0 else { return 0 }
        let pad = meldSlotPadding(for: cardWidth)
        let step = cardWidth * (1 - meldOverlapFraction)
        return pad * 2 + cardWidth + step * CGFloat(cardCount - 1)
    }

    /// Deadwood wraps past this many cards so a no-meld hand fits narrow screens.
    static let deadwoodMaxPerRow = 5

    /// Cards in the widest wrapped deadwood row (balanced split past the wrap point).
    static func deadwoodCardsInWidestRow(cardCount: Int) -> Int {
        guard cardCount > deadwoodMaxPerRow else { return cardCount }
        return Int((Double(cardCount) / 2).rounded(.up))
    }

    /// Width of a deadwood card row (no overlap), accounting for wrapping.
    static func deadwoodRowWidth(cardWidth: CGFloat, cardCount: Int) -> CGFloat {
        let n = deadwoodCardsInWidestRow(cardCount: cardCount)
        guard n > 0 else { return 0 }
        let spacing = max(4, cardWidth * 0.10)
        return CGFloat(n) * cardWidth + spacing * CGFloat(n - 1)
    }

    /// Largest card width that keeps every hand-end row within `availableWidth`.
    static func handEndCardWidth(
        availableWidth: CGFloat,
        meldCardCounts: [Int],
        maxDeadwoodCount: Int,
        minWidth: CGFloat = 34,
        maxWidth: CGFloat = compactWidth
    ) -> CGFloat {
        let width = max(availableWidth, 1)
        let gutter: CGFloat = 8

        func rowFits(_ cardWidth: CGFloat) -> Bool {
            let sorted = meldCardCounts.sorted(by: >)
            var rowWidths: [CGFloat] = []

            if sorted.count >= 2 {
                rowWidths.append(
                    meldRowWidth(cardWidth: cardWidth, cardCount: sorted[0])
                        + gutter
                        + meldRowWidth(cardWidth: cardWidth, cardCount: sorted[1])
                )
            } else if let only = sorted.first {
                rowWidths.append(meldRowWidth(cardWidth: cardWidth, cardCount: only))
            }

            if sorted.count > 2 {
                rowWidths.append(meldRowWidth(cardWidth: cardWidth, cardCount: sorted[2]))
            }
            if sorted.count > 3 {
                let extras = sorted.dropFirst(3)
                let extrasWidth = extras.reduce(CGFloat(0)) { partial, count in
                    partial + meldRowWidth(cardWidth: cardWidth, cardCount: count)
                } + gutter * CGFloat(extras.count - 1)
                rowWidths.append(extrasWidth)
            }

            let deadwoodWidth = deadwoodRowWidth(cardWidth: cardWidth, cardCount: maxDeadwoodCount)
            let widest = max(rowWidths.max() ?? 0, deadwoodWidth)
            return widest <= width
        }

        if rowFits(maxWidth) { return maxWidth }

        var lo = minWidth
        var hi = maxWidth
        for _ in 0 ..< 14 {
            let mid = (lo + hi) / 2
            if rowFits(mid) {
                lo = mid
            } else {
                hi = mid
            }
        }
        return floor(lo)
    }
}

// MARK: - Card back (shared face-down styling)

struct CardBackFace: View {
    var width: CGFloat
    var height: CGFloat? = nil
    var cornerRadius: CGFloat? = nil
    /// Gold double-border highlight (cut spread picker).
    var highlighted: Bool = false
    /// Spinner overlay while opponent's cut card is still hidden.
    var showProgress: Bool = false
    /// When true, draws the card's own drop shadow (e.g. cut spread). Off inside `PlayingCardView`.
    var castsShadow: Bool = false

    private var h: CGFloat { height ?? CardMetrics.height(for: width) }
    private var corner: CGFloat { cornerRadius ?? max(5, width * 0.10) }
    private var pad: CGFloat { max(3, width * 0.06) }

    private var goldStrong: Color { GinRummyPalette.gold.opacity(highlighted ? 0.62 : 0.42) }
    private var goldSoft: Color { GinRummyPalette.gold.opacity(highlighted ? 0.42 : 0.22) }

    var body: some View {
        RoundedRectangle(cornerRadius: corner)
            .fill(GinRummyPalette.cardBackGradient)
            .frame(width: width, height: h)
            .overlay {
                // Faint diagonal cross-hatch (guilloché), clipped to the card.
                CardBackHatch(spacing: max(5, width * 0.12))
                    .stroke(GinRummyPalette.gold.opacity(highlighted ? 0.16 : 0.10), lineWidth: 0.6)
                    .padding(pad * 0.7)
                    .clipShape(RoundedRectangle(cornerRadius: corner * 0.8))
            }
            .overlay {
                // Inner hairline frame.
                RoundedRectangle(cornerRadius: corner * 0.8)
                    .stroke(goldSoft, lineWidth: 1)
                    .padding(pad)
            }
            .overlay {
                // Rhombus crest around the spade.
                ZStack {
                    Rectangle()
                        .stroke(goldStrong, lineWidth: 1.4)
                        .frame(width: width * 0.46, height: width * 0.46)
                        .rotationEffect(.degrees(45))
                    Rectangle()
                        .stroke(goldSoft, lineWidth: 0.8)
                        .frame(width: width * 0.56, height: width * 0.56)
                        .rotationEffect(.degrees(45))
                    Image(systemName: "suit.spade.fill")
                        .font(.system(size: width * 0.26))
                        .foregroundStyle(goldStrong)
                }
            }
            .overlay {
                if highlighted {
                    RoundedRectangle(cornerRadius: corner)
                        .stroke(GinRummyPalette.gold, lineWidth: 2.4)
                        .padding(3)
                    RoundedRectangle(cornerRadius: corner)
                        .stroke(GinRummyPalette.gold.opacity(0.55), lineWidth: 1.6)
                }
            }
            .overlay {
                if showProgress {
                    ProgressView()
                        .tint(GinRummyPalette.gold)
                        .offset(y: h * 0.18)
                }
            }
            .shadow(
                color: .black.opacity(castsShadow ? (highlighted ? 0.4 : 0.2) : 0),
                radius: castsShadow ? (highlighted ? 10 : 3) : 0,
                y: castsShadow ? (highlighted ? 6 : 2) : 0
            )
    }
}

/// Diagonal cross-hatch used as a subtle guilloché on the card back.
private struct CardBackHatch: Shape {
    var spacing: CGFloat

    func path(in rect: CGRect) -> Path {
        var p = Path()
        let step = max(3, spacing)
        // Lines at +45°
        var x = rect.minX - rect.height
        while x < rect.maxX {
            p.move(to: CGPoint(x: x, y: rect.minY))
            p.addLine(to: CGPoint(x: x + rect.height, y: rect.maxY))
            x += step
        }
        // Lines at -45°
        x = rect.minX
        while x < rect.maxX + rect.height {
            p.move(to: CGPoint(x: x, y: rect.minY))
            p.addLine(to: CGPoint(x: x - rect.height, y: rect.maxY))
            x += step
        }
        return p
    }
}

// MARK: - Single card

struct PlayingCardView: View {
    let card: String
    var selected: Bool = false
    var faceDown: Bool = false
    var compact: Bool = false
    /// Explicit width override; height derives from the standard card aspect.
    var width: CGFloat? = nil
    var onTap: (() -> Void)? = nil

    private var cw: CGFloat { width ?? (compact ? CardMetrics.compactWidth : CardMetrics.fullWidth) }
    private var ch: CGFloat { CardMetrics.height(for: cw) }
    private var pad: CGFloat { max(3, cw * 0.06) }

    private var corner: CGFloat { max(5, cw * 0.10) }

    var body: some View {
        Group {
            if faceDown {
                CardBackFace(width: cw, height: ch, cornerRadius: corner)
            } else {
                RoundedRectangle(cornerRadius: corner)
                    .fill(PlayingCard.cardFaceGradient)
                    .overlay(
                        PlayingCardFaceContent(
                            card: card,
                            width: cw,
                            height: ch,
                            pad: pad,
                            corner: corner
                        )
                    )
            }
        }
        .frame(width: cw, height: ch)
        .background(
            // Solid base so nothing behind the card ever shows through.
            RoundedRectangle(cornerRadius: corner).fill(GinRummyPalette.cream.opacity(0.96))
        )
        .overlay(
            RoundedRectangle(cornerRadius: corner)
                .stroke(
                    selected ? GinRummyPalette.burgundy : PlayingCard.inkColor(card).opacity(0.22),
                    lineWidth: selected ? 2.5 : 1
                )
        )
        .shadow(color: .black.opacity(0.28), radius: selected ? 6 : 3, x: 0, y: selected ? 4 : 2)
        .onTapGesture { onTap?() }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(faceDown ? "Face-down card" : GameNarration.cardName(card))
        .accessibilityAddTraits(selected ? [.isSelected] : [])
        .accessibilityAddTraits(onTap != nil ? [.isButton] : [])
    }
}

/// Shared fan geometry: a full-bleed, bottom-aligned fan that spans the row
/// edge-to-edge. The leftmost card hugs the left edge and the rightmost hugs
/// the right edge; cards overlap as the hand grows. Pivot is the card bottom.
private enum CardFanLayout {
    static let hPad: CGFloat = 2

    /// Card width that fits both the available width (overlap) and height.
    static func cardWidth(n: Int, width: CGFloat, height: CGFloat) -> CGFloat {
        let byWidth = CardMetrics.handCardWidth(availableWidth: max(width - 2 * hPad, 1), count: n)
        // Leave a little vertical room for the fan arc / selection lift.
        let byHeight = max((height - 10), 1) / CardMetrics.aspect
        return max(44, min(byWidth, byHeight))
    }

    static let rotationPerCard: Double = 1.6

    /// Extra horizontal room a rotated edge card needs beyond half its width, so
    /// the tilted top corners (where the rank/suit live) never clip off-screen.
    static func edgeInset(n: Int, cardW: CGFloat) -> CGFloat {
        guard n > 1 else { return hPad }
        let cardH = cardW * CardMetrics.aspect
        let maxAngle = abs(rotation(index: 0, count: n)) * .pi / 180
        // Outer top corner x-extent of a card rotated about its bottom center.
        let halfExtent = (cardW / 2) * cos(maxAngle) + cardH * sin(maxAngle)
        let overhang = max(0, halfExtent - cardW / 2)
        return hPad + overhang
    }

    /// Horizontal center of card `i` measured from the row's left edge.
    /// First/last centers are inset enough that rotated corners stay on-screen.
    static func centerX(index i: Int, n: Int, width: CGFloat, cardW: CGFloat) -> CGFloat {
        guard n > 1 else { return width / 2 }
        let inset = edgeInset(n: n, cardW: cardW)
        let first = inset + cardW / 2
        let last = width - inset - cardW / 2
        guard last > first else { return width / 2 }
        let step = (last - first) / CGFloat(n - 1)
        return first + CGFloat(i) * step
    }

    static func step(n: Int, width: CGFloat, cardW: CGFloat) -> CGFloat {
        guard n > 1 else { return 0 }
        let inset = edgeInset(n: n, cardW: cardW)
        let first = inset + cardW / 2
        let last = width - inset - cardW / 2
        guard last > first else { return 0 }
        return (last - first) / CGFloat(n - 1)
    }

    static func rotation(index i: Int, count n: Int) -> Double {
        (Double(i) - 0.5 * Double(max(n - 1, 0))) * rotationPerCard
    }
}

/// Hand along the bottom of the row: same baseline, slight rotation, arc opens toward the table center.
/// Drag a card to rearrange the hand (no long-press); small movements still allow tap to select.
/// When `onDragDiscard` is set, dragging a card up past the release threshold discards it.
struct FannedHandRow: View {
    private enum HandReorderFeedback {
        static let lift = UIImpactFeedbackGenerator(style: .medium)
        static let slot = UIImpactFeedbackGenerator(style: .light)
    }

    /// How far up (pt) a card must be dragged before release discards it.
    private static let discardArmThreshold: CGFloat = 80

    let displayOrder: [String]
    @Binding var selected: String?
    var canReorder: Bool = false
    var onReorder: (([String]) -> Void)? = nil
    /// Non-nil when a plain discard is currently legal (your turn, 11 cards):
    /// drag a card up and release to discard it.
    var onDragDiscard: ((String) -> Void)? = nil
    /// Card just added to the hand — rendered with a short-lived gold glow.
    var recentlyDrawn: String? = nil

    @State private var draggingId: String? = nil
    @State private var dragStartIndex: Int? = nil
    @State private var dragTranslation: CGSize = .zero
    @State private var liveOrder: [String]? = nil
    @State private var lastInsertionIndex: Int? = nil
    @State private var dragDiscardArmed = false

    var body: some View {
        Group {
            if displayOrder.isEmpty {
                Text("—")
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            } else {
                GeometryReader { geo in
                    let effective = liveOrder ?? displayOrder
                    let n = effective.count
                    let cardW = CardFanLayout.cardWidth(n: n, width: geo.size.width, height: geo.size.height)
                    let step = CardFanLayout.step(n: n, width: geo.size.width, cardW: cardW)
                    ZStack(alignment: .bottom) {
                        ForEach(Array(effective.enumerated()), id: \.element) { pair in
                            cardCell(c: pair.element, i: pair.offset, n: n, width: geo.size.width, cardW: cardW, step: step)
                        }
                        if dragDiscardArmed {
                            Text("Release to discard")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(GinRummyPalette.cream)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(Capsule().fill(GinRummyPalette.burgundy.opacity(0.92)))
                                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                                .allowsHitTesting(false)
                                .transition(.opacity)
                                .zIndex(200)
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                }
            }
        }
        .frame(maxWidth: .infinity, minHeight: 96, maxHeight: .infinity)
        .onChange(of: displayOrder) { _, _ in
            if liveOrder != nil { resetDragState() }
        }
        .onDisappear { resetDragState() }
    }

    @ViewBuilder
    private func cardCell(c: String, i: Int, n: Int, width: CGFloat, cardW: CGFloat, step: CGFloat) -> some View {
        let isDragging = (c == draggingId)
        // Offset from the ZStack's horizontal center to this card's target center.
        let baseX = CardFanLayout.centerX(index: i, n: n, width: width, cardW: cardW) - width / 2
        let dragX: CGFloat = {
            guard isDragging, let from = dragStartIndex else { return 0 }
            return dragTranslation.width - CGFloat(i - from) * step
        }()
        let dragY: CGFloat = isDragging ? dragTranslation.height : 0
        let restRot = CardFanLayout.rotation(index: i, count: n)
        let isGlowing = c == recentlyDrawn && c != "HIDDEN"

        PlayingCardView(
            card: c,
            selected: selected == c,
            faceDown: c == "HIDDEN",
            width: cardW,
            onTap: {
                if c != "HIDDEN" { selected = selected == c ? nil : c }
            }
        )
        .overlay {
            if isGlowing {
                RoundedRectangle(cornerRadius: max(5, cardW * 0.10))
                    .stroke(GinRummyPalette.goldAccentSoft, lineWidth: 2.2)
                    .shadow(color: GinRummyPalette.goldAccent.opacity(0.85), radius: 7)
                    .allowsHitTesting(false)
                    .transition(.opacity)
            }
        }
        .rotationEffect(.degrees(isDragging ? 0 : restRot), anchor: .bottom)
        .scaleEffect(isDragging ? (dragDiscardArmed ? 1.14 : 1.08) : 1.0, anchor: .center)
        .offset(y: selected == c && !isDragging ? -14 : 0)
        .shadow(
            color: isDragging ? Color.black.opacity(0.28) : .clear,
            radius: isDragging ? 10 : 0,
            y: isDragging ? 6 : 0
        )
        .offset(x: baseX + dragX, y: dragY)
        .zIndex(isDragging ? 100 : Double(i))
        .animation(.spring(response: 0.25, dampingFraction: 0.8), value: selected == c)
        .animation(.easeOut(duration: 0.3), value: isGlowing)
        .gesture(
            makeReorderGesture(cardId: c, step: step),
            including: ((canReorder || onDragDiscard != nil) && c != "HIDDEN") ? .all : .subviews
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
        HandReorderFeedback.lift.prepare()
        withAnimation(.spring(response: 0.25, dampingFraction: 0.78)) {
            draggingId = cardId
            dragStartIndex = from
            liveOrder = displayOrder
        }
        HandReorderFeedback.lift.impactOccurred()
    }

    private func updateDrag(translation: CGSize, step: CGFloat) {
        guard draggingId != nil, let from = dragStartIndex else { return }
        dragTranslation = translation

        // Dragging up past the threshold arms discard-on-release (and pauses reordering).
        let armed = onDragDiscard != nil && translation.height < -Self.discardArmThreshold
        if armed != dragDiscardArmed {
            HandReorderFeedback.lift.prepare()
            withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                dragDiscardArmed = armed
                if armed { liveOrder = displayOrder }
            }
            HandReorderFeedback.lift.impactOccurred()
            if armed { lastInsertionIndex = from }
        }
        guard !armed else { return }

        guard canReorder, step > 0 else { return }
        let n = displayOrder.count
        let raw = Double(from) + Double(translation.width) / Double(step)
        let proposed = max(0, min(n - 1, Int(raw.rounded())))
        guard proposed != lastInsertionIndex else { return }
        lastInsertionIndex = proposed
        HandReorderFeedback.slot.prepare()
        withAnimation(.interactiveSpring(response: 0.28, dampingFraction: 0.82)) {
            var arr = displayOrder
            let card = arr.remove(at: from)
            arr.insert(card, at: proposed)
            liveOrder = arr
        }
        HandReorderFeedback.slot.impactOccurred()
    }

    private func commitDrag() {
        guard let dragged = draggingId else {
            resetDragState()
            return
        }
        if dragDiscardArmed, dragged != "HIDDEN" {
            withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) {
                resetDragState()
            }
            onDragDiscard?(dragged)
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
        dragDiscardArmed = false
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
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            } else {
                GeometryReader { geo in
                    let n = cardCount
                    let cardW = CardFanLayout.cardWidth(n: n, width: geo.size.width, height: geo.size.height)
                    ZStack(alignment: .bottom) {
                        ForEach(0 ..< n, id: \.self) { i in
                            let x = CardFanLayout.centerX(index: i, n: n, width: geo.size.width, cardW: cardW) - geo.size.width / 2
                            let rot = CardFanLayout.rotation(index: i, count: n)
                            PlayingCardView(
                                card: "AS",
                                faceDown: true,
                                width: cardW,
                                onTap: nil
                            )
                            .rotationEffect(.degrees(rot), anchor: .bottom)
                            .offset(x: x, y: 0)
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                }
            }
        }
        .frame(maxWidth: .infinity, minHeight: 70, maxHeight: .infinity)
    }
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

// MARK: - Messy discard pile (face-up cards peek through like a real toss)

/// Deterministic, slightly wonky stack geometry so the pile feels tossed but stable between renders.
private enum DiscardPileLayout {
    /// Face-up cards drawn in the pile (deepest = earliest discard still peeking through).
    static let maxVisibleCards = 5

    struct CardTransform {
        var offsetX: CGFloat = 0
        var offsetY: CGFloat = 0
        var rotation: Double = 0
    }

    static func transform(pileIndex: Int, totalCount: Int, card: String, cardWidth: CGFloat) -> CardTransform {
        let seed = stableHash(card: card, salt: pileIndex)

        // First upcard / pile foundation: perfectly flat and centered.
        if pileIndex == 0 {
            return CardTransform()
        }

        let isTop = pileIndex == totalCount - 1
        let depth = pileIndex // 1 = second card, 2 = third, …

        // Barely-there nudge — just enough for one corner to peek (~3–7 pt).
        let nudge = cardWidth * (0.028 + 0.010 * CGFloat(min(depth - 1, 3)))
        let wobbleX = pseudo(seed, 1) * cardWidth * 0.010
        let wobbleY = pseudo(seed, 2) * cardWidth * 0.008

        let (ox, oy): (CGFloat, CGFloat) = switch pileIndex % 4 {
        case 0: (nudge * 0.50 + wobbleX, nudge * 0.32 + wobbleY)
        case 1: (-nudge * 0.46 + wobbleX, nudge * 0.28 + wobbleY)
        case 2: (nudge * 0.42 + wobbleX, -nudge * 0.22 + wobbleY)
        default: (-nudge * 0.44 + wobbleX, -nudge * 0.20 + wobbleY)
        }

        // Tilt ramps up with each toss; top card gets a little extra lean.
        let baseRot = 4.0 + Double(min(depth, 4)) * 2.0
        let rotWobble = pseudo(seed, 3) * 2.4
        let sign: Double = pileIndex % 2 == 0 ? 1 : -1
        let topBoost = isTop ? 1.8 + abs(pseudo(seed, 4)) * 1.2 : 0
        let rotation = sign * (baseRot + rotWobble + topBoost)

        return CardTransform(offsetX: ox, offsetY: oy, rotation: rotation)
    }

    static func stackSpread(for cardWidth: CGFloat) -> CGFloat { cardWidth * 0.11 }

    private static func stableHash(card: String, salt: Int) -> UInt64 {
        var h = UInt64(bitPattern: Int64(salt &* 0x9E37))
        for u in card.utf8 { h = h &* 1_099_511_628_211 &+ UInt64(u) }
        return h
    }

    /// Stable value in `[-1, 1]`.
    private static func pseudo(_ seed: UInt64, _ channel: Int) -> CGFloat {
        let mixed = seed &+ UInt64(channel &* 0x517CC1B7)
        let unit = Double(mixed % 10_001) / 5_000.0 - 1.0
        return CGFloat(unit)
    }
}

struct DiscardPileStackView: View {
    let cards: [String]
    var cardWidth: CGFloat = CardMetrics.compactWidth
    /// When set, only the face-up top card is tappable (take discard / down card).
    var topOnTap: (() -> Void)? = nil
    var highlightTop: Bool = false

    private var cardHeight: CGFloat { CardMetrics.height(for: cardWidth) }
    private var cornerRadius: CGFloat { max(5, cardWidth * 0.10) }
    private var spread: CGFloat { DiscardPileLayout.stackSpread(for: cardWidth) }

    private var visibleSlice: [(pileIndex: Int, card: String)] {
        let start = max(0, cards.count - DiscardPileLayout.maxVisibleCards)
        return Array(cards.enumerated()).suffix(from: start).map { ($0.offset, $0.element) }
    }

    var body: some View {
        ZStack {
            ForEach(Array(visibleSlice.enumerated()), id: \.offset) { zIndex, entry in
                let isTop = entry.pileIndex == cards.count - 1
                let t = DiscardPileLayout.transform(
                    pileIndex: entry.pileIndex,
                    totalCount: cards.count,
                    card: entry.card,
                    cardWidth: cardWidth
                )
                PlayingCardView(
                    card: entry.card,
                    compact: true,
                    width: cardWidth,
                    onTap: isTop ? topOnTap : nil
                )
                .rotationEffect(.degrees(t.rotation))
                .offset(x: t.offsetX, y: t.offsetY)
                .zIndex(Double(zIndex))
                .allowsHitTesting(isTop)
                .overlay {
                    if isTop, highlightTop {
                        RoundedRectangle(cornerRadius: cornerRadius)
                            .stroke(GinRummyPalette.gold.opacity(0.72), lineWidth: 2)
                    }
                }
            }
        }
        .frame(width: cardWidth + spread * 2, height: cardHeight + spread * 2)
    }
}

/// Center table: draw pile (with count) + discard, reference-style.
struct StockAndDiscardPiles: View {
    let stockCount: Int
    let discard: [String]
    /// When set, tapping the face-up discard takes that card (down card: your turn; play: your turn, 10 cards).
    var discardOnTap: (() -> Void)? = nil
    /// When set, tapping the stock draws (play or upcard dealer draw).
    var stockOnTap: (() -> Void)? = nil

    private var pileW: CGFloat { CardMetrics.compactWidth }
    private var pileH: CGFloat { CardMetrics.height(for: pileW) }

    var body: some View {
        HStack(alignment: .center, spacing: 28) {
            VStack(spacing: 6) {
                Button {
                    stockOnTap?()
                } label: {
                    ZStack {
                        CardBackFace(width: pileW, height: pileH, cornerRadius: max(5, pileW * 0.10))
                        Text("\(max(0, stockCount))")
                            .font(.headline.weight(.bold))
                            .monospacedDigit()
                            .foregroundStyle(GinRummyPalette.cream)
                    }
                }
                .buttonStyle(.plain)
                .disabled(stockOnTap == nil || stockCount <= 1)
                .opacity(stockOnTap == nil || stockCount <= 1 ? 0.55 : 1)
                .tableFlightAnchor(.stock)
                Text("Deck")
                    .font(.caption2)
                    .foregroundStyle(GinRummyPalette.sage.opacity(0.92))
            }
            VStack(spacing: 6) {
                Group {
                    if discard.isEmpty {
                        RoundedRectangle(cornerRadius: max(5, pileW * 0.10))
                            .fill(GinRummyPalette.bgPanel.opacity(0.82))
                            .frame(width: pileW, height: pileH)
                            .overlay { Text("—").foregroundStyle(GinRummyPalette.sage.opacity(0.85)) }
                    } else {
                        DiscardPileStackView(
                            cards: discard,
                            cardWidth: pileW,
                            topOnTap: discardOnTap,
                            highlightTop: discardOnTap != nil
                        )
                    }
                }
                .tableFlightAnchor(.discardPile)
                Text("Discard")
                    .font(.caption2)
                    .foregroundStyle(GinRummyPalette.sage.opacity(0.92))
            }
        }
    }
}

// MARK: - Cut spread (overlapping slivers)

struct CutSpreadPicker: View {
    private enum CutSpreadFeedback {
        static let select = UIImpactFeedbackGenerator(style: .light)
        static let cross = UIImpactFeedbackGenerator(style: .light)
    }

    private static let scrollMinimumDistance: CGFloat = 14

    let cardCount: Int
    @Binding var highlightIndex: Int?

    /// Every card in the spread is a full-size face-down card; they overlap so
    /// only left edges show, with the rightmost card fully visible.
    private let fullW: CGFloat = 80
    private let cardH: CGFloat = 118
    private let lift: CGFloat = 24
    private let margin: CGFloat = 8

    @State private var dragHoverIndex: Int?
    @State private var isScrolling = false
    @State private var lastHapticIndex: Int?

    var body: some View {
        GeometryReader { geo in
            let n = max(0, cardCount)
            if n == 0 {
                Color.clear
            } else {
                let avail = geo.size.width
                let usable = max(fullW, avail - 2 * margin)
                let rawStep = n > 1 ? (usable - fullW) / CGFloat(n - 1) : 0
                // Keep cards overlapping (so the rightmost reads as the full card)
                // but never thinner than a hairline sliver.
                let step = n > 1 ? max(4, min(fullW * 0.5, rawStep)) : 0
                let spreadW = fullW + step * CGFloat(max(0, n - 1))
                let leading = max(margin, (avail - spreadW) / 2)
                let hover = isScrolling ? dragHoverIndex : highlightIndex
                ZStack(alignment: .topLeading) {
                    ForEach(0 ..< n, id: \.self) { i in
                        let isSel = highlightIndex == i
                        CardBackFace(
                            width: fullW,
                            height: cardH,
                            cornerRadius: 8,
                            highlighted: isSel,
                            castsShadow: true
                        )
                            .offset(
                                x: leading + CGFloat(i) * step,
                                y: cardYOffset(index: i, hoverIndex: hover, wave: isScrolling)
                            )
                            .zIndex(cardZIndex(index: i, hoverIndex: hover, isSelected: isSel, wave: isScrolling))
                            .animation(
                                isScrolling
                                    ? .interactiveSpring(response: 0.22, dampingFraction: 0.82)
                                    : .spring(response: 0.3, dampingFraction: 0.7),
                                value: hover
                            )
                            .accessibilityLabel("Card position \(i + 1) of \(n)")
                            .accessibilityAddTraits(isSel ? .isSelected : [])
                            .onTapGesture {
                                selectCard(at: i)
                            }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: Self.scrollMinimumDistance)
                        .onChanged { value in
                            let idx = indexAt(x: value.location.x, n: n, leading: leading, step: step)
                            if !isScrolling {
                                isScrolling = true
                                dragHoverIndex = idx
                                lastHapticIndex = idx
                            }
                            if idx != dragHoverIndex {
                                dragHoverIndex = idx
                            }
                            if idx != lastHapticIndex {
                                lastHapticIndex = idx
                                CutSpreadFeedback.cross.prepare()
                                CutSpreadFeedback.cross.impactOccurred()
                                highlightIndex = idx
                            }
                        }
                        .onEnded { _ in
                            isScrolling = false
                            dragHoverIndex = nil
                            lastHapticIndex = nil
                        }
                )
            }
        }
        .frame(height: cardH + lift + 4)
    }

    private func selectCard(at index: Int) {
        guard !isScrolling else { return }
        CutSpreadFeedback.select.prepare()
        CutSpreadFeedback.select.impactOccurred()
        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
            highlightIndex = index
        }
    }

    /// Wave lift only while scrolling; tap/random selection lifts a single card.
    private func cardYOffset(index: Int, hoverIndex: Int?, wave: Bool) -> CGFloat {
        guard let h = hoverIndex else { return lift }
        if !wave {
            return index == h ? 0 : lift
        }
        switch abs(index - h) {
        case 0: return 0
        case 1: return lift * 0.42
        case 2: return lift * 0.68
        default: return lift
        }
    }

    private func cardZIndex(index: Int, hoverIndex: Int?, isSelected: Bool, wave: Bool) -> Double {
        if isSelected { return 1000 }
        guard wave, let h = hoverIndex else { return Double(index) }
        return Double(index) + Double(max(0, 3 - abs(index - h))) * 100
    }

    private func indexAt(x: CGFloat, n: Int, leading: CGFloat, step: CGFloat) -> Int {
        guard n > 0 else { return 0 }
        if n == 1 { return 0 }
        let raw = (x - leading - fullW / 2) / step
        return max(0, min(n - 1, Int(raw.rounded())))
    }
}

// MARK: - Cut: zones + spread

struct CutForDealTable: View {
    let p: PlayerPerspective
    @Binding var highlightIndex: Int?
    @Binding var busy: Bool

    var body: some View {
        VStack(spacing: 18) {
            if let c = p.cut {
                HStack(alignment: .top, spacing: 28) {
                    zone(title: "You", state: youZoneState(c))
                    zone(title: "Opponent", state: opponentZoneState(c))
                }

                if c.youMustPick, !busy {
                    CutSpreadPicker(cardCount: c.faceDownRemaining, highlightIndex: $highlightIndex)
                } else if waitingForOpponent(c) {
                    Label("Waiting for opponent to draw…", systemImage: "hourglass")
                        .font(.subheadline)
                        .foregroundStyle(GinRummyPalette.sage.opacity(0.95))
                        .padding(.vertical, 8)
                }
            }
        }
        .frame(maxWidth: .infinity)
    }

    private enum ZoneState: Equatable {
        case card(String)
        case drawing
        case empty
    }

    private func youZoneState(_ c: PlayerPerspective.CutState) -> ZoneState {
        if let y = c.yourCut, !y.isEmpty { return .card(y) }
        return .empty
    }

    private func opponentZoneState(_ c: PlayerPerspective.CutState) -> ZoneState {
        if let t = c.theirCut, !t.isEmpty { return .card(t) }
        if c.yourCut != nil, !c.opponentHasPicked { return .drawing }
        return .empty
    }

    private func waitingForOpponent(_ c: PlayerPerspective.CutState) -> Bool {
        if c.youMustPick { return false }
        if c.yourCut != nil, !c.opponentHasPicked { return true }
        if p.seat != c.activePicker, c.yourCut == nil { return true }
        return false
    }

    @ViewBuilder
    private func zone(title: String, state: ZoneState) -> some View {
        VStack(spacing: 8) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(GinRummyPalette.cream)
            Group {
                switch state {
                case let .card(card):
                    PlayingCardView(card: card, compact: false, onTap: nil)
                        .transition(.scale.combined(with: .opacity))
                case .drawing:
                    placeholder
                        .overlay { ProgressView().tint(GinRummyPalette.gold) }
                case .empty:
                    placeholder
                        .overlay {
                            Image(systemName: "questionmark")
                                .font(.title2)
                                .foregroundStyle(GinRummyPalette.sage.opacity(0.5))
                        }
                }
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var placeholder: some View {
        RoundedRectangle(cornerRadius: 12)
            .fill(GinRummyPalette.bgPanel.opacity(0.5))
            .frame(width: 86, height: 124)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(GinRummyPalette.gold.opacity(0.25), style: StrokeStyle(lineWidth: 1, dash: [5, 4]))
            )
    }
}

// MARK: - Table anchors (real view positions for flight/deal animations)

/// Zones a card can fly between on the table.
enum TableFlightAnchor: String, CaseIterable {
    case stock, discardPile, myHand, opponentHand
}

/// Collects the on-screen frames of the table zones (in the "gameTable"
/// coordinate space) so animations land exactly on the piles and hands.
struct TableAnchorFramesKey: PreferenceKey {
    static var defaultValue: [String: CGRect] { [:] }
    static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) {
        value.merge(nextValue()) { _, new in new }
    }
}

extension View {
    /// Publish this view's frame as a named flight anchor.
    func tableFlightAnchor(_ anchor: TableFlightAnchor) -> some View {
        background(
            GeometryReader { geo in
                Color.clear.preference(
                    key: TableAnchorFramesKey.self,
                    value: [anchor.rawValue: geo.frame(in: .named("gameTable"))]
                )
            }
        )
    }
}

// MARK: - Deal animation (card backs fly from the stock to each seat)

/// Short non-blocking flourish at the start of each hand: card backs fly from
/// the stock to the two hands, alternating seats with a small stagger.
struct DealAnimationOverlay: View {
    var anchorFrames: [String: CGRect] = [:]
    var onFinished: () -> Void = {}

    private static let cardsPerSeat = 4
    private static let stagger: Double = 0.09
    private static let flightDuration: Double = 0.38

    var body: some View {
        GeometryReader { g in
            let w = g.size.width
            let h = g.size.height
            let from = anchorCenter(.stock) ?? CGPoint(x: w * 0.36, y: h * 0.45)
            let toMe = anchorCenter(.myHand) ?? CGPoint(x: w * 0.5, y: h * 0.9)
            let toOpp = anchorCenter(.opponentHand) ?? CGPoint(x: w * 0.5, y: h * 0.12)
            ZStack {
                ForEach(0 ..< (Self.cardsPerSeat * 2), id: \.self) { i in
                    DealFlightCard(
                        delay: Double(i) * Self.stagger,
                        duration: Self.flightDuration,
                        from: from,
                        // Non-dealer style alternation: you, opponent, you, …
                        to: i % 2 == 0 ? toMe : toOpp
                    )
                }
            }
        }
        .allowsHitTesting(false)
        .onAppear {
            let total = Double(Self.cardsPerSeat * 2) * Self.stagger + Self.flightDuration + 0.15
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: UInt64(total * 1_000_000_000))
                onFinished()
            }
        }
    }

    private func anchorCenter(_ a: TableFlightAnchor) -> CGPoint? {
        guard let rect = anchorFrames[a.rawValue], rect.width > 0 else { return nil }
        return CGPoint(x: rect.midX, y: rect.midY)
    }
}

private struct DealFlightCard: View {
    let delay: Double
    let duration: Double
    let from: CGPoint
    let to: CGPoint

    @State private var progress: CGFloat = 0

    var body: some View {
        PlayingCardView(card: "AS", faceDown: true, compact: true, onTap: nil)
            .position(
                x: from.x + (to.x - from.x) * progress,
                y: from.y + (to.y - from.y) * progress
            )
            .opacity(progress > 0.02 && progress < 0.97 ? 1 : 0)
            .onAppear {
                withAnimation(.timingCurve(0.25, 0.0, 0.3, 1.0, duration: duration).delay(delay)) {
                    progress = 1
                }
            }
    }
}

// MARK: - Draw / discard flight (table → hand or hand → discard)

/// Full-screen overlay: a card slides in a straight line between canonical
/// table zones with a gentle ease — like dealing a card, no spin or arc.
struct CardFlightAnimationOverlay: View {
    enum Route: Equatable {
        case drawFromStock(toOpponent: Bool)
        case drawFromDiscard(toOpponent: Bool)
        case discardFromHand(isOpponent: Bool)
    }

    let route: Route
    let card: String
    /// Measured table-zone frames; falls back to canonical points when empty.
    var anchorFrames: [String: CGRect] = [:]

    @State private var progress: CGFloat = 0

    private var faceDown: Bool {
        switch route {
        case .drawFromStock(let opp): return opp
        case .drawFromDiscard: return false
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
            let cx = from.x + (to.x - from.x) * progress
            let cy = from.y + (to.y - from.y) * progress
            // Subtle settle as the card lands; no spin or arc.
            let settle = 1 + 0.05 * sin(.pi * Double(progress))

            PlayingCardView(
                card: displayCard,
                faceDown: faceDown,
                compact: true,
                onTap: nil
            )
            .position(x: cx, y: cy)
            .scaleEffect(settle)
            .shadow(color: Color.black.opacity(0.22), radius: 6, y: 4)
            .opacity(progress < 0.03 ? 0 : 1)
        }
        .allowsHitTesting(false)
        .onAppear {
            progress = 0
            withAnimation(.timingCurve(0.2, 0.0, 0.1, 1.0, duration: 0.5)) {
                progress = 1
            }
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

    /// Real measured zone centers when available; otherwise the canonical
    /// normalized layout for the portrait table (opponent strip up top,
    /// stock/discard piles in the center, your hand along the bottom).
    private func point(fromAnchor a: Anchor, width: CGFloat, height: CGFloat) -> CGPoint {
        if let rect = anchorFrames[flightAnchor(for: a).rawValue], rect.width > 0 {
            return CGPoint(x: rect.midX, y: rect.midY)
        }
        switch a {
        case .stock:
            return CGPoint(x: width * 0.36, y: height * 0.45)
        case .discardPile:
            return CGPoint(x: width * 0.64, y: height * 0.45)
        case .myHand:
            return CGPoint(x: width * 0.5, y: height * 0.9)
        case .opponentHand:
            return CGPoint(x: width * 0.5, y: height * 0.12)
        }
    }

    private func flightAnchor(for a: Anchor) -> TableFlightAnchor {
        switch a {
        case .stock: .stock
        case .discardPile: .discardPile
        case .myHand: .myHand
        case .opponentHand: .opponentHand
        }
    }
}
