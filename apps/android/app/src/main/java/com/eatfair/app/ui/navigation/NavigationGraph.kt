package com.eatfair.app.ui.navigation

import android.app.Activity
import android.util.Log
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.platform.LocalContext
import androidx.hilt.lifecycle.viewmodel.compose.hiltViewModel
import androidx.lifecycle.viewmodel.compose.viewModel
import androidx.navigation.NavGraphBuilder
import androidx.navigation.NavHostController
import androidx.navigation.NavType
import androidx.navigation.compose.NavHost
import androidx.navigation.compose.composable
import androidx.navigation.compose.rememberNavController
import androidx.navigation.navArgument
import androidx.navigation.navigation
import com.google.android.gms.auth.api.signin.GoogleSignIn
import com.google.android.gms.auth.api.signin.GoogleSignInOptions
import com.google.android.gms.common.api.ApiException
import com.eatfair.shared.model.address.LocationData
import com.eatfair.app.ui.address.AddAddressDetailsScreen
import com.eatfair.app.ui.address.LocationMapScreen
import com.eatfair.app.ui.address.LocationViewModel
import com.eatfair.app.ui.address.SavedAddressesScreen
import com.eatfair.app.ui.auth.AuthState
import com.eatfair.app.ui.auth.AuthViewModel
import com.eatfair.app.ui.auth.EmailVerificationScreen
import com.eatfair.app.ui.auth.EmailVerificationState
import com.eatfair.app.ui.auth.ForgotPasswordScreen
import com.eatfair.app.ui.auth.LoginScreen
import com.eatfair.app.ui.auth.RegisterScreen
import com.eatfair.app.ui.auth.ResetCodeEntryScreen
import com.eatfair.app.ui.auth.LegalAcceptanceScreen
import com.eatfair.app.ui.notification.NotificationScreen
import com.eatfair.app.ui.notification.NotificationViewModel
import com.eatfair.app.ui.profile.EditProfileScreen
import com.eatfair.app.ui.profile.PrivacyPolicyScreen
import com.eatfair.app.ui.profile.ProfileScreen
import com.eatfair.app.ui.profile.ProfileViewModel
import com.eatfair.app.ui.profile.SettingsScreen
import com.eatfair.app.ui.profile.TermsConditionsScreen
import com.eatfair.shared.data.repository.DollorRepository
import com.eatfair.app.ui.refer.ReferAndEarnScreen
import com.eatfair.app.ui.rideshare.RideRequestScreen
import com.eatfair.app.ui.help.HelpSupportScreen
import com.eatfair.app.ui.main.MainScreen

