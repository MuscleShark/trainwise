import Foundation

// Turns raw Apple Health samples into one Readiness per day. Kept free of HealthKit so
// it can be tested; the app converts HealthKit samples into these types.

public enum SleepStage: Sendable, Hashable {
    case inBed, awake, core, deep, rem
    /// Asleep, without a stage (older devices and some apps).
    case asleep
}

public struct SleepSample: Sendable, Hashable {
    public let start: Date
    public let end: Date
    public let stage: SleepStage

    public init(start: Date, end: Date, stage: SleepStage) {
        self.start = start
        self.end = end
        self.stage = stage
    }
}

public struct HealthValue: Sendable, Hashable {
    public let date: Date
    public let value: Double

    public init(date: Date, value: Double) {
        self.date = date
        self.value = value
    }
}

public enum HealthDays {
    /// "2026-10-25" for `date` in `calendar`'s time zone.
    public static func key(_ date: Date, calendar: Calendar = .current) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year!, c.month!, c.day!)
    }

    /// Midday of the day a key names, in `calendar`'s time zone; nil for a malformed key.
    /// Midday keeps adding and subtracting days clear of daylight-saving changes.
    public static func date(_ key: String, calendar: Calendar = .current) -> Date? {
        let parts = key.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        return calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2], hour: 12))
    }

    /// Sleep counts for the day it ended on (the morning you wake up). Overlapping
    /// samples, such as the same night from a watch and a phone, are merged so time is
    /// not counted twice. HRV and resting heart rate are averaged per day.
    public static func readiness(
        sleep: [SleepSample],
        hrv: [HealthValue],
        restingHeartRate: [HealthValue],
        calendar: Calendar = .current
    ) -> [Readiness] {
        var days: [String: Readiness] = [:]
        func day(_ key: String) -> Readiness { days[key] ?? Readiness(date: key) }

        // A night is many short stage samples, some before midnight and some after: group
        // them into nights first, then count each night for the day it ends on.
        let byDay = Dictionary(grouping: nights(sleep)) { key($0.map(\.end).max()!, calendar: calendar) }
            .mapValues { $0.flatMap { $0 } }
        for (key, samples) in byDay {
            var r = day(key)
            let asleepStages: Set<SleepStage> = [.core, .deep, .rem, .asleep]
            let asleep = minutes(samples.filter { asleepStages.contains($0.stage) })
            r.sleepMinutes = asleep > 0 ? asleep : nil
            r.deepMinutes = optionalMinutes(samples.filter { $0.stage == .deep })
            r.remMinutes = optionalMinutes(samples.filter { $0.stage == .rem })
            r.coreMinutes = optionalMinutes(samples.filter { $0.stage == .core })
            r.awakeMinutes = optionalMinutes(samples.filter { $0.stage == .awake })
            days[key] = r
        }
        for (key, values) in Dictionary(grouping: hrv, by: { key($0.date, calendar: calendar) }) {
            var r = day(key)
            r.hrvSdnnMs = (average(values) * 10).rounded() / 10
            days[key] = r
        }
        for (key, values) in Dictionary(grouping: restingHeartRate, by: { key($0.date, calendar: calendar) }) {
            var r = day(key)
            r.restingHrBpm = average(values).rounded()
            days[key] = r
        }
        return days.values.filter { !$0.isEmpty }.sorted { $0.date < $1.date }
    }

    /// Samples less than this apart belong to the same night.
    static let nightGap: TimeInterval = 3 * 3600

    /// Sleep samples grouped into nights: runs with no gap of `nightGap` or more.
    static func nights(_ samples: [SleepSample]) -> [[SleepSample]] {
        var nights: [[SleepSample]] = []
        var end = Date.distantPast
        for sample in samples.sorted(by: { $0.start < $1.start }) {
            if nights.isEmpty || sample.start.timeIntervalSince(end) >= nightGap {
                nights.append([sample])
            } else {
                nights[nights.count - 1].append(sample)
            }
            end = max(end, sample.end)
        }
        return nights
    }

    /// Minutes covered by the samples, overlaps counted once.
    static func minutes(_ samples: [SleepSample]) -> Int {
        let sorted = samples.map { ($0.start, $0.end) }.filter { $0.0 < $0.1 }.sorted { $0.0 < $1.0 }
        var total: TimeInterval = 0
        var current: (Date, Date)?
        for interval in sorted {
            if let open = current, interval.0 <= open.1 {
                current = (open.0, max(open.1, interval.1))
            } else {
                if let open = current { total += open.1.timeIntervalSince(open.0) }
                current = interval
            }
        }
        if let open = current { total += open.1.timeIntervalSince(open.0) }
        return Int((total / 60).rounded())
    }

    private static func optionalMinutes(_ samples: [SleepSample]) -> Int? {
        samples.isEmpty ? nil : minutes(samples)
    }

    private static func average(_ values: [HealthValue]) -> Double {
        values.map(\.value).reduce(0, +) / Double(values.count)
    }
}
