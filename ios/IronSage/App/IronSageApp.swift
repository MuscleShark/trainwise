import ClerkKit
import IronSageAPI
import IronSageCore
import SwiftUI

@main
struct IronSageApp: App {
    private let config = Result { try AppConfig.fromMainBundle() }

    init() {
        if case .success(let config) = config {
            Clerk.configure(publishableKey: config.clerkPublishableKey)
        }
    }

    var body: some Scene {
        WindowGroup {
            switch config {
            case .success(let config):
                RootView()
                    .environment(Clerk.shared)
                    .environment(\.api, APIClient.ironSage(serverURL: config.apiBaseURL, token: sessionToken))
            case .failure(let error):
                // Only reachable with a broken build configuration.
                ContentUnavailableView(
                    "IronSage isn't set up",
                    systemImage: "exclamationmark.triangle",
                    description: Text(verbatim: String(describing: error))
                )
            }
        }
    }
}

/// The current Clerk session token; nil when signed out.
@Sendable private func sessionToken() async throws -> String? {
    try await Clerk.shared.auth.getToken()
}

extension EnvironmentValues {
    @Entry var api: APIClient?
}
