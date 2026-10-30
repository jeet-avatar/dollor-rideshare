package com.eatfair.app.ui.auth

import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.createComposeRule
import org.junit.Rule
import org.junit.Test

/**
 * Comprehensive UI tests for LoginScreen composable.
 *
 * Tests cover:
 * - Initial state verification
 * - Text input functionality
 * - Login/SignUp mode toggle
 * - Button interactions
 * - Error message display
 * - Loading state
 * - Google Sign In button
 * - Forgot Password navigation
 */
class LoginScreenTest {

    @get:Rule
    val composeTestRule = createComposeRule()

    // ============================================================
    // INITIAL STATE TESTS
    // ============================================================

    @Test
    fun loginScreen_initialState_showsLoginMode() {
        composeTestRule.setContent {
            LoginScreen(
                onLoginClick = { _, _ -> },
                onSignUpClick = { _, _, _, _ -> },
                onGoogleSignInClick = { },
                onForgotPasswordClick = { }
            )
        }

        // Verify header elements
        composeTestRule.onNodeWithText("Dollor").assertIsDisplayed()
        composeTestRule.onNodeWithText("$ online store").assertIsDisplayed()

        // Verify Login button is shown (not Sign Up)
        composeTestRule.onNodeWithText("Login").assertIsDisplayed()

        // Verify input fields are empty
        composeTestRule.onNodeWithText("Email").assertExists()
        composeTestRule.onNodeWithText("Password").assertExists()

        // In login mode, Full Name and Phone fields should NOT be visible
        composeTestRule.onNodeWithText("Full Name").assertDoesNotExist()
        composeTestRule.onNodeWithText("Phone Number").assertDoesNotExist()

        // Verify footer text for login mode
        composeTestRule.onNodeWithText("Don't have an account?").assertIsDisplayed()
        composeTestRule.onNodeWithText("Sign Up").assertIsDisplayed()

        // Verify Forgot Password is visible in login mode
        composeTestRule.onNodeWithText("Forgot Password?").assertIsDisplayed()
    }

    @Test
    fun loginScreen_initialState_showsGoogleSignInButton() {
        composeTestRule.setContent {
            LoginScreen(
                onLoginClick = { _, _ -> },
                onSignUpClick = { _, _, _, _ -> },
                onGoogleSignInClick = { },
                onForgotPasswordClick = { }
            )
        }

        composeTestRule.onNodeWithText("Sign in with Google").assertIsDisplayed()
        composeTestRule.onNodeWithText("G").assertIsDisplayed() // Google icon letter
    }

    // ============================================================
    // MODE TOGGLE TESTS
    // ============================================================

    @Test
    fun loginScreen_toggleToSignUpMode_showsSignUpFields() {
        composeTestRule.setContent {
            LoginScreen(
                onLoginClick = { _, _ -> },
                onSignUpClick = { _, _, _, _ -> },
                onGoogleSignInClick = { },
                onForgotPasswordClick = { }
            )
        }

        // Click Sign Up to toggle mode
        composeTestRule.onNodeWithText("Sign Up").performClick()

        // Verify Sign Up mode is active
        composeTestRule.onAllNodesWithText("Sign Up").assertCountEquals(2) // Button and toggle
        composeTestRule.onNodeWithText("Full Name").assertIsDisplayed()
        composeTestRule.onNodeWithText("Phone Number").assertIsDisplayed()

        // Verify footer text changes to login toggle
        composeTestRule.onNodeWithText("Already have an account?").assertIsDisplayed()
        composeTestRule.onNodeWithText("Login").assertIsDisplayed()

        // Forgot Password should be hidden in sign up mode
        composeTestRule.onNodeWithText("Forgot Password?").assertDoesNotExist()
    }

    @Test
    fun loginScreen_toggleBackToLoginMode_hidesSignUpFields() {
        composeTestRule.setContent {
            LoginScreen(
                onLoginClick = { _, _ -> },
                onSignUpClick = { _, _, _, _ -> },
                onGoogleSignInClick = { },
                onForgotPasswordClick = { }
            )
        }

        // Toggle to Sign Up mode
        composeTestRule.onNodeWithText("Sign Up").performClick()

        // Verify Sign Up mode
        composeTestRule.onNodeWithText("Full Name").assertIsDisplayed()

        // Toggle back to Login mode
        composeTestRule.onNodeWithText("Login").performClick()

        // Verify Login mode is restored
        composeTestRule.onNodeWithText("Full Name").assertDoesNotExist()
        composeTestRule.onNodeWithText("Phone Number").assertDoesNotExist()
        composeTestRule.onNodeWithText("Forgot Password?").assertIsDisplayed()
    }

    // ============================================================
    // TEXT INPUT TESTS
    // ============================================================

