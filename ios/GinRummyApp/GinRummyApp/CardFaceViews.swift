import SwiftUI

// MARK: - Card face rendering (pip layouts + court art)

extension PlayingCard {
    static func rankChar(_ card: String) -> Character? {
        let u = CardIdValidation.normalize(card)
        guard u.count == 2 else { return nil }
        return u.first
    }

    static func suitChar(_ card: String) -> Character? {
        let u = CardIdValidation.normalize(card)
        guard u.count == 2 else { return nil }
        return u.last
    }

    static func isRedSuit(_ card: String) -> Bool {
        guard let s = suitChar(card) else { return false }
        return s == "H" || s == "D"
    }

    /// Ink color for card faces — muted burgundy / navy to match the felt table.
    static func inkColor(_ card: String) -> Color {
        isRedSuit(card) ? GinRummyPalette.burgundy.opacity(0.92) : GinRummyPalette.navy.opacity(0.93)
    }

    static func suitSystemName(_ card: String) -> String {
        switch suitChar(card) {
        case "S": return "suit.spade.fill"
        case "H": return "suit.heart.fill"
        case "D": return "suit.diamond.fill"
        case "C": return "suit.club.fill"
        default: return "suit.spade.fill"
        }
    }

    static var cardFaceGradient: LinearGradient {
        LinearGradient(
            colors: [
                Color(red: 0.99, green: 0.975, blue: 0.945),
                Color(red: 0.955, green: 0.935, blue: 0.895),
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }
}

// MARK: - Suit glyphs

/// Corner indices — SF Symbols read cleanly at small size.
private struct CardCornerSuitGlyph: View {
    let card: String
    var size: CGFloat

    var body: some View {
        Image(systemName: PlayingCard.suitSystemName(card))
            .font(.system(size: size, weight: .medium))
            .foregroundStyle(PlayingCard.inkColor(card))
    }
}

/// Center pips — Unicode suits match classic card proportions.
private struct CardPipSymbol: View {
    let card: String
    var size: CGFloat

    var body: some View {
        Text(PlayingCard.suitSymbol(card))
            .font(.system(size: size))
            .foregroundStyle(PlayingCard.inkColor(card))
            .frame(width: size * 1.05, height: size * 1.15)
    }
}

// MARK: - Pip positions (standard Anglo-American layouts)

private enum CardPipLayout {
    struct Pip {
        var x: CGFloat
        var y: CGFloat
        var inverted: Bool
    }

    private static let lx: CGFloat = 0.28
    private static let rx: CGFloat = 0.72
    private static let cx: CGFloat = 0.50
    private static let y1: CGFloat = 0.16
    private static let y2: CGFloat = 0.36
    private static let y3: CGFloat = 0.50
    private static let y4: CGFloat = 0.64
    private static let y5: CGFloat = 0.84

    static func pips(for rank: Character) -> [Pip] {
        switch rank {
        case "2":
            return [p(cx, y1, false), p(cx, y5, true)]
        case "3":
            return [p(cx, y1, false), p(cx, y3, false), p(cx, y5, true)]
        case "4":
            return corners()
        case "5":
            return corners() + [p(cx, y3, false)]
        case "6":
            return columnSix()
        case "7":
            return columnSix() + [p(cx, 0.26, false)]
        case "8":
            return [
                p(lx, 0.14, false), p(rx, 0.14, false),
                p(lx, 0.34, false), p(rx, 0.34, false),
                p(lx, 0.66, true), p(rx, 0.66, true),
                p(lx, 0.86, true), p(rx, 0.86, true),
            ]
        case "9":
            return grid3x3()
        case "T":
            return grid3x3() + [p(cx, 0.40, false), p(cx, 0.60, true)]
        default:
            return []
        }
    }

    private static func p(_ x: CGFloat, _ y: CGFloat, _ inverted: Bool) -> Pip {
        Pip(x: x, y: y, inverted: inverted)
    }

    private static func corners() -> [Pip] {
        [p(lx, y1, false), p(rx, y1, false), p(lx, y5, true), p(rx, y5, true)]
    }

    private static func columnSix() -> [Pip] {
        [p(lx, y1, false), p(rx, y1, false), p(lx, y3, false), p(rx, y3, false), p(lx, y5, true), p(rx, y5, true)]
    }

    private static func grid3x3() -> [Pip] {
        let xs: [CGFloat] = [0.26, cx, 0.74]
        let ys: [CGFloat] = [y1, y3, y5]
        return ys.flatMap { y in
            xs.map { x in p(x, y, y > 0.55) }
        }
    }
}

// MARK: - Court card line art (stroke-based, traditional silhouettes)

private struct CardCourtArt: View {
    let rank: Character
    let card: String

    private var ink: Color { PlayingCard.inkColor(card) }
    private var suit: String { PlayingCard.suitSymbol(card) }

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            let stroke = max(1.0, min(w, h) * 0.028)

            ZStack {
                RoundedRectangle(cornerRadius: max(2, w * 0.04))
                    .stroke(ink.opacity(0.16), lineWidth: 0.75)
                    .padding(w * 0.04)

                ZStack {
                    switch rank {
                    case "J":
                        JackCourtShape()
                            .stroke(ink, style: StrokeStyle(lineWidth: stroke, lineCap: .round, lineJoin: .round))
                    case "Q":
                        QueenCourtShape()
                            .stroke(ink, style: StrokeStyle(lineWidth: stroke, lineCap: .round, lineJoin: .round))
                    case "K":
                        KingCourtShape()
                            .stroke(ink, style: StrokeStyle(lineWidth: stroke, lineCap: .round, lineJoin: .round))
                    default:
                        EmptyView()
                    }

                    Text(suit)
                        .font(.system(size: min(w, h) * 0.17, weight: .semibold))
                        .foregroundStyle(ink)
                        .offset(y: h * 0.14)
                }
                .padding(.horizontal, w * 0.10)
                .padding(.vertical, h * 0.06)
            }
        }
    }
}

