import Foundation
import Testing

@testable import IronSageCore

private let bench = Exercise(
    nameEn: "Barbell bench press", equipment: .barbell, loadType: .total,
    primaryMuscles: [.chest], secondaryMuscles: [.frontDelts, .triceps], isCustom: false
)
private let squat = Exercise(
    nameEn: "Back squat", equipment: .barbell, loadType: .total,
    primaryMuscles: [.quads, .glutes], secondaryMuscles: [.adductors, .lowerBack], isCustom: false
)
private let curl = Exercise(
    nameEn: "Dumbbell curl", equipment: .dumbbell, loadType: .perSide,
    primaryMuscles: [.biceps], secondaryMuscles: [.forearms], isCustom: false
)
private let pullUp = Exercise(
    nameEn: "Pull-up", equipment: .bodyweight, loadType: .bodyweightPlus,
    primaryMuscles: [.lats], secondaryMuscles: [.biceps, .upperBack], isCustom: false
)
private let assistedDip = Exercise(
    nameEn: "Assisted dip", equipment: .machine, loadType: .assisted,
    primaryMuscles: [.chest, .triceps], isCustom: false
)

private func day(_ daysAgo: Int) -> Date {
    Date(timeIntervalSince1970: 1_792_800_000 - Double(daysAgo) * 86_400)
}

/// A finished workout; each set is (kg, reps) or (kg, reps, RIR).
private func workout(_ daysAgo: Int, _ exercise: Exercise, _ sets: [(Double, Int, Int?)], templateID: UUID? = nil, title: String = "Workout") -> Workout {
    Workout(
        title: title,
        templateId: templateID,
        startedAt: day(daysAgo),
        endedAt: day(daysAgo).addingTimeInterval(3600),
        exercises: [WorkoutExercise(
            exerciseId: exercise.id,
            sets: sets.map { WorkoutSet(reps: $0.1, weightKg: $0.0, rir: $0.2, completedAt: day(daysAgo)) }
        )]
    )
}

private func sets(_ sets: [(Double, Int)]) -> [(Double, Int, Int?)] {
    sets.map { ($0.0, $0.1, nil) }
}

private func template(_ exercise: Exercise, sets count: Int, reps: ClosedRange<Int>, rir: Int? = nil, warmups: Int = 0) -> TemplateExercise {
    TemplateExercise(
        exerciseId: exercise.id,
        sets: Array(repeating: TemplateSet(setType: .warmup), count: warmups)
            + Array(repeating: TemplateSet(repMin: reps.lowerBound, repMax: reps.upperBound, targetRir: rir), count: count)
    )
}

// MARK: Double progression

@Test func theTopOfTheRangeOnEverySetAddsOneStep() {
    let history = [workout(2, bench, sets([(60, 8), (60, 8), (60, 8)]))]
    let s = NextSession.suggest(bench, template: template(bench, sets: 3, reps: 5...8), context: .init(history: history))
    #expect(s.change == .increase(fromKg: 60, toKg: 62.5))
    #expect(s.sets.map(\.weightKg) == [62.5, 62.5, 62.5])
    #expect(s.sets.map(\.reps) == [5, 5, 5])
    #expect(s.sets.allSatisfy { !$0.isCompleted })
}

@Test func otherwiseTheSameWeightWithOneMoreRep() {
    let history = [workout(2, bench, sets([(60, 8), (60, 7), (60, 6)]))]
    let s = NextSession.suggest(bench, template: template(bench, sets: 3, reps: 5...8), context: .init(history: history))
    #expect(s.change == .addReps)
    #expect(s.sets.map(\.weightKg) == [60, 60, 60])
    // A set already at the top stays there.
    #expect(s.sets.map(\.reps) == [8, 8, 7])
}

@Test func lessReserveThanTheTargetHoldsTheWeight() {
    let history = [workout(2, bench, [(60, 8, 2), (60, 8, 0)])]
    let s = NextSession.suggest(bench, template: template(bench, sets: 2, reps: 5...8, rir: 2), context: .init(history: history))
    #expect(s.change == .addReps)
    #expect(s.sets.map(\.weightKg) == [60, 60])

    // Unlogged RIR doesn't hold anything back.
    let unlogged = [workout(2, bench, sets([(60, 8), (60, 8)]))]
    #expect(NextSession.suggest(bench, template: template(bench, sets: 2, reps: 5...8, rir: 2), context: .init(history: unlogged)).change
        == .increase(fromKg: 60, toKg: 62.5))
}

