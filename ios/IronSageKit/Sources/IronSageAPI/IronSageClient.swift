import Foundation
import HTTPTypes
import OpenAPIRuntime
import OpenAPIURLSession

/// The generated client. Named for the app because ClerkKit also has a `Client` type.
public typealias APIClient = Client

/// Returns the current session token, or nil when no one is signed in.
public typealias TokenProvider = @Sendable () async throws -> String?

/// Adds `Authorization: Bearer <token>` to every request that has a token.
public struct BearerTokenMiddleware: ClientMiddleware {
    private let token: TokenProvider

    public init(token: @escaping TokenProvider) {
        self.token = token
    }

    public func intercept(
        _ request: HTTPRequest,
        body: HTTPBody?,
        baseURL: URL,
        operationID: String,
        next: @Sendable (HTTPRequest, HTTPBody?, URL) async throws -> (HTTPResponse, HTTPBody?)
    ) async throws -> (HTTPResponse, HTTPBody?) {
        var request = request
        if let token = try await token() {
            request.headerFields[.authorization] = "Bearer \(token)"
        }
        return try await next(request, body, baseURL)
    }
}

/// Reads ISO 8601 dates with or without fractional seconds. The backend writes
/// microseconds when a time has them (`2026-10-24T22:59:10.038062Z`) and none when it
/// doesn't; the runtime's default transcoder rejects the first form.
public struct FlexibleISO8601DateTranscoder: DateTranscoder {
    private static let fractional = Date.ISO8601FormatStyle(includingFractionalSeconds: true)
    private static let whole = Date.ISO8601FormatStyle()

    public init() {}

    public func encode(_ date: Date) throws -> String {
        Self.fractional.format(date)
    }

    public func decode(_ string: String) throws -> Date {
        if let date = try? Self.fractional.parse(string) {
            return date
        }
        return try Self.whole.parse(string)
    }
}

extension Client {
    /// A client for the IronSage API at `serverURL` (paths in the contract already start with /v1).
    public static func ironSage(
        serverURL: URL,
        token: @escaping TokenProvider,
        transport: any ClientTransport = URLSessionTransport()
    ) -> Client {
        Client(
            serverURL: serverURL,
            configuration: Configuration(dateTranscoder: FlexibleISO8601DateTranscoder()),
            transport: transport,
            middlewares: [BearerTokenMiddleware(token: token)]
        )
    }
}
