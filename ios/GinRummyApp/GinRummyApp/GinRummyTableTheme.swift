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

struct PostCutInterstitial: View {
    let last: PlayerPerspective.LastCutResult
    let youAreSeat: Int

    var body: some View {
        ZStack {
            GinRummyPalette.bgDeep
                .ignoresSafeArea()
            backdropBlend
                .ignoresSafeArea()
            VStack {
                Spacer(minLength: 24)
                StaggeredCutResultBanner(
                    last: last,
                    youAreSeat: youAreSeat,
                    prominent: true
                )
                .id("\(last.p0)-\(last.p1)-\(last.nonDealer)-full")
                Spacer(minLength: 24)
            }
            .padding(20)
        }
    }

    private var backdropBlend: some View {
        LinearGradient(
            colors: [
                GinRummyPalette.bgPanel.opacity(0.45),
                GinRummyPalette.bgDeep.opacity(0.92),
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }
}
