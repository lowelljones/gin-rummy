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
    private var rankFont: Font { .system(size: cw * 0.22, weight: .semibold) }
    private var cornerSuitFont: Font { .system(size: cw * 0.20, weight: .semibold) }
    private var centerSuitFont: Font { .system(size: cw * 0.44, weight: .regular) }
    private var pad: CGFloat { max(3, cw * 0.06) }

    private var cardBackGradient: LinearGradient {
        LinearGradient(
            colors: [GinRummyPalette.navy, GinRummyPalette.burgundy.opacity(0.9)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private var corner: CGFloat { max(5, cw * 0.10) }

    private var cardBackFiligree: some View {
        ZStack {
            RoundedRectangle(cornerRadius: corner * 0.8)
                .stroke(GinRummyPalette.gold.opacity(0.22), lineWidth: 1)
                .padding(pad)
            Image(systemName: "suit.spade.fill")
                .font(.system(size: cw * 0.34))
                .foregroundStyle(GinRummyPalette.gold.opacity(0.22))
        }
    }

    /// Opaque ivory face with a soft top-down sheen so cards read as solid
    /// objects on the felt rather than translucent panes.
    private var cardFaceFill: LinearGradient {
        LinearGradient(
            colors: [Color(red: 1.0, green: 0.99, blue: 0.96), Color(red: 0.95, green: 0.92, blue: 0.85)],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    var body: some View {
        Group {
            if faceDown {
                RoundedRectangle(cornerRadius: corner)
                    .fill(cardBackGradient)
                    .overlay { cardBackFiligree.opacity(0.35) }
            } else {
                RoundedRectangle(cornerRadius: corner)
                    .fill(cardFaceFill)
                    .overlay(
                        VStack(spacing: 0) {
                            HStack {
                                VStack(alignment: .leading, spacing: cw * 0.02) {
                                    Text(PlayingCard.displayRank(card))
                                        .font(rankFont)
                                        .fontWeight(.bold)
                                    Text(PlayingCard.suitSymbol(card))
                                        .font(cornerSuitFont)
                                }
                                Spacer()
                            }
                            Spacer()
                            Text(PlayingCard.suitSymbol(card))
                                .font(centerSuitFont)
                        }
                        .padding(pad)
                    )
                    .foregroundStyle(PlayingCard.suitColor(card))
            }
        }
        .frame(width: cw, height: ch)
        .background(
            // Solid base so nothing behind the card ever shows through.
            RoundedRectangle(cornerRadius: corner).fill(Color(red: 0.97, green: 0.95, blue: 0.9))
        )
        .overlay(
            RoundedRectangle(cornerRadius: corner)
                .stroke(
                    selected ? GinRummyPalette.burgundy : GinRummyPalette.navy.opacity(0.28),
                    lineWidth: selected ? 2.5 : 1
                )
        )
        .shadow(color: .black.opacity(0.28), radius: selected ? 6 : 3, x: 0, y: selected ? 4 : 2)
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
/// Drag a card to rearrange the hand (no long-press). Small movements still allow tap to select.
struct FannedHandRow: View {
    private enum HandReorderFeedback {
        static let lift = UIImpactFeedbackGenerator(style: .medium)
        static let slot = UIImpactFeedbackGenerator(style: .light)
    }

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

        PlayingCardView(
            card: c,
            selected: selected == c,
            faceDown: c == "HIDDEN",
            width: cardW,
            onTap: {
                if c != "HIDDEN" { selected = selected == c ? nil : c }
            }
        )
        .rotationEffect(.degrees(isDragging ? 0 : restRot), anchor: .bottom)
        .scaleEffect(isDragging ? 1.08 : 1.0, anchor: .center)
        .offset(y: selected == c && !isDragging ? -14 : 0)
        .shadow(
            color: isDragging ? Color.black.opacity(0.28) : .clear,
            radius: isDragging ? 10 : 0,
            y: isDragging ? 6 : 0
        )
        .offset(x: baseX + dragX, y: dragY)
        .zIndex(isDragging ? 100 : Double(i))
        .animation(.spring(response: 0.25, dampingFraction: 0.8), value: selected == c)
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
        guard step > 0 else { return }
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
                            Text("Knock limit: unmelded ≤ \(v)")
                                .font(.caption2)
                        } else {
                            Text("Ace first upcard: no knock this hand (house rule — not even with 1 deadwood).")
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
                        RoundedRectangle(cornerRadius: max(5, pileW * 0.10))
                            .fill(
                                LinearGradient(
                                    colors: [GinRummyPalette.navy, GinRummyPalette.burgundy.opacity(0.78)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: pileW, height: pileH)
                        Image(systemName: "suit.spade.fill")
                            .font(.system(size: pileW * 0.34))
                            .foregroundStyle(GinRummyPalette.gold.opacity(0.28))
                        Text("\(max(0, stockCount))")
                            .font(.headline.weight(.bold))
                            .monospacedDigit()
                            .foregroundStyle(GinRummyPalette.cream)
                    }
                }
                .buttonStyle(.plain)
                .disabled(stockOnTap == nil || stockCount <= 1)
                .opacity(stockOnTap == nil || stockCount <= 1 ? 0.55 : 1)
                Text("Deck")
                    .font(.caption2)
                    .foregroundStyle(GinRummyPalette.sage.opacity(0.92))
            }
            VStack(spacing: 6) {
                if let d = discardTop, !d.isEmpty {
                    PlayingCardView(card: d, compact: true, onTap: discardOnTap)
                        .overlay(
                            RoundedRectangle(cornerRadius: max(5, pileW * 0.10))
                                .stroke(discardOnTap == nil ? Color.clear : GinRummyPalette.gold.opacity(0.72), lineWidth: discardOnTap == nil ? 0 : 2)
                        )
                } else {
                    RoundedRectangle(cornerRadius: max(5, pileW * 0.10))
                        .fill(GinRummyPalette.bgPanel.opacity(0.82))
                        .frame(width: pileW, height: pileH)
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

    /// Every card in the spread is a full-size face-down card; they overlap so
    /// only left edges show, with the rightmost card fully visible.
    private let fullW: CGFloat = 80
    private let cardH: CGFloat = 118
    private let lift: CGFloat = 24
    private let margin: CGFloat = 8

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
                ZStack(alignment: .topLeading) {
                    ForEach(0 ..< n, id: \.self) { i in
                        let isSel = highlightIndex == i
                        cardBack(selected: isSel)
                            // Selected card lifts up above its own slot.
                            .offset(x: leading + CGFloat(i) * step, y: isSel ? 0 : lift)
                            .zIndex(isSel ? 1000 : Double(i))
                            .onTapGesture {
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                    highlightIndex = i
                                }
                            }
                            .accessibilityLabel("Card position \(i + 1) of \(n)")
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        }
        .frame(height: cardH + lift + 4)
    }

    private func cardBack(selected: Bool) -> some View {
        RoundedRectangle(cornerRadius: 8)
            .fill(
                LinearGradient(
                    colors: [GinRummyPalette.navy, GinRummyPalette.burgundy.opacity(0.92)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .frame(width: fullW, height: cardH)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(selected ? GinRummyPalette.gold : GinRummyPalette.gold.opacity(0.4),
                            lineWidth: selected ? 2.4 : 1)
                    .padding(3)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(selected ? GinRummyPalette.gold : GinRummyPalette.gold.opacity(0.25),
                            lineWidth: selected ? 2 : 0.8)
            )
            .overlay {
                Image(systemName: "suit.spade.fill")
                    .font(.system(size: fullW * 0.34))
                    .foregroundStyle(GinRummyPalette.gold.opacity(selected ? 0.9 : 0.45))
            }
            .shadow(color: .black.opacity(selected ? 0.4 : 0.2),
                    radius: selected ? 10 : 3, y: selected ? 6 : 2)
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

    /// Normalized layout tuned for the redesigned portrait table: opponent strip
    /// up top, stock/discard piles in the center, your hand along the bottom.
    private func point(fromAnchor a: Anchor, width: CGFloat, height: CGFloat) -> CGPoint {
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
}
