import Charts
import IronSageCore
import IronSageStore
import SwiftUI

/// The Progress tab: body weight and body fat, weekly sets per muscle, weekly cardio,
/// and a way into each exercise's progress.
struct ProgressTabView: View {
    @Environment(LocalStore.self) private var store
    @Environment(HealthService.self) private var health
    @Environment(SyncEngine.self) private var sync
    @AppStorage("IronSage.body.range") private var range = BodyTrend.Range.month
    /// The measurement being entered. The sheet hangs on the list: on a section it
    /// would be copied to each row, and iOS 26 then doesn't show it.
    @State private var entering: Entering?

    var body: some View {
        NavigationStack {
            List {
                WeeklySummaryCard()
                BodyWeightSection(range: $range) { entering = Entering(kind: .weight) }
                BodyFatSection(range: $range) { entering = Entering(kind: .bodyFat) }
                WeeklySetsSection()
                CardioProgressSection()
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
            .sheet(item: $entering) { entering in
                if entering.kind == .bodyFat {
                    BodyFatEntryView(onSave: save)
                } else {
                    WeightEntryView(onSave: save)
                }
            }
        }
    }

    private func save(_ measurement: BodyMeasurement) {
        store.save(measurement)
        Task {
            // An estimate isn't a measurement, so Apple Health doesn't get it.
            if measurement.estimate == nil {
                await health.saveToHealth(measurement)
            }
            await sync.sync()
        }
    }

    private struct Entering: Identifiable {
        let kind: MeasurementKind
        var id: MeasurementKind { kind }
    }
}

private struct MeasurementListRoute: Hashable {
    let kind: MeasurementKind
}

// MARK: Body weight and body fat

/// The latest weight, over the chart: touching the chart shows that day's weight
/// instead. One from Apple Health also asks whether it is still current; if it isn't,
/// or there is none, the user types it in. The period chosen here applies to the body
/// fat chart too.
private struct BodyWeightSection: View {
    @Binding var range: BodyTrend.Range
    let enter: () -> Void
    @Environment(LocalStore.self) private var store
    @Environment(HealthService.self) private var health
    @AppStorage("IronSage.weight.confirmed") private var confirmedIDs = ""
    /// The date of the point being touched on the chart.
    @State private var touched: Date?

    private var confirmed: Set<UUID> {
        Set(confirmedIDs.split(separator: ",").compactMap { UUID(uuidString: String($0)) })
    }

    var body: some View {
        let unit = store.weightUnit
        let latest = BodyTrend.latest(store.bodyMeasurements, kind: .weight)
        Section {
            if let latest {
                let asking = BodyWeight.needsConfirmation(latest, confirmed: confirmed)
                let kilograms = BodyTrend.points(store.bodyMeasurements, kind: .weight, range: range)
                let shown = touched.flatMap { date in kilograms.first { $0.date == date } }
                LatestRow(value: unit.formatWithUnit(kilograms: shown?.value ?? latest.value), date: shown == nil ? latest.measuredAt : nil)
                if asking {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Apple Health has \(unit.formatWithUnit(kilograms: latest.value)) from \(latest.measuredAt.shortDay). Is that still your weight?")
                        FittingStack {
                            Button("Yes, still current") { confirm(latest) }
                                .buttonStyle(.borderedProminent)
                            Button("Enter my weight", action: enter)
                                .buttonStyle(.bordered)
                        }
                        .font(.subheadline.weight(.semibold))
                    }
                    .padding(.vertical, 4)
                }
                BodyChart(
                    points: kilograms.map { BodyTrend.Point(date: $0.date, value: unit.value(fromKilograms: $0.value)) },
                    range: $range,
                    touched: $touched,
                    title: "Body weight",
                    unit: String(appLocalized: unit.symbol)
                )
                if !asking {
                    Button("Enter my weight", systemImage: "plus", action: enter)
                }
                NavigationLink("All weights", value: MeasurementListRoute(kind: .weight))
            } else {
                Text(health.hasAsked
                     ? "Apple Health has no weight for you yet."
                     : "No weight yet.")
                    .foregroundStyle(.secondary)
                Button("Enter my weight", systemImage: "plus", action: enter)
            }
        } header: {
            Text("Body weight")
        }
    }

    private func confirm(_ weight: BodyMeasurement) {
        confirmedIDs = (confirmed.union([weight.id])).map(\.uuidString).joined(separator: ",")
    }
}