@Test func everySetBelowTheRangeGoesOneStepLighter() {
    let history = [workout(2, bench, sets([(80, 4), (80, 3)]))]
    let s = NextSession.suggest(bench, template: template(bench, sets: 2, reps: 5...8), context: .init(history: history))
    #expect(s.change == .decrease(fromKg: 80, toKg: 77.5))
    #expect(s.sets.map(\.weightKg) == [77.5, 77.5])
    #expect(s.sets.map(\.reps) == [5, 5])
}

@Test func setsKeepTheirShape() {
    // A top set and two lighter back-off sets all move by the same step.
    let history = [workout(2, bench, sets([(70, 8), (60, 10), (60, 10)]))]
    let s = NextSession.suggest(bench, template: template(bench, sets: 3, reps: 6...8), context: .init(history: history))
    #expect(s.change == .increase(fromKg: 70, toKg: 72.5))
    #expect(s.sets.map(\.weightKg) == [72.5, 62.5, 62.5])
}

@Test func warmUpsAreCopiedAndNotProgressed() {
    let last = Workout(
        title: "Workout", startedAt: day(2), endedAt: day(2).addingTimeInterval(3600),
        exercises: [WorkoutExercise(exerciseId: bench.id, sets: [
            WorkoutSet(setType: .warmup, reps: 10, weightKg: 40, completedAt: day(2)),
            WorkoutSet(reps: 8, weightKg: 60, completedAt: day(2)),
            WorkoutSet(reps: 8, weightKg: 60, completedAt: day(2)),
        ])]
    )
    let s = NextSession.suggest(bench, template: template(bench, sets: 2, reps: 5...8, warmups: 1), context: .init(history: [last]))
    #expect(s.sets.map(\.setType) == [.warmup, .working, .working])
    #expect(s.sets.map(\.weightKg) == [40, 62.5, 62.5])
    #expect(s.sets.map(\.reps) == [10, 5, 5])
}

// MARK: Linear progression

@Test func fixedRepsAddTwoAndAHalfKiloUpperAndFiveLower() {
    let benchHistory = [workout(2, bench, sets([(60, 5), (60, 5), (60, 5)]))]
    #expect(NextSession.suggest(bench, template: template(bench, sets: 3, reps: 5...5), context: .init(history: benchHistory)).change
        == .increase(fromKg: 60, toKg: 62.5))

    let squatHistory = [workout(2, squat, sets([(80, 5), (80, 5), (80, 5)]))]
    #expect(NextSession.suggest(squat, template: template(squat, sets: 3, reps: 5...5), context: .init(history: squatHistory)).change
        == .increase(fromKg: 80, toKg: 85))

    // In pounds: 5 and 10 lb.
    let pounds = NextSession.Context(history: squatHistory, unit: .lb)
    if case let .increase(_, to) = NextSession.suggest(squat, template: template(squat, sets: 3, reps: 5...5), context: pounds).change {
        #expect(WeightUnit.lb.format(kilograms: to, locale: Locale(identifier: "en_US")) == "185")
    } else {
        Issue.record("expected an increase")
    }
}

@Test func eachTemplateSetKeepsItsOwnReps() {
    // A template saved from a workout of 8, 7 and 6 reps.
    let saved = TemplateExercise(exerciseId: bench.id, sets: [
        TemplateSet(repMin: 8, repMax: 8), TemplateSet(repMin: 7, repMax: 7), TemplateSet(repMin: 6, repMax: 6),
    ])
    let done = [workout(2, bench, sets([(60, 8), (60, 7), (60, 6)]))]
    let s = NextSession.suggest(bench, template: saved, context: .init(history: done))
    #expect(s.change == .increase(fromKg: 60, toKg: 62.5))
    #expect(s.sets.map(\.reps) == [8, 7, 6])

    let missed = [workout(2, bench, sets([(60, 8), (60, 7), (60, 5)]))]
    #expect(NextSession.suggest(bench, template: saved, context: .init(history: missed)).change == .repeatWeight)
}

@Test func missedFixedRepsRepeatTheWeight() {
    let history = [workout(2, squat, sets([(80, 5), (80, 5), (80, 3)]))]
    let s = NextSession.suggest(squat, template: template(squat, sets: 3, reps: 5...5), context: .init(history: history))
    #expect(s.change == .repeatWeight)
    #expect(s.sets.map(\.weightKg) == [80, 80, 80])
    #expect(s.sets.map(\.reps) == [5, 5, 5])
}

