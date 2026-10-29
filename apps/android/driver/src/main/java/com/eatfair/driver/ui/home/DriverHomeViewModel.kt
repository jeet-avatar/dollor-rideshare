package com.eatfair.driver.ui.home

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.eatfair.driver.location.DriverLocationManager
import com.eatfair.shared.data.repository.DollorRepository
import com.eatfair.shared.model.rideshare.RideChatMessage
import com.eatfair.shared.model.rideshare.RideRequestForBidding
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import javax.inject.Inject

/**
 * Driver Home: online/offline (restored from GET /auth/driver/me), today's stats,
 * and the matched ride lifecycle (arrived/start/complete, cancel, no-show, chat,
 * rate rider) — mirrors iOS ActiveRideView.
 */
@HiltViewModel
class DriverHomeViewModel @Inject constructor(
    private val repository: DollorRepository,
    private val locationManager: DriverLocationManager
) : ViewModel() {

    data class HomeUiState(
        val isOnline: Boolean = false,
        val isToggling: Boolean = false,
        val todayEarnings: Double = 0.0,
        val todayRides: Int = 0,
        val todayHours: Double? = null,
        val activeRide: RideRequestForBidding? = null,
        val completedRide: RideRequestForBidding? = null,
        val isRideActionInProgress: Boolean = false,
        val chatOpen: Boolean = false,
        val chatMessages: List<RideChatMessage> = emptyList(),
        val error: String? = null,
        val message: String? = null
    )

    private val _uiState = MutableStateFlow(HomeUiState())
    val uiState: StateFlow<HomeUiState> = _uiState.asStateFlow()

    private var chatJob: Job? = null

    init {
        viewModelScope.launch {
            repository.getDriverMe().onSuccess { me ->
                _uiState.update { it.copy(isOnline = me.isOnline) }
            }
        }
        // Active-ride poll runs on its own short interval so a rider cancel clears the ride card within seconds,
        // independent of the slower online-status and stats calls below.
        viewModelScope.launch {
            while (isActive) {
                loadActiveRide()
                delay(ACTIVE_RIDE_POLL_MS)
            }
        }
        viewModelScope.launch {
            var tick = 0
            while (isActive) {
                // The server is the source of truth for online/offline; re-check it so a stale value self-corrects.
                if (!_uiState.value.isToggling) {
                    repository.getDriverMe().onSuccess { me ->
                        if (me.isOnline != _uiState.value.isOnline) {
                            _uiState.update { it.copy(isOnline = me.isOnline) }
                            if (me.isOnline) locationManager.startLocationUpdates() else locationManager.stopLocationUpdates()
                        }
                    }
                }
                if (tick % 6 == 0) loadTodayStats()
                tick++
                delay(5000)
            }
        }
    }

    fun refresh() {
        loadTodayStats()
        viewModelScope.launch { loadActiveRide() }
    }

    /** Called by the screen once location permission is granted while online. */
    fun onLocationPermissionGranted() {
        if (_uiState.value.isOnline) locationManager.startLocationUpdates()
    }

    private fun loadTodayStats() {
        viewModelScope.launch {
            repository.getDriverEarningsDetailed("today").onSuccess { earnings ->
                _uiState.update {
                    it.copy(
                        todayEarnings = earnings.total,
                        todayRides = earnings.deliveries,
                        todayHours = earnings.hoursOnline
                    )
                }
            }
        }
    }

    private suspend fun loadActiveRide() {
        repository.getDriverActiveRideRequests().onSuccess { rides ->
            val ride = rides.firstOrNull()
            _uiState.update { it.copy(activeRide = ride) }
            if (ride == null) closeChat()
        }
    }

    fun setOnline(target: Boolean) {
        if (!target && _uiState.value.activeRide != null) {
            _uiState.update { it.copy(error = "Finish or cancel your current ride before going offline.") }
            return
        }
        viewModelScope.launch {
            _uiState.update { it.copy(isToggling = true, error = null) }
            repository.setDriverOnline(target)
                .onSuccess { online ->
                    _uiState.update { it.copy(isOnline = online, isToggling = false) }
                    if (online) {
                        locationManager.startLocationUpdates()
                        loadActiveRide()
                    } else {
                        locationManager.stopLocationUpdates()
                    }
                }
                .onFailure { e ->
                    _uiState.update { it.copy(isToggling = false, error = e.message) }
                }
        }
    }

    fun markArrived() = rideAction("You've arrived — the rider has been notified") { repository.markRideRequestArrived(it) }

    fun startRide() = rideAction("Trip started") { repository.startRideRequest(it) }

    fun completeRide() {
        val ride = _uiState.value.activeRide ?: return
        viewModelScope.launch {
            _uiState.update { it.copy(isRideActionInProgress = true, error = null) }
            repository.completeRideRequest(ride.id)
                .onSuccess { resp ->
                    _uiState.update {
                        it.copy(
                            isRideActionInProgress = false,
                            activeRide = null,
                            completedRide = resp.rideRequest ?: ride
                        )
                    }
                    closeChat()
                    loadTodayStats()
                }
                .onFailure { e -> _uiState.update { it.copy(isRideActionInProgress = false, error = e.message) } }
        }
    }

    fun cancelRide(reason: String) = rideAction("Ride cancelled") { repository.driverCancelRide(it, reason) }

    fun markNoShow() = rideAction("Marked as no-show") { repository.markPassengerNoShow(it) }

    fun rateRider(rating: Int, comment: String?) {
        val ride = _uiState.value.completedRide ?: return
        viewModelScope.launch {
            repository.ratePassenger(ride.id, rating, comment?.ifBlank { null })
                .onSuccess { _uiState.update { it.copy(completedRide = null, message = "Thanks for rating your rider") } }
                .onFailure { e -> _uiState.update { it.copy(completedRide = null, error = e.message) } }
        }
    }

    fun dismissSummary() {
        _uiState.update { it.copy(completedRide = null) }
    }

    fun openChat() {
        val rideId = _uiState.value.activeRide?.id ?: return
        _uiState.update { it.copy(chatOpen = true) }
        chatJob?.cancel()
        chatJob = viewModelScope.launch {
            while (isActive) {
                repository.getDriverRideChat(rideId).onSuccess { msgs ->
                    _uiState.update { it.copy(chatMessages = msgs) }
                }
                delay(3000)
            }
        }
    }

    /** Report/block operations for the chat of [rideRequestId]; the other participant is the rider (customer). */
    fun chatSafetyOps(rideRequestId: Int): com.eatfair.shared.ui.ChatSafetyOps =
        object : com.eatfair.shared.ui.ChatSafetyOps {
            override suspend fun report(reason: String, details: String) =
                repository.reportChat(rideRequestId, reason, details)

            override suspend fun setBlocked(block: Boolean, userId: Int) =
                repository.setChatBlock(block, "customer", userId)

            override suspend fun fetchBlocks() = repository.getChatBlocks()
        }

    fun closeChat() {
        chatJob?.cancel()
        chatJob = null
        _uiState.update { it.copy(chatOpen = false) }
    }

    fun sendChat(text: String) {
        val rideId = _uiState.value.activeRide?.id ?: return
        if (text.isBlank()) return
        viewModelScope.launch {
            repository.sendDriverRideChat(rideId, text.trim())
                .onSuccess {
                    repository.getDriverRideChat(rideId).onSuccess { msgs ->
                        _uiState.update { it.copy(chatMessages = msgs) }
                    }
                }
                .onFailure { e -> _uiState.update { it.copy(error = e.message) } }
        }
    }

    private fun <T> rideAction(successText: String, action: suspend (Int) -> Result<T>) {
        val id = _uiState.value.activeRide?.id ?: return
        viewModelScope.launch {
            _uiState.update { it.copy(isRideActionInProgress = true, error = null) }
            action(id)
                .onSuccess {
                    _uiState.update { it.copy(isRideActionInProgress = false, message = successText) }
                    loadActiveRide()
                }
                .onFailure { e ->
                    _uiState.update { it.copy(isRideActionInProgress = false, error = e.message) }
                }
        }
    }

    fun clearError() {
        _uiState.update { it.copy(error = null) }
    }

    fun clearMessage() {
        _uiState.update { it.copy(message = null) }
    }

    override fun onCleared() {
        super.onCleared()
        locationManager.stopLocationUpdates()
    }

    private companion object {
        const val ACTIVE_RIDE_POLL_MS = 3000L
    }
}
