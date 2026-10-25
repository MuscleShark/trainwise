import Foundation

/// The next session's weights and reps for an exercise, from the progression rules in
/// docs/coaching.md. Deterministic and offline; the AI coach (later in M3) only adjusts
/// and explains what these rules suggest.
public enum NextSession {
    /// What the rules look at besides the exercise itself.
    public struct Context: Sendable {
        /// Finished and in-progress workouts; only finished ones before `before` count.
        public var history: [Workout]
        public var goal: Goal?
        public var unit: WeightUnit
        /// Last night was short (see `isShortNight`): no weight goes up.
        public var shortNight: Bool
        /// Only workouts that started before this count, so editing an old workout
        /// compares it with what came before it.
        public var before: Date

        public init(history: [Workout], goal: Goal? = nil, unit: WeightUnit = .kg, shortNight: Bool = false, before: Date = .distantFuture) {
            self.history = history
            self.goal = goal
            self.unit = unit
            self.shortNight = shortNight
            self.before = before
        }
    }

    /// The reps to aim for on working sets.
    public struct RepRange: Hashable, Sendable {
        public let min: Int
        public let max: Int

        public init(_ min: Int, _ max: Int) {
            self.min = min
            self.max = Swift.max(min, max)
        }

        /// Fixed reps (5 × 5): linear progression. A range: double progression.
        public var isFixed: Bool { min == max }
    }

    public enum Change: Hashable, Sendable {
        /// No earlier sets of this exercise.
        case firstTime
        /// Every working set reached the top of the range: more weight, reps back to the bottom.
        case increase(fromKg: Double, toKg: Double)
        /// The same weight, one more rep on sets below the top of the range.
        case addReps
        /// Fixed reps were missed: the same weight until every set reaches them.
        case repeatWeight
        /// Every working set fell short of the bottom of the range: a step lighter.
        case decrease(fromKg: Double, toKg: Double)
        /// Fixed reps were missed two sessions in a row at the same weight: about 10%
        /// lighter, to build back up.
        case deload(fromKg: Double, toKg: Double)
        /// The weight would have gone up, but last night was short.
        case heldForSleep
        /// The top of the range without weight to add (body weight): add weight or a
        /// harder variation.
        case addLoadOrVariation
    }

    public struct Suggestion: Hashable, Sendable {
        public let exerciseID: UUID
        /// Planned sets, not done yet.
        public let sets: [WorkoutSet]
        public let change: Change
        public let range: RepRange
        /// No estimated one-rep max progress in the last three sessions.
        public let isStalled: Bool
    }

    /// Sessions without progress before an exercise counts as stalled.
    public static let stallSessions = 3

    /// Never more than this share added in one step (the smallest plate step aside).
    public static let maxIncrease = 0.10

    /// The suggestion for an exercise, following its template sets when there are some.
    /// Each template set keeps its own rep target, so a template saved from a workout
    /// with 8, 7 and 6 reps progresses each set from its own reps.
    public static func suggest(_ exercise: Exercise, template: TemplateExercise? = nil, context: Context) -> Suggestion {
        let targets = template?.sets ?? []
        let workingTargets = targets.filter { $0.setType != .warmup }
        let last = WorkoutLog.lastSets(of: exercise.id, in: context.history, before: context.before)
        let warmups = last?.filter { $0.setType == .warmup } ?? []
        let working = last?.filter { $0.setType != .warmup } ?? []

        let fallback = defaultRange(for: exercise, goal: context.goal, lastReps: working.compactMap(\.reps).min())
        let ranges = workingTargets.map { set -> RepRange in
            guard let min = set.repMin ?? set.repMax else { return fallback }
            return RepRange(min, set.repMax ?? min)
        }
        func range(at index: Int) -> RepRange {
            ranges.isEmpty ? fallback : ranges[Swift.min(index, ranges.count - 1)]
        }
        func targetRir(at index: Int) -> Int? {
            workingTargets.isEmpty ? nil : workingTargets[Swift.min(index, workingTargets.count - 1)].targetRir
        }

        guard last != nil else {
            var index = 0
            let sets = targets.isEmpty
                ? [WorkoutSet()]
                : targets.map { target -> WorkoutSet in
                    guard target.setType != .warmup else { return WorkoutSet(setType: .warmup) }
                    defer { index += 1 }
                    return WorkoutSet(setType: target.setType, reps: range(at: index).min)
                }
            return Suggestion(exerciseID: exercise.id, sets: sets, change: .firstTime, range: range(at: 0), isStalled: false)
        }

        let earlier = last.flatMap { _ in previousSession(of: exercise.id, context: context) }
        let change = decide(exercise, working: working, earlier: earlier, range: range(at:), targetRir: targetRir(at:), context: context)

        // Each planned set follows the set at the same place last time, so pyramids and
        // back-off sets keep their shape.
        var sets: [WorkoutSet] = []
        let plan: [SetType] = targets.isEmpty ? (last ?? []).map(\.setType) : targets.map(\.setType)
        var warmupIndex = 0
        var workingIndex = 0
        for type in plan {
            if type == .warmup {
                let previous = warmups.isEmpty ? nil : warmups[Swift.min(warmupIndex, warmups.count - 1)]
                sets.append(WorkoutSet(setType: .warmup, reps: previous?.reps, weightKg: previous?.weightKg))
                warmupIndex += 1
                continue
            }
            if working.isEmpty {
                sets.append(WorkoutSet(setType: type, reps: range(at: workingIndex).min))
            } else {
                let previous = working[Swift.min(workingIndex, working.count - 1)]
                sets.append(plannedSet(type, after: previous, change: change, range: range(at: workingIndex)))
            }
            workingIndex += 1
        }
        return Suggestion(
            exerciseID: exercise.id,
            sets: sets,
            change: change,
            range: range(at: 0),
            isStalled: isStalled(exercise.id, history: context.history, before: context.before)
        )
    }

