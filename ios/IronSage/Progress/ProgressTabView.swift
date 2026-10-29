import Charts
import IronSageCore
import IronSageStore
import SwiftUI

/// The Progress tab: body weight and body fat, weekly sets per muscle, weekly volume,
/// and a way into each exercise's progress.
struct ProgressTabView: View {
    @Environment(LocalStore.self) private var store
    @AppStorage("IronSage.body.range") private var range = BodyTrend.Range.month

    var body: some View {
        NavigationStack {
            List {
                WeeklySummaryCard()
                BodyWeightSection(range: $range)
                BodyFatSection(range: range)
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
            .navigationDestination(for: MeasurementListRoute.self) { route in
                MeasurementListView(kind: route.kind)
            }
        }
    }
}

private struct MeasurementListRoute: Hashable {
    let kind: MeasurementKind
}

// MARK: Body weight and body fat

/// The latest weight. One from Apple Health is shown with its date and the question
/// whether it is still current; if it isn't, or there is none, the user types it in.
/// The period chosen here applies to the body fat chart too.
private struct BodyWeightSection: View {
    @Binding var range: BodyTrend.Range
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
        let latest = BodyTrend.latest(store.bodyMeasurements, kind: .weight)
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
                    LatestRow(value: unit.formatWithUnit(kilograms: latest.value), date: latest.measuredAt)
                }
                BodyRangePicker(range: $range)
                let points = BodyTrend.points(store.bodyMeasurements, kind: .weight, range: range)
                    .map { BodyTrend.Point(date: $0.date, value: unit.value(fromKilograms: $0.value)) }
                BodyChart(points: points, range: range, title: "Body weight", unit: String(localized: unit.symbol))
                if !asking {
                    Button("Enter my weight", systemImage: "plus") { isEntering = true }
                }
                NavigationLink("All weights", value: MeasurementListRoute(kind: .weight))
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

/// The latest body fat, from Apple Health (smart scales save it there) or typed in.
private struct BodyFatSection: View {
    let range: BodyTrend.Range
    @Environment(LocalStore.self) private var store
    @Environment(HealthService.self) private var health
    @Environment(SyncEngine.self) private var sync
    @State private var isEntering = false

    var body: some View {
        let latest = BodyTrend.latest(store.bodyMeasurements, kind: .bodyFat)
        Section {
            if let latest {
                LatestRow(value: BodyFat.format(latest.value), date: latest.measuredAt)
                BodyChart(
                    points: BodyTrend.points(store.bodyMeasurements, kind: .bodyFat, range: range),
                    range: range,
                    title: "Body fat",
                    unit: "%"
                )
                Button("Enter body fat", systemImage: "plus") { isEntering = true }
                NavigationLink("All body fat", value: MeasurementListRoute(kind: .bodyFat))
            } else {
                Text("No body fat yet. Smart scales usually save it to Apple Health.")
                    .foregroundStyle(.secondary)
                Button("Enter body fat", systemImage: "plus") { isEntering = true }
            }
            if health.hasNewTypes {
                Button("Allow body fat from Apple Health", systemImage: "heart") {
                    Task { await health.connect() }
                }
            }
        } header: {
            Text("Body fat")
        }
        .task { await health.checkForNewTypes() }
        .sheet(isPresented: $isEntering) {
            BodyFatEntryView { bodyFat in
                store.save(bodyFat)
                Task {
                    await health.saveToHealth(bodyFat)
                    await sync.sync()
                }
            }
        }
    }
}

private struct LatestRow: View {
    let value: String
    let date: Date

    var body: some View {
        LabeledContent {
            Text(date.shortDay)
        } label: {
            Text(value)
                .font(.title2.weight(.bold))
                .monospacedDigit()
        }
    }
}

/// Week, month, year or everything, for both body charts.
private struct BodyRangePicker: View {
    @Binding var range: BodyTrend.Range

    var body: some View {
        Picker("Period", selection: $range) {
            ForEach(BodyTrend.Range.allCases, id: \.self) { range in
                Text(range.label).tag(range)
            }
        }
        .pickerStyle(.segmented)
        .accessibilityIdentifier("bodyRange")
    }
}

extension BodyTrend.Range {
    var label: LocalizedStringResource {
        switch self {
        case .week: "Week"
        case .month: "Month"
        case .year: "Year"
        case .all: "All"
        }
    }

    /// "the last month", for VoiceOver.
    var spoken: LocalizedStringResource {
        switch self {
        case .week: "the last 7 days"
        case .month: "the last month"
        case .year: "the last year"
        case .all: "all time"
        }
    }

