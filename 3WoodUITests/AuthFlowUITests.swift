import XCTest

/// Sign-in, sign-out, and password-reset entry points.
///
/// These live apart from NavigationUITests because they are the only tests that
/// care about the *signed-out* half of the app. Everything there starts by
/// getting past the auth gate as fast as possible; here the gate is the subject.
final class AuthFlowUITests: XCTestCase {
    let app = XCUIApplication()
    let timeout: TimeInterval = 15

    override func setUp() {
        continueAfterFailure = true
        app.launch()
    }

    // MARK: - Helpers

    private func snapshot(_ name: String) {
        let shot = XCUIScreen.main.screenshot()
        let attachment = XCTAttachment(screenshot: shot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func tap(_ element: XCUIElement, _ label: String) {
        XCTAssertTrue(element.waitForExistence(timeout: timeout), "Missing element: \(label)")
        let deadline = Date().addingTimeInterval(5)
        while !element.isHittable, Date() < deadline {
            usleep(100_000)
        }
        element.tap()
    }

    /// Switch tabs reliably. The first tab switch after a sign-in is routinely
    /// dropped — the tab bar is still settling — so tap until it reports
    /// selected rather than trusting one tap.
    private func switchToTab(_ name: String) {
        let tab = app.tabBars.buttons[name]
        XCTAssertTrue(tab.waitForExistence(timeout: timeout), "Missing tab: \(name)")
        for _ in 0..<3 where !tab.isSelected {
            tab.tap()
            _ = tab.waitForExistence(timeout: 1)
        }
        XCTAssertTrue(tab.isSelected, "Could not switch to \(name) tab")
    }

    /// Fresh simulators offer to save the password after a sign-in; it steals
    /// taps from whatever is underneath it.
    private func dismissSavePasswordPrompt() {
        let notNow = app.buttons["Not Now"]
        if notNow.waitForExistence(timeout: 3) {
            notNow.tap()
            return
        }
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        if springboard.buttons["Not Now"].waitForExistence(timeout: 1) {
            springboard.buttons["Not Now"].tap()
        }
    }

    /// Get to the Welcome screen from wherever the app happens to be.
    private func ensureSignedOut() {
        if app.tabBars.buttons["Profile"].waitForExistence(timeout: 5) {
            app.tabBars.buttons["Profile"].tap()
            let signOut = app.buttons["Sign out"]
            if signOut.waitForExistence(timeout: 5) { signOut.tap() }
        }
        XCTAssertTrue(app.buttons["Sign in"].waitForExistence(timeout: timeout),
                      "Did not reach the Welcome screen")
    }

    /// Fill the sign-in form and submit. Does not assert the outcome — callers
    /// test both the success and the failure paths.
    private func submitSignIn(email address: String, password secret: String) {
        tap(app.buttons["Sign in"], "Sign in button on Welcome")

        let email = app.textFields.firstMatch
        tap(email, "Email field")
        email.typeText(address)

        let password = app.secureTextFields.firstMatch
        tap(password, "Password field")
        password.typeText(secret)

        tap(app.buttons["Sign in"], "Sign in submit")
    }

    // MARK: - Sign in

    /// A wrong password must say so and leave the form up — not fall through to
    /// the app, and not clear the screen with no explanation.
    func testSignInRejectsWrongPassword() {
        ensureSignedOut()
        submitSignIn(email: "birdie_ben@example.com", password: "definitelywrong")

        let error = app.staticTexts["Invalid login credentials"]
        XCTAssertTrue(error.waitForExistence(timeout: timeout),
                      "No error shown for a wrong password")
        XCTAssertFalse(app.tabBars.buttons["Lists"].exists,
                       "A wrong password still reached the main app")
        snapshot("30-SignIn-WrongPassword")
    }

    /// Regression: the form used to hand GoTrue whatever was typed, so a
    /// trailing space — exactly what a paste or an autofill leaves behind —
    /// came back as "Invalid login credentials" with nothing on screen to
    /// explain it. The address is normalised before it is sent now.
    func testSignInAcceptsEmailWithSurroundingWhitespace() {
        ensureSignedOut()
        submitSignIn(email: "birdie_ben@example.com ", password: "testpass123")

        XCTAssertTrue(app.tabBars.buttons["Lists"].waitForExistence(timeout: timeout),
                      "A trailing space in the email blocked sign-in")
        dismissSavePasswordPrompt()
        snapshot("31-SignIn-WhitespaceEmail")
    }

    // MARK: - Password reset entry point

    /// "Forgot password?" with an empty field has to explain itself rather than
    /// silently doing nothing.
    func testForgotPasswordWithoutAnEmailExplainsItself() {
        ensureSignedOut()
        tap(app.buttons["Sign in"], "Sign in button on Welcome")
        tap(app.buttons["Forgot password?"], "Forgot password")

        let alert = app.alerts["Password reset"]
        XCTAssertTrue(alert.waitForExistence(timeout: timeout),
                      "Forgot password with no email gave no feedback")
        XCTAssertTrue(alert.staticTexts.element(matching: NSPredicate(
            format: "label CONTAINS[c] 'Enter your email'")).exists,
                      "Alert did not ask for an email address")
        snapshot("32-ForgotPassword-NoEmail")
        alert.buttons["OK"].tap()
    }

    /// The happy path as far as the UI can see it: a real address gets the
    /// "check your email" confirmation. Delivery itself is covered outside
    /// XCUITest, against the local mail catcher.
    func testForgotPasswordConfirmsTheEmailWasSent() {
        ensureSignedOut()
        tap(app.buttons["Sign in"], "Sign in button on Welcome")

        let email = app.textFields.firstMatch
        tap(email, "Email field")
        email.typeText("chip_charlie@example.com")

        tap(app.buttons["Forgot password?"], "Forgot password")

        let alert = app.alerts["Password reset"]
        XCTAssertTrue(alert.waitForExistence(timeout: timeout),
                      "No confirmation after requesting a reset")
        XCTAssertTrue(alert.staticTexts.element(matching: NSPredicate(
            format: "label CONTAINS[c] 'chip_charlie@example.com'")).exists,
                      "Confirmation did not name the address it sent to")
        snapshot("33-ForgotPassword-Sent")
        alert.buttons["OK"].tap()
    }

    // MARK: - Sign out

    func testSignOutReturnsToWelcome() {
        ensureSignedOut()
        submitSignIn(email: "birdie_ben@example.com", password: "testpass123")
        XCTAssertTrue(app.tabBars.buttons["Lists"].waitForExistence(timeout: timeout),
                      "Sign-in did not reach the main app")
        dismissSavePasswordPrompt()

        switchToTab("Profile")
        tap(app.buttons["Sign out"], "Sign out")

        XCTAssertTrue(app.buttons["Create account"].waitForExistence(timeout: timeout),
                      "Sign out did not land on the Welcome screen")
        XCTAssertFalse(app.tabBars.buttons["Lists"].exists,
                       "Tab bar survived sign-out")
        snapshot("34-SignOut-Welcome")
    }

    /// Regression: AppNavigation is @State on ThreeWoodApp, so it outlives the
    /// session — only MainTabView is torn down. The next account used to
    /// inherit the previous one's tab selection and per-tab stacks, landing on
    /// a screen that belonged to somebody else's session.
    func testSignOutClearsNavigationForTheNextAccount() {
        ensureSignedOut()
        submitSignIn(email: "birdie_ben@example.com", password: "testpass123")
        XCTAssertTrue(app.tabBars.buttons["Lists"].waitForExistence(timeout: timeout),
                      "Sign-in did not reach the main app")
        dismissSavePasswordPrompt()

        // Push a screen onto the Feed tab's stack, so there is state to leak.
        tap(app.buttons["leaderboardButton"], "Leaderboard button")
        if !app.navigationBars["Leaderboard"].waitForExistence(timeout: 6) {
            app.buttons["leaderboardButton"].tap() // a dropped first tap
        }
        XCTAssertTrue(app.navigationBars["Leaderboard"].waitForExistence(timeout: timeout),
                      "Could not push the Leaderboard")

        // Sign out from the Profile tab: that also leaves the selected tab
        // somewhere other than the default.
        switchToTab("Profile")
        tap(app.buttons["Sign out"], "Sign out")
        XCTAssertTrue(app.buttons["Sign in"].waitForExistence(timeout: timeout),
                      "Sign out did not land on the Welcome screen")

        // A different account signs in.
        submitSignIn(email: "mulligan_mike@example.com", password: "testpass123")
        XCTAssertTrue(app.tabBars.buttons["Lists"].waitForExistence(timeout: timeout),
                      "Second sign-in did not reach the main app")
        dismissSavePasswordPrompt()

        XCTAssertFalse(app.navigationBars["Leaderboard"].exists,
                       "The previous account's pushed screen survived sign-out")
        XCTAssertTrue(app.tabBars.buttons["Feed"].isSelected,
                      "Did not return to the default tab for the new account")
        snapshot("35-SignOut-ClearsNavigation")
    }
}
