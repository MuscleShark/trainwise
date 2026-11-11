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

/// Estimated one-rep max by session, a point per session, over the chosen period (see
/// ChartParts.swift for how the charts work). Touching the chart shows that session's
/// value above it and its date over the line.
private struct EstimatedMaxChart: View {
    let sessions: [ExerciseProgress.Session]
    let unit: WeightUnit
    @AppStorage("IronSage.oneRepMax.range") private var range = BodyTrend.Range.all
    /// Where the finger is, before snapping to the nearest session.
    @State private var finger: Date?
    @ChartHeight(200, maximum: 300) private var chartHeight

    private static let ranges: [BodyTrend.Range] = [.month, .quarter, .year, .all]

    private struct Point: Identifiable {
        let id: UUID
        let date: Date
        let kilograms: Double
        /// In the user's unit, for the chart.
        let value: Double
    }

    var body: some View {
        let all = sessions.compactMap { session in
            session.estimatedOneRepMax.map { Point(id: session.workoutID, date: session.date, kilograms: $0, value: unit.value(fromKilograms: $0)) }
        }
        .sorted { $0.date < $1.date }

        if all.count < 2 {
            Text("The chart appears after two sessions with sets of 1 to 12 reps.")
                .foregroundStyle(.secondary)
        } else {
            let start = range.start()
            let points = all.filter { start == nil || $0.date >= start! }
            let shown = finger.flatMap { date in points.nearest(to: date, by: \.date) }
            let headline = shown ?? points.last ?? all[all.count - 1]
            VStack(alignment: .leading, spacing: 4) {
                VStack(alignment: .leading, spacing: 0) {
                    Text(unit.formatWithUnit(kilograms: headline.kilograms))
                        .font(.title2.weight(.bold))
                        .monospacedDigit()
                        .contentTransition(.numericText())
                    // Kept in place while hidden: the date is over the line then.
                    Text(headline.date.shortDay)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .opacity(shown == nil ? 1 : 0)
                }
                if points.isEmpty {
                    Text("Nothing in this period")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 8)
                } else {
                    chart(points, shown: shown)
                }
                ChartRangeButtons(range: $range, options: Self.ranges)
            }
            .padding(.vertical, 4)
            .onChange(of: range) { finger = nil }
        }
    }

    private func chart(_ points: [Point], shown: Point?) -> some View {
        let cut = shown.flatMap { point in points.firstIndex { $0.id == point.id } } ?? points.count - 1
        return Chart {
            ForEach(Array(points[...cut])) { point in
                LineMark(x: .value("Date", point.date), y: .value("Estimated 1RM", point.value), series: .value("Part", "before"))
                    .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                    .foregroundStyle(Color.chartMark)
                    .interpolationMethod(.monotone)
            }
            ForEach(Array(points[cut...])) { point in
                LineMark(x: .value("Date", point.date), y: .value("Estimated 1RM", point.value), series: .value("Part", "after"))
                    .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                    .foregroundStyle(Color.chartMark.opacity(0.25))
                    .interpolationMethod(.monotone)
            }
            ForEach(points) { point in
                PointMark(x: .value("Date", point.date), y: .value("Estimated 1RM", point.value))
                    .symbolSize(40)
                    .foregroundStyle(Color.chartMark.opacity(point.date > points[cut].date ? 0.25 : 1))
            }
            if let shown {
                RuleMark(x: .value("Date", shown.date))
                    .lineStyle(StrokeStyle(lineWidth: 1))
                    .foregroundStyle(Color.secondary.opacity(0.6))
                    .annotation(position: .top, spacing: 6, overflowResolution: .init(x: .fit(to: .chart), y: .disabled)) {
                        ChartDateLabel(date: shown.date)
                    }
                PointMark(x: .value("Date", shown.date), y: .value("Estimated 1RM", shown.value))
                    .symbol { ChartTouchDot() }
            }
        }
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .chartYScale(domain: .automatic(includesZero: false))
        // Room at both ends so the first and last points aren't cut off.
        .chartXScale(domain: chartSpan(points.map(\.date)), range: .plotDimension(padding: 16))
        .chartXSelection(value: $finger)
        .sensoryFeedback(.selection, trigger: shown?.id)
        .frame(height: chartHeight)
        // Room over the line for the touched session's date.
        .padding(.top, 24)
        .accessibilityLabel(Text("Estimated 1RM by session over \(String(appLocalized: range.spoken)), in \(String(appLocalized: unit.symbol))"))
        .accessibilityIdentifier("oneRepMaxChart")
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
                                Text(item.weightKg > 0 ? unit.formatWithUnit(kilograms: item.weightKg) : String(appLocalized: "Body weight"))
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
