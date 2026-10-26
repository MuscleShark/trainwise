import Foundation
import IronSageAPI
import IronSageCore
import OpenAPIRuntime
import OSLog

private let log = Logger(subsystem: "app.ironsage.IronSage", category: "sync")

/// Sends local edits to the API and brings in changes from other devices.
///
/// One sync: upload pending edits (each record as a whole, so retries are safe), then
/// read `GET /v1/sync` from the saved cursor, then refresh the built-in exercises and
/// templates once a day. Run it when the app starts or comes to the foreground and after a workout.
@MainActor
@Observable
public final class SyncEngine {
    public enum State: Equatable, Sendable {
        case idle, syncing
        /// No connection; edits stay on the phone until the next sync.
        case offline
        case failed
    }

    public private(set) var state: State = .idle
    public private(set) var lastSyncedAt: Date?
    /// Whether requests to the AI coach may be sent; checked right before each one, so
    /// a request queued before the coach was turned off is cancelled instead.
    @ObservationIgnored public var allowsCoach: @MainActor () -> Bool = { true }

    @ObservationIgnored private let store: LocalStore
    @ObservationIgnored private let api: any APIProtocol
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let now: @Sendable () -> Date

    static let catalogMaxAge: TimeInterval = 24 * 60 * 60

    public init(
        store: LocalStore,
        api: any APIProtocol,
        defaults: UserDefaults = .standard,
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.store = store
        self.api = api
        self.defaults = defaults
        self.now = now
        lastSyncedAt = defaults.object(forKey: Keys.lastSyncedAt) as? Date
    }

    public func sync() async {
        guard state != .syncing else {
            // The running sync may have read the pending edits already; go again after it.
            runAgain = true
            return
        }
        let run = generation
        upgradeCursorIfNeeded()
        repeat {
            runAgain = false
            state = .syncing
            do {
                try await push(run)
                try await pull(run)
                try await refreshCatalogIfNeeded(run)
                lastSyncedAt = now()
                defaults.set(lastSyncedAt, forKey: Keys.lastSyncedAt)
                state = .idle
            } catch is CancellationError {
                // reset() ran meanwhile: the results belong to data that is gone.
                return
            } catch {
                log.error("Sync failed: \(String(describing: error), privacy: .public)")
                state = Self.isOffline(error) ? .offline : .failed
                return
            }
        } while runAgain && run == generation
    }

    /// Forgets the sync position, for example after the local data was removed. A sync
    /// that is still running stops at its next step without writing anything.
    public func reset() {
        generation += 1
        runAgain = false
        for key in [Keys.changeSeq, Keys.catalogFetchedAt, Keys.lastSyncedAt] {
            defaults.removeObject(forKey: key)
        }
        lastSyncedAt = nil
        state = .idle
    }

    /// Version 2 added body measurements and readiness. The server sent them before, but
    /// older versions of the app skipped them, so the first sync after the update starts
    /// again from 0 to pick them up. Records with unsent edits still win.
    static let cursorVersion = 2

    private func upgradeCursorIfNeeded() {
        if defaults.integer(forKey: Keys.cursorVersion) < Self.cursorVersion {
            defaults.removeObject(forKey: Keys.changeSeq)
            defaults.set(Self.cursorVersion, forKey: Keys.cursorVersion)
        }
    }

    /// Each reset starts a new generation; a sync from an older one must stop.
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var runAgain = false

    private func ensureCurrent(_ run: Int) throws {
        if run != generation {
            throw CancellationError()
        }
    }

    // MARK: Push

    func push(_ run: Int) async throws {
        for change in store.pendingChanges() {
            if change.kind == .recommendation {
                try await send(recommendation: change, run)
                continue
            }
            let outcome: Outcome
            do {
                outcome = try await upload(change)
            } catch let error as ClientError where error.response != nil {
                // The client could not read the error body (the API's 422 and 409
                // bodies are {"detail": "..."}), but the status still decides.
                outcome = .from(status: error.response!.status.code)
            }
            try ensureCurrent(run)

            switch outcome {
            case .accepted(let changeSeq):
                store.markUploaded(change, changeSeq: changeSeq)
            case .rejected(let status):
                store.discardPending(change, status: status)
            case .retryLater(let status):
                throw SyncError.server(status: status)
            }
        }
    }

