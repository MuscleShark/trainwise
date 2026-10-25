import IronSageCore
import IronSageStore
import SwiftUI

/// Finished workouts by week.
struct HistoryView: View {
    @Environment(LocalStore.self) private var store
    @Environment(SyncEngine.self) private var sync
    @Environment(HealthService.self) private var health
    @State private var pendingDelete: Workout?

    var body: some View {
        NavigationStack {
            let weeks = WorkoutHistory.weeks(store.finishedWorkouts)
            List {
                ForEach(weeks) { week in
                    Section {
                        ForEach(week.workouts) { workout in
                            NavigationLink(value: WorkoutRoute(id: workout.id)) {
                                WorkoutRow(workout: workout)
                            }
                            .swipeActions {
                                Button("Delete", systemImage: "trash", role: .destructive) {
                                    pendingDelete = workout
                                }
                            }
                        }
                    } header: {
                        WeekHeader(week: week)
                    }
                }
            }
            .brandBackground()
            .overlay {
                if weeks.isEmpty {
                    ContentUnavailableView(
                        "No workouts yet",
                        systemImage: "calendar",
                        description: Text("Finished workouts will be listed here by week.")
                    )
                }
            }
            .navigationTitle("History")
            .navigationDestination(for: WorkoutRoute.self) { route in
                WorkoutDetailView(workoutID: route.id)
            }
            .navigationDestination(for: ExerciseRoute.self) { route in
                ExerciseDetailView(exerciseID: route.id)
            }
            .refreshable { await sync.sync() }
            .confirmationDialog(
                "Delete this workout?",
                isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }),
                titleVisibility: .visible,
                presenting: pendingDelete
            ) { workout in
                Button("Delete workout", role: .destructive) {
                    store.deleteWorkout(id: workout.id)
                    Task {
                        await health.removeFromHealth(workout)
                        await sync.sync()
                    }
                }
            } message: { workout in
                Text("“\(workout.title)” will be removed from all your devices.")
            }
        }
    }
}

private struct WeekHeader: View {
    let week: WorkoutHistory.Week

    var body: some View {
        HStack {
            Text(title)
            Spacer()
            Text("^[\(week.workouts.count) workout](inflect: true)")
        }
    }

    private var title: String {
        let calendar = Calendar.current
        let thisWeek = calendar.dateInterval(of: .weekOfYear, for: .now)?.start
        if week.start == thisWeek {
            return String(localized: "This week")
        }
        if let thisWeek, let lastWeek = calendar.date(byAdding: .weekOfYear, value: -1, to: thisWeek), week.start == lastWeek {
            return String(localized: "Last week")
        }
        let end = calendar.date(byAdding: .day, value: 6, to: week.start) ?? week.start
        return (week.start..<end).formatted(.interval.month(.abbreviated).day())
    }
}

/// One workout with all its sets; edit or delete it from here.
struct WorkoutDetailView: View {
    let workoutID: UUID
    @Environment(LocalStore.self) private var store
    @Environment(SyncEngine.self) private var sync
    @Environment(HealthService.self) private var health
    @Environment(\.dismiss) private var dismiss
    @State private var editing: WorkoutSession?
    @State private var isConfirmingDelete = false
    @State private var isSavingTemplate = false
    @State private var templateName = ""

    var body: some View {
        if let workout = store.workouts.first(where: { $0.id == workoutID }) {
            content(workout)
        } else {
            ContentUnavailableView("Workout deleted", systemImage: "trash")
        }
    }

    private func content(_ workout: Workout) -> some View {
        let unit = store.weightUnit
        return List {
            Section {
                LabeledContent("Date") {
                    Text(workout.startedAt, format: .dateTime.weekday(.wide).month().day().hour().minute())
                }
                if let endedAt = workout.endedAt {
                    LabeledContent("Duration", value: Duration.clock(endedAt.timeIntervalSince(workout.startedAt)))
                }
                LabeledContent("Volume", value: unit.formatTotal(kilograms: WorkoutLog.volumeKg(of: workout, exercises: store.exercises)))
                if let average = workout.avgHeartRate, let maximum = workout.maxHeartRate {
                    LabeledContent("Heart rate", value: String(localized: "\(average) avg, \(maximum) max"))
                }
            }

            ForEach(workout.exercises) { item in
                Section {
                    ForEach(Array(item.sets.enumerated()), id: \.element.id) { index, set in
                        HStack {
                            Group {
                                if let badge = set.setType.badge {
                                    Text(badge)
                                } else {
                                    Text(item.sets[...index].filter { $0.setType != .warmup }.count, format: .number)
                                }
                            }
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .frame(width: 28, alignment: .leading)
                            Text(unit.formatSet(set))
                                .monospacedDigit()
                            Spacer()
                            if let rir = set.rir {
                                Text("RIR \(rir)")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                } header: {
                    // Opens the exercise's progress: every session, the chart and records.
                    NavigationLink(value: ExerciseRoute(id: item.exerciseId)) {
                        HStack(spacing: 4) {
                            Text(store.exerciseName(item.exerciseId))
                            Image(systemName: "chevron.right")
                                .font(.caption.weight(.semibold))
                                .accessibilityHidden(true)
                        }
                    }
                    .accessibilityHint(Text("Shows this exercise's progress and records"))
                }
            }

            if let notes = workout.notes, !notes.isEmpty {
                Section("Notes") {
                    Text(notes)
                }
            }
        }
        .brandBackground()
        .navigationTitle(workout.title)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu("Options", systemImage: "ellipsis.circle") {
                    Button("Edit", systemImage: "pencil") {
                        editing = WorkoutSession(workout: workout, store: store)
                    }
                    Button("Save as template", systemImage: "square.and.arrow.down") {
                        templateName = workout.title
                        isSavingTemplate = true
                    }
                    Button("Delete", systemImage: "trash", role: .destructive) {
                        isConfirmingDelete = true
                    }
                }
            }
        }
        .fullScreenCover(item: $editing) { session in
            WorkoutView(session: session)
                .interactiveDismissDisabled()
        }
        .alert("Save as template", isPresented: $isSavingTemplate) {
            TextField("Name", text: $templateName)
            Button("Cancel", role: .cancel) {}
            Button("Save") {
                let name = String(templateName.trimmingCharacters(in: .whitespaces).prefix(120))
                guard !name.isEmpty else { return }
                store.save(WorkoutLog.template(from: workout, name: name))
                Task { await sync.sync() }
            }
        } message: {
            Text("Starts with the same exercises and sets. It appears under My templates.")
        }
        .confirmationDialog("Delete this workout?", isPresented: $isConfirmingDelete, titleVisibility: .visible) {
            Button("Delete workout", role: .destructive) {
                store.deleteWorkout(id: workout.id)
                Task {
                    await health.removeFromHealth(workout)
                    await sync.sync()
                }
                dismiss()
            }
        } message: {
            Text("“\(workout.title)” will be removed from all your devices.")
        }
    }
}
