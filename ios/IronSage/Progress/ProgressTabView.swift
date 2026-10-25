import Charts
import IronSageCore
import IronSageStore
import SwiftUI

/// The Progress tab: body weight, weekly sets per muscle, weekly volume, and a way into
/// each exercise's progress.
struct ProgressTabView: View {
    @Environment(LocalStore.self) private var store

    var body: some View {
        NavigationStack {
            List {
                BodyWeightSection()
                WeeklySetsSection()
                WeeklyVolumeSection()
                ExercisesSection()
            }
            .brandBackground()
            .navigationTitle("Progress")
            .navigationDestination(for: ExerciseRoute.self) { route in
                ExerciseDetailView(exerciseID: route.id)
            }
            .navigationDestination(for: WorkoutRoute.self) { route in
                WorkoutDetailView(workoutID: route.id)
            }
            .navigationDestination(for: WeightListRoute.self) { _ in
                WeightListView()
            }
        }
    }
}

private struct WeightListRoute: Hashable {}

// MARK: Body weight

/// The latest weight. One from Apple Health is shown with its date and the question
/// whether it is still current; if it isn't, or there is none, the user types it in.
private struct BodyWeightSection: View {
    @Environment(LocalStore.self) private var store
    @Environment(HealthService.self) private var health
    @Environment(SyncEngine.self) private var sync
    @AppStorage("IronSage.weight.confirmed") private var confirmedIDs = ""
    @State private var isEntering = false

    private var confirmed: Set<UUID> {
        Set(confirmedIDs.split(separator: ",").compactMap { UUID(uuidString: String($0)) })
    }

    var body: some View {
        let unit = store.weightUnit
        let latest = BodyWeight.latest(store.bodyMeasurements)
        Section {
            if let latest {
                let asking = BodyWeight.needsConfirmation(latest, confirmed: confirmed)
                if asking {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Apple Health has \(unit.formatWithUnit(kilograms: latest.value)) from \(latest.measuredAt.shortDay). Is that still your weight?")
                        HStack {
                            Button("Yes, still current") { confirm(latest) }
                                .buttonStyle(.borderedProminent)
                            Button("Enter my weight") { isEntering = true }
                                .buttonStyle(.bordered)
                        }
                        .font(.subheadline.weight(.semibold))
                    }
                    .padding(.vertical, 4)
                } else {
                    LabeledContent {
                        Text(latest.measuredAt.shortDay)
                    } label: {
                        Text(unit.formatWithUnit(kilograms: latest.value))
                            .font(.title2.weight(.bold))
                            .monospacedDigit()
                    }
                }
                let trend = BodyWeight.trend(store.bodyMeasurements, days: 90)
                if trend.count >= 2 {
                    WeightChart(weights: trend, unit: unit)
                }
                if !asking {
                    Button("Enter my weight", systemImage: "plus") { isEntering = true }
                }
                NavigationLink("All weights", value: WeightListRoute())
            } else {
                Text(health.hasAsked
                     ? "Apple Health has no weight for you yet."
                     : "No weight yet.")
                    .foregroundStyle(.secondary)
                Button("Enter my weight", systemImage: "plus") { isEntering = true }
            }
        } header: {
            Text("Body weight")
        }
        .sheet(isPresented: $isEntering) {
            WeightEntryView { weight in
                store.save(weight)
                Task {
                    await health.saveToHealth(weight)
                    await sync.sync()
                }
            }
        }
    }

    private func confirm(_ weight: BodyMeasurement) {
        confirmedIDs = (confirmed.union([weight.id])).map(\.uuidString).joined(separator: ",")
    }
}

private struct WeightChart: View {
    let weights: [BodyMeasurement]
    let unit: WeightUnit

