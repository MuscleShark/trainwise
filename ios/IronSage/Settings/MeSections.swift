import Charts
import IronSageCore
import IronSageStore
import SwiftUI

/// Shown only when changes can't reach the server; syncing that works stays out of sight.
struct SyncProblemSection: View {
    @Environment(LocalStore.self) private var store
    @Environment(SyncEngine.self) private var sync

    var body: some View {
        switch sync.state {
        case .failed:
            Section {
                problem("Couldn't sync", detail: "Your changes are safe on this iPhone.")
                Button("Try again") {
                    Task { await sync.sync() }
                }
            }
        case .offline where store.hasUnsyncedChanges:
            Section {
                problem("Not synced yet", detail: "Your changes are saved on this iPhone and upload when you're back online.")
            }
        default:
            EmptyView()
        }
    }

    private func problem(_ title: LocalizedStringResource, detail: LocalizedStringResource) -> some View {
        Label {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        } icon: {
            Image(systemName: "exclamationmark.icloud")
                .foregroundStyle(.orange)
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("syncProblem")
    }
}

/// Workouts in all, this week against the planned training days, and weeks in a row.
struct TrainingStatsSection: View {
    @Environment(LocalStore.self) private var store

    var body: some View {
        let workouts = store.finishedWorkouts
        let thisWeek = TrainingProgress.workoutsThisWeek(in: workouts)
        Section("Training") {
            HStack(spacing: 0) {
                stat(Text(workouts.count, format: .number), label: "Workouts")
                Divider()
                if let planned = store.profile?.trainingDaysPerWeek {
                    stat(Text(verbatim: "\(thisWeek.formatted())/\(planned.formatted())"), label: "This week")
                } else {
                    stat(Text(thisWeek, format: .number), label: "This week")
                }
                Divider()
                stat(Text(TrainingProgress.weekStreak(in: workouts), format: .number), label: "Weeks in a row")
            }
            .padding(.vertical, 6)
        }
    }

    private func stat(_ value: Text, label: LocalizedStringResource) -> some View {
        VStack(spacing: 2) {
            value
                .font(.title2.weight(.bold))
                .monospacedDigit()
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }
}

/// The latest body weight with its recent trend; opens Progress.
struct BodySection: View {
    @Environment(LocalStore.self) private var store
    @Environment(\.selectTab) private var selectTab

    var body: some View {
        let unit = store.weightUnit
        let latest = BodyWeight.latest(store.bodyMeasurements)
        let trend = BodyWeight.trend(store.bodyMeasurements, days: 90)
        Section("Body") {
            Button {
                selectTab(.progress)
            } label: {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Body weight")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        if let latest {
                            Text(unit.formatWithUnit(kilograms: latest.value))
                                .font(.title3.weight(.bold))
                                .monospacedDigit()
                            Text(latest.measuredAt.shortDay)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else {
                            Text("Not entered yet")
                                .font(.subheadline)
                        }
                    }
                    Spacer()
                    if trend.count >= 2 {
                        Sparkline(weights: trend, unit: unit)
                    }
                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("bodyWeight")
            .accessibilityHint(Text("Opens Progress"))
        }
    }
}

/// A small line of the last 90 days of weight, without axes.
private struct Sparkline: View {
    let weights: [BodyMeasurement]
    let unit: WeightUnit

    var body: some View {
        Chart(weights) { weight in
            LineMark(x: .value("Date", weight.measuredAt), y: .value("Weight", unit.value(fromKilograms: weight.value)))
                .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                .foregroundStyle(Color.chartMark)
        }
        .chartYScale(domain: .automatic(includesZero: false))
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .frame(width: 96, height: 36)
        .accessibilityHidden(true)
    }
}
