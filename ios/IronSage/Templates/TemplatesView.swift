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

/// Built-in programs, one experience level at a time, and the user's own templates.
/// Also pushed from Today.
struct TemplateList: View {
    @Environment(LocalStore.self) private var store
    @Environment(SyncEngine.self) private var sync
    @State private var pendingDelete: Template?
    @State private var creating: Template?
    /// The level picked here; until then the profile's, or beginner.
    @State private var pickedLevel: Level?
    /// The IronSage programs folded away, for someone who follows their own templates.
    /// On this phone only.
    @AppStorage("IronSage.programs.folded") private var areProgramsFolded = false

    private var profileLevel: Level? { store.profile?.experienceLevel }
    private var level: Level { pickedLevel ?? profileLevel ?? .beginner }

    var body: some View {
        let hiddenIDs = Set(store.profile?.hiddenTemplateIds ?? [])
        let builtIn = store.templates.filter { !$0.isCustom }
        let shown = builtIn.filter { !hiddenIDs.contains($0.id) && ($0.level ?? .beginner) == level }
        let hidden = builtIn.filter { hiddenIDs.contains($0.id) }
        let own = store.templates.filter(\.isCustom)
        List {
            Section {
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
            } header: {
                Text("My templates")
            } footer: {
                // Under the header, not in a row: a row looks like something to tap.
                if own.isEmpty {
                    Text("None yet. Create one with +, copy a program, or save a finished workout as a template from History.")
                }
            }

            if !builtIn.isEmpty && areProgramsFolded {
                Section {
                } header: {
                    programsHeader
                } footer: {
                    Text("Hidden on this iPhone. Tap Show to see them again.")
                }
            } else if !builtIn.isEmpty {
                Section {
                    Picker("Level", selection: Binding(get: { level }, set: { pickedLevel = $0 })) {
                        ForEach(Level.allCases, id: \.self) { level in
                            Text(level.label).tag(level)
                        }
                    }
                    .pickerStyle(.segmented)
                    .accessibilityIdentifier("programLevel")
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
                } header: {
                    programsHeader
                } footer: {
                    if let note = levelNote {
                        Text(note)
                    }
                }

                Section {
                    ForEach(shown) { template in
                        NavigationLink(value: TemplateRoute(id: template.id)) {
                            ProgramRow(template: template, plannedDays: store.profile?.trainingDaysPerWeek)
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
                } footer: {
                    Text("Each muscle is trained at least twice a week: heavy compound lifts at lower reps, accessories at higher reps.")
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
                    creating = .new(dayName: String(appLocalized: "Day \(1)"))
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

    /// "IronSage programs" with Hide or Show, like a section of Apple's own lists.
    private var programsHeader: some View {
        HStack {
            Text("IronSage programs")
            Spacer()
            Button(areProgramsFolded ? "Show" : "Hide") {
                withAnimation { areProgramsFolded.toggle() }
            }
            .font(.subheadline)
            .textCase(nil)
            .frame(minHeight: 44)
            .accessibilityLabel(areProgramsFolded ? Text("Show IronSage programs") : Text("Hide IronSage programs"))
            .accessibilityIdentifier("foldPrograms")
        }
    }

    private var levelNote: LocalizedStringResource? {
        guard let profileLevel else {
            return "Set your experience in Me › Profile to start on your level."
        }
        return profileLevel == level ? "Your level, from Me › Profile." : nil
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

/// A built-in program in the list: its name, days, goal and who it suits.
private struct ProgramRow: View {
    let template: Template
    let plannedDays: Int?

    var body: some View {
        let guide = ProgramGuide.forTemplate(template.id)
        VStack(alignment: .leading, spacing: 6) {
            Text(template.name(chinese: AppLanguage.isChinese))
                .font(.headline)
            if let days = template.daysPerWeek {
                Text("\(days) days a week")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            FittingStack(spacing: 6) {
                if let guide {
                    Chip(text: Text(guide.goal.label))
                }
                if let days = template.daysPerWeek, days == plannedDays {
                    Chip(text: Text("Fits your \(days) days"), systemImage: "checkmark")
                }
            }
            if let guide {
                Text(guide.who(chinese: AppLanguage.isChinese))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }
}

/// A small label with a rounded background.
/// A fact about a program. Plain text in a neutral color: a filled or red capsule
/// would look like a button, and red is for things that can be tapped.
private struct Chip: View {
    let text: Text
    var systemImage: String?

    var body: some View {
        HStack(spacing: 3) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.caption2.weight(.bold))
                    .accessibilityHidden(true)
            }
            text
        }
        .font(.caption.weight(.medium))
        .foregroundStyle(Color.primary.opacity(0.75))
    }
}

/// A template, one day at a time; each day can start a workout. A program also says
/// who it suits and how to progress on it, and can be copied to edit, or hidden; the
/// user's own templates can be edited.
struct TemplateDetailView: View {
    let templateID: UUID
    @Environment(LocalStore.self) private var store
    @Environment(SyncEngine.self) private var sync
    @Environment(CoachService.self) private var coach
    @Environment(\.dismiss) private var dismiss
    @Environment(WorkoutPresenter.self) private var workouts
    @State private var editing: Template?
    @State private var isBlockedByActiveWorkout = false
    @State private var dayIndex = 0

    var body: some View {
        if let template = store.templates.first(where: { $0.id == templateID }) {
            content(template)
        } else {
            ContentUnavailableView("Template deleted", systemImage: "trash")
        }
    }

    private func content(_ template: Template) -> some View {
        let chinese = AppLanguage.isChinese
        let name = template.name(chinese: chinese)
        let isHidden = store.profile?.hiddenTemplateIds.contains(template.id) ?? false
        let guide = template.isCustom ? nil : ProgramGuide.forTemplate(template.id)
        let days = template.days
        let day = days.isEmpty ? nil : days[min(dayIndex, days.count - 1)]
        return List {
            if !template.isCustom {
                Section {
                    VStack(alignment: .leading, spacing: 10) {
                        FittingStack(spacing: 6) {
                            if let level = template.level {
                                Chip(text: Text(level.label))
                            }
                            if let count = template.daysPerWeek {
                                Chip(text: Text("\(count) days a week"))
                            }
                            if let guide {
                                Chip(text: Text(guide.goal.label))
                            }
                        }
                        if let guide {
                            Text(guide.who(chinese: chinese))
                        }
                    }
                    .listRowBackground(Color.clear)
                    // Room above and below: the row's rounded corners would cut into
                    // the first and last lines this close to the edge.
                    .listRowInsets(EdgeInsets(top: 14, leading: 4, bottom: 14, trailing: 4))
                }
                if let guide {
                    Section {
                        Label {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("How to progress")
                                    .font(.subheadline.weight(.semibold))
                                Text(guide.progress(chinese: chinese))
                                    .font(.subheadline)
                            }
                        } icon: {
                            Image(systemName: "chart.line.uptrend.xyaxis")
                                .foregroundStyle(.tint)
                        }
                    }
                }
            }

            if days.count > 1 {
                Section {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(Array(days.enumerated()), id: \.element.id) { index, item in
                                Button(item.name(chinese: chinese)) { dayIndex = index }
                                    .buttonStyle(DayChipStyle(isSelected: index == min(dayIndex, days.count - 1)))
                            }
                        }
                        .padding(.horizontal, 4)
                    }
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
                }
            }

            if let day {
                Section {
                    ForEach(day.exercises) { item in
                        AdaptiveRow {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(store.exerciseName(item.exerciseId))
                                if let rest = TemplateTarget(item: item, exercise: store.exercises[item.exerciseId], unit: store.weightUnit).rest {
                                    Text(rest)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        } trailing: {
                            Text(TemplateTarget(item: item, exercise: store.exercises[item.exerciseId], unit: store.weightUnit).summary)
                                .monospacedDigit()
                                .fontWeight(.semibold)
                        }
                    }
                    Button {
                        start(day, of: template)
                    } label: {
                        Label("Start \(day.name(chinese: chinese))", systemImage: "play.fill")
                    }
                    .buttonStyle(BrandPrimaryButtonStyle())
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 8, leading: 0, bottom: 0, trailing: 0))
                    .accessibilityIdentifier("startDay")
                } header: {
                    if days.count == 1 {
                        Text(day.name(chinese: chinese))
                    }
                } footer: {
                    Text("Sets × reps. Sets start from what you did last time.")
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
                            editing = template.copy(named: String(appLocalized: "\(name) (my copy)"), chinese: chinese)
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
        workouts.show(started)
    }
}

/// A day's name as a pill, 44 points high; the picked one is outlined in red, so it
/// doesn't compete with the filled Start button under it.
private struct DayChipStyle: ButtonStyle {
    let isSelected: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(isSelected ? .semibold : .regular))
            .foregroundStyle(isSelected ? Color.accentColor : Color.primary)
            .padding(.horizontal, 16)
            .frame(minHeight: 44)
            .background(isSelected ? AnyShapeStyle(Color(.secondarySystemGroupedBackground)) : AnyShapeStyle(.clear), in: .capsule)
            .overlay {
                Capsule().strokeBorder(isSelected ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.secondary.opacity(0.4)), lineWidth: isSelected ? 1.5 : 1)
            }
            .opacity(configuration.isPressed ? 0.7 : 1)
            .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// "3 × 5–8", and the rest after the exercise.
struct TemplateTarget {
    let item: TemplateExercise
    var exercise: Exercise?
    var unit: WeightUnit = .default()

    var summary: String {
        if exercise?.isCardio == true, let target = item.sets.first {
            return CardioText.target(target, exercise: exercise, unit: unit)
        }
        let working = item.sets.filter { $0.setType != .warmup }
        guard let first = working.first else { return "" }
        return "\(working.count) × \(Self.reps(first))"
    }

    /// "Rest 3 min", or that a superset goes straight on; nil when the exercise's usual
    /// rest applies.
    var rest: LocalizedStringResource? {
        guard let seconds = item.restSeconds else { return nil }
        if seconds == 0 {
            return item.supersetGroup == nil ? "No rest" : "Then straight to the next exercise"
        }
        return seconds % 60 == 0 ? "Rest \(seconds / 60) min" : "Rest \(seconds) s"
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

extension ProgramGuide.Goal {
    var label: LocalizedStringResource {
        switch self {
        case .strength: "Strength"
        case .muscle: "Build muscle"
        case .strengthAndMuscle: "Strength + muscle"
        case .allRound: "All-round"
        case .quick: "Quick"
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