/// The latest body fat, from Apple Health (smart scales save it there) or typed in.
private struct BodyFatSection: View {
    @Binding var range: BodyTrend.Range
    let enter: () -> Void
    @Environment(LocalStore.self) private var store
    @Environment(HealthService.self) private var health
    /// The date of the point being touched on the chart.
    @State private var touched: Date?

    var body: some View {
        let latest = BodyTrend.latest(store.bodyMeasurements, kind: .bodyFat)
        Section {
            if let latest {
                let points = BodyTrend.points(store.bodyMeasurements, kind: .bodyFat, range: range)
                let shown = touched.flatMap { date in points.first { $0.date == date } }
                LatestRow(
                    value: shown.map(BodyFat.format) ?? BodyFat.format(latest),
                    date: shown == nil ? latest.measuredAt : nil,
                    isEstimate: latest.estimate != nil
                )
                if let change = BodyFat.estimateChange(store.bodyMeasurements) {
                    Text(BodyFat.describe(change))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                BodyChart(
                    points: points,
                    range: $range,
                    touched: $touched,
                    title: "Body fat",
                    unit: "%",
                    marksEachPoint: true
                )
                Button("Enter body fat", systemImage: "plus", action: enter)
                NavigationLink("All body fat", value: MeasurementListRoute(kind: .bodyFat))
            } else {
                Text("No body fat yet. Smart scales usually save it to Apple Health.")
                    .foregroundStyle(.secondary)
                Button("Enter body fat", systemImage: "plus", action: enter)
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
    }
}

/// The number over a body chart: the latest value with its date, or, while the chart
/// is touched, the touched point's value (its date is over the line then).
private struct LatestRow: View {
    let value: String
    /// Nil while the chart is touched.
    let date: Date?
    var isEstimate = false

    var body: some View {
        LabeledContent {
            // Kept in place while hidden, so the row doesn't change height.
            Group {
                if isEstimate {
                    Text("\((date ?? .now).shortDay), estimate")
                } else {
                    Text((date ?? .now).shortDay)
                }
            }
            .opacity(date == nil ? 0 : 1)
        } label: {
            Text(value)
                .font(.title2.weight(.bold))
                .monospacedDigit()
                .contentTransition(.numericText())
        }
    }
}

/// A body measurement over the chosen period, already in the unit shown, with the
/// period's buttons under it (see ChartParts.swift for how the charts work).
private struct BodyChart: View {
    let points: [BodyTrend.Point]
    @Binding var range: BodyTrend.Range
    /// The date of the touched point, for the number above the chart.
    @Binding var touched: Date?
    let title: LocalizedStringResource
    let unit: String
    /// Body fat marks every entry: a dot when measured, a band when estimated. Body
    /// weight, often daily, marks only the latest.
    var marksEachPoint = false
    /// Where the finger is, before snapping to the nearest point.
    @State private var finger: Date?
    @ChartHeight(160, maximum: 240) private var chartHeight

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if points.isEmpty {
                Text("Nothing in this period")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 8)
            } else {
                chart
            }
            ChartRangeButtons(range: $range)
        }
        .onChange(of: range) { touched = nil }
        if marksEachPoint, points.contains(where: { $0.estimate != nil }) {
            HStack(spacing: 18) {
                HStack(spacing: 6) {
                    PointSymbol(isEstimate: false)
                    Text("Measured")
                }
                HStack(spacing: 6) {
                    PointSymbol(isEstimate: true)
                        .background { Capsule().fill(Color.chartMark.opacity(0.22)).frame(width: 8, height: 18) }
                    Text("Estimate")
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .accessibilityHidden(true)
        }
    }

    private var chart: some View {
        let name = String(appLocalized: title)
        let touchedIndex = touched.flatMap { date in points.firstIndex { $0.date == date } }
        let cut = touchedIndex ?? points.count - 1
        return Chart {
            ForEach(points, id: \.date) { point in
                if let estimate = point.estimate {
                    RuleMark(x: .value("Date", point.date), yStart: .value(name, estimate.lowerBound), yEnd: .value(name, estimate.upperBound))
                        .lineStyle(StrokeStyle(lineWidth: 8, lineCap: .round))
                        .foregroundStyle(Color.chartMark.opacity(0.18))
                }
            }
            ForEach(Array(points[...cut]), id: \.date) { point in
                LineMark(x: .value("Date", point.date), y: .value(name, point.value), series: .value("Part", "before"))
                    .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                    .foregroundStyle(Color.chartMark)
            }
            ForEach(Array(points[cut...]), id: \.date) { point in
                LineMark(x: .value("Date", point.date), y: .value(name, point.value), series: .value("Part", "after"))
                    .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                    .foregroundStyle(Color.chartMark.opacity(0.25))
            }
            if marksEachPoint {
                ForEach(points, id: \.date) { point in
                    PointMark(x: .value("Date", point.date), y: .value(name, point.value))
                        .symbol { PointSymbol(isEstimate: point.estimate != nil) }
                }
            }
            if let touchedIndex {
                let point = points[touchedIndex]
                RuleMark(x: .value("Date", point.date))
                    .lineStyle(StrokeStyle(lineWidth: 1))
                    .foregroundStyle(Color.secondary.opacity(0.6))
                    .annotation(position: .top, spacing: 6, overflowResolution: .init(x: .fit(to: .chart), y: .disabled)) {
                        ChartDateLabel(date: point.date)
                    }
                PointMark(x: .value("Date", point.date), y: .value(name, point.value))
                    .symbol { ChartTouchDot() }
            } else if !marksEachPoint, let last = points.last {
                PointMark(x: .value("Date", last.date), y: .value(name, last.value))
                    .symbol { PointSymbol(isEstimate: false) }
            }
        }
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .chartYScale(domain: .automatic(includesZero: false))
        .chartXScale(domain: domain, range: .plotDimension(padding: 8))
        .chartXSelection(value: $finger)
        .onChange(of: finger) {
            touched = finger.flatMap { date in points.nearest(to: date, by: \.date)?.date }
        }
        .sensoryFeedback(.selection, trigger: touched)
        .frame(height: chartHeight)
        // Room over the line for the touched point's date.
        .padding(.top, 24)
        .padding(.bottom, 4)
        .accessibilityLabel(Text("\(name) over \(String(appLocalized: range.spoken)), in \(unit)"))
        .accessibilityIdentifier("bodyChart")
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

/// A filled dot for a measured value, a hollow one on a band for an estimate.
private struct PointSymbol: View {
    let isEstimate: Bool

    var body: some View {
        if isEstimate {
            Circle()
                .strokeBorder(Color.chartMark, lineWidth: 2)
                .background(Circle().fill(Color(.secondarySystemGroupedBackground)))
                .frame(width: 9, height: 9)
        } else {
            Circle()
                .fill(Color.chartMark)
                .overlay { Circle().strokeBorder(Color(.secondarySystemGroupedBackground), lineWidth: 2) }
                .frame(width: 11, height: 11)
        }
    }
}

/// Typing in a weight. It is saved to the phone and to Apple Health.
private struct WeightEntryView: View {
    let onSave: (BodyMeasurement) -> Void
    @Environment(LocalStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var value: Double?
    /// What is typed. Read on every keystroke, so Save works without closing the
    /// keyboard first (a formatted field only reads it when editing ends).
    @State private var text = ""
    @State private var date = Date.now
    @FocusState private var isFocused: Bool

    var body: some View {
        let unit = store.weightUnit
        NavigationStack {
            Form {
                LabeledContent("Weight") {
                    HStack(spacing: 4) {
                        TextField("Weight", text: $text)
                            .keyboardType(.decimalPad)
                            .onChange(of: text) { _, typed in
                                value = NumberField.parse(typed, decimals: true).map { unit.rounded($0) }
                            }
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
            .keyboardDoneButton()
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

/// Entering body fat: by default a range picked by eye, or an exact number from a
/// scale or scan. Only exact numbers go to Apple Health.
private struct BodyFatEntryView: View {
    let onSave: (BodyMeasurement) -> Void
    @Environment(\.dismiss) private var dismiss
    /// The last way used, so someone with a scale gets the number field straight away.
    @AppStorage("IronSage.bodyFat.exact") private var isExact = false
    @State private var estimate: ClosedRange<Double>?
    @State private var value: Double?
    /// What is typed. Read on every keystroke, so Save works without closing the
    /// keyboard first (a formatted field only reads it when editing ends).
    @State private var text = ""
    @State private var date = Date.now
    @FocusState private var isFocused: Bool

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("How", selection: $isExact) {
                        Text("Estimate a range").tag(false)
                        Text("Exact number").tag(true)
                    }
                    .pickerStyle(.segmented)
                    .accessibilityIdentifier("bodyFatMode")
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
                }

                if isExact {
                    Section {
                        HStack(alignment: .firstTextBaseline, spacing: 4) {
                            TextField(String("17.8"), text: $text)
                                .keyboardType(.decimalPad)
                                .onChange(of: text) { _, typed in
                                    value = NumberField.parse(typed, decimals: true).map { ($0 * 10).rounded() / 10 }
                                }
                                .multilineTextAlignment(.trailing)
                                .font(.system(size: 44, weight: .bold))
                                .monospacedDigit()
                                .focused($isFocused)
                                .accessibilityLabel("Body fat")
                            Text(verbatim: "%")
                                .font(.title.weight(.semibold))
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                    } footer: {
                        Text("From a body-fat scale, an InBody or a DEXA scan. Saved to Apple Health too.")
                    }
                } else {
                    Section {
                        LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                            ForEach(BodyFat.estimates, id: \.lowerBound) { range in
                                Button(BodyFat.label(range)) { estimate = range }
                                    .buttonStyle(RangeButtonStyle(isSelected: estimate == range))
                            }
                        }
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets())
                    } footer: {
                        Text("Pick the range closest to what you see in the mirror. A range shows as a band on your chart and isn't saved to Apple Health.")
                    }
                }

                DatePicker("Date", selection: $date, in: ...Date.now)
            }
            .brandBackground()
            .navigationTitle("Body fat")
            .keyboardDoneButton()
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        guard let entry else { return }
                        onSave(entry)
                        dismiss()
                    }
                    .disabled(entry == nil)
                }
            }
            .onChange(of: isExact) { isFocused = isExact }
            .onAppear { isFocused = isExact }
        }
        .presentationDetents([.large])
    }

    private var entry: BodyMeasurement? {
        if isExact {
            guard let value, BodyFat.plausible.contains(value) else { return nil }
            return BodyMeasurement(measuredAt: date, kind: .bodyFat, value: value, source: .manual)
        }
        return estimate.map { BodyFat.estimate($0, at: date) }
    }
}

/// One range to pick: a tile that fills with the accent when picked.
private struct RangeButtonStyle: ButtonStyle {
    let isSelected: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.title3.weight(isSelected ? .semibold : .regular))
            .monospacedDigit()
            .foregroundStyle(isSelected ? AnyShapeStyle(.tint) : AnyShapeStyle(.primary))
            .frame(maxWidth: .infinity, minHeight: 56)
            .background(
                isSelected ? AnyShapeStyle(.tint.opacity(0.12)) : AnyShapeStyle(Color(.secondarySystemGroupedBackground)),
                in: .rect(cornerRadius: 12)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(isSelected ? AnyShapeStyle(.tint) : AnyShapeStyle(.clear), lineWidth: 2)
            }
            .opacity(configuration.isPressed ? 0.7 : 1)
            .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

extension BodyFat {
    /// "18.5%"
    static func format(_ percent: Double) -> String {
        (percent / 100).formatted(.percent.precision(.fractionLength(0...1)).locale(AppLanguage.locale))
    }

    /// "18.5%", or an estimate: "About 15–20%", "Under 10%", "40% or more".
    static func format(_ measurement: BodyMeasurement) -> String {
        guard let estimate = measurement.estimate else { return format(measurement.value) }
        if estimate == estimates.first || estimate == estimates.last { return label(estimate) }
        return String(appLocalized: "About \(label(estimate))")
    }

    /// The same for a point on the chart.
    static func format(_ point: BodyTrend.Point) -> String {
        guard let estimate = point.estimate else { return format(point.value) }
        if estimate == estimates.first || estimate == estimates.last { return label(estimate) }
        return String(appLocalized: "About \(label(estimate))")
    }

    /// A range to pick: "15–20%", "Under 10%", "40% or more".
    static func label(_ range: ClosedRange<Double>) -> String {
        if range == estimates.first { return String(appLocalized: "Under \(format(range.upperBound))") }
        if range == estimates.last { return String(appLocalized: "\(format(range.lowerBound)) or more") }
        return "\(Int(range.lowerBound))–\(format(range.upperBound))"
    }

    /// "One range lower than your last estimate"
    static func describe(_ change: Int) -> String {
        switch change {
        case 0: String(appLocalized: "Same range as your last estimate")
        case -1: String(appLocalized: "One range lower than your last estimate")
        case 1: String(appLocalized: "One range higher than your last estimate")
        case ..<0: String(appLocalized: "\(-change) ranges lower than your last estimate")
        default: String(appLocalized: "\(change) ranges higher than your last estimate")
        }
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
                    Text(source(of: measurement))
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(kind == .bodyFat ? BodyFat.format(measurement) : unit.formatWithUnit(kilograms: measurement.value))
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

    private func source(of measurement: BodyMeasurement) -> String {
        if measurement.source == .healthkit { return String(appLocalized: "Apple Health") }
        return measurement.estimate == nil ? String(appLocalized: "Entered") : String(appLocalized: "Estimate")
    }
}

// MARK: Weekly sets

/// Sets per muscle as rows, as in Apple Fitness: the muscle, a bar on a track, and the
/// number, each in its own column so they line up. The track runs to 20 sets, the top
/// of the range most people grow in (or the most sets, when more).
private struct WeeklySetsSection: View {
    @Environment(LocalStore.self) private var store
    @Environment(\.dynamicTypeSize) private var size
    @State private var weeksBack = 0

    var body: some View {
        let calendar = Calendar.current
        let day = calendar.date(byAdding: .weekOfYear, value: -weeksBack, to: .now)!
        let week = calendar.dateInterval(of: .weekOfYear, for: day)!
        let sets = TrainingProgress.weeklySets(in: store.finishedWorkouts, exercises: store.exercises, week: week)
        let reference = TrainingProgress.setsReference
        let scale = max(reference.upperBound, sets.first?.sets ?? 0)
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
            } else if size.isAccessibilitySize {
                // The name gets its own line, so the bar keeps the whole width.
                ForEach(sets, id: \.muscle) { item in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(String(appLocalized: item.muscle.label))
                            Spacer()
                            count(item.sets)
                        }
                        SetsBar(sets: item.sets, scale: scale)
                    }
                    .modifier(MuscleRowAccessibility(muscle: item.muscle, sets: item.sets))
                }
            } else {
                Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 14) {
                    ForEach(sets, id: \.muscle) { item in
                        GridRow {
                            Text(String(appLocalized: item.muscle.label))
                                .lineLimit(1)
                            SetsBar(sets: item.sets, scale: scale)
                            count(item.sets)
                                .gridColumnAlignment(.trailing)
                        }
                        .modifier(MuscleRowAccessibility(muscle: item.muscle, sets: item.sets))
                    }
                }
                .font(.subheadline)
                .padding(.vertical, 4)
            }
        } header: {
            Text("Sets per muscle")
        } footer: {
            Text("A set counts 1 for the main muscles of the exercise and ½ for the ones that help. 10 to 20 sets a week is where most people grow.")
        }
    }

    private func count(_ sets: Double) -> some View {
        Text(sets.formatted(.number.precision(.fractionLength(0...1))))
            .font(.subheadline.weight(.semibold))
            .monospacedDigit()
    }
}

