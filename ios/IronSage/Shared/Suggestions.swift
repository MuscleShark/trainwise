import Foundation
import IronSageCore
import IronSageStore

extension LocalStore {
    /// What the next-session rules need for a workout that starts at `date`. When
    /// editing or resuming a workout, pass its start as `before` so only earlier
    /// workouts count.
    func nextSessionContext(at date: Date = .now, before: Date = .distantFuture) -> NextSession.Context {
        NextSession.Context(
            history: finishedWorkouts,
            goal: profile?.goal,
            unit: weightUnit,
            shortNight: NextSession.isShortNight(readiness, on: HealthDays.key(date)),
            before: before
        )
    }

    /// The next day of the template followed most recently.
    var upNext: (template: Template, day: TemplateDay)? {
        let hidden = Set(profile?.hiddenTemplateIds ?? [])
        for workout in finishedWorkouts {
            guard let id = workout.templateId, !hidden.contains(id) else { continue }
            // A deleted or hidden template: look at the workout before.
            guard let template = templates.first(where: { $0.id == id }),
                  let day = NextSession.nextDay(of: template, history: finishedWorkouts)
            else { continue }
            return (template, day)
        }
        return nil
    }

    /// The suggestion for one exercise; nil when it was removed from the catalog.
    func suggestion(for exerciseID: UUID, template: TemplateExercise?, context: NextSession.Context) -> NextSession.Suggestion? {
        exercises[exerciseID].map { NextSession.suggest($0, template: template, context: context) }
    }
}

extension Template {
    /// The day a workout followed, found by the day's name at the end of its title in
    /// either language; a one-day template has only one.
    func day(of workout: Workout) -> TemplateDay? {
        guard workout.templateId == id else { return nil }
        if days.count == 1 { return days[0] }
        return days.last { day in [day.name, day.nameZh].compactMap { $0 }.contains { workout.title.hasSuffix($0) } }
    }
}

extension NextSession.Suggestion {
    /// Why the sets look the way they do, in one line.
    func reason(unit: WeightUnit) -> String {
        switch change {
        case .firstTime:
            String(appLocalized: "First time: choose a weight that leaves 1–3 reps in reserve.")
        case let .increase(_, to):
            String(appLocalized: "Every set reached \(range.max) reps, so \(unit.formatWithUnit(kilograms: to)) this time.")
        case .addReps:
            String(appLocalized: "Same weight. Aim for one more rep per set, up to \(range.max).")
        case .repeatWeight:
            String(appLocalized: "Same weight until every set reaches \(range.min) reps.")
        case let .decrease(_, to):
            String(appLocalized: "Every set was under \(range.min) reps, so \(unit.formatWithUnit(kilograms: to)) this time.")
        case let .deload(_, to):
            String(appLocalized: "Missed \(range.min) reps two sessions running, so \(unit.formatWithUnit(kilograms: to)) to build back up.")
        case .heldForSleep:
            String(appLocalized: "Ready for more weight, but you slept little last night. Same weight today.")
        case .addLoadOrVariation:
            String(appLocalized: "Top of the range: add weight or try a harder variation.")
        case .cardio(firstTime: true):
            String(appLocalized: "First time: log what you did.")
        case .cardio(firstTime: false):
            String(appLocalized: "Same as last time. Cardio isn't stepped up the way sets are.")
        }
    }

    var systemImage: String {
        switch change {
        case .firstTime: "flag"
        case .increase: "arrow.up"
        case .addReps: "plus"
        case .repeatWeight: "equal"
        case .decrease, .deload: "arrow.down"
        case .heldForSleep: "moon.zzz"
        case .addLoadOrVariation: "arrow.up.right"
        case .cardio(let firstTime): firstTime ? "flag" : "equal"
        }
    }

    static var stallNote: String {
        String(appLocalized: "No progress in the last \(NextSession.stallSessions) sessions. Consider a different rep range or exercise.")
    }

    /// The hardest planned working set, "62.5 kg × 5", for short summaries: the
    /// heaviest, or for an assisted exercise the one with the least assistance.
    func topSet(unit: WeightUnit, loadType: LoadType) -> String? {
        let working = sets.filter { $0.setType != .warmup }
        let byWeight: (WorkoutSet, WorkoutSet) -> Bool = { ($0.weightKg ?? 0) < ($1.weightKg ?? 0) }
        guard let top = loadType == .assisted ? working.min(by: byWeight) : working.max(by: byWeight) else { return nil }
        return unit.formatSet(top)
    }
}
