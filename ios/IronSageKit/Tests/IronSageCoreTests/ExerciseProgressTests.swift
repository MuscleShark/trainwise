import Foundation
import Testing

@testable import IronSageCore

struct ExerciseProgressTests {
    let squat = UUID()
    let other = UUID()

    func day(_ n: Int) -> Date {
        Date(timeIntervalSince1970: 1_792_800_000 + Double(n) * 86_400)
    }

    func set(_ kg: Double?, _ reps: Int?, done: Bool = true, warmup: Bool = false) -> WorkoutSet {
        WorkoutSet(setType: warmup ? .warmup : .working, reps: reps, weightKg: kg, completedAt: done ? day(0) : nil)
    }

    func workout(_ n: Int, _ sets: [WorkoutSet], finished: Bool = true) -> Workout {
        Workout(
            title: "Legs",
            startedAt: day(n),
            endedAt: finished ? day(n).addingTimeInterval(3600) : nil,
            exercises: [
                WorkoutExercise(exerciseId: squat, sets: sets),
                WorkoutExercise(exerciseId: other, sets: [set(200, 1)]),
            ]
        )
    }

    @Test func sessionsKeepCompletedWorkingSetsNewestFirst() throws {
        let sessions = ExerciseProgress.sessions(of: squat, in: [
            workout(1, [set(60, 10, warmup: true), set(100, 5), set(105, 3), set(110, 5, done: false)]),
            workout(3, [set(100, 6)]),
            workout(4, [set(120, 5)], finished: false),
            workout(5, [set(60, 5, warmup: true)]),
        ])
        #expect(sessions.map(\.date) == [day(3), day(1)])
        let first = try #require(sessions.last)
        #expect(first.sets.map(\.weightKg) == [100, 105])
        #expect(first.heaviestKg == 105)
        // 100 × 5 → 116.7; 105 × 3 → 115.5.
        #expect(abs((first.estimatedOneRepMax ?? 0) - 100 * (1 + 5.0 / 30)) < 0.001)
    }

    @Test func recordsKeepTheDayEachWasFirstSet() throws {
        let sessions = ExerciseProgress.sessions(of: squat, in: [
            workout(1, [set(100, 5), set(100, 8)]),
            workout(2, [set(110, 1), set(100, 8)]),
            workout(3, [set(110, 2), set(90, 12)]),
        ])
        let records = ExerciseProgress.records(sessions, loadType: .total)
        // Heaviest: 110 kg, and the 2-rep set beats the single.
        #expect(records.heaviest == .init(weightKg: 110, reps: 2, date: day(3)))
        // Best estimate: 90 × 12 = 126; 100 × 8 = 126.7 set on day 1 stays.
        #expect(records.bestEstimate == .init(weightKg: 100, reps: 8, date: day(1)))
        #expect(records.mostReps == [
            .init(weightKg: 110, reps: 2, date: day(3)),
            .init(weightKg: 100, reps: 8, date: day(1)),
            .init(weightKg: 90, reps: 12, date: day(3)),
        ])
    }

    @Test func bodyWeightSetsOnlyCountReps() {
        let sessions = ExerciseProgress.sessions(of: squat, in: [
            workout(1, [set(nil, 12), set(0, 15)]),
            workout(2, [set(10, 8)]),
        ])
        let records = ExerciseProgress.records(sessions, loadType: .total)
        #expect(records.heaviest == .init(weightKg: 10, reps: 8, date: day(2)))
        #expect(records.mostReps.last == .init(weightKg: 0, reps: 15, date: day(1)))
    }

    @Test func assistedExercisesHaveNoWeightRecords() {
        let sessions = ExerciseProgress.sessions(of: squat, in: [workout(1, [set(30, 8), set(20, 6)])])
        let records = ExerciseProgress.records(sessions, loadType: .assisted)
        #expect(records.heaviest == nil)
        #expect(records.bestEstimate == nil)
        #expect(records.mostReps == [
            .init(weightKg: 20, reps: 6, date: day(1)),
            .init(weightKg: 30, reps: 8, date: day(1)),
        ])
    }

    @Test func noSessionsMeansNoRecords() {
        #expect(ExerciseProgress.records([], loadType: .total).isEmpty)
    }
}
