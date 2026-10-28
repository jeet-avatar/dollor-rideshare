package com.eatfair.shared.network

import android.util.Log
import com.eatfair.shared.config.AppConfig
import com.eatfair.shared.data.local.SecureStorage
import okhttp3.Interceptor
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody
import okhttp3.Response
import org.json.JSONObject
import java.io.IOException
import javax.inject.Inject
import javax.inject.Singleton

/**
 * TokenRefreshInterceptor - Handles 401 errors and token expiration
 *
 * Behaviour:
 * - On a 401 for a CUSTOMER request, tries to refresh the access token via
 *   POST /api/auth/customer/refresh and retries the original request once with
 *   the new token (so the user is NOT forced back to the login screen on a
 *   routine token expiry).
 * - If the refresh fails (or the 401 was for a driver/vendor request), clears
 *   that user type's auth and throws TokenExpiredException so the app can route
 *   the user back to login.
 *
 * Thread-safe: refresh is guarded on secureStorage so concurrent 401s don't
 * trigger multiple refreshes.
 */
@Singleton
class TokenRefreshInterceptor @Inject constructor(
    private val secureStorage: SecureStorage
) : Interceptor {

    companion object {
        private const val TAG = "TokenRefreshInterceptor"
        private const val HEADER_AUTHORIZATION = "Authorization"
        // Marks a request that already went through a refresh+retry to prevent loops.
        private const val HEADER_RETRY = "X-Token-Refresh-Retry"
    }

    // Plain client (no interceptors) used for the refresh call so it can't recurse.
    private val refreshClient: OkHttpClient by lazy { OkHttpClient.Builder().build() }
    private val jsonMediaType = "application/json; charset=utf-8".toMediaType()

    @Throws(IOException::class)
    override fun intercept(chain: Interceptor.Chain): Response {
        val originalRequest = chain.request()
        val response = chain.proceed(originalRequest)

        if (response.code != 401) return response

        val authHeader = originalRequest.header(HEADER_AUTHORIZATION)
        val token = authHeader?.removePrefix("Bearer ")?.trim()

        // Already retried once, or not a customer request → clear + force re-login.
        val alreadyRetried = originalRequest.header(HEADER_RETRY) != null
        val isCustomerRequest = token != null && token == secureStorage.customerToken

        if (!alreadyRetried && isCustomerRequest) {
            val newToken = synchronized(secureStorage) {
                // Another thread may have already refreshed while we waited.
                val current = secureStorage.customerToken
                if (current != null && current != token) {
                    current
                } else {
                    refreshCustomerToken(token)
                }
            }

            if (newToken != null) {
                response.close()
                val retried = originalRequest.newBuilder()
                    .header(HEADER_AUTHORIZATION, "Bearer $newToken")
                    .header(HEADER_RETRY, "1")
                    .build()
                Log.d(TAG, "Customer token refreshed - retrying original request")
                return chain.proceed(retried)
            }
        }

        // Refresh not possible/failed → clear the matching auth and force re-login.
        response.close()
        if (clearExpiredAuth(token)) SessionEvents.notifyExpired()
        throw TokenExpiredException(SessionEvents.MESSAGE)
    }

    /**
     * Calls POST /api/auth/customer/refresh with the (expired) customer token as
     * the credential, persists and returns the new access token, or null on
     * failure. Mirrors the driver refresh endpoint (Authorization-header based);
     * a stored refresh token is sent too when one is available.
     */
    private fun refreshCustomerToken(expiredToken: String?): String? {
        if (expiredToken.isNullOrBlank()) return null
        return try {
            val body = JSONObject().apply {
                secureStorage.customerRefreshToken?.let { put("refresh_token", it) }
            }.toString().toRequestBody(jsonMediaType)

            val request = Request.Builder()
                .url("${AppConfig.apiBaseUrl}/auth/customer/refresh")
                .post(body)
                .header(HEADER_AUTHORIZATION, "Bearer $expiredToken")
                .header("Content-Type", "application/json")
                .build()

            refreshClient.newCall(request).execute().use { resp ->
                val raw = resp.body?.string()
                if (!resp.isSuccessful || raw.isNullOrBlank()) {
                    Log.w(TAG, "Customer token refresh failed: HTTP ${resp.code}")
                    return null
                }
                val json = JSONObject(raw)
                val newToken = json.optString("access_token", "")
                    .ifBlank { json.optString("token", "") }
                    .ifBlank { json.optString("accessToken", "") }
                if (newToken.isBlank()) {
                    Log.w(TAG, "Customer token refresh returned no access_token")
                    return null
                }
                secureStorage.customerToken = newToken
                json.optString("refresh_token", "").takeIf { it.isNotBlank() }?.let {
                    secureStorage.customerRefreshToken = it
                }
                newToken
            }
        } catch (e: Exception) {
            Log.e(TAG, "Exception refreshing customer token: ${e.message}")
            null
        }
    }

    /** Clear expired authentication based on which token was used. */
    private fun clearExpiredAuth(token: String?): Boolean {
        if (token == null) return false
        return synchronized(secureStorage) {
            when (token) {
                secureStorage.customerToken -> secureStorage.clearCustomerAuth()
                secureStorage.driverToken -> secureStorage.clearDriverAuth()
                secureStorage.vendorToken -> secureStorage.clearVendorAuth()
                else -> return@synchronized false
            }
            true
        }
    }
}

/**
 * Exception thrown when a token has expired
 */
class TokenExpiredException(message: String) : IOException(message)