@Composable
fun NavigationGraph(
//    innerPadding: PaddingValues,
    startDestination: String = "auth_flow"
) {
    val context = LocalContext.current

    val authViewModel: AuthViewModel = hiltViewModel()
    val authState = authViewModel.authState.collectAsState().value

    val profileViewModel: ProfileViewModel = hiltViewModel()

    val navController = rememberNavController()

    // Track previous auth state to detect login success
    var previousAuthState by remember { mutableStateOf<AuthState?>(null) }

    LaunchedEffect(authState) {
        when (authState) {
            is AuthState.Initial, AuthState.Loading -> {
                // Stay on splash/loading screen while the session check is ongoing
            }

            is AuthState.Authenticated -> {
                // Show success toast only when transitioning from Loading (actual login)
                if (previousAuthState is AuthState.Loading) {
                    android.widget.Toast.makeText(
                        context,
                        "Welcome back! You're now logged in.",
                        android.widget.Toast.LENGTH_SHORT
                    ).show()
                }
                // User logged in: Redirect to Main (with bottom tabs), clearing the back stack
                navController.navigate(Screen.Main.route) {
                    popUpTo(Screen.Login.route) { inclusive = true }
                    launchSingleTop = true
                }
            }

            AuthState.NeedsLegalAcceptance -> {
                // Navigate to legal acceptance screen
                navController.navigate(Screen.LegalAcceptance.route) {
                    popUpTo(Screen.Login.route) { inclusive = false }
                    launchSingleTop = true
                }
            }

            AuthState.UnAuthenticated -> {
                // User logged out: Redirect to Login, clearing back stack
                navController.navigate(Screen.Login.route) {
                    popUpTo(Screen.Login.route) { inclusive = false }
                    launchSingleTop = true
                }
            }

            is AuthState.Error -> {
                // Stay on login screen - error displayed via authState
            }
        }
        // Update previous state for next comparison
        previousAuthState = authState
    }

    NavHost(
        navController = navController,
        startDestination = startDestination
    ) {

        authGraph(navController, authViewModel)

        // Main Screen with Bottom Navigation (rideshare-only: Ride + Profile)
        composable(route = Screen.Main.route) {
            MainScreen(
                profileViewModel = profileViewModel,
                onRideChatClick = { rideRequestId, driverName ->
                    // Rideshare-only landing: open driver chat from the embedded ride screen
                    navController.navigate(Screen.DriverChat.createRoute(rideRequestId, driverName))
                },
                onEditProfileClick = {
                    navController.navigate(Screen.EditProfile.route)
                },
                onNotificationsClick = {
                    navController.navigate(Screen.Notifications.route)
                },
                onFoundingMemberClick = {
                    navController.navigate(Screen.FoundingMember.route)
                },
                onReferAndEarnClick = {
                    navController.navigate(Screen.ReferAndEarn.route)
                },
                onSavedAddressClick = {
                    navController.navigate(Screen.SavedAddressesScreen.route)
                },
                onSettingsClick = {
                    navController.navigate(Screen.Settings.route)
                },
                onHelpSupportClick = {
                    navController.navigate(Screen.HelpSupport.route)
                },
                onPaymentMethodClick = {
                    navController.navigate(Screen.PaymentMethods.route)
                },
                onWhatDriversSeeClick = {
                    navController.navigate(Screen.WhatDriversSee.route)
                },
                onYourPrivacyClick = {
                    navController.navigate(Screen.YourPrivacy.route)
                },
                onSafetyFeaturesClick = {
                    navController.navigate(Screen.SafetyFeatures.route)
                },
                onDeleteAccountClick = {
                    // Call delete account API - matches Settings screen behavior
                    authViewModel.deleteAccount(
                        onSuccess = {
                            // Account deleted, logout and navigate to welcome
                            authViewModel.logout()
                        },
                        onError = { error ->
                            // Log error but still logout for safety
                            android.util.Log.e("NavigationGraph", "Delete account failed: $error")
                            authViewModel.logout()
                        }
                    )
                },
                onLogoutClick = {
                    authViewModel.logout()
                }
            )
        }

        addressGraph(navController)

        rideshareGraph(navController)

        profileGraph(navController, authViewModel, profileViewModel)
    }
}

