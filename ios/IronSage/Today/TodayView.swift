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
                        Text("Add exercises as you go. Each set starts from what you did last time.")
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
