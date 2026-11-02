@testable import IronSage
import IronSageCore
import XCTest

/// Text looked up in code follows a language picked in Me › Profile at once, like the
/// text in the views.
@MainActor
final class AppLanguageTests: XCTestCase {
    override func tearDown() async throws {
        AppLanguage.choose(.system)
    }

    func testCodeLookupsFollowThePickedLanguage() {
        AppLanguage.choose(.chinese)
        XCTAssertEqual(String(appLocalized: "Connected"), "已连接")
        XCTAssertEqual(String(appLocalized: Goal.hypertrophy.label), "增肌")

        AppLanguage.choose(.english)
        XCTAssertEqual(String(appLocalized: "Connected"), "Connected")
        XCTAssertEqual(String(appLocalized: Goal.hypertrophy.label), "Build muscle")
    }
}
