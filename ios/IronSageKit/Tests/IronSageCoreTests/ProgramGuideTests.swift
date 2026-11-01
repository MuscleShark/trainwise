import Foundation
@testable import IronSageCore
import XCTest

final class ProgramGuideTests: XCTestCase {
    func testBuiltinIDsMatchTheAPI() {
        // uuid.uuid5(TEMPLATE_NAMESPACE, "template:push_pull_legs") in backend/template_catalog.py
        XCTAssertEqual(ProgramGuide.builtinID(slug: "push_pull_legs"), UUID(uuidString: "8e1d0bd8-d0cb-5c2f-a8ae-74bf54c2cd02"))
    }

    func testEveryBuiltinProgramHasAGuide() throws {
        let catalog = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().appendingPathComponent("../../../../backend/template_catalog.py").standardized
        let source = try String(contentsOf: catalog, encoding: .utf8)
        let slugs = source.matches(of: /BuiltinTemplate\(\s*"(\w+)"/).map { String($0.output.1) }
        XCTAssertEqual(slugs.count, 15)
        XCTAssertEqual(Set(slugs), Set(ProgramGuide.bySlug.keys))
        for slug in slugs {
            let guide = try XCTUnwrap(ProgramGuide.forTemplate(ProgramGuide.builtinID(slug: slug)), slug)
            XCTAssertFalse(guide.who(chinese: true).isEmpty)
            XCTAssertNotEqual(guide.progress(chinese: false), guide.progress(chinese: true))
        }
    }
}
