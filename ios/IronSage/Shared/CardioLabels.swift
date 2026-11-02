import Foundation
import IronSageCore
import IronSageStore

extension CardioMetric {
    var label: LocalizedStringResource {
        switch self {
        case .incline: "Incline"
        case .speed: "Speed"
        case .distance: "Distance"
        case .level: LocalizedStringResource("machineLevel", defaultValue: "Level")
        case .resistance: "Resistance"
        case .damper: "Damper"
        case .floors: "Floors"
        }
    }

    /// The machine's level, resistance or damper: all kept in `WorkoutSet.level`.
    var isLevel: Bool { self == .level || self == .resistance || self == .damper }
}

extension Exercise {
    /// A rower's distance is in meters whatever the unit; everything else in mi or km.
    var distanceInMeters: Bool { cardioMetrics.contains(.damper) }
}

/// Cardio's numbers as the app shows them: "15 min · 0.75 mi · 3.0 mph · 12%".
enum CardioText {
    static func minutes(_ seconds: Int) -> String {
        // Whole minutes as "15 min"; a time the Watch measured to the second as "22:04".
        seconds % 60 == 0 ? String(appLocalized: "\(seconds / 60) min") : Duration.clock(TimeInterval(seconds))
    }

    static func distanceUnit(_ unit: WeightUnit, meters: Bool) -> String {
        meters ? "m" : unit == .lb ? "mi" : "km"
    }

    static func speedUnit(_ unit: WeightUnit) -> String {
        unit == .lb ? "mph" : "km/h"
    }

    static func distance(_ meters: Double, unit: WeightUnit, inMeters: Bool) -> String {
        let value = inMeters ? meters : CardioUnits.distance(fromMeters: meters, unit: unit)
        let digits = inMeters ? 0 : 2
        return "\(value.formatted(.number.precision(.fractionLength(0...digits)).locale(AppLanguage.locale))) \(distanceUnit(unit, meters: inMeters))"
    }

    static func speed(_ kmh: Double, unit: WeightUnit) -> String {
        let value = CardioUnits.speed(fromKmh: kmh, unit: unit)
        return "\(value.formatted(.number.precision(.fractionLength(1)).locale(AppLanguage.locale))) \(speedUnit(unit))"
    }

    static func incline(_ percent: Double) -> String {
        "\(percent.formatted(.number.precision(.fractionLength(0...1)).locale(AppLanguage.locale)))%"
    }

    static func level(_ value: Int, metric: CardioMetric) -> String {
        switch metric {
        case .resistance: String(appLocalized: "Resistance \(value)")
        case .damper: String(appLocalized: "Damper \(value)")
        default: String(appLocalized: "Level \(value)")
        }
    }

    /// Everything a done (or planned) cardio set has, in the exercise's order, time first.
    static func summary(_ set: WorkoutSet, exercise: Exercise?, unit: WeightUnit) -> String {
        var parts: [String] = []
        if let seconds = set.durationSeconds { parts.append(minutes(seconds)) }
        let metrics = exercise?.cardioMetrics ?? [.distance]
        for metric in metrics {
            switch metric {
            case .distance: if let meters = set.distanceM { parts.append(distance(meters, unit: unit, inMeters: exercise?.distanceInMeters == true)) }
            case .speed: if let kmh = set.speedKmh { parts.append(speed(kmh, unit: unit)) }
            case .incline: if let percent = set.inclinePct { parts.append(incline(percent)) }
            case .floors: if let floors = set.floors { parts.append(String(appLocalized: "\(floors) floors")) }
            case .level, .resistance, .damper: if let value = set.level { parts.append(level(value, metric: metric)) }
            }
        }
        // A Watch-recorded outdoor workout may have a distance its exercise doesn't list.
        if !metrics.contains(.distance), let meters = set.distanceM {
            parts.append(distance(meters, unit: unit, inMeters: false))
        }
        return parts.isEmpty ? "–" : parts.joined(separator: " · ")
    }

    /// A template's target: "15 min · 12% · 3.0 mph".
    static func target(_ set: TemplateSet, exercise: Exercise?, unit: WeightUnit) -> String {
        summary(WorkoutSet(durationSeconds: set.durationSeconds, speedKmh: set.speedKmh, inclinePct: set.inclinePct, level: set.level), exercise: exercise, unit: unit)
    }
}

extension Workout {
    /// A cardio workout read from Apple Health (an Apple Watch run, a stair climber
    /// session), not one logged in IronSage.
    var isFromAppleWatch: Bool {
        guard let id = healthkitWorkoutId else { return false }
        return !exercises.isEmpty && exercises.allSatisfy { $0.sets.allSatisfy { $0.healthkitWorkoutId == id } }
    }
}

extension LocalStore {
    var cardioExerciseIDs: Set<UUID> {
        Set(exercises.values.filter(\.isCardio).map(\.id))
    }

    /// Cardio the Watch recorded on the day of `date` that isn't part of a workout yet.
    func watchCardio(on date: Date, calendar: Calendar = .current) -> [Workout] {
        finishedWorkouts.filter { $0.isFromAppleWatch && calendar.isDate($0.startedAt, inSameDayAs: date) }
    }
}
