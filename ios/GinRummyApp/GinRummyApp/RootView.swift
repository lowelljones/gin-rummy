import SwiftUI

struct RootView: View {
    @EnvironmentObject private var app: AppModel

    var body: some View {
        NavigationStack {
            Group {
                if app.restoring {
                    /* Stored refresh token is being exchanged at launch — avoid flashing AuthView. */
                    ProgressView("Restoring session…")
                        .progressViewStyle(.circular)
                        .tint(GinRummyPalette.gold)
                        .foregroundStyle(GinRummyPalette.cream)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if app.accessToken == nil {
                    AuthView()
                } else if app.activeGameId != nil {
                    GameView()
                } else {
                    LobbyView()
                }
            }
        }
        .ginFeltChrome()
        .toolbarBackground(GinRummyPalette.bgDeep.opacity(0.92), for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .tint(GinRummyPalette.gold)
        .fullScreenCover(item: $app.inviteAcceptPresentation) { presentation in
            InviteAcceptView(inviteCode: presentation.inviteCode)
        }
        .onOpenURL { url in
            app.handleInviteURL(url)
        }
        .onContinueUserActivity(NSUserActivityTypeBrowsingWeb) { activity in
            if let url = activity.webpageURL {
                app.handleInviteURL(url)
            }
        }
        .onChange(of: app.activeGameId) { _, _ in
            app.reconcileInviteAcceptPresentation()
        }
    }
}
