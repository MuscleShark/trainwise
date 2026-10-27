import Foundation
@testable import IronSageCore
import XCTest

final class ExerciseVisualsTests: XCTestCase {
    func testBuiltinIDsMatchTheAPI() {
        // uuid.uuid5(CATALOG_NAMESPACE, "exercise:<slug>") in backend/catalog.py
        XCTAssertEqual(ExerciseVisuals.builtinID(slug: "back_squat"), UUID(uuidString: "f203cee6-6f92-5cc0-aaf8-95671d8de7c6"))
        XCTAssertEqual(ExerciseVisuals.builtinID(slug: "lateral_raise"), UUID(uuidString: "d28e580e-328e-5333-8a3c-fc8da09015c9"))
    }

    func testEveryBuiltinExerciseHasAMovement() throws {
        let catalog = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().appendingPathComponent("../../../../backend/catalog.py").standardized
        let source = try String(contentsOf: catalog, encoding: .utf8)
        let slugs = source.matches(of: /\n\s+E\("(\w+)"/).map { String($0.output.1) }
        XCTAssertEqual(slugs.count, 145)
        XCTAssertEqual(Set(slugs), Set(ExerciseVisuals.movementBySlug.keys))
        for slug in slugs {
            XCTAssertNotNil(ExerciseVisuals.movement(forID: ExerciseVisuals.builtinID(slug: slug)), slug)
        }
    }

    func testEveryPoseIsComplete() {
        for (name, pattern) in ExerciseVisuals.patterns {
            guard case .side(let side) = pattern.view else { continue }
            for pose in [side.start.over(side.base), side.end.over(side.base)] {
                for key in [\Pose.t, \.th, \.sh, \.ua, \.fa] {
                    XCTAssertNotNil(pose[keyPath: key], "\(name) leaves an angle to the default")
                }
                XCTAssertNotNil(pose.anchor, name)
                XCTAssertEqual(pose.th2 == nil, pose.sh2 == nil, "\(name) has half a far leg")
                XCTAssertEqual(pose.ua2 == nil, pose.fa2 == nil, "\(name) has half a far arm")
            }
        }
    }

    func testFiguresStayInTheirBox() {
        for name in ExerciseVisuals.patterns.keys {
            let movement = ExerciseVisuals.movement(named: name)!
            for progress in stride(from: 0.0, through: 1.0, by: 0.25) {
                for equipment in Equipment.allCases {
                    var bounds = Bounds()
                    bounds.add(movement.figure(at: progress, equipment: equipment))
                    XCTAssertTrue(bounds.minX >= 0 && bounds.maxX <= Figure.size, "\(name) at \(progress): x \(bounds.minX)…\(bounds.maxX)")
                    XCTAssertTrue(bounds.minY >= 0 && bounds.maxY <= Figure.size, "\(name) at \(progress): y \(bounds.minY)…\(bounds.maxY)")
                }
            }
        }
    }

    func testTheFigureMovesBetweenItsPoses() {
        let squat = ExerciseVisuals.movement(named: "squat")!
        XCTAssertNotEqual(hipHeight(squat.figure(at: 0, equipment: .barbell)), hipHeight(squat.figure(at: 1, equipment: .barbell)))
        XCTAssertFalse(squat.isHold)
        XCTAssertTrue(ExerciseVisuals.movement(named: "plank")!.isHold)
    }

    func testACustomVariationShowsItsBaseExercise() {
        let hack = ExerciseVisuals.builtinID(slug: "hack_squat")
        let custom = Exercise(nameEn: "Narrow hack squat", equipment: .machine, loadType: .total, primaryMuscles: [.quads],
                              baseExerciseId: hack, isCustom: true)
        XCTAssertEqual(ExerciseVisuals.movement(for: custom)?.name, "machine_squat")
        let plain = Exercise(nameEn: "Mystery machine", equipment: .machine, loadType: .total, primaryMuscles: [.chest], isCustom: true)
        XCTAssertNil(ExerciseVisuals.movement(for: plain))
    }

    /// The torso line's lowest point (the hip, for a standing figure).
    private func hipHeight(_ figure: Figure) -> Double {
        for case .polyline(let points, .body) in figure.items { return points[3].y }
        return .nan
    }
}

extension ExerciseVisualsTests {
    func testAZoomedFigureFillsItsBox() {
        for name in ExerciseVisuals.patterns.keys {
            // Zooming fits the whole movement, so measure every pose of it.
            var bounds = Bounds()
            for progress in [0, 0.25, 0.5, 0.75, 1.0] {
                bounds.add(ExerciseVisuals.movement(named: name)!.figure(at: progress, equipment: .barbell, zoomed: true))
            }
            let size = max(bounds.maxX - bounds.minX, bounds.maxY - bounds.minY)
            // Line widths don't change with the figure's scale, so it lands near, not on, the margin.
            XCTAssertGreaterThan(size, Figure.size * 0.9, name)
            XCTAssertTrue(bounds.minX >= 0 && bounds.maxX <= Figure.size && bounds.minY >= 0 && bounds.maxY <= Figure.size, name)
        }
    }
}
