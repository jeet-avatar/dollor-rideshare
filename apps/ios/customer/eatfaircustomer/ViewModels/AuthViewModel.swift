import SwiftUI
import Combine
import GoogleSignIn
import EatFairShared
import AuthenticationServices
import CryptoKit
import os.log

private let logger = Logger(subsystem: "com.dollorai.customer", category: "AuthViewModel")

/// Customer Authentication ViewModel
/// Uses Google Sign-In SDK directly + P2P backend (no Firebase)
class AuthViewModel: NSObject, ObservableObject {
    @Published var isAuthenticated: Bool = false
    @Published var isLoading: Bool = false
    @Published var errorMessage: String?
    @Published var customerName: String = ""
    @Published var customerEmail: String = ""

    // Password Reset State
    @Published var showForgotPassword: Bool = false
    @Published var showResetCodeEntry: Bool = false
    @Published var resetEmail: String = ""
    @Published var resetCode: String = ""
    @Published var newPassword: String = ""
    @Published var passwordResetSuccess: Bool = false
    @Published var passwordResetMessage: String = ""

    private let p2pService = P2PAPIService.shared
    private var sessionExpiredObserver: NSObjectProtocol?

    /// Load Google Client ID from GoogleService-Info.plist - no hardcoded credentials
    private var googleClientID: String {
        guard let path = Bundle.main.path(forResource: "GoogleService-Info", ofType: "plist"),
              let plist = NSDictionary(contentsOfFile: path),
              let clientID = plist["CLIENT_ID"] as? String else {
            logger.error("[AuthViewModel] ERROR: Could not load CLIENT_ID from GoogleService-Info.plist")
            return ""
        }
        return clientID
    }

    // Apple Sign-In nonce for security
    private var currentNonce: String?

    // Keys for storing Apple user info locally (Apple only provides name on first sign-in)
    private let appleUserNameKey = "apple_signin_user_name"
    private let appleUserIdKey = "apple_signin_user_id"

