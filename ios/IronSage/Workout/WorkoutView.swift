import IronSageCore
import IronSageStore
import SwiftUI
import UIKit

/// Logging a workout: one section per exercise, one row per set.
struct WorkoutView: View {
    @Bindable var session: WorkoutSession
    @Environment(LocalStore.self) private var store
    @Environment(SyncEngine.self) private var sync
    @Environment(HealthService.self) private var health
    @Environment(CoachService.self) private var coach
    @Environment(\.dismiss) private var dismiss
    @FocusState private var focus: SetField?
    @State private var isPickingExercise = false
    @State private var isAddingCardio = false
    @State private var isConfirmingFinish = false
    @State private var isConfirmingDiscard = false
    @State private var finished: Workout?
    @State private var info: Exercise?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    TextField("Workout name", text: Binding(
                        get: { session.workout.title },
                        set: { title in session.update { $0.title = String(title.prefix(120)) } }
                    ))
                    .font(.title3.weight(.semibold))
                    if session.isEditing {
                        LabeledContent("Date") {
                            Text(session.workout.startedAt, format: .dateTime.weekday().month().day().hour().minute())
                        }
                    } else {
                        LabeledContent("Duration") {
                            Text(session.workout.startedAt, style: .timer)
                                .monospacedDigit()
                        }
                    }
                }

                ForEach(session.workout.exercises) { item in
                    if store.exercises[item.exerciseId]?.isCardio == true {
                        CardioSection(session: session, item: item) { info = $0 }
                    } else {
                        ExerciseSection(session: session, item: item, focus: $focus) { info = $0 }
                    }
                }

                Section {
                    Button("Add exercise", systemImage: "plus") {
                        isPickingExercise = true
                    }
                    Button("Add cardio", systemImage: "figure.stair.stepper") {
                        isAddingCardio = true
                    }
                }

                if !session.isEditing {
                    Section {
                        Button("Discard workout", role: .destructive) {
                            isConfirmingDiscard = true
                        }
                    }
                }
            }
            .brandBackground()
            .listSectionSpacing(.compact)
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle(session.isEditing ? "Edit workout" : "Workout")
            .navigationBarTitleDisplayMode(.inline)
            .safeAreaInset(edge: .bottom) {
                if let timer = session.restTimer {
                    RestTimerBar(timer: timer, session: session)
                        .modifier(ClearWhileTyping())
                }
            }
            .toolbar {
                if session.isEditing {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") {
                            session.revertEdits()
                            dismiss()
                        }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Save") {
                            focus = nil
                            session.saveEdits()
                            Task { await sync.sync() }
                            dismiss()
                        }
                    }
                } else {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("Hide", systemImage: "chevron.down") { dismiss() }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Finish") {
                            focus = nil
                            isConfirmingFinish = true
                        }
                        .buttonStyle(.borderedProminent)
                        .foregroundStyle(Color.brandOnAccent)
                        .disabled(!session.hasCompletedSets)
                    }
                }
                // A number pad has no return key: Next goes weight, reps, the next set's
                // weight, as in other workout loggers, and Done closes the keyboard
                // (cardio's fields too, which aren't in `focus`).
                ToolbarItemGroup(placement: .keyboard) {
                    if case .weight(let setID, let exerciseID) = focus {
                        Button("Less weight", systemImage: "minus") { stepWeight(setID, in: exerciseID, by: -1) }
                        Button("More weight", systemImage: "plus") { stepWeight(setID, in: exerciseID, by: 1) }
                    }
                    Spacer()
                    if let next = nextField(after: focus) {
                        Button("Next") { focus = next }
                    }
                    Button("Done") {
                        focus = nil
                        Keyboard.dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
            .sheet(isPresented: $isPickingExercise) {
                ExercisePickerView { exercise in session.add(exercise) }
            }
            .sheet(isPresented: $isAddingCardio) {
                CardioAddView(session: session)
            }
            .confirmationDialog("Finish this workout?", isPresented: $isConfirmingFinish, titleVisibility: .visible) {
                Button("Finish workout") {
                    session.finish()
                    finished = session.workout
                    let workout = session.workout
                    Task {
                        await health.saveToHealth(workout)
                        await sync.sync()
                        // The next session's plan just changed.
                        await coach.refresh()
                    }
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
            .sheet(item: $info) { exercise in
                ExerciseInfoView(exercise: exercise)
            }
        }
    }

    /// The field after this one: a set's reps after its weight, then the next set's
    /// weight in the same exercise. None after the last set.
    private func nextField(after field: SetField?) -> SetField? {
        switch field {
        case .weight(let setID, _):
            return .reps(setID)
        case .reps(let setID):
            guard let item = session.workout.exercises.first(where: { $0.sets.contains { $0.id == setID } }),
                  let index = item.sets.firstIndex(where: { $0.id == setID }),
                  index + 1 < item.sets.count
            else { return nil }
            return .weight(item.sets[index + 1].id, exercise: item.id)
        case nil:
            return nil
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
}

enum SetField: Hashable {
    case weight(UUID, exercise: UUID)
    case reps(UUID)
}

private struct ExerciseSection: View {
    let session: WorkoutSession
    let item: WorkoutExercise
    var focus: FocusState<SetField?>.Binding
    let showInfo: (Exercise) -> Void
    @Environment(LocalStore.self) private var store

    var body: some View {
        let unit = store.weightUnit
        let last = WorkoutLog.lastSets(of: item.exerciseId, in: store.finishedWorkouts, before: session.workout.startedAt)
        Section {
            if session.doneExerciseIDs.contains(item.id) && !session.isEditing {
                DoneExerciseRow(item: item, unit: unit) {
                    withAnimation { session.setDone(false, exerciseID: item.id) }
                }
            } else {
                sets(unit: unit, last: last)
            }
        } header: {
            ExerciseHeader(session: session, item: item, showInfo: showInfo)
        }
    }

    @ViewBuilder private func sets(unit: WeightUnit, last: [WorkoutSet]?) -> some View {
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
        // Once a set is checked off: fold this exercise and go on to the next.
        // Sets left unchecked stay, and Finish removes them as before.
        if !session.isEditing && item.sets.contains(where: \.isCompleted) {
            Button("Done with this exercise", systemImage: "checkmark.circle") {
                focus.wrappedValue = nil
                Keyboard.dismiss()
                withAnimation { session.setDone(true, exerciseID: item.id) }
            }
            .font(.subheadline)
            .accessibilityIdentifier("exerciseDone")
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
    let showInfo: (Exercise) -> Void
    @Environment(LocalStore.self) private var store
    @Environment(CoachService.self) private var coach
    @Environment(\.dynamicTypeSize) private var size

    private static let restChoices = [30, 45, 60, 75, 90, 120, 150, 180, 240, 300]

    var body: some View {
        // At the accessibility text sizes the picture and buttons go above the name, so
        // the name and the notes get the whole width.
        if size.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    thumbnail
                    Spacer()
                    buttons
                }
                details
            }
        } else {
            HStack {
                thumbnail
                details
                Spacer()
                buttons
            }
        }
    }

    private var thumbnail: some View {
        ExerciseThumbnail(exercise: store.exercises[item.exerciseId], size: 44, background: Color(.secondarySystemGroupedBackground))
    }

    private var details: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(store.exerciseName(item.exerciseId))
                .font(.headline)
                .foregroundStyle(Color.primary)
                .textCase(nil)
            Group {
                if let templateItem {
                    Text("Target \(TemplateTarget(item: templateItem, exercise: store.exercises[item.exerciseId], unit: store.weightUnit).summary)")
                }
                if let rest = item.restSeconds {
                    Text("Rest \(Duration.clock(TimeInterval(rest)))")
                }
                if let coachAdvice {
                    Label(coachAdvice.reason, systemImage: "sparkles")
                        .padding(.top, 2)
                        .accessibilityLabel(Text("AI coach: \(coachAdvice.reason)"))
                } else if let suggestion {
                    Label(suggestion.reason(unit: store.weightUnit), systemImage: suggestion.systemImage)
                        .padding(.top, 2)
                }
                if let suggestion {
                    if suggestion.isStalled {
                        Label(NextSession.Suggestion.stallNote, systemImage: "exclamationmark.circle")
                    }
                }
            }
            .font(.caption)
            .textCase(nil)
        }
    }

    @ViewBuilder private var buttons: some View {
        if let exercise = store.exercises[item.exerciseId] {
            Button {
                showInfo(exercise)
            } label: {
                IconCircle(systemName: "info")
            }
            .buttonStyle(.borderless)
            .accessibilityLabel(Text("How to do \(exercise.name(chinese: AppLanguage.isChinese))"))
        }
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
            IconCircle(systemName: "ellipsis")
                .accessibilityLabel("Exercise options")
        }
    }

    private func update(_ change: (inout WorkoutExercise) -> Void) {
        session.update { workout in
            guard let e = workout.exercises.firstIndex(where: { $0.id == item.id }) else { return }
            change(&workout.exercises[e])
        }
    }

    /// The template's sets and reps for this exercise, when the workout follows a
    /// template day that has it.
    private var templateItem: TemplateExercise? {
        guard let templateID = session.workout.templateId,
              let day = store.templates.first(where: { $0.id == templateID })?.day(of: session.workout)
        else { return nil }
        return day.exercises.first { $0.exerciseId == item.exerciseId }
    }

    private var suggestion: NextSession.Suggestion? {
        session.suggestion(for: item, template: templateItem)
    }

    /// The AI coach's reason, when this workout's sets started from its advice.
    private var coachAdvice: CoachAdvice.Exercise? {
        guard !session.isEditing, templateItem != nil else { return nil }
        return coach.appliedAdvice(for: session.workout.id)?.advice(for: item.exerciseId)
    }
}

