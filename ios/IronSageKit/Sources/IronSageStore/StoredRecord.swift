import Foundation
import SwiftData

enum RecordKind: String, Sendable {
    case exercise, workout, template, profile
    case bodyMeasurement = "body_measurement"
    case readiness

    /// Records that others refer to go up first.
    var uploadOrder: Int {
        switch self {
        case .profile: 0
        case .exercise: 1
        case .template: 2
        case .workout: 3
        case .bodyMeasurement: 4
        case .readiness: 5
        }
    }
}

/// What still has to be sent to the API.
enum PendingUpload: String, Sendable {
    case save, delete
}

/// One synced record, kept as the JSON of the app's type.
///
/// The app reads records into memory at launch and works with its own types, so the
/// table only needs to find a record by kind and id. Storing JSON keeps the schema
/// stable while the app's types grow.
@Model
final class StoredRecord {
    /// "kind:uuid"
    @Attribute(.unique) var key: String
    var kind: String
    var recordID: UUID
    var payload: Data
    /// The API's change_seq once the server has the record; 0 before that.
    var changeSeq: Int
    /// Deleted exercises stay so past workouts can still show their names.
    var isRemoved: Bool
    /// Part of the built-in catalog rather than the user's own records.
    var isBuiltIn: Bool
    var pendingRaw: String?

    init(kind: RecordKind, id: UUID, payload: Data, isBuiltIn: Bool = false) {
        self.key = Self.key(kind, id)
        self.kind = kind.rawValue
        self.recordID = id
        self.payload = payload
        self.changeSeq = 0
        self.isRemoved = false
        self.isBuiltIn = isBuiltIn
        self.pendingRaw = nil
    }

    var pending: PendingUpload? {
        get { pendingRaw.flatMap(PendingUpload.init(rawValue:)) }
        set { pendingRaw = newValue?.rawValue }
    }

    static func key(_ kind: RecordKind, _ id: UUID) -> String {
        "\(kind.rawValue):\(id.uuidString)"
    }
}
