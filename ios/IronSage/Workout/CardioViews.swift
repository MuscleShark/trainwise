import IronSageCore
import IronSageStore
import SwiftUI

/// Cardio in a workout: one card with the time and the machine's numbers. What the Watch
/// recorded is shown as it is; cardio logged here can be changed until it's done.
struct CardioSection: View {
    let session: WorkoutSession
    let item: WorkoutExercise
    let showInfo: (Exercise) -> Void
    @Environment(LocalStore.self) private var store
    @Environment(HealthService.self) private var health

    var body: some View {
        let exercise = store.exercises[item.exerciseId]
        let unit = store.weightUnit
        Section {
            ForEach(item.sets) { set in
                if set.healthkitWorkoutId != nil {
                    RecordedCardio(set: set, exercise: exercise, unit: unit)
                } else {
                    CardioFields(session: session, exerciseID: item.id, set: set, exercise: exercise, unit: unit)
                }
            }
        } header: {
            HStack(spacing: 12) {
                ExerciseThumbnail(exercise: exercise, size: 44, background: Color(.secondarySystemGroupedBackground))
                VStack(alignment: .leading, spacing: 2) {
                    Text(store.exerciseName(item.exerciseId))
                        .font(.headline)
                        .foregroundStyle(Color.primary)
                    Text(caption(exercise: exercise, unit: unit))
                        .font(.caption)
                }
                .textCase(nil)
                Spacer()
                if let exercise {
                    Button {
                        showInfo(exercise)
                    } label: {
                        IconCircle(systemName: "info")
                    }
                    .buttonStyle(.borderless)
                    .accessibilityLabel(Text("How to do \(exercise.name(chinese: AppLanguage.isChinese))"))
                }
                Menu {
                    Button("Remove", systemImage: "trash", role: .destructive) {
                        // A Watch workout taken out of the workout isn't imported again.
                        for id in item.sets.compactMap(\.healthkitWorkoutId) { health.forgetWatchWorkout(id) }
                        session.update { $0.exercises.removeAll { $0.id == item.id } }
                    }
                } label: {
                    IconCircle(systemName: "ellipsis")
                        .accessibilityLabel("Exercise options")
                }
            }
        }
    }

    private func caption(exercise: Exercise?, unit: WeightUnit) -> String {
        if let recorded = item.sets.first(where: { $0.healthkitWorkoutId != nil }), let end = recorded.completedAt {
            let start = end.addingTimeInterval(-TimeInterval(recorded.durationSeconds ?? 0))
            let span = (start..<end).formatted(.interval.hour().minute().locale(AppLanguage.locale))
            return String(appLocalized: "Apple Watch · \(span)")
        }
        let last = WorkoutLog.lastSets(of: item.exerciseId, in: store.finishedWorkouts, before: session.workout.startedAt)?.last
        guard let last else { return String(appLocalized: "First time: log what you did.") }
        return String(appLocalized: "Last time: \(CardioText.summary(last, exercise: exercise, unit: unit))")
    }
}

/// Time, distance, heart rate and energy the Watch recorded.
private struct RecordedCardio: View {
    let set: WorkoutSet
    let exercise: Exercise?
    let unit: WeightUnit

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(CardioText.summary(set, exercise: exercise, unit: unit))
                .font(.body.monospacedDigit().weight(.semibold))
            if set.avgHeartRate != nil || set.energyKcal != nil {
                HStack(spacing: 14) {
                    if let heart = set.avgHeartRate {
                        Label(String(appLocalized: "\(heart) bpm avg"), systemImage: "heart.fill")
                    }
                    if let energy = set.energyKcal {
                        Label(String(appLocalized: "\(energy) kcal"), systemImage: "flame.fill")
                    }
                }
                .font(.subheadline.monospacedDigit())
                .foregroundStyle(.secondary)
                .labelStyle(TintedIconLabelStyle())
            }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }
}

private struct TintedIconLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 4) {
            configuration.icon.foregroundStyle(.tint).imageScale(.small)
            configuration.title
        }
    }
}