    private func upload(_ change: LocalStore.PendingChange) async throws -> Outcome {
        let id = change.id.uuidString.lowercased()
        switch (change.kind, change.upload) {
        case (.workout, .save):
            let body = try Wire.api(store.payload(of: change, as: Workout.self), as: Components.Schemas.WorkoutWrite.self)
            return try await .from(api.putWorkout(path: .init(workoutId: id), body: .json(body))) {
                try $0.ok.body.json.changeSeq
            }
        case (.workout, .delete):
            return try await .deleted(api.deleteWorkout(path: .init(workoutId: id)))
        case (.exercise, .save):
            let body = try Wire.api(store.payload(of: change, as: Exercise.self), as: Components.Schemas.ExerciseWrite.self)
            return try await .from(api.putExercise(path: .init(exerciseId: id), body: .json(body))) {
                try $0.ok.body.json.changeSeq
            }
        case (.exercise, .delete):
            return try await .deleted(api.deleteExercise(path: .init(exerciseId: id)))
        case (.template, .save):
            let body = try Wire.api(store.payload(of: change, as: Template.self), as: Components.Schemas.TemplateWrite.self)
            return try await .from(api.putTemplate(path: .init(templateId: id), body: .json(body))) {
                try $0.ok.body.json.changeSeq
            }
        case (.template, .delete):
            return try await .deleted(api.deleteTemplate(path: .init(templateId: id)))
        case (.profile, _):
            let body = try Wire.api(store.payload(of: change, as: Profile.self), as: Components.Schemas.ProfileWrite.self)
            return try await .from(api.putProfile(body: .json(body))) {
                try $0.ok.body.json.changeSeq
            }
        case (.bodyMeasurement, .save):
            let body = try Wire.api(store.payload(of: change, as: BodyMeasurement.self), as: Components.Schemas.BodyMeasurementWrite.self)
            return try await .from(api.putBodyMeasurement(path: .init(measurementId: id), body: .json(body))) {
                try $0.ok.body.json.changeSeq
            }
        case (.bodyMeasurement, .delete):
            return try await .deleted(api.deleteBodyMeasurement(path: .init(measurementId: id)))
        case (.readiness, .save):
            let day = try store.payload(of: change, as: Readiness.self)
            let body = try Wire.api(day, as: Components.Schemas.ReadinessWrite.self)
            return try await .from(api.putReadiness(path: .init(day: day.date), body: .json(body))) {
                try $0.ok.body.json.changeSeq
            }
        case (.readiness, .delete):
            // The API keeps one record per day and has no delete; a day is only replaced.
            return .accepted(changeSeq: nil)
        case (.recommendation, _):
            // Sent by send(recommendation:_:).
            return .accepted(changeSeq: nil)
        }
    }

    /// Asks the AI coach. The answer comes later through the pull. A refusal (no
    /// access, the daily limit, an invalid request) is final for this request: it is
    /// recorded on the phone and never blocks the rest of the sync.
    private func send(recommendation change: LocalStore.PendingChange, _ run: Int) async throws {
        var recommendation = try store.payload(of: change, as: Recommendation.self)
        guard let request = recommendation.request else {
            store.discardPending(change, status: 400)
            return
        }
        guard allowsCoach() else {
            recommendation.status = .failed
            recommendation.error = "cancelled"
            store.resolveLocally(recommendation)
            return
        }
        struct Body: Encodable {
            let forDate: String
            let input: CoachRequest
        }
        let body = try Wire.api(Body(forDate: recommendation.forDate, input: request), as: Components.Schemas.RecommendationWrite.self)
        let status: Int
        do {
            let response = try await api.requestRecommendation(
                path: .init(recommendationId: change.id.uuidString.lowercased()), body: .json(body)
            )
            try ensureCurrent(run)
            switch response {
            case .ok(let ok):
                let read = try ok.body.json
                store.markUploaded(change, changeSeq: read.changeSeq)
                var accepted = try Wire.app(read, as: Recommendation.self)
                accepted.request = recommendation.request
                accepted.planKey = recommendation.planKey
                accepted.requestedAt = recommendation.requestedAt
                // The answer is due from now, the server's clock for its timeout.
                accepted.sentAt = now()
                store.resolveLocally(accepted)
                return
            case .unprocessableContent:
                status = 422
            case .undocumented(let code, _):
                status = code
            }
        } catch let error as ClientError where error.response != nil {
            status = error.response!.status.code
        }
        let reason: String
        switch status {
        case 402: reason = "not_allowed"
        case 429: reason = "limit_reached"
        case 400, 404, 409, 422: reason = "invalid_request"
        default: throw SyncError.server(status: status)
        }
        log.error("The coach refused recommendation \(change.id, privacy: .public) with \(status)")
        recommendation.status = .failed
        recommendation.error = reason
        store.resolveLocally(recommendation)
    }

