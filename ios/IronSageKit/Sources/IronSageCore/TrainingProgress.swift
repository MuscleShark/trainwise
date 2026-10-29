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

    /// Finished workouts in the week containing `now`.
    public static func workoutsThisWeek(
        in workouts: [Workout],
        now: Date = .now,
        calendar: Calendar = .current
    ) -> Int {
        guard let week = calendar.dateInterval(of: .weekOfYear, for: now) else { return 0 }
        return workouts.filter { !$0.isInProgress && week.contains($0.startedAt) && $0.startedAt < week.end }.count
    }

    /// Weeks in a row with at least one finished workout, counted back from the week
    /// containing `now`. This week counts once trained in; until then, the streak runs
    /// up to last week, so it only breaks when a whole week passes without training.
    public static func weekStreak(
        in workouts: [Workout],
        now: Date = .now,
        calendar: Calendar = .current
    ) -> Int {
        let trained = Set(workouts.filter { !$0.isInProgress }.compactMap {
            calendar.dateInterval(of: .weekOfYear, for: $0.startedAt)?.start
        })
        guard var week = calendar.dateInterval(of: .weekOfYear, for: now)?.start else { return 0 }
        if !trained.contains(week), let previous = calendar.date(byAdding: .weekOfYear, value: -1, to: week) {
            week = previous
        }
        var streak = 0
        while trained.contains(week), let previous = calendar.date(byAdding: .weekOfYear, value: -1, to: week) {
            streak += 1
            week = previous
        }
        return streak
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

/// Body measurements over a chosen period, for the body weight and body fat charts.
public enum BodyTrend {
    public enum Range: String, CaseIterable, Hashable, Sendable {
        case week, month, year, all

        /// The first moment shown, or nil for everything.
        public func start(now: Date = .now, calendar: Calendar = .current) -> Date? {
            switch self {
            case .week: calendar.date(byAdding: .day, value: -7, to: now)
            case .month: calendar.date(byAdding: .month, value: -1, to: now)
            case .year: calendar.date(byAdding: .year, value: -1, to: now)
            case .all: nil
            }
        }
    }

    public struct Point: Hashable, Sendable {
        public let date: Date
        public let value: Double

        public init(date: Date, value: Double) {
            self.date = date
            self.value = value
        }
    }

    /// Measurements spread over more than this many days are averaged per week, so a
    /// year of daily weigh-ins stays a readable line.
    public static let weeklyAfterDays = 120

    /// The most recent measurement of one kind, from any source.
    public static func latest(_ measurements: [BodyMeasurement], kind: MeasurementKind) -> BodyMeasurement? {
        measurements.filter { $0.kind == kind }.max { $0.measuredAt < $1.measuredAt }
    }

    /// The measurements of one kind in the range, oldest first; one per week (the week's
    /// average, at the average time) once they span more than `weeklyAfterDays` days.
    public static func points(
        _ measurements: [BodyMeasurement],
        kind: MeasurementKind,
        range: Range,
        now: Date = .now,
        calendar: Calendar = .current
    ) -> [Point] {
        let start = range.start(now: now, calendar: calendar)
        let shown = measurements
            .filter { $0.kind == kind && $0.measuredAt <= now && $0.measuredAt >= (start ?? .distantPast) }
            .sorted { $0.measuredAt < $1.measuredAt }
        guard let first = shown.first, let last = shown.last else { return [] }
        let points = shown.map { Point(date: $0.measuredAt, value: $0.value) }
        guard last.measuredAt.timeIntervalSince(first.measuredAt) > Double(weeklyAfterDays) * 86_400 else { return points }

        var weeks: [Date: [Point]] = [:]
        for point in points {
            guard let week = calendar.dateInterval(of: .weekOfYear, for: point.date)?.start else { continue }
            weeks[week, default: []].append(point)
        }
        return weeks.keys.sorted().map { week in
            let inWeek = weeks[week]!
            let time = inWeek.map(\.date.timeIntervalSince1970).reduce(0, +) / Double(inWeek.count)
            return Point(date: Date(timeIntervalSince1970: time), value: inWeek.map(\.value).reduce(0, +) / Double(inWeek.count))
        }
    }
}

/// Body fat in percent.
public enum BodyFat {
    /// What a typed-in body fat can be.
    public static let plausible: ClosedRange<Double> = 2...70
}