/// Cardio logged in the app: time and the machine's numbers, then Done.
private struct CardioFields: View {
    let session: WorkoutSession
    let exerciseID: UUID
    let set: WorkoutSet
    let exercise: Exercise?
    let unit: WeightUnit

    private let columns = [GridItem(.adaptive(minimum: 76), spacing: 8)]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            LazyVGrid(columns: columns, alignment: .leading, spacing: 8) {
                CardioNumberField(title: "Minutes", value: minutes, decimals: true)
                ForEach(metrics, id: \.self) { metric in
                    field(metric)
                }
            }
            HStack {
                if !set.isCompleted {
                    Label("Heart rate is added from Apple Watch when you finish.", systemImage: "heart")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    session.toggleCompleted(setID: set.id, in: exerciseID)
                } label: {
                    Text(set.isCompleted ? "Done" : "Mark done")
                        .font(.subheadline.weight(.semibold))
                }
                .buttonStyle(.borderedProminent)
                .tint(set.isCompleted ? Color.secondary : Color.accentColor)
                .disabled((set.durationSeconds ?? 0) <= 0)
                .accessibilityLabel(set.isCompleted ? Text("Mark not done") : Text("Mark done"))
            }
        }
        .padding(.vertical, 4)
        .listRowBackground(set.isCompleted ? Color.accentColor.opacity(0.08) : nil)
    }

    /// What the exercise logs besides time; a custom one without a list gets distance.
    private var metrics: [CardioMetric] {
        exercise?.cardioMetrics.isEmpty == false ? exercise!.cardioMetrics : [.distance]
    }

    @ViewBuilder private func field(_ metric: CardioMetric) -> some View {
        switch metric {
        case .incline:
            CardioNumberField(title: "Incline", unit: "%", value: Binding(
                get: { set.inclinePct },
                set: { value in update { $0.inclinePct = value.map { CardioUnits.incline(min(max($0, -10), 40)) } } }
            ), decimals: true)
        case .speed:
            CardioNumberField(title: "Speed", unit: CardioText.speedUnit(unit), value: Binding(
                get: { set.speedKmh.map { (CardioUnits.speed(fromKmh: $0, unit: unit) * 10).rounded() / 10 } },
                set: { value in update { $0.speedKmh = value.map { min(CardioUnits.kmh(fromSpeed: $0, unit: unit), 60) } } }
            ), decimals: true)
        case .distance:
            let meters = exercise?.distanceInMeters == true
            CardioNumberField(title: "Distance", unit: CardioText.distanceUnit(unit, meters: meters), value: Binding(
                get: { set.distanceM.map { meters ? $0.rounded() : (CardioUnits.distance(fromMeters: $0, unit: unit) * 100).rounded() / 100 } },
                set: { value in update { $0.distanceM = value.map { min(meters ? $0.rounded() : CardioUnits.meters(fromDistance: $0, unit: unit), 1_000_000) } } }
            ), decimals: !meters)
        case .floors:
            CardioNumberField(title: metric.label, value: Binding(
                get: { set.floors.map(Double.init) },
                set: { value in update { $0.floors = value.map { Int(min($0, 10_000)) } } }
            ), decimals: false)
        case .level, .resistance, .damper:
            CardioNumberField(title: metric.label, value: Binding(
                get: { set.level.map(Double.init) },
                set: { value in update { $0.level = value.map { Int(min($0, 100)) } } }
            ), decimals: false)
        }
    }

    private var minutes: Binding<Double?> {
        Binding(
            get: { set.durationSeconds.map { (Double($0) / 60 * 10).rounded() / 10 } },
            set: { value in update { $0.durationSeconds = value.map { Int((min($0, 1440) * 60).rounded()) } } }
        )
    }

    private func update(_ change: (inout WorkoutSet) -> Void) {
        session.update { workout in
            guard let e = workout.exercises.firstIndex(where: { $0.id == exerciseID }),
                  let s = workout.exercises[e].sets.firstIndex(where: { $0.id == set.id })
            else { return }
            change(&workout.exercises[e].sets[s])
        }
    }
}

