package com.eatfair.app.ui.auth

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.filled.Email
import androidx.compose.material.icons.filled.Lock
import androidx.compose.material.icons.filled.Person
import androidx.compose.material.icons.filled.Phone
import androidx.compose.material.icons.filled.LocationOn
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.tooling.preview.Preview
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.eatfair.app.ui.components.DollorLogo
import com.eatfair.app.ui.components.DollorBrandColors

// Enterprise Brand Colors
private val PrimaryOrange = DollorBrandColors.PrimaryOrange
private val DarkOrange = DollorBrandColors.DarkOrange
private val TextPrimary = Color(0xFF1A1A2E)
private val TextSecondary = Color(0xFF6B7280)
private val BorderColor = Color(0xFFE5E7EB)
private val BackgroundWhite = Color(0xFFFFFFFF)
private val BackgroundLight = Color(0xFFFFF7ED)
private val SuccessGreen = Color(0xFF10B981)

@Preview(showBackground = true)
@Composable
fun RegisterScreenPreview() {
    RegisterScreen(
        onJoinClick = { _, _, _, _, _ -> },
        onLoginClick = { }
    )
}

@Composable
fun RegisterScreen(
    onJoinClick: (email: String, password: String, name: String, phone: String, zipCode: String) -> Unit,
    onLoginClick: () -> Unit,
    isLoading: Boolean = false,
    errorMessage: String? = null
) {
    var email by remember { mutableStateOf("") }
    var password by remember { mutableStateOf("") }
    var name by remember { mutableStateOf("") }
    var phoneNumber by remember { mutableStateOf("") }
    var zipCode by remember { mutableStateOf("") }

    var emailError by remember { mutableStateOf<String?>(null) }
    var passwordError by remember { mutableStateOf<String?>(null) }
    var nameError by remember { mutableStateOf<String?>(null) }
    var phoneError by remember { mutableStateOf<String?>(null) }
    var zipCodeError by remember { mutableStateOf<String?>(null) }

    fun validateEmail(email: String): String? {
        return when {
            email.isBlank() -> "Email is required"
            !android.util.Patterns.EMAIL_ADDRESS.matcher(email).matches() -> "Please enter a valid email address"
            else -> null
        }
    }

    fun validatePassword(password: String): String? {
        return when {
            password.isBlank() -> "Password is required"
            password.length < 8 -> "Password must be at least 8 characters"
            !password.any { it.isUpperCase() } -> "Password must contain an uppercase letter"
            !password.any { it.isDigit() } -> "Password must contain a number"
            else -> null
        }
    }

    fun validateName(name: String): String? {
        return when {
            name.isBlank() -> "Full name is required"
            name.length < 2 -> "Name must be at least 2 characters"
            !name.contains(" ") -> "Please enter your full name"
            else -> null
        }
    }

    fun validatePhone(phone: String): String? {
        val digits = phone.replace(Regex("[^0-9]"), "")
        return when {
            phone.isBlank() -> "Phone number is required"
            digits.length < 10 -> "Please enter a valid 10-digit phone number"
            else -> null
        }
    }

    fun validateZipCode(zipCode: String): String? {
        return when {
            zipCode.isBlank() -> "ZIP code is required"
            zipCode.length != 5 || !zipCode.all { it.isDigit() } -> "Please enter a valid 5-digit ZIP code"
            else -> null
        }
    }

    fun validateAndRegister() {
        emailError = validateEmail(email)
        passwordError = validatePassword(password)
        nameError = validateName(name)
        phoneError = validatePhone(phoneNumber)
        zipCodeError = validateZipCode(zipCode)

        if (emailError == null && passwordError == null && nameError == null &&
            phoneError == null && zipCodeError == null) {
            onJoinClick(email, password, name, phoneNumber, zipCode)
        }
    }

    Box(
        modifier = Modifier
            .fillMaxSize()
            .background(BackgroundWhite)
            .systemBarsPadding()
    ) {
        Column(
            modifier = Modifier
                .fillMaxSize()
                .verticalScroll(rememberScrollState())
        ) {
            // Hero Section with Mission Statement
            Box(
                modifier = Modifier
                    .fillMaxWidth()
                    .background(
                        brush = Brush.verticalGradient(
                            colors = listOf(PrimaryOrange, DarkOrange)
                        )
                    )
                    .padding(vertical = 32.dp, horizontal = 24.dp)
            ) {
                Column(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalAlignment = Alignment.CenterHorizontally
                ) {
                    // Logo
                    DollorLogo(
                        size = 56.dp,
                        backgroundColor = Color.White,
                        contentColor = PrimaryOrange
                    )

                    Spacer(modifier = Modifier.height(16.dp))

                    Text(
                        text = "Join the Fair Economy",
                        fontSize = 26.sp,
                        fontWeight = FontWeight.Bold,
                        color = Color.White,
                        textAlign = TextAlign.Center
                    )

                    Spacer(modifier = Modifier.height(8.dp))

                    Text(
                        text = "We're building a platform where everyone wins.\n100% of your payment goes directly to drivers.",
                        fontSize = 15.sp,
                        color = Color.White.copy(alpha = 0.95f),
                        textAlign = TextAlign.Center,
                        lineHeight = 22.sp
                    )

                    Spacer(modifier = Modifier.height(20.dp))

                    // Mission Highlights
                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        horizontalArrangement = Arrangement.SpaceEvenly
                    ) {
                        MissionHighlight(value = "$1", label = "Platform Fee")
                        MissionHighlight(value = "0%", label = "Commission")
                        MissionHighlight(value = "100%", label = "Tips to Drivers")
                    }
                }
            }

            // Form Section
            Column(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(24.dp)
            ) {
                Text(
                    text = "Create Your Account",
                    fontSize = 22.sp,
                    fontWeight = FontWeight.Bold,
                    color = TextPrimary
                )

                Spacer(modifier = Modifier.height(4.dp))

                Text(
                    text = "Book your first ride in minutes",
                    fontSize = 14.sp,
                    color = TextSecondary
                )

                Spacer(modifier = Modifier.height(24.dp))

                // Form Fields
                RegisterTextField(
                    value = name,
                    onValueChange = { name = it; nameError = null },
                    label = "Full Name",
                    placeholder = "John Smith",
                    icon = Icons.Default.Person,
                    error = nameError,
                    keyboardType = KeyboardType.Text
                )

                Spacer(modifier = Modifier.height(16.dp))

                RegisterTextField(
                    value = email,
                    onValueChange = { email = it; emailError = null },
                    label = "Email Address",
                    placeholder = "john@example.com",
                    icon = Icons.Default.Email,
                    error = emailError,
                    keyboardType = KeyboardType.Email
                )

                Spacer(modifier = Modifier.height(16.dp))

                RegisterTextField(
                    value = phoneNumber,
                    onValueChange = { phoneNumber = it; phoneError = null },
                    label = "Phone Number",
                    placeholder = "(555) 123-4567",
                    icon = Icons.Default.Phone,
                    error = phoneError,
                    keyboardType = KeyboardType.Phone
                )

                Spacer(modifier = Modifier.height(16.dp))

                RegisterTextField(
                    value = zipCode,
                    onValueChange = { zipCode = it; zipCodeError = null },
                    label = "ZIP Code",
                    placeholder = "82001",
                    icon = Icons.Default.LocationOn,
                    error = zipCodeError,
                    keyboardType = KeyboardType.Number
                )

                Spacer(modifier = Modifier.height(16.dp))

                RegisterTextField(
                    value = password,
                    onValueChange = { password = it; passwordError = null },
                    label = "Password",
                    placeholder = "Min 8 chars, 1 uppercase, 1 number",
                    icon = Icons.Default.Lock,
                    error = passwordError,
                    keyboardType = KeyboardType.Password,
                    isPassword = true
                )

                // Error Message
                errorMessage?.let { error ->
                    Spacer(modifier = Modifier.height(16.dp))
                    Text(
                        text = error,
                        fontSize = 14.sp,
                        color = Color(0xFFEF4444),
                        textAlign = TextAlign.Center,
                        modifier = Modifier.fillMaxWidth()
                    )
                }

                Spacer(modifier = Modifier.height(24.dp))

                // Why Join Card
                Card(
                    modifier = Modifier.fillMaxWidth(),
                    colors = CardDefaults.cardColors(containerColor = BackgroundLight),
                    shape = RoundedCornerShape(16.dp),
                    elevation = CardDefaults.cardElevation(defaultElevation = 0.dp)
                ) {
                    Column(
                        modifier = Modifier.padding(20.dp)
                    ) {
                        Text(
                            text = "Our Mission",
                            fontSize = 18.sp,
                            fontWeight = FontWeight.Bold,
                            color = TextPrimary
                        )

                        Spacer(modifier = Modifier.height(4.dp))

                        Text(
                            text = "Fair pricing for everyone in the rideshare ecosystem",
                            fontSize = 13.sp,
                            color = TextSecondary
                        )

                        Spacer(modifier = Modifier.height(16.dp))

                        MissionBenefit(
                            text = "No hidden fees or surge pricing"
                        )
                        MissionBenefit(
                            text = "Drivers receive 100% of fares & tips"
                        )
                        MissionBenefit(
                            text = "You pay only a flat \$1 platform fee"
                        )
                    }
                }

                Spacer(modifier = Modifier.height(24.dp))

                // Register Button
                Button(
                    onClick = { validateAndRegister() },
                    modifier = Modifier
                        .fillMaxWidth()
                        .height(54.dp),
                    colors = ButtonDefaults.buttonColors(containerColor = PrimaryOrange),
                    shape = RoundedCornerShape(12.dp),
                    enabled = !isLoading
                ) {
                    if (isLoading) {
                        CircularProgressIndicator(
                            color = Color.White,
                            modifier = Modifier.size(22.dp),
                            strokeWidth = 2.dp
                        )
                    } else {
                        Text(
                            text = "Create Account",
                            fontSize = 17.sp,
                            fontWeight = FontWeight.SemiBold,
                            color = Color.White
                        )
                    }
                }

                Spacer(modifier = Modifier.height(16.dp))

                // Terms
                Text(
                    text = "By creating an account, you agree to our Terms of Service and Privacy Policy. We'll send you a confirmation email.",
                    fontSize = 12.sp,
                    color = TextSecondary,
                    textAlign = TextAlign.Center,
                    lineHeight = 18.sp,
                    modifier = Modifier.fillMaxWidth()
                )

                Spacer(modifier = Modifier.height(24.dp))

                // Login Link
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.Center,
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    Text(
                        text = "Already have an account?",
                        fontSize = 15.sp,
                        color = TextSecondary
                    )
                    TextButton(
                        onClick = onLoginClick,
                        contentPadding = PaddingValues(horizontal = 8.dp)
                    ) {
                        Text(
                            text = "Sign In",
                            fontSize = 15.sp,
                            color = PrimaryOrange,
                            fontWeight = FontWeight.SemiBold
                        )
                    }
                }

                Spacer(modifier = Modifier.height(16.dp))
            }
        }
    }
}

