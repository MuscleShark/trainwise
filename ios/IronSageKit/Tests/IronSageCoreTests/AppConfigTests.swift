import Foundation
import Testing

@testable import IronSageCore

@Test func readsTheBuildSettings() throws {
    let config = try AppConfig(info: [
        "API_BASE_URL": "https://api.example.com",
        "CLERK_PUBLISHABLE_KEY": "pk_test_abc",
    ])
    #expect(config.apiBaseURL == URL(string: "https://api.example.com"))
    #expect(config.clerkPublishableKey == "pk_test_abc")
}

@Test func rejectsUnsetBuildSettings() {
    #expect(throws: AppConfig.Error.missing("API_BASE_URL")) {
        try AppConfig(info: ["API_BASE_URL": "$(API_BASE_URL)", "CLERK_PUBLISHABLE_KEY": "pk"])
    }
    #expect(throws: AppConfig.Error.missing("CLERK_PUBLISHABLE_KEY")) {
        try AppConfig(info: ["API_BASE_URL": "https://api.example.com", "CLERK_PUBLISHABLE_KEY": ""])
    }
}

@Test func requiresHTTPSOutsideLocalhost() throws {
    #expect(throws: AppConfig.Error.invalidURL("http://api.example.com")) {
        try AppConfig(info: ["API_BASE_URL": "http://api.example.com", "CLERK_PUBLISHABLE_KEY": "pk"])
    }
    let local = try AppConfig(info: [
        "API_BASE_URL": "http://localhost:8000", "CLERK_PUBLISHABLE_KEY": "pk",
    ])
    #expect(local.apiBaseURL.port == 8000)
}
