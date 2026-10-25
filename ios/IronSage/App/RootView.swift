import ClerkKit
import IronSageStore
import SwiftUI

/// Signed out: the welcome screen. Signed in: the tabs. Clerk keeps the session in the
/// Keychain and the workouts are on the phone, so a signed-in user gets straight to the
/// tabs even without a connection.
struct RootView: View {
    @Environment(Clerk.self) private var clerk
    @Environment(SyncEngine.self) private var sync
    @Environment(\.services) private var services
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        Group {
            if !clerk.isLoaded {
                ProgressView()
            } else if clerk.user == nil {
                WelcomeView()
            } else {
                MainTabView()
            }
        }
        .task(id: clerk.user?.id) {
            guard let userID = clerk.user?.id else { return }
            services?.prepare(forUser: userID)
            await sync.sync()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active, clerk.user != nil {
                Task { await sync.sync() }
            }
        }
        .onOpenURL { url in
            // Returns from Google sign-in in the browser.
            Task { try? await clerk.handle(url) }
        }
    }
}
