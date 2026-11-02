import Foundation
import Testing

@testable import IronSageCore

private let both: [String: String] = [
    "STAGING_API_URL": "https://staging.example.com",
    "PRODUCTION_API_URL": "https://api.example.com",
    "CLERK_PUBLISHABLE_KEY": "pk_test_abc",
]

@Test func readsTheBuildSettingsForEachServer() throws {
    let staging = try AppConfig(info: both, server: .staging)
    #expect(staging.apiBaseURL == URL(string: "https://staging.example.com"))
    #expect(staging.clerkPublishableKey == "pk_test_abc")
    let production = try AppConfig(info: both, server: .production)
    #expect(production.apiBaseURL == URL(string: "https://api.example.com"))
    #expect(production.server == .production)
}

@Test func theServerFollowsWhereTheAppCameFrom() {
    // Run from Xcode: staging, whatever the receipt.
    #expect(AppConfig.Server.forInstall(debugBuild: true, receiptName: nil) == .staging)
    #expect(AppConfig.Server.forInstall(debugBuild: true, receiptName: "receipt") == .staging)
    // TestFlight (and App Review): a sandbox receipt.
    #expect(AppConfig.Server.forInstall(debugBuild: false, receiptName: "sandboxReceipt") == .staging)
    // The App Store.
    #expect(AppConfig.Server.forInstall(debugBuild: false, receiptName: "receipt") == .production)
    #expect(AppConfig.Server.forInstall(debugBuild: false, receiptName: nil) == .production)
}

@Test func rejectsUnsetBuildSettings() {
    #expect(throws: AppConfig.Error.missing("STAGING_API_URL")) {
        try AppConfig(info: ["STAGING_API_URL": "$(STAGING_API_URL)", "CLERK_PUBLISHABLE_KEY": "pk"], server: .staging)
    }
    #expect(throws: AppConfig.Error.missing("CLERK_PUBLISHABLE_KEY")) {
        try AppConfig(info: ["PRODUCTION_API_URL": "https://api.example.com", "CLERK_PUBLISHABLE_KEY": ""], server: .production)
    }
}

@Test func requiresHTTPSOutsideLocalhost() throws {
    #expect(throws: AppConfig.Error.invalidURL("http://api.example.com")) {
        try AppConfig(info: ["PRODUCTION_API_URL": "http://api.example.com", "CLERK_PUBLISHABLE_KEY": "pk"], server: .production)
    }
    let local = try AppConfig(info: ["STAGING_API_URL": "http://localhost:8000", "CLERK_PUBLISHABLE_KEY": "pk"], server: .staging)
    #expect(local.apiBaseURL.port == 8000)
}
