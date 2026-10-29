import Charts
import IronSageCore
import IronSageStore
import SwiftUI

/// One exercise over time: the estimated one-rep max chart, personal records, and every
/// session it was done in.
struct ExerciseDetailView: View {
    let exerciseID: UUID
    @Environment(LocalStore.self) private var store

    var body: some View {
        let unit = store.weightUnit
        let exercise = store.exercises[exerciseID]
        let sessions = ExerciseProgress.sessions(of: exerciseID, in: store.finishedWorkouts)
        let records = ExerciseProgress.records(sessions, loadType: exercise?.loadType ?? .total)
        List {
            if sessions.isEmpty {
                ContentUnavailableView(
                    "No sessions yet",
                    systemImage: "chart.line.uptrend.xyaxis",
                    description: Text("Finish a workout with this exercise to see its progress here.")
                )
                .listRowBackground(Color.clear)
            } else {
                if exercise?.loadType != .assisted {
                    Section {
                        EstimatedMaxChart(sessions: sessions, unit: unit)
                    } header: {
                        Text("Estimated 1RM")
                    } footer: {
                        Text("The best set of each session, from sets of 1 to 12 reps: weight × (1 + reps ÷ 30).")
                    }
                }
                if !records.isEmpty {
                    RecordsSection(records: records, unit: unit, loadType: exercise?.loadType ?? .total)
                }
                Section("Sessions") {
                    ForEach(sessions) { session in
                        NavigationLink(value: WorkoutRoute(id: session.workoutID)) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(session.date.shortDayWithWeekday)
                                    .font(.subheadline.weight(.semibold))
                                Text(session.sets.map(unit.formatSet).joined(separator: ", "))
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                    .monospacedDigit()
                            }
                        }
                    }
                }
            }
        }
        .brandBackground()
        .navigationTitle(store.exerciseName(exerciseID))
    }
}

/// Estimated one-rep max by session, as a line with a point per session. Touching the
/// chart shows that session's value.
private struct EstimatedMaxChart: View {
    let sessions: [ExerciseProgress.Session]
    let unit: WeightUnit
    @State private var selected: Date?
    @ChartHeight(200, maximum: 300) private var chartHeight

    private struct Point: Identifiable {
        let id: UUID
        let date: Date
        let kilograms: Double
        /// In the user's unit, for the chart's axis.
        let value: Double
    }

    var body: some View {
        let points = sessions.compactMap { session in
            session.estimatedOneRepMax.map { Point(id: session.workoutID, date: session.date, kilograms: $0, value: unit.value(fromKilograms: $0)) }
        }
        .sorted { $0.date < $1.date }
        let symbol = String(localized: unit.symbol)

        if points.count < 2 {
            Text("The chart appears after two sessions with sets of 1 to 12 reps.")
                .foregroundStyle(.secondary)
        } else {
            let shown = selected.flatMap { date in points.min { abs($0.date.timeIntervalSince(date)) < abs($1.date.timeIntervalSince(date)) } }
            let latest = points[points.count - 1]
            VStack(alignment: .leading, spacing: 8) {
                let headline = shown ?? latest
                VStack(alignment: .leading, spacing: 0) {
                    Text(unit.formatWithUnit(kilograms: headline.kilograms))
                        .font(.title2.weight(.bold))
                        .monospacedDigit()
                    Text(headline.date.shortDay)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                Chart(points) { point in
                    LineMark(x: .value("Date", point.date), y: .value("Estimated 1RM", point.value))
                        .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                        .foregroundStyle(Color.chartMark)
                        .interpolationMethod(.monotone)
                    PointMark(x: .value("Date", point.date), y: .value("Estimated 1RM", point.value))
                        .symbolSize(point.id == shown?.id ? 120 : 64)
                        .foregroundStyle(Color.chartMark)
                    if point.id == shown?.id {
                        RuleMark(x: .value("Date", point.date))
                            .lineStyle(StrokeStyle(lineWidth: 1))
                            .foregroundStyle(.secondary.opacity(0.5))
                    }
                }
                .chartYScale(domain: .automatic(includesZero: false))
                // Room at both ends so the first and last points and dates aren't cut off.
                .chartXScale(range: .plotDimension(padding: 16))
                .chartXAxis {
                    AxisMarks(values: .automatic(desiredCount: 4)) { _ in
                        AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                        AxisValueLabel(format: .dateTime.month(.abbreviated).day(), collisionResolution: .greedy(minimumSpacing: 8))
                    }
                }
                .chartYAxis {
                    AxisMarks(position: .leading) { _ in
                        AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                        AxisValueLabel()
                    }
                }
                .chartXSelection(value: $selected)
                .frame(height: chartHeight)
                .chartTextSize()
                .accessibilityLabel(Text("Estimated 1RM by session, in \(symbol)"))
            }
            .padding(.vertical, 4)
        }
    }
}

private struct RecordsSection: View {
    let records: ExerciseProgress.Records
    let unit: WeightUnit
    let loadType: LoadType

    var body: some View {
        Section("Records") {
            if let heaviest = records.heaviest {
                record("Heaviest set", value: unit.formatWithUnit(kilograms: heaviest.weightKg), detail: lift(heaviest), date: heaviest.date)
            }
            if let best = records.bestEstimate, let estimate = records.bestEstimateKg {
                record("Best estimated 1RM", value: unit.formatWithUnit(kilograms: estimate), detail: lift(best), date: best.date)
            }
            if !records.mostReps.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text(loadType == .assisted ? "Most reps at each assistance" : "Most reps at each weight")
                    Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 4) {
                        ForEach(records.mostReps, id: \.self) { item in
                            GridRow {
                                Text(item.weightKg > 0 ? unit.formatWithUnit(kilograms: item.weightKg) : String(localized: "Body weight"))
                                Text("\(item.reps) reps")
                                Text(item.date.shortDay)
                                    .foregroundStyle(.secondary)
                            }
                            .font(.subheadline)
                            .monospacedDigit()
                        }
                    }
                }
                .padding(.vertical, 2)
            }
        }
    }

    private func lift(_ lift: ExerciseProgress.Lift) -> String {
        unit.formatSet(WorkoutSet(reps: lift.reps, weightKg: lift.weightKg))
    }

    private func record(_ title: LocalizedStringKey, value: String, detail: String, date: Date) -> some View {
        LabeledContent {
            VStack(alignment: .trailing, spacing: 2) {
                Text(value)
                    .monospacedDigit()
                    .foregroundStyle(.primary)
                Text("\(detail), \(date.shortDay)")
                    .font(.caption)
                    .monospacedDigit()
            }
        } label: {
            Text(title)
        }
    }
}
