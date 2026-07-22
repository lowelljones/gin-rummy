import SwiftUI

/// Private Club palette and reusable chrome for auth, lobby, and table.
enum GinRummyPalette {
    // Felt — darkened toward near-black green for a richer table + lobby.
    static let bgDeep = Color(red: 0.027, green: 0.078, blue: 0.063) // #07140F
    static let bgPanel = Color(red: 0.055, green: 0.152, blue: 0.114) // #0E271D

    static let cream = Color(red: 0.965, green: 0.953, blue: 0.925) // #F6F3EC
    /// Card-coupled gold (hairline frames + card back guilloché). DO NOT retune —
    /// the card art depends on this exact value.
    static let gold = Color(red: 0.918, green: 0.886, blue: 0.831) // #EAE2D4
    static let sage = Color(red: 0.655, green: 0.698, blue: 0.624) // #A7B29F
    static let burgundy = Color(red: 0.357, green: 0.122, blue: 0.133) // #5B1F22
    static let navy = Color(red: 0.071, green: 0.137, blue: 0.227) // #12233A

    /// Antique-gold CHROME accent (pills, crest, lobby detailing). Separate from
    /// `gold` so it never touches card rendering.
    static let goldAccent = Color(red: 0.761, green: 0.631, blue: 0.306) // #C2A14E
    static let goldAccentSoft = Color(red: 0.847, green: 0.769, blue: 0.537) // #D8C489

    /// Face-down card back — warm wine tones that read clearly on green felt.
    static let cardBackLight = Color(red: 0.42, green: 0.13, blue: 0.15)
    static let cardBackDark = Color(red: 0.26, green: 0.08, blue: 0.10)

    static var cardBackGradient: LinearGradient {
        LinearGradient(
            colors: [cardBackLight, cardBackDark],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    static var feltGradient: LinearGradient {
        LinearGradient(
            colors: [bgDeep, bgPanel.opacity(0.94), bgDeep.opacity(1.03)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    static func titleFont(size: CGFloat) -> Font {
        .system(size: size, weight: .semibold, design: .serif)
    }

    /// Accent chips for phases (game board · readable on felt).
    static let phaseCutDeal = navy
    static let phaseReveal = burgundy.opacity(0.85)
    static let phaseDownCard = burgundy.opacity(0.72)
    static let phasePlay = sage.opacity(1.08)
    static let phaseKnockLayoff = gold.opacity(0.75)
    static let phaseHandOver = burgundy.opacity(0.58)
    static let phaseMatchOver = cream.opacity(0.55)
}

struct FeltBackgroundModifier: ViewModifier {
    func body(content: Content) -> some View {
        ZStack {
            GinRummyPalette.feltGradient
                .ignoresSafeArea()
            content
        }
        .preferredColorScheme(.dark)
    }
}

struct GoldBorderModifier: ViewModifier {
    var cornerRadius: CGFloat = 12
    func body(content: Content) -> some View {
        content
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .stroke(GinRummyPalette.gold.opacity(0.35), lineWidth: 1)
            )
    }
}

extension View {
    func ginFeltChrome() -> some View { modifier(FeltBackgroundModifier()) }
    func ginGoldBorder(cornerRadius: CGFloat = 12) -> some View {
        modifier(GoldBorderModifier(cornerRadius: cornerRadius))
    }
}

/// Logo lockup: an antique-gold rhombus crest around a white spade,
/// the serif wordmark, a hairline rule, and a tracked subtitle.
struct GinRummyLogoBlock: View {
    var subtitle: String?

    var body: some View {
        VStack(spacing: 15) {
            ZStack {
                RoundedRectangle(cornerRadius: 6)
                    .fill(GinRummyPalette.burgundy.opacity(0.38))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(GinRummyPalette.goldAccent, lineWidth: 1.6)
                    )
                    .frame(width: 52, height: 52)
                    .rotationEffect(.degrees(45))
                    .shadow(color: GinRummyPalette.goldAccent.opacity(0.25), radius: 12)

                Image(systemName: "suit.spade.fill")
                    .font(.system(size: 23, weight: .semibold))
                    .foregroundStyle(GinRummyPalette.cream)
            }
            .frame(width: 74, height: 74)

            VStack(spacing: 9) {
                Text("GIN RUMMY")
                    .font(GinRummyPalette.titleFont(size: 34))
                    .foregroundStyle(GinRummyPalette.cream)
                    .tracking(5)

                Rectangle()
                    .fill(GinRummyPalette.goldAccent.opacity(0.6))
                    .frame(width: 46, height: 1)

                Text((subtitle ?? "“Get rid of the pretty ones”").uppercased())
                    .font(.caption.weight(.semibold))
                    .tracking(3)
                    .foregroundStyle(GinRummyPalette.goldAccentSoft)
            }
        }
    }
}

struct GinPrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(GinRummyPalette.cream)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 15)
            .background(GinRummyPalette.burgundy.opacity(configuration.isPressed ? 0.85 : 1))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(GinRummyPalette.goldAccent.opacity(0.35), lineWidth: 1)
            )
    }
}

struct GinGhostButtonStyle: ButtonStyle {
    var textColor: Color = GinRummyPalette.goldAccentSoft
    var strokeColor: Color = GinRummyPalette.goldAccent

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(textColor)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(strokeColor.opacity(configuration.isPressed ? 0.4 : 0.5), lineWidth: 1.3)
            )
    }
}

/// Compact action-bar button: filled (primary) or gold-outlined (secondary).
/// Dims when disabled so the action bar reads clearly.
struct GinActionButtonStyle: ButtonStyle {
    var filled: Bool = true
    var tint: Color = GinRummyPalette.burgundy

    func makeBody(configuration: Configuration) -> some View {
        Inner(configuration: configuration, filled: filled, tint: tint)
    }

    private struct Inner: View {
        let configuration: Configuration
        let filled: Bool
        let tint: Color
        @Environment(\.isEnabled) private var isEnabled

        var body: some View {
            configuration.label
                .font(.callout.weight(.semibold))
                .foregroundStyle(filled ? GinRummyPalette.cream : tint)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 13)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(filled ? tint.opacity(configuration.isPressed ? 0.82 : 1) : Color.clear)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(tint.opacity(filled ? 0 : 0.6), lineWidth: filled ? 0 : 1.4)
                )
                .contentShape(RoundedRectangle(cornerRadius: 12))
                .opacity(isEnabled ? (configuration.isPressed ? 0.92 : 1) : 0.4)
        }
    }
}

/// Small capsule status chip used in the table status row and banners.
struct GinStatusPill: View {
    let text: String
    var systemImage: String? = nil
    var tint: Color = GinRummyPalette.goldAccent

    var body: some View {
        HStack(spacing: 6) {
            if let systemImage {
                Image(systemName: systemImage)
            }
            Text(text)
        }
        .font(.footnote.weight(.semibold))
        .foregroundStyle(GinRummyPalette.cream)
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(Capsule().fill(tint.opacity(0.18)))
        .overlay(Capsule().stroke(tint.opacity(0.45), lineWidth: 1))
    }
}

struct GinOutlinedFieldModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(12)
            .background(GinRummyPalette.bgPanel.opacity(0.72))
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(GinRummyPalette.goldAccent.opacity(0.32), lineWidth: 1)
            )
            .foregroundStyle(GinRummyPalette.cream)
    }
}

extension View {
    func ginOutlinedField() -> some View { modifier(GinOutlinedFieldModifier()) }
}
