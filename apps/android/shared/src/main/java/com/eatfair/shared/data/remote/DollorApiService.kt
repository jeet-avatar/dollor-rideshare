package com.eatfair.shared.data.remote

import com.eatfair.shared.model.*
import retrofit2.Response
import retrofit2.http.*

/**
 * Dollor.AI API Service
 * Complete API interface matching iOS P2PAPIService.swift
 * PRODUCTION: https://api.dollor.ai (see AppConfig.API_BASE_URL)
 */
interface DollorApiService {

    // ==========================================
    // CUSTOMER AUTHENTICATION
    // ==========================================

    @FormUrlEncoded
    @POST("auth/customer/login")
    suspend fun customerLogin(
        @Field("username") email: String,
        @Field("password") password: String
    ): CustomerLoginResponse

    @POST("auth/customer/register")
    suspend fun customerRegister(@Body request: CustomerRegisterRequest): CustomerLoginResponse

    @POST("auth/customer/google")
    suspend fun customerGoogleAuth(@Body request: GoogleAuthRequest): CustomerLoginResponse

    @POST("auth/customer/apple-auth")
    suspend fun customerAppleAuth(@Body request: AppleAuthRequest): CustomerLoginResponse

    @POST("customer/password-reset/request")
    suspend fun customerPasswordReset(@Body request: PasswordResetRequest): GenericResponse

    /**
     * Request password reset code - sends code to email
     * Matches iOS: POST /customer/password-reset/request
     * Matches Backend: POST /api/customer/password-reset/request
     */
    @POST("customer/password-reset/request")
    suspend fun requestPasswordReset(@Body request: ForgotPasswordRequest): GenericResponse

    /**
     * Confirm password reset with code
     * Matches iOS: POST /customer/password-reset/confirm
     * Matches Backend: POST /api/customer/password-reset/confirm
     */
    @POST("customer/password-reset/confirm")
    suspend fun confirmPasswordResetWithCode(@Body request: ResetPasswordWithCodeRequest): GenericResponse

    /**
     * Confirm password reset with token
     * Matches iOS: POST /customer/password-reset/confirm
     */
    @POST("customer/password-reset/confirm")
    suspend fun confirmPasswordReset(@Body request: ConfirmPasswordResetRequest): GenericResponse

    /**
     * Update customer profile
     * Backend route: PUT /api/customer/{customerId}/profile
     * Backend reads name/phone as QUERY params (no request body), so this uses
     * @PUT + @Query to match. Only name and phone are updatable server-side.
     */
    /** PUT /api/auth/customer/profile {full_name} — what iOS sends (Edit Profile sheet). */
    @PUT("auth/customer/profile")
    suspend fun updateCustomerFullName(
        @Body request: com.eatfair.shared.model.UpdateFullNameRequest,
        @Header("Authorization") token: String
    ): com.eatfair.shared.model.UpdateProfileAck

    @PUT("customer/{customerId}/profile")
    suspend fun updateCustomerProfile(
        @Path("customerId") customerId: Int,
        @Query("name") name: String?,
        @Query("phone") phone: String?,
        @Header("Authorization") token: String
    ): CustomerProfileResponse

    /**
     * Demo login for App Store review - server validates demo accounts
     * No password required - server generates session for verified demo emails
     */
    @POST("customer/demo-login")
    suspend fun customerDemoLogin(@Body request: DemoLoginRequest): CustomerLoginResponse

    /**
     * Delete customer account - required by Google Play Store policy
     * Matches iOS: DELETE /api/customers/{customerId}/delete
     */
    @DELETE("customers/{customerId}/delete")
    suspend fun deleteCustomerAccount(
        @Path("customerId") customerId: Int,
        @Header("Authorization") token: String
    ): GenericResponse

    // ==========================================
    // EMAIL VERIFICATION
    // ==========================================

    /**
     * Send email verification code to customer
     * POST /customer/email/send-verification
     */
    @POST("customer/email/send-verification")
    suspend fun sendEmailVerification(
        @Header("Authorization") token: String
    ): EmailVerificationSendResponse

    /**
     * Verify customer email with 6-digit code
     * POST /customer/email/verify
     */
    @POST("customer/email/verify")
    suspend fun verifyEmail(
        @Body request: VerifyEmailRequest,
        @Header("Authorization") token: String
    ): EmailVerificationResponse