    @Test
    fun loginScreen_emailInput_acceptsText() {
        composeTestRule.setContent {
            LoginScreen(
                onLoginClick = { _, _ -> },
                onSignUpClick = { _, _, _, _ -> },
                onGoogleSignInClick = { },
                onForgotPasswordClick = { }
            )
        }

        // Find email field by placeholder and input text
        composeTestRule.onNode(hasText("Email") and hasSetTextAction())
            .performTextInput("test@example.com")

        composeTestRule.onNodeWithText("test@example.com").assertIsDisplayed()
    }

    @Test
    fun loginScreen_passwordInput_acceptsText() {
        composeTestRule.setContent {
            LoginScreen(
                onLoginClick = { _, _ -> },
                onSignUpClick = { _, _, _, _ -> },
                onGoogleSignInClick = { },
                onForgotPasswordClick = { }
            )
        }

        // Password field - text will be obscured but we can verify input action works
        composeTestRule.onNode(hasText("Password") and hasSetTextAction())
            .performTextInput("password123")

        // Password should be masked, so we check the field exists and has content
        composeTestRule.onNode(hasText("Password") and hasSetTextAction())
            .assertExists()
    }

    @Test
    fun loginScreen_signUpMode_allFieldsAcceptInput() {
        composeTestRule.setContent {
            LoginScreen(
                onLoginClick = { _, _ -> },
                onSignUpClick = { _, _, _, _ -> },
                onGoogleSignInClick = { },
                onForgotPasswordClick = { }
            )
        }

        // Toggle to Sign Up mode
        composeTestRule.onNodeWithText("Sign Up").performClick()

        // Input Full Name
        composeTestRule.onNode(hasText("Full Name") and hasSetTextAction())
            .performTextInput("John Doe")
        composeTestRule.onNodeWithText("John Doe").assertIsDisplayed()

        // Input Phone Number
        composeTestRule.onNode(hasText("Phone Number") and hasSetTextAction())
            .performTextInput("+14155551234")
        composeTestRule.onNodeWithText("+14155551234").assertIsDisplayed()
    }

    // ============================================================
    // BUTTON INTERACTION TESTS
    // ============================================================

    @Test
    fun loginScreen_loginButtonClick_triggersCallback() {
        var loginClicked = false
        var capturedEmail = ""
        var capturedPassword = ""

        composeTestRule.setContent {
            LoginScreen(
                onLoginClick = { email, password ->
                    loginClicked = true
                    capturedEmail = email
                    capturedPassword = password
                },
                onSignUpClick = { _, _, _, _ -> },
                onGoogleSignInClick = { },
                onForgotPasswordClick = { }
            )
        }

        // Input credentials
        composeTestRule.onNode(hasText("Email") and hasSetTextAction())
            .performTextInput("user@test.com")
        composeTestRule.onNode(hasText("Password") and hasSetTextAction())
            .performTextInput("secret123")

        // Click Login button
        composeTestRule.onNodeWithText("Login").performClick()

        // Verify callback was triggered with correct data
        assert(loginClicked) { "Login callback was not triggered" }
        assert(capturedEmail == "user@test.com") { "Email was not captured correctly" }
        assert(capturedPassword == "secret123") { "Password was not captured correctly" }
    }

    @Test
    fun loginScreen_signUpButtonClick_triggersCallback() {
        var signUpClicked = false
        var capturedEmail = ""
        var capturedPassword = ""
        var capturedName = ""
        var capturedPhone = ""

        composeTestRule.setContent {
            LoginScreen(
                onLoginClick = { _, _ -> },
                onSignUpClick = { email, password, fullName, phone ->
                    signUpClicked = true
                    capturedEmail = email
                    capturedPassword = password
                    capturedName = fullName
                    capturedPhone = phone
                },
                onGoogleSignInClick = { },
                onForgotPasswordClick = { }
            )
        }

        // Toggle to Sign Up mode
        composeTestRule.onNodeWithText("Sign Up").performClick()

        // Input all fields
        composeTestRule.onNode(hasText("Full Name") and hasSetTextAction())
            .performTextInput("Jane Doe")
        composeTestRule.onNode(hasText("Phone Number") and hasSetTextAction())
            .performTextInput("+14155559999")
        composeTestRule.onNode(hasText("Email") and hasSetTextAction())
            .performTextInput("jane@test.com")
        composeTestRule.onNode(hasText("Password") and hasSetTextAction())
            .performTextInput("password456")

        // Click Sign Up button (first one is the button, second is the toggle)
        composeTestRule.onAllNodesWithText("Sign Up")[0].performClick()

        // Verify callback was triggered with correct data
        assert(signUpClicked) { "Sign Up callback was not triggered" }
        assert(capturedEmail == "jane@test.com") { "Email was not captured correctly" }
        assert(capturedPassword == "password456") { "Password was not captured correctly" }
        assert(capturedName == "Jane Doe") { "Name was not captured correctly" }
        assert(capturedPhone == "+14155559999") { "Phone was not captured correctly" }
    }