/// A labeled number field for cardio.
struct CardioNumberField: View {
    let title: LocalizedStringResource
    /// "%", "mph", "km": the same in every language.
    var unit: String?
    @Binding var value: Double?
    let decimals: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            CardioFieldTitle(title: title, unit: unit)
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
            NumberField(placeholder: "–", value: $value, decimals: decimals)
                .accessibilityLabel(Text(title))
        }
    }
}

/// "Speed (mph)".
struct CardioFieldTitle: View {
    let title: LocalizedStringResource
    var unit: String?

    var body: some View {
        if let unit {
            Text(title) + Text(verbatim: " (\(unit))")
        } else {
            Text(title)
        }
    }
}

/// Adding cardio to a workout: first what the Watch recorded today, then any machine
/// to log by hand.
struct CardioAddView: View {
    let session: WorkoutSession
    @Environment(LocalStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var logging: Exercise?

    var body: some View {
        NavigationStack {
            List {
                let recorded = store.watchCardio(on: session.workout.startedAt)
                let added = session.workout.exercises.filter { $0.sets.contains { $0.healthkitWorkoutId != nil } }
                Section {
                    if recorded.isEmpty && added.isEmpty {
                        Text("Nothing from Apple Watch today. Cardio you record on your Watch shows up here.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    ForEach(added) { item in
                        watchRow(item, isAdded: true) {}
                    }
                    ForEach(recorded) { workout in
                        ForEach(workout.exercises) { item in
                            watchRow(item, isAdded: false) {
                                session.absorb(workout)
                            }
                        }
                    }
                } header: {
                    Text("From Apple Watch today")
                } footer: {
                    Text("Anything your Watch records during this workout is added for you.")
                }

                Section("Log it yourself") {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 96), spacing: 8)], spacing: 8) {
                        ForEach(machines) { exercise in
                            Button {
                                logging = exercise
                            } label: {
                                VStack(spacing: 6) {
                                    ExerciseThumbnail(exercise: exercise, size: 72, background: .appBackground)
                                    Text(exercise.name(chinese: AppLanguage.isChinese))
                                        .font(.caption.weight(.semibold))
                                        .multilineTextAlignment(.center)
                                        .foregroundStyle(Color.primary)
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 8)
                            }
                            .buttonStyle(.borderless)
                            .accessibilityIdentifier("cardio-\(exercise.nameEn)")
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
            .brandBackground()
            .navigationTitle("Add cardio")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .navigationDestination(item: $logging) { exercise in
                CardioLogView(exercise: exercise, session: session) { dismiss() }
            }
        }
    }

    /// Cardio exercises to log by hand: machines first, as the catalog lists them.
    private var machines: [Exercise] {
        store.availableExercises.filter(\.isCardio).sorted { ($0.equipment == .machine ? 0 : 1) < ($1.equipment == .machine ? 0 : 1) }
    }

    private func watchRow(_ item: WorkoutExercise, isAdded: Bool, add: @escaping () -> Void) -> some View {
        let exercise = store.exercises[item.exerciseId]
        return HStack(spacing: 12) {
            ExerciseThumbnail(exercise: exercise, size: 44, background: .appBackground)
            VStack(alignment: .leading, spacing: 2) {
                Text(store.exerciseName(item.exerciseId))
                Text(item.sets.map { CardioText.summary($0, exercise: exercise, unit: store.weightUnit) }.joined(separator: ", "))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if isAdded {
                Label("Added", systemImage: "checkmark")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                Button("Add", action: add)
                    .buttonStyle(.bordered)
                    .accessibilityLabel(Text("Add \(store.exerciseName(item.exerciseId))"))
            }
        }
    }
}

/// Logging one machine by hand: its moving figure, last time, and its numbers.
private struct CardioLogView: View {
    let exercise: Exercise
    let session: WorkoutSession
    let onAdd: () -> Void
    @Environment(LocalStore.self) private var store
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var set = WorkoutSet()

    var body: some View {
        let unit = store.weightUnit
        let last = WorkoutLog.lastSets(of: exercise.id, in: store.finishedWorkouts, before: session.workout.startedAt)?.last
        Form {
            if let movement = ExerciseVisuals.movement(for: exercise) {
                Section {
                    AnimatedFigureView(movement: movement, equipment: exercise.equipment, isPlaying: !reduceMotion, background: Color(.secondarySystemGroupedBackground))
                        .frame(height: 180)
                        .frame(maxWidth: .infinity)
                } footer: {
                    if let last {
                        Text("Last time: \(CardioText.summary(last, exercise: exercise, unit: unit))")
                    } else {
                        Text("First time: log what you did.")
                    }
                }
            }
            Section {
                row("Minutes", unit: nil, value: Binding(
                    get: { set.durationSeconds.map { Double($0) / 60 } },
                    set: { set.durationSeconds = $0.map { Int((min($0, 1440) * 60).rounded()) } }
                ), placeholder: last?.durationSeconds.map { (Double($0) / 60).formatted() })
                ForEach(exercise.cardioMetrics.isEmpty ? [.distance] : exercise.cardioMetrics, id: \.self) { metric in
                    metricRow(metric, unit: unit, last: last)
                }
            } footer: {
                Text("Only time is needed. The rest helps you compare sessions. Heart rate comes from Apple Watch if you wear it.")
            }
        }
        .brandBackground()
        .navigationTitle(exercise.name(chinese: AppLanguage.isChinese))
        .navigationBarTitleDisplayMode(.inline)
        .keyboardDoneButton()
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Add") {
                    session.addCardio(exercise, set: set)
                    onAdd()
                }
                .disabled((set.durationSeconds ?? 0) <= 0)
            }
        }
        .onAppear {
            // Starts from last time's settings; the distance is new each time.
            guard set.durationSeconds == nil, let last else { return }
            set = WorkoutSet(durationSeconds: last.durationSeconds, speedKmh: last.speedKmh, inclinePct: last.inclinePct, level: last.level)
        }
    }

