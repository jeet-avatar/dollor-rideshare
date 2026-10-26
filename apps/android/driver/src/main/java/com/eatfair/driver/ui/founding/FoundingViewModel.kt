package com.eatfair.driver.ui.founding

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.eatfair.shared.data.repository.DollorRepository
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import javax.inject.Inject

/**
 * Driver Founding Member ($100, non-refundable). Mirrors iOS FoundingMemberView: the card is
 * tokenized on-device into a Stripe PaymentMethod (screen), and POST /api/founding/driver/join
 * {state, payment_method_id} charges it server-side. Demo accounts are not charged.
 */
@HiltViewModel
class FoundingViewModel @Inject constructor(
    private val repository: DollorRepository
) : ViewModel() {

    data class UiState(
        val isLoading: Boolean = true,
        val selectedState: String = "CA",
        val isFounder: Boolean = false,
        val founderState: String? = null,
        val eligible: Boolean = false,
        val ridesTaken: Int = 0,
        val claimWindowRides: Int = 3,
        val slotsRemaining: Int? = null,
        val deposit: Double = 100.0,
        val benefit: String? = null,
        val isDemo: Boolean = false,
        val publishableKey: String? = null,
        val isJoining: Boolean = false,
        val error: String? = null,
        val message: String? = null
    )

    private val _uiState = MutableStateFlow(UiState())
    val uiState: StateFlow<UiState> = _uiState.asStateFlow()

    init {
        loadStatus()
    }

    fun selectState(code: String) {
        _uiState.update { it.copy(selectedState = code) }
        loadStatus()
    }

    fun loadStatus() {
        viewModelScope.launch {
            _uiState.update { it.copy(isLoading = true, error = null) }
            repository.getDriverFoundingStatus(_uiState.value.selectedState)
                .onSuccess { s ->
                    _uiState.update {
                        it.copy(
                            isLoading = false,
                            isFounder = s.isFounder,
                            founderState = s.founderState,
                            eligible = s.eligibleToJoin,
                            ridesTaken = s.ridesTaken,
                            claimWindowRides = s.claimWindowRides,
                            slotsRemaining = s.slotsRemaining,
                            deposit = s.depositUsd,
                            benefit = s.benefit,
                            isDemo = s.isDemo,
                            publishableKey = s.publishableKey
                        )
                    }
                }
                .onFailure { e -> _uiState.update { it.copy(isLoading = false, error = e.message) } }
        }
    }

    fun onTokenizing() = _uiState.update { it.copy(isJoining = true, error = null) }

    fun onTokenizeFailed(message: String?) =
        _uiState.update { it.copy(isJoining = false, error = message ?: "Card could not be verified") }

    /** [paymentMethodId] is null only for demo accounts. */
    fun join(paymentMethodId: String?) {
        viewModelScope.launch {
            _uiState.update { it.copy(isJoining = true, error = null) }
            repository.joinDriverFounding(_uiState.value.selectedState, paymentMethodId)
                .onSuccess {
                    _uiState.update { it.copy(isJoining = false, message = "Welcome, Founding Driver!") }
                    loadStatus()
                }
                .onFailure { e -> _uiState.update { it.copy(isJoining = false, error = e.message) } }
        }
    }

    fun clearError() = _uiState.update { it.copy(error = null) }
    fun clearMessage() = _uiState.update { it.copy(message = null) }
}
