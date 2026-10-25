import ClerkKit
import SwiftUI

/// Signed out: the welcome screen. Signed in: the tabs. Clerk keeps the session in the
/// Keychain, so a signed-in user gets straight to the tabs even without a connection.
struct RootView: View {
    @Environment(Clerk.self) private var clerk

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
        .onOpenURL { url in
            // Returns from Google sign-in in the browser.
            Task { try? await clerk.handle(url) }
        }
    }
}
