package com.eatfair.shared.model

import com.eatfair.shared.validation.*
import com.google.gson.annotations.SerializedName

// ==========================================
// AUTHENTICATION MODELS
// ==========================================

data class CustomerLoginRequest(
    val email: String,
    val password: String
) {
    fun validate(): ValidationResult = validate {
        validate(email.isValidEmail(), "Invalid email format")
        validate(password.isNotBlank(), "Password cannot be empty")
        validate(password.hasMinLength(6), "Password must be at least 6 characters")
    }
}

data class CustomerLoginResponse(
    @SerializedName("access_token") val accessToken: String,
    @SerializedName("token_type") val tokenType: String = "bearer",
    @SerializedName("customer_id") val customerId: Int,
    val name: String? = null,
    val email: String? = null
)

data class CustomerRegisterRequest(
    val email: String,
    val password: String,
    val name: String,  // Backend expects 'name' field
    val phone: String
) {
    fun validate(): ValidationResult = validate {
        validate(email.isValidEmail(), "Invalid email format")
        validate(password.isValidPassword(), "Password must be at least 8 characters with letters and numbers")
        validate(name.isNotBlank(), "Name cannot be empty")
        validate(name.hasMinLength(2), "Name must be at least 2 characters")
        validate(phone.isNotBlank(), "Phone number cannot be empty")
    }
}

/**
 * Demo login request for App Store review
 * Only demo emails are accepted - server validates and generates session
 */
data class DemoLoginRequest(
    val email: String
)

data class GoogleAuthRequest(
    @SerializedName("id_token") val idToken: String,
    val email: String? = null,
    val name: String? = null,
    @SerializedName("google_id") val googleId: String? = null
) {
    // Convenience constructor for simple idToken auth
    constructor(idToken: String) : this(idToken, null, null, null)
}

data class AppleAuthRequest(
    val email: String,
    val name: String,
    @SerializedName("apple_id") val appleId: String
)

data class PasswordResetRequest(
    val email: String
)

data class PasswordResetConfirmRequest(
    val email: String,
    val code: String,
    @com.google.gson.annotations.SerializedName("new_password") val newPassword: String
)

/**
 * Forgot password request - sends reset code to email
 * Matches iOS: POST /auth/customer/forgot-password
 */
data class ForgotPasswordRequest(
    val email: String
)

/**
 * Reset password with code request
 * Matches iOS: POST /auth/customer/reset-password
 */
data class ResetPasswordWithCodeRequest(
    val email: String,
    val code: String,
    @SerializedName("new_password") val newPassword: String
)

data class DriverLoginResponse(
    @SerializedName("access_token") val accessToken: String,
    @SerializedName("token_type") val tokenType: String = "bearer",
    @SerializedName("driver_id") val driverId: Int,
    val name: String? = null,
    val email: String? = null,
    @SerializedName("driver_code") val driverCode: String? = null
)

data class DriverRegisterRequest(
    val email: String,
    val password: String,
    @SerializedName("first_name") val firstName: String,
    @SerializedName("last_name") val lastName: String,
    val phone: String
)

data class DriverGoogleAuthRequest(
    @SerializedName("id_token") val idToken: String,
    val email: String,
    val name: String
)

// ==========================================
// ORDER MODELS
// ==========================================

data class DriverInfo(
    val id: Int,
    val name: String,
    val phone: String? = null,
    @SerializedName("vehicle_type") val vehicleType: String? = null,
    @SerializedName("vehicle_color") val vehicleColor: String? = null,
    @SerializedName("license_plate") val licensePlate: String? = null,
    val rating: Double? = null,
    val latitude: Double? = null,
    val longitude: Double? = null
)

// ==========================================
// ADDRESS MODELS
// Aligned with backend schema (Uber/DoorDash pattern)
// ==========================================

