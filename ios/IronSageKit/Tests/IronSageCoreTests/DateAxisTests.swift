import Foundation
import Testing

@testable import IronSageCore

struct DateAxisTests {
    var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        calendar.firstWeekday = 2
        return calendar
    }

    func date(_ year: Int, _ month: Int, _ day: Int, hour: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour))!
    }

    func days(_ ticks: [DateAxis.Tick]) -> [Int] {
        ticks.map { calendar.component(.day, from: $0.date) }
    }

    func months(_ ticks: [DateAxis.Tick]) -> [Int] {
        ticks.map { calendar.component(.month, from: $0.date) }
    }

    @Test func aWeekHasAMarkEachDay() {
        let ticks = DateAxis.ticks(from: date(2026, 10, 30, hour: 14), to: date(2026, 11, 6, hour: 14), calendar: calendar)
        #expect(days(ticks) == [31, 1, 2, 3, 4, 5, 6])
        #expect(ticks.allSatisfy { $0.label == .weekday })
    }

    @Test func aMonthHasAMarkEachMondayAndNamesTheMonthOnlyWhereItChanges() {
        let ticks = DateAxis.ticks(from: date(2026, 10, 6, hour: 9), to: date(2026, 11, 6, hour: 9), calendar: calendar)
        #expect(days(ticks) == [12, 19, 26, 2])
        #expect(ticks.map(\.label) == [.monthDay, .day, .day, .monthDay])
    }

    @Test func sixWeeksHaveAMarkEveryOtherWeek() {
        let ticks = DateAxis.ticks(from: date(2026, 9, 24), to: date(2026, 11, 4), calendar: calendar)
        // Mondays of even-numbered weeks: 28 Sep, 12 Oct, 26 Oct.
        #expect(ticks.count == 3)
        #expect(ticks.map(\.label) == [.monthDay, .monthDay, .day])
        #expect(ticks.allSatisfy { calendar.component(.weekday, from: $0.date) == 2 })
    }

    @Test func aYearHasAMarkEveryOtherMonthAndTheYearOnJanuary() {
        let ticks = DateAxis.ticks(from: date(2025, 11, 6), to: date(2026, 11, 6), calendar: calendar)
        #expect(months(ticks) == [1, 3, 5, 7, 9, 11])
        #expect(ticks.map(\.label) == [.year, .month, .month, .month, .month, .month])
    }

    @Test func aFewMonthsHaveAMarkEachMonth() {
        let ticks = DateAxis.ticks(from: date(2026, 6, 20), to: date(2026, 11, 6), calendar: calendar)
        #expect(months(ticks) == [7, 8, 9, 10, 11])
        #expect(ticks.allSatisfy { $0.label == .month })
    }

    @Test func aboutTwoYearsHaveAMarkEachQuarter() {
        let ticks = DateAxis.ticks(from: date(2025, 2, 10), to: date(2026, 11, 6), calendar: calendar)
        #expect(months(ticks) == [4, 7, 10, 1, 4, 7, 10])
        #expect(ticks[3].label == .year)
        #expect(ticks.filter { $0.label == .year }.count == 1)
    }

    @Test func manyYearsHaveAMarkEachYearOrFewer() {
        let three = DateAxis.ticks(from: date(2023, 3, 1), to: date(2026, 11, 6), calendar: calendar)
        #expect(three.map { calendar.component(.year, from: $0.date) } == [2024, 2025, 2026])
        #expect(three.allSatisfy { $0.label == .year })
        let twelve = DateAxis.ticks(from: date(2014, 3, 1), to: date(2026, 11, 6), calendar: calendar)
        #expect(twelve.map { calendar.component(.year, from: $0.date) } == [2016, 2019, 2022, 2025])
    }

    @Test func aMarkOnTheFirstMomentIsKept() {
        let ticks = DateAxis.ticks(from: date(2026, 1, 1), to: date(2026, 5, 15), calendar: calendar)
        #expect(months(ticks) == [1, 2, 3, 4, 5])
        #expect(ticks.first?.label == .year)
    }

    @Test func anEmptySpanHasNoMarks() {
        #expect(DateAxis.ticks(from: date(2026, 1, 1), to: date(2026, 1, 1), calendar: calendar).isEmpty)
    }
}
