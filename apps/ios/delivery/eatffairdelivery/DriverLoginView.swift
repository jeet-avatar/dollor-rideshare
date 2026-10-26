import SwiftUI
import GoogleSignIn
import GoogleSignInSwift
import EatFairShared
import Security
import AuthenticationServices
import CryptoKit
import os

private let logger = Logger(subsystem: "com.dollorai.delivery", category: "DriverLogin")

// MARK: - Keychain Helper for Secure Password Storage
//
// Remembers the driver's email/password login so a return to this screen
// (session expired, logged out, reinstall) can be prefilled instead of
// forcing the driver to retype credentials. See `loadRememberedCredentials()`
// and the `driverLogin`/`driverRegister` success handlers below.
struct KeychainHelper {

    enum KeychainError: Error {
        case encodingFailed
        case saveFailed(OSStatus)
        case deleteFailed(OSStatus)
        case notFound
    }

    /// Saves password to Keychain with proper error handling
    /// - Issue #1 Fixed: Removed force unwrap on data encoding
    /// - Issue #2 Fixed: Added proper error handling for SecItemAdd
    @discardableResult
    static func save(password: String, for email: String) -> Result<Void, KeychainError> {
        // Issue #1: Safe optional binding instead of force unwrap
        guard let data = password.data(using: .utf8) else {
            #if DEBUG
            logger.info("[KeychainHelper] Failed to encode password for email: \(email)")
            #endif
            return .failure(.encodingFailed)
        }

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: email,
            kSecAttrService as String: "com.dollorai.driver.login-password",
            kSecValueData as String: data
        ]

        // Delete any existing item first
        let deleteStatus = SecItemDelete(query as CFDictionary)
        // Issue #3: Log deletion status (not critical if fails with itemNotFound)
        if deleteStatus != errSecSuccess && deleteStatus != errSecItemNotFound {
            #if DEBUG
            logger.info("[KeychainHelper] Warning: Delete before save returned status: \(deleteStatus)")
            #endif
        }

        // Issue #2: Check SecItemAdd return value
        let addStatus = SecItemAdd(query as CFDictionary, nil)
        if addStatus != errSecSuccess {
            #if DEBUG
            logger.info("[KeychainHelper] Failed to save password. Status: \(addStatus)")
            #endif
            return .failure(.saveFailed(addStatus))
        }

        return .success(())
    }

    static func getPassword(for email: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: email,
            kSecAttrService as String: "com.dollorai.driver.login-password",
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess,
              let data = result as? Data,
              let password = String(data: data, encoding: .utf8) else {
            return nil
        }

        return password
    }

    /// Deletes password from Keychain with proper error handling
    /// - Issue #3 Fixed: Added return value and logging for SecItemDelete
    @discardableResult
    static func deletePassword(for email: String) -> Result<Void, KeychainError> {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: email,
            kSecAttrService as String: "com.dollorai.driver.login-password"
        ]
        let status = SecItemDelete(query as CFDictionary)

        if status != errSecSuccess && status != errSecItemNotFound {
            #if DEBUG
            logger.info("[KeychainHelper] Failed to delete password. Status: \(status)")
            #endif
            return .failure(.deleteFailed(status))
        }

        return .success(())
    }
}

struct DriverLoginView: View {
    @State private var email = ""
    @State private var password = ""
    @State private var confirmPassword = ""
    @State private var errorMessage = ""
    @State private var isLoading = false
    @State private var isSignUp = false
    @State private var firstName = ""
    @State private var lastName = ""
    @State private var phone = ""
    @State private var showTerms = false
    @State private var agreedToTerms = false
    @State private var currentNonce: String?
    @State private var showForgotPassword = false
    @State private var showRegistrationAlert = false
    @State private var registrationURL: String = ""
    @Binding var isLoggedIn: Bool
    @EnvironmentObject var authManager: AuthManager

    private let p2pService = P2PAPIService.shared

    // Keys for storing Apple user info (Apple only provides name on first sign-in)
    private let appleUserNameKey = "driver_apple_user_name"
    private let appleUserIdKey = "driver_apple_user_id"

    // Key for the last email used to sign in — paired with KeychainHelper to
    // prefill the login form so a driver who does land back here (session
    // expired, logged out, new install) doesn't have to retype credentials.
    private let lastLoginEmailKey = "driver_last_login_email"

    /// Prefills email + password from the last successful login, if any.
    /// Only applies to the sign-in form (not sign-up) and never overwrites
    /// text the driver has already started typing.
    private func loadRememberedCredentials() {
        guard !isSignUp, email.isEmpty, password.isEmpty,
              let savedEmail = UserDefaults.standard.string(forKey: lastLoginEmailKey),
              !savedEmail.isEmpty else { return }
        email = savedEmail
        if let savedPassword = KeychainHelper.getPassword(for: savedEmail) {
            password = savedPassword
        }
    }

