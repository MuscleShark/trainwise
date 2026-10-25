import Foundation
import Testing

@testable import IronSageCore

private let bench = Exercise(
    nameEn: "Barbell bench press", equipment: .barbell, loadType: .total,
    primaryMuscles: [.chest], secondaryMuscles: [.frontDelts, .triceps], isCustom: false
)
private let curl = Exercise(
    nameEn: "Dumbbell curl", equipment: .dumbbell, loadType: .perSide,
    primaryMuscles: [.biceps], secondaryMuscles: [.forearms], isCustom: false
)
private let hackSquat = Exercise(
    nameEn: "Hack squat", equipment: .machine, loadType: .total,
    primaryMuscles: [.quads], secondaryMuscles: [.glutes], isCustom: false
)
private let exercises = [bench.id: bench, curl.id: curl]

private func day(_ daysAgo: Int) -> Date {
    Date(timeIntervalSince1970: 1_792_800_000 - Double(daysAgo) * 86_400)
}

private func workout(_ daysAgo: Int, _ items: [(Exercise, [(Double, Int)])], finished: Bool = true, rest: Int? = nil) -> Workout {
    Workout(
        title: "Workout",
        startedAt: day(daysAgo),
        endedAt: finished ? day(daysAgo).addingTimeInterval(3600) : nil,
        exercises: items.map { exercise, sets in
            WorkoutExercise(
                exerciseId: exercise.id,
                restSeconds: rest,
                sets: sets.map { WorkoutSet(reps: $0.1, weightKg: $0.0, completedAt: day(daysAgo)) }
            )
        }
    )
}

@Test func restDefaultsDependOnTheKindOfLift() {
    #expect(bench.isCompound)
    #expect(hackSquat.isCompound)
    #expect(!curl.isCompound)
    #expect(bench.defaultRestSeconds == 180)
    #expect(curl.defaultRestSeconds == 90)
}

@Test func newExercisesStartFromTheSuggestion() {
    let history = [
        workout(7, [(bench, [(57.5, 8)])]),
        workout(3, [(bench, [(60, 8), (60, 7)])], rest: 150),
        workout(0, [(bench, [(70, 5)])], finished: false),
    ]

    let added = WorkoutLog.adding(bench, context: .init(history: history))

    // Below the top of the 6–10 range: the same weight, one more rep.
    #expect(added.sets.map(\.weightKg) == [60, 60])
    #expect(added.sets.map(\.reps) == [9, 8])
    #expect(added.sets.allSatisfy { !$0.isCompleted })
    #expect(added.restSeconds == 150)
    // Editing the older workout shows what came before it, not after.
    #expect(WorkoutLog.lastSets(of: bench.id, in: history, before: day(3))?.map(\.weightKg) == [57.5])
}

@Test func aFirstTimeExerciseStartsWithOneEmptySet() {
    let added = WorkoutLog.adding(curl, context: .init(history: []))
    #expect(added.sets.count == 1)
    #expect(added.sets[0].weightKg == nil)
    #expect(added.restSeconds == 90)
}

@Test func volumeCountsWorkingSetsAndBothDumbbells() {
    var session = workout(0, [(bench, [(60, 8)]), (curl, [(12.5, 10)])])
    session.exercises[0].sets.append(WorkoutSet(setType: .warmup, reps: 10, weightKg: 40, completedAt: day(0)))
    session.exercises[0].sets.append(WorkoutSet(reps: 8, weightKg: 60))

    let expected: Double = 60 * 8 + 12.5 * 10 * 2
    #expect(WorkoutLog.volumeKg(of: session, exercises: exercises) == expected)
}

@Test func recordsNeedSomethingToBeat() {
    let history = [workout(3, [(bench, [(60, 8)])])]

    let heavier = workout(0, [(bench, [(62.5, 5)]), (curl, [(15, 8)])])
    let records = WorkoutLog.personalRecords(in: heavier, history: history + [heavier], exercises: exercises)
    #expect(records == [.init(exerciseID: bench.id, kind: .heaviestWeight, kilograms: 62.5, previousKilograms: 60)])

    let moreReps = workout(0, [(bench, [(60, 10)])])
    let e1rm = WorkoutLog.personalRecords(in: moreReps, history: history, exercises: exercises)
    #expect(e1rm.map(\.kind) == [.estimatedOneRepMax])

    let same = workout(0, [(bench, [(60, 8)])])
    #expect(WorkoutLog.personalRecords(in: same, history: history, exercises: exercises).isEmpty)
}

@Test func oneRepMaxIsOnlyEstimatedForUpToTwelveReps() throws {
    #expect(WorkoutLog.estimatedOneRepMax(weightKg: 100, reps: 1) == 100)
    let threeReps = try #require(WorkoutLog.estimatedOneRepMax(weightKg: 100, reps: 3))
    #expect(abs(threeReps - 110) < 0.000_001)
    #expect(WorkoutLog.estimatedOneRepMax(weightKg: 100, reps: 15) == nil)
    #expect(WorkoutLog.estimatedOneRepMax(weightKg: 0, reps: 5) == nil)
}

