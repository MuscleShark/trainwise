import Foundation

// The AI coach (M3): the phone sends the rule plan for the next session with a short
// summary of recent training and last night's readiness; the backend asks the model,
// which may only follow the plan, hold the weight or drop a set, and explain why
// (backend/coach/). The advice comes back through sync as a Recommendation.

/// What the coach is asked: mirrors CoachInput in api/openapi.json.
public struct CoachRequest: Codable, Hashable, Sendable {
    public struct Metric: Codable, Hashable, Sendable {
        public var value: Double
        public var usual: Double?

        public init(value: Double, usual: Double? = nil) {
            self.value = value
            self.usual = usual
        }
    }

    public struct ReadinessSummary: Codable, Hashable, Sendable {
        public var sleepMinutes: Metric?
        public var hrvMs: Metric?
        public var restingHrBpm: Metric?

        public init(sleepMinutes: Metric? = nil, hrvMs: Metric? = nil, restingHrBpm: Metric? = nil) {
            self.sleepMinutes = sleepMinutes
            self.hrvMs = hrvMs
            self.restingHrBpm = restingHrBpm
        }
    }

    public struct PlannedSet: Codable, Hashable, Sendable {
        public var reps: Int?
        public var weightKg: Double?
        public var setType: SetType

        public init(reps: Int?, weightKg: Double?, setType: SetType = .working) {
            self.reps = reps
            self.weightKg = weightKg
            self.setType = setType
        }
    }

    public struct DoneSet: Codable, Hashable, Sendable {
        public var reps: Int?
        public var weightKg: Double?
        public var rir: Int?

        public init(reps: Int?, weightKg: Double?, rir: Int? = nil) {
            self.reps = reps
            self.weightKg = weightKg
            self.rir = rir
        }
    }

    public struct Session: Codable, Hashable, Sendable {
        /// "2026-10-22"
        public var date: String
        public var sets: [DoneSet]

        public init(date: String, sets: [DoneSet]) {
            self.date = date
            self.sets = sets
        }
    }

    public struct ExercisePlan: Codable, Hashable, Sendable {
        public var exerciseId: String
        public var name: String
        public var isCompound: Bool
        public var change: String
        public var repMin: Int
        public var repMax: Int
        public var stalled: Bool
        public var plannedSets: [PlannedSet]
        public var lastWeightKg: Double?
        public var recentSessions: [Session]

        public init(
            exerciseId: String, name: String, isCompound: Bool, change: String, repMin: Int, repMax: Int,
            stalled: Bool, plannedSets: [PlannedSet], lastWeightKg: Double?, recentSessions: [Session]
        ) {
            self.exerciseId = exerciseId
            self.name = name
            self.isCompound = isCompound
            self.change = change
            self.repMin = repMin
            self.repMax = repMax
            self.stalled = stalled
            self.plannedSets = plannedSets
            self.lastWeightKg = lastWeightKg
            self.recentSessions = recentSessions
        }
    }

    public var language: String
    public var unit: String
    public var goal: Goal?
    public var experience: Level?
    public var readiness: ReadinessSummary
    public var exercises: [ExercisePlan]

    public init(
        language: String, unit: String, goal: Goal?, experience: Level?,
        readiness: ReadinessSummary, exercises: [ExercisePlan]
    ) {
        self.language = language
        self.unit = unit
        self.goal = goal
        self.experience = experience
        self.readiness = readiness
        self.exercises = exercises
    }
}

public enum CoachAction: String, Codable, Hashable, Sendable {
    case follow
    case holdWeight = "hold_weight"
    case oneSetFewer = "one_set_fewer"
}

/// The coach's advice for one exercise: what it chose, why, and the resulting sets.
public struct CoachAdvice: Codable, Hashable, Sendable {
    public struct Exercise: Codable, Hashable, Sendable {
        public var exerciseId: String
        public var action: CoachAction
        public var reason: String
        public var sets: [CoachRequest.PlannedSet]

        public init(exerciseId: String, action: CoachAction, reason: String, sets: [CoachRequest.PlannedSet]) {
            self.exerciseId = exerciseId
            self.action = action
            self.reason = reason
            self.sets = sets
        }
    }

    public var summary: String
    public var exercises: [Exercise]
    public var model: String

    public init(summary: String, exercises: [Exercise], model: String) {
        self.summary = summary
        self.exercises = exercises
        self.model = model
    }

    public func advice(for exerciseID: UUID) -> Exercise? {
        exercises.first { $0.exerciseId.lowercased() == exerciseID.uuidString.lowercased() }
    }
}

/// One request to the coach and, once it has answered, its advice.
public struct Recommendation: Identifiable, Hashable, Codable, Sendable {
    public enum Status: String, Codable, Hashable, Sendable {
        case pending, running, ready, failed
    }

    public var id: UUID
    /// The local date the session is planned for, "2026-10-26".
    public var forDate: String
    public var status: Status
    public var output: CoachAdvice?
    /// Why there is no advice: invalid_answer, declined, unavailable, timed_out, or on
    /// the phone not_allowed (no access) and limit_reached.
    public var error: String?
    /// What was sent. Only the phone keeps it; the server's copy isn't synced back.
    public var request: CoachRequest?
    /// Which plan it was for (`Coach.planKey`), so a changed plan asks again.
    public var planKey: String?
    public var requestedAt: Date?
    /// When the server last accepted it; an answer is overdue `Coach.answerTimeout` later.
    public var sentAt: Date?