    /// Completes a successful sign-in: refreshes the driver's real approval
    /// status from the backend before flipping `isLoggedIn`, so an already-
    /// approved driver lands straight on the dashboard instead of flashing
    /// through the onboarding/pending screen (which only self-corrects after
    /// a background poll). See AuthManager.refreshApprovalStatus.
    private func completeLogin() {
        authManager.refreshApprovalStatus { _ in
            self.isLoggedIn = true
        }
    }

    /// Load Google Client ID from GoogleService-Info.plist - no hardcoded credentials
    private var googleClientID: String {
        guard let path = Bundle.main.path(forResource: "GoogleService-Info", ofType: "plist"),
              let plist = NSDictionary(contentsOfFile: path),
              let clientID = plist["CLIENT_ID"] as? String else {
            #if DEBUG
            logger.info("[DriverLoginView] ERROR: Could not load CLIENT_ID from GoogleService-Info.plist")
            #endif
            // Return empty string - will fail gracefully in handleGoogleLogin()
            return ""
        }
        return clientID
    }

    // MARK: - Input Validation (Issues #5-7 Fixed)

    /// Issue #5 Fixed: RFC 5322 compliant email validation using shared EmailValidator
    /// Also blocks disposable/temporary email domains
    private var isValidEmail: Bool {
        return EmailValidator.isValid(email)
    }

    /// Get email validation error message for display
    private var emailValidationError: String? {
        return EmailValidator.getErrorMessage(email)
    }

    /// Issue #6 Fixed: Added special character requirement for password
    private var isValidPassword: Bool {
        let specialCharacters = CharacterSet(charactersIn: "!@#$%^&*()_+-=[]{}|;':\",./<>?")
        return password.count >= 8 &&
            password.rangeOfCharacter(from: .uppercaseLetters) != nil &&
            password.rangeOfCharacter(from: .lowercaseLetters) != nil &&
            password.rangeOfCharacter(from: .decimalDigits) != nil &&
            password.rangeOfCharacter(from: specialCharacters) != nil
    }

    /// Password strength for UI feedback
    private var passwordStrength: (level: Int, message: String) {
        var strength = 0
        if password.count >= 8 { strength += 1 }
        if password.rangeOfCharacter(from: .uppercaseLetters) != nil { strength += 1 }
        if password.rangeOfCharacter(from: .lowercaseLetters) != nil { strength += 1 }
        if password.rangeOfCharacter(from: .decimalDigits) != nil { strength += 1 }
        let specialCharacters = CharacterSet(charactersIn: "!@#$%^&*()_+-=[]{}|;':\",./<>?")
        if password.rangeOfCharacter(from: specialCharacters) != nil { strength += 1 }

        switch strength {
        case 0...2: return (strength, "Weak")
        case 3...4: return (strength, "Medium")
        default: return (strength, "Strong")
        }
    }

    /// Issue #7 Fixed: E.164 format validation for phone numbers
    private var isValidPhone: Bool {
        let cleanPhone = phone.replacingOccurrences(of: "[^0-9+]", with: "", options: .regularExpression)

        // E.164 format: optional + followed by 10-15 digits
        // US format: exactly 10 digits
        // International: 11-15 digits with or without +

        if cleanPhone.hasPrefix("+") {
            // International format
            let digitsOnly = cleanPhone.dropFirst()
            return digitsOnly.count >= 10 && digitsOnly.count <= 15 && digitsOnly.allSatisfy { $0.isNumber }
        } else {
            // Local format (US)
            return cleanPhone.count >= 10 && cleanPhone.count <= 15 && cleanPhone.allSatisfy { $0.isNumber }
        }
    }