fun NavGraphBuilder.authGraph(navController: NavHostController, authViewModel: AuthViewModel) {
    navigation(
        startDestination = Screen.Login.route,  // Skip WelcomeScreen, go directly to Login
        route = "auth_flow"
    ) {
        // WelcomeScreen removed - users go directly to LoginScreen with Apple/Google sign-in

        composable(route = Screen.SignUp.route) {
            RegisterScreen(
                onJoinClick = { email, password, name, phone, zipCode ->
                    // Handle sign up logic
                    // For now, navigate to login or main screen
                    // You can pass data to ViewModel here
                    Log.d("NavigationGraph", "Sign Up: $email, $name, $phone, $zipCode")

                    // After successful signup, navigate to login or main screen
                    navController.navigate(Screen.Login.route) {
                        popUpTo(Screen.Login.route) {
                            inclusive = false
                        }
                    }
                },
                onLoginClick = {
                    navController.navigate(Screen.Login.route) {
                        popUpTo(Screen.Login.route) {
                            inclusive = false
                        }
                    }
                }
            )
        }

        composable(route = Screen.Login.route) {
            val context = LocalContext.current
            val activity = context as? Activity

            // Google Sign-In configuration
            // Web Client ID is configured in local.properties: GOOGLE_WEB_CLIENT_ID=...
            val webClientId = com.eatfair.app.BuildConfig.GOOGLE_WEB_CLIENT_ID
            val isGoogleSignInConfigured = webClientId.isNotEmpty()

            // Only create GoogleSignInClient if Web Client ID is configured
            val googleSignInClient = remember(webClientId) {
                if (isGoogleSignInConfigured) {
                    val gso = GoogleSignInOptions.Builder(GoogleSignInOptions.DEFAULT_SIGN_IN)
                        .requestIdToken(webClientId)
                        .requestEmail()
                        .build()
                    GoogleSignIn.getClient(context, gso)
                } else {
                    null
                }
            }

            // Google Sign-In launcher
            val googleSignInLauncher = rememberLauncherForActivityResult(
                contract = ActivityResultContracts.StartActivityForResult()
            ) { result ->
                if (result.resultCode == Activity.RESULT_OK) {
                    val task = GoogleSignIn.getSignedInAccountFromIntent(result.data)
                    try {
                        val account = task.getResult(ApiException::class.java)
                        val idToken = account?.idToken
                        val email = account?.email ?: ""
                        val name = account?.displayName ?: ""

                        if (idToken != null) {
                            Log.d("NavigationGraph", "Google Sign In success: $email")
                            authViewModel.googleSignIn(idToken, email, name)
                        } else {
                            Log.e("NavigationGraph", "Google Sign In: No ID token received")
                            android.widget.Toast.makeText(context, "Sign in failed: No token received", android.widget.Toast.LENGTH_SHORT).show()
                        }
                    } catch (e: ApiException) {
                        Log.e("NavigationGraph", "Google Sign In failed: ${e.statusCode}", e)
                        android.widget.Toast.makeText(context, "Sign in failed: ${e.message}", android.widget.Toast.LENGTH_SHORT).show()
                    }
                } else {
                    Log.d("NavigationGraph", "Google Sign In cancelled")
                }
            }

            val currentAuthState by authViewModel.authState.collectAsState()
            val isLoading = currentAuthState is AuthState.Loading
            val errorMessage = (currentAuthState as? AuthState.Error)?.message

            // Track if signup was just completed to show success toast
            var justSignedUp by remember { mutableStateOf(false) }

            // Show success toast when signup completes
            LaunchedEffect(currentAuthState) {
                if (justSignedUp && currentAuthState is AuthState.NeedsLegalAcceptance) {
                    android.widget.Toast.makeText(
                        context,
                        "Account created successfully! Welcome to Dollor.ai",
                        android.widget.Toast.LENGTH_LONG
                    ).show()
                    justSignedUp = false
                }
            }

            LoginScreen(
                onLoginClick = { email, password ->
                    // Handle login logic
                    Log.d("NavigationGraph", "Login: $email")
                    authViewModel.login(email, password)
                },
                onSignUpClick = { email, password, fullName, phone ->
                    // Handle sign up logic
                    Log.d("NavigationGraph", "SignUp: $email, $fullName")
                    justSignedUp = true
                    authViewModel.signUp(email, password, fullName, phone, "")
                },
                isLoading = isLoading,
                errorMessage = errorMessage,
                onGoogleSignInClick = {
                    if (googleSignInClient != null) {
                        // Launch Google Sign-In
                        Log.d("NavigationGraph", "Starting Google Sign In")
                        googleSignInLauncher.launch(googleSignInClient.signInIntent)
                    } else {
                        // Google Sign-In not configured
                        Log.w("NavigationGraph", "Google Sign-In not configured: Missing GOOGLE_WEB_CLIENT_ID")
                        android.widget.Toast.makeText(context, "Google Sign-In coming soon!", android.widget.Toast.LENGTH_SHORT).show()
                    }
                },
                onForgotPasswordClick = {
                    Log.d("NavigationGraph", "Navigating to Forgot Password")
                    navController.navigate(Screen.ForgotPassword.route)
                },
                onTermsClick = {
                    navController.navigate(Screen.TermsConditions.route)
                },
                onPrivacyClick = {
                    navController.navigate(Screen.PrivacyPolicy.route)
                }
            )
        }

        composable(route = Screen.LegalAcceptance.route) {
            LegalAcceptanceScreen(
                onAccept = {
                    authViewModel.acceptTermsAndPrivacy()
                }
            )
        }

        // Email Verification Screen
        composable(route = Screen.EmailVerification.route) {
            val context = LocalContext.current
            val emailVerificationState by authViewModel.emailVerificationState.collectAsState()
            var customerEmail by remember { mutableStateOf("") }
            var isEmailVerified by remember { mutableStateOf(false) }

            // Get email verification status on load
            LaunchedEffect(Unit) {
                authViewModel.getEmailVerificationStatus { verified, email ->
                    isEmailVerified = verified
                    customerEmail = email
                }
            }

            EmailVerificationScreen(
                email = customerEmail,
                isVerified = isEmailVerified || emailVerificationState is EmailVerificationState.Verified || emailVerificationState is EmailVerificationState.AlreadyVerified,
                onSendCodeClick = {
                    authViewModel.sendEmailVerificationCode { success ->
                        if (success) {
                            android.widget.Toast.makeText(
                                context,
                                "Verification code sent!",
                                android.widget.Toast.LENGTH_SHORT
                            ).show()
                        }
                    }
                },
                onVerifyCodeClick = { code ->
                    authViewModel.verifyEmail(code) { success ->
                        if (success) {
                            android.widget.Toast.makeText(
                                context,
                                "Email verified successfully!",
                                android.widget.Toast.LENGTH_LONG
                            ).show()
                        }
                    }
                },
                onBackClick = {
                    navController.popBackStack()
                },
                onSkipClick = {
                    navController.navigate(Screen.Main.route) {
                        popUpTo(Screen.Login.route) { inclusive = true }
                    }
                },
                isSendingCode = emailVerificationState is EmailVerificationState.SendingCode,
                isVerifying = emailVerificationState is EmailVerificationState.Verifying,
                errorMessage = (emailVerificationState as? EmailVerificationState.Error)?.message,
                successMessage = (emailVerificationState as? EmailVerificationState.CodeSent)?.message
            )
        }

        // Forgot Password Screen - Matches iOS ForgotPasswordView
        composable(route = Screen.ForgotPassword.route) {
            val isLoading by authViewModel.isLoadingState.collectAsState()
            val errorMessage by authViewModel.errorMessageState.collectAsState()

            ForgotPasswordScreen(
                onSendCodeClick = { email ->
                    authViewModel.requestPasswordReset(email) { success ->
                        if (success) {
                            navController.navigate(Screen.ResetCodeEntry.createRoute(email))
                        }
                    }
                },
                onCancelClick = {
                    navController.navigateUp()
                },
                isLoading = isLoading,
                errorMessage = errorMessage
            )
        }

        // Reset Code Entry Screen - Matches iOS ResetCodeEntryView
        composable(
            route = Screen.ResetCodeEntry.route,
            arguments = listOf(
                navArgument("email") { type = NavType.StringType; defaultValue = "" }
            )
        ) { backStackEntry ->
            val email = backStackEntry.arguments?.getString("email") ?: ""
            val isLoading by authViewModel.isLoadingState.collectAsState()
            val errorMessage by authViewModel.errorMessageState.collectAsState()

            ResetCodeEntryScreen(
                email = email,
                onResetPasswordClick = { code, newPassword ->
                    authViewModel.confirmPasswordReset(email, code, newPassword) { success ->
                        if (success) {
                            android.widget.Toast.makeText(
                                navController.context,
                                "Password reset successfully! Please login.",
                                android.widget.Toast.LENGTH_SHORT
                            ).show()
                            navController.navigate(Screen.Login.route) {
                                popUpTo(Screen.Login.route) { inclusive = false }
                            }
                        }
                    }
                },
                onCancelClick = {
                    navController.navigate(Screen.Login.route) {
                        popUpTo(Screen.Login.route) { inclusive = false }
                    }
                },
                isLoading = isLoading,
                errorMessage = errorMessage
            )
        }

    }
}

