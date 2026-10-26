package com.eatfair.shared.model.rideshare

import com.google.gson.annotations.SerializedName

/**
 * Location data for pickup/dropoff
 */
data class RideLocation(
    @SerializedName("latitude") val latitude: Double,
    @SerializedName("longitude") val longitude: Double,
    @SerializedName("address") val address: String,
    @SerializedName("city") val city: String? = null,
    @SerializedName("state") val state: String? = null,
    @SerializedName("zip") val zip: String? = null
) {
    val fullAddress: String
        get() {
            val parts = mutableListOf(address)
            city?.let { parts.add(it) }
            state?.let { parts.add(it) }
            zip?.let { parts.add(it) }
            return parts.joinToString(", ")
        }
}

/** A bid this driver placed - GET /api/rides/driver/{driver_id}/bids */
data class DriverOwnBid(
    @SerializedName("id") val id: Int,
    @SerializedName("ride_request_id") val rideRequestId: Int,
    @SerializedName("proposed_price") val proposedPrice: Double,
    @SerializedName("status") val status: String,
    @SerializedName("customer_counter_price") val customerCounterPrice: Double? = null,
    @SerializedName("ride_request") val rideRequest: RideRequestForBidding? = null
) {
    val isCountered: Boolean get() = status == "countered" && customerCounterPrice != null

    /**
     * Why this bid is no longer live, or null while it is still open. The server marks every losing bid
     * `rejected`, which a rider's explicit decline also does — so the ride's own status tells them apart.
     */
    val closedReason: String?
        get() = when (status) {
            "rejected" ->
                if (rideRequest?.status in TAKEN_RIDE_STATUSES) "Accepted by another driver" else "Declined by rider"
            "expired" -> "Offer expired"
            "withdrawn" -> "You withdrew this offer"
            else -> null
        }

    companion object {
        private val TAKEN_RIDE_STATUSES = setOf("matched", "in_progress", "completed")
    }
}

data class DriverOwnBidsResponse(
    @SerializedName("bids") val bids: List<DriverOwnBid> = emptyList()
)

data class DriverCounterRequest(
    @SerializedName("counter_price") val counterPrice: Double
)

data class BidActionResponse(
    @SerializedName("success") val success: Boolean = false,
    @SerializedName("message") val message: String? = null
)

/**
 * Ride request available for bidding - matches iOS RideRequestForBidding
 */
data class RideRequestForBidding(
    @SerializedName("id") val id: Int,
    @SerializedName("customer_id") val customerId: Int? = null,
    @SerializedName("customer_name") val customerName: String? = null,
    @SerializedName("pickup") val pickup: RideLocation,
    @SerializedName("dropoff") val dropoff: RideLocation,
    @SerializedName("suggested_price") val suggestedPrice: Double? = null,
    @SerializedName("customer_preferred_price") val customerPreferredPrice: Double? = null,
    @SerializedName("estimated_distance_km") val estimatedDistanceKm: Double? = null,
    @SerializedName("estimated_duration_minutes") val estimatedDurationMinutes: Int? = null,
    @SerializedName("distance_to_pickup_km") val distanceToPickupKm: Double? = null,
    @SerializedName("bid_count") val bidCount: Int? = null,
    @SerializedName("special_requests") val specialRequests: String? = null,
    @SerializedName("status") val status: String? = null,
    @SerializedName("created_at") val createdAt: String? = null,
    @SerializedName("expires_at") val expiresAt: String? = null,
    @SerializedName("final_price") val finalPrice: Double? = null,
    @SerializedName("driver_payout") val driverPayout: Double? = null,
    @SerializedName("platform_fee") val platformFee: Double? = null,
    @SerializedName("tip_amount") val tipAmount: Double? = null,
    @SerializedName("matched_at") val matchedAt: String? = null,
    @SerializedName("driver_arrived_at") val driverArrivedAt: String? = null,
    @SerializedName("customer_phone") val customerPhone: String? = null,
    @SerializedName("accessibility_requested") val accessibilityRequested: Boolean? = null,
    @SerializedName("accessibility_notes") val accessibilityNotes: String? = null
) {
    /** Human-readable accessibility needs, e.g. "Wheelchair accessible vehicle, Service animal". */
    val accessibilitySummary: String?
        get() {
            if (accessibilityRequested != true) return null
            val labels = linkedMapOf(
                "wheelchair" to "Wheelchair accessible vehicle",
                "service_animal" to "Service animal",
                "mobility_storage" to "Mobility aid storage",
                "audio_visual" to "Audio/visual assistance"
            )
            val parts = mutableListOf<String>()
            var note: String? = null
            try {
                val json = org.json.JSONObject(accessibilityNotes ?: "{}")
                labels.forEach { (key, label) -> if (json.optBoolean(key, false)) parts.add(label) }
                note = json.optString("notes").takeIf { it.isNotBlank() }
            } catch (e: Exception) {
                note = accessibilityNotes?.takeIf { it.isNotBlank() }
            }
            note?.let { parts.add("Note: $it") }
            return if (parts.isEmpty()) "Accessible vehicle requested" else parts.joinToString(" · ")
        }

    val hasArrived: Boolean get() = driverArrivedAt != null
    val isInProgress: Boolean get() = status.equals("in_progress", ignoreCase = true)

    /** What the rider is offering to pay; falls back to the suggested fare. */
    val riderOffer: Double?
        get() = customerPreferredPrice ?: suggestedPrice

    val formattedTripDistance: String
        get() {
            val km = estimatedDistanceKm ?: return "--"
            val miles = km * 0.621371
            return String.format("%.1f mi", miles)
        }

    val formattedPickupDistance: String
        get() {
            val km = distanceToPickupKm ?: return "--"
            val miles = km * 0.621371
            return String.format("%.1f mi", miles)
        }

    val formattedDuration: String
        get() {
            val minutes = estimatedDurationMinutes ?: return "--"
            return if (minutes < 60) {
                "$minutes min"
            } else {
                val hours = minutes / 60
                val mins = minutes % 60
                "${hours}h ${mins}m"
            }
        }

    val tripDistanceMiles: Double?
        get() = estimatedDistanceKm?.let { it * 0.621371 }
}

