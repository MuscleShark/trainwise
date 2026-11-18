import Foundation
import IronSageAPI
import IronSageCore
import OpenAPIRuntime

/// A template someone shared, as the link shows it: its days and the exercises they use.
public struct SharedPlan: Sendable, Identifiable {
    public struct Exercise: Sendable, Identifiable {
        public var id: UUID
        public var nameEn: String
        public var nameZh: String?
        public var isCustom: Bool

        public func name(chinese: Bool) -> String {
            chinese ? (nameZh ?? nameEn) : nameEn
        }
    }

    public var code: String
    /// The shared template, under an id of its own: it isn't anyone's yet.
    public var template: Template
    public var exercises: [UUID: Exercise]

    public var id: String { code }
}

public enum SharingError: Error, Equatable {
    /// Not shared (anymore), or no such link.
    case notFound
    case signedOut
    case offline
    case server(status: Int)
}

/// Sharing a template with a link and copying one that was shared (backend
/// routers/shares.py). Every call needs the network; nothing here is kept on the phone.
@MainActor
public struct TemplateSharing {
    private let api: any APIProtocol

    public init(api: any APIProtocol) {
        self.api = api
    }

    /// Shares one of the user's templates, or takes a new snapshot of it: the code of its
    /// link, the same each time. Sync first, so the server has the latest edits.
    public func share(_ templateID: UUID) async throws -> String {
        let response = try await call { try await api.shareTemplate(path: .init(templateId: Self.id(templateID))) }
        switch response {
        case .ok(let ok): return try ok.body.json.code
        case .unprocessableContent: throw SharingError.server(status: 422)
        case .undocumented(let status, _): throw Self.error(status)
        }
    }

    /// Stops sharing: the link no longer opens. Copies already made stay.
    public func stopSharing(_ templateID: UUID) async throws {
        let response = try await call { try await api.stopSharingTemplate(path: .init(templateId: Self.id(templateID))) }
        switch response {
        case .noContent: return
        case .unprocessableContent: throw SharingError.server(status: 422)
        case .undocumented(let status, _): throw Self.error(status)
        }
    }

    /// What a link holds, read without signing in.
    public func plan(code: String) async throws -> SharedPlan {
        let response = try await call { try await api.getSharedTemplate(path: .init(code: code)) }
        switch response {
        case .ok(let ok):
            let shared = try ok.body.json
            let days = try shared.days.map { try Wire.app($0, as: TemplateDay.self) }
            let template = Template(
                nameEn: shared.nameEn,
                nameZh: shared.nameZh,
                level: shared.level.flatMap { Level(rawValue: $0.rawValue) },
                daysPerWeek: shared.daysPerWeek,
                notes: shared.notes,
                days: days,
                isCustom: true
            )
            let exercises = shared.exercises.map {
                SharedPlan.Exercise(id: UUID(uuidString: $0.id)!, nameEn: $0.nameEn, nameZh: $0.nameZh, isCustom: $0.isCustom)
            }
            return SharedPlan(code: code, template: template, exercises: Dictionary(uniqueKeysWithValues: exercises.map { ($0.id, $0) }))
        case .unprocessableContent: throw SharingError.notFound
        case .undocumented(let status, _): throw Self.error(status)
        }
    }

    /// Copies a shared template into the user's own templates: the new template's id.
    /// The server adds it (and any custom exercise it uses); the next sync brings it.
    public func copy(code: String) async throws -> UUID {
        let response = try await call { try await api.copySharedTemplate(path: .init(code: code)) }
        switch response {
        case .created(let created): return UUID(uuidString: try created.body.json.id)!
        case .unprocessableContent: throw SharingError.server(status: 422)
        case .undocumented(let status, _): throw Self.error(status)
        }
    }

    private func call<T>(_ request: () async throws -> T) async throws -> T {
        do {
            return try await request()
        } catch {
            let underlying = (error as? ClientError)?.underlyingError ?? error
            if underlying is URLError { throw SharingError.offline }
            throw error
        }
    }

    private static func id(_ id: UUID) -> String {
        id.uuidString.lowercased()
    }

    private static func error(_ status: Int) -> SharingError {
        switch status {
        case 404: .notFound
        case 401, 403: .signedOut
        default: .server(status: status)
        }
    }
}