    override init() {
        super.init()
        // A rider API call hit an unrefreshable 401: sign out and tell the rider why.
        sessionExpiredObserver = NotificationCenter.default.addObserver(
            forName: NSNotification.Name("CustomerTokenExpired"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self = self, self.isAuthenticated else { return }
            self.logout()
            self.errorMessage = "Session expired, please sign in again."
        }
        #if DEBUG
        // UITest screenshot bypass: inject pre-obtained token to skip SSL-pinned login
        if let token = ProcessInfo.processInfo.environment["UITEST_ACCESS_TOKEN"] {
            SecureStorage.shared.customerAccessToken = token
            UserDefaults.standard.set(74, forKey: "p2p_customer_id")
            UserDefaults.standard.set("Demo Customer", forKey: "p2p_customer_name")
            UserDefaults.standard.set("demo.customer@dollor.ai", forKey: "p2p_customer_email")
            self.isAuthenticated = true
            self.customerName = "Demo Customer"
            self.customerEmail = "demo.customer@dollor.ai"
            return
        }
        #endif
        // Check if already logged in via P2P
        if p2pService.isCustomerLoggedIn {
            self.isAuthenticated = true
            // Restore customer name/email from UserDefaults (set during login)
            self.customerName = UserDefaults.standard.string(forKey: "p2p_customer_name") ?? ""
            self.customerEmail = UserDefaults.standard.string(forKey: "p2p_customer_email") ?? ""

            // Validate the restored session in the background. If the server rejects the
            // token (stale/expired), drop to the login screen so the user isn't stuck
            // "already signed in" with a dead session.
            p2pService.validateCustomerSession { [weak self] isValid in
                if !isValid {
                    self?.logout()
                    self?.errorMessage = "Session expired, please sign in again."
                }
            }
        }
    }

    deinit {
        if let sessionExpiredObserver = sessionExpiredObserver {
            NotificationCenter.default.removeObserver(sessionExpiredObserver)
        }
    }

    /// Email/password login via P2P backend
    func login(email: String, password: String) {
        // Validate email
        guard isValidEmail(email) else {
            errorMessage = "Please enter a valid email address"
            return
        }

        // Validate password
        guard !password.isEmpty else {
            errorMessage = "Password cannot be empty"
            return
        }

        isLoading = true
        errorMessage = nil

        p2pService.customerLogin(email: email, password: password) { [weak self] result in
            DispatchQueue.main.async {
                self?.isLoading = false
                switch result {
                case .success(let response):
                    self?.customerName = response.fullName
                    self?.customerEmail = response.email
                    self?.isAuthenticated = true
                case .failure(let error):
                    // Check for specific error types
                    let errorMsg = error.localizedDescription.lowercased()
                    if errorMsg.contains("invalid") || errorMsg.contains("password") || errorMsg.contains("credential") {
                        self?.errorMessage = "Invalid email or password. Please check and try again."
                    } else if errorMsg.contains("not found") || errorMsg.contains("no account") {
                        self?.errorMessage = "No account found with this email. Please sign up first."
                    } else if errorMsg.contains("network") || errorMsg.contains("connection") {
                        self?.errorMessage = "Unable to connect. Please check your internet connection."
                    } else {
                        self?.errorMessage = "Unable to sign in. Please try again."
                    }
                    logger.error("Login error: \(error.localizedDescription)")
                }
            }
        }
    }

    /// Register new customer
    func register(email: String, password: String, fullName: String, phone: String) {
        // Validate email
        guard isValidEmail(email) else {
            errorMessage = "Please enter a valid email address"
            return
        }

        // Validate password
        guard isValidPassword(password) else {
            errorMessage = "Password must be at least 8 characters long and contain at least one letter and one number"
            return
        }

        // Validate full name
        guard !fullName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            errorMessage = "Please enter your full name"
            return
        }

        // Validate phone
        guard isValidPhone(phone) else {
            errorMessage = "Please enter a valid phone number"
            return
        }

        isLoading = true
        errorMessage = nil

        p2pService.customerRegister(email: email, password: password, fullName: fullName, phone: phone) { [weak self] result in
            DispatchQueue.main.async {
                self?.isLoading = false
                switch result {
                case .success(let response):
                    self?.customerName = response.fullName
                    self?.customerEmail = response.email
                    self?.isAuthenticated = true
                case .failure(let error):
                    let errorMsg = error.localizedDescription.lowercased()
                    if errorMsg.contains("exists") || errorMsg.contains("already") {
                        self?.errorMessage = "An account with this email already exists. Please sign in instead."
                    } else if errorMsg.contains("network") || errorMsg.contains("connection") {
                        self?.errorMessage = "Unable to connect. Please check your internet connection."
                    } else {
                        self?.errorMessage = "Unable to create account. Please try again."
                    }
                    logger.error("Registration error: \(error.localizedDescription)")
                }
            }
        }
    }

    /// Helper to find topmost view controller
    private func getTopViewController() -> UIViewController? {
        // Prefer the FOREGROUND-ACTIVE window scene. `connectedScenes.first` can return a
        // background/inactive scene, which gives Google Sign-In's web session an invalid
        // presentation anchor and makes the flow hang after the account is chosen.
        let windowScenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let activeScene = windowScenes.first { $0.activationState == .foregroundActive } ?? windowScenes.first

        guard let windowScene = activeScene,
              let window = windowScene.windows.first(where: { $0.isKeyWindow }) ?? windowScene.windows.first,
              var topController = window.rootViewController else {
            return nil
        }

        // Walk to the topmost presented controller, skipping one that's being dismissed.
        while let presented = topController.presentedViewController, !presented.isBeingDismissed {
            topController = presented
        }

        return topController
    }

