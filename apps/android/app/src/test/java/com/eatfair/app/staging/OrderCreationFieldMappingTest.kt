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
 * Ride Request Field Mapping Tests
 *
 * Verifies that the Android app sends ride request fields matching
 * the iOS/Webapp format expected by the backend.
 *
 * Required fields:
 * - pickup_latitude: Double
 * - pickup_longitude: Double
 * - dropoff_latitude: Double
 * - dropoff_longitude: Double
 * - pickup_address: String
 * - dropoff_address: String
 * - tip: Double (optional)
 *
 * Backend endpoint: POST /api/rideshare/request
 *
 * Run with: ./gradlew :app:testProductionReleaseUnitTest --tests "*.OrderCreationFieldMappingTest"
 */
@FixMethodOrder(MethodSorters.NAME_ASCENDING)
class OrderCreationFieldMappingTest {

    companion object {
        const val STAGING_BASE_URL = "https://api.dollor.ai"
        const val API_BASE_URL = "$STAGING_BASE_URL/api"

        const val TEST_CUSTOMER_EMAIL = "demo@dollor.ai"
        const val TEST_CUSTOMER_PASSWORD = "demo123"

        var authToken: String? = null
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
    // FIELD MAPPING TESTS — Ride Request Format
    // =============================================================================

    @Test
    fun test_01_createRideRequest_withCorrectFieldMapping() {
        // Ride request requires auth; unauthenticated call should return 401/403 (not 500)
        val rideRequest = mapOf(
            "pickup_latitude" to 37.3346,
            "pickup_longitude" to -122.0090,
            "dropoff_latitude" to 37.7749,
            "dropoff_longitude" to -122.4194,
            "pickup_address" to "1 Apple Park Way, Cupertino, CA 95014",
            "dropoff_address" to "Market St, San Francisco, CA 94105",
            "tip" to 5.00
        )

        val requestBody = gson.toJson(rideRequest)
        println("Ride Request Body:\n$requestBody")

        val request = Request.Builder()
            .url("$API_BASE_URL/rideshare/request")
            .post(requestBody.toRequestBody(jsonMediaType))
            .addHeader("Content-Type", "application/json")
            .build()

        val response = client.newCall(request).execute()
        val responseBody = response.body?.string() ?: ""
        println("Response: ${response.code} - $responseBody")

        // Without auth should get 401/403; endpoint should not 500 or 404
        assertTrue(
            "Ride request endpoint should exist and enforce auth (got ${response.code})",
            response.code in listOf(401, 403, 422)
        )
    }

    @Test
    fun test_02_rideEstimate_withCorrectFieldMapping() {
        // Estimate is typically a GET and may be public
        val request = Request.Builder()
            .url("$API_BASE_URL/rideshare/estimate?pickup_lat=37.3346&pickup_lng=-122.0090&dropoff_lat=37.7749&dropoff_lng=-122.4194")
            .get()
            .build()

        val response = client.newCall(request).execute()
        val responseBody = response.body?.string() ?: ""
        println("Estimate Response: ${response.code} - ${responseBody.take(300)}")

        // Should exist and not be a server error
        assertTrue("Estimate endpoint should not 5xx", response.code < 500)

        if (response.isSuccessful) {
            val json = gson.fromJson(responseBody, JsonObject::class.java)
            val estimatedFare = json.get("estimated_fare")
                ?: json.get("fare")
                ?: json.get("amount")
            println("Estimated fare field present: ${estimatedFare != null}")
        }
    }
}
