import Foundation
import HTTPTypes
import IronSageAPI
import OpenAPIRuntime

/// Stands in for the API: records each request and answers with `respond`.
final class FakeServer: ClientTransport, @unchecked Sendable {
    struct Request: Sendable {
        let method: HTTPRequest.Method
        let path: String
        let body: Data

        var json: [String: Any] {
            (try? JSONSerialization.jsonObject(with: body)) as? [String: Any] ?? [:]
        }

        /// The request body as the server would return it.
        func echo(changeSeq: Int, deleted: Bool = false) -> String {
            var object = json
            object["id"] = object["id"] ?? String(path.split(separator: "/").last ?? "")
            object["updated_at"] = "2026-10-25T10:00:00.123456Z"
            object["deleted_at"] = deleted ? "2026-10-25T10:00:00Z" : NSNull()
            object["change_seq"] = changeSeq
            object["is_custom"] = true
            let data = try! JSONSerialization.data(withJSONObject: object)
            return String(decoding: data, as: UTF8.self)
        }
    }

    typealias Responder = @Sendable (Request) throws -> (Int, String)

    private let lock = NSLock()
    private var recorded: [Request] = []
    private var responder: Responder

    init(_ respond: @escaping Responder = FakeServer.standard) {
        responder = respond
    }

    var requests: [Request] { lock.withLock { recorded } }

    func respond(with respond: @escaping Responder) {
        lock.withLock { responder = respond }
    }

    func send(
        _ request: HTTPRequest,
        body: HTTPBody?,
        baseURL: URL,
        operationID: String
    ) async throws -> (HTTPResponse, HTTPBody?) {
        var data = Data()
        if let body {
            data = try await Data(collecting: body, upTo: 1_000_000)
        }
        let recordedRequest = Request(method: request.method, path: request.path ?? "", body: data)
        let respond = lock.withLock {
            recorded.append(recordedRequest)
            return responder
        }
        let (status, text) = try respond(recordedRequest)
        var response = HTTPResponse(status: .init(code: status))
        response.headerFields[.contentType] = "application/json"
        return (response, HTTPBody(text))
    }

    /// An empty account with a one-exercise catalog; PUTs and DELETEs succeed.
    static let standard: Responder = { request in
        switch request.method {
        case .put: (200, request.echo(changeSeq: 1))
        case .delete: (204, "")
        default:
            if request.path.hasPrefix("/v1/sync") {
                (200, syncPage(changeSeq: 0))
            } else if request.path == "/v1/exercises" {
                (200, "[\(benchJSON)]")
            } else if request.path == "/v1/templates" {
                (200, "[\(templateJSON)]")
            } else {
                (404, #"{"detail": "Not Found"}"#)
            }
        }
    }

    static func syncPage(
        changeSeq: Int,
        hasMore: Bool = false,
        workouts: [String] = [],
        templates: [String] = [],
        exercises: [String] = [],
        bodyMeasurements: [String] = [],
        readiness: [String] = [],
        recommendations: [String]? = nil,
        weeklySummaries: [String]? = nil,
        profile: String = "null"
    ) -> String {
        // Without recommendations, the page looks like one from before the AI coach.
        let coach = (recommendations.map { #", "recommendations": [\#($0.joined(separator: ","))]"# } ?? "")
            + (weeklySummaries.map { #", "weekly_summaries": [\#($0.joined(separator: ","))]"# } ?? "")
        return """
        {"change_seq": \(changeSeq), "has_more": \(hasMore), "profile": \(profile),
         "exercises": [\(exercises.joined(separator: ","))],
         "workouts": [\(workouts.joined(separator: ","))],
         "templates": [\(templates.joined(separator: ","))],
         "body_measurements": [\(bodyMeasurements.joined(separator: ","))],
         "readiness": [\(readiness.joined(separator: ","))]\(coach)}
        """
    }

    static let benchID = "0b4f8d2e-5a43-5d3e-9a8f-2c6e1f0d7b11"

    static let benchJSON = """
        {"id": "\(benchID)", "name_en": "Barbell bench press", "name_zh": "杠铃卧推",
         "equipment": "barbell", "load_type": "total", "primary_muscles": ["chest"],
         "secondary_muscles": ["front_delts", "triceps"], "aliases": ["bench", "卧推"],
         "base_exercise_id": null, "is_custom": false,
         "updated_at": "2026-10-24T12:00:00.123456Z", "deleted_at": null, "change_seq": 0}
        """

    static let templateID = "5b9e1f9c-7d2a-5c43-8e61-3f0a2b4c6d88"

    static let templateJSON = """
        {"id": "\(templateID)", "name_en": "Push / pull / legs", "name_zh": "推拉腿",
         "level": "intermediate", "days_per_week": 6, "notes": null, "is_custom": false,
         "days": [{"id": "6c0f2a1d-8e3b-5d54-9f72-4a1b3c5d7e99", "name": "Push", "name_zh": "推",
           "exercises": [{"id": "7d1a3b2e-9f4c-5e65-8a83-5b2c4d6e8fa0", "exercise_id": "\(benchID)",
             "rest_seconds": 180, "superset_group": null,
             "sets": [{"id": "8e2b4c3f-0a5d-5f76-9b94-6c3d5e7f9ab1", "set_type": "working",
               "rep_min": 5, "rep_max": 8, "target_rir": 2}]}]}],
         "updated_at": "2026-10-24T12:00:00Z", "deleted_at": null, "change_seq": 0}
        """

    static func workoutJSON(id: String, title: String, changeSeq: Int, deleted: Bool = false) -> String {
        """
        {"id": "\(id)", "title": "\(title)", "template_id": null,
         "started_at": "2026-10-20T16:00:00Z", "ended_at": "2026-10-20T17:05:00.5Z",
         "time_zone": "Europe/Berlin", "notes": null, "avg_heart_rate": null,
         "max_heart_rate": null, "healthkit_workout_id": null,
         "exercises": [{"id": "\(UUID().uuidString.lowercased())", "exercise_id": "\(benchID)",
           "notes": null, "superset_group": null, "rest_seconds": 180,
           "sets": [{"id": "\(UUID().uuidString.lowercased())", "set_type": "working",
             "reps": 8, "weight_kg": 61.235, "rir": 2, "duration_seconds": null,
             "completed_at": "2026-10-20T16:10:00Z"}]}],
         "updated_at": "2026-10-25T10:00:00.123456Z",
         "deleted_at": \(deleted ? #""2026-10-25T10:00:00Z""# : "null"), "change_seq": \(changeSeq)}
        """
    }
}