    /// Google Sign-In → P2P backend (no Firebase Auth)
    func signInWithGoogle() {
            logger.debug("signInWithGoogle() called")

        guard !googleClientID.isEmpty else {
            errorMessage = "Google Sign-In not configured. Please contact support."
            return
        }

        let config = GIDConfiguration(clientID: googleClientID)
        GIDSignIn.sharedInstance.configuration = config

        guard let topViewController = getTopViewController() else {
            logger.error("Unable to get top view controller")
            errorMessage = "Unable to get view controller for sign-in"
            return
        }

        isLoading = true
        errorMessage = nil

        GIDSignIn.sharedInstance.signIn(withPresenting: topViewController) { [weak self] result, error in
            guard let self = self else { return }

            if let error = error {
                logger.error("Google Sign-In error: \(error.localizedDescription)")
                DispatchQueue.main.async {
                    self.isLoading = false
                    // Don't show error if user cancelled
                    let nsError = error as NSError
                    if nsError.code != -5 { // GIDSignInError.canceled
                        self.errorMessage = "Google sign-in failed. Please try again."
                    }
                }
                return
            }

            guard let user = result?.user else {
                DispatchQueue.main.async {
                    self.isLoading = false
                    self.errorMessage = "Failed to get user info from Google"
                }
                return
            }

            // Extract Google user info
            let googleEmail = user.profile?.email ?? ""
            let googleName = user.profile?.name ?? ""
            let googleUserId = user.userID ?? ""

            // Use the dedicated Google OAuth endpoint - handles both login and registration
            self.p2pService.customerGoogleAuth(
                email: googleEmail,
                name: googleName,
                googleId: googleUserId
            ) { result in
                DispatchQueue.main.async {
                    self.isLoading = false
                    switch result {
                    case .success(let response):
                        self.customerName = response.fullName
                        self.customerEmail = response.email
                        self.isAuthenticated = true
                    case .failure(let error):
                        let errorMsg = error.localizedDescription.lowercased()
                        if errorMsg.contains("network") || errorMsg.contains("connection") {
                            self.errorMessage = "Unable to connect. Please check your internet connection."
                        } else {
                            self.errorMessage = "Unable to complete Google sign-in. Please try again."
                        }
                        logger.error("Google auth error: \(error.localizedDescription)")
                    }
                }
            }
        }
    }

    func logout() {
        GIDSignIn.sharedInstance.signOut()
        p2pService.customerLogout()
        isAuthenticated = false
        customerName = ""
        customerEmail = ""
    }

    // MARK: - Password Reset

    /// Request password reset - sends code to email
    func requestPasswordReset(email: String) {
        // Validate email
        guard isValidEmail(email) else {
            errorMessage = "Please enter a valid email address"
            return
        }

        isLoading = true
        errorMessage = nil
        resetEmail = email

        p2pService.requestPasswordReset(email: email) { [weak self] result in
            DispatchQueue.main.async {
                self?.isLoading = false
                switch result {
                case .success(let response):
                    self?.passwordResetMessage = response.message
                    self?.showResetCodeEntry = true
                    self?.showForgotPassword = false
                case .failure(let error):
                    let errorMsg = error.localizedDescription.lowercased()
                    if errorMsg.contains("not found") || errorMsg.contains("no account") {
                        self?.errorMessage = "No account found with this email address."
                    } else if errorMsg.contains("network") || errorMsg.contains("connection") {
                        self?.errorMessage = "Unable to connect. Please check your internet connection."
                    } else {
                        self?.errorMessage = "Unable to send reset code. Please try again."
                    }
                    logger.error("Password reset request error: \(error.localizedDescription)")
                }
            }
        }
    }

