import IronSageCore
import IronSageStore
import SwiftUI

/// Search by name, alias or pinyin, filter by equipment or muscle, or create an
/// exercise with the typed name.
struct ExercisePickerView: View {
    let onPick: (Exercise) -> Void
    @Environment(LocalStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var equipment: Equipment?
    @State private var muscle: Muscle?
    @State private var index: ExerciseSearch?
    @State private var isCreating = false
    @FocusState private var isSearching: Bool

    var body: some View {
        NavigationStack {
            List {
                if store.availableExercises.isEmpty {
                    ContentUnavailableView(
                        "No exercises yet",
                        systemImage: "dumbbell",
                        description: Text("The exercise list downloads the first time IronSage connects.")
                    )
                } else if query.isEmpty, equipment == nil, muscle == nil, !recent.isEmpty {
                    Section("Recent") {
                        ForEach(recent) { exercise in
                            row(ExerciseSearch.Result(exercise: exercise, matched: nil))
                        }
                    }
                }

                Section(query.isEmpty && equipment == nil && muscle == nil ? "All exercises" : "Results") {
                    ForEach(results) { result in
                        row(result)
                    }
                }

                Section {
                    Button {
                        isCreating = true
                    } label: {
                        if query.trimmingCharacters(in: .whitespaces).isEmpty {
                            Label("Create exercise", systemImage: "plus")
                        } else {
                            Label("Create “\(query.trimmingCharacters(in: .whitespaces))”", systemImage: "plus")
                        }
                    }
                } footer: {
                    Text("For a machine or variation that isn't listed.")
                }
            }
            .brandBackground()
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: Text("Name, alias or pinyin"))
            .searchFocused($isSearching)
            .onAppear { isSearching = true }
            .autocorrectionDisabled()
            .textInputAutocapitalization(.never)
            .navigationTitle("Add exercise")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    filterMenu
                }
            }
            .task(id: store.availableExercises) {
                index = ExerciseSearch(exercises: store.availableExercises, chinese: AppLanguage.isChinese)
            }
            .sheet(isPresented: $isCreating) {
                CreateExerciseView(name: query.trimmingCharacters(in: .whitespaces)) { exercise in
                    store.save(exercise)
                    pick(exercise)
                }
            }
        }
    }

    private var results: [ExerciseSearch.Result] {
        (index?.search(query, limit: 200) ?? []).filter { result in
            (equipment == nil || result.exercise.equipment == equipment)
                && (muscle == nil || result.exercise.primaryMuscles.contains(muscle!))
        }
    }

    /// Exercises from the last few workouts, most recent first.
    private var recent: [Exercise] {
        var seen: Set<UUID> = []
        return store.finishedWorkouts.prefix(10)
            .flatMap(\.exercises)
            .compactMap { seen.insert($0.exerciseId).inserted ? store.exercises[$0.exerciseId] : nil }
            .filter { !store.removedExerciseIDs.contains($0.id) }
            .prefix(8)
            .map(\.self)
    }

    private func row(_ result: ExerciseSearch.Result) -> some View {
        Button {
            pick(result.exercise)
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(result.exercise.name(chinese: AppLanguage.isChinese))
                    .foregroundStyle(.primary)
                Group {
                    if let matched = result.matched {
                        Text(matched)
                    } else if let muscle = result.exercise.primaryMuscles.first {
                        Text(result.exercise.equipment.label) + Text(verbatim: " · ") + Text(muscle.label)
                    } else {
                        Text(result.exercise.equipment.label)
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .tint(.primary)
    }

    private var filterMenu: some View {
        Menu {
            Picker("Equipment", selection: $equipment) {
                Text("Any equipment").tag(Equipment?.none)
                ForEach(Equipment.allCases, id: \.self) { item in
                    Text(item.label).tag(Equipment?.some(item))
                }
            }
            .pickerStyle(.menu)
            Picker("Muscle", selection: $muscle) {
                Text("Any muscle").tag(Muscle?.none)
                ForEach(Muscle.allCases, id: \.self) { item in
                    Text(item.label).tag(Muscle?.some(item))
                }
            }
            .pickerStyle(.menu)
        } label: {
            Label("Filter", systemImage: equipment == nil && muscle == nil
                ? "line.3.horizontal.decrease.circle"
                : "line.3.horizontal.decrease.circle.fill")
        }
    }

    private func pick(_ exercise: Exercise) {
        onPick(exercise)
        dismiss()
    }
}

/// A user's own exercise, such as a specific machine.
struct CreateExerciseView: View {
    let onCreate: (Exercise) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var equipment: Equipment = .machine
    @State private var loadType: LoadType = .total
    @State private var primary: Set<Muscle> = []

    init(name: String, onCreate: @escaping (Exercise) -> Void) {
        _name = State(initialValue: name)
        self.onCreate = onCreate
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name", text: $name)
                }
                Section {
                    Picker("Equipment", selection: $equipment) {
                        ForEach(Equipment.allCases, id: \.self) { Text($0.label).tag($0) }
                    }
                    Picker("Weight logged as", selection: $loadType) {
                        ForEach(LoadType.allCases, id: \.self) { Text($0.label).tag($0) }
                    }
                } footer: {
                    Text("For one dumbbell, cable handle or machine arm, log the weight per side.")
                }
                Section("Main muscles") {
                    ForEach(Muscle.allCases, id: \.self) { muscle in
                        Button {
                            if primary.contains(muscle) {
                                primary.remove(muscle)
                            } else if primary.count < 5 {
                                primary.insert(muscle)
                            }
                        } label: {
                            HStack {
                                Text(muscle.label).foregroundStyle(.primary)
                                Spacer()
                                if primary.contains(muscle) {
                                    Image(systemName: "checkmark").foregroundStyle(.tint)
                                }
                            }
                        }
                    }
                }
            }
            .brandBackground()
            .navigationTitle("New exercise")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") { create() }
                        .disabled(trimmedName.isEmpty || primary.isEmpty)
                }
            }
        }
    }

    private var trimmedName: String {
        String(name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(120))
    }

    private func create() {
        let typedChinese = trimmedName.unicodeScalars.contains { (0x4E00...0x9FFF).contains($0.value) }
        onCreate(Exercise(
            nameEn: trimmedName,
            nameZh: typedChinese ? trimmedName : nil,
            equipment: equipment,
            loadType: loadType,
            primaryMuscles: Muscle.allCases.filter(primary.contains),
            isCustom: true
        ))
        dismiss()
    }
}
