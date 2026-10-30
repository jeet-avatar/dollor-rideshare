package com.eatfair.app.ui.navigation

sealed class Screen(val route: String) {
    object Welcome : Screen("welcome")
    object SignUp : Screen("signup")
    object Login : Screen("login")
    object ForgotPassword : Screen("forgot_password")
    object ResetCodeEntry : Screen("reset_code_entry?email={email}") {
        fun createRoute(email: String) = "reset_code_entry?email=$email"
    }
    object LegalAcceptance : Screen("legal_acceptance")
    object EmailVerification : Screen("email_verification") // Email verification screen
    object Main: Screen("main") // Main screen with bottom navigation
    object Home: Screen("home")
    object Search: Screen("search")
    object Profile: Screen("profile")
    object EditProfile: Screen("edit_profile")
    object ReferAndEarn: Screen("refer_and_earn")
    object Notifications: Screen("notification")
    object PaymentMethods: Screen("payment_methods")

    object LocationMap: Screen("location_map")

    object AddAddressDetailsScreen: Screen("add_address_details?addressId={addressId}") {
        fun createRoute(addressId: String) = "add_address_details?addressId=$addressId"
    }

    object SavedAddressesScreen: Screen("saved_addresses")

    // Settings & Legal screens - Required for Google Play Store
    object Settings: Screen("settings")
    object PrivacyPolicy: Screen("privacy_policy")
    object TermsConditions: Screen("terms_conditions")

    // Rideshare screens - P2P ride matching (matches iOS RideRequestView)
    object RideRequest: Screen("ride_request")
    object RideTracking: Screen("ride_tracking/{rideId}") {
        fun createRoute(rideId: String) = "ride_tracking/$rideId"
    }
    object DriverChat: Screen("driver_chat/{rideRequestId}/{driverName}?driverId={driverId}") {
        fun createRoute(rideRequestId: Int, driverName: String, driverId: Int? = null) =
            "driver_chat/$rideRequestId/${java.net.URLEncoder.encode(driverName, "UTF-8")}?driverId=${driverId ?: 0}"
    }

    // Help & Support screen
    object HelpSupport: Screen("help_support")

    // Privacy & Safety screens - Uber Eats style transparency
    object WhatDriversSee: Screen("what_drivers_see")
    object YourPrivacy: Screen("your_privacy")
    object SafetyFeatures: Screen("safety_features")
}