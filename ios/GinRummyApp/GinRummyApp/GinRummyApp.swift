import SwiftUI

@main
struct GinRummyApp: App {
    @StateObject private var appModel = AppModel()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(appModel)
                .onChange(of: scenePhase) { _, newPhase in
                    /* iOS suspends background Tasks; on foreground, top up the access token
                     * immediately so the user's first interaction never hits a 401. */
                    if newPhase == .active {
                        Task { await appModel.refreshIfExpiringSoon() }
                    }
                }
        }
    }
}
