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
    /// The next day of the template followed most recently.
    private var upNext: (template: Template, day: TemplateDay)? {
        for workout in store.finishedWorkouts {
            guard let id = workout.templateId else { continue }
            // A deleted template: look at the workout before.
            guard let template = store.templates.first(where: { $0.id == id }),
                  let day = NextSession.nextDay(of: template, history: store.finishedWorkouts)
            else { continue }
            return (template, day)
        }
        return nil
    }
}

/// The template day due next, with each exercise's suggested top set.
private struct UpNextSection: View {
    let template: Template
    let day: TemplateDay
    @Binding var session: WorkoutSession?
    @Environment(LocalStore.self) private var store

    var body: some View {
        let unit = store.weightUnit
        let context = store.nextSessionContext()
        Section {
            Button {
                session = WorkoutSession.start(day, of: template, store: store)
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
            ForEach(day.exercises) { item in
                if let suggestion = store.suggestion(for: item.exerciseId, template: item, context: context) {
                    HStack(spacing: 8) {
                        Text(store.exerciseName(item.exerciseId))
                            .lineLimit(1)
                        Spacer()
                        Text(suggestion.topSet(unit: unit, loadType: store.exercises[item.exerciseId]?.loadType ?? .total) ?? TemplateTarget(item: item).summary)
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                        Image(systemName: suggestion.systemImage)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .frame(width: 16)
                            .accessibilityHidden(true)
                    }
                    .font(.subheadline)
                }
            }
        } header: {
            Text("Up next")
        } footer: {
            Text("Suggested from your last sessions. Each exercise says why once you start.")
        }
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
