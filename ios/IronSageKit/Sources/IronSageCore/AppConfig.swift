import Foundation

/// Settings the app reads from its Info.plist, where the build fills them in from
/// the project's build settings (STAGING_API_URL, PRODUCTION_API_URL,
/// CLERK_PUBLISHABLE_KEY).
public struct AppConfig: Equatable, Sendable {
    /// Which API the app talks to. One build serves both: TestFlight tries a release on
    /// staging, and the same build from the App Store uses production.
    public enum Server: String, Sendable {
        case staging, production

        /// Builds run from Xcode and TestFlight installs (and App Review's, which also has
        /// a sandbox receipt) use staging; App Store installs use production.
        public static func forInstall(debugBuild: Bool, receiptName: String?) -> Server {
            debugBuild || receiptName == "sandboxReceipt" ? .staging : .production
        }
    }

    public let server: Server
    public let apiBaseURL: URL
    public let clerkPublishableKey: String

    public enum Error: Swift.Error, Equatable {
        case missing(String)
        case invalidURL(String)
    }

    public init(info: [String: Any], server: Server) throws {
        let key = server == .staging ? "STAGING_API_URL" : "PRODUCTION_API_URL"
        let urlString = try Self.value(key, in: info)
        guard let url = URL(string: urlString), url.scheme == "https" || url.host == "localhost"
        else { throw Error.invalidURL(urlString) }
        self.server = server
        apiBaseURL = url
        clerkPublishableKey = try Self.value("CLERK_PUBLISHABLE_KEY", in: info)
    }

    /// The settings for how this copy of the app was built and installed.
    public static func fromMainBundle() throws -> AppConfig {
        #if DEBUG
        let debugBuild = true
        #else
        let debugBuild = false
        #endif
        // Read through key-value coding: `appStoreReceiptURL` is deprecated for
        // AppTransaction, which is async and may go online, and this has to be known
        // at once, offline, before anything starts.
        let receipt = (Bundle.main.value(forKey: "appStoreReceiptURL") as? URL)?.lastPathComponent
        return try AppConfig(
            info: Bundle.main.infoDictionary ?? [:],
            server: .forInstall(debugBuild: debugBuild, receiptName: receipt)
        )
    }

    private static func value(_ key: String, in info: [String: Any]) throws -> String {
        // An unset build setting reaches the plist as an empty string or as "$(KEY)".
        guard let value = (info[key] as? String)?.trimmingCharacters(in: .whitespaces),
              !value.isEmpty, !value.hasPrefix("$(")
        else { throw Error.missing(key) }
        return value
    }
}
