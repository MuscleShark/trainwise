import Foundation
import HealthKit
import IronSageCore
import IronSageStore
import OSLog

private let log = Logger(subsystem: "app.ironsage.IronSage", category: "health")

/// Reads sleep, HRV, resting heart rate and body weight from Apple Health into the
/// store, which syncs them like any other record.
///
/// Apple Health never says whether reading was allowed (that would itself reveal health
/// information), so the app only knows whether it has asked. Data that wasn't allowed
/// simply never arrives.
@MainActor
@Observable
final class HealthService {
    private(set) var hasAsked: Bool
    private(set) var isImporting = false
    private var introDismissed: Bool

    @ObservationIgnored let healthStore = HKHealthStore()
    @ObservationIgnored private let store: LocalStore
    @ObservationIgnored private let enabled: Bool
    @ObservationIgnored private let defaults = UserDefaults.standard

    /// How far back the first import reaches.
    static let firstImportDays = 90

    private enum Keys {
        static let asked = "IronSage.health.asked"
        static let introDismissed = "IronSage.health.introDismissed"
        static let lastImport = "IronSage.health.lastImport"
    }

    static let readTypes: Set<HKObjectType> = [
        HKCategoryType(.sleepAnalysis),
        HKQuantityType(.heartRateVariabilitySDNN),
        HKQuantityType(.restingHeartRate),
        HKQuantityType(.heartRate),
        HKQuantityType(.activeEnergyBurned),
        HKQuantityType(.bodyMass),
        HKObjectType.workoutType(),
    ]

    static let writeTypes: Set<HKSampleType> = [
        HKObjectType.workoutType(),
        HKQuantityType(.activeEnergyBurned),
        HKQuantityType(.bodyMass),
    ]

    /// `enabled` is false in demo mode, which never touches Apple Health.
    init(store: LocalStore, enabled: Bool) {
        self.store = store
        self.enabled = enabled
        hasAsked = UserDefaults.standard.bool(forKey: Keys.asked)
        introDismissed = UserDefaults.standard.bool(forKey: Keys.introDismissed)
    }

    var isAvailable: Bool {
        enabled && HKHealthStore.isHealthDataAvailable()
    }

    /// Show the explanation page once: available, not asked yet, not put off.
    var shouldOfferConnection: Bool {
        isAvailable && !hasAsked && !introDismissed
    }

    func dismissIntro() {
        defaults.set(true, forKey: Keys.introDismissed)
        introDismissed = true
    }

    /// After another user's data was removed: the next import reaches back 90 days again,
    /// and an import still running for the previous user stops without writing anything.
    /// Apple Health's permission belongs to the phone, so whether we asked stays.
    func reset() {
        generation += 1
        isImporting = false
        defaults.removeObject(forKey: Keys.lastImport)
    }

    /// Changes with every `reset()`, so work started before it can tell it is stale.
    @ObservationIgnored private var generation = 0

    /// Shows Apple's permission sheet, then imports what was allowed.
    func connect() async {
        guard isAvailable else { return }
        do {
            try await healthStore.requestAuthorization(toShare: Self.writeTypes, read: Self.readTypes)
            hasAsked = true
            defaults.set(true, forKey: Keys.asked)
            await importRecent()
        } catch {
            log.error("Asking for Apple Health access failed: \(error, privacy: .public)")
        }
    }

    /// Brings in what changed since the last import (the last 90 days the first time).
    /// The last two days are read again, since a night or a day's average can still change.
    /// Whole days are read, so each day it saves is complete.
    func importRecent() async {
        guard isAvailable, hasAsked, !isImporting else { return }
        isImporting = true
        let generation = generation
        defer {
            if generation == self.generation { isImporting = false }
        }

        let now = Date.now
        let calendar = Calendar.current
        let last = defaults.object(forKey: Keys.lastImport) as? Date
        let back = last.map { calendar.date(byAdding: .day, value: -2, to: $0)! }
            ?? calendar.date(byAdding: .day, value: -Self.firstImportDays, to: now)!
        let firstDay = calendar.startOfDay(for: back)
        // The night that ends on the first day started the evening before.
        let sleepStart = firstDay.addingTimeInterval(-12 * 3600)

        do {
            let sleep = try await categorySamples(.sleepAnalysis, from: sleepStart).compactMap(Self.sleepSample)
            let hrv = try await values(.heartRateVariabilitySDNN, unit: .secondUnit(with: .milli), from: firstDay)
            let resting = try await values(.restingHeartRate, unit: .count().unitDivided(by: .minute()), from: firstDay)
            let weights = try await quantitySamples(.bodyMass, from: firstDay)
            // Signed out or switched user while Apple Health was being read.
            guard generation == self.generation else { return }

            let firstKey = HealthDays.key(firstDay, calendar: calendar)
            for day in HealthDays.readiness(sleep: sleep, hrv: hrv, restingHeartRate: resting, calendar: calendar)
            where day.date >= firstKey && store.readiness[day.date] != day {
                store.save(day)
            }
            saveBodyMass(weights)
            defaults.set(now, forKey: Keys.lastImport)
        } catch {
            log.error("Importing from Apple Health failed: \(error, privacy: .public)")
        }
    }

    // MARK: Reading

    private func categorySamples(_ id: HKCategoryTypeIdentifier, from start: Date) async throws -> [HKCategorySample] {
        let predicate = HKQuery.predicateForSamples(withStart: start, end: nil)
        let query = HKSampleQueryDescriptor(predicates: [.categorySample(type: HKCategoryType(id), predicate: predicate)], sortDescriptors: [])
        return try await query.result(for: healthStore)
    }

    func quantitySamples(_ id: HKQuantityTypeIdentifier, from start: Date, to end: Date? = nil) async throws -> [HKQuantitySample] {
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end)
        let query = HKSampleQueryDescriptor(predicates: [.quantitySample(type: HKQuantityType(id), predicate: predicate)], sortDescriptors: [])
        return try await query.result(for: healthStore)
    }

    private func values(_ id: HKQuantityTypeIdentifier, unit: HKUnit, from start: Date) async throws -> [HealthValue] {
        try await quantitySamples(id, from: start).map { HealthValue(date: $0.startDate, value: $0.quantity.doubleValue(for: unit)) }
    }

    /// Weights from other apps and devices. IronSage's own entries are already in the store.
    private func saveBodyMass(_ samples: [HKQuantitySample]) {
        let known = Set(store.bodyMeasurements.compactMap(\.healthkitSampleId))
        for sample in samples {
            let id = sample.uuid.uuidString
            guard !known.contains(id), sample.sourceRevision.source.bundleIdentifier != Bundle.main.bundleIdentifier else { continue }
            let kg = (sample.quantity.doubleValue(for: .gramUnit(with: .kilo)) * 1000).rounded() / 1000
            store.save(BodyMeasurement(id: sample.uuid, measuredAt: sample.endDate, value: kg, source: .healthkit, healthkitSampleId: id))
        }
    }

    private static func sleepSample(_ sample: HKCategorySample) -> SleepSample? {
        let stage: SleepStage? = switch HKCategoryValueSleepAnalysis(rawValue: sample.value) {
        case .inBed: .inBed
        case .awake: .awake
        case .asleepCore: .core
        case .asleepDeep: .deep
        case .asleepREM: .rem
        case .asleepUnspecified: .asleep
        default: nil
        }
        return stage.map { SleepSample(start: sample.startDate, end: sample.endDate, stage: $0) }
    }
}