    /// Confirm password reset with code and new password
    func confirmPasswordReset() {
        guard !resetCode.isEmpty, !newPassword.isEmpty else {
            errorMessage = "Please enter the reset code and new password"
            return
        }

        // Validate new password
        guard isValidPassword(newPassword) else {
            errorMessage = "Password must be at least 8 characters long and contain at least one letter and one number"
            return
        }

        isLoading = true
        errorMessage = nil

        p2pService.confirmPasswordReset(email: resetEmail, code: resetCode, newPassword: newPassword) { [weak self] result in
            DispatchQueue.main.async {
                self?.isLoading = false
                switch result {
                case .success(let response):
                    self?.passwordResetSuccess = true
                    self?.passwordResetMessage = response.message
                    self?.showResetCodeEntry = false
                    // Clear reset fields
                    self?.resetCode = ""
                    self?.newPassword = ""
                case .failure(let error):
                    let errorMsg = error.localizedDescription.lowercased()
                    if errorMsg.contains("invalid") || errorMsg.contains("code") || errorMsg.contains("expired") {
                        self?.errorMessage = "Invalid or expired reset code. Please request a new one."
                    } else if errorMsg.contains("network") || errorMsg.contains("connection") {
                        self?.errorMessage = "Unable to connect. Please check your internet connection."
                    } else {
                        self?.errorMessage = "Unable to reset password. Please try again."
                    }
                    logger.error("Password reset confirm error: \(error.localizedDescription)")
                }
            }
        }
    }

    /// Reset the password reset flow state
    func resetPasswordResetState() {
        showForgotPassword = false
        showResetCodeEntry = false
        resetEmail = ""
        resetCode = ""
        newPassword = ""
        passwordResetSuccess = false
        passwordResetMessage = ""
        errorMessage = nil
    }

    // MARK: - Apple Sign-In

    /// Generate random nonce for Apple Sign-In security
    private func randomNonceString(length: Int = 32) -> String {
        let charset = "0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz"
        guard length > 0 else {
            return String((0..<32).compactMap { _ in charset.randomElement() })
        }
        var randomBytes = [UInt8](repeating: 0, count: length)
        let errorCode = SecRandomCopyBytes(kSecRandomDefault, randomBytes.count, &randomBytes)
        if errorCode != errSecSuccess {
            // Fallback to UUID-based nonce if secure random fails
            let fallbackNonce = UUID().uuidString.replacingOccurrences(of: "-", with: "") + UUID().uuidString.replacingOccurrences(of: "-", with: "")
            return String(fallbackNonce.prefix(length))
        }
        let charsetArray: [Character] = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._")
        let nonce = randomBytes.map { byte in charsetArray[Int(byte) % charsetArray.count] }
        return String(nonce)
    }

    /// SHA256 hash of the nonce
    private func sha256(_ input: String) -> String {
        let inputData = Data(input.utf8)
        let hashedData = SHA256.hash(data: inputData)
        let hashString = hashedData.compactMap { String(format: "%02x", $0) }.joined()
        return hashString
    }

    /// Start Apple Sign-In flow
    func signInWithApple() {
        isLoading = true
        errorMessage = nil

        let nonce = randomNonceString()
        currentNonce = nonce

        let appleIDProvider = ASAuthorizationAppleIDProvider()
        let request = appleIDProvider.createRequest()
        request.requestedScopes = [.fullName, .email]
        request.nonce = sha256(nonce)

        let authorizationController = ASAuthorizationController(authorizationRequests: [request])
        authorizationController.delegate = self
        authorizationController.presentationContextProvider = self
        authorizationController.performRequests()
    }

    // MARK: - Input Validation

    /// Validate email format
    private func isValidEmail(_ email: String) -> Bool {
        let emailRegex = "[A-Z0-9a-z._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,64}"
        let emailPredicate = NSPredicate(format: "SELF MATCHES %@", emailRegex)
        return emailPredicate.evaluate(with: email)
    }

    /// Validate password (at least 8 characters, contains letter and number)
    private func isValidPassword(_ password: String) -> Bool {
        guard password.count >= 8 else { return false }
        let hasLetter = password.rangeOfCharacter(from: .letters) != nil
        let hasNumber = password.rangeOfCharacter(from: .decimalDigits) != nil
        return hasLetter && hasNumber
    }

    /// Validate phone number (10 digits, optional formatting)
    private func isValidPhone(_ phone: String) -> Bool {
        let digits = phone.components(separatedBy: CharacterSet.decimalDigits.inverted).joined()
        return digits.count >= 10
    }
}