    // MARK: Pull

    func pull(_ run: Int) async throws {
        var since = defaults.integer(forKey: Keys.changeSeq)
        while true {
            let page: Components.Schemas.SyncResponse
            let response = try await api.sync(query: .init(since: since, limit: 200))
            try ensureCurrent(run)
            switch response {
            case .ok(let ok):
                page = try ok.body.json
            case .unprocessableContent:
                throw SyncError.server(status: 422)
            case .undocumented(let status, _):
                throw SyncError.server(status: status)
            }

            if let profile = page.profile {
                store.applyRemote(
                    .profile(try Wire.app(profile, as: Profile.self)),
                    id: LocalStore.profileID, changeSeq: profile.changeSeq, deleted: false
                )
            }
            for exercise in page.exercises {
                let value = try Wire.app(exercise, as: Exercise.self)
                store.applyRemote(.exercise(value), id: value.id, changeSeq: exercise.changeSeq, deleted: exercise.deletedAt != nil)
            }
            for workout in page.workouts {
                let value = try Wire.app(workout, as: Workout.self)
                store.applyRemote(.workout(value), id: value.id, changeSeq: workout.changeSeq, deleted: workout.deletedAt != nil)
            }
            for template in page.templates {
                let value = try Wire.app(template, as: Template.self)
                store.applyRemote(.template(value), id: value.id, changeSeq: template.changeSeq, deleted: template.deletedAt != nil)
            }
            for measurement in page.bodyMeasurements {
                let value = try Wire.app(measurement, as: BodyMeasurement.self)
                store.applyRemote(.bodyMeasurement(value), id: value.id, changeSeq: measurement.changeSeq, deleted: measurement.deletedAt != nil)
            }
            for day in page.readiness {
                let value = try Wire.app(day, as: Readiness.self)
                store.applyRemote(.readiness(value), id: LocalStore.readinessID(value.date), changeSeq: day.changeSeq, deleted: day.deletedAt != nil)
            }
            for recommendation in page.recommendations ?? [] {
                let value = try Wire.app(recommendation, as: Recommendation.self)
                store.applyRemote(.recommendation(value), id: value.id, changeSeq: recommendation.changeSeq, deleted: recommendation.deletedAt != nil)
            }

            since = page.changeSeq
            defaults.set(since, forKey: Keys.changeSeq)
            if !page.hasMore {
                return
            }
        }
    }

    // MARK: Catalog

    func refreshCatalogIfNeeded(_ run: Int) async throws {
        let fetchedAt = defaults.object(forKey: Keys.catalogFetchedAt) as? Date
        if store.hasBuiltInExercises, let fetchedAt, now().timeIntervalSince(fetchedAt) < Self.catalogMaxAge {
            return
        }
        let exercises = try await api.listExercises()
        try ensureCurrent(run)
        switch exercises {
        case .ok(let ok):
            let builtIn = try ok.body.json.filter { !$0.isCustom }
            store.replaceBuiltInExercises(try builtIn.map { try Wire.app($0, as: Exercise.self) })
        case .undocumented(let status, _):
            throw SyncError.server(status: status)
        }
        // Built-in templates refer to catalog exercises, so they come second.
        switch try await api.listTemplates() {
        case .ok(let ok):
            let builtIn = try ok.body.json.filter { !$0.isCustom }
            store.replaceBuiltInTemplates(try builtIn.map { try Wire.app($0, as: Template.self) })
        case .undocumented(let status, _):
            throw SyncError.server(status: status)
        }
        defaults.set(now(), forKey: Keys.catalogFetchedAt)
    }

    // MARK: Helpers

