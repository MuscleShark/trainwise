import IronSageCore
import IronSageStore
import SwiftUI

struct TodayView: View {
    @Environment(LocalStore.self) private var store
    @State private var session: WorkoutSession?

    var body: some View {
        NavigationStack {
            List {
                if let active = store.activeWorkout {
                    Section {
                        Button {
                            session = WorkoutSession(workout: active, store: store)
                        } label: {
                            ActiveWorkoutRow(workout: active)
                        }
                    } header: {
                        Text("In progress")
                    }
                } else {
                    Section {
                        Button("Start an empty workout", systemImage: "plus.circle.fill") {
                            session = WorkoutSession.start(store: store)
                        }
                        .font(.headline)
                        NavigationLink(value: TemplateListRoute()) {
                            Label("Start from a template", systemImage: "list.bullet.rectangle")
                        }
                    } footer: {
                        Text("Add exercises as you go. Sets start from what you did last time, with the next step suggested.")
                    }

                    if let upNext {
                        UpNextSection(template: upNext.template, day: upNext.day, session: $session)
                    }
                }

                WeeklySummaryCard()

                ReadinessCard()

                if let last = store.finishedWorkouts.first {
                    Section("Last workout") {
                        NavigationLink(value: WorkoutRoute(id: last.id)) {
                            WorkoutRow(workout: last)
                        }
                    }
                }
            }
            .brandBackground()
            .navigationTitle("Today")
            .navigationDestination(for: WorkoutRoute.self) { route in
                WorkoutDetailView(workoutID: route.id)
            }
            .navigationDestination(for: ExerciseRoute.self) { route in
                ExerciseDetailView(exerciseID: route.id)
            }
            .navigationDestination(for: CoachRoute.self) { route in
                CoachDataView(id: route.id)
            }
            .navigationDestination(for: TemplateListRoute.self) { _ in
                TemplateList()
                    .navigationTitle("Templates")
            }
            .fullScreenCover(item: $session) { session in
                WorkoutView(session: session)
            }
        }
    }
}

extension TodayView {
    private var upNext: (template: Template, day: TemplateDay)? { store.upNext }
}

/// The template day due next, with each exercise's suggested top set.
private struct UpNextSection: View {
    let template: Template
    let day: TemplateDay
    @Binding var session: WorkoutSession?
    @Environment(LocalStore.self) private var store
    @Environment(CoachService.self) private var coach

    var body: some View {
        let unit = store.weightUnit
        let context = store.nextSessionContext()
        let recommendation = coach.isEnabled ? coach.current : nil
        let advised = coach.advice(for: day)
        let advice = advised?.output
        Section {
            Button {
                let started = WorkoutSession.start(day, of: template, store: store, advice: advice)
                if let advised {
                    coach.recordApplied(advised, to: started.workout.id)
                }
                session = started
            } label: {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(day.name(chinese: AppLanguage.isChinese))
                            .font(.headline)
                            .foregroundStyle(Color.primary)
                        if template.days.count > 1 {
                            Text(template.name(chinese: AppLanguage.isChinese))
                                .font(.subheadline)
                                .foregroundStyle(Color.secondary)
                        }
                    }
                    Spacer()
                    Text("Start")
                        .font(.subheadline.weight(.semibold))
                }
            }
            if context.shortNight {
                Label("You slept little last night, so no weight goes up today.", systemImage: "moon.zzz")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            CoachUpNextRow(recommendation: recommendation)
            ForEach(day.exercises) { item in
                if let suggestion = store.suggestion(for: item.exerciseId, template: item, context: context) {
                    let loadType = store.exercises[item.exerciseId]?.loadType ?? .total
                    let advised = advice?.advice(for: item.exerciseId)
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 8) {
                            Text(store.exerciseName(item.exerciseId))
                                .lineLimit(1)
                            Spacer()
                            Text(advised.flatMap { topSet($0, unit: unit, loadType: loadType) }
                                ?? suggestion.topSet(unit: unit, loadType: loadType)
                                ?? TemplateTarget(item: item).summary)
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                            Image(systemName: advised == nil ? suggestion.systemImage : "sparkles")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(advised == nil ? AnyShapeStyle(.secondary) : AnyShapeStyle(.tint))
                                .frame(width: 16)
                                .accessibilityHidden(true)
                        }
                        if let advised {
                            Text(advised.reason)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .font(.subheadline)
                }
            }
        } header: {
            Text("Up next")
        } footer: {
            if advice != nil {
                Text("Training guidance, not medical advice. Stop if something hurts.")
            } else {
                Text("Suggested from your last sessions. Each exercise says why once you start.")
            }
        }
    }

    /// The hardest of the coach's sets, as `NextSession.Suggestion.topSet` does.
    private func topSet(_ advised: CoachAdvice.Exercise, unit: WeightUnit, loadType: LoadType) -> String? {
        let sets = advised.sets.filter { $0.setType != .warmup }
        let byWeight: (CoachRequest.PlannedSet, CoachRequest.PlannedSet) -> Bool = { ($0.weightKg ?? 0) < ($1.weightKg ?? 0) }
        guard let top = loadType == .assisted ? sets.min(by: byWeight) : sets.max(by: byWeight) else { return nil }
        return unit.formatSet(WorkoutSet(reps: top.reps, weightKg: top.weightKg))
    }
}

private struct ActiveWorkoutRow: View {
    let workout: Workout

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(workout.title)
                    .font(.headline)
                    .foregroundStyle(.primary)
                Text("Started \(workout.startedAt, style: .relative) ago")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text("Resume")
                .font(.subheadline.weight(.semibold))
        }
    }
}

/// One line per workout: title, date and what was done.
struct WorkoutRow: View {
    let workout: Workout
    @Environment(LocalStore.self) private var store

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text(workout.title)
                    .font(.headline)
                Spacer()
                Text(workout.startedAt, format: .dateTime.weekday(.abbreviated).month(.abbreviated).day())
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Text(summary)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
    }

    private var summary: String {
        workout.exercises
            .map { "\(store.exerciseName($0.exerciseId)) × \($0.sets.count)" }
            .joined(separator: ", ")
    }
}

#Preview {
    TodayView()
        .environment(try! LocalStore(inMemory: true))
}
