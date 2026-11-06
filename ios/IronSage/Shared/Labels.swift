import Foundation
import IronSageCore
import IronSageStore

extension LocalStore {
    /// The user's unit, or the region's until a profile exists.
    var weightUnit: WeightUnit {
        profile.map { WeightUnit($0.unitSystem) } ?? .default()
    }

    func exerciseName(_ id: UUID) -> String {
        exercises[id]?.name(chinese: AppLanguage.isChinese) ?? String(appLocalized: "Unknown exercise")
    }
}

extension WeightUnit {
    var symbol: LocalizedStringResource {
        switch self {
        case .kg: "kg"
        case .lb: "lb"
        }
    }

    /// "60 kg"
    func formatWithUnit(kilograms: Double) -> String {
        "\(format(kilograms: kilograms)) \(String(appLocalized: symbol))"
    }

    /// "60 kg × 8", or "× 12" for a set without weight.
    func formatSet(_ set: WorkoutSet) -> String {
        let reps = set.reps.map(String.init) ?? "–"
        guard let weight = set.weightKg, weight > 0 else { return "× \(reps)" }
        return "\(formatWithUnit(kilograms: weight)) × \(reps)"
    }
}

extension Muscle {
    var label: LocalizedStringResource {
        switch self {
        case .chest: "Chest"
        case .upperBack: "Upper back"
        case .lats: "Lats"
        case .traps: "Traps"
        case .frontDelts: "Front delts"
        case .sideDelts: "Side delts"
        case .rearDelts: "Rear delts"
        case .biceps: "Biceps"
        case .triceps: "Triceps"
        case .forearms: "Forearms"
        case .abs: "Abs"
        case .obliques: "Obliques"
        case .lowerBack: "Lower back"
        case .glutes: "Glutes"
        case .quads: "Quads"
        case .hamstrings: "Hamstrings"
        case .adductors: "Adductors"
        case .abductors: "Abductors"
        case .calves: "Calves"
        }
    }
}

extension Equipment {
    var label: LocalizedStringResource {
        switch self {
        case .barbell: "Barbell"
        case .dumbbell: "Dumbbell"
        case .machine: "Machine"
        case .cable: "Cable"
        case .smith: "Smith machine"
        case .bodyweight: "Bodyweight"
        case .kettlebell: "Kettlebell"
        case .band: "Band"
        case .other: "Other"
        }
    }
}

extension LoadType {
    var label: LocalizedStringResource {
        switch self {
        case .total: "Total weight"
        case .perSide: "Per dumbbell or side"
        case .bodyweightPlus: "Added to bodyweight"
        case .assisted: "Assistance"
        }
    }
}

extension SetType {
    var label: LocalizedStringResource {
        switch self {
        case .warmup: "Warm-up"
        case .working: "Working set"
        case .drop: "Drop set"
        case .failure: "To failure"
        }
    }

    /// One letter in the set column; working sets show their number instead.
    var badge: LocalizedStringResource? {
        switch self {
        case .warmup: "W"
        case .drop: "D"
        case .failure: "F"
        case .working: nil
        }
    }
}

extension Duration {
    /// "1:05:12" or "3:00".
    static func clock(_ seconds: TimeInterval) -> String {
        Duration.seconds(Int(seconds.rounded())).formatted(
            .time(pattern: seconds >= 3600 ? .hourMinuteSecond : .minuteSecond)
        )
    }
}

extension Date {
    /// "Oct 21", with the year only when it isn't this year: "Oct 21, 2025".
    var shortDay: String {
        Calendar.current.isDate(self, equalTo: .now, toGranularity: .year)
            ? formatted(.dateTime.month().day().locale(AppLanguage.locale))
            : formatted(.dateTime.month().day().year().locale(AppLanguage.locale))
    }

    /// "Sat, Oct 24", with the year only when it isn't this year.
    var shortDayWithWeekday: String {
        Calendar.current.isDate(self, equalTo: .now, toGranularity: .year)
            ? formatted(.dateTime.weekday(.abbreviated).month().day().locale(AppLanguage.locale))
            : formatted(.dateTime.weekday(.abbreviated).month().day().year().locale(AppLanguage.locale))
    }
}
