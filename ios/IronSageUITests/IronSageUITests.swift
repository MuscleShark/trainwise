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

    func testAProgramCanBeHiddenAndShownAgain() {
        app.tabBars.buttons["Templates"].tap()
        let program = app.buttons.containing(NSPredicate(format: "label BEGINSWITH 'Beginner full body'")).firstMatch
        XCTAssertTrue(program.waitForExistence(timeout: 10))
        program.swipeLeft()
        app.buttons["Hide program"].tap()
        XCTAssertTrue(program.waitForNonExistence(timeout: 5))

        app.buttons.containing(NSPredicate(format: "label BEGINSWITH 'Hidden programs'")).firstMatch.tap()
        XCTAssertTrue(app.navigationBars["Hidden programs"].waitForExistence(timeout: 5))
        app.buttons["Show"].tap()
        app.navigationBars.buttons.firstMatch.tap()
        XCTAssertTrue(program.waitForExistence(timeout: 5))
    }

    func testATemplateCanBeBuiltFromScratch() {
        app.tabBars.buttons["Templates"].tap()
        let new = app.buttons["New template"]
        XCTAssertTrue(new.waitForExistence(timeout: 10))
        new.tap()

        let save = app.navigationBars["New template"].buttons["Save"]
        XCTAssertTrue(save.waitForExistence(timeout: 5))
        XCTAssertFalse(save.isEnabled)
        let name = app.textFields["templateName"]
        name.tap()
        name.typeText("Home legs")
        app.buttons["Add exercise"].tap()
        let squat = app.buttons.containing(NSPredicate(format: "label BEGINSWITH 'Back squat'")).firstMatch
        XCTAssertTrue(squat.waitForExistence(timeout: 10))
        squat.tap()

        // Three sets of 8–12 to start with.
        XCTAssertTrue(app.staticTexts["3 × 8–12 · RIR 2"].waitForExistence(timeout: 5))
        XCTAssertTrue(save.isEnabled)
        save.tap()

        let saved = app.buttons.containing(NSPredicate(format: "label BEGINSWITH 'Home legs'")).firstMatch
        XCTAssertTrue(saved.waitForExistence(timeout: 5))
        saved.tap()
        XCTAssertTrue(app.buttons["Start this workout"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.navigationBars["Home legs"].buttons["Edit"].exists)
    }

    func testAProgramCanBeCopiedToEdit() {
        app.tabBars.buttons["Templates"].tap()
        let program = app.buttons.containing(NSPredicate(format: "label BEGINSWITH 'Push / pull / legs'")).firstMatch
        XCTAssertTrue(program.waitForExistence(timeout: 10))
        program.tap()
        app.buttons["programMenu"].tap()
        app.buttons["Copy and edit"].tap()

        let save = app.navigationBars["Copy and edit"].buttons["Save"]
        XCTAssertTrue(save.waitForExistence(timeout: 5))
        XCTAssertTrue(save.isEnabled)
        save.tap()
        app.navigationBars.buttons.firstMatch.tap()
        let copy = app.buttons.containing(NSPredicate(format: "label BEGINSWITH 'Push / pull / legs (my copy)'")).firstMatch
        XCTAssertTrue(copy.waitForExistence(timeout: 5))
    }

    func testBodyWeightAndBodyFatFollowThePeriod() {
        app.tabBars.buttons["Progress"].tap()
        let year = app.segmentedControls["bodyRange"].buttons["Year"]
        XCTAssertTrue(year.waitForExistence(timeout: 10))
        year.tap()
        XCTAssertTrue(year.isSelected)

        let allBodyFat = app.buttons["All body fat"]
        for _ in 0..<4 where !allBodyFat.isHittable {
            app.swipeUp()
        }
        XCTAssertTrue(app.staticTexts["Body fat"].exists)
        allBodyFat.tap()
        XCTAssertTrue(app.navigationBars["All body fat"].waitForExistence(timeout: 5))
        app.navigationBars.buttons.firstMatch.tap()

        // Back to the default for the other tests.
        for _ in 0..<4 where !year.isHittable {
            app.swipeDown()
        }
        app.segmentedControls["bodyRange"].buttons["Month"].tap()
    }

    func testTurningTheCoachOffAsksFirst() {
        app.tabBars.buttons["Me"].tap()
        app.buttons["profile"].tap()
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

    func testMeShowsTrainingAndBodyWeightThatOpensProgress() {
        app.tabBars.buttons["Me"].tap()
        XCTAssertTrue(app.staticTexts["Weeks in a row"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Workouts"].exists)
        // Syncing that works isn't shown.
        XCTAssertFalse(app.otherElements["syncProblem"].exists)
        XCTAssertTrue(app.buttons["bodyFat"].exists)

        app.buttons["bodyWeight"].tap()
        XCTAssertTrue(app.navigationBars["Progress"].waitForExistence(timeout: 5))
    }

    func testMeShowsWhatTheCoachAddsAndSignOutComesLast() {
        app.tabBars.buttons["Me"].tap()
        app.buttons["coachPlan"].tap()
        XCTAssertTrue(app.staticTexts["Log workouts, even offline"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["The reason behind each suggested weight and rep"].exists)
        app.navigationBars.buttons.firstMatch.tap()

        let signOut = app.buttons["Sign out"]
        let delete = app.buttons["Delete account"]
        for _ in 0..<4 where !delete.isHittable {
            app.swipeUp()
        }
        XCTAssertTrue(signOut.waitForExistence(timeout: 5))
        XCTAssertLessThan(signOut.frame.minY, delete.frame.minY)
        XCTAssertFalse(app.switches["AI coach"].exists)
    }
}
