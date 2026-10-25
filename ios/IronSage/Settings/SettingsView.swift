import ClerkKit
import IronSageAPI
import OSLog
import SwiftUI

private let log = Logger(subsystem: "app.ironsage.IronSage", category: "settings")

struct SettingsView: View {
    @Environment(Clerk.self) private var clerk
    @Environment(\.api) private var api
    @Environment(\.openURL) private var openURL
    @State private var account: AccountState = .loading
    @State private var isConfirmingSignOut = false

    enum AccountState {
        case loading
        case signedIn(email: String)
        case unavailable
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Account") {
                    switch account {
                    case .loading:
                        ProgressView()
                    case .signedIn(let email):
                        LabeledContent("Email", value: email)
                    case .unavailable:
                        Text("Couldn't load your account. Check your connection, then pull down to try again.")
                            .foregroundStyle(.secondary)
                    }
                    Button("Sign out", role: .destructive) {
                        isConfirmingSignOut = true
                    }
                }

                Section("App") {
                    Button("Language") {
                        // iOS keeps a per-app language setting on the app's page in Settings.
                        if let url = URL(string: UIApplication.openSettingsURLString) {
                            openURL(url)
                        }
                    }
                    Link("Privacy policy", destination: Site.page("privacy"))
                    Link("Support", destination: Site.page("support"))
                    LabeledContent("Version", value: Self.version)
                }
            }
            .navigationTitle("Settings")
            .task { await loadAccount() }
            .refreshable { await loadAccount() }
            .confirmationDialog(
                "Sign out of IronSage?",
                isPresented: $isConfirmingSignOut,
                titleVisibility: .visible
            ) {
                Button("Sign out", role: .destructive) {
                    Task { try? await clerk.auth.signOut() }
                }
            }
        }
    }

    private func loadAccount() async {
        guard let api else { return }
        do {
            let me = try await api.getMe().ok.body.json
            account = .signedIn(email: me.email)
        } catch {
            log.error("Loading the account failed: \(String(describing: error), privacy: .public)")
            account = .unavailable
        }
    }

    private static var version: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return "\(version) (\(build))"
    }
}

/// Pages on ironsage.app, in Chinese when the app runs in Chinese.
enum Site {
    static func page(_ path: String) -> URL {
        let chinese = Bundle.main.preferredLocalizations.first?.hasPrefix("zh") == true
        return URL(string: "https://ironsage.app/\(path)\(chinese ? "/zh" : "")")!
    }
}
