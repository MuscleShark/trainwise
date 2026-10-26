import Foundation
import Testing

@testable import IronSageCore

private let bench = Exercise(
    nameEn: "Barbell bench press", nameZh: "杠铃卧推", equipment: .barbell, loadType: .total,
    primaryMuscles: [.chest], secondaryMuscles: [.frontDelts, .triceps], isCustom: false
)
private let squat = Exercise(
    nameEn: "Back squat", equipment: .barbell, loadType: .total,
    primaryMuscles: [.quads, .glutes], secondaryMuscles: [.adductors], isCustom: false
)

private func day(_ daysAgo: Int) -> Date {
    Date(timeIntervalSince1970: 1_792_800_000 - Double(daysAgo) * 86_400)
}

private func workout(_ daysAgo: Int, _ exercise: Exercise, _ sets: [(Double, Int)]) -> Workout {
    Workout(
        title: "Workout", startedAt: day(daysAgo), endedAt: day(daysAgo).addingTimeInterval(3600),
        exercises: [WorkoutExercise(
            exerciseId: exercise.id,
            sets: sets.map { WorkoutSet(reps: $0.1, weightKg: $0.0, rir: 2, completedAt: day(daysAgo)) }
        )]
    )
}

private let push = TemplateDay(name: "Push", exercises: [
    TemplateExercise(exerciseId: bench.id, sets: Array(repeating: TemplateSet(repMin: 6, repMax: 10, targetRir: 2), count: 2)),
    // Removed from the catalog: left out of the request.
    TemplateExercise(exerciseId: UUID(), sets: [TemplateSet(repMin: 8, repMax: 12)]),
])

@Test func theRequestCarriesThePlanRecentSessionsAndReadiness() throws {
    let history = (1...4).map { workout($0 * 3, bench, [(60, 10), (60, 10)]) }
    let readiness = ReadinessComparison.Day(
        date: "2026-10-26",
        sleep: .init(value: 310, usual: 445, direction: .lower),
        hrv: .init(value: 48, usual: nil, direction: nil),
        restingHeartRate: nil
    )
    let request = try #require(Coach.request(
        for: push,
        exercises: [bench.id: bench, squat.id: squat],
        context: .init(history: history, unit: .lb),
        readiness: readiness,
        profile: Profile(experienceLevel: .intermediate, goal: .hypertrophy),
        chinese: true
    ))

    #expect(request.language == "zh" && request.unit == "lb")
    #expect(request.goal == .hypertrophy && request.experience == .intermediate)
    #expect(request.readiness.sleepMinutes == .init(value: 310, usual: 445))
    #expect(request.readiness.hrvMs == .init(value: 48))
    #expect(request.readiness.restingHrBpm == nil)

    let plan = try #require(request.exercises.first)
    #expect(request.exercises.count == 1)
    #expect(plan.exerciseId == bench.id.uuidString.lowercased())
    #expect(plan.name == "杠铃卧推")
    #expect(plan.change == "increase")
    #expect((plan.repMin, plan.repMax) == (6, 10))
    #expect(plan.lastWeightKg == 60)
    #expect(plan.plannedSets.allSatisfy { $0.setType == .working && $0.reps == 6 })
    // The three most recent sessions, newest first.
    #expect(plan.recentSessions.count == 3)
    #expect(plan.recentSessions.first?.date == HealthDays.key(day(3)))
}

@Test func nothingToAskWithoutKnownExercises() {
    #expect(Coach.request(for: push, exercises: [:], context: .init(history: []), readiness: nil, profile: nil, chinese: false) == nil)
}

@Test func thePlanKeyChangesWithANewWorkoutSleepOrPlannedSets() throws {
    let earlier = workout(3, bench, [(60, 8)])
    let later = workout(1, bench, [(60, 9)])
    func request(_ history: [Workout], unit: WeightUnit = .kg, hrv: Double? = nil) throws -> CoachRequest {
        let readiness = hrv.map { ReadinessComparison.Day(date: "2026-10-26", sleep: nil, hrv: .init(value: $0, usual: nil, direction: nil), restingHeartRate: nil) }
        return try #require(Coach.request(for: push, exercises: [bench.id: bench], context: .init(history: history, unit: unit), readiness: readiness, profile: nil, chinese: false))
    }
    let base = Coach.planKey(day: push, lastWorkout: earlier, readiness: nil, request: try request([earlier]))
    #expect(base == Coach.planKey(day: push, lastWorkout: earlier, readiness: nil, request: try request([earlier])))
    #expect(base != Coach.planKey(day: push, lastWorkout: later, readiness: nil, request: try request([earlier, later])))
    #expect(base != Coach.planKey(day: push, lastWorkout: earlier, readiness: Readiness(date: "2026-10-26", sleepMinutes: 420), request: try request([earlier])))
    // Different planned sets (here pounds instead of kilograms) make a different plan.
    #expect(base != Coach.planKey(day: push, lastWorkout: earlier, readiness: nil, request: try request([earlier], unit: .lb)))
    // HRV changes during the day and never changes the plan on its own.
    #expect(base == Coach.planKey(day: push, lastWorkout: earlier, readiness: nil, request: try request([earlier], hrv: 40)))
}

@Test func adviceReplacesTheSetsOfTheExercisesItCovers() {
    let planned = [
        WorkoutExercise(exerciseId: bench.id, sets: [WorkoutSet(reps: 6, weightKg: 62.5), WorkoutSet(reps: 6, weightKg: 62.5)]),
        WorkoutExercise(exerciseId: squat.id, sets: [WorkoutSet(reps: 5, weightKg: 100)]),
    ]
    let advice = CoachAdvice(
        summary: "Hold today.",
        exercises: [.init(
            exerciseId: bench.id.uuidString.uppercased(), action: .holdWeight, reason: "Short night.",
            sets: [.init(reps: 10, weightKg: 60), .init(reps: 10, weightKg: 60)]
        )],
        model: "anthropic:claude-sonnet-5-5"
    )
    let applied = Coach.applying(advice, to: planned)
    #expect(applied[0].sets.map(\.weightKg) == [60, 60])
    #expect(applied[0].sets.allSatisfy { !$0.isCompleted })
    #expect(applied[0].id == planned[0].id)
    #expect(applied[1] == planned[1])
}

@Test func ruleChangesUseTheBackendsNames() {
    #expect(NextSession.Change.increase(fromKg: 60, toKg: 62.5).wireName == "increase")
    #expect(NextSession.Change.heldForSleep.wireName == "held_for_sleep")
    #expect(NextSession.Change.addLoadOrVariation.wireName == "add_load_or_variation")
}
