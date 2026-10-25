import IronSageCore
import IronSageStore
import SwiftUI

/// Logging a workout: one section per exercise, one row per set.
struct WorkoutView: View {
    @Bindable var session: WorkoutSession
    @Environment(LocalStore.self) private var store
    @Environment(SyncEngine.self) private var sync
    @Environment(\.dismiss) private var dismiss
    @FocusState private var focus: SetField?
    @State private var isPickingExercise = false
    @State private var isConfirmingFinish = false
    @State private var isConfirmingDiscard = false
    @State private var finished: Workout?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    TextField("Workout name", text: Binding(
                        get: { session.workout.title },
                        set: { title in session.update { $0.title = String(title.prefix(120)) } }
                    ))
                    .font(.title3.weight(.semibold))
                    LabeledContent("Duration") {
                        Text(session.workout.startedAt, style: .timer)
                            .monospacedDigit()
                    }
                }

                ForEach(session.workout.exercises) { item in
                    ExerciseSection(session: session, item: item, focus: $focus)
                }

                Section {
                    Button("Add exercise", systemImage: "plus") {
                        isPickingExercise = true
                    }
                }

                Section {
                    Button("Discard workout", role: .destructive) {
                        isConfirmingDiscard = true
                    }
                }
            }
            .listSectionSpacing(.compact)
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle("Workout")
            .navigationBarTitleDisplayMode(.inline)
            .safeAreaInset(edge: .bottom) {
                if let timer = session.restTimer {
                    RestTimerBar(timer: timer, session: session)
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Hide", systemImage: "chevron.down") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Finish") {
                        focus = nil
                        isConfirmingFinish = true
                    }
                    .disabled(!session.hasCompletedSets)
                }
                ToolbarItemGroup(placement: .keyboard) {
                    if case .weight(let setID, let exerciseID) = focus {
                        Button("Less weight", systemImage: "minus") { stepWeight(setID, in: exerciseID, by: -1) }
                        Button("More weight", systemImage: "plus") { stepWeight(setID, in: exerciseID, by: 1) }
                    }
                    Spacer()
                    Button("Done") { focus = nil }
                }
            }
            .sheet(isPresented: $isPickingExercise) {
                ExercisePickerView { exercise in session.add(exercise) }
            }
            .confirmationDialog("Finish this workout?", isPresented: $isConfirmingFinish, titleVisibility: .visible) {
                Button("Finish workout") {
                    session.finish()
                    finished = session.workout
                    Task { await sync.sync() }
                }
            } message: {
                if session.hasUnfinishedSets {
                    Text("Sets you haven't checked off will be removed.")
                }
            }
            .confirmationDialog("Discard this workout?", isPresented: $isConfirmingDiscard, titleVisibility: .visible) {
                Button("Discard workout", role: .destructive) {
                    session.discard()
                    dismiss()
                }
            } message: {
                Text("Nothing from it will be saved.")
            }
            .sheet(item: $finished, onDismiss: { dismiss() }) { workout in
                WorkoutSummaryView(workout: workout)
            }
        }
    }

    private func stepWeight(_ setID: UUID, in exerciseID: UUID, by steps: Int) {
        guard let e = session.workout.exercises.firstIndex(where: { $0.id == exerciseID }),
              let s = session.workout.exercises[e].sets.firstIndex(where: { $0.id == setID })
        else { return }
        let loadType = store.exercises[session.workout.exercises[e].exerciseId]?.loadType ?? .total
        let current = session.workout.exercises[e].sets[s].weightKg ?? 0
        let next = store.weightUnit.step(kilograms: current, by: steps, loadType: loadType)
        session.update { $0.exercises[e].sets[s].weightKg = next }
    }
}

/// The API's limits; a value beyond them would get the whole workout rejected.
enum Limits {
    static let maxWeightKg = 2000.0
    static let maxReps = 1000
    static let maxRir = 10
}

enum SetField: Hashable {
    case weight(UUID, exercise: UUID)
    case reps(UUID)
    case rir(UUID)
}

private struct ExerciseSection: View {
    let session: WorkoutSession
    let item: WorkoutExercise
    var focus: FocusState<SetField?>.Binding
    @Environment(LocalStore.self) private var store

    var body: some View {
        let unit = store.weightUnit
        let last = WorkoutLog.lastSets(of: item.exerciseId, in: store.finishedWorkouts, excluding: session.workout.id)
        Section {
            SetHeader(unit: unit)
            ForEach(Array(item.sets.enumerated()), id: \.element.id) { index, set in
                SetRow(
                    session: session,
                    exerciseID: item.id,
                    set: set,
                    number: workingNumber(at: index),
                    previous: last.flatMap { index < $0.count ? $0[index] : nil },
                    unit: unit,
                    focus: focus
                )
            }
            .onDelete { offsets in
                session.update { workout in
                    guard let e = workout.exercises.firstIndex(where: { $0.id == item.id }) else { return }
                    workout.exercises[e].sets.remove(atOffsets: offsets)
                }
            }
            Button("Add set", systemImage: "plus") {
                session.addSet(to: item.id)
            }
            .font(.subheadline)
        } header: {
            ExerciseHeader(session: session, item: item)
        }
    }

