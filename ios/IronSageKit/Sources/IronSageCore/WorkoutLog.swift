import Foundation

// Rules for logging a workout. M1 has no progression: new sets start from what the
// user did last time, and the coach (M3) will suggest changes.

extension Exercise {
    /// Multi-joint lifts get the longer rest. Without a field for it in the catalog, an
    /// exercise counts as compound when it trains three or more muscles, two primary
    /// ones (forearms aside), or the quads together with the glutes.
    public var isCompound: Bool {
        let all = Set(primaryMuscles + secondaryMuscles)
        let primary = Set(primaryMuscles).subtracting([.forearms])
        return all.count >= 3 || primary.count >= 2 || (primaryMuscles.contains(.quads) && all.contains(.glutes))
    }

    /// Three minutes for compound lifts, 90 seconds for isolation work.
    public var defaultRestSeconds: Int {
        isCompound ? 180 : 90
    }
}

public enum WorkoutLog {
    /// The sets of `exerciseID` from the most recent finished workout that has it,
    /// counting only workouts that started before `date`.
    public static func lastSets(of exerciseID: UUID, in history: [Workout], before date: Date = .distantFuture) -> [WorkoutSet]? {
        let previous = history
            .filter { !$0.isInProgress && $0.startedAt < date }
            .sorted { $0.startedAt > $1.startedAt }
        for workout in previous {
            let sets = workout.exercises
                .filter { $0.exerciseId == exerciseID }
                .flatMap(\.sets)
                .filter(\.isCompleted)
            if !sets.isEmpty {
                return sets
            }
        }
        return nil
    }

    /// The sets a new exercise starts with: last time's, not yet done; otherwise one
    /// empty working set.
    public static func plannedSets(for exerciseID: UUID, history: [Workout]) -> [WorkoutSet] {
        guard let last = lastSets(of: exerciseID, in: history) else {
            return [WorkoutSet()]
        }
        return last.map {
            WorkoutSet(setType: $0.setType, reps: $0.reps, weightKg: $0.weightKg, durationSeconds: $0.durationSeconds)
        }
    }

    /// The rest the user set for this exercise last time, or the default.
    public static func restSeconds(for exercise: Exercise, history: [Workout]) -> Int {
        let previous = history
            .filter { !$0.isInProgress }
            .sorted { $0.startedAt > $1.startedAt }
            .lazy
            .flatMap(\.exercises)
            .first { $0.exerciseId == exercise.id && $0.restSeconds != nil }
        return previous?.restSeconds ?? exercise.defaultRestSeconds
    }

    /// A new workout exercise with last time's sets and rest.
    public static func adding(_ exercise: Exercise, history: [Workout]) -> WorkoutExercise {
        WorkoutExercise(
            exerciseId: exercise.id,
            restSeconds: restSeconds(for: exercise, history: history),
            sets: plannedSets(for: exercise.id, history: history)
        )
    }

    /// Epley's formula, used only for 1–12 reps, where it is reasonably accurate.
    public static func estimatedOneRepMax(weightKg: Double, reps: Int) -> Double? {
        guard weightKg > 0, (1...12).contains(reps) else { return nil }
        return reps == 1 ? weightKg : weightKg * (1 + Double(reps) / 30)
    }

    /// Total weight moved in the workout's completed, non-warm-up sets. One dumbbell
    /// per side counts twice; assisted sets count nothing.
    public static func volumeKg(of workout: Workout, exercises: [UUID: Exercise]) -> Double {
        workout.exercises.reduce(0) { total, item in
            let factor: Double = switch exercises[item.exerciseId]?.loadType {
            case .perSide: 2
            case .assisted: 0
            default: 1
            }
            return total + item.sets
                .filter { $0.isCompleted && $0.setType != .warmup }
                .reduce(0) { $0 + ($1.weightKg ?? 0) * Double($1.reps ?? 0) * factor }
        }
    }

    public struct PersonalRecord: Hashable, Sendable {
        public enum Kind: Hashable, Sendable {
            case heaviestWeight, estimatedOneRepMax
        }

        public let exerciseID: UUID
        public let kind: Kind
        public let kilograms: Double
        public let previousKilograms: Double
    }

    /// Exercises where this workout beat every earlier one, by heaviest completed set or
    /// by estimated one-rep max. A first attempt sets no record: there is nothing to beat.
    public static func personalRecords(in workout: Workout, history: [Workout], exercises: [UUID: Exercise]) -> [PersonalRecord] {
        let earlier = history.filter { !$0.isInProgress && $0.id != workout.id && $0.startedAt < workout.startedAt }
        var records: [PersonalRecord] = []
        var seen: Set<UUID> = []
        for item in workout.exercises where seen.insert(item.exerciseId).inserted {
            guard exercises[item.exerciseId]?.loadType != .assisted else { continue }
            let now = best(of: item.exerciseId, in: [workout])
            let before = best(of: item.exerciseId, in: earlier)
            guard let now, let before else { continue }
            if now.weight > before.weight + 0.0005 {
                records.append(PersonalRecord(exerciseID: item.exerciseId, kind: .heaviestWeight, kilograms: now.weight, previousKilograms: before.weight))
            } else if let nowE1RM = now.e1rm, let beforeE1RM = before.e1rm, nowE1RM > beforeE1RM + 0.0005 {
                records.append(PersonalRecord(exerciseID: item.exerciseId, kind: .estimatedOneRepMax, kilograms: nowE1RM, previousKilograms: beforeE1RM))
            }
        }
        return records
    }

