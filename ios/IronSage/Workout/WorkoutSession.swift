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
    /// Each exercise's suggestion, worked out once: it explains how the sets were
    /// planned, so it shouldn't change while they are logged.
    @ObservationIgnored private var suggestions: [UUID: NextSession.Suggestion] = [:]
    /// The workout before editing started; only set when editing a finished workout.
    @ObservationIgnored private let original: Workout?

    var id: UUID { workout.id }

    /// Editing a finished workout from History rather than logging one.
    var isEditing: Bool { original != nil }

    init(workout: Workout, store: LocalStore) {
        self.workout = workout
        self.store = store
        original = workout.isInProgress ? nil : workout
    }

    /// Starts and saves a new workout.
    static func start(title: String = String(localized: "Workout"), exercises: [WorkoutExercise] = [], templateID: UUID? = nil, store: LocalStore) -> WorkoutSession {
        let workout = Workout(title: title, templateId: templateID, startedAt: .now, exercises: exercises)
        store.save(workout)
        return WorkoutSession(workout: workout, store: store)
    }

    /// Why an exercise's sets were planned as they are; nil when editing a finished
    /// workout or when the exercise was removed from the catalog.
    func suggestion(for item: WorkoutExercise, template: TemplateExercise?) -> NextSession.Suggestion? {
        guard !isEditing else { return nil }
        if let cached = suggestions[item.id] { return cached }
        let context = store.nextSessionContext(at: workout.startedAt, before: workout.startedAt)
        let suggestion = store.suggestion(for: item.exerciseId, template: template, context: context)
        suggestions[item.id] = suggestion
        return suggestion
    }

    /// Starts a workout that follows a template day, with the suggested sets, adjusted
    /// by the AI coach's advice when there is some for this day.
    static func start(_ day: TemplateDay, of template: Template, store: LocalStore, advice: CoachAdvice? = nil) -> WorkoutSession {
        let planned = WorkoutLog.exercises(for: day, exercises: store.exercises, context: store.nextSessionContext())
        let title = template.days.count > 1
            ? "\(template.name(chinese: AppLanguage.isChinese)) · \(day.name(chinese: AppLanguage.isChinese))"
            : template.name(chinese: AppLanguage.isChinese)
        return start(
            title: String(title.prefix(120)),
            exercises: advice.map { Coach.applying($0, to: planned) } ?? planned,
            templateID: template.id,
            store: store
        )
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
        let context = store.nextSessionContext(at: workout.startedAt, before: workout.startedAt)
        update { $0.exercises.append(WorkoutLog.adding(exercise, context: context)) }
    }

    /// Marks a set done (or not done), starting the rest timer when it is done.
    func toggleCompleted(setID: UUID, in exerciseID: UUID) {
        guard let e = workout.exercises.firstIndex(where: { $0.id == exerciseID }),
              let s = workout.exercises[e].sets.firstIndex(where: { $0.id == setID })
        else { return }
        let completing = !workout.exercises[e].sets[s].isCompleted
        let completedAt = isEditing ? workout.endedAt : .now
        update { $0.exercises[e].sets[s].completedAt = completing ? completedAt : nil }
        if completing && !isEditing {
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

    /// Ends editing a finished workout: sets with reps count as done, empty ones go.
    func saveEdits() {
        update { workout in
            let endedAt = workout.endedAt
            for e in workout.exercises.indices {
                workout.exercises[e].sets = workout.exercises[e].sets.compactMap { set in
                    if set.isCompleted { return set }
                    guard set.reps != nil else { return nil }
                    var done = set
                    done.completedAt = endedAt
                    return done
                }
            }
            workout.exercises.removeAll { $0.sets.isEmpty }
        }
    }

    /// Undoes everything since editing started.
    func revertEdits() {
        guard let original else { return }
        workout = original
        store.save(original)
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
