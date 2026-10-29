import Foundation
import Combine
import os

private let logger = Logger(subsystem: "com.dollorai.shared", category: "P2PAPIService")

/// P2P Platform API Service
/// Connects iOS apps to the P2P backend for restaurant data, menus, and orders
public class P2PAPIService: ObservableObject {
    public static let shared = P2PAPIService()

    // MARK: - Configuration
    // Uses centralized AppConfig for baseURL - no hardcodes!
    private var baseURL: String {
        return "\(AppConfig.shared.p2pAPIBaseURL)/api"
    }

    @Published public var isLoading = false
    @Published public var error: String?

    private var cancellables = Set<AnyCancellable>()

    // MARK: - Secure Storage Keys (for non-sensitive data in UserDefaults)
    private enum UserDefaultsKey {
        static let vendorId = "p2p_vendor_id"
        static let vendorName = "p2p_vendor_name"
        static let vendorEmail = "p2p_vendor_email"
        static let customerId = "p2p_customer_id"
        static let driverId = "p2p_driver_id"
        static let driverCode = "p2p_driver_code"
        static let driverName = "p2p_driver_name"
        static let driverEmail = "p2p_driver_email"
        static let driverStatus = "p2p_driver_status"
        static let driverIsApproved = "p2p_driver_is_approved"
        static let driverRequiresDocuments = "p2p_driver_requires_documents"
        static let customerName = "p2p_customer_name"
        static let customerEmail = "p2p_customer_email"
    }

    // MARK: - Secure Token Access
    // All tokens are now stored securely in Keychain via SecureStorage

    /// Get customer access token from secure storage
    private var customerToken: String? {
        return SecureStorage.shared.customerAccessToken
    }

    /// Get driver access token from secure storage
    private var driverToken: String? {
        return SecureStorage.shared.driverAccessToken
    }

    /// Get vendor access token from secure storage
    private var vendorToken: String? {
        return SecureStorage.shared.vendorAccessToken
    }

    private init() {
        // Migrate any tokens from UserDefaults to Keychain on first access
        SecureStorage.shared.migrateFromUserDefaults()
        NotificationCenter.default.addObserver(
            forName: .apiUnauthorizedResponse,
            object: nil,
            queue: .main
        ) { [weak self] note in
            self?.handleUnauthorized(bearer: note.userInfo?["bearer"] as? String)
        }
    }

    private var isRecoveringSession = false

    /// Any call that came back 401 lands here (most call sites do not handle 401 themselves).
    /// Try one token refresh for the token that was rejected; if that fails, tell the app the
    /// session is over so it can sign out and show "Session expired".
    private func handleUnauthorized(bearer: String?) {
        guard let bearer = bearer, !isRecoveringSession else { return }
        isRecoveringSession = true
        let finish = { [weak self] in self?.isRecoveringSession = false }
        if bearer == customerToken {
            refreshCustomerToken { result in
                if case .failure(let error) = result, !(error is URLError) {
                    NotificationCenter.default.post(name: Notification.Name("CustomerTokenExpired"), object: nil)
                }
                finish()
            }
        } else if bearer == driverToken {
            refreshDriverToken { result in
                if case .failure(let error) = result, !(error is URLError) {
                    NotificationCenter.default.post(name: Notification.Name("DriverTokenExpired"), object: nil)
                }
                finish()
            }
        } else {
            finish()
        }
    }

    // MARK: - Secure URLSession (SSL Pinning)
    // Uses NetworkSecurity's pinning delegate instead of URLSession.shared
    // This ensures all API calls go through SSL certificate pinning validation
    private lazy var secureSession: URLSession = NetworkSecurity.shared.createSecureSession()

    // MARK: - Public Restaurant APIs (Customer App)

    // MARK: - Restaurant App APIs (Menu Management)

    // MARK: - Promotions API (Customer App)

    // MARK: - Promotions API (Restaurant App)

    // MARK: - AI Insights API

    // MARK: - Menu Verification APIs (Aria AI Employee)

    // MARK: - Vendor Authentication

    /// Get stored vendor ID
    public var currentVendorId: Int? {
        return UserDefaults.standard.object(forKey: UserDefaultsKey.vendorId) as? Int
    }

    /// Check if logged in
    public var isLoggedIn: Bool {
        return vendorToken != nil
    }

    /// Logout
    public func logout() {
        SecureStorage.shared.clearAuthTokens(type: .vendor)
        UserDefaults.standard.removeObject(forKey: UserDefaultsKey.vendorId)
    }

    // MARK: - Customer Authentication

