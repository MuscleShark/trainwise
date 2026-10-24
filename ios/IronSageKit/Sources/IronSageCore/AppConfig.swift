import Foundation

/// Settings the app reads from its Info.plist, where the build fills them in from
/// the project's build settings (API_BASE_URL, CLERK_PUBLISHABLE_KEY).
public struct AppConfig: Equatable, Sendable {
    public let apiBaseURL: URL
    public let clerkPublishableKey: String

    public enum Error: Swift.Error, Equatable {
        case missing(String)
        case invalidURL(String)
    }

    public init(info: [String: Any]) throws {
        let urlString = try Self.value("API_BASE_URL", in: info)
        guard let url = URL(string: urlString), url.scheme == "https" || url.host == "localhost"
        else { throw Error.invalidURL(urlString) }
        apiBaseURL = url
        clerkPublishableKey = try Self.value("CLERK_PUBLISHABLE_KEY", in: info)
    }

    public static func fromMainBundle() throws -> AppConfig {
        try AppConfig(info: Bundle.main.infoDictionary ?? [:])
    }

    private static func value(_ key: String, in info: [String: Any]) throws -> String {
        // An unset build setting reaches the plist as an empty string or as "$(KEY)".
        guard let value = (info[key] as? String)?.trimmingCharacters(in: .whitespaces),
              !value.isEmpty, !value.hasPrefix("$(")
        else { throw Error.missing(key) }
        return value
    }
}