    public init(
        id: UUID = UUID(),
        forDate: String,
        status: Status = .pending,
        output: CoachAdvice? = nil,
        error: String? = nil,
        request: CoachRequest? = nil,
        planKey: String? = nil,
        requestedAt: Date? = nil,
        sentAt: Date? = nil
    ) {
        self.id = id
        self.forDate = forDate
        self.status = status
        self.output = output
        self.error = error
        self.request = request
        self.planKey = planKey
        self.requestedAt = requestedAt
        self.sentAt = sentAt
    }

    public var isWaiting: Bool { status == .pending || status == .running }
}

public enum Coach {
    /// After this long without an answer the request is sent again, and the server
    /// marks it timed out (backend/routers/coach.py).
    public static let answerTimeout: TimeInterval = 2 * 60
    /// The phone asks at most this often per day, under the server's limit of 5.
    public static let dailyRequests = 3

    /// Identifies the plan a request was for: the template day, the last finished
    /// workout and whether last night's sleep was known. When any of them changes (a
    /// new workout, or the morning's sleep arriving), the coach is asked again.
    ///
    /// The planned sets are part of it too, so editing the template, a past workout or
    /// the unit makes a new plan: advice is only ever applied to the sets it was given.
    /// HRV and resting heart rate are not, since they change during the day and never
    /// change the plan on their own.
    public static func planKey(day: TemplateDay, lastWorkout: Workout?, readiness: Readiness?, request: CoachRequest) -> String {
        let sleep = readiness?.sleepMinutes.map(String.init) ?? "-"
        return "\(day.id.uuidString)|\(lastWorkout?.id.uuidString ?? "-")|\(sleep)|\(stableHash(of: request))"
    }

    /// A hash of the plan that stays the same across launches (Hasher is seeded per launch).
    private static func stableHash(of request: CoachRequest) -> String {
        let plan = request.exercises.map { exercise in
            "\(exercise.exerciseId):\(exercise.repMin)-\(exercise.repMax):"
                + exercise.plannedSets.map { "\($0.setType.rawValue)/\($0.reps ?? -1)/\($0.weightKg ?? -1)" }.joined(separator: ",")
        }.joined(separator: ";")
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325  // FNV-1a
        for byte in "\(request.unit)|\(request.language)|\(plan)".utf8 {
            hash = (hash ^ UInt64(byte)) &* 0x100_0000_01b3
        }
        return String(hash, radix: 16)
    }

    /// The request for a template day: each exercise's rule plan, its last sessions
    /// and last night's readiness next to the usual. Exercises missing from the catalog
    /// are left out.
    public static func request(
        for day: TemplateDay,
        exercises: [UUID: Exercise],
        context: NextSession.Context,
        readiness: ReadinessComparison.Day?,
        profile: Profile?,
        chinese: Bool
    ) -> CoachRequest? {
        let plans = day.exercises.compactMap { item -> CoachRequest.ExercisePlan? in
            guard let exercise = exercises[item.exerciseId] else { return nil }
            let suggestion = NextSession.suggest(exercise, template: item, context: context)
            let sessions = ExerciseProgress.sessions(of: exercise.id, in: context.history.filter { $0.startedAt < context.before })
            return CoachRequest.ExercisePlan(
                exerciseId: exercise.id.uuidString.lowercased(),
                name: exercise.name(chinese: chinese),
                isCompound: exercise.isCompound,
                change: suggestion.change.wireName,
                repMin: suggestion.range.min,
                repMax: suggestion.range.max,
                stalled: suggestion.isStalled,
                plannedSets: suggestion.sets.map {
                    CoachRequest.PlannedSet(reps: $0.reps, weightKg: $0.weightKg, setType: $0.setType)
                },
                lastWeightKg: sessions.first?.sets.compactMap(\.weightKg).max(),
                recentSessions: sessions.prefix(3).map { session in
                    CoachRequest.Session(
                        date: HealthDays.key(session.date),
                        sets: session.sets.map { CoachRequest.DoneSet(reps: $0.reps, weightKg: $0.weightKg, rir: $0.rir) }
                    )
                }
            )
        }
        guard !plans.isEmpty else { return nil }
        func metric(_ value: ReadinessComparison.Metric?) -> CoachRequest.Metric? {
            value.map { CoachRequest.Metric(value: $0.value, usual: $0.usual) }
        }
        return CoachRequest(
            language: chinese ? "zh" : "en",
            unit: context.unit.rawValue,
            goal: profile?.goal,
            experience: profile?.experienceLevel,
            readiness: CoachRequest.ReadinessSummary(
                sleepMinutes: metric(readiness?.sleep),
                hrvMs: metric(readiness?.hrv),
                restingHrBpm: metric(readiness?.restingHeartRate)
            ),
            exercises: Array(plans.prefix(15))
        )
    }

    /// The workout's planned sets with the coach's advice applied: exercises it advised
    /// get its sets, the others keep the rule plan.
    public static func applying(_ advice: CoachAdvice, to exercises: [WorkoutExercise]) -> [WorkoutExercise] {
        exercises.map { item in
            guard let advised = advice.advice(for: item.exerciseId), !advised.sets.isEmpty else { return item }
            var item = item
            item.sets = advised.sets.map { WorkoutSet(setType: $0.setType, reps: $0.reps, weightKg: $0.weightKg) }
            return item
        }
    }
}

extension NextSession.Change {
    /// The name the backend uses (RuleChange in api/openapi.json).
    public var wireName: String {
        switch self {
        case .firstTime: "first_time"
        case .increase: "increase"
        case .addReps: "add_reps"
        case .repeatWeight: "repeat_weight"
        case .decrease: "decrease"
        case .deload: "deload"
        case .heldForSleep: "held_for_sleep"
        case .addLoadOrVariation: "add_load_or_variation"
        }
    }
}
