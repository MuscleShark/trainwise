import ClerkKit
import IronSageCore
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
    @Environment(CoachService.self) private var coach
    @Environment(SubscriptionService.self) private var subscriptions
    @Environment(WorkoutPresenter.self) private var workouts
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
            // The server's data first, so what Apple Health adds isn't added twice.
            await sync.sync()
            await health.importRecent()
            await sync.sync()
            await subscriptions.refresh()
            await coach.refresh()
            updateWidgets()
        }
        .onChange(of: scenePhase) { _, phase in
            // The widgets are seen once the app is away.
            if phase == .background {
                updateWidgets()
            }
            if phase == .active {
                RestNotifications.removeDelivered()
            }
            if phase == .active, clerk.user != nil, services?.isDemo != true {
                Task {
                    await health.importRecent()
                    await sync.sync()
                    await subscriptions.refresh()
                    await coach.refresh()
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
            if url.scheme == WidgetLink.scheme {
                openFromWidget(url)
                return
            }
            // Returns from Google sign-in in the browser.
            Task { try? await clerk.handle(url) }
        }
    }

    private func updateWidgets() {
        WidgetData.update(store, signedIn: clerk.user != nil || services?.isDemo == true)
    }

    /// A widget's link: Today opens with the app; Start begins the template day due
    /// next, as Today's button does, or goes back to the workout in progress.
    private func openFromWidget(_ url: URL) {
        guard url == WidgetLink.startUpNext, clerk.user != nil || services?.isDemo == true else { return }
        if let active = store.activeWorkout {
            workouts.resume(active, store: store)
            return
        }
        guard let upNext = store.upNext else { return }
        let advised = coach.advice(for: upNext.day)
        let started = WorkoutSession.start(upNext.day, of: upNext.template, store: store, advice: advised?.output)
        if let advised {
            coach.recordApplied(advised, to: started.workout.id)
        }
        workouts.show(started)
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