    /// A rep range for exercises without a template: 3–6 for compound lifts when the goal
    /// is strength, 6–10 for other compound lifts, 10–15 for isolation work. Someone who
    /// trains outside it keeps their own reps, as a range of two from the fewest done.
    public static func defaultRange(for exercise: Exercise, goal: Goal?, lastReps: Int? = nil) -> RepRange {
        let range = exercise.isCompound
            ? (goal == .strength ? RepRange(3, 6) : RepRange(6, 10))
            : RepRange(10, 15)
        if let reps = lastReps, reps > 0, !(range.min...range.max).contains(reps) {
            return RepRange(reps, reps + 2)
        }
        return range
    }

    /// A short night: under six hours of sleep, or an hour or more below the user's
    /// usual. HRV and resting heart rate alone never change the plan (coaching.md).
    public static func isShortNight(_ readiness: [String: Readiness], on key: String, calendar: Calendar = .current) -> Bool {
        guard let sleep = ReadinessComparison.compare(readiness, on: key, calendar: calendar)?.sleep else { return false }
        if sleep.value < 6 * 60 { return true }
        if let usual = sleep.usual, usual - sleep.value >= 60 { return true }
        return false
    }

    /// No progress: the best estimated one-rep max of the last `stallSessions` sessions
    /// is no better than the best before them.
    public static func isStalled(_ exerciseID: UUID, history: [Workout], before: Date = .distantFuture) -> Bool {
        let sessions = ExerciseProgress.sessions(of: exerciseID, in: history.filter { $0.startedAt < before })
        guard sessions.count > stallSessions else { return false }
        let recent = sessions.prefix(stallSessions).compactMap(\.estimatedOneRepMax).max()
        let earlier = sessions.dropFirst(stallSessions).compactMap(\.estimatedOneRepMax).max()
        guard let recent, let earlier else { return false }
        return recent <= earlier + 0.0005
    }

    /// The day after the template day done most recently; the first day when none of the
    /// template's days has been done. The day is found by its name in the workout title,
    /// or else by the exercises the workout shares with it.
    public static func nextDay(of template: Template, history: [Workout]) -> TemplateDay? {
        guard !template.days.isEmpty else { return nil }
        guard let last = history
            .filter({ !$0.isInProgress && $0.templateId == template.id })
            .max(by: { $0.startedAt < $1.startedAt })
        else { return template.days[0] }
        let done = Set(last.exercises.map(\.exerciseId))
        let titled = template.days.lastIndex { day in
            [day.name, day.nameZh].compactMap { $0 }.contains { last.title.hasSuffix($0) }
        }
        let index = titled ?? template.days.indices.max { a, b in
            done.intersection(template.days[a].exercises.map(\.exerciseId)).count
                < done.intersection(template.days[b].exercises.map(\.exerciseId)).count
        }!
        return template.days[(index + 1) % template.days.count]
    }

    // MARK: Rules

    private static func decide(_ exercise: Exercise, working: [WorkoutSet], earlier: [WorkoutSet]?, range: (Int) -> RepRange, targetRir: (Int) -> Int?, context: Context) -> Change {
        // Only sets of the working type are judged; drop and failure sets follow along.
        func judged(_ sets: [WorkoutSet]) -> [(index: Int, set: WorkoutSet)] {
            let all = sets.enumerated().map { (index: $0.offset, set: $0.element) }
            let main = all.filter { $0.set.setType == .working }
            return main.isEmpty ? all : main
        }
        let sets = judged(working)
        guard sets.contains(where: { $0.set.reps != nil }) else { return .addReps }
        let weight = working.compactMap(\.weightKg).max() ?? 0
        let hasLoad = weight > 0 || exercise.loadType == .assisted
        let fixed = sets.allSatisfy { range($0.index).isFixed }

        let reachedTop = sets.allSatisfy { index, set in
            guard let done = set.reps, done >= range(index).max else { return false }
            // An RIR below the target means the reps took more effort than planned.
            if let target = targetRir(index), let rir = set.rir { return rir >= target }
            return true
        }
        if reachedTop {
            guard hasLoad else {
                // Without weight on a body-weight exercise the next step is weight or a
                // harder variation; on anything else the weight just wasn't logged.
                return exercise.isBodyweight ? .addLoadOrVariation : .addReps
            }
            if context.shortNight { return .heldForSleep }
            let to = heavier(weight, exercise: exercise, linear: fixed, unit: context.unit)
            return to == weight ? .addLoadOrVariation : .increase(fromKg: weight, toKg: to)
        }
        guard hasLoad else { return fixed ? .repeatWeight : .addReps }
        if fixed {
            // A second miss in a row at the same weight: back off and build up again.
            if let earlier, !earlier.isEmpty,
               abs((earlier.compactMap(\.weightKg).max() ?? 0) - weight) < 0.0005,
               judged(earlier).contains(where: { ($0.set.reps ?? 0) < range($0.index).min }) {
                let to = deloaded(weight, exercise: exercise, unit: context.unit)
                if to != weight { return .deload(fromKg: weight, toKg: to) }
            }
            return .repeatWeight
        }
        if sets.allSatisfy({ ($0.set.reps ?? 0) < range($0.index).min }) {
            let to = lighter(weight, exercise: exercise, unit: context.unit)
            if to != weight { return .decrease(fromKg: weight, toKg: to) }
        }
        return .addReps
    }