@Test func twoMissesInARowBackOffAboutTenPercent() {
    let history = [
        workout(5, squat, sets([(100, 5), (100, 5), (100, 4)])),
        workout(2, squat, sets([(100, 5), (100, 3), (100, 3)])),
    ]
    let s = NextSession.suggest(squat, template: template(squat, sets: 3, reps: 5...5), context: .init(history: history))
    #expect(s.change == .deload(fromKg: 100, toKg: 90))
    #expect(s.sets.map(\.reps) == [5, 5, 5])

    // A miss after a success at a lower weight is only repeated.
    let firstMiss = [workout(5, squat, sets([(97.5, 5), (97.5, 5)])), workout(2, squat, sets([(100, 5), (100, 4)]))]
    #expect(NextSession.suggest(squat, template: template(squat, sets: 2, reps: 5...5), context: .init(history: firstMiss)).change == .repeatWeight)
}

@Test func increasesStayWithinTenPercent() {
    // 5 kg on a 40 kg squat would be 12.5%: one step instead.
    let history = [workout(2, squat, sets([(40, 5), (40, 5)]))]
    #expect(NextSession.suggest(squat, template: template(squat, sets: 2, reps: 5...5), context: .init(history: history)).change
        == .increase(fromKg: 40, toKg: 42.5))

    // The smallest step is always allowed, even when it is more than 10%.
    let light = [workout(2, curl, sets([(8, 12), (8, 12)]))]
    #expect(NextSession.suggest(curl, template: template(curl, sets: 2, reps: 10...12), context: .init(history: light)).change
        == .increase(fromKg: 8, toKg: 8.75))
}

// MARK: Other load types

@Test func dropSetsFollowTheWorkingSets() {
    let last = Workout(
        title: "Workout", startedAt: day(2), endedAt: day(2).addingTimeInterval(3600),
        exercises: [WorkoutExercise(exerciseId: bench.id, sets: [
            WorkoutSet(reps: 10, weightKg: 60, completedAt: day(2)),
            WorkoutSet(reps: 10, weightKg: 60, completedAt: day(2)),
            WorkoutSet(setType: .drop, reps: 8, weightKg: 40, completedAt: day(2)),
        ])]
    )
    let s = NextSession.suggest(bench, context: .init(history: [last]))
    #expect(s.change == .increase(fromKg: 60, toKg: 62.5))
    #expect(s.sets.map(\.setType) == [.working, .working, .drop])
    #expect(s.sets.map(\.weightKg) == [62.5, 62.5, 42.5])
    #expect(s.sets.map(\.reps) == [6, 6, 8])
}

@Test func anUnloggedWeightIsNotBodyWeight() {
    let history = [Workout(
        title: "Workout", startedAt: day(2), endedAt: day(2).addingTimeInterval(3600),
        exercises: [WorkoutExercise(exerciseId: bench.id, sets: [WorkoutSet(reps: 10, completedAt: day(2))])]
    )]
    #expect(NextSession.suggest(bench, context: .init(history: history)).change == .addReps)
}

@Test func bodyWeightAtTheTopAsksForWeightOrAHarderVariation() {
    let history = [workout(2, pullUp, sets([(0, 10), (0, 10)]))]
    let s = NextSession.suggest(pullUp, template: template(pullUp, sets: 2, reps: 6...10), context: .init(history: history))
    #expect(s.change == .addLoadOrVariation)
    #expect(s.sets.map(\.reps) == [10, 10])
}

@Test func assistedExercisesProgressWithLessAssistance() {
    let history = [workout(2, assistedDip, sets([(30, 10), (30, 10)]))]
    #expect(NextSession.suggest(assistedDip, template: template(assistedDip, sets: 2, reps: 6...10), context: .init(history: history)).change
        == .increase(fromKg: 30, toKg: 27.5))

    let tooHard = [workout(2, assistedDip, sets([(30, 3), (30, 4)]))]
    #expect(NextSession.suggest(assistedDip, template: template(assistedDip, sets: 2, reps: 6...10), context: .init(history: tooHard)).change
        == .decrease(fromKg: 30, toKg: 32.5))
}

// MARK: Readiness and stalls

@Test func aShortNightHoldsTheWeight() {
    let history = [workout(2, bench, sets([(60, 8), (60, 8)]))]
    let s = NextSession.suggest(bench, template: template(bench, sets: 2, reps: 5...8), context: .init(history: history, shortNight: true))
    #expect(s.change == .heldForSleep)
    #expect(s.sets.map(\.weightKg) == [60, 60])
    #expect(s.sets.map(\.reps) == [8, 8])
}