/// One-eyed Jack: profile bust facing the staff (classic playing-card pose).
private struct JackCourtShape: Shape {
    func path(in rect: CGRect) -> Path {
        let w = rect.width
        let h = rect.height
        var p = Path()

        // Staff
        let staffX = rect.maxX - w * 0.06
        p.move(to: CGPoint(x: staffX, y: rect.minY + h * 0.04))
        p.addLine(to: CGPoint(x: staffX, y: rect.maxY - h * 0.04))
        p.addEllipse(in: CGRect(x: staffX - w * 0.045, y: rect.minY, width: w * 0.09, height: w * 0.09))

        // Head (profile oval)
        let head = CGRect(x: rect.minX + w * 0.14, y: rect.minY + h * 0.06, width: w * 0.30, height: h * 0.24)
        p.addEllipse(in: head)

        // Cap / hair
        p.move(to: CGPoint(x: head.minX + w * 0.04, y: head.minY + h * 0.04))
        p.addQuadCurve(
            to: CGPoint(x: head.maxX - w * 0.02, y: head.minY + h * 0.02),
            control: CGPoint(x: head.midX, y: head.minY - h * 0.04)
        )

        // Nose & chin profile
        p.move(to: CGPoint(x: head.midX + w * 0.06, y: head.minY + h * 0.10))
        p.addQuadCurve(
            to: CGPoint(x: head.midX + w * 0.10, y: head.midY),
            control: CGPoint(x: head.midX + w * 0.12, y: head.minY + h * 0.14)
        )
        p.addQuadCurve(
            to: CGPoint(x: head.midX + w * 0.02, y: head.maxY - h * 0.02),
            control: CGPoint(x: head.midX + w * 0.10, y: head.maxY - h * 0.04)
        )

        // Neck & shoulder
        p.move(to: CGPoint(x: head.midX, y: head.maxY))
        p.addQuadCurve(
            to: CGPoint(x: rect.minX + w * 0.22, y: rect.minY + h * 0.52),
            control: CGPoint(x: rect.minX + w * 0.10, y: rect.minY + h * 0.44)
        )

        // Torso & arm toward staff
        p.addQuadCurve(
            to: CGPoint(x: staffX - w * 0.04, y: rect.minY + h * 0.46),
            control: CGPoint(x: rect.minX + w * 0.44, y: rect.minY + h * 0.50)
        )
        p.addQuadCurve(
            to: CGPoint(x: rect.minX + w * 0.18, y: rect.maxY - h * 0.06),
            control: CGPoint(x: rect.minX + w * 0.30, y: rect.maxY - h * 0.02)
        )
        p.addQuadCurve(
            to: CGPoint(x: head.midX - w * 0.02, y: head.maxY),
            control: CGPoint(x: rect.minX + w * 0.08, y: rect.minY + h * 0.62)
        )

        return p
    }
}