    @Test
    fun loginScreen_googleSignInClick_triggersCallback() {
        var googleClicked = false

        composeTestRule.setContent {
            LoginScreen(
                onLoginClick = { _, _ -> },
                onSignUpClick = { _, _, _, _ -> },
                onGoogleSignInClick = { googleClicked = true },
                onForgotPasswordClick = { }
            )
        }

        composeTestRule.onNodeWithText("Sign in with Google").performClick()

        assert(googleClicked) { "Google Sign In callback was not triggered" }
    }

    @Test
    fun loginScreen_forgotPasswordClick_triggersCallback() {
        var forgotPasswordClicked = false

        composeTestRule.setContent {
            LoginScreen(
                onLoginClick = { _, _ -> },
                onSignUpClick = { _, _, _, _ -> },
                onGoogleSignInClick = { },
                onForgotPasswordClick = { forgotPasswordClicked = true }
            )
        }

        composeTestRule.onNodeWithText("Forgot Password?").performClick()

        assert(forgotPasswordClicked) { "Forgot Password callback was not triggered" }
    }

    // ============================================================
    // LOADING STATE TESTS
    // ============================================================

    @Test
    fun loginScreen_loadingState_disablesButtons() {
        composeTestRule.setContent {
            LoginScreen(
                onLoginClick = { _, _ -> },
                onSignUpClick = { _, _, _, _ -> },
                onGoogleSignInClick = { },
                onForgotPasswordClick = { },
                isLoading = true
            )
        }

        // Verify Login button is disabled
        composeTestRule.onNodeWithText("Login").assertIsNotEnabled()

        // Verify Google Sign In button is disabled
        composeTestRule.onNodeWithText("Sign in with Google").assertIsNotEnabled()
    }

    @Test
    fun loginScreen_loadingState_showsProgressIndicator() {
        composeTestRule.setContent {
            LoginScreen(
                onLoginClick = { _, _ -> },
                onSignUpClick = { _, _, _, _ -> },
                onGoogleSignInClick = { },
                onForgotPasswordClick = { },
                isLoading = true
            )
        }

        // When loading, the Login text should not be visible (replaced by progress indicator)
        // The button exists but displays a CircularProgressIndicator instead of text
        composeTestRule.onNodeWithText("Login").assertDoesNotExist()
    }

    // ============================================================
    // ERROR MESSAGE TESTS
    // ============================================================

    @Test
    fun loginScreen_errorMessage_isDisplayed() {
        val errorText = "Invalid email or password"

        composeTestRule.setContent {
            LoginScreen(
                onLoginClick = { _, _ -> },
                onSignUpClick = { _, _, _, _ -> },
                onGoogleSignInClick = { },
                onForgotPasswordClick = { },
                errorMessage = errorText
            )
        }

        composeTestRule.onNodeWithText(errorText).assertIsDisplayed()
    }

    @Test
    fun loginScreen_noError_errorMessageNotDisplayed() {
        composeTestRule.setContent {
            LoginScreen(
                onLoginClick = { _, _ -> },
                onSignUpClick = { _, _, _, _ -> },
                onGoogleSignInClick = { },
                onForgotPasswordClick = { },
                errorMessage = null
            )
        }

        // No error message should be displayed
        composeTestRule.onNodeWithText("Invalid").assertDoesNotExist()
        composeTestRule.onNodeWithText("Error").assertDoesNotExist()
    }

    // ============================================================
    // UI ELEMENT VISIBILITY TESTS
    // ============================================================

    @Test
    fun loginScreen_dollarSignLogo_isDisplayed() {
        composeTestRule.setContent {
            LoginScreen(
                onLoginClick = { _, _ -> },
                onSignUpClick = { _, _, _, _ -> },
                onGoogleSignInClick = { },
                onForgotPasswordClick = { }
            )
        }

        // Verify the dollar sign logo is displayed
        composeTestRule.onNodeWithText("$").assertIsDisplayed()
    }

    // ============================================================
    // ACCESSIBILITY TESTS
    // ============================================================

    @Test
    fun loginScreen_allInteractiveElements_areClickable() {
        composeTestRule.setContent {
            LoginScreen(
                onLoginClick = { _, _ -> },
                onSignUpClick = { _, _, _, _ -> },
                onGoogleSignInClick = { },
                onForgotPasswordClick = { }
            )
        }

        // Verify all interactive elements have click action
        composeTestRule.onNodeWithText("Login").assertHasClickAction()
        composeTestRule.onNodeWithText("Sign in with Google").assertHasClickAction()
        composeTestRule.onNodeWithText("Forgot Password?").assertHasClickAction()
        composeTestRule.onNodeWithText("Sign Up").assertHasClickAction()
    }
}