@Test func restTimerCountsDownAndCanBeExtended() {
    let start = Date(timeIntervalSince1970: 0)
    var timer = RestTimer(exerciseName: "Bench", seconds: 90, from: start)
    #expect(timer.remaining(at: start.addingTimeInterval(30)) == 60)

    timer.extend(by: 15, at: start.addingTimeInterval(30))
    #expect(timer.remaining(at: start.addingTimeInterval(30)) == 75)
    timer.extend(by: -120, at: start.addingTimeInterval(30))
    #expect(timer.isFinished(at: start.addingTimeInterval(30)))
}

@Test func poundsRoundTripThroughKilograms() {
    let stored = WeightUnit.lb.kilograms(from: 135)
    #expect(stored == 61.235)
    #expect(WeightUnit.lb.format(kilograms: stored, locale: Locale(identifier: "en_US")) == "135")
    #expect(WeightUnit.kg.format(kilograms: 61.25, locale: Locale(identifier: "en_US")) == "61.25")
    #expect(WeightUnit.kg.format(kilograms: 60, locale: Locale(identifier: "en_US")) == "60")
    #expect(WeightUnit.lb.format(kilograms: 60, locale: Locale(identifier: "en_US")) == "132.3")
}

@Test func stepsLandOnPlateIncrements() {
    #expect(WeightUnit.kg.step(kilograms: 61, by: 1, loadType: .total) == 62.5)
    #expect(WeightUnit.kg.step(kilograms: 61, by: -1, loadType: .total) == 60)
    #expect(WeightUnit.kg.step(kilograms: 60, by: 1, loadType: .total) == 62.5)
    #expect(WeightUnit.kg.step(kilograms: 10, by: 1, loadType: .perSide) == 11.25)
    #expect(WeightUnit.kg.step(kilograms: 0, by: -1, loadType: .total) == 0)
    let pounds = WeightUnit.lb
    let next = pounds.step(kilograms: pounds.kilograms(from: 135), by: 1, loadType: .total)
    #expect(pounds.value(fromKilograms: next).rounded() == 140)
}

@Test func theDefaultUnitFollowsTheRegion() {
    #expect(WeightUnit.default(for: Locale(identifier: "en_US")) == .lb)
    #expect(WeightUnit.default(for: Locale(identifier: "zh_Hans_CN")) == .kg)
    #expect(WeightUnit.default(for: Locale(identifier: "de_DE")) == .kg)
}

@Test func historyGroupsFinishedWorkoutsByWeek() throws {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = try #require(TimeZone(identifier: "Europe/Berlin"))
    calendar.firstWeekday = 2 // Monday
    func date(_ day: Int) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: day, hour: 18))!
    }
    func session(_ day: Int, finished: Bool = true) -> Workout {
        Workout(title: "\(day)", startedAt: date(day), endedAt: finished ? date(day).addingTimeInterval(3600) : nil,
                exercises: [WorkoutExercise(exerciseId: bench.id, sets: [WorkoutSet(reps: 5, weightKg: 60, completedAt: date(day))])])
    }

    // Monday 19 to Sunday 25 October is one week; Sunday 18 belongs to the week before.
    let weeks = WorkoutHistory.weeks([session(18), session(19), session(25), session(22), session(24, finished: false)], calendar: calendar)

    #expect(weeks.map { $0.workouts.map(\.title) } == [["25", "22", "19"], ["18"]])
    #expect(weeks[0].start == calendar.date(from: DateComponents(year: 2026, month: 10, day: 19)))
    #expect(weeks[0].setCount == 3)
}

@Test func templateDaysStartFromTheSuggestionOrTheBottomOfTheRange() {
    let day = TemplateDay(name: "Push", exercises: [
        TemplateExercise(exerciseId: bench.id, restSeconds: 180, sets: [
            TemplateSet(repMin: 5, repMax: 8, targetRir: 2),
            TemplateSet(repMin: 5, repMax: 8, targetRir: 2),
            TemplateSet(repMin: 5, repMax: 8, targetRir: 2),
        ]),
        TemplateExercise(exerciseId: curl.id, restSeconds: 90, sets: [TemplateSet(repMin: 10, repMax: 12)]),
    ])
    let history = [workout(2, [(bench, [(60, 8), (62.5, 6)])])]

    let exercises = WorkoutLog.exercises(for: day, exercises: exercises, context: .init(history: history))

    #expect(exercises.map(\.restSeconds) == [180, 90])
    #expect(exercises[0].sets.map(\.weightKg) == [60, 62.5, 62.5])
    #expect(exercises[0].sets.map(\.reps) == [8, 7, 7])
    #expect(exercises[1].sets.map(\.reps) == [10])
    #expect(exercises[1].sets[0].weightKg == nil)
    #expect(exercises.allSatisfy { $0.sets.allSatisfy { !$0.isCompleted } })
}

@Test func aWorkoutBecomesATemplateOfItsDoneSets() {
    var done = workout(1, [(bench, [(60, 8), (60, 7)]), (curl, [])], rest: 150)
    done.exercises[0].sets.append(WorkoutSet(reps: 8, weightKg: 60))

    let template = WorkoutLog.template(from: done, name: "My push")

    #expect(template.isCustom)
    #expect(template.days.count == 1)
    #expect(template.days[0].exercises.map(\.exerciseId) == [bench.id])
    #expect(template.days[0].exercises[0].sets.map(\.repMax) == [8, 7])
    #expect(template.days[0].exercises[0].restSeconds == 150)
}
