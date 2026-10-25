import Foundation
import Testing

@testable import IronSageCore

struct ReadinessComparisonTests {
    var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Berlin")!
        return calendar
    }

    /// `days` days of the same night before 2026-11-30, plus that day itself.
    func history(days: Int, today: Readiness) -> [String: Readiness] {
        var all = ["2026-11-30": today]
        let end = HealthDays.date("2026-11-30", calendar: calendar)!
        for back in stride(from: 1, through: days, by: 1) {
            let key = HealthDays.key(calendar.date(byAdding: .day, value: -back, to: end)!, calendar: calendar)
            all[key] = Readiness(date: key, sleepMinutes: 420, hrvSdnnMs: 50, restingHrBpm: 55)
        }
        return all
    }

    @Test func comparesEachValueWithTheUsual() throws {
        let today = Readiness(date: "2026-11-30", sleepMinutes: 360, hrvSdnnMs: 52, restingHrBpm: 60)
        let day = try #require(ReadinessComparison.compare(history(days: 28, today: today), on: "2026-11-30", calendar: calendar))
        #expect(day.sleep == .init(value: 360, usual: 420, direction: .lower))
        // 2 ms from a usual of 50 is within a tenth.
        #expect(day.hrv == .init(value: 52, usual: 50, direction: .usual))
        #expect(day.restingHeartRate == .init(value: 60, usual: 55, direction: .higher))
    }

    @Test func onlyTheTwentyEightDaysBeforeCount() throws {
        var days = history(days: 28, today: Readiness(date: "2026-11-30", sleepMinutes: 420))
        // A long night 29 days back, outside the window.
        days["2026-11-01"] = Readiness(date: "2026-11-01", sleepMinutes: 900)
        let day = try #require(ReadinessComparison.compare(days, on: "2026-11-30", calendar: calendar))
        #expect(day.sleep?.usual == 420)
    }

    @Test func noUsualBeforeAWeekOfData() throws {
        let today = Readiness(date: "2026-11-30", sleepMinutes: 400)
        let day = try #require(ReadinessComparison.compare(history(days: 6, today: today), on: "2026-11-30", calendar: calendar))
        #expect(day.sleep == .init(value: 400, usual: nil, direction: nil))
        #expect(day.hrv == nil)
    }

    @Test func nothingForADayWithoutData() {
        let days = history(days: 28, today: Readiness(date: "2026-11-30"))
        #expect(ReadinessComparison.compare(days, on: "2026-11-30", calendar: calendar) == nil)
        #expect(ReadinessComparison.compare(days, on: "2026-12-01", calendar: calendar) == nil)
    }

    @Test func dateKeysRoundTrip() {
        #expect(HealthDays.date("2026-10-25", calendar: calendar).map { HealthDays.key($0, calendar: calendar) } == "2026-10-25")
        #expect(HealthDays.date("not a date", calendar: calendar) == nil)
    }
}
