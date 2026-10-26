import CryptoKit
import Foundation
import IronSageCore
import OSLog
import SwiftData

private let log = Logger(subsystem: "app.ironsage.IronSage", category: "store")

/// The user's data on the phone. Views read it and every edit is saved here first, so
/// the app works without a connection; `SyncEngine` sends edits to the API later.
///
/// Records are kept in memory as the app's own types and written through to SwiftData.
@MainActor
@Observable
public final class LocalStore {
    /// Every exercise ever seen, deleted ones included, so past workouts keep names.
    public private(set) var exercises: [UUID: Exercise] = [:]
    /// Exercises that were deleted (custom) or retired from the catalog.
    public private(set) var removedExerciseIDs: Set<UUID> = []
    /// Newest first.
    public private(set) var workouts: [Workout] = []
    public private(set) var templates: [Template] = []
    public private(set) var profile: Profile?
    /// Newest first.
    public private(set) var bodyMeasurements: [BodyMeasurement] = []
    /// By date, "2026-10-25".
    public private(set) var readiness: [String: Readiness] = [:]
    /// The AI coach's requests and advice, newest first.
    public private(set) var recommendations: [Recommendation] = []

    @ObservationIgnored private let context: ModelContext

    /// Keeps data on disk; `inMemory` is for tests and previews.
    public init(inMemory: Bool = false) throws {
        let configuration = ModelConfiguration("IronSage", isStoredInMemoryOnly: inMemory)
        let container = try ModelContainer(for: StoredRecord.self, configurations: configuration)
        context = ModelContext(container)
        context.autosaveEnabled = false
        reload()
    }

    // MARK: Reading

    /// Exercises that can be added to a workout, by name.
    public var availableExercises: [Exercise] {
        exercises.values
            .filter { !removedExerciseIDs.contains($0.id) }
            .sorted { $0.nameEn.localizedStandardCompare($1.nameEn) == .orderedAscending }
    }

    public var activeWorkout: Workout? {
        workouts.first(where: \.isInProgress)
    }

    public var finishedWorkouts: [Workout] {
        workouts.filter { !$0.isInProgress }
    }

    /// Edits the server does not have yet.
    public var hasUnsyncedChanges: Bool {
        !pendingChanges().isEmpty
    }

    public var hasBuiltInExercises: Bool {
        exercises.values.contains { !$0.isCustom }
    }

    // MARK: Local edits

    public func save(_ workout: Workout) {
        write(.workout, workout.id, workout)
        cacheWorkout(workout)
    }

    public func deleteWorkout(id: UUID) {
        markDeleted(.workout, id)
        workouts.removeAll { $0.id == id }
    }

    /// Saves one of the user's own exercises.
    public func save(_ exercise: Exercise) {
        precondition(exercise.isCustom, "Built-in exercises come from the catalog")
        write(.exercise, exercise.id, exercise)
        exercises[exercise.id] = exercise
        removedExerciseIDs.remove(exercise.id)
    }

    public func deleteExercise(id: UUID) {
        markDeleted(.exercise, id)
        removedExerciseIDs.insert(id)
    }

    /// Saves one of the user's own templates.
    public func save(_ template: Template) {
        precondition(template.isCustom, "Built-in templates come from the catalog")
        write(.template, template.id, template)
        cacheTemplate(template)
    }

    public func deleteTemplate(id: UUID) {
        markDeleted(.template, id)
        templates.removeAll { $0.id == id }
    }

    public func save(_ measurement: BodyMeasurement) {
        write(.bodyMeasurement, measurement.id, measurement)
        cacheMeasurement(measurement)
    }

    public func deleteBodyMeasurement(id: UUID) {
        markDeleted(.bodyMeasurement, id)
        bodyMeasurements.removeAll { $0.id == id }
    }

    /// Saves a day's recovery data, replacing what that day had.
    public func save(_ day: Readiness) {
        write(.readiness, Self.readinessID(day.date), day)
        readiness[day.date] = day
    }

    /// The local id of a day's readiness record: the API keys readiness by date.
    nonisolated static func readinessID(_ date: String) -> UUID {
        let digest = Array(Insecure.MD5.hash(data: Data("readiness:\(date)".utf8)))
        return UUID(uuid: (digest[0], digest[1], digest[2], digest[3], digest[4], digest[5], digest[6], digest[7],
                           digest[8], digest[9], digest[10], digest[11], digest[12], digest[13], digest[14], digest[15]))
    }

    public func save(_ profile: Profile) {
        write(.profile, Self.profileID, profile)
        self.profile = profile
    }

