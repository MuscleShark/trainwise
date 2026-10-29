import Foundation
import Testing

@testable import IronSageCore

struct TrainingProgressTests {
    let bench = Exercise(
        nameEn: "Bench press", equipment: .barbell, loadType: .total,
        primaryMuscles: [.chest], secondaryMuscles: [.frontDelts, .triceps], isCustom: false
    )
    let curl = Exercise(
        nameEn: "Curl", equipment: .dumbbell, loadType: .perSide,
        primaryMuscles: [.biceps], secondaryMuscles: [.forearms, .biceps], isCustom: false
    )
    var exercises: [UUID: Exercise] { [bench.id: bench, curl.id: curl] }

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

    func set(_ kg: Double, _ reps: Int, done: Bool = true, warmup: Bool = false) -> WorkoutSet {
        WorkoutSet(setType: warmup ? .warmup : .working, reps: reps, weightKg: kg, completedAt: done ? day(0) : nil)
    }

    func workout(_ days: Int, _ items: [(Exercise, [WorkoutSet])], finished: Bool = true) -> Workout {
        Workout(
            title: "W",
            startedAt: day(days),
            endedAt: finished ? day(days).addingTimeInterval(3600) : nil,
            exercises: items.map { WorkoutExercise(exerciseId: $0.0.id, sets: $0.1) }
        )
    }

    @Test func primaryMusclesCountOneAndSecondaryHalf() {
        let week = calendar.dateInterval(of: .weekOfYear, for: day(0))!
        let sets = TrainingProgress.weeklySets(in: [
            workout(0, [(bench, [set(60, 8, warmup: true), set(80, 5), set(80, 5), set(80, 5, done: false)])]),
            workout(3, [(bench, [set(80, 5)]), (curl, [set(12, 10), set(12, 10)])]),
            workout(7, [(bench, [set(80, 5)])]),  // next week
            workout(-1, [(bench, [set(80, 5)])]),  // last week
            workout(4, [(curl, [set(12, 10)])], finished: false),
        ], exercises: exercises, week: week)
        #expect(sets.map(\.muscle) == [.chest, .biceps, .frontDelts, .triceps, .forearms])
        #expect(sets.map(\.sets) == [3, 2, 1.5, 1.5, 1])
    }

    @Test func weeklyVolumeIncludesEmptyWeeksOldestFirst() {
        let volume = TrainingProgress.weeklyVolume(in: [
            workout(1, [(bench, [set(100, 5)])]),
            workout(-6, [(curl, [set(10, 10)])]),  // per side: 200
            workout(-20, [(bench, [set(100, 1)])]),  // three weeks back: outside
        ], exercises: exercises, weeks: 3, now: day(2), calendar: calendar)
        #expect(volume.map(\.kilograms) == [0, 200, 500])
        #expect(volume.last?.start == calendar.dateInterval(of: .weekOfYear, for: day(0))!.start)
    }

    @Test func workoutsThisWeekCountsOnlyFinishedOnesInTheWeek() {
        let count = TrainingProgress.workoutsThisWeek(in: [
            workout(0, [(bench, [set(100, 5)])]),
            workout(2, [(bench, [set(100, 5)])]),
            workout(3, [(bench, [set(100, 5)])], finished: false),
            workout(-1, [(bench, [set(100, 5)])]),  // last Sunday
        ], now: day(3), calendar: calendar)
        #expect(count == 2)
    }

    @Test func weekStreakCountsWeeksInARowWithTraining() {
        let workouts = [
            workout(1, [(bench, [set(100, 5)])]),
            workout(-6, [(bench, [set(100, 5)])]),
            workout(-5, [(bench, [set(100, 5)])]),
            workout(-13, [(bench, [set(100, 5)])]),
            workout(-27, [(bench, [set(100, 5)])]),  // after a week off
        ]
        #expect(TrainingProgress.weekStreak(in: workouts, now: day(2), calendar: calendar) == 3)
    }

    @Test func weekStreakIsNotBrokenBeforeThisWeekEnds() {
        let workouts = [
            workout(-6, [(bench, [set(100, 5)])]),
            workout(-13, [(bench, [set(100, 5)])]),
        ]
        #expect(TrainingProgress.weekStreak(in: workouts, now: day(2), calendar: calendar) == 2)
        #expect(TrainingProgress.weekStreak(in: workouts, now: day(9), calendar: calendar) == 0)
        #expect(TrainingProgress.weekStreak(in: [], now: day(2), calendar: calendar) == 0)
    }

    @Test func recentExercisesComeFirst() {
        let order = TrainingProgress.recentExercises(in: [
            workout(0, [(bench, [set(80, 5)])]),
            workout(2, [(curl, [set(12, 10)])]),
            workout(3, [(bench, [set(80, 5, done: false)])]),
        ])
        #expect(order == [curl.id, bench.id])
    }

    @Test func onlyAWeightFromAppleHealthAsksForConfirmation() {
        let typed = BodyMeasurement(measuredAt: day(0), value: 80, source: .manual)
        let imported = BodyMeasurement(measuredAt: day(1), value: 81, source: .healthkit)
        let waist = BodyMeasurement(measuredAt: day(2), kind: .waist, value: 85, source: .manual)
        let latest = BodyWeight.latest([typed, imported, waist])
        #expect(latest == imported)
        #expect(BodyWeight.needsConfirmation(imported, confirmed: []))
        #expect(!BodyWeight.needsConfirmation(imported, confirmed: [imported.id]))
        #expect(!BodyWeight.needsConfirmation(typed, confirmed: []))
        #expect(BodyWeight.latest([waist]) == nil)
    }

    @Test func trendKeepsRecentWeightsOldestFirst() {
        let old = BodyMeasurement(measuredAt: day(-40), value: 82, source: .manual)
        let a = BodyMeasurement(measuredAt: day(-3), value: 81, source: .manual)
        let b = BodyMeasurement(measuredAt: day(-10), value: 81.5, source: .healthkit)
        #expect(BodyWeight.trend([a, old, b], days: 30, now: day(0)) == [b, a])
    }
}