/**
 * Driver's bid on a ride request - matches iOS RideBid
 */
data class RideBid(
    @SerializedName("id") val id: Int,
    @SerializedName("ride_request_id") val rideRequestId: Int,
    @SerializedName("driver_id") val driverId: Int,
    @SerializedName("proposed_price") val proposedPrice: Double,
    @SerializedName("estimated_arrival_minutes") val estimatedArrivalMinutes: Int? = null,
    @SerializedName("message") val message: String? = null,
    @SerializedName("status") val status: String, // pending, accepted, rejected, countered
    @SerializedName("customer_counter_price") val customerCounterPrice: Double? = null,
    @SerializedName("customer_counter_message") val customerCounterMessage: String? = null,
    @SerializedName("ride_request") val rideRequest: RideRequestForBidding? = null,
    @SerializedName("created_at") val createdAt: String? = null,
    @SerializedName("expires_at") val expiresAt: String? = null
) {
    val finalPrice: Double
        get() = customerCounterPrice ?: proposedPrice

    val isPending: Boolean
        get() = status == "pending"

    val isCountered: Boolean
        get() = status == "countered"

    val isAccepted: Boolean
        get() = status == "accepted"
}

/**
 * Response from submitting a bid
 */
data class SubmitBidResponse(
    @SerializedName("success") val success: Boolean,
    @SerializedName("message") val message: String,
    @SerializedName("bid_id") val bidId: Int? = null,
    @SerializedName("bid") val bid: RideBid? = null
)

/**
 * Response from counter-offer action
 */
data class CounterOfferResponse(
    @SerializedName("success") val success: Boolean,
    @SerializedName("message") val message: String,
    @SerializedName("status") val status: String? = null,
    @SerializedName("ride_request") val rideRequest: RideRequestForBidding? = null
)

/**
 * Response from ride status update
 */
data class RideStatusResponse(
    @SerializedName("success") val success: Boolean,
    @SerializedName("message") val message: String,
    @SerializedName("status") val status: String? = null,
    @SerializedName("ride_request") val rideRequest: RideRequestForBidding? = null
)

data class DriverCancelRideRequest(@SerializedName("reason") val reason: String)

data class PassengerRatingRequest(
    @SerializedName("rating") val rating: Int,
    @SerializedName("comment") val comment: String? = null
)

/** GET /api/p2p/ride-requests/{id}/chat */
data class RideChatListResponse(
    @SerializedName("messages") val messages: List<RideChatMessage> = emptyList()
)

/** POST /api/p2p/ride-requests/{id}/chat */
data class SendRideChatRequest(
    @SerializedName("message") val message: String,
    @SerializedName("sender_type") val senderType: String
)