/// Symmetric Queen: crown, face, and bell-shaped gown.
private struct QueenCourtShape: Shape {
    func path(in rect: CGRect) -> Path {
        let w = rect.width
        let h = rect.height
        let cx = rect.midX
        var p = Path()

        // Crown
        let crownY = rect.minY + h * 0.04
        p.move(to: CGPoint(x: cx - w * 0.20, y: crownY + h * 0.06))
        p.addLine(to: CGPoint(x: cx - w * 0.14, y: crownY))
        p.addLine(to: CGPoint(x: cx - w * 0.07, y: crownY + h * 0.05))
        p.addLine(to: CGPoint(x: cx, y: crownY - h * 0.01))
        p.addLine(to: CGPoint(x: cx + w * 0.07, y: crownY + h * 0.05))
        p.addLine(to: CGPoint(x: cx + w * 0.14, y: crownY))
        p.addLine(to: CGPoint(x: cx + w * 0.20, y: crownY + h * 0.06))

        // Face
        let face = CGRect(x: cx - w * 0.13, y: rect.minY + h * 0.14, width: w * 0.26, height: h * 0.18)
        p.addEllipse(in: face)

        // Neck
        p.move(to: CGPoint(x: cx - w * 0.04, y: face.maxY))
        p.addLine(to: CGPoint(x: cx - w * 0.06, y: rect.minY + h * 0.36))
        p.move(to: CGPoint(x: cx + w * 0.04, y: face.maxY))
        p.addLine(to: CGPoint(x: cx + w * 0.06, y: rect.minY + h * 0.36))

        // Gown
        let shoulderY = rect.minY + h * 0.36
        p.move(to: CGPoint(x: cx - w * 0.18, y: shoulderY))
        p.addLine(to: CGPoint(x: cx + w * 0.18, y: shoulderY))
        p.addQuadCurve(
            to: CGPoint(x: cx + w * 0.24, y: rect.maxY - h * 0.04),
            control: CGPoint(x: cx + w * 0.26, y: rect.minY + h * 0.68)
        )
        p.addQuadCurve(
            to: CGPoint(x: cx - w * 0.24, y: rect.maxY - h * 0.04),
            control: CGPoint(x: cx, y: rect.maxY + h * 0.02)
        )
        p.addQuadCurve(
            to: CGPoint(x: cx - w * 0.18, y: shoulderY),
            control: CGPoint(x: cx - w * 0.26, y: rect.minY + h * 0.68)
        )

        // Sleeves
        p.move(to: CGPoint(x: cx - w * 0.18, y: shoulderY + h * 0.02))
        p.addQuadCurve(
            to: CGPoint(x: cx - w * 0.28, y: rect.minY + h * 0.52),
            control: CGPoint(x: cx - w * 0.32, y: rect.minY + h * 0.40)
        )
        p.move(to: CGPoint(x: cx + w * 0.18, y: shoulderY + h * 0.02))
        p.addQuadCurve(
            to: CGPoint(x: cx + w * 0.28, y: rect.minY + h * 0.52),
            control: CGPoint(x: cx + w * 0.32, y: rect.minY + h * 0.40)
        )

        return p
    }
}

