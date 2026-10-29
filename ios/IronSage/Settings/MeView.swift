import ClerkKit
import IronSageAPI
import IronSageCore
import IronSageStore
import OSLog
import SwiftUI

private let log = Logger(subsystem: "app.ironsage.IronSage", category: "settings")

/// The Me tab: the profile, a look at the user's training and body, the coach plan,
/// and the account.
struct MeView: View {
    @Environment(Clerk.self) private var clerk
    @Environment(\.api) private var api
    @Environment(\.services) private var services
    @Environment(LocalStore.self) private var store
    @Environment(SyncEngine.self) private var sync
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

        var email: String? {
            if case .signedIn(let email) = self { email } else { nil }
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    NavigationLink {
                        ProfileSettingsView(account: account)
                    } label: {
                        ProfileHeader(email: account.email)
                    }
                    .accessibilityIdentifier("profile")
                }

                SyncProblemSection()
                TrainingStatsSection()
                BodySection()

                Section {
                    NavigationLink {
                        CoachPlanView()
                    } label: {
                        CoachPlanRow()
                    }
                    .accessibilityIdentifier("coachPlan")
                }

                Section {
                    Button("Sign out", role: .destructive) {
                        isConfirmingSignOut = true
                    }
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
            .navigationTitle("Me")
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
                            await services?.coach.withdrawBeforeSignOut()
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
        // The sign-in account and its photo go too, as on the website (routers/auth.py).
        try? await clerk.user?.delete()
        try? await clerk.auth.signOut()
        services?.removeLocalData()
    }
}

/// The top row of Me: the photo, name and email, opening the profile.
struct ProfileHeader: View {
    let email: String?
    @Environment(Clerk.self) private var clerk

    var body: some View {
        HStack(spacing: 14) {
            AvatarView(url: ProfilePhoto.url(of: clerk.user), email: email)
            VStack(alignment: .leading, spacing: 2) {
                Text(name ?? String(localized: "Profile"))
                    .font(.headline)
                if let email {
                    Text(email)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 4)
    }

    private var name: String? {
        let parts = [clerk.user?.firstName, clerk.user?.lastName].compactMap { $0 }.filter { !$0.isEmpty }
        return parts.isEmpty ? nil : parts.joined(separator: " ")
    }
}

/// Pages on ironsage.app, in Chinese when the app runs in Chinese.
enum Site {
    static func page(_ path: String) -> URL {
        URL(string: "https://ironsage.app/\(path)\(AppLanguage.isChinese ? "/zh" : "")")!
    }
}