    /**
     * Get email verification status
     * GET /customer/email/status
     */
    @GET("customer/email/status")
    suspend fun getEmailVerificationStatus(
        @Header("Authorization") token: String
    ): EmailVerificationStatusResponse

    // ==========================================
    // CUSTOMER ADDRESSES
    // Aligned with iOS P2PAPIService (Uber/DoorDash pattern)
    // ==========================================

    @GET("addresses/{customerId}")
    suspend fun getAddresses(
        @Path("customerId") customerId: Int,
        @Header("Authorization") token: String
    ): List<Address>

    @GET("addresses/{customerId}/default")
    suspend fun getDefaultAddress(
        @Path("customerId") customerId: Int,
        @Header("Authorization") token: String
    ): Address

    @POST("addresses/{customerId}")
    suspend fun addAddress(
        @Path("customerId") customerId: Int,
        @Body address: AddAddressRequest,
        @Header("Authorization") token: String
    ): Address

    @PUT("addresses/{customerId}/{addressId}")
    suspend fun updateAddress(
        @Path("customerId") customerId: Int,
        @Path("addressId") addressId: Int,
        @Body address: UpdateAddressRequest,
        @Header("Authorization") token: String
    ): Address

    @DELETE("addresses/{customerId}/{addressId}")
    suspend fun deleteAddress(
        @Path("customerId") customerId: Int,
        @Path("addressId") addressId: Int,
        @Header("Authorization") token: String
    ): GenericResponse

    @POST("addresses/{customerId}/{addressId}/set-default")
    suspend fun setDefaultAddress(
        @Path("customerId") customerId: Int,
        @Path("addressId") addressId: Int,
        @Header("Authorization") token: String
    ): Address

    // ==========================================
    // CUSTOMER RIDESHARE
    // ==========================================

    @POST("rides/request")
    suspend fun requestRide(
        @Body request: RideRequest,
        @Header("Authorization") token: String
    ): RideResponse

    @GET("customer/rides")
    suspend fun getCustomerRides(@Header("Authorization") token: String): CustomerRidesResponse

    @GET("rides/{rideId}/track")
    suspend fun trackRide(
        @Path("rideId") rideId: Int,
        @Header("Authorization") token: String
    ): RideTrackingResponse

    @POST("rides/{rideId}/cancel")
    suspend fun cancelRide(
        @Path("rideId") rideId: Int,
        @Body request: CancelRideRequest,
        @Header("Authorization") token: String
    ): GenericResponse

    @POST("rides/{rideId}/rate")
    suspend fun rateRide(
        @Path("rideId") rideId: Int,
        @Body request: RateRideRequest,
        @Header("Authorization") token: String
    ): GenericResponse

    @POST("rides/estimate")
    suspend fun estimateRideFare(@Body request: RideEstimateRequest): RideEstimateResponse

    /**
     * Customer submit fare offer for negotiation
     * Matches iOS: POST /erp/rides/{rideId}/customer-negotiate
     */
    @POST("erp/rides/{rideId}/customer-negotiate")
    suspend fun customerSubmitFareOffer(
        @Path("rideId") rideId: Int,
        @Body request: CustomerFareOfferRequest,
        @Header("Authorization") token: String
    ): FareNegotiationResponse

    /**
     * Customer accept driver's fare offer
     * Matches iOS: POST /erp/rides/{rideId}/customer-accept-fare
     */
    @POST("erp/rides/{rideId}/customer-accept-fare")
    suspend fun customerAcceptDriverFare(
        @Path("rideId") rideId: Int,
        @Header("Authorization") token: String
    ): FareNegotiationResponse

    // ==========================================
    // CUSTOMER PAYMENT CARDS
    // Matches iOS P2PAPIService card management
    // ==========================================

    /**
     * Get saved payment cards
     * Matches iOS: GET /customers/{customerId}/cards
     */
    @GET("customers/{customerId}/cards")
    suspend fun getSavedCards(
        @Path("customerId") customerId: Int,
        @Header("Authorization") token: String
    ): SavedCardsResponse

    /**
     * Set default payment card
     * Matches iOS: POST /customers/{customerId}/cards/{cardId}/default
     */
    @POST("customers/{customerId}/cards/{cardId}/default")
    suspend fun setDefaultCard(
        @Path("customerId") customerId: Int,
        @Path("cardId") cardId: String,
        @Header("Authorization") token: String
    ): PaymentCard