    var axisFormat: Date.FormatStyle {
        switch self {
        case .week: .dateTime.weekday(.abbreviated)
        case .month: .dateTime.month(.abbreviated).day()
        case .year: .dateTime.month(.abbreviated)
        case .all: .dateTime.month(.abbreviated).year(.twoDigits)
        }
    }
}

/// A body measurement over the chosen period, already in the unit shown.
private struct BodyChart: View {
    let points: [BodyTrend.Point]
    let range: BodyTrend.Range
    let title: LocalizedStringResource
    let unit: String

    var body: some View {
        if points.isEmpty {
            Text("Nothing in this period")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        } else {
            Chart(points, id: \.date) { point in
                LineMark(x: .value("Date", point.date), y: .value(String(localized: title), point.value))
                    .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                    .foregroundStyle(Color.chartMark)
                if point == points.last {
                    PointMark(x: .value("Date", point.date), y: .value(String(localized: title), point.value))
                        .symbolSize(64)
                        .foregroundStyle(Color.chartMark)
                }
            }
            .chartYScale(domain: .automatic(includesZero: false))
            .chartXScale(domain: domain, range: .plotDimension(padding: 8))
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: 4)) { _ in
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                    AxisValueLabel(format: range.axisFormat)
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
            .accessibilityLabel(Text("\(String(localized: title)) over \(String(localized: range.spoken)), in \(unit)"))
        }
    }

    /// The whole period, so a few points don't stretch across the chart; all time spans
    /// the points themselves.
    private var domain: ClosedRange<Date> {
        let first = points.first?.date ?? .now
        let start = range.start().map { min($0, first) } ?? first
        let end = max(points.last?.date ?? .now, range == .all ? first : .now)
        return start...max(end, start.addingTimeInterval(86_400))
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

/// Typing in body fat. It is saved to the phone and to Apple Health.
private struct BodyFatEntryView: View {
    let onSave: (BodyMeasurement) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var value: Double?
    @State private var date = Date.now
    @FocusState private var isFocused: Bool

    var body: some View {
        NavigationStack {
            Form {
                LabeledContent("Body fat") {
                    HStack(spacing: 4) {
                        TextField("Body fat", value: $value, format: .number.precision(.fractionLength(0...1)))
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .focused($isFocused)
                        Text(verbatim: "%")
                            .foregroundStyle(.secondary)
                    }
                }
                DatePicker("Date", selection: $date, in: ...Date.now)
            }
            .brandBackground()
            .navigationTitle("Enter body fat")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        guard let percent else { return }
                        onSave(BodyMeasurement(measuredAt: date, kind: .bodyFat, value: percent, source: .manual))
                        dismiss()
                    }
                    .disabled(percent == nil)
                }
            }
            .onAppear { isFocused = true }
        }
        .presentationDetents([.medium])
    }

    private var percent: Double? {
        guard let value, BodyFat.plausible.contains(value) else { return nil }
        return value
    }
}

extension BodyFat {
    /// "18.5%"
    static func format(_ percent: Double) -> String {
        (percent / 100).formatted(.percent.precision(.fractionLength(0...1)))
    }
}

/// Every weight or body fat, newest first. Typed-in ones can be deleted; those from
/// Apple Health are managed in the Health app.
private struct MeasurementListView: View {
    let kind: MeasurementKind
    @Environment(LocalStore.self) private var store
    @Environment(HealthService.self) private var health
    @Environment(SyncEngine.self) private var sync

    var body: some View {
        let unit = store.weightUnit
        let measurements = store.bodyMeasurements
            .filter { $0.kind == kind }
            .sorted { $0.measuredAt > $1.measuredAt }
        List {
            ForEach(measurements) { measurement in
                LabeledContent {
                    Text(measurement.source == .healthkit ? String(localized: "Apple Health") : String(localized: "Entered"))
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(kind == .bodyFat ? BodyFat.format(measurement.value) : unit.formatWithUnit(kilograms: measurement.value))
                            .monospacedDigit()
                        Text(measurement.measuredAt, format: .dateTime.month().day().year().hour().minute())
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .deleteDisabled(measurement.source == .healthkit)
            }
            .onDelete { offsets in
                for measurement in offsets.map({ measurements[$0] }) where measurement.source == .manual {
                    store.deleteBodyMeasurement(id: measurement.id)
                    Task { await health.removeFromHealth(measurement) }
                }
                Task { await sync.sync() }
            }
        }
        .brandBackground()
        .navigationTitle(kind == .bodyFat ? LocalizedStringKey("All body fat") : LocalizedStringKey("All weights"))
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
