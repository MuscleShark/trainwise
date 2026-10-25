import Foundation

/// Last night's sleep, HRV and resting heart rate, each next to the user's own usual:
/// the average of the 28 days before. Plain comparisons, no combined score.
public enum ReadinessComparison {
    public static let baselineDays = 28
    /// Fewer days than this and there is no usual yet.
    public static let minimumDays = 7

    public enum Direction: Hashable, Sendable {
        case lower, usual, higher
    }

    public struct Metric: Hashable, Sendable {
        public let value: Double
        /// Nil until there are enough earlier days.
        public let usual: Double?
        public let direction: Direction?
    }

    public struct Day: Hashable, Sendable {
        public let date: String
        /// Minutes asleep.
        public let sleep: Metric?
        /// Milliseconds.
        public let hrv: Metric?
        /// Beats per minute.
        public let restingHeartRate: Metric?

        public var isEmpty: Bool { sleep == nil && hrv == nil && restingHeartRate == nil }
    }

    /// How far a value must be from the usual to count as lower or higher.
    static let sleepMargin = 30.0  // minutes
    static let hrvMargin = 0.1  // a tenth of the usual
    static let restingMargin = 3.0  // bpm

    /// The comparison for `date` (YYYY-MM-DD), from the days recorded. Days are keyed by
    /// date, so the baseline is the 28 dates before it, whichever of them have data.
    public static func compare(_ days: [String: Readiness], on date: String, calendar: Calendar = .current) -> Day? {
        guard let today = days[date], !today.isEmpty, let start = HealthDays.date(date, calendar: calendar) else { return nil }
        let earlier = (1...baselineDays).compactMap { back -> Readiness? in
            calendar.date(byAdding: .day, value: -back, to: start).flatMap { days[HealthDays.key($0, calendar: calendar)] }
        }
        func metric(_ value: Double?, _ history: [Double], margin: (Double) -> Double) -> Metric? {
            guard let value else { return nil }
            guard history.count >= minimumDays else { return Metric(value: value, usual: nil, direction: nil) }
            let usual = history.reduce(0, +) / Double(history.count)
            let difference = value - usual
            let direction: Direction = abs(difference) < margin(usual) ? .usual : (difference < 0 ? .lower : .higher)
            return Metric(value: value, usual: usual, direction: direction)
        }
        let day = Day(
            date: date,
            sleep: metric(today.sleepMinutes.map(Double.init), earlier.compactMap(\.sleepMinutes).map(Double.init)) { _ in sleepMargin },
            hrv: metric(today.hrvSdnnMs, earlier.compactMap(\.hrvSdnnMs)) { $0 * hrvMargin },
            restingHeartRate: metric(today.restingHrBpm, earlier.compactMap(\.restingHrBpm)) { _ in restingMargin }
        )
        return day.isEmpty ? nil : day
    }
}