    // ==========================================
    // DRIVER AUTHENTICATION
    // ==========================================

    @FormUrlEncoded
    @POST("auth/driver/login")
    suspend fun driverLogin(
        @Field("username") email: String,
        @Field("password") password: String
    ): DriverLoginResponse

    @POST("auth/driver/register")
    suspend fun driverRegister(@Body request: DriverRegisterRequest): DriverLoginResponse

    @POST("auth/driver/google")
    suspend fun driverGoogleAuth(@Body request: DriverGoogleAuthRequest): DriverLoginResponse

    @POST("auth/driver/apple-auth")
    suspend fun driverAppleAuth(@Body request: AppleAuthRequest): DriverLoginResponse

    /** POST /api/driver/password-reset/request -> emails a reset code (same endpoint as iOS). */
    @POST("driver/password-reset/request")
    suspend fun driverForgotPassword(@Body request: PasswordResetRequest): GenericResponse

    /** POST /api/driver/password-reset/confirm {email, code, new_password} */
    @POST("driver/password-reset/confirm")
    suspend fun driverResetPassword(@Body request: PasswordResetConfirmRequest): GenericResponse

    /**
     * Refresh driver auth token
     * Matches iOS: POST /auth/driver/refresh
     */
    @POST("auth/driver/refresh")
    suspend fun refreshDriverToken(
        @Header("Authorization") token: String
    ): DriverLoginResponse

    /**
     * Demo login for driver App Store review - server validates demo accounts
     */
    @POST("auth/driver/demo-login")
    suspend fun driverDemoLogin(@Body request: DemoLoginRequest): DriverLoginResponse

    // ==========================================
    // DRIVER DOCUMENT VERIFICATION (license/insurance photos)
    // ==========================================
    // Matches iOS: POST/GET /api/auth/driver/documents (self-service, token-scoped —
    // NOT the by-id /drivers/{driverId}/documents pair below, which is a different,
    // Persona-webhook-gated pipeline and leaves drivers_license/insurance flipped
    // false until a separate admin/webhook step clears them).

    @Multipart
    @POST("auth/driver/documents")
    suspend fun uploadDriverDocumentSelf(
        @Part file: okhttp3.MultipartBody.Part,
        @Part("document_type") documentType: okhttp3.RequestBody,
        @Header("Authorization") token: String
    ): DriverDocumentUploadResponse

    @GET("auth/driver/documents")
    suspend fun getDriverDocumentsStatusSelf(
        @Header("Authorization") token: String
    ): DriverDocumentsStatusResponse

    // ==========================================
    // DRIVER PROFILE
    // ==========================================

    @Multipart
    @POST("drivers/{driverId}/documents")
    suspend fun uploadDriverDocument(
        @Path("driverId") driverId: Int,
        @Part file: okhttp3.MultipartBody.Part,
        @Part("document_type") documentType: okhttp3.RequestBody,
        @Header("Authorization") token: String
    ): DocumentUploadResponse

    /**
     * Delete driver account - required by Google Play Store policy
     * Matches iOS: DELETE /api/drivers/{driverId}/delete
     */
    @DELETE("drivers/{driverId}/delete")
    suspend fun deleteDriverAccount(
        @Path("driverId") driverId: Int,
        @Header("Authorization") token: String
    ): GenericResponse

    // ==========================================
    // DRIVER LOCATION
    // ==========================================

    @POST("driver/location")
    suspend fun updateDriverLocation(
        @Body request: DriverLocationRequest,
        @Header("Authorization") token: String
    ): GenericResponse

    // ==========================================
    // DRIVER RIDESHARE (REAL BACKEND - bid_routes.py /api/rides + main_new.py)
    // These map to the production endpoints the web/iOS driver clients use.
    // The v2/driver/rides/* methods below are legacy and not backed by the API.
    // ==========================================

    /**
     * Go online / offline. Backend gates going online on approval + a passed
     * background check and returns 403 with a `detail` message otherwise.
     * PUT /api/auth/driver/online
     */
    @PUT("auth/driver/online")
    suspend fun setDriverOnline(
        @Body request: com.eatfair.shared.model.rideshare.DriverOnlineRequest,
        @Header("Authorization") token: String
    ): com.eatfair.shared.model.rideshare.DriverOnlineResponse

