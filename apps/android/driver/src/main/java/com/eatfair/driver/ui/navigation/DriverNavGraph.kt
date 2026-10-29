package com.eatfair.driver.ui.navigation

import android.app.Activity
import android.util.Log
import android.widget.Toast
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.AttachMoney
import androidx.compose.material.icons.filled.DirectionsCar
import androidx.compose.material.icons.filled.Home
import androidx.compose.material.icons.filled.Person
import androidx.compose.material.icons.outlined.AttachMoney
import androidx.compose.material.icons.outlined.DirectionsCar
import androidx.compose.material.icons.outlined.Home
import androidx.compose.material.icons.outlined.Person
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.NavigationBar
import androidx.compose.material3.NavigationBarItem
import androidx.compose.material3.NavigationBarItemDefaults
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.LocalContext
import androidx.hilt.navigation.compose.hiltViewModel
import androidx.navigation.NavHostController
import androidx.navigation.compose.NavHost
import androidx.navigation.compose.composable
import androidx.navigation.compose.currentBackStackEntryAsState
import androidx.navigation.compose.rememberNavController
import com.eatfair.driver.BuildConfig
import com.eatfair.driver.ui.auth.LoginScreen
import com.eatfair.driver.ui.auth.LoginState
import com.eatfair.driver.ui.auth.LoginViewModel
import com.eatfair.driver.ui.compliance.BackgroundCheckConsentScreen
import com.eatfair.driver.ui.compliance.IndependentContractorAgreementScreen
import com.eatfair.driver.ui.compliance.InsuranceDisclosureScreen
import com.eatfair.driver.ui.compliance.VehicleRequirementsScreen
import com.eatfair.driver.ui.earnings.EarningsScreen
import com.eatfair.driver.ui.home.DriverHomeScreen
import com.eatfair.driver.ui.orders.AvailableOrdersScreen
import com.eatfair.driver.ui.profile.ProfileScreen
import com.eatfair.shared.ui.LegalAcceptanceScreen
import com.google.android.gms.auth.api.signin.GoogleSignIn
import com.google.android.gms.auth.api.signin.GoogleSignInOptions
import com.google.android.gms.common.api.ApiException

sealed class DriverScreen(
    val route: String,
    val title: String,
    val selectedIcon: ImageVector,
    val unselectedIcon: ImageVector
) {
    object Home : DriverScreen("home", "Home", Icons.Filled.Home, Icons.Outlined.Home)
    object Orders : DriverScreen("orders", "Rides", Icons.Filled.DirectionsCar, Icons.Outlined.DirectionsCar)
    object Earnings : DriverScreen("earnings", "Earnings", Icons.Filled.AttachMoney, Icons.Outlined.AttachMoney)
    object Profile : DriverScreen("profile", "Profile", Icons.Filled.Person, Icons.Outlined.Person)
}

val bottomNavItems = listOf(
    DriverScreen.Home,
    DriverScreen.Orders,
    DriverScreen.Earnings,
    DriverScreen.Profile
)

/**
 * Onboarding steps for driver compliance
 * P2P Matchmaking Platform Requirements:
 * - Legal acceptance (Terms & Privacy)
 * - Insurance disclosure (driver's own coverage)
 * - Background check consent (safety best practice)
 * - Vehicle requirements (quality standards)
 * - Independent contractor agreement (P2P relationship clarity)
 */
enum class OnboardingStep {
    LOGIN,
    LEGAL_ACCEPTANCE,
    INSURANCE_DISCLOSURE,
    BACKGROUND_CHECK,
    VEHICLE_REQUIREMENTS,
    INDEPENDENT_CONTRACTOR,
    COMPLETED
}

