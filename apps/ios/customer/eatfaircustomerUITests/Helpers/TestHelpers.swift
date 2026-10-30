//
//  TestHelpers.swift
//  eatfaircustomerUITests
//
//  Shared test helpers for Dollor.ai Customer iOS App UI Tests.
//  Provides base test case, login helpers, navigation, and assertion utilities.
//

import XCTest

/// Base test case for all Dollor.ai Customer UI tests.
/// Handles app launch, teardown, and common navigation patterns.
class DollorTestCase: XCTestCase {

    var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launch()

        // Dismiss the system notification permission alert that pops on first
        // launch and blocks the login form (Phase 68 insurance capture).
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

    private static let demoEmail = "demo.customer@dollor.ai"
    private static let demoPassword = ProcessInfo.processInfo.environment["DEMO_LOGIN_PASSWORD"] ?? ""

    // MARK: - Navigation Helpers

    /// Ensures the app is on the login screen.
    /// If already logged in (tab bar visible), logs out first via Profile > Log Out.
    /// The app goes directly to LoginView when not authenticated (no WelcomeView in flow).
    func navigateToLogin() {
        // Check if we're already logged in (tab bar present = authenticated)
        let tabBar = app.tabBars.firstMatch
        if tabBar.waitForExistence(timeout: 3) {
            // Logged in -- navigate to Profile tab and log out
            let profileTab = app.tabBars.buttons["Profile"]
            if profileTab.exists {
                profileTab.tap()
                // Scroll down to find Log Out button
                let scrollView = app.scrollViews.firstMatch
                if scrollView.waitForExistence(timeout: 3) {
                    scrollView.swipeUp()
                }
                let logOutButton = app.buttons.containing(NSPredicate(format: "label CONTAINS[c] 'Log Out'")).firstMatch
                if logOutButton.waitForExistence(timeout: 5) {
                    logOutButton.tap()
                }
            }
        }
        // Wait for login screen identifiers (MainAppView.swift:152)
        let welcomeBackText = app.staticTexts["Welcome back"]
        let dollorText = app.staticTexts["Dollor.ai"]
        _ = welcomeBackText.waitForExistence(timeout: 5) || dollorText.waitForExistence(timeout: 3)
    }

    /// Enters email and password credentials and taps the Continue button.
    func loginWithCredentials(email: String, password: String) {
        navigateToLogin()

        let emailField = app.textFields["Email address"]
        if emailField.waitForExistence(timeout: 5) {
            emailField.tap()
            emailField.typeText(email)
        }

        let passwordField = app.secureTextFields["Password"]
        if passwordField.waitForExistence(timeout: 3) {
            passwordField.tap()
            passwordField.typeText(password)
        }

        let loginButton = app.buttons["Continue to sign in"]
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
    /// If already logged in (tab bar visible), does nothing.
    /// If on login screen, logs in with demo customer credentials.
    /// If login fails (server down, invalid creds), throws XCTSkip.
    func ensureLoggedIn() throws {
        // Check if already logged in (tab bar = authenticated)
        let tabBar = app.tabBars.firstMatch
        if tabBar.waitForExistence(timeout: 5) {
            return // Already logged in
        }

        // Not logged in -- attempt login with demo credentials
        loginWithCredentials(email: Self.demoEmail, password: Self.demoPassword)

        // Wait for tab bar to confirm successful auth
        let loggedInTabBar = app.tabBars.firstMatch
        if !loggedInTabBar.waitForExistence(timeout: 15) {
            throw XCTSkip("Demo login failed -- staging may be unreachable (demo.customer@dollor.ai)")
        }
    }

    /// Throws `XCTSkip` if the login screen is still visible (user not logged in).
    /// Use at the top of tests that require authenticated state.
    func skipIfNotLoggedIn() throws {
        // LoginView shows "Welcome back" or "Create your account" or "Dollor.ai" when unauthenticated
        let welcomeBack = app.staticTexts["Welcome back"]
        let createAccount = app.staticTexts["Create your account"]
        let dollorLogo = app.staticTexts["Dollor.ai"]
        if welcomeBack.waitForExistence(timeout: 3) || createAccount.exists || dollorLogo.exists {
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
        attachment.name = "customer__\(name)"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
