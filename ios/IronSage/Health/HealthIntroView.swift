import SwiftUI

/// Explains what IronSage reads and writes before Apple's permission sheet appears.
struct HealthIntroView: View {
    @Environment(HealthService.self) private var health
    @Environment(\.dismiss) private var dismiss

    private let reads: [(String, LocalizedStringResource)] = [
        ("bed.double", "Sleep, by stage"),
        ("waveform.path.ecg", "Heart rate variability and resting heart rate"),
        ("heart", "Heart rate and active energy during workouts"),
        ("scalemass", "Body weight"),
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Image(systemName: "heart.text.square")
                        .font(.system(size: 48))
                        .foregroundStyle(.tint)
                        .accessibilityHidden(true)
                    Text("Connect Apple Health")
                        .font(.largeTitle.weight(.bold))
                    Text("IronSage reads these to show your progress and to compare each day with your usual:")
                        .foregroundStyle(.secondary)
                    VStack(alignment: .leading, spacing: 14) {
                        ForEach(reads, id: \.0) { icon, label in
                            Label { Text(label) } icon: { Image(systemName: icon).foregroundStyle(.tint).frame(width: 28) }
                        }
                    }
                    Text("It saves your workouts, and the weights you enter, to Apple Health.")
                        .foregroundStyle(.secondary)
                    Text("Your health data is kept in your IronSage account and is never used for ads. You can change what IronSage may read at any time in the Health settings on your iPhone.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .padding(24)
            }
            .safeAreaInset(edge: .bottom) {
                VStack(spacing: 8) {
                    Button("Connect Apple Health") {
                        Task {
                            await health.connect()
                            dismiss()
                        }
                    }
                    .buttonStyle(BrandPrimaryButtonStyle())
                    Button("Not now") {
                        health.dismissIntro()
                        dismiss()
                    }
                    .padding(.vertical, 8)
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 8)
                .background(Color.appBackground)
            }
            .background(Color.appBackground)
        }
        .interactiveDismissDisabled()
    }
}

/// Settings → Apple Health.
struct HealthSettingsSection: View {
    @Environment(HealthService.self) private var health
    @State private var isShowingIntro = false

    var body: some View {
        Section {
            if !health.isAvailable {
                Text("Apple Health isn't available on this device.")
                    .foregroundStyle(.secondary)
            } else if health.hasAsked {
                LabeledContent("Apple Health", value: String(localized: "Connected"))
            } else {
                Button("Connect Apple Health") { isShowingIntro = true }
            }
        } header: {
            Text("Apple Health")
        } footer: {
            if health.isAvailable && health.hasAsked {
                Text("To change what IronSage can read or write, open Settings on your iPhone, then Health, Data Access & Devices, IronSage.")
            }
        }
        .sheet(isPresented: $isShowingIntro) {
            HealthIntroView()
        }
    }
}
