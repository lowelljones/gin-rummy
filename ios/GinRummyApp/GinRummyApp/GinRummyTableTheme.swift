import SwiftUI
import UIKit

/// Table container: full-width white (system background) to match the rest of the app.
struct GinRummyTableChrome<Content: View>: View {
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(spacing: 0) { content() }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .background(Color(UIColor.systemBackground))
    }
}

struct PostCutInterstitial: View {
    let last: PlayerPerspective.LastCutResult
    let youAreSeat: Int

    var body: some View {
        ZStack {
            Color(UIColor.systemBackground)
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
}
