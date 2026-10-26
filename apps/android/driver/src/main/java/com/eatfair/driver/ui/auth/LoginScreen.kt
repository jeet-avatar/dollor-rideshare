package com.eatfair.driver.ui.auth

import com.eatfair.shared.ui.Lx
import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Email
import androidx.compose.material.icons.filled.Lock
import androidx.compose.material.icons.filled.Visibility
import androidx.compose.material.icons.filled.VisibilityOff
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.focus.FocusDirection
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalFocusManager
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.text.input.VisualTransformation
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.eatfair.driver.ui.theme.DollorDriverColors

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun LoginScreen(
    loginState: LoginState,
    onLogin: (email: String, password: String) -> Unit,
    onGoogleSignInClick: () -> Unit,
    onClearError: () -> Unit,
    onForgotPassword: (email: String, onResult: (Boolean, String) -> Unit) -> Unit,
    onResetPassword: (email: String, code: String, newPassword: String, onResult: (Boolean, String) -> Unit) -> Unit,
    rememberedCredentials: Pair<String, String>? = null
) {
    // Prefills from the last successful login so a driver who lands back on this screen
    // (logged out, session expired, reinstall) doesn't have to retype credentials.
    var email by remember { mutableStateOf(rememberedCredentials?.first ?: "") }
    var password by remember { mutableStateOf(rememberedCredentials?.second ?: "") }
    var passwordVisible by remember { mutableStateOf(false) }
    var showForgotPassword by remember { mutableStateOf(false) }
    val focusManager = LocalFocusManager.current

    val isLoading = loginState is LoginState.Loading
    val errorMessage = (loginState as? LoginState.Error)?.message

    Box(
        modifier = Modifier
            .fillMaxSize()
            .background(Lx.Bg)
    ) {
        Column(
            modifier = Modifier
                .fillMaxSize()
                .padding(24.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.Center
        ) {
            // Logo/Title Section
            Text(
                text = "DOLLOR",
                style = MaterialTheme.typography.headlineLarge.copy(
                    fontWeight = FontWeight.Bold,
                    letterSpacing = 4.sp
                ),
                color = DollorDriverColors.White
            )
            Text(
                text = "DRIVER",
                style = MaterialTheme.typography.titleLarge.copy(
                    fontWeight = FontWeight.Medium,
                    letterSpacing = 2.sp
                ),
                color = Lx.Orange
            )

            Spacer(modifier = Modifier.height(48.dp))

            // Login Card
            Card(
                modifier = Modifier.fillMaxWidth(),
                shape = RoundedCornerShape(Lx.Radius.sheet),
                colors = CardDefaults.cardColors(containerColor = Lx.Surface)
            ) {
                Column(
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(24.dp),
                    horizontalAlignment = Alignment.CenterHorizontally
                ) {
                    Text(
                        text = "Welcome Back",
                        style = MaterialTheme.typography.headlineSmall.copy(
                            fontWeight = FontWeight.Bold
                        ),
                        color = DollorDriverColors.Gray900
                    )
                    Text(
                        text = "Sign in to continue driving",
                        style = MaterialTheme.typography.bodyMedium,
                        color = DollorDriverColors.Gray500,
                        modifier = Modifier.padding(top = 4.dp)
                    )

                    Spacer(modifier = Modifier.height(32.dp))

                    // Email Field
                    OutlinedTextField(
                        value = email,
                        onValueChange = {
                            email = it
                            if (errorMessage != null) onClearError()
                        },
                        label = { Text("Email") },
                        leadingIcon = {
                            Icon(
                                imageVector = Icons.Default.Email,
                                contentDescription = "Email",
                                tint = DollorDriverColors.Blue
                            )
                        },
                        modifier = Modifier.fillMaxWidth(),
                        shape = RoundedCornerShape(Lx.Radius.button),
                        keyboardOptions = KeyboardOptions(
                            keyboardType = KeyboardType.Email,
                            imeAction = ImeAction.Next
                        ),
                        keyboardActions = KeyboardActions(
                            onNext = { focusManager.moveFocus(FocusDirection.Down) }
                        ),
                        singleLine = true,
                        enabled = !isLoading,
                        colors = OutlinedTextFieldDefaults.colors(
                            focusedBorderColor = DollorDriverColors.Blue,
                            unfocusedBorderColor = DollorDriverColors.Gray300
                        )
                    )

                    Spacer(modifier = Modifier.height(16.dp))

                    // Password Field
                    OutlinedTextField(
                        value = password,
                        onValueChange = {
                            password = it
                            if (errorMessage != null) onClearError()
                        },
                        label = { Text("Password") },
                        leadingIcon = {
                            Icon(
                                imageVector = Icons.Default.Lock,
                                contentDescription = "Password",
                                tint = DollorDriverColors.Blue
                            )
                        },
                        trailingIcon = {
                            IconButton(onClick = { passwordVisible = !passwordVisible }) {
                                Icon(
                                    imageVector = if (passwordVisible) Icons.Default.Visibility else Icons.Default.VisibilityOff,
                                    contentDescription = if (passwordVisible) "Hide password" else "Show password",
                                    tint = DollorDriverColors.Gray400
                                )
                            }
                        },
                        modifier = Modifier.fillMaxWidth(),
                        shape = RoundedCornerShape(Lx.Radius.button),
                        visualTransformation = if (passwordVisible) VisualTransformation.None else PasswordVisualTransformation(),
                        keyboardOptions = KeyboardOptions(
                            keyboardType = KeyboardType.Password,
                            imeAction = ImeAction.Done
                        ),
                        keyboardActions = KeyboardActions(
                            onDone = {
                                focusManager.clearFocus()
                                if (email.isNotBlank() && password.isNotBlank()) {
                                    onLogin(email.trim(), password)
                                }
                            }
                        ),
                        singleLine = true,
                        enabled = !isLoading,
                        colors = OutlinedTextFieldDefaults.colors(
                            focusedBorderColor = DollorDriverColors.Blue,
                            unfocusedBorderColor = DollorDriverColors.Gray300
                        )
                    )

                    // Error Message
                    errorMessage?.let { error ->
                        Spacer(modifier = Modifier.height(8.dp))
                        Text(
                            text = error,
                            color = DollorDriverColors.Error,
                            style = MaterialTheme.typography.bodySmall,
                            textAlign = TextAlign.Center,
                            modifier = Modifier.fillMaxWidth()
                        )
                    }

                    Spacer(modifier = Modifier.height(24.dp))

                    // Login Button
                    Button(
                        onClick = {
                            if (email.isBlank() || password.isBlank()) {
                                // Let the ViewModel handle this via the caller if needed,
                                // but we can show a local hint
                            } else {
                                onLogin(email.trim(), password)
                            }
                        },
                        modifier = Modifier
                            .fillMaxWidth()
                            .height(56.dp),
                        shape = RoundedCornerShape(Lx.Radius.card),
                        colors = ButtonDefaults.buttonColors(
                            containerColor = DollorDriverColors.Blue
                        ),
                        enabled = !isLoading && email.isNotBlank() && password.isNotBlank()
                    ) {
                        if (isLoading) {
                            CircularProgressIndicator(
                                modifier = Modifier.size(24.dp),
                                color = DollorDriverColors.White,
                                strokeWidth = 2.dp
                            )
                        } else {
                            Text(
                                text = "Sign In",
                                style = MaterialTheme.typography.titleMedium.copy(
                                    fontWeight = FontWeight.Bold
                                )
                            )
                        }
                    }

                    Spacer(modifier = Modifier.height(16.dp))

                    // Divider
                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        verticalAlignment = Alignment.CenterVertically
                    ) {
                        HorizontalDivider(modifier = Modifier.weight(1f), color = DollorDriverColors.Gray300)
                        Text(
                            text = "  or  ",
                            style = MaterialTheme.typography.bodySmall,
                            color = DollorDriverColors.Gray500
                        )
                        HorizontalDivider(modifier = Modifier.weight(1f), color = DollorDriverColors.Gray300)
                    }

                    Spacer(modifier = Modifier.height(16.dp))

                    // Google Sign-In Button
                    OutlinedButton(
                        onClick = onGoogleSignInClick,
                        modifier = Modifier
                            .fillMaxWidth()
                            .height(56.dp),
                        shape = RoundedCornerShape(Lx.Radius.card),
                        colors = ButtonDefaults.outlinedButtonColors(
                            containerColor = Lx.Surface
                        ),
                        border = BorderStroke(1.dp, DollorDriverColors.Gray300),
                        enabled = !isLoading
                    ) {
                        Row(
                            horizontalArrangement = Arrangement.Center,
                            verticalAlignment = Alignment.CenterVertically
                        ) {
                            Text(
                                text = "G",
                                fontSize = Lx.FontSize.body,
                                fontWeight = FontWeight.Bold,
                                color = Lx.GoogleRed // Google Red
                            )
                            Spacer(modifier = Modifier.width(12.dp))
                            Text(
                                text = "Continue with Google",
                                style = MaterialTheme.typography.titleMedium.copy(
                                    fontWeight = FontWeight.Medium
                                ),
                                color = DollorDriverColors.Gray900
                            )
                        }
                    }

                    Spacer(modifier = Modifier.height(16.dp))

                    // Forgot Password
                    TextButton(
                        onClick = { showForgotPassword = true },
                        enabled = !isLoading
                    ) {
                        Text(
                            text = "Forgot Password?",
                            color = DollorDriverColors.Blue,
                            style = MaterialTheme.typography.bodyMedium
                        )
                    }
                }
            }

            // NOTE: Driver self-registration ("Apply to Drive") has no in-app flow
            // yet (no driver registration/onboarding screen exists in this module),
            // so the row is intentionally omitted rather than left as a dead button.
        }
    }

    if (showForgotPassword) {
        ForgotPasswordDialog(
            initialEmail = email,
            onDismiss = { showForgotPassword = false },
            onSubmit = onForgotPassword,
            onConfirm = onResetPassword
        )
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun ForgotPasswordDialog(
    initialEmail: String,
    onDismiss: () -> Unit,
    onSubmit: (email: String, onResult: (Boolean, String) -> Unit) -> Unit,
    onConfirm: (email: String, code: String, newPassword: String, onResult: (Boolean, String) -> Unit) -> Unit
) {
    var resetEmail by remember { mutableStateOf(initialEmail) }
    var code by remember { mutableStateOf("") }
    var newPassword by remember { mutableStateOf("") }
    var codeSent by remember { mutableStateOf(false) }
    var done by remember { mutableStateOf(false) }
    var isSubmitting by remember { mutableStateOf(false) }
    var resultMessage by remember { mutableStateOf<String?>(null) }

    AlertDialog(
        onDismissRequest = { if (!isSubmitting) onDismiss() },
        containerColor = Lx.Surface,
        title = { Text("Reset Password", color = Lx.Text) },
        text = {
            Column {
                Text(
                    text = when {
                        done -> "Your password has been updated."
                        codeSent -> "Enter the code we emailed you and choose a new password."
                        else -> "Enter your account email and we'll send a reset code."
                    },
                    style = MaterialTheme.typography.bodyMedium,
                    color = Lx.TextSecondary
                )
                if (!done) {
                    Spacer(modifier = Modifier.height(12.dp))
                    OutlinedTextField(
                        value = resetEmail,
                        onValueChange = { resetEmail = it },
                        label = { Text("Email") },
                        singleLine = true,
                        enabled = !isSubmitting && !codeSent,
                        keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Email),
                        modifier = Modifier.fillMaxWidth()
                    )
                }
                if (codeSent && !done) {
                    Spacer(modifier = Modifier.height(8.dp))
                    OutlinedTextField(
                        value = code,
                        onValueChange = { code = it.filter(Char::isDigit).take(8) },
                        label = { Text("Reset code") },
                        singleLine = true,
                        enabled = !isSubmitting,
                        keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.NumberPassword),
                        modifier = Modifier.fillMaxWidth()
                    )
                    Spacer(modifier = Modifier.height(8.dp))
                    OutlinedTextField(
                        value = newPassword,
                        onValueChange = { newPassword = it },
                        label = { Text("New password") },
                        singleLine = true,
                        enabled = !isSubmitting,
                        visualTransformation = androidx.compose.ui.text.input.PasswordVisualTransformation(),
                        keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Password),
                        modifier = Modifier.fillMaxWidth()
                    )
                }
                resultMessage?.let {
                    Spacer(modifier = Modifier.height(8.dp))
                    Text(text = it, style = MaterialTheme.typography.bodySmall, color = Lx.Orange)
                }
            }
        },
        confirmButton = {
            if (done) {
                TextButton(onClick = { onDismiss() }) { Text("Done", color = Lx.Orange) }
            } else {
                TextButton(
                    enabled = !isSubmitting && resetEmail.isNotBlank() && (!codeSent || (code.length >= 4 && newPassword.length >= 8)),
                    onClick = {
                        isSubmitting = true
                        resultMessage = null
                        if (!codeSent) {
                            onSubmit(resetEmail.trim()) { ok, message ->
                                isSubmitting = false
                                resultMessage = message
                                if (ok) codeSent = true
                            }
                        } else {
                            onConfirm(resetEmail.trim(), code, newPassword) { ok, message ->
                                isSubmitting = false
                                resultMessage = message
                                if (ok) done = true
                            }
                        }
                    }
                ) {
                    Text(
                        when {
                            isSubmitting -> "Working..."
                            codeSent -> "Reset password"
                            else -> "Send code"
                        },
                        color = Lx.Orange
                    )
                }
            }
        },
        dismissButton = {
            if (!done) TextButton(onClick = { onDismiss() }, enabled = !isSubmitting) { Text("Close", color = Lx.TextSecondary) }
        }
    )
}
