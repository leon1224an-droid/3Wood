import XCTest

/// The half of the password-reset flow no self-contained UI test can reach.
///
/// XCUITest cannot open a URL scheme, and the PKCE code verifier lives in the
/// app's own keychain — so the reset must be requested by the app and the link
/// delivered from outside it. `scripts/verify-reset-deeplink.sh` runs these,
/// watches the local mail catcher, and fires `simctl openurl` for each one.
///
/// Skipped unless that script is driving, so a plain `xcodebuild test` does not
/// sit here waiting for a link that will never arrive.
///
/// Every method uses chip_charlie, whose password the driver script resets to
/// the seed value afterwards — one of these deliberately changes it.
final class ResetDeepLinkProbe: XCTestCase {
    let app = XCUIApplication()
    let account = "chip_charlie@example.com"

    private func requireDriver() throws {
        try XCTSkipUnless(
            ProcessInfo.processInfo.environment["RESET_DEEPLINK_PROBE"] == "1",
            "Driven by scripts/verify-reset-deeplink.sh — it delivers the URL from outside."
        )
    }

    private func snapshot(_ name: String) {
        let shot = XCUIScreen.main.screenshot()
        let attachment = XCTAttachment(screenshot: shot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    /// Launch, get to Welcome, ask for a reset, and wait for the deep link the
    /// driver script delivers. Returns with the new-password sheet on screen.
    private func reachResetSheet() {
        continueAfterFailure = true
        app.launch()

        if app.tabBars.buttons["Profile"].waitForExistence(timeout: 5) {
            app.tabBars.buttons["Profile"].tap()
            let signOut = app.buttons["Sign out"]
            if signOut.waitForExistence(timeout: 5) { signOut.tap() }
        }
        XCTAssertTrue(app.buttons["Sign in"].waitForExistence(timeout: 20), "No Welcome screen")
        app.buttons["Sign in"].tap()

        let email = app.textFields.firstMatch
        XCTAssertTrue(email.waitForExistence(timeout: 20), "No email field")
        email.tap()
        email.typeText(account)
        app.buttons["Forgot password?"].tap()

        let alert = app.alerts["Password reset"]
        XCTAssertTrue(alert.waitForExistence(timeout: 20), "No reset confirmation")
        alert.buttons["OK"].tap()

        // iOS asks before handing a custom scheme to an app the FIRST time
        // only — once confirmed on this simulator it never asks again. Take the
        // prompt if it appears, otherwise the URL already went straight through.
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let open = springboard.buttons["Open"]
        if open.waitForExistence(timeout: 45) {
            open.tap()
        }

        XCTAssertTrue(app.navigationBars["New password"].waitForExistence(timeout: 30),
                      "Recovery link did not raise UpdatePasswordView")
    }

    /// The link must land on the new-password screen rather than silently
    /// signing the user in behind it — which is exactly what shipped, because
    /// the flow waited on a .passwordRecovery event that PKCE never emits.
    func testDeepLinkRaisesTheResetSheet() throws {
        try requireDriver()
        reachResetSheet()
        snapshot("40-Reset-Sheet")
    }

    /// The success path. RootView signs the recovery session out when the sheet
    /// is dismissed without a password being set, so this checks the completion
    /// flag actually lands before onDismiss reads it — otherwise a *successful*
    /// reset would sign you straight back out.
    func testSettingANewPasswordKeepsYouSignedIn() throws {
        try requireDriver()
        reachResetSheet()

        let field = app.secureTextFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 10), "No new-password field")
        field.tap()
        field.typeText("probepass456")
        app.buttons["Set new password"].tap()

        XCTAssertTrue(app.tabBars.buttons["Lists"].waitForExistence(timeout: 30),
                      "Setting a new password did not leave the user signed in")
        XCTAssertFalse(app.navigationBars["New password"].exists,
                       "The reset sheet stayed up after a successful change")
        snapshot("41-Reset-Succeeded")
    }

    /// Cancelling must not leave someone signed in to an account they still
    /// have no password for. The recovery link establishes a real session
    /// before the sheet appears, and it is single-use, so there is no way back.
    func testCancellingTheResetSignsYouOut() throws {
        try requireDriver()
        reachResetSheet()

        app.buttons["Cancel"].tap()

        XCTAssertTrue(app.buttons["Create account"].waitForExistence(timeout: 30),
                      "Cancelling the reset left the session in place")
        XCTAssertFalse(app.tabBars.buttons["Lists"].exists,
                       "Cancelling the reset dropped the user into the app")
        snapshot("42-Reset-Cancelled")
    }
}
