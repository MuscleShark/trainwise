import Combine
import IronSageCore
import IronSageStore
import SwiftUI

/// Last night's sleep, HRV and resting heart rate, each next to the user's usual (the 28
/// days before). Without Apple Health access it offers to connect; without data it says so.
struct ReadinessCard: View {
    @Environment(LocalStore.self) private var store
    @Environment(HealthService.self) private var health
    @State private var isConnecting = false
    /// Today's date, moved on at midnight so the card doesn't keep showing yesterday.
    @State private var today = HealthDays.key(.now)

    var body: some View {
        content
            .onReceive(NotificationCenter.default.publisher(for: .NSCalendarDayChanged).receive(on: RunLoop.main)) { _ in
                today = HealthDays.key(.now)
            }
    }

    @ViewBuilder private var content: some View {
        let day = ReadinessComparison.compare(store.readiness, on: today)
        if let day {
            Section {
                if let sleep = day.sleep {
                    row("Sleep", systemImage: "bed.double", value: Self.duration(sleep.value), metric: sleep, usual: sleep.usual.map(Self.duration))
                }
                if let hrv = day.hrv {
                    row("HRV", systemImage: "waveform.path.ecg", value: Self.milliseconds(hrv.value), metric: hrv, usual: hrv.usual.map(Self.milliseconds))
                }
                if let resting = day.restingHeartRate {
                    row("Resting heart rate", systemImage: "heart", value: Self.beats(resting.value), metric: resting, usual: resting.usual.map(Self.beats))
                }
            } header: {
                Text("Last night")
            } footer: {
                if [day.sleep, day.hrv, day.restingHeartRate].contains(where: { $0 != nil && $0?.usual == nil }) {
                    Text("Your usual appears after a week of nights.")
                } else {
                    Text("Compared with your average over the 28 days before.")
                }
            }
        } else if health.isAvailable {
            Section {
                if health.hasAsked {
                    Text("No sleep or heart data for last night yet. With an Apple Watch worn overnight, it appears here in the morning.")
                        .foregroundStyle(.secondary)
                } else {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Connect Apple Health to see last night's sleep and heart rate next to your usual.")
                        Button("Connect Apple Health") { isConnecting = true }
                            .font(.subheadline.weight(.semibold))
                            .buttonStyle(.bordered)
                    }
                    .padding(.vertical, 4)
                }
            } header: {
                Text("Last night")
            }
            .sheet(isPresented: $isConnecting) {
                HealthIntroView()
            }
        }
    }

    private func row(_ title: LocalizedStringKey, systemImage: String, value: String, metric: ReadinessComparison.Metric, usual: String?) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Label {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                    if let comparison = Self.comparison(metric.direction, usual: usual) {
                        Text(comparison)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
            } icon: {
                Image(systemName: systemImage)
                    .foregroundStyle(.tint)
                    .frame(width: 28)
            }
            Spacer()
            HStack(spacing: 4) {
                if let arrow = Self.arrow(metric.direction) {
                    Image(systemName: arrow)
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.secondary)
                        .accessibilityHidden(true)
                }
                Text(value)
                    .font(.headline)
                    .monospacedDigit()
            }
        }
        .accessibilityElement(children: .combine)
    }

    private static func comparison(_ direction: ReadinessComparison.Direction?, usual: String?) -> String? {
        guard let direction, let usual else { return nil }
        return switch direction {
        case .lower: String(localized: "Lower than your usual \(usual)")
        case .usual: String(localized: "About your usual \(usual)")
        case .higher: String(localized: "Higher than your usual \(usual)")
        }
    }

    private static func arrow(_ direction: ReadinessComparison.Direction?) -> String? {
        switch direction {
        case .lower: "arrow.down"
        case .higher: "arrow.up"
        case .usual, nil: nil
        }
    }

    /// "7 hr, 5 min"
    static func duration(_ minutes: Double) -> String {
        Duration.seconds((minutes.rounded()) * 60)
            .formatted(.units(allowed: [.hours, .minutes], width: .abbreviated))
    }

    static func milliseconds(_ value: Double) -> String {
        String(localized: "\(Int(value.rounded())) ms")
    }

    static func beats(_ value: Double) -> String {
        String(localized: "\(Int(value.rounded())) bpm")
    }
}
