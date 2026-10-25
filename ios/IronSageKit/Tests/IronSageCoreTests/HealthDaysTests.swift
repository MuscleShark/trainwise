import Foundation
import Testing

@testable import IronSageCore

private var berlin: Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "Europe/Berlin")!
    return calendar
}

// November: no daylight saving change (Berlin's falls on 25 October 2026, which makes a night an hour longer).
private func at(_ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
    berlin.date(from: DateComponents(year: 2026, month: 11, day: day, hour: hour, minute: minute))!
}

@Test func sleepCountsForTheMorningItEndsOn() {
    let night = [
        SleepSample(start: at(24, 23), end: at(25, 1), stage: .core),
        SleepSample(start: at(25, 1), end: at(25, 2, 30), stage: .deep),
        SleepSample(start: at(25, 2, 30), end: at(25, 3), stage: .awake),
        SleepSample(start: at(25, 3), end: at(25, 6, 30), stage: .rem),
        SleepSample(start: at(24, 22, 45), end: at(25, 6, 45), stage: .inBed),
    ]

    let days = HealthDays.readiness(sleep: night, hrv: [], restingHeartRate: [], calendar: berlin)

    #expect(days.map(\.date) == ["2026-11-25"])
    #expect(days[0].sleepMinutes == 120 + 90 + 210)
    #expect(days[0].deepMinutes == 90)
    #expect(days[0].awakeMinutes == 30)
}

@Test func theSameNightFromTwoDevicesIsCountedOnce() {
    let watch = SleepSample(start: at(24, 23), end: at(25, 7), stage: .core)
    let phone = SleepSample(start: at(24, 23, 30), end: at(25, 7, 30), stage: .asleep)

    let days = HealthDays.readiness(sleep: [watch, phone], hrv: [], restingHeartRate: [], calendar: berlin)

    #expect(days[0].sleepMinutes == 8 * 60 + 30)
}

@Test func hrvAndRestingHeartRateAreDailyAverages() {
    let hrv = [HealthValue(date: at(25, 3), value: 40), HealthValue(date: at(25, 9), value: 45.5), HealthValue(date: at(24, 9), value: 50)]
    let resting = [HealthValue(date: at(25, 8), value: 57.6)]

    let days = HealthDays.readiness(sleep: [], hrv: hrv, restingHeartRate: resting, calendar: berlin)

    #expect(days.map(\.date) == ["2026-11-24", "2026-11-25"])
    #expect(days[1].hrvSdnnMs == 42.8)
    #expect(days[1].restingHrBpm == 58)
    #expect(days[1].sleepMinutes == nil)
}

@Test func inBedAloneIsNotSleep() {
    let days = HealthDays.readiness(
        sleep: [SleepSample(start: at(24, 23), end: at(25, 7), stage: .inBed)],
        hrv: [], restingHeartRate: [], calendar: berlin
    )
    #expect(days.isEmpty)
}

@Test func theNightTheClocksGoBackCountsRealTime() {
    // 25 October 2026: Berlin's clocks go back an hour at 3:00, so 23:00 to 7:00 is nine hours.
    let start = berlin.date(from: DateComponents(year: 2026, month: 10, day: 24, hour: 23))!
    let end = berlin.date(from: DateComponents(year: 2026, month: 10, day: 25, hour: 7))!

    let days = HealthDays.readiness(sleep: [SleepSample(start: start, end: end, stage: .core)], hrv: [], restingHeartRate: [], calendar: berlin)

    #expect(days[0].sleepMinutes == 9 * 60)
}

@Test func aNightAcrossMidnightCountsWholeForTheMorning() {
    let night = [
        SleepSample(start: at(24, 22, 30), end: at(24, 23, 15), stage: .core),
        SleepSample(start: at(24, 23, 15), end: at(24, 23, 50), stage: .deep),
        SleepSample(start: at(24, 23, 55), end: at(25, 6, 30), stage: .core),
        // An afternoon nap is a night of its own, on the same day.
        SleepSample(start: at(25, 14), end: at(25, 14, 30), stage: .asleep),
    ]

    let days = HealthDays.readiness(sleep: night, hrv: [], restingHeartRate: [], calendar: berlin)

    #expect(days.map(\.date) == ["2026-11-25"])
    #expect(days[0].sleepMinutes == 45 + 35 + 395 + 30)
    #expect(days[0].deepMinutes == 35)
}