    /// Saves a request to the AI coach; the next sync sends it.
    public func save(_ recommendation: Recommendation) {
        write(.recommendation, recommendation.id, recommendation)
        cacheRecommendation(recommendation)
    }

    /// The newest request for a date, "2026-10-26".
    public func recommendation(for date: String) -> Recommendation? {
        recommendations.first { $0.forDate == date }
    }

    /// Requests not sent yet are cancelled, for example when the coach is turned off:
    /// nothing goes to the AI after that.
    public func cancelPendingRecommendations() {
        for change in pendingChanges() where change.kind == .recommendation {
            guard var recommendation = try? Wire.decode(Recommendation.self, from: change.payload) else { continue }
            recommendation.status = .failed
            recommendation.error = "cancelled"
            resolveLocally(recommendation)
        }
    }

    /// Records an answer the phone worked out itself (the server refused the request),
    /// without sending anything.
    func resolveLocally(_ recommendation: Recommendation) {
        guard let stored = record(.recommendation, recommendation.id),
              let payload = try? Wire.encode(recommendation)
        else { return }
        stored.payload = payload
        stored.pending = nil
        persist()
        cacheRecommendation(recommendation)
    }

    /// Removes everything, for example when another user signs in.
    public func removeAll() {
        do {
            try context.delete(model: StoredRecord.self)
            try context.save()
        } catch {
            log.error("Clearing the store failed: \(error, privacy: .public)")
        }
        exercises = [:]
        removedExerciseIDs = []
        workouts = []
        templates = []
        profile = nil
        bodyMeasurements = []
        readiness = [:]
        recommendations = []
    }

    // MARK: Sync

    struct PendingChange {
        let kind: RecordKind
        let id: UUID
        let upload: PendingUpload
        /// What was sent; an edit made while the request runs changes it.
        let payload: Data
    }

    func pendingChanges() -> [PendingChange] {
        let records = (try? context.fetch(FetchDescriptor<StoredRecord>(
            predicate: #Predicate { $0.pendingRaw != nil }
        ))) ?? []
        return records
            .compactMap { record -> PendingChange? in
                guard let kind = RecordKind(rawValue: record.kind), let upload = record.pending
                else { return nil }
                return PendingChange(kind: kind, id: record.recordID, upload: upload, payload: record.payload)
            }
            // Exercises before the templates and workouts that use them: the API
            // rejects a workout whose custom exercise it doesn't have yet.
            .sorted { $0.kind.uploadOrder < $1.kind.uploadOrder }
    }

    func payload<T: Decodable>(of change: PendingChange, as type: T.Type) throws -> T {
        try Wire.decode(type, from: change.payload)
    }

    /// The server accepted the change. If the record changed again meanwhile, it stays
    /// pending so the newer version goes up next time.
    func markUploaded(_ change: PendingChange, changeSeq: Int?) {
        guard let record = record(change.kind, change.id),
              record.pending == change.upload, record.payload == change.payload
        else { return }
        if change.upload == .delete && change.kind != .exercise {
            context.delete(record)
        } else {
            record.pending = nil
            record.changeSeq = changeSeq ?? record.changeSeq
        }
        persist()
    }

    /// The server rejected the change for good (invalid, or the id is taken). Keep the
    /// local copy but stop retrying, so one bad record does not block the others.
    func discardPending(_ change: PendingChange, status: Int) {
        log.error("The server rejected \(change.kind.rawValue, privacy: .public) \(change.id, privacy: .public) with \(status)")
        record(change.kind, change.id)?.pending = nil
        persist()
    }

    enum RemoteValue {
        case exercise(Exercise)
        case workout(Workout)
        case template(Template)
        case profile(Profile)
        case bodyMeasurement(BodyMeasurement)
        case readiness(Readiness)
        case recommendation(Recommendation)
    }

    /// Applies a change from the server. Local edits not yet uploaded win: they go up on
    /// the next push and replace the server's version.
    func applyRemote(_ value: RemoteValue, id: UUID, changeSeq: Int, deleted: Bool) {
        var value = value
        let kind = value.kind
        let existing = record(kind, id)
        if existing?.pending != nil {
            return
        }
        // The server doesn't send back what was asked; keep the phone's copy of it.
        if case .recommendation(var remote) = value,
           let existing, let local = try? Wire.decode(Recommendation.self, from: existing.payload) {
            remote.request = local.request
            remote.planKey = local.planKey
            remote.requestedAt = local.requestedAt
            remote.sentAt = local.sentAt
            value = .recommendation(remote)
        }
        if deleted && kind != .exercise {
            if let existing {
                context.delete(existing)
            }
            uncache(kind, id)
        } else {
            guard let payload = try? Wire.encode(value.encodable) else { return }
            let stored = existing ?? insert(kind, id, payload: payload)
            stored.payload = payload
            stored.changeSeq = changeSeq
            stored.isRemoved = deleted
            cache(value, removed: deleted)
        }
        persist()
    }