@Composable
private fun MissionHighlight(value: String, label: String) {
    Column(
        horizontalAlignment = Alignment.CenterHorizontally
    ) {
        Box(
            modifier = Modifier
                .size(52.dp)
                .clip(CircleShape)
                .background(Color.White.copy(alpha = 0.2f))
                .border(2.dp, Color.White.copy(alpha = 0.4f), CircleShape),
            contentAlignment = Alignment.Center
        ) {
            Text(
                text = value,
                fontSize = 16.sp,
                fontWeight = FontWeight.Bold,
                color = Color.White
            )
        }
        Spacer(modifier = Modifier.height(6.dp))
        Text(
            text = label,
            fontSize = 12.sp,
            color = Color.White.copy(alpha = 0.9f),
            fontWeight = FontWeight.Medium
        )
    }
}

@Composable
private fun RegisterTextField(
    value: String,
    onValueChange: (String) -> Unit,
    label: String,
    placeholder: String,
    icon: ImageVector,
    error: String?,
    keyboardType: KeyboardType,
    isPassword: Boolean = false
) {
    Column {
        Text(
            text = label,
            fontSize = 14.sp,
            fontWeight = FontWeight.Medium,
            color = TextPrimary
        )
        Spacer(modifier = Modifier.height(6.dp))
        OutlinedTextField(
            value = value,
            onValueChange = onValueChange,
            modifier = Modifier.fillMaxWidth(),
            placeholder = {
                Text(
                    text = placeholder,
                    color = TextSecondary.copy(alpha = 0.6f)
                )
            },
            leadingIcon = {
                Icon(
                    imageVector = icon,
                    contentDescription = null,
                    tint = if (error != null) Color(0xFFEF4444) else TextSecondary
                )
            },
            visualTransformation = if (isPassword) PasswordVisualTransformation() else androidx.compose.ui.text.input.VisualTransformation.None,
            keyboardOptions = KeyboardOptions(keyboardType = keyboardType),
            shape = RoundedCornerShape(10.dp),
            isError = error != null,
            singleLine = true,
            colors = OutlinedTextFieldDefaults.colors(
                focusedTextColor = TextPrimary,
                unfocusedTextColor = TextPrimary,
                cursorColor = PrimaryOrange,
                focusedContainerColor = BackgroundWhite,
                unfocusedContainerColor = BackgroundWhite,
                errorContainerColor = Color(0xFFFEF2F2),
                focusedBorderColor = PrimaryOrange,
                unfocusedBorderColor = BorderColor,
                errorBorderColor = Color(0xFFEF4444)
            )
        )
        if (error != null) {
            Spacer(modifier = Modifier.height(4.dp))
            Text(
                text = error,
                fontSize = 12.sp,
                color = Color(0xFFEF4444)
            )
        }
    }
}

@Composable
private fun MissionBenefit(text: String) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .padding(vertical = 6.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        Icon(
            imageVector = Icons.Default.CheckCircle,
            contentDescription = null,
            tint = SuccessGreen,
            modifier = Modifier.size(20.dp)
        )
        Spacer(modifier = Modifier.width(12.dp))
        Text(
            text = text,
            fontSize = 14.sp,
            color = TextPrimary,
            fontWeight = FontWeight.Medium
        )
    }
}