@Composable
fun DriverNavGraph(
    navController: NavHostController = rememberNavController(),
    loginViewModel: LoginViewModel = hiltViewModel()
) {
    val loginState by loginViewModel.loginState.collectAsState()
    val context = LocalContext.current

    // Google Sign-In configuration
    val webClientId = BuildConfig.GOOGLE_WEB_CLIENT_ID
    val isGoogleSignInConfigured = webClientId.isNotEmpty()

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
                    Log.d("DriverNavGraph", "Google Sign In success: $email")
                    loginViewModel.googleSignIn(idToken, email, name)
                } else {
                    Log.e("DriverNavGraph", "Google Sign In: No ID token received")
                    Toast.makeText(context, "Sign in failed: No token received", Toast.LENGTH_SHORT).show()
                }
            } catch (e: ApiException) {
                Log.e("DriverNavGraph", "Google Sign In failed: ${e.statusCode}", e)
                Toast.makeText(context, "Sign in failed: ${e.message}", Toast.LENGTH_SHORT).show()
            }
        } else {
            Log.d("DriverNavGraph", "Google Sign In cancelled")
        }
    }

    // Determine which step to show based on login state
    val currentStep = when (loginState) {
        is LoginState.Idle, is LoginState.Loading, is LoginState.Error -> OnboardingStep.LOGIN
        is LoginState.NeedsLegalAcceptance -> OnboardingStep.LEGAL_ACCEPTANCE
        is LoginState.LoggedIn -> OnboardingStep.COMPLETED
    }

    when (currentStep) {
        OnboardingStep.LOGIN -> {
            LoginScreen(
                loginState = loginState,
                onLogin = { email, password ->
                    loginViewModel.login(email, password)
                },
                onGoogleSignInClick = {
                    if (googleSignInClient != null) {
                        Log.d("DriverNavGraph", "Starting Google Sign In")
                        googleSignInLauncher.launch(googleSignInClient.signInIntent)
                    } else {
                        Log.w("DriverNavGraph", "Google Sign-In not configured: Missing GOOGLE_WEB_CLIENT_ID")
                        Toast.makeText(context, "Google Sign-In coming soon!", Toast.LENGTH_SHORT).show()
                    }
                },
                onClearError = { loginViewModel.clearError() },
                onForgotPassword = { email, onResult ->
                    loginViewModel.forgotPassword(email, onResult)
                },
                onResetPassword = { email, code, newPassword, onResult ->
                    loginViewModel.resetPassword(email, code, newPassword, onResult)
                },
                rememberedCredentials = remember { loginViewModel.rememberedCredentials() }
            )
        }

        OnboardingStep.LEGAL_ACCEPTANCE -> {
            LegalAcceptanceScreen(
                userType = "Driver",
                onAccept = {
                    loginViewModel.acceptTermsAndPrivacy()
                }
            )
        }

        // These onboarding steps are driven inside DriverMainOrCompliance below
        // (reached via the COMPLETED branch), not as top-level steps.
        OnboardingStep.INSURANCE_DISCLOSURE,
        OnboardingStep.BACKGROUND_CHECK,
        OnboardingStep.VEHICLE_REQUIREMENTS,
        OnboardingStep.INDEPENDENT_CONTRACTOR -> {
            // Not reached in current flow - kept for future onboarding
        }

        OnboardingStep.COMPLETED -> {
            // New / unverified drivers go through compliance + the Checkr
            // background check first; verified (or already-pending) drivers go
            // straight to the main app.
            DriverMainOrCompliance(
                navController = navController,
                loginViewModel = loginViewModel
            )
        }
    }
}

/**
 * Gates the main driver app behind document verification + compliance + background-check
 * onboarding. Mirrors iOS's DriverOnboardingView step order (license -> insurance -> vehicle
 * -> background check -> pending): a driver can't reach the main app without both the license
 * and insurance photos uploaded (main_new.py:3566-3589's online-gate requires them), on top of
 * the existing compliance/background-check requirements below.
 *
 * - Already-cleared or already-pending drivers with both documents uploaded see the main app
 *   immediately.
 * - New (not_started) drivers walk License photo -> Insurance photo -> Insurance disclosure ->
 *   Background Check -> Vehicle -> Contractor. The Background Check step calls the Checkr
 *   initiate endpoint and opens the hosted invitation URL; status is polled to reflect
 *   pending/clear.
 */