    /// Working sets are numbered 1, 2, 3; warm-ups and the like show a letter.
    private func workingNumber(at index: Int) -> Int {
        item.sets[...index].filter { $0.setType != .warmup }.count
    }
}

private struct ExerciseHeader: View {
    let session: WorkoutSession
    let item: WorkoutExercise
    @Environment(LocalStore.self) private var store

    private static let restChoices = [30, 45, 60, 75, 90, 120, 150, 180, 240, 300]

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(store.exerciseName(item.exerciseId))
                    .font(.headline)
                    .foregroundStyle(Color.primary)
                    .textCase(nil)
                if let rest = item.restSeconds {
                    Text("Rest \(Duration.clock(TimeInterval(rest)))")
                        .font(.caption)
                        .textCase(nil)
                }
            }
            Spacer()
            Menu {
                Picker("Rest between sets", selection: Binding(
                    get: { item.restSeconds ?? 120 },
                    set: { seconds in update { $0.restSeconds = seconds } }
                )) {
                    ForEach(Self.restChoices, id: \.self) { seconds in
                        Text(Duration.clock(TimeInterval(seconds))).tag(seconds)
                    }
                }
                .pickerStyle(.menu)
                Button("Remove exercise", systemImage: "trash", role: .destructive) {
                    session.update { $0.exercises.removeAll { $0.id == item.id } }
                }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .imageScale(.large)
                    .accessibilityLabel("Exercise options")
            }
        }
    }

    private func update(_ change: (inout WorkoutExercise) -> Void) {
        session.update { workout in
            guard let e = workout.exercises.firstIndex(where: { $0.id == item.id }) else { return }
            change(&workout.exercises[e])
        }
    }
}

private struct SetHeader: View {
    let unit: WeightUnit

    var body: some View {
        HStack(spacing: 8) {
            Text("Set").frame(width: 30)
            Text("Last time").frame(maxWidth: .infinity, alignment: .leading)
            Text(unit.symbol).frame(width: 64)
            Text("Reps").frame(width: 48)
            Text("RIR").frame(width: 40)
            Image(systemName: "checkmark").frame(width: 32)
                .accessibilityLabel("Done")
        }
        .font(.caption.weight(.medium))
        .foregroundStyle(.secondary)
    }
}

private struct SetRow: View {
    let session: WorkoutSession
    let exerciseID: UUID
    let set: WorkoutSet
    let number: Int
    let previous: WorkoutSet?
    let unit: WeightUnit
    var focus: FocusState<SetField?>.Binding

    var body: some View {
        HStack(spacing: 8) {
            Menu {
                Picker("Set type", selection: binding(\.setType, default: .working)) {
                    ForEach(SetType.allCases, id: \.self) { type in
                        Text(type.label).tag(type)
                    }
                }
            } label: {
                Group {
                    if let badge = set.setType.badge {
                        Text(badge)
                    } else {
                        Text(number, format: .number)
                    }
                }
                .font(.subheadline.weight(.semibold))
                .frame(width: 30, height: 30)
                .background(.quaternary, in: .rect(cornerRadius: 6))
            }
            .accessibilityLabel(Text(set.setType.label))

            Text(previousText)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(maxWidth: .infinity, alignment: .leading)

            NumberField(
                placeholder: previous?.weightKg.map { unit.format(kilograms: $0) } ?? "–",
                value: Binding(
                    get: { set.weightKg.map { unit.rounded(unit.value(fromKilograms: $0)) } },
                    set: { value in update { $0.weightKg = value.map { min(unit.kilograms(from: $0), Limits.maxWeightKg) } } }
                ),
                decimals: true
            )
            .focused(focus, equals: .weight(set.id, exercise: exerciseID))
            .frame(width: 64)
            .accessibilityLabel(Text("Weight"))

            NumberField(
                placeholder: previous?.reps.map(String.init) ?? "–",
                value: intBinding(\.reps, max: Limits.maxReps),
                decimals: false
            )
            .focused(focus, equals: .reps(set.id))
            .frame(width: 48)
            .accessibilityLabel(Text("Reps"))

            NumberField(placeholder: "–", value: intBinding(\.rir, max: Limits.maxRir), decimals: false)
                .focused(focus, equals: .rir(set.id))
                .frame(width: 40)
                .accessibilityLabel(Text("Reps in reserve"))

            Button {
                if !set.isCompleted {
                    fillFromPrevious()
                }
                session.toggleCompleted(setID: set.id, in: exerciseID)
            } label: {
                Image(systemName: set.isCompleted ? "checkmark.circle.fill" : "circle")
                    .font(.title2)
                    .foregroundStyle(set.isCompleted ? Color.accentColor : .secondary)
            }
            .buttonStyle(.plain)
            .frame(width: 32)
            .accessibilityLabel(set.isCompleted ? Text("Mark not done") : Text("Mark done"))
            .sensoryFeedback(.success, trigger: set.isCompleted) { _, done in done }
        }
        .listRowBackground(set.isCompleted ? Color.accentColor.opacity(0.08) : nil)
    }

