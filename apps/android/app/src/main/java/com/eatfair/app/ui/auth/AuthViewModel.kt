package com.eatfair.app.ui.auth

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.eatfair.shared.config.AppConfig
import com.eatfair.shared.data.local.SecureStorage
import com.eatfair.shared.data.local.SessionManager
import com.eatfair.shared.data.repository.DollorRepository
import com.eatfair.shared.network.SessionEvents
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import javax.inject.Inject

sealed class AuthState {
    object Initial : AuthState()
    object Loading : AuthState()
    object UnAuthenticated : AuthState()
    object NeedsLegalAcceptance : AuthState()
    data class Authenticated(val userId: String) : AuthState()
    data class Error(val message: String) : AuthState()
}

sealed class EmailVerificationState {
    object Initial : EmailVerificationState()
    object SendingCode : EmailVerificationState()
    data class CodeSent(val maskedEmail: String, val message: String) : EmailVerificationState()
    object Verifying : EmailVerificationState()
    object Verified : EmailVerificationState()
    object AlreadyVerified : EmailVerificationState()
    data class Error(val message: String) : EmailVerificationState()
}

@HiltViewModel
class AuthViewModel @Inject constructor(
    private val sessionManager: SessionManager,
    private val secureStorage: SecureStorage,
    private val dollorRepository: DollorRepository
) : ViewModel() {

    private val _authState = MutableStateFlow<AuthState>(AuthState.Initial)
    val authState: StateFlow<AuthState> = _authState.asStateFlow()

    // Password reset states - Matches iOS AuthViewModel
    private val _isLoading = MutableStateFlow(false)
    val isLoadingState: StateFlow<Boolean> = _isLoading.asStateFlow()

    private val _errorMessage = MutableStateFlow<String?>(null)
    val errorMessageState: StateFlow<String?> = _errorMessage.asStateFlow()

    init {
        observeAuthState()
        observeSessionExpiry()
        registerPushTokenOnSignIn()
    }

    /** Register the device for push as soon as the rider is signed in (not only on app resume). */
    private fun registerPushTokenOnSignIn() {
        viewModelScope.launch {
            authState.collect { state ->
                if (state is AuthState.Authenticated) dollorRepository.registerCurrentPushToken()
            }
        }
    }

    /** A rider API call hit an unrefreshable 401: drop the local session and return to login. */
    private fun observeSessionExpiry() {
        viewModelScope.launch {
            SessionEvents.expired.collect {
                sessionManager.clearSession()
                _authState.value = AuthState.UnAuthenticated
            }
        }
    }

    /**
     * Observes authentication state on app startup.
     *
     * IMPORTANT: This observer must check hasAcceptedTerms to avoid race condition.
     * When login() saves session, the SessionManager Flow emits, triggering this collector.
     * Without the terms check here, it would override NeedsLegalAcceptance with Authenticated.
     *
     * Flow: login() -> saveSession() -> Flow emits -> collector runs -> must check terms!
     */
    private fun observeAuthState() {
        viewModelScope.launch {
            // Check if user is already logged in via SecureStorage
            if (secureStorage.isCustomerLoggedIn) {
                if (!secureStorage.hasAcceptedTerms) {
                    _authState.value = AuthState.NeedsLegalAcceptance
                } else {
                    _authState.value = AuthState.Authenticated(secureStorage.customerEmail ?: "")
                }
            } else {
                // Fallback to SessionManager for backward compatibility
                // CRITICAL: Must also check hasAcceptedTerms here to prevent race condition
                // with login()/signUp() functions that set NeedsLegalAcceptance
                sessionManager.isLoggedIn.collect { isLoggedIn ->
                    if (isLoggedIn) {
                        val email = sessionManager.getUserEmail() ?: ""
                        // Check terms acceptance - same logic as login() functions
                        if (!secureStorage.hasAcceptedTerms) {
                            _authState.value = AuthState.NeedsLegalAcceptance
                        } else {
                            _authState.value = AuthState.Authenticated(email)
                        }
                    } else {
                        _authState.value = AuthState.UnAuthenticated
                    }
                }
            }
        }
    }

    fun login(email: String, password: String) {
        viewModelScope.launch {
            _authState.value = AuthState.Loading

            val result = dollorRepository.customerLogin(email, password)
            result.onSuccess { response ->
                // Also save to SessionManager for backward compatibility
                sessionManager.saveSession(
                    response.customerId.toString(),
                    response.name ?: email,
                    response.email ?: email
                )

                if (!secureStorage.hasAcceptedTerms) {
                    _authState.value = AuthState.NeedsLegalAcceptance
                } else {
                    _authState.value = AuthState.Authenticated(response.email ?: email)
                }
            }.onFailure { e ->
                _authState.value = AuthState.Error(e.message ?: "Login failed")
            }
        }
    }

    fun signUp(email: String, password: String, name: String, phone: String, zipCode: String) {
        viewModelScope.launch {
            _authState.value = AuthState.Loading

            val result = dollorRepository.customerRegister(
                email = email,
                password = password,
                name = name,
                phone = phone
            )

            result.onSuccess { response ->
                // Save to SessionManager for backward compatibility
                sessionManager.saveSession(
                    response.customerId.toString(),
                    response.name ?: name,
                    response.email ?: email
                )

                // New users need to accept terms
                _authState.value = AuthState.NeedsLegalAcceptance
            }.onFailure { e ->
                _authState.value = AuthState.Error(e.message ?: "Signup failed")
            }
        }
    }

    fun googleSignIn(idToken: String, email: String? = null, name: String? = null) {
        viewModelScope.launch {
            _authState.value = AuthState.Loading

            val result = dollorRepository.customerGoogleAuth(idToken, email, name)
            result.onSuccess { response ->
                sessionManager.saveSession(
                    response.customerId.toString(),
                    response.name ?: "",
                    response.email ?: ""
                )

                if (!secureStorage.hasAcceptedTerms) {
                    _authState.value = AuthState.NeedsLegalAcceptance
                } else {
                    _authState.value = AuthState.Authenticated(response.email ?: "")
                }
            }.onFailure { e ->
                _authState.value = AuthState.Error(e.message ?: "Google sign-in failed")
            }
        }
    }

    fun acceptTermsAndPrivacy() {
        secureStorage.acceptTermsAndPrivacy()
        _authState.value = AuthState.Authenticated(secureStorage.customerEmail ?: "")
    }

    /**
     * Login with demo credentials for App Store review
     * Demo credentials are managed server-side - actual passwords are never stored in app code
     * Server has a special demo endpoint that validates demo accounts
     */
    fun loginWithDemo() {
        viewModelScope.launch {
            _authState.value = AuthState.Loading

            val result = dollorRepository.customerDemoLogin(
                AppConfig.DemoCredentials.CUSTOMER_EMAIL_HINT
            )
            result.onSuccess { response ->
                sessionManager.saveSession(
                    response.customerId.toString(),
                    response.name ?: "Demo User",
                    response.email ?: AppConfig.DemoCredentials.CUSTOMER_EMAIL_HINT
                )

                if (!secureStorage.hasAcceptedTerms) {
                    _authState.value = AuthState.NeedsLegalAcceptance
                } else {
                    _authState.value = AuthState.Authenticated(
                        response.email ?: AppConfig.DemoCredentials.CUSTOMER_EMAIL_HINT
                    )
                }
            }.onFailure { e ->
                _authState.value = AuthState.Error(e.message ?: "Demo login failed")
            }
        }
    }

    fun logout() {
        viewModelScope.launch {
            dollorRepository.unregisterPushToken()
            dollorRepository.customerLogout()
            sessionManager.clearSession()
            _authState.value = AuthState.UnAuthenticated
        }
    }

    /**
     * Delete customer account - required by Google Play Store policy
     * API: DELETE /api/customers/{customerId}/delete
     */
    fun deleteAccount(onSuccess: () -> Unit, onError: (String) -> Unit) {
        viewModelScope.launch {
            dollorRepository.deleteCustomerAccount().fold(
                onSuccess = {
                    // Clear local session after successful account deletion
                    sessionManager.clearSession()
                    _authState.value = AuthState.UnAuthenticated
                    onSuccess()
                },
                onFailure = { error ->
                    onError(error.message ?: "Failed to delete account")
                }
            )
        }
    }

    /**
     * Request password reset - sends code to email
     * Matches iOS AuthViewModel.requestPasswordReset()
     */
    fun requestPasswordReset(email: String, onResult: (Boolean) -> Unit) {
        viewModelScope.launch {
            _isLoading.value = true
            _errorMessage.value = null

            val result = dollorRepository.requestPasswordReset(email)
            result.onSuccess {
                _isLoading.value = false
                onResult(true)
            }.onFailure { e ->
                _isLoading.value = false
                _errorMessage.value = e.message ?: "Failed to send reset code"
                onResult(false)
            }
        }
    }

    /**
     * Confirm password reset with code and new password
     * Matches iOS AuthViewModel.confirmPasswordReset()
     */
    fun confirmPasswordReset(email: String, code: String, newPassword: String, onResult: (Boolean) -> Unit) {
        viewModelScope.launch {
            _isLoading.value = true
            _errorMessage.value = null

            val result = dollorRepository.confirmPasswordReset(email, code, newPassword)
            result.onSuccess {
                _isLoading.value = false
                onResult(true)
            }.onFailure { e ->
                _isLoading.value = false
                _errorMessage.value = e.message ?: "Failed to reset password"
                onResult(false)
            }
        }
    }

    /**
     * Clear error message
     */
    fun clearError() {
        _errorMessage.value = null
    }

    // ==========================================
    // EMAIL VERIFICATION
    // ==========================================

    private val _emailVerificationState = MutableStateFlow<EmailVerificationState>(EmailVerificationState.Initial)
    val emailVerificationState: StateFlow<EmailVerificationState> = _emailVerificationState.asStateFlow()

    /**
     * Send email verification code to customer
     */
    fun sendEmailVerificationCode(onResult: (Boolean) -> Unit) {
        viewModelScope.launch {
            _emailVerificationState.value = EmailVerificationState.SendingCode

            val result = dollorRepository.sendEmailVerification()
            result.onSuccess { response ->
                if (response.alreadyVerified == true) {
                    _emailVerificationState.value = EmailVerificationState.AlreadyVerified
                } else {
                    _emailVerificationState.value = EmailVerificationState.CodeSent(
                        maskedEmail = response.email ?: "",
                        message = response.message ?: "Code sent"
                    )
                }
                onResult(true)
            }.onFailure { e ->
                _emailVerificationState.value = EmailVerificationState.Error(
                    e.message ?: "Failed to send verification code"
                )
                onResult(false)
            }
        }
    }

    /**
     * Verify email with the 6-digit code
     */
    fun verifyEmail(code: String, onResult: (Boolean) -> Unit) {
        viewModelScope.launch {
            _emailVerificationState.value = EmailVerificationState.Verifying

            val result = dollorRepository.verifyEmail(code)
            result.onSuccess { response ->
                if (response.verified) {
                    _emailVerificationState.value = EmailVerificationState.Verified
                    onResult(true)
                } else {
                    _emailVerificationState.value = EmailVerificationState.Error(
                        response.message ?: "Verification failed"
                    )
                    onResult(false)
                }
            }.onFailure { e ->
                _emailVerificationState.value = EmailVerificationState.Error(
                    e.message ?: "Verification failed"
                )
                onResult(false)
            }
        }
    }

    /**
     * Get email verification status
     */
    fun getEmailVerificationStatus(onResult: (Boolean, String) -> Unit) {
        viewModelScope.launch {
            val result = dollorRepository.getEmailVerificationStatus()
            result.onSuccess { response ->
                if (response.verified) {
                    _emailVerificationState.value = EmailVerificationState.AlreadyVerified
                }
                onResult(response.verified, response.email)
            }.onFailure { e ->
                onResult(false, "")
            }
        }
    }

    fun resetEmailVerificationState() {
        _emailVerificationState.value = EmailVerificationState.Initial
    }

    override fun onCleared() {
        super.onCleared()
        // All jobs are automatically cancelled by viewModelScope
    }
}