    var body: some View {
        Chart(weights) { weight in
            LineMark(x: .value("Date", weight.measuredAt), y: .value("Weight", unit.value(fromKilograms: weight.value)))
                .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                .foregroundStyle(Color.chartMark)
            if weight.id == weights.last?.id {
                PointMark(x: .value("Date", weight.measuredAt), y: .value("Weight", unit.value(fromKilograms: weight.value)))
                    .symbolSize(64)
                    .foregroundStyle(Color.chartMark)
            }
        }
        .chartYScale(domain: .automatic(includesZero: false))
        .chartXScale(range: .plotDimension(padding: 8))
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 4)) { _ in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                AxisValueLabel(format: .dateTime.month(.abbreviated).day())
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) { _ in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                AxisValueLabel()
            }
        }
        .frame(height: 160)
        .padding(.vertical, 4)
        .accessibilityLabel(Text("Body weight over the last 90 days, in \(String(localized: unit.symbol))"))
    }
}

/// Typing in a weight. It is saved to the phone and to Apple Health.
private struct WeightEntryView: View {
    let onSave: (BodyMeasurement) -> Void
    @Environment(LocalStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var value: Double?
    @State private var date = Date.now
    @FocusState private var isFocused: Bool

    var body: some View {
        let unit = store.weightUnit
        NavigationStack {
            Form {
                LabeledContent("Weight") {
                    HStack(spacing: 4) {
                        TextField("Weight", value: $value, format: .number.precision(.fractionLength(0...unit.decimals)))
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .focused($isFocused)
                        Text(unit.symbol)
                            .foregroundStyle(.secondary)
                    }
                }
                DatePicker("Date", selection: $date, in: ...Date.now)
            }
            .brandBackground()
            .navigationTitle("Enter my weight")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        guard let kilograms else { return }
                        onSave(BodyMeasurement(measuredAt: date, value: kilograms, source: .manual))
                        dismiss()
                    }
                    .disabled(kilograms == nil)
                }
            }
            .onAppear { isFocused = true }
        }
        .presentationDetents([.medium])
    }

    /// The typed weight in kilograms, when it is a plausible body weight (20–400 kg).
    private var kilograms: Double? {
        guard let value else { return nil }
        let kg = store.weightUnit.kilograms(from: value)
        return (20...400).contains(kg) ? kg : nil
    }
}

/// Every weight, newest first. Typed-in ones can be deleted; those from Apple Health
/// are managed in the Health app.
private struct WeightListView: View {
    @Environment(LocalStore.self) private var store
    @Environment(HealthService.self) private var health
    @Environment(SyncEngine.self) private var sync

    var body: some View {
        let unit = store.weightUnit
        let weights = store.bodyMeasurements.filter { $0.kind == .weight }
        List {
            ForEach(weights) { weight in
                LabeledContent {
                    Text(weight.source == .healthkit ? String(localized: "Apple Health") : String(localized: "Entered"))
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(unit.formatWithUnit(kilograms: weight.value))
                            .monospacedDigit()
                        Text(weight.measuredAt, format: .dateTime.month().day().year().hour().minute())
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .deleteDisabled(weight.source == .healthkit)
            }
            .onDelete { offsets in
                for weight in offsets.map({ weights[$0] }) where weight.source == .manual {
                    store.deleteBodyMeasurement(id: weight.id)
                    Task { await health.removeFromHealth(weight) }
                }
                Task { await sync.sync() }
            }
        }
        .brandBackground()
        .navigationTitle("All weights")
    }
}

// MARK: Weekly sets

private struct WeeklySetsSection: View {
    @Environment(LocalStore.self) private var store
    @State private var weeksBack = 0
    private let rowHeight: CGFloat = 26