    /// Format phone number for display
    private var formattedPhone: String {
        let cleanPhone = phone.replacingOccurrences(of: "[^0-9]", with: "", options: .regularExpression)
        if cleanPhone.count == 10 {
            let areaCode = cleanPhone.prefix(3)
            let middle = cleanPhone.dropFirst(3).prefix(3)
            let last = cleanPhone.dropFirst(6)
            return "(\(areaCode)) \(middle)-\(last)"
        }
        return phone
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // App branding with dollar sign
                ZStack {
                    Circle()
                        .fill(Theme.lxOrange.opacity(0.15))
                        .frame(width: 120, height: 120)

                    Text("$")
                        .font(Lx.Typography.iconHero.weight(.bold))
                        .foregroundColor(Theme.lxOrange)
                }
                .padding(.bottom, isSignUp ? 10 : 20)

                Text("Dollor AI Service")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                    .foregroundColor(Theme.lxText)

                Text("$ online store")
                    .font(.subheadline)
                    .foregroundColor(Theme.lxTextSecondary)
                    .padding(.bottom, isSignUp ? 10 : 20)

                Text(isSignUp ? "Driver Sign Up" : "Driver Login")
                    .font(.title2)
                    .fontWeight(.semibold)
                    .foregroundColor(Theme.lxText)

                if isSignUp {
                    HStack(spacing: 10) {
                        VStack(alignment: .leading, spacing: 4) {
                            TextField("First Name", text: $firstName)
                                .textFieldStyle(.plain).lxField()
                                .autocapitalization(.words)
                            if isSignUp && firstName.isEmpty {
                                Text("Required")
                                    .font(.caption2)
                                    .foregroundColor(Theme.lxError)
                            }
                        }

                        VStack(alignment: .leading, spacing: 4) {
                            TextField("Last Name", text: $lastName)
                                .textFieldStyle(.plain).lxField()
                                .autocapitalization(.words)
                            if isSignUp && lastName.isEmpty {
                                Text("Required")
                                    .font(.caption2)
                                    .foregroundColor(Theme.lxError)
                            }
                        }
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        TextField("Phone Number", text: $phone)
                            .textFieldStyle(.plain).lxField()
                            .keyboardType(.phonePad)
                        if !phone.isEmpty && !isValidPhone {
                            Text("Enter valid phone (10-15 digits)")
                                .font(.caption2)
                                .foregroundColor(Theme.lxError)
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 4) {
                    TextField("Email", text: $email)
                        .textFieldStyle(.plain).lxField()
                        .autocapitalization(.none)
                        .keyboardType(.emailAddress)
                        .textContentType(.emailAddress)
                    if !email.isEmpty && !isValidEmail {
                        Text(emailValidationError ?? "Enter a valid email address")
                            .font(.caption2)
                            .foregroundColor(Theme.lxError)
                    }
                }

                VStack(alignment: .leading, spacing: 4) {
                    SecureField("Password", text: $password)
                        .textFieldStyle(.plain).lxField()
                        .textContentType(isSignUp ? .newPassword : .password)
                    if isSignUp && !password.isEmpty {
                        if !isValidPassword {
                            Text("Min 8 chars, uppercase, lowercase, number & special char (!@#$%)")
                                .font(.caption2)
                                .foregroundColor(Theme.lxError)
                        }
                        // Password strength indicator
                        HStack(spacing: 4) {
                            ForEach(0..<5, id: \.self) { index in
                                Rectangle()
                                    .fill(index < passwordStrength.level ?
                                          (passwordStrength.level <= 2 ? Theme.lxError :
                                           passwordStrength.level <= 4 ? Theme.lxOrange : Theme.lxSuccess) :
                                          Theme.lxHairline)
                                    .frame(height: 4)
                                    .cornerRadius(Lx.Radius.grabber)
                            }
                            Text(passwordStrength.message)
                                .font(.caption2)
                                .foregroundColor(passwordStrength.level <= 2 ? Theme.lxError :
                                                passwordStrength.level <= 4 ? Theme.lxOrange : Theme.lxSuccess)
                        }
                    }
                }

                // Forgot Password Link (only show on login)
                if !isSignUp {
                    HStack {
                        Spacer()
                        Button(action: { showForgotPassword = true }) {
                            Text("Forgot Password?")
                                .font(.subheadline)
                                .foregroundColor(Theme.lxOrange)
                        }
                    }
                }

                if isSignUp {
                    VStack(alignment: .leading, spacing: 4) {
                        SecureField("Confirm Password", text: $confirmPassword)
                            .textFieldStyle(.plain).lxField()
                            .textContentType(.newPassword)
                        if !confirmPassword.isEmpty && password != confirmPassword {
                            Text("Passwords do not match")
                                .font(.caption2)
                                .foregroundColor(Theme.lxError)
                        }
                    }

                    // Terms and Conditions
                    HStack(spacing: 8) {
                        Button(action: { agreedToTerms.toggle() }) {
                            Image(systemName: agreedToTerms ? "checkmark.square.fill" : "square")
                                .foregroundColor(agreedToTerms ? Theme.lxOrange : Theme.lxTextMuted)
                        }

                        Text("I agree to the ")
                            .font(.caption)
                            .foregroundColor(Theme.lxTextSecondary)
                        +
                        Text("Terms & Conditions")
                            .font(.caption)
                            .foregroundColor(Theme.lxOrange)
                            .underline()
                    }
                    .onTapGesture {
                        showTerms = true
                    }
                }

                if !errorMessage.isEmpty {
                    Text(errorMessage)
                        .foregroundColor(Theme.lxError)
                        .font(.caption)
                        .multilineTextAlignment(.center)
                }

                Button(action: handleAction) {
                    if isLoading {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Theme.lxButtonGradient)
                            .cornerRadius(Lx.Radius.button)
                            .shadow(color: Theme.lxOrange.opacity(0.4), radius: 14, x: 0, y: 6)
                    } else {
                        Text(isSignUp ? "Sign Up" : "Login")
                            .fontWeight(.bold)
                            .foregroundColor(Lx.Palette.onAccent)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Theme.lxButtonGradient)
                            .cornerRadius(Lx.Radius.button)
                            .shadow(color: Theme.lxOrange.opacity(0.4), radius: 14, x: 0, y: 6)
                    }
                }
                .disabled(isLoading)

                Button(action: {
                    isSignUp.toggle()
                    errorMessage = ""
                    // Reset fields when switching
                    if !isSignUp {
                        firstName = ""
                        lastName = ""
                        phone = ""
                        confirmPassword = ""
                        agreedToTerms = false
                    }
                }) {
                    Text(isSignUp ? "Already have an account? Login" : "Don't have an account? Sign Up")
                        .foregroundColor(Theme.lxOrange)
                }

                HStack {
                    VStack { Divider().overlay(Theme.lxHairline) }
                    Text("OR")
                        .foregroundColor(Theme.lxTextMuted)
                        .font(.caption)
                    VStack { Divider().overlay(Theme.lxHairline) }
                }
                .padding(.vertical)

                GoogleSignInButton(action: handleGoogleLogin)
                    .colorScheme(.dark)

                // Sign in with Apple Button (Required by Apple for App Store)
                SignInWithAppleButton(.signIn) { request in
                    let nonce = randomNonceString()
                    currentNonce = nonce
                    request.requestedScopes = [.fullName, .email]
                    request.nonce = sha256(nonce)
                } onCompletion: { result in
                    handleAppleSignIn(result: result)
                }
                .signInWithAppleButtonStyle(.white)
                .frame(height: 50)
                .cornerRadius(Lx.Radius.chip)

                #if DEBUG
                demoLoginButton
                #endif

                Spacer()
            }
            .padding()
        }
        .background(Theme.lxBg.ignoresSafeArea())
        .preferredColorScheme(.dark)
        .onAppear {
            loadRememberedCredentials()
        }
        .sheet(isPresented: $showTerms) {
            DriverTermsSheet(agreedToTerms: $agreedToTerms)
        }
        .sheet(isPresented: $showForgotPassword) {
            DriverForgotPasswordView(isPresented: $showForgotPassword)
        }
        .alert("Registration Required", isPresented: $showRegistrationAlert) {
            Button("Register Now") {
                if let url = URL(string: registrationURL) {
                    UIApplication.shared.open(url)
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("You need to register as a driver first. Tap 'Register Now' to apply on our website.")
        }
    }

    // MARK: - Demo Login (App Store Review)
    #if DEBUG
    private var demoLoginButton: some View {
        Button(action: {
            email = "demo.driver@dollor.ai"
            password = "DemoDriver2025!"
        }) {
            HStack {
                Image(systemName: "bolt.fill")
                Text("Demo Login (App Review)")
                    .font(Lx.Typography.footnote.weight(.medium))
            }
            .foregroundColor(Theme.lxOrange)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(Theme.lxOrange.opacity(0.12))
            .cornerRadius(Lx.Radius.chip)
        }
        .accessibilityLabel("Demo login for App Store review")
    }
    #endif

    // MARK: - Apple Sign-In Helper Functions

    /// Generate random nonce for Apple Sign-In security
    /// Issue #10 Fixed: Replaced fatalError with graceful fallback for nonce generation
    private func randomNonceString(length: Int = 32) -> String {
        let charset = "0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz"
        guard length > 0 else {
            return String((0..<32).compactMap { _ in charset.randomElement() })
        }
        var randomBytes = [UInt8](repeating: 0, count: length)
        let errorCode = SecRandomCopyBytes(kSecRandomDefault, randomBytes.count, &randomBytes)

        // Issue #10: Use fallback instead of crashing the app
        if errorCode != errSecSuccess {
            #if DEBUG
            logger.info("[DriverLoginView] SecRandomCopyBytes failed with OSStatus \(errorCode), using fallback nonce generation")
            #endif
            // Fallback: Use UUID-based nonce generation
            let uuid = UUID().uuidString.replacingOccurrences(of: "-", with: "")
            let timestamp = String(Date().timeIntervalSince1970 * 1000000)
            let fallbackNonce = "\(uuid)\(timestamp)".prefix(length)
            return String(fallbackNonce)
        }

        let charsetArray: [Character] = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._")
        let nonce = randomBytes.map { byte in
            charsetArray[Int(byte) % charsetArray.count]
        }
        return String(nonce)
    }

    /// SHA256 hash for nonce
    private func sha256(_ input: String) -> String {
        let inputData = Data(input.utf8)
        let hashedData = SHA256.hash(data: inputData)
        let hashString = hashedData.compactMap { String(format: "%02x", $0) }.joined()
        return hashString
    }

    /// Handle Apple Sign-In result
    private func handleAppleSignIn(result: Result<ASAuthorization, Error>) {
        switch result {
        case .success(let authorization):
            guard let appleIDCredential = authorization.credential as? ASAuthorizationAppleIDCredential else {
                errorMessage = "Unable to get Apple ID credential"
                return
            }

            guard let _ = currentNonce else {
                errorMessage = "Invalid login state. Please try again."
                return
            }

            isLoading = true
            errorMessage = ""

            // Extract user info
            let appleUserId = appleIDCredential.user
            let appleEmail = appleIDCredential.email ?? ""
            var fullName = [appleIDCredential.fullName?.givenName, appleIDCredential.fullName?.familyName]
                .compactMap { $0 }
                .joined(separator: " ")

            // Extract identity token (contains email for returning users)
            let identityTokenString = appleIDCredential.identityToken.flatMap { String(data: $0, encoding: .utf8) }

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

            // Call P2P backend for Apple auth (include identity_token for returning user email lookup)
            p2pService.driverAppleAuth(
                email: appleEmail,
                name: fullName,
                appleId: appleUserId,
                identityToken: identityTokenString
            ) { [self] result in
                DispatchQueue.main.async {
                    self.isLoading = false
                    switch result {
                    case .success:
                        self.completeLogin()
                    case .failure(let error):
                        if case P2PAPIError.registrationRequired(_, let url) = error {
                            self.registrationURL = url
                            self.showRegistrationAlert = true
                        } else {
                            let errMsg = error.localizedDescription.lowercased()
                            if errMsg.contains("not found") || errMsg.contains("no account") {
                                self.errorMessage = "No driver account found. Please register first."
                            } else if errMsg.contains("not approved") || errMsg.contains("pending") {
                                self.errorMessage = "Your driver account is pending approval."
                            } else {
                                self.errorMessage = "Unable to sign in with Apple. Please try again."
                            }
                        }
                    }
                }
            }

        case .failure(let error):
            let nsError = error as NSError
            // Don't show error if user cancelled
            if nsError.code != ASAuthorizationError.canceled.rawValue {
                errorMessage = "Apple Sign-In could not be completed. Please try again."
            }
        }
    }

    /// Issues #8-9 Fixed: Comprehensive Google Sign-In error handling
    func handleGoogleLogin() {
        guard !googleClientID.isEmpty else {
            errorMessage = "Google Sign-In not configured. Please contact support."
            return
        }
        let config = GIDConfiguration(clientID: googleClientID)
        GIDSignIn.sharedInstance.configuration = config

        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let rootViewController = windowScene.windows.first?.rootViewController else {
            errorMessage = "Unable to get root view controller. Please try again."
            return
        }

        isLoading = true
        errorMessage = ""

        GIDSignIn.sharedInstance.signIn(withPresenting: rootViewController) { result, error in

            // Issue #8: Handle all error cases including cancellation
            if let error = error {
                DispatchQueue.main.async {
                    // Check if user cancelled
                    let nsError = error as NSError
                    if nsError.domain == "com.google.GIDSignIn" && nsError.code == -5 {
                        // User cancelled - don't show error
                        self.isLoading = false
                        return
                    }
                    let errMsg = error.localizedDescription.lowercased()
                    if errMsg.contains("network") || errMsg.contains("connection") {
                        self.errorMessage = "Unable to connect. Please check your internet connection."
                    } else {
                        self.errorMessage = "Google Sign-In could not be completed. Please try again."
                    }
                    self.isLoading = false
                }
                return
            }

            // Issue #8: Handle nil result when no error
            guard let user = result?.user else {
                DispatchQueue.main.async {
                    self.errorMessage = "Failed to get user information from Google. Please try again."
                    self.isLoading = false
                }
                return
            }

            // Issue #9: Validate email is not empty before proceeding
            guard let googleEmail = user.profile?.email, !googleEmail.isEmpty else {
                DispatchQueue.main.async {
                    self.errorMessage = "Unable to retrieve email from Google account. Please ensure your Google account has a valid email."
                    self.isLoading = false
                }
                return
            }

            let googleFirstName = user.profile?.givenName ?? "Driver"
            let googleLastName = user.profile?.familyName ?? ""
            let googleName = "\(googleFirstName) \(googleLastName)".trimmingCharacters(in: .whitespaces)
            let googleId = user.userID ?? ""

            guard !googleId.isEmpty else {
                DispatchQueue.main.async {
                    self.errorMessage = "Failed to get Google user ID. Please try again."
                    self.isLoading = false
                }
                return
            }

            // Use proper Google OAuth endpoint (handles both login and registration)
            self.p2pService.driverGoogleAuth(
                email: googleEmail,
                name: googleName,
                googleId: googleId
            ) { result in
                DispatchQueue.main.async {
                    self.isLoading = false
                    switch result {
                    case .success:
                        self.completeLogin()
                    case .failure(let error):
                        if case P2PAPIError.registrationRequired(_, let url) = error {
                            self.registrationURL = url
                            self.showRegistrationAlert = true
                        } else {
                            let errMsg = error.localizedDescription.lowercased()
                            if errMsg.contains("suspended") || errMsg.contains("deactivated") {
                                self.errorMessage = "Your driver account has been suspended. Please contact support."
                            } else if errMsg.contains("not approved") || errMsg.contains("pending") {
                                self.errorMessage = "Your driver account is pending approval."
                            } else {
                                self.errorMessage = "Google Sign-In failed. Please try again."
                            }
                        }
                    }
                }
            }
        }
    }

    func handleAction() {
        // Validate email format
        guard isValidEmail else {
            errorMessage = "Please enter a valid email address"
            return
        }

        if isSignUp {
            // Full signup validation
            guard !firstName.isEmpty else {
                errorMessage = "Please enter your first name"
                return
            }
            guard !lastName.isEmpty else {
                errorMessage = "Please enter your last name"
                return
            }
            guard !phone.isEmpty && isValidPhone else {
                errorMessage = "Please enter a valid phone number"
                return
            }
            guard isValidPassword else {
                errorMessage = "Password must be at least 8 characters with uppercase, lowercase, number, and special character"
                return
            }
            guard password == confirmPassword else {
                errorMessage = "Passwords do not match"
                return
            }
            guard agreedToTerms else {
                errorMessage = "Please agree to the Terms & Conditions"
                return
            }
        } else {
            guard !password.isEmpty else {
                errorMessage = "Please enter your password"
                return
            }
        }

        isLoading = true
        errorMessage = ""

        if isSignUp {
            p2pService.driverRegister(
                email: email,
                password: password,
                firstName: firstName,
                lastName: lastName,
                phone: phone.replacingOccurrences(of: "[^0-9]", with: "", options: .regularExpression)
            ) { result in
                DispatchQueue.main.async {
                    self.isLoading = false
                    switch result {
                    case .success:
                        UserDefaults.standard.set(self.email, forKey: self.lastLoginEmailKey)
                        KeychainHelper.save(password: self.password, for: self.email)
                        self.completeLogin()
                    case .failure(let error):
                        let errMsg = error.localizedDescription.lowercased()
                        if errMsg.contains("email") && errMsg.contains("exist") {
                            self.errorMessage = "This email is already registered. Please sign in instead."
                        } else if errMsg.contains("password") {
                            self.errorMessage = "Password does not meet requirements. Please use at least 8 characters."
                        } else if errMsg.contains("phone") {
                            self.errorMessage = "Invalid phone number. Please check and try again."
                        } else {
                            self.errorMessage = "Unable to create account. Please try again."
                        }
                    }
                }
            }
        } else {
            p2pService.driverLogin(email: email, password: password) { result in
                DispatchQueue.main.async {
                    self.isLoading = false
                    switch result {
                    case .success:
                        UserDefaults.standard.set(self.email, forKey: self.lastLoginEmailKey)
                        KeychainHelper.save(password: self.password, for: self.email)
                        self.completeLogin()
                    case .failure(let error):
                        let errMsg = error.localizedDescription.lowercased()
                        if errMsg.contains("invalid") || errMsg.contains("password") || errMsg.contains("credential") {
                            self.errorMessage = "Invalid email or password. Please check and try again."
                        } else if errMsg.contains("not found") || errMsg.contains("no account") {
                            self.errorMessage = "No driver account found. Please register first."
                        } else if errMsg.contains("not approved") || errMsg.contains("pending") {
                            self.errorMessage = "Your driver account is pending approval."
                        } else if errMsg.contains("suspended") || errMsg.contains("deactivated") {
                            self.errorMessage = "Your account has been suspended. Please contact support."
                        } else {
                            self.errorMessage = "Unable to sign in. Please try again."
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Terms and Conditions Sheet
struct DriverTermsSheet: View {
    @Environment(\.dismiss) var dismiss
    @Binding var agreedToTerms: Bool

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Terms & Conditions")
                        .font(.title)
                        .fontWeight(.bold)
                        .foregroundColor(Theme.lxText)

                    Text("Last Updated: December 2024")
                        .font(.caption)
                        .foregroundColor(Theme.lxTextMuted)

                    Group {
                        sectionHeader("1. Driver Agreement")
                        Text("By registering as a driver on Dollor AI Service, you agree to provide rideshare services in accordance with these terms. You must maintain a valid driver's license, vehicle insurance, and pass our background verification process.")

                        sectionHeader("2. Account Requirements")
                        Text("You must be at least 18 years old, possess a valid driver's license, and have access to a reliable vehicle. You are responsible for maintaining accurate account information.")

                        sectionHeader("3. Document Verification")
                        Text("All submitted documents (driver's license, insurance, etc.) will be verified by our AI-powered verification system. Approval is automatic upon successful verification. Falsified documents will result in immediate account termination.")

                        sectionHeader("4. Earnings & Payments")
                        Text("You will receive payment for completed rides as per the agreed rates. Payments are processed weekly via direct deposit or your preferred payment method.")

                        sectionHeader("5. Code of Conduct")
                        Text("You agree to provide professional, courteous service. Any violations of our code of conduct may result in account suspension or termination.")

                        sectionHeader("6. Privacy")
                        Text("Your personal information is protected under our Privacy Policy. We collect only necessary information for providing our services and compliance purposes.")
                    }

                    Spacer(minLength: 40)

                    Button(action: {
                        agreedToTerms = true
                        dismiss()
                    }) {
                        Text("I Agree to Terms & Conditions")
                            .fontWeight(.bold)
                            .foregroundColor(Lx.Palette.onAccent)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Theme.lxButtonGradient)
                            .cornerRadius(Lx.Radius.button)
                            .shadow(color: Theme.lxOrange.opacity(0.4), radius: 14, x: 0, y: 6)
                    }
                }
                .padding()
            }
            .background(Theme.lxBg.ignoresSafeArea())
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Close") {
                        dismiss()
                    }
                    .foregroundColor(Theme.lxOrange)
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    private func sectionHeader(_ text: String) -> some View {
        Text(text)
            .font(.headline)
            .foregroundColor(Theme.lxText)
            .padding(.top, 8)
    }
}

// MARK: - Driver Forgot Password View
struct DriverForgotPasswordView: View {
    @Binding var isPresented: Bool
    @State private var email = ""
    @State private var resetCode = ""
    @State private var newPassword = ""
    @State private var errorMessage = ""
    @State private var successMessage = ""
    @State private var isLoading = false
    @State private var showCodeEntry = false
    @State private var resetComplete = false

    private let p2pService = P2PAPIService.shared

    var body: some View {
        NavigationView {
            VStack(spacing: 24) {
                // Icon
                Image(systemName: "lock.rotation")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 80, height: 80)
                    .foregroundColor(Theme.lxOrange)
                    .padding(.top, 40)

                // Title
                Text(showCodeEntry ? "Enter Reset Code" : "Reset Password")
                    .font(.title)
                    .fontWeight(.bold)
                    .foregroundColor(Theme.lxText)

                if resetComplete {
                    // Success State
                    VStack(spacing: 16) {
                        Image(systemName: "checkmark.circle.fill")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 60, height: 60)
                            .foregroundColor(Theme.lxSuccess)

                        Text("Password Reset Successful!")
                            .font(.headline)
                            .foregroundColor(Theme.lxSuccess)

                        Text("You can now login with your new password.")
                            .font(.subheadline)
                            .foregroundColor(Theme.lxTextSecondary)
                            .multilineTextAlignment(.center)

                        Button(action: { isPresented = false }) {
                            Text("Back to Login")
                                .fontWeight(.bold)
                                .foregroundColor(Lx.Palette.onAccent)
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(Theme.lxButtonGradient)
                                .cornerRadius(Lx.Radius.button)
                                .shadow(color: Theme.lxOrange.opacity(0.4), radius: 14, x: 0, y: 6)
                        }
                        .padding(.horizontal)
                        .padding(.top, 20)
                    }
                } else if showCodeEntry {
                    // Code Entry State
                    VStack(spacing: 16) {
                        Text("We sent a code to \(email). Enter it below with your new password.")
                            .font(.subheadline)
                            .foregroundColor(Theme.lxTextSecondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)

                        VStack(alignment: .leading, spacing: 8) {
                            Text("Reset Code")
                                .font(.subheadline)
                                .fontWeight(.medium)
                                .foregroundColor(Theme.lxTextSecondary)

                            TextField("Enter code", text: $resetCode)
                                .textFieldStyle(.plain).lxField()
                                .keyboardType(.numberPad)
                        }
                        .padding(.horizontal)

                        VStack(alignment: .leading, spacing: 8) {
                            Text("New Password")
                                .font(.subheadline)
                                .fontWeight(.medium)
                                .foregroundColor(Theme.lxTextSecondary)

                            SecureField("Enter new password", text: $newPassword)
                                .textFieldStyle(.plain).lxField()
                                .textContentType(.newPassword)
                        }
                        .padding(.horizontal)

                        if !errorMessage.isEmpty {
                            Text(errorMessage)
                                .foregroundColor(Theme.lxError)
                                .font(.subheadline)
                                .padding(.horizontal)
                        }

                        Button(action: confirmReset) {
                            HStack {
                                if isLoading {
                                    ProgressView()
                                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                } else {
                                    Text("Reset Password")
                                        .fontWeight(.bold)
                                }
                            }
                            .foregroundColor(Lx.Palette.onAccent)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Theme.lxButtonGradient)
                            .cornerRadius(Lx.Radius.button)
                            .shadow(color: Theme.lxOrange.opacity(0.4), radius: 14, x: 0, y: 6)
                        }
                        .disabled(isLoading || resetCode.isEmpty || newPassword.isEmpty)
                        .opacity((resetCode.isEmpty || newPassword.isEmpty) ? 0.6 : 1.0)
                        .padding(.horizontal)
                    }
                } else {
                    // Email Entry State
                    VStack(spacing: 16) {
                        Text("Enter your email address and we'll send you a code to reset your password.")
                            .font(.subheadline)
                            .foregroundColor(Theme.lxTextSecondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)

                        VStack(alignment: .leading, spacing: 8) {
                            Text("Email")
                                .font(.subheadline)
                                .fontWeight(.medium)
                                .foregroundColor(Theme.lxTextSecondary)

                            TextField("Enter your email", text: $email)
                                .textFieldStyle(.plain).lxField()
                                .autocapitalization(.none)
                                .keyboardType(.emailAddress)
                                .textContentType(.emailAddress)
                        }
                        .padding(.horizontal)

                        if !errorMessage.isEmpty {
                            Text(errorMessage)
                                .foregroundColor(Theme.lxError)
                                .font(.subheadline)
                                .padding(.horizontal)
                        }

                        Button(action: sendResetEmail) {
                            HStack {
                                if isLoading {
                                    ProgressView()
                                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                } else {
                                    Text("Send Reset Code")
                                        .fontWeight(.bold)
                                }
                            }
                            .foregroundColor(Lx.Palette.onAccent)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Theme.lxButtonGradient)
                            .cornerRadius(Lx.Radius.button)
                            .shadow(color: Theme.lxOrange.opacity(0.4), radius: 14, x: 0, y: 6)
                        }
                        .disabled(isLoading || email.isEmpty)
                        .opacity(email.isEmpty ? 0.6 : 1.0)
                        .padding(.horizontal)
                    }
                }

                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Theme.lxBg.ignoresSafeArea())
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(action: { isPresented = false }) {
                        Image(systemName: "xmark")
                            .foregroundColor(Theme.lxTextSecondary)
                    }
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    func sendResetEmail() {
        guard !email.isEmpty else {
            errorMessage = "Please enter your email"
            return
        }

        // Validate email
        guard EmailValidator.isValid(email) else {
            errorMessage = EmailValidator.getErrorMessage(email) ?? "Invalid email address"
            return
        }

        isLoading = true
        errorMessage = ""

        // Use driver password reset endpoint
        p2pService.requestDriverPasswordReset(email: email) { result in
            DispatchQueue.main.async {
                isLoading = false
                switch result {
                case .success:
                    showCodeEntry = true
                case .failure(let error):
                    if let apiError = error as? P2PAPIError {
                        switch apiError {
                        case .serverError(let message):
                            errorMessage = message
                        default:
                            errorMessage = "Failed to send reset email. Please try again."
                        }
                    } else {
                        errorMessage = "Failed to send reset email. Please try again."
                    }
                }
            }
        }
    }

    func confirmReset() {
        guard !resetCode.isEmpty, !newPassword.isEmpty else {
            errorMessage = "Please enter the code and new password"
            return
        }

        guard newPassword.count >= 8 else {
            errorMessage = "Password must be at least 8 characters"
            return
        }

        isLoading = true
        errorMessage = ""

        // Use driver password reset confirm endpoint
        p2pService.confirmDriverPasswordReset(email: email, code: resetCode, newPassword: newPassword) { result in
            DispatchQueue.main.async {
                isLoading = false
                switch result {
                case .success:
                    resetComplete = true
                case .failure(let error):
                    if let apiError = error as? P2PAPIError {
                        switch apiError {
                        case .serverError(let message):
                            errorMessage = message
                        default:
                            errorMessage = "Failed to reset password. Please try again."
                        }
                    } else {
                        errorMessage = "Failed to reset password. Please try again."
                    }
                }
            }
        }
    }
}

// MARK: - Luxury Dark Text Field Styling
private struct LxFieldModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .foregroundColor(Theme.lxText)
            .tint(Theme.lxOrange)
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(Theme.lxSurface)
            .cornerRadius(Lx.Radius.button)
            .overlay(
                RoundedRectangle(cornerRadius: Lx.Radius.button)
                    .stroke(Theme.lxHairline, lineWidth: 1)
            )
    }
}

private extension View {
    func lxField() -> some View {
        modifier(LxFieldModifier())
    }
}

#if DEBUG
struct DriverLoginView_Previews: PreviewProvider {
    static var previews: some View {
        DriverLoginView(isLoggedIn: .constant(false))
    }
}
#endif
