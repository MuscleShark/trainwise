import XCTest

/// The app's main flows, clicked through in the simulator. They run in demo mode
/// (`-demo`): sample data in memory, no sign-in and no network, so they need no
/// account and never touch the real API.
@MainActor
final class IronSageUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() async throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-demo", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
    }

    func testTodayShowsTheNextTemplateDayWithTheCoachsReasons() {
        XCTAssertTrue(app.staticTexts["Up next"].waitForExistence(timeout: 15))
        XCTAssertTrue(app.staticTexts["Legs"].exists)
        XCTAssertTrue(app.staticTexts["Back squat"].exists)
        XCTAssertTrue(app.staticTexts["Training guidance, not medical advice. Stop if something hurts."].exists)
    }

    func testAWorkoutFromUpNextCanBeLoggedAndFinished() {
        let start = app.buttons.containing(NSPredicate(format: "label CONTAINS 'Legs'")).firstMatch
        XCTAssertTrue(start.waitForExistence(timeout: 15))
        start.tap()

        XCTAssertTrue(app.navigationBars["Workout"].waitForExistence(timeout: 10))
        let markDone = app.buttons["Mark done"].firstMatch
        XCTAssertTrue(markDone.waitForExistence(timeout: 5))
        markDone.tap()
        XCTAssertTrue(app.buttons["Mark not done"].firstMatch.waitForExistence(timeout: 5))

        app.buttons["Finish"].tap()
        let confirm = app.buttons["Finish workout"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 5))
        confirm.tap()

        // The summary opens; Done closes it and the workout, back on Today.
        let done = app.buttons["Done"]
        XCTAssertTrue(done.waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Volume is weight × reps of the working sets; one dumbbell per side counts twice."].exists)
        done.tap()
        XCTAssertTrue(app.tabBars.buttons["Today"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.navigationBars["Workout"].exists)
    }

    func testTheWorkoutScreenShowsHowToDoAnExercise() {
        let start = app.buttons.containing(NSPredicate(format: "label CONTAINS 'Legs'")).firstMatch
        XCTAssertTrue(start.waitForExistence(timeout: 15))
        start.tap()

        let info = app.buttons["How to do Back squat"]
        XCTAssertTrue(info.waitForExistence(timeout: 10))
        info.tap()
        XCTAssertTrue(app.staticTexts["Brace your core and keep your whole foot on the floor."].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Main: Quads"].exists)
        app.buttons["Close"].tap()
        XCTAssertTrue(app.navigationBars["Workout"].waitForExistence(timeout: 5))
    }

    func testAnExerciseCanBeAddedFromItsHowToSheet() {
        let empty = app.buttons["Start an empty workout"]
        XCTAssertTrue(empty.waitForExistence(timeout: 15))
        empty.tap()
        app.buttons["Add exercise"].firstMatch.tap()

        // It's in both Recent and All exercises.
        let info = app.buttons["How to do Dumbbell lateral raise"].firstMatch
        XCTAssertTrue(info.waitForExistence(timeout: 10))
        info.tap()
        XCTAssertTrue(app.staticTexts["Raise to shoulder height, no higher."].waitForExistence(timeout: 5))
        // The sheet's own Add, not the list's Add exercise underneath it.
        app.navigationBars["Dumbbell lateral raise"].buttons["Add"].tap()

        XCTAssertTrue(app.buttons["How to do Dumbbell lateral raise"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.navigationBars["Workout"].exists)
    }

    func testTheProgressTabShowsBodyWeightAndVolume() {
        app.tabBars.buttons["Progress"].tap()
        XCTAssertTrue(app.navigationBars["Progress"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Body weight"].waitForExistence(timeout: 5))
        let volume = app.staticTexts["Weekly volume"]
        for _ in 0..<4 where !volume.isHittable {
            app.swipeUp()
        }
        XCTAssertTrue(volume.waitForExistence(timeout: 5))
    }

    func testTurningTheCoachOffAsksFirst() {
        app.tabBars.buttons["Settings"].tap()
        let coach = app.switches["AI coach"]
        for _ in 0..<4 where !coach.isHittable {
            app.swipeUp()
        }
        XCTAssertTrue(coach.waitForExistence(timeout: 5))
        XCTAssertEqual(coach.value as? String, "1")

        // A plain tap on a SwiftUI switch can miss its knob; tap the knob itself.
        coach.switches.firstMatch.exists ? coach.switches.firstMatch.tap() : coach.tap()
        let alert = app.alerts["Turn off the AI coach?"]
        XCTAssertTrue(alert.waitForExistence(timeout: 5))
        alert.buttons["Keep on"].tap()
        XCTAssertEqual(coach.value as? String, "1")
    }
}
