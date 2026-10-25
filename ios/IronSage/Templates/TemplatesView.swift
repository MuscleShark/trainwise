import IronSageCore
import IronSageStore
import SwiftUI

struct TemplatesView: View {
    var body: some View {
        NavigationStack {
            TemplateList()
                .navigationTitle("Templates")
        }
    }
}

/// Built-in programs and the user's own templates. Also pushed from Today.
struct TemplateList: View {
    @Environment(LocalStore.self) private var store
    @Environment(SyncEngine.self) private var sync
    @State private var pendingDelete: Template?

    var body: some View {
        let builtIn = store.templates.filter { !$0.isCustom }
        let own = store.templates.filter(\.isCustom)
        List {
            if !builtIn.isEmpty {
                Section {
                    ForEach(builtIn) { template in
                        NavigationLink(value: TemplateRoute(id: template.id)) {
                            TemplateRow(template: template)
                        }
                    }
                } header: {
                    Text("IronSage programs")
                } footer: {
                    Text("Each muscle is trained at least twice a week: heavy compound lifts at lower reps, accessories at higher reps, most sets one to three reps short of failure.")
                }
            }

            Section("My templates") {
                if own.isEmpty {
                    Text("Save a finished workout as a template from its page in History.")
                        .foregroundStyle(.secondary)
                }
                ForEach(own) { template in
                    NavigationLink(value: TemplateRoute(id: template.id)) {
                        TemplateRow(template: template)
                    }
                    .swipeActions {
                        Button("Delete", systemImage: "trash", role: .destructive) {
                            pendingDelete = template
                        }
                    }
                }
            }
        }
        .overlay {
            if store.templates.isEmpty && !store.hasBuiltInExercises {
                ContentUnavailableView(
                    "No templates yet",
                    systemImage: "list.bullet.rectangle",
                    description: Text("The programs download the first time IronSage connects.")
                )
            }
        }
        .navigationDestination(for: TemplateRoute.self) { route in
            TemplateDetailView(templateID: route.id)
        }
        .refreshable { await sync.sync() }
        .confirmationDialog(
            "Delete this template?",
            isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }),
            titleVisibility: .visible,
            presenting: pendingDelete
        ) { template in
            Button("Delete template", role: .destructive) {
                store.deleteTemplate(id: template.id)
                Task { await sync.sync() }
            }
        } message: { _ in
            Text("Workouts you did with it stay in History.")
        }
    }
}

private struct TemplateRow: View {
    let template: Template

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(template.name(chinese: AppLanguage.isChinese))
                .font(.headline)
            HStack(spacing: 6) {
                if let level = template.level {
                    Text(level.label)
                }
                if let days = template.daysPerWeek {
                    Text(verbatim: "·")
                    Text("\(days) days a week")
                }
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)
        }
    }
}

/// A template's days; each can start a workout.
struct TemplateDetailView: View {
    let templateID: UUID
    @Environment(LocalStore.self) private var store
    @State private var session: WorkoutSession?
    @State private var isRenaming = false
    @State private var newName = ""
    @State private var isBlockedByActiveWorkout = false

    var body: some View {
        if let template = store.templates.first(where: { $0.id == templateID }) {
            content(template)
        } else {
            ContentUnavailableView("Template deleted", systemImage: "trash")
        }
    }

    private func content(_ template: Template) -> some View {
        List {
            ForEach(template.days) { day in
                Section {
                    ForEach(day.exercises) { item in
                        HStack(alignment: .firstTextBaseline) {
                            Text(store.exerciseName(item.exerciseId))
                            Spacer()
                            Text(TemplateTarget(item: item).summary)
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                        }
                    }
                    Button("Start this workout", systemImage: "play.fill") {
                        start(day, of: template)
                    }
                    .fontWeight(.semibold)
                } header: {
                    Text(day.name(chinese: AppLanguage.isChinese))
                }
            }
        }
        .navigationTitle(template.name(chinese: AppLanguage.isChinese))
        .toolbar {
            if template.isCustom {
                ToolbarItem(placement: .primaryAction) {
                    Button("Rename") {
                        newName = template.nameEn
                        isRenaming = true
                    }
                }
            }
        }
        .alert("Rename template", isPresented: $isRenaming) {
            TextField("Name", text: $newName)
            Button("Cancel", role: .cancel) {}
            Button("Save") {
                let name = String(newName.trimmingCharacters(in: .whitespaces).prefix(120))
                guard !name.isEmpty else { return }
                var renamed = template
                renamed.nameEn = name
                renamed.nameZh = nil
                store.save(renamed)
            }
        }
        .alert("A workout is in progress", isPresented: $isBlockedByActiveWorkout) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Finish or discard it on the Today tab first.")
        }
        .fullScreenCover(item: $session) { session in
            WorkoutView(session: session)
        }
    }

    private func start(_ day: TemplateDay, of template: Template) {
        guard store.activeWorkout == nil else {
            isBlockedByActiveWorkout = true
            return
        }
        let title = template.days.count > 1
            ? "\(template.name(chinese: AppLanguage.isChinese)) · \(day.name(chinese: AppLanguage.isChinese))"
            : template.name(chinese: AppLanguage.isChinese)
        session = WorkoutSession.start(
            title: String(title.prefix(120)),
            exercises: WorkoutLog.exercises(for: day, history: store.finishedWorkouts),
            templateID: template.id,
            store: store
        )
    }
}

/// "3 × 5–8 · RIR 2"
struct TemplateTarget {
    let item: TemplateExercise

    var summary: String {
        let working = item.sets.filter { $0.setType != .warmup }
        guard let first = working.first else { return "" }
        var text = "\(working.count) × \(Self.reps(first))"
        if let rir = first.targetRir {
            text += " · RIR \(rir)"
        }
        return text
    }

    static func reps(_ set: TemplateSet) -> String {
        switch (set.repMin, set.repMax) {
        case let (min?, max?) where min != max: "\(min)–\(max)"
        case let (min?, _): "\(min)"
        case let (nil, max?): "\(max)"
        default: "–"
        }
    }
}

extension Level {
    var label: LocalizedStringResource {
        switch self {
        case .beginner: "Beginner"
        case .intermediate: "Intermediate"
        case .advanced: "Advanced"
        }
    }
}