    private var previousText: String {
        guard let previous, let reps = previous.reps else { return "–" }
        if let weight = previous.weightKg, weight > 0 {
            return "\(unit.format(kilograms: weight)) × \(reps)"
        }
        return "× \(reps)"
    }

    /// Checking off an untouched set means "same as the placeholder": last time's numbers.
    private func fillFromPrevious() {
        guard let previous else { return }
        update { set in
            if set.weightKg == nil { set.weightKg = previous.weightKg }
            if set.reps == nil { set.reps = previous.reps }
        }
    }

    private func update(_ change: (inout WorkoutSet) -> Void) {
        session.update { workout in
            guard let e = workout.exercises.firstIndex(where: { $0.id == exerciseID }),
                  let s = workout.exercises[e].sets.firstIndex(where: { $0.id == set.id })
            else { return }
            change(&workout.exercises[e].sets[s])
        }
    }

    private func binding<Value>(_ keyPath: WritableKeyPath<WorkoutSet, Value>, default value: Value) -> Binding<Value> {
        Binding(get: { set[keyPath: keyPath] }, set: { newValue in update { $0[keyPath: keyPath] = newValue } })
    }

    private func intBinding(_ keyPath: WritableKeyPath<WorkoutSet, Int?>, max upper: Int) -> Binding<Double?> {
        Binding(
            get: { set[keyPath: keyPath].map(Double.init) },
            set: { value in update { $0[keyPath: keyPath] = value.map { Int(min($0, Double(upper))) } } }
        )
    }
}

/// A number field that updates its value on every keystroke, so a value typed just
/// before tapping the checkmark is never lost.
struct NumberField: View {
    let placeholder: String
    @Binding var value: Double?
    let decimals: Bool
    @State private var text = ""

    var body: some View {
        TextField(placeholder, text: $text)
            .keyboardType(decimals ? .decimalPad : .numberPad)
            .multilineTextAlignment(.center)
            .font(.body.monospacedDigit())
            .padding(.vertical, 6)
            .background(.quaternary.opacity(0.6), in: .rect(cornerRadius: 6))
            .onAppear { text = Self.format(value) }
            .onChange(of: text) { _, newText in
                let parsed = Self.parse(newText, decimals: decimals)
                if parsed != value {
                    value = parsed
                }
            }
            .onChange(of: value) { _, newValue in
                if Self.parse(text, decimals: decimals) != newValue {
                    text = Self.format(newValue)
                }
            }
    }

    static func parse(_ text: String, decimals: Bool) -> Double? {
        let normalized = text.replacingOccurrences(of: ",", with: ".").trimmingCharacters(in: .whitespaces)
        guard let number = Double(normalized), number >= 0 else { return nil }
        return decimals ? number : number.rounded(.down)
    }

    static func format(_ value: Double?) -> String {
        guard let value else { return "" }
        return value.formatted(.number.precision(.fractionLength(0...2)).grouping(.never))
    }
}

private struct RestTimerBar: View {
    let timer: RestTimer
    let session: WorkoutSession

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let remaining = timer.remaining(at: context.date)
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(remaining > 0 ? "Rest" : "Rest is over")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text(Duration.clock(remaining))
                        .font(.title2.monospacedDigit().weight(.semibold))
                        .contentTransition(.numericText(countsDown: true))
                }
                Spacer()
                Button("−15 s") { session.extendRest(by: -15) }
                    .accessibilityLabel("15 seconds less")
                Button("+15 s") { session.extendRest(by: 15) }
                    .accessibilityLabel("15 seconds more")
                Button(remaining > 0 ? "Skip" : "Close") { session.skipRest() }
                    .buttonStyle(.borderedProminent)
            }
            .buttonStyle(.bordered)
            .padding(.horizontal)
            .padding(.vertical, 10)
            .background(.bar)
            .overlay(alignment: .top) {
                GeometryReader { proxy in
                    let total = max(1, Double(timer.totalSeconds))
                    Rectangle()
                        .fill(Color.accentColor)
                        .frame(width: proxy.size.width * (1 - remaining / total), height: 3)
                }
                .frame(height: 3)
            }
            .sensoryFeedback(.warning, trigger: remaining <= 0)
        }
    }
}
