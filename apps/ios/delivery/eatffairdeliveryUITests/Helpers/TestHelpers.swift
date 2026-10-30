//
//  TestHelpers.swift
//  eatffairdeliveryUITests
//
//  Shared test helpers for Dollor.ai Driver iOS App UI Tests.
//  Provides base test case, login helpers, navigation, and assertion utilities.
//

import XCTest

/// Base test case for all Dollor.ai Driver UI tests.
/// Handles app launch, teardown, and common navigation patterns.
class DollorTestCase: XCTestCase {

    var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launch()

        // Dismiss the system notification permission alert that pops on first
        // launch and blocks the login form. Phase 68 insurance capture needs
        // a clean path past this on fresh simulators.
        let alert = app.alerts.firstMatch
        if alert.waitForExistence(timeout: 4) {
            let dontAllow = alert.buttons["Don't Allow"]
            if dontAllow.exists {
                dontAllow.tap()
            } else {
                alert.buttons.firstMatch.tap()
            }
        }
    }

    override func tearDownWithError() throws {
        app = nil
    }

    // MARK: - Demo Credentials

    private static let demoEmail = "demo.driver@dollor.ai"
    private static let demoPassword = ProcessInfo.processInfo.environment["DEMO_LOGIN_PASSWORD"] ?? ""

    // MARK: - Navigation Helpers

    /// Navigates to the login screen. If already logged in, logs out first via Profile > Settings > Logout.
    func navigateToLogin() {
        // Check if we're already logged in (tab bar present = authenticated)
        let tabBar = app.tabBars.firstMatch
        if tabBar.waitForExistence(timeout: 3) {
            // Dismiss Terms sheet if it's blocking
            dismissTermsSheetIfPresent()

            // Logged in -- navigate to Profile tab and log out
            let profileTab = app.tabBars.buttons["Profile"]
            if profileTab.exists {
                profileTab.tap()
                // Tap Settings sub-tab within Profile (accessibilityLabel is "Settings tab")
                let settingsTab = app.buttons["Settings tab"]
                if settingsTab.waitForExistence(timeout: 3) {
                    settingsTab.tap()
                }
                // Scroll down to find Logout button
                for _ in 0..<5 {
                    app.swipeUp()
                    Thread.sleep(forTimeInterval: 0.3)
                }
                let logoutButton = app.buttons.containing(NSPredicate(format: "label CONTAINS[c] 'Logout' OR label CONTAINS[c] 'Log Out' OR label CONTAINS[c] 'Sign Out'")).firstMatch
                if logoutButton.waitForExistence(timeout: 5) {
                    logoutButton.tap()
                    // Handle confirmation alert
                    let confirmButton = app.alerts.buttons["Logout"]
                    if confirmButton.waitForExistence(timeout: 3) {
                        confirmButton.tap()
                    }
                }
            }
        }
        // Wait for login screen
        _ = app.staticTexts["Driver Login"].waitForExistence(timeout: 5)
    }

    /// Enters email and password credentials and taps the Login button.
    func loginWithCredentials(email: String, password: String) {
        navigateToLogin()

        let emailField = app.textFields["Email"]
        if emailField.waitForExistence(timeout: 5) {
            emailField.tap()
            emailField.typeText(email)
        }

        let passwordField = app.secureTextFields["Password"]
        if passwordField.waitForExistence(timeout: 3) {
            passwordField.tap()
            passwordField.typeText(password)
        }

        let loginButton = app.buttons["Login"]
        if loginButton.waitForExistence(timeout: 3) {
            loginButton.tap()
        }
    }

    /// Waits for an element to exist within the given timeout.
    /// - Returns: `true` if the element appeared before timeout.
    @discardableResult
    func waitForElement(_ element: XCUIElement, timeout: TimeInterval = 10) -> Bool {
        return element.waitForExistence(timeout: timeout)
    }

    /// Asserts that an element exists, with a descriptive message.
    func assertElementExists(_ element: XCUIElement, _ message: String) {
        XCTAssertTrue(element.waitForExistence(timeout: 10), message)
    }

    /// Ensures the app is in a logged-in state using demo credentials.
    /// If already logged in (no login screen visible), does nothing.
    /// If on login screen, logs in with demo driver credentials.
    /// After login, dismisses Terms & Conditions sheet if it appears.
    /// If login fails, throws XCTSkip.
    func ensureLoggedIn() throws {
        // Check if already on login screen
        let loginButton = app.buttons["Login"]
        let driverLoginText = app.staticTexts["Driver Login"]
        let onLoginScreen = loginButton.waitForExistence(timeout: 3) || driverLoginText.waitForExistence(timeout: 1)

        if !onLoginScreen {
            // Already logged in -- but check if Terms sheet is blocking
            dismissTermsSheetIfPresent()
            return
        }

        // On login screen -- attempt login with demo credentials
        loginWithCredentials(email: Self.demoEmail, password: Self.demoPassword)

        // Verify login succeeded -- login screen elements should disappear
        // Wait a moment for navigation, then check login screen is gone
        let tabBar = app.tabBars.firstMatch
        let stillOnLogin = driverLoginText.waitForExistence(timeout: 15)
        if stillOnLogin && !tabBar.exists {
            throw XCTSkip("Demo login failed -- staging may be unreachable (demo.driver@dollor.ai)")
        }

        // After login, the DriverDashboardView may show Terms & Conditions sheet
        dismissTermsSheetIfPresent()
    }

    /// Dismisses the Terms & Conditions sheet if it appears after login.
    /// The sheet shows when driverTermsAccepted is not set in UserDefaults.
    private func dismissTermsSheetIfPresent() {
        // Check if Terms sheet is showing (it appears ~0.5s after dashboard loads)
        let termsTitle = app.staticTexts["Driver Terms & Conditions"]
        if termsTitle.waitForExistence(timeout: 2) {
            // Toggle "I accept the Terms & Conditions"
            let acceptToggle = app.switches.firstMatch
            if acceptToggle.waitForExistence(timeout: 3) {
                acceptToggle.tap()
            }
            // Tap "Accept & Continue"
            let acceptButton = app.buttons["Accept & Continue"]
            if acceptButton.waitForExistence(timeout: 3) {
                acceptButton.tap()
            } else {
                // Fallback: dismiss via Cancel button in toolbar
                let cancelButton = app.buttons["Cancel"]
                if cancelButton.waitForExistence(timeout: 2) {
                    cancelButton.tap()
                }
            }
            // Wait for sheet to dismiss
            _ = app.tabBars.firstMatch.waitForExistence(timeout: 3)
        }
    }

    /// Throws `XCTSkip` if the login screen is still visible (user not logged in).
    func skipIfNotLoggedIn() throws {
        let loginButton = app.buttons["Login"]
        let driverLoginText = app.staticTexts["Driver Login"]
        if loginButton.waitForExistence(timeout: 2) || driverLoginText.waitForExistence(timeout: 1) {
            throw XCTSkip("Test requires logged-in state")
        }
    }

    /// Taps a tab bar button by name.
    func navigateToTab(_ tabName: String) {
        let tab = app.tabBars.buttons[tabName]
        if tab.waitForExistence(timeout: 5) {
            tab.tap()
        }
    }

    /// Captures the current screen as an XCTAttachment that survives in the
    /// .xcresult bundle. Used by Phase 68 to assemble the insurance evidence
    /// PDF — each named screenshot becomes a captioned page.
    func screenshot(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = "driver__\(name)"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
