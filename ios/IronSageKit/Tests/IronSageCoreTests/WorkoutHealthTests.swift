import Foundation
import Testing
@testable import IronSageCore

struct WorkoutHealthTests {
    let start = Date(timeIntervalSince1970: 1_800_000_000)
    var end: Date { start.addingTimeInterval(3600) }

    @Test func heartRateUsesOnlyReadingsDuringTheWorkout() throws {
        let readings = [
            HealthValue(date: start.addingTimeInterval(-60), value: 180),
            HealthValue(date: start.addingTimeInterval(60), value: 100),
            HealthValue(date: start.addingTimeInterval(1800), value: 151),
            HealthValue(date: end, value: 120),
            HealthValue(date: end.addingTimeInterval(60), value: 190),
        ]
        let heart = try #require(WorkoutHealth.heartRate(readings, from: start, to: end))
        #expect(heart.average == 124)
        #expect(heart.maximum == 151)
    }

    @Test func noReadingsMeansNoHeartRate() {
        #expect(WorkoutHealth.heartRate([], from: start, to: end) == nil)
    }

    @Test func energyCountsTheOverlappingShare() {
        let readings = [
            // Half inside: 10 of 20 kcal.
            HealthInterval(start: start.addingTimeInterval(-600), end: start.addingTimeInterval(600), value: 20),
            // Fully inside.
            HealthInterval(start: start.addingTimeInterval(1200), end: start.addingTimeInterval(1800), value: 50.04),
            // A moment inside, and one outside.
            HealthInterval(start: start.addingTimeInterval(2000), end: start.addingTimeInterval(2000), value: 3),
            HealthInterval(start: end.addingTimeInterval(10), end: end.addingTimeInterval(10), value: 99),
            // Entirely after.
            HealthInterval(start: end, end: end.addingTimeInterval(600), value: 40),
        ]
        #expect(WorkoutHealth.activeEnergy(readings, from: start, to: end) == 63)
    }

    @Test func noEnergyReadingsMeansNoEnergy() {
        let after = [HealthInterval(start: end.addingTimeInterval(60), end: end.addingTimeInterval(120), value: 5)]
        #expect(WorkoutHealth.activeEnergy(after, from: start, to: end) == nil)
    }

    @Test func aWatchWorkoutOverTheSameTimeIsTheSameSession() {
        let logged = (start: start, end: end)
        #expect(WorkoutHealth.isSameSession(logged, (start.addingTimeInterval(120), end.addingTimeInterval(300))))
        // A short Watch workout mostly inside the session.
        #expect(WorkoutHealth.isSameSession(logged, (start.addingTimeInterval(600), start.addingTimeInterval(1200))))
        // A morning run that only touches the start.
        #expect(!WorkoutHealth.isSameSession(logged, (start.addingTimeInterval(-1800), start.addingTimeInterval(300))))
        #expect(!WorkoutHealth.isSameSession(logged, (end, end.addingTimeInterval(600))))
    }
}
