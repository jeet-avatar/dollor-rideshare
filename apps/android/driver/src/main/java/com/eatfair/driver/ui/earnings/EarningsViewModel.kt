package com.eatfair.driver.ui.earnings

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.eatfair.shared.data.repository.DollorRepository
import com.eatfair.shared.model.driver.DriverEarningsResponse
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import javax.inject.Inject

data class EarningsUiState(
    val isLoading: Boolean = true,
    val error: String? = null,
    val earnings: DriverEarningsResponse? = null,
    val selectedPeriod: String = "today",
    val isRequestingPayout: Boolean = false,
    val payoutMessage: String? = null
)

/**
 * Backs the driver Earnings screen with real data from
 * GET /api/drivers/{id}/earnings (auth handled by the repository), plus
 * payout requests via POST /api/drivers/{id}/payouts.
 */
@HiltViewModel
class EarningsViewModel @Inject constructor(
    private val repository: DollorRepository
) : ViewModel() {

    private val _uiState = MutableStateFlow(EarningsUiState())
    val uiState: StateFlow<EarningsUiState> = _uiState.asStateFlow()

    init {
        loadEarnings()
    }

    fun loadEarnings() {
        viewModelScope.launch {
            _uiState.update { it.copy(isLoading = true, error = null) }
            repository.getDriverEarningsDetailed(_uiState.value.selectedPeriod)
                .onSuccess { response ->
                    _uiState.update { it.copy(isLoading = false, earnings = response, error = null) }
                }
                .onFailure { e ->
                    _uiState.update {
                        it.copy(isLoading = false, error = e.message ?: "Failed to load earnings")
                    }
                }
        }
    }

    /** @param period one of "today", "week", "month" */
    fun selectPeriod(period: String) {
        if (period == _uiState.value.selectedPeriod) return
        _uiState.update { it.copy(selectedPeriod = period) }
        loadEarnings()
    }

    fun requestPayout() {
        val amount = _uiState.value.earnings?.availableBalance
        if (amount == null) {
            _uiState.update { it.copy(payoutMessage = "Your payout balance isn't available yet.") }
            return
        }
        if (amount <= 0.0) {
            _uiState.update { it.copy(payoutMessage = "No balance available to pay out yet.") }
            return
        }
        viewModelScope.launch {
            _uiState.update { it.copy(isRequestingPayout = true, payoutMessage = null) }
            repository.requestDriverPayout(amount)
                .onSuccess { resp ->
                    _uiState.update {
                        it.copy(
                            isRequestingPayout = false,
                            payoutMessage = resp.message ?: "Payout requested"
                        )
                    }
                    loadEarnings()
                }
                .onFailure { e ->
                    _uiState.update {
                        it.copy(isRequestingPayout = false, payoutMessage = e.message)
                    }
                }
        }
    }

    fun clearError() {
        _uiState.update { it.copy(error = null) }
    }

    fun clearPayoutMessage() {
        _uiState.update { it.copy(payoutMessage = null) }
    }
}