data class Address(
    val id: Int,
    @SerializedName("user_id") val userId: Int,  // Backend returns user_id
    @SerializedName("location_name") val locationName: String? = null,  // "Home", "Work", etc.
    val street: String,
    val unit: String? = null,
    val city: String,
    val state: String,
    @SerializedName("zip_code") val zipCode: String,
    val instructions: String? = null,
    @SerializedName("address_type") val addressType: String? = "Home",  // "Home", "Work", "Other"
    val latitude: Double? = null,
    val longitude: Double? = null,
    @SerializedName("phone_number") val phoneNumber: String? = null,
    @SerializedName("is_default") val isDefault: Boolean = false,
    val label: String? = null  // Backward compatibility - same as location_name
) {
    // Convenience properties for backward compatibility
    val addressLine1: String get() = street
    val addressLine2: String? get() = unit
    val customerId: Int get() = userId

    // Formatted address for display
    val formattedAddress: String
        get() = listOfNotNull(
            street,
            unit?.let { "Unit $it" },
            city,
            state,
            zipCode
        ).joinToString(", ")

    // Display name (location name or address type)
    val displayName: String
        get() = locationName?.takeIf { it.isNotEmpty() } ?: addressType ?: "Home"
}

data class AddAddressRequest(
    @SerializedName("location_name") val locationName: String? = null,
    val street: String,
    val unit: String? = null,
    val city: String,
    val state: String,
    @SerializedName("zip_code") val zipCode: String,
    val instructions: String? = null,
    @SerializedName("address_type") val addressType: String? = "Home",
    val latitude: Double? = null,
    val longitude: Double? = null,
    @SerializedName("phone_number") val phoneNumber: String? = null,
    @SerializedName("is_default") val isDefault: Boolean = false
) {
    fun validate(): ValidationResult = validate {
        validate(street.isNotBlank(), "Street address cannot be empty")
        validate(street.hasMinLength(3), "Street address must be at least 3 characters")
        validate(city.isNotBlank(), "City cannot be empty")
        validate(city.hasMinLength(2), "City must be at least 2 characters")
        validate(state.isNotBlank(), "State cannot be empty")
        validate(state.length == 2, "State must be 2-letter code (e.g., CA)")
        validate(zipCode.isValidZipCode(), "Invalid ZIP code format")
        latitude?.let { validate(it.isValidLatitude(), "Invalid latitude value") }
        longitude?.let { validate(it.isValidLongitude(), "Invalid longitude value") }
        phoneNumber?.let {
            if (it.isNotBlank()) {
                validate(it.isValidPhone(), "Invalid phone number format")
            }
        }
    }
}

data class UpdateAddressRequest(
    @SerializedName("location_name") val locationName: String? = null,
    val street: String? = null,
    val unit: String? = null,
    val city: String? = null,
    val state: String? = null,
    @SerializedName("zip_code") val zipCode: String? = null,
    val instructions: String? = null,
    @SerializedName("address_type") val addressType: String? = null,
    val latitude: Double? = null,
    val longitude: Double? = null,
    @SerializedName("phone_number") val phoneNumber: String? = null,
    @SerializedName("is_default") val isDefault: Boolean? = null
)

// ==========================================
// RIDESHARE MODELS
// ==========================================

data class RideRequest(
    @SerializedName("customer_id") val customerId: Int,
    @SerializedName("pickup_lat") val pickupLat: Double,
    @SerializedName("pickup_lng") val pickupLng: Double,
    @SerializedName("pickup_address") val pickupAddress: String,
    @SerializedName("dropoff_lat") val dropoffLat: Double,
    @SerializedName("dropoff_lng") val dropoffLng: Double,
    @SerializedName("dropoff_address") val dropoffAddress: String
)

data class RideResponse(
    @SerializedName("ride_id") val rideId: Int,
    val status: String,
    @SerializedName("estimated_fare") val estimatedFare: Double,
    @SerializedName("estimated_time") val estimatedTime: String? = null,
    @SerializedName("distance_miles") val distanceMiles: Double? = null
)

