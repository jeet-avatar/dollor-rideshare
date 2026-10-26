package com.eatfair.driver.ui.profile

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.eatfair.shared.data.repository.DollorRepository
import com.eatfair.shared.model.rideshare.DriverAccessibilitySettings
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import javax.inject.Inject

data class AccessibilityUiState(
    val capable: Boolean = false,
    val wheelchair: Boolean = false,
    val serviceAnimal: Boolean = false,
    val mobilityStorage: Boolean = false,
    val isSaving: Boolean = false,
    val error: String? = null
)

/** Driver-side TNC-12 capability (same endpoint and options as the iOS ComplianceView). */
@HiltViewModel
class AccessibilityViewModel @Inject constructor(
    private val repository: DollorRepository
) : ViewModel() {

    private val _state = MutableStateFlow(AccessibilityUiState())
    val state: StateFlow<AccessibilityUiState> = _state.asStateFlow()

    init {
        viewModelScope.launch {
            repository.getDriverAccessibility().onSuccess { settings ->
                val features = settings.accessibilityFeatures.orEmpty()
                _state.update {
                    it.copy(
                        capable = settings.accessibilityCapable,
                        wheelchair = features["wheelchair"] == true,
                        serviceAnimal = features["service_animal"] == true,
                        mobilityStorage = features["mobility_storage"] == true
                    )
                }
            }
        }
    }

    fun setCapable(value: Boolean) = update { it.copy(capable = value) }
    fun setWheelchair(value: Boolean) = update { it.copy(wheelchair = value) }
    fun setServiceAnimal(value: Boolean) = update { it.copy(serviceAnimal = value) }
    fun setMobilityStorage(value: Boolean) = update { it.copy(mobilityStorage = value) }

    private fun update(change: (AccessibilityUiState) -> AccessibilityUiState) {
        _state.update(change)
        save()
    }

    private fun save() {
        val current = _state.value
        _state.update { it.copy(isSaving = true, error = null) }
        viewModelScope.launch {
            val settings = DriverAccessibilitySettings(
                accessibilityCapable = current.capable,
                accessibilityFeatures = mapOf(
                    "wheelchair" to current.wheelchair,
                    "service_animal" to current.serviceAnimal,
                    "mobility_storage" to current.mobilityStorage
                )
            )
            repository.updateDriverAccessibility(settings)
                .onSuccess { _state.update { it.copy(isSaving = false) } }
                .onFailure { e -> _state.update { it.copy(isSaving = false, error = e.message ?: "Couldn't save") } }
        }
    }
}
