import SwiftUI

struct RootView: View {
    @EnvironmentObject private var app: AppModel

    /// Each top-level branch owns its own NavigationStack instead of nesting
    /// inside a shared outer one. LobbyView previously had a nested
    /// `NavigationStack(path: $path)` inside RootView's NavigationStack, and
    /// when `app.activeGameId` flipped while the waiting room was pushed on the
    /// inner stack, SwiftUI didn't always tear that pushed view down — the
    /// user was left staring at "Game starting…" until they manually swiped
    /// back. Giving each branch its own root-level NavigationStack means
    /// switching branches replaces the whole stack atomically.
    var body: some View {
        Group {
            if app.restoring {
                /* Stored refresh token is being exchanged at launch — avoid flashing AuthView. */
                NavigationStack {
                    ProgressView("Restoring session…")
                        .progressViewStyle(.circular)
                        .tint(GinRummyPalette.gold)
                        .foregroundStyle(GinRummyPalette.cream)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .rootNavChrome()
            } else if app.accessToken == nil {
                NavigationStack {
                    AuthView()
                }
                .rootNavChrome()
            } else if app.activeGameId != nil {
                NavigationStack {
                    GameView()
                }
                .rootNavChrome()
            } else {
                /* LobbyView brings its own NavigationStack with a `path` binding
                 * for pushing the join-code screen and the waiting room. */
                LobbyView()
                    .rootNavChrome()
            }
        }
        .ginFeltChrome()
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

private extension View {
    /// Toolbar chrome modifiers shared by every top-level branch's
    /// NavigationStack. Lifted out so each branch can apply them consistently
    /// without us having to maintain a single outer NavigationStack.
    func rootNavChrome() -> some View {
        self
            .toolbarBackground(GinRummyPalette.bgDeep.opacity(0.92), for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .tint(GinRummyPalette.gold)
    }
}