    enum Keys {
        static let changeSeq = "IronSage.sync.changeSeq"
        static let catalogFetchedAt = "IronSage.sync.catalogFetchedAt"
        static let lastSyncedAt = "IronSage.sync.lastSyncedAt"
        static let cursorVersion = "IronSage.sync.cursorVersion"
    }

    enum SyncError: Error {
        case server(status: Int)
    }

    private static func isOffline(_ error: any Error) -> Bool {
        let underlying = (error as? ClientError)?.underlyingError ?? error
        guard let urlError = underlying as? URLError else { return false }
        let offline: [URLError.Code] = [
            .notConnectedToInternet, .networkConnectionLost, .timedOut, .cannotFindHost,
            .cannotConnectToHost, .dataNotAllowed, .internationalRoamingOff,
        ]
        return offline.contains(urlError.code)
    }
}

/// What a push request means for the pending change.
private enum Outcome {
    case accepted(changeSeq: Int?)
    /// The request can never succeed as sent (invalid, or the id belongs to someone else).
    case rejected(status: Int)
    /// Signed out, rate limited or a server problem: keep it and stop this sync.
    case retryLater(status: Int)

    static func from<Output: SyncOutput>(_ output: Output, changeSeq: (Output) throws -> Int) rethrows -> Outcome {
        if let status = output.statusCode {
            return classify(status)
        }
        return .accepted(changeSeq: try changeSeq(output))
    }

    static func deleted<Output: SyncOutput>(_ output: Output) -> Outcome {
        guard let status = output.statusCode else { return .accepted(changeSeq: nil) }
        // Already gone on the server.
        return status == 404 ? .accepted(changeSeq: nil) : classify(status)
    }

    static func from(status: Int) -> Outcome {
        (200..<300).contains(status) ? .accepted(changeSeq: nil) : classify(status)
    }

    private static func classify(_ status: Int) -> Outcome {
        switch status {
        case 400, 403, 404, 409, 422: .rejected(status: status)
        default: .retryLater(status: status)
        }
    }
}

/// Generated outputs: nil for the success case, otherwise the HTTP status.
private protocol SyncOutput {
    var statusCode: Int? { get }
}

extension Operations.PutWorkout.Output: SyncOutput {
    var statusCode: Int? {
        switch self {
        case .ok: nil
        case .unprocessableContent: 422
        case .undocumented(let status, _): status
        }
    }
}

extension Operations.DeleteWorkout.Output: SyncOutput {
    var statusCode: Int? {
        switch self {
        case .noContent: nil
        case .unprocessableContent: 422
        case .undocumented(let status, _): status
        }
    }
}

extension Operations.PutExercise.Output: SyncOutput {
    var statusCode: Int? {
        switch self {
        case .ok: nil
        case .unprocessableContent: 422
        case .undocumented(let status, _): status
        }
    }
}

extension Operations.DeleteExercise.Output: SyncOutput {
    var statusCode: Int? {
        switch self {
        case .noContent: nil
        case .unprocessableContent: 422
        case .undocumented(let status, _): status
        }
    }
}

extension Operations.PutTemplate.Output: SyncOutput {
    var statusCode: Int? {
        switch self {
        case .ok: nil
        case .unprocessableContent: 422
        case .undocumented(let status, _): status
        }
    }
}

extension Operations.DeleteTemplate.Output: SyncOutput {
    var statusCode: Int? {
        switch self {
        case .noContent: nil
        case .unprocessableContent: 422
        case .undocumented(let status, _): status
        }
    }
}

extension Operations.PutProfile.Output: SyncOutput {
    var statusCode: Int? {
        switch self {
        case .ok: nil
        case .unprocessableContent: 422
        case .undocumented(let status, _): status
        }
    }
}

extension Operations.PutBodyMeasurement.Output: SyncOutput {
    var statusCode: Int? {
        switch self {
        case .ok: nil
        case .unprocessableContent: 422
        case .undocumented(let status, _): status
        }
    }
}

extension Operations.DeleteBodyMeasurement.Output: SyncOutput {
    var statusCode: Int? {
        switch self {
        case .noContent: nil
        case .unprocessableContent: 422
        case .undocumented(let status, _): status
        }
    }
}

extension Operations.PutReadiness.Output: SyncOutput {
    var statusCode: Int? {
        switch self {
        case .ok: nil
        case .unprocessableContent: 422
        case .undocumented(let status, _): status
        }
    }
}
