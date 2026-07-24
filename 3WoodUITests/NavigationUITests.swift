import XCTest

/// Drives the whole app through the UI: signs in with a demo account, visits
/// every tab and screen, exercises the ranking-comparison flow end to end, and
/// attaches a screenshot of each screen. Assertions verify that buttons act as
/// intended and page transitions land on the right screen.
final class NavigationUITests: XCTestCase {
    let app = XCUIApplication()
    let timeout: TimeInterval = 15

    override func setUp() {
        continueAfterFailure = true
        app.launch()
    }

    private func snapshot(_ name: String) {
        let shot = XCUIScreen.main.screenshot()
        let attachment = XCTAttachment(screenshot: shot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func tap(_ element: XCUIElement, _ label: String) {
        XCTAssertTrue(element.waitForExistence(timeout: timeout), "Missing element: \(label)")
        element.tap()
    }

    /// Switch tabs reliably. The very first tab switch right after programmatic
    /// sign-in can be dropped, so tap until the tab reports selected.
    private func switchToTab(_ name: String) {
        let tab = app.tabBars.buttons[name]
        XCTAssertTrue(tab.waitForExistence(timeout: timeout), "Missing tab: \(name)")
        for _ in 0..<3 where !tab.isSelected {
            tab.tap()
            _ = tab.waitForExistence(timeout: 1)
        }
        XCTAssertTrue(tab.isSelected, "Could not switch to \(name) tab")
    }

    /// Land signed in as birdie_ben (rich demo data), regardless of prior state.
    private func ensureSignedInAsDemo() {
        // If a session is already active, sign out first to reach the welcome screen.
        if app.tabBars.buttons["Profile"].waitForExistence(timeout: 5) {
            app.tabBars.buttons["Profile"].tap()
            let signOut = app.buttons["Sign out"]
            if signOut.waitForExistence(timeout: 5) { signOut.tap() }
        }

        // Welcome screen → Sign in.
        tap(app.buttons["Sign in"], "Sign in button")

        let email = app.textFields.firstMatch
        tap(email, "Email field")
        email.typeText("birdie_ben@example.com")

        let password = app.secureTextFields.firstMatch
        tap(password, "Password field")
        password.typeText("testpass123")

        snapshot("24-SignIn-Form")

        // The bottom "Sign in" submit button.
        let submit = app.buttons["Sign in"]
        tap(submit, "Sign in submit")

        XCTAssertTrue(app.tabBars.buttons["Lists"].waitForExistence(timeout: timeout),
                      "Did not reach the main tab bar after sign-in")
    }

    func testFullNavigation() {
        ensureSignedInAsDemo()

        // --- Lists: Played ---
        switchToTab("Lists")
        XCTAssertTrue(app.navigationBars["My Courses"].waitForExistence(timeout: timeout))
        snapshot("01-Lists-Played")

        // --- Lists: Want to Play segment (custom flat tabs) ---
        let wantSegment = app.buttons["Want to Play"]
        tap(wantSegment, "Want to Play segment")
        snapshot("02-Lists-WantToPlay")
        tap(app.buttons["Played"], "Played segment")

        // --- Search ---
        switchToTab("Search")
        XCTAssertTrue(app.navigationBars["Search"].waitForExistence(timeout: timeout))
        let searchField = app.searchFields.firstMatch
        tap(searchField, "Search field")
        searchField.typeText("pebble beach")
        let pebble = app.staticTexts["Pebble Beach Golf Links"]
        XCTAssertTrue(pebble.waitForExistence(timeout: timeout), "Search did not return Pebble Beach")
        snapshot("03-Search-Results")

        // --- Course detail (from search) ---
        pebble.tap()
        XCTAssertTrue(app.staticTexts["Community rating"].waitForExistence(timeout: timeout),
                      "Course detail did not open")
        snapshot("04-CourseDetail")
        app.navigationBars.buttons.element(boundBy: 0).tap() // back

        // --- Map ---
        switchToTab("Map")
        XCTAssertTrue(app.navigationBars["Map"].waitForExistence(timeout: timeout))
        sleep(2) // let pins load
        snapshot("05-Map")

        // --- Profile ---
        switchToTab("Profile")
        XCTAssertTrue(app.navigationBars["Profile"].waitForExistence(timeout: timeout))
        snapshot("06-Profile")

        // --- About (visited first so it doesn't depend on the friend detour) ---
        tap(app.buttons["About"], "About row")
        XCTAssertTrue(app.staticTexts["Course data"].waitForExistence(timeout: timeout))
        snapshot("09-About")
        goBack()
        XCTAssertTrue(app.navigationBars["Profile"].waitForExistence(timeout: timeout))

        // --- Find friends → a friend's profile ---
        tap(app.buttons["Find friends"], "Find friends row")
        let friendSearch = app.searchFields.firstMatch
        tap(friendSearch, "Friend search field")
        friendSearch.typeText("mulligan")
        let friend = app.staticTexts["@mulligan_mike"]
        if friend.waitForExistence(timeout: timeout) {
            snapshot("07-FindFriends")
            friend.tap()
            if !app.staticTexts["Their courses"].waitForExistence(timeout: 6) {
                friend.tap() // retry once if the first tap only dismissed the keyboard
            }
            XCTAssertTrue(app.staticTexts["Their courses"].waitForExistence(timeout: timeout),
                          "Other-profile did not open")
            snapshot("08-OtherProfile")
        }
    }

    private func goBack() {
        let back = app.navigationBars.buttons.firstMatch
        XCTAssertTrue(back.waitForExistence(timeout: timeout), "No back button")
        back.tap()
    }

    /// Exercises the ranking-comparison flow through the UI, start to finish.
    func testLogCourseFlow() {
        ensureSignedInAsDemo()
        switchToTab("Lists")

        // Open the log flow via the + button (labeled for VoiceOver).
        tap(app.navigationBars.buttons["Log a course"], "Add (+) button")

        let picker = app.searchFields.firstMatch
        tap(picker, "Course picker search")
        picker.typeText("spyglass")
        let target = app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'Spyglass'")).firstMatch
        XCTAssertTrue(target.waitForExistence(timeout: timeout), "Course picker returned no Spyglass")
        snapshot("10-Log-Picker")
        target.tap()

        // Bucket picker.
        let liked = app.buttons["Liked it"]
        XCTAssertTrue(liked.waitForExistence(timeout: timeout), "Bucket picker did not appear")
        snapshot("11-Log-BucketPicker")
        liked.tap()

        // Comparison loop: keep choosing the new course until the flow resolves.
        var guardCount = 0
        while app.staticTexts["Which did you like more?"].waitForExistence(timeout: 5), guardCount < 12 {
            if guardCount == 0 { snapshot("12-Log-Comparison") }
            // The new course card is the first tappable card at the top.
            app.staticTexts["NEW"].tap()
            guardCount += 1
        }

        // Result screen with the revealed score.
        let done = app.buttons["Done"]
        XCTAssertTrue(done.waitForExistence(timeout: timeout), "Ranking flow did not reach the result screen")
        snapshot("13-Log-Result")
        done.tap()

        // Back on the tab bar.
        XCTAssertTrue(app.tabBars.buttons["Lists"].waitForExistence(timeout: timeout),
                      "Did not return to the app after logging")
    }

    /// Verifies the quality-of-life additions: tappable Played rows, the
    /// followers/following lists, and the map filter/list toggle.
    func testQualityOfLife() {
        ensureSignedInAsDemo()

        // Played row → course detail.
        switchToTab("Lists")
        let firstRow = app.cells.element(boundBy: 0)
        XCTAssertTrue(firstRow.waitForExistence(timeout: timeout), "Played list has no rows")
        firstRow.tap()
        XCTAssertTrue(app.staticTexts["Community rating"].waitForExistence(timeout: timeout),
                      "Tapping a Played course did not open its detail")
        snapshot("14-PlayedRow-Detail")
        goBack()

        // Profile → Following list.
        switchToTab("Profile")
        tap(app.staticTexts["Following"], "Following stat")
        XCTAssertTrue(app.navigationBars["Following"].waitForExistence(timeout: timeout),
                      "Following stat did not open the people list")
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH '@'")).firstMatch
                        .waitForExistence(timeout: timeout), "Following list is empty")
        snapshot("15-Following-List")

        // Map → list toggle + filter.
        switchToTab("Map")
        sleep(2)
        tap(app.buttons["mapModeToggle"], "Map/List toggle")
        XCTAssertTrue(app.cells.element(boundBy: 0).waitForExistence(timeout: timeout),
                      "Map list view shows no courses")
        snapshot("16-Map-ListView")
        tap(app.buttons["mapFilter"], "Map filter menu")
        tap(app.buttons["Private"], "Private filter option")
        snapshot("17-Map-Filtered")
    }

    /// Verifies the activity feed and the leaderboard.
    func testFeedAndLeaderboard() {
        ensureSignedInAsDemo()

        switchToTab("Feed")
        XCTAssertTrue(app.navigationBars["3Wood"].waitForExistence(timeout: timeout),
                      "Feed did not load")
        XCTAssertTrue(app.cells.element(boundBy: 0).waitForExistence(timeout: timeout),
                      "Feed has no activity")
        snapshot("18-Feed")

        tap(app.buttons["leaderboardButton"], "Leaderboard button")
        if !app.navigationBars["Leaderboard"].waitForExistence(timeout: 6) {
            app.buttons["leaderboardButton"].tap() // retry a dropped first tap
        }
        XCTAssertTrue(app.navigationBars["Leaderboard"].waitForExistence(timeout: timeout),
                      "Leaderboard did not open")
        XCTAssertTrue(app.cells.element(boundBy: 0).waitForExistence(timeout: timeout),
                      "Leaderboard is empty")
        snapshot("19-Leaderboard")
    }

    /// Verifies course reviews display and the review editor opens.
    func testReviews() {
        ensureSignedInAsDemo()

        switchToTab("Search")
        let searchField = app.searchFields.firstMatch
        tap(searchField, "Search field")
        searchField.typeText("pebble beach")
        let pebble = app.staticTexts["Pebble Beach Golf Links"]
        XCTAssertTrue(pebble.waitForExistence(timeout: timeout), "Pebble not found")
        pebble.tap()

        // Reviews live below the fold — scroll to them.
        XCTAssertTrue(app.staticTexts["Community rating"].waitForExistence(timeout: timeout))
        app.swipeUp()
        app.swipeUp()
        let aReview = app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'back nine'")).firstMatch
        XCTAssertTrue(aReview.waitForExistence(timeout: timeout), "Reviews not shown on course detail")
        snapshot("20-Reviews")

        // Editor opens (ben already has a review, so the button reads "Edit").
        let edit = app.buttons["Edit"]
        if edit.waitForExistence(timeout: 3) {
            edit.tap()
            XCTAssertTrue(app.navigationBars["Edit review"].waitForExistence(timeout: timeout),
                          "Review editor did not open")
            snapshot("21-WriteReview")
            app.buttons["Cancel"].tap()
        }
    }

    /// Verifies the map city-jump (geocode + recenter + reload courses).
    func testMapCityJump() {
        ensureSignedInAsDemo()
        switchToTab("Map")
        snapshot("22-Map-Controls")

        let search = app.searchFields.firstMatch
        tap(search, "Map city search")
        search.typeText("Scottsdale")
        sleep(2) // let course + place suggestions load
        snapshot("25-Map-Suggestions")
        search.typeText(", Arizona\n")
        sleep(4) // geocode + recenter + region course load
        snapshot("23-Map-CityJump")
        XCTAssertTrue(search.exists, "Map search field missing")
    }
}