fun NavGraphBuilder.addressGraph(navController: NavHostController) {
    navigation(
        startDestination = Screen.LocationMap.route,
        route = "address_flow"
    ) {

        composable(route = Screen.LocationMap.route) { backStackEntry ->

            val parentEntry = remember(backStackEntry) {
                navController.getBackStackEntry("address_flow")
            }

            val locationViewModel: LocationViewModel = hiltViewModel(parentEntry)

            LocationMapScreen(
                locationViewModel = locationViewModel,
                onBackClick = { navController.navigateUp() },
                onConfirmLocation = { locationData ->
                    navController.currentBackStackEntry?.savedStateHandle?.set(
                        "location", locationData
                    )
                    navController.navigate(Screen.AddAddressDetailsScreen.route)
                }
            )
        }

        composable(route = Screen.AddAddressDetailsScreen.route) { backStackEntry ->

            val parentEntry = remember(backStackEntry) {
                navController.getBackStackEntry("address_flow")
            }

            val locationViewModel: LocationViewModel = hiltViewModel(parentEntry)

            val location = navController.previousBackStackEntry
                ?.savedStateHandle?.get<LocationData>("location")

            val addressIdToEdit =
                backStackEntry.arguments?.getString("addressId")?.toIntOrNull() ?: 0

            if (location != null || addressIdToEdit != 0) {
                AddAddressDetailsScreen(
                    location = location,
                    addressId = addressIdToEdit,
                    locationViewModel = locationViewModel,
                    onBackClick = { navController.navigateUp() },
                    onSaveAddress = {
                        navController.navigateUp()
                    }
                )
            }
        }

        composable(route = Screen.SavedAddressesScreen.route) { backStackEntry ->

            val parentEntry = remember(backStackEntry) {
                navController.getBackStackEntry("address_flow")
            }

            val locationViewModel: LocationViewModel = hiltViewModel(parentEntry)

            SavedAddressesScreen(
                locationViewModel = locationViewModel,
                onBackClick = { navController.navigateUp() },
                onAddAddressClick = {
                    navController.navigate(Screen.LocationMap.route)
                },
                onEditAddress = { addressDto ->
                    navController.navigate(
                        Screen.AddAddressDetailsScreen.createRoute(addressDto.id)
                    )
                },
            )
        }
    }
}