/// An exercise marked done, in one row: the sets checked off and the best one. A tap
/// shows the sets again.
private struct DoneExerciseRow: View {
    let item: WorkoutExercise
    let unit: WeightUnit
    let open: () -> Void

    var body: some View {
        let done = item.sets.filter(\.isCompleted)
        Button(action: open) {
            HStack(spacing: 10) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.title3)
                    .foregroundStyle(Color.accentColor)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(done.count) of \(item.sets.count) sets")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.primary)
                    if let best = best(of: done) {
                        Text("Best \(best)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 8)
                Text("Show sets")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Image(systemName: "chevron.down")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
            }
            .frame(minHeight: 44)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("showSets")
    }

    /// The heaviest working set (the most reps at that weight), as "100 kg × 5".
    private func best(of sets: [WorkoutSet]) -> String? {
        let working = sets.filter { $0.setType != .warmup }
        guard let top = (working.isEmpty ? sets : working).max(by: { ($0.weightKg ?? 0, $0.reps ?? 0) < ($1.weightKg ?? 0, $1.reps ?? 0) }),
              let reps = top.reps
        else { return nil }
        if let weight = top.weightKg, weight > 0 {
            return "\(unit.format(kilograms: weight)) × \(reps)"
        }
        return "× \(reps)"
    }
}

/// The column titles above the sets. Not shown from the XXXL text size up, where each
/// set labels its own fields.
private struct SetHeader: View {
    let unit: WeightUnit
    @Environment(\.dynamicTypeSize) private var size
    @ScaledMetric(relativeTo: .body) private var weightWidth: CGFloat = 68
    @ScaledMetric(relativeTo: .body) private var repsWidth: CGFloat = 52