// MARK: - ASAuthorizationControllerDelegate
extension AuthViewModel: ASAuthorizationControllerDelegate {
    func authorizationController(controller: ASAuthorizationController, didCompleteWithAuthorization authorization: ASAuthorization) {
        guard let appleIDCredential = authorization.credential as? ASAuthorizationAppleIDCredential else {
            DispatchQueue.main.async {
                self.isLoading = false
                self.errorMessage = "Unable to get Apple ID credential"
            }
            return
        }

        guard let _ = currentNonce else {
            DispatchQueue.main.async {
                self.isLoading = false
                self.errorMessage = "Invalid login state. Please try again."
            }
            return
        }

        // Extract user info
        let appleUserId = appleIDCredential.user
        let appleEmail = appleIDCredential.email ?? ""
        var fullName = [appleIDCredential.fullName?.givenName, appleIDCredential.fullName?.familyName]
            .compactMap { $0 }
            .joined(separator: " ")

        // Extract identity token (contains real email for backend verification)
        var identityTokenString: String?
        if let identityTokenData = appleIDCredential.identityToken,
           let tokenString = String(data: identityTokenData, encoding: .utf8) {
            identityTokenString = tokenString
        }

        let authorizationCodeString = appleIDCredential.authorizationCode.flatMap { String(data: $0, encoding: .utf8) }

        // IMPORTANT: Apple only provides name on FIRST sign-in
        // Save name locally if provided, or retrieve saved name for subsequent logins
        if !fullName.isEmpty {
            // First sign-in - save the name locally for future logins
            UserDefaults.standard.set(fullName, forKey: appleUserNameKey)
            UserDefaults.standard.set(appleUserId, forKey: appleUserIdKey)
        } else {
            // Subsequent sign-in - try to retrieve saved name for this Apple ID
            let savedAppleId = UserDefaults.standard.string(forKey: appleUserIdKey)
            if savedAppleId == appleUserId, let savedName = UserDefaults.standard.string(forKey: appleUserNameKey), !savedName.isEmpty {
                fullName = savedName
            }
        }

        // Call P2P backend for Apple auth
        // Send identity token so backend can extract real email for returning users
        p2pService.customerAppleAuth(
            email: appleEmail,
            name: fullName,
            appleId: appleUserId,
            identityToken: identityTokenString,
            authorizationCode: authorizationCodeString
        ) { [weak self] result in
            DispatchQueue.main.async {
                self?.isLoading = false
                switch result {
                case .success(let response):
                    self?.customerName = response.fullName
                    self?.customerEmail = response.email
                    self?.isAuthenticated = true
                case .failure(let error):
                    let errorMsg = error.localizedDescription.lowercased()
                    if errorMsg.contains("network") || errorMsg.contains("connection") {
                        self?.errorMessage = "Unable to connect. Please check your internet connection."
                    } else {
                        self?.errorMessage = "Unable to complete Apple sign-in. Please try again."
                    }
                    logger.error("Apple auth error: \(error.localizedDescription)")
                }
            }
        }
    }

    func authorizationController(controller: ASAuthorizationController, didCompleteWithError error: Error) {
        let nsError = error as NSError
        DispatchQueue.main.async {
            self.isLoading = false
            // Don't show error if user cancelled
            if nsError.code != ASAuthorizationError.canceled.rawValue {
                self.errorMessage = "Apple sign-in failed. Please try again."
                logger.error("Apple sign-in error: \(error.localizedDescription)")
            }
        }
    }
}

// MARK: - ASAuthorizationControllerPresentationContextProviding
extension AuthViewModel: ASAuthorizationControllerPresentationContextProviding {
    func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        // First try to get key window from connected scenes
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene {
            if let keyWindow = windowScene.windows.first(where: { $0.isKeyWindow }) {
                return keyWindow
            }
            if let firstWindow = windowScene.windows.first {
                return firstWindow
            }
        }

        // Fallback: create a new window if none exists (should never happen in normal use)
        let fallbackWindow = UIWindow(frame: UIScreen.main.bounds)
        fallbackWindow.makeKeyAndVisible()
        return fallbackWindow
    }
}