    /**
     * Available ride requests to bid on.
     * GET /api/rides/available
     */
    @GET("rides/available")
    suspend fun getAvailableRideRequests(
        @Header("Authorization") token: String,
        @Query("latitude") latitude: Double? = null,
        @Query("longitude") longitude: Double? = null
    ): com.eatfair.shared.model.rideshare.AvailableRideRequestsResponse

    /**
     * Driver's matched/in-progress rides.
     * GET /api/rides/driver/active
     */
    @GET("rides/driver/active")
    suspend fun getDriverActiveRideRequests(
        @Header("Authorization") token: String
    ): com.eatfair.shared.model.rideshare.DriverActiveRidesResponse

    /**
     * Submit a bid on a ride request (accepting a ride == bidding on it).
     * POST /api/rides/request/{request_id}/bid
     */
    @POST("rides/request/{requestId}/bid")
    suspend fun submitRideBid(
        @Path("requestId") requestId: Int,
        @Body request: com.eatfair.shared.model.rideshare.SubmitRideBidRequest,
        @Header("Authorization") token: String
    ): com.eatfair.shared.model.rideshare.SubmitBidResponse

    @GET("rides/driver/{driverId}/bids")
    suspend fun getDriverOwnBids(
        @Path("driverId") driverId: Int,
        @Header("Authorization") token: String
    ): com.eatfair.shared.model.rideshare.DriverOwnBidsResponse

    @POST("rides/bid/{bidId}/accept-counter")
    suspend fun acceptRiderCounter(
        @Path("bidId") bidId: Int,
        @Header("Authorization") token: String
    ): com.eatfair.shared.model.rideshare.BidActionResponse

    @POST("rides/bid/{bidId}/reject-counter")
    suspend fun rejectRiderCounter(
        @Path("bidId") bidId: Int,
        @Header("Authorization") token: String
    ): com.eatfair.shared.model.rideshare.BidActionResponse

    @POST("rides/bid/{bidId}/withdraw")
    suspend fun withdrawBid(
        @Path("bidId") bidId: Int,
        @Header("Authorization") token: String
    ): com.eatfair.shared.model.rideshare.BidActionResponse

    @POST("rides/bid/{bidId}/driver-counter")
    suspend fun driverFinalCounter(
        @Path("bidId") bidId: Int,
        @Body request: com.eatfair.shared.model.rideshare.DriverCounterRequest,
        @Header("Authorization") token: String
    ): com.eatfair.shared.model.rideshare.BidActionResponse

    /** POST /api/rides/request/{id}/arrived */
    @POST("rides/request/{requestId}/arrived")
    suspend fun markRideRequestArrived(
        @Path("requestId") requestId: Int,
        @Header("Authorization") token: String
    ): com.eatfair.shared.model.rideshare.RideStatusResponse

    /** POST /api/rides/request/{id}/start */
    @POST("rides/request/{requestId}/start")
    suspend fun startRideRequest(
        @Path("requestId") requestId: Int,
        @Header("Authorization") token: String
    ): com.eatfair.shared.model.rideshare.RideStatusResponse

    /** POST /api/rides/request/{id}/complete */
    @POST("rides/request/{requestId}/complete")
    suspend fun completeRideRequest(
        @Path("requestId") requestId: Int,
        @Header("Authorization") token: String
    ): com.eatfair.shared.model.rideshare.RideStatusResponse

    @POST("rides/request/{requestId}/driver-cancel")
    suspend fun driverCancelRideRequest(
        @Path("requestId") requestId: Int,
        @Body request: com.eatfair.shared.model.rideshare.DriverCancelRideRequest,
        @Header("Authorization") token: String
    ): com.eatfair.shared.model.rideshare.BidActionResponse

    @POST("rides/request/{requestId}/no-show")
    suspend fun markPassengerNoShow(
        @Path("requestId") requestId: Int,
        @Header("Authorization") token: String
    ): com.eatfair.shared.model.rideshare.BidActionResponse

    @POST("rides/request/{requestId}/rate-passenger")
    suspend fun ratePassenger(
        @Path("requestId") requestId: Int,
        @Body request: com.eatfair.shared.model.rideshare.PassengerRatingRequest,
        @Header("Authorization") token: String
    ): com.eatfair.shared.model.rideshare.BidActionResponse

