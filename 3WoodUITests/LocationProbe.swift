import XCTest

/// Reproduces the "Allow Once and the map never pans" report.
///
/// Needs the simulator's location permission reset and a simulated fix in
/// place, which only the shell can do — see scripts/probe-location.sh.
final class LocationProbe: XCTestCase {
    let app = XCUIApplication()

    func testAllowOnceCentersTheMap() throws {
        try XCTSkipUnless(
            ProcessInfo.processInfo.environment["LOCATION_PROBE"] == "1",
            "Driven by scripts/probe-location.sh — it resets the permission first."
        )
        continueAfterFailure = true
        app.launch()

        // Sign in.
        if !app.tabBars.buttons["Profile"].waitForExistence(timeout: 5) {
            XCTAssertTrue(app.buttons["Sign in"].waitForExistence(timeout: 20), "No Welcome")
            app.buttons["Sign in"].tap()
            let email = app.textFields.firstMatch
            XCTAssertTrue(email.waitForExistence(timeout: 20), "No email field")
            email.tap()
            email.typeText("birdie_ben@example.com")
            let password = app.secureTextFields.firstMatch
            password.tap()
            password.typeText("testpass123")
            app.buttons["Sign in"].tap()
            XCTAssertTrue(app.tabBars.buttons["Lists"].waitForExistence(timeout: 30), "Sign-in failed")
            let notNow = app.buttons["Not Now"]
            if notNow.waitForExistence(timeout: 3) { notNow.tap() }
        }

        // Explore tab — this is where the permission is asked for.
        let explore = app.tabBars.buttons["Explore"]
        XCTAssertTrue(explore.waitForExistence(timeout: 20), "No Explore tab")
        for _ in 0..<3 where !explore.isSelected {
            explore.tap()
            _ = explore.waitForExistence(timeout: 1)
        }

        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let allowOnce = springboard.buttons["Allow Once"]
        XCTAssertTrue(allowOnce.waitForExistence(timeout: 30), "No location permission prompt")

        let before = XCUIScreen.main.screenshot()
        let b = XCTAttachment(screenshot: before)
        b.name = "50-Map-BeforeGrant"
        b.lifetime = .keepAlways
        add(b)

        allowOnce.tap()

        // Generous: a fix plus the region fetch. If the map is going to pan at
        // all, it has happened well inside this.
        Thread.sleep(forTimeInterval: 12)

        let after = XCUIScreen.main.screenshot()
        let a = XCTAttachment(screenshot: after)
        a.name = "51-Map-AfterAllowOnce"
        a.lifetime = .keepAlways
        add(a)
    }
}
