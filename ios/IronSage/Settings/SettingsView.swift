import ClerkKit
import IronSageAPI
import IronSageCore
import IronSageStore
import OSLog
import SwiftUI

private let log = Logger(subsystem: "app.ironsage.IronSage", category: "settings")

struct SettingsView: View {
    @Environment(Clerk.self) private var clerk
    @Environment(\.api) private var api
    @Environment(\.services) private var services
    @Environment(LocalStore.self) private var store
    @Environment(SyncEngine.self) private var sync
    @Environment(\.openURL) private var openURL
    @State private var account: AccountState = .loading
    @State private var isConfirmingSignOut = false
    @State private var signOutFailed = false
    @State private var isConfirmingDelete = false
    @State private var isDeleting = false
    @State private var deleteFailed = false

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
                    LabeledContent("Sync") {
                        SyncStatusText(state: sync.state, lastSyncedAt: sync.lastSyncedAt)
                    }
                    Button("Sign out", role: .destructive) {
                        isConfirmingSignOut = true
                    }
                }

                Section("Training") {
                    NavigationLink("Profile") {
                        ProfileSettingsView()
                    }
                    LabeledContent("Weights in") {
                        Picker("Weights in", selection: Binding(
                            get: { store.profile?.unitSystem ?? (WeightUnit.default() == .lb ? .imperial : .metric) },
                            set: { system in
                                var profile = store.profile ?? Profile()
                                profile.unitSystem = system
                                store.save(profile)
                                Task { await sync.sync() }
                            }
                        )) {
                            Text("kg").tag(UnitSystem.metric)
                            Text("lb").tag(UnitSystem.imperial)
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                        .fixedSize()
                    }
                }

                HealthSettingsSection()

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

                Section {
                    Button(role: .destructive) {
                        isConfirmingDelete = true
                    } label: {
                        if isDeleting {
                            ProgressView()
                        } else {
                            Text("Delete account")
                        }
                    }
                    .disabled(isDeleting)
                } footer: {
                    Text("Deletes your account and all your training data from IronSage. This can't be undone.")
                }
            }
            .brandBackground()
            .navigationTitle("Settings")
            .task { await loadAccount() }
            .refreshable {
                await loadAccount()
                await sync.sync()
            }
            .confirmationDialog(
                "Sign out of IronSage?",
                isPresented: $isConfirmingSignOut,
                titleVisibility: .visible
            ) {
                Button("Sign out", role: .destructive) {
                    Task {
                        do {
                            try await clerk.auth.signOut()
                            services?.removeLocalData()
                        } catch {
                            log.error("Signing out failed: \(String(describing: error), privacy: .public)")
                            signOutFailed = true
                        }
                    }
                }
            } message: {
                if store.hasUnsyncedChanges {
                    Text("Some changes haven't synced yet and will be removed from this iPhone.")
                }
            }
            .alert("Couldn't sign out", isPresented: $signOutFailed) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("Check your connection and try again. Your data is still on this iPhone.")
            }
            .alert("Delete your account?", isPresented: $isConfirmingDelete) {
                Button("Cancel", role: .cancel) {}
                Button("Delete account", role: .destructive) {
                    Task { await deleteAccount() }
                }
            } message: {
                Text("Your workouts, templates and profile are deleted from IronSage, and you are signed out.")
            }
            .alert("Couldn't delete your account", isPresented: $deleteFailed) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("Check your connection and try again. Nothing was deleted.")
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

    private func deleteAccount() async {
        guard let api else { return }
        isDeleting = true
        defer { isDeleting = false }
        do {
            guard case .noContent = try await api.deleteMe() else {
                deleteFailed = true
                return
            }
        } catch {
            log.error("Deleting the account failed: \(String(describing: error), privacy: .public)")
            deleteFailed = true
            return
        }
        try? await clerk.auth.signOut()
        services?.removeLocalData()
    }

    private static var version: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return "\(version) (\(build))"
    }
}

/// "Synced 2 min ago", or why it isn't.
struct SyncStatusText: View {
    let state: SyncEngine.State
    let lastSyncedAt: Date?

    var body: some View {
        switch state {
        case .syncing:
            Text("Syncing…")
        case .offline:
            Text("Waiting for a connection")
        case .failed:
            Text("Couldn't sync")
        case .idle:
            if let lastSyncedAt {
                Text("Synced \(lastSyncedAt, format: .relative(presentation: .named))")
            } else {
                Text("Not synced yet")
            }
        }
    }
}

/// Pages on ironsage.app, in Chinese when the app runs in Chinese.
enum Site {
    static func page(_ path: String) -> URL {
        URL(string: "https://ironsage.app/\(path)\(AppLanguage.isChinese ? "/zh" : "")")!
    }
}
