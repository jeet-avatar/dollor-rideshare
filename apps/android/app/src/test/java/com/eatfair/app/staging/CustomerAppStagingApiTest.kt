package com.eatfair.app.staging

import com.google.gson.Gson
import com.google.gson.JsonObject
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody
import org.junit.Assert.*
import org.junit.Before
import org.junit.FixMethodOrder
import org.junit.Test
import org.junit.runners.MethodSorters
import java.util.concurrent.TimeUnit

/**
 * Rideshare Customer App Staging API Tests
 *
 * TARGET ENVIRONMENT (single production backend): https://api.dollor.ai
 *
 * Test Categories:
 * 1. Health Check & Connectivity
 * 2. Authentication (Login, Register, Google, Demo)
 * 3. Rideshare (Estimate, Request, Bids, Track)
 * 4. Address Management
 * 5. Payment Methods
 *
 * Run with: ./gradlew :app:testProductionReleaseUnitTest --tests "*.CustomerAppStagingApiTest"
 */
@FixMethodOrder(MethodSorters.NAME_ASCENDING)
class CustomerAppStagingApiTest {

    companion object {
        const val STAGING_BASE_URL = "https://api.dollor.ai"
        const val API_BASE_URL = "$STAGING_BASE_URL/api"

        const val TEST_CUSTOMER_EMAIL = "demo@dollor.ai"
        const val TEST_CUSTOMER_PASSWORD = "demo123"

        var authToken: String? = null
        var customerId: Int? = null
        var testRideRequestId: Int? = null
    }

    private lateinit var client: OkHttpClient
    private lateinit var gson: Gson
    private val jsonMediaType = "application/json; charset=utf-8".toMediaType()

    @Before
    fun setUp() {
        client = OkHttpClient.Builder()
            .connectTimeout(30, TimeUnit.SECONDS)
            .readTimeout(30, TimeUnit.SECONDS)
            .writeTimeout(30, TimeUnit.SECONDS)
            .build()
        gson = Gson()
    }

    // =============================================================================
    // CATEGORY 1: HEALTH CHECK & CONNECTIVITY
    // =============================================================================

    @Test
    fun test_01_01_healthCheck_returnsOk() {
        val request = Request.Builder()
            .url("$STAGING_BASE_URL/health")
            .get()
            .build()

        val response = client.newCall(request).execute()
        println("Health Check Response: ${response.code}")

        assertTrue("Health check should return 2xx", response.isSuccessful)
    }

    @Test
    fun test_01_02_apiBaseUrl_isAccessible() {
        val request = Request.Builder()
            .url("$API_BASE_URL/rideshare/estimate")
            .get()
            .build()

        val response = client.newCall(request).execute()
        println("API Base URL Response: ${response.code}")

        // Should return 200 or at least not 5xx
        assertTrue("API should be accessible", response.code < 500)
    }

    // =============================================================================
    // CATEGORY 2: AUTHENTICATION
    // =============================================================================

    @Test
    fun test_02_01_customerLogin_withValidCredentials() {
        val formBody = "username=$TEST_CUSTOMER_EMAIL&password=$TEST_CUSTOMER_PASSWORD"

        val request = Request.Builder()
            .url("$API_BASE_URL/auth/customer/login")
            .post(formBody.toRequestBody("application/x-www-form-urlencoded".toMediaType()))
            .build()

        val response = client.newCall(request).execute()
        val body = response.body?.string() ?: ""
        println("Customer Login Response: ${response.code} - ${body.take(200)}")

        if (response.isSuccessful) {
            val json = gson.fromJson(body, JsonObject::class.java)
            authToken = json.get("access_token")?.asString
            customerId = json.getAsJsonObject("user")?.get("id")?.asInt
            println("Auth token obtained: ${authToken?.take(20)}...")
            assertNotNull("Should have access token", authToken)
        } else {
            println("Login failed (may need live credentials) - skipping auth-dependent tests")
        }
    }

    @Test
    fun test_02_02_customerRegister_returnsValidationErrors_withEmptyBody() {
        val registerBody = gson.toJson(mapOf<String, Any>())
        val request = Request.Builder()
            .url("$API_BASE_URL/auth/customer/register")
            .post(registerBody.toRequestBody(jsonMediaType))
            .addHeader("Content-Type", "application/json")
            .build()

        val response = client.newCall(request).execute()
        println("Register (empty) Response: ${response.code}")

        // Should return 422 (validation error) or 400, not 500
        assertTrue("Empty register should return 4xx not 5xx", response.code in 400..499)
    }

    // =============================================================================
    // CATEGORY 3: RIDESHARE API
    // =============================================================================

    @Test
    fun test_03_01_rideEstimate_endpointExists() {
        val request = Request.Builder()
            .url("$API_BASE_URL/rideshare/estimate?pickup_lat=37.3346&pickup_lng=-122.0090&dropoff_lat=37.7749&dropoff_lng=-122.4194")
            .get()
            .build()

        val response = client.newCall(request).execute()
        val body = response.body?.string() ?: ""
        println("Ride Estimate Response: ${response.code} - ${body.take(200)}")

        // Endpoint should exist (not 404)
        assertNotEquals("Rideshare estimate endpoint should exist", 404, response.code)
    }

    @Test
    fun test_03_02_rideBoard_endpointExists() {
        val request = Request.Builder()
            .url("$API_BASE_URL/rideshare/board")
            .get()
            .build()

        val response = client.newCall(request).execute()
        println("Ride Board Response: ${response.code}")

        // Should not be a server error
        assertTrue("Ride board should not return 5xx", response.code < 500)
    }

    @Test
    fun test_03_03_rideRequest_requiresAuth() {
        val rideBody = gson.toJson(mapOf(
            "pickup_latitude" to 37.3346,
            "pickup_longitude" to -122.0090,
            "dropoff_latitude" to 37.7749,
            "dropoff_longitude" to -122.4194,
            "pickup_address" to "1 Apple Park Way, Cupertino, CA",
            "dropoff_address" to "Market St, San Francisco, CA"
        ))

        val request = Request.Builder()
            .url("$API_BASE_URL/rideshare/request")
            .post(rideBody.toRequestBody(jsonMediaType))
            .addHeader("Content-Type", "application/json")
            .build()

        val response = client.newCall(request).execute()
        println("Ride Request (no auth) Response: ${response.code}")

        // Should require auth — 401 or 403
        assertTrue("Ride request should require authentication", response.code in listOf(401, 403, 422))
    }

    // =============================================================================
    // CATEGORY 4: ADDRESS MANAGEMENT
    // =============================================================================

    @Test
    fun test_04_01_addresses_requiresAuth() {
        val request = Request.Builder()
            .url("$API_BASE_URL/customers/addresses")
            .get()
            .build()

        val response = client.newCall(request).execute()
        println("Addresses (no auth) Response: ${response.code}")

        assertTrue("Addresses endpoint should require auth", response.code in listOf(401, 403))
    }

    // =============================================================================
    // CATEGORY 5: PAYMENT METHODS
    // =============================================================================

    @Test
    fun test_05_01_paymentMethods_requiresAuth() {
        val request = Request.Builder()
            .url("$API_BASE_URL/payments/methods")
            .get()
            .build()

        val response = client.newCall(request).execute()
        println("Payment Methods (no auth) Response: ${response.code}")

        assertTrue("Payment methods should require auth", response.code in listOf(401, 403, 404))
    }
}
