import Foundation
import HealthKit
import IronSageCore
import IronSageStore
import OSLog

private let log = Logger(subsystem: "app.ironsage.IronSage", category: "health")

/// Reads sleep, HRV, resting heart rate and body weight from Apple Health into the
/// store, which syncs them like any other record, and saves finished workouts to it.
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
        await saveRecentWorkouts()
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

    // MARK: Writing workouts

    /// Saves a finished workout to Apple Health, with the active energy and heart rate a
    /// Watch measured during it. If the Watch recorded the session as a workout itself, that
    /// one is kept and linked instead of adding a second; so is one IronSage already wrote
    /// from another iPhone sharing the same Apple Health data. Keeps the heart rate on the workout.
    func saveToHealth(_ workout: Workout) async {
        // The stored copy: sync may have linked it since the caller read it.
        let workout = store.workouts.first { $0.id == workout.id } ?? workout
        guard isAvailable, hasAsked, workout.healthkitWorkoutId == nil, let end = workout.endedAt,
              healthStore.authorizationStatus(for: .workoutType()) == .sharingAuthorized,
              !writing.contains(workout.id)
        else { return }
        writing.insert(workout.id)
        defer { writing.remove(workout.id) }
        let generation = generation

        let start = workout.startedAt
        do {
            let heartRates = try await quantitySamples(.heartRate, from: start, to: end)
                .map { HealthValue(date: $0.startDate, value: $0.quantity.doubleValue(for: .count().unitDivided(by: .minute()))) }
            let heart = WorkoutHealth.heartRate(heartRates, from: start, to: end)

            let id: UUID
            if let saved = try await savedWorkout(workout.id) {
                id = saved.uuid
            } else if let recorded = try await watchWorkout(from: start, to: end) {
                id = recorded.uuid
            } else {
                // Signed out or switched user meanwhile: don't write the previous user's workout.
                guard generation == self.generation else { return }
                id = try await writeWorkout(workout, from: start, to: end)
            }
            // The workout may have changed while Apple Health was busy: update the latest copy.
            guard var latest = store.workouts.first(where: { $0.id == workout.id }) else { return }
            latest.healthkitWorkoutId = id.uuidString
            latest.avgHeartRate = heart?.average
            latest.maxHeartRate = heart?.maximum
            store.save(latest)
        } catch {
            log.error("Saving a workout to Apple Health failed: \(error, privacy: .public)")
        }
    }

    /// Workouts finished in the last two days that aren't in Apple Health yet, for example
    /// because saving failed or Apple Health was connected just after.
    func saveRecentWorkouts() async {
        let since = Date.now.addingTimeInterval(-2 * 86_400)
        for workout in store.finishedWorkouts where workout.healthkitWorkoutId == nil && (workout.endedAt ?? .distantPast) > since {
            await saveToHealth(workout)
        }
    }

    /// Removes a workout IronSage wrote. One the Watch recorded is left alone.
    func removeFromHealth(_ workout: Workout) async {
        guard isAvailable, let id = workout.healthkitWorkoutId.flatMap(UUID.init(uuidString:)) else { return }
        do {
            let predicate = HKQuery.predicateForObjects(with: [id])
            let query = HKSampleQueryDescriptor(predicates: [.workout(predicate)], sortDescriptors: [])
            let found = try await query.result(for: healthStore)
                .filter { $0.sourceRevision.source.bundleIdentifier == Bundle.main.bundleIdentifier }
            if !found.isEmpty {
                try await healthStore.delete(found)
            }
        } catch {
            log.error("Removing a workout from Apple Health failed: \(error, privacy: .public)")
        }
    }

    @ObservationIgnored private var writing: Set<UUID> = []

    /// The workout IronSage wrote for this logged workout, from this phone or another one.
    private func savedWorkout(_ id: UUID) async throws -> HKWorkout? {
        let predicate = HKQuery.predicateForObjects(withMetadataKey: HKMetadataKeyExternalUUID, allowedValues: [id.uuidString])
        let query = HKSampleQueryDescriptor(predicates: [.workout(predicate)], sortDescriptors: [], limit: 1)
        return try await query.result(for: healthStore).first
    }

    /// A workout another app or the Watch recorded over the same time.
    private func watchWorkout(from start: Date, to end: Date) async throws -> HKWorkout? {
        let predicate = HKQuery.predicateForSamples(withStart: start.addingTimeInterval(-3600), end: end.addingTimeInterval(3600))
        let query = HKSampleQueryDescriptor(predicates: [.workout(predicate)], sortDescriptors: [])
        return try await query.result(for: healthStore).first { recorded in
            recorded.sourceRevision.source.bundleIdentifier != Bundle.main.bundleIdentifier
                && WorkoutHealth.isSameSession((start, end), (recorded.startDate, recorded.endDate))
        }
    }

    private func writeWorkout(_ workout: Workout, from start: Date, to end: Date) async throws -> UUID {
        let configuration = HKWorkoutConfiguration()
        configuration.activityType = .traditionalStrengthTraining
        configuration.locationType = .indoor
        let builder = HKWorkoutBuilder(healthStore: healthStore, configuration: configuration, device: .local())
        do {
            try await builder.beginCollection(at: start)

            // Energy the Watch measured during the session, when writing energy is allowed.
            // Apple Health counts each moment once across sources, so this doesn't add to
            // the day's total.
            if healthStore.authorizationStatus(for: HKQuantityType(.activeEnergyBurned)) == .sharingAuthorized {
                let energy = try await quantitySamples(.activeEnergyBurned, from: start, to: end)
                    .filter { $0.sourceRevision.source.bundleIdentifier != Bundle.main.bundleIdentifier }
                    .map { HealthInterval(start: $0.startDate, end: $0.endDate, value: $0.quantity.doubleValue(for: .kilocalorie())) }
                if let kcal = WorkoutHealth.activeEnergy(energy, from: start, to: end), kcal > 0 {
                    let sample = HKQuantitySample(
                        type: HKQuantityType(.activeEnergyBurned),
                        quantity: HKQuantity(unit: .kilocalorie(), doubleValue: kcal),
                        start: start,
                        end: end
                    )
                    try await builder.addSamples([sample])
                }
            }

            try await builder.addMetadata([
                HKMetadataKeyExternalUUID: workout.id.uuidString,
                HKMetadataKeyWorkoutBrandName: "IronSage",
            ])
            try await builder.endCollection(at: end)
            guard let saved = try await builder.finishWorkout() else {
                throw CocoaError(.coderInvalidValue)
            }
            return saved.uuid
        } catch {
            builder.discardWorkout()
            throw error
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
