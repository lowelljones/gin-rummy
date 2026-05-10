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
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if app.accessToken == nil {
                    AuthView()
                } else if app.activeGameId != nil {
                    GameView()
                } else {
                    LobbyView()
                }
            }
            .toolbar {
                if app.accessToken != nil {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Sign out") { app.signOut() }
                    }
                }
            }
        }
        .onOpenURL { url in
            app.handleInviteURL(url)
            if app.accessToken != nil, app.activeGameId == nil {
                /* Navigation stays on lobby; join code prefilled via onAppear */
            }
        }
    }
}
