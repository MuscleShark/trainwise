import Foundation
import HTTPTypes
import OpenAPIRuntime
import Testing

@testable import IronSageAPI

/// Records the request and answers with a fixed JSON body.
private final class StubTransport: ClientTransport, @unchecked Sendable {
    private(set) var request: HTTPRequest?
    private(set) var url: URL?
    let status: HTTPResponse.Status
    let json: String

    init(status: HTTPResponse.Status = .ok, json: String) {
        self.status = status
        self.json = json
    }

    func send(
        _ request: HTTPRequest,
        body: HTTPBody?,
        baseURL: URL,
        operationID: String
    ) async throws -> (HTTPResponse, HTTPBody?) {
        self.request = request
        self.url = baseURL
        var response = HTTPResponse(status: status)
        response.headerFields[.contentType] = "application/json"
        return (response, HTTPBody(json))
    }
}

private let server = URL(string: "https://api.example.com")!

@Test func sendsTheSessionTokenAsBearer() async throws {
    let transport = StubTransport(
        json: #"{"id": 7, "email": "a@example.com", "created_at": "2026-10-24T12:00:00Z"}"#)
    let client = Client.ironSage(serverURL: server, token: { "token-123" }, transport: transport)

    let me = try await client.getMe().ok.body.json

    #expect(me.email == "a@example.com")
    #expect(transport.request?.headerFields[.authorization] == "Bearer token-123")
    #expect(transport.request?.path == "/v1/me")
}

@Test func sendsNoAuthorizationWhenSignedOut() async throws {
    let transport = StubTransport(status: .unauthorized, json: #"{"detail": "Not authenticated"}"#)
    let client = Client.ironSage(serverURL: server, token: { nil }, transport: transport)

    let response = try await client.getMe()

    #expect(transport.request?.headerFields[.authorization] == nil)
    guard case .undocumented(statusCode: 401, _) = response else {
        Issue.record("Expected 401, got \(response)")
        return
    }
}

@Test func decodesNullableFieldsAndNumericWeights() async throws {
    // Guards the contract rewrite in backend/main.py: without it the generator drops
    // every optional field, and decimals arrive as strings.
    let json = """
        {"id": "9b1deb4d-3b7d-4bad-9bdd-2b0d7b3dcb6d", "set_type": "working",
         "reps": 8, "weight_kg": 61.235, "rir": null, "duration_seconds": null,
         "completed_at": null}
        """
    let decoded = try JSONDecoder().decode(Components.Schemas.SetRead.self, from: Data(json.utf8))

    #expect(decoded.weightKg == 61.235)
    #expect(decoded.reps == 8)
    #expect(decoded.rir == nil)
}
