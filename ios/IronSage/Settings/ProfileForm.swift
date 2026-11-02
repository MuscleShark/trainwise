import IronSageCore
import IronSageStore
import SwiftUI

/// The profile fields, shared by the first-run setup and Settings.
struct ProfileForm: View {
    @Binding var profile: Profile
    @ScaledMetric(relativeTo: .body) private var heightWidth: CGFloat = 90

    var body: some View {
        Section {
            Picker("Weights in", selection: $profile.unitSystem) {
                Text("Kilograms (kg)").tag(UnitSystem.metric)
                Text("Pounds (lb)").tag(UnitSystem.imperial)
            }
            .adaptivePickerStyle()
        }

        Section {
            Picker("Experience", selection: $profile.experienceLevel) {
                Text("Not set").tag(Level?.none)
                ForEach(Level.allCases, id: \.self) { level in
                    Text(level.label).tag(Level?.some(level))
                }
            }
            .adaptivePickerStyle()
            Picker("Goal", selection: $profile.goal) {
                Text("Not set").tag(Goal?.none)
                ForEach(Goal.allCases, id: \.self) { goal in
                    Text(goal.label).tag(Goal?.some(goal))
                }
            }
            .adaptivePickerStyle()
            Picker("Training days a week", selection: $profile.trainingDaysPerWeek) {
                Text("Not set").tag(Int?.none)
                ForEach(1...7, id: \.self) { days in
                    Text(days, format: .number).tag(Int?.some(days))
                }
            }
            .adaptivePickerStyle()
        } footer: {
            Text("Templates opens on the programs for your experience, beginner until you set it. The coach uses these to suggest your next sessions.")
        }

        Section {
            LabeledContent(profile.unitSystem == .imperial ? "Height (in)" : "Height (cm)") {
                NumberField(
                    placeholder: "–",
                    value: Binding(
                        get: { profile.unitSystem == .imperial ? profile.heightInches : profile.heightCm },
                        set: { value in
                            if profile.unitSystem == .imperial {
                                profile.heightInches = value
                            } else {
                                profile.heightCm = value
                            }
                            // The API accepts more than 0 and up to 300 cm.
                            if let cm = profile.heightCm {
                                profile.heightCm = cm > 0 ? min(cm, 300) : nil
                            }
                        }
                    ),
                    decimals: true
                )
                .frame(width: heightWidth)
            }
            Toggle("Birthday", isOn: Binding(
                get: { profile.birthday != nil },
                set: { on in profile.birthdayDate = on ? (profile.birthdayDate ?? Self.defaultBirthday) : nil }
            ))
            if profile.birthday != nil {
                DatePicker(
                    "Date of birth",
                    selection: Binding(
                        get: { profile.birthdayDate ?? Self.defaultBirthday },
                        set: { profile.birthdayDate = $0 }
                    ),
                    in: ...Date.now,
                    displayedComponents: .date
                )
                .environment(\.timeZone, TimeZone(identifier: "UTC")!)
            }
        } header: {
            Text("Optional")
        }
    }

    private static let defaultBirthday = Date(timeIntervalSince1970: 631_152_000) // 1 Jan 1990
}

/// Asked once after the first sign-in, when the account has no profile yet.
struct ProfileSetupView: View {
    @Environment(LocalStore.self) private var store
    @Environment(SyncEngine.self) private var sync
    @State private var profile = Profile(unitSystem: WeightUnit.default() == .lb ? .imperial : .metric)

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("A few details so weights show in your unit and programs fit you. You can change them in Me › Profile.")
                        .foregroundStyle(.secondary)
                }
                ProfileForm(profile: $profile)
            }
            .brandBackground()
            .navigationTitle("About you")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Continue") {
                        store.save(profile)
                        Task { await sync.sync() }
                    }
                }
            }
        }
        .interactiveDismissDisabled()
    }
}

/// Me → Profile: the photo and email, the profile fields, and the app's settings.
struct ProfileSettingsView: View {
    let account: MeView.AccountState
    @Environment(LocalStore.self) private var store
    @Environment(SyncEngine.self) private var sync

    var body: some View {
        Form {
            ProfilePhotoSection(account: account)

            ProfileForm(profile: Binding(
                get: { store.profile ?? Profile(unitSystem: WeightUnit.default() == .lb ? .imperial : .metric) },
                set: { store.save($0) }
            ))

            HealthSettingsSection()
            CoachSettingsSection()
            AppFooter()
        }
        .brandBackground()
        .navigationTitle("Profile")
        .onDisappear {
            Task { await sync.sync() }
        }
    }
}

/// The end of the profile, without a card: the app's language, the website's pages,
/// and the version.
private struct AppFooter: View {
    @Environment(CoachService.self) private var coach

    var body: some View {
        Section {
            VStack(spacing: 18) {
                Menu {
                    Picker("Language", selection: Binding(
                        get: { AppLanguage.choice },
                        set: { choice in
                            AppLanguage.choose(choice)
                            coach.languageChanged()
                        }
                    )) {
                        Text("Same as iPhone").tag(AppLanguage.Choice.system)
                        // Each language in its own words, as iOS lists them.
                        Text(verbatim: "English").tag(AppLanguage.Choice.english)
                        Text(verbatim: "简体中文").tag(AppLanguage.Choice.chinese)
                    }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "globe")
                        Text(verbatim: AppLanguage.isChinese ? "简体中文" : "English")
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                    .font(.subheadline)
                    .foregroundStyle(.primary)
                    .padding(.horizontal, 14)
                    .frame(minHeight: 36)
                    .overlay { Capsule().stroke(Color.secondary.opacity(0.35)) }
                }
                .tint(.primary)
                .accessibilityLabel("Language")
                .accessibilityValue(Text(verbatim: AppLanguage.isChinese ? "简体中文" : "English"))
                .accessibilityIdentifier("language")

                FittingStack(spacing: 28) {
                    SitePageButton(page: .privacy)
                    SitePageButton(page: .support)
                }
                .font(.subheadline)

                VStack(spacing: 2) {
                    Text(verbatim: "IronSage")
                        .font(.subheadline.weight(.bold))
                    Text("Version \(Self.version)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .buttonStyle(.borderless)
            .frame(maxWidth: .infinity)
            .padding(.top, 24)
            .listRowBackground(Color.clear)
        }
    }

    private static var version: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return "\(version) (\(build))"
    }
}

extension Goal {
    var label: LocalizedStringResource {
        switch self {
        case .strength: "Get stronger"
        case .hypertrophy: "Build muscle"
        case .general: "Stay fit"
        }
    }
}