    /// Makes the built-in exercises match the catalog. Exercises that left the catalog
    /// stay, marked removed, because past workouts may use them.
    public func replaceBuiltInExercises(_ catalog: [Exercise]) {
        let current = Dictionary(
            uniqueKeysWithValues: builtInRecords(.exercise).map { ($0.recordID, $0) }
        )
        for exercise in catalog {
            guard let payload = try? Wire.encode(exercise) else { continue }
            let record = current[exercise.id] ?? insert(.exercise, exercise.id, payload: payload, isBuiltIn: true)
            record.payload = payload
            record.isRemoved = false
            exercises[exercise.id] = exercise
            removedExerciseIDs.remove(exercise.id)
        }
        let catalogIDs = Set(catalog.map(\.id))
        for (id, record) in current where !catalogIDs.contains(id) {
            record.isRemoved = true
            removedExerciseIDs.insert(id)
        }
        persist()
    }

    /// Makes the built-in templates match the catalog.
    public func replaceBuiltInTemplates(_ catalog: [Template]) {
        let current = Dictionary(
            uniqueKeysWithValues: builtInRecords(.template).map { ($0.recordID, $0) }
        )
        for template in catalog {
            guard let payload = try? Wire.encode(template) else { continue }
            let record = current[template.id] ?? insert(.template, template.id, payload: payload, isBuiltIn: true)
            record.payload = payload
            cacheTemplate(template)
        }
        let catalogIDs = Set(catalog.map(\.id))
        for (id, record) in current where !catalogIDs.contains(id) {
            context.delete(record)
            templates.removeAll { $0.id == id }
        }
        persist()
    }

    // MARK: Storage

