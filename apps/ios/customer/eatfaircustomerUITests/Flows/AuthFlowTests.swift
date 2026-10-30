//
//  AuthFlowTests.swift
//  eatfaircustomerUITests
//
//  Customer authentication flow tests: login, register, forgot password, social auth.
//  Source: UI_INTERACTION_AUDIT.md iOS Customer Auth Flow (#1-27)
//

import XCTest

final class CustomerAuthFlowTests: DollorTestCase {

    // MARK: - Login Tests

    @MainActor
    func testLogin_validCredentials_navigatesToHome() throws {
        navigateToLogin()

        let emailField = app.textFields["Email address"]
        XCTAssertTrue(emailField.waitForExistence(timeout: 5), "Email field should exist")
        emailField.tap()
        emailField.typeText("demo.customer@dollor.ai")

        let passwordField = app.secureTextFields["Password"]
        XCTAssertTrue(passwordField.waitForExistence(timeout: 3), "Password field should exist")
        passwordField.tap()
        passwordField.typeText(ProcessInfo.processInfo.environment["DEMO_LOGIN_PASSWORD"] ?? "")

        let loginButton = app.buttons["Continue to sign in"]
        XCTAssertTrue(loginButton.waitForExistence(timeout: 3), "Login button should exist")
        loginButton.tap()

        // Verify home tab exists after login (may take time for network)
        let homeTab = app.tabBars.buttons.firstMatch
        XCTAssertTrue(homeTab.waitForExistence(timeout: 15), "Home tab should appear after successful login")
    }

    @MainActor
    func testLogin_emptyFields_showsError() throws {
        navigateToLogin()

        let loginButton = app.buttons["Continue to sign in"]
        XCTAssertTrue(loginButton.waitForExistence(timeout: 5), "Login button should exist")
        loginButton.tap()

        // LoginView uses EmailValidator -- empty email shows inline error text
        let errorAlert = app.alerts.firstMatch
        let errorText = app.staticTexts.containing(NSPredicate(format: "label CONTAINS[c] 'error' OR label CONTAINS[c] 'required' OR label CONTAINS[c] 'enter' OR label CONTAINS[c] 'email' OR label CONTAINS[c] 'valid'")).firstMatch
        let hasError = errorAlert.waitForExistence(timeout: 5) || errorText.waitForExistence(timeout: 3)
        XCTAssertTrue(hasError, "Error should appear when submitting with empty fields")
    }

    @MainActor
    func testLogin_invalidEmail_showsValidation() throws {
        navigateToLogin()

        let emailField = app.textFields["Email address"]
        XCTAssertTrue(emailField.waitForExistence(timeout: 5))
        emailField.tap()
        emailField.typeText("not-an-email")

        let passwordField = app.secureTextFields["Password"]
        passwordField.tap()
        passwordField.typeText("SomePassword1!")

        let loginButton = app.buttons["Continue to sign in"]
        loginButton.tap()

        // Verify validation message (EmailValidator shows inline error)
        let validationText = app.staticTexts.containing(NSPredicate(format: "label CONTAINS[c] 'valid' OR label CONTAINS[c] 'email' OR label CONTAINS[c] 'error'")).firstMatch
        let errorAlert = app.alerts.firstMatch
        let hasValidation = validationText.waitForExistence(timeout: 5) || errorAlert.waitForExistence(timeout: 3)
        XCTAssertTrue(hasValidation, "Validation should appear for invalid email")
    }

    // MARK: - Sign Up Tests

    @MainActor
    func testSignUp_allFieldsVisible() throws {
        navigateToLogin()

        let signUpToggle = app.buttons["Switch to sign up"]
        XCTAssertTrue(signUpToggle.waitForExistence(timeout: 5), "Sign Up toggle should exist")
        signUpToggle.tap()

        let fullNameField = app.textFields["Full name"]
        XCTAssertTrue(fullNameField.waitForExistence(timeout: 3), "Full name field should appear in sign up mode")

        let phoneField = app.textFields["Phone number"]
        XCTAssertTrue(phoneField.waitForExistence(timeout: 3), "Phone number field should appear in sign up mode")

        let emailField = app.textFields["Email address"]
        XCTAssertTrue(emailField.exists, "Email field should exist in sign up mode")

        let passwordField = app.secureTextFields["Password"]
        XCTAssertTrue(passwordField.exists, "Password field should exist in sign up mode")
    }

    @MainActor
    func testSignUp_toggleBackToLogin() throws {
        navigateToLogin()

        // Toggle to Sign Up
        let signUpToggle = app.buttons["Switch to sign up"]
        XCTAssertTrue(signUpToggle.waitForExistence(timeout: 5))
        signUpToggle.tap()

        let fullNameField = app.textFields["Full name"]
        XCTAssertTrue(fullNameField.waitForExistence(timeout: 3), "Full name should be visible in sign up mode")

        // Toggle back to Login
        let loginToggle = app.buttons["Switch to log in"]
        XCTAssertTrue(loginToggle.waitForExistence(timeout: 3))
        loginToggle.tap()

        // Full name field should be hidden
        XCTAssertFalse(app.textFields["Full name"].exists, "Full name should be hidden in login mode")
    }

    // MARK: - Forgot Password Tests

    @MainActor
    func testForgotPassword_opensSheet() throws {
        navigateToLogin()

        let forgotPasswordButton = app.buttons["Forgot password"]
        XCTAssertTrue(forgotPasswordButton.waitForExistence(timeout: 5), "Forgot Password button should exist")

        forgotPasswordButton.tap()

        let resetPasswordTitle = app.staticTexts["Reset Password"]
        XCTAssertTrue(resetPasswordTitle.waitForExistence(timeout: 5), "Reset Password sheet should appear")
    }

    // MARK: - Social Auth Tests

    @MainActor
    func testGoogleSignIn_buttonExists() throws {
        navigateToLogin()

        let googleButton = app.buttons["Sign in with Google"]
        XCTAssertTrue(googleButton.waitForExistence(timeout: 5), "Google Sign In button should exist")
        XCTAssertTrue(googleButton.isEnabled, "Google Sign In button should be enabled")
    }

    @MainActor
    func testAppleSignIn_buttonExists() throws {
        navigateToLogin()

        let appleButton = app.buttons["Sign in with Apple"]
        XCTAssertTrue(appleButton.waitForExistence(timeout: 5), "Apple Sign In button should exist")
        XCTAssertTrue(appleButton.isEnabled, "Apple Sign In button should be enabled")
    }

    // MARK: - Legal Acceptance Tests

    @MainActor
    func testLegalAcceptance_allDocumentsPresent() throws {
        navigateToLogin()

        // Footer links are always visible on LoginView (not just sign-up mode)
        // They are SwiftUI Link views which appear as links/buttons in accessibility tree
        let termsLink = app.links.containing(NSPredicate(format: "label CONTAINS[c] 'terms'")).firstMatch
        let termsButton = app.buttons.containing(NSPredicate(format: "label CONTAINS[c] 'terms'")).firstMatch
        let termsText = app.staticTexts.containing(NSPredicate(format: "label CONTAINS[c] 'terms'")).firstMatch

        let hasLegal = termsLink.waitForExistence(timeout: 5) || termsButton.exists || termsText.exists
        XCTAssertTrue(hasLegal, "Terms and/or Privacy links should be present on login screen")
    }
}
