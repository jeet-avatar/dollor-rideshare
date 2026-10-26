package com.eatfair.app.ui.profile

import com.eatfair.shared.data.local.SessionManager
import com.eatfair.shared.data.repository.DollorRepository
import android.net.Uri
import android.util.Log
import androidx.core.net.toUri
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.launchIn
import kotlinx.coroutines.flow.onEach
import kotlinx.coroutines.launch
import javax.inject.Inject

@HiltViewModel
class ProfileViewModel @Inject constructor(
    private val sessionManager: SessionManager,
    private val dollorRepository: DollorRepository
) : ViewModel() {

    private val _profileImageUri = MutableStateFlow<Uri?>(null)
    val profileImageUri = _profileImageUri.asStateFlow()

    val userNameFlow = sessionManager.userNameFlow
    val userEmailFlow = sessionManager.userEmailFlow

    init {
        sessionManager.profileImageUriFlow
            .onEach { uriString ->
                _profileImageUri.value = uriString?.toUri()
            }
            .launchIn(viewModelScope)
    }

    /**
     * Persist profile changes to the backend (name / phone) via
     * PUT /api/customer/{customerId}/profile, then refresh the locally cached name.
     */
    fun saveName(name: String, onResult: (Result<Unit>) -> Unit) {
        viewModelScope.launch {
            dollorRepository.updateCustomerFullName(name)
                .onSuccess {
                    sessionManager.updateUserName(name.trim())
                    onResult(Result.success(Unit))
                }
                .onFailure { onResult(Result.failure(it)) }
        }
    }

    fun updateProfile(name: String, phone: String) {
        viewModelScope.launch {
            dollorRepository.updateCustomerProfile(name, phone)
                .onSuccess {
                    if (name.isNotBlank()) sessionManager.updateUserName(name)
                    Log.d("ProfileViewModel", "Profile updated successfully")
                }
                .onFailure { Log.w("ProfileViewModel", "Profile update failed: ${it.message}") }
        }
    }

    // Called from the UI when a new image is selected
    fun onProfileImageChange(uri: Uri?) {
        viewModelScope.launch {
            sessionManager.saveProfileImageUri(uri?.toString())
        }
    }

    override fun onCleared() {
        super.onCleared()
        // All jobs are automatically cancelled by viewModelScope
    }
}
