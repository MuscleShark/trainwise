import Foundation

/// Training across weeks: sets per muscle and volume.
public enum TrainingProgress {
    /// A weekly set count where most people grow, used as a light reference on the chart.
    public static let setsReference: ClosedRange<Double> = 10...20

    /// Completed working sets per muscle in the given week. A set counts 1 for each
    /// primary muscle of its exercise and 0.5 for each secondary one. Most sets first.
    public static func weeklySets(
        in workouts: [Workout],
        exercises: [UUID: Exercise],
        week: DateInterval
    ) -> [(muscle: Muscle, sets: Double)] {
        var sets: [Muscle: Double] = [:]
        for workout in workouts where !workout.isInProgress && week.contains(workout.startedAt) && workout.startedAt < week.end {
            for item in workout.exercises {
                guard let exercise = exercises[item.exerciseId] else { continue }
                let done = Double(item.sets.filter { $0.isCompleted && $0.setType != .warmup }.count)
                guard done > 0 else { continue }
                for muscle in exercise.primaryMuscles {
                    sets[muscle, default: 0] += done
                }
                for muscle in exercise.secondaryMuscles where !exercise.primaryMuscles.contains(muscle) {
                    sets[muscle, default: 0] += done / 2
                }
            }
        }
        return sets
            .map { (muscle: $0.key, sets: $0.value) }
            .sorted { $0.sets != $1.sets ? $0.sets > $1.sets : Muscle.allCases.firstIndex(of: $0.muscle)! < Muscle.allCases.firstIndex(of: $1.muscle)! }
    }

    /// Volume of each of the last `count` weeks, oldest first, including weeks without
    /// training. The last one is the week containing `now`.
    public static func weeklyVolume(
        in workouts: [Workout],
        exercises: [UUID: Exercise],
        weeks count: Int,
        now: Date = .now,
        calendar: Calendar = .current
    ) -> [(start: Date, kilograms: Double)] {
        guard count > 0, let current = calendar.dateInterval(of: .weekOfYear, for: now)?.start else { return [] }
        let starts = (0..<count).reversed().compactMap { calendar.date(byAdding: .weekOfYear, value: -$0, to: current) }
        var volume: [Date: Double] = [:]
        for workout in workouts where !workout.isInProgress {
            guard let start = calendar.dateInterval(of: .weekOfYear, for: workout.startedAt)?.start else { continue }
            volume[start, default: 0] += WorkoutLog.volumeKg(of: workout, exercises: exercises)
        }
        return starts.map { ($0, volume[$0] ?? 0) }
    }

    /// The exercises done in finished workouts, most recently done first; within one
    /// workout, in the order they were done.
    public static func recentExercises(in workouts: [Workout]) -> [UUID] {
        var seen: Set<UUID> = []
        var order: [UUID] = []
        for workout in workouts.filter({ !$0.isInProgress }).sorted(by: { $0.startedAt > $1.startedAt }) {
            for item in workout.exercises where item.sets.contains(where: \.isCompleted) && seen.insert(item.exerciseId).inserted {
                order.append(item.exerciseId)
            }
        }
        return order
    }
}

/// The user's body weight, and whether it can be used as it is.
public enum BodyWeight {
    /// The most recent weight, from any source.
    public static func latest(_ measurements: [BodyMeasurement]) -> BodyMeasurement? {
        measurements.filter { $0.kind == .weight }.max { $0.measuredAt < $1.measuredAt }
    }

    /// Weights in the last `days` days, oldest first.
    public static func trend(_ measurements: [BodyMeasurement], days: Int, now: Date = .now) -> [BodyMeasurement] {
        let since = now.addingTimeInterval(-Double(days) * 86_400)
        return measurements
            .filter { $0.kind == .weight && $0.measuredAt >= since }
            .sorted { $0.measuredAt < $1.measuredAt }
    }

    /// A weight from Apple Health is only used once the user says it is still current;
    /// one they typed in is current already.
    public static func needsConfirmation(_ latest: BodyMeasurement, confirmed: Set<UUID>) -> Bool {
        latest.source == .healthkit && !confirmed.contains(latest.id)
    }
}
