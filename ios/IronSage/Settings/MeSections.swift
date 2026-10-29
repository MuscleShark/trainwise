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
    @Environment(\.dynamicTypeSize) private var size

    var body: some View {
        let workouts = store.finishedWorkouts
        let thisWeek = TrainingProgress.workoutsThisWeek(in: workouts)
        let stats: [(Text, LocalizedStringResource)] = [
            (Text(workouts.count, format: .number), "Workouts"),
            (store.profile?.trainingDaysPerWeek.map { Text(verbatim: "\(thisWeek.formatted())/\($0.formatted())") }
                ?? Text(thisWeek, format: .number), "This week"),
            (Text(TrainingProgress.weekStreak(in: workouts), format: .number), "Weeks in a row"),
        ]
        Section("Training") {
            // Three across would break the labels mid-word at the accessibility sizes.
            if size.isAccessibilitySize {
                ForEach(stats.indices, id: \.self) { index in
                    AdaptiveRow {
                        Text(stats[index].1)
                            .foregroundStyle(.secondary)
                    } trailing: {
                        stats[index].0
                            .font(.title2.weight(.bold))
                            .monospacedDigit()
                    }
                    .accessibilityElement(children: .combine)
                }
            } else {
                HStack(spacing: 0) {
                    ForEach(stats.indices, id: \.self) { index in
                        if index > 0 {
                            Divider()
                        }
                        stat(stats[index].0, label: stats[index].1)
                    }
                }
                .padding(.vertical, 6)
            }
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

/// The latest body weight and body fat with their recent trend; each opens Progress.
struct BodySection: View {
    @Environment(LocalStore.self) private var store
    @Environment(\.selectTab) private var selectTab
    @Environment(\.dynamicTypeSize) private var size

    var body: some View {
        let unit = store.weightUnit
        let measurements = store.bodyMeasurements
        let bodyFat = BodyTrend.latest(measurements, kind: .bodyFat)
        let since = Date.now.addingTimeInterval(-90 * 86_400)
        Section("Body") {
            row(
                "Body weight",
                latest: BodyTrend.latest(measurements, kind: .weight),
                format: { unit.formatWithUnit(kilograms: $0) },
                trend: BodyWeight.trend(measurements, days: 90).map {
                    BodyTrend.Point(date: $0.measuredAt, value: unit.value(fromKilograms: $0.value))
                }
            )
            .accessibilityIdentifier("bodyWeight")
            // Shown once there is one: most people have no body fat to show.
            if bodyFat != nil {
                row(
                    "Body fat",
                    latest: bodyFat,
                    format: BodyFat.format,
                    trend: BodyTrend.points(measurements, kind: .bodyFat, range: .all).filter { $0.date >= since }
                )
                .accessibilityIdentifier("bodyFat")
            }
        }
    }

    private func row(
        _ title: LocalizedStringResource,
        latest: BodyMeasurement?,
        format: (Double) -> String,
        trend: [BodyTrend.Point]
    ) -> some View {
        Button {
            selectTab(.progress)
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    if let latest {
                        Text(format(latest.value))
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
                // The value gets the room at the accessibility sizes.
                if trend.count >= 2 && !size.isAccessibilitySize {
                    Sparkline(points: trend)
                }
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityHint(Text("Opens Progress"))
    }
}

/// A small line of the last 90 days, without axes.
private struct Sparkline: View {
    let points: [BodyTrend.Point]

    var body: some View {
        Chart(points, id: \.date) { point in
            LineMark(x: .value("Date", point.date), y: .value("Value", point.value))
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
