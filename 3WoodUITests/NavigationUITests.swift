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
        // Existing isn't the same as hittable: a freshly laid-out List row can
        // report a frame a moment before it accepts touches, which made the
        // feed's reaction button flaky. Wait for it rather than for luck.
        let deadline = Date().addingTimeInterval(5)
        while !element.isHittable, Date() < deadline {
            usleep(100_000)
        }
        element.tap()
    }

    /// Backspaces out whatever the field already holds, then types `text`.
    /// XCUITest has no first-class "select all" on a plain TextField, so this
    /// is the standard workaround: delete-key characters equal to the
    /// current value's length, typed as text.
    private func clearAndType(_ element: XCUIElement, _ text: String) {
        element.tap()
        if let current = element.value as? String, !current.isEmpty {
            element.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: current.count))
        }
        element.typeText(text)
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

        // Fresh simulators offer to save the password — dismiss so the
        // sheet doesn't photobomb screenshots or block taps.
        let notNow = app.buttons["Not Now"]
        if notNow.waitForExistence(timeout: 3) {
            notNow.tap()
        } else {
            let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
            if springboard.buttons["Not Now"].waitForExistence(timeout: 1) {
                springboard.buttons["Not Now"].tap()
            }
        }
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

        // --- Explore: browse the map first. Searching focuses the field and
        // raises the keyboard, which covers the tab bar, so do the map pass
        // before typing rather than trying to dismiss search afterwards.
        switchToTab("Explore")
        XCTAssertTrue(app.navigationBars["Explore"].waitForExistence(timeout: timeout))
        sleep(2) // let pins load
        snapshot("05-Map")

        // --- Explore: course search (the old Search tab, same screen now) ---
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

        // --- Profile ---
        switchToTab("Profile")
        XCTAssertTrue(app.buttons["Find friends"].waitForExistence(timeout: timeout),
                      "Profile screen did not appear")
        snapshot("06-Profile")

        // --- About (visited first so it doesn't depend on the friend detour) ---
        tap(app.buttons["About"], "About row")
        XCTAssertTrue(app.staticTexts["Course data"].waitForExistence(timeout: timeout))
        snapshot("09-About")
        goBack()
        XCTAssertTrue(app.buttons["Find friends"].waitForExistence(timeout: timeout),
                      "Profile screen did not appear")

        // --- Find friends → contacts matching entry ---
        tap(app.buttons["Find friends"], "Find friends row")
        tap(app.buttons["Find from contacts"], "Find from contacts row")
        XCTAssertTrue(app.navigationBars["From Contacts"].waitForExistence(timeout: timeout),
                      "Contacts matching screen did not open")
        snapshot("27-Contacts")
        goBack()

        // --- Find friends → a friend's profile ---
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

            // Regression: a course tapped from their list must open its
            // detail, and back must land on the profile again (the push used
            // to bounce straight back and desync the back button).
            let theirCourse = app.staticTexts["Pebble Beach Golf Links"]
            if theirCourse.waitForExistence(timeout: 6) {
                theirCourse.tap()
                XCTAssertTrue(app.staticTexts["Community rating"].waitForExistence(timeout: timeout),
                              "Course from their list did not open its detail")
                snapshot("26-OtherProfile-Course")
                goBack()
                XCTAssertTrue(app.staticTexts["Their courses"].waitForExistence(timeout: timeout),
                              "Back from the course did not return to the profile")
            }
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

        // The + is a menu now: played vs want-to-play.
        tap(app.navigationBars.buttons["Add a course"], "Add (+) menu")
        tap(app.buttons["Log a played course"], "Log a played course menu item")

        let picker = app.searchFields.firstMatch
        tap(picker, "Course picker search")
        picker.typeText("spyglass")
        let target = app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'Spyglass'")).firstMatch
        XCTAssertTrue(target.waitForExistence(timeout: timeout), "Course picker returned no Spyglass")
        snapshot("10-Log-Picker")
        target.tap()

        // Companions first — a fact about the round, before the judgement.
        let solo = app.buttons["I played solo"]
        XCTAssertTrue(solo.waitForExistence(timeout: timeout),
                      "Companion picker did not appear after choosing a course")
        snapshot("35-Log-Companions")
        solo.tap()

        // Then the bucket.
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
        XCTAssertTrue(app.buttons["Add photos"].exists,
                      "Result screen is missing the add-photos shortcut")
        snapshot("13-Log-Result")

        // Regression: the result screen used to stack three .sheet modifiers,
        // and Add photos did nothing on device.
        tap(app.buttons["Add photos"], "Add photos")
        XCTAssertTrue(app.navigationBars["Photos"].waitForExistence(timeout: timeout),
                      "Add photos did not open the photo sheet")
        snapshot("39-Result-Photos")
        // Scope to the sheet's own bar: the result screen behind it also has
        // a "Done", and firstMatch picks that one.
        tap(app.navigationBars["Photos"].buttons["Done"], "Close photo sheet")

        // And the review sheet, which shared the same defect.
        tap(app.buttons["Write a review"], "Write a review")
        XCTAssertTrue(app.navigationBars["Review"].waitForExistence(timeout: 6)
                      || app.textViews.firstMatch.waitForExistence(timeout: 6),
                      "Write a review did not open its sheet")
        snapshot("40-Result-Review")
        tap(app.buttons["Cancel"].firstMatch, "Close review sheet")
        XCTAssertTrue(app.buttons["Add photos"].waitForExistence(timeout: timeout),
                      "Did not return to the result screen")
        done.tap()

        // Back on the tab bar.
        XCTAssertTrue(app.tabBars.buttons["Lists"].waitForExistence(timeout: timeout),
                      "Did not return to the app after logging")
    }

    /// Two `.sheet` modifiers on one view is a known SwiftUI hazard — only one
    /// may be honoured. Profile stacks them for phone and username, so both
    /// paths are exercised here.
    func testProfileSheetsBothOpen() {
        ensureSignedInAsDemo()
        switchToTab("Profile")

        snapshot("38-Profile-BeforeTap")
        // The row is a plain-styled Button inside a List; its label is the
        // reliable hit target.
        tap(app.staticTexts["Change username"], "Change username row")
        XCTAssertTrue(app.navigationBars["Change username"].waitForExistence(timeout: timeout),
                      "Username sheet did not open")
        tap(app.buttons["Cancel"], "Cancel username sheet")

        tap(app.staticTexts["Phone number"], "Phone number row")
        XCTAssertTrue(app.navigationBars["Link phone number"].waitForExistence(timeout: timeout),
                      "Phone sheet did not open — stacked .sheet modifiers")
        tap(app.buttons["Cancel"], "Cancel phone sheet")
    }

    /// Rounds: a played course shows when it was played, and can take another
    /// check-in without being re-ranked.
    func testCourseCheckIn() {
        ensureSignedInAsDemo()
        switchToTab("Lists")

        let firstRow = app.cells.element(boundBy: 0)
        XCTAssertTrue(firstRow.waitForExistence(timeout: timeout), "Played list has no rows")
        firstRow.tap()
        XCTAssertTrue(app.staticTexts["Community rating"].waitForExistence(timeout: timeout),
                      "Course detail did not open")

        // Rounds section lives below the fold.
        app.swipeUp()
        let checkIn = app.buttons["Check in again"]
        XCTAssertTrue(checkIn.waitForExistence(timeout: timeout),
                      "Played course has no check-in affordance")
        snapshot("36-Course-Rounds")
        tap(checkIn, "Check in again")

        XCTAssertTrue(app.navigationBars["Another round"].waitForExistence(timeout: timeout),
                      "Check-in sheet did not open")
        snapshot("37-CheckIn-Sheet")
        tap(app.buttons["Save"], "Save round")

        // Back on the course page with the round recorded.
        XCTAssertTrue(app.buttons["Check in again"].waitForExistence(timeout: timeout),
                      "Did not return to the course page after checking in")
    }

    /// The other half of the "+" menu: saving a course to Want to Play
    /// without opening it first.
    func testAddToWantToPlayFromList() {
        ensureSignedInAsDemo()
        switchToTab("Lists")

        tap(app.navigationBars.buttons["Add a course"], "Add (+) menu")
        tap(app.buttons["Add to Want to Play"], "Add to Want to Play menu item")

        XCTAssertTrue(app.navigationBars["Want to Play"].waitForExistence(timeout: timeout),
                      "Want to Play picker did not open")
        let picker = app.searchFields.firstMatch
        tap(picker, "Course picker search")
        picker.typeText("erin hills")
        let target = app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'Erin Hills'")).firstMatch
        XCTAssertTrue(target.waitForExistence(timeout: timeout), "Picker returned no Erin Hills")
        snapshot("28-WantToPlay-Picker")
        target.tap()

        // Saving lands the user on the Want to Play segment so the add is visible.
        XCTAssertTrue(app.navigationBars["My Courses"].waitForExistence(timeout: timeout),
                      "Did not return to the list after saving")
        XCTAssertTrue(app.cells.element(boundBy: 0).waitForExistence(timeout: timeout),
                      "Want to Play list is empty after saving")
        snapshot("29-WantToPlay-AfterAdd")
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

        // Re-tapping the active tab pops its stack back to the root.
        app.tabBars.buttons["Profile"].tap()
        XCTAssertTrue(app.buttons["Find friends"].waitForExistence(timeout: timeout),
                      "Re-tapping the Profile tab did not pop to the root")

        // Map → list toggle + filter.
        switchToTab("Explore")
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

    /// Reactions, the comment thread, and the alert feed.
    func testReactionsCommentsAndAlerts() {
        ensureSignedInAsDemo()
        switchToTab("Feed")
        XCTAssertTrue(app.cells.element(boundBy: 0).waitForExistence(timeout: timeout),
                      "Feed has no activity")

        // React from the feed without leaving it. Slack-style: the add button
        // opens the palette, and each emoji becomes its own counted chip.
        snapshot("30-Feed-BeforeReact")
        tap(app.buttons["Add a reaction"].firstMatch, "Add-reaction button")
        tap(app.buttons.matching(NSPredicate(format: "label CONTAINS 'On fire'")).firstMatch,
            "🔥 reaction")
        let fireChip = app.buttons.matching(
            NSPredicate(format: "label BEGINSWITH 'On fire'")
        ).firstMatch
        XCTAssertTrue(fireChip.waitForExistence(timeout: timeout),
                      "Reacting did not produce a counted chip")
        snapshot("30-Feed-Reactions")

        // Holding two reactions at once is the whole point of the Slack model.
        tap(app.buttons["Add a reaction"].firstMatch, "Add-reaction button again")
        tap(app.buttons.matching(NSPredicate(format: "label CONTAINS 'Well played'")).firstMatch,
            "👏 reaction")
        XCTAssertTrue(
            app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Well played'"))
                .firstMatch.waitForExistence(timeout: timeout),
            "Second reaction replaced the first instead of stacking")
        XCTAssertTrue(fireChip.exists, "First reaction disappeared when a second was added")
        snapshot("34-Feed-TwoReactions")

        // Reactions toggle, so leaving them behind would make the next run of
        // this test remove them instead of adding — it would then fail looking
        // for a chip it just deleted. Put the row back as we found it.
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Well played'"))
            .firstMatch.tap()
        fireChip.tap()

        // Comments live on the activity screen.
        tap(app.buttons.matching(NSPredicate(format: "label CONTAINS 'comment' OR label == 'Comment'"))
                .firstMatch, "Comment button")
        XCTAssertTrue(app.navigationBars["Activity"].waitForExistence(timeout: timeout),
                      "Activity detail did not open")
        let composer = app.textFields["Add a comment"]
        tap(composer, "Comment composer")
        composer.typeText("Great round")
        tap(app.buttons["Send comment"], "Send comment")
        XCTAssertTrue(app.staticTexts["Great round"].waitForExistence(timeout: timeout),
                      "Posted comment did not appear in the thread")
        snapshot("31-Activity-Comments")
        goBack()

        // Alert feed: Ben's fixtures give him followers, reactions and comments.
        tap(app.buttons["alertsButton"], "Alerts button")
        if !app.navigationBars["Alerts"].waitForExistence(timeout: 6) {
            app.buttons["alertsButton"].tap()
        }
        XCTAssertTrue(app.navigationBars["Alerts"].waitForExistence(timeout: timeout),
                      "Alerts did not open")
        XCTAssertTrue(app.cells.element(boundBy: 0).waitForExistence(timeout: timeout),
                      "Alert feed is empty")
        snapshot("32-Alerts")

        // Tapping an engagement alert deep-links to the activity it happened
        // on — covers the single-activity RPC, its loader and the router case,
        // none of which the feed's own push exercises.
        let engagement = app.cells.containing(
            NSPredicate(format: "label CONTAINS 'reacted' OR label CONTAINS 'commented'")
        ).firstMatch
        if engagement.waitForExistence(timeout: 5) {
            engagement.tap()
            XCTAssertTrue(app.navigationBars["Activity"].waitForExistence(timeout: timeout),
                          "Alert did not open the activity it points at")
            snapshot("33-Alert-Activity")
        }
    }

    /// Verifies course reviews display and the review editor opens.
    func testReviews() {
        ensureSignedInAsDemo()

        switchToTab("Explore")
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
        switchToTab("Explore")
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

    /// Custom lists end to end: create, add a course via a state filter,
    /// rename, toggle to public, then delete.
    func testCustomListLifecycle() {
        ensureSignedInAsDemo()
        switchToTab("Lists")
        tap(app.buttons["My Lists"], "My Lists segment")

        tap(app.buttons["newListButton"], "New list button")
        XCTAssertTrue(app.navigationBars["New List"].waitForExistence(timeout: timeout),
                      "New list sheet did not open")

        let titleField = app.textFields["listTitleField"]
        tap(titleField, "List title field")
        titleField.typeText("UI Test List")
        snapshot("40-NewList-Form")
        tap(app.buttons["saveListButton"], "Save new list")

        XCTAssertTrue(app.staticTexts["UI Test List"].waitForExistence(timeout: timeout),
                      "New list row not visible after saving")
        snapshot("41-MyLists-AfterCreate")
        tap(app.staticTexts["UI Test List"], "New list row")

        XCTAssertTrue(app.navigationBars["UI Test List"].waitForExistence(timeout: timeout),
                      "List detail did not open")

        // Add a course, filtered to a state the demo account (birdie_ben) has
        // ranked courses in — Pebble Beach, CA, from the seeded fixtures.
        tap(app.buttons["listManageMenu"], "List manage menu")
        tap(app.buttons["addCoursesButton"], "Add or remove courses")
        XCTAssertTrue(app.navigationBars["Add Courses"].waitForExistence(timeout: timeout),
                      "Add-courses sheet did not open")

        tap(app.buttons["listFilterMenu"], "State filter menu")
        tap(app.buttons["CA"], "CA filter option")
        snapshot("42-AddCourses-Filtered")

        let firstCourse = app.cells.element(boundBy: 0)
        XCTAssertTrue(firstCourse.waitForExistence(timeout: timeout), "No courses matched the CA filter")
        firstCourse.tap()
        tap(app.navigationBars.buttons["Save"], "Save added courses")

        // Rows aren't in a List (they live alongside the header/comments in
        // one scroll view), so assert via the per-row remove button rather
        // than app.cells. That button only renders when live.isMine == true,
        // so this also doubles as a check that the manage-menu path (and the
        // asMine() patch on the My Lists row) resolved ownership correctly —
        // a failure here could mean either "no courses" or "isMine came back
        // false," not just an empty list.
        let removeButton = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Remove'")).firstMatch
        XCTAssertTrue(removeButton.waitForExistence(timeout: timeout),
                      "List detail shows no courses after adding")
        snapshot("43-ListDetail-WithCourse")

        // Rename via the manage menu.
        tap(app.buttons["listManageMenu"], "List manage menu")
        tap(app.buttons["Edit list"], "Edit list")
        XCTAssertTrue(app.navigationBars["Edit List"].waitForExistence(timeout: timeout),
                      "Edit list sheet did not open")

        let editTitleField = app.textFields["listTitleField"]
        clearAndType(editTitleField, "Renamed UI Test List")

        // Toggle to public while the sheet is open. Segmented style, so
        // "Public" is tappable directly — no push-to-detail row to open first.
        tap(app.buttons["Public"], "Public option")

        tap(app.buttons["saveListButton"], "Save edited list")

        XCTAssertTrue(app.navigationBars["Renamed UI Test List"].waitForExistence(timeout: timeout),
                      "Rename did not take effect")
        snapshot("44-ListDetail-Renamed")

        // Delete.
        tap(app.buttons["listManageMenu"], "List manage menu")
        tap(app.buttons["deleteListButton"], "Delete list menu item")
        tap(app.buttons["Delete list"], "Confirm delete")

        XCTAssertTrue(app.navigationBars["My Courses"].waitForExistence(timeout: timeout),
                      "Did not return to the list after deleting")
        XCTAssertFalse(app.staticTexts["Renamed UI Test List"].exists,
                       "Deleted list still visible")
        snapshot("45-MyLists-AfterDelete")
    }

    /// Bookmark (replaces Like on lists), comment reactions, one-level
    /// replies, and the Saved segment — the 2026-08-21 addition on top of
    /// Custom Lists. Bookmarking your own list is unusual in practice but
    /// exercises the same toggle/decode path as bookmarking someone else's.
    func testListBookmarkCommentReactionAndReply() {
        ensureSignedInAsDemo()
        switchToTab("Lists")
        tap(app.buttons["My Lists"], "My Lists segment")

        tap(app.buttons["newListButton"], "New list")
        clearAndType(app.textFields["listTitleField"], "Bookmark UI Test List")
        app.buttons["Public"].tap()
        tap(app.buttons["saveListButton"], "Save")

        _ = app.staticTexts["Bookmark UI Test List"].waitForExistence(timeout: timeout)
        tap(app.staticTexts["Bookmark UI Test List"], "Bookmark UI Test List row")
        XCTAssertTrue(app.navigationBars["Bookmark UI Test List"].waitForExistence(timeout: timeout))

        tap(app.buttons["listBookmarkButton"], "Bookmark button")
        XCTAssertTrue(app.buttons["listBookmarkButton"].label == "1",
                      "Bookmark count did not move to 1")
        snapshot("50-ListDetail-Bookmarked")

        let field = app.textFields["Add a comment"]
        tap(field, "Comment field")
        field.typeText("Top-level UI test comment")
        app.buttons["Send comment"].tap()
        XCTAssertTrue(app.staticTexts["Top-level UI test comment"].waitForExistence(timeout: timeout),
                      "Top-level comment did not appear")

        tap(app.buttons["Add a reaction"], "Add reaction menu")
        app.buttons["⛳  Nice track"].tap()
        XCTAssertTrue(app.buttons["Nice track, 1"].waitForExistence(timeout: timeout),
                      "Reaction chip did not appear on the comment")
        snapshot("51-ListDetail-CommentReaction")

        tap(app.buttons["Comment actions"], "Comment actions menu")
        app.buttons["Reply"].tap()
        XCTAssertTrue(
            app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'Replying to'")).firstMatch
                .waitForExistence(timeout: timeout),
            "Replying-to banner did not appear"
        )
        field.typeText("A reply")
        app.buttons["Send comment"].tap()
        XCTAssertTrue(app.staticTexts["A reply"].waitForExistence(timeout: timeout),
                      "Reply did not appear in the thread")
        snapshot("52-ListDetail-CommentReply")

        tap(app.buttons["BackButton"], "Back to My Courses")
        tap(app.buttons["Saved"], "Saved segment")
        XCTAssertTrue(app.staticTexts["Bookmark UI Test List"].waitForExistence(timeout: timeout),
                      "Bookmarked list did not appear in Saved")
        snapshot("53-Saved-Segment")

        // Cleanup: unbookmark, then delete the list from My Lists. Swipe the
        // row by its own text, not app.cells.firstMatch — My Lists' list
        // has an "Explore public lists" banner row ahead of the list rows,
        // which app.cells.firstMatch would hit instead.
        app.staticTexts["Bookmark UI Test List"].swipeLeft()
        app.buttons["Remove"].tap()
        XCTAssertFalse(app.staticTexts["Bookmark UI Test List"].waitForExistence(timeout: 3),
                       "List still visible in Saved after unbookmarking")

        tap(app.buttons["My Lists"], "My Lists segment")
        _ = app.staticTexts["Bookmark UI Test List"].waitForExistence(timeout: timeout)
        app.staticTexts["Bookmark UI Test List"].swipeLeft()
        app.buttons["Delete"].tap()
        tap(app.buttons["Delete list"], "Confirm delete list")
    }
}