fun NavGraphBuilder.profileGraph(
    navController: NavHostController,
    authViewModel: AuthViewModel,
    profileViewModel: ProfileViewModel,
    dollorRepository: DollorRepository? = null
) {
    navigation(
        startDestination = Screen.Login.route,
        route = "profile_flow"
    ) {
        composable(route = Screen.Profile.route) {
            ProfileScreen(
                profileViewModel = profileViewModel,
                onBackClick = { navController.navigateUp() },
                onEditProfileClick = { navController.navigate(Screen.EditProfile.route) },
                onNotificationsClick = { navController.navigate(Screen.Notifications.route) },
                onReferAndEarnClick = { navController.navigate(Screen.ReferAndEarn.route) },
                onSavedAddressClick = { navController.navigate(Screen.SavedAddressesScreen.route) },
                onSettingsClick = { navController.navigate(Screen.Settings.route) },
                onPaymentMethodClick = { navController.navigate(Screen.PaymentMethods.route) },
                onHelpSupportClick = { navController.navigate(Screen.HelpSupport.route) },
                onWhatDriversSeeClick = { navController.navigate(Screen.WhatDriversSee.route) },
                onYourPrivacyClick = { navController.navigate(Screen.YourPrivacy.route) },
                onSafetyFeaturesClick = { navController.navigate(Screen.SafetyFeatures.route) },
                onDeleteAccountClick = {
                    // Delete account handled in ProfileScreen dialog, then logout
                    authViewModel.deleteAccount(
                        onSuccess = { authViewModel.logout() },
                        onError = { /* Error already shown in ProfileScreen */ }
                    )
                },
                onFoundingMemberClick = { navController.navigate(Screen.FoundingMember.route) },
                onLogoutClick = { authViewModel.logout() }
            )
        }

        composable(route = Screen.FoundingMember.route) {
            com.eatfair.app.ui.founding.FoundingMemberScreen(
                onBackClick = { navController.navigateUp() }
            )
        }

        composable(Screen.EditProfile.route) {
            val profileName by profileViewModel.userNameFlow.collectAsState(initial = "")
            val profileEmail by profileViewModel.userEmailFlow.collectAsState(initial = "")
            EditProfileScreen(
                userName = profileName ?: "",
                userEmail = profileEmail ?: "",
                onBackClick = { navController.navigateUp() },
                onSave = { name, onResult -> profileViewModel.saveName(name, onResult) }
            )
        }

        composable(Screen.Notifications.route) {
            val notificationViewModel: NotificationViewModel = hiltViewModel()
            val notifications by notificationViewModel.notifications.collectAsState()

            NotificationScreen(
                notifications = notifications,
                onBackClick = { navController.navigateUp() },
                onNotificationClick = { notification ->
                    // Mark as read
                    notificationViewModel.markAsRead(notification.id)
                },
                onClearAllClick = {
                    // Clear all notifications via API
                    notificationViewModel.clearAllNotifications()
                }
            )
        }

        composable(Screen.ReferAndEarn.route) {
            val ctx = LocalContext.current
            val code = "DOLLOR" + (com.eatfair.app.data.CustomerRideshareApiService.currentCustomerId?.toString() ?: "")
            ReferAndEarnScreen(
                referralCode = code,
                onBackClick = { navController.navigateUp() },
                onShareClick = {
                    val send = android.content.Intent(android.content.Intent.ACTION_SEND).apply {
                        type = "text/plain"
                        putExtra(
                            android.content.Intent.EXTRA_TEXT,
                            "Join me on Dollor.ai! Use my code $code to get \$5 off your first ride. Download now: https://dollor.ai/app"
                        )
                    }
                    ctx.startActivity(android.content.Intent.createChooser(send, "Share your code"))
                },
                onCopyCodeClick = {
                    val clipboard = ctx.getSystemService(android.content.Context.CLIPBOARD_SERVICE) as android.content.ClipboardManager
                    clipboard.setPrimaryClip(android.content.ClipData.newPlainText("Dollor referral code", code))
                }
            )
        }

        // Settings Screen - Required for Google Play Store compliance
        composable(Screen.Settings.route) {
            val settingsContext = LocalContext.current
            val emailVerificationState by authViewModel.emailVerificationState.collectAsState()
            var isEmailVerified by remember { mutableStateOf(false) }

            // Check email verification status on load
            LaunchedEffect(Unit) {
                authViewModel.getEmailVerificationStatus { verified, _ ->
                    isEmailVerified = verified
                }
            }

            // Update when verification state changes
            LaunchedEffect(emailVerificationState) {
                if (emailVerificationState is EmailVerificationState.Verified ||
                    emailVerificationState is EmailVerificationState.AlreadyVerified) {
                    isEmailVerified = true
                }
            }

            SettingsScreen(
                onBackClick = { navController.navigateUp() },
                onPrivacyPolicyClick = { navController.navigate(Screen.PrivacyPolicy.route) },
                onTermsClick = { navController.navigate(Screen.TermsConditions.route) },
                onEmailVerificationClick = { navController.navigate(Screen.EmailVerification.route) },
                onCaliforniaPrivacyClick = {
                    // Open the public privacy policy page (covers CCPA/CPRA rights)
                    val intent = android.content.Intent(
                        android.content.Intent.ACTION_VIEW,
                        android.net.Uri.parse(com.eatfair.shared.config.AppConfig.Legal.PRIVACY_POLICY_URL)
                    )
                    try {
                        settingsContext.startActivity(intent)
                    } catch (e: android.content.ActivityNotFoundException) {
                        android.widget.Toast.makeText(
                            settingsContext,
                            "No browser app found",
                            android.widget.Toast.LENGTH_SHORT
                        ).show()
                    }
                },
                isEmailVerified = isEmailVerified,
                onDeleteAccount = { onSuccess, onError ->
                    authViewModel.deleteAccount(onSuccess, onError)
                },
                onAccountDeleted = {
                    // Navigate back to welcome screen after account deletion
                    navController.navigate(Screen.Login.route) {
                        popUpTo(0) { inclusive = true }
                    }
                }
            )
        }

        // Privacy Policy Screen
        composable(Screen.PrivacyPolicy.route) {
            PrivacyPolicyScreen(
                onBackClick = { navController.navigateUp() }
            )
        }

        // Terms & Conditions Screen
        composable(Screen.TermsConditions.route) {
            TermsConditionsScreen(
                onBackClick = { navController.navigateUp() }
            )
        }

        // Help & Support Screen
        composable(Screen.HelpSupport.route) {
            val ctx = LocalContext.current
            HelpSupportScreen(
                onBackClick = { navController.navigateUp() },
                onContactSupport = {
                    val mail = android.content.Intent(android.content.Intent.ACTION_SENDTO, android.net.Uri.parse("mailto:support@dollor.ai"))
                        .putExtra(android.content.Intent.EXTRA_SUBJECT, "Dollor.ai Support")
                    runCatching { ctx.startActivity(mail) }.onFailure {
                        android.widget.Toast.makeText(ctx, "Email us at support@dollor.ai", android.widget.Toast.LENGTH_LONG).show()
                    }
                },
                onChatWithUs = { navController.navigate("support_chat") },
                onCallSupport = {
                    ctx.startActivity(android.content.Intent(android.content.Intent.ACTION_DIAL, android.net.Uri.parse("tel:+18003655671")))
                }
            )
        }

        composable("support_chat") {
            com.eatfair.app.ui.help.SupportChatScreen(onBackClick = { navController.navigateUp() })
        }

        // Payment Methods Screen
        composable(Screen.PaymentMethods.route) {
            com.eatfair.app.ui.payment.PaymentMethodsScreen(
                onBackClick = { navController.navigateUp() }
            )
        }

        // Privacy & Safety Screens - Uber Eats style transparency
        composable(Screen.WhatDriversSee.route) {
            com.eatfair.app.ui.privacy.WhatDriversSeePage(
                onBackClick = { navController.navigateUp() }
            )
        }

        composable(Screen.YourPrivacy.route) {
            com.eatfair.app.ui.privacy.YourPrivacyPage(
                onBackClick = { navController.navigateUp() }
            )
        }

        composable(Screen.SafetyFeatures.route) {
            com.eatfair.app.ui.privacy.SafetyFeaturesPage(
                onBackClick = { navController.navigateUp() }
            )
        }
    }
}

