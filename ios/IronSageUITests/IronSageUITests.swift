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
        app.launchArguments = ["-demo", "-resetLanguage", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
    }

    func testTodayShowsTheNextTemplateDayWithTheCoachsReasons() {
        XCTAssertTrue(app.staticTexts["Up next"].waitForExistence(timeout: 15))
        XCTAssertTrue(app.staticTexts["Legs"].exists)
        XCTAssertTrue(app.staticTexts["Back squat"].exists)
        XCTAssertTrue(app.staticTexts["Training guidance, not medical advice. Stop if something hurts."].exists)
    }

    func testAWorkoutFromUpNextCanBeLoggedAndFinished() {
        let start = app.buttons["startUpNext"]
        XCTAssertTrue(start.waitForExistence(timeout: 15))
        start.tap()

        XCTAssertTrue(app.navigationBars["Workout"].waitForExistence(timeout: 10))
        let markDone = app.buttons["Mark done"].firstMatch
        XCTAssertTrue(markDone.waitForExistence(timeout: 5))
        markDone.tap()
        XCTAssertTrue(app.buttons["Mark not done"].firstMatch.waitForExistence(timeout: 5))

        // A centered alert, with Cancel, rather than a popover from the button.
        app.buttons["Finish"].tap()
        let alert = app.alerts["Finish this workout?"]
        XCTAssertTrue(alert.waitForExistence(timeout: 5))
        XCTAssertTrue(alert.buttons["Cancel"].exists)
        alert.buttons["Finish workout"].tap()

        // The summary opens, with the sets and no volume; Done closes it and the
        // workout, back on Today.
        let done = app.buttons["Done"]
        XCTAssertTrue(done.waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Sets"].exists)
        XCTAssertFalse(app.staticTexts["Volume"].exists)
        done.tap()
        XCTAssertTrue(app.tabBars.buttons["Today"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.navigationBars["Workout"].exists)
    }

    func testAHiddenWorkoutStaysInTheBarAboveTheTabs() {
        let start = app.buttons["startUpNext"]
        XCTAssertTrue(start.waitForExistence(timeout: 15))
        start.tap()
        let markDone = app.buttons["Mark done"].firstMatch
        XCTAssertTrue(markDone.waitForExistence(timeout: 10))
        markDone.tap()
        app.buttons["Hide"].tap()

        // The rest keeps counting in the bar, and a tap opens the workout again with it.
        let bar = app.buttons.containing(NSPredicate(format: "label CONTAINS 'Rest'")).firstMatch
        XCTAssertTrue(bar.waitForExistence(timeout: 10))
        bar.tap()
        XCTAssertTrue(app.navigationBars["Workout"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Rest"].exists)
    }

    func testAnExerciseMarkedDoneFoldsAndOpensAgain() {
        let start = app.buttons["startUpNext"]
        XCTAssertTrue(start.waitForExistence(timeout: 15))
        start.tap()
        let markDone = app.buttons["Mark done"].firstMatch
        XCTAssertTrue(markDone.waitForExistence(timeout: 10))
        markDone.tap()
        // Without the rest bar: it redraws every second, so the app never idles and
        // each lookup while scrolling waits for it, which takes minutes on CI.
        let skip = app.buttons["Skip"]
        XCTAssertTrue(skip.waitForExistence(timeout: 5))
        skip.tap()

        let done = app.buttons["exerciseDone"].firstMatch
        scrollIntoClearView(done)
        done.tap()
        // Back squat folds to one row; its set fields go.
        let folded = app.buttons["showSets"].firstMatch
        XCTAssertTrue(folded.waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label BEGINSWITH '1 of '")).firstMatch.exists)
        XCTAssertFalse(app.buttons["Mark not done"].exists)

        // Still folded after hiding the workout and opening it again.
        app.buttons["Hide"].tap()
        let bar = app.buttons.containing(NSPredicate(format: "label CONTAINS ' sets'")).firstMatch
        XCTAssertTrue(bar.waitForExistence(timeout: 10))
        bar.tap()
        // The first exercise, so it opens near the top: no scrolling needed.
        XCTAssertTrue(folded.waitForExistence(timeout: 10))
        folded.tap()
        XCTAssertTrue(app.buttons["Mark not done"].firstMatch.waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["showSets"].exists)
    }

    func testTheKeyboardGoesOnWithNextAndClosesOnATapOutside() {
        let start = app.buttons["startUpNext"]
        XCTAssertTrue(start.waitForExistence(timeout: 15))
        start.tap()
        let weight = app.textFields["Weight"].firstMatch
        XCTAssertTrue(weight.waitForExistence(timeout: 10))
        weight.tap()
        XCTAssertTrue(hasFocus(weight))

        // A number pad has no return key: Next goes to the reps.
        app.buttons["Next"].tap()
        XCTAssertTrue(hasFocus(app.textFields["Reps"].firstMatch))

        // A tap outside the fields closes the keyboard.
        app.navigationBars["Workout"].staticTexts["Workout"].tap()
        XCTAssertTrue(waitForNoFocus())

        // So does Done.
        weight.tap()
        XCTAssertTrue(hasFocus(weight))
        app.buttons["Done"].tap()
        XCTAssertTrue(waitForNoFocus())

        // And with the rest timer running after a set: the next set's weight still has
        // Next and Done above the keyboard.
        app.buttons["Mark done"].firstMatch.tap()
        XCTAssertTrue(app.staticTexts["Rest"].waitForExistence(timeout: 5))
        let nextWeight = app.textFields.matching(identifier: "Weight").element(boundBy: 1)
        nextWeight.tap()
        XCTAssertTrue(hasFocus(nextWeight))
        XCTAssertTrue(app.buttons["Next"].waitForExistence(timeout: 5))
        app.buttons["Done"].tap()
        XCTAssertTrue(waitForNoFocus())
    }

    func testAWeightCanBeSavedWithoutClosingTheKeyboard() {
        app.tabBars.buttons["Progress"].tap()
        XCTAssertTrue(app.navigationBars["Progress"].waitForExistence(timeout: 10))
        let enter = app.buttons["Enter my weight"].firstMatch
        scrollIntoClearView(enter)
        enter.tap()
        let field = app.textFields["Weight"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        XCTAssertTrue(hasFocus(field))
        field.typeText("81.5")
        let save = app.navigationBars["Enter my weight"].buttons["Save"]
        XCTAssertTrue(save.isEnabled)
        save.tap()
        XCTAssertTrue(app.navigationBars["Enter my weight"].waitForNonExistence(timeout: 5))
    }

    func testASetCanBeLoggedAtTheLargestTextSize() {
        app.terminate()
        app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        app.launch()
        // Up next is further down at this size; the list only makes rows as they scroll in.
        XCTAssertTrue(app.tabBars.buttons["Today"].waitForExistence(timeout: 15))
        let start = app.buttons["startUpNext"]
        scrollIntoClearView(start)
        start.tap()
        XCTAssertTrue(app.navigationBars["Workout"].waitForExistence(timeout: 10))

        // Each set takes two lines, so its fields and the done button stay on screen.
        let markDone = app.buttons["Mark done"].firstMatch
        for _ in 0..<8 where !markDone.isHittable {
            app.swipeUp()
        }
        XCTAssertTrue(markDone.isHittable)
        XCTAssertTrue(app.textFields["Weight"].firstMatch.isHittable)
        markDone.tap()
        XCTAssertTrue(app.buttons["Mark not done"].firstMatch.waitForExistence(timeout: 5))
    }

    func testTheWorkoutScreenShowsHowToDoAnExercise() {
        let start = app.buttons["startUpNext"]
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
        let empty = app.buttons["Empty workout"]
        XCTAssertTrue(empty.waitForExistence(timeout: 15))
        empty.tap()
        app.buttons["Add exercise"].firstMatch.tap()

        // Search first: with every exercise listed, each lookup in the sheet above it
        // takes many seconds on CI.
        app.searchFields.firstMatch.typeText("lateral raise")
        let info = app.buttons["How to do Dumbbell lateral raise"].firstMatch
        XCTAssertTrue(info.waitForExistence(timeout: 10))
        info.tap()
        XCTAssertTrue(app.staticTexts["Raise to shoulder height, no higher."].waitForExistence(timeout: 5))
        // The sheet's own Add, not the list's Add exercise underneath it.
        app.navigationBars["Dumbbell lateral raise"].buttons["Add"].tap()

        XCTAssertTrue(app.buttons["How to do Dumbbell lateral raise"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.navigationBars["Workout"].exists)
    }

    func testCardioCanBeAddedFromTheWatchOrLoggedByHand() {
        let empty = app.buttons["Empty workout"]
        XCTAssertTrue(empty.waitForExistence(timeout: 15))
        empty.tap()
        let addCardio = app.buttons["Add cardio"].firstMatch
        XCTAssertTrue(addCardio.waitForExistence(timeout: 10))
        addCardio.tap()

        // The demo's Watch recorded stairs this morning.
        let fromWatch = app.buttons["Add Stair climber"]
        XCTAssertTrue(fromWatch.waitForExistence(timeout: 10))
        fromWatch.tap()
        XCTAssertTrue(app.staticTexts["Added"].waitForExistence(timeout: 5))

        // The incline walk starts from last time's 15 minutes.
        app.buttons["cardio-Incline walk"].tap()
        let add = app.navigationBars["Incline walk"].buttons["Add"]
        XCTAssertTrue(add.waitForExistence(timeout: 5))
        XCTAssertTrue(add.isEnabled)
        add.tap()

        XCTAssertTrue(app.navigationBars["Workout"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Incline walk"].exists)
        XCTAssertTrue(app.staticTexts["Stair climber"].exists)
        app.buttons["Finish"].tap()
        let confirm = app.buttons["Finish workout"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 5))
        confirm.tap()
        XCTAssertTrue(app.staticTexts["Cardio"].waitForExistence(timeout: 10))
    }

    func testTheProgressTabShowsBodyWeightAndSetsPerMuscle() {
        app.tabBars.buttons["Progress"].tap()
        XCTAssertTrue(app.navigationBars["Progress"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Body weight"].waitForExistence(timeout: 5))
        // Each muscle is one row, read as its name and its sets.
        let glutes = app.descendants(matching: .any).matching(NSPredicate(format: "label == 'Glutes' AND value == '5 sets'")).firstMatch
        scrollIntoClearView(glutes)
        XCTAssertFalse(app.staticTexts["Weekly volume"].exists)
    }

    func testDiscardingAWorkoutAsksInACenteredAlert() {
        let empty = app.buttons["Empty workout"]
        XCTAssertTrue(empty.waitForExistence(timeout: 15))
        empty.tap()
        let discard = app.buttons["Discard workout"]
        XCTAssertTrue(discard.waitForExistence(timeout: 10))
        discard.tap()
        let alert = app.alerts["Discard this workout?"]
        XCTAssertTrue(alert.waitForExistence(timeout: 5))
        alert.buttons["Cancel"].tap()
        XCTAssertTrue(alert.waitForNonExistence(timeout: 5))
        XCTAssertTrue(app.navigationBars["Workout"].exists)

        discard.tap()
        app.alerts["Discard this workout?"].buttons["Discard workout"].tap()
        XCTAssertTrue(app.tabBars.buttons["Today"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.navigationBars["Workout"].exists)
    }

    func testAProgramCanBeHiddenAndShownAgain() {
        app.tabBars.buttons["Templates"].tap()
        // The demo profile is intermediate, so the list opens on that level.
        let program = app.buttons.containing(NSPredicate(format: "label BEGINSWITH 'Upper / lower: strength and size'")).firstMatch
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

    func testTheProgramsCanBeHiddenAndShownAgain() {
        app.tabBars.buttons["Templates"].tap()
        let program = app.buttons.containing(NSPredicate(format: "label BEGINSWITH 'Upper / lower: strength and size'")).firstMatch
        XCTAssertTrue(program.waitForExistence(timeout: 10))
        let fold = app.buttons["foldPrograms"]
        XCTAssertEqual(fold.label, "Hide IronSage programs")
        fold.tap()
        XCTAssertTrue(program.waitForNonExistence(timeout: 5))
        XCTAssertFalse(app.segmentedControls["programLevel"].exists)
        XCTAssertTrue(app.staticTexts["Hidden on this iPhone. Tap Show to see them again."].exists)

        XCTAssertEqual(fold.label, "Show IronSage programs")
        fold.tap()
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
        // Search first, so the lookups don't go through every exercise.
        app.searchFields.firstMatch.typeText("back squat")
        let squat = app.buttons.containing(NSPredicate(format: "label BEGINSWITH 'Back squat'")).firstMatch
        XCTAssertTrue(squat.waitForExistence(timeout: 10))
        squat.tap()

        // Three sets of 8–12 to start with.
        XCTAssertTrue(app.staticTexts["3 × 8–12"].waitForExistence(timeout: 5))
        XCTAssertTrue(save.isEnabled)
        save.tap()

        let saved = app.buttons.containing(NSPredicate(format: "label BEGINSWITH 'Home legs'")).firstMatch
        XCTAssertTrue(saved.waitForExistence(timeout: 5))
        saved.tap()
        XCTAssertTrue(app.buttons["startDay"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.navigationBars["Home legs"].buttons["Edit"].exists)
    }

    func testProgramsAreShownByLevelWithTheirGuide() {
        app.tabBars.buttons["Templates"].tap()
        let level = app.segmentedControls["programLevel"]
        XCTAssertTrue(level.waitForExistence(timeout: 10))
        XCTAssertTrue(level.buttons["Intermediate"].isSelected)
        XCTAssertFalse(app.buttons.containing(NSPredicate(format: "label BEGINSWITH 'Barbell basics'")).firstMatch.exists)

        level.buttons["Beginner"].tap()
        let program = app.buttons.containing(NSPredicate(format: "label BEGINSWITH 'Barbell basics'")).firstMatch
        XCTAssertTrue(program.waitForExistence(timeout: 5))
        program.tap()
        XCTAssertTrue(app.staticTexts["How to progress"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["3 × 5"].exists)
        XCTAssertTrue(app.staticTexts["Rest 3 min"].exists)

        app.buttons["Day B"].tap()
        XCTAssertTrue(app.staticTexts["Romanian deadlift"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["startDay"].exists)
    }

    func testAProgramCanBeCopiedToEdit() {
        app.tabBars.buttons["Templates"].tap()
        app.segmentedControls["programLevel"].buttons["Advanced"].tap()
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
        let copy = app.buttons.containing(NSPredicate(format: "label BEGINSWITH 'Push / pull / legs ×2 (my copy)'")).firstMatch
        XCTAssertTrue(copy.waitForExistence(timeout: 5))
    }

    func testBodyWeightAndBodyFatFollowThePeriod() {
        app.tabBars.buttons["Progress"].tap()
        let year = app.segmentedControls["bodyRange"].buttons["Year"]
        XCTAssertTrue(year.waitForExistence(timeout: 10))
        year.tap()
        XCTAssertTrue(year.isSelected)

        // The section is taller than the screen: its heading has scrolled away by the
        // time its last row is clear of the tab bar.
        let heading = app.staticTexts["Body fat"]
        scrollIntoClearView(heading)
        let allBodyFat = app.buttons["All body fat"]
        scrollIntoClearView(allBodyFat)
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
        scrollIntoClearView(coach)
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
        XCTAssertTrue(app.staticTexts["Weeks in a row"].waitForExistence(timeout: 15))
        XCTAssertTrue(app.staticTexts["Workouts"].exists)
        // Syncing that works isn't shown.
        XCTAssertFalse(app.otherElements["syncProblem"].exists)
        XCTAssertTrue(app.buttons["bodyFat"].exists)

        app.buttons["bodyWeight"].tap()
        // Switching tabs can take a while on a busy CI runner.
        XCTAssertTrue(app.navigationBars["Progress"].waitForExistence(timeout: 15))
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

    func testTheLanguageCanBeChangedInTheApp() {
        app.tabBars.buttons["Me"].tap()
        app.buttons["profile"].tap()
        let language = app.buttons["language"]
        scrollIntoClearView(language)
        XCTAssertTrue(language.waitForExistence(timeout: 5))
        language.tap()
        app.buttons["简体中文"].tap()

        // The app switches at once and stays on Me.
        XCTAssertTrue(app.tabBars.buttons["我"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["连续周数"].exists)

        // Only the two languages are offered, the one in use checked; back to English.
        app.buttons["profile"].tap()
        scrollIntoClearView(language)
        language.tap()
        XCTAssertFalse(app.buttons["跟随 iPhone"].exists)
        app.buttons["English"].tap()
        XCTAssertTrue(app.tabBars.buttons["Me"].waitForExistence(timeout: 10))
    }

    func testThePrivacyPolicyOpensWithoutANetwork() {
        // Demo mode never goes online, so the text comes with the app.
        app.tabBars.buttons["Me"].tap()
        app.buttons["profile"].tap()
        let privacy = app.buttons["Privacy policy"]
        scrollIntoClearView(privacy)
        privacy.tap()
        XCTAssertTrue(app.staticTexts["What IronSage keeps"].waitForExistence(timeout: 5))
        app.buttons["Done"].tap()
        XCTAssertTrue(privacy.waitForExistence(timeout: 5))
    }

    func testBodyFatCanBeEnteredAsARange() {
        app.tabBars.buttons["Progress"].tap()
        let enter = app.buttons["Enter body fat"]
        XCTAssertTrue(app.navigationBars["Progress"].waitForExistence(timeout: 10))
        scrollIntoClearView(enter)
        enter.tap()

        // A range is the default; an exact number is the other choice.
        let estimate = app.buttons["Estimate a range"]
        XCTAssertTrue(estimate.waitForExistence(timeout: 5))
        XCTAssertTrue(estimate.isSelected)
        app.buttons["25–30%"].tap()
        app.navigationBars["Body fat"].buttons["Save"].tap()

        app.buttons["All body fat"].tap()
        XCTAssertTrue(app.staticTexts["About 25–30%"].waitForExistence(timeout: 5))
    }

    /// Whether `field` has the keyboard. Read from the field rather than the keyboard,
    /// which a simulator with a hardware keyboard connected doesn't show.
    private func hasFocus(_ field: XCUIElement) -> Bool {
        for _ in 0..<10 {
            if (field.value(forKey: "hasKeyboardFocus") as? Bool) == true { return true }
            usleep(300_000)
        }
        return false
    }

    /// Whether, within a few seconds, no text field has the keyboard.
    private func waitForNoFocus() -> Bool {
        let focused = app.textFields.matching(NSPredicate(format: "hasKeyboardFocus == true"))
        for _ in 0..<10 {
            if focused.count == 0 { return true }
            usleep(300_000)
        }
        return false
    }

    /// Scrolls until `element` sits between the navigation bar and the tab bar, then
    /// waits for the list to stop. Hittable is not enough: iOS 26's bars float over
    /// the list, so a tap on a part they cover lands on the bar, and a tap on a list
    /// that is still moving only stops it. A fast swipe goes a different distance each
    /// time, which can leave the element under the navigation bar, so swipes are slow.
    private func scrollIntoClearView(_ element: XCUIElement, file: StaticString = #filePath, line: UInt = #line) {
        let top = app.navigationBars.firstMatch
        let bottom = app.tabBars.firstMatch
        func isClear() -> Bool {
            guard element.exists, element.isHittable else { return false }
            let frame = element.frame
            return frame.minY > (top.exists ? top.frame.maxY : 0)
                && frame.maxY < (bottom.exists ? bottom.frame.minY - 8 : app.frame.maxY)
        }
        for _ in 0..<12 where !isClear() {
            if element.exists, top.exists, element.frame.minY <= top.frame.maxY {
                app.swipeDown(velocity: .slow)
            } else {
                app.swipeUp(velocity: .slow)
            }
        }
        var last = CGRect.null
        for _ in 0..<10 where element.exists && element.frame != last {
            last = element.frame
            usleep(300_000)
        }
        XCTAssertTrue(isClear(), "\(element) is not clear of the bars", file: file, line: line)
    }
}