    @ViewBuilder private func metricRow(_ metric: CardioMetric, unit: WeightUnit, last: WorkoutSet?) -> some View {
        switch metric {
        case .incline:
            row("Incline", unit: "%", value: Binding(
                get: { set.inclinePct },
                set: { set.inclinePct = $0.map { CardioUnits.incline(min(max($0, -10), 40)) } }
            ), placeholder: nil)
        case .speed:
            row("Speed", unit: CardioText.speedUnit(unit), value: Binding(
                get: { set.speedKmh.map { (CardioUnits.speed(fromKmh: $0, unit: unit) * 10).rounded() / 10 } },
                set: { set.speedKmh = $0.map { min(CardioUnits.kmh(fromSpeed: $0, unit: unit), 60) } }
            ), placeholder: nil)
        case .distance:
            let meters = exercise.distanceInMeters
            row("Distance", unit: CardioText.distanceUnit(unit, meters: meters), value: Binding(
                get: { set.distanceM.map { meters ? $0.rounded() : (CardioUnits.distance(fromMeters: $0, unit: unit) * 100).rounded() / 100 } },
                set: { set.distanceM = $0.map { min(meters ? $0.rounded() : CardioUnits.meters(fromDistance: $0, unit: unit), 1_000_000) } }
            ), placeholder: String(appLocalized: "Optional"))
        case .floors:
            row(metric.label, unit: nil, value: Binding(
                get: { set.floors.map(Double.init) },
                set: { set.floors = $0.map { Int(min($0, 10_000)) } }
            ), placeholder: String(appLocalized: "Optional"), decimals: false)
        case .level, .resistance, .damper:
            row(metric.label, unit: nil, value: Binding(
                get: { set.level.map(Double.init) },
                set: { set.level = $0.map { Int(min($0, 100)) } }
            ), placeholder: nil, decimals: false)
        }
    }

    private func row(_ title: LocalizedStringResource, unit: String?, value: Binding<Double?>, placeholder: String?, decimals: Bool = true) -> some View {
        LabeledContent {
            NumberField(placeholder: placeholder ?? "–", value: value, decimals: decimals)
                .frame(width: 110)
                .accessibilityLabel(Text(title))
        } label: {
            CardioFieldTitle(title: title, unit: unit)
        }
    }
}
