import Foundation
import IronSageCore
import IronSageStore
import UserNotifications

/// The workout being logged. Every change is saved to the phone at once, so closing
/// the app mid-workout loses nothing.
@MainActor
@Observable
final class WorkoutSession: Identifiable {
    private(set) var workout: Workout
    private(set) var restTimer: RestTimer?

    @ObservationIgnored private let store: LocalStore

    var id: UUID { workout.id }

    init(workout: Workout, store: LocalStore) {
        self.workout = workout
        self.store = store
    }

    /// Starts and saves a new workout.
    static func start(title: String = String(localized: "Workout"), exercises: [WorkoutExercise] = [], templateID: UUID? = nil, store: LocalStore) -> WorkoutSession {
        let workout = Workout(title: title, templateId: templateID, startedAt: .now, exercises: exercises)
        store.save(workout)
        return WorkoutSession(workout: workout, store: store)
    }

    func update(_ change: (inout Workout) -> Void) {
        change(&workout)
        // The title field may be empty while someone types; the API needs a name.
        var saved = workout
        if saved.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            saved.title = String(localized: "Workout")
        }
        store.save(saved)
    }

    func add(_ exercise: Exercise) {
        update { $0.exercises.append(WorkoutLog.adding(exercise, history: store.finishedWorkouts)) }
    }

    /// Marks a set done (or not done), starting the rest timer when it is done.
    func toggleCompleted(setID: UUID, in exerciseID: UUID) {
        guard let e = workout.exercises.firstIndex(where: { $0.id == exerciseID }),
              let s = workout.exercises[e].sets.firstIndex(where: { $0.id == setID })
        else { return }
        let completing = !workout.exercises[e].sets[s].isCompleted
        update { $0.exercises[e].sets[s].completedAt = completing ? .now : nil }
        if completing {
            let item = workout.exercises[e]
            let exercise = store.exercises[item.exerciseId]
            let seconds = item.restSeconds ?? exercise?.defaultRestSeconds ?? 120
            startRest(RestTimer(exerciseName: store.exerciseName(item.exerciseId), seconds: seconds))
        }
    }

    func addSet(to exerciseID: UUID) {
        update { workout in
            guard let e = workout.exercises.firstIndex(where: { $0.id == exerciseID }) else { return }
            let last = workout.exercises[e].sets.last
            workout.exercises[e].sets.append(WorkoutSet(
                setType: last?.setType == .warmup ? .working : (last?.setType ?? .working),
                reps: last?.reps,
                weightKg: last?.weightKg
            ))
        }
    }

    // MARK: Rest

    func extendRest(by seconds: Int) {
        guard var timer = restTimer else { return }
        timer.extend(by: seconds)
        startRest(timer)
    }

    func skipRest() {
        restTimer = nil
        RestNotifications.cancel()
    }

    private func startRest(_ timer: RestTimer) {
        restTimer = timer
        RestNotifications.schedule(for: timer)
    }

    // MARK: End

    /// Ends the workout, dropping sets that were never done and exercises left empty.
    func finish() {
        skipRest()
        update { workout in
            workout.endedAt = .now
            for index in workout.exercises.indices {
                workout.exercises[index].sets.removeAll { !$0.isCompleted }
            }
            workout.exercises.removeAll { $0.sets.isEmpty }
        }
    }

    func discard() {
        skipRest()
        store.deleteWorkout(id: workout.id)
    }

    var hasUnfinishedSets: Bool {
        workout.exercises.contains { $0.sets.contains { !$0.isCompleted } }
    }

    var hasCompletedSets: Bool {
        workout.exercises.contains { $0.sets.contains(where: \.isCompleted) }
    }
}

/// A notification when rest is over, so it reaches a locked phone.
enum RestNotifications {
    private static let id = "rest-timer"

    static func schedule(for timer: RestTimer) {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [id])
        let seconds = timer.remaining()
        guard seconds > 1 else { return }
        Task {
            guard (try? await center.requestAuthorization(options: [.alert, .sound])) == true else { return }
            let content = UNMutableNotificationContent()
            content.title = String(localized: "Rest is over")
            content.body = String(localized: "Next set: \(timer.exerciseName)")
            content.sound = .default
            let trigger = UNTimeIntervalNotificationTrigger(timeInterval: seconds, repeats: false)
            try? await center.add(UNNotificationRequest(identifier: id, content: content, trigger: trigger))
        }
    }

    static func cancel() {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [id])
    }
}
