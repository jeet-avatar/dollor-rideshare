package com.eatfair.app.ui.founding

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.eatfair.app.data.CustomerRideshareApiService
import com.eatfair.app.data.SavedCard
import com.eatfair.shared.data.repository.DollorRepository
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import javax.inject.Inject

/**
 * Customer Founding Member ($100, non-refundable lifetime fee-lock).
 * Status: GET /api/founding/status?state=XX. Join: POST /api/founding/join {state, payment_method_id};
 * the backend charges the saved card itself (demo accounts are not charged) — iOS parity.
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
        val capPerState: Int? = null,
        val deposit: Double = 100.0,
        val benefit: String? = null,
        val isDemo: Boolean = false,
        val isJoining: Boolean = false,
        val confirmCard: SavedCard? = null,
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
            repository.getFoundingStatus(_uiState.value.selectedState)
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
                            capPerState = s.capPerState,
                            deposit = s.depositUsd,
                            benefit = s.benefit,
                            isDemo = s.isDemo
                        )
                    }
                }
                .onFailure { e -> _uiState.update { it.copy(isLoading = false, error = e.message) } }
        }
    }

    fun onJoinClicked() {
        val s = _uiState.value
        if (s.isDemo) {
            join(null)
            return
        }
        viewModelScope.launch {
            _uiState.update { it.copy(isJoining = true, error = null) }
            CustomerRideshareApiService.getSavedCards()
                .onSuccess { cards ->
                    val card = cards.firstOrNull { it.isDefault } ?: cards.firstOrNull()
                    _uiState.update {
                        if (card == null) it.copy(isJoining = false, error = "Add a card in Payment Methods first.")
                        else it.copy(isJoining = false, confirmCard = card)
                    }
                }
                .onFailure { e -> _uiState.update { it.copy(isJoining = false, error = e.message) } }
        }
    }

    fun confirmCharge() {
        val card = _uiState.value.confirmCard ?: return
        _uiState.update { it.copy(confirmCard = null) }
        join(card.id)
    }

    fun cancelCharge() = _uiState.update { it.copy(confirmCard = null) }

    private fun join(paymentMethodId: String?) {
        viewModelScope.launch {
            _uiState.update { it.copy(isJoining = true, error = null) }
            repository.joinFounding(_uiState.value.selectedState, paymentMethodId)
                .onSuccess {
                    _uiState.update { it.copy(isJoining = false, message = "Welcome, Founding Member!") }
                    loadStatus()
                }
                .onFailure { e -> _uiState.update { it.copy(isJoining = false, error = e.message) } }
        }
    }

    fun clearError() = _uiState.update { it.copy(error = null) }
    fun clearMessage() = _uiState.update { it.copy(message = null) }
}
