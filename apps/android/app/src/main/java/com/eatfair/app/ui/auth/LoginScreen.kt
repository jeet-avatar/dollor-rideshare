package com.eatfair.app.ui.auth

import com.eatfair.shared.config.AppConfig
import com.eatfair.shared.ui.Lx
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Email
import androidx.compose.material.icons.filled.Lock
import androidx.compose.material.icons.filled.Person
import androidx.compose.material.icons.filled.Phone
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.tooling.preview.Preview
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.eatfair.app.ui.components.DollorLogo
import com.eatfair.app.ui.components.DollorBrandColors

// Brand Colors - Enterprise Orange Theme
private val PrimaryOrange = DollorBrandColors.PrimaryOrange  // Vibrant orange
private val DarkOrange = DollorBrandColors.DarkOrange
private val TextPrimary = Lx.Text
private val TextSecondary = Lx.TextSecondary
private val BorderColor = Lx.Hairline
private val BackgroundWhite = Lx.Surface
private val BackgroundGrey = Lx.Surface2

@Preview(showBackground = true)
@Composable
fun LoginScreenPreview() {
    LoginScreen(
        onLoginClick = { _, _ -> },
        onSignUpClick = { _, _, _, _ -> },
        onGoogleSignInClick = { },
        onAppleSignInClick = { },
        onForgotPasswordClick = { }
    )
}

