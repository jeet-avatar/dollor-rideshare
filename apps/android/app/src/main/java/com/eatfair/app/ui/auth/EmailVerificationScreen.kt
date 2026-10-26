package com.eatfair.app.ui.auth

import com.eatfair.shared.ui.Lx
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.filled.Email
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.tooling.preview.Preview
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.eatfair.app.ui.theme.BrandGreen
import com.eatfair.app.ui.theme.BrandGrey
import com.eatfair.app.ui.theme.BrandBlack
import com.eatfair.app.ui.theme.TextGrey

/**
 * Email Verification Screen
 *
 * Allows customers to verify their email address with a 6-digit code.
 * Required for App Store / Play Store compliance.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun EmailVerificationScreen(
    email: String,
    isVerified: Boolean = false,
    onSendCodeClick: () -> Unit,
    onVerifyCodeClick: (code: String) -> Unit,
    onBackClick: () -> Unit,
    onSkipClick: () -> Unit,
    isSendingCode: Boolean = false,
    isVerifying: Boolean = false,
    errorMessage: String? = null,
    successMessage: String? = null
) {
    var verificationCode by remember { mutableStateOf("") }
    var codeSent by remember { mutableStateOf(false) }

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text("Verify Email") },
                navigationIcon = {
                    IconButton(onClick = onBackClick) {
                        Icon(
                            Icons.AutoMirrored.Filled.ArrowBack,
                            contentDescription = "Back"
                        )
                    }
                },
                actions = {
                    TextButton(onClick = onSkipClick) {
                        Text(
                            text = "Skip",
                            color = TextGrey,
                            fontWeight = FontWeight.Medium
                        )
                    }
                },
                colors = TopAppBarDefaults.topAppBarColors(
                    containerColor = BrandGrey
                )
            )
        },
        containerColor = BrandGrey
    ) { paddingValues ->
        Column(
            modifier = Modifier
                .fillMaxSize()
                .padding(paddingValues)
                .padding(horizontal = 30.dp),
            horizontalAlignment = Alignment.CenterHorizontally
        ) {
            Spacer(modifier = Modifier.height(40.dp))

            // Email Icon
            Icon(
                imageVector = if (isVerified) Icons.Default.CheckCircle else Icons.Default.Email,
                contentDescription = null,
                modifier = Modifier.size(80.dp),
                tint = if (isVerified) BrandGreen else BrandGreen.copy(alpha = 0.7f)
            )

            Spacer(modifier = Modifier.height(24.dp))

            // Title
            Text(
                text = if (isVerified) "Email Verified!" else "Verify Your Email",
                fontSize = Lx.FontSize.title,
                fontWeight = FontWeight.Bold,
                color = BrandBlack
            )

            Spacer(modifier = Modifier.height(16.dp))

            if (isVerified) {
                // Already verified state
                Text(
                    text = "Your email $email has been verified successfully.",
                    fontSize = Lx.FontSize.footnote,
                    color = TextGrey,
                    textAlign = TextAlign.Center,
                    lineHeight = 20.sp
                )

                Spacer(modifier = Modifier.height(32.dp))

                Button(
                    onClick = onBackClick,
                    modifier = Modifier
                        .fillMaxWidth()
                        .height(52.dp),
                    colors = ButtonDefaults.buttonColors(
                        containerColor = BrandGreen
                    ),
                    shape = RoundedCornerShape(Lx.Radius.button)
                ) {
                    Text(
                        text = "Continue",
                        fontSize = Lx.FontSize.callout,
                        fontWeight = FontWeight.SemiBold
                    )
                }
            } else {
                // Not verified - show verification flow
                Text(
                    text = if (codeSent)
                        "We sent a 6-digit code to $email. Enter it below to verify your email."
                    else
                        "We'll send a verification code to $email",
                    fontSize = Lx.FontSize.footnote,
                    color = TextGrey,
                    textAlign = TextAlign.Center,
                    lineHeight = 20.sp
                )

                Spacer(modifier = Modifier.height(32.dp))

                if (!codeSent) {
                    // Send Code Button
                    Button(
                        onClick = {
                            onSendCodeClick()
                            codeSent = true
                        },
                        modifier = Modifier
                            .fillMaxWidth()
                            .height(52.dp),
                        colors = ButtonDefaults.buttonColors(
                            containerColor = BrandGreen,
                            disabledContainerColor = BrandGreen.copy(alpha = 0.5f)
                        ),
                        shape = RoundedCornerShape(Lx.Radius.button),
                        enabled = !isSendingCode
                    ) {
                        if (isSendingCode) {
                            CircularProgressIndicator(
                                color = Color.White,
                                modifier = Modifier.size(24.dp),
                                strokeWidth = 2.dp
                            )
                        } else {
                            Text(
                                text = "Send Verification Code",
                                fontSize = Lx.FontSize.callout,
                                fontWeight = FontWeight.SemiBold
                            )
                        }
                    }
                } else {
                    // Code Entry
                    OutlinedTextField(
                        value = verificationCode,
                        onValueChange = {
                            if (it.length <= 6 && it.all { char -> char.isDigit() }) {
                                verificationCode = it
                            }
                        },
                        modifier = Modifier
                            .fillMaxWidth()
                            .shadow(
                                elevation = 2.dp,
                                shape = RoundedCornerShape(Lx.Radius.button),
                                ambientColor = Color.Black.copy(alpha = 0.05f)
                            ),
                        placeholder = { Text("Enter 6-digit code", color = TextGrey) },
                        keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Number),
                        shape = RoundedCornerShape(Lx.Radius.button),
                        colors = OutlinedTextFieldDefaults.colors(
                            focusedContainerColor = Lx.Surface,
                            unfocusedContainerColor = Lx.Surface,
                            focusedBorderColor = BrandGreen,
                            unfocusedBorderColor = Color.Transparent
                        ),
                        singleLine = true,
                        textStyle = LocalTextStyle.current.copy(
                            textAlign = TextAlign.Center,
                            fontSize = Lx.FontSize.title,
                            letterSpacing = 8.sp
                        )
                    )

                    // Success Message
                    successMessage?.let { message ->
                        Spacer(modifier = Modifier.height(12.dp))
                        Text(
                            text = message,
                            fontSize = Lx.FontSize.caption,
                            color = BrandGreen,
                            textAlign = TextAlign.Center
                        )
                    }

                    // Error Message
                    errorMessage?.let { error ->
                        Spacer(modifier = Modifier.height(12.dp))
                        Text(
                            text = error,
                            fontSize = Lx.FontSize.caption,
                            color = Lx.Error,
                            textAlign = TextAlign.Center
                        )
                    }

                    Spacer(modifier = Modifier.height(24.dp))

                    // Verify Button
                    Button(
                        onClick = { onVerifyCodeClick(verificationCode) },
                        modifier = Modifier
                            .fillMaxWidth()
                            .height(52.dp),
                        colors = ButtonDefaults.buttonColors(
                            containerColor = BrandGreen,
                            disabledContainerColor = BrandGreen.copy(alpha = 0.5f)
                        ),
                        shape = RoundedCornerShape(Lx.Radius.button),
                        enabled = !isVerifying && verificationCode.length == 6
                    ) {
                        if (isVerifying) {
                            CircularProgressIndicator(
                                color = Color.White,
                                modifier = Modifier.size(24.dp),
                                strokeWidth = 2.dp
                            )
                        } else {
                            Text(
                                text = "Verify Email",
                                fontSize = Lx.FontSize.callout,
                                fontWeight = FontWeight.SemiBold
                            )
                        }
                    }

                    Spacer(modifier = Modifier.height(16.dp))

                    // Resend Code
                    TextButton(
                        onClick = onSendCodeClick,
                        enabled = !isSendingCode
                    ) {
                        Text(
                            text = if (isSendingCode) "Sending..." else "Resend Code",
                            color = BrandGreen,
                            fontWeight = FontWeight.Medium
                        )
                    }
                }
            }

            Spacer(modifier = Modifier.weight(1f))

            // Footer note
            if (!isVerified) {
                Text(
                    text = "Verifying your email helps keep your account secure",
                    fontSize = Lx.FontSize.caption,
                    color = TextGrey,
                    textAlign = TextAlign.Center
                )
                Spacer(modifier = Modifier.height(24.dp))
            }
        }
    }
}

@Preview(showBackground = true)
@Composable
fun EmailVerificationScreenPreview() {
    EmailVerificationScreen(
        email = "user@example.com",
        isVerified = false,
        onSendCodeClick = { },
        onVerifyCodeClick = { },
        onBackClick = { },
        onSkipClick = { }
    )
}

@Preview(showBackground = true)
@Composable
fun EmailVerificationScreenVerifiedPreview() {
    EmailVerificationScreen(
        email = "user@example.com",
        isVerified = true,
        onSendCodeClick = { },
        onVerifyCodeClick = { },
        onBackClick = { },
        onSkipClick = { }
    )
}
