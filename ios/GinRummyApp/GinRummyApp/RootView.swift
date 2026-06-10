import SwiftUI

/// Which top-level screen RootView shows. Pulled out of the view body as a pure
/// function so the lobby→game handoff is unit-testable: the invariant that the
/// game table *replaces* the lobby stack (waiting room included) the instant
/// `activeGameId` flips must never regress into the old "swipe back to find the
/// game" bug.
enum RootScreen: Equatable {
    case restoringSession
    case auth
    case game
    case lobby

    static func resolve(restoring: Bool, hasSession: Bool, activeGameId: String?) -> RootScreen {
        if restoring { return .restoringSession }
        guard hasSession else { return .auth }
        if activeGameId != nil { return .game }
        return .lobby
    }
}

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
            switch RootScreen.resolve(
                restoring: app.restoring,
                hasSession: app.accessToken != nil,
                activeGameId: app.activeGameId
            ) {
            case .restoringSession:
                /* Stored refresh token is being exchanged at launch — avoid flashing AuthView. */
                NavigationStack {
                    ProgressView("Restoring session…")
                        .progressViewStyle(.circular)
                        .tint(GinRummyPalette.gold)
                        .foregroundStyle(GinRummyPalette.cream)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .rootNavChrome()
            case .auth:
                NavigationStack {
                    AuthView()
                }
                .rootNavChrome()
            case .game:
                NavigationStack {
                    GameView()
                }
                .rootNavChrome()
            case .lobby:
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
