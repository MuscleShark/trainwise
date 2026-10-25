import Foundation

/// Weights are stored in kilograms (three decimals, so pounds survive the trip) and
/// shown in the user's unit.
public enum WeightUnit: String, Sendable, CaseIterable {
    case kg, lb

    public static let kilogramsPerPound = 0.45359237

    public init(_ system: UnitSystem) {
        self = system == .imperial ? .lb : .kg
    }

    /// The unit for someone without a profile yet, from the phone's region.
    public static func `default`(for locale: Locale = .current) -> WeightUnit {
        locale.measurementSystem == .us ? .lb : .kg
    }

    public func value(fromKilograms kg: Double) -> Double {
        switch self {
        case .kg: kg
        case .lb: kg / Self.kilogramsPerPound
        }
    }

    /// Kilograms to store, rounded to the API's three decimals.
    public func kilograms(from value: Double) -> Double {
        let kg = self == .kg ? value : value * Self.kilogramsPerPound
        return (kg * 1000).rounded() / 1000
    }

    /// "60", "61.25", "135", "132.3": kilograms to two decimals (1.25 kg plates),
    /// pounds to one, without trailing zeros.
    public func format(kilograms kg: Double, locale: Locale = .current) -> String {
        rounded(value(fromKilograms: kg))
            .formatted(.number.precision(.fractionLength(0...decimals)).locale(locale))
    }

    /// Decimals worth showing in this unit.
    public var decimals: Int {
        self == .kg ? 2 : 1
    }

    /// A value in this unit, rounded to the decimals worth showing.
    public func rounded(_ value: Double) -> Double {
        let scale = self == .kg ? 100.0 : 10.0
        return (value * scale).rounded() / scale
    }

    /// The step for + and −: the smallest common plate jump. Barbells and machine
    /// stacks move by 2.5 kg or 5 lb, one dumbbell or one side by 1.25 kg or 2.5 lb.
    public func increment(for loadType: LoadType) -> Double {
        switch (self, loadType) {
        case (.kg, .perSide): 1.25
        case (.kg, _): 2.5
        case (.lb, .perSide): 2.5
        case (.lb, _): 5
        }
    }

    /// Moves a weight `steps` increments up or down, landing on a multiple of the
    /// increment: 61 kg goes up to 62.5 and down to 60.
    public func step(kilograms kg: Double, by steps: Int, loadType: LoadType) -> Double {
        let increment = increment(for: loadType)
        let current = value(fromKilograms: kg) / increment
        let base = steps > 0 ? (current + 0.001).rounded(.down) : (current - 0.001).rounded(.up)
        return kilograms(from: max(0, (base + Double(steps)) * increment))
    }
}
