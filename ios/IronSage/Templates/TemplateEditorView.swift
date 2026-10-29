import IronSageCore
import IronSageStore
import SwiftUI

/// Creating or changing one of the user's own templates: its name, its days, and each
/// day's exercises with their sets, reps, reps in reserve and rest.
struct TemplateEditorView: View {
    let title: LocalizedStringResource
    let onSave: (Template) -> Void
    private let original: Template
    @State private var template: Template
    @State private var addingTo: DayID?
    @State private var isConfirmingDiscard = false
    @Environment(LocalStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    init(template: Template, title: LocalizedStringResource, onSave: @escaping (Template) -> Void) {
        self.title = title
        self.onSave = onSave
        original = template
        _template = State(initialValue: template)
    }

    private struct DayID: Identifiable {
        let id: UUID
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name", text: $template.nameEn)
                        .accessibilityIdentifier("templateName")
                } header: {
                    Text("Name")
                }

                ForEach(Array(template.days.enumerated()), id: \.element.id) { index, day in
                    daySection(index: index, day: day)
                }

                Section {
                    if template.days.count < Template.maxDays {
                        Button("Add day", systemImage: "plus") {
                            template.days.append(TemplateDay(name: String(localized: "Day \(template.days.count + 1)")))
                        }
                    }
                } footer: {
                    if let problem = template.problem {
                        Text(problem.message)
                    }
                }
            }
            .brandBackground()
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(for: ExerciseRoute.self) { route in
                if let binding = exerciseBinding(route.id) {
                    TemplateExerciseEditor(item: binding)
                }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        if template == original {
                            dismiss()
                        } else {
                            isConfirmingDiscard = true
                        }
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onSave(template.tidied())
                        dismiss()
                    }
                    .disabled(template.problem != nil)
                }
            }
            .confirmationDialog("Discard your changes?", isPresented: $isConfirmingDiscard, titleVisibility: .visible) {
                Button("Discard changes", role: .destructive) { dismiss() }
            }
            .sheet(item: $addingTo) { day in
                ExercisePickerView { exercise in
                    guard let index = template.days.firstIndex(where: { $0.id == day.id }) else { return }
                    template.days[index].exercises.append(.standard(exercise.id))
                }
            }
        }
        .interactiveDismissDisabled(template != original)
    }

    private func daySection(index: Int, day: TemplateDay) -> some View {
        Section {
            TextField("Day name", text: Binding(
                get: { template.days[safe: index]?.name ?? "" },
                set: { template.days[safe: index]?.name = $0 }
            ))
            ForEach(day.exercises) { item in
                NavigationLink(value: ExerciseRoute(id: item.id)) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(store.exerciseName(item.exerciseId))
                        Spacer()
                        Text(TemplateTarget(item: item).summary)
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .onDelete { offsets in
                template.days[index].exercises.remove(atOffsets: offsets)
            }
            .onMove { offsets, destination in
                template.days[index].exercises.move(fromOffsets: offsets, toOffset: destination)
            }
            if day.exercises.count < Template.maxExercisesPerDay {
                Button("Add exercise", systemImage: "plus") {
                    addingTo = DayID(id: day.id)
                }
            }
            if template.days.count > 1 {
                Button("Remove day", systemImage: "minus.circle", role: .destructive) {
                    template.days.removeAll { $0.id == day.id }
                }
            }
        } header: {
            Text("Day \(index + 1)")
        }
    }

    /// An exercise of the template by its id, wherever it is.
    private func exerciseBinding(_ id: UUID) -> Binding<TemplateExercise>? {
        guard let day = template.days.firstIndex(where: { $0.exercises.contains { $0.id == id } }) else { return nil }
        return Binding(
            get: { template.days[safe: day]?.exercises.first { $0.id == id } ?? TemplateExercise(exerciseId: id) },
            set: { item in
                guard let index = template.days[safe: day]?.exercises.firstIndex(where: { $0.id == id }) else { return }
                template.days[day].exercises[index] = item
            }
        )
    }

    private struct ExerciseRoute: Hashable {
        let id: UUID
    }
}

extension TemplateProblem {
    var message: LocalizedStringResource {
        switch self {
        case .noName: "Give the template a name."
        case .dayWithoutName: "Give each day a name."
        case .dayWithoutExercises: "Add at least one exercise to each day."
        }
    }
}

/// Sets, reps, reps in reserve and rest for one exercise of a template.
private struct TemplateExerciseEditor: View {
    @Binding var item: TemplateExercise
    @Environment(LocalStore.self) private var store

    private static let rests = [60, 90, 120, 180, 240, 300]

    var body: some View {
        let targets = item.targets
        let repMin = targets.repMin ?? 8
        let repMax = targets.repMax ?? repMin
        Form {
            Section {
                Stepper(value: $item.targets.sets, in: 1...TemplateTargets.maxSets) {
                    LabeledContent("Sets", value: targets.sets.formatted())
                }
                Stepper(value: Binding(get: { repMin }, set: { item.targets.repMin = $0; item.targets.repMax = max($0, repMax) }), in: 1...100) {
                    LabeledContent("Fewest reps", value: repMin.formatted())
                }
                Stepper(value: Binding(get: { repMax }, set: { item.targets.repMax = $0; item.targets.repMin = min($0, repMin) }), in: 1...100) {
                    LabeledContent("Most reps", value: repMax.formatted())
                }
                Picker("Reps in reserve", selection: $item.targets.rir) {
                    Text("Not set").tag(Int?.none)
                    ForEach(0...5, id: \.self) { rir in
                        Text(rir, format: .number).tag(Int?.some(rir))
                    }
                }
            } footer: {
                Text("Each working set aims for this many reps. Reps in reserve is how many more you could have done.")
            }

            Section {
                Picker("Rest", selection: $item.restSeconds) {
                    Text("Usual (\(Self.duration(store.exercises[item.exerciseId]?.defaultRestSeconds ?? 120)))").tag(Int?.none)
                    // A program's own rest stays selectable even when it isn't one of these.
                    ForEach(Set(Self.rests + [item.restSeconds].compactMap { $0 }).sorted(), id: \.self) { seconds in
                        Text(Self.duration(seconds)).tag(Int?.some(seconds))
                    }
                }
            }
        }
        .brandBackground()
        .navigationTitle(store.exerciseName(item.exerciseId))
        .navigationBarTitleDisplayMode(.inline)
    }

    private static func duration(_ seconds: Int) -> String {
        Duration.seconds(seconds).formatted(.units(allowed: [.minutes, .seconds], width: .abbreviated))
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        get { indices.contains(index) ? self[index] : nil }
        set {
            guard let newValue, indices.contains(index) else { return }
            self[index] = newValue
        }
    }
}