@Test func shortNightsAreUnderSixHoursOrAnHourBelowUsual() {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "Europe/Berlin")!
    func history(today minutes: Int, usual: Int) -> [String: Readiness] {
        var all = ["2026-11-30": Readiness(date: "2026-11-30", sleepMinutes: minutes)]
        let end = HealthDays.date("2026-11-30", calendar: calendar)!
        for back in 1...14 {
            let key = HealthDays.key(calendar.date(byAdding: .day, value: -back, to: end)!, calendar: calendar)
            all[key] = Readiness(date: key, sleepMinutes: usual)
        }
        return all
    }
    #expect(NextSession.isShortNight(history(today: 350, usual: 360), on: "2026-11-30", calendar: calendar))
    #expect(NextSession.isShortNight(history(today: 420, usual: 480), on: "2026-11-30", calendar: calendar))
    #expect(!NextSession.isShortNight(history(today: 430, usual: 480), on: "2026-11-30", calendar: calendar))
    // HRV alone never counts, and no data is not a short night.
    #expect(!NextSession.isShortNight(["2026-11-30": Readiness(date: "2026-11-30", hrvSdnnMs: 20)], on: "2026-11-30", calendar: calendar))
    #expect(!NextSession.isShortNight([:], on: "2026-11-30", calendar: calendar))
}

@Test func threeSessionsWithoutProgressAreAStall() {
    let stalled = [
        workout(12, bench, sets([(60, 8)])),
        workout(9, bench, sets([(60, 8)])),
        workout(6, bench, sets([(60, 7)])),
        workout(3, bench, sets([(60, 8)])),
    ]
    #expect(NextSession.isStalled(bench.id, history: stalled))
    #expect(NextSession.suggest(bench, context: .init(history: stalled)).isStalled)

    let progressing = stalled + [workout(1, bench, sets([(62.5, 8)]))]
    #expect(!NextSession.isStalled(bench.id, history: progressing))
    // Too few sessions to tell.
    #expect(!NextSession.isStalled(bench.id, history: Array(stalled.prefix(3))))
}

// MARK: Without a template

@Test func withoutATemplateTheRangeDependsOnTheLiftAndGoal() {
    #expect(NextSession.defaultRange(for: bench, goal: .hypertrophy) == .init(6, 10))
    #expect(NextSession.defaultRange(for: bench, goal: .strength) == .init(3, 6))
    #expect(NextSession.defaultRange(for: curl, goal: .strength) == .init(10, 15))
    // Someone training outside it keeps their own reps.
    #expect(NextSession.defaultRange(for: bench, goal: nil, lastReps: 15) == .init(15, 17))

    let history = [workout(2, bench, sets([(60, 10), (60, 10)]))]
    let s = NextSession.suggest(bench, context: .init(history: history))
    #expect(s.change == .increase(fromKg: 60, toKg: 62.5))
    #expect(s.sets.map(\.reps) == [6, 6])
}

@Test func theFirstTimeStartsAtTheBottomOfTheRange() {
    let s = NextSession.suggest(bench, template: template(bench, sets: 3, reps: 5...8), context: .init(history: []))
    #expect(s.change == .firstTime)
    #expect(s.sets.map(\.reps) == [5, 5, 5])
    #expect(s.sets.allSatisfy { $0.weightKg == nil })
    #expect(NextSession.suggest(curl, context: .init(history: [])).sets.count == 1)
}

@Test func editingAnOldWorkoutOnlySeesWhatCameBefore() {
    let history = [workout(9, bench, sets([(57.5, 8)])), workout(3, bench, sets([(60, 10)]))]
    let s = NextSession.suggest(bench, template: template(bench, sets: 1, reps: 6...10), context: .init(history: history, before: day(3)))
    #expect(s.change == .addReps)
    #expect(s.sets.map(\.weightKg) == [57.5])
}

// MARK: Template rotation

@Test func theNextDayFollowsTheLastOneDone() {
    let a = TemplateDay(name: "Day A", nameZh: "A 日", exercises: [template(squat, sets: 3, reps: 5...5), template(bench, sets: 3, reps: 5...5)])
    let b = TemplateDay(name: "Day B", nameZh: "B 日", exercises: [template(pullUp, sets: 3, reps: 6...10), template(curl, sets: 2, reps: 10...12)])
    let program = Template(nameEn: "Full body", days: [a, b], isCustom: false)

    #expect(NextSession.nextDay(of: program, history: [])?.id == a.id)
    let didA = workout(2, squat, sets([(80, 5)]), templateID: program.id, title: "Full body · Day A")
    #expect(NextSession.nextDay(of: program, history: [didA])?.id == b.id)
    // Chinese title.
    let didB = workout(1, pullUp, sets([(0, 8)]), templateID: program.id, title: "新手全身训练 · B 日")
    #expect(NextSession.nextDay(of: program, history: [didA, didB])?.id == a.id)
    // A renamed workout is matched by its exercises.
    let renamed = workout(0, curl, sets([(10, 10)]), templateID: program.id, title: "Arms")
    #expect(NextSession.nextDay(of: program, history: [didA, renamed])?.id == a.id)
}
