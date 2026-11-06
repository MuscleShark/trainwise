import IronSageCore
import IronSageStore
import SwiftUI

/// Search by name, alias, pinyin, equipment or muscle ("哑铃胸"), filter with the
/// equipment and muscle buttons under the search field, as in other workout loggers,
/// or create an exercise with the typed name.
struct ExercisePickerView: View {
    /// Only lifting or only cardio; nil lets the filter menu choose.
    var only: ExerciseKind?
    let onPick: (Exercise) -> Void
    @Environment(LocalStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var equipment: Equipment?
    @State private var muscle: Muscle?
    @State private var kind: ExerciseKind?
    @State private var index: ExerciseSearch?
    @State private var isCreating = false
    @State private var info: Exercise?
    @FocusState private var isSearching: Bool

    var body: some View {
        NavigationStack {
            List {
                if !store.availableExercises.isEmpty {
                    filters
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
                        .listRowSeparator(.hidden)
                }
                if store.availableExercises.isEmpty {
                    ContentUnavailableView(
                        "No exercises yet",
                        systemImage: "dumbbell",
                        description: Text("The exercise list downloads the first time IronSage connects.")
                    )
                } else if query.isEmpty, !isFiltered, !recent.isEmpty {
                    Section("Recent") {
                        ForEach(recent) { exercise in
                            row(ExerciseSearch.Result(exercise: exercise, matched: nil))
                        }
                    }
                }

                Section(query.isEmpty && !isFiltered ? "All exercises" : "Results") {
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
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: Text("Name, equipment or muscle"))
            .searchFocused($isSearching)
            .onAppear { isSearching = true }
            .autocorrectionDisabled()
            .textInputAutocapitalization(.never)
            .navigationTitle(only == .cardio ? "Add cardio" : "Add exercise")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .task(id: store.availableExercises) {
                index = ExerciseSearch(exercises: store.availableExercises, chinese: AppLanguage.isChinese)
            }
            .sheet(item: $info) { exercise in
                ExerciseInfoView(exercise: exercise) { pick(exercise) }
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
        let kind = only ?? kind
        return (index?.search(query, limit: 200) ?? []).filter { result in
            (equipment == nil || result.exercise.equipment == equipment)
                && (muscle == nil || result.exercise.primaryMuscles.contains(muscle!))
                && (kind == nil || result.exercise.kind == kind)
        }
    }

    private var kindTitle: LocalizedStringResource {
        switch kind {
        case .cardio: "Cardio"
        case .strength: "Lifting"
        case nil: "Type"
        }
    }

    private var isFiltered: Bool {
        equipment != nil || muscle != nil || kind != nil || only != nil
    }

    /// Exercises from the last few workouts, most recent first: lifting, or only cardio
    /// when adding cardio (it has its own button in a workout).
    private var recent: [Exercise] {
        var seen: Set<UUID> = []
        let cardio = only == .cardio
        return store.finishedWorkouts.filter { !$0.isFromAppleWatch }.prefix(10)
            .flatMap(\.exercises)
            .compactMap { seen.insert($0.exerciseId).inserted ? store.exercises[$0.exerciseId] : nil }
            .filter { !store.removedExerciseIDs.contains($0.id) && $0.isCardio == cardio }
            .prefix(8)
            .map(\.self)
    }

    private func row(_ result: ExerciseSearch.Result) -> some View {
        let name = result.exercise.name(chinese: AppLanguage.isChinese)
        return HStack(spacing: 12) {
            Button {
                pick(result.exercise)
            } label: {
                HStack(spacing: 12) {
                    ExerciseThumbnail(exercise: result.exercise)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(name)
                            .foregroundStyle(.primary)
                        Group {
                            if let matched = result.matched {
                                Text(matched)
                            } else if result.exercise.isCardio {
                                Text(result.exercise.equipment.label) + Text(verbatim: " · ") + Text("Cardio")
                            } else if let muscle = result.exercise.primaryMuscles.first {
                                Text(result.exercise.equipment.label) + Text(verbatim: " · ") + Text(muscle.label)
                            } else {
                                Text(result.exercise.equipment.label)
                            }
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                }
                .contentShape(.rect)
            }
            .tint(.primary)
            Button("How to do \(name)", systemImage: "info.circle") {
                info = result.exercise
            }
            .labelStyle(.iconOnly)
            .font(.title3)
            .frame(width: 44, height: 44)
            .contentShape(.rect)
        }
        .buttonStyle(.borderless)
    }

    /// Equipment and muscle (and lifting or cardio, when both can be added), each a
    /// button that opens its list; a chosen one is filled and says what it is.
    private var filters: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                // First, so it stays in view however many filters are on.
                if equipment != nil || muscle != nil || kind != nil {
                    Button {
                        equipment = nil
                        muscle = nil
                        kind = nil
                    } label: {
                        Image(systemName: "xmark")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Color.primary)
                            .frame(width: 36, height: 36)
                            .background(Color(.secondarySystemGroupedBackground), in: .circle)
                            .overlay { Circle().strokeBorder(Color.primary.opacity(0.12)) }
                            .frame(width: 44, height: 44)
                            .contentShape(.circle)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Clear filters")
                }
                if only == nil {
                    FilterChip(title: kindTitle, isOn: kind != nil, identifier: "filterType") {
                        Picker("Type", selection: $kind) {
                            Text("Lifting and cardio").tag(ExerciseKind?.none)
                            Text("Lifting").tag(ExerciseKind?.some(.strength))
                            Text("Cardio").tag(ExerciseKind?.some(.cardio))
                        }
                    }
                }
                FilterChip(title: equipment?.label ?? "Equipment", isOn: equipment != nil, identifier: "filterEquipment") {
                    Picker("Equipment", selection: $equipment) {
                        Text("Any equipment").tag(Equipment?.none)
                        ForEach(Equipment.allCases, id: \.self) { item in
                            Text(item.label).tag(Equipment?.some(item))
                        }
                    }
                }
                FilterChip(title: muscle?.label ?? "Muscle", isOn: muscle != nil, identifier: "filterMuscle") {
                    Picker("Muscle", selection: $muscle) {
                        Text("Any muscle").tag(Muscle?.none)
                        ForEach(Muscle.allCases, id: \.self) { item in
                            Text(item.label).tag(Muscle?.some(item))
                        }
                    }
                }
            }
            .padding(.vertical, 4)
        }
        .scrollIndicators(.hidden)
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

/// A capsule button that opens a menu, filled when its filter is on.
private struct FilterChip<Content: View>: View {
    let title: LocalizedStringResource
    let isOn: Bool
    let identifier: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        Menu {
            content()
        } label: {
            HStack(spacing: 4) {
                Text(title)
                Image(systemName: "chevron.down")
                    .font(.caption2.weight(.semibold))
                    .accessibilityHidden(true)
            }
            .font(.subheadline.weight(.medium))
            .foregroundStyle(isOn ? Color.brandOnAccent : Color.primary)
            .padding(.horizontal, 14)
            .frame(minHeight: 36)
            .background(isOn ? Color.accentColor : Color(.secondarySystemGroupedBackground), in: .capsule)
            .overlay {
                if !isOn {
                    Capsule().strokeBorder(Color.primary.opacity(0.12))
                }
            }
            .contentShape(.capsule)
            .frame(minHeight: 44)
        }
        .accessibilityIdentifier(identifier)
    }
}