    @GET("p2p/ride-requests/{requestId}/chat")
    suspend fun getRideChat(
        @Path("requestId") requestId: Int,
        @Header("Authorization") token: String
    ): com.eatfair.shared.model.rideshare.RideChatListResponse

    @POST("p2p/ride-requests/{requestId}/chat")
    suspend fun sendRideChat(
        @Path("requestId") requestId: Int,
        @Body request: com.eatfair.shared.model.rideshare.SendRideChatRequest,
        @Header("Authorization") token: String
    ): com.eatfair.shared.model.rideshare.BidActionResponse

    @GET("auth/driver/me")
    suspend fun getDriverMe(
        @Header("Authorization") token: String
    ): com.eatfair.shared.model.rideshare.DriverMeResponse

    @GET("tnc/driver/accessibility")
    suspend fun getDriverAccessibility(
        @Header("Authorization") token: String
    ): com.eatfair.shared.model.rideshare.DriverAccessibilitySettings

    @retrofit2.http.PATCH("tnc/driver/accessibility")
    suspend fun updateDriverAccessibility(
        @Body body: com.eatfair.shared.model.rideshare.DriverAccessibilitySettings,
        @Header("Authorization") token: String
    ): com.eatfair.shared.model.rideshare.DriverAccessibilitySettings

    /** GET /api/driver/earnings?period=today|week|month|all (driver resolved from token) */
    @GET("driver/earnings")
    suspend fun getDriverEarningsSummary(
        @Query("period") period: String,
        @Header("Authorization") token: String
    ): com.eatfair.shared.model.driver.DriverEarningsSummaryDto

    /**
     * Request a manual payout via Stripe Connect.
     * POST /api/drivers/{driver_id}/payouts
     */
    @POST("drivers/{driverId}/payouts")
    suspend fun requestDriverPayout(
        @Path("driverId") driverId: Int,
        @Body request: com.eatfair.shared.model.driver.CreatePayoutRequest,
        @Header("Authorization") token: String
    ): com.eatfair.shared.model.driver.CreatePayoutResponse

    // ==========================================
    // DRIVER RIDESHARE (LEGACY v2 - not backed by API, kept for compatibility)
    // ==========================================

    @GET("v2/driver/rides/available")
    suspend fun getAvailableRides(
        @Header("Authorization") token: String
    ): List<AvailableRide>

    @POST("v2/driver/rides/{rideId}/accept")
    suspend fun acceptRide(
        @Path("rideId") rideId: Int,
        @Header("Authorization") token: String
    ): RideActionResponse

    @POST("v2/driver/rides/{rideId}/arrive")
    suspend fun markRideArrived(
        @Path("rideId") rideId: Int,
        @Header("Authorization") token: String
    ): RideActionResponse

    @POST("v2/driver/rides/{rideId}/start")
    suspend fun startRide(
        @Path("rideId") rideId: Int,
        @Header("Authorization") token: String
    ): RideActionResponse

    @POST("v2/driver/rides/{rideId}/complete")
    suspend fun completeRide(
        @Path("rideId") rideId: Int,
        @Header("Authorization") token: String
    ): RideCompleteResponse

    @POST("v2/driver/rides/{rideId}/cancel")
    suspend fun driverCancelRide(
        @Path("rideId") rideId: Int,
        @Body request: CancelRideRequest,
        @Header("Authorization") token: String
    ): GenericResponse

    // ==========================================
    // DRIVER EARNINGS & DASHBOARD
    // ==========================================

    @GET("drivers/{driverId}/earnings")
    suspend fun getDriverEarnings(
        @Path("driverId") driverId: Int,
        @Header("Authorization") token: String
    ): DriverEarningsResponse

    @GET("v2/driver/dashboard/{driverId}")
    suspend fun getDriverDashboard(
        @Path("driverId") driverId: Int,
        @Header("Authorization") token: String
    ): DriverDashboardResponse

    @GET("erp/driver/{driverId}/stats")
    suspend fun getDriverStats(
        @Path("driverId") driverId: Int,
        @Header("Authorization") token: String
    ): DriverStatsResponse

    // ==========================================
    // DRIVER PAYOUTS (ACH Bank Transfer)
    // ==========================================

