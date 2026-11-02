import Foundation
import HealthKit
import IronSageCore
import IronSageStore
import OSLog

private let log = Logger(subsystem: "app.ironsage.IronSage", category: "health")

/// Reads sleep, HRV, resting heart rate, body weight, body fat and the cardio an Apple
/// Watch recorded from Apple Health into the store, which syncs them like any other
/// record, and saves finished workouts to it.
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
        static let forgottenWorkouts = "IronSage.health.forgottenWorkouts"
    }

    static let readTypes: Set<HKObjectType> = [
        HKCategoryType(.sleepAnalysis),
        HKQuantityType(.heartRateVariabilitySDNN),
        HKQuantityType(.restingHeartRate),
        HKQuantityType(.heartRate),
        HKQuantityType(.activeEnergyBurned),
        HKQuantityType(.bodyMass),
        HKQuantityType(.bodyFatPercentage),
        HKObjectType.workoutType(),
        // The distance of cardio a Watch recorded.
        HKQuantityType(.distanceWalkingRunning),
        HKQuantityType(.distanceCycling),
        HKQuantityType(.distanceRowing),
    ]

    static let writeTypes: Set<HKSampleType> = [
        HKObjectType.workoutType(),
        HKQuantityType(.activeEnergyBurned),
        HKQuantityType(.bodyMass),
        HKQuantityType(.bodyFatPercentage),
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
        defaults.removeObject(forKey: Keys.forgottenWorkouts)
    }

    /// Changes with every `reset()`, so work started before it can tell it is stale.
    @ObservationIgnored private var generation = 0

    /// Whether Apple's permission sheet has types the user hasn't been asked about yet,
    /// such as body fat for those who connected before IronSage read it.
    private(set) var hasNewTypes = false

    func checkForNewTypes() async {
        guard isAvailable, hasAsked else { return }
        let status = try? await healthStore.statusForAuthorizationRequest(toShare: Self.writeTypes, read: Self.readTypes)
        hasNewTypes = status == .shouldRequest
    }

    /// Shows Apple's permission sheet, then imports what was allowed.
    func connect() async {
        guard isAvailable else { return }
        do {
            try await healthStore.requestAuthorization(toShare: Self.writeTypes, read: Self.readTypes)
            hasAsked = true
            hasNewTypes = false
            defaults.set(true, forKey: Keys.asked)
            // Read the last 90 days again, for types allowed only now. What is already in
            // the store is skipped.
            defaults.removeObject(forKey: Keys.lastImport)
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
            let bodyFat = try await quantitySamples(.bodyFatPercentage, from: firstDay)
            let cardio = try await recordedCardio(from: firstDay)
            // Signed out or switched user while Apple Health was being read.
            guard generation == self.generation else { return }

            let firstKey = HealthDays.key(firstDay, calendar: calendar)
            for day in HealthDays.readiness(sleep: sleep, hrv: hrv, restingHeartRate: resting, calendar: calendar)
            where day.date >= firstKey && store.readiness[day.date] != day {
                store.save(day)
            }
            saveMeasurements(weights, kind: .weight)
            saveMeasurements(bodyFat, kind: .bodyFat)
            saveCardio(cardio)
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

    /// Weights or body fat from other apps and devices. IronSage's own entries are
    /// already in the store.
    private func saveMeasurements(_ samples: [HKQuantitySample], kind: MeasurementKind) {
        guard let health = Self.healthType(kind) else { return }
        let known = Set(store.bodyMeasurements.compactMap(\.healthkitSampleId))
        for sample in samples {
            let id = sample.uuid.uuidString
            guard !known.contains(id), sample.sourceRevision.source.bundleIdentifier != Bundle.main.bundleIdentifier else { continue }
            let value = (sample.quantity.doubleValue(for: health.unit) * health.scale * 1000).rounded() / 1000
            store.save(BodyMeasurement(id: sample.uuid, measuredAt: sample.endDate, kind: kind, value: value, source: .healthkit, healthkitSampleId: id))
        }
    }

    /// Apple Health's type for a measurement, its unit, and what turns that unit into the
    /// stored one: Apple Health keeps body fat as a fraction (0.18), IronSage as percent (18).
    private static func healthType(_ kind: MeasurementKind) -> (type: HKQuantityType, unit: HKUnit, scale: Double)? {
        switch kind {
        case .weight: (HKQuantityType(.bodyMass), .gramUnit(with: .kilo), 1)
        case .bodyFat: (HKQuantityType(.bodyFatPercentage), .percent(), 100)
        default: nil
        }
    }

    // MARK: Cardio the Watch recorded

    /// Cardio workouts other apps and devices (an Apple Watch) recorded, with the
    /// exercise each one is.
    private func recordedCardio(from start: Date) async throws -> [(workout: HKWorkout, exerciseID: UUID)] {
        let predicate = HKQuery.predicateForSamples(withStart: start, end: nil)
        let query = HKSampleQueryDescriptor(predicates: [.workout(predicate)], sortDescriptors: [])
        return try await query.result(for: healthStore).compactMap { workout in
            guard workout.sourceRevision.source.bundleIdentifier != Bundle.main.bundleIdentifier,
                  let slug = Self.cardioSlug(for: workout)
            else { return nil }
            return (workout, ExerciseVisuals.builtinID(slug: slug))
        }
    }

    /// The built-in cardio exercise for a workout type, inside (a treadmill, a bike) or out.
    static func cardioSlug(for workout: HKWorkout) -> String? {
        let indoor = workout.metadata?[HKMetadataKeyIndoorWorkout] as? Bool ?? false
        return switch workout.workoutActivityType {
        case .walking: indoor ? "incline_walk" : "outdoor_walk"
        case .hiking: "outdoor_walk"
        case .running: indoor ? "treadmill_run" : "outdoor_run"
        case .cycling: indoor ? "exercise_bike" : "outdoor_ride"
        case .stairClimbing, .stairs, .stepTraining: "stair_climber"
        case .elliptical: "elliptical"
        case .rowing: "rowing_machine"
        default: nil
        }
    }

    /// Adds recorded cardio not seen before: into the IronSage workout it happened during,
    /// or as a workout of its own. Cardio removed in the app isn't brought back.
    private func saveCardio(_ recorded: [(workout: HKWorkout, exerciseID: UUID)]) {
        var known = Set(store.workouts.flatMap { workout in
            [workout.healthkitWorkoutId].compactMap { $0 } + workout.exercises.flatMap { $0.sets.compactMap(\.healthkitWorkoutId) }
        })
        known.formUnion(forgotten)
        for (workout, exerciseID) in recorded.sorted(by: { $0.workout.startDate < $1.workout.startDate }) {
            let id = workout.uuid.uuidString
            // The catalog may not have arrived yet; the next import tries again.
            guard !known.contains(id), store.exercises[exerciseID] != nil else { continue }
            known.insert(id)
            let item = WorkoutExercise(exerciseId: exerciseID, sets: [Self.cardioSet(workout)])
            let span = (workout.startDate, workout.endDate)
            if var host = store.finishedWorkouts.first(where: { finished in
                guard !finished.isFromAppleWatch, let end = finished.endedAt else { return false }
                return WorkoutHealth.isSameSession((finished.startedAt, end), span)
            }) {
                host.exercises.append(item)
                store.save(host)
            } else {
                store.save(Workout(
                    title: store.exerciseName(exerciseID),
                    startedAt: workout.startDate,
                    endedAt: workout.endDate,
                    healthkitWorkoutId: id,
                    exercises: [item]
                ))
            }
        }
    }

    private static func cardioSet(_ workout: HKWorkout) -> WorkoutSet {
        let bpm = HKUnit.count().unitDivided(by: .minute())
        let heart = workout.statistics(for: HKQuantityType(.heartRate))?.averageQuantity()?.doubleValue(for: bpm)
        let energy = workout.statistics(for: HKQuantityType(.activeEnergyBurned))?.sumQuantity()?.doubleValue(for: .kilocalorie())
        let distance = [HKQuantityType(.distanceWalkingRunning), HKQuantityType(.distanceCycling), HKQuantityType(.distanceRowing)]
            .lazy.compactMap { workout.statistics(for: $0)?.sumQuantity()?.doubleValue(for: .meter()) }.first
        return WorkoutSet(
            durationSeconds: min(Int(workout.duration.rounded()), 86_400),
            distanceM: distance.map { min(($0 * 100).rounded() / 100, 1_000_000) },
            avgHeartRate: heart.map { Int($0.rounded()) }.flatMap { (20...250).contains($0) ? $0 : nil },
            energyKcal: energy.map { min(Int($0.rounded()), 10_000) },
            healthkitWorkoutId: workout.uuid.uuidString,
            completedAt: workout.endDate
        )
    }

    /// Recorded cardio the user removed: kept out of the next imports on this iPhone.
    private var forgotten: Set<String> {
        Set(defaults.stringArray(forKey: Keys.forgottenWorkouts) ?? [])
    }

    func forgetWatchWorkout(_ id: String) {
        defaults.set(Array(forgotten.union([id])), forKey: Keys.forgottenWorkouts)
    }

    // MARK: Writing body measurements

    /// Saves a weight or body fat the user typed in to Apple Health and keeps the sample's
    /// id with it, so it can be removed again and isn't imported back.
    func saveToHealth(_ measurement: BodyMeasurement) async {
        guard isAvailable, hasAsked, measurement.healthkitSampleId == nil,
              let health = Self.healthType(measurement.kind),
              healthStore.authorizationStatus(for: health.type) == .sharingAuthorized
        else { return }
        let sample = HKQuantitySample(
            type: health.type,
            quantity: HKQuantity(unit: health.unit, doubleValue: measurement.value / health.scale),
            start: measurement.measuredAt,
            end: measurement.measuredAt,
            metadata: [HKMetadataKeyExternalUUID: measurement.id.uuidString]
        )
        do {
            try await healthStore.save(sample)
            guard var latest = store.bodyMeasurements.first(where: { $0.id == measurement.id }) else {
                // Deleted while Apple Health was saving it.
                try await healthStore.delete(sample)
                return
            }
            latest.healthkitSampleId = sample.uuid.uuidString
            store.save(latest)
        } catch {
            log.error("Saving a body measurement to Apple Health failed: \(error, privacy: .public)")
        }
    }

    /// Removes a weight or body fat IronSage wrote to Apple Health. It is found by
    /// IronSage's own id, so this works from another iPhone too.
    func removeFromHealth(_ measurement: BodyMeasurement) async {
        guard isAvailable, measurement.source == .manual, let health = Self.healthType(measurement.kind) else { return }
        do {
            let predicate = HKQuery.predicateForObjects(withMetadataKey: HKMetadataKeyExternalUUID, allowedValues: [measurement.id.uuidString])
            try await healthStore.deleteObjects(of: health.type, predicate: predicate)
        } catch {
            log.error("Removing a body measurement from Apple Health failed: \(error, privacy: .public)")
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
            // Cardio logged in the app gets the heart rate from its own minutes.
            func cardioHeart(_ set: WorkoutSet) -> Int? {
                guard set.healthkitWorkoutId == nil, let done = set.completedAt, let seconds = set.durationSeconds, seconds > 0 else { return set.avgHeartRate }
                return set.avgHeartRate ?? WorkoutHealth.heartRate(heartRates, from: done.addingTimeInterval(-TimeInterval(seconds)), to: done)?.average
            }

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
            for e in latest.exercises.indices where store.exercises[latest.exercises[e].exerciseId]?.isCardio == true {
                for s in latest.exercises[e].sets.indices {
                    latest.exercises[e].sets[s].avgHeartRate = cardioHeart(latest.exercises[e].sets[s])
                }
            }
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

    /// Removes a workout IronSage wrote. One the Watch recorded is left alone, and its
    /// cardio isn't imported again.
    func removeFromHealth(_ workout: Workout) async {
        for id in workout.exercises.flatMap({ $0.sets.compactMap(\.healthkitWorkoutId) }) {
            forgetWatchWorkout(id)
        }
        guard !workout.isFromAppleWatch, isAvailable, let id = workout.healthkitWorkoutId.flatMap(UUID.init(uuidString:)) else { return }
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

    /// A workout another app or the Watch recorded over the same time. Cardio recorded
    /// during it doesn't count: that is part of the workout, not the workout itself.
    private func watchWorkout(from start: Date, to end: Date) async throws -> HKWorkout? {
        let predicate = HKQuery.predicateForSamples(withStart: start.addingTimeInterval(-3600), end: end.addingTimeInterval(3600))
        let query = HKSampleQueryDescriptor(predicates: [.workout(predicate)], sortDescriptors: [])
        return try await query.result(for: healthStore).first { recorded in
            recorded.sourceRevision.source.bundleIdentifier != Bundle.main.bundleIdentifier
                && Self.cardioSlug(for: recorded) == nil
                && WorkoutHealth.isSameSession((start, end), (recorded.startDate, recorded.endDate))
        }
    }

    private func writeWorkout(_ workout: Workout, from start: Date, to end: Date) async throws -> UUID {
        let configuration = HKWorkoutConfiguration()
        configuration.activityType = .traditionalStrengthTraining
        configuration.locationType = .indoor
        // Cardio on its own is saved as that cardio (a stair climber session), not as lifting.
        if Cardio.isCardioOnly(workout, exercises: store.exercises), let first = workout.exercises.first,
           let type = Self.activity[first.exerciseId] {
            configuration.activityType = type.activity
            configuration.locationType = type.indoor ? .indoor : .outdoor
        }
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

    /// Apple Health's workout type for each built-in cardio exercise.
    private static let activity: [UUID: (activity: HKWorkoutActivityType, indoor: Bool)] = [
        "incline_walk": (HKWorkoutActivityType.walking, true), "treadmill_run": (.running, true), "stair_climber": (.stairClimbing, true),
        "exercise_bike": (.cycling, true), "rowing_machine": (.rowing, true), "elliptical": (.elliptical, true),
        "outdoor_walk": (.walking, false), "outdoor_run": (.running, false), "outdoor_ride": (.cycling, false),
    ].reduce(into: [:]) { $0[ExerciseVisuals.builtinID(slug: $1.key)] = $1.value }

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