@Composable
private fun DriverMainOrCompliance(
    navController: NavHostController,
    loginViewModel: LoginViewModel,
    complianceViewModel: com.eatfair.driver.ui.compliance.DriverComplianceViewModel = hiltViewModel(),
    documentViewModel: com.eatfair.driver.ui.compliance.DriverDocumentViewModel = hiltViewModel()
) {
    val context = LocalContext.current
    val compliance by complianceViewModel.uiState.collectAsState()
    val documents by documentViewModel.uiState.collectAsState()

    var complianceDone by rememberSaveable { mutableStateOf(false) }
    // 0 license, 1 insurance, 2 insurance disclosure, 3 bg check, 4 vehicle, 5 contractor
    var step by rememberSaveable { mutableStateOf(0) }

    // Open the Checkr hosted invitation URL once initiate returns it, then advance.
    LaunchedEffect(compliance.invitationUrl) {
        val url = compliance.invitationUrl
        if (url != null) {
            try {
                context.startActivity(
                    android.content.Intent(android.content.Intent.ACTION_VIEW, android.net.Uri.parse(url))
                )
            } catch (e: Exception) {
                Log.e("DriverNavGraph", "Failed to open background check URL: ${e.message}")
            }
            complianceViewModel.onInvitationOpened()
            if (step == 3) step = 4
        }
    }

    // A driver who already reached the main app must not be dropped onto the onboarding steps just because
    // the status requests are still loading or failed (slow relaunch mid-ride): unknown is not "incomplete".
    val onboardingPrefs = remember { context.getSharedPreferences("driver_onboarding", android.content.Context.MODE_PRIVATE) }
    val onboardedKey = "main_app_reached_" + (loginViewModel.secureStorage.driverEmail ?: "")
    val previouslyOnboarded = remember(onboardedKey) { onboardingPrefs.getBoolean(onboardedKey, false) }
    val statusKnown = !documents.isLoadingStatus && !documents.statusFailed &&
        !compliance.isLoadingStatus && !compliance.statusFailed

    val documentsReady = documents.licenseUploaded && documents.insuranceUploaded
    val verifiedOnboarded = documentsReady && (compliance.isClear || compliance.isPending || complianceDone)
    val showMainApp = verifiedOnboarded || (previouslyOnboarded && !statusKnown)

    LaunchedEffect(verifiedOnboarded, statusKnown) {
        if (verifiedOnboarded && statusKnown) onboardingPrefs.edit().putBoolean(onboardedKey, true).apply()
    }

    when {
        !showMainApp && (compliance.isLoadingStatus || documents.isLoadingStatus) -> {
            androidx.compose.foundation.layout.Box(
                modifier = Modifier.fillMaxSize(),
                contentAlignment = androidx.compose.ui.Alignment.Center
            ) {
                androidx.compose.material3.CircularProgressIndicator()
            }
        }

        !showMainApp -> {
            when (step) {
                0 -> com.eatfair.driver.ui.compliance.DriverDocumentCaptureScreen(
                    title = "Driver's License",
                    subtitle = "A clear photo of the front of your license",
                    requirementBullets = listOf(
                        "Valid, unexpired driver's license",
                        "All four corners visible",
                        "Text and photo clearly readable"
                    ),
                    documentType = "drivers_license",
                    isUploaded = documents.licenseUploaded,
                    isUploading = documents.uploadingType == "drivers_license",
                    error = documents.error,
                    onPicked = { uri -> documentViewModel.upload(context, uri, "drivers_license") },
                    onContinue = { step = 1 }
                )
                1 -> com.eatfair.driver.ui.compliance.DriverDocumentCaptureScreen(
                    title = "Proof of Insurance",
                    subtitle = "A clear photo of your insurance card",
                    requirementBullets = listOf(
                        "Current, unexpired insurance card",
                        "Your name and policy number visible"
                    ),
                    documentType = "insurance",
                    isUploaded = documents.insuranceUploaded,
                    isUploading = documents.uploadingType == "insurance",
                    error = documents.error,
                    onPicked = { uri -> documentViewModel.upload(context, uri, "insurance") },
                    onContinue = { step = 2 },
                    onBackClick = { step = 0 }
                )
                2 -> InsuranceDisclosureScreen(onContinue = { step = 3 }, onBackClick = { step = 1 })
                3 -> BackgroundCheckConsentScreen(
                    onContinue = { complianceViewModel.initiateBackgroundCheck() },
                    onBackClick = { step = 2 },
                    isInitiating = compliance.isInitiating,
                    statusText = when {
                        compliance.error != null -> compliance.error
                        compliance.isPending -> "Background check in progress. You can finish setup now; you'll be able to go online once it clears."
                        else -> "You'll be taken to our screening partner to verify your identity, driving record and criminal history."
                    }
                )
                4 -> VehicleRequirementsScreen(onContinue = { step = 5 }, onBackClick = { step = 3 })
                else -> IndependentContractorAgreementScreen(
                    onAccept = { complianceDone = true },
                    onBackClick = { step = 4 }
                )
            }
        }

        else -> DriverMainApp(navController = navController, loginViewModel = loginViewModel)
    }
}

