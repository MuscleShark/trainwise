import ClerkKit
import IronSageStore
import SwiftUI

/// Signed out: the welcome screen. Signed in: the tabs. Clerk keeps the session in the
/// Keychain and the workouts are on the phone, so a signed-in user gets straight to the
/// tabs even without a connection.
struct RootView: View {
    @Environment(Clerk.self) private var clerk
    @Environment(SyncEngine.self) private var sync
    @Environment(LocalStore.self) private var store
    @Environment(\.services) private var services
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        Group {
            if services?.isDemo == true {
                MainTabView()
            } else if !clerk.isLoaded {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.appBackground)
            } else if clerk.user == nil {
                WelcomeView()
            } else {
                MainTabView()
            }
        }
        .task(id: clerk.user?.id) {
            guard let userID = clerk.user?.id, services?.isDemo != true else { return }
            services?.prepare(forUser: userID)
            await sync.sync()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active, clerk.user != nil, services?.isDemo != true {
                Task { await sync.sync() }
            }
        }
        .sheet(isPresented: Binding(get: { needsProfile }, set: { _ in })) {
            ProfileSetupView()
        }
        .onOpenURL { url in
            // Returns from Google sign-in in the browser.
            Task { try? await clerk.handle(url) }
        }
    }

    /// Signed in, synced once (so an existing profile has arrived), and still none.
    private var needsProfile: Bool {
        clerk.user != nil && services?.isDemo != true && sync.lastSyncedAt != nil && store.profile == nil
    }
}