data class DriverMeResponse(
    @SerializedName("id") val id: Int,
    @SerializedName("status") val status: String? = null,
    @SerializedName("is_online") val isOnline: Boolean = false,
    @SerializedName("phone") val phone: String? = null
)

/**
 * Chat message between driver and rider
 */
data class RideChatMessage(
    @SerializedName("id") val id: Int,
    @SerializedName("ride_request_id") val rideRequestId: Int,
    @SerializedName("sender_type") val senderType: String, // driver, customer
    @SerializedName("sender_id") val senderId: Int,
    @SerializedName("message") val message: String,
    @SerializedName("created_at") val createdAt: String
) {
    val isFromDriver: Boolean
        get() = senderType == "driver"
}

/**
 * Request body for submitting a bid
 */
data class SubmitBidRequest(
    @SerializedName("proposed_price") val proposedPrice: Double,
    @SerializedName("estimated_arrival_minutes") val estimatedArrivalMinutes: Int,
    @SerializedName("message") val message: String? = null
)

/**
 * Request body for counter-offer response
 */
data class CounterOfferActionRequest(
    @SerializedName("action") val action: String, // accept, reject, counter
    @SerializedName("counter_price") val counterPrice: Double? = null
)

// ==========================================
// CUSTOMER-SIDE MODELS
// ==========================================

/**
 * Request to create a ride request
 */
data class CreateRideRequest(
    @SerializedName("pickup") val pickup: RideLocation,
    @SerializedName("dropoff") val dropoff: RideLocation,
    @SerializedName("customer_name") val customerName: String,
    @SerializedName("customer_phone") val customerPhone: String? = null,
    @SerializedName("special_requests") val specialRequests: String? = null,
    @SerializedName("suggested_price") val suggestedPrice: Double? = null
)

/**
 * Response from creating a ride request
 */
data class CreateRideResponse(
    @SerializedName("success") val success: Boolean,
    @SerializedName("message") val message: String,
    @SerializedName("ride_request_id") val rideRequestId: Int? = null,
    @SerializedName("ride_request") val rideRequest: RideRequestForBidding? = null
)

/**
 * Customer's view of a bid from a driver
 */
data class DriverBidForCustomer(
    @SerializedName("id") val id: Int,
    @SerializedName("driver_id") val driverId: Int,
    @SerializedName("driver_name") val driverName: String? = null,
    @SerializedName("driver_rating") val driverRating: Double? = null,
    @SerializedName("driver_trips") val driverTrips: Int? = null,
    @SerializedName("driver_photo_url") val driverPhotoUrl: String? = null,
    @SerializedName("proposed_price") val proposedPrice: Double,
    @SerializedName("estimated_arrival_minutes") val estimatedArrivalMinutes: Int? = null,
    @SerializedName("message") val message: String? = null,
    @SerializedName("status") val status: String,
    @SerializedName(value = "vehicle_make", alternate = ["driver_vehicle_make"]) val vehicleMake: String? = null,
    @SerializedName(value = "vehicle_model", alternate = ["driver_vehicle_model"]) val vehicleModel: String? = null,
    @SerializedName(value = "vehicle_color", alternate = ["driver_vehicle_color"]) val vehicleColor: String? = null,
    @SerializedName(value = "vehicle_plate", alternate = ["driver_license_plate"]) val vehiclePlate: String? = null,
    @SerializedName("created_at") val createdAt: String? = null,
    @SerializedName("customer_counter_price") val customerCounterPrice: Double? = null
) {
    val formattedArrival: String
        get() = estimatedArrivalMinutes?.let { "$it min" } ?: "--"

    val formattedRating: String
        get() = driverRating?.let { String.format("%.1f", it) } ?: "--"

    val formattedTrips: String
        get() = driverTrips?.toString() ?: "New"

    val vehicleInfo: String
        get() {
            val parts = listOfNotNull(vehicleColor, vehicleMake, vehicleModel).filter { it.isNotEmpty() }
            return if (parts.isNotEmpty()) parts.joinToString(" ") else "Vehicle info not available"
        }
}

/**
 * Customer's ride request with bids
 */