@Composable
private fun DriverMainApp(
    navController: NavHostController,
    loginViewModel: LoginViewModel
) {
    Scaffold(
        bottomBar = {
            DriverBottomNavigation(navController = navController)
        }
    ) { innerPadding ->
        NavHost(
            navController = navController,
            startDestination = DriverScreen.Home.route,
            modifier = Modifier.padding(innerPadding)
        ) {
            composable(DriverScreen.Home.route) {
                DriverHomeScreen(
                    navController = navController,
                    driverName = loginViewModel.secureStorage.driverName
                )
            }
            composable(DriverScreen.Orders.route) {
                AvailableOrdersScreen(navController = navController)
            }
            composable(DriverScreen.Earnings.route) {
                EarningsScreen(navController = navController)
            }
            composable(DriverScreen.Profile.route) {
                ProfileScreen(
                    driverName = loginViewModel.secureStorage.driverName ?: "Driver",
                    driverEmail = loginViewModel.secureStorage.driverEmail ?: "",
                    driverPhone = loginViewModel.secureStorage.driverPhone ?: "",
                    onLogout = { loginViewModel.logout() },
                    onDeleteAccount = { onSuccess, onError ->
                        loginViewModel.deleteAccount(onSuccess, onError)
                    },
                    navController = navController
                )
            }
        }
    }
}

@Composable
fun DriverBottomNavigation(navController: NavHostController) {
    val navBackStackEntry by navController.currentBackStackEntryAsState()
    val currentRoute = navBackStackEntry?.destination?.route

    NavigationBar(
        containerColor = MaterialTheme.colorScheme.surface,
        contentColor = MaterialTheme.colorScheme.onSurface
    ) {
        bottomNavItems.forEach { screen ->
            val isSelected = currentRoute == screen.route
            NavigationBarItem(
                icon = {
                    Icon(
                        imageVector = if (isSelected) screen.selectedIcon else screen.unselectedIcon,
                        contentDescription = screen.title
                    )
                },
                label = { Text(screen.title) },
                selected = isSelected,
                onClick = {
                    if (currentRoute != screen.route) {
                        navController.navigate(screen.route) {
                            popUpTo(navController.graph.startDestinationId) {
                                saveState = true
                            }
                            launchSingleTop = true
                            restoreState = true
                        }
                    }
                },
                colors = NavigationBarItemDefaults.colors(
                    selectedIconColor = MaterialTheme.colorScheme.primary,
                    selectedTextColor = MaterialTheme.colorScheme.primary,
                    unselectedIconColor = MaterialTheme.colorScheme.onSurfaceVariant,
                    unselectedTextColor = MaterialTheme.colorScheme.onSurfaceVariant,
                    indicatorColor = MaterialTheme.colorScheme.primaryContainer
                )
            )
        }
    }
}