    /**
     * Link bank account for payouts (Stripe Connect)
     */
    @POST("v2/driver/{driverId}/bank-account")
    suspend fun linkBankAccount(
        @Path("driverId") driverId: Int,
        @Body request: com.eatfair.shared.model.driver.LinkBankAccountRequest,
        @Header("Authorization") token: String
    ): com.eatfair.shared.model.driver.LinkBankAccountResponse

    /**
     * Get payout history
     */
    @GET("v2/driver/{driverId}/payouts")
    suspend fun getPayoutHistory(
        @Path("driverId") driverId: Int,
        @Query("limit") limit: Int = 20,
        @Query("offset") offset: Int = 0,
        @Header("Authorization") token: String
    ): com.eatfair.shared.model.driver.PayoutHistoryResponse

    /**
     * Request a payout (standard: 2-3 business days, instant: immediate with fee)
     */
    @POST("v2/driver/{driverId}/payouts")
    suspend fun requestPayout(
        @Path("driverId") driverId: Int,
        @Body request: com.eatfair.shared.model.driver.CreatePayoutRequest,
        @Header("Authorization") token: String
    ): com.eatfair.shared.model.driver.CreatePayoutResponse

    /**
     * Get available balance for payout
     */
    @GET("v2/driver/{driverId}/balance")
    suspend fun getDriverBalance(
        @Path("driverId") driverId: Int,
        @Header("Authorization") token: String
    ): DriverBalanceResponse

    // ==========================================
    // PAYMENTS
    // ==========================================

    @POST("payments/create-intent")
    suspend fun createPaymentIntent(
        @Body request: CreatePaymentIntentRequest,
        @Header("Authorization") token: String
    ): PaymentIntentResponse

    // ==========================================
    // LEGAL & PUBLIC PAGES
    // ==========================================

    // ==========================================
    // PUSH NOTIFICATIONS
    // ==========================================

    /**
     * Register FCM push token with backend
     * Called when app starts and when token refreshes
     */
    /** POST /api/erp/customers/{id}/fcm-token {fcm_token, platform} (iOS parity) */
    @POST("erp/customers/{customerId}/fcm-token")
    suspend fun registerCustomerFcmToken(
        @Path("customerId") customerId: Int,
        @Body request: com.eatfair.shared.model.FcmTokenRequest,
        @Header("Authorization") token: String
    ): GenericResponse

    /** POST /api/erp/drivers/{id}/fcm-token {fcm_token, platform} (iOS parity) */
    @POST("erp/drivers/{driverId}/fcm-token")
    suspend fun registerDriverFcmToken(
        @Path("driverId") driverId: Int,
        @Body request: com.eatfair.shared.model.FcmTokenRequest,
        @Header("Authorization") token: String
    ): GenericResponse

    /** DELETE /api/erp/customers/{id}/fcm-token (call on logout) */
    @DELETE("erp/customers/{customerId}/fcm-token")
    suspend fun unregisterCustomerFcmToken(
        @Path("customerId") customerId: Int,
        @Header("Authorization") token: String
    ): GenericResponse

    /** DELETE /api/erp/drivers/{id}/fcm-token (call on logout) */
    @DELETE("erp/drivers/{driverId}/fcm-token")
    suspend fun unregisterDriverFcmToken(
        @Path("driverId") driverId: Int,
        @Header("Authorization") token: String
    ): GenericResponse

    @POST("notifications/register-token")
    suspend fun registerPushToken(
        @Body request: RegisterPushTokenRequest,
        @Header("Authorization") token: String
    ): GenericResponse

    // ==========================================
    // DRIVER BACKGROUND CHECK (Checkr-Hosted)
    // ==========================================

    /**
     * Initiate a Checkr-hosted background check. Returns a hosted `invitation_url`
     * the driver opens (ACTION_VIEW) to complete ID + criminal + MVR screening.
     * POST /api/checkr/background-check/initiate
     */
    @POST("checkr/background-check/initiate")
    suspend fun initiateBackgroundCheck(
        @Body request: CheckrInitiateRequest,
        @Header("Authorization") token: String
    ): CheckrInitiateResponse

    /**
     * Poll the driver's background check status (not_started / pending / clear).
     * GET /api/checkr/background-check/{driverId}/status
     */
    @GET("checkr/background-check/{driverId}/status")
    suspend fun getBackgroundCheckStatus(
        @Path("driverId") driverId: Int,
        @Header("Authorization") token: String
    ): CheckrStatusResponse
}
