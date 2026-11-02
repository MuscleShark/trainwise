import Foundation

/// Cardio: a session on a machine or outside, logged as one set with the time and the
/// machine's own numbers. It isn't stepped up like sets (docs/coaching.md): the next
/// time starts from what was done last time.
public enum Cardio {
    /// The WHO guideline for adults: 150 to 300 minutes of moderate cardio a week.
    public static let weeklyMinutesReference: ClosedRange<Int> = 150...300

    /// The next session's planned set: last time's time and machine settings (not the
    /// distance, which follows from them), or the template's targets the first time.
    public static func suggestion(_ exercise: Exercise, template: TemplateExercise?, context: NextSession.Context) -> NextSession.Suggestion {
        let last = WorkoutLog.lastSets(of: exercise.id, in: context.history, before: context.before)?.last
        let target = template?.sets.first
        let set = WorkoutSet(
            durationSeconds: last?.durationSeconds ?? target?.durationSeconds,
            speedKmh: last?.speedKmh ?? target?.speedKmh,
            inclinePct: last?.inclinePct ?? target?.inclinePct,
            level: last?.level ?? target?.level
        )
        return NextSession.Suggestion(
            exerciseID: exercise.id,
            sets: [set],
            change: .cardio(firstTime: last == nil),
            range: NextSession.RepRange(0, 0),
            isStalled: false
        )
    }

    /// Minutes of completed cardio in each of the last `count` weeks, oldest first,
    /// including weeks without any. The last one is the week containing `now`.
    public static func weeklyMinutes(
        in workouts: [Workout],
        exercises: [UUID: Exercise],
        weeks count: Int,
        now: Date = .now,
        calendar: Calendar = .current
    ) -> [(start: Date, minutes: Int)] {
        guard count > 0, let current = calendar.dateInterval(of: .weekOfYear, for: now)?.start else { return [] }
        let starts = (0..<count).reversed().compactMap { calendar.date(byAdding: .weekOfYear, value: -$0, to: current) }
        var seconds: [Date: Int] = [:]
        for session in sessions(in: workouts, exercises: exercises) {
            guard let start = calendar.dateInterval(of: .weekOfYear, for: session.date)?.start else { continue }
            seconds[start, default: 0] += session.done.durationSeconds ?? 0
        }
        return starts.map { ($0, Int((Double(seconds[$0] ?? 0) / 60).rounded())) }
    }

    /// One completed cardio session.
    public struct Session: Identifiable, Hashable, Sendable {
        public let workoutID: UUID
        public let exerciseID: UUID
        public let done: WorkoutSet
        public let date: Date
        public var id: UUID { done.id }
    }

    /// Completed cardio in finished workouts, newest first.
    public static func sessions(in workouts: [Workout], exercises: [UUID: Exercise], from start: Date = .distantPast) -> [Session] {
        workouts
            .filter { !$0.isInProgress && $0.startedAt >= start }
            .flatMap { workout in
                workout.exercises
                    .filter { exercises[$0.exerciseId]?.isCardio == true }
                    .flatMap { item in
                        item.sets.filter(\.isCompleted).map {
                            Session(workoutID: workout.id, exerciseID: item.exerciseId, done: $0, date: $0.completedAt ?? workout.startedAt)
                        }
                    }
            }
            .sorted { $0.date > $1.date }
    }

    /// True when a workout is only cardio, like a run the Watch recorded.
    public static func isCardioOnly(_ workout: Workout, exercises: [UUID: Exercise]) -> Bool {
        !workout.exercises.isEmpty && workout.exercises.allSatisfy { exercises[$0.exerciseId]?.isCardio == true }
    }
}

/// Distance and speed in the user's units: miles and mph with pounds, otherwise
/// kilometers and km/h. Stored as meters and km/h, rounded to what the API keeps.
public enum CardioUnits {
    public static let metersPerMile = 1609.344

    public static func distance(fromMeters meters: Double, unit: WeightUnit) -> Double {
        unit == .lb ? meters / metersPerMile : meters / 1000
    }

    public static func meters(fromDistance value: Double, unit: WeightUnit) -> Double {
        rounded(unit == .lb ? value * metersPerMile : value * 1000, places: 2)
    }

    public static func speed(fromKmh kmh: Double, unit: WeightUnit) -> Double {
        unit == .lb ? kmh * 1000 / metersPerMile : kmh
    }

    public static func kmh(fromSpeed value: Double, unit: WeightUnit) -> Double {
        rounded(unit == .lb ? value * metersPerMile / 1000 : value, places: 2)
    }

    public static func incline(_ value: Double) -> Double {
        rounded(value, places: 1)
    }

    static func rounded(_ value: Double, places: Int) -> Double {
        let scale = pow(10, Double(places))
        return (value * scale).rounded() / scale
    }
}