/// Symmetric King: crown with cross, beard, robe, and sword.
private struct KingCourtShape: Shape {
    func path(in rect: CGRect) -> Path {
        let w = rect.width
        let h = rect.height
        let cx = rect.midX
        var p = Path()

        // Crown
        let crownY = rect.minY + h * 0.03
        p.move(to: CGPoint(x: cx - w * 0.22, y: crownY + h * 0.08))
        p.addLine(to: CGPoint(x: cx - w * 0.16, y: crownY))
        p.addLine(to: CGPoint(x: cx - w * 0.08, y: crownY + h * 0.06))
        p.addLine(to: CGPoint(x: cx, y: crownY - h * 0.02))
        p.addLine(to: CGPoint(x: cx + w * 0.08, y: crownY + h * 0.06))
        p.addLine(to: CGPoint(x: cx + w * 0.16, y: crownY))
        p.addLine(to: CGPoint(x: cx + w * 0.22, y: crownY + h * 0.08))
        // Cross atop crown
        p.move(to: CGPoint(x: cx, y: crownY - h * 0.02))
        p.addLine(to: CGPoint(x: cx, y: crownY - h * 0.10))
        p.move(to: CGPoint(x: cx - w * 0.04, y: crownY - h * 0.06))
        p.addLine(to: CGPoint(x: cx + w * 0.04, y: crownY - h * 0.06))

        // Face
        let face = CGRect(x: cx - w * 0.14, y: rect.minY + h * 0.15, width: w * 0.28, height: h * 0.17)
        p.addEllipse(in: face)

        // Beard
        p.move(to: CGPoint(x: cx - w * 0.08, y: face.maxY - h * 0.01))
        p.addQuadCurve(
            to: CGPoint(x: cx + w * 0.08, y: face.maxY - h * 0.01),
            control: CGPoint(x: cx, y: face.maxY + h * 0.06)
        )
        p.addLine(to: CGPoint(x: cx, y: face.maxY + h * 0.04))

        // Robe
        let shoulderY = rect.minY + h * 0.38
        p.move(to: CGPoint(x: cx - w * 0.20, y: shoulderY))
        p.addLine(to: CGPoint(x: cx + w * 0.20, y: shoulderY))
        p.addLine(to: CGPoint(x: cx + w * 0.26, y: rect.maxY - h * 0.04))
        p.addQuadCurve(
            to: CGPoint(x: cx - w * 0.26, y: rect.maxY - h * 0.04),
            control: CGPoint(x: cx, y: rect.maxY + h * 0.02)
        )
        p.closeSubpath()

        // Sword
        let swordX = rect.maxX - w * 0.08
        p.move(to: CGPoint(x: swordX, y: rect.minY + h * 0.12))
        p.addLine(to: CGPoint(x: swordX, y: rect.maxY - h * 0.08))
        p.move(to: CGPoint(x: swordX - w * 0.05, y: rect.minY + h * 0.48))
        p.addLine(to: CGPoint(x: swordX + w * 0.05, y: rect.minY + h * 0.48))

        return p
    }
}

// MARK: - Full card face

struct PlayingCardFaceContent: View {
    let card: String
    var width: CGFloat
    var height: CGFloat
    var pad: CGFloat
    var corner: CGFloat

    private var ink: Color { PlayingCard.inkColor(card) }
    private var rank: Character? { PlayingCard.rankChar(card) }
    private var rankLabel: String { PlayingCard.displayRank(card) }
    private var rankFont: Font { .system(size: width * 0.22, weight: .bold, design: .serif) }
    private var cornerSuitSize: CGFloat { width * 0.17 }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: corner * 0.75)
                .stroke(ink.opacity(0.14), lineWidth: 0.8)
                .padding(pad * 0.55)

            VStack(spacing: 0) {
                HStack(alignment: .top, spacing: 0) {
                    cornerIndex(inverted: false)
                    Spacer(minLength: 0)
                }
                Spacer(minLength: 0)
                HStack(alignment: .bottom, spacing: 0) {
                    Spacer(minLength: 0)
                    cornerIndex(inverted: true)
                }
            }
            .padding(pad)

            centerArt
                .padding(.horizontal, pad * 1.1)
                .padding(.vertical, pad * 1.55)
        }
    }

    @ViewBuilder
    private var centerArt: some View {
        if let rank {
            switch rank {
            case "A":
                CardPipSymbol(card: card, size: width * 0.36)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            case "J", "Q", "K":
                CardCourtArt(rank: rank, card: card)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            default:
                pipField(for: rank)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    private func cornerIndex(inverted: Bool) -> some View {
        VStack(spacing: width * 0.01) {
            Text(rankLabel)
                .font(rankFont)
                .minimumScaleFactor(0.65)
                .lineLimit(1)
            CardCornerSuitGlyph(card: card, size: cornerSuitSize)
        }
        .foregroundStyle(ink)
        .rotationEffect(inverted ? .degrees(180) : .zero)
    }

    @ViewBuilder
    private func pipField(for rank: Character) -> some View {
        GeometryReader { geo in
            let pips = CardPipLayout.pips(for: rank)
            let pipSize = min(geo.size.width * 0.20, geo.size.height * 0.125)
            ZStack {
                ForEach(Array(pips.enumerated()), id: \.offset) { _, pip in
                    CardPipSymbol(card: card, size: pipSize)
                        .position(x: geo.size.width * pip.x, y: geo.size.height * pip.y)
                        .rotationEffect(pip.inverted ? .degrees(180) : .zero)
                }
            }
        }
    }
}