data class CustomerRidesResponse(
    val rides: List<Ride>,
    val count: Int
)

data class Ride(
    val id: Int,
    @SerializedName("customer_id") val customerId: Int,
    @SerializedName("driver_id") val driverId: Int? = null,
    val status: String,
    @SerializedName("pickup_address") val pickupAddress: String,
    @SerializedName("dropoff_address") val dropoffAddress: String,
    @SerializedName("pickup_lat") val pickupLat: Double,
    @SerializedName("pickup_lng") val pickupLng: Double,
    @SerializedName("dropoff_lat") val dropoffLat: Double,
    @SerializedName("dropoff_lng") val dropoffLng: Double,
    @SerializedName("distance_miles") val distanceMiles: Double? = null,
    @SerializedName("fare_amount") val fareAmount: Double? = null,
    @SerializedName("platform_fee") val platformFee: Double? = null,
    @SerializedName("driver_earnings") val driverEarnings: Double? = null,
    @SerializedName("created_at") val createdAt: String? = null,
    @SerializedName("started_at") val startedAt: String? = null,
    @SerializedName("completed_at") val completedAt: String? = null,
    val driver: DriverInfo? = null
)

data class RideTrackingResponse(
    @SerializedName("ride_id") val rideId: Int,
    val status: String,
    val driver: DriverInfo? = null,
    @SerializedName("driver_location") val driverLocation: DriverLocation? = null,
    val eta: String? = null
)

data class DriverLocation(
    val lat: Double,
    val lng: Double,
    val heading: Double? = null
)

data class CancelRideRequest(
    val reason: String? = null
)

data class RateRideRequest(
    val rating: Int,
    val comment: String? = null
)

data class RideEstimateRequest(
    @SerializedName("pickup_latitude") val pickupLat: Double,
    @SerializedName("pickup_longitude") val pickupLng: Double,
    @SerializedName("dropoff_latitude") val dropoffLat: Double,
    @SerializedName("dropoff_longitude") val dropoffLng: Double
)

data class RideEstimateResponse(
    @SerializedName("distance_miles") val distanceMiles: Double,
    @SerializedName("estimated_fare") val estimatedFare: Double,
    @SerializedName("estimated_time") val estimatedTime: String,
    val breakdown: FareBreakdown? = null
)

data class FareBreakdown(
    val base: Double,
    val distance: Double,
    @SerializedName("platform_fee") val platformFee: Double
)

data class AvailableRide(
    @SerializedName("ride_id") val rideId: Int,
    @SerializedName("pickup_address") val pickupAddress: String,
    @SerializedName("dropoff_address") val dropoffAddress: String,
    @SerializedName("pickup_lat") val pickupLat: Double,
    @SerializedName("pickup_lng") val pickupLng: Double,
    @SerializedName("dropoff_lat") val dropoffLat: Double,
    @SerializedName("dropoff_lng") val dropoffLng: Double,
    @SerializedName("distance_miles") val distanceMiles: Double,
    @SerializedName("estimated_fare") val estimatedFare: Double,
    @SerializedName("customer_name") val customerName: String? = null
)

data class RideActionResponse(
    val success: Boolean,
    val ride: Ride? = null,
    val message: String? = null
)

data class RideCompleteResponse(
    val success: Boolean,
    val status: String,
    val earnings: Double,
    val tip: Double? = null,
    @SerializedName("total_earned") val totalEarned: Double
)

data class DriverRidesResponse(
    val rides: List<Ride>,
    @SerializedName("total_rides") val totalRides: Int,
    @SerializedName("total_earnings") val totalEarnings: Double
)

// ==========================================
// DRIVER MODELS
// ==========================================

