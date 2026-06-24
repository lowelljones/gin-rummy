import SwiftUI

/// Table container: felt-style background for hands and piles.
struct GinRummyTableChrome<Content: View>: View {
    @ViewBuilder var content: () -> Content

    var body: some View {
        ZStack {
            GinRummyPalette.bgDeep
            GinRummyPalette.feltGradient
                .opacity(0.94)
                .blendMode(.softLight)

            VStack(spacing: 0) {
                content()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
    }
}

/// Full-screen, on-brand reveal shown the instant the cut resolves. It owns the
/// whole screen for its duration, so the down-card stage can never flash
/// underneath. The reveal stages itself: your card → opponent's card → verdict,
/// then calls `onFinished` (also reachable with a tap once the verdict shows).
struct CutRevealView: View {
    let last: PlayerPerspective.LastCutResult
    let youAreSeat: Int
    /// When true the opponent's card starts hidden ("drawing…") and flips a beat later.
    var staged: Bool = false
    var onFinished: () -> Void

    @State private var stage = 0 // 0: your card only · 1: both cards · 2: verdict
    @State private var finished = false
    @State private var task: Task<Void, Never>?

    private var yourCard: String { youAreSeat == 0 ? last.p0 : last.p1 }
    private var oppCard: String { youAreSeat == 0 ? last.p1 : last.p0 }
    /// `nonDealer` is the seat that cut the higher card and leads; the other deals.
    private var youLead: Bool { youAreSeat == last.nonDealer }

    var body: some View {
        ZStack {
            GinRummyPalette.bgDeep.ignoresSafeArea()
            GinRummyPalette.feltGradient
                .opacity(0.5)
                .blendMode(.softLight)
                .ignoresSafeArea()
            RadialGradient(
                colors: [GinRummyPalette.gold.opacity(0.16), .clear],
                center: .center,
                startRadius: 8,
                endRadius: 320
            )
            .ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer(minLength: 0)

                Text("CUT FOR THE DEAL")
                    .font(.caption.weight(.bold))
                    .tracking(4)
                    .foregroundStyle(GinRummyPalette.gold.opacity(0.95))
                Text("Higher card leads · the other deals")
                    .font(.caption2)
                    .foregroundStyle(GinRummyPalette.sage.opacity(0.9))
                    .padding(.top, 4)

                Spacer().frame(height: 30)

                HStack(alignment: .center, spacing: 20) {
                    column(title: "You", card: yourCard, faceUp: true, isWinner: youLead)
                    Text("vs")
                        .font(.subheadline.weight(.heavy))
                        .foregroundStyle(GinRummyPalette.sage.opacity(0.8))
                    column(title: "Opponent", card: oppCard, faceUp: stage >= 1, isWinner: !youLead)
                }

                Spacer().frame(height: 30)

                verdict
                    .opacity(stage >= 2 ? 1 : 0)
                    .scaleEffect(stage >= 2 ? 1 : 0.92)

                Spacer(minLength: 0)

                Text("Tap to continue")
                    .font(.footnote)
                    .foregroundStyle(GinRummyPalette.sage.opacity(0.8))
                    .opacity(stage >= 2 ? 1 : 0)
                    .padding(.bottom, 26)
            }
            .padding(.horizontal, 28)
        }
        .contentShape(Rectangle())
        .onTapGesture { if stage >= 2 { finish() } }
        .onAppear { start() }
        .onDisappear { task?.cancel() }
    }

    @ViewBuilder
    private func column(title: String, card: String, faceUp: Bool, isWinner: Bool) -> some View {
        let highlighted = stage >= 2 && isWinner
        VStack(spacing: 10) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(highlighted ? GinRummyPalette.gold : GinRummyPalette.cream)

            ZStack {
                if faceUp {
                    PlayingCardView(card: card, compact: false, onTap: nil)
                        .transition(.asymmetric(
                            insertion: .scale(scale: 0.7).combined(with: .opacity),
                            removal: .opacity
                        ))
                } else {
                    cardBack
                }
            }
            .overlay {
                RoundedRectangle(cornerRadius: 12)
                    .stroke(GinRummyPalette.gold, lineWidth: highlighted ? 3 : 0)
                    .shadow(color: GinRummyPalette.gold.opacity(highlighted ? 0.7 : 0), radius: 10)
            }

            Text(faceUp ? " " : "drawing…")
                .font(.caption2.italic())
                .foregroundStyle(GinRummyPalette.sage.opacity(0.9))
        }
        .frame(maxWidth: .infinity)
    }

    private var cardBack: some View {
        RoundedRectangle(cornerRadius: 12)
            .fill(
                LinearGradient(
                    colors: [GinRummyPalette.bgPanel, GinRummyPalette.bgDeep],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .frame(width: 86, height: 124)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(GinRummyPalette.gold.opacity(0.4), lineWidth: 1)
            )
            .overlay {
                Image(systemName: "suit.spade.fill")
                    .font(.title)
                    .foregroundStyle(GinRummyPalette.gold.opacity(0.35))
            }
            .overlay { ProgressView().tint(GinRummyPalette.gold).offset(y: 44) }
    }

    private var verdict: some View {
        VStack(spacing: 6) {
            Text(youLead ? "You cut higher" : "Opponent cut higher")
                .font(.title2.weight(.bold))
                .foregroundStyle(GinRummyPalette.cream)
            Text(youLead ? "You lead · opponent deals the first hand" : "You deal · opponent leads the first hand")
                .font(.subheadline)
                .foregroundStyle(GinRummyPalette.sage.opacity(0.95))
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 16)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 18)
                .fill(GinRummyPalette.bgPanel.opacity(0.72))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .stroke(GinRummyPalette.gold.opacity(0.3), lineWidth: 1)
        )
    }

    private func start() {
        stage = staged ? 0 : 1
        task?.cancel()
        task = Task { @MainActor in
            if staged {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                withAnimation(.spring(response: 0.45, dampingFraction: 0.78)) { stage = 1 }
            }
            try? await Task.sleep(nanoseconds: 1_150_000_000)
            withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) { stage = 2 }
            try? await Task.sleep(nanoseconds: 2_700_000_000)
            finish()
        }
    }

    private func finish() {
        guard !finished else { return }
        finished = true
        task?.cancel()
        onFinished()
    }
}
