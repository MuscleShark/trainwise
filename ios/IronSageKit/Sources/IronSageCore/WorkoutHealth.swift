import Foundation

/// A reading over a span of time, such as the active energy a Watch measured between two moments.
public struct HealthInterval: Hashable, Sendable {
    public var start: Date
    public var end: Date
    public var value: Double

    public init(start: Date, end: Date, value: Double) {
        self.start = start
        self.end = end
        self.value = value
    }
}

/// What Apple Health measured during a workout.
public enum WorkoutHealth {
    /// Average and maximum heart rate from the readings taken between `start` and `end`.
    public static func heartRate(_ readings: [HealthValue], from start: Date, to end: Date) -> (average: Int, maximum: Int)? {
        let during = readings.filter { $0.date >= start && $0.date <= end }.map(\.value)
        guard let maximum = during.max() else { return nil }
        let average = during.reduce(0, +) / Double(during.count)
        return (Int(average.rounded()), Int(maximum.rounded()))
    }

    /// Active energy (kcal) burned between `start` and `end`. A reading that only partly
    /// overlaps the workout counts for the overlapping share of its time.
    public static func activeEnergy(_ readings: [HealthInterval], from start: Date, to end: Date) -> Double? {
        var total = 0.0
        var any = false
        for reading in readings {
            let overlap = min(reading.end, end).timeIntervalSince(max(reading.start, start))
            let length = reading.end.timeIntervalSince(reading.start)
            if length <= 0 {
                // A reading at a single moment counts when it falls inside.
                guard reading.start >= start, reading.start <= end else { continue }
                total += reading.value
            } else {
                guard overlap > 0 else { continue }
                total += reading.value * overlap / length
            }
            any = true
        }
        return any ? (total * 10).rounded() / 10 : nil
    }

    /// True when two time spans overlap by more than half of the shorter one, which is how
    /// a workout the Watch recorded is recognised as the same session.
    public static func isSameSession(_ a: (start: Date, end: Date), _ b: (start: Date, end: Date)) -> Bool {
        let overlap = min(a.end, b.end).timeIntervalSince(max(a.start, b.start))
        let shorter = min(a.end.timeIntervalSince(a.start), b.end.timeIntervalSince(b.start))
        return shorter > 0 && overlap > shorter / 2
    }
}