fun NavGraphBuilder.rideshareGraph(navController: NavHostController) {
    navigation(
        // Start directly at RideRequest - matches iOS RideRequestView
        startDestination = Screen.RideRequest.route,
        route = "rideshare_flow"
    ) {
        // Ride Request - Request a ride with P2P bidding (START DESTINATION - matches iOS)
        composable(route = Screen.RideRequest.route) {
            com.eatfair.app.ui.rideshare.RideRequestScreen(
                onBackClick = { navController.navigateUp() },
                onNavigateToActiveRide = { rideRequestId ->
                    // Navigate to ride tracking
                },
                onNavigateToChat = { rideRequestId, driverName ->
                    navController.navigate(Screen.DriverChat.createRoute(rideRequestId, driverName))
                }
            )
        }

        // Driver Chat - Chat with driver during active ride
        composable(
            route = Screen.DriverChat.route,
            arguments = listOf(
                navArgument("rideRequestId") { type = NavType.IntType },
                navArgument("driverName") { type = NavType.StringType }
            )
        ) { backStackEntry ->
            val rideRequestId = backStackEntry.arguments?.getInt("rideRequestId") ?: 0
            val driverName = backStackEntry.arguments?.getString("driverName") ?: "Driver"
            val decodedName = java.net.URLDecoder.decode(driverName, "UTF-8")

            com.eatfair.app.ui.rideshare.DriverChatScreen(
                rideRequestId = rideRequestId,
                driverName = decodedName,
                onNavigateBack = { navController.navigateUp() }
            )
        }
    }
}

