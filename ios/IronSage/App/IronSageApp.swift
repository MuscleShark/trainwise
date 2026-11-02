import ClerkKit
import IronSageAPI
import IronSageCore
import IronSageStore
import SwiftUI

@main
struct IronSageApp: App {
    private let setup: Result<AppServices, Error>
    /// Changing it rebuilds the views in the new language.
    @AppStorage(AppLanguage.key) private var language = AppLanguage.Choice.system

    init() {
        AppLanguage.start()
        setup = Result { try AppServices() }
    }

    var body: some Scene {
        WindowGroup {
            switch setup {
            case .success(let services):
                RootView()
                    .id(language)
                    .appLanguage(language)
                    .environment(Clerk.shared)
                    .environment(\.api, services.api)
                    .environment(services.store)
                    .environment(services.sync)
                    .environment(services.health)
                    .environment(services.coach)
                    .environment(services.subscriptions)
                    .environment(services.workouts)
                    .environment(\.services, services)
            case .failure(let error):
                // Only reachable with a broken build configuration or a broken disk.
                ContentUnavailableView(
                    "IronSage isn't set up",
                    systemImage: "exclamationmark.triangle",
                    description: Text(verbatim: String(describing: error))
                )
            }
        }
    }
}

/// What the app is built from: configuration, the API client, the phone's copy of the
/// signed-in user's data with its sync, and Apple Health.
@MainActor
final class AppServices {
    let api: APIClient
    let store: LocalStore
    let sync: SyncEngine
    let health: HealthService
    let coach: CoachService
    let subscriptions: SubscriptionService
    /// The workout screen and its session, kept when the views are rebuilt in another
    /// language.
    let workouts = WorkoutPresenter()
    /// Debug builds launched with `-demo`: sample data in memory, no sign-in, no network.
    let isDemo: Bool

    private static let ownerKey = "IronSage.store.owner"
    /// The API the phone's data came from (see AppConfig.Server).
    private static let serverKey = "IronSage.store.server"

    init() throws {
        let config = try AppConfig.fromMainBundle()
        Clerk.configure(publishableKey: config.clerkPublishableKey)
        api = APIClient.ironSage(serverURL: config.apiBaseURL, token: sessionToken)
        #if DEBUG
        isDemo = ProcessInfo.processInfo.arguments.contains("-demo")
        #else
        isDemo = false
        #endif
        store = try LocalStore(inMemory: isDemo)
        sync = SyncEngine(store: store, api: api)
        health = HealthService(store: store, enabled: !isDemo)
        health.hasServerData = { [sync] in sync.lastSyncedAt != nil }
        coach = CoachService(store: store, sync: sync, isOnline: !isDemo, defaults: isDemo ? Self.demoDefaults() : .standard)
        // Checked right before each request goes out, so turning the coach off stops
        // one that is already queued.
        sync.allowsCoach = { [coach] in coach.isEnabled }
        subscriptions = SubscriptionService(api: isDemo ? nil : api)
        subscriptions.onAccessGained = { [coach] in coach.accessGained() }
        #if DEBUG
        if isDemo {
            DemoData.fill(store, coach: coach)
        }
        #endif
        if !isDemo {
            startOver(ifNotFrom: config.apiBaseURL)
        }
    }

    /// The phone's data and sync position belong to one server. When the app now talks to
    /// another (a TestFlight build replaced by the App Store's, or an Xcode build by
    /// either), it starts over and downloads the signed-in user's data from the new one.
    private func startOver(ifNotFrom server: URL) {
        let defaults = UserDefaults.standard
        let previous = defaults.string(forKey: Self.serverKey)
        // Unknown before this was recorded: the same server is the likely case, and
        // starting over would lose changes not synced yet.
        if let previous, previous != server.absoluteString {
            removeLocalData()
        }
        defaults.set(server.absoluteString, forKey: Self.serverKey)
    }

    /// Keeps only this user's data on the phone: another user's is removed first.
    func prepare(forUser userID: String) {
        let defaults = UserDefaults.standard
        if defaults.string(forKey: Self.ownerKey) != userID {
            removeLocalData()
            defaults.set(userID, forKey: Self.ownerKey)
        }
    }

    func removeLocalData() {
        store.removeAll()
        sync.reset()
        health.reset()
        coach.reset()
        subscriptions.reset()
        UserDefaults.standard.removeObject(forKey: Self.ownerKey)
    }

    /// Demo launches keep their settings out of the real app's.
    private static func demoDefaults() -> UserDefaults {
        let defaults = UserDefaults(suiteName: "IronSage.demo")!
        defaults.removePersistentDomain(forName: "IronSage.demo")
        return defaults
    }
}

private extension View {
    /// The picked language's locale. Left alone otherwise, so the views keep the
    /// phone's own locale.
    @ViewBuilder func appLanguage(_ choice: AppLanguage.Choice) -> some View {
        if choice == .system {
            self
        } else {
            environment(\.locale, AppLanguage.locale)
        }
    }
}

/// The current Clerk session token; nil when signed out.
@Sendable private func sessionToken() async throws -> String? {
    try await Clerk.shared.auth.getToken()
}

extension EnvironmentValues {
    @Entry var api: APIClient?
    @Entry var services: AppServices?
}