    var body: some View {
        let calendar = Calendar.current
        let day = calendar.date(byAdding: .weekOfYear, value: -weeksBack, to: .now)!
        let week = calendar.dateInterval(of: .weekOfYear, for: day)!
        let sets = TrainingProgress.weeklySets(in: store.finishedWorkouts, exercises: store.exercises, week: week)
        let reference = TrainingProgress.setsReference
        Section {
            Picker("Week", selection: $weeksBack) {
                Text("This week").tag(0)
                Text("Last week").tag(1)
            }
            .pickerStyle(.segmented)
            .listRowSeparator(.hidden)

            if sets.isEmpty {
                Text("No sets this week yet.")
                    .foregroundStyle(.secondary)
            } else {
                Chart {
                    ForEach(sets, id: \.muscle) { item in
                        RectangleMark(
                            xStart: .value("Reference low", reference.lowerBound),
                            xEnd: .value("Reference high", reference.upperBound),
                            y: .value("Muscle", String(localized: item.muscle.label)),
                            height: .fixed(rowHeight)
                        )
                        .foregroundStyle(Color.primary.opacity(0.06))
                        BarMark(
                            x: .value("Sets", item.sets),
                            y: .value("Muscle", String(localized: item.muscle.label)),
                            height: .fixed(14)
                        )
                        .clipShape(UnevenRoundedRectangle(bottomTrailingRadius: 4, topTrailingRadius: 4))
                        .foregroundStyle(Color.chartMark)
                        .annotation(position: .trailing, spacing: 4) {
                            Text(item.sets.formatted(.number.precision(.fractionLength(0...1))))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                    }
                }
                .chartXScale(domain: 0...max(reference.upperBound + 2, (sets.first?.sets ?? 0) + 3))
                .chartXAxis {
                    AxisMarks(values: [0, reference.lowerBound, reference.upperBound]) { _ in
                        AxisValueLabel()
                    }
                }
                .chartYAxis {
                    AxisMarks(preset: .extended, position: .leading) { _ in
                        AxisValueLabel()
                    }
                }
                .frame(height: CGFloat(sets.count) * rowHeight + 24)
                .accessibilityLabel(Text("Sets per muscle"))
            }
        } header: {
            Text("Sets per muscle")
        } footer: {
            Text("A set counts 1 for the main muscles of the exercise and ½ for the ones that help. The shaded band, 10 to 20 sets a week, is where most people grow.")
        }
    }
}

// MARK: Weekly volume

private struct WeeklyVolumeSection: View {
    @Environment(LocalStore.self) private var store

    var body: some View {
        let unit = store.weightUnit
        let weeks = TrainingProgress.weeklyVolume(in: store.finishedWorkouts, exercises: store.exercises, weeks: 8)
        Section {
            if weeks.allSatisfy({ $0.kilograms == 0 }) {
                Text("Finish a workout to see your weekly volume.")
                    .foregroundStyle(.secondary)
            } else {
                Chart(weeks, id: \.start) { week in
                    BarMark(
                        x: .value("Week", week.start, unit: .weekOfYear),
                        y: .value("Volume", unit.value(fromKilograms: week.kilograms)),
                        width: .ratio(0.6)
                    )
                    .clipShape(UnevenRoundedRectangle(topLeadingRadius: 4, topTrailingRadius: 4))
                    .foregroundStyle(Color.chartMark)
                }
                .chartXAxis {
                    AxisMarks(values: .stride(by: .weekOfYear, count: 2)) { _ in
                        AxisValueLabel(format: .dateTime.month(.abbreviated).day(), centered: true)
                    }
                }
                .chartYAxis {
                    AxisMarks(position: .leading, values: .automatic(desiredCount: 3)) { value in
                        AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                        AxisValueLabel {
                            if let amount = value.as(Double.self) {
                                Text(amount.formatted(.number.notation(.compactName)))
                            }
                        }
                    }
                }
                .frame(height: 160)
                .padding(.vertical, 4)
                .accessibilityLabel(Text("Volume per week, in \(String(localized: unit.symbol))"))
            }
        } header: {
            Text("Weekly volume")
        } footer: {
            Text("Weight × reps of the working sets, per week.")
        }
    }
}

// MARK: Exercises

private struct ExercisesSection: View {
    @Environment(LocalStore.self) private var store

    var body: some View {
        let exercises = TrainingProgress.recentExercises(in: store.finishedWorkouts)
        if !exercises.isEmpty {
            Section("Exercises") {
                ForEach(exercises, id: \.self) { id in
                    NavigationLink(store.exerciseName(id), value: ExerciseRoute(id: id))
                }
            }
        }
    }
}
