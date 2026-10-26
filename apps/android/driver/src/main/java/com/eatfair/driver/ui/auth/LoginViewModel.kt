package com.eatfair.driver.ui.auth

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.eatfair.shared.data.local.SecureStorage
import com.eatfair.shared.data.repository.DollorRepository
import com.eatfair.shared.model.DriverGoogleAuthRequest
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import javax.inject.Inject

sealed class LoginState {
    object Idle : LoginState()
    object Loading : LoginState()
    object LoggedIn : LoginState()
    object NeedsLegalAcceptance : LoginState()
    data class Error(val message: String) : LoginState()
}

@HiltViewModel
class LoginViewModel @Inject constructor(
    private val repository: DollorRepository,
    val secureStorage: SecureStorage
) : ViewModel() {

    private val _loginState = MutableStateFlow<LoginState>(LoginState.Idle)
    val loginState: StateFlow<LoginState> = _loginState.asStateFlow()

    init {
        checkExistingAuth()
    }

    private fun checkExistingAuth() {
        if (secureStorage.isDriverLoggedIn) {
            if (!secureStorage.hasAcceptedTerms) {
                _loginState.value = LoginState.NeedsLegalAcceptance
            } else {
                _loginState.value = LoginState.LoggedIn
            }
        }
    }

    /** Last-used email + password, if remembered, to prefill the login form. Empty if none. */
    fun rememberedCredentials(): Pair<String, String>? {
        val email = secureStorage.driverEmail
        val password = secureStorage.driverRememberedPassword
        return if (!email.isNullOrEmpty() && !password.isNullOrEmpty()) email to password else null
    }

    fun login(email: String, password: String) {
        viewModelScope.launch {
            _loginState.value = LoginState.Loading

            repository.driverLogin(email, password)
                .onSuccess { response ->
                    // Remember for next time so a driver who does land back on this screen
                    // (logged out, session expired, reinstall) doesn't have to retype it.
                    secureStorage.driverRememberedPassword = password
                    if (!secureStorage.hasAcceptedTerms) {
                        _loginState.value = LoginState.NeedsLegalAcceptance
                    } else {
                        _loginState.value = LoginState.LoggedIn
                    }
                }
                .onFailure { e ->
                    _loginState.value = LoginState.Error(e.message ?: "Login failed")
                }
        }
    }

    fun googleSignIn(idToken: String, email: String, name: String) {
        viewModelScope.launch {
            _loginState.value = LoginState.Loading

            repository.driverGoogleAuth(DriverGoogleAuthRequest(idToken, email, name))
                .onSuccess { response ->
                    if (!secureStorage.hasAcceptedTerms) {
                        _loginState.value = LoginState.NeedsLegalAcceptance
                    } else {
                        _loginState.value = LoginState.LoggedIn
                    }
                }
                .onFailure { e ->
                    _loginState.value = LoginState.Error(e.message ?: "Google sign-in failed")
                }
        }
    }

    fun acceptTermsAndPrivacy() {
        secureStorage.acceptTermsAndPrivacy()
        _loginState.value = LoginState.LoggedIn
    }

    fun logout() {
        viewModelScope.launch {
            repository.driverLogout()
            _loginState.value = LoginState.Idle
        }
    }

    fun deleteAccount(onSuccess: () -> Unit, onError: (String) -> Unit) {
        viewModelScope.launch {
            repository.deleteDriverAccount().fold(
                onSuccess = {
                    repository.driverLogout()
                    _loginState.value = LoginState.Idle
                    onSuccess()
                },
                onFailure = { error ->
                    onError(error.message ?: "Failed to delete account")
                }
            )
        }
    }

    fun clearError() {
        _loginState.value = LoginState.Idle
    }

    /**
     * Request a driver password-reset code by email.
     * Backend: POST /api/driver/password-reset/request (same endpoint as the iOS driver app)
     */
    fun forgotPassword(email: String, onResult: (success: Boolean, message: String) -> Unit) {
        viewModelScope.launch {
            repository.driverForgotPassword(email).fold(
                onSuccess = {
                    onResult(true, "If an account exists for $email, a reset code has been sent.")
                },
                onFailure = { e ->
                    onResult(false, e.message ?: "Could not send reset code. Please try again.")
                }
            )
        }
    }

    /** Finish the reset with the emailed code. Backend: POST /api/driver/password-reset/confirm */
    fun resetPassword(email: String, code: String, newPassword: String, onResult: (success: Boolean, message: String) -> Unit) {
        viewModelScope.launch {
            repository.driverResetPassword(email, code, newPassword).fold(
                onSuccess = { onResult(true, "Password updated. You can sign in now.") },
                onFailure = { e -> onResult(false, e.message ?: "Could not reset password. Check the code and try again.") }
            )
        }
    }
}
