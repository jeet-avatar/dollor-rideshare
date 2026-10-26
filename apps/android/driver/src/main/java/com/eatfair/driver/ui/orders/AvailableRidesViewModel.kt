package com.eatfair.driver.ui.orders

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.eatfair.driver.location.DriverLocationManager
import com.eatfair.shared.data.repository.DollorRepository
import com.eatfair.shared.model.rideshare.DriverOwnBid
import com.eatfair.shared.model.rideshare.RideRequestForBidding
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import javax.inject.Inject

/**
 * Loads open ride requests (GET /api/rides/available) and this driver's own bids
 * (GET /api/rides/driver/{id}/bids). Drivers can accept the rider's offer, counter
 * with their own price, and respond to a rider's counter-offer (matches iOS).
 */
@HiltViewModel
class AvailableRidesViewModel @Inject constructor(
    private val repository: DollorRepository,
    private val locationManager: DriverLocationManager
) : ViewModel() {

    data class UiState(
        val isLoading: Boolean = true,
        val rides: List<RideRequestForBidding> = emptyList(),
        val myBids: List<DriverOwnBid> = emptyList(),
        val closedBids: List<DriverOwnBid> = emptyList(),
        val busyId: Int? = null,
        val matchedRideId: Int? = null,
        val error: String? = null,
        val message: String? = null
    )

    private val _uiState = MutableStateFlow(UiState())
    private val announcedMatches = mutableSetOf<Int>()
    private val announcedClosures = mutableSetOf<Int>()
    val uiState: StateFlow<UiState> = _uiState.asStateFlow()

    init {
        load()
        viewModelScope.launch {
            while (isActive) {
                delay(5000)
                refresh()
            }
        }
    }

    fun load() {
        _uiState.update { it.copy(isLoading = true, error = null) }
        viewModelScope.launch { refresh() }
    }

    private suspend fun refresh() {
        val loc = locationManager.lastLocation.value
        val ridesResult = repository.getAvailableRideRequests(loc?.latitude, loc?.longitude)
        val allBids = repository.getDriverOwnBids().getOrNull()
        allBids?.firstOrNull { bid ->
            bid.status == "accepted" && bid.rideRequest?.status in setOf("matched", "in_progress")
        }?.takeIf { it.rideRequestId !in announcedMatches }
            ?.let { matched -> _uiState.update { it.copy(matchedRideId = matched.rideRequestId) } }
        val closed = allBids.orEmpty()
            .filter { it.closedReason != null }
            .sortedByDescending { it.id }
            .take(MAX_CLOSED_BIDS)
        // Tell the driver once when a ride they bid on went to someone else.
        closed.firstOrNull { it.closedReason == TAKEN_BY_OTHER && it.id !in announcedClosures }?.let { lost ->
            announcedClosures += lost.id
            _uiState.update { it.copy(message = "That ride was accepted by another driver") }
        }
        announcedClosures += closed.map { it.id }
        val bids = (allBids ?: _uiState.value.myBids)
            .filter { it.status == "pending" || it.status == "countered" }
            .filter { bid -> bid.rideRequest?.status.let { it == null || it in OPEN_RIDE_STATUSES } }
        val biddedIds = bids.map { it.rideRequestId }.toSet()
        ridesResult
            .onSuccess { rides ->
                _uiState.update { s ->
                    s.copy(isLoading = false, rides = rides.filterNot { it.id in biddedIds }, myBids = bids, closedBids = closed)
                }
            }
            .onFailure { e ->
                _uiState.update { it.copy(isLoading = false, myBids = bids, closedBids = closed, error = if (it.isLoading) e.message else null) }
            }
    }

    /** Accept the ride at the rider's offered price. */
    fun accept(ride: RideRequestForBidding) {
        val price = ride.riderOffer
        if (price == null || price <= 0.0) {
            _uiState.update { it.copy(error = "This request has no price to accept.") }
            return
        }
        placeBid(ride, price)
    }

    /** Counter the rider's offer with the driver's own price. */
    fun counter(ride: RideRequestForBidding, price: Double) = placeBid(ride, price)

    /** Bid from the bid sheet (price + estimated arrival + optional message), like iOS `SubmitBidSheet`. */
    fun submitBid(ride: RideRequestForBidding, price: Double, etaMinutes: Int, message: String?) =
        placeBid(ride, price, etaMinutes, message)

    private fun placeBid(ride: RideRequestForBidding, price: Double, etaMinutes: Int? = null, message: String? = null) {
        viewModelScope.launch {
            _uiState.update { it.copy(busyId = ride.id, error = null) }
            repository.submitRideBid(
                requestId = ride.id,
                proposedPrice = price,
                estimatedArrivalMinutes = etaMinutes,
                message = message
            )
                .onSuccess { resp ->
                    _uiState.update {
                        it.copy(busyId = null, message = resp.message.ifBlank { "Offer sent to rider" })
                    }
                    refresh()
                }
                .onFailure { e -> _uiState.update { it.copy(busyId = null, error = e.message) } }
        }
    }

    fun acceptCounter(bid: DriverOwnBid) =
        bidAction(bid, "Counter-offer accepted") { repository.acceptRiderCounter(bid.id) }

    fun rejectCounter(bid: DriverOwnBid) =
        bidAction(bid, "Counter-offer declined") { repository.rejectRiderCounter(bid.id) }

    fun finalCounter(bid: DriverOwnBid, price: Double) =
        bidAction(bid, "Final offer sent to rider") { repository.driverFinalCounter(bid.id, price) }

    private fun bidAction(
        bid: DriverOwnBid,
        successText: String,
        call: suspend () -> Result<com.eatfair.shared.model.rideshare.BidActionResponse>
    ) {
        viewModelScope.launch {
            _uiState.update { it.copy(busyId = bid.id, error = null) }
            call()
                .onSuccess { resp ->
                    _uiState.update { it.copy(busyId = null, message = resp.message ?: successText) }
                    refresh()
                }
                .onFailure { e -> _uiState.update { it.copy(busyId = null, error = e.message) } }
        }
    }

    /** Decline a ride request = remove it from this driver's list locally. */
    fun decline(ride: RideRequestForBidding) {
        _uiState.update { it.copy(rides = it.rides.filterNot { r -> r.id == ride.id }) }
    }

    fun clearError() {
        _uiState.update { it.copy(error = null) }
    }

    fun onMatchedRideShown() {
        _uiState.value.matchedRideId?.let { announcedMatches += it }
        _uiState.update { it.copy(matchedRideId = null) }
    }

    fun clearMessage() {
        _uiState.update { it.copy(message = null) }
    }

    private companion object {
        val OPEN_RIDE_STATUSES = setOf("open", "bidding")
    }
}

private const val MAX_CLOSED_BIDS = 3
private const val TAKEN_BY_OTHER = "Accepted by another driver"