data class CustomerRideRequest(
    @SerializedName("id") val id: Int,
    @SerializedName("pickup") val pickup: RideLocation,
    @SerializedName("dropoff") val dropoff: RideLocation,
    @SerializedName("suggested_price") val suggestedPrice: Double? = null,
    @SerializedName("estimated_distance_km") val estimatedDistanceKm: Double? = null,
    @SerializedName("estimated_duration_minutes") val estimatedDurationMinutes: Int? = null,
    @SerializedName("status") val status: String,
    @SerializedName("bids") val bids: List<DriverBidForCustomer> = emptyList(),
    @SerializedName("accepted_bid") val acceptedBid: DriverBidForCustomer? = null,
    @SerializedName("created_at") val createdAt: String? = null,
    @SerializedName("bidding_expires_at") val biddingExpiresAt: String? = null
) {
    /** When bidding closes, as epoch millis (server sends UTC ISO without a zone suffix). */
    val biddingExpiresAtMillis: Long?
        get() = biddingExpiresAt?.take(19)?.let {
            try {
                java.text.SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss", java.util.Locale.US)
                    .apply { timeZone = java.util.TimeZone.getTimeZone("UTC") }
                    .parse(it)?.time
            } catch (e: Exception) { null }
        }

    val formattedDistance: String
        get() {
            val km = estimatedDistanceKm ?: return "--"
            val miles = km * 0.621371
            return String.format("%.1f mi", miles)
        }

    val formattedDuration: String
        get() {
            val minutes = estimatedDurationMinutes ?: return "--"
            return if (minutes < 60) "$minutes min" else "${minutes / 60}h ${minutes % 60}m"
        }

    val isWaitingForBids: Boolean
        get() = status == "open" || status == "pending"

    val hasAcceptedBid: Boolean
        get() = status == "matched" || acceptedBid != null

    val isInProgress: Boolean
        get() = status == "in_progress"

    val isCompleted: Boolean
        get() = status == "completed"
}

/**
 * Customer counter-offer request
 */
data class CustomerCounterOfferRequest(
    @SerializedName("action") val action: String, // accept, reject, counter
    @SerializedName("counter_price") val counterPrice: Double? = null,
    @SerializedName("message") val message: String? = null
)

/**
 * Active ride tracking info for customer
 */
data class CustomerRideTracking(
    @SerializedName("ride_request_id") val rideRequestId: Int,
    @SerializedName("ride_number") val rideNumber: String? = null,
    @SerializedName("status") val status: String,
    @SerializedName("driver") val driver: DriverInfo? = null,
    @SerializedName("driver_location") val driverLocation: RideLocation? = null,
    @SerializedName("eta_minutes") val etaMinutes: Int? = null,
    @SerializedName("pickup") val pickup: RideLocation,
    @SerializedName("dropoff") val dropoff: RideLocation,
    @SerializedName("final_price") val finalPrice: Double? = null,
    @SerializedName("driver_arrived_at") val driverArrivedAt: String? = null
) {
    /** True once the driver tapped "I've arrived". */
    val hasDriverArrived: Boolean get() = driverArrivedAt != null
}

/**
 * Driver info for customer view
 */
data class DriverInfo(
    @SerializedName("id") val id: Int,
    @SerializedName("name") val name: String,
    @SerializedName("phone") val phone: String? = null,
    @SerializedName("rating") val rating: Double? = null,
    @SerializedName("photo_url") val photoUrl: String? = null,
    @SerializedName("latitude") val latitude: Double? = null,
    @SerializedName("longitude") val longitude: Double? = null,
    @SerializedName(value = "vehicle_make", alternate = ["driver_vehicle_make"]) val vehicleMake: String? = null,
    @SerializedName(value = "vehicle_model", alternate = ["driver_vehicle_model"]) val vehicleModel: String? = null,
    @SerializedName(value = "vehicle_color", alternate = ["driver_vehicle_color"]) val vehicleColor: String? = null,
    @SerializedName(value = "vehicle_plate", alternate = ["driver_license_plate"]) val vehiclePlate: String? = null
) {
    val vehicleInfo: String
        get() {
            val parts = listOfNotNull(vehicleColor, vehicleMake, vehicleModel).filter { it.isNotEmpty() }
            return if (parts.isNotEmpty()) parts.joinToString(" ") else "Vehicle"
        }
}

/** GET/PATCH /api/tnc/driver/accessibility (TNC-12) */
data class DriverAccessibilitySettings(
    @SerializedName("accessibility_capable") val accessibilityCapable: Boolean = false,
    @SerializedName("accessibility_features") val accessibilityFeatures: Map<String, Boolean>? = null
)
