import Foundation
import Testing

@testable import IronSageCore

struct CardioTests {
    let walk = Exercise(
        nameEn: "Incline walk", equipment: .machine, loadType: .total, primaryMuscles: [.glutes, .calves],
        isCustom: false, kind: .cardio, cardioMetrics: [.incline, .speed, .distance]
    )
    let bench = Exercise(
        nameEn: "Bench press", equipment: .barbell, loadType: .total,
        primaryMuscles: [.chest], secondaryMuscles: [.frontDelts, .triceps], isCustom: false
    )
    var exercises: [UUID: Exercise] { [walk.id: walk, bench.id: bench] }

    var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        calendar.firstWeekday = 2
        return calendar
    }

    /// Monday 2 November 2026, midday UTC, plus `days`.
    func day(_ days: Int) -> Date {
        Date(timeIntervalSince1970: 1_793_620_800 + Double(days) * 86_400)
    }

    func walked(_ minutes: Int, on days: Int, incline: Double = 12, done: Bool = true) -> WorkoutExercise {
        WorkoutExercise(exerciseId: walk.id, sets: [
            WorkoutSet(durationSeconds: minutes * 60, distanceM: 1200, speedKmh: 4.83, inclinePct: incline, completedAt: done ? day(days) : nil),
        ])
    }

    func workout(_ days: Int, _ items: [WorkoutExercise]) -> Workout {
        Workout(title: "W", startedAt: day(days), endedAt: day(days).addingTimeInterval(3600), exercises: items)
    }

    @Test func theNextSessionStartsFromLastTimesSettingsNotItsDistance() {
        let history = [workout(-2, [walked(15, on: -2, incline: 12)]), workout(-9, [walked(10, on: -9, incline: 8)])]
        let suggestion = NextSession.suggest(walk, context: .init(history: history))
        #expect(suggestion.change == .cardio(firstTime: false))
        #expect(suggestion.sets.count == 1)
        let planned = suggestion.sets[0]
        #expect(planned.durationSeconds == 900 && planned.inclinePct == 12 && planned.speedKmh == 4.83)
        #expect(planned.distanceM == nil && !planned.isCompleted)
    }

    @Test func theFirstTimeFollowsTheTemplatesTargets() {
        let target = TemplateExercise(exerciseId: walk.id, sets: [TemplateSet(durationSeconds: 1200, inclinePct: 10)])
        let suggestion = NextSession.suggest(walk, template: target, context: .init(history: []))
        #expect(suggestion.change == .cardio(firstTime: true))
        #expect(suggestion.sets[0].durationSeconds == 1200 && suggestion.sets[0].inclinePct == 10)
    }

    @Test func cardioCountsAsMinutesNotAsSetsPerMuscle() {
        let workouts = [
            workout(0, [walked(15, on: 0), WorkoutExercise(exerciseId: bench.id, sets: [WorkoutSet(reps: 8, weightKg: 60, completedAt: day(0))])]),
            workout(2, [walked(30, on: 2)]),
            workout(3, [walked(20, on: 3, done: false)]),
            workout(-7, [walked(25, on: -7)]),
        ]
        let week = calendar.dateInterval(of: .weekOfYear, for: day(0))!
        let sets = TrainingProgress.weeklySets(in: workouts, exercises: exercises, week: week)
        #expect(sets.map(\.muscle) == [.chest, .frontDelts, .triceps])

        let minutes = Cardio.weeklyMinutes(in: workouts, exercises: exercises, weeks: 3, now: day(4), calendar: calendar)
        #expect(minutes.map(\.minutes) == [0, 25, 45])
        #expect(Cardio.sessions(in: workouts, exercises: exercises, from: week.start).map(\.workoutID) == [workouts[1].id, workouts[0].id])
        #expect(Cardio.isCardioOnly(workouts[1], exercises: exercises))
        #expect(!Cardio.isCardioOnly(workouts[0], exercises: exercises))
        #expect(TrainingProgress.recentExercises(in: workouts, skipping: [walk.id]) == [bench.id])
    }

    @Test func distanceAndSpeedFollowTheWeightUnit() {
        #expect(CardioUnits.meters(fromDistance: 0.75, unit: .lb) == 1207.01)
        #expect(CardioUnits.meters(fromDistance: 1.2, unit: .kg) == 1200)
        #expect(CardioUnits.kmh(fromSpeed: 3.0, unit: .lb) == 4.83)
        #expect(abs(CardioUnits.speed(fromKmh: 4.83, unit: .lb) - 3.0) < 0.01)
        #expect(CardioUnits.incline(12.34) == 12.3)
    }
}
