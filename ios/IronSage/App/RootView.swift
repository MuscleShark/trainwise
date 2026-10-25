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
    @Environment(HealthService.self) private var health
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
            await health.importRecent()
            await sync.sync()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active, clerk.user != nil, services?.isDemo != true {
                Task {
                    await health.importRecent()
                    await sync.sync()
                }
            }
        }
        // One sheet for both: SwiftUI can drop a second sheet asked for while the first is
        // still closing, which is exactly when the Apple Health page follows the profile.
        .sheet(item: Binding(get: { setupStep }, set: { _ in })) { step in
            switch step {
            case .profile: ProfileSetupView()
            case .health: HealthIntroView()
            }
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

    /// Once the profile exists, offer Apple Health one time.
    private var offersHealth: Bool {
        clerk.user != nil && store.profile != nil && health.shouldOfferConnection
    }

    private enum SetupStep: String, Identifiable {
        case profile, health
        var id: String { rawValue }
    }

    private var setupStep: SetupStep? {
        needsProfile ? .profile : offersHealth ? .health : nil
    }
}