/// One muscle's sets on a track from 0 to `scale`.
private struct SetsBar: View {
    let sets: Double
    let scale: Double

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let x = { (value: Double) in width * min(value, scale) / scale }
            ZStack(alignment: .leading) {
                Capsule().fill(Color.primary.opacity(0.08))
                Capsule()
                    .fill(Color.chartMark)
                    .frame(width: max(x(sets), 8))
            }
            .clipShape(Capsule())
        }
        .frame(height: 10)
        .frame(maxWidth: .infinity)
        .accessibilityHidden(true)
    }
}

/// "Glutes, 5 sets", read as one row.
private struct MuscleRowAccessibility: ViewModifier {
    let muscle: Muscle
    let sets: Double

    func body(content: Content) -> some View {
        content
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(String(appLocalized: muscle.label)))
            .accessibilityValue(Text("\(sets.formatted(.number.precision(.fractionLength(0...1)))) sets"))
    }
}

// MARK: Cardio

/// Minutes of cardio a week against the WHO guideline, and this week's sessions.
private struct CardioProgressSection: View {
    @Environment(LocalStore.self) private var store
    @ChartHeight(160, maximum: 240) private var chartHeight

    var body: some View {
        let weeks = Cardio.weeklyMinutes(in: store.finishedWorkouts, exercises: store.exercises, weeks: 8)
        let reference = Cardio.weeklyMinutesReference
        let thisWeek = weeks.last?.minutes ?? 0
        let start = Calendar.current.dateInterval(of: .weekOfYear, for: .now)?.start ?? .now
        let sessions = Cardio.sessions(in: store.finishedWorkouts, exercises: store.exercises, from: start)
        Section {
            if weeks.allSatisfy({ $0.minutes == 0 }) {
                Text("No cardio yet. Add it to a workout, or record it on your Apple Watch.")
                    .foregroundStyle(.secondary)
            } else {
                AdaptiveRow {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(CardioText.minutes(thisWeek * 60))
                            .font(.title2.weight(.bold))
                            .monospacedDigit()
                        Text("This week so far")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } trailing: {
                    Text(thisWeek < reference.lowerBound ? "Below 150–300 min" : thisWeek > reference.upperBound ? "Above 150–300 min" : "Inside 150–300 min")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Chart {
                    RectangleMark(
                        yStart: .value("Reference low", reference.lowerBound),
                        yEnd: .value("Reference high", reference.upperBound)
                    )
                    .foregroundStyle(Color.primary.opacity(0.06))
                    ForEach(weeks, id: \.start) { week in
                        BarMark(
                            x: .value("Week", week.start, unit: .weekOfYear),
                            y: .value("Minutes", week.minutes),
                            width: .ratio(0.6)
                        )
                        .clipShape(UnevenRoundedRectangle(topLeadingRadius: 4, topTrailingRadius: 4))
                        // This week isn't over yet.
                        .foregroundStyle(Color.chartMark.opacity(week.start == weeks.last?.start ? 0.5 : 1))
                    }
                }
                .chartYScale(domain: 0...max(reference.upperBound + 30, (weeks.map(\.minutes).max() ?? 0) + 20))
                .chartXAxis {
                    AxisMarks(values: .stride(by: .weekOfYear, count: 2)) { _ in
                        AxisValueLabel(format: .dateTime.month(.abbreviated).day(), centered: true)
                    }
                }
                .chartYAxis {
                    AxisMarks(position: .leading, values: [0, 150, 300]) { _ in
                        AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                        AxisValueLabel()
                    }
                }
                .frame(height: chartHeight)
                .chartTextSize()
                .padding(.vertical, 4)
                .accessibilityLabel(Text("Minutes of cardio per week"))
                .accessibilityValue(Text(weeks.map { "\($0.start.shortDay): \(CardioText.minutes($0.minutes * 60))" }.joined(separator: ", ")))

                ForEach(sessions) { session in
                    NavigationLink(value: WorkoutRoute(id: session.workoutID)) {
                        CardioRow(session: session)
                    }
                }
            }
        } header: {
            Text("Cardio")
        } footer: {
            Text("The shaded band is the WHO guideline for adults: 150 to 300 minutes of moderate cardio a week, or half that if it's vigorous. Cardio isn't counted in sets or records.")
        }
    }
}

private struct CardioRow: View {
    let session: Cardio.Session
    @Environment(LocalStore.self) private var store

