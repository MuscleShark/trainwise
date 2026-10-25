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

extension Client {
    /// A client for the IronSage API at `serverURL` (paths in the contract already start with /v1).
    public static func ironSage(
        serverURL: URL,
        token: @escaping TokenProvider,
        transport: any ClientTransport = URLSessionTransport()
    ) -> Client {
        Client(
            serverURL: serverURL,
            transport: transport,
            middlewares: [BearerTokenMiddleware(token: token)]
        )
    }
}