    /// Customer login
    public func customerLogin(
        email: String,
        password: String,
        completion: @escaping (Result<P2PCustomerLoginResponse, Error>) -> Void
    ) {
        guard let url = URL(string: "\(baseURL)/auth/customer/login") else {
            completion(.failure(P2PAPIError.invalidURL))
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        // Properly URL-encode form values (special chars like ! @ # in passwords)
        var allowedCharacters = CharacterSet.alphanumerics
        allowedCharacters.insert(charactersIn: "-._~")
        guard let encodedEmail = email.addingPercentEncoding(withAllowedCharacters: allowedCharacters),
              let encodedPassword = password.addingPercentEncoding(withAllowedCharacters: allowedCharacters) else {
            // addingPercentEncoding should never return nil for standard CharacterSet
            // but if it does, fail loudly rather than send raw credentials
            completion(.failure(P2PAPIError.invalidURL))
            return
        }
        let bodyString = "username=\(encodedEmail)&password=\(encodedPassword)"
        request.httpBody = bodyString.data(using: .utf8)

        isLoading = true

        secureSession.dataTask(with: request) { [weak self] data, response, error in
            DispatchQueue.main.async {
                self?.isLoading = false

                if let error = error {
                    logger.error("customerLogin network error: \(error.localizedDescription)")
                    self?.error = error.localizedDescription
                    completion(.failure(error))
                    return
                }

                guard let data = data else {
                    logger.error("customerLogin: no data in response")
                    completion(.failure(P2PAPIError.noData))
                    return
                }

                if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode >= 400 {
                    logger.error("customerLogin HTTP error: \(httpResponse.statusCode)")
                    if let errorResponse = try? JSONDecoder().decode(P2PErrorResponse.self, from: data) {
                        completion(.failure(P2PAPIError.serverError(errorResponse.detail)))
                    } else {
                        completion(.failure(P2PAPIError.serverError("Login failed")))
                    }
                    return
                }

                do {
                    let loginResponse = try JSONDecoder().decode(P2PCustomerLoginResponse.self, from: data)
                    SecureStorage.shared.customerAccessToken = loginResponse.accessToken
                    UserDefaults.standard.set(loginResponse.customerId, forKey: UserDefaultsKey.customerId)
                    // Also save name and email for profile display
                    UserDefaults.standard.set(loginResponse.fullName, forKey: "p2p_customer_name")
                    UserDefaults.standard.set(loginResponse.email, forKey: "p2p_customer_email")
                    completion(.success(loginResponse))
                } catch {
                    logger.error("customerLogin decode error: \(error.localizedDescription)")
                    self?.error = "Failed to decode login response: \(error.localizedDescription)"
                    completion(.failure(error))
                }
            }
        }.resume()
    }

    /// Google OAuth login/registration for customers
    /// This endpoint handles both login and registration - if user exists, logs them in; if not, registers them
    public func customerGoogleAuth(
        email: String,
        name: String,
        googleId: String,
        completion: @escaping (Result<P2PCustomerLoginResponse, Error>) -> Void
    ) {
        guard let url = URL(string: "\(baseURL)/auth/customer/google") else {
            completion(.failure(P2PAPIError.invalidURL))
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = [
            "email": email,
            "name": name,
            "google_id": googleId
        ]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        isLoading = true

        secureSession.dataTask(with: request) { [weak self] data, response, error in
            DispatchQueue.main.async {
                self?.isLoading = false

                if let error = error {
                    logger.error("customerGoogleAuth network error: \(error.localizedDescription)")
                    self?.error = error.localizedDescription
                    completion(.failure(error))
                    return
                }

                guard let data = data else {
                    logger.error("customerGoogleAuth: no data in response")
                    completion(.failure(P2PAPIError.noData))
                    return
                }

                if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode >= 400 {
                    logger.error("customerGoogleAuth HTTP error: \(httpResponse.statusCode)")
                    if let errorResponse = try? JSONDecoder().decode(P2PErrorResponse.self, from: data) {
                        completion(.failure(P2PAPIError.serverError(errorResponse.detail)))
                    } else {
                        completion(.failure(P2PAPIError.serverError("Google auth failed")))
                    }
                    return
                }

                do {
                    let loginResponse = try JSONDecoder().decode(P2PCustomerLoginResponse.self, from: data)
                    SecureStorage.shared.customerAccessToken = loginResponse.accessToken
                    UserDefaults.standard.set(loginResponse.customerId, forKey: UserDefaultsKey.customerId)
                    // Save customer name and email for profile display
                    UserDefaults.standard.set(loginResponse.fullName, forKey: UserDefaultsKey.customerName)
                    UserDefaults.standard.set(loginResponse.email, forKey: UserDefaultsKey.customerEmail)
                    completion(.success(loginResponse))
                } catch {
                    logger.error("customerGoogleAuth decode error: \(error.localizedDescription)")
                    self?.error = "Failed to decode Google auth response: \(error.localizedDescription)"
                    completion(.failure(error))
                }
            }
        }.resume()
    }

    /// Apple OAuth login/registration for customers
    /// This endpoint handles both login and registration - if user exists, logs them in; if not, registers them
    public func customerAppleAuth(
        email: String,
        name: String,
        appleId: String,
        identityToken: String? = nil,
        completion: @escaping (Result<P2PCustomerLoginResponse, Error>) -> Void
    ) {
        guard let url = URL(string: "\(baseURL)/customer/apple-auth") else {
            completion(.failure(P2PAPIError.invalidURL))
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        var body: [String: Any] = [
            "email": email,
            "name": name,
            "apple_id": appleId
        ]
        // Send identity token if available (contains real email for returning users)
        if let token = identityToken {
            body["identity_token"] = token
        }
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        isLoading = true

        secureSession.dataTask(with: request) { [weak self] data, response, error in
            DispatchQueue.main.async {
                self?.isLoading = false

                if let error = error {
                    logger.error("customerAppleAuth network error: \(error.localizedDescription)")
                    self?.error = error.localizedDescription
                    completion(.failure(error))
                    return
                }

                guard let data = data else {
                    logger.error("customerAppleAuth: no data in response")
                    completion(.failure(P2PAPIError.noData))
                    return
                }

                if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode >= 400 {
                    logger.error("customerAppleAuth HTTP error: \(httpResponse.statusCode)")
                    if let errorResponse = try? JSONDecoder().decode(P2PErrorResponse.self, from: data) {
                        completion(.failure(P2PAPIError.serverError(errorResponse.detail)))
                    } else {
                        completion(.failure(P2PAPIError.serverError("Apple auth failed")))
                    }
                    return
                }

                do {
                    let loginResponse = try JSONDecoder().decode(P2PCustomerLoginResponse.self, from: data)
                    SecureStorage.shared.customerAccessToken = loginResponse.accessToken
                    UserDefaults.standard.set(loginResponse.customerId, forKey: UserDefaultsKey.customerId)
                    // Also save name and email for profile display
                    UserDefaults.standard.set(loginResponse.fullName, forKey: "p2p_customer_name")
                    UserDefaults.standard.set(loginResponse.email, forKey: "p2p_customer_email")
                    completion(.success(loginResponse))
                } catch {
                    logger.error("customerAppleAuth decode error: \(error.localizedDescription)")
                    self?.error = "Failed to decode Apple auth response: \(error.localizedDescription)"
                    completion(.failure(error))
                }
            }
        }.resume()
    }

    /// Update customer profile name
    public func updateCustomerProfile(
        customerId: Int,
        name: String,
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        guard let url = URL(string: "\(baseURL)/auth/customer/profile") else {
            completion(.failure(P2PAPIError.invalidURL))
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        if let token = SecureStorage.shared.customerAccessToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        let body: [String: Any] = ["full_name": name]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        secureSession.dataTask(with: request) { data, response, error in
            DispatchQueue.main.async {
                if let error = error {
                    completion(.failure(error))
                    return
                }

                if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode >= 400 {
                    if let data = data, let errorResponse = try? JSONDecoder().decode(P2PErrorResponse.self, from: data) {
                        completion(.failure(P2PAPIError.serverError(errorResponse.detail)))
                    } else {
                        completion(.failure(P2PAPIError.serverError("Failed to update profile")))
                    }
                    return
                }

                completion(.success(()))
            }
        }.resume()
    }

    /// Request password reset - sends reset code to email
    public func requestPasswordReset(
        email: String,
        completion: @escaping (Result<P2PPasswordResetResponse, Error>) -> Void
    ) {
        guard let url = URL(string: "\(baseURL)/customer/password-reset/request") else {
            completion(.failure(P2PAPIError.invalidURL))
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = ["email": email]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        isLoading = true

        secureSession.dataTask(with: request) { [weak self] data, response, error in
            DispatchQueue.main.async {
                self?.isLoading = false

                if let error = error {
                    self?.error = error.localizedDescription
                    completion(.failure(error))
                    return
                }

                guard let data = data else {
                    completion(.failure(P2PAPIError.noData))
                    return
                }

                if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode >= 400 {
                    if let errorResponse = try? JSONDecoder().decode(P2PErrorResponse.self, from: data) {
                        completion(.failure(P2PAPIError.serverError(errorResponse.detail)))
                    } else {
                        completion(.failure(P2PAPIError.serverError("Password reset request failed")))
                    }
                    return
                }

                do {
                    let resetResponse = try JSONDecoder().decode(P2PPasswordResetResponse.self, from: data)
                    completion(.success(resetResponse))
                } catch {
                    self?.error = "Failed to decode response: \(error.localizedDescription)"
                    completion(.failure(error))
                }
            }
        }.resume()
    }

    /// Confirm password reset with code and new password
    public func confirmPasswordReset(
        email: String,
        code: String,
        newPassword: String,
        completion: @escaping (Result<P2PPasswordResetResponse, Error>) -> Void
    ) {
        guard let url = URL(string: "\(baseURL)/customer/password-reset/confirm") else {
            completion(.failure(P2PAPIError.invalidURL))
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = [
            "email": email,
            "code": code,
            "new_password": newPassword
        ]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        isLoading = true

        secureSession.dataTask(with: request) { [weak self] data, response, error in
            DispatchQueue.main.async {
                self?.isLoading = false

                if let error = error {
                    self?.error = error.localizedDescription
                    completion(.failure(error))
                    return
                }

                guard let data = data else {
                    completion(.failure(P2PAPIError.noData))
                    return
                }

                if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode >= 400 {
                    if let errorResponse = try? JSONDecoder().decode(P2PErrorResponse.self, from: data) {
                        completion(.failure(P2PAPIError.serverError(errorResponse.detail)))
                    } else {
                        completion(.failure(P2PAPIError.serverError("Password reset confirmation failed")))
                    }
                    return
                }

                do {
                    let resetResponse = try JSONDecoder().decode(P2PPasswordResetResponse.self, from: data)
                    completion(.success(resetResponse))
                } catch {
                    self?.error = "Failed to decode response: \(error.localizedDescription)"
                    completion(.failure(error))
                }
            }
        }.resume()
    }

    // MARK: - Driver Password Reset

    /// Request password reset for driver - sends reset code to email
    public func requestDriverPasswordReset(
        email: String,
        completion: @escaping (Result<P2PPasswordResetResponse, Error>) -> Void
    ) {
        guard let url = URL(string: "\(baseURL)/driver/password-reset/request") else {
            completion(.failure(P2PAPIError.invalidURL))
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = ["email": email]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        isLoading = true

        secureSession.dataTask(with: request) { [weak self] data, response, error in
            DispatchQueue.main.async {
                self?.isLoading = false

                if let error = error {
                    self?.error = error.localizedDescription
                    completion(.failure(error))
                    return
                }

                guard let data = data else {
                    completion(.failure(P2PAPIError.noData))
                    return
                }

                if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode >= 400 {
                    if let errorResponse = try? JSONDecoder().decode(P2PErrorResponse.self, from: data) {
                        completion(.failure(P2PAPIError.serverError(errorResponse.detail)))
                    } else {
                        completion(.failure(P2PAPIError.serverError("Password reset request failed")))
                    }
                    return
                }

                do {
                    let resetResponse = try JSONDecoder().decode(P2PPasswordResetResponse.self, from: data)
                    completion(.success(resetResponse))
                } catch {
                    self?.error = "Failed to decode response: \(error.localizedDescription)"
                    completion(.failure(error))
                }
            }
        }.resume()
    }

    /// Confirm password reset for driver with code and new password
    public func confirmDriverPasswordReset(
        email: String,
        code: String,
        newPassword: String,
        completion: @escaping (Result<P2PPasswordResetResponse, Error>) -> Void
    ) {
        guard let url = URL(string: "\(baseURL)/driver/password-reset/confirm") else {
            completion(.failure(P2PAPIError.invalidURL))
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = [
            "email": email,
            "code": code,
            "new_password": newPassword
        ]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        isLoading = true

        secureSession.dataTask(with: request) { [weak self] data, response, error in
            DispatchQueue.main.async {
                self?.isLoading = false

                if let error = error {
                    self?.error = error.localizedDescription
                    completion(.failure(error))
                    return
                }

                guard let data = data else {
                    completion(.failure(P2PAPIError.noData))
                    return
                }

                if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode >= 400 {
                    if let errorResponse = try? JSONDecoder().decode(P2PErrorResponse.self, from: data) {
                        completion(.failure(P2PAPIError.serverError(errorResponse.detail)))
                    } else {
                        completion(.failure(P2PAPIError.serverError("Password reset confirmation failed")))
                    }
                    return
                }

                do {
                    let resetResponse = try JSONDecoder().decode(P2PPasswordResetResponse.self, from: data)
                    completion(.success(resetResponse))
                } catch {
                    self?.error = "Failed to decode response: \(error.localizedDescription)"
                    completion(.failure(error))
                }
            }
        }.resume()
    }

    // MARK: - Vendor/Restaurant Password Reset

    /// Customer registration
    public func customerRegister(
        email: String,
        password: String,
        fullName: String,
        phone: String,
        completion: @escaping (Result<P2PCustomerLoginResponse, Error>) -> Void
    ) {
        guard let url = URL(string: "\(baseURL)/auth/customer/register") else {
            completion(.failure(P2PAPIError.invalidURL))
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        // Backend expects "name" (not "full_name")
        let body: [String: Any] = [
            "email": email,
            "password": password,
            "name": fullName,
            "phone": phone
        ]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        isLoading = true

        secureSession.dataTask(with: request) { [weak self] data, response, error in
            DispatchQueue.main.async {
                self?.isLoading = false

                if let error = error {
                    self?.error = error.localizedDescription
                    completion(.failure(error))
                    return
                }

                guard let data = data else {
                    completion(.failure(P2PAPIError.noData))
                    return
                }

                if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode >= 400 {
                    if let errorResponse = try? JSONDecoder().decode(P2PErrorResponse.self, from: data) {
                        completion(.failure(P2PAPIError.serverError(errorResponse.detail)))
                    } else {
                        completion(.failure(P2PAPIError.serverError("Registration failed")))
                    }
                    return
                }

                do {
                    let loginResponse = try JSONDecoder().decode(P2PCustomerLoginResponse.self, from: data)
                    SecureStorage.shared.customerAccessToken = loginResponse.accessToken
                    UserDefaults.standard.set(loginResponse.customerId, forKey: UserDefaultsKey.customerId)
                    UserDefaults.standard.set(loginResponse.fullName, forKey: UserDefaultsKey.customerName)
                    UserDefaults.standard.set(loginResponse.email, forKey: UserDefaultsKey.customerEmail)
                    completion(.success(loginResponse))
                } catch {
                    self?.error = "Failed to decode response: \(error.localizedDescription)"
                    completion(.failure(error))
                }
            }
        }.resume()
    }

    /// Get stored customer ID
    public var currentCustomerId: Int? {
        return UserDefaults.standard.object(forKey: UserDefaultsKey.customerId) as? Int
    }

    /// Check if customer is logged in
    public var isCustomerLoggedIn: Bool {
        return customerToken != nil
    }

    /// Customer logout
    public func customerLogout() {
        SecureStorage.shared.clearAuthTokens(type: .customer)
        UserDefaults.standard.removeObject(forKey: UserDefaultsKey.customerId)
        UserDefaults.standard.removeObject(forKey: UserDefaultsKey.customerName)
        UserDefaults.standard.removeObject(forKey: UserDefaultsKey.customerEmail)
    }

    // MARK: - Customer Address APIs

    /// Fetch all addresses for a customer
    public func fetchAddresses(
        userId: Int,
        completion: @escaping (Result<[P2PCustomerAddress], Error>) -> Void
    ) {
        guard let url = URL(string: "\(baseURL)/addresses/\(userId)") else {
            completion(.failure(P2PAPIError.invalidURL))
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"

        if let token = customerToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        secureSession.dataTask(with: request) { [weak self] data, response, error in
            DispatchQueue.main.async {
                if let error = error {
                    self?.error = error.localizedDescription
                    completion(.failure(error))
                    return
                }

                guard let data = data else {
                    completion(.failure(P2PAPIError.noData))
                    return
                }

                do {
                    let addresses = try JSONDecoder().decode([P2PCustomerAddress].self, from: data)
                    completion(.success(addresses))
                } catch {
                    self?.error = "Failed to decode addresses: \(error.localizedDescription)"
                    #if DEBUG
                    logger.error("Address decode error: \(error)")
                    #endif
                    completion(.failure(error))
                }
            }
        }.resume()
    }

    /// Create a new address for a customer
    public func createAddress(
        userId: Int,
        address: Address,
        completion: @escaping (Result<P2PCustomerAddress, Error>) -> Void
    ) {
        #if DEBUG
        logger.info("createAddress called for userId: \(userId)")
        #endif

        guard let url = URL(string: "\(baseURL)/addresses/\(userId)") else {
            #if DEBUG
            logger.info("createAddress: Invalid URL")
            #endif
            completion(.failure(P2PAPIError.invalidURL))
            return
        }

        #if DEBUG
        logger.info("createAddress URL: \(url.absoluteString)")
        #endif

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        if let token = customerToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            #if DEBUG
            logger.info("createAddress: Auth token present")
            #endif
        } else {
            #if DEBUG
            logger.info("createAddress: WARNING - No auth token!")
            #endif
        }

        let body: [String: Any] = [
            "location_name": address.locationName,
            "street": address.street,
            "unit": address.unit,
            "city": address.city,
            "state": address.state,
            "zip_code": address.zipCode,
            "instructions": address.instructions,
            "address_type": address.type,
            "latitude": address.latitude,
            "longitude": address.longitude,
            "phone_number": address.phoneNumber,
            "is_default": address.isDefault
        ]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        #if DEBUG
        logger.info("createAddress body: \(body)")
        #endif

        isLoading = true

        secureSession.dataTask(with: request) { [weak self] data, response, error in
            DispatchQueue.main.async {
                self?.isLoading = false

                if let error = error {
                    #if DEBUG
                    logger.error("createAddress network error: \(error)")
                    #endif
                    self?.error = error.localizedDescription
                    completion(.failure(error))
                    return
                }

                guard let data = data else {
                    #if DEBUG
                    logger.info("createAddress: No data received")
                    #endif
                    completion(.failure(P2PAPIError.noData))
                    return
                }

                #if DEBUG
                if let jsonString = String(data: data, encoding: .utf8) {
                    logger.info("createAddress response: \(jsonString)")
                }
                #endif

                if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode >= 400 {
                    #if DEBUG
                    logger.error("createAddress HTTP error: \(httpResponse.statusCode)")
                    #endif
                    if let errorResponse = try? JSONDecoder().decode(P2PErrorResponse.self, from: data) {
                        completion(.failure(P2PAPIError.serverError(errorResponse.detail)))
                    } else {
                        completion(.failure(P2PAPIError.serverError("Failed to create address")))
                    }
                    return
                }

                do {
                    let createdAddress = try JSONDecoder().decode(P2PCustomerAddress.self, from: data)
                    #if DEBUG
                    logger.info("createAddress success: id=\(createdAddress.id)")
                    #endif
                    completion(.success(createdAddress))
                } catch {
                    #if DEBUG
                    logger.error("createAddress decode error: \(error)")
                    #endif
                    self?.error = "Failed to decode created address: \(error.localizedDescription)"
                    completion(.failure(error))
                }
            }
        }.resume()
    }

    /// Update an existing address
    public func updateAddress(
        userId: Int,
        addressId: Int,
        address: Address,
        completion: @escaping (Result<P2PCustomerAddress, Error>) -> Void
    ) {
        guard let url = URL(string: "\(baseURL)/addresses/\(userId)/\(addressId)") else {
            completion(.failure(P2PAPIError.invalidURL))
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        if let token = customerToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        let body: [String: Any] = [
            "location_name": address.locationName,
            "street": address.street,
            "unit": address.unit,
            "city": address.city,
            "state": address.state,
            "zip_code": address.zipCode,
            "instructions": address.instructions,
            "address_type": address.type,
            "latitude": address.latitude,
            "longitude": address.longitude,
            "phone_number": address.phoneNumber,
            "is_default": address.isDefault
        ]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        secureSession.dataTask(with: request) { [weak self] data, response, error in
            DispatchQueue.main.async {
                if let error = error {
                    self?.error = error.localizedDescription
                    completion(.failure(error))
                    return
                }

                guard let data = data else {
                    completion(.failure(P2PAPIError.noData))
                    return
                }

                if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode >= 400 {
                    if let errorResponse = try? JSONDecoder().decode(P2PErrorResponse.self, from: data) {
                        completion(.failure(P2PAPIError.serverError(errorResponse.detail)))
                    } else {
                        completion(.failure(P2PAPIError.serverError("Failed to update address")))
                    }
                    return
                }

                do {
                    let updatedAddress = try JSONDecoder().decode(P2PCustomerAddress.self, from: data)
                    completion(.success(updatedAddress))
                } catch {
                    self?.error = "Failed to decode updated address: \(error.localizedDescription)"
                    completion(.failure(error))
                }
            }
        }.resume()
    }

    /// Delete an address
    public func deleteAddress(
        userId: Int,
        addressId: Int,
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        guard let url = URL(string: "\(baseURL)/addresses/\(userId)/\(addressId)") else {
            completion(.failure(P2PAPIError.invalidURL))
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"

        if let token = customerToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        secureSession.dataTask(with: request) { [weak self] data, response, error in
            DispatchQueue.main.async {
                if let error = error {
                    self?.error = error.localizedDescription
                    completion(.failure(error))
                    return
                }

                if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode >= 400 {
                    if let data = data,
                       let errorResponse = try? JSONDecoder().decode(P2PErrorResponse.self, from: data) {
                        completion(.failure(P2PAPIError.serverError(errorResponse.detail)))
                    } else {
                        completion(.failure(P2PAPIError.serverError("Failed to delete address")))
                    }
                    return
                }

                completion(.success(()))
            }
        }.resume()
    }

    /// Set an address as default
    public func setDefaultAddress(
        userId: Int,
        addressId: Int,
        completion: @escaping (Result<P2PCustomerAddress, Error>) -> Void
    ) {
        guard let url = URL(string: "\(baseURL)/addresses/\(userId)/\(addressId)/set-default") else {
            completion(.failure(P2PAPIError.invalidURL))
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"

        if let token = customerToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        secureSession.dataTask(with: request) { [weak self] data, response, error in
            DispatchQueue.main.async {
                if let error = error {
                    self?.error = error.localizedDescription
                    completion(.failure(error))
                    return
                }

                guard let data = data else {
                    completion(.failure(P2PAPIError.noData))
                    return
                }

                if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode >= 400 {
                    if let errorResponse = try? JSONDecoder().decode(P2PErrorResponse.self, from: data) {
                        completion(.failure(P2PAPIError.serverError(errorResponse.detail)))
                    } else {
                        completion(.failure(P2PAPIError.serverError("Failed to set default address")))
                    }
                    return
                }

                do {
                    let address = try JSONDecoder().decode(P2PCustomerAddress.self, from: data)
                    completion(.success(address))
                } catch {
                    self?.error = "Failed to decode address: \(error.localizedDescription)"
                    completion(.failure(error))
                }
            }
        }.resume()
    }

    // MARK: - Customer Favorites APIs

    // MARK: - Customer Order APIs

    // MARK: - Order Creation API (Customer App)

    // MARK: - Confirm Order Payment (Customer App)

    // MARK: - Promo Code Validation API (Customer App)

    // MARK: - Vendor Orders API (Restaurant App)

    /// Fetch orders for a vendor from the P2P backend
    /// quick-366: holds the in-flight fetch task so a newer call can cancel an
    /// older one in flight. Avoids race conditions where a slow fetch lands
    /// after a fresh fetch and overwrites with stale data.
    private var inFlightVendorOrdersTask: URLSessionDataTask?

    // MARK: - Restaurant Acceptance Flow APIs (3-minute window)

    // MARK: - Delivery Decision Flow APIs (3-minute window)

    // MARK: - Vendor Stripe Connect (Payout Setup)

    // MARK: - Driver Authentication APIs

    /// Login as a driver
    public func driverLogin(
        email: String,
        password: String,
        completion: @escaping (Result<P2PDriverLoginResponse, Error>) -> Void
    ) {
        guard let url = URL(string: "\(baseURL)/auth/driver/login") else {
            completion(.failure(P2PAPIError.invalidURL))
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        // Properly URL-encode form values (special chars like ! @ # in passwords)
        var allowedCharacters = CharacterSet.alphanumerics
        allowedCharacters.insert(charactersIn: "-._~")
        guard let encodedEmail = email.addingPercentEncoding(withAllowedCharacters: allowedCharacters),
              let encodedPassword = password.addingPercentEncoding(withAllowedCharacters: allowedCharacters) else {
            // addingPercentEncoding should never return nil for standard CharacterSet
            // but if it does, fail loudly rather than send raw credentials
            completion(.failure(P2PAPIError.invalidURL))
            return
        }
        let bodyString = "username=\(encodedEmail)&password=\(encodedPassword)"
        request.httpBody = bodyString.data(using: .utf8)

        isLoading = true

        secureSession.dataTask(with: request) { [weak self] data, response, error in
            DispatchQueue.main.async {
                self?.isLoading = false

                if let error = error {
                    logger.error("driverLogin network error: \(error.localizedDescription)")
                    self?.error = error.localizedDescription
                    completion(.failure(error))
                    return
                }

                guard let data = data else {
                    logger.error("driverLogin: no data in response")
                    completion(.failure(P2PAPIError.noData))
                    return
                }

                // Check for error response
                if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode != 200 {
                    logger.error("driverLogin HTTP error: \(httpResponse.statusCode)")
                    if let errorResponse = try? JSONDecoder().decode(P2PErrorResponse.self, from: data) {
                        completion(.failure(P2PAPIError.serverError(errorResponse.detail)))
                    } else {
                        completion(.failure(P2PAPIError.serverError("Login failed")))
                    }
                    return
                }

                do {
                    let loginResponse = try JSONDecoder().decode(P2PDriverLoginResponse.self, from: data)

                    #if DEBUG
                    logger.info("=== DRIVER LOGIN SUCCESS ===")
                    logger.info("Driver ID from response: \(String(describing: loginResponse.driverId))")
                    logger.info("Driver Name: \(loginResponse.name)")
                    logger.info("Driver Status: \(loginResponse.status ?? "nil")")
                    logger.info("Is Approved: \(loginResponse.isApproved ?? false)")
                    logger.info("Access Token prefix: \(String(loginResponse.accessToken.prefix(20)))...")
                    #endif

                    // Store the token and driver info
                    SecureStorage.shared.driverAccessToken = loginResponse.accessToken
                    UserDefaults.standard.set(loginResponse.driverId, forKey: UserDefaultsKey.driverId)
                    UserDefaults.standard.set(loginResponse.driverCode, forKey: UserDefaultsKey.driverCode)
                    UserDefaults.standard.set(loginResponse.name, forKey: UserDefaultsKey.driverName)
                    UserDefaults.standard.set(loginResponse.email, forKey: UserDefaultsKey.driverEmail)
                    // Store driver status info for UI
                    UserDefaults.standard.set(loginResponse.status ?? "pending", forKey: UserDefaultsKey.driverStatus)
                    UserDefaults.standard.set(loginResponse.isApproved ?? false, forKey: UserDefaultsKey.driverIsApproved)
                    UserDefaults.standard.set(loginResponse.requiresDocuments ?? true, forKey: UserDefaultsKey.driverRequiresDocuments)
                    // Cache bank account fields for profile fallback
                    if let bank = loginResponse.bankAccount {
                        UserDefaults.standard.set(bank.bankName, forKey: "driver_bank_name")
                        UserDefaults.standard.set(bank.accountHolderName, forKey: "driver_bank_holder")
                        UserDefaults.standard.set(bank.accountNumberLast4, forKey: "driver_bank_last4")
                        UserDefaults.standard.set(bank.isVerified ?? false, forKey: "driver_bank_verified")
                    }

                    // Force synchronize and verify
                    UserDefaults.standard.synchronize()

                    #if DEBUG
                    let savedDriverId = UserDefaults.standard.object(forKey: UserDefaultsKey.driverId)
                    logger.info("VERIFIED - Saved driverId in UserDefaults: \(String(describing: savedDriverId))")
                    logger.info("VERIFIED - currentDriverId property: \(String(describing: self?.currentDriverId))")
                    #endif

                    completion(.success(loginResponse))
                } catch {
                    #if DEBUG
                    logger.error("DRIVER LOGIN DECODE ERROR: \(error)")
                    if let jsonString = String(data: data, encoding: .utf8) {
                        logger.info("Raw login response: \(jsonString)")
                    }
                    #endif
                    self?.error = "Failed to decode login response: \(error.localizedDescription)"
                    completion(.failure(error))
                }
            }
        }.resume()
    }

    /// Register a new driver
    public func driverRegister(
        email: String,
        password: String,
        firstName: String,
        lastName: String,
        phone: String,
        completion: @escaping (Result<P2PDriverLoginResponse, Error>) -> Void
    ) {
        guard let url = URL(string: "\(baseURL)/auth/driver/register") else {
            completion(.failure(P2PAPIError.invalidURL))
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = [
            "email": email,
            "password": password,
            "first_name": firstName,
            "last_name": lastName,
            "phone": phone
        ]

        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        isLoading = true
        error = nil

        secureSession.dataTask(with: request) { [weak self] data, response, error in
            DispatchQueue.main.async {
                self?.isLoading = false

                if let error = error {
                    self?.error = error.localizedDescription
                    completion(.failure(error))
                    return
                }

                guard let data = data else {
                    completion(.failure(P2PAPIError.noData))
                    return
                }

                // Check for error response
                if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode >= 400 {
                    if let errorResponse = try? JSONDecoder().decode(P2PErrorResponse.self, from: data) {
                        completion(.failure(P2PAPIError.serverError(errorResponse.detail)))
                    } else {
                        completion(.failure(P2PAPIError.serverError("Registration failed")))
                    }
                    return
                }

                do {
                    let loginResponse = try JSONDecoder().decode(P2PDriverLoginResponse.self, from: data)
                    // Store the token and driver info
                    SecureStorage.shared.driverAccessToken = loginResponse.accessToken
                    UserDefaults.standard.set(loginResponse.driverId, forKey: UserDefaultsKey.driverId)
                    UserDefaults.standard.set(loginResponse.driverCode, forKey: UserDefaultsKey.driverCode)
                    UserDefaults.standard.set(loginResponse.name, forKey: UserDefaultsKey.driverName)
                    UserDefaults.standard.set(loginResponse.email, forKey: UserDefaultsKey.driverEmail)
                    // Store driver status info for UI
                    UserDefaults.standard.set(loginResponse.status ?? "pending", forKey: UserDefaultsKey.driverStatus)
                    UserDefaults.standard.set(loginResponse.isApproved ?? false, forKey: UserDefaultsKey.driverIsApproved)
                    UserDefaults.standard.set(loginResponse.requiresDocuments ?? true, forKey: UserDefaultsKey.driverRequiresDocuments)
                    completion(.success(loginResponse))
                } catch {
                    self?.error = "Failed to decode response: \(error.localizedDescription)"
                    completion(.failure(error))
                }
            }
        }.resume()
    }

    /// Get stored driver ID
    public var currentDriverId: Int? {
        return UserDefaults.standard.object(forKey: UserDefaultsKey.driverId) as? Int
    }

    /// Get stored driver name
    public var currentDriverName: String? {
        return UserDefaults.standard.string(forKey: UserDefaultsKey.driverName)
    }

    /// Get stored driver code
    public var currentDriverCode: String? {
        return UserDefaults.standard.string(forKey: UserDefaultsKey.driverCode)
    }

    /// Get stored driver status (pending, approved, active, etc.)
    public var currentDriverStatus: String {
        return UserDefaults.standard.string(forKey: UserDefaultsKey.driverStatus) ?? "pending"
    }

    /// Check if driver is approved to accept jobs
    public var isDriverApproved: Bool {
        return UserDefaults.standard.bool(forKey: UserDefaultsKey.driverIsApproved)
    }

    /// Check if driver still needs to upload documents
    public var driverRequiresDocuments: Bool {
        return UserDefaults.standard.bool(forKey: UserDefaultsKey.driverRequiresDocuments)
    }

    /// Check if driver is logged in
    public var isDriverLoggedIn: Bool {
        return driverToken != nil
    }

    /// Driver logout
    public func driverLogout() {
        SecureStorage.shared.clearAuthTokens(type: .driver)
        UserDefaults.standard.removeObject(forKey: UserDefaultsKey.driverId)
        UserDefaults.standard.removeObject(forKey: UserDefaultsKey.driverCode)
        UserDefaults.standard.removeObject(forKey: UserDefaultsKey.driverName)
        UserDefaults.standard.removeObject(forKey: UserDefaultsKey.driverEmail)
        UserDefaults.standard.removeObject(forKey: UserDefaultsKey.driverStatus)
        UserDefaults.standard.removeObject(forKey: UserDefaultsKey.driverIsApproved)
        UserDefaults.standard.removeObject(forKey: UserDefaultsKey.driverRequiresDocuments)
    }

    /// Google OAuth login/registration for drivers
    /// This endpoint handles both login and registration - if user exists, logs them in; if not, registers them
    public func driverGoogleAuth(
        email: String,
        name: String,
        googleId: String,
        completion: @escaping (Result<P2PDriverLoginResponse, Error>) -> Void
    ) {
        guard let url = URL(string: "\(baseURL)/auth/driver/google") else {
            completion(.failure(P2PAPIError.invalidURL))
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = [
            "email": email,
            "name": name,
            "google_id": googleId
        ]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        isLoading = true

        secureSession.dataTask(with: request) { [weak self] data, response, error in
            DispatchQueue.main.async {
                self?.isLoading = false

                if let error = error {
                    self?.error = error.localizedDescription
                    completion(.failure(error))
                    return
                }

                guard let data = data else {
                    completion(.failure(P2PAPIError.noData))
                    return
                }

                if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode >= 400 {
                    // Check for registration-required response (403 with registration_url)
                    if httpResponse.statusCode == 403,
                       let regResponse = try? JSONDecoder().decode(P2PRegistrationRequiredResponse.self, from: data),
                       let regURL = regResponse.registrationUrl {
                        completion(.failure(P2PAPIError.registrationRequired(regResponse.detail, regURL)))
                        return
                    }
                    if let errorResponse = try? JSONDecoder().decode(P2PErrorResponse.self, from: data) {
                        completion(.failure(P2PAPIError.serverError(errorResponse.detail)))
                    } else {
                        completion(.failure(P2PAPIError.serverError("Google auth failed")))
                    }
                    return
                }

                do {
                    let loginResponse = try JSONDecoder().decode(P2PDriverLoginResponse.self, from: data)
                    // Store the token and driver info
                    SecureStorage.shared.driverAccessToken = loginResponse.accessToken
                    UserDefaults.standard.set(loginResponse.driverId, forKey: UserDefaultsKey.driverId)
                    UserDefaults.standard.set(loginResponse.driverCode, forKey: UserDefaultsKey.driverCode)
                    UserDefaults.standard.set(loginResponse.name, forKey: UserDefaultsKey.driverName)
                    UserDefaults.standard.set(loginResponse.email, forKey: UserDefaultsKey.driverEmail)
                    // Store driver status info for UI
                    UserDefaults.standard.set(loginResponse.status ?? "pending", forKey: UserDefaultsKey.driverStatus)
                    UserDefaults.standard.set(loginResponse.isApproved ?? false, forKey: UserDefaultsKey.driverIsApproved)
                    UserDefaults.standard.set(loginResponse.requiresDocuments ?? true, forKey: UserDefaultsKey.driverRequiresDocuments)
                    completion(.success(loginResponse))
                } catch {
                    self?.error = "Failed to decode Google auth response: \(error.localizedDescription)"
                    completion(.failure(error))
                }
            }
        }.resume()
    }

    /// Apple OAuth login/registration for drivers
    /// This endpoint handles both login and registration - if user exists, logs them in; if not, registers them
    public func driverAppleAuth(
        email: String,
        name: String,
        appleId: String,
        identityToken: String? = nil,
        completion: @escaping (Result<P2PDriverLoginResponse, Error>) -> Void
    ) {
        guard let url = URL(string: "\(baseURL)/auth/driver/apple-auth") else {
            completion(.failure(P2PAPIError.invalidURL))
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        var body: [String: Any] = [
            "email": email,
            "name": name,
            "apple_id": appleId
        ]
        // Include identity_token if available - backend can decode JWT to get real email
        if let token = identityToken {
            body["identity_token"] = token
        }
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        isLoading = true

        secureSession.dataTask(with: request) { [weak self] data, response, error in
            DispatchQueue.main.async {
                self?.isLoading = false

                if let error = error {
                    self?.error = error.localizedDescription
                    completion(.failure(error))
                    return
                }

                guard let data = data else {
                    completion(.failure(P2PAPIError.noData))
                    return
                }

                if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode >= 400 {
                    // Check for registration-required response (403 with registration_url)
                    if httpResponse.statusCode == 403,
                       let regResponse = try? JSONDecoder().decode(P2PRegistrationRequiredResponse.self, from: data),
                       let regURL = regResponse.registrationUrl {
                        completion(.failure(P2PAPIError.registrationRequired(regResponse.detail, regURL)))
                        return
                    }
                    if let errorResponse = try? JSONDecoder().decode(P2PErrorResponse.self, from: data) {
                        completion(.failure(P2PAPIError.serverError(errorResponse.detail)))
                    } else {
                        completion(.failure(P2PAPIError.serverError("Apple auth failed")))
                    }
                    return
                }

                do {
                    let loginResponse = try JSONDecoder().decode(P2PDriverLoginResponse.self, from: data)
                    // Store the token and driver info
                    SecureStorage.shared.driverAccessToken = loginResponse.accessToken
                    UserDefaults.standard.set(loginResponse.driverId, forKey: UserDefaultsKey.driverId)
                    UserDefaults.standard.set(loginResponse.driverCode, forKey: UserDefaultsKey.driverCode)
                    UserDefaults.standard.set(loginResponse.name, forKey: UserDefaultsKey.driverName)
                    UserDefaults.standard.set(loginResponse.email, forKey: UserDefaultsKey.driverEmail)
                    // Store driver status info for UI
                    UserDefaults.standard.set(loginResponse.status ?? "pending", forKey: UserDefaultsKey.driverStatus)
                    UserDefaults.standard.set(loginResponse.isApproved ?? false, forKey: UserDefaultsKey.driverIsApproved)
                    UserDefaults.standard.set(loginResponse.requiresDocuments ?? true, forKey: UserDefaultsKey.driverRequiresDocuments)
                    completion(.success(loginResponse))
                } catch {
                    self?.error = "Failed to decode Apple auth response: \(error.localizedDescription)"
                    completion(.failure(error))
                }
            }
        }.resume()
    }

    /// Get driver profile from P2P API
    public func getDriverProfile(
        driverId: Int,
        completion: @escaping (Result<[String: Any], Error>) -> Void
    ) {
        guard let url = URL(string: "\(baseURL)/erp/drivers/\(driverId)") else {
            completion(.failure(P2PAPIError.invalidURL))
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        // Add auth token if available
        if let token = driverToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        secureSession.dataTask(with: request) { [weak self] data, response, error in
            DispatchQueue.main.async {
                if let error = error {
                    self?.error = error.localizedDescription
                    completion(.failure(error))
                    return
                }

                guard let data = data else {
                    completion(.failure(P2PAPIError.noData))
                    return
                }

                // Try to decode as generic dictionary
                if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    completion(.success(json))
                } else {
                    // Return basic info from stored UserDefaults
                    let storedProfile: [String: Any] = [
                        "id": driverId,
                        "name": UserDefaults.standard.string(forKey: UserDefaultsKey.driverName) ?? "",
                        "email": UserDefaults.standard.string(forKey: UserDefaultsKey.driverEmail) ?? "",
                        "status": "pending",
                        "approval_status": "pending"
                    ]
                    completion(.success(storedProfile))
                }
            }
        }.resume()
    }

    // MARK: - Update Driver Profile

    /// Update driver profile information
    public func updateDriverProfile(
        driverId: Int,
        firstName: String? = nil,
        lastName: String? = nil,
        phone: String? = nil,
        street: String? = nil,
        city: String? = nil,
        state: String? = nil,
        zipCode: String? = nil,
        vehicleType: String? = nil,
        vehicleMake: String? = nil,
        vehicleModel: String? = nil,
        vehicleYear: Int? = nil,
        vehicleColor: String? = nil,
        licensePlate: String? = nil,
        licenseExpiry: Date? = nil,
        insuranceExpiry: Date? = nil,
        bankName: String? = nil,
        bankRoutingNumber: String? = nil,
        accountNumber: String? = nil,
        completion: @escaping (Result<[String: Any], Error>) -> Void
    ) {
        guard let url = URL(string: "\(baseURL)/drivers/\(driverId)") else {
            completion(.failure(P2PAPIError.invalidURL))
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        // Add auth token
        if let token = driverToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        // Build request body - only include non-nil values
        var body: [String: Any] = [:]

        if let firstName = firstName { body["first_name"] = firstName }
        if let lastName = lastName { body["last_name"] = lastName }
        if let phone = phone { body["phone"] = phone }
        if let street = street { body["street"] = street }
        if let city = city { body["city"] = city }
        if let state = state { body["state"] = state }
        if let zipCode = zipCode { body["zip_code"] = zipCode }
        if let vehicleType = vehicleType { body["vehicle_type"] = vehicleType }
        if let vehicleMake = vehicleMake { body["vehicle_make"] = vehicleMake }
        if let vehicleModel = vehicleModel { body["vehicle_model"] = vehicleModel }
        if let vehicleYear = vehicleYear { body["vehicle_year"] = vehicleYear }
        if let vehicleColor = vehicleColor { body["vehicle_color"] = vehicleColor }
        if let licensePlate = licensePlate { body["license_plate"] = licensePlate }

        if let licenseExpiry = licenseExpiry {
            let formatter = ISO8601DateFormatter()
            body["license_expiry"] = formatter.string(from: licenseExpiry)
        }
        if let insuranceExpiry = insuranceExpiry {
            let formatter = ISO8601DateFormatter()
            body["insurance_expiry"] = formatter.string(from: insuranceExpiry)
        }

        if let bankName = bankName, !bankName.isEmpty {
            body["bank_name"] = bankName
        }
        if let bankRoutingNumber = bankRoutingNumber, !bankRoutingNumber.isEmpty {
            body["bank_routing_number"] = bankRoutingNumber
        }
        if let accountNumber = accountNumber, !accountNumber.isEmpty {
            body["account_number"] = accountNumber
        }

        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        secureSession.dataTask(with: request) { data, response, error in
            DispatchQueue.main.async {
                if let error = error {
                    completion(.failure(error))
                    return
                }

                guard let data = data else {
                    completion(.failure(P2PAPIError.noData))
                    return
                }

                // Check HTTP status code
                if let httpResponse = response as? HTTPURLResponse {
                    if httpResponse.statusCode >= 400 {
                        if let errorJson = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                           let detail = errorJson["detail"] as? String {
                            completion(.failure(P2PAPIError.serverError(detail)))
                        } else {
                            completion(.failure(P2PAPIError.serverError("HTTP \(httpResponse.statusCode)")))
                        }
                        return
                    }
                }

                if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    completion(.success(json))
                } else {
                    completion(.failure(P2PAPIError.decodingError))
                }
            }
        }.resume()
    }

    // MARK: - Driver Documents APIs

    /// Fetch driver documents status
    public func getDriverDocuments(
        driverId: Int,
        completion: @escaping (Result<DriverDocumentsResponse, Error>) -> Void
    ) {
        guard let url = URL(string: "\(baseURL)/drivers/\(driverId)/documents") else {
            completion(.failure(P2PAPIError.invalidURL))
            return
        }

        var request = URLRequest(url: url)
        if let token = driverToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        secureSession.dataTask(with: request) { data, response, error in
            DispatchQueue.main.async {
                if let error = error {
                    completion(.failure(error))
                    return
                }

                guard let data = data else {
                    completion(.failure(P2PAPIError.noData))
                    return
                }

                do {
                    let response = try JSONDecoder().decode(DriverDocumentsResponse.self, from: data)
                    completion(.success(response))
                } catch {
                    completion(.failure(error))
                }
            }
        }.resume()
    }

    // TODO: [CRITICAL] API mismatch — backend alias at main_new.py:21033 maps POST /api/drivers/{id}/documents to wrong handler (get_driver_documents instead of upload_driver_document_by_id); upload silently fails
    /// Upload driver document (driver's license, insurance, etc.)
    public func uploadDriverDocument(
        driverId: Int,
        documentType: DriverDocumentType,
        imageData: Data,
        expiryDate: Date? = nil,
        completion: @escaping (Result<DocumentUploadResponse, Error>) -> Void
    ) {
        guard let url = URL(string: "\(baseURL)/drivers/\(driverId)/documents") else {
            completion(.failure(P2PAPIError.invalidURL))
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"

        // Add auth token
        if let token = driverToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        // Create multipart form data
        let boundary = UUID().uuidString
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        var body = Data()

        // Add document type field
        guard let boundaryData1 = "--\(boundary)\r\n".data(using: .utf8),
              let contentDisp1 = "Content-Disposition: form-data; name=\"document_type\"\r\n\r\n".data(using: .utf8),
              let docTypeData = "\(documentType.rawValue)\r\n".data(using: .utf8) else {
            completion(.failure(P2PAPIError.encodingFailed))
            return
        }
        body.append(boundaryData1)
        body.append(contentDisp1)
        body.append(docTypeData)

        // Add expiry date if provided
        if let expiryDate = expiryDate {
            let formatter = ISO8601DateFormatter()
            guard let boundaryData2 = "--\(boundary)\r\n".data(using: .utf8),
                  let contentDisp2 = "Content-Disposition: form-data; name=\"expiry_date\"\r\n\r\n".data(using: .utf8),
                  let expiryData = "\(formatter.string(from: expiryDate))\r\n".data(using: .utf8) else {
                completion(.failure(P2PAPIError.encodingFailed))
                return
            }
            body.append(boundaryData2)
            body.append(contentDisp2)
            body.append(expiryData)
        }

        // Add file
        guard let boundaryData3 = "--\(boundary)\r\n".data(using: .utf8),
              let contentDisp3 = "Content-Disposition: form-data; name=\"file\"; filename=\"\(documentType.rawValue).jpg\"\r\n".data(using: .utf8),
              let contentType = "Content-Type: image/jpeg\r\n\r\n".data(using: .utf8),
              let newline = "\r\n".data(using: .utf8),
              let closeBoundary = "--\(boundary)--\r\n".data(using: .utf8) else {
            completion(.failure(P2PAPIError.encodingFailed))
            return
        }
        body.append(boundaryData3)
        body.append(contentDisp3)
        body.append(contentType)
        body.append(imageData)
        body.append(newline)

        // Close boundary
        body.append(closeBoundary)

        request.httpBody = body

        isLoading = true

        secureSession.dataTask(with: request) { [weak self] data, response, error in
            DispatchQueue.main.async {
                self?.isLoading = false

                if let error = error {
                    self?.error = error.localizedDescription
                    completion(.failure(error))
                    return
                }

                guard let data = data else {
                    completion(.failure(P2PAPIError.noData))
                    return
                }

                do {
                    let response = try JSONDecoder().decode(DocumentUploadResponse.self, from: data)
                    completion(.success(response))
                } catch {
                    // Try to parse as generic JSON for error messages
                    if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                       let success = json["success"] as? Bool, success {
                        let mockResponse = DocumentUploadResponse(
                            success: true,
                            message: json["message"] as? String ?? "Document uploaded",
                            fileUrl: json["file_url"] as? String,
                            documentType: documentType.rawValue,
                            verificationStatus: json["verification_status"] as? String ?? "pending",
                            aiVerificationId: json["ai_verification_id"] as? String
                        )
                        completion(.success(mockResponse))
                    } else {
                        self?.error = "Failed to upload document"
                        completion(.failure(error))
                    }
                }
            }
        }.resume()
    }

    // MARK: - Driver Onboarding Documents (verified /auth/driver/documents contract)

    /// Upload a verification document for the authenticated driver.
    ///
    /// Posts multipart/form-data to `POST /api/auth/driver/documents` with the
    /// `document_type` + `file` fields the backend expects (main_new.py:6646).
    /// `documentType` must be one of: `drivers_license`, `insurance`,
    /// `vehicle_registration`. Driver JWT auth is taken from SecureStorage.
    /// On success the backend sets `drivers_license`/`insurance` = true on the driver.
    ///
    /// This is distinct from `uploadDriverDocument(driverId:documentType:imageData:...)`,
    /// which targets the `/drivers/{id}/documents` alias known to be mis-routed.
    public func uploadDriverDocument(
        documentType: String,
        imageData: Data,
        completion: @escaping (Result<[String: Any], Error>) -> Void
    ) {
        guard let token = driverToken else {
            completion(.failure(P2PAPIError.serverError("Driver not logged in")))
            return
        }

        guard let url = URL(string: "\(baseURL)/auth/driver/documents") else {
            completion(.failure(P2PAPIError.invalidURL))
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let boundary = UUID().uuidString
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        var body = Data()

        // document_type text field
        guard let docTypeField = "--\(boundary)\r\nContent-Disposition: form-data; name=\"document_type\"\r\n\r\n\(documentType)\r\n".data(using: .utf8),
              let fileHeader = "--\(boundary)\r\nContent-Disposition: form-data; name=\"file\"; filename=\"\(documentType).jpg\"\r\nContent-Type: image/jpeg\r\n\r\n".data(using: .utf8),
              let newline = "\r\n".data(using: .utf8),
              let closeBoundary = "--\(boundary)--\r\n".data(using: .utf8) else {
            completion(.failure(P2PAPIError.encodingFailed))
            return
        }
        body.append(docTypeField)
        body.append(fileHeader)
        body.append(imageData)
        body.append(newline)
        body.append(closeBoundary)

        request.httpBody = body

        secureSession.dataTask(with: request) { [weak self] data, response, error in
            DispatchQueue.main.async {
                if let error = error {
                    self?.error = error.localizedDescription
                    completion(.failure(error))
                    return
                }

                guard let data = data else {
                    completion(.failure(P2PAPIError.noData))
                    return
                }

                let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
                if statusCode >= 400 {
                    if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                       let detail = json["detail"] as? String {
                        completion(.failure(P2PAPIError.serverError(detail)))
                    } else {
                        completion(.failure(P2PAPIError.serverError("HTTP \(statusCode)")))
                    }
                    return
                }

                if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    completion(.success(json))
                } else {
                    completion(.failure(P2PAPIError.decodingError))
                }
            }
        }.resume()
    }

    /// Fetch the authenticated driver's document status.
    ///
    /// Calls `GET /api/auth/driver/documents`, returning the raw JSON which
    /// contains `documents.drivers_license.uploaded`, `documents.insurance.uploaded`
    /// and `documents.background_check.completed` booleans (main_new.py:6700).
    public func getDriverDocumentsStatus(
        completion: @escaping (Result<[String: Any], Error>) -> Void
    ) {
        guard let token = driverToken else {
            completion(.failure(P2PAPIError.serverError("Driver not logged in")))
            return
        }

        guard let url = URL(string: "\(baseURL)/auth/driver/documents") else {
            completion(.failure(P2PAPIError.invalidURL))
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        secureSession.dataTask(with: request) { data, _, error in
            DispatchQueue.main.async {
                if let error = error {
                    completion(.failure(error))
                    return
                }
                guard let data = data,
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                    completion(.failure(P2PAPIError.noData))
                    return
                }
                completion(.success(json))
            }
        }.resume()
    }

    /// Fetch the authenticated driver's live profile/status.
    ///
    /// Calls `GET /api/auth/driver/me` (main_new.py:3527). The returned JSON
    /// includes `status` (`pending`/`approved`/`active`/…). On success this also
    /// persists `status` + derived approval flag to UserDefaults so the gate
    /// (AuthManager / P2PAPIService.isDriverApproved) reflects the latest value.
    public func getDriverMe(
        completion: @escaping (Result<[String: Any], Error>) -> Void
    ) {
        guard let token = driverToken else {
            completion(.failure(P2PAPIError.serverError("Driver not logged in")))
            return
        }

        guard let url = URL(string: "\(baseURL)/auth/driver/me") else {
            completion(.failure(P2PAPIError.invalidURL))
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        secureSession.dataTask(with: request) { data, response, error in
            DispatchQueue.main.async {
                if let error = error {
                    completion(.failure(error))
                    return
                }
                guard let data = data else {
                    completion(.failure(P2PAPIError.noData))
                    return
                }

                // Check HTTP status BEFORE trusting the body as success — an error body like
                // {"detail": "Authentication required"} is still valid JSON and would otherwise
                // be mistaken for a successful profile response (callers rely on this function
                // to detect a truly-invalid token, e.g. for session restore on launch).
                if let http = response as? HTTPURLResponse, http.statusCode >= 400 {
                    let detail = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])
                        .flatMap { $0?["detail"] as? String }
                        ?? "Unable to load driver profile (\(http.statusCode))"
                    if http.statusCode == 401 || http.statusCode == 403 {
                        completion(.failure(P2PAPIError.unauthorized(detail)))
                    } else {
                        completion(.failure(P2PAPIError.serverError(detail)))
                    }
                    return
                }

                guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                    completion(.failure(P2PAPIError.noData))
                    return
                }

                // Persist latest status so isDriverApproved / gate stays in sync.
                if let statusValue = json["status"] as? String {
                    let approved = ["approved", "active", "online"].contains(statusValue.lowercased())
                    UserDefaults.standard.set(statusValue, forKey: UserDefaultsKey.driverStatus)
                    UserDefaults.standard.set(approved, forKey: UserDefaultsKey.driverIsApproved)
                }
                // Repopulate id/name/email in case local UserDefaults was cleared (e.g. a
                // delete+reinstall that wipes UserDefaults but leaves a Keychain-backed token
                // behind) while the backend session is still valid — keeps the driver logged
                // in instead of forcing them back to the login screen.
                if let id = json["id"] as? Int {
                    UserDefaults.standard.set(id, forKey: UserDefaultsKey.driverId)
                }
                if let code = json["driver_code"] as? String {
                    UserDefaults.standard.set(code, forKey: UserDefaultsKey.driverCode)
                }
                if let name = json["name"] as? String {
                    UserDefaults.standard.set(name, forKey: UserDefaultsKey.driverName)
                }
                if let email = json["email"] as? String {
                    UserDefaults.standard.set(email, forKey: UserDefaultsKey.driverEmail)
                }

                completion(.success(json))
            }
        }.resume()
    }

    // MARK: - Driver Delivery APIs

    /// Refresh driver token - call when receiving 401 Unauthorized
    public func refreshDriverToken(completion: @escaping (Result<String, Error>) -> Void) {
        guard let token = driverToken else {
            completion(.failure(P2PAPIError.serverError("No token to refresh")))
            return
        }

        guard let url = URL(string: "\(baseURL)/auth/driver/refresh") else {
            completion(.failure(P2PAPIError.invalidURL))
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        secureSession.dataTask(with: request) { data, response, error in
            if let error = error {
                DispatchQueue.main.async {
                    completion(.failure(error))
                }
                return
            }

            guard let httpResponse = response as? HTTPURLResponse else {
                DispatchQueue.main.async {
                    completion(.failure(P2PAPIError.serverError("Invalid response")))
                }
                return
            }

            if httpResponse.statusCode == 200, let data = data {
                do {
                    if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                       let newToken = json["access_token"] as? String {
                        // Save new token securely
                        SecureStorage.shared.driverAccessToken = newToken
                        DispatchQueue.main.async {
                            #if DEBUG
                            logger.info("Token refreshed successfully")
                            #endif
                            completion(.success(newToken))
                        }
                        return
                    }
                } catch {
                    // Parse error
                }
            }

            DispatchQueue.main.async {
                completion(.failure(P2PAPIError.serverError("Token refresh failed - please log in again")))
            }
        }.resume()
    }

    /// Refresh customer token - call when receiving 401 Unauthorized.
    /// Mirrors `refreshDriverToken`: POST /api/auth/customer/refresh.
    /// The stored customer refresh token (SecureStorage.customerRefreshToken) is sent in
    /// the body so backends that key off the refresh token can use it, while the current
    /// access token is sent as the Bearer (matching the driver flow's proven pattern).
    public func refreshCustomerToken(completion: @escaping (Result<String, Error>) -> Void) {
        guard let token = customerToken else {
            completion(.failure(P2PAPIError.serverError("No token to refresh")))
            return
        }

        guard let url = URL(string: "\(baseURL)/auth/customer/refresh") else {
            completion(.failure(P2PAPIError.invalidURL))
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        if let refresh = SecureStorage.shared.customerRefreshToken {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try? JSONSerialization.data(withJSONObject: ["refresh_token": refresh])
        }

        secureSession.dataTask(with: request) { data, response, error in
            if let error = error {
                DispatchQueue.main.async { completion(.failure(error)) }
                return
            }

            guard let httpResponse = response as? HTTPURLResponse else {
                DispatchQueue.main.async {
                    completion(.failure(P2PAPIError.serverError("Invalid response")))
                }
                return
            }

            if httpResponse.statusCode == 200, let data = data,
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let newToken = json["access_token"] as? String {
                // Persist new access token (and rotated refresh token when provided)
                if let newRefresh = json["refresh_token"] as? String {
                    SecureStorage.shared.saveAuthTokens(accessToken: newToken, refreshToken: newRefresh, type: .customer)
                } else {
                    SecureStorage.shared.customerAccessToken = newToken
                }
                DispatchQueue.main.async {
                    #if DEBUG
                    logger.info("Customer token refreshed successfully")
                    #endif
                    completion(.success(newToken))
                }
                return
            }

            DispatchQueue.main.async {
                completion(.failure(P2PAPIError.serverError("Token refresh failed - please log in again")))
            }
        }.resume()
    }

    /// Execute an authenticated customer request, refreshing the customer token once on 401.
    ///
    /// `makeRequest` is a closure so the retried attempt rebuilds the URLRequest and picks
    /// up the freshly-refreshed Bearer token. Completion is always delivered on the main queue.
    private func performCustomerRequest(
        _ makeRequest: @escaping () -> URLRequest?,
        retryOnExpired: Bool = true,
        completion: @escaping (Result<Data, Error>) -> Void
    ) {
        guard let request = makeRequest() else {
            DispatchQueue.main.async { completion(.failure(P2PAPIError.invalidURL)) }
            return
        }

        secureSession.dataTask(with: request) { [weak self] data, response, error in
            if let error = error {
                DispatchQueue.main.async { completion(.failure(error)) }
                return
            }

            if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 401, retryOnExpired {
                self?.refreshCustomerToken { result in
                    switch result {
                    case .success:
                        self?.performCustomerRequest(makeRequest, retryOnExpired: false, completion: completion)
                    case .failure:
                        DispatchQueue.main.async {
                            NotificationCenter.default.post(name: Notification.Name("CustomerTokenExpired"), object: nil)
                            completion(.failure(P2PAPIError.serverError("Session expired - please log in again")))
                        }
                    }
                }
                return
            }

            guard let data = data else {
                DispatchQueue.main.async { completion(.failure(P2PAPIError.noData)) }
                return
            }

            DispatchQueue.main.async { completion(.success(data)) }
        }.resume()
    }

    /// Update driver location (with automatic token refresh on 401)
    public func updateDriverLocation(
        latitude: Double,
        longitude: Double,
        completion: @escaping (Result<Bool, Error>) -> Void
    ) {
        updateDriverLocationInternal(latitude: latitude, longitude: longitude, retryOnExpired: true, completion: completion)
    }

    /// Internal implementation with retry capability
    private func updateDriverLocationInternal(
        latitude: Double,
        longitude: Double,
        retryOnExpired: Bool,
        completion: @escaping (Result<Bool, Error>) -> Void
    ) {
        guard let token = driverToken else {
            completion(.failure(P2PAPIError.serverError("Driver not logged in")))
            return
        }

        guard let url = URL(string: "\(baseURL)/auth/driver/location?latitude=\(latitude)&longitude=\(longitude)") else {
            completion(.failure(P2PAPIError.invalidURL))
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        secureSession.dataTask(with: request) { [weak self] data, response, error in
            if let error = error {
                DispatchQueue.main.async {
                    self?.error = error.localizedDescription
                    completion(.failure(error))
                }
                return
            }

            // Check for 401 Unauthorized - token expired
            if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 401 {
                if retryOnExpired {
                    #if DEBUG
                    logger.info("Token expired, attempting refresh...")
                    #endif
                    self?.refreshDriverToken { result in
                        switch result {
                        case .success:
                            // Retry the request with new token
                            self?.updateDriverLocationInternal(
                                latitude: latitude,
                                longitude: longitude,
                                retryOnExpired: false,
                                completion: completion
                            )
                        case .failure(let error):
                            // Token refresh failed - user needs to re-login
                            #if DEBUG
                            logger.info("Token refresh failed: \(error)")
                            #endif
                            NotificationCenter.default.post(
                                name: Notification.Name("DriverTokenExpired"),
                                object: nil
                            )
                            completion(.failure(P2PAPIError.serverError("Session expired - please log in again")))
                        }
                    }
                    return
                } else {
                    // Already retried, fail
                    DispatchQueue.main.async {
                        NotificationCenter.default.post(
                            name: Notification.Name("DriverTokenExpired"),
                            object: nil
                        )
                        completion(.failure(P2PAPIError.serverError("Session expired - please log in again")))
                    }
                    return
                }
            }

            DispatchQueue.main.async {
                completion(.success(true))
            }
        }.resume()
    }

    /// Set driver online/offline status (with automatic token refresh on 401)
    ///
    /// Backend `PUT /api/auth/driver/online` returns 403 until the background check
    /// passes. We MUST inspect the HTTP status rather than reporting success for any
    /// non-transport response (the previous implementation faked success on 403).
    public func setDriverOnlineStatus(
        isOnline: Bool,
        completion: @escaping (Result<Bool, Error>) -> Void
    ) {
        setDriverOnlineStatusInternal(isOnline: isOnline, retryOnExpired: true, completion: completion)
    }

    private func setDriverOnlineStatusInternal(
        isOnline: Bool,
        retryOnExpired: Bool,
        completion: @escaping (Result<Bool, Error>) -> Void
    ) {
        guard let token = driverToken else {
            completion(.failure(P2PAPIError.serverError("Driver not logged in")))
            return
        }

        guard let url = URL(string: "\(baseURL)/auth/driver/online?is_online=\(isOnline)") else {
            completion(.failure(P2PAPIError.invalidURL))
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        secureSession.dataTask(with: request) { [weak self] data, response, error in
            if let error = error {
                DispatchQueue.main.async {
                    self?.error = error.localizedDescription
                    completion(.failure(error))
                }
                return
            }

            let httpResponse = response as? HTTPURLResponse
            let statusCode = httpResponse?.statusCode ?? 0

            // 401 → attempt a single token refresh then retry (blocker 5)
            if statusCode == 401, retryOnExpired {
                self?.refreshDriverToken { result in
                    switch result {
                    case .success:
                        self?.setDriverOnlineStatusInternal(isOnline: isOnline, retryOnExpired: false, completion: completion)
                    case .failure:
                        DispatchQueue.main.async {
                            NotificationCenter.default.post(name: Notification.Name("DriverTokenExpired"), object: nil)
                            completion(.failure(P2PAPIError.serverError("Session expired - please log in again")))
                        }
                    }
                }
                return
            }

            // Extract server `detail` message when present
            func serverDetail() -> String? {
                guard let data = data,
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                    return nil
                }
                return json["detail"] as? String
            }

            DispatchQueue.main.async {
                // 403 → compliance gate (background check not approved). Surface the reason.
                if statusCode == 403 {
                    let detail = serverDetail() ?? "You must complete your background check before going online."
                    completion(.failure(P2PAPIError.gateError(detail)))
                    return
                }

                // Any other HTTP error → real failure (do NOT fake success)
                if statusCode >= 400 {
                    let message = serverDetail() ?? "HTTP \(statusCode)"
                    completion(.failure(P2PAPIError.serverError(message)))
                    return
                }

                completion(.success(true))
            }
        }.resume()
    }

    /// Optional payout fields of GET /api/driver/earnings. Both are nil when the server does not
    /// send them (older backend), so the UI shows a dash instead of a made-up $0.00 / 0.0 h.
    public struct DriverPayoutFields {
        public let availableBalance: Double?
        public let hoursOnline: Double?
    }

    /// GET /api/driver/earnings?period=today|week|month. `hours_online` may be a number (for the
    /// requested period) or an object keyed today/week/month; `available_balance` a number or string.
    public func getDriverPayoutFields(
        period: String,
        completion: @escaping (Result<DriverPayoutFields, Error>) -> Void
    ) {
        guard let url = URL(string: "\(baseURL)/driver/earnings?period=\(period)") else {
            completion(.failure(P2PAPIError.invalidURL))
            return
        }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let token = driverToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        secureSession.dataTask(with: request) { data, response, error in
            DispatchQueue.main.async {
                if let error = error {
                    completion(.failure(error))
                    return
                }
                guard let data = data,
                      (response as? HTTPURLResponse)?.statusCode == 200,
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                    completion(.failure(P2PAPIError.noData))
                    return
                }
                completion(.success(DriverPayoutFields(
                    availableBalance: Self.number(json["available_balance"]),
                    hoursOnline: Self.hours(json["hours_online"], period: period)
                )))
            }
        }.resume()
    }

    private static func number(_ value: Any?) -> Double? {
        if let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID() { return number.doubleValue }
        if let text = value as? String { return Double(text) }
        return nil
    }

    private static func hours(_ value: Any?, period: String) -> Double? {
        if let object = value as? [String: Any] {
            let keys: [String]
            switch period {
            case "week": keys = ["week", "this_week"]
            case "month": keys = ["month", "this_month"]
            default: keys = ["today"]
            }
            return keys.compactMap { number(object[$0]) }.first
        }
        return number(value)
    }

    /// Fetch driver earnings dashboard from V5 API
    public func getDriverDashboard(
        driverId: String,
        completion: @escaping (Result<DriverDashboardResponse, Error>) -> Void
    ) {
        guard let url = URL(string: "\(baseURL)/v5/driver/\(driverId)/dashboard") else {
            completion(.failure(P2PAPIError.invalidURL))
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        if let token = driverToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        secureSession.dataTask(with: request) { [weak self] data, response, error in
            DispatchQueue.main.async {
                if let error = error {
                    self?.error = error.localizedDescription
                    completion(.failure(error))
                    return
                }

                guard let data = data else {
                    completion(.failure(P2PAPIError.noData))
                    return
                }

                // Check for HTTP errors
                if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode >= 400 {
                    if let errorJson = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                       let detail = errorJson["detail"] as? String {
                        completion(.failure(P2PAPIError.serverError(detail)))
                    } else {
                        completion(.failure(P2PAPIError.serverError("HTTP \(httpResponse.statusCode)")))
                    }
                    return
                }

                do {
                    let dashboard = try JSONDecoder().decode(DriverDashboardResponse.self, from: data)
                    completion(.success(dashboard))
                } catch {
                    #if DEBUG
                    logger.info("Failed to decode driver dashboard: \(error)")
                    if let jsonString = String(data: data, encoding: .utf8) {
                        logger.info("Raw response: \(jsonString)")
                    }
                    #endif
                    completion(.failure(error))
                }
            }
        }.resume()
    }

    /// Update driver location for an order
    public func updateDriverLocation(
        orderId: Int,
        latitude: Double,
        longitude: Double,
        completion: @escaping (Result<Bool, Error>) -> Void
    ) {
        guard let token = driverToken else {
            completion(.failure(P2PAPIError.serverError("Driver not logged in")))
            return
        }

        guard let url = URL(string: "\(baseURL)/erp/orders/\(orderId)/driver-location") else {
            completion(.failure(P2PAPIError.invalidURL))
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = [
            "latitude": latitude,
            "longitude": longitude,
            "updated_at": ISO8601DateFormatter().string(from: Date())
        ]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        secureSession.dataTask(with: request) { _, _, _ in
            DispatchQueue.main.async {
                completion(.success(true))
            }
        }.resume()
    }

    // MARK: - P2P Ride APIs (Ride-sharing like Uber)

    /// Fetch available rides for drivers
    public func fetchAvailableRides(
        completion: @escaping (Result<[P2PRide], Error>) -> Void
    ) {
        guard let url = URL(string: "\(baseURL)/erp/rides/available") else {
            completion(.failure(P2PAPIError.invalidURL))
            return
        }

        var request = URLRequest(url: url)
        if let token = driverToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        secureSession.dataTask(with: request) { data, response, error in
            DispatchQueue.main.async {
                if let error = error {
                    #if DEBUG
                    logger.error("fetchAvailableRides network error: \(error.localizedDescription)")
                    #endif
                    completion(.failure(error))
                    return
                }

                // Check HTTP status code
                if let httpResponse = response as? HTTPURLResponse {
                    #if DEBUG
                    logger.info("fetchAvailableRides status: \(httpResponse.statusCode)")
                    #endif
                    if httpResponse.statusCode == 404 {
                        // Endpoint not available - return empty rides
                        completion(.success([]))
                        return
                    }
                }

                guard let data = data, !data.isEmpty else {
                    // No data - return empty rides instead of error
                    completion(.success([]))
                    return
                }

                do {
                    let response = try JSONDecoder().decode(P2PRidesResponse.self, from: data)
                    completion(.success(response.rides))
                } catch {
                    #if DEBUG
                    logger.error("Ride decode error: \(error)")
                    if let jsonString = String(data: data, encoding: .utf8) {
                        logger.info("Raw response: \(jsonString.prefix(500))")
                    }
                    #endif
                    // If decode fails, return empty rides instead of crashing
                    completion(.success([]))
                }
            }
        }.resume()
    }

    /// Get MATCHED and IN_PROGRESS rides for the authenticated driver.
    /// Calls GET /api/rides/driver/active — populates DeliveryViewModel.myActiveRides.
    public func fetchDriverActiveRides(
        completion: @escaping (Result<[RideRequestForBidding], Error>) -> Void
    ) {
        guard let url = URL(string: "\(baseURL)/rides/driver/active") else {
            completion(.failure(P2PAPIError.invalidURL))
            return
        }

        var request = URLRequest(url: url)
        if let token = driverToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        secureSession.dataTask(with: request) { data, response, error in
            DispatchQueue.main.async {
                if let error = error {
                    completion(.failure(error))
                    return
                }

                guard let data = data, !data.isEmpty else {
                    completion(.success([]))
                    return
                }

                do {
                    let response = try JSONDecoder().decode(DriverActiveRidesResponse.self, from: data)
                    completion(.success(response.active_rides))
                } catch {
                    #if DEBUG
                    logger.error("fetchDriverActiveRides decode error: \(error)")
                    #endif
                    completion(.success([]))
                }
            }
        }.resume()
    }

    /// Accept a ride (driver picks up passenger)
    public func acceptRide(
        rideId: Int,
        completion: @escaping (Result<Bool, Error>) -> Void
    ) {
        guard let driverId = currentDriverId else {
            completion(.failure(P2PAPIError.serverError("Driver not logged in")))
            return
        }

        guard let url = URL(string: "\(baseURL)/erp/rides/\(rideId)/accept") else {
            completion(.failure(P2PAPIError.invalidURL))
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        if let token = driverToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        let body: [String: Any] = ["driver_id": driverId]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        secureSession.dataTask(with: request) { data, response, error in
            DispatchQueue.main.async {
                if let error = error {
                    completion(.failure(error))
                    return
                }

                if let httpResponse = response as? HTTPURLResponse {
                    if httpResponse.statusCode == 200 {
                        completion(.success(true))
                    } else {
                        if let data = data,
                           let errorResponse = try? JSONDecoder().decode(P2PErrorResponse.self, from: data) {
                            completion(.failure(P2PAPIError.serverError(errorResponse.detail)))
                        } else {
                            completion(.failure(P2PAPIError.serverError("Failed to accept ride")))
                        }
                    }
                }
            }
        }.resume()
    }

    /// Mark passenger as picked up
    public func ridePickedUp(
        rideId: Int,
        completion: @escaping (Result<Bool, Error>) -> Void
    ) {
        guard let token = driverToken else {
            completion(.failure(P2PAPIError.serverError("Driver not logged in")))
            return
        }

        guard let url = URL(string: "\(baseURL)/erp/rides/\(rideId)/picked-up") else {
            completion(.failure(P2PAPIError.invalidURL))
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        secureSession.dataTask(with: request) { data, response, error in
            DispatchQueue.main.async {
                if let error = error {
                    completion(.failure(error))
                    return
                }

                if let httpResponse = response as? HTTPURLResponse {
                    if httpResponse.statusCode == 200 {
                        completion(.success(true))
                    } else {
                        if let data = data,
                           let errorResponse = try? JSONDecoder().decode(P2PErrorResponse.self, from: data) {
                            completion(.failure(P2PAPIError.serverError(errorResponse.detail)))
                        } else {
                            completion(.failure(P2PAPIError.serverError("Failed to confirm pickup")))
                        }
                    }
                }
            }
        }.resume()
    }

    // MARK: - Customer Ride Request APIs

    /// Get fare estimate from production API (consistent pricing with Android)
    /// Uses same endpoint as Android: /api/rides/estimate
    public func estimateRideFare(
        pickupLat: Double,
        pickupLng: Double,
        dropoffLat: Double,
        dropoffLng: Double,
        stateCode: String = "CA",
        completion: @escaping (Result<RideFareEstimateResponse, Error>) -> Void
    ) {
        guard let url = URL(string: "\(baseURL)/rides/estimate") else {
            completion(.failure(P2PAPIError.invalidURL))
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        // Include auth header if available (endpoint accepts both authenticated and public requests)
        if let token = customerToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        let body: [String: Any] = [
            "pickup_latitude": pickupLat,
            "pickup_longitude": pickupLng,
            "dropoff_latitude": dropoffLat,
            "dropoff_longitude": dropoffLng,
            "state_code": stateCode
        ]

        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        secureSession.dataTask(with: request) { data, response, error in
            DispatchQueue.main.async {
                if let error = error {
                    completion(.failure(error))
                    return
                }

                guard let data = data else {
                    completion(.failure(P2PAPIError.noData))
                    return
                }

                do {
                    let response = try JSONDecoder().decode(RideFareEstimateResponse.self, from: data)
                    completion(.success(response))
                } catch {
                    #if DEBUG
                    logger.error("Fare estimate decode error: \(error)")
                    if let str = String(data: data, encoding: .utf8) {
                        logger.info("Response: \(str)")
                    }
                    #endif
                    completion(.failure(error))
                }
            }
        }.resume()
    }

    /// Request a ride (customer requests pickup)
    /// Production: POST /api/rides/request
    ///
    /// Required fields per OpenAPI CreateRideRequestInput schema:
    /// - customer_id: Int
    /// - pickup_address: String
    /// - pickup_latitude: Double
    /// - pickup_longitude: Double
    /// - dropoff_address: String
    /// - dropoff_latitude: Double
    /// - dropoff_longitude: Double
    public func requestRide(
        customerId: Int,
        pickupAddress: RideAddressInput,
        dropoffAddress: RideAddressInput,
        notes: String? = nil,
        preferredPrice: Double? = nil,
        accessibilityRequested: Bool = false,
        accessibilityNotes: String? = nil,
        completion: @escaping (Result<RideRequestResponse, Error>) -> Void
    ) {
        // Build flat structure matching production API schema
        var body: [String: Any] = [
            "customer_id": customerId,
            "pickup_address": pickupAddress.fullAddress,
            "pickup_latitude": pickupAddress.lat,
            "pickup_longitude": pickupAddress.lng,
            "dropoff_address": dropoffAddress.fullAddress,
            "dropoff_latitude": dropoffAddress.lat,
            "dropoff_longitude": dropoffAddress.lng,
            "ride_type": "standard",
            "bidding_duration_minutes": 5
        ]

        // Add optional fields
        if let notes = notes, !notes.isEmpty {
            body["special_requests"] = notes
        }
        if let price = preferredPrice, price > 0 {
            body["customer_preferred_price"] = price
        }
        // TNC-12: Accessibility request
        if accessibilityRequested {
            body["accessibility_requested"] = true
            if let accessNotes = accessibilityNotes, !accessNotes.isEmpty {
                body["accessibility_notes"] = accessNotes
            }
        }

        // Routed through performCustomerRequest so a 401 triggers a token refresh + retry
        // instead of dead-ending the customer into a re-login.
        performCustomerRequest({ [weak self] in
            guard let self = self, let url = URL(string: "\(self.baseURL)/rides/request") else { return nil }
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            if let token = self.customerToken {
                request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            }
            request.httpBody = try? JSONSerialization.data(withJSONObject: body)
            return request
        }) { result in
            switch result {
            case .failure(let error):
                completion(.failure(error))
            case .success(let data):
                do {
                    let response = try JSONDecoder().decode(RideRequestResponse.self, from: data)
                    completion(.success(response))
                } catch {
                    #if DEBUG
                    logger.error("Ride request decode error: \(error)")
                    #endif
                    // Try to get error message from response
                    if let errorResponse = try? JSONDecoder().decode(P2PErrorResponse.self, from: data) {
                        completion(.failure(P2PAPIError.serverError(errorResponse.detail)))
                    } else {
                        completion(.failure(error))
                    }
                }
            }
        }
    }

    /// Track customer's active ride
    public func trackMyRide(
        rideId: Int,
        completion: @escaping (Result<RideTrackingInfo, Error>) -> Void
    ) {
        guard let url = URL(string: "\(baseURL)/erp/rides/\(rideId)/track") else {
            completion(.failure(P2PAPIError.invalidURL))
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        if let token = customerToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        secureSession.dataTask(with: request) { data, response, error in
            DispatchQueue.main.async {
                if let error = error {
                    completion(.failure(error))
                    return
                }

                guard let data = data else {
                    completion(.failure(P2PAPIError.noData))
                    return
                }

                do {
                    let response = try JSONDecoder().decode(RideTrackingInfo.self, from: data)
                    completion(.success(response))
                } catch {
                    completion(.failure(error))
                }
            }
        }.resume()
    }

    // MARK: - Ride Bidding APIs (P2P Matchmaking Platform)

    /// Fetch available ride requests near the driver for bidding
    public func fetchAvailableRideRequests(
        latitude: Double?,
        longitude: Double?,
        radiusKm: Double = 15.0,
        completion: @escaping (Result<[RideRequestForBidding], Error>) -> Void
    ) {
        guard let driverId = currentDriverId else {
            completion(.failure(P2PAPIError.serverError("Driver not logged in")))
            return
        }

        var urlComponents = URLComponents(string: "\(baseURL)/rides/available")
        var queryItems = [URLQueryItem(name: "driver_id", value: String(driverId))]
        // Without a GPS fix, omit coordinates: sending 0,0 makes the server's radius filter hide every ride.
        if let latitude = latitude, let longitude = longitude {
            queryItems.append(URLQueryItem(name: "latitude", value: String(latitude)))
            queryItems.append(URLQueryItem(name: "longitude", value: String(longitude)))
            queryItems.append(URLQueryItem(name: "radius_km", value: String(radiusKm)))
        }
        urlComponents?.queryItems = queryItems

        guard let url = urlComponents?.url else {
            completion(.failure(P2PAPIError.invalidURL))
            return
        }

        var request = URLRequest(url: url)
        if let token = driverToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        secureSession.dataTask(with: request) { data, response, error in
            DispatchQueue.main.async {
                if let error = error {
                    completion(.failure(error))
                    return
                }

                guard let data = data else {
                    completion(.failure(P2PAPIError.noData))
                    return
                }

                // Surface server errors instead of showing an empty list (which would hide
                // a 5xx/401 and silently drop available rides).
                if let http = response as? HTTPURLResponse, http.statusCode >= 400 {
                    completion(.failure(P2PAPIError.serverError("Unable to load available rides (\(http.statusCode))")))
                    return
                }

                do {
                    let response = try JSONDecoder().decode(AvailableRideRequestsResponse.self, from: data)
                    completion(.success(response.available_requests))
                } catch {
                    #if DEBUG
                    logger.error("fetchAvailableRideRequests decode error: \(error)")
                    if let jsonString = String(data: data, encoding: .utf8) {
                        logger.info("Raw response: \(jsonString.prefix(500))")
                    }
                    #endif
                    completion(.failure(error))
                }
            }
        }.resume()
    }

    /// Submit a bid on a ride request
    public func submitRideBid(
        requestId: Int,
        proposedPrice: Double,
        message: String? = nil,
        estimatedArrivalMinutes: Int? = nil,
        completion: @escaping (Result<RideBidResponse, Error>) -> Void
    ) {
        submitRideBidInternal(
            requestId: requestId,
            proposedPrice: proposedPrice,
            message: message,
            estimatedArrivalMinutes: estimatedArrivalMinutes,
            retryOnExpired: true,
            completion: completion
        )
    }

    private func submitRideBidInternal(
        requestId: Int,
        proposedPrice: Double,
        message: String?,
        estimatedArrivalMinutes: Int?,
        retryOnExpired: Bool,
        completion: @escaping (Result<RideBidResponse, Error>) -> Void
    ) {
        guard let driverId = currentDriverId else {
            completion(.failure(P2PAPIError.serverError("Driver not logged in")))
            return
        }

        guard let url = URL(string: "\(baseURL)/rides/request/\(requestId)/bid") else {
            completion(.failure(P2PAPIError.invalidURL))
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        if let token = driverToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        var body: [String: Any] = [
            "driver_id": driverId,
            "proposed_price": proposedPrice
        ]
        if let message = message {
            body["message"] = message
        }
        if let eta = estimatedArrivalMinutes {
            body["estimated_arrival_minutes"] = eta
        }

        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        secureSession.dataTask(with: request) { [weak self] data, response, error in
            if let error = error {
                DispatchQueue.main.async { completion(.failure(error)) }
                return
            }

            // 401 → refresh driver token once and retry (blocker 5)
            if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 401, retryOnExpired {
                self?.refreshDriverToken { result in
                    switch result {
                    case .success:
                        self?.submitRideBidInternal(
                            requestId: requestId,
                            proposedPrice: proposedPrice,
                            message: message,
                            estimatedArrivalMinutes: estimatedArrivalMinutes,
                            retryOnExpired: false,
                            completion: completion
                        )
                    case .failure:
                        DispatchQueue.main.async {
                            NotificationCenter.default.post(name: Notification.Name("DriverTokenExpired"), object: nil)
                            completion(.failure(P2PAPIError.serverError("Session expired - please log in again")))
                        }
                    }
                }
                return
            }

            DispatchQueue.main.async {
                guard let data = data else {
                    completion(.failure(P2PAPIError.noData))
                    return
                }

                do {
                    let response = try JSONDecoder().decode(RideBidResponse.self, from: data)
                    completion(.success(response))
                } catch {
                    if let errorResponse = try? JSONDecoder().decode(P2PErrorResponse.self, from: data) {
                        completion(.failure(P2PAPIError.serverError(errorResponse.detail)))
                    } else {
                        completion(.failure(error))
                    }
                }
            }
        }.resume()
    }

    /// Get driver's bids
    public func fetchDriverBids(
        status: String? = nil,
        completion: @escaping (Result<[RideBid], Error>) -> Void
    ) {
        guard let driverId = currentDriverId else {
            completion(.failure(P2PAPIError.serverError("Driver not logged in")))
            return
        }

        var urlComponents = URLComponents(string: "\(baseURL)/rides/driver/\(driverId)/bids")
        var queryItems: [URLQueryItem] = [URLQueryItem(name: "days", value: "1")]
        if let status = status {
            queryItems.append(URLQueryItem(name: "status", value: status))
        }
        urlComponents?.queryItems = queryItems

        guard let url = urlComponents?.url else {
            completion(.failure(P2PAPIError.invalidURL))
            return
        }

        var request = URLRequest(url: url)
        if let token = driverToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        secureSession.dataTask(with: request) { data, response, error in
            DispatchQueue.main.async {
                if let error = error {
                    completion(.failure(error))
                    return
                }

                guard let data = data else {
                    completion(.failure(P2PAPIError.noData))
                    return
                }

                // Surface server errors instead of an empty list — a swallowed 5xx/401 here would
                // silently drop the driver's active ride, accepted-ride nav, and counter-offers.
                if let http = response as? HTTPURLResponse, http.statusCode >= 400 {
                    completion(.failure(P2PAPIError.serverError("Unable to load your bids (\(http.statusCode))")))
                    return
                }

                do {
                    let response = try JSONDecoder().decode(DriverBidsResponse.self, from: data)
                    completion(.success(response.bids))
                } catch {
                    #if DEBUG
                    logger.error("fetchDriverBids decode error: \(error)")
                    #endif
                    completion(.failure(error))
                }
            }
        }.resume()
    }

    /// Withdraw a bid
    public func withdrawBid(
        bidId: Int,
        completion: @escaping (Result<Bool, Error>) -> Void
    ) {
        guard let url = URL(string: "\(baseURL)/rides/bid/\(bidId)/withdraw") else {
            completion(.failure(P2PAPIError.invalidURL))
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"

        if let token = driverToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        secureSession.dataTask(with: request) { data, response, error in
            DispatchQueue.main.async {
                if let error = error {
                    completion(.failure(error))
                    return
                }

                if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 {
                    completion(.success(true))
                } else {
                    completion(.failure(P2PAPIError.serverError("Failed to withdraw bid")))
                }
            }
        }.resume()
    }

    // MARK: - Customer P2P Bid Methods (for viewing and accepting driver bids)

    /// Fetch incoming driver bids for a ride request (Customer API)
    public func fetchRideRequestBids(
        requestId: Int,
        completion: @escaping (Result<CustomerRideBidsResponse, Error>) -> Void
    ) {
        guard let url = URL(string: "\(baseURL)/rides/request/\(requestId)/bids") else {
            completion(.failure(P2PAPIError.invalidURL))
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"

        if let token = customerToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        secureSession.dataTask(with: request) { data, response, error in
            DispatchQueue.main.async {
                if let error = error {
                    logger.error("fetchRideRequestBids network error: \(error)")
                    completion(.failure(error))
                    return
                }

                guard let data = data else {
                    completion(.failure(P2PAPIError.serverError("No data received")))
                    return
                }

                do {
                    let response = try JSONDecoder().decode(CustomerRideBidsResponse.self, from: data)
                    completion(.success(response))
                } catch {
                    logger.error("fetchRideRequestBids decode error: \(error)")
                    // Return empty response on decode error
                    let emptyResponse = CustomerRideBidsResponse(
                        request_id: requestId,
                        bids: [],
                        total_bids: 0,
                        bidding_open: true,
                        bidding_ends_at: nil
                    )
                    completion(.success(emptyResponse))
                }
            }
        }.resume()
    }

    /// Accept a driver's bid (Customer API)
    public func acceptDriverBid(
        bidId: Int,
        completion: @escaping (Result<AcceptedRideDetails, Error>) -> Void
    ) {
        guard let url = URL(string: "\(baseURL)/rides/bid/\(bidId)/respond") else {
            completion(.failure(P2PAPIError.invalidURL))
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        if let token = customerToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        let body: [String: Any] = ["action": "accept"]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        secureSession.dataTask(with: request) { data, response, error in
            DispatchQueue.main.async {
                if let error = error {
                    logger.error("acceptDriverBid network error: \(error)")
                    completion(.failure(error))
                    return
                }

                guard let data = data else {
                    completion(.failure(P2PAPIError.serverError("No data received")))
                    return
                }

                do {
                    let response = try JSONDecoder().decode(AcceptedRideDetails.self, from: data)
                    completion(.success(response))
                } catch {
                    logger.error("acceptDriverBid decode error: \(error)")
                    // Try to parse basic success response
                    if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                       let success = json["success"] as? Bool, success {
                        let basicResponse = AcceptedRideDetails(
                            success: true,
                            message: json["message"] as? String ?? "Bid accepted",
                            ride_id: nil,
                            driver: nil,
                            pickup: nil,
                            dropoff: nil,
                            estimated_arrival_minutes: nil,
                            fare: nil,
                            status: "accepted"
                        )
                        completion(.success(basicResponse))
                    } else {
                        completion(.failure(error))
                    }
                }
            }
        }.resume()
    }

    /// Reject a driver's bid (Customer API)
    public func rejectDriverBid(
        bidId: Int,
        completion: @escaping (Result<Bool, Error>) -> Void
    ) {
        guard let url = URL(string: "\(baseURL)/rides/bid/\(bidId)/respond") else {
            completion(.failure(P2PAPIError.invalidURL))
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        if let token = customerToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        let body: [String: Any] = ["action": "reject"]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        secureSession.dataTask(with: request) { data, response, error in
            DispatchQueue.main.async {
                if let error = error {
                    completion(.failure(error))
                    return
                }

                if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 {
                    completion(.success(true))
                } else {
                    completion(.failure(P2PAPIError.serverError("Failed to reject bid")))
                }
            }
        }.resume()
    }

    /// Counter a driver's bid with a new price (Customer API)
    /// Uses /rides/bid/{id}/respond with action="counter"
    public func counterDriverBid(
        bidId: Int,
        counterPrice: Double,
        message: String? = nil,
        completion: @escaping (Result<CounterBidResponse, Error>) -> Void
    ) {
        guard let url = URL(string: "\(baseURL)/rides/bid/\(bidId)/respond") else {
            completion(.failure(P2PAPIError.invalidURL))
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        if let token = customerToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        var body: [String: Any] = [
            "action": "counter",
            "counter_price": counterPrice
        ]
        if let msg = message {
            body["message"] = msg
        }
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        secureSession.dataTask(with: request) { data, response, error in
            DispatchQueue.main.async {
                if let error = error {
                    logger.error("counterDriverBid network error: \(error)")
                    completion(.failure(error))
                    return
                }

                guard let data = data else {
                    completion(.failure(P2PAPIError.serverError("No data received")))
                    return
                }

                // Check for error response first
                if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let detail = json["detail"] as? String {
                    completion(.failure(P2PAPIError.serverError(detail)))
                    return
                }

                do {
                    let response = try JSONDecoder().decode(CounterBidResponse.self, from: data)
                    completion(.success(response))
                } catch {
                    logger.error("counterDriverBid decode error: \(error)")
                    completion(.failure(error))
                }
            }
        }.resume()
    }

    /// Driver submits counter-offer to customer (Driver API)
    /// Uses /rides/bid/{id}/driver-counter
    public func driverSubmitCounter(
        bidId: Int,
        counterPrice: Double,
        message: String? = nil,
        completion: @escaping (Result<DriverCounterResponse, Error>) -> Void
    ) {
        guard let url = URL(string: "\(baseURL)/rides/bid/\(bidId)/driver-counter") else {
            completion(.failure(P2PAPIError.invalidURL))
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        if let token = driverToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        var body: [String: Any] = ["counter_price": counterPrice]
        if let msg = message {
            body["message"] = msg
        }
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        secureSession.dataTask(with: request) { data, response, error in
            DispatchQueue.main.async {
                if let error = error {
                    logger.error("driverSubmitCounter network error: \(error)")
                    completion(.failure(error))
                    return
                }

                guard let data = data else {
                    completion(.failure(P2PAPIError.serverError("No data received")))
                    return
                }

                // Check for error response first
                if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let detail = json["detail"] as? String {
                    completion(.failure(P2PAPIError.serverError(detail)))
                    return
                }

                do {
                    let response = try JSONDecoder().decode(DriverCounterResponse.self, from: data)
                    completion(.success(response))
                } catch {
                    logger.error("driverSubmitCounter decode error: \(error)")
                    completion(.failure(error))
                }
            }
        }.resume()
    }

    /// Accept customer's counter-offer
    public func acceptCounterOffer(
        bidId: Int,
        completion: @escaping (Result<RideBidResponse, Error>) -> Void
    ) {
        guard let url = URL(string: "\(baseURL)/rides/bid/\(bidId)/accept-counter") else {
            completion(.failure(P2PAPIError.invalidURL))
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"

        if let token = driverToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        secureSession.dataTask(with: request) { data, response, error in
            DispatchQueue.main.async {
                if let error = error {
                    completion(.failure(error))
                    return
                }

                guard let data = data else {
                    completion(.failure(P2PAPIError.noData))
                    return
                }

                // Surface the real reason (e.g. "offer expired" / "already matched") instead of
                // a generic decode error when the server returns a 4xx/5xx { "detail": ... }.
                if let http = response as? HTTPURLResponse, http.statusCode >= 400 {
                    if let err = try? JSONDecoder().decode(P2PErrorResponse.self, from: data) {
                        completion(.failure(P2PAPIError.serverError(err.detail)))
                    } else {
                        completion(.failure(P2PAPIError.serverError("Unable to accept the counter-offer (\(http.statusCode))")))
                    }
                    return
                }

                do {
                    let response = try JSONDecoder().decode(RideBidResponse.self, from: data)
                    completion(.success(response))
                } catch {
                    completion(.failure(error))
                }
            }
        }.resume()
    }

    /// Reject customer's counter-offer
    public func rejectCounterOffer(
        bidId: Int,
        completion: @escaping (Result<Bool, Error>) -> Void
    ) {
        guard let url = URL(string: "\(baseURL)/rides/bid/\(bidId)/reject-counter") else {
            completion(.failure(P2PAPIError.invalidURL))
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"

        if let token = driverToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        secureSession.dataTask(with: request) { data, response, error in
            DispatchQueue.main.async {
                if let error = error {
                    completion(.failure(error))
                    return
                }

                if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 {
                    completion(.success(true))
                } else {
                    completion(.failure(P2PAPIError.serverError("Failed to reject counter-offer")))
                }
            }
        }.resume()
    }

    /// Respond to customer's counter-offer (accept, reject, or counter)
    public func respondToCounterOffer(
        bidId: Int,
        action: String,  // "accept", "reject", or "counter"
        counterPrice: Double?,
        completion: @escaping (Result<RideBidResponse, Error>) -> Void
    ) {
        guard let url = URL(string: "\(baseURL)/rides/bid/\(bidId)/respond") else {
            completion(.failure(P2PAPIError.invalidURL))
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        if let token = driverToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        var body: [String: Any] = ["action": action]
        if let price = counterPrice {
            body["counter_price"] = price
        }

        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        secureSession.dataTask(with: request) { data, response, error in
            DispatchQueue.main.async {
                if let error = error {
                    completion(.failure(error))
                    return
                }

                guard let data = data else {
                    completion(.failure(P2PAPIError.noData))
                    return
                }

                do {
                    let response = try JSONDecoder().decode(RideBidResponse.self, from: data)
                    completion(.success(response))
                } catch {
                    completion(.failure(error))
                }
            }
        }.resume()
    }

    /// Mark driver arrived at pickup location
    public func driverArrivedAtPickup(
        rideRequestId: Int,
        completion: @escaping (Result<Bool, Error>) -> Void
    ) {
        guard let url = URL(string: "\(baseURL)/rides/request/\(rideRequestId)/arrived") else {
            completion(.failure(P2PAPIError.invalidURL))
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"

        if let token = driverToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        secureSession.dataTask(with: request) { data, response, error in
            DispatchQueue.main.async {
                if let error = error {
                    completion(.failure(error))
                    return
                }

                if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 {
                    completion(.success(true))
                } else {
                    completion(.failure(P2PAPIError.serverError("Failed to mark driver arrived")))
                }
            }
        }.resume()
    }

    /// Start a ride (driver picked up passenger)
    public func startRide(
        rideRequestId: Int,
        completion: @escaping (Result<Bool, Error>) -> Void
    ) {
        guard let url = URL(string: "\(baseURL)/rides/request/\(rideRequestId)/start") else {
            completion(.failure(P2PAPIError.invalidURL))
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"

        if let token = driverToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        secureSession.dataTask(with: request) { data, response, error in
            DispatchQueue.main.async {
                if let error = error {
                    completion(.failure(error))
                    return
                }

                if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 {
                    completion(.success(true))
                } else {
                    completion(.failure(P2PAPIError.serverError("Failed to start ride")))
                }
            }
        }.resume()
    }

    /// Complete a ride (driver dropped off passenger)
    public func completeRideRequest(
        rideRequestId: Int,
        completion: @escaping (Result<RideCompletionResponse, Error>) -> Void
    ) {
        guard let url = URL(string: "\(baseURL)/rides/request/\(rideRequestId)/complete") else {
            completion(.failure(P2PAPIError.invalidURL))
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"

        if let token = driverToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        secureSession.dataTask(with: request) { data, response, error in
            DispatchQueue.main.async {
                if let error = error {
                    completion(.failure(error))
                    return
                }

                guard let data = data else {
                    completion(.failure(P2PAPIError.noData))
                    return
                }

                if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 {
                    do {
                        let decoded = try JSONDecoder().decode(RideCompletionResponse.self, from: data)
                        completion(.success(decoded))
                    } catch {
                        // Fallback if decoding fails — still treat as success
                        let fallback = RideCompletionResponse(success: true, message: "Ride completed", ride_request: nil, final_price: nil)
                        completion(.success(fallback))
                    }
                } else {
                    completion(.failure(P2PAPIError.serverError("Failed to complete ride")))
                }
            }
        }.resume()
    }

    // MARK: - Cancel Ride Request (Customer)

    /// Cancel a ride request (customer only)
    public func cancelRideRequest(
        rideRequestId: Int,
        reason: String? = nil,
        completion: @escaping (Result<Bool, Error>) -> Void
    ) {
        guard let url = URL(string: "\(baseURL)/rides/request/\(rideRequestId)/cancel") else {
            completion(.failure(P2PAPIError.invalidURL))
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        if let token = customerToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        if let reason = reason {
            let body: [String: Any] = ["reason": reason]
            request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        }

        secureSession.dataTask(with: request) { data, response, error in
            DispatchQueue.main.async {
                if let error = error {
                    completion(.failure(error))
                    return
                }

                if let httpResponse = response as? HTTPURLResponse,
                   (200...299).contains(httpResponse.statusCode) {
                    completion(.success(true))
                } else {
                    completion(.failure(P2PAPIError.serverError("Failed to cancel ride")))
                }
            }
        }.resume()
    }

    // MARK: - Driver Cancel Ride

    /// Driver cancels a matched ride before starting it
    /// Calls POST /api/rides/request/{id}/driver-cancel
    public func driverCancelRide(
        rideRequestId: Int,
        reason: String?,
        completion: @escaping (Result<Bool, Error>) -> Void
    ) {
        guard let url = URL(string: "\(baseURL)/rides/request/\(rideRequestId)/driver-cancel") else {
            completion(.failure(P2PAPIError.invalidURL))
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        if let token = driverToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        var body: [String: Any] = [:]
        if let reason = reason {
            body["reason"] = reason
        }
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        secureSession.dataTask(with: request) { data, response, error in
            DispatchQueue.main.async {
                if let error = error {
                    completion(.failure(error))
                    return
                }

                if let httpResponse = response as? HTTPURLResponse,
                   (200...299).contains(httpResponse.statusCode) {
                    completion(.success(true))
                } else {
                    completion(.failure(P2PAPIError.serverError("Failed to cancel ride")))
                }
            }
        }.resume()
    }

    // MARK: - TNC Compliance

    /// Report a safety concern (zero-tolerance) for a driver
    /// Calls POST /api/tnc/zero-tolerance/report
    public func reportSafetyConcern(
        driverId: Int,
        rideRequestId: Int?,
        description: String,
        completion: @escaping (Bool) -> Void
    ) {
        guard let url = URL(string: "\(baseURL)/tnc/zero-tolerance/report") else {
            completion(false)
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        if let token = customerToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        var body: [String: Any] = [
            "driver_id": driverId,
            "description": description,
            "reporter_type": "customer"
        ]
        if let rideId = rideRequestId {
            body["ride_request_id"] = rideId
        }
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        secureSession.dataTask(with: request) { data, _, _ in
            DispatchQueue.main.async {
                guard let data = data,
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      json["success"] as? Bool == true else {
                    completion(false)
                    return
                }
                completion(true)
            }
        }.resume()
    }

    /// Get ride waybill (TNC-15)
    /// Calls GET /api/rides/request/{id}/waybill
    public func getRideWaybill(
        rideRequestId: Int,
        completion: @escaping ([String: Any]?) -> Void
    ) {
        guard let url = URL(string: "\(baseURL)/rides/request/\(rideRequestId)/waybill") else {
            completion(nil)
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"

        if let token = driverToken ?? customerToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        secureSession.dataTask(with: request) { data, _, _ in
            DispatchQueue.main.async {
                guard let data = data,
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let waybill = json["waybill"] as? [String: Any] else {
                    completion(nil)
                    return
                }
                completion(waybill)
            }
        }.resume()
    }

    /// Initiate an in-app Checkr background check for the signed-in driver.
    /// Calls POST /api/checkr/background-check/initiate
    /// Returns the Checkr-hosted `invitation_url` the driver opens to complete the check.
    public func initiateBackgroundCheck(
        completion: @escaping (Result<CheckrInvitation, Error>) -> Void
    ) {
        guard let token = driverToken else {
            completion(.failure(P2PAPIError.serverError("Driver not logged in")))
            return
        }

        guard let url = URL(string: "\(baseURL)/checkr/background-check/initiate") else {
            completion(.failure(P2PAPIError.invalidURL))
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.httpBody = try? JSONSerialization.data(withJSONObject: [:])

        secureSession.dataTask(with: request) { data, response, error in
            DispatchQueue.main.async {
                if let error = error {
                    completion(.failure(error))
                    return
                }

                guard let data = data else {
                    completion(.failure(P2PAPIError.noData))
                    return
                }

                let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
                if statusCode >= 400 {
                    if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                       let detail = json["detail"] as? String {
                        completion(.failure(P2PAPIError.serverError(detail)))
                    } else {
                        completion(.failure(P2PAPIError.serverError("HTTP \(statusCode)")))
                    }
                    return
                }

                do {
                    let invitation = try JSONDecoder().decode(CheckrInvitation.self, from: data)
                    completion(.success(invitation))
                } catch {
                    completion(.failure(error))
                }
            }
        }.resume()
    }

    /// Get background check status (TNC-07 / Checkr)
    /// Calls GET /api/checkr/background-check/{driver_id}/status
    public func getBackgroundCheckStatus(
        driverId: Int,
        completion: @escaping ([String: Any]?) -> Void
    ) {
        guard let url = URL(string: "\(baseURL)/checkr/background-check/\(driverId)/status") else {
            completion(nil)
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"

        if let token = driverToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        secureSession.dataTask(with: request) { data, _, _ in
            DispatchQueue.main.async {
                guard let data = data,
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                    completion(nil)
                    return
                }
                completion(json)
            }
        }.resume()
    }

    /// Get vehicle inspection status (TNC-09)
    /// Calls GET /api/tnc/vehicle-inspection/{driver_id}/status
    public func getVehicleInspectionStatus(
        driverId: Int,
        completion: @escaping ([String: Any]?) -> Void
    ) {
        guard let url = URL(string: "\(baseURL)/tnc/vehicle-inspection/\(driverId)/status") else {
            completion(nil)
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"

        if let token = driverToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        secureSession.dataTask(with: request) { data, _, _ in
            DispatchQueue.main.async {
                guard let data = data,
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                    completion(nil)
                    return
                }
                completion(json)
            }
        }.resume()
    }

    /// Submit vehicle inspection (TNC-09)
    /// Calls POST /api/tnc/vehicle-inspection/submit
    public func submitVehicleInspection(
        driverId: Int,
        inspectionDate: String,
        facilityName: String,
        barLicense: String?,
        mileage: Int?,
        documentUrl: String,
        completion: @escaping (Bool) -> Void
    ) {
        guard let url = URL(string: "\(baseURL)/tnc/vehicle-inspection/submit") else {
            completion(false)
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        if let token = driverToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        var body: [String: Any] = [
            "driver_id": driverId,
            "inspection_date": inspectionDate,
            "facility_name": facilityName,
            "document_url": documentUrl
        ]
        if let bar = barLicense { body["facility_bar_license"] = bar }
        if let m = mileage { body["mileage_at_inspection"] = m }
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        secureSession.dataTask(with: request) { data, _, _ in
            DispatchQueue.main.async {
                guard let data = data,
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      json["success"] as? Bool == true else {
                    completion(false)
                    return
                }
                completion(true)
            }
        }.resume()
    }

    /// Get driver accessibility settings
    /// Calls GET /api/tnc/driver/accessibility
    public func getDriverAccessibility(
        completion: @escaping ([String: Any]?) -> Void
    ) {
        guard let url = URL(string: "\(baseURL)/tnc/driver/accessibility") else {
            completion(nil)
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"

        if let token = driverToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        secureSession.dataTask(with: request) { data, _, _ in
            DispatchQueue.main.async {
                guard let data = data,
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                    completion(nil)
                    return
                }
                completion(json)
            }
        }.resume()
    }

    /// Update driver accessibility settings
    /// Calls PATCH /api/tnc/driver/accessibility
    public func updateDriverAccessibility(
        capable: Bool,
        features: [String: Bool],
        completion: @escaping (Bool) -> Void
    ) {
        guard let url = URL(string: "\(baseURL)/tnc/driver/accessibility") else {
            completion(false)
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "PATCH"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        if let token = driverToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        let body: [String: Any] = [
            "accessibility_capable": capable,
            "accessibility_features": features
        ]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        secureSession.dataTask(with: request) { data, _, _ in
            DispatchQueue.main.async {
                guard let data = data,
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      json["success"] as? Bool == true else {
                    completion(false)
                    return
                }
                completion(true)
            }
        }.resume()
    }

    // MARK: - No-Show

    /// Driver marks passenger as no-show after waiting at pickup
    /// Calls POST /api/rides/request/{id}/no-show
    public func markPassengerNoShow(
        rideRequestId: Int,
        completion: @escaping (Result<NoShowResponse, Error>) -> Void
    ) {
        guard let url = URL(string: "\(baseURL)/rides/request/\(rideRequestId)/no-show") else {
            completion(.failure(P2PAPIError.invalidURL))
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"

        if let token = driverToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        secureSession.dataTask(with: request) { data, response, error in
            DispatchQueue.main.async {
                if let error = error {
                    completion(.failure(error))
                    return
                }

                guard let data = data else {
                    completion(.failure(P2PAPIError.noData))
                    return
                }

                if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 {
                    do {
                        let decoded = try JSONDecoder().decode(NoShowResponse.self, from: data)
                        completion(.success(decoded))
                    } catch {
                        completion(.failure(error))
                    }
                } else {
                    // Try to parse error detail
                    if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                       let detail = json["detail"] as? String {
                        completion(.failure(P2PAPIError.serverError(detail)))
                    } else {
                        completion(.failure(P2PAPIError.serverError("Failed to mark no-show")))
                    }
                }
            }
        }.resume()
    }

    // MARK: - Surge Status

    /// Get current surge/demand pricing status
    public func getSurgeStatus(
        completion: @escaping (Result<SurgeStatusResponse, Error>) -> Void
    ) {
        guard let url = URL(string: "\(baseURL)/rides/surge") else {
            completion(.failure(P2PAPIError.invalidURL))
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"

        secureSession.dataTask(with: request) { data, response, error in
            DispatchQueue.main.async {
                if let error = error {
                    completion(.failure(error))
                    return
                }

                guard let data = data else {
                    completion(.failure(P2PAPIError.noData))
                    return
                }

                do {
                    let decoded = try JSONDecoder().decode(SurgeStatusResponse.self, from: data)
                    completion(.success(decoded))
                } catch {
                    completion(.failure(error))
                }
            }
        }.resume()
    }

    // MARK: - Rate Passenger

    /// Driver rates passenger after ride completion
    public func ratePassenger(
        rideRequestId: Int,
        rating: Int,
        comment: String? = nil,
        completion: @escaping (Result<Bool, Error>) -> Void
    ) {
        guard let url = URL(string: "\(baseURL)/rides/request/\(rideRequestId)/rate-passenger") else {
            completion(.failure(P2PAPIError.invalidURL))
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        if let token = driverToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        var body: [String: Any] = ["rating": rating]
        if let comment = comment, !comment.isEmpty {
            body["comment"] = comment
        }

        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        secureSession.dataTask(with: request) { data, response, error in
            DispatchQueue.main.async {
                if let error = error {
                    completion(.failure(error))
                    return
                }

                if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 {
                    completion(.success(true))
                } else if let data = data,
                          let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                          let detail = json["detail"] as? String {
                    completion(.failure(P2PAPIError.serverError(detail)))
                } else {
                    completion(.failure(P2PAPIError.serverError("Failed to rate passenger")))
                }
            }
        }.resume()
    }

    // MARK: - Customer Ride History

    /// Fetch customer's ride request history
    public func getCustomerRideRequests(
        customerId: Int,
        status: String? = nil,
        limit: Int = 20,
        offset: Int = 0,
        completion: @escaping (Result<[RideRequestForBidding], Error>) -> Void
    ) {
        var urlComponents = URLComponents(string: "\(baseURL)/rides/customer/\(customerId)/requests")
        var queryItems: [URLQueryItem] = [
            URLQueryItem(name: "limit", value: String(limit)),
            URLQueryItem(name: "offset", value: String(offset))
        ]
        if let status = status {
            queryItems.append(URLQueryItem(name: "status", value: status))
        }
        urlComponents?.queryItems = queryItems

        guard let url = urlComponents?.url else {
            completion(.failure(P2PAPIError.invalidURL))
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"

        if let token = customerToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        secureSession.dataTask(with: request) { data, response, error in
            DispatchQueue.main.async {
                if let error = error {
                    completion(.failure(error))
                    return
                }

                guard let data = data else {
                    completion(.failure(P2PAPIError.noData))
                    return
                }

                do {
                    let decoded = try JSONDecoder().decode(CustomerRideRequestsResponse.self, from: data)
                    completion(.success(decoded.requests))
                } catch {
                    completion(.failure(error))
                }
            }
        }.resume()
    }

    // MARK: - Ride History (Customer)

    /// Get customer's ride history with pagination
    /// Calls GET /api/customer/rides/history (authenticated via customer token)
    public func getCustomerRideHistory(
        limit: Int = 20,
        offset: Int = 0,
        completion: @escaping (Result<RideHistoryResponse, Error>) -> Void
    ) {
        var urlComponents = URLComponents(string: "\(baseURL)/customer/rides/history")
        urlComponents?.queryItems = [
            URLQueryItem(name: "limit", value: String(limit)),
            URLQueryItem(name: "offset", value: String(offset))
        ]

        guard let url = urlComponents?.url else {
            completion(.failure(P2PAPIError.invalidURL))
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"

        if let token = customerToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        secureSession.dataTask(with: request) { data, response, error in
            DispatchQueue.main.async {
                if let error = error {
                    completion(.failure(error))
                    return
                }

                guard let data = data else {
                    completion(.failure(P2PAPIError.noData))
                    return
                }

                do {
                    let decoded = try JSONDecoder().decode(RideHistoryResponse.self, from: data)
                    completion(.success(decoded))
                } catch {
                    completion(.failure(error))
                }
            }
        }.resume()
    }

    /// Lightweight session validity check for the customer.
    /// Returns `false` ONLY when the server rejects the token (HTTP 401/403), so a stale/expired
    /// session can be dropped to the login screen. On network errors or other statuses it returns
    /// `true` so a transient blip never signs the user out.
    public func validateCustomerSession(completion: @escaping (Bool) -> Void) {
        guard let token = customerToken else {
            DispatchQueue.main.async { completion(false) }
            return
        }
        guard let url = URL(string: "\(baseURL)/customer/rides/history?limit=1&offset=0") else {
            DispatchQueue.main.async { completion(true) }
            return
        }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        secureSession.dataTask(with: request) { _, response, _ in
            DispatchQueue.main.async {
                if let http = response as? HTTPURLResponse, http.statusCode == 401 || http.statusCode == 403 {
                    completion(false) // token rejected by server
                } else {
                    completion(true)  // valid, or a transient error we won't sign out over
                }
            }
        }.resume()
    }

    // MARK: - Update Bid (Driver)

    /// Update an existing pending bid (driver only)
    public func updateBid(
        bidId: Int,
        proposedPrice: Double,
        message: String? = nil,
        completion: @escaping (Result<RideBidResponse, Error>) -> Void
    ) {
        guard let url = URL(string: "\(baseURL)/rides/bid/\(bidId)") else {
            completion(.failure(P2PAPIError.invalidURL))
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        if let token = driverToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        var body: [String: Any] = ["proposed_price": proposedPrice]
        if let message = message {
            body["message"] = message
        }

        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        secureSession.dataTask(with: request) { data, response, error in
            DispatchQueue.main.async {
                if let error = error {
                    completion(.failure(error))
                    return
                }

                guard let data = data else {
                    completion(.failure(P2PAPIError.noData))
                    return
                }

                do {
                    let decoded = try JSONDecoder().decode(RideBidResponse.self, from: data)
                    completion(.success(decoded))
                } catch {
                    completion(.failure(error))
                }
            }
        }.resume()
    }

    // MARK: - Fare Negotiation APIs (Rideshare Only - $1+$1 Model)

    /// Submit a fare counter-offer (driver or customer)
    public func submitFareNegotiation(
        rideId: Int,
        proposedFare: Double,
        isDriverOffer: Bool,
        completion: @escaping (Result<FareNegotiationResponse, Error>) -> Void
    ) {
        guard let url = URL(string: "\(baseURL)/erp/rides/\(rideId)/negotiate") else {
            completion(.failure(P2PAPIError.invalidURL))
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        // Add driver auth token for negotiation
        if let token = driverToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        let body: [String: Any] = [
            "proposed_fare": proposedFare,
            "is_driver_offer": isDriverOffer,
            "platform_fee_driver": 1.0,  // $1 to driver
            "platform_fee_customer": 1.0  // $1 to customer = $2 total platform fee
        ]

        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        secureSession.dataTask(with: request) { data, response, error in
            if let error = error {
                completion(.failure(error))
                return
            }

            guard let data = data else {
                completion(.failure(P2PAPIError.noData))
                return
            }

            DispatchQueue.main.async {
                do {
                    let response = try JSONDecoder().decode(FareNegotiationResponse.self, from: data)
                    completion(.success(response))
                } catch {
                    completion(.failure(error))
                }
            }
        }.resume()
    }

    /// Accept a negotiated fare
    public func acceptFareNegotiation(
        rideId: Int,
        acceptedFare: Double,
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        guard let url = URL(string: "\(baseURL)/erp/rides/\(rideId)/accept-fare") else {
            completion(.failure(P2PAPIError.invalidURL))
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        // Add driver auth token for accepting fare
        if let token = driverToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        let body: [String: Any] = [
            "accepted_fare": acceptedFare,
            "platform_fee_driver": 1.0,
            "platform_fee_customer": 1.0
        ]

        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        secureSession.dataTask(with: request) { data, response, error in
            if let error = error {
                completion(.failure(error))
                return
            }

            if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 {
                completion(.success(()))
            } else {
                completion(.failure(P2PAPIError.serverError("Failed to accept fare")))
            }
        }.resume()
    }

    // MARK: - Stripe Payment APIs (Rideshare)

    /// Create Stripe PaymentIntent for ride payment
    /// Uses tiered platform fee model:
    /// - Tier 1 (fare <= $35): $1 fee
    /// - Tier 2 ($35 < fare <= $70): $2 fee
    /// - Tier 3 (fare > $70): $3 fee
    public func createRidePaymentIntent(
        rideId: Int,
        amount: Double,
        currency: String = "usd",
        completion: @escaping (Result<StripePaymentIntentResponse, Error>) -> Void
    ) {
        // Correct backend endpoint: /api/payments/ride/create-intent
        // Takes ride_request_id in request body
        guard let url = URL(string: "\(baseURL)/payments/ride/create-intent") else {
            completion(.failure(P2PAPIError.invalidURL))
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        // Add customer auth token
        if let token = customerToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        // Backend expects ride_request_id in body
        let body: [String: Any] = ["ride_request_id": rideId]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        secureSession.dataTask(with: request) { data, response, error in
            if let error = error {
                completion(.failure(error))
                return
            }

            guard let data = data else {
                completion(.failure(P2PAPIError.noData))
                return
            }

            DispatchQueue.main.async {
                do {
                    let response = try JSONDecoder().decode(StripePaymentIntentResponse.self, from: data)
                    completion(.success(response))
                } catch {
                    completion(.failure(error))
                }
            }
        }.resume()
    }

    /// Confirm Stripe payment for ride
    /// Note: Payment is automatically confirmed via Stripe webhooks.
    /// This function polls the ride status to verify payment was processed.
    public func confirmRidePayment(
        rideId: Int,
        paymentIntentId: String,
        completion: @escaping (Result<RidePaymentConfirmation, Error>) -> Void
    ) {
        // Poll ride status to verify payment was processed
        // Stripe webhooks handle the actual payment confirmation on the backend
        guard let url = URL(string: "\(baseURL)/erp/rides/\(rideId)/status") else {
            completion(.failure(P2PAPIError.invalidURL))
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        // Add customer auth token
        if let token = customerToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        secureSession.dataTask(with: request) { data, response, error in
            if let error = error {
                completion(.failure(error))
                return
            }

            guard let data = data else {
                completion(.failure(P2PAPIError.noData))
                return
            }

            DispatchQueue.main.async {
                // Parse ride status response and create confirmation
                if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let status = json["status"] as? String {
                    // Check if payment was processed (status updated by webhook)
                    let isPaid = status == "matched" || status == "in_progress" || status == "completed"
                    let confirmation = RidePaymentConfirmation(
                        success: isPaid,
                        message: isPaid ? "Payment confirmed successfully" : "Payment pending",
                        rideId: rideId,
                        paymentStatus: isPaid ? "paid" : "pending"
                    )
                    completion(.success(confirmation))
                } else {
                    // Fallback - assume success if status endpoint returned data
                    let confirmation = RidePaymentConfirmation(
                        success: true,
                        message: "Payment processed",
                        rideId: rideId,
                        paymentStatus: "processed"
                    )
                    completion(.success(confirmation))
                }
            }
        }.resume()
    }

    // MARK: - Stripe Customer Card Management APIs

    /// Fetch saved cards for a customer from Stripe
    public func fetchSavedCards(
        customerId: Int,
        completion: @escaping (Result<[StripeCard], Error>) -> Void
    ) {
        guard let url = URL(string: "\(baseURL)/customers/\(customerId)/cards") else {
            completion(.failure(P2PAPIError.invalidURL))
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"

        if let token = customerToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        secureSession.dataTask(with: request) { data, response, error in
            if let error = error {
                DispatchQueue.main.async { completion(.failure(error)) }
                return
            }

            guard let data = data else {
                DispatchQueue.main.async { completion(.failure(P2PAPIError.noData)) }
                return
            }

            DispatchQueue.main.async {
                do {
                    let response = try JSONDecoder().decode(StripeCardsResponse.self, from: data)
                    completion(.success(response.cards))
                } catch {
                    // If decoding fails, return empty array (new customer)
                    completion(.success([]))
                }
            }
        }.resume()
    }

    /// Create/save a card for customer via Stripe
    /// Attach an already-tokenized Stripe payment method to a customer.
    /// SECURITY: `paymentMethodId` must come from Stripe's SDK tokenizing the card
    /// on-device (e.g. STPAPIClient.createPaymentMethod) — raw card number/CVC must
    /// never be sent here or to any of our own backend endpoints (PCI scope).
    public func attachPaymentMethod(
        customerId: Int,
        paymentMethodId: String,
        completion: @escaping (Result<StripeCard, Error>) -> Void
    ) {
        guard let url = URL(string: "\(baseURL)/customers/\(customerId)/cards") else {
            completion(.failure(P2PAPIError.invalidURL))
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        if let token = customerToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        let body: [String: Any] = ["payment_method_id": paymentMethodId]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        secureSession.dataTask(with: request) { data, response, error in
            if let error = error {
                DispatchQueue.main.async { completion(.failure(error)) }
                return
            }

            guard let data = data else {
                DispatchQueue.main.async { completion(.failure(P2PAPIError.noData)) }
                return
            }

            if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode >= 400 {
                let detail = (try? JSONDecoder().decode(APIErrorResponse.self, from: data))?.detail
                DispatchQueue.main.async {
                    completion(.failure(P2PAPIError.serverError(detail ?? "Card could not be saved")))
                }
                return
            }

            // Response is {"success": true, "card": {id, brand, last4, exp_month, exp_year}, "message": ...}
            // — "card" has no "is_default" field, so decode the nested object manually
            // rather than via StripeCard's Codable conformance (which requires it).
            struct AddCardResponse: Decodable {
                struct Card: Decodable {
                    let id: String
                    let brand: String
                    let last4: String
                    let exp_month: Int
                    let exp_year: Int
                }
                let card: Card
            }

            DispatchQueue.main.async {
                do {
                    let decoded = try JSONDecoder().decode(AddCardResponse.self, from: data)
                    let card = StripeCard(
                        id: decoded.card.id,
                        last4: decoded.card.last4,
                        brand: StripeCard.CardBrand(rawValue: decoded.card.brand) ?? .unknown,
                        expiryMonth: decoded.card.exp_month,
                        expiryYear: decoded.card.exp_year,
                        isDefault: false
                    )
                    completion(.success(card))
                } catch {
                    completion(.failure(error))
                }
            }
        }.resume()
    }

    /// Create a Stripe SetupIntent so the client can save a payment method without
    /// charging anything yet. Needed for Apple Pay, which confirms a PaymentIntent/
    /// SetupIntent via STPApplePayContext rather than producing a token that can be
    /// handed to attachPaymentMethod directly.
    public func createSetupIntent(
        customerId: Int,
        completion: @escaping (Result<(clientSecret: String, publishableKey: String), Error>) -> Void
    ) {
        guard let url = URL(string: "\(baseURL)/customers/\(customerId)/stripe/setup-intent") else {
            completion(.failure(P2PAPIError.invalidURL))
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        if let token = customerToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        secureSession.dataTask(with: request) { data, response, error in
            if let error = error {
                DispatchQueue.main.async { completion(.failure(error)) }
                return
            }
            guard let data = data else {
                DispatchQueue.main.async { completion(.failure(P2PAPIError.noData)) }
                return
            }
            if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode >= 400 {
                let detail = (try? JSONDecoder().decode(APIErrorResponse.self, from: data))?.detail
                DispatchQueue.main.async {
                    completion(.failure(P2PAPIError.serverError(detail ?? "Could not start payment setup")))
                }
                return
            }
            struct SetupIntentResponse: Decodable {
                let client_secret: String
                let publishable_key: String
            }
            DispatchQueue.main.async {
                do {
                    let decoded = try JSONDecoder().decode(SetupIntentResponse.self, from: data)
                    completion(.success((clientSecret: decoded.client_secret, publishableKey: decoded.publishable_key)))
                } catch {
                    completion(.failure(error))
                }
            }
        }.resume()
    }

    /// Delete a saved card
    public func deleteCard(
        customerId: Int,
        cardId: String,
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        guard let url = URL(string: "\(baseURL)/customers/\(customerId)/cards/\(cardId)") else {
            completion(.failure(P2PAPIError.invalidURL))
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"

        if let token = customerToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        secureSession.dataTask(with: request) { data, response, error in
            if let error = error {
                DispatchQueue.main.async { completion(.failure(error)) }
                return
            }

            if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode < 300 {
                DispatchQueue.main.async { completion(.success(())) }
            } else {
                DispatchQueue.main.async {
                    completion(.failure(P2PAPIError.serverError("Failed to delete card")))
                }
            }
        }.resume()
    }

    /// Set a card as the default payment method
    public func setDefaultCard(
        customerId: Int,
        cardId: String,
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        guard let url = URL(string: "\(baseURL)/customers/\(customerId)/cards/\(cardId)/default") else {
            completion(.failure(P2PAPIError.invalidURL))
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"

        if let token = customerToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        secureSession.dataTask(with: request) { data, response, error in
            if let error = error {
                DispatchQueue.main.async { completion(.failure(error)) }
                return
            }

            if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode < 300 {
                DispatchQueue.main.async { completion(.success(())) }
            } else {
                DispatchQueue.main.async {
                    completion(.failure(P2PAPIError.serverError("Failed to set default card")))
                }
            }
        }.resume()
    }

    // MARK: - Account Deletion APIs (Apple App Store Requirement 5.1.1)

    /// Delete driver account and all associated data
    /// Required by Apple App Store Guidelines for account-based apps
    public func deleteDriverAccount(
        driverId: Int,
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        guard let url = URL(string: "\(baseURL)/drivers/\(driverId)/delete") else {
            completion(.failure(P2PAPIError.invalidURL))
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"

        if let token = driverToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        secureSession.dataTask(with: request) { data, response, error in
            if let error = error {
                DispatchQueue.main.async { completion(.failure(error)) }
                return
            }

            if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode < 300 {
                // Clear driver session from secure storage
                SecureStorage.shared.clearAuthTokens(type: .driver)
                DispatchQueue.main.async { completion(.success(())) }
            } else {
                DispatchQueue.main.async {
                    completion(.failure(P2PAPIError.serverError("Failed to delete driver account")))
                }
            }
        }.resume()
    }

    /// Delete customer account and all associated data
    /// Required by Apple App Store Guidelines for account-based apps
    public func deleteCustomerAccount(
        customerId: Int,
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        guard let url = URL(string: "\(baseURL)/customers/\(customerId)/delete") else {
            completion(.failure(P2PAPIError.invalidURL))
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"

        if let token = customerToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        secureSession.dataTask(with: request) { data, response, error in
            if let error = error {
                DispatchQueue.main.async { completion(.failure(error)) }
                return
            }

            if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode < 300 {
                // Clear customer session from secure storage
                SecureStorage.shared.clearAuthTokens(type: .customer)
                DispatchQueue.main.async { completion(.success(())) }
            } else {
                DispatchQueue.main.async {
                    completion(.failure(P2PAPIError.serverError("Failed to delete customer account")))
                }
            }
        }.resume()
    }

    // MARK: - Ride Cancellation APIs

    /// Cancel ride with cancellation fee (if applicable)
    /// Fee schedule:
    /// - Free: Within 2 minutes of request OR no driver assigned
    /// - $5: After driver assigned but before pickup
    /// - $10: After driver en route (>50% of fare)
    public func cancelRide(
        rideId: Int,
        reason: String?,
        completion: @escaping (Result<RideCancellationResponse, Error>) -> Void
    ) {
        guard let url = URL(string: "\(baseURL)/rides/request/\(rideId)/cancel") else {
            completion(.failure(P2PAPIError.invalidURL))
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        // Add customer auth token
        if let token = customerToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        var body: [String: Any] = ["ride_id": rideId]
        if let reason = reason {
            body["reason"] = reason
        }

        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        secureSession.dataTask(with: request) { data, response, error in
            if let error = error {
                completion(.failure(error))
                return
            }

            guard let data = data else {
                completion(.failure(P2PAPIError.noData))
                return
            }

            DispatchQueue.main.async {
                do {
                    let response = try JSONDecoder().decode(RideCancellationResponse.self, from: data)
                    completion(.success(response))
                } catch {
                    completion(.failure(error))
                }
            }
        }.resume()
    }

    // MARK: - Rideshare Chat APIs (REST - matches Android)

    /// Fetch chat messages for a ride request
    /// Endpoint: GET /api/p2p/ride-requests/{ride_id}/chat
    /// Uses production URL (api.dollor.ai)
    public func fetchRideChatMessages(
        rideRequestId: Int,
        completion: @escaping (Result<[RideChatMessage], Error>) -> Void
    ) {
        guard let url = URL(string: "\(baseURL)/p2p/ride-requests/\(rideRequestId)/chat") else {
            completion(.failure(P2PAPIError.invalidURL))
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        if let token = driverToken ?? customerToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        secureSession.dataTask(with: request) { data, response, error in
            if let error = error {
                DispatchQueue.main.async {
                    completion(.failure(error))
                }
                return
            }

            guard let data = data else {
                DispatchQueue.main.async {
                    completion(.failure(P2PAPIError.noData))
                }
                return
            }

            DispatchQueue.main.async {
                // Server returns {"messages": [...]}; older builds expected a bare array.
                struct ChatEnvelope: Decodable { let messages: [RideChatMessage] }
                if let envelope = try? JSONDecoder().decode(ChatEnvelope.self, from: data) {
                    completion(.success(envelope.messages))
                } else if let messages = try? JSONDecoder().decode([RideChatMessage].self, from: data) {
                    completion(.success(messages))
                } else {
                    completion(.success([]))
                }
            }
        }.resume()
    }

    /// Send a chat message for a ride request
    /// Endpoint: POST /api/p2p/ride-requests/{ride_id}/chat
    /// Uses production URL (api.dollor.ai)
    public func sendRideChatMessage(
        rideRequestId: Int,
        message: String,
        senderType: String, // "customer" or "driver"
        completion: @escaping (Result<RideChatMessage, Error>) -> Void
    ) {
        guard let url = URL(string: "\(baseURL)/p2p/ride-requests/\(rideRequestId)/chat") else {
            completion(.failure(P2PAPIError.invalidURL))
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        if let token = driverToken ?? customerToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        let body: [String: Any] = [
            "message": message,
            "sender_type": senderType
        ]

        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        secureSession.dataTask(with: request) { data, response, error in
            if let error = error {
                DispatchQueue.main.async {
                    completion(.failure(error))
                }
                return
            }

            guard let data = data else {
                DispatchQueue.main.async {
                    completion(.failure(P2PAPIError.noData))
                }
                return
            }

            DispatchQueue.main.async {
                do {
                    let chatMessage = try JSONDecoder().decode(RideChatMessage.self, from: data)
                    completion(.success(chatMessage))
                } catch {
                    completion(.failure(error))
                }
            }
        }.resume()
    }

    // MARK: - AI Support Chat

    /// Send a message to the AI support chat agent
    /// Endpoint: POST /api/support/chat
    /// Public endpoint (no auth required), but includes customer token if available for context
    public func sendSupportChatMessage(
        message: String,
        completion: @escaping (Result<String, Error>) -> Void
    ) {
        guard let url = URL(string: "\(baseURL)/support/chat") else {
            completion(.failure(P2PAPIError.invalidURL))
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        // Include customer token if available for user context
        if let token = customerToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        let body: [String: Any] = ["message": message]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        secureSession.dataTask(with: request) { data, response, error in
            if let error = error {
                DispatchQueue.main.async {
                    completion(.failure(error))
                }
                return
            }

            guard let data = data else {
                DispatchQueue.main.async {
                    completion(.failure(P2PAPIError.noData))
                }
                return
            }

            DispatchQueue.main.async {
                if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let success = json["success"] as? Bool, success,
                   let aiResponse = json["response"] as? String {
                    completion(.success(aiResponse))
                } else {
                    completion(.failure(P2PAPIError.serverError("AI support is temporarily unavailable")))
                }
            }
        }.resume()
    }

    /// Customer fare negotiation - submit counter offer
    public func customerSubmitFareOffer(
        rideId: Int,
        proposedFare: Double,
        completion: @escaping (Result<FareNegotiationResponse, Error>) -> Void
    ) {
        // TODO: [LOW] API mismatch — uses GET with query param for mutation; POST with JSON body is conventional
        // Backend expects proposed_fare as query parameter
        guard let url = URL(string: "\(baseURL)/erp/rides/\(rideId)/customer-negotiate?proposed_fare=\(proposedFare)") else {
            completion(.failure(P2PAPIError.invalidURL))
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        // Add customer auth token
        if let token = customerToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        // No body needed - fare is in query param

        secureSession.dataTask(with: request) { data, response, error in
            if let error = error {
                DispatchQueue.main.async { completion(.failure(error)) }
                return
            }

            guard let data = data else {
                DispatchQueue.main.async { completion(.failure(P2PAPIError.noData)) }
                return
            }

            DispatchQueue.main.async {
                // Surface the real backend error instead of a silent/generic failure.
                if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode >= 400 {
                    if let errorResponse = try? JSONDecoder().decode(P2PErrorResponse.self, from: data) {
                        completion(.failure(P2PAPIError.serverError(errorResponse.detail)))
                    } else {
                        let bodyText = String(data: data, encoding: .utf8) ?? "Fare offer failed"
                        completion(.failure(P2PAPIError.serverError("(\(httpResponse.statusCode)) \(bodyText)")))
                    }
                    return
                }
                do {
                    let response = try JSONDecoder().decode(FareNegotiationResponse.self, from: data)
                    completion(.success(response))
                } catch {
                    completion(.failure(error))
                }
            }
        }.resume()
    }

    /// Customer accepts driver's fare offer
    public func customerAcceptDriverFare(
        rideId: Int,
        acceptedFare: Double,
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        // TODO: [LOW] API mismatch — uses GET with query param for mutation; POST with JSON body is conventional
        // Backend expects accepted_fare as query parameter, not POST body
        guard let url = URL(string: "\(baseURL)/erp/rides/\(rideId)/customer-accept-fare?accepted_fare=\(acceptedFare)") else {
            completion(.failure(P2PAPIError.invalidURL))
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        // Add customer auth token
        if let token = customerToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        // No body needed - fare is passed as query parameter

        secureSession.dataTask(with: request) { data, response, error in
            if let error = error {
                completion(.failure(error))
                return
            }

            if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 {
                completion(.success(()))
            } else {
                completion(.failure(P2PAPIError.serverError("Failed to accept fare")))
            }
        }.resume()
    }

    /// Get current negotiation status for a ride (polling endpoint for customers)
    public func getRideNegotiationStatus(
        rideId: Int,
        completion: @escaping (Result<RideNegotiationStatus, Error>) -> Void
    ) {
        guard let url = URL(string: "\(baseURL)/erp/rides/\(rideId)/negotiation-status") else {
            completion(.failure(P2PAPIError.invalidURL))
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        // Add customer auth token
        if let token = customerToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        secureSession.dataTask(with: request) { data, response, error in
            if let error = error {
                completion(.failure(error))
                return
            }

            guard let data = data else {
                completion(.failure(P2PAPIError.noData))
                return
            }

            DispatchQueue.main.async {
                do {
                    let response = try JSONDecoder().decode(RideNegotiationStatus.self, from: data)
                    completion(.success(response))
                } catch {
                    completion(.failure(error))
                }
            }
        }.resume()
    }
}

/// Ride negotiation status response (for polling)
public struct RideNegotiationStatus: Codable {
    public let success: Bool
    public let rideId: Int
    public let negotiationStatus: String  // "none", "customer_offered", "driver_countered", "accepted", "rejected"
    public let customerOffer: Double?
    public let driverOffer: Double?
    public let agreedFare: Double?
    public let platformFee: Double
    public let driverEarnings: Double?
    public let message: String?
    public let lastUpdated: String?

    enum CodingKeys: String, CodingKey {
        case success
        case rideId = "ride_id"
        case negotiationStatus = "negotiation_status"
        case customerOffer = "customer_offer"
        case driverOffer = "driver_offer"
        case agreedFare = "agreed_fare"
        case platformFee = "platform_fee"
        case driverEarnings = "driver_earnings"
        case message
        case lastUpdated = "last_updated"
    }
}

// MARK: - Stripe Payment Models

/// Stripe saved card model
public struct StripeCard: Identifiable, Codable, Sendable {
    public let id: String
    public let last4: String
    public let brand: CardBrand
    public let expiryMonth: Int
    public let expiryYear: Int
    public var isDefault: Bool

    public enum CardBrand: String, Codable, Sendable {
        case visa, mastercard, amex, discover, unknown

        public var displayName: String {
            switch self {
            case .visa: return "Visa"
            case .mastercard: return "Mastercard"
            case .amex: return "Amex"
            case .discover: return "Discover"
            case .unknown: return "Card"
            }
        }

        public var icon: String {
            switch self {
            case .visa: return "creditcard.fill"
            case .mastercard: return "creditcard.fill"
            case .amex: return "creditcard.fill"
            case .discover: return "creditcard.fill"
            case .unknown: return "creditcard.fill"
            }
        }
    }

    enum CodingKeys: String, CodingKey {
        case id
        case last4
        case brand
        case expiryMonth = "exp_month"
        case expiryYear = "exp_year"
        case isDefault = "is_default"
    }
}

/// Response wrapper for list of cards
public struct StripeCardsResponse: Codable {
    public let cards: [StripeCard]
}

/// API Error response
public struct APIErrorResponse: Codable {
    public let detail: String?
    public let message: String?
}

/// Stripe PaymentIntent response
public struct StripePaymentIntentResponse: Codable {
    public let success: Bool
    public let clientSecret: String
    public let paymentIntentId: String
    // Tiered pricing fields from /api/payments/ride/create-intent
    public let fare: Double?
    public let tierFee: Double?
    public let customerPays: Double?
    public let driverReceives: Double?
    public let platformEarns: Double?
    // Legacy fields (for backward compatibility with other payment flows)
    public let amount: Int?  // in cents
    public let currency: String?
    public let publishableKey: String?

    enum CodingKeys: String, CodingKey {
        case success
        case clientSecret = "client_secret"
        case paymentIntentId = "payment_intent_id"
        case fare
        case tierFee = "tier_fee"
        case customerPays = "customer_pays"
        case driverReceives = "driver_receives"
        case platformEarns = "platform_earns"
        case amount
        case currency
        case publishableKey = "publishable_key"
    }
}

/// Ride payment confirmation
public struct RidePaymentConfirmation: Codable {
    public let success: Bool
    public let rideId: Int
    public let paymentStatus: String
    public let amountPaid: Double?
    public let receiptUrl: String?
    public let message: String?

    enum CodingKeys: String, CodingKey {
        case success
        case rideId = "ride_id"
        case paymentStatus = "payment_status"
        case amountPaid = "amount_paid"
        case receiptUrl = "receipt_url"
        case message
    }

    /// Public initializer for creating local confirmation
    public init(success: Bool, message: String?, rideId: Int, paymentStatus: String, amountPaid: Double? = nil, receiptUrl: String? = nil) {
        self.success = success
        self.message = message
        self.rideId = rideId
        self.paymentStatus = paymentStatus
        self.amountPaid = amountPaid
        self.receiptUrl = receiptUrl
    }
}

/// Ride cancellation response
public struct RideCancellationResponse: Codable {
    public let success: Bool
    public let message: String
    public let rideId: Int?
    public let cancellationFee: Double?
    public let refundAmount: Double?
    public let reason: String?
    public let cancelledAt: String?

    enum CodingKeys: String, CodingKey {
        case success
        case message
        case rideId = "ride_id"
        case cancellationFee = "cancellation_fee"
        case refundAmount = "refund_amount"
        case reason
        case cancelledAt = "cancelled_at"
    }
}

/// Fare negotiation response
public struct FareNegotiationResponse: Codable {
    public let success: Bool
    public let status: String  // "pending", "counter_offered", "accepted", "rejected"
    public let customerOffer: Double
    public let driverOffer: Double?
    public let platformFeeDriver: Double  // Always $1
    public let platformFeeCustomer: Double  // Always $1
    public let message: String?

    enum CodingKeys: String, CodingKey {
        case success
        case status
        case customerOffer = "customer_offer"
        case driverOffer = "driver_offer"
        case platformFeeDriver = "platform_fee_driver"
        case platformFeeCustomer = "platform_fee_customer"
        case message
    }
}

/// Chat message between driver and rider (matches Android RideChatMessage)
/// Used by REST API endpoints: /api/p2p/ride-requests/{id}/chat
public struct RideChatMessage: Identifiable, Codable {
    public let id: Int
    public let rideRequestId: Int
    public let senderType: String // "driver" or "customer"
    public let senderId: Int
    public let message: String
    public let createdAt: String

    public var isFromDriver: Bool {
        return senderType == "driver"
    }

    /// Local-time "h:mm a" for the message. The server sends naive UTC timestamps (no "Z"), so a missing zone means UTC.
    public var timeText: String {
        let parser = DateFormatter()
        parser.locale = Locale(identifier: "en_US_POSIX")
        parser.timeZone = TimeZone(identifier: "UTC")
        parser.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        var date = parser.date(from: String(createdAt.prefix(19)))
        let hasZone = createdAt.count > 19 && (createdAt.hasSuffix("Z") || createdAt.dropFirst(19).contains("+") || createdAt.dropFirst(19).contains("-"))
        if hasZone {
            let iso = ISO8601DateFormatter()
            iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            date = iso.date(from: createdAt) ?? {
                iso.formatOptions = [.withInternetDateTime]
                return iso.date(from: createdAt)
            }() ?? date
        }
        guard let date = date else { return "" }
        let display = DateFormatter()
        display.timeStyle = .short
        return display.string(from: date)
    }

    enum CodingKeys: String, CodingKey {
        case id
        case rideRequestId = "ride_request_id"
        case senderType = "sender_type"
        case senderId = "sender_id"
        case message
        case createdAt = "created_at"
    }
}

/// MARK: - Customer Ride Request Models

/// Response from fare estimate API (matches Android RideEstimateResponse)
/// Endpoint: POST /api/rides/estimate
public struct RideFareEstimateResponse: Codable {
    public let success: Bool
    public let estimate: RideFareEstimate

    enum CodingKeys: String, CodingKey {
        case success, estimate
    }
}

/// Fare estimate details from production API
public struct RideFareEstimate: Codable {
    public let distanceMiles: Double
    public let durationMinutes: Double
    public let breakdown: RideFareBreakdown
    public let subtotal: Double
    public let platformFee: Double
    public let accessForAllFee: RideAccessForAllFee?
    public let total: Double
    public let tier: Int
    public let tierLabel: String
    public let driverInfo: RideDriverInfo?
    public let suggestedBids: [RideSuggestedBid]?
    public let messaging: RideMessaging?
    public let rideType: String?
    public let distanceKm: Double?
    public let surgeMultiplier: Double?
    public let surgeLabel: String?
    public let isSurging: Bool?

    enum CodingKeys: String, CodingKey {
        case distanceMiles = "distance_miles"
        case durationMinutes = "duration_minutes"
        case breakdown, subtotal
        case platformFee = "platform_fee"
        case accessForAllFee = "access_for_all_fee"
        case total, tier
        case tierLabel = "tier_label"
        case driverInfo = "driver_info"
        case suggestedBids = "suggested_bids"
        case messaging
        case rideType = "ride_type"
        case distanceKm = "distance_km"
        case surgeMultiplier = "surge_multiplier"
        case surgeLabel = "surge_label"
        case isSurging = "is_surging"
    }
}

/// CPUC Access for All fee split from the fare estimate
public struct RideAccessForAllFee: Codable {
    public let total: Double?
    public let customerShare: Double?
    public let driverShare: Double?

    enum CodingKeys: String, CodingKey {
        case total
        case customerShare = "customer_share"
        case driverShare = "driver_share"
    }
}

/// Fare breakdown from production API
public struct RideFareBreakdown: Codable {
    public let baseFare: Double
    public let distanceCost: Double
    public let timeCost: Double
    public let timeAdjustment: Double?
    public let timeAdjustmentLabel: String?
    public let longDistanceDiscount: Double?
    public let minimumFareAdjustment: Double?
    public let demandAdjustment: Double?

    enum CodingKeys: String, CodingKey {
        case baseFare = "base_fare"
        case distanceCost = "distance_cost"
        case timeCost = "time_cost"
        case timeAdjustment = "time_adjustment"
        case timeAdjustmentLabel = "time_adjustment_label"
        case longDistanceDiscount = "long_distance_discount"
        case minimumFareAdjustment = "minimum_fare_adjustment"
        case demandAdjustment = "demand_adjustment"
    }
}

/// Driver earnings info from fare estimate
public struct RideDriverInfo: Codable {
    public let earnings: Double
    public let perMile: Double
    public let perHour: Double
    public let percentage: Double

    enum CodingKeys: String, CodingKey {
        case earnings
        case perMile = "per_mile"
        case perHour = "per_hour"
        case percentage
    }
}

/// Suggested bid options for fare negotiation
public struct RideSuggestedBid: Codable {
    public let label: String
    public let emoji: String
    public let price: Double
    public let driverEarnings: Double
    public let acceptanceHint: String
    public let perMile: Double
    public let isRecommended: Bool

    enum CodingKeys: String, CodingKey {
        case label, emoji, price
        case driverEarnings = "driver_earnings"
        case acceptanceHint = "acceptance_hint"
        case perMile = "per_mile"
        case isRecommended = "is_recommended"
    }
}

/// Messaging hints for customer and driver
public struct RideMessaging: Codable {
    public let customer: String?
    public let driver: [String]?
}

/// Input for ride address (pickup or dropoff)
public struct RideAddressInput: Codable {
    public let street: String
    public let city: String
    public let state: String
    public let zip: String
    public let lat: Double
    public let lng: Double

    public init(street: String, city: String, state: String, zip: String, lat: Double, lng: Double) {
        self.street = street
        self.city = city
        self.state = state
        self.zip = zip
        self.lat = lat
        self.lng = lng
    }

    public var fullAddress: String {
        [street, city, state, zip].filter { !$0.isEmpty }.joined(separator: ", ")
    }
}

/// Response from ride request creation
/// Backend returns: { success, message, ride_request: RideRequestForBidding }
public struct RideRequestResponse: Codable {
    public let success: Bool
    public let message: String?
    public let ride_request: RideRequestForBidding?

    public init(success: Bool, message: String?, ride_request: RideRequestForBidding?) {
        self.success = success
        self.message = message
        self.ride_request = ride_request
    }

    /// Convenience accessors for the ride request details
    public var rideId: Int? { ride_request?.id }
    public var rideNumber: String? { ride_request?.request_id }
    public var status: String? { ride_request?.status }
    public var suggestedPrice: Double? { ride_request?.suggested_price }
}

/// Ride tracking info for customers
public struct RideTrackingInfo: Codable {
    public let success: Bool
    public let orderId: Int
    public let orderNumber: String
    public let status: String
    public let driverName: String?
    public let driverPhone: String?
    public let driverPhotoUrl: String?
    public let driverLatitude: Double?
    public let driverLongitude: Double?
    public let estimatedArrival: String?
    // Vehicle info for customer display
    public let driverVehicle: String?
    public let driverVehicleColor: String?
    public let driverLicensePlate: String?
    public let driverVehiclePhotoUrl: String?
    public let driverRating: Double?
    public let driverArrivedAt: String?
    public let estimatedDestinationArrival: String?
    public let etaPickupMinutes: Int?
    public let etaDestinationMinutes: Int?

    /// Current ETA in minutes (pickup before pickup, destination during ride)
    public var currentETAMinutes: Int? {
        if status == "in_progress" { return etaDestinationMinutes }
        return etaPickupMinutes ?? etaDestinationMinutes
    }

    enum CodingKeys: String, CodingKey {
        case success
        case orderId = "order_id"
        case orderNumber = "order_number"
        case status
        case driverName = "driver_name"
        case driverPhone = "driver_phone"
        case driverPhotoUrl = "driver_photo_url"
        case driverLatitude = "driver_latitude"
        case driverLongitude = "driver_longitude"
        case estimatedArrival = "estimated_arrival"
        case driverVehicle = "driver_vehicle"
        case driverVehicleColor = "driver_vehicle_color"
        case driverLicensePlate = "driver_license_plate"
        case driverVehiclePhotoUrl = "driver_vehicle_photo_url"
        case driverRating = "driver_rating"
        case driverArrivedAt = "driver_arrived_at"
        case estimatedDestinationArrival = "estimated_destination_arrival"
        case etaPickupMinutes = "eta_pickup_minutes"
        case etaDestinationMinutes = "eta_destination_minutes"
    }
}

// MARK: - Auth Response Models

public struct P2PErrorResponse: Codable {
    public let detail: String
}

public struct P2PRegistrationRequiredResponse: Codable {
    public let detail: String
    public let registrationUrl: String?
    public let requiresRegistration: Bool?

    enum CodingKeys: String, CodingKey {
        case detail
        case registrationUrl = "registration_url"
        case requiresRegistration = "requires_registration"
    }
}

// MARK: - Error Types

public enum P2PAPIError: Error, LocalizedError {
    case invalidURL
    case noData
    case decodingError
    case encodingFailed
    case serverError(String)
    case httpError(Int)
    case registrationRequired(String, String) // (message, registrationURL)
    case priceChanged(String, [[String: Any]])  // (message, price_changes array)
    case vendorOffline(String)                   // (detail message)
    case gateError(String)                       // (detail) — compliance/eligibility gate (e.g. 403 background check not approved)
    case unauthorized(String)                    // (detail) — server rejected the token (401/403); distinct from serverError so
                                                  // callers (e.g. session-restore-on-launch) can tell "token is truly invalid"
                                                  // apart from any other failure without string-matching the message.

    public var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid URL"
        case .noData:
            return "No data received from server"
        case .decodingError:
            return "Failed to decode server response"
        case .encodingFailed:
            return "Failed to encode data"
        case .serverError(let message):
            return message
        case .httpError(let statusCode):
            return "HTTP error: \(statusCode)"
        case .registrationRequired(let message, _):
            return message
        case .priceChanged(let message, _):
            return message
        case .vendorOffline(let message):
            return message
        case .gateError(let message):
            return message
        case .unauthorized(let message):
            return message
        }
    }
}

// MARK: - Response Models

/// Active promotion for a restaurant
public struct P2PActivePromotion: Decodable {
    public let id: Int
    public let code: String
    public let name: String
    public let type: String
    public let value: Double
    public let dealText: String
    public let minOrder: Double

    enum CodingKeys: String, CodingKey {
        case id, code, name, type, value
        case dealText = "deal_text"
        case minOrder = "min_order"
    }
}

public struct P2PRestaurant: Identifiable, Decodable {
    public let id: Int
    public let vendorId: String
    public let name: String
    public let cuisineType: String?
    public let address: P2PAddress
    public let location: P2PLocation
    public let contact: P2PContact
    public let operatingHours: String?
    public let deliveryAvailable: Bool
    public let pickupAvailable: Bool
    public let averagePrepTime: Int?
    public let menuItemsCount: Int
    public let imageUrl: String?  // Restaurant main image
    public let previewImages: [String]
    public let rating: Double
    public let isOpen: Bool
    public let activePromotion: P2PActivePromotion?  // Active deal if any

    enum CodingKeys: String, CodingKey {
        case id
        case vendorId = "vendor_id"
        case name
        case cuisineType = "cuisine_type"
        case address
        case street, city, state
        case zipCode = "zip_code"
        case location
        case contact
        case operatingHours = "operating_hours"
        case deliveryAvailable = "delivery_available"
        case pickupAvailable = "pickup_available"
        case averagePrepTime = "average_prep_time"
        case menuItemsCount = "menu_items_count"
        case imageUrl = "image_url"
        case previewImages = "preview_images"
        case rating
        case isOpen = "is_open"
        case activePromotion = "active_promotion"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(Int.self, forKey: .id)
        vendorId = try container.decode(String.self, forKey: .vendorId)
        name = try container.decode(String.self, forKey: .name)
        cuisineType = try container.decodeIfPresent(String.self, forKey: .cuisineType)

        // Handle address - can be either P2PAddress object or String
        if let addressObj = try? container.decode(P2PAddress.self, forKey: .address) {
            address = addressObj
        } else if let addressString = try? container.decode(String.self, forKey: .address) {
            // API returns flat structure - build P2PAddress from top-level fields
            address = P2PAddress(
                street: try container.decodeIfPresent(String.self, forKey: .street),
                city: try container.decodeIfPresent(String.self, forKey: .city),
                state: try container.decodeIfPresent(String.self, forKey: .state),
                zipCode: try container.decodeIfPresent(String.self, forKey: .zipCode),
                country: nil,
                fullAddress: addressString
            )
        } else {
            address = P2PAddress(street: nil, city: nil, state: nil, zipCode: nil, country: nil, fullAddress: "Address not available")
        }

        location = try container.decode(P2PLocation.self, forKey: .location)
        contact = try container.decode(P2PContact.self, forKey: .contact)
        operatingHours = try container.decodeIfPresent(String.self, forKey: .operatingHours)
        deliveryAvailable = try container.decodeIfPresent(Bool.self, forKey: .deliveryAvailable) ?? true
        pickupAvailable = try container.decodeIfPresent(Bool.self, forKey: .pickupAvailable) ?? true
        averagePrepTime = try container.decodeIfPresent(Int.self, forKey: .averagePrepTime)
        menuItemsCount = try container.decodeIfPresent(Int.self, forKey: .menuItemsCount) ?? 0
        imageUrl = try container.decodeIfPresent(String.self, forKey: .imageUrl)
        previewImages = try container.decodeIfPresent([String].self, forKey: .previewImages) ?? []
        rating = try container.decodeIfPresent(Double.self, forKey: .rating) ?? 4.5
        isOpen = try container.decodeIfPresent(Bool.self, forKey: .isOpen) ?? true
        activePromotion = try container.decodeIfPresent(P2PActivePromotion.self, forKey: .activePromotion)
    }
}

public struct P2PAddress: Codable {
    public let street: String?
    public let city: String?
    public let state: String?
    public let zipCode: String?
    public let country: String?
    public let fullAddress: String

    enum CodingKeys: String, CodingKey {
        case street, city, state
        case zipCode = "zip_code"
        case country
        case fullAddress = "full_address"
    }

    public init(street: String?, city: String?, state: String?, zipCode: String?, country: String?, fullAddress: String) {
        self.street = street
        self.city = city
        self.state = state
        self.zipCode = zipCode
        self.country = country
        self.fullAddress = fullAddress
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        street = try container.decodeIfPresent(String.self, forKey: .street)
        city = try container.decodeIfPresent(String.self, forKey: .city)
        state = try container.decodeIfPresent(String.self, forKey: .state)
        zipCode = try container.decodeIfPresent(String.self, forKey: .zipCode)
        country = try container.decodeIfPresent(String.self, forKey: .country)
        // Build fullAddress from components if not provided
        if let full = try container.decodeIfPresent(String.self, forKey: .fullAddress) {
            fullAddress = full
        } else {
            var parts: [String] = []
            if let s = street, !s.isEmpty { parts.append(s) }
            if let c = city, !c.isEmpty { parts.append(c) }
            if let st = state, !st.isEmpty { parts.append(st) }
            if let z = zipCode, !z.isEmpty { parts.append(z) }
            fullAddress = parts.isEmpty ? "Address not available" : parts.joined(separator: ", ")
        }
    }
}

public struct P2PLocation: Codable {
    public let latitude: Double?
    public let longitude: Double?

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        latitude = try container.decodeIfPresent(Double.self, forKey: .latitude)
        longitude = try container.decodeIfPresent(Double.self, forKey: .longitude)
    }

    enum CodingKeys: String, CodingKey {
        case latitude, longitude
    }
}

public struct P2PContact: Codable {
    public let phone: String?
    public let email: String?

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        phone = try container.decodeIfPresent(String.self, forKey: .phone)
        email = try container.decodeIfPresent(String.self, forKey: .email)
    }

    enum CodingKeys: String, CodingKey {
        case phone, email
    }
}

// MARK: - Vendor Profile (for Restaurant App Settings)

// MARK: - Vendor Settings PATCH API

extension P2PAPIService {
}

// MARK: - Vendor Documents API

public struct P2PDocumentUploadResponse: Codable {
    public let message: String
    public let filePath: String?

    enum CodingKeys: String, CodingKey {
        case message
        case filePath = "file_path"
    }
}

extension P2PAPIService {

}

// MARK: - P2P Customization Models

public struct P2PCustomizationOption: Codable {
    public let name: String
    public let price: Double
    public let isDefault: Bool?
    public let isAvailable: Bool?

    enum CodingKeys: String, CodingKey {
        case name, price
        case isDefault = "is_default"
        case isAvailable = "is_available"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decode(String.self, forKey: .name)
        price = try container.decodeIfPresent(Double.self, forKey: .price) ?? 0.0
        isDefault = try container.decodeIfPresent(Bool.self, forKey: .isDefault)
        isAvailable = try container.decodeIfPresent(Bool.self, forKey: .isAvailable)
    }
}

public struct P2PMenuItemCustomization: Codable {
    public let name: String
    public let type: String  // "single" or "multiple"
    public let required: Bool
    public let minSelections: Int?
    public let maxSelections: Int?
    public let options: [P2PCustomizationOption]

    enum CodingKeys: String, CodingKey {
        case name, type, required, options
        case minSelections = "min_selections"
        case maxSelections = "max_selections"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decode(String.self, forKey: .name)
        type = try container.decodeIfPresent(String.self, forKey: .type) ?? "single"
        required = try container.decodeIfPresent(Bool.self, forKey: .required) ?? false
        minSelections = try container.decodeIfPresent(Int.self, forKey: .minSelections)
        maxSelections = try container.decodeIfPresent(Int.self, forKey: .maxSelections)
        options = try container.decodeIfPresent([P2PCustomizationOption].self, forKey: .options) ?? []
    }
}

// MARK: - Promotion Models

// MARK: - AI Insights Models

// MARK: - Conversion Extensions

public extension P2PRestaurant {
}

// MARK: - Driver Authentication Response Models

public struct P2PDriverLoginResponse: Codable {
    public let accessToken: String
    public let tokenType: String
    public let driverId: Int
    public let driverCode: String
    private let _name: String?  // Backend may return combined name
    public let firstName: String?  // Backend returns separate first/last
    public let lastName: String?
    public let email: String
    public let status: String?  // Driver status: pending, approved, active, etc.
    public let isApproved: Bool?  // True if driver is approved and can accept jobs
    public let requiresDocuments: Bool?  // True if driver still needs to upload documents
    public let message: String?  // Only present in registration response
    public let bankAccount: P2PBankAccountInfo?  // Included in login response for immediate display

    /// Computed property that returns full name from either format
    public var name: String {
        if let combinedName = _name, !combinedName.isEmpty {
            return combinedName
        }
        let parts = [firstName, lastName].compactMap { $0 }.filter { !$0.isEmpty }
        return parts.isEmpty ? email.components(separatedBy: "@").first ?? "Driver" : parts.joined(separator: " ")
    }

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case tokenType = "token_type"
        case driverId = "driver_id"
        case driverCode = "driver_code"
        case _name = "name"
        case firstName = "first_name"
        case lastName = "last_name"
        case email
        case status
        case isApproved = "is_approved"
        case requiresDocuments = "requires_documents"
        case message
        case bankAccount = "bankAccount"
    }
}

// MARK: - Bank Account Info Model
public struct P2PBankAccountInfo: Codable {
    public let bankName: String?
    public let accountNumberLast4: String?
    public let accountHolderName: String?
    public let routingNumber: String?
    public let accountType: String?
    public let isVerified: Bool?
}

// MARK: - Driver Document Models

public enum DriverDocumentType: String, Codable {
    case driversLicense = "drivers_license"
    case licenseFront = "license_front"
    case licenseBack = "license_back"
    case insurance = "insurance"
    case insuranceCard = "insurance_card"
    case backgroundCheck = "background_check"
    case vehicleFront = "vehicle_front"
    case vehicleSide = "vehicle_side"
    case vehicleBack = "vehicle_back"
    case profilePhoto = "profile_photo"

    public var displayName: String {
        switch self {
        case .driversLicense: return "Driver's License"
        case .licenseFront: return "License Front"
        case .licenseBack: return "License Back"
        case .insurance: return "Vehicle Insurance"
        case .insuranceCard: return "Insurance Card"
        case .backgroundCheck: return "Background Check"
        case .vehicleFront: return "Vehicle Front"
        case .vehicleSide: return "Vehicle Side"
        case .vehicleBack: return "Vehicle Back"
        case .profilePhoto: return "Profile Photo"
        }
    }
}

public struct DriverDocument: Codable, Identifiable {
    public let id: Int
    public let documentType: String
    public let fileName: String
    public let fileUrl: String?
    public let uploadDate: String?
    public let expiryDate: String?
    public let status: String
    public let verified: Bool

    enum CodingKeys: String, CodingKey {
        case id
        case documentType = "document_type"
        case fileName = "file_name"
        case fileUrl = "file_url"
        case uploadDate = "upload_date"
        case expiryDate = "expiry_date"
        case status
        case verified
    }
}

public struct DriverDocumentsResponse: Codable {
    public let driverId: Int
    public let documents: [DriverDocument]
    public let count: Int
    public let allVerified: Bool

    enum CodingKeys: String, CodingKey {
        case driverId = "driver_id"
        case documents
        case count
        case allVerified = "all_verified"
    }
}

// MARK: - Driver Dashboard Response Models (V5 API)

public struct DriverDashboardResponse: Codable {
    public let driverId: String
    public let snapshotTime: String
    public let today: DriverEarningsPeriod
    public let thisWeek: DriverEarningsPeriod
    public let thisMonth: DriverEarningsPeriod
    public let taxInfo: DriverTaxInfo?
    public let platformFeesPaid: DriverPlatformFees?
    public let paymentMethods: DriverPaymentMethods?
    public let ratings: DriverRatings?

    enum CodingKeys: String, CodingKey {
        case driverId = "driver_id"
        case snapshotTime = "snapshot_time"
        case today
        case thisWeek = "this_week"
        case thisMonth = "this_month"
        case taxInfo = "tax_info"
        case platformFeesPaid = "platform_fees_paid"
        case paymentMethods = "payment_methods"
        case ratings
    }
}

/// Earnings for a specific time period - Unified across iOS, Android, and Web
public struct DriverEarningsPeriod: Codable {
    public let deliveries: Int
    public let grossEarnings: Double
    public let basePay: Double?
    public let tips: Double?
    public let bonuses: Double?
    public let totalMiles: Double?
    public let activeHours: Double?
    public let effectiveHourlyRate: Double?
    public let perDeliveryAverage: Double?
    public let foodDeliveries: Int?
    public let rideshareRides: Int?
    public let foodBasePay: Double?
    public let rideshareBasePay: Double?

    enum CodingKeys: String, CodingKey {
        case deliveries
        case grossEarnings = "gross_earnings"
        case basePay = "base_pay"
        case tips
        case bonuses
        case totalMiles = "total_miles"
        case activeHours = "active_hours"
        case effectiveHourlyRate = "effective_hourly_rate"
        case perDeliveryAverage = "per_delivery_average"
        case foodDeliveries = "food_deliveries"
        case rideshareRides = "rideshare_rides"
        case foodBasePay = "food_base_pay"
        case rideshareBasePay = "rideshare_base_pay"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        deliveries = try container.decodeIfPresent(Int.self, forKey: .deliveries) ?? 0
        grossEarnings = try container.decodeIfPresent(Double.self, forKey: .grossEarnings) ?? 0.0
        basePay = try container.decodeIfPresent(Double.self, forKey: .basePay)
        tips = try container.decodeIfPresent(Double.self, forKey: .tips)
        bonuses = try container.decodeIfPresent(Double.self, forKey: .bonuses)
        totalMiles = try container.decodeIfPresent(Double.self, forKey: .totalMiles)
        activeHours = try container.decodeIfPresent(Double.self, forKey: .activeHours)
        effectiveHourlyRate = try container.decodeIfPresent(Double.self, forKey: .effectiveHourlyRate)
        perDeliveryAverage = try container.decodeIfPresent(Double.self, forKey: .perDeliveryAverage)
        foodDeliveries = try container.decodeIfPresent(Int.self, forKey: .foodDeliveries)
        rideshareRides = try container.decodeIfPresent(Int.self, forKey: .rideshareRides)
        foodBasePay = try container.decodeIfPresent(Double.self, forKey: .foodBasePay)
        rideshareBasePay = try container.decodeIfPresent(Double.self, forKey: .rideshareBasePay)
    }
}

public struct DriverTaxInfo: Codable {
    public let totalMilesYtd: Double?
    public let mileageDeductionYtd: Double?
    public let grossEarningsYtd: Double?
    public let estimatedTaxableAfterMileage: Double?
    public let note: String?
    public let otherDeductions: [String]?

    enum CodingKeys: String, CodingKey {
        case totalMilesYtd = "total_miles_ytd"
        case mileageDeductionYtd = "mileage_deduction_ytd"
        case grossEarningsYtd = "gross_earnings_ytd"
        case estimatedTaxableAfterMileage = "estimated_taxable_after_mileage"
        case note
        case otherDeductions = "other_deductions"
    }
}

public struct DriverPlatformFees: Codable {
    public let toDollor: Double?
    public let note: String?

    enum CodingKeys: String, CodingKey {
        case toDollor = "to_dollor"
        case note
    }
}

public struct DriverPaymentMethods: Codable {
    public let primary: String?
    public let backup: String?
    public let acceptsCash: Bool?

    enum CodingKeys: String, CodingKey {
        case primary
        case backup
        case acceptsCash = "accepts_cash"
    }
}

/// Driver ratings summary - Unified across iOS, Android, and Web
public struct DriverRatings: Codable {
    public let average: Double?
    public let overall: Double?  // Legacy field, use average
    public let totalRatings: Int?
    public let totalReviews: Int?  // Legacy field, use totalRatings
    public let fiveStar: Int?
    public let fourStar: Int?
    public let threeStar: Int?
    public let twoStar: Int?
    public let oneStar: Int?
    public let onTimePercentage: Int?
    public let customerCompliments: Int?

    enum CodingKeys: String, CodingKey {
        case average
        case overall
        case totalRatings = "total_ratings"
        case totalReviews = "total_reviews"
        case fiveStar = "five_star"
        case fourStar = "four_star"
        case threeStar = "three_star"
        case twoStar = "two_star"
        case oneStar = "one_star"
        case onTimePercentage = "on_time_percentage"
        case customerCompliments = "customer_compliments"
    }
}

/// Daily earnings breakdown for charts - Unified across iOS, Android, and Web
public struct DailyEarning: Codable, Identifiable {
    public var id: String { date }
    public let day: String
    public let date: String
    public let deliveries: Int
    public let earnings: Double
    public let hours: Double

    enum CodingKeys: String, CodingKey {
        case day, date, deliveries, earnings, hours
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        day = try container.decodeIfPresent(String.self, forKey: .day) ?? ""
        date = try container.decodeIfPresent(String.self, forKey: .date) ?? ""
        deliveries = try container.decodeIfPresent(Int.self, forKey: .deliveries) ?? 0
        earnings = try container.decodeIfPresent(Double.self, forKey: .earnings) ?? 0.0
        hours = try container.decodeIfPresent(Double.self, forKey: .hours) ?? 0.0
    }
}

/// Payout record - Unified across iOS, Android, and Web
public struct PayoutRecord: Codable, Identifiable {
    public var id: String
    public let date: String
    public let amount: Double
    public let method: String
    public let status: String  // pending, processing, completed, failed
    public let fee: Double?

    enum CodingKeys: String, CodingKey {
        case id, date, amount, method, status, fee
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString
        date = try container.decodeIfPresent(String.self, forKey: .date) ?? ""
        amount = try container.decodeIfPresent(Double.self, forKey: .amount) ?? 0.0
        method = try container.decodeIfPresent(String.self, forKey: .method) ?? ""
        status = try container.decodeIfPresent(String.self, forKey: .status) ?? "pending"
        fee = try container.decodeIfPresent(Double.self, forKey: .fee)
    }
}

/// Unified Driver Earnings Response - Aligned across iOS, Android, and Web
/// Matches backend /api/drivers/{driver_id}/earnings response
public struct DriverEarningsResponse: Codable {
    // Primary earnings data (for selected period)
    public let total: Double
    public let basePay: Double
    public let tips: Double
    public let bonuses: Double
    public let previousPeriod: Double
    public let deliveries: Int
    public let hoursOnline: Double
    public let avgPerDelivery: Double
    public let hourlyRate: Double

    // Multi-period data (for dashboard)
    public let today: DriverEarningsPeriod?
    public let thisWeek: DriverEarningsPeriod?
    public let thisMonth: DriverEarningsPeriod?

    // Daily breakdown (for charts)
    public let dailyBreakdown: [DailyEarning]?

    // Ratings
    public let ratings: DriverRatings?

    // Payout info
    public let availableBalance: Double?
    public let pendingBalance: Double?
    public let lastPayout: PayoutRecord?

    // Payment history
    public let paymentHistory: [PayoutRecord]?

    // Metadata
    public let driverId: Int?
    public let period: String?
    public let snapshotTime: String?

    enum CodingKeys: String, CodingKey {
        case total
        case basePay = "base_pay"
        case tips, bonuses
        case previousPeriod = "previous_period"
        case deliveries
        case hoursOnline = "hours_online"
        case avgPerDelivery = "avg_per_delivery"
        case hourlyRate = "hourly_rate"
        case today
        case thisWeek = "this_week"
        case thisMonth = "this_month"
        case dailyBreakdown = "daily_breakdown"
        case ratings
        case availableBalance = "available_balance"
        case pendingBalance = "pending_balance"
        case lastPayout = "last_payout"
        case paymentHistory = "payment_history"
        case driverId = "driver_id"
        case period
        case snapshotTime = "snapshot_time"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        total = try container.decodeIfPresent(Double.self, forKey: .total) ?? 0.0
        basePay = try container.decodeIfPresent(Double.self, forKey: .basePay) ?? 0.0
        tips = try container.decodeIfPresent(Double.self, forKey: .tips) ?? 0.0
        bonuses = try container.decodeIfPresent(Double.self, forKey: .bonuses) ?? 0.0
        previousPeriod = try container.decodeIfPresent(Double.self, forKey: .previousPeriod) ?? 0.0
        deliveries = try container.decodeIfPresent(Int.self, forKey: .deliveries) ?? 0
        hoursOnline = try container.decodeIfPresent(Double.self, forKey: .hoursOnline) ?? 0.0
        avgPerDelivery = try container.decodeIfPresent(Double.self, forKey: .avgPerDelivery) ?? 0.0
        hourlyRate = try container.decodeIfPresent(Double.self, forKey: .hourlyRate) ?? 0.0
        today = try container.decodeIfPresent(DriverEarningsPeriod.self, forKey: .today)
        thisWeek = try container.decodeIfPresent(DriverEarningsPeriod.self, forKey: .thisWeek)
        thisMonth = try container.decodeIfPresent(DriverEarningsPeriod.self, forKey: .thisMonth)
        dailyBreakdown = try container.decodeIfPresent([DailyEarning].self, forKey: .dailyBreakdown)
        ratings = try container.decodeIfPresent(DriverRatings.self, forKey: .ratings)
        availableBalance = try container.decodeIfPresent(Double.self, forKey: .availableBalance)
        pendingBalance = try container.decodeIfPresent(Double.self, forKey: .pendingBalance)
        lastPayout = try container.decodeIfPresent(PayoutRecord.self, forKey: .lastPayout)
        paymentHistory = try container.decodeIfPresent([PayoutRecord].self, forKey: .paymentHistory)
        driverId = try container.decodeIfPresent(Int.self, forKey: .driverId)
        period = try container.decodeIfPresent(String.self, forKey: .period)
        snapshotTime = try container.decodeIfPresent(String.self, forKey: .snapshotTime)
    }
}

public struct DocumentUploadResponse: Codable {
    public let success: Bool
    public let message: String
    public let fileUrl: String?
    public let documentType: String
    public let verificationStatus: String
    public let aiVerificationId: String?

    enum CodingKeys: String, CodingKey {
        case success
        case message
        case fileUrl = "file_url"
        case documentType = "document_type"
        case verificationStatus = "verification_status"
        case aiVerificationId = "ai_verification_id"
    }

    public init(success: Bool, message: String, fileUrl: String?, documentType: String, verificationStatus: String, aiVerificationId: String?) {
        self.success = success
        self.message = message
        self.fileUrl = fileUrl
        self.documentType = documentType
        self.verificationStatus = verificationStatus
        self.aiVerificationId = aiVerificationId
    }
}

// MARK: - Delivery Completion Response

// MARK: - Delivery Order Models

// MARK: - P2P Ride Models

/// Driver mode - Food Delivery or Ride-sharing
public enum DriverMode: String, CaseIterable {
    case foodDelivery = "food_delivery"
    case rideShare = "ride_share"

    public var displayName: String {
        switch self {
        case .foodDelivery: return "Food Delivery"
        case .rideShare: return "Ride Share"
        }
    }

    public var icon: String {
        switch self {
        case .foodDelivery: return "bag.fill"
        case .rideShare: return "car.fill"
        }
    }
}

/// Response for available rides
public struct P2PRidesResponse: Codable {
    public let success: Bool
    public let rides: [P2PRide]
}

/// P2P Ride model - for passenger pickup/dropoff
public struct P2PRide: Identifiable, Codable {
    public let rideId: Int
    public let rideNumber: String
    public let customerName: String?
    public let pickup: P2PRideLocation?
    public let dropoff: P2PRideLocation?
    public let fee: Double
    public let tip: Double?
    public let totalEarnings: Double?
    public let customerPreferredPrice: Double?  // Customer's negotiated offer
    public let notes: String?
    public let createdAt: String?

    public var id: Int { rideId }

    public var earnings: Double {
        totalEarnings ?? (fee + (tip ?? 0))
    }

    /// Display price - customer's offer if available, otherwise suggested fee
    public var displayPrice: Double {
        customerPreferredPrice ?? fee
    }

    /// True if customer has made a specific price offer
    public var hasCustomerOffer: Bool {
        customerPreferredPrice != nil && customerPreferredPrice! > 0
    }

    enum CodingKeys: String, CodingKey {
        case rideId = "ride_id"
        case rideNumber = "ride_number"
        case customerName = "customer_name"
        case pickup
        case dropoff
        case fee
        case tip
        case totalEarnings = "total_earnings"
        case customerPreferredPrice = "customer_preferred_price"
        case notes
        case createdAt = "created_at"
    }
}

/// Ride location with address details
public struct P2PRideLocation: Codable {
    public let street: String?
    public let city: String?
    public let state: String?
    public let zip: String?
    public let lat: Double?
    public let lng: Double?

    public var fullAddress: String {
        [street, city, state, zip].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: ", ")
    }

    public var coordinate: (lat: Double, lng: Double)? {
        guard let lat = lat, let lng = lng else { return nil }
        return (lat, lng)
    }
}

// MARK: - Ride Bidding Models (P2P Matchmaking Platform)

/// Available ride requests response
public struct AvailableRideRequestsResponse: Codable {
    public let success: Bool
    public let available_requests: [RideRequestForBidding]
    public let count: Int
}

/// Shared location type for ride requests
public struct RideLocation: Codable, Equatable {
    public let address: String
    public let latitude: Double
    public let longitude: Double
    public let place_name: String?

    public init(address: String, latitude: Double, longitude: Double, place_name: String? = nil) {
        self.address = address
        self.latitude = latitude
        self.longitude = longitude
        self.place_name = place_name
    }
}

/// Ride request available for bidding (without circular reference)
public struct RideRequestForBidding: Identifiable, Codable, Equatable {
    public let id: Int
    public let request_id: String
    public let customer_id: Int
    public let customer_name: String?
    public let customer_phone: String?  // Available after ride is matched/accepted
    public let pickup: RideLocation
    public let dropoff: RideLocation
    public let estimated_distance_km: Double?
    public let estimated_duration_minutes: Int?
    public let ride_type: String?
    public let suggested_price: Double?
    public let customer_max_price: Double?
    public let customer_preferred_price: Double?
    public let status: String
    public let bidding_expires_at: String?
    public let special_requests: String?
    public let accessibility_requested: Bool?
    public let accessibility_notes: String?
    public let created_at: String?
    public let bid_count: Int?
    public let distance_to_pickup_km: Double?
    public let already_bid: Bool?
    public let driver_arrived_at: String?
    public let driver_payout: Double?
    public let final_price: Double?  // Agreed price once matched
    // Note: my_bid removed to avoid circular reference - fetch separately if needed
}

/// Response from GET /api/rides/driver/active
public struct DriverActiveRidesResponse: Codable {
    public let success: Bool
    public let active_rides: [RideRequestForBidding]
    public let count: Int
}

/// Response from POST /api/rides/request/{id}/complete
public struct RideCompletionResponse: Codable {
    public let success: Bool
    public let message: String?
    public let ride_request: RideCompletionDetail?
    public let final_price: Double?
}

/// Response from POST /api/rides/request/{id}/no-show
public struct NoShowResponse: Codable {
    public let success: Bool
    public let message: String?
    public let cancellation_fee: Double?
    public let driver_payout: Double?
}

/// Surge/demand pricing status
public struct SurgeStatusResponse: Codable {
    public let success: Bool
    public let surge_multiplier: Double
    public let label: String
    public let is_surging: Bool
    public let open_requests: Int
    public let online_drivers: Int
    public let message: String
}

/// Ride detail subset for completion summary
public struct RideCompletionDetail: Codable {
    public let id: Int
    public let request_id: String?
    public let final_price: Double?
    public let platform_fee: Double?
    public let driver_payout: Double?
    public let tip_amount: Double?
    public let pickup: RideLocation?
    public let dropoff: RideLocation?
    public let estimated_distance_km: Double?
    public let estimated_duration_minutes: Int?
    public let customer_name: String?
    public let customer_rating: Int?
    public let status: String?
    public let completed_at: String?
}

/// Ride bid response
public struct RideBidResponse: Codable {
    public let success: Bool
    public let message: String
    public let bid: RideBid?
    public let ride_request: RideRequestForBidding?
    public let accepted_bid: RideBid?
}

/// Driver's bids response
public struct DriverBidsResponse: Codable {
    public let success: Bool
    public let bids: [RideBid]
}

/// Customer's ride request history response
public struct CustomerRideRequestsResponse: Codable {
    public let success: Bool
    public let requests: [RideRequestForBidding]
    public let total: Int?
    public let limit: Int?
    public let offset: Int?
}

/// Ride history item returned by GET /api/customer/rides/history
public struct RideHistoryItem: Codable, Identifiable {
    public let id: Int
    public let pickup: String?
    public let dropoff: String?
    public let pickup_lat: Double?
    public let pickup_lng: Double?
    public let dropoff_lat: Double?
    public let dropoff_lng: Double?
    public let date: String?
    /// Naive UTC timestamp; `date` is the UTC calendar day and can be a day ahead of the rider's local date.
    public let created_at: String?
    public let fare: Double?
    public let platform_fee: Double?
    public let tip: Double?
    /// What the rider actually paid (server-computed, equals the receipt total).
    public let total: Double?
    public let driver_name: String?
    public let status: String?
}

/// Response from GET /api/customer/rides/history
public struct RideHistoryResponse: Codable {
    public let rides: [RideHistoryItem]
    public let total: Int
    public let has_more: Bool
}

/// Customer's ride request bids response (incoming driver bids)
public struct CustomerRideBidsResponse: Codable {
    public let request_id: Int
    public let bids: [RideBid]
    public let total_bids: Int
    public let bidding_open: Bool
    public let bidding_ends_at: String?
}

/// Accepted ride details with driver info for customer
public struct AcceptedRideDetails: Codable {
    public let success: Bool
    public let message: String
    public let ride_id: Int?
    public let driver: AcceptedDriverInfo?
    public let pickup: AcceptedRideLocation?
    public let dropoff: AcceptedRideLocation?
    public let estimated_arrival_minutes: Int?
    public let fare: Double?
    public let status: String?
}

public struct AcceptedDriverInfo: Codable {
    public let id: Int
    public let name: String?
    public let phone: String?
    public let rating: Double?
    public let photo_url: String?
    public let vehicle_make: String?
    public let vehicle_model: String?
    public let vehicle_color: String?
    public let vehicle_year: Int?
    public let license_plate: String?
    public let vehicle_photo_url: String?

    public init(
        id: Int,
        name: String?,
        phone: String?,
        rating: Double?,
        photo_url: String?,
        vehicle_make: String?,
        vehicle_model: String?,
        vehicle_color: String?,
        vehicle_year: Int?,
        license_plate: String?,
        vehicle_photo_url: String?
    ) {
        self.id = id
        self.name = name
        self.phone = phone
        self.rating = rating
        self.photo_url = photo_url
        self.vehicle_make = vehicle_make
        self.vehicle_model = vehicle_model
        self.vehicle_color = vehicle_color
        self.vehicle_year = vehicle_year
        self.license_plate = license_plate
        self.vehicle_photo_url = vehicle_photo_url
    }
}

public struct AcceptedRideLocation: Codable {
    public let address: String?
    public let latitude: Double?
    public let longitude: Double?
}

// MARK: - Checkr Models

/// Checkr-hosted background-check invitation returned by POST /api/checkr/background-check/initiate
public struct CheckrInvitation: Decodable {
    public let invitationUrl: String?
    public let status: String?
    public let message: String?

    enum CodingKeys: String, CodingKey {
        case invitationUrl = "invitation_url"
        case status
        case message
    }
}

/// Ride bid model
public struct RideBid: Identifiable, Codable, Equatable {
    public let id: Int
    public let bid_id: String
    public let ride_request_id: Int
    public let driver_id: Int
    public let driver_name: String?
    public let driver_rating: Double?
    public let driver_photo_url: String?
    public let driver_vehicle: String?
    // Individual vehicle fields from Driver relationship
    public let driver_vehicle_make: String?
    public let driver_vehicle_model: String?
    public let driver_vehicle_year: Int?
    public let driver_vehicle_color: String?
    public let driver_license_plate: String?
    public let driver_trips: Int?
    public let proposed_price: Double
    public let message: String?
    public let estimated_arrival_minutes: Int?
    public let is_counter_offer: Bool?
    public let original_price: Double?
    public let status: String
    public let customer_response: String?
    public let customer_counter_price: Double?
    public let expires_at: String?
    public let created_at: String?
    public let ride_request: RideRequestForBidding?
    // Multi-round negotiation fields
    public let negotiation_round: Int?
    public let last_offer_by: String?
    public let is_final_round: Bool?

    /// Formatted vehicle string from individual fields
    public var vehicleDescription: String? {
        if let make = driver_vehicle_make, let model = driver_vehicle_model {
            var parts = [make, model]
            if let year = driver_vehicle_year { parts.insert(String(year), at: 0) }
            return parts.joined(separator: " ")
        }
        return driver_vehicle
    }
}

/// Response for customer counter-offer
public struct CounterBidResponse: Codable {
    public let success: Bool
    public let message: String?
    public let bid: RideBid?
    public let negotiation_round: Int?
    public let customer_counters_remaining: Int?
    public let rounds_remaining_this_bid: Int?
    public let warning: String?
}

/// Response for driver counter-offer
public struct DriverCounterResponse: Codable {
    public let success: Bool
    public let message: String?
    public let bid: RideBid?
    public let negotiation_round: Int?
    public let is_final_round: Bool?
}

// MARK: - Customer Address Model (for saved delivery addresses)

/// Customer address model matching backend /api/addresses response
public struct P2PCustomerAddress: Codable, Identifiable {
    public let id: Int
    public let userId: Int
    public let locationName: String
    public let street: String
    public let unit: String
    public let city: String
    public let state: String
    public let zipCode: String
    public let instructions: String
    public let addressType: String
    public let latitude: Double
    public let longitude: Double
    public let phoneNumber: String
    public let isDefault: Bool
    public let createdAt: String?
    public let updatedAt: String?

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case locationName = "location_name"
        case label  // API returns "label" instead of "location_name"
        case street
        case unit
        case city
        case state
        case zipCode = "zip_code"
        case instructions
        case addressType = "address_type"
        case latitude
        case longitude
        case phoneNumber = "phone_number"
        case isDefault = "is_default"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(Int.self, forKey: .id)
        userId = try container.decodeIfPresent(Int.self, forKey: .userId) ?? 0
        // Try location_name first, then label
        locationName = try container.decodeIfPresent(String.self, forKey: .locationName)
            ?? container.decodeIfPresent(String.self, forKey: .label)
            ?? "Home"
        street = try container.decodeIfPresent(String.self, forKey: .street) ?? ""
        unit = try container.decodeIfPresent(String.self, forKey: .unit) ?? ""
        city = try container.decodeIfPresent(String.self, forKey: .city) ?? ""
        state = try container.decodeIfPresent(String.self, forKey: .state) ?? ""
        zipCode = try container.decodeIfPresent(String.self, forKey: .zipCode) ?? ""
        instructions = try container.decodeIfPresent(String.self, forKey: .instructions) ?? ""
        addressType = try container.decodeIfPresent(String.self, forKey: .addressType)
            ?? container.decodeIfPresent(String.self, forKey: .label)
            ?? "Home"
        latitude = try container.decodeIfPresent(Double.self, forKey: .latitude) ?? 0.0
        longitude = try container.decodeIfPresent(Double.self, forKey: .longitude) ?? 0.0
        phoneNumber = try container.decodeIfPresent(String.self, forKey: .phoneNumber) ?? ""
        isDefault = try container.decodeIfPresent(Bool.self, forKey: .isDefault) ?? false
        createdAt = try container.decodeIfPresent(String.self, forKey: .createdAt)
        updatedAt = try container.decodeIfPresent(String.self, forKey: .updatedAt)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(userId, forKey: .userId)
        try container.encode(locationName, forKey: .locationName)
        try container.encode(street, forKey: .street)
        try container.encode(unit, forKey: .unit)
        try container.encode(city, forKey: .city)
        try container.encode(state, forKey: .state)
        try container.encode(zipCode, forKey: .zipCode)
        try container.encode(instructions, forKey: .instructions)
        try container.encode(addressType, forKey: .addressType)
        try container.encode(latitude, forKey: .latitude)
        try container.encode(longitude, forKey: .longitude)
        try container.encode(phoneNumber, forKey: .phoneNumber)
        try container.encode(isDefault, forKey: .isDefault)
        try container.encodeIfPresent(createdAt, forKey: .createdAt)
        try container.encodeIfPresent(updatedAt, forKey: .updatedAt)
    }

    /// Convert P2PCustomerAddress to shared Address model
    public func toAddress() -> Address {
        return Address(
            id: String(id),
            userId: String(userId),
            locationName: locationName,
            street: street,
            unit: unit,
            city: city,
            state: state,
            zipCode: zipCode,
            instructions: instructions,
            addressType: addressType,
            latitude: latitude,
            longitude: longitude,
            phoneNumber: phoneNumber,
            isDefault: isDefault
        )
    }
}

// MARK: - Order Creation Response

/// Driver information for pickup/delivery coordination
public struct P2PDriverInfo: Codable {
    public let id: Int?
    public let name: String?
    public let phone: String?
    public let photoUrl: String?
    public let rating: Double?
    public let vehicle: String?          // "Silver Toyota Camry"
    public let vehicleMake: String?
    public let vehicleModel: String?
    public let vehicleColor: String?
    public let licensePlate: String?

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case phone
        case photoUrl = "photo_url"
        case rating
        case vehicle
        case vehicleMake = "vehicle_make"
        case vehicleModel = "vehicle_model"
        case vehicleColor = "vehicle_color"
        case licensePlate = "license_plate"
    }
}

// MARK: - Customer Auth Response Models

public struct P2PPasswordResetResponse: Codable {
    public let message: String
    public let success: Bool

    enum CodingKeys: String, CodingKey {
        case message
        case success
    }
}

public struct P2PCustomerLoginResponse: Codable {
    public let accessToken: String
    public let tokenType: String
    public let customerId: Int
    public let email: String
    public let fullName: String
    public let phone: String?

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case tokenType = "token_type"
        case customerId = "customer_id"
        case email
        case fullName = "full_name"
        case name  // Backend may return "name" instead of "full_name"
        case phone
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        accessToken = try container.decode(String.self, forKey: .accessToken)
        tokenType = try container.decode(String.self, forKey: .tokenType)
        customerId = try container.decode(Int.self, forKey: .customerId)
        email = try container.decode(String.self, forKey: .email)
        phone = try container.decodeIfPresent(String.self, forKey: .phone)

        // Try "full_name" first, fall back to "name"
        if let name = try container.decodeIfPresent(String.self, forKey: .fullName) {
            fullName = name
        } else if let name = try container.decodeIfPresent(String.self, forKey: .name) {
            fullName = name
        } else {
            fullName = ""
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(accessToken, forKey: .accessToken)
        try container.encode(tokenType, forKey: .tokenType)
        try container.encode(customerId, forKey: .customerId)
        try container.encode(email, forKey: .email)
        try container.encode(fullName, forKey: .fullName)
        try container.encodeIfPresent(phone, forKey: .phone)
    }
}

// MARK: - Customer Order Models

// MARK: - Order Tracking Model

// MARK: - Enterprise WebSocket Manager

/// Notification name for WebSocket messages
public extension Notification.Name {
    static let p2pWebSocketMessage = Notification.Name("p2pWebSocketMessage")
}

// MARK: - P2PAPIService Extensions for Enterprise Features

extension P2PAPIService {

    // MARK: - FCM Token Management

    /// Save FCM token for customer
    public func saveCustomerFCMToken(
        customerId: Int,
        token: String,
        completion: @escaping (Result<Bool, Error>) -> Void
    ) {
        guard let url = URL(string: "\(baseURL)/erp/customers/\(customerId)/fcm-token") else {
            completion(.failure(P2PAPIError.invalidURL))
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let token = customerToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        // Backend expects fcm_token and platform fields
        let body = ["fcm_token": token, "platform": "ios"]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        secureSession.dataTask(with: request) { data, response, error in
            DispatchQueue.main.async {
                if let error = error {
                    completion(.failure(error))
                    return
                }
                completion(.success(true))
            }
        }.resume()
    }

    /// Save FCM token for driver
    public func saveDriverFCMToken(
        driverId: Int,
        token: String,
        completion: @escaping (Result<Bool, Error>) -> Void
    ) {
        guard let url = URL(string: "\(baseURL)/erp/drivers/\(driverId)/fcm-token") else {
            completion(.failure(P2PAPIError.invalidURL))
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let token = driverToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        // Backend expects fcm_token and platform fields
        let body = ["fcm_token": token, "platform": "ios"]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        secureSession.dataTask(with: request) { data, response, error in
            DispatchQueue.main.async {
                if let error = error {
                    completion(.failure(error))
                    return
                }
                completion(.success(true))
            }
        }.resume()
    }

    // MARK: - Driver Location Updates

    /// Update driver's current location
    public func updateDriverLocation(
        driverId: Int,
        latitude: Double,
        longitude: Double,
        completion: @escaping (Result<Bool, Error>) -> Void
    ) {
        guard let url = URL(string: "\(baseURL)/erp/drivers/\(driverId)/location") else {
            completion(.failure(P2PAPIError.invalidURL))
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let token = driverToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        let body: [String: Any] = [
            "latitude": latitude,
            "longitude": longitude,
            "updated_at": ISO8601DateFormatter().string(from: Date())
        ]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        secureSession.dataTask(with: request) { data, response, error in
            DispatchQueue.main.async {
                if let error = error {
                    completion(.failure(error))
                    return
                }
                completion(.success(true))
            }
        }.resume()
    }

    /// Update driver online/offline status
    public func updateDriverOnlineStatus(
        driverId: Int,
        isOnline: Bool,
        completion: @escaping (Result<Bool, Error>) -> Void
    ) {
        guard let url = URL(string: "\(baseURL)/erp/drivers/\(driverId)/status?is_online=\(isOnline)") else {
            completion(.failure(P2PAPIError.invalidURL))
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        if let token = driverToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        secureSession.dataTask(with: request) { data, response, error in
            DispatchQueue.main.async {
                if let error = error {
                    completion(.failure(error))
                    return
                }
                completion(.success(true))
            }
        }.resume()
    }

    /// Save FCM token for push notifications
    public func saveDriverFCMToken(
        driverId: Int,
        fcmToken: String,
        completion: @escaping (Result<Bool, Error>) -> Void
    ) {
        guard let url = URL(string: "\(baseURL)/erp/drivers/\(driverId)/fcm-token") else {
            completion(.failure(P2PAPIError.invalidURL))
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let token = driverToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        let body: [String: Any] = ["fcm_token": fcmToken, "platform": "ios"]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        secureSession.dataTask(with: request) { data, response, error in
            DispatchQueue.main.async {
                if let error = error {
                    completion(.failure(error))
                    return
                }
                completion(.success(true))
            }
        }.resume()
    }

    // MARK: - Order Tracking

    /// Get driver location for an order
    public func getDriverLocation(
        orderId: Int,
        completion: @escaping (Result<P2PDriverLocation, Error>) -> Void
    ) {
        guard let url = URL(string: "\(baseURL)/erp/orders/\(orderId)/driver-location") else {
            completion(.failure(P2PAPIError.invalidURL))
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        if let token = customerToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        secureSession.dataTask(with: request) { data, response, error in
            DispatchQueue.main.async {
                if let error = error {
                    completion(.failure(error))
                    return
                }

                guard let data = data else {
                    completion(.failure(P2PAPIError.noData))
                    return
                }

                do {
                    let location = try JSONDecoder().decode(P2PDriverLocation.self, from: data)
                    completion(.success(location))
                } catch {
                    completion(.failure(error))
                }
            }
        }.resume()
    }

    // MARK: - Enterprise Analytics

    /// Get AI employee stats
    public func getAIEmployeeStats(
        completion: @escaping (Result<P2PAIEmployeeStats, Error>) -> Void
    ) {
        guard let url = URL(string: "\(baseURL)/erp/analytics/ai-employees") else {
            completion(.failure(P2PAPIError.invalidURL))
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        if let token = vendorToken ?? customerToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        secureSession.dataTask(with: request) { data, response, error in
            DispatchQueue.main.async {
                if let error = error {
                    completion(.failure(error))
                    return
                }

                guard let data = data else {
                    completion(.failure(P2PAPIError.noData))
                    return
                }

                do {
                    let stats = try JSONDecoder().decode(P2PAIEmployeeStats.self, from: data)
                    completion(.success(stats))
                } catch {
                    completion(.failure(error))
                }
            }
        }.resume()
    }

    // MARK: - Driver Rating & Tip APIs


    // MARK: - Ride Rating & Tip APIs

    /// Submit driver rating for a completed ride
    public func submitRideRating(
        rideId: Int,
        rating: Int,
        comment: String? = nil,
        completion: @escaping (Result<P2PRatingResponse, Error>) -> Void
    ) {
        guard let url = URL(string: "\(baseURL)/rides/\(rideId)/rate") else {
            completion(.failure(P2PAPIError.invalidURL))
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        if let token = customerToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        var body: [String: Any] = [
            "rating": rating
        ]
        if let comment = comment {
            body["comment"] = comment
        }
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        secureSession.dataTask(with: request) { data, response, error in
            DispatchQueue.main.async {
                if let error = error {
                    completion(.failure(error))
                    return
                }

                guard let data = data else {
                    completion(.failure(P2PAPIError.noData))
                    return
                }

                if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode >= 400 {
                    if let errorResponse = try? JSONDecoder().decode(P2PErrorResponse.self, from: data) {
                        completion(.failure(P2PAPIError.serverError(errorResponse.detail)))
                    } else {
                        completion(.failure(P2PAPIError.serverError("Failed to submit rating")))
                    }
                    return
                }

                // Parse success response
                do {
                    let ratingResponse = try JSONDecoder().decode(P2PRatingResponse.self, from: data)
                    completion(.success(ratingResponse))
                } catch {
                    // Even if parsing fails, treat as success if HTTP was OK
                    let fallbackResponse = P2PRatingResponse(
                        success: true,
                        message: "Rating submitted",
                        newDriverRating: nil
                    )
                    completion(.success(fallbackResponse))
                }
            }
        }.resume()
    }

    /// Submit tip for a completed ride (100% goes to driver)
    public func submitRideTip(
        rideId: Int,
        amount: Double,
        completion: @escaping (Result<P2PTipResponse, Error>) -> Void
    ) {
        guard let url = URL(string: "\(baseURL)/rides/\(rideId)/tip") else {
            completion(.failure(P2PAPIError.invalidURL))
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        if let token = customerToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        let body: [String: Any] = [
            "tip_amount": amount,
            "tip_type": "post_ride"
        ]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        secureSession.dataTask(with: request) { data, response, error in
            DispatchQueue.main.async {
                if let error = error {
                    completion(.failure(error))
                    return
                }

                guard let data = data else {
                    completion(.failure(P2PAPIError.noData))
                    return
                }

                if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode >= 400 {
                    if let errorResponse = try? JSONDecoder().decode(P2PErrorResponse.self, from: data) {
                        completion(.failure(P2PAPIError.serverError(errorResponse.detail)))
                    } else {
                        completion(.failure(P2PAPIError.serverError("Failed to submit tip")))
                    }
                    return
                }

                // Parse success response
                do {
                    let tipResponse = try JSONDecoder().decode(P2PTipResponse.self, from: data)
                    completion(.success(tipResponse))
                } catch {
                    // Even if parsing fails, treat as success if HTTP was OK
                    let fallbackResponse = P2PTipResponse(
                        success: true,
                        message: "Tip submitted",
                        tipAmount: amount
                    )
                    completion(.success(fallbackResponse))
                }
            }
        }.resume()
    }

    // MARK: - Ride Receipt APIs

    /// Fetch receipt for a completed ride
    public func fetchRideReceipt(
        rideId: Int,
        completion: @escaping (Result<[String: Any], Error>) -> Void
    ) {
        guard let url = URL(string: "\(baseURL)/rides/request/\(rideId)/receipt") else {
            completion(.failure(P2PAPIError.invalidURL))
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let token = customerToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        secureSession.dataTask(with: request) { data, response, error in
            DispatchQueue.main.async {
                if let error = error { completion(.failure(error)); return }
                guard let data = data else { completion(.failure(P2PAPIError.noData)); return }
                if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode >= 400 {
                    completion(.failure(P2PAPIError.serverError("Failed to fetch receipt")))
                    return
                }
                if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    completion(.success(json))
                } else {
                    completion(.failure(P2PAPIError.decodingError))
                }
            }
        }.resume()
    }

    /// Re-send receipt email for a completed ride
    public func emailRideReceipt(
        rideId: Int,
        completion: @escaping (Result<Bool, Error>) -> Void
    ) {
        guard let url = URL(string: "\(baseURL)/rides/request/\(rideId)/email-receipt") else {
            completion(.failure(P2PAPIError.invalidURL))
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let token = customerToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        secureSession.dataTask(with: request) { _, response, error in
            DispatchQueue.main.async {
                if let error = error { completion(.failure(error)); return }
                if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode < 400 {
                    completion(.success(true))
                } else {
                    completion(.failure(P2PAPIError.serverError("Failed to send email")))
                }
            }
        }.resume()
    }

    // MARK: - Driver Payout APIs

    /// Fetch payout history for a driver with period filter
    public func fetchPayoutHistory(
        driverId: Int,
        period: String = "week",
        completion: @escaping (Result<[String: Any], Error>) -> Void
    ) {
        guard let url = URL(string: "\(baseURL)/rides/driver/\(driverId)/payout-history?period=\(period)") else {
            completion(.failure(P2PAPIError.invalidURL))
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let token = driverToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        secureSession.dataTask(with: request) { data, response, error in
            DispatchQueue.main.async {
                if let error = error { completion(.failure(error)); return }
                guard let data = data else { completion(.failure(P2PAPIError.noData)); return }
                if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode >= 400 {
                    completion(.failure(P2PAPIError.serverError("Failed to fetch payout history")))
                    return
                }
                if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    completion(.success(json))
                } else {
                    completion(.failure(P2PAPIError.decodingError))
                }
            }
        }.resume()
    }

    // MARK: - Ride Dispute APIs

    /// Create a dispute for a ride
    public func createRideDispute(
        rideRequestId: Int,
        reason: String,
        description: String,
        completion: @escaping (Result<[String: Any], Error>) -> Void
    ) {
        guard let url = URL(string: "\(baseURL)/rides/dispute") else {
            completion(.failure(P2PAPIError.invalidURL))
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let token = customerToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        let body: [String: Any] = [
            "ride_request_id": rideRequestId,
            "reason": reason,
            "description": description
        ]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        secureSession.dataTask(with: request) { data, response, error in
            DispatchQueue.main.async {
                if let error = error { completion(.failure(error)); return }
                guard let data = data else { completion(.failure(P2PAPIError.noData)); return }
                if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode >= 400 {
                    if let errorResponse = try? JSONDecoder().decode(P2PErrorResponse.self, from: data) {
                        completion(.failure(P2PAPIError.serverError(errorResponse.detail)))
                    } else {
                        completion(.failure(P2PAPIError.serverError("Failed to create dispute")))
                    }
                    return
                }
                if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    completion(.success(json))
                } else {
                    completion(.failure(P2PAPIError.decodingError))
                }
            }
        }.resume()
    }

    /// Fetch disputes for a customer
    public func fetchMyDisputes(
        customerId: Int,
        completion: @escaping (Result<[[String: Any]], Error>) -> Void
    ) {
        guard let url = URL(string: "\(baseURL)/rides/customer/\(customerId)/disputes") else {
            completion(.failure(P2PAPIError.invalidURL))
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let token = customerToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        secureSession.dataTask(with: request) { data, response, error in
            DispatchQueue.main.async {
                if let error = error { completion(.failure(error)); return }
                guard let data = data else { completion(.failure(P2PAPIError.noData)); return }
                if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode >= 400 {
                    completion(.failure(P2PAPIError.serverError("Failed to fetch disputes")))
                    return
                }
                if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let disputes = json["disputes"] as? [[String: Any]] {
                    completion(.success(disputes))
                } else {
                    completion(.failure(P2PAPIError.decodingError))
                }
            }
        }.resume()
    }

    /// Fetch a specific dispute status
    public func fetchDisputeStatus(
        disputeId: Int,
        completion: @escaping (Result<[String: Any], Error>) -> Void
    ) {
        guard let url = URL(string: "\(baseURL)/rides/dispute/\(disputeId)") else {
            completion(.failure(P2PAPIError.invalidURL))
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let token = customerToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        secureSession.dataTask(with: request) { data, response, error in
            DispatchQueue.main.async {
                if let error = error { completion(.failure(error)); return }
                guard let data = data else { completion(.failure(P2PAPIError.noData)); return }
                if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode >= 400 {
                    completion(.failure(P2PAPIError.serverError("Failed to fetch dispute status")))
                    return
                }
                if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    completion(.success(json))
                } else {
                    completion(.failure(P2PAPIError.decodingError))
                }
            }
        }.resume()
    }

    // MARK: - Recurring Ride APIs

    /// Create a recurring ride pattern
    public func createRecurringRide(
        customerId: Int,
        pickupAddress: String,
        pickupLatitude: Double,
        pickupLongitude: Double,
        dropoffAddress: String,
        dropoffLatitude: Double,
        dropoffLongitude: Double,
        scheduleDays: String,
        scheduleTime: String,
        timezone: String,
        maxPrice: Double? = nil,
        preferredDriverId: Int? = nil,
        completion: @escaping (Result<[String: Any], Error>) -> Void
    ) {
        guard let url = URL(string: "\(baseURL)/rides/customer/\(customerId)/recurring-rides") else {
            completion(.failure(P2PAPIError.invalidURL))
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let token = customerToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        var body: [String: Any] = [
            "pickup_address": pickupAddress,
            "pickup_latitude": pickupLatitude,
            "pickup_longitude": pickupLongitude,
            "dropoff_address": dropoffAddress,
            "dropoff_latitude": dropoffLatitude,
            "dropoff_longitude": dropoffLongitude,
            "schedule_days": scheduleDays,
            "schedule_time": scheduleTime,
            "timezone": timezone
        ]
        if let maxPrice = maxPrice { body["max_price"] = maxPrice }
        if let driverId = preferredDriverId { body["preferred_driver_id"] = driverId }
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        secureSession.dataTask(with: request) { data, response, error in
            DispatchQueue.main.async {
                if let error = error { completion(.failure(error)); return }
                guard let data = data else { completion(.failure(P2PAPIError.noData)); return }
                if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode >= 400 {
                    if let errorResponse = try? JSONDecoder().decode(P2PErrorResponse.self, from: data) {
                        completion(.failure(P2PAPIError.serverError(errorResponse.detail)))
                    } else {
                        completion(.failure(P2PAPIError.serverError("Failed to create recurring ride")))
                    }
                    return
                }
                if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    completion(.success(json))
                } else {
                    completion(.failure(P2PAPIError.decodingError))
                }
            }
        }.resume()
    }

    /// Fetch recurring rides for a customer
    public func fetchRecurringRides(
        customerId: Int,
        completion: @escaping (Result<[[String: Any]], Error>) -> Void
    ) {
        guard let url = URL(string: "\(baseURL)/rides/customer/\(customerId)/recurring-rides") else {
            completion(.failure(P2PAPIError.invalidURL))
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let token = customerToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        secureSession.dataTask(with: request) { data, response, error in
            DispatchQueue.main.async {
                if let error = error { completion(.failure(error)); return }
                guard let data = data else { completion(.failure(P2PAPIError.noData)); return }
                if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode >= 400 {
                    completion(.failure(P2PAPIError.serverError("Failed to fetch recurring rides")))
                    return
                }
                if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let rides = json["recurring_rides"] as? [[String: Any]] {
                    completion(.success(rides))
                } else {
                    completion(.failure(P2PAPIError.decodingError))
                }
            }
        }.resume()
    }

    /// Delete a recurring ride
    public func deleteRecurringRide(
        recurringRideId: Int,
        completion: @escaping (Result<Bool, Error>) -> Void
    ) {
        guard let url = URL(string: "\(baseURL)/rides/recurring-rides/\(recurringRideId)") else {
            completion(.failure(P2PAPIError.invalidURL))
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        if let token = customerToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        secureSession.dataTask(with: request) { _, response, error in
            DispatchQueue.main.async {
                if let error = error { completion(.failure(error)); return }
                if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode < 400 {
                    completion(.success(true))
                } else {
                    completion(.failure(P2PAPIError.serverError("Failed to delete recurring ride")))
                }
            }
        }.resume()
    }

    // MARK: - Order Chat APIs

    /// Send chat message for an order
    public func sendChatMessage(
        orderId: Int,
        message: String,
        senderType: String = "customer",
        completion: @escaping (Result<P2PChatMessageResponse, Error>) -> Void
    ) {
        guard let url = URL(string: "\(baseURL)/customer/orders/\(orderId)/chat") else {
            completion(.failure(P2PAPIError.invalidURL))
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        if let token = customerToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        let body: [String: Any] = [
            "order_id": orderId,
            "message": message,
            "sender_type": senderType
        ]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        secureSession.dataTask(with: request) { data, response, error in
            DispatchQueue.main.async {
                if let error = error {
                    completion(.failure(error))
                    return
                }

                guard let data = data else {
                    completion(.failure(P2PAPIError.noData))
                    return
                }

                if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode >= 400 {
                    if let errorResponse = try? JSONDecoder().decode(P2PErrorResponse.self, from: data) {
                        completion(.failure(P2PAPIError.serverError(errorResponse.detail)))
                    } else {
                        completion(.failure(P2PAPIError.serverError("Failed to send message")))
                    }
                    return
                }

                do {
                    let chatResponse = try JSONDecoder().decode(P2PChatMessageResponse.self, from: data)
                    completion(.success(chatResponse))
                } catch {
                    completion(.failure(error))
                }
            }
        }.resume()
    }

    /// Fetch chat messages for an order
    public func fetchChatMessages(
        orderId: Int,
        completion: @escaping (Result<P2PChatMessagesResponse, Error>) -> Void
    ) {
        guard let url = URL(string: "\(baseURL)/customer/orders/\(orderId)/chat") else {
            completion(.failure(P2PAPIError.invalidURL))
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"

        if let token = customerToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        secureSession.dataTask(with: request) { data, response, error in
            DispatchQueue.main.async {
                if let error = error {
                    completion(.failure(error))
                    return
                }

                guard let data = data else {
                    completion(.failure(P2PAPIError.noData))
                    return
                }

                if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode >= 400 {
                    if let errorResponse = try? JSONDecoder().decode(P2PErrorResponse.self, from: data) {
                        completion(.failure(P2PAPIError.serverError(errorResponse.detail)))
                    } else {
                        completion(.failure(P2PAPIError.serverError("Failed to fetch messages")))
                    }
                    return
                }

                do {
                    let messagesResponse = try JSONDecoder().decode(P2PChatMessagesResponse.self, from: data)
                    completion(.success(messagesResponse))
                } catch {
                    completion(.failure(error))
                }
            }
        }.resume()
    }

    // MARK: - Driver Earnings APIs

    // MARK: - Stripe Connect APIs (Driver Payouts)

    /// Get Stripe onboarding link for driver to complete payout setup
    public func getStripeOnboardingLink(
        driverId: Int,
        // Must be an https://*.dollor.ai URL — the backend validates return_url/
        // refresh_url against an allowed-domain list to prevent open-redirect abuse
        // and rejects a custom URL scheme like "dollor://..." with a 400 before ever
        // creating the Stripe AccountLink.
        returnUrl: String = "https://www.dollor.ai/driver/profile",
        completion: @escaping (Result<String, Error>) -> Void
    ) {
        var components = URLComponents(string: "\(baseURL)/drivers/\(driverId)/stripe/onboarding-link")
        components?.queryItems = [
            URLQueryItem(name: "return_url", value: returnUrl),
            URLQueryItem(name: "refresh_url", value: returnUrl)
        ]

        guard let url = components?.url else {
            completion(.failure(P2PAPIError.invalidURL))
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        if let token = driverToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        secureSession.dataTask(with: request) { data, response, error in
            DispatchQueue.main.async {
                if let error = error {
                    completion(.failure(error))
                    return
                }
                guard let data = data,
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                    completion(.failure(P2PAPIError.noData))
                    return
                }
                if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode >= 400 {
                    let detail = json["detail"] as? String ?? "Failed to get onboarding link"
                    completion(.failure(P2PAPIError.serverError(detail)))
                    return
                }
                if let onboardingUrl = json["onboarding_url"] as? String {
                    completion(.success(onboardingUrl))
                } else {
                    completion(.failure(P2PAPIError.serverError("No onboarding URL returned")))
                }
            }
        }.resume()
    }

    /// Get Stripe Express dashboard link for driver to manage payouts
    public func getStripeDashboardLink(
        driverId: Int,
        completion: @escaping (Result<String, Error>) -> Void
    ) {
        guard let url = URL(string: "\(baseURL)/drivers/\(driverId)/stripe/dashboard-link") else {
            completion(.failure(P2PAPIError.invalidURL))
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        if let token = driverToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        secureSession.dataTask(with: request) { data, response, error in
            DispatchQueue.main.async {
                if let error = error {
                    completion(.failure(error))
                    return
                }
                guard let data = data,
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                    completion(.failure(P2PAPIError.noData))
                    return
                }
                if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode >= 400 {
                    let detail = json["detail"] as? String ?? "Failed to get dashboard link"
                    completion(.failure(P2PAPIError.serverError(detail)))
                    return
                }
                if let dashboardUrl = json["dashboard_url"] as? String {
                    completion(.success(dashboardUrl))
                } else {
                    completion(.failure(P2PAPIError.serverError("No dashboard URL returned")))
                }
            }
        }.resume()
    }

    /// Get driver's payout history from completed rides
    public func getPayoutHistory(
        driverId: Int,
        limit: Int = 20,
        completion: @escaping (Result<P2PPayoutHistoryResponse, Error>) -> Void
    ) {
        guard let url = URL(string: "\(baseURL)/drivers/\(driverId)/payout-history?limit=\(limit)") else {
            completion(.failure(P2PAPIError.invalidURL))
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        if let token = driverToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        secureSession.dataTask(with: request) { data, response, error in
            DispatchQueue.main.async {
                if let error = error {
                    completion(.failure(error))
                    return
                }
                guard let data = data else {
                    completion(.failure(P2PAPIError.noData))
                    return
                }
                if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode >= 400 {
                    if let errorResponse = try? JSONDecoder().decode(P2PErrorResponse.self, from: data) {
                        completion(.failure(P2PAPIError.serverError(errorResponse.detail)))
                    } else {
                        completion(.failure(P2PAPIError.serverError("Failed to fetch payout history")))
                    }
                    return
                }
                do {
                    let decoder = JSONDecoder()
                    decoder.keyDecodingStrategy = .convertFromSnakeCase
                    let history = try decoder.decode(P2PPayoutHistoryResponse.self, from: data)
                    completion(.success(history))
                } catch {
                    completion(.failure(error))
                }
            }
        }.resume()
    }

    // MARK: - Cart Management APIs

    // MARK: - Restaurant Order Assignment APIs

    /// Assign a driver to an order (Restaurant App)
    /// - Parameters:
    ///   - orderId: The order ID
    ///   - driverId: The driver ID to assign
    ///   - completion: Result with success or error
    public func assignDriver(
        orderId: Int,
        driverId: Int,
        completion: @escaping (Result<P2PAssignDriverResponse, Error>) -> Void
    ) {
        guard let url = URL(string: "\(baseURL)/erp/orders/\(orderId)/assign-driver") else {
            completion(.failure(P2PAPIError.invalidURL))
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        if let token = vendorToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        let body: [String: Any] = ["driver_id": driverId]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        secureSession.dataTask(with: request) { data, response, error in
            DispatchQueue.main.async {
                if let error = error {
                    completion(.failure(error))
                    return
                }

                guard let data = data else {
                    completion(.failure(P2PAPIError.noData))
                    return
                }

                if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode >= 400 {
                    if let errorResponse = try? JSONDecoder().decode(P2PErrorResponse.self, from: data) {
                        completion(.failure(P2PAPIError.serverError(errorResponse.detail)))
                    } else {
                        completion(.failure(P2PAPIError.serverError("Failed to assign driver")))
                    }
                    return
                }

                do {
                    let decoder = JSONDecoder()
                    decoder.keyDecodingStrategy = .convertFromSnakeCase
                    let assignResponse = try decoder.decode(P2PAssignDriverResponse.self, from: data)
                    completion(.success(assignResponse))
                } catch {
                    completion(.failure(error))
                }
            }
        }.resume()
    }

    // MARK: - Refund Processing APIs

}

// MARK: - Partial Order Response Models

// MARK: - Order Cancellation Response Models

// MARK: - Driver Rating & Tip Response Models

public struct P2PRatingResponse: Codable {
    public let success: Bool
    public let message: String
    public let orderId: Int?
    public let newDriverRating: Double?

    enum CodingKeys: String, CodingKey {
        case success, message
        case orderId = "order_id"
        case newDriverRating = "new_driver_rating"
    }

    public init(success: Bool, message: String, orderId: Int? = nil, newDriverRating: Double? = nil) {
        self.success = success
        self.message = message
        self.orderId = orderId
        self.newDriverRating = newDriverRating
    }
}

public struct P2PTipResponse: Codable {
    public let success: Bool
    public let message: String
    public let orderId: Int?
    public let tipAmount: Double
    public let driverNewEarnings: Double?

    enum CodingKeys: String, CodingKey {
        case success, message
        case orderId = "order_id"
        case tipAmount = "tip_amount"
        case driverNewEarnings = "driver_new_earnings"
    }

    public init(success: Bool, message: String, orderId: Int? = nil, tipAmount: Double, driverNewEarnings: Double? = nil) {
        self.success = success
        self.message = message
        self.orderId = orderId
        self.tipAmount = tipAmount
        self.driverNewEarnings = driverNewEarnings
    }
}

public struct P2PChatMessageResponse: Codable {
    public let success: Bool
    public let message: String
    public let chatMessage: P2PChatMessage

    enum CodingKeys: String, CodingKey {
        case success, message
        case chatMessage = "chat_message"
    }
}

public struct P2PChatMessagesResponse: Codable {
    public let success: Bool
    public let orderId: Int
    public let messages: [P2PChatMessage]

    enum CodingKeys: String, CodingKey {
        case success
        case orderId = "order_id"
        case messages
    }
}

public struct P2PChatMessage: Codable, Identifiable {
    public let id: String
    public let orderId: Int
    public let message: String
    public let senderType: String
    public let timestamp: String

    enum CodingKeys: String, CodingKey {
        case id
        case orderId = "order_id"
        case message
        case senderType = "sender_type"
        case timestamp
    }
}

// MARK: - Customer Favorites Response Models

// MARK: - Enterprise Response Models

public struct P2PTrackingDriver: Codable {
    public let id: Int?
    public let name: String?
    public let phone: String?
    public let rating: Double?
    public let photoUrl: String?
    public let vehicle: String?
    public let vehicleColor: String?
    public let vehiclePhotoUrl: String?
    public let licensePlate: String?
    public let location: P2PLocation?

    enum CodingKeys: String, CodingKey {
        case id, name, phone, rating
        case photoUrl = "photo_url"
        case vehicle
        case vehicleColor = "vehicle_color"
        case vehiclePhotoUrl = "vehicle_photo_url"
        case licensePlate = "license_plate"
        case location
    }
}

public struct P2PDriverLocation: Codable {
    public let success: Bool
    public let orderId: Int
    public let driver: P2PDriverInfo?
    public let location: P2PLocation?
    public let orderStatus: String
    public let estimatedArrival: String?

    enum CodingKeys: String, CodingKey {
        case success
        case orderId = "order_id"
        case driver, location
        case orderStatus = "order_status"
        case estimatedArrival = "estimated_arrival"
    }
}

// P2PDriverInfo is defined earlier in this file with vehicle fields

public struct P2PDriversAnalytics: Codable {
    public let totalActive: Int
    public let onlineNow: Int
    public let utilizationRate: Double

    enum CodingKeys: String, CodingKey {
        case totalActive = "total_active"
        case onlineNow = "online_now"
        case utilizationRate = "utilization_rate"
    }
}

public struct P2PAIEmployeeStats: Codable {
    public let success: Bool
    public let timestamp: String
    public let aiEmployees: [P2PAIEmployee]
    public let systemHealth: P2PSystemHealth

    enum CodingKeys: String, CodingKey {
        case success, timestamp
        case aiEmployees = "ai_employees"
        case systemHealth = "system_health"
    }
}

public struct P2PAIEmployee: Codable {
    public let id: String
    public let name: String
    public let role: String
    public let tasksToday: Int
    public let status: String
    public let efficiency: String

    enum CodingKeys: String, CodingKey {
        case id, name, role
        case tasksToday = "tasks_today"
        case status, efficiency
    }
}

public struct P2PSystemHealth: Codable {
    public let allEmployeesOnline: Bool
    public let processingDelayMs: Int
    public let errorRate: String

    enum CodingKeys: String, CodingKey {
        case allEmployeesOnline = "all_employees_online"
        case processingDelayMs = "processing_delay_ms"
        case errorRate = "error_rate"
    }
}

// MARK: - Restaurant Delivery Decision Models (60-Second Window)

// MARK: - P2PAPIService Extension for Delivery Decision

extension P2PAPIService {

    // MARK: - KOT (Kitchen Order Ticket) / POS Integration API

}

// MARK: - KOT Configuration Models

// MARK: - Driver Earnings Response Models

public struct P2PEarningsBreakdown: Codable {
    public let total: Double
    public let basePay: Double
    public let tips: Double
    public let bonuses: Double
    public let deliveryCount: Int

    enum CodingKeys: String, CodingKey {
        case total
        case basePay = "base_pay"
        case tips, bonuses
        case deliveryCount = "delivery_count"
    }
}

public struct P2PMultiPeriodEarnings: Codable {
    public let today: Double
    public let thisWeek: Double
    public let thisMonth: Double

    enum CodingKeys: String, CodingKey {
        case today
        case thisWeek = "this_week"
        case thisMonth = "this_month"
    }
}

public struct P2PDailyEarning: Codable {
    public let date: String
    public let amount: Double
    public let deliveries: Int
}

public struct P2PPaymentHistoryItem: Codable {
    public let id: Int
    public let amount: Double
    public let type: String
    public let status: String
    public let date: String
}

// MARK: - Stripe Connect Response Models

public struct P2PStripeRequirements: Codable {
    public let currentlyDue: [String]?
    public let eventuallyDue: [String]?
    public let pendingVerification: [String]?

    enum CodingKeys: String, CodingKey {
        case currentlyDue = "currently_due"
        case eventuallyDue = "eventually_due"
        case pendingVerification = "pending_verification"
    }
}

// MARK: - Payout History Response Models

public struct P2PPayoutHistoryResponse: Codable {
    public let driverId: Int
    public let driverName: String
    public let stripeConnected: Bool
    public let stripeOnboarded: Bool
    public let totalEarnings: Double
    public let totalTips: Double
    public let payoutCount: Int
    public let payouts: [P2PPayout]

    enum CodingKeys: String, CodingKey {
        case driverId = "driver_id"
        case driverName = "driver_name"
        case stripeConnected = "stripe_connected"
        case stripeOnboarded = "stripe_onboarded"
        case totalEarnings = "total_earnings"
        case totalTips = "total_tips"
        case payoutCount = "payout_count"
        case payouts
    }
}

public struct P2PPayout: Codable {
    public let id: Int
    public let requestId: String?
    public let completedAt: String?
    public let pickup: String?
    public let dropoff: String?
    public let rideFare: Double
    public let platformFee: Double
    public let tip: Double
    public let payout: Double
    public let stripeTransferId: String?

    enum CodingKeys: String, CodingKey {
        case id
        case requestId = "request_id"
        case completedAt = "completed_at"
        case pickup, dropoff
        case rideFare = "ride_fare"
        case platformFee = "platform_fee"
        case tip, payout
        case stripeTransferId = "stripe_transfer_id"
    }
}

// MARK: - Cart Response Models

// MARK: - Driver Assignment Response Models

public struct P2PAssignDriverResponse: Codable {
    public let success: Bool
    public let message: String
    public let orderId: Int?
    public let driverId: Int?
    public let driverName: String?
    public let estimatedPickup: String?

    enum CodingKeys: String, CodingKey {
        case success, message
        case orderId = "order_id"
        case driverId = "driver_id"
        case driverName = "driver_name"
        case estimatedPickup = "estimated_pickup"
    }
}

// MARK: - Refund Processing Response Models
