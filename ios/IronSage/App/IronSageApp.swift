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

/// What the app is built from: configuration, the API client, and the phone's copy of
/// the signed-in user's data with its sync.
@MainActor
final class AppServices {
    let api: APIClient
    let store: LocalStore
    let sync: SyncEngine
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
        #if DEBUG
        if isDemo {
            DemoData.fill(store)
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
        UserDefaults.standard.removeObject(forKey: Self.ownerKey)
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
