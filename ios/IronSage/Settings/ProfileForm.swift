import IronSageCore
import IronSageStore
import SwiftUI

/// The profile fields, shared by the first-run setup and Settings.
struct ProfileForm: View {
    @Binding var profile: Profile

    var body: some View {
        Section {
            Picker("Weights in", selection: $profile.unitSystem) {
                Text("Kilograms (kg)").tag(UnitSystem.metric)
                Text("Pounds (lb)").tag(UnitSystem.imperial)
            }
        }

        Section {
            Picker("Experience", selection: $profile.experienceLevel) {
                Text("Not set").tag(Level?.none)
                ForEach(Level.allCases, id: \.self) { level in
                    Text(level.label).tag(Level?.some(level))
                }
            }
            Picker("Goal", selection: $profile.goal) {
                Text("Not set").tag(Goal?.none)
                ForEach(Goal.allCases, id: \.self) { goal in
                    Text(goal.label).tag(Goal?.some(goal))
                }
            }
            Picker("Training days a week", selection: $profile.trainingDaysPerWeek) {
                Text("Not set").tag(Int?.none)
                ForEach(1...7, id: \.self) { days in
                    Text(days, format: .number).tag(Int?.some(days))
                }
            }
        } footer: {
            Text("Beginners usually start with Beginner full body; the coach will use these later to suggest your next sessions.")
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
                .frame(width: 90)
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
                    Text("A few details so weights show in your unit and programs fit you. You can change them in Settings.")
                        .foregroundStyle(.secondary)
                }
                ProfileForm(profile: $profile)
            }
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

/// Settings → Profile.
struct ProfileSettingsView: View {
    @Environment(LocalStore.self) private var store
    @Environment(SyncEngine.self) private var sync

    var body: some View {
        Form {
            ProfileForm(profile: Binding(
                get: { store.profile ?? Profile(unitSystem: WeightUnit.default() == .lb ? .imperial : .metric) },
                set: { store.save($0) }
            ))
        }
        .navigationTitle("Profile")
        .onDisappear {
            Task { await sync.sync() }
        }
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
