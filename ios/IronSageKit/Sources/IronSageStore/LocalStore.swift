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

    public func save(_ profile: Profile) {
        write(.profile, Self.profileID, profile)
        self.profile = profile
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
    }

    /// Applies a change from the server. Local edits not yet uploaded win: they go up on
    /// the next push and replace the server's version.
    func applyRemote(_ value: RemoteValue, id: UUID, changeSeq: Int, deleted: Bool) {
        let kind = value.kind
        let existing = record(kind, id)
        if existing?.pending != nil {
            return
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

    // MARK: Storage

    static let profileID = UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1))

    private func reload() {
        exercises = [:]
        removedExerciseIDs = []
        workouts = []
        templates = []
        profile = nil
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
                }
            } catch {
                log.error("Skipping unreadable \(kind.rawValue, privacy: .public) \(record.recordID, privacy: .public): \(error, privacy: .public)")
            }
        }
        workouts.sort { $0.startedAt > $1.startedAt }
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
        }
    }

    private func uncache(_ kind: RecordKind, _ id: UUID) {
        switch kind {
        case .exercise: removedExerciseIDs.insert(id)
        case .workout: workouts.removeAll { $0.id == id }
        case .template: templates.removeAll { $0.id == id }
        case .profile: profile = nil
        }
    }

    private func cacheWorkout(_ workout: Workout) {
        workouts.removeAll { $0.id == workout.id }
        let index = workouts.firstIndex { $0.startedAt < workout.startedAt } ?? workouts.endIndex
        workouts.insert(workout, at: index)
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
        }
    }

    var encodable: any Encodable {
        switch self {
        case .exercise(let value): value
        case .workout(let value): value
        case .template(let value): value
        case .profile(let value): value
        }
    }
}