    var body: some View {
        if size < SetRow.stackedFrom {
            HStack(spacing: 8) {
                Text("Set").frame(width: 30)
                Text("Last time").frame(maxWidth: .infinity, alignment: .leading)
                Text(unit.symbol).frame(width: weightWidth)
                Text("Reps").frame(width: repsWidth)
                Image(systemName: "checkmark").frame(width: 44)
                    .accessibilityLabel("Done")
            }
            .font(.caption.weight(.medium))
            .foregroundStyle(.secondary)
        }
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
    @Environment(\.dynamicTypeSize) private var size
    /// The weight field grows with the text, so "220.5" still fits.
    @ScaledMetric(relativeTo: .body) private var weightWidth: CGFloat = 68
    @ScaledMetric(relativeTo: .body) private var repsWidth: CGFloat = 52
    @ScaledMetric(relativeTo: .subheadline) private var badgeSide: CGFloat = 30

    /// From this text size a set takes two lines: what it is and last time, then the
    /// fields, each with its own label.
    static let stackedFrom = DynamicTypeSize.xxxLarge

    var body: some View {
        Group {
            if size >= Self.stackedFrom {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        typeMenu
                        Text("Last time: \(previousText)")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    // Reps are a few digits at most; the weight gets the rest.
                    HStack(alignment: .bottom, spacing: 8) {
                        labeled(Text(unit.symbol)) { weightField }
                        labeled(Text("Reps")) { repsField }
                            .frame(width: 64)
                        doneButton
                    }
                    // Two numbers and a button fit on one line up to this size; the
                    // rest of the screen keeps growing.
                    .dynamicTypeSize(...DynamicTypeSize.accessibility2)
                }
            } else {
                HStack(spacing: 8) {
                    typeMenu
                    Text(previousText)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    weightField.frame(width: weightWidth)
                    repsField.frame(width: repsWidth)
                    doneButton
                }
            }
        }
        .listRowBackground(set.isCompleted ? Color.accentColor.opacity(0.08) : nil)
    }

