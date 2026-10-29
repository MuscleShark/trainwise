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

    func fat(_ days: Int, _ percent: Double) -> BodyMeasurement {
        BodyMeasurement(measuredAt: day(days), kind: .bodyFat, value: percent, source: .healthkit)
    }

    @Test func bodyTrendShowsOneKindInTheRangeOldestFirst() {
        let weight = BodyMeasurement(measuredAt: day(-2), value: 80, source: .manual)
        let measurements = [fat(-1, 18), fat(-10, 19), fat(-40, 20), weight]
        let week = BodyTrend.points(measurements, kind: .bodyFat, range: .week, now: day(0), calendar: calendar)
        #expect(week.map(\.value) == [18])
        let month = BodyTrend.points(measurements, kind: .bodyFat, range: .month, now: day(0), calendar: calendar)
        #expect(month.map(\.value) == [19, 18])
        let all = BodyTrend.points(measurements, kind: .bodyFat, range: .all, now: day(0), calendar: calendar)
        #expect(all.map(\.value) == [20, 19, 18])
        #expect(BodyTrend.latest(measurements, kind: .bodyFat)?.value == 18)
        #expect(BodyTrend.latest(measurements, kind: .weight) == weight)
    }

    @Test func bodyTrendAveragesEachWeekOverLongSpans() {
        // Monday and Wednesday of one week, half a year before a single later weigh-in.
        let measurements = [fat(-196, 20), fat(-194, 22), fat(0, 18)]
        let points = BodyTrend.points(measurements, kind: .bodyFat, range: .year, now: day(1), calendar: calendar)
        #expect(points.map(\.value) == [21, 18])
        #expect(points.first?.date == day(-195))
    }

    @Test func bodyTrendKeepsEachMeasurementOverShortSpans() {
        let measurements = [fat(-6, 20), fat(-5, 22), fat(0, 18)]
        let points = BodyTrend.points(measurements, kind: .bodyFat, range: .all, now: day(1), calendar: calendar)
        #expect(points.map(\.value) == [20, 22, 18])
    }
}
