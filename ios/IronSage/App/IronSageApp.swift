import ClerkKit
import IronSageAPI
import IronSageCore
import IronSageStore
import SwiftUI

@main
struct IronSageApp: App {
    private let setup = Result { try AppServices() }

    var body: some Scene {
        WindowGroup {
            switch setup {
            case .success(let services):
                RootView()
                    .environment(Clerk.shared)
                    .environment(\.api, services.api)
                    .environment(services.store)
                    .environment(services.sync)
                    .environment(services.health)
                    .environment(services.coach)
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
    /// Debug builds launched with `-demo`: sample data in memory, no sign-in, no network.
    let isDemo: Bool

    private static let ownerKey = "IronSage.store.owner"

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
        coach = CoachService(store: store, sync: sync, isOnline: !isDemo, defaults: isDemo ? Self.demoDefaults() : .standard)
        // Checked right before each request goes out, so turning the coach off stops
        // one that is already queued.
        sync.allowsCoach = { [coach] in coach.isEnabled }
        #if DEBUG
        if isDemo {
            DemoData.fill(store, coach: coach)
        }
        #endif
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
        UserDefaults.standard.removeObject(forKey: Self.ownerKey)
    }

    /// Demo launches keep their settings out of the real app's.
    private static func demoDefaults() -> UserDefaults {
        let defaults = UserDefaults(suiteName: "IronSage.demo")!
        defaults.removePersistentDomain(forName: "IronSage.demo")
        return defaults
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