@Composable
fun LoginScreen(
    onLoginClick: (email: String, password: String) -> Unit,
    onSignUpClick: (email: String, password: String, fullName: String, phone: String) -> Unit,
    onGoogleSignInClick: () -> Unit = {},
    onAppleSignInClick: () -> Unit = {},
    onForgotPasswordClick: () -> Unit = {},
    onTermsClick: () -> Unit = {},
    onPrivacyClick: () -> Unit = {},
    isLoading: Boolean = false,
    isGoogleLoading: Boolean = false,
    isAppleLoading: Boolean = false,
    // Hidden by default: Sign in with Apple has no native Android SDK and no Apple
    // OAuth web flow is wired here, so the button would be dead. The backend customer
    // apple-auth route is built for the iOS native flow. Enable only once a real
    // Android Apple OAuth flow exists.
    showAppleSignIn: Boolean = false,
    errorMessage: String? = null
) {
    var email by remember { mutableStateOf("") }
    var password by remember { mutableStateOf("") }
    var isSignUp by remember { mutableStateOf(false) }
    var fullName by remember { mutableStateOf("") }
    var phone by remember { mutableStateOf("") }
    var validationError by remember { mutableStateOf<String?>(null) }

    // Validation functions
    fun isValidEmail(email: String): Boolean {
        return android.util.Patterns.EMAIL_ADDRESS.matcher(email).matches()
    }

    fun validateLogin(): String? {
        return when {
            email.isBlank() -> "Please enter your email address"
            !isValidEmail(email) -> "Please enter a valid email address"
            password.isBlank() -> "Please enter your password"
            password.length < 6 -> "Password must be at least 6 characters"
            else -> null
        }
    }

    fun validateSignUp(): String? {
        return when {
            fullName.isBlank() -> "Please enter your full name"
            fullName.length < 2 -> "Name must be at least 2 characters"
            phone.isBlank() -> "Please enter your phone number"
            phone.length < 10 -> "Please enter a valid phone number"
            email.isBlank() -> "Please enter your email address"
            !isValidEmail(email) -> "Please enter a valid email address"
            password.isBlank() -> "Please enter your password"
            password.length < 6 -> "Password must be at least 6 characters"
            else -> null
        }
    }

    Box(
        modifier = Modifier
            .fillMaxSize()
            .background(Lx.Bg)
            .systemBarsPadding()
    ) {
        Column(
            modifier = Modifier
                .fillMaxSize()
                .verticalScroll(rememberScrollState())
                .padding(horizontal = 24.dp),
            horizontalAlignment = Alignment.CenterHorizontally
        ) {
            Spacer(modifier = Modifier.height(20.dp))

            // Logo Section - Smiley with $$ eyes
            DollorLogo(
                size = 60.dp,
                backgroundColor = PrimaryOrange,
                contentColor = Color.White
            )

            Spacer(modifier = Modifier.height(8.dp))

            Text(
                text = "Dollor.ai",
                fontSize = Lx.FontSize.title,
                fontWeight = FontWeight.SemiBold,
                color = TextPrimary,
                letterSpacing = (-0.5).sp
            )

            Spacer(modifier = Modifier.height(16.dp))

            // Header
            Text(
                text = if (isSignUp) "Create your account" else "Welcome back",
                fontSize = Lx.FontSize.title,
                fontWeight = FontWeight.SemiBold,
                color = TextPrimary,
                letterSpacing = (-0.5).sp
            )

            Spacer(modifier = Modifier.height(4.dp))

            Text(
                text = if (isSignUp) "Start riding with a flat ${AppConfig.Rideshare.feeRangeText} platform fee" else "Log in to continue to Dollor.ai",
                fontSize = Lx.FontSize.footnote,
                color = TextSecondary,
                textAlign = TextAlign.Center
            )

            Spacer(modifier = Modifier.height(20.dp))

            // Social Login Buttons
            // Apple Sign In Button (Black) - hidden on Android (no Apple OAuth flow wired)
            if (showAppleSignIn) {
                Button(
                    onClick = onAppleSignInClick,
                    modifier = Modifier
                        .fillMaxWidth()
                        .height(48.dp),
                    colors = ButtonDefaults.buttonColors(
                        containerColor = Lx.Text
                    ),
                    shape = RoundedCornerShape(Lx.Radius.chip),
                    enabled = !isAppleLoading && !isLoading
                ) {
                    if (isAppleLoading) {
                        CircularProgressIndicator(
                            color = Color.White,
                            modifier = Modifier.size(20.dp),
                            strokeWidth = 2.dp
                        )
                    } else {
                        Row(
                            horizontalArrangement = Arrangement.Center,
                            verticalAlignment = Alignment.CenterVertically
                        ) {
                            // Apple Logo (simplified)
                            Text(
                                text = "\uF8FF", // Apple logo unicode
                                fontSize = Lx.FontSize.body,
                                color = Color.White,
                                fontWeight = FontWeight.Normal
                            )
                            Spacer(modifier = Modifier.width(12.dp))
                            Text(
                                text = "Continue with Apple",
                                fontSize = Lx.FontSize.callout,
                                fontWeight = FontWeight.Medium,
                                color = Color.White
                            )
                        }
                    }
                }

                Spacer(modifier = Modifier.height(10.dp))
            }

            // Google Sign In Button (White with border)
            OutlinedButton(
                onClick = onGoogleSignInClick,
                modifier = Modifier
                    .fillMaxWidth()
                    .height(48.dp),
                shape = RoundedCornerShape(Lx.Radius.chip),
                colors = ButtonDefaults.outlinedButtonColors(
                    containerColor = BackgroundWhite
                ),
                border = androidx.compose.foundation.BorderStroke(1.dp, BorderColor),
                enabled = !isGoogleLoading && !isLoading
            ) {
                if (isGoogleLoading) {
                    CircularProgressIndicator(
                        color = PrimaryOrange,
                        modifier = Modifier.size(20.dp),
                        strokeWidth = 2.dp
                    )
                } else {
                    Row(
                        horizontalArrangement = Arrangement.Center,
                        verticalAlignment = Alignment.CenterVertically
                    ) {
                        // Google Logo Colors
                        Text(
                            text = "G",
                            fontSize = Lx.FontSize.body,
                            fontWeight = FontWeight.Bold,
                            color = Lx.GoogleRed // Google Red
                        )
                        Spacer(modifier = Modifier.width(12.dp))
                        Text(
                            text = "Continue with Google",
                            fontSize = Lx.FontSize.callout,
                            fontWeight = FontWeight.Medium,
                            color = TextPrimary
                        )
                    }
                }
            }

            Spacer(modifier = Modifier.height(16.dp))

            // Divider with "or"
            Row(
                modifier = Modifier.fillMaxWidth(),
                verticalAlignment = Alignment.CenterVertically
            ) {
                Divider(
                    modifier = Modifier.weight(1f),
                    color = BorderColor,
                    thickness = 1.dp
                )
                Text(
                    text = "or",
                    modifier = Modifier.padding(horizontal = 16.dp),
                    fontSize = Lx.FontSize.footnote,
                    color = TextSecondary
                )
                Divider(
                    modifier = Modifier.weight(1f),
                    color = BorderColor,
                    thickness = 1.dp
                )
            }

            Spacer(modifier = Modifier.height(16.dp))

            // Input Fields
            Column(
                verticalArrangement = Arrangement.spacedBy(12.dp)
            ) {
                if (isSignUp) {
                    // Full Name Field
                    OutlinedTextField(
                        value = fullName,
                        onValueChange = { fullName = it },
                        modifier = Modifier.fillMaxWidth(),
                        placeholder = { Text("Full name", color = TextSecondary) },
                        leadingIcon = {
                            Icon(Icons.Default.Person, contentDescription = null, tint = TextSecondary)
                        },
                        shape = RoundedCornerShape(Lx.Radius.chip),
                        colors = OutlinedTextFieldDefaults.colors(
                            focusedTextColor = TextPrimary,
                            unfocusedTextColor = TextPrimary,
                            cursorColor = PrimaryOrange,
                            focusedContainerColor = BackgroundWhite,
                            unfocusedContainerColor = BackgroundWhite,
                            focusedBorderColor = PrimaryOrange,
                            unfocusedBorderColor = BorderColor
                        ),
                        singleLine = true
                    )

                    // Phone Field
                    OutlinedTextField(
                        value = phone,
                        onValueChange = { phone = it },
                        modifier = Modifier.fillMaxWidth(),
                        placeholder = { Text("Phone number", color = TextSecondary) },
                        leadingIcon = {
                            Icon(Icons.Default.Phone, contentDescription = null, tint = TextSecondary)
                        },
                        keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Phone),
                        shape = RoundedCornerShape(Lx.Radius.chip),
                        colors = OutlinedTextFieldDefaults.colors(
                            focusedTextColor = TextPrimary,
                            unfocusedTextColor = TextPrimary,
                            cursorColor = PrimaryOrange,
                            focusedContainerColor = BackgroundWhite,
                            unfocusedContainerColor = BackgroundWhite,
                            focusedBorderColor = PrimaryOrange,
                            unfocusedBorderColor = BorderColor
                        ),
                        singleLine = true
                    )
                }

                // Email Field
                OutlinedTextField(
                    value = email,
                    onValueChange = { email = it },
                    modifier = Modifier.fillMaxWidth(),
                    placeholder = { Text("Email address", color = TextSecondary) },
                    leadingIcon = {
                        Icon(Icons.Default.Email, contentDescription = null, tint = TextSecondary)
                    },
                    keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Email),
                    shape = RoundedCornerShape(Lx.Radius.chip),
                    colors = OutlinedTextFieldDefaults.colors(
                        focusedTextColor = TextPrimary,
                        unfocusedTextColor = TextPrimary,
                        cursorColor = PrimaryOrange,
                        focusedContainerColor = BackgroundWhite,
                        unfocusedContainerColor = BackgroundWhite,
                        focusedBorderColor = PrimaryOrange,
                        unfocusedBorderColor = BorderColor
                    ),
                    singleLine = true
                )

                // Password Field
                OutlinedTextField(
                    value = password,
                    onValueChange = { password = it },
                    modifier = Modifier.fillMaxWidth(),
                    placeholder = { Text("Password", color = TextSecondary) },
                    leadingIcon = {
                        Icon(Icons.Default.Lock, contentDescription = null, tint = TextSecondary)
                    },
                    visualTransformation = PasswordVisualTransformation(),
                    keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Password),
                    shape = RoundedCornerShape(Lx.Radius.chip),
                    colors = OutlinedTextFieldDefaults.colors(
                        focusedTextColor = TextPrimary,
                        unfocusedTextColor = TextPrimary,
                        cursorColor = PrimaryOrange,
                        focusedContainerColor = BackgroundWhite,
                        unfocusedContainerColor = BackgroundWhite,
                        focusedBorderColor = PrimaryOrange,
                        unfocusedBorderColor = BorderColor
                    ),
                    singleLine = true
                )
            }

            // Forgot Password (only show on login)
            if (!isSignUp) {
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.End
                ) {
                    TextButton(onClick = onForgotPasswordClick) {
                        Text(
                            text = "Forgot password?",
                            fontSize = Lx.FontSize.footnote,
                            fontWeight = FontWeight.Medium,
                            color = PrimaryOrange
                        )
                    }
                }
            } else {
                Spacer(modifier = Modifier.height(16.dp))
            }

            // Login/Sign Up Button
            Button(
                onClick = {
                    validationError = null // Clear previous validation error
                    if (isSignUp) {
                        val error = validateSignUp()
                        if (error != null) {
                            validationError = error
                        } else {
                            onSignUpClick(email, password, fullName, phone)
                        }
                    } else {
                        val error = validateLogin()
                        if (error != null) {
                            validationError = error
                        } else {
                            onLoginClick(email, password)
                        }
                    }
                },
                modifier = Modifier
                    .fillMaxWidth()
                    .height(48.dp),
                colors = ButtonDefaults.buttonColors(
                    containerColor = PrimaryOrange
                ),
                shape = RoundedCornerShape(Lx.Radius.chip),
                enabled = !isLoading
            ) {
                if (isLoading) {
                    CircularProgressIndicator(
                        color = Color.White,
                        modifier = Modifier.size(20.dp),
                        strokeWidth = 2.dp
                    )
                } else {
                    Text(
                        text = if (isSignUp) "Create account" else "Continue",
                        fontSize = Lx.FontSize.callout,
                        fontWeight = FontWeight.SemiBold
                    )
                }
            }

            // Error Message (validation or API error)
            val displayError = validationError ?: errorMessage
            displayError?.let { error ->
                Spacer(modifier = Modifier.height(12.dp))
                Text(
                    text = error,
                    fontSize = Lx.FontSize.footnote,
                    color = Lx.Error,
                    textAlign = TextAlign.Center,
                    modifier = Modifier.fillMaxWidth()
                )
            }

            Spacer(modifier = Modifier.height(16.dp))

            // Toggle Login/Sign Up
            Row(
                verticalAlignment = Alignment.CenterVertically
            ) {
                Text(
                    text = if (isSignUp) "Already have an account?" else "Don't have an account?",
                    fontSize = Lx.FontSize.footnote,
                    color = TextSecondary
                )
                TextButton(
                    onClick = { isSignUp = !isSignUp }
                ) {
                    Text(
                        text = if (isSignUp) "Log in" else "Sign up",
                        fontSize = Lx.FontSize.footnote,
                        fontWeight = FontWeight.SemiBold,
                        color = PrimaryOrange
                    )
                }
            }

            Spacer(modifier = Modifier.height(16.dp))

            // Fee Info Badge
            Row(
                modifier = Modifier
                    .clip(RoundedCornerShape(Lx.Radius.chip))
                    .background(BackgroundGrey)
                    .padding(horizontal = 12.dp, vertical = 8.dp),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.Center
            ) {
                Box(
                    modifier = Modifier
                        .size(28.dp)
                        .clip(CircleShape)
                        .background(PrimaryOrange),
                    contentAlignment = Alignment.Center
                ) {
                    Text(
                        text = "$1",
                        fontSize = Lx.FontSize.caption,
                        fontWeight = FontWeight.Bold,
                        color = Color.White
                    )
                }
                Spacer(modifier = Modifier.width(10.dp))
                Text(
                    text = "flat platform fee. 100% tips go to drivers.",
                    fontSize = Lx.FontSize.caption,
                    color = TextSecondary
                )
            }

            Spacer(modifier = Modifier.height(12.dp))

            // Footer Links - Clickable for legal compliance
            Row(
                modifier = Modifier.padding(bottom = 16.dp),
                horizontalArrangement = Arrangement.Center,
                verticalAlignment = Alignment.CenterVertically
            ) {
                Text(
                    text = "Terms of Use",
                    fontSize = Lx.FontSize.caption,
                    color = PrimaryOrange,
                    fontWeight = FontWeight.Medium,
                    modifier = Modifier.clickable { onTermsClick() }
                )
                Text(
                    text = " · ",
                    fontSize = Lx.FontSize.caption,
                    color = BorderColor
                )
                Text(
                    text = "Privacy Policy",
                    fontSize = Lx.FontSize.caption,
                    color = PrimaryOrange,
                    fontWeight = FontWeight.Medium,
                    modifier = Modifier.clickable { onPrivacyClick() }
                )
            }
        }
    }
}