    var body: some View {
        let exercise = store.exercises[session.exerciseID]
        HStack(spacing: 12) {
            ExerciseThumbnail(exercise: exercise, size: 40)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(store.exerciseName(session.exerciseID))
                    if session.done.healthkitWorkoutId != nil {
                        Label("Apple Watch", systemImage: "applewatch")
                            .font(.caption)
                            .labelStyle(.titleAndIcon)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 1)
                            .background(.quaternary, in: .rect(cornerRadius: 6))
                    }
                }
                Text(detail(exercise))
                    .font(.subheadline)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func detail(_ exercise: Exercise?) -> String {
        let day = session.date.formatted(.dateTime.weekday(.abbreviated).locale(AppLanguage.locale))
        var parts = [day, CardioText.summary(session.done, exercise: exercise, unit: store.weightUnit)]
        if let heart = session.done.avgHeartRate { parts.append(String(appLocalized: "\(heart) bpm avg")) }
        return parts.joined(separator: " · ")
    }
}

// MARK: Exercises

private struct ExercisesSection: View {
    @Environment(LocalStore.self) private var store

    var body: some View {
        let exercises = TrainingProgress.recentExercises(in: store.finishedWorkouts, skipping: store.cardioExerciseIDs)
        if !exercises.isEmpty {
            Section("Exercises") {
                ForEach(exercises, id: \.self) { id in
                    NavigationLink(store.exerciseName(id), value: ExerciseRoute(id: id))
                }
            }
        }
    }
}
