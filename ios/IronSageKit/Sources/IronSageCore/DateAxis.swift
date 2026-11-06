import Foundation

/// Where a time chart's x-axis gets its marks and what each one says, the way Health and
/// most training apps draw it: marks on calendar boundaries (each day, each week's
/// first day, the first of a month, the first of a year) so they don't drift as the
/// range changes, and short labels that name the month or the year only where it
/// changes.
public enum DateAxis {
    /// What a mark's label shows.
    public enum Label: Hashable, Sendable {
        /// "Mon".
        case weekday
        /// "13", a day in the month already named.
        case day
        /// "Oct 13", the first mark or the first in a new month.
        case monthDay
        /// "Oct".
        case month
        /// "2026", a mark on the first of January.
        case year
    }

    public struct Tick: Hashable, Sendable {
        public let date: Date
        public let label: Label

        public init(date: Date, label: Label) {
            self.date = date
            self.label = label
        }
    }

    /// The marks between `start` and `end` (both included). The spacing follows the
    /// span: a mark a day up to about a week and a half, a week up to five weeks, every
    /// other week up to about ten weeks, a month up to about seven months, two months up to about thirteen, three months
    /// up to a little over two years, then whole years.
    public static func ticks(from start: Date, to end: Date, calendar: Calendar = .current) -> [Tick] {
        guard end > start else { return [] }
        let days = end.timeIntervalSince(start) / 86_400
        switch days {
        case ...10:
            return dates(from: start, to: end, calendar: calendar, matching: DateComponents(hour: 0, minute: 0, second: 0))
                .map { Tick(date: $0, label: .weekday) }
        case ...35:
            return weeks(from: start, to: end, every: 1, calendar: calendar)
        case ...75:
            return weeks(from: start, to: end, every: 2, calendar: calendar)
        case ...210:
            return months(from: start, to: end, every: 1, calendar: calendar)
        case ...400:
            return months(from: start, to: end, every: 2, calendar: calendar)
        case ...800:
            return months(from: start, to: end, every: 3, calendar: calendar)
        default:
            let years = days / 365.25
            let every = max(1, Int((years / 5).rounded(.up)))
            return dates(from: start, to: end, calendar: calendar, matching: DateComponents(month: 1, day: 1, hour: 0, minute: 0, second: 0))
                .filter { calendar.component(.year, from: $0) % every == 0 }
                .map { Tick(date: $0, label: .year) }
        }
    }

    /// The first day of every `every`th week (every other one by week number, so the
    /// marks don't shift as the range moves). The first mark and the first in a new
    /// month name the month.
    private static func weeks(from start: Date, to end: Date, every: Int, calendar: Calendar) -> [Tick] {
        let weekStarts = dates(
            from: start, to: end, calendar: calendar,
            matching: DateComponents(hour: 0, minute: 0, second: 0, weekday: calendar.firstWeekday)
        )
        .filter { calendar.component(.weekOfYear, from: $0) % every == 0 }
        return weekStarts.enumerated().map { index, date in
            let newMonth = index == 0 || !calendar.isDate(date, equalTo: weekStarts[index - 1], toGranularity: .month)
            return Tick(date: date, label: newMonth ? .monthDay : .day)
        }
    }

    /// The first of every `every`th month counted from January (Jan, Mar, May… or Jan,
    /// Apr, Jul, Oct), so the marks land on the same months whatever the range. January
    /// shows the year instead.
    private static func months(from start: Date, to end: Date, every: Int, calendar: Calendar) -> [Tick] {
        dates(from: start, to: end, calendar: calendar, matching: DateComponents(day: 1, hour: 0, minute: 0, second: 0))
            .filter { (calendar.component(.month, from: $0) - 1) % every == 0 }
            .map { Tick(date: $0, label: calendar.component(.month, from: $0) == 1 ? .year : .month) }
    }

    private static func dates(from start: Date, to end: Date, calendar: Calendar, matching components: DateComponents) -> [Date] {
        var found: [Date] = []
        // `start` itself when it is on a boundary, then each following one.
        let first = calendar.date(start, matchesComponents: components)
            ? start
            : calendar.nextDate(after: start, matching: components, matchingPolicy: .nextTime)
        guard let first else { return [] }
        calendar.enumerateDates(startingAfter: first, matching: components, matchingPolicy: .nextTime) { date, _, stop in
            guard let date, date <= end else {
                stop = true
                return
            }
            found.append(date)
        }
        return first <= end ? [first] + found : []
    }
}
