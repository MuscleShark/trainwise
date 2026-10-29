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
    @State private var creating: Template?

    var body: some View {
        let hiddenIDs = Set(store.profile?.hiddenTemplateIds ?? [])
        let builtIn = store.templates.filter { !$0.isCustom }
        let shown = builtIn.filter { !hiddenIDs.contains($0.id) }
        let hidden = builtIn.filter { hiddenIDs.contains($0.id) }
        let own = store.templates.filter(\.isCustom)
        List {
            Section("My templates") {
                if own.isEmpty {
                    Text("Create one with +, copy a program, or save a finished workout as a template from History.")
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

            if !builtIn.isEmpty {
                Section {
                    ForEach(shown) { template in
                        NavigationLink(value: TemplateRoute(id: template.id)) {
                            TemplateRow(template: template)
                        }
                        .swipeActions {
                            Button("Hide program", systemImage: "eye.slash") {
                                hide(template)
                            }
                            .tint(.gray)
                        }
                    }
                    if !hidden.isEmpty {
                        NavigationLink(value: HiddenProgramsRoute()) {
                            LabeledContent("Hidden programs", value: hidden.count.formatted())
                        }
                    }
                } header: {
                    Text("IronSage programs")
                } footer: {
                    Text("Each muscle is trained at least twice a week: heavy compound lifts at lower reps, accessories at higher reps, most sets one to three reps short of failure.")
                }
            }
        }
        .brandBackground()
        .overlay {
            if store.templates.isEmpty && !store.hasBuiltInExercises {
                ContentUnavailableView(
                    "No templates yet",
                    systemImage: "list.bullet.rectangle",
                    description: Text("The programs download the first time IronSage connects.")
                )
            }
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("New template", systemImage: "plus") {
                    creating = .new(dayName: String(localized: "Day \(1)"))
                }
            }
        }
        .navigationDestination(for: TemplateRoute.self) { route in
            TemplateDetailView(templateID: route.id)
        }
        .navigationDestination(for: HiddenProgramsRoute.self) { _ in
            HiddenProgramsView()
        }
        .refreshable { await sync.sync() }
        .sheet(item: $creating) { template in
            TemplateEditorView(template: template, title: "New template") { saved in
                store.save(saved)
                Task { await sync.sync() }
            }
        }
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

    private func hide(_ template: Template) {
        store.setTemplate(template.id, hidden: true)
        Task { await sync.sync() }
    }
}

private struct HiddenProgramsRoute: Hashable {}

/// Programs the user hid, each with a way to show it again.
private struct HiddenProgramsView: View {
    @Environment(LocalStore.self) private var store
    @Environment(SyncEngine.self) private var sync

    var body: some View {
        let hiddenIDs = Set(store.profile?.hiddenTemplateIds ?? [])
        let hidden = store.templates.filter { !$0.isCustom && hiddenIDs.contains($0.id) }
        List {
            Section {
                ForEach(hidden) { template in
                    HStack {
                        TemplateRow(template: template)
                        Spacer()
                        Button("Show") {
                            store.setTemplate(template.id, hidden: false)
                            Task { await sync.sync() }
                        }
                        .buttonStyle(.bordered)
                    }
                }
            } footer: {
                Text("Hidden programs are hidden on all your devices. Workouts you did with them stay in History.")
            }
        }
        .brandBackground()
        .overlay {
            if hidden.isEmpty {
                ContentUnavailableView("No hidden programs", systemImage: "eye")
            }
        }
        .navigationTitle("Hidden programs")
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
                    if template.level != nil {
                        Text(verbatim: "·")
                    }
                    Text("\(days) days a week")
                }
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)
        }
    }
}

/// A template's days; each can start a workout. A program can be copied to edit, or
/// hidden; the user's own templates can be edited.
struct TemplateDetailView: View {
    let templateID: UUID
    @Environment(LocalStore.self) private var store
    @Environment(SyncEngine.self) private var sync
    @Environment(CoachService.self) private var coach
    @Environment(\.dismiss) private var dismiss
    @State private var session: WorkoutSession?
    @State private var editing: Template?
    @State private var isBlockedByActiveWorkout = false

    var body: some View {
        if let template = store.templates.first(where: { $0.id == templateID }) {
            content(template)
        } else {
            ContentUnavailableView("Template deleted", systemImage: "trash")
        }
    }

    private func content(_ template: Template) -> some View {
        let name = template.name(chinese: AppLanguage.isChinese)
        let isHidden = store.profile?.hiddenTemplateIds.contains(template.id) ?? false
        return List {
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
        .brandBackground()
        .navigationTitle(name)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                if template.isCustom {
                    Button("Edit") { editing = template }
                } else {
                    Menu("More", systemImage: "ellipsis.circle") {
                        Button("Copy and edit", systemImage: "doc.on.doc") {
                            editing = template.copy(named: String(localized: "\(name) (my copy)"), chinese: AppLanguage.isChinese)
                        }
                        if isHidden {
                            Button("Show program", systemImage: "eye") {
                                setHidden(template, false)
                            }
                        } else {
                            Button("Hide program", systemImage: "eye.slash") {
                                setHidden(template, true)
                                dismiss()
                            }
                        }
                    }
                    .accessibilityIdentifier("programMenu")
                }
            }
        }
        .sheet(item: $editing) { draft in
            TemplateEditorView(template: draft, title: draft.id == template.id ? "Edit template" : "Copy and edit") { saved in
                store.save(saved)
                Task { await sync.sync() }
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

    private func setHidden(_ template: Template, _ hidden: Bool) {
        store.setTemplate(template.id, hidden: hidden)
        Task { await sync.sync() }
    }

    private func start(_ day: TemplateDay, of template: Template) {
        guard store.activeWorkout == nil else {
            isBlockedByActiveWorkout = true
            return
        }
        let advised = coach.advice(for: day)
        let started = WorkoutSession.start(day, of: template, store: store, advice: advised?.output)
        if let advised {
            coach.recordApplied(advised, to: started.workout.id)
        }
        session = started
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
