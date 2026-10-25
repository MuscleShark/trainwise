import Foundation

/// One exercise across all finished workouts: each session, and the personal records.
public enum ExerciseProgress {
    /// The exercise in one workout: its completed working sets and their best.
    public struct Session: Identifiable, Hashable, Sendable {
        public var id: UUID { workoutID }
        public let workoutID: UUID
        public let date: Date
        public let sets: [WorkoutSet]
        /// Best estimated one-rep max of the session; nil when no set had 1–12 reps with weight.
        public let estimatedOneRepMax: Double?
        public let heaviestKg: Double?
    }

    public struct Lift: Hashable, Sendable {
        public let weightKg: Double
        public let reps: Int
        public let date: Date
    }

    public struct Records: Hashable, Sendable {
        /// The heaviest completed set (the most reps when several share that weight).
        public var heaviest: Lift?
        /// The set with the best estimated one-rep max, and that estimate.
        public var bestEstimate: Lift?
        public var bestEstimateKg: Double?
        /// The most reps done at each weight, hardest first: the heaviest weight, or for an
        /// assisted exercise the least assistance. Weight 0 is body weight.
        public var mostReps: [Lift] = []

        public var isEmpty: Bool { heaviest == nil && mostReps.isEmpty }
    }

    /// Sessions with at least one completed working set, newest first.
    public static func sessions(of exerciseID: UUID, in workouts: [Workout]) -> [Session] {
        workouts
            .filter { !$0.isInProgress }
            .compactMap { workout -> Session? in
                let sets = workout.exercises
                    .filter { $0.exerciseId == exerciseID }
                    .flatMap(\.sets)
                    .filter { $0.isCompleted && $0.setType != .warmup && ($0.reps ?? 0) > 0 }
                guard !sets.isEmpty else { return nil }
                let estimate = sets.compactMap { set in
                    WorkoutLog.estimatedOneRepMax(weightKg: set.weightKg ?? 0, reps: set.reps ?? 0)
                }.max()
                let heaviest = sets.compactMap(\.weightKg).filter { $0 > 0 }.max()
                return Session(workoutID: workout.id, date: workout.startedAt, sets: sets, estimatedOneRepMax: estimate, heaviestKg: heaviest)
            }
            .sorted { $0.date > $1.date }
    }

    /// The records over all sessions. Ties keep the earliest, the day the record was set.
    /// Assisted exercises get no weight records, since less assistance is the harder set;
    /// their most reps are kept per assistance weight.
    public static func records(_ sessions: [Session], loadType: LoadType, mostRepsLimit: Int = 6) -> Records {
        var records = Records()
        var mostReps: [Double: Lift] = [:]
        for session in sessions.sorted(by: { $0.date < $1.date }) {
            for set in session.sets {
                let reps = set.reps ?? 0
                let weight = max(set.weightKg ?? 0, 0)
                // Weights are kept to the gram, so 60 and 60.0001 count as one weight.
                let key = (weight * 1000).rounded() / 1000
                let lift = Lift(weightKg: key, reps: reps, date: session.date)
                if reps > mostReps[key]?.reps ?? 0 {
                    mostReps[key] = lift
                }
                guard loadType != .assisted, weight > 0 else { continue }
                if let best = records.heaviest {
                    if key > best.weightKg || (key == best.weightKg && reps > best.reps) {
                        records.heaviest = lift
                    }
                } else {
                    records.heaviest = lift
                }
                if let estimate = WorkoutLog.estimatedOneRepMax(weightKg: weight, reps: reps),
                   estimate > (records.bestEstimateKg ?? 0) + 0.0005 {
                    records.bestEstimate = lift
                    records.bestEstimateKg = estimate
                }
            }
        }
        records.mostReps = mostReps.values
            .sorted { loadType == .assisted ? $0.weightKg < $1.weightKg : $0.weightKg > $1.weightKg }
            .prefix(mostRepsLimit)
            .map { $0 }
        return records
    }
}
