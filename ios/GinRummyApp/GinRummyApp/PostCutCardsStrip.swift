import SwiftUI

/// Staged reveal after both cut picks complete: optionally show only your card while "opponent drawing",
/// then both cards, before the full post-cut summary interstitial.
enum PostCutRevealMode: Equatable {
    case yourOnly
    case both
}

struct PostCutCardsStrip: View {
    let last: PlayerPerspective.LastCutResult
    let youAreSeat: Int
    var mode: PostCutRevealMode = .both

    private var yourCard: String { youAreSeat == 0 ? last.p0 : last.p1 }
    private var oppCard: String { youAreSeat == 0 ? last.p1 : last.p0 }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(spacing: 6) {
                Text("Your Card")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                PlayingCardView(card: yourCard, compact: false, onTap: nil)
            }
            .frame(maxWidth: .infinity)

            VStack(spacing: 6) {
                Text("Opponent Card")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                if mode == .both {
                    PlayingCardView(card: oppCard, compact: false, onTap: nil)
                } else {
                    CardBackFace(width: CardMetrics.fullWidth, showProgress: true)
                    Text("Opponent drawing…")
                        .font(.caption.italic())
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity)
        }
        .padding(12)
        .frame(maxWidth: .infinity)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color(UIColor.secondarySystemBackground)))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.primary.opacity(0.08)))
    }
}