data class DriverProfile(
    val id: Int,
    @SerializedName("driver_id") val driverId: String? = null,  // Business ID like "DRV-00002"
    val email: String,
    val name: String? = null,  // Backend returns combined name
    @SerializedName("first_name") val firstName: String? = null,  // Optional - may not be returned
    @SerializedName("last_name") val lastName: String? = null,  // Optional - may not be returned
    val phone: String? = null,
    val status: String? = null,  // "pending", "active", "suspended", "deactivated"
    @SerializedName("vehicle_type") val vehicleType: String? = null,
    @SerializedName("vehicle_color") val vehicleColor: String? = null,
    @SerializedName("license_plate") val licensePlate: String? = null,
    @SerializedName("drivers_license") val driversLicense: Boolean = false,
    val insurance: Boolean = false,
    @SerializedName("background_check") val backgroundCheck: Boolean = false,
    @SerializedName("is_online") val isOnline: Boolean = false,
    @SerializedName("driver_type") val driverType: String? = null,
    @SerializedName("current_lat") val currentLat: Double? = null,
    @SerializedName("current_lng") val currentLng: Double? = null,
    val rating: Double = 0.0,
    @SerializedName("total_deliveries") val totalDeliveries: Int = 0,
    @SerializedName("total_rides") val totalRides: Int = 0,
    @SerializedName("profile_image_url") val profileImageUrl: String? = null
) {
    // Helper to get display name (prefers combined name, falls back to first+last)
    val displayName: String
        get() = name ?: listOfNotNull(firstName, lastName).joinToString(" ").ifEmpty { "Driver" }
}

data class UpdateDriverRequest(
    @SerializedName("first_name") val firstName: String? = null,
    @SerializedName("last_name") val lastName: String? = null,
    val phone: String? = null,
    @SerializedName("vehicle_type") val vehicleType: String? = null,
    @SerializedName("vehicle_color") val vehicleColor: String? = null,
    @SerializedName("license_plate") val licensePlate: String? = null,
    @SerializedName("driver_type") val driverType: String? = null
)

data class DriverDocumentsResponse(
    @SerializedName("driver_id") val driverId: Int,
    val documents: List<DriverDocument>,
    val count: Int,
    @SerializedName("all_verified") val allVerified: Boolean
)

data class DriverDocument(
    val id: Int,
    @SerializedName("document_type") val documentType: String,
    @SerializedName("file_name") val fileName: String,
    @SerializedName("file_url") val fileUrl: String? = null,
    @SerializedName("upload_date") val uploadDate: String? = null,
    @SerializedName("expiry_date") val expiryDate: String? = null,
    val status: String,
    val verified: Boolean
)

data class DocumentUploadResponse(
    @SerializedName("document_id") val documentId: Int,
    val status: String,
    val message: String? = null
)

// Response shapes for the self-service /api/auth/driver/documents pair (matches iOS
// P2PAPIService.uploadDriverDocument / getDriverDocumentsStatus — main_new.py:6646,6700).
// Deliberately separate from DocumentUploadResponse/DriverDocumentsResponse above, which
// describe the different by-id/Persona-gated endpoint.
data class DriverDocumentUploadResponse(
    val success: Boolean,
    val message: String? = null,
    @SerializedName("file_path") val filePath: String? = null,
    @SerializedName("document_type") val documentType: String? = null
)

data class DriverDocumentsStatusResponse(
    val documents: DriverDocumentsStatus
)

data class DriverDocumentsStatus(
    @SerializedName("drivers_license") val driversLicense: DriverDocumentTypeStatus,
    val insurance: DriverDocumentTypeStatus,
    @SerializedName("background_check") val backgroundCheck: DriverBackgroundCheckTypeStatus
)

data class DriverDocumentTypeStatus(
    val uploaded: Boolean,
    val url: String? = null,
    val expiry: String? = null
)

data class DriverBackgroundCheckTypeStatus(
    val completed: Boolean,
    val date: String? = null
)

data class DriverStatusResponse(
    @SerializedName("driver_id") val driverId: Int,
    @SerializedName("is_online") val isOnline: Boolean,
    @SerializedName("driver_type") val driverType: String? = null
)