    /// The exercise's sets in the session before the last one.
    private static func previousSession(of exerciseID: UUID, context: Context) -> [WorkoutSet]? {
        let sessions = context.history
            .filter { !$0.isInProgress && $0.startedAt < context.before }
            .filter { $0.exercises.contains { $0.exerciseId == exerciseID && $0.sets.contains(where: \.isCompleted) } }
            .sorted { $0.startedAt > $1.startedAt }
        guard sessions.count > 1 else { return nil }
        return WorkoutLog.lastSets(of: exerciseID, in: context.history, before: sessions[0].startedAt)?
            .filter { $0.setType != .warmup }
    }

    /// One plate step for a range; for fixed reps 2.5 kg on upper-body lifts and 5 kg on
    /// lower-body ones (5 and 10 lb), or one step for a single dumbbell. Never more than
    /// `maxIncrease`, except that one step is always allowed. Assisted exercises get
    /// less assistance instead.
    static func heavier(_ kg: Double, exercise: Exercise, linear: Bool, unit: WeightUnit) -> Double {
        if exercise.loadType == .assisted {
            return unit.step(kilograms: kg, by: -1, loadType: exercise.loadType)
        }
        var steps = linear && exercise.loadType != .perSide && exercise.isLowerBody ? 2 : 1
        while steps > 1, unit.step(kilograms: kg, by: steps, loadType: exercise.loadType) > kg * (1 + maxIncrease) + 0.0005 {
            steps -= 1
        }
        return unit.step(kilograms: kg, by: steps, loadType: exercise.loadType)
    }

    static func lighter(_ kg: Double, exercise: Exercise, unit: WeightUnit) -> Double {
        unit.step(kilograms: kg, by: exercise.loadType == .assisted ? 1 : -1, loadType: exercise.loadType)
    }

    /// About 10% lighter, in whole plate steps (at least one).
    static func deloaded(_ kg: Double, exercise: Exercise, unit: WeightUnit) -> Double {
        var to = lighter(kg, exercise: exercise, unit: unit)
        while true {
            let next = lighter(to, exercise: exercise, unit: unit)
            guard next != to, abs(next - kg) <= kg * maxIncrease + 0.0005 else { return to }
            to = next
        }
    }

    private static func plannedSet(_ type: SetType, after previous: WorkoutSet, change: Change, range: RepRange) -> WorkoutSet {
        let weight = previous.weightKg
        let reps = previous.reps
        switch change {
        case let .increase(from, to), let .decrease(from, to), let .deload(from, to):
            // Sets lighter or heavier than the top set move by the same amount; reps go
            // back to the bottom of the range (drop and failure sets keep theirs).
            let moved = weight.map { $0 == from ? to : max(0, $0 + (to - from)) }
            return WorkoutSet(setType: type, reps: type == .working ? range.min : reps, weightKg: moved)
        case .addReps:
            let target = reps.map { $0 >= range.max || type != .working ? $0 : $0 + 1 }
            return WorkoutSet(setType: type, reps: target ?? range.min, weightKg: weight)
        case .repeatWeight:
            return WorkoutSet(setType: type, reps: type == .working ? range.min : reps, weightKg: weight)
        case .heldForSleep, .addLoadOrVariation, .firstTime:
            return WorkoutSet(setType: type, reps: reps ?? range.min, weightKg: weight)
        }
    }
}

extension Exercise {
    /// Done with body weight, so the way up is added weight or a harder variation.
    public var isBodyweight: Bool {
        loadType == .bodyweightPlus || equipment == .bodyweight
    }

    /// Trains mainly the legs or hips, which take bigger jumps in linear progression.
    public var isLowerBody: Bool {
        !Set(primaryMuscles).isDisjoint(with: [.quads, .hamstrings, .glutes, .adductors, .abductors, .calves])
    }
}
