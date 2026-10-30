package com.eatfair.shared.data.repository

import android.util.Log
import com.google.firebase.messaging.FirebaseMessaging
import kotlinx.coroutines.suspendCancellableCoroutine
import kotlin.coroutines.resume
import com.eatfair.shared.data.local.SecureStorage
import com.eatfair.shared.data.remote.DollorApiService
import com.eatfair.shared.model.*
import com.eatfair.shared.network.TokenExpiredException
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import okhttp3.MediaType.Companion.toMediaTypeOrNull
import okhttp3.RequestBody.Companion.toRequestBody
import retrofit2.HttpException
import java.io.IOException
import java.net.SocketTimeoutException
import java.net.UnknownHostException
import javax.inject.Inject
import javax.inject.Singleton

/**
 * Dollor.AI Repository
 * Provides clean data access layer matching iOS P2PAPIService functionality
 *
 * Error Handling:
 * - All API calls wrapped in comprehensive error handling
 * - Network errors mapped to user-friendly messages
 * - 401 errors handled by TokenRefreshInterceptor
 * - Proper Result.failure() on all error paths
 */
@Singleton
class DollorRepository @Inject constructor(
    private val apiService: DollorApiService,
    private val secureStorage: SecureStorage
) {
    companion object {
        private const val TAG = "DollorRepository"
    }

    /**
     * Safe API call wrapper with comprehensive error handling
     */
    private suspend fun <T> safeApiCall(
        apiCall: suspend () -> T
    ): Result<T> {
        return try {
            Result.success(apiCall())
        } catch (e: TokenExpiredException) {
            Log.e(TAG, "Token expired: ${e.message}")
            Result.failure(Exception("Session expired. Please login again."))
        } catch (e: HttpException) {
            val errorMessage = when (e.code()) {
                400 -> "Invalid request. Please check your input."
                401 -> "Authentication failed. Please login again."
                403 -> "Access denied."
                404 -> "Resource not found."
                409 -> "Conflict. The resource already exists."
                422 -> "Validation error. Please check your input."
                500 -> "Server error. Please try again later."
                502, 503 -> "Service temporarily unavailable. Please try again."
                else -> "Network error: ${e.message()}"
            }
            Log.e(TAG, "HTTP ${e.code()}: $errorMessage")
            Result.failure(Exception(errorMessage))
        } catch (e: SocketTimeoutException) {
            Log.e(TAG, "Request timeout: ${e.message}")
            Result.failure(Exception("Request timed out. Please check your connection and try again."))
        } catch (e: UnknownHostException) {
            Log.e(TAG, "No internet connection: ${e.message}")
            Result.failure(Exception("No internet connection. Please check your network and try again."))
        } catch (e: IOException) {
            Log.e(TAG, "Network error: ${e.message}")
            Result.failure(Exception("Network error. Please check your connection and try again."))
        } catch (e: Exception) {
            Log.e(TAG, "Unexpected error: ${e.message}", e)
            Result.failure(Exception("An unexpected error occurred. Please try again."))
        }
    }

    /**
     * Like [safeApiCall] but surfaces the backend's FastAPI `detail` message on
     * 4xx errors (e.g. "Background check not passed...") instead of a generic
     * string. Used for driver rideshare actions where the server message is
     * actionable for the driver.
     */
    private suspend fun <T> safeApiCallWithDetail(
        apiCall: suspend () -> T
    ): Result<T> {
        return try {
            Result.success(apiCall())
        } catch (e: TokenExpiredException) {
            Result.failure(Exception("Session expired. Please login again."))
        } catch (e: HttpException) {
            val detail = try {
                val body = e.response()?.errorBody()?.string()
                if (!body.isNullOrBlank()) {
                    org.json.JSONObject(body).optString("detail").ifBlank { null }
                } else null
            } catch (ex: Exception) {
                null
            }
            Log.e(TAG, "HTTP ${e.code()}: ${detail ?: e.message()}")
            Result.failure(Exception(detail ?: "Request failed (${e.code()})"))
        } catch (e: SocketTimeoutException) {
            Result.failure(Exception("Request timed out. Please check your connection and try again."))
        } catch (e: UnknownHostException) {
            Result.failure(Exception("No internet connection. Please check your network and try again."))
        } catch (e: IOException) {
            Result.failure(Exception("Network error. Please check your connection and try again."))
        } catch (e: Exception) {
            Log.e(TAG, "Unexpected error: ${e.message}", e)
            Result.failure(Exception(e.message ?: "An unexpected error occurred. Please try again."))
        }
    }

    // ==========================================
    // CUSTOMER AUTHENTICATION
    // ==========================================

    suspend fun customerLogin(email: String, password: String): Result<CustomerLoginResponse> =
        withContext(Dispatchers.IO) {
            safeApiCall {
                val response = apiService.customerLogin(email, password)
                secureStorage.saveCustomerAuth(
                    token = response.accessToken,
                    id = response.customerId,
                    name = response.name,
                    email = response.email
                )
                response
            }
        }

    suspend fun customerRegister(
        email: String,
        password: String,
        name: String,
        phone: String
    ): Result<CustomerLoginResponse> = withContext(Dispatchers.IO) {
        safeApiCall {
            val request = CustomerRegisterRequest(email, password, name, phone)
            // Validate input before sending to API
            val validation = request.validate()
            if (!validation.isValid()) {
                throw IllegalArgumentException(validation.getErrorsOrNull()?.joinToString(", ") ?: "Invalid input")
            }

            val response = apiService.customerRegister(request)
            secureStorage.saveCustomerAuth(
                token = response.accessToken,
                id = response.customerId,
                name = response.name,
                email = response.email
            )
            response
        }
    }

    suspend fun customerGoogleAuth(idToken: String, email: String? = null, name: String? = null): Result<CustomerLoginResponse> =
        withContext(Dispatchers.IO) {
            safeApiCall {
                val response = apiService.customerGoogleAuth(GoogleAuthRequest(idToken, email, name))
                secureStorage.saveCustomerAuth(
                    token = response.accessToken,
                    id = response.customerId,
                    name = response.name,
                    email = response.email
                )
                response
            }
        }

    fun customerLogout() {
        secureStorage.clearCustomerAuth()
    }

    /**
     * Request password reset - sends code to email
     * Matches iOS: P2PAPIService.requestPasswordReset()
     * API: POST /api/customer/password-reset/request
     */
    suspend fun requestPasswordReset(email: String): Result<Unit> =
        withContext(Dispatchers.IO) {
            safeApiCall {
                apiService.requestPasswordReset(ForgotPasswordRequest(email))
            }.map { }
        }

    /**
     * Confirm password reset with code and new password
     * Matches iOS: P2PAPIService.confirmPasswordReset()
     * API: POST /api/customer/password-reset/confirm
     */
    suspend fun confirmPasswordReset(
        email: String,
        code: String,
        newPassword: String
    ): Result<Unit> = withContext(Dispatchers.IO) {
        safeApiCall {
            apiService.confirmPasswordResetWithCode(
                ResetPasswordWithCodeRequest(email, code, newPassword)
            )
        }.map { }
    }

    /**
     * Demo login for App Store review
     * Server validates demo accounts without password - no credentials stored in app
     */
    suspend fun customerDemoLogin(email: String): Result<CustomerLoginResponse> =
        withContext(Dispatchers.IO) {
            safeApiCall {
                val response = apiService.customerDemoLogin(DemoLoginRequest(email))
                secureStorage.saveCustomerAuth(
                    token = response.accessToken,
                    id = response.customerId,
                    name = response.name,
                    email = response.email
                )
                response
            }
        }

    /**
     * Delete customer account - required by Google Play Store policy
     * Matches iOS: P2PAPIService.deleteCustomerAccount()
     * API: DELETE /api/customers/{customerId}/delete
     */
    suspend fun deleteCustomerAccount(): Result<Unit> = withContext(Dispatchers.IO) {
        val token = secureStorage.getAuthHeader(SecureStorage.UserType.CUSTOMER)
            ?: return@withContext Result.failure(Exception("Not authenticated"))
        val customerId = secureStorage.customerId
        // Surfaces the server message, e.g. 409 "You have a ride in progress..."
        safeApiCallWithDetail {
            apiService.deleteCustomerAccount(customerId, token)
            // Clear all auth data after successful deletion
            secureStorage.clearCustomerAuth()
        }
    }

    /**
     * Update customer profile (name / phone).
     * Backend route: PUT /api/customer/{customerId}/profile (name & phone as query params).
     */
    suspend fun updateCustomerFullName(name: String): Result<UpdateProfileAck> =
        withContext(Dispatchers.IO) {
            val token = secureStorage.getAuthHeader(SecureStorage.UserType.CUSTOMER)
                ?: return@withContext Result.failure(Exception("Not authenticated"))
            safeApiCallWithDetail { apiService.updateCustomerFullName(UpdateFullNameRequest(name.trim()), token) }
        }

    suspend fun updateCustomerProfile(name: String?, phone: String?): Result<CustomerProfileResponse> =
        withContext(Dispatchers.IO) {
            val token = secureStorage.getAuthHeader(SecureStorage.UserType.CUSTOMER)
                ?: return@withContext Result.failure(Exception("Not authenticated"))
            val customerId = secureStorage.customerId
            safeApiCall {
                apiService.updateCustomerProfile(
                    customerId = customerId,
                    name = name?.takeIf { it.isNotBlank() },
                    phone = phone?.takeIf { it.isNotBlank() },
                    token = token
                )
            }
        }

    // ==========================================
    // EMAIL VERIFICATION
    // ==========================================

    suspend fun sendEmailVerification(): Result<EmailVerificationSendResponse> = withContext(Dispatchers.IO) {
        val token = secureStorage.getAuthHeader(SecureStorage.UserType.CUSTOMER)
            ?: return@withContext Result.failure(Exception("Not authenticated"))
        safeApiCall {
            apiService.sendEmailVerification(token)
        }
    }

    suspend fun verifyEmail(code: String): Result<EmailVerificationResponse> = withContext(Dispatchers.IO) {
        val token = secureStorage.getAuthHeader(SecureStorage.UserType.CUSTOMER)
            ?: return@withContext Result.failure(Exception("Not authenticated"))
        safeApiCall {
            apiService.verifyEmail(VerifyEmailRequest(code), token)
        }
    }

    suspend fun getEmailVerificationStatus(): Result<EmailVerificationStatusResponse> = withContext(Dispatchers.IO) {
        val token = secureStorage.getAuthHeader(SecureStorage.UserType.CUSTOMER)
            ?: return@withContext Result.failure(Exception("Not authenticated"))
        safeApiCall {
            apiService.getEmailVerificationStatus(token)
        }
    }

    // ==========================================
    // DRIVER AUTHENTICATION
    // ==========================================

    suspend fun driverLogin(email: String, password: String): Result<DriverLoginResponse> =
        withContext(Dispatchers.IO) {
            safeApiCall {
                val response = apiService.driverLogin(email, password)
                secureStorage.saveDriverAuth(
                    token = response.accessToken,
                    id = response.driverId,
                    name = response.name,
                    email = response.email
                )
                response
            }
        }

    suspend fun driverRegister(
        email: String,
        password: String,
        firstName: String,
        lastName: String,
        phone: String
    ): Result<DriverLoginResponse> = withContext(Dispatchers.IO) {
        safeApiCall {
            val response = apiService.driverRegister(
                DriverRegisterRequest(email, password, firstName, lastName, phone)
            )
            secureStorage.saveDriverAuth(
                token = response.accessToken,
                id = response.driverId,
                name = response.name,
                email = response.email
            )
            response
        }
    }

    fun driverLogout() {
        secureStorage.clearDriverAuth()
    }

    /**
     * Demo login for driver App Store review
     * Server validates demo accounts without password
     */
    suspend fun driverDemoLogin(email: String): Result<DriverLoginResponse> =
        withContext(Dispatchers.IO) {
            safeApiCall {
                val response = apiService.driverDemoLogin(DemoLoginRequest(email))
                secureStorage.saveDriverAuth(
                    token = response.accessToken,
                    id = response.driverId,
                    name = response.name,
                    email = response.email
                )
                response
            }
        }

    suspend fun driverGoogleAuth(request: DriverGoogleAuthRequest): Result<DriverLoginResponse> =
        withContext(Dispatchers.IO) {
            safeApiCall {
                val response = apiService.driverGoogleAuth(request)
                secureStorage.saveDriverAuth(
                    token = response.accessToken,
                    id = response.driverId,
                    name = response.name,
                    email = response.email
                )
                response
            }
        }

    suspend fun driverAppleAuth(request: AppleAuthRequest): Result<DriverLoginResponse> =
        withContext(Dispatchers.IO) {
            safeApiCall {
                val response = apiService.driverAppleAuth(request)
                secureStorage.saveDriverAuth(
                    token = response.accessToken,
                    id = response.driverId,
                    name = response.name,
                    email = response.email
                )
                response
            }
        }

    /**
     * Delete driver account - required by Google Play Store policy
     * Matches iOS: P2PAPIService.deleteDriverAccount()
     * API: DELETE /api/drivers/{driverId}/delete
     */
    suspend fun deleteDriverAccount(): Result<Unit> = withContext(Dispatchers.IO) {
        val token = secureStorage.getAuthHeader(SecureStorage.UserType.DRIVER)
            ?: return@withContext Result.failure(Exception("Not authenticated"))
        val driverId = secureStorage.driverId
        // Surfaces the server message, e.g. 409 "You have a ride in progress..."
        safeApiCallWithDetail {
            apiService.deleteDriverAccount(driverId, token)
            // Clear all auth data after successful deletion
            secureStorage.clearDriverAuth()
        }
    }

    // ==========================================
    // CUSTOMER ADDRESSES
    // ==========================================

    suspend fun getAddresses(): Result<List<Address>> = withContext(Dispatchers.IO) {
        val token = secureStorage.getAuthHeader(SecureStorage.UserType.CUSTOMER)
            ?: return@withContext Result.failure(Exception("Not authenticated"))
        val customerId = secureStorage.customerId
        safeApiCall {
            apiService.getAddresses(customerId, token)
        }
    }

    suspend fun addAddress(address: AddAddressRequest): Result<Address> =
        withContext(Dispatchers.IO) {
            val token = secureStorage.getAuthHeader(SecureStorage.UserType.CUSTOMER)
                ?: return@withContext Result.failure(Exception("Not authenticated"))
            val customerId = secureStorage.customerId

            // Validate input
            val validation = address.validate()
            if (!validation.isValid()) {
                return@withContext Result.failure(
                    IllegalArgumentException(validation.getErrorsOrNull()?.joinToString(", ") ?: "Invalid address")
                )
            }

            safeApiCall {
                apiService.addAddress(customerId, address, token)
            }
        }

    suspend fun updateAddress(addressId: Int, address: UpdateAddressRequest): Result<Address> =
        withContext(Dispatchers.IO) {
            val token = secureStorage.getAuthHeader(SecureStorage.UserType.CUSTOMER)
                ?: return@withContext Result.failure(Exception("Not authenticated"))
            val customerId = secureStorage.customerId
            safeApiCall {
                apiService.updateAddress(customerId, addressId, address, token)
            }
        }

    suspend fun deleteAddress(addressId: Int): Result<GenericResponse> =
        withContext(Dispatchers.IO) {
            val token = secureStorage.getAuthHeader(SecureStorage.UserType.CUSTOMER)
                ?: return@withContext Result.failure(Exception("Not authenticated"))
            val customerId = secureStorage.customerId
            safeApiCall {
                apiService.deleteAddress(customerId, addressId, token)
            }
        }

    suspend fun setDefaultAddress(addressId: Int): Result<Address> =
        withContext(Dispatchers.IO) {
            val token = secureStorage.getAuthHeader(SecureStorage.UserType.CUSTOMER)
                ?: return@withContext Result.failure(Exception("Not authenticated"))
            val customerId = secureStorage.customerId
            safeApiCall {
                apiService.setDefaultAddress(customerId, addressId, token)
            }
        }

    suspend fun getDefaultAddress(): Result<Address> =
        withContext(Dispatchers.IO) {
            val token = secureStorage.getAuthHeader(SecureStorage.UserType.CUSTOMER)
                ?: return@withContext Result.failure(Exception("Not authenticated"))
            val customerId = secureStorage.customerId
            safeApiCall {
                apiService.getDefaultAddress(customerId, token)
            }
        }

    // ==========================================
    // RIDESHARE - CUSTOMER
    // ==========================================

    suspend fun requestRide(
        pickupLat: Double,
        pickupLng: Double,
        pickupAddress: String,
        dropoffLat: Double,
        dropoffLng: Double,
        dropoffAddress: String
    ): Result<RideResponse> = withContext(Dispatchers.IO) {
        val token = secureStorage.getAuthHeader(SecureStorage.UserType.CUSTOMER)
            ?: return@withContext Result.failure(Exception("Not authenticated"))
        val customerId = secureStorage.customerId
        safeApiCall {
            val request = RideRequest(
                customerId = customerId,
                pickupLat = pickupLat,
                pickupLng = pickupLng,
                pickupAddress = pickupAddress,
                dropoffLat = dropoffLat,
                dropoffLng = dropoffLng,
                dropoffAddress = dropoffAddress
            )
            apiService.requestRide(request, token)
        }
    }

    suspend fun getCustomerRides(): Result<CustomerRidesResponse> = withContext(Dispatchers.IO) {
        val token = secureStorage.getAuthHeader(SecureStorage.UserType.CUSTOMER)
            ?: return@withContext Result.failure(Exception("Not authenticated"))
        safeApiCall {
            apiService.getCustomerRides(token)
        }
    }

    suspend fun trackRide(rideId: Int): Result<RideTrackingResponse> = withContext(Dispatchers.IO) {
        val token = secureStorage.getAuthHeader(SecureStorage.UserType.CUSTOMER)
            ?: return@withContext Result.failure(Exception("Not authenticated"))
        safeApiCall {
            apiService.trackRide(rideId, token)
        }
    }

    suspend fun cancelRide(rideId: Int, reason: String): Result<GenericResponse> =
        withContext(Dispatchers.IO) {
            val token = secureStorage.getAuthHeader(SecureStorage.UserType.CUSTOMER)
                ?: return@withContext Result.failure(Exception("Not authenticated"))
            safeApiCall {
                apiService.cancelRide(rideId, CancelRideRequest(reason), token)
            }
        }

    suspend fun estimateRideFare(
        pickupLat: Double,
        pickupLng: Double,
        dropoffLat: Double,
        dropoffLng: Double
    ): Result<RideEstimateResponse> = withContext(Dispatchers.IO) {
        safeApiCall {
            val request = RideEstimateRequest(pickupLat, pickupLng, dropoffLat, dropoffLng)
            apiService.estimateRideFare(request)
        }
    }

    // ==========================================
    // DRIVER LOCATION
    // ==========================================

    suspend fun updateDriverLocation(lat: Double, lng: Double): Result<GenericResponse> =
        withContext(Dispatchers.IO) {
            val token = secureStorage.getAuthHeader(SecureStorage.UserType.DRIVER)
                ?: return@withContext Result.failure(Exception("Not authenticated"))
            val driverId = secureStorage.driverId
            safeApiCall {
                val request = DriverLocationRequest(driverId, lat, lng)
                apiService.updateDriverLocation(request, token)
            }
        }

    // ==========================================
    // DRIVER RIDESHARE
    // ==========================================

    suspend fun getAvailableRides(): Result<List<AvailableRide>> = withContext(Dispatchers.IO) {
        val token = secureStorage.getAuthHeader(SecureStorage.UserType.DRIVER)
            ?: return@withContext Result.failure(Exception("Not authenticated"))
        safeApiCall { apiService.getAvailableRides(token) }
    }

    suspend fun acceptRide(rideId: Int): Result<RideActionResponse> = withContext(Dispatchers.IO) {
        val token = secureStorage.getAuthHeader(SecureStorage.UserType.DRIVER)
            ?: return@withContext Result.failure(Exception("Not authenticated"))
        safeApiCall { apiService.acceptRide(rideId, token) }
    }

    // ==========================================
    // DRIVER DOCUMENT VERIFICATION (license/insurance photos)
    // ==========================================
    // Self-service pair matching iOS P2PAPIService.uploadDriverDocument /
    // getDriverDocumentsStatus — NOT uploadVendorDocument's by-id/vendor cousin above.

    /**
     * Upload a driver verification document photo (license, insurance, or vehicle
     * registration). Sets the matching boolean immediately server-side (main_new.py:6683-6690) —
     * unlike the by-id endpoint, there's no separate webhook/admin review step.
     */
    suspend fun uploadDriverDocument(
        file: okhttp3.MultipartBody.Part,
        documentType: String
    ): Result<DriverDocumentUploadResponse> = withContext(Dispatchers.IO) {
        val token = secureStorage.getAuthHeader(SecureStorage.UserType.DRIVER)
            ?: return@withContext Result.failure(Exception("Not authenticated"))
        val docTypePart = documentType.toRequestBody("text/plain".toMediaTypeOrNull())
        safeApiCallWithDetail {
            apiService.uploadDriverDocumentSelf(file, docTypePart, token)
        }
    }

    /** Current upload status for license/insurance/background-check, for resuming onboarding. */
    suspend fun getDriverDocumentsStatus(): Result<DriverDocumentsStatusResponse> = withContext(Dispatchers.IO) {
        val token = secureStorage.getAuthHeader(SecureStorage.UserType.DRIVER)
            ?: return@withContext Result.failure(Exception("Not authenticated"))
        safeApiCall { apiService.getDriverDocumentsStatusSelf(token) }
    }

    // ==========================================
    // DRIVER RIDESHARE (REAL BACKEND - bid-based)
    // ==========================================

    /**
     * Toggle driver online/offline. Returns the resulting online state.
     * Surfaces the backend's 403 detail (approval / background-check gate).
     */
    suspend fun setDriverOnline(isOnline: Boolean): Result<Boolean> = withContext(Dispatchers.IO) {
        val token = secureStorage.getAuthHeader(SecureStorage.UserType.DRIVER)
            ?: return@withContext Result.failure(Exception("Not authenticated"))
        safeApiCallWithDetail {
            apiService.setDriverOnline(
                com.eatfair.shared.model.rideshare.DriverOnlineRequest(isOnline),
                token
            ).isOnline
        }
    }

    /** Available ride requests the driver can bid on. */
    suspend fun getAvailableRideRequests(
        latitude: Double? = null,
        longitude: Double? = null
    ): Result<List<com.eatfair.shared.model.rideshare.RideRequestForBidding>> = withContext(Dispatchers.IO) {
        val token = secureStorage.getAuthHeader(SecureStorage.UserType.DRIVER)
            ?: return@withContext Result.failure(Exception("Not authenticated"))
        safeApiCall { apiService.getAvailableRideRequests(token, latitude, longitude).availableRequests }
    }

    /** Driver's matched / in-progress rides. */
    suspend fun getDriverActiveRideRequests():
        Result<List<com.eatfair.shared.model.rideshare.RideRequestForBidding>> = withContext(Dispatchers.IO) {
        val token = secureStorage.getAuthHeader(SecureStorage.UserType.DRIVER)
            ?: return@withContext Result.failure(Exception("Not authenticated"))
        safeApiCall { apiService.getDriverActiveRideRequests(token).activeRides }
    }

    /** Submit a bid (accept a ride by bidding on it). Surfaces backend detail. */
    suspend fun submitRideBid(
        requestId: Int,
        proposedPrice: Double,
        estimatedArrivalMinutes: Int? = null,
        message: String? = null
    ): Result<com.eatfair.shared.model.rideshare.SubmitBidResponse> = withContext(Dispatchers.IO) {
        val token = secureStorage.getAuthHeader(SecureStorage.UserType.DRIVER)
            ?: return@withContext Result.failure(Exception("Not authenticated"))
        val driverId = secureStorage.driverId
        safeApiCallWithDetail {
            apiService.submitRideBid(
                requestId,
                com.eatfair.shared.model.rideshare.SubmitRideBidRequest(
                    driverId = driverId,
                    proposedPrice = proposedPrice,
                    estimatedArrivalMinutes = estimatedArrivalMinutes,
                    message = message
                ),
                token
            )
        }
    }

    suspend fun getDriverOwnBids(): Result<List<com.eatfair.shared.model.rideshare.DriverOwnBid>> =
        withContext(Dispatchers.IO) {
            val token = secureStorage.getAuthHeader(SecureStorage.UserType.DRIVER)
                ?: return@withContext Result.failure(Exception("Not authenticated"))
            safeApiCall { apiService.getDriverOwnBids(secureStorage.driverId, token).bids }
        }

    suspend fun acceptRiderCounter(bidId: Int): Result<com.eatfair.shared.model.rideshare.BidActionResponse> =
        withContext(Dispatchers.IO) {
            val token = secureStorage.getAuthHeader(SecureStorage.UserType.DRIVER)
                ?: return@withContext Result.failure(Exception("Not authenticated"))
            safeApiCallWithDetail { apiService.acceptRiderCounter(bidId, token) }
        }

    suspend fun rejectRiderCounter(bidId: Int): Result<com.eatfair.shared.model.rideshare.BidActionResponse> =
        withContext(Dispatchers.IO) {
            val token = secureStorage.getAuthHeader(SecureStorage.UserType.DRIVER)
                ?: return@withContext Result.failure(Exception("Not authenticated"))
            safeApiCallWithDetail { apiService.rejectRiderCounter(bidId, token) }
        }

    suspend fun withdrawBid(bidId: Int): Result<com.eatfair.shared.model.rideshare.BidActionResponse> =
        withContext(Dispatchers.IO) {
            val token = secureStorage.getAuthHeader(SecureStorage.UserType.DRIVER)
                ?: return@withContext Result.failure(Exception("Not authenticated"))
            safeApiCallWithDetail { apiService.withdrawBid(bidId, token) }
        }

    suspend fun driverFinalCounter(bidId: Int, price: Double): Result<com.eatfair.shared.model.rideshare.BidActionResponse> =
        withContext(Dispatchers.IO) {
            val token = secureStorage.getAuthHeader(SecureStorage.UserType.DRIVER)
                ?: return@withContext Result.failure(Exception("Not authenticated"))
            safeApiCallWithDetail {
                apiService.driverFinalCounter(bidId, com.eatfair.shared.model.rideshare.DriverCounterRequest(price), token)
            }
        }

    /** Mark arrived at pickup for an active (matched) ride. */
    suspend fun markRideRequestArrived(requestId: Int):
        Result<com.eatfair.shared.model.rideshare.RideStatusResponse> = withContext(Dispatchers.IO) {
        val token = secureStorage.getAuthHeader(SecureStorage.UserType.DRIVER)
            ?: return@withContext Result.failure(Exception("Not authenticated"))
        safeApiCallWithDetail { apiService.markRideRequestArrived(requestId, token) }
    }

    /** Start an active (matched) ride. */
    suspend fun startRideRequest(requestId: Int):
        Result<com.eatfair.shared.model.rideshare.RideStatusResponse> = withContext(Dispatchers.IO) {
        val token = secureStorage.getAuthHeader(SecureStorage.UserType.DRIVER)
            ?: return@withContext Result.failure(Exception("Not authenticated"))
        safeApiCallWithDetail { apiService.startRideRequest(requestId, token) }
    }

    /** Complete an in-progress ride. */
    suspend fun completeRideRequest(requestId: Int):
        Result<com.eatfair.shared.model.rideshare.RideStatusResponse> = withContext(Dispatchers.IO) {
        val token = secureStorage.getAuthHeader(SecureStorage.UserType.DRIVER)
            ?: return@withContext Result.failure(Exception("Not authenticated"))
        safeApiCallWithDetail { apiService.completeRideRequest(requestId, token) }
    }

    private fun driverToken(): String? = secureStorage.getAuthHeader(SecureStorage.UserType.DRIVER)

    suspend fun driverCancelRide(requestId: Int, reason: String) = withContext(Dispatchers.IO) {
        val token = driverToken() ?: return@withContext Result.failure(Exception("Not authenticated"))
        safeApiCallWithDetail {
            apiService.driverCancelRideRequest(requestId, com.eatfair.shared.model.rideshare.DriverCancelRideRequest(reason), token)
        }
    }

    suspend fun markPassengerNoShow(requestId: Int) = withContext(Dispatchers.IO) {
        val token = driverToken() ?: return@withContext Result.failure(Exception("Not authenticated"))
        safeApiCallWithDetail { apiService.markPassengerNoShow(requestId, token) }
    }

    suspend fun ratePassenger(requestId: Int, rating: Int, comment: String?) = withContext(Dispatchers.IO) {
        val token = driverToken() ?: return@withContext Result.failure(Exception("Not authenticated"))
        safeApiCallWithDetail {
            apiService.ratePassenger(requestId, com.eatfair.shared.model.rideshare.PassengerRatingRequest(rating, comment), token)
        }
    }

    suspend fun getDriverRideChat(requestId: Int) = withContext(Dispatchers.IO) {
        val token = driverToken() ?: return@withContext Result.failure(Exception("Not authenticated"))
        safeApiCall { apiService.getRideChat(requestId, token).messages }
    }

    suspend fun sendDriverRideChat(requestId: Int, text: String) = withContext(Dispatchers.IO) {
        val token = driverToken() ?: return@withContext Result.failure(Exception("Not authenticated"))
        safeApiCallWithDetail {
            apiService.sendRideChat(requestId, com.eatfair.shared.model.rideshare.SendRideChatRequest(text, "driver"), token)
        }
    }

    // Chat safety (report / block) for the driver app. 404/405 = older backend.
    // Each call returns a concrete Result type. The earlier generic Result<T?> helper threw a
    // ClassCastException in the R8-optimised release build when the chat screen opened.
    private suspend fun chatSafetyBody(
        call: suspend (token: String) -> retrofit2.Response<*>
    ): Any? {
        val token = driverToken() ?: throw Exception("Not authenticated")
        val response = try {
            call(token)
        } catch (e: IOException) {
            throw Exception("Network error. Check your connection and try again.")
        } catch (e: TokenExpiredException) {
            throw Exception("Session expired. Please login again.")
        }
        if (!response.isSuccessful) {
            throw com.eatfair.shared.ui.ChatSafety.httpError(response.code(), response.errorBody()?.string())
        }
        return response.body()
    }

    suspend fun reportChat(requestId: Int, reason: String, details: String): Result<Unit> =
        withContext(Dispatchers.IO) {
            try {
                chatSafetyBody {
                    apiService.reportChat(com.eatfair.shared.ui.ChatReportRequest(requestId, null, reason, details), it)
                }
                Result.success(Unit)
            } catch (e: Exception) {
                Result.failure(e)
            }
        }

    suspend fun setChatBlock(block: Boolean, userType: String, userId: Int): Result<Unit> =
        withContext(Dispatchers.IO) {
            try {
                chatSafetyBody {
                    val body = com.eatfair.shared.ui.ChatBlockRequest(userType, userId)
                    if (block) apiService.blockChatUser(body, it) else apiService.unblockChatUser(body, it)
                }
                Result.success(Unit)
            } catch (e: Exception) {
                Result.failure(e)
            }
        }

    suspend fun getChatBlocks(): Result<List<com.eatfair.shared.ui.ChatBlockEntry>> =
        withContext(Dispatchers.IO) {
            try {
                val body = chatSafetyBody { apiService.getChatBlocks(it) }
                    as? com.eatfair.shared.ui.ChatBlocksResponse
                Result.success(body?.blocks.orEmpty())
            } catch (e: Exception) {
                Result.failure(e)
            }
        }

    suspend fun getDriverMe() = withContext(Dispatchers.IO) {
        val token = driverToken() ?: return@withContext Result.failure(Exception("Not authenticated"))
        safeApiCall { apiService.getDriverMe(token) }
    }

    /**
     * Unified driver earnings with multi-period breakdown.
     * @param period one of "today", "week", "month", "year"
     */
    suspend fun getDriverEarningsDetailed(period: String = "today"):
        Result<com.eatfair.shared.model.driver.DriverEarningsResponse> = withContext(Dispatchers.IO) {
        val token = secureStorage.getAuthHeader(SecureStorage.UserType.DRIVER)
            ?: return@withContext Result.failure(Exception("Not authenticated"))
        safeApiCall { apiService.getDriverEarningsSummary(period, token).toResponse(period) }
    }

    suspend fun getDriverAccessibility(): Result<com.eatfair.shared.model.rideshare.DriverAccessibilitySettings> =
        withContext(Dispatchers.IO) {
            val token = driverToken() ?: return@withContext Result.failure(Exception("Not authenticated"))
            safeApiCall { apiService.getDriverAccessibility(token) }
        }

    suspend fun updateDriverAccessibility(
        settings: com.eatfair.shared.model.rideshare.DriverAccessibilitySettings
    ): Result<com.eatfair.shared.model.rideshare.DriverAccessibilitySettings> = withContext(Dispatchers.IO) {
        val token = driverToken() ?: return@withContext Result.failure(Exception("Not authenticated"))
        safeApiCall { apiService.updateDriverAccessibility(settings, token) }
    }

    /** Request a payout for the given amount (standard = free, 2-3 days). */
    suspend fun requestDriverPayout(
        amount: Double,
        method: String = "standard"
    ): Result<com.eatfair.shared.model.driver.CreatePayoutResponse> = withContext(Dispatchers.IO) {
        val token = secureStorage.getAuthHeader(SecureStorage.UserType.DRIVER)
            ?: return@withContext Result.failure(Exception("Not authenticated"))
        val driverId = secureStorage.driverId
        safeApiCallWithDetail {
            apiService.requestDriverPayout(
                driverId,
                com.eatfair.shared.model.driver.CreatePayoutRequest(amount = amount, method = method),
                token
            )
        }
    }

    /** Send a driver password reset email/code. */
    suspend fun driverForgotPassword(email: String): Result<GenericResponse> = withContext(Dispatchers.IO) {
        safeApiCall { apiService.driverForgotPassword(PasswordResetRequest(email)) }
    }

    /** Complete a driver password reset with the emailed code. */
    suspend fun driverResetPassword(email: String, code: String, newPassword: String): Result<GenericResponse> =
        withContext(Dispatchers.IO) {
            safeApiCallWithDetail { apiService.driverResetPassword(PasswordResetConfirmRequest(email, code, newPassword)) }
        }

    suspend fun markRideArrived(rideId: Int): Result<RideActionResponse> =
        withContext(Dispatchers.IO) {
            val token = secureStorage.getAuthHeader(SecureStorage.UserType.DRIVER)
                ?: return@withContext Result.failure(Exception("Not authenticated"))
            safeApiCall { apiService.markRideArrived(rideId, token) }
        }

    suspend fun startRide(rideId: Int): Result<RideActionResponse> = withContext(Dispatchers.IO) {
        val token = secureStorage.getAuthHeader(SecureStorage.UserType.DRIVER)
            ?: return@withContext Result.failure(Exception("Not authenticated"))
        safeApiCall { apiService.startRide(rideId, token) }
    }

    suspend fun completeRide(rideId: Int): Result<RideCompleteResponse> =
        withContext(Dispatchers.IO) {
            val token = secureStorage.getAuthHeader(SecureStorage.UserType.DRIVER)
                ?: return@withContext Result.failure(Exception("Not authenticated"))
            safeApiCall { apiService.completeRide(rideId, token) }
        }

    // ==========================================
    // DRIVER DASHBOARD & EARNINGS
    // ==========================================

    suspend fun getDriverDashboard(): Result<DriverDashboardResponse> =
        withContext(Dispatchers.IO) {
            val token = secureStorage.getAuthHeader(SecureStorage.UserType.DRIVER)
                ?: return@withContext Result.failure(Exception("Not authenticated"))
            val driverId = secureStorage.driverId
            safeApiCall { apiService.getDriverDashboard(driverId, token) }
        }

    suspend fun getDriverEarnings(): Result<DriverEarningsResponse> = withContext(Dispatchers.IO) {
        val token = secureStorage.getAuthHeader(SecureStorage.UserType.DRIVER)
            ?: return@withContext Result.failure(Exception("Not authenticated"))
        val driverId = secureStorage.driverId
        safeApiCall { apiService.getDriverEarnings(driverId, token) }
    }

    suspend fun getDriverStats(): Result<DriverStatsResponse> = withContext(Dispatchers.IO) {
        val token = secureStorage.getAuthHeader(SecureStorage.UserType.DRIVER)
            ?: return@withContext Result.failure(Exception("Not authenticated"))
        val driverId = secureStorage.driverId
        safeApiCall { apiService.getDriverStats(driverId, token) }
    }

    // ==========================================
    // DRIVER PAYOUTS (ACH Bank Transfer)
    // ==========================================

    /**
     * Get driver's current balance available for payout
     */
    suspend fun getDriverBalance(): Result<DriverBalanceResponse> = withContext(Dispatchers.IO) {
        val token = secureStorage.getAuthHeader(SecureStorage.UserType.DRIVER)
            ?: return@withContext Result.failure(Exception("Not authenticated"))
        val driverId = secureStorage.driverId
        safeApiCall { apiService.getDriverBalance(driverId, token) }
    }

    /**
     * Link a bank account for receiving payouts via ACH
     */
    suspend fun linkBankAccount(
        accountHolderName: String,
        routingNumber: String,
        accountNumber: String,
        accountType: String = "checking"
    ): Result<com.eatfair.shared.model.driver.LinkBankAccountResponse> = withContext(Dispatchers.IO) {
        val token = secureStorage.getAuthHeader(SecureStorage.UserType.DRIVER)
            ?: return@withContext Result.failure(Exception("Not authenticated"))
        val driverId = secureStorage.driverId
        safeApiCall {
            val request = com.eatfair.shared.model.driver.LinkBankAccountRequest(
                accountHolderName = accountHolderName,
                routingNumber = routingNumber,
                accountNumber = accountNumber,
                accountType = accountType
            )
            apiService.linkBankAccount(driverId, request, token)
        }
    }

    /**
     * Request a payout to linked bank account
     * @param amount Amount to withdraw
     * @param method "standard" (free, 2-3 days) or "instant" ($1.50 fee)
     */
    suspend fun requestPayout(
        amount: Double,
        method: String = "standard"
    ): Result<com.eatfair.shared.model.driver.CreatePayoutResponse> = withContext(Dispatchers.IO) {
        val token = secureStorage.getAuthHeader(SecureStorage.UserType.DRIVER)
            ?: return@withContext Result.failure(Exception("Not authenticated"))
        val driverId = secureStorage.driverId
        safeApiCall {
            val request = com.eatfair.shared.model.driver.CreatePayoutRequest(
                amount = amount,
                method = method
            )
            apiService.requestPayout(driverId, request, token)
        }
    }

    /**
     * Get payout history
     */
    suspend fun getPayoutHistory(
        limit: Int = 20,
        offset: Int = 0
    ): Result<com.eatfair.shared.model.driver.PayoutHistoryResponse> = withContext(Dispatchers.IO) {
        val token = secureStorage.getAuthHeader(SecureStorage.UserType.DRIVER)
            ?: return@withContext Result.failure(Exception("Not authenticated"))
        val driverId = secureStorage.driverId
        safeApiCall { apiService.getPayoutHistory(driverId, limit, offset, token) }
    }

    // ==========================================
    // PAYMENTS
    // ==========================================

    suspend fun createPaymentIntent(
        amount: Int,
        currency: String = "usd",
        userType: SecureStorage.UserType = SecureStorage.UserType.CUSTOMER
    ): Result<PaymentIntentResponse> = withContext(Dispatchers.IO) {
        val token = secureStorage.getAuthHeader(userType)
            ?: return@withContext Result.failure(Exception("Not authenticated"))
        safeApiCall {
            val request = CreatePaymentIntentRequest(amount, currency)
            apiService.createPaymentIntent(request, token)
        }
    }

    // ==========================================
    // UTILITY
    // ==========================================

    val isCustomerLoggedIn: Boolean
        get() = secureStorage.isCustomerLoggedIn

    val isDriverLoggedIn: Boolean
        get() = secureStorage.isDriverLoggedIn

    val isVendorLoggedIn: Boolean
        get() = secureStorage.isVendorLoggedIn

    val customerName: String?
        get() = secureStorage.customerName

    val driverName: String?
        get() = secureStorage.driverName

    val vendorName: String?
        get() = secureStorage.vendorName

    // ==========================================
    // DRIVER BACKGROUND CHECK (Checkr-Hosted)
    // ==========================================

    /**
     * Start the Checkr-hosted background check for the logged-in driver.
     * Surfaces the backend `detail` on 4xx so the compliance screen can show it.
     */
    suspend fun initiateBackgroundCheck(): Result<CheckrInitiateResponse> =
        withContext(Dispatchers.IO) {
            val token = secureStorage.getAuthHeader(SecureStorage.UserType.DRIVER)
                ?: return@withContext Result.failure(Exception("Not authenticated"))
            val driverId = secureStorage.driverId
            safeApiCallWithDetail {
                apiService.initiateBackgroundCheck(CheckrInitiateRequest(driverId), token)
            }
        }

    /** Poll the driver's background check status (not_started / pending / clear). */
    suspend fun getBackgroundCheckStatus(): Result<CheckrStatusResponse> =
        withContext(Dispatchers.IO) {
            val token = secureStorage.getAuthHeader(SecureStorage.UserType.DRIVER)
                ?: return@withContext Result.failure(Exception("Not authenticated"))
            val driverId = secureStorage.driverId
            safeApiCall { apiService.getBackgroundCheckStatus(driverId, token) }
        }

    // ==========================================
    // PUSH NOTIFICATIONS
    // ==========================================

    /**
     * Register FCM push token with backend
     * Works for all user types (customer, driver, vendor)
     */
    /**
     * Register this device's FCM token for the signed-in user — the same JSON endpoints
     * iOS uses (POST /api/erp/{customers|drivers}/{id}/fcm-token). Call after login and
     * whenever Firebase rotates the token.
     */
    suspend fun registerPushToken(
        token: String,
        platform: String = "android",
        @Suppress("UNUSED_PARAMETER") pushService: String = "fcm"
    ): Result<GenericResponse> = withContext(Dispatchers.IO) {
        val request = com.eatfair.shared.model.FcmTokenRequest(token, platform)
        val customerAuth = secureStorage.getAuthHeader(SecureStorage.UserType.CUSTOMER)
        val driverAuth = secureStorage.getAuthHeader(SecureStorage.UserType.DRIVER)
        when {
            secureStorage.isCustomerLoggedIn && customerAuth != null ->
                safeApiCallWithDetail { apiService.registerCustomerFcmToken(secureStorage.customerId, request, customerAuth) }
            secureStorage.isDriverLoggedIn && driverAuth != null ->
                safeApiCallWithDetail { apiService.registerDriverFcmToken(secureStorage.driverId, request, driverAuth) }
            else -> Result.failure(Exception("Not authenticated"))
        }
    }

    /** Fetches the device's current FCM token and registers it for the signed-in user. */
    suspend fun registerCurrentPushToken() {
        val token = runCatching { currentFcmToken() }.getOrNull() ?: return
        registerPushToken(token)
    }

    /**
     * Logout: tell the server to stop pushing to this device (DELETE .../fcm-token), then drop
     * the device's FCM token so the next sign-in gets a fresh one. Call BEFORE clearing auth.
     * Best effort: a failure never blocks logout.
     */
    suspend fun unregisterPushToken() = withContext(Dispatchers.IO) {
        val customerAuth = secureStorage.getAuthHeader(SecureStorage.UserType.CUSTOMER)
        val driverAuth = secureStorage.getAuthHeader(SecureStorage.UserType.DRIVER)
        runCatching {
            when {
                secureStorage.isCustomerLoggedIn && customerAuth != null ->
                    apiService.unregisterCustomerFcmToken(secureStorage.customerId, customerAuth)
                secureStorage.isDriverLoggedIn && driverAuth != null ->
                    apiService.unregisterDriverFcmToken(secureStorage.driverId, driverAuth)
                else -> null
            }
        }.onFailure { Log.w(TAG, "FCM unregister failed: ${it.message}") }
        runCatching { FirebaseMessaging.getInstance().deleteToken() }
    }

    private suspend fun currentFcmToken(): String? = suspendCancellableCoroutine { cont ->
        FirebaseMessaging.getInstance().token
            .addOnSuccessListener { if (cont.isActive) cont.resume(it) }
            .addOnFailureListener { if (cont.isActive) cont.resume(null) }
    }
}