data class UpdateDriverStatusRequest(
    @SerializedName("is_online") val isOnline: Boolean,
    @SerializedName("driver_type") val driverType: String? = null
)

data class DriverLocationRequest(
    @SerializedName("driver_id") val driverId: Int,
    val latitude: Double,
    val longitude: Double,
    val heading: Double? = null,
    val speed: Double? = null
)

// ==========================================
// DELIVERY MODELS
// ==========================================
// AvailableDelivery/DeliveryActionResponse (v2/driver/deliveries food endpoints)
// removed. `Delivery` itself is kept below: DriverDashboardResponse.activeDelivery
// still references it even though nothing populates that field anymore.

data class Delivery(
    val id: Int,
    @SerializedName("order_id") val orderId: Int,
    @SerializedName("driver_id") val driverId: Int,
    val status: String,
    @SerializedName("restaurant_name") val restaurantName: String,
    @SerializedName("restaurant_address") val restaurantAddress: String,
    @SerializedName("delivery_address") val deliveryAddress: String,
    val earnings: Double,
    val tip: Double? = null,
    @SerializedName("created_at") val createdAt: String? = null,
    @SerializedName("completed_at") val completedAt: String? = null
)

// ==========================================
// DRIVER EARNINGS MODELS
// ==========================================

data class DriverEarningsResponse(
    val today: Double,
    val week: Double,
    val month: Double,
    val pending: Double,
    @SerializedName("total_tips") val totalTips: Double? = null,
    @SerializedName("deliveries_today") val deliveriesToday: Int? = null,
    @SerializedName("rides_today") val ridesToday: Int? = null
)

data class DriverDashboardResponse(
    val stats: DriverStats,
    val earnings: DriverEarningsResponse,
    @SerializedName("active_delivery") val activeDelivery: Delivery? = null,
    @SerializedName("active_ride") val activeRide: Ride? = null
)

data class DriverStats(
    @SerializedName("total_deliveries") val totalDeliveries: Int,
    @SerializedName("total_rides") val totalRides: Int,
    val rating: Double,
    @SerializedName("acceptance_rate") val acceptanceRate: Double? = null,
    @SerializedName("completion_rate") val completionRate: Double? = null
)

data class DriverStatsResponse(
    @SerializedName("driver_id") val driverId: Int,
    val stats: DriverStats,
    @SerializedName("weekly_summary") val weeklySummary: WeeklySummary? = null
)

data class WeeklySummary(
    val deliveries: Int,
    val rides: Int,
    val earnings: Double,
    val tips: Double,
    @SerializedName("hours_online") val hoursOnline: Double? = null
)

/**
 * Driver balance for payouts
 */
data class DriverBalanceResponse(
    @SerializedName("available_balance") val availableBalance: Double = 0.0,
    @SerializedName("pending_balance") val pendingBalance: Double = 0.0,
    @SerializedName("instant_payout_available") val instantPayoutAvailable: Boolean = false,
    @SerializedName("instant_payout_fee") val instantPayoutFee: Double = 1.50,
    @SerializedName("min_payout_amount") val minPayoutAmount: Double = 10.0,
    @SerializedName("has_bank_account") val hasBankAccount: Boolean = false,
    @SerializedName("bank_last4") val bankLast4: String? = null,
    @SerializedName("bank_name") val bankName: String? = null
)

// ==========================================
// PAYMENT MODELS
// ==========================================

data class CreatePaymentIntentRequest(
    val amount: Int, // in cents
    val currency: String = "usd",
    @SerializedName("customer_id") val customerId: Int? = null
)

data class PaymentIntentResponse(
    @SerializedName("clientSecret") val clientSecret: String,
    @SerializedName("publishableKey") val publishableKey: String,
    @SerializedName("paymentIntent") val paymentIntent: String? = null,
    @SerializedName("ephemeralKey") val ephemeralKey: String? = null,
    val customer: String? = null
)