    private func labeled(_ label: Text, @ViewBuilder field: () -> some View) -> some View {
        VStack(spacing: 2) {
            label
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
            field()
        }
        .frame(maxWidth: .infinity)
    }

    private var typeMenu: some View {
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
            // Explicit colors: a menu's label takes the red tint otherwise, and the set
            // number isn't a warning.
            .foregroundStyle(Color.primary)
            .frame(minWidth: badgeSide, minHeight: badgeSide)
            .background(Color(.tertiarySystemFill), in: .rect(cornerRadius: 8))
        }
        .accessibilityLabel(Text(set.setType.label))
    }

    private var weightField: some View {
        NumberField(
            placeholder: previous?.weightKg.map { unit.format(kilograms: $0) } ?? "–",
            value: Binding(
                get: { set.weightKg.map { unit.rounded(unit.value(fromKilograms: $0)) } },
                set: { value in update { $0.weightKg = value.map { min(unit.kilograms(from: $0), Limits.maxWeightKg) } } }
            ),
            decimals: true
        )
        .focused(focus, equals: .weight(set.id, exercise: exerciseID))
        .accessibilityLabel(Text("Weight"))
    }

    private var repsField: some View {
        NumberField(
            placeholder: previous?.reps.map(String.init) ?? "–",
            value: intBinding(\.reps, max: Limits.maxReps),
            decimals: false
        )
        .focused(focus, equals: .reps(set.id))
        .accessibilityLabel(Text("Reps"))
    }

    private var doneButton: some View {
        Button {
            focus.wrappedValue = nil
            if !set.isCompleted {
                fillFromPrevious()
            }
            session.toggleCompleted(setID: set.id, in: exerciseID)
        } label: {
            // A 44-point square, the smallest target Apple recommends: the button
            // pressed most in the app, often with tired, sweaty hands.
            Image(systemName: "checkmark")
                .font(.body.weight(.bold))
                .foregroundStyle(set.isCompleted ? Color.brandOnAccent : Color.secondary.opacity(0.5))
                .frame(width: 44, height: 44)
                .background(set.isCompleted ? Color.accentColor : Color.clear, in: .rect(cornerRadius: 10))
                .overlay {
                    if !set.isCompleted {
                        RoundedRectangle(cornerRadius: 10).strokeBorder(Color.secondary.opacity(0.4), lineWidth: 1.5)
                    }
                }
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(set.isCompleted ? Text("Mark not done") : Text("Mark done"))
        .sensoryFeedback(.success, trigger: set.isCompleted) { _, done in done }
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
            .frame(minHeight: 44)
            .background(.quaternary.opacity(0.6), in: .rect(cornerRadius: 10))
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

/// Makes the rest bar clear while the keyboard is up: the bar rises with the keyboard,
/// and the buttons above the keyboard would sit on top of its own. The rest keeps
/// counting, and its notification still comes. Clear rather than removed: changing the
/// layout as the keyboard comes up drops the buttons above it.
private struct ClearWhileTyping: ViewModifier {
    @State private var isKeyboardUp = false

    func body(content: Content) -> some View {
        content
            .opacity(isKeyboardUp ? 0 : 1)
            .allowsHitTesting(!isKeyboardUp)
            .accessibilityHidden(isKeyboardUp)
            .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { _ in
                isKeyboardUp = true
            }
            .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
                isKeyboardUp = false
            }
    }
}

private struct RestTimerBar: View {
    let timer: RestTimer
    let session: WorkoutSession

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let remaining = timer.remaining(at: context.date)
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(remaining > 0 ? "Rest" : "Rest is over")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text(Duration.clock(remaining))
                        .font(.title2.monospacedDigit().weight(.semibold))
                        .contentTransition(.numericText(countsDown: true))
                }
                Spacer()
                // Three equal buttons: skipping the rest isn't the one to push.
                Button("−15 s") { session.extendRest(by: -15) }
                    .accessibilityLabel("15 seconds less")
                Button("+15 s") { session.extendRest(by: 15) }
                    .accessibilityLabel("15 seconds more")
                Button(remaining > 0 ? "Skip" : "Close") { session.skipRest() }
            }
            // One line each, shrinking a little rather than wrapping; the bar stops
            // growing at the size the set rows do, so the buttons still fit.
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .dynamicTypeSize(...DynamicTypeSize.accessibility2)
            .buttonStyle(.bordered)
            .buttonBorderShape(.capsule)
            .controlSize(.large)
            .tint(.primary)
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
