package com.eatfair.app.ui.rideshare

import android.Manifest
import android.content.Context
import android.content.pm.PackageManager
import android.location.Location
import android.util.Log
import androidx.core.content.ContextCompat
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.eatfair.app.data.CustomerRideshareApiService
import com.eatfair.shared.data.local.SecureStorage
import com.eatfair.shared.model.rideshare.*
import com.google.android.gms.location.FusedLocationProviderClient
import com.google.android.gms.location.LocationServices
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import javax.inject.Inject
import kotlin.math.*

/**
 * RideRequestViewModel - Manages customer ride request and bidding flow
 * Matches iOS RideRequestViewModel functionality
 *
 * Uses Hilt to inject SecureStorage for customer authentication.
 * Sets CustomerRideshareApiService.currentCustomerId from SecureStorage.
 */
@HiltViewModel
class RideRequestViewModel @Inject constructor(
    private val secureStorage: SecureStorage
) : ViewModel() {

    companion object {
        private const val TAG = "RideRequestViewModel"
        private val RESUMABLE_STATUSES = setOf("open", "bidding", "matched", "in_progress")
    }

    // ==========================================
    // AUTHENTICATION STATE
    // ==========================================

    private val _isAuthenticated = MutableStateFlow(false)
    val isAuthenticated: StateFlow<Boolean> = _isAuthenticated.asStateFlow()

    private val _authError = MutableStateFlow<String?>(null)
    val authError: StateFlow<String?> = _authError.asStateFlow()

    init {
        // Initialize CustomerRideshareApiService with SecureStorage (matches iOS pattern)
        // The service now reads customerId and customerToken directly from SecureStorage
        CustomerRideshareApiService.initialize(secureStorage)

        // Check authentication status using the service's isAuthenticated property
        if (CustomerRideshareApiService.isAuthenticated) {
            _isAuthenticated.value = true
            Log.d(TAG, "Customer authenticated via SecureStorage")
            restoreActiveRide()
        } else {
            _isAuthenticated.value = false
            _authError.value = "Please log in to request a ride"
            Log.w(TAG, "Customer not authenticated - please log in")
        }
    }

    /** Resume an open or in-flight ride after the app was closed or recreated. */
    private fun restoreActiveRide() {
        viewModelScope.launch {
            CustomerRideshareApiService.getMyRideRequests().onSuccess { requests ->
                val ride = requests
                    .filter { it.status.lowercase() in RESUMABLE_STATUSES }
                    .maxByOrNull { it.id } ?: return@onSuccess
                if (_activeRideRequest.value != null) return@onSuccess
                _activeRideRequest.value = ride
                when (ride.status.lowercase()) {
                    "open", "bidding" -> {
                        _currentStep.value = RideStep.WAITING_FOR_BIDS
                        startPollingForBids()
                    }
                    else -> {
                        _selectedBid.value = ride.acceptedBid
                        updateStepFromStatus(ride.status)
                        startTrackingRide()
                    }
                }
            }
        }
    }

    /**
     * Check if user is authenticated before making API calls
     * @return true if authenticated, false otherwise (also sets error message)
     */
    private fun requireAuth(): Boolean {
        if (!_isAuthenticated.value) {
            _authError.value = "Please log in to continue"
            _errorMessage.value = "Authentication required. Please log in."
            return false
        }
        return true
    }

    // ==========================================
    // LOCATION STATE
    // ==========================================

    private val _pickupLocation = MutableStateFlow<RideLocation?>(null)
    val pickupLocation: StateFlow<RideLocation?> = _pickupLocation.asStateFlow()

    private val _dropoffLocation = MutableStateFlow<RideLocation?>(null)
    val dropoffLocation: StateFlow<RideLocation?> = _dropoffLocation.asStateFlow()

    private val _currentLocation = MutableStateFlow<Location?>(null)
    val currentLocation: StateFlow<Location?> = _currentLocation.asStateFlow()

    private val _isGettingLocation = MutableStateFlow(false)
    val isGettingLocation: StateFlow<Boolean> = _isGettingLocation.asStateFlow()

    // ==========================================
    // FARE ESTIMATION
    // ==========================================

    private val _estimatedDistance = MutableStateFlow(0.0) // km
    val estimatedDistance: StateFlow<Double> = _estimatedDistance.asStateFlow()

    private val _estimatedDuration = MutableStateFlow(0) // minutes
    val estimatedDuration: StateFlow<Int> = _estimatedDuration.asStateFlow()

    private val _estimatedFare = MutableStateFlow(0.0)
    val estimatedFare: StateFlow<Double> = _estimatedFare.asStateFlow()

    // TNC-12 accessibility request (mirrors iOS RideRequestViewModel)
    private val _accessibilityRequested = MutableStateFlow(false)
    val accessibilityRequested: StateFlow<Boolean> = _accessibilityRequested.asStateFlow()
    private val _accessibilityOptions = MutableStateFlow<Set<String>>(emptySet())
    val accessibilityOptions: StateFlow<Set<String>> = _accessibilityOptions.asStateFlow()
    private val _accessibilityNotes = MutableStateFlow("")
    val accessibilityNotes: StateFlow<String> = _accessibilityNotes.asStateFlow()

    fun setAccessibilityRequested(requested: Boolean) {
        _accessibilityRequested.value = requested
        if (!requested) {
            _accessibilityOptions.value = emptySet()
            _accessibilityNotes.value = ""
        }
    }

    fun toggleAccessibilityOption(key: String) {
        val current = _accessibilityOptions.value
        _accessibilityOptions.value = if (key in current) current - key else current + key
    }

    fun setAccessibilityNotes(notes: String) {
        _accessibilityNotes.value = notes
    }

    /** Same JSON shape iOS sends: every option as a boolean plus optional free-text "notes". */
    private fun structuredAccessibilityNotes(): String? {
        if (!_accessibilityRequested.value) return null
        val json = org.json.JSONObject()
        ACCESSIBILITY_OPTION_KEYS.forEach { json.put(it, it in _accessibilityOptions.value) }
        val freeText = _accessibilityNotes.value.trim()
        if (freeText.isNotEmpty()) json.put("notes", freeText)
        return json.toString()
    }

    private val _suggestedPrice = MutableStateFlow<Double?>(null)
    val suggestedPrice: StateFlow<Double?> = _suggestedPrice.asStateFlow()

    // ==========================================
    // RIDE REQUEST STATE
    // ==========================================

    private val _activeRideRequest = MutableStateFlow<CustomerRideRequest?>(null)
    val activeRideRequest: StateFlow<CustomerRideRequest?> = _activeRideRequest.asStateFlow()

    private val _incomingBids = MutableStateFlow<List<DriverBidForCustomer>>(emptyList())
    val incomingBids: StateFlow<List<DriverBidForCustomer>> = _incomingBids.asStateFlow()

    private val _rideTracking = MutableStateFlow<CustomerRideTracking?>(null)
    val rideTracking: StateFlow<CustomerRideTracking?> = _rideTracking.asStateFlow()

    // ==========================================
    // UI STATE
    // ==========================================

    enum class RideStep {
        SELECT_PICKUP,
        SELECT_DROPOFF,
        CONFIRM_RIDE,
        WAITING_FOR_BIDS,
        VIEW_BIDS,
        MATCHED,
        DRIVER_EN_ROUTE,
        RIDE_IN_PROGRESS,
        COMPLETED
    }

    private val _currentStep = MutableStateFlow(RideStep.SELECT_PICKUP)
    val currentStep: StateFlow<RideStep> = _currentStep.asStateFlow()

    private val _isLoading = MutableStateFlow(false)
    val isLoading: StateFlow<Boolean> = _isLoading.asStateFlow()

    private val _errorMessage = MutableStateFlow<String?>(null)
    val errorMessage: StateFlow<String?> = _errorMessage.asStateFlow()

    private val _showError = MutableStateFlow(false)
    val showError: StateFlow<Boolean> = _showError.asStateFlow()

    private val _successMessage = MutableStateFlow<String?>(null)
    val successMessage: StateFlow<String?> = _successMessage.asStateFlow()

    private val _messageTitle = MutableStateFlow("Error")
    val messageTitle: StateFlow<String> = _messageTitle.asStateFlow()

    private var riderCancelling = false

    private val _showSuccess = MutableStateFlow(false)
    val showSuccess: StateFlow<Boolean> = _showSuccess.asStateFlow()

    // ==========================================
    // SELECTED BID
    // ==========================================

    private val _selectedBid = MutableStateFlow<DriverBidForCustomer?>(null)
    val selectedBid: StateFlow<DriverBidForCustomer?> = _selectedBid.asStateFlow()

    // ==========================================
    // TIP AMOUNT
    // ==========================================

    private val _selectedTipAmount = MutableStateFlow(0.0)
    val selectedTipAmount: StateFlow<Double> = _selectedTipAmount.asStateFlow()

    // ==========================================
    // PRIVATE
    // ==========================================

    private var pollingJob: Job? = null
    private val counteredBids = mutableMapOf<Int, DriverBidForCustomer>()
    private var trackingJob: Job? = null
    private var locationClient: FusedLocationProviderClient? = null

    // Platform fee (calculated dynamically based on fare)
    private val _platformFee = MutableStateFlow(0.0)
    val platformFee: StateFlow<Double> = _platformFee.asStateFlow()

    // ==========================================
    // INITIALIZATION
    // ==========================================

    private var appContext: Context? = null

    fun initialize(context: Context) {
        appContext = context.applicationContext
        locationClient = LocationServices.getFusedLocationProviderClient(context)
        getCurrentLocation(context)
    }

    @android.annotation.SuppressLint("MissingPermission")
    private fun getCurrentLocation(context: Context) {
        Log.d(TAG, "getCurrentLocation called")
        if (ContextCompat.checkSelfPermission(
                context,
                Manifest.permission.ACCESS_FINE_LOCATION
            ) == PackageManager.PERMISSION_GRANTED
        ) {
            Log.d(TAG, "Location permission granted, requesting fresh high-accuracy location")
            // Always request fresh location for accuracy
            requestFreshLocation()
        } else {
            Log.d(TAG, "Location permission NOT granted")
        }
    }

    @android.annotation.SuppressLint("MissingPermission")
    private fun requestFreshLocation() {
        Log.d(TAG, "requestFreshLocation called - requesting HIGH_ACCURACY GPS")
        val locationRequest = com.google.android.gms.location.LocationRequest.Builder(
            com.google.android.gms.location.Priority.PRIORITY_HIGH_ACCURACY,
            500L // Fast interval
        )
            .setWaitForAccurateLocation(true) // Wait for accurate GPS fix
            .setMinUpdateIntervalMillis(500L)
            .setMaxUpdates(3) // Get a few updates for better accuracy
            .build()

        locationClient?.requestLocationUpdates(
            locationRequest,
            object : com.google.android.gms.location.LocationCallback() {
                override fun onLocationResult(result: com.google.android.gms.location.LocationResult) {
                    result.lastLocation?.let { location ->
                        Log.d(TAG, "Fresh GPS location: ${location.latitude}, ${location.longitude}, accuracy: ${location.accuracy}m")
                        // Only use location if accuracy is good (< 50 meters)
                        if (location.accuracy < 100) {
                            _currentLocation.value = location
                            locationClient?.removeLocationUpdates(this)
                        } else {
                            Log.d(TAG, "Location accuracy poor (${location.accuracy}m), waiting for better fix")
                        }
                    }
                }
            },
            android.os.Looper.getMainLooper()
        )
    }

    // ==========================================
    // LOCATION SELECTION
    // ==========================================

    fun setPickupLocation(
        address: String,
        city: String?,
        state: String?,
        zip: String?,
        latitude: Double,
        longitude: Double
    ) {
        _pickupLocation.value = RideLocation(
            latitude = latitude,
            longitude = longitude,
            address = address,
            city = city,
            state = state,
            zip = zip
        )
        _currentStep.value = RideStep.SELECT_DROPOFF
    }

    /**
     * Use current GPS location for pickup with reverse geocoding
     */
    fun useCurrentLocationForPickup() {
        val context = appContext ?: return

        _isGettingLocation.value = true

        // Request fresh high-accuracy location
        requestFreshLocationForPickup(context)
    }

    @android.annotation.SuppressLint("MissingPermission")
    private fun requestFreshLocationForPickup(context: Context) {
        Log.d(TAG, "Requesting fresh GPS for pickup")

        val locationRequest = com.google.android.gms.location.LocationRequest.Builder(
            com.google.android.gms.location.Priority.PRIORITY_HIGH_ACCURACY,
            100L
        )
            .setWaitForAccurateLocation(true)
            .setMinUpdateIntervalMillis(100L)
            .setMaxUpdates(5)
            .build()

        locationClient?.requestLocationUpdates(
            locationRequest,
            object : com.google.android.gms.location.LocationCallback() {
                override fun onLocationResult(result: com.google.android.gms.location.LocationResult) {
                    result.lastLocation?.let { location ->
                        Log.d(TAG, "Got location for pickup: ${location.latitude}, ${location.longitude}, accuracy: ${location.accuracy}m")
                        if (location.accuracy < 100) {
                            _currentLocation.value = location
                            locationClient?.removeLocationUpdates(this)
                            geocodeAndSetPickup(location, context)
                        }
                    }
                }
            },
            android.os.Looper.getMainLooper()
        )
    }

    private fun geocodeAndSetPickup(location: Location, context: Context) {
        Log.d(TAG, "Geocoding location for pickup: ${location.latitude}, ${location.longitude}")

        // Use geocoder to get address from coordinates
        viewModelScope.launch {
            try {
                val geocoder = android.location.Geocoder(context, java.util.Locale.getDefault())
                val addresses = if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.TIRAMISU) {
                    kotlinx.coroutines.suspendCancellableCoroutine { cont ->
                        geocoder.getFromLocation(location.latitude, location.longitude, 1) { list ->
                            cont.resume(list) {}
                        }
                    }
                } else {
                    @Suppress("DEPRECATION")
                    geocoder.getFromLocation(location.latitude, location.longitude, 1)
                }

                val address = addresses?.firstOrNull()
                if (address != null) {
                    // Show full address with house number (subThoroughfare + thoroughfare)
                    // Example: "123 Main St" not just "Main St"
                    val streetNumber = address.subThoroughfare ?: ""
                    val streetName = address.thoroughfare ?: ""
                    val streetAddress = listOf(streetNumber, streetName)
                        .filter { it.isNotEmpty() }
                        .joinToString(" ")
                        .ifEmpty { address.featureName ?: "Current Location" }

                    Log.d(TAG, "Geocoded full address: $streetAddress, city=${address.locality}, state=${address.adminArea}")
                    Log.d(TAG, "SubThoroughfare: ${address.subThoroughfare}, Thoroughfare: ${address.thoroughfare}")

                    setPickupLocation(
                        address = streetAddress,
                        city = address.locality ?: address.subLocality,
                        state = address.adminArea,
                        zip = address.postalCode,
                        latitude = location.latitude,
                        longitude = location.longitude
                    )
                } else {
                    Log.w(TAG, "Geocoder returned no addresses")
                    // Fallback if geocoding fails
                    setPickupLocation(
                        address = "Current Location",
                        city = null,
                        state = null,
                        zip = null,
                        latitude = location.latitude,
                        longitude = location.longitude
                    )
                }
            } catch (e: Exception) {
                Log.e(TAG, "Geocoding failed", e)
                // Fallback
                setPickupLocation(
                    address = "Current Location",
                    city = null,
                    state = null,
                    zip = null,
                    latitude = location.latitude,
                    longitude = location.longitude
                )
            } finally {
                _isGettingLocation.value = false
            }
        }
    }

    fun setDropoffLocation(
        address: String,
        city: String?,
        state: String?,
        zip: String?,
        latitude: Double,
        longitude: Double
    ) {
        _dropoffLocation.value = RideLocation(
            latitude = latitude,
            longitude = longitude,
            address = address,
            city = city,
            state = state,
            zip = zip
        )
        _currentStep.value = RideStep.CONFIRM_RIDE
        calculateFareEstimate()
    }

    // ==========================================
    // FARE CALCULATION
    // ==========================================

    private fun calculateFareEstimate() {
        val pickup = _pickupLocation.value ?: return
        val dropoff = _dropoffLocation.value ?: return

        // Get state code from pickup location
        val stateCode = pickup.state?.take(2) ?: "CA"

        // Call backend API for real driving distance (matches iOS P2PAPIService.getFareEstimate)
        viewModelScope.launch {
            Log.d(TAG, "Calling fare estimate API - pickup: ${pickup.latitude},${pickup.longitude}, dropoff: ${dropoff.latitude},${dropoff.longitude}")

            val result = CustomerRideshareApiService.getFareEstimate(
                pickupLat = pickup.latitude,
                pickupLng = pickup.longitude,
                dropoffLat = dropoff.latitude,
                dropoffLng = dropoff.longitude,
                stateCode = stateCode
            )

            result.onSuccess { response ->
                Log.d(TAG, "Fare estimate API success - distance: ${response.estimate.distanceMiles} mi, duration: ${response.estimate.durationMinutes} min, fare: ${response.estimate.total}")

                // Use real driving distance from API
                _estimatedDistance.value = response.estimate.distanceMiles / 0.621371 // Convert miles to km
                _estimatedDuration.value = response.estimate.durationMinutes
                _estimatedFare.value = response.estimate.total
                _suggestedPrice.value = response.estimate.total
                _platformFee.value = response.estimate.platformFee

            }.onFailure { error ->
                Log.w(TAG, "Fare estimate API failed, using local calculation: ${error.message}")
                // Fall back to local Haversine calculation if API fails
                calculateFareEstimateLocally(pickup, dropoff)
            }
        }
    }

    /**
     * Fallback local fare calculation using Haversine formula
     * Used when API is unavailable
     */
    private fun calculateFareEstimateLocally(pickup: RideLocation, dropoff: RideLocation) {
        // Calculate distance using Haversine formula
        val distance = haversineDistance(
            pickup.latitude, pickup.longitude,
            dropoff.latitude, dropoff.longitude
        )

        // Estimate duration (25 mph average + 20% buffer)
        val duration = ((distance / 25.0) * 60 * 1.2).toInt()

        _estimatedDistance.value = distance / 0.621371 // Convert to km for storage
        _estimatedDuration.value = duration

        // Calculate fare using local calculation
        val fare = CustomerRideshareApiService.calculateEstimatedFare(
            _estimatedDistance.value,
            duration
        )
        _estimatedFare.value = fare
        _suggestedPrice.value = fare

        // Update platform fee based on fare
        _platformFee.value = CustomerRideshareApiService.calculatePlatformFee(fare)
    }

    /**
     * Haversine formula to calculate distance between two coordinates
     */
    private fun haversineDistance(lat1: Double, lon1: Double, lat2: Double, lon2: Double): Double {
        val R = 3959.0 // Earth's radius in miles

        val dLat = Math.toRadians(lat2 - lat1)
        val dLon = Math.toRadians(lon2 - lon1)

        val a = sin(dLat / 2) * sin(dLat / 2) +
                cos(Math.toRadians(lat1)) * cos(Math.toRadians(lat2)) *
                sin(dLon / 2) * sin(dLon / 2)

        val c = 2 * atan2(sqrt(a), sqrt(1 - a))

        return R * c
    }

    fun setSuggestedPrice(price: Double) {
        _suggestedPrice.value = price
        // Update platform fee based on new price
        _platformFee.value = CustomerRideshareApiService.calculatePlatformFee(price)
    }

    fun setTipAmount(amount: Double) {
        _selectedTipAmount.value = amount
    }

    /**
     * Post the selected tip to the driver once the ride is completed.
     * No-op when no tip was selected. 100% of the tip goes to the driver.
     * Backend: POST /api/rides/{ride_id}/tip (only accepted on COMPLETED rides).
     *
     * The ride-request id is used here deliberately: it is the same id the
     * tracking endpoint uses and the backend resolves it to the underlying ride.
     * Success/failure is now surfaced to the user (previously silently swallowed).
     */
    private fun submitTip() {
        val tip = _selectedTipAmount.value
        if (tip <= 0.0) return
        val rideRequest = _activeRideRequest.value ?: return

        viewModelScope.launch {
            CustomerRideshareApiService.tipRide(rideRequest.id, tip)
                .onSuccess {
                    Log.d(TAG, "Tip of $tip posted for ride ${rideRequest.id}")
                    showSuccessMessage("Your $${String.format("%.2f", tip)} tip was sent to your driver.")
                }
                .onFailure {
                    Log.w(TAG, "Failed to post tip: ${it.message}")
                    showErrorMessage("We couldn't send your tip: ${it.message ?: "please try again"}")
                }
        }
    }

    // ==========================================
    // RATE DRIVER
    // ==========================================

    private val _ratingSubmitted = MutableStateFlow(false)
    val ratingSubmitted: StateFlow<Boolean> = _ratingSubmitted.asStateFlow()

    /**
     * Submit a star rating (+ optional tags/comment) for the completed ride's
     * driver. Backend: POST /api/rides/{ride_id}/rate.
     */
    fun rateDriver(rating: Int, tags: List<String>, comment: String?) {
        val rideRequest = _activeRideRequest.value ?: return
        viewModelScope.launch {
            CustomerRideshareApiService.rateRide(rideRequest.id, rating, comment, tags)
                .onSuccess {
                    _ratingSubmitted.value = true
                    showSuccessMessage("Thanks for rating your driver!")
                }
                .onFailure {
                    showErrorMessage("Couldn't submit rating: ${it.message ?: "please try again"}")
                }
        }
    }

    // ==========================================
    // RIDE RECEIPT
    // ==========================================

    private val _rideReceipt = MutableStateFlow<com.eatfair.app.data.RideReceipt?>(null)
    val rideReceipt: StateFlow<com.eatfair.app.data.RideReceipt?> = _rideReceipt.asStateFlow()

    private val _isLoadingReceipt = MutableStateFlow(false)
    val isLoadingReceipt: StateFlow<Boolean> = _isLoadingReceipt.asStateFlow()

    /** Load the itemized receipt for the completed ride request. */
    fun loadReceipt() {
        val rideRequest = _activeRideRequest.value ?: return
        viewModelScope.launch {
            _isLoadingReceipt.value = true
            CustomerRideshareApiService.getRideReceipt(rideRequest.id)
                .onSuccess { _rideReceipt.value = it }
                .onFailure { showErrorMessage("Couldn't load receipt: ${it.message ?: "please try again"}") }
            _isLoadingReceipt.value = false
        }
    }

    // ==========================================
    // CREATE RIDE REQUEST
    // ==========================================

    fun createRideRequest() {
        if (!requireAuth()) return

        val pickup = _pickupLocation.value ?: run {
            showErrorMessage("Please select pickup location")
            return
        }
        val dropoff = _dropoffLocation.value ?: run {
            showErrorMessage("Please select dropoff location")
            return
        }

        _isLoading.value = true

        viewModelScope.launch {
            val result = CustomerRideshareApiService.createRideRequest(
                pickup = pickup,
                dropoff = dropoff,
                specialRequests = null,
                suggestedPrice = _suggestedPrice.value,
                accessibilityRequested = _accessibilityRequested.value,
                accessibilityNotes = structuredAccessibilityNotes()
            )

            _isLoading.value = false

            result.onSuccess { response ->
                val rideRequest = response.rideRequest
                if (response.success && rideRequest != null) {
                    _activeRideRequest.value = CustomerRideRequest(
                        id = response.rideRequestId ?: rideRequest.id,
                        pickup = pickup,
                        dropoff = dropoff,
                        suggestedPrice = _suggestedPrice.value,
                        estimatedDistanceKm = _estimatedDistance.value,
                        estimatedDurationMinutes = _estimatedDuration.value,
                        status = "open",
                        bids = emptyList(),
                        biddingExpiresAt = java.text.SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss", java.util.Locale.US)
                            .apply { timeZone = java.util.TimeZone.getTimeZone("UTC") }
                            .format(java.util.Date(System.currentTimeMillis() + CustomerRideshareApiService.BIDDING_WINDOW_MINUTES * 60_000L))
                    )
                    _currentStep.value = RideStep.WAITING_FOR_BIDS
                    startPollingForBids()
                    showSuccessMessage("Ride request created! Waiting for driver bids...")
                } else {
                    showErrorMessage(response.message)
                }
            }.onFailure { error ->
                showErrorMessage("Failed to create ride request: ${error.message}")
            }
        }
    }

    // ==========================================
    // POLLING FOR BIDS
    // ==========================================

    private fun startPollingForBids() {
        pollingJob?.cancel()
        pollingJob = viewModelScope.launch {
            while (isActive) {
                fetchBids()
                delay(3000) // Poll every 3 seconds
            }
        }
    }

    private fun stopPollingForBids() {
        pollingJob?.cancel()
        pollingJob = null
    }

    private suspend fun fetchBids() {
        val rideRequest = _activeRideRequest.value ?: return

        // A current server lists pending and countered bids, so a bid the driver declined or withdrew drops
        // out on the next poll. An older server lists pending bids only: keep the rider's countered bids
        // visible until the driver answers (a driver re-counter returns it as pending).
        CustomerRideshareApiService.getBidsForRide(rideRequest.id).onSuccess { response ->
            val bids = response.bids
            val visible = if (response.includesCountered) {
                counteredBids.clear()
                bids.filter { it.status.equals("countered", ignoreCase = true) }.forEach { counteredBids[it.id] = it }
                bids
            } else {
                bids.forEach { counteredBids.remove(it.id) }
                bids + counteredBids.values
            }
            _incomingBids.value = visible
            if (visible.isNotEmpty() && _currentStep.value == RideStep.WAITING_FOR_BIDS) {
                _currentStep.value = RideStep.VIEW_BIDS
            }
        }

        // Detect the driver accepting a counter-offer, or the bidding window expiring.
        CustomerRideshareApiService.trackRide(rideRequest.id).onSuccess { tracking ->
            when (tracking.status.lowercase()) {
                "matched", "accepted", "driver_en_route", "en_route" -> {
                    _selectedBid.value = counteredBids.values.firstOrNull() ?: _selectedBid.value
                    counteredBids.clear()
                    stopPollingForBids()
                    _rideTracking.value = tracking
                    updateStepFromStatus(tracking.status)
                    showSuccessMessage("A driver accepted your ride!")
                    startTrackingRide()
                }
                "expired", "cancelled" -> {
                    counteredBids.clear()
                    stopPollingForBids()
                    _incomingBids.value = emptyList()
                    _activeRideRequest.value = null
                    _currentStep.value = RideStep.CONFIRM_RIDE
                    showInfoMessage("No driver accepted in time. Please request again, or try a higher offer.")
                }
            }
        }
    }

    // ==========================================
    // BID ACTIONS
    // ==========================================

    fun acceptBid(bid: DriverBidForCustomer) {
        if (!requireAuth()) return

        _isLoading.value = true
        _selectedBid.value = bid

        viewModelScope.launch {
            val result = CustomerRideshareApiService.acceptBid(bid.id)

            _isLoading.value = false

            result.onSuccess { response ->
                if (response.success) {
                    stopPollingForBids()
                    _currentStep.value = RideStep.MATCHED
                    showSuccessMessage("Bid accepted! Driver is on the way.")
                    startTrackingRide()
                } else {
                    showErrorMessage(response.message)
                }
            }.onFailure { error ->
                showErrorMessage("Failed to accept bid: ${error.message}")
            }
        }
    }

    fun rejectBid(bid: DriverBidForCustomer) {
        if (!requireAuth()) return

        viewModelScope.launch {
            val result = CustomerRideshareApiService.rejectBid(bid.id)
            result.onSuccess {
                // Remove from list
                _incomingBids.value = _incomingBids.value.filter { it.id != bid.id }
            }
        }
    }

    fun counterBid(bid: DriverBidForCustomer, counterPrice: Double, message: String?) {
        if (!requireAuth()) return

        _isLoading.value = true

        viewModelScope.launch {
            val result = CustomerRideshareApiService.counterBid(bid.id, counterPrice, message)

            _isLoading.value = false

            result.onSuccess { response ->
                if (response.success) {
                    showSuccessMessage("Counter-offer sent to driver!")
                    val countered = bid.copy(status = "countered", customerCounterPrice = counterPrice)
                    counteredBids[bid.id] = countered
                    _incomingBids.value = _incomingBids.value.map { if (it.id == bid.id) countered else it }
                } else {
                    showErrorMessage(response.message)
                }
            }.onFailure { error ->
                showErrorMessage("Failed to send counter-offer: ${error.message}")
            }
        }
    }

    // ==========================================
    // RIDE TRACKING
    // ==========================================

    private fun startTrackingRide() {
        trackingJob?.cancel()
        trackingJob = viewModelScope.launch {
            while (isActive) {
                fetchRideTracking()
                delay(5000) // Poll every 5 seconds
            }
        }
    }

    private fun stopTrackingRide() {
        trackingJob?.cancel()
        trackingJob = null
    }

    private suspend fun fetchRideTracking() {
        val rideRequest = _activeRideRequest.value ?: return

        val result = CustomerRideshareApiService.trackRide(rideRequest.id)
        result.onSuccess { tracking ->
            _rideTracking.value = tracking
            updateStepFromStatus(tracking.status)
        }
    }

    private fun updateStepFromStatus(status: String) {
        when (status.lowercase()) {
            "matched", "accepted" -> _currentStep.value = RideStep.MATCHED
            "driver_en_route", "en_route" -> _currentStep.value = RideStep.DRIVER_EN_ROUTE
            "picked_up", "in_progress" -> _currentStep.value = RideStep.RIDE_IN_PROGRESS
            "completed" -> {
                _currentStep.value = RideStep.COMPLETED
                submitTip()
                stopTrackingRide()
            }
            "cancelled", "expired" -> {
                if (_currentStep.value in setOf(RideStep.MATCHED, RideStep.DRIVER_EN_ROUTE, RideStep.RIDE_IN_PROGRESS)) {
                    if (!riderCancelling) showInfoMessage("Your ride was cancelled. You can request a new ride anytime.")
                    resetRide()
                }
            }
            "open", "bidding" -> {
                // The matched driver cancelled and the request went back out for bids.
                if (_currentStep.value in setOf(RideStep.MATCHED, RideStep.DRIVER_EN_ROUTE)) {
                    stopTrackingRide()
                    _selectedBid.value = null
                    _rideTracking.value = null
                    _incomingBids.value = emptyList()
                    _currentStep.value = RideStep.WAITING_FOR_BIDS
                    showInfoMessage("Your driver cancelled. We're finding you another driver.")
                    startPollingForBids()
                }
            }
        }
    }

    // ==========================================
    // CANCEL RIDE
    // ==========================================

    fun cancelRide() {
        if (!requireAuth()) return

        val rideRequest = _activeRideRequest.value ?: return

        _isLoading.value = true
        riderCancelling = true

        viewModelScope.launch {
            val result = CustomerRideshareApiService.cancelRideRequest(rideRequest.id)

            _isLoading.value = false

            result.onSuccess {
                stopPollingForBids()
                stopTrackingRide()
                showSuccessMessage("Ride cancelled")
                resetRide()
            }.onFailure { error ->
                showErrorMessage("Failed to cancel ride: ${error.message}")
            }
            riderCancelling = false
        }
    }

    // ==========================================
    // RESET
    // ==========================================

    fun resetRide() {
        _ratingSubmitted.value = false
        setAccessibilityRequested(false)
        stopPollingForBids()
        stopTrackingRide()
        _pickupLocation.value = null
        _dropoffLocation.value = null
        _estimatedDistance.value = 0.0
        _estimatedDuration.value = 0
        _estimatedFare.value = 0.0
        _suggestedPrice.value = null
        _activeRideRequest.value = null
        _incomingBids.value = emptyList()
        counteredBids.clear()
        _rideTracking.value = null
        _selectedBid.value = null
        _currentStep.value = RideStep.SELECT_PICKUP
    }

    // ==========================================
    // HELPERS
    // ==========================================

    private fun showInfoMessage(message: String) {
        _messageTitle.value = "Ride update"
        _errorMessage.value = message
        _showError.value = true
    }

    private fun showErrorMessage(message: String) {
        _messageTitle.value = "Error"
        _errorMessage.value = message
        _showError.value = true
    }

    private fun showSuccessMessage(message: String) {
        _successMessage.value = message
        _showSuccess.value = true
    }

    fun dismissError() {
        _showError.value = false
        _errorMessage.value = null
    }

    fun dismissSuccess() {
        _showSuccess.value = false
        _successMessage.value = null
    }

    // ==========================================
    // COMPUTED VALUES
    // ==========================================

    val canRequestRide: Boolean
        get() = _pickupLocation.value != null && _dropoffLocation.value != null

    val totalWithPlatformFee: Double
        get() = CustomerRideshareApiService.calculateTotal(_estimatedFare.value)

    val driverEarnings: Double
        get() = CustomerRideshareApiService.calculateDriverEarnings(_estimatedFare.value)

    val formattedDistance: String
        get() {
            val km = _estimatedDistance.value
            val miles = km * 0.621371
            return if (miles > 0) String.format("%.1f mi", miles) else "--"
        }

    val formattedDuration: String
        get() {
            val minutes = _estimatedDuration.value
            return if (minutes > 0) "$minutes min" else "--"
        }

    // Distance fee - per mile charge
    val distanceFee: Double
        get() {
            val km = _estimatedDistance.value
            val miles = km * 0.621371
            return miles * com.eatfair.shared.config.AppConfig.Rideshare.PER_MILE_RATE
        }

    // Time fee - per minute charge
    val timeFee: Double
        get() {
            return _estimatedDuration.value * com.eatfair.shared.config.AppConfig.Rideshare.PER_MINUTE_RATE
        }

    // Base fare constant
    val baseFare: Double
        get() = com.eatfair.shared.config.AppConfig.Rideshare.BASE_FARE

    // Platform fee tier description
    val platformFeeTierDescription: String
        get() = com.eatfair.shared.config.AppConfig.Rideshare.getTierName(_estimatedFare.value)

    override fun onCleared() {
        super.onCleared()
        stopPollingForBids()
        stopTrackingRide()
    }
}

val ACCESSIBILITY_OPTION_KEYS = listOf("wheelchair", "service_animal", "mobility_storage", "audio_visual")