// ==========================================
// GENERIC RESPONSE
// ==========================================

// ==========================================
// EMAIL VERIFICATION MODELS
// ==========================================

data class VerifyEmailRequest(
    val code: String
)

data class EmailVerificationSendResponse(
    val success: Boolean,
    val message: String? = null,
    val email: String? = null,
    @SerializedName("already_verified") val alreadyVerified: Boolean? = null,
    @SerializedName("expires_in_minutes") val expiresInMinutes: Int? = null
)

data class EmailVerificationResponse(
    val success: Boolean,
    val message: String? = null,
    val verified: Boolean = false,
    @SerializedName("verified_at") val verifiedAt: String? = null
)

data class EmailVerificationStatusResponse(
    val email: String,
    val verified: Boolean = false,
    @SerializedName("verified_at") val verifiedAt: String? = null
)

data class GenericResponse(
    val success: Boolean = true,
    val message: String? = null,
    val error: String? = null
)

data class ErrorResponse(
    val detail: String
)

// ==========================================
// DRIVER RATING & CHAT MODELS
// Aligned with iOS (Uber/DoorDash pattern)
// ==========================================

data class ChatMessageRequest(
    val message: String,
    @SerializedName("sender_type") val senderType: String = "customer"  // customer, driver, restaurant
)

data class ChatMessage(
    val id: Int,
    @SerializedName("order_id") val orderId: Int,
    @SerializedName("sender_type") val senderType: String,
    @SerializedName("sender_id") val senderId: Int,
    @SerializedName("sender_name") val senderName: String? = null,
    val message: String,
    @SerializedName("created_at") val createdAt: String
)

// ==========================================
// ORDER STATUS ENUM
// NOTE: Use com.eatfair.shared.constants.OrderStatus instead
// This import alias is provided for backward compatibility
// ==========================================
// OrderStatus is defined in EnumConst.kt with all 11 backend statuses:
// PENDING_PAYMENT, CONFIRMED, PENDING_RESTAURANT, PENDING_MODIFICATION,
// PREPARING, READY_FOR_PICKUP, OUT_FOR_DELIVERY, DELIVERED, CANCELLED,
// DECLINED_BY_RESTAURANT, RESTAURANT_TIMEOUT

// ==========================================
// PUSH NOTIFICATION MODELS
// ==========================================

/**
 * Request to register FCM push token with backend
 */
data class RegisterPushTokenRequest(
    val token: String,
    val platform: String = "android",  // "ios" or "android"
    @SerializedName("push_service") val pushService: String = "fcm",  // "fcm" or "apns"
    @SerializedName("device_id") val deviceId: String? = null,
    @SerializedName("app_version") val appVersion: String? = null,
    @SerializedName("user_type") val userType: String? = null  // "customer", "driver", "vendor"
)

// ==========================================
// iOS PARITY - ADDITIONAL MODELS
// These models match iOS P2PAPIService.swift endpoints
// ==========================================

/**
 * Confirm password reset with token
 * Matches iOS: POST /customer/password-reset/confirm
 */
data class ConfirmPasswordResetRequest(
    val token: String,
    @SerializedName("new_password") val newPassword: String
)

/**
 * Update customer profile
 * Matches iOS: POST /customer/{customerId}/profile
 */
data class UpdateCustomerProfileRequest(
    val name: String? = null,
    val phone: String? = null,
    val email: String? = null,
    @SerializedName("profile_image_url") val profileImageUrl: String? = null
)

data class CustomerProfileResponse(
    val id: Int,
    val name: String?,
    val email: String,
    val phone: String?,
    @SerializedName("profile_image_url") val profileImageUrl: String?,
    @SerializedName("created_at") val createdAt: String?
)

// ==========================================
// RIDESHARE FARE NEGOTIATION MODELS
// Matches iOS negotiation-service integration
// ==========================================