    static let profileID = UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1))

    private func reload() {
        exercises = [:]
        removedExerciseIDs = []
        workouts = []
        templates = []
        profile = nil
        bodyMeasurements = []
        readiness = [:]
        recommendations = []
        let records = (try? context.fetch(FetchDescriptor<StoredRecord>())) ?? []
        for record in records {
            guard let kind = RecordKind(rawValue: record.kind) else { continue }
            if record.isRemoved && kind != .exercise {
                continue
            }
            do {
                switch kind {
                case .exercise:
                    let exercise = try Wire.decode(Exercise.self, from: record.payload)
                    exercises[exercise.id] = exercise
                    if record.isRemoved {
                        removedExerciseIDs.insert(exercise.id)
                    }
                case .workout:
                    workouts.append(try Wire.decode(Workout.self, from: record.payload))
                case .template:
                    templates.append(try Wire.decode(Template.self, from: record.payload))
                case .profile:
                    profile = try Wire.decode(Profile.self, from: record.payload)
                case .bodyMeasurement:
                    bodyMeasurements.append(try Wire.decode(BodyMeasurement.self, from: record.payload))
                case .readiness:
                    let day = try Wire.decode(Readiness.self, from: record.payload)
                    readiness[day.date] = day
                case .recommendation:
                    recommendations.append(try Wire.decode(Recommendation.self, from: record.payload))
                }
            } catch {
                log.error("Skipping unreadable \(kind.rawValue, privacy: .public) \(record.recordID, privacy: .public): \(error, privacy: .public)")
            }
        }
        workouts.sort { $0.startedAt > $1.startedAt }
        bodyMeasurements.sort { $0.measuredAt > $1.measuredAt }
        recommendations.sort(by: Self.newestFirst)
        sortTemplates()
    }

    private func write(_ kind: RecordKind, _ id: UUID, _ value: some Encodable) {
        let payload: Data
        do {
            payload = try Wire.encode(value)
        } catch {
            log.error("Encoding \(kind.rawValue, privacy: .public) failed: \(error, privacy: .public)")
            return
        }
        let stored = record(kind, id) ?? insert(kind, id, payload: payload)
        stored.payload = payload
        stored.isRemoved = false
        stored.pending = .save
        persist()
    }

    private func markDeleted(_ kind: RecordKind, _ id: UUID) {
        guard let stored = record(kind, id) else { return }
        // Always tell the server, even if the record looks new: its first upload may
        // be in flight, or may have arrived without the reply reaching the phone. A
        // record the server never had answers 404, which counts as done.
        stored.isRemoved = true
        stored.pending = .delete
        persist()
    }

    private func record(_ kind: RecordKind, _ id: UUID) -> StoredRecord? {
        let key = StoredRecord.key(kind, id)
        var descriptor = FetchDescriptor<StoredRecord>(predicate: #Predicate { $0.key == key })
        descriptor.fetchLimit = 1
        return (try? context.fetch(descriptor))?.first
    }

    private func builtInRecords(_ kind: RecordKind) -> [StoredRecord] {
        let raw = kind.rawValue
        return (try? context.fetch(FetchDescriptor<StoredRecord>(
            predicate: #Predicate { $0.kind == raw && $0.isBuiltIn }
        ))) ?? []
    }

    private func insert(_ kind: RecordKind, _ id: UUID, payload: Data, isBuiltIn: Bool = false) -> StoredRecord {
        let stored = StoredRecord(kind: kind, id: id, payload: payload, isBuiltIn: isBuiltIn)
        context.insert(stored)
        return stored
    }

    private func persist() {
        do {
            try context.save()
        } catch {
            log.error("Saving the store failed: \(error, privacy: .public)")
        }
    }

    private func cache(_ value: RemoteValue, removed: Bool) {
        switch value {
        case .exercise(let exercise):
            exercises[exercise.id] = exercise
            if removed {
                removedExerciseIDs.insert(exercise.id)
            } else {
                removedExerciseIDs.remove(exercise.id)
            }
        case .workout(let workout):
            cacheWorkout(workout)
        case .template(let template):
            cacheTemplate(template)
        case .profile(let profile):
            self.profile = profile
        case .bodyMeasurement(let measurement):
            cacheMeasurement(measurement)
        case .readiness(let day):
            readiness[day.date] = day
        case .recommendation(let recommendation):
            cacheRecommendation(recommendation)
        }
    }

    private func uncache(_ kind: RecordKind, _ id: UUID) {
        switch kind {
        case .exercise: removedExerciseIDs.insert(id)
        case .workout: workouts.removeAll { $0.id == id }
        case .template: templates.removeAll { $0.id == id }
        case .profile: profile = nil
        case .bodyMeasurement: bodyMeasurements.removeAll { $0.id == id }
        case .readiness: readiness = readiness.filter { Self.readinessID($0.key) != id }
        case .recommendation: recommendations.removeAll { $0.id == id }
        }
    }

    private func cacheWorkout(_ workout: Workout) {
        workouts.removeAll { $0.id == workout.id }
        let index = workouts.firstIndex { $0.startedAt < workout.startedAt } ?? workouts.endIndex
        workouts.insert(workout, at: index)
    }

    private func cacheMeasurement(_ measurement: BodyMeasurement) {
        bodyMeasurements.removeAll { $0.id == measurement.id }
        let index = bodyMeasurements.firstIndex { $0.measuredAt < measurement.measuredAt } ?? bodyMeasurements.endIndex
        bodyMeasurements.insert(measurement, at: index)
    }

    private func cacheRecommendation(_ recommendation: Recommendation) {
        recommendations.removeAll { $0.id == recommendation.id }
        recommendations.append(recommendation)
        recommendations.sort(by: Self.newestFirst)
    }

    private static func newestFirst(_ a: Recommendation, _ b: Recommendation) -> Bool {
        a.forDate != b.forDate ? a.forDate > b.forDate : (a.requestedAt ?? .distantPast) > (b.requestedAt ?? .distantPast)
    }

    private func cacheTemplate(_ template: Template) {
        templates.removeAll { $0.id == template.id }
        templates.append(template)
        sortTemplates()
    }

    private func sortTemplates() {
        templates.sort { $0.nameEn.localizedStandardCompare($1.nameEn) == .orderedAscending }
    }
}

extension LocalStore.RemoteValue {
    var kind: RecordKind {
        switch self {
        case .exercise: .exercise
        case .workout: .workout
        case .template: .template
        case .profile: .profile
        case .bodyMeasurement: .bodyMeasurement
        case .readiness: .readiness
        case .recommendation: .recommendation
        }
    }

    var encodable: any Encodable {
        switch self {
        case .exercise(let value): value
        case .workout(let value): value
        case .template(let value): value
        case .profile(let value): value
        case .bodyMeasurement(let value): value
        case .readiness(let value): value
        case .recommendation(let value): value
        }
    }
}
