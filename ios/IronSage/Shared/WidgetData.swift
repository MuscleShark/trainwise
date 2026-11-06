import Foundation
import IronSageCore
import IronSageStore
import WidgetKit

/// Writes what the home and lock screen widgets show (`WidgetSnapshot`) to the App Group
/// and reloads them when it changed. Called when the app goes to the background, after
/// a workout ends and after syncing, so the widgets are current whenever they're seen.
@MainActor
enum WidgetData {
    static func update(_ store: LocalStore, signedIn: Bool) {
        if WidgetStore.write(signedIn ? snapshot(store) : nil) {
            WidgetCenter.shared.reloadAllTimelines()
        }
    }

    static func snapshot(_ store: LocalStore, now: Date = .now) -> WidgetSnapshot {
        let chinese = AppLanguage.isChinese
        let unit = store.weightUnit
        // Training sessions, as on Me: a walk the Watch recorded on its own isn't one.
        let workouts = store.finishedWorkouts.filter { !Cardio.isCardioOnly($0, exercises: store.exercises) }
        let streak = TrainingProgress.weekStreak(in: workouts, now: now)

        var nextDay: String?
        var nextTemplate: String?
        var nextExercises: [String] = []
        var start: String?
        if let upNext = store.upNext {
            let day = upNext.day.name(chinese: chinese)
            nextDay = day
            nextTemplate = upNext.template.days.count > 1 ? upNext.template.name(chinese: chinese) : nil
            start = String(appLocalized: "Start \(day)")
            let context = store.nextSessionContext(at: now)
            nextExercises = upNext.day.exercises.prefix(3).compactMap { item in
                guard let exercise = store.exercises[item.exerciseId],
                      let suggestion = store.suggestion(for: item.exerciseId, template: item, context: context)
                else { return nil }
                let name = exercise.name(chinese: chinese)
                if exercise.isCardio, let set = suggestion.sets.first, set.durationSeconds != nil {
                    return "\(name) \(CardioText.summary(set, exercise: exercise, unit: unit))"
                }
                return suggestion.topSet(unit: unit, loadType: exercise.loadType).map { "\(name) \($0)" } ?? name
            }
        }

        var lastNight: String?
        if let day = ReadinessComparison.compare(store.readiness, on: HealthDays.key(now)) {
            let parts = [
                day.sleep.map { String(appLocalized: "Slept \(ReadinessCard.duration($0.value))") },
                day.hrv.map { String(appLocalized: "HRV \(ReadinessCard.milliseconds($0.value))") },
            ].compactMap(\.self)
            lastNight = parts.isEmpty ? nil : parts.joined(separator: " · ")
        }

        let week = Calendar.current.dateInterval(of: .weekOfYear, for: now)!
        let sets = TrainingProgress.weeklySets(in: store.finishedWorkouts, exercises: store.exercises, week: week)
        return WidgetSnapshot(
            nextDay: nextDay,
            nextTemplate: nextTemplate,
            nextExercises: nextExercises,
            weekDone: TrainingProgress.workoutsThisWeek(in: workouts, now: now),
            weekPlanned: store.profile?.trainingDaysPerWeek,
            streakWeeks: streak,
            lastNight: lastNight,
            muscles: sets.map { WidgetSnapshot.Muscle(name: String(appLocalized: $0.muscle.label), sets: $0.sets) },
            musclesScale: max(TrainingProgress.setsReference.upperBound, sets.first?.sets ?? 0),
            labels: WidgetSnapshot.Labels(
                nextWorkout: String(appLocalized: "Up next"),
                thisWeek: String(appLocalized: "This week"),
                streak: String(appLocalized: "\(streak) weeks in a row"),
                setsPerMuscle: String(appLocalized: "Sets per muscle"),
                start: start,
                noTemplate: String(appLocalized: "Start a workout from a template to see what's next.")
            )
        )
    }
}