/**
 * Customer fare offer for negotiation
 * Matches iOS: POST /erp/rides/{rideId}/customer-negotiate
 */
data class CustomerFareOfferRequest(
    @SerializedName("offered_fare") val offeredFare: Double,
    val message: String? = null
)

/**
 * Fare negotiation response
 * Matches iOS negotiation responses
 */
data class FareNegotiationResponse(
    @SerializedName("ride_id") val rideId: Int,
    @SerializedName("negotiation_status") val negotiationStatus: String,
    @SerializedName("current_fare") val currentFare: Double,
    @SerializedName("customer_offer") val customerOffer: Double?,
    @SerializedName("driver_offer") val driverOffer: Double?,
    @SerializedName("platform_suggested_fare") val platformSuggestedFare: Double,
    @SerializedName("is_accepted") val isAccepted: Boolean,
    val message: String?
)

// ==========================================
// PAYMENT CARD MODELS
// Matches iOS P2PAPIService card management
// ==========================================

/**
 * Saved payment cards response
 * Matches iOS: GET /customers/{customerId}/cards
 */
data class SavedCardsResponse(
    val cards: List<PaymentCard>
)

/**
 * Payment card details
 */
data class PaymentCard(
    val id: String,
    val brand: String,  // "visa", "mastercard", "amex", etc.
    @SerializedName("last4") val last4: String,
    @SerializedName("exp_month") val expMonth: Int,
    @SerializedName("exp_year") val expYear: Int,
    @SerializedName("is_default") val isDefault: Boolean = false,
    @SerializedName("cardholder_name") val cardholderName: String? = null
)

/**
 * Add new payment card request
 * Matches iOS: POST /customers/{customerId}/cards
 */
data class AddCardRequest(
    @SerializedName("payment_method_id") val paymentMethodId: String,  // Stripe PaymentMethod ID
    @SerializedName("set_as_default") val setAsDefault: Boolean = false
)

// ==========================================
// CHECKR BACKGROUND CHECK MODELS (Driver)
// Checkr-Hosted flow: backend creates the invitation and returns a hosted URL
// the driver opens to complete ID + criminal + MVR screening.
// Backend: POST /api/checkr/background-check/initiate
//          GET  /api/checkr/background-check/{driverId}/status
// ==========================================

data class CheckrInitiateRequest(
    @SerializedName("driver_id") val driverId: Int
)

data class CheckrInitiateResponse(
    val success: Boolean = true,
    @SerializedName("invitation_url") val invitationUrl: String? = null,
    @SerializedName("candidate_id") val candidateId: String? = null,
    @SerializedName("report_id") val reportId: String? = null,
    val status: String? = null,
    val message: String? = null,
    val error: String? = null
)

data class CheckrStatusResponse(
    @SerializedName("driver_id") val driverId: Int? = null,
    val status: String? = null,  // not_started | pending | clear | consider | suspended
    @SerializedName("background_check_status") val backgroundCheckStatus: String? = null,
    @SerializedName("invitation_url") val invitationUrl: String? = null,
    @SerializedName("completed_at") val completedAt: String? = null,
    val message: String? = null
) {
    /** Normalized status, falling back across the field names the backend may use. */
    val effectiveStatus: String
        get() = (status ?: backgroundCheckStatus ?: "not_started").lowercase()

    val isClear: Boolean get() = effectiveStatus == "clear" || effectiveStatus == "complete" || effectiveStatus == "passed"
    val isPending: Boolean get() = effectiveStatus == "pending" || effectiveStatus == "in_progress"
}

data class FcmTokenRequest(
    @SerializedName("fcm_token") val fcmToken: String,
    @SerializedName("platform") val platform: String = "android"
)


data class UpdateFullNameRequest(@SerializedName("full_name") val fullName: String)

data class UpdateProfileAck(
    val success: Boolean = false,
    val name: String? = null,
    val phone: String? = null
)