    private static func best(of exerciseID: UUID, in workouts: [Workout]) -> (weight: Double, e1rm: Double?)? {
        let sets = workouts
            .flatMap(\.exercises)
            .filter { $0.exerciseId == exerciseID }
            .flatMap(\.sets)
            .filter { $0.isCompleted && $0.setType != .warmup && ($0.weightKg ?? 0) > 0 }
        guard let heaviest = sets.compactMap(\.weightKg).max() else { return nil }
        let e1rm = sets.compactMap { set in set.reps.flatMap { estimatedOneRepMax(weightKg: set.weightKg ?? 0, reps: $0) } }.max()
        return (heaviest, e1rm)
    }
}

/// The countdown after a completed set.
public struct RestTimer: Equatable, Sendable {
    public let exerciseName: String
    public private(set) var endsAt: Date
    public private(set) var totalSeconds: Int

    public init(exerciseName: String, seconds: Int, from start: Date = .now) {
        self.exerciseName = exerciseName
        totalSeconds = seconds
        endsAt = start.addingTimeInterval(TimeInterval(seconds))
    }

    public func remaining(at date: Date = .now) -> TimeInterval {
        max(0, endsAt.timeIntervalSince(date))
    }

    public func isFinished(at date: Date = .now) -> Bool {
        remaining(at: date) <= 0
    }

    /// Adds (or with a negative number, takes away) time.
    public mutating func extend(by seconds: Int, at date: Date = .now) {
        let remaining = remaining(at: date) + TimeInterval(seconds)
        endsAt = date.addingTimeInterval(max(0, remaining))
        totalSeconds = max(0, totalSeconds + seconds)
    }
}

public enum WorkoutHistory {
    public struct Week: Identifiable, Hashable, Sendable {
        /// The first day of the week, at midnight, in the calendar used to group.
        public let start: Date
        /// Newest first.
        public let workouts: [Workout]
        public var id: Date { start }

        public var setCount: Int {
            workouts.reduce(0) { $0 + $1.exercises.reduce(0) { $0 + $1.sets.count } }
        }
    }

    /// Finished workouts by week, newest week first. Weeks start on the calendar's first
    /// weekday (Monday or Sunday, depending on the region).
    public static func weeks(_ workouts: [Workout], calendar: Calendar = .current) -> [Week] {
        let finished = workouts.filter { !$0.isInProgress }
        let grouped = Dictionary(grouping: finished) { workout in
            calendar.dateInterval(of: .weekOfYear, for: workout.startedAt)?.start ?? calendar.startOfDay(for: workout.startedAt)
        }
        return grouped
            .map { Week(start: $0.key, workouts: $0.value.sorted { $0.startedAt > $1.startedAt }) }
            .sorted { $0.start > $1.start }
    }
}

extension WorkoutLog {
    /// The exercises of a workout that follows a template day: the template's sets,
    /// with last time's weights and reps, or the bottom of the rep range the first time.
    public static func exercises(for day: TemplateDay, history: [Workout]) -> [WorkoutExercise] {
        day.exercises.map { item in
            let last = lastSets(of: item.exerciseId, in: history)?.filter { $0.setType != .warmup } ?? []
            let sets = item.sets.enumerated().map { index, target in
                let previous = last.isEmpty ? nil : last[min(index, last.count - 1)]
                return WorkoutSet(setType: target.setType, reps: previous?.reps ?? target.repMin, weightKg: previous?.weightKg)
            }
            return WorkoutExercise(
                exerciseId: item.exerciseId,
                supersetGroup: item.supersetGroup,
                restSeconds: item.restSeconds,
                sets: sets
            )
        }
    }

    /// A one-day template of the user's own from a finished workout: the same exercises
    /// and sets, each aiming for the reps done.
    public static func template(from workout: Workout, name: String) -> Template {
        let exercises = workout.exercises.compactMap { item -> TemplateExercise? in
            let sets = item.sets.filter(\.isCompleted).map {
                TemplateSet(setType: $0.setType, repMin: $0.reps, repMax: $0.reps, targetRir: $0.rir)
            }
            guard !sets.isEmpty else { return nil }
            return TemplateExercise(exerciseId: item.exerciseId, restSeconds: item.restSeconds, supersetGroup: item.supersetGroup, sets: sets)
        }
        return Template(nameEn: name, days: [TemplateDay(name: name, exercises: exercises)], isCustom: true)
    }
}
