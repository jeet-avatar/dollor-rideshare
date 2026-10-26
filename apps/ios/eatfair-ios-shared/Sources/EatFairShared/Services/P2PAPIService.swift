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
    }

    // MARK: - Secure URLSession (SSL Pinning)
    // Uses NetworkSecurity's pinning delegate instead of URLSession.shared
    // This ensures all API calls go through SSL certificate pinning validation
    private lazy var secureSession: URLSession = NetworkSecurity.shared.createSecureSession()

    // MARK: - Public Restaurant APIs (Customer App)

    /// Fetch all published/approved restaurants for customer apps
    /// Uses /api/vendors/published endpoint which returns only approved and published restaurants
    public func fetchRestaurants(
        city: String? = nil,
        cuisine: String? = nil,
        completion: @escaping (Result<[P2PRestaurant], Error>) -> Void
    ) {
        // Use vendors/published endpoint - returns only approved & published restaurants
        guard var urlComponents = URLComponents(string: "\(baseURL)/vendors/published") else {
            completion(.failure(P2PAPIError.invalidURL))
            return
        }
        var queryItems: [URLQueryItem] = [
            // Always filter for iOS platform to get restaurants published for iOS
            URLQueryItem(name: "platform", value: "ios")
        ]

        if let city = city {
            queryItems.append(URLQueryItem(name: "city", value: city))
        }
        if let cuisine = cuisine {
            queryItems.append(URLQueryItem(name: "cuisine", value: cuisine))
        }

        urlComponents.queryItems = queryItems

        guard let url = urlComponents.url else {
            completion(.failure(P2PAPIError.invalidURL))
            return
        }

        isLoading = true

        secureSession.dataTask(with: url) { [weak self] data, response, error in
            DispatchQueue.main.async {
                self?.isLoading = false

                if let error = error {
                    #if DEBUG
                    logger.error("fetchRestaurants network error: \(error)")
                    #endif
                    self?.error = error.localizedDescription
                    completion(.failure(error))
                    return
                }

                // Validate HTTP status code
                if let httpResponse = response as? HTTPURLResponse {
                    guard (200...299).contains(httpResponse.statusCode) else {
                        #if DEBUG
                        logger.info("fetchRestaurants: Invalid HTTP status \(httpResponse.statusCode)")
                        #endif
                        let error = P2PAPIError.httpError(httpResponse.statusCode)
                        self?.error = "Server error: \(httpResponse.statusCode)"
                        completion(.failure(error))
                        return
                    }
                }

                guard let data = data, !data.isEmpty else {
                    #if DEBUG
                    logger.info("fetchRestaurants: No data received")
                    if let httpResponse = response as? HTTPURLResponse {
                        logger.info("HTTP status: \(httpResponse.statusCode)")
                    }
                    #endif
                    completion(.failure(P2PAPIError.noData))
                    return
                }

                #if DEBUG
                if let jsonString = String(data: data, encoding: .utf8) {
                    logger.info("fetchRestaurants response (\(data.count) bytes): \(jsonString.prefix(500))")
                }
                #endif

                do {
                    let response = try JSONDecoder().decode(P2PRestaurantsResponse.self, from: data)
                    completion(.success(response.restaurants))
                } catch {
                    #if DEBUG
                    logger.error("fetchRestaurants decode error: \(error)")
                    #endif
                    self?.error = "Failed to decode restaurants: \(error.localizedDescription)"
                    completion(.failure(error))
                }
            }
        }.resume()
    }

    /// Fetch restaurant detail with full menu
    public func fetchRestaurantDetail(
        vendorId: Int,
        completion: @escaping (Result<P2PRestaurantDetail, Error>) -> Void
    ) {
        guard let url = URL(string: "\(baseURL)/public/restaurants/\(vendorId)") else {
            completion(.failure(P2PAPIError.invalidURL))
            return
        }

        isLoading = true

        secureSession.dataTask(with: url) { [weak self] data, response, error in
            DispatchQueue.main.async {
                self?.isLoading = false

                if let error = error {
                    self?.error = error.localizedDescription
                    completion(.failure(error))
                    return
                }

                // Validate HTTP status code
                if let httpResponse = response as? HTTPURLResponse {
                    guard (200...299).contains(httpResponse.statusCode) else {
                        let error = P2PAPIError.httpError(httpResponse.statusCode)
                        self?.error = "Server error: \(httpResponse.statusCode)"
                        completion(.failure(error))
                        return
                    }
                }

                guard let data = data else {
                    completion(.failure(P2PAPIError.noData))
                    return
                }

                do {
                    let response = try JSONDecoder().decode(P2PRestaurantDetailResponse.self, from: data)
                    completion(.success(response.toDetail()))
                } catch {
                    self?.error = "Failed to decode restaurant detail: \(error.localizedDescription)"
                    completion(.failure(error))
                }
            }
        }.resume()
    }

    /// Fetch vendor profile info (for Restaurant App settings)
    /// Uses public endpoint so no auth required
    public func fetchVendorProfile(
        vendorId: Int,
        completion: @escaping (Result<P2PVendorProfile, Error>) -> Void
    ) {
        guard let url = URL(string: "\(baseURL)/public/restaurants/\(vendorId)") else {
            completion(.failure(P2PAPIError.invalidURL))
            return
        }

        isLoading = true

        secureSession.dataTask(with: url) { [weak self] data, response, error in
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
                    let response = try JSONDecoder().decode(P2PVendorProfileResponse.self, from: data)
                    completion(.success(response.restaurant))
                } catch {
                    self?.error = "Failed to decode vendor profile: \(error.localizedDescription)"
                    #if DEBUG
                    logger.error("Vendor profile decode error: \(error)")
                    #endif
                    completion(.failure(error))
                }
            }
        }.resume()
    }

    // MARK: - Restaurant App APIs (Menu Management)

    /// Fetch menu items for a vendor (Restaurant App)
    public func fetchMenuItems(
        vendorId: Int,
        completion: @escaping (Result<[P2PMenuItem], Error>) -> Void
    ) {
        guard let url = URL(string: "\(baseURL)/vendors/\(vendorId)/menu") else {
            completion(.failure(P2PAPIError.invalidURL))
            return
        }

        isLoading = true

        secureSession.dataTask(with: url) { [weak self] data, response, error in
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
                    // Backend returns array directly, not wrapped in response object
                    let items = try JSONDecoder().decode([P2PMenuItem].self, from: data)
                    completion(.success(items))
                } catch {
                    self?.error = "Failed to decode menu items: \(error.localizedDescription)"
                    #if DEBUG
                    logger.error("Decode error: \(error)")
                    #endif
                    completion(.failure(error))
                }
            }
        }.resume()
    }

    /// Create a new menu item (Restaurant App)
    /// - Parameters:
    ///   - vendorId: The vendor ID
    ///   - menuItem: Dictionary containing menu item data
    ///   - completion: Result with created menu item or error
    public func createMenuItem(
        vendorId: Int,
        menuItem: P2PMenuItemCreate,
        completion: @escaping (Result<P2PMenuItem, Error>) -> Void
    ) {
        guard let url = URL(string: "\(baseURL)/vendors/\(vendorId)/menu") else {
            completion(.failure(P2PAPIError.invalidURL))
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        if let token = vendorToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        do {
            let encoder = JSONEncoder()
            encoder.keyEncodingStrategy = .convertToSnakeCase
            request.httpBody = try encoder.encode(menuItem)
        } catch {
            completion(.failure(error))
            return
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
                        completion(.failure(P2PAPIError.serverError("Failed to create menu item")))
                    }
                    return
                }

                do {
                    let decoder = JSONDecoder()
                    decoder.keyDecodingStrategy = .convertFromSnakeCase
                    let item = try decoder.decode(P2PMenuItem.self, from: data)
                    completion(.success(item))
                } catch {
                    self?.error = "Failed to decode created item: \(error.localizedDescription)"
                    completion(.failure(error))
                }
            }
        }.resume()
    }

    /// Create a combo deal from existing menu items (Restaurant App)
    public func createComboItem(
        vendorId: Int,
        comboData: [String: Any],
        completion: @escaping (Result<[String: Any], Error>) -> Void
    ) {
        guard let url = URL(string: "\(baseURL)/vendors/\(vendorId)/menu/combo") else {
            completion(.failure(P2PAPIError.invalidURL))
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        if let token = vendorToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: comboData)
        } catch {
            completion(.failure(error))
            return
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
                        completion(.failure(P2PAPIError.serverError("Failed to create combo item")))
                    }
                    return
                }

                do {
                    if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
                        completion(.success(json))
                    } else {
                        completion(.failure(P2PAPIError.noData))
                    }
                } catch {
                    self?.error = "Failed to decode combo response: \(error.localizedDescription)"
                    completion(.failure(error))
                }
            }
        }.resume()
    }

    /// Update a menu item (Restaurant App)
    public func updateMenuItem(
        vendorId: Int,
        itemId: Int,
        updates: [String: Any],
        completion: @escaping (Result<P2PMenuItem, Error>) -> Void
    ) {
        guard let url = URL(string: "\(baseURL)/vendors/\(vendorId)/menu/\(itemId)") else {
            completion(.failure(P2PAPIError.invalidURL))
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        if let token = vendorToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: updates)
        } catch {
            completion(.failure(error))
            return
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
                    let response = try JSONDecoder().decode(P2PMenuItemResponse.self, from: data)
                    completion(.success(response.item))
                } catch {
                    self?.error = "Failed to decode updated item: \(error.localizedDescription)"
                    completion(.failure(error))
                }
            }
        }.resume()
    }

    /// Delete a menu item (Restaurant App)
    /// - Parameters:
    ///   - vendorId: The vendor ID
    ///   - itemId: The menu item ID to delete
    ///   - completion: Result with success or error
    public func deleteMenuItem(
        vendorId: Int,
        itemId: Int,
        completion: @escaping (Result<Bool, Error>) -> Void
    ) {
        guard let url = URL(string: "\(baseURL)/vendors/\(vendorId)/menu/\(itemId)") else {
            completion(.failure(P2PAPIError.invalidURL))
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"

        if let token = vendorToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        secureSession.dataTask(with: request) { data, response, error in
            DispatchQueue.main.async {
                if let error = error {
                    completion(.failure(error))
                    return
                }

                if let httpResponse = response as? HTTPURLResponse {
                    if httpResponse.statusCode == 200 || httpResponse.statusCode == 204 {
                        completion(.success(true))
                    } else if httpResponse.statusCode >= 400 {
                        if let data = data,
                           let errorResponse = try? JSONDecoder().decode(P2PErrorResponse.self, from: data) {
                            completion(.failure(P2PAPIError.serverError(errorResponse.detail)))
                        } else {
                            completion(.failure(P2PAPIError.serverError("Failed to delete menu item")))
                        }
                    } else {
                        completion(.success(true))
                    }
                } else {
                    completion(.failure(P2PAPIError.serverError("Invalid response")))
                }
            }
        }.resume()
    }

    /// Get menu categories for a vendor (Restaurant App)
    /// - Parameters:
    ///   - vendorId: The vendor ID
    ///   - completion: Result with list of categories or error
    public func getMenuCategories(
        vendorId: Int,
        completion: @escaping (Result<[String], Error>) -> Void
    ) {
        guard let url = URL(string: "\(baseURL)/vendors/\(vendorId)/menu/categories") else {
            completion(.failure(P2PAPIError.invalidURL))
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"

        if let token = vendorToken {
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
                        completion(.failure(P2PAPIError.serverError("Failed to get categories")))
                    }
                    return
                }

                do {
                    let categoriesResponse = try JSONDecoder().decode(P2PMenuCategoriesResponse.self, from: data)
                    completion(.success(categoriesResponse.categories))
                } catch {
                    completion(.failure(error))
                }
            }
        }.resume()
    }

    /// Toggle menu item availability (Restaurant App)
    public func toggleItemAvailability(
        vendorId: Int,
        itemId: Int,
        inStock: Bool,
        completion: @escaping (Result<Bool, Error>) -> Void
    ) {
        updateMenuItem(vendorId: vendorId, itemId: itemId, updates: ["in_stock": inStock]) { result in
            switch result {
            case .success(let item):
                completion(.success(item.inStock))
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }

    // MARK: - Promotions API (Customer App)

    /// Get all active promotions for customers to browse
    public func getActivePromotions(
        completion: @escaping (Result<P2PActivePromotionsResponse, Error>) -> Void
    ) {
        let endpoint = "\(baseURL)/promotions/active"

        guard let url = URL(string: endpoint) else {
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
                    let response = try JSONDecoder().decode(P2PActivePromotionsResponse.self, from: data)
                    completion(.success(response))
                } catch {
                    completion(.failure(error))
                }
            }
        }.resume()
    }

    /// Get featured deals for homepage banner
    public func getFeaturedDeals(
        completion: @escaping (Result<P2PFeaturedDealsResponse, Error>) -> Void
    ) {
        let endpoint = "\(baseURL)/promotions/featured"

        guard let url = URL(string: endpoint) else {
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
                    #if DEBUG
                    logger.error("getFeaturedDeals network error: \(error)")
                    #endif
                    completion(.failure(error))
                    return
                }

                guard let data = data, !data.isEmpty else {
                    #if DEBUG
                    logger.info("getFeaturedDeals: No data received")
                    #endif
                    // Return empty response instead of error
                    let emptyResponse = P2PFeaturedDealsResponse(success: true, featured: [], count: 0)
                    completion(.success(emptyResponse))
                    return
                }

                #if DEBUG
                if let jsonString = String(data: data, encoding: .utf8) {
                    logger.info("getFeaturedDeals response: \(jsonString.prefix(300))")
                }
                #endif

                do {
                    let response = try JSONDecoder().decode(P2PFeaturedDealsResponse.self, from: data)
                    completion(.success(response))
                } catch {
                    #if DEBUG
                    logger.error("getFeaturedDeals decode error: \(error)")
                    #endif
                    // Return empty response on decode error
                    let emptyResponse = P2PFeaturedDealsResponse(success: true, featured: [], count: 0)
                    completion(.success(emptyResponse))
                }
            }
        }.resume()
    }

    // MARK: - Promotions API (Restaurant App)

    /// Create a new promotion
    public func createPromotion(
        vendorId: Int,
        promotion: P2PPromotionCreate,
        completion: @escaping (Result<P2PPromotion, Error>) -> Void
    ) {
        guard let url = URL(string: "\(baseURL)/promotions/create?vendor_id=\(vendorId)") else {
            completion(.failure(P2PAPIError.invalidURL))
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        if let token = vendorToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        do {
            let encoder = JSONEncoder()
            encoder.keyEncodingStrategy = .convertToSnakeCase
            request.httpBody = try encoder.encode(promotion)
        } catch {
            completion(.failure(error))
            return
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
                        completion(.failure(P2PAPIError.serverError("Failed to create promotion")))
                    }
                    return
                }

                do {
                    let decoder = JSONDecoder()
                    decoder.keyDecodingStrategy = .convertFromSnakeCase
                    let promo = try decoder.decode(P2PPromotion.self, from: data)
                    completion(.success(promo))
                } catch {
                    completion(.failure(error))
                }
            }
        }.resume()
    }

    /// Get all promotions for a vendor
    public func getVendorPromotions(
        vendorId: Int,
        completion: @escaping (Result<[P2PPromotion], Error>) -> Void
    ) {
        guard let url = URL(string: "\(baseURL)/promotions/vendor/\(vendorId)") else {
            completion(.failure(P2PAPIError.invalidURL))
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"

        if let token = vendorToken {
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
                    let decoder = JSONDecoder()
                    decoder.keyDecodingStrategy = .convertFromSnakeCase
                    let response = try decoder.decode(P2PPromotionsResponse.self, from: data)
                    completion(.success(response.promotions))
                } catch {
                    completion(.failure(error))
                }
            }
        }.resume()
    }

    /// Update a promotion
    public func updatePromotion(
        promotionId: Int,
        updates: [String: Any],
        completion: @escaping (Result<P2PPromotion, Error>) -> Void
    ) {
        guard let url = URL(string: "\(baseURL)/promotions/\(promotionId)") else {
            completion(.failure(P2PAPIError.invalidURL))
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        if let token = vendorToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        request.httpBody = try? JSONSerialization.data(withJSONObject: updates)

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
                    let decoder = JSONDecoder()
                    decoder.keyDecodingStrategy = .convertFromSnakeCase
                    let promo = try decoder.decode(P2PPromotion.self, from: data)
                    completion(.success(promo))
                } catch {
                    completion(.failure(error))
                }
            }
        }.resume()
    }

    /// Delete a promotion
    public func deletePromotion(
        promotionId: Int,
        completion: @escaping (Result<Bool, Error>) -> Void
    ) {
        guard let url = URL(string: "\(baseURL)/promotions/\(promotionId)") else {
            completion(.failure(P2PAPIError.invalidURL))
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"

        if let token = vendorToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        secureSession.dataTask(with: request) { data, response, error in
            DispatchQueue.main.async {
                if let error = error {
                    completion(.failure(error))
                    return
                }

                if let httpResponse = response as? HTTPURLResponse {
                    completion(.success(httpResponse.statusCode == 200 || httpResponse.statusCode == 204))
                } else {
                    completion(.failure(P2PAPIError.serverError("Invalid response")))
                }
            }
        }.resume()
    }

    /// Get AI-suggested promotions
    public func getPromotionSuggestions(
        vendorId: Int,
        completion: @escaping (Result<[P2PPromotionSuggestion], Error>) -> Void
    ) {
        guard let url = URL(string: "\(baseURL)/promotions/suggestions/\(vendorId)") else {
            completion(.failure(P2PAPIError.invalidURL))
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"

        if let token = vendorToken {
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
                    let decoder = JSONDecoder()
                    decoder.keyDecodingStrategy = .convertFromSnakeCase
                    let response = try decoder.decode(P2PPromotionSuggestionsResponse.self, from: data)
                    completion(.success(response.suggestions))
                } catch {
                    completion(.failure(error))
                }
            }
        }.resume()
    }

    /// Get promotion analytics
    public func getPromotionAnalytics(
        vendorId: Int,
        completion: @escaping (Result<P2PPromotionAnalytics, Error>) -> Void
    ) {
        guard let url = URL(string: "\(baseURL)/promotions/analytics/\(vendorId)") else {
            completion(.failure(P2PAPIError.invalidURL))
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"

        if let token = vendorToken {
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
                    let decoder = JSONDecoder()
                    decoder.keyDecodingStrategy = .convertFromSnakeCase
                    let analytics = try decoder.decode(P2PPromotionAnalytics.self, from: data)
                    completion(.success(analytics))
                } catch {
                    completion(.failure(error))
                }
            }
        }.resume()
    }

    // MARK: - AI Insights API

    /// Fetch AI-powered insights for a vendor's restaurant
    /// - Parameters:
    ///   - vendorId: The vendor's ID
    ///   - period: Time period - "today", "week", "month", "year"
    ///   - completion: Callback with AI insights or error
    public func getAIInsights(
        vendorId: Int,
        period: String = "today",
        completion: @escaping (Result<P2PAIInsightsResponse, Error>) -> Void
    ) {
        guard let url = URL(string: "\(baseURL)/vendors/\(vendorId)/ai-insights?period=\(period)") else {
            completion(.failure(P2PAPIError.invalidURL))
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"

        if let token = vendorToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        #if DEBUG
        logger.info("Fetching AI Insights for vendor \(vendorId), period: \(period)")
        #endif

        secureSession.dataTask(with: request) { data, response, error in
            DispatchQueue.main.async {
                if let error = error {
                    #if DEBUG
                    logger.error("AI Insights error: \(error.localizedDescription)")
                    #endif
                    completion(.failure(error))
                    return
                }

                guard let data = data else {
                    completion(.failure(P2PAPIError.noData))
                    return
                }

                #if DEBUG
                if let jsonString = String(data: data, encoding: .utf8) {
                    logger.info("AI Insights response: \(jsonString.prefix(500))...")
                }
                #endif

                do {
                    let decoder = JSONDecoder()
                    let insights = try decoder.decode(P2PAIInsightsResponse.self, from: data)
                    #if DEBUG
                    logger.info("AI Insights decoded successfully - \(insights.totalOrders) orders")
                    #endif
                    completion(.success(insights))
                } catch {
                    #if DEBUG
                    logger.error("AI Insights decode error: \(error)")
                    #endif
                    completion(.failure(error))
                }
            }
        }.resume()
    }

    /// Quick-create a promotion by type
    public func quickCreatePromotion(
        vendorId: Int,
        promoType: String,
        completion: @escaping (Result<P2PPromotion, Error>) -> Void
    ) {
        guard let url = URL(string: "\(baseURL)/promotions/quick-create/\(vendorId)/\(promoType)") else {
            completion(.failure(P2PAPIError.invalidURL))
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"

        if let token = vendorToken {
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
                    let decoder = JSONDecoder()
                    decoder.keyDecodingStrategy = .convertFromSnakeCase
                    let promo = try decoder.decode(P2PPromotion.self, from: data)
                    completion(.success(promo))
                } catch {
                    completion(.failure(error))
                }
            }
        }.resume()
    }

    /// Assign stock images to menu items without images
    public func assignStockImages(
        vendorId: Int,
        completion: @escaping (Result<Int, Error>) -> Void
    ) {
        guard let url = URL(string: "\(baseURL)/vendors/\(vendorId)/menu/assign-stock-images") else {
            completion(.failure(P2PAPIError.invalidURL))
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        if let token = vendorToken {
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
                    let response = try JSONDecoder().decode(P2PStockImageResponse.self, from: data)
                    completion(.success(response.itemsUpdated))
                } catch {
                    self?.error = "Failed to assign stock images: \(error.localizedDescription)"
                    completion(.failure(error))
                }
            }
        }.resume()
    }

    // MARK: - Menu Verification APIs (Aria AI Employee)

    /// Get menu verification status
    public func getVerificationStatus(
        vendorId: Int,
        completion: @escaping (Result<P2PVerificationStatus, Error>) -> Void
    ) {
        guard let url = URL(string: "\(baseURL)/menu-verification/status/\(vendorId)") else {
            completion(.failure(P2PAPIError.invalidURL))
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        if let token = vendorToken {
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
                    let status = try JSONDecoder().decode(P2PVerificationStatus.self, from: data)
                    completion(.success(status))
                } catch {
                    self?.error = "Failed to decode verification status: \(error.localizedDescription)"
                    completion(.failure(error))
                }
            }
        }.resume()
    }

    /// Approve all prices (Aria AI)
    public func approveAllPrices(
        vendorId: Int,
        completion: @escaping (Result<Bool, Error>) -> Void
    ) {
        guard let url = URL(string: "\(baseURL)/menu-verification/approve-all/\(vendorId)") else {
            completion(.failure(P2PAPIError.invalidURL))
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        if let token = vendorToken {
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
                    let response = try JSONDecoder().decode(P2PApprovalResponse.self, from: data)
                    completion(.success(response.success))
                } catch {
                    self?.error = "Failed to approve prices: \(error.localizedDescription)"
                    completion(.failure(error))
                }
            }
        }.resume()
    }

    // MARK: - Vendor Authentication

    /// Login as a vendor (restaurant owner)
    public func vendorLogin(
        email: String,
        password: String,
        completion: @escaping (Result<P2PLoginResponse, Error>) -> Void
    ) {
        guard let url = URL(string: "\(baseURL)/auth/vendor/login") else {
            completion(.failure(P2PAPIError.invalidURL))
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        // Custom CharacterSet - .urlQueryAllowed does NOT encode ! @ # $ etc.
        // For form-urlencoded, only alphanumerics and -._~ are safe
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
                    self?.error = error.localizedDescription
                    completion(.failure(error))
                    return
                }

                guard let data = data else {
                    completion(.failure(P2PAPIError.noData))
                    return
                }

                // Check for error response
                if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode != 200 {
                    if let errorResponse = try? JSONDecoder().decode(P2PErrorResponse.self, from: data) {
                        completion(.failure(P2PAPIError.serverError(errorResponse.detail)))
                    } else {
                        completion(.failure(P2PAPIError.serverError("Login failed")))
                    }
                    return
                }

                do {
                    let loginResponse = try JSONDecoder().decode(P2PLoginResponse.self, from: data)
                    // Store the token securely in Keychain
                    SecureStorage.shared.vendorAccessToken = loginResponse.accessToken
                    UserDefaults.standard.set(loginResponse.user.vendorId, forKey: UserDefaultsKey.vendorId)
                    // Save vendor name and email for profile display
                    UserDefaults.standard.set(loginResponse.user.fullName, forKey: UserDefaultsKey.vendorName)
                    UserDefaults.standard.set(loginResponse.user.email, forKey: UserDefaultsKey.vendorEmail)
                    completion(.success(loginResponse))
                } catch {
                    self?.error = "Failed to decode login response: \(error.localizedDescription)"
                    completion(.failure(error))
                }
            }
        }.resume()
    }

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

    /// Register a new vendor
    public func vendorRegister(
        email: String,
        password: String,
        restaurantName: String,
        completion: @escaping (Result<P2PLoginResponse, Error>) -> Void
    ) {
        guard let url = URL(string: "\(baseURL)/auth/vendor/register") else {
            completion(.failure(P2PAPIError.invalidURL))
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = [
            "email": email,
            "password": password,
            "full_name": restaurantName,
            "restaurant_name": restaurantName
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
                    let loginResponse = try JSONDecoder().decode(P2PLoginResponse.self, from: data)
                    // Store the token securely in Keychain
                    SecureStorage.shared.vendorAccessToken = loginResponse.accessToken
                    UserDefaults.standard.set(loginResponse.user.vendorId, forKey: UserDefaultsKey.vendorId)
                    // Save vendor name and email for profile display
                    UserDefaults.standard.set(loginResponse.user.fullName, forKey: UserDefaultsKey.vendorName)
                    UserDefaults.standard.set(loginResponse.user.email, forKey: UserDefaultsKey.vendorEmail)
                    completion(.success(loginResponse))
                } catch {
                    self?.error = "Failed to decode response: \(error.localizedDescription)"
                    completion(.failure(error))
                }
            }
        }.resume()
    }

    /// Public vendor registration with full form data (matching Web 4-step form)
    /// Used by RestaurantRegistrationView for complete vendor onboarding
    public func vendorPublicRegister(
        data: [String: Any],
        completion: @escaping (Result<P2PVendorRegistrationResponse, Error>) -> Void
    ) {
        guard let url = URL(string: "\(baseURL)/vendors/public") else {
            completion(.failure(P2PAPIError.invalidURL))
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: data)
        } catch {
            completion(.failure(P2PAPIError.encodingFailed))
            return
        }

        isLoading = true
        self.error = nil

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
                    let registrationResponse = try JSONDecoder().decode(P2PVendorRegistrationResponse.self, from: data)
                    // Store vendor info for later use
                    UserDefaults.standard.set(registrationResponse.id, forKey: UserDefaultsKey.vendorId)
                    UserDefaults.standard.set(registrationResponse.restaurantName, forKey: UserDefaultsKey.vendorName)
                    UserDefaults.standard.set(registrationResponse.contactEmail, forKey: UserDefaultsKey.vendorEmail)
                    completion(.success(registrationResponse))
                } catch {
                    self?.error = "Failed to decode response: \(error.localizedDescription)"
                    completion(.failure(error))
                }
            }
        }.resume()
    }

    /// Google OAuth login/registration for vendors
    /// This endpoint handles both login and registration - if user exists, logs them in; if not, registers them
    public func vendorGoogleAuth(
        email: String,
        name: String,
        googleId: String,
        completion: @escaping (Result<P2PLoginResponse, Error>) -> Void
    ) {
        let fullURL = "\(baseURL)/auth/vendor/google-auth"
        logger.debug("API vendorGoogleAuth: URL = \(fullURL)")

        guard let url = URL(string: fullURL) else {
            logger.debug("API vendorGoogleAuth: FAILED - Invalid URL")
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
        logger.debug("API vendorGoogleAuth: Request body = \(body)")

        isLoading = true

        secureSession.dataTask(with: request) { [weak self] data, response, error in
            DispatchQueue.main.async {
                self?.isLoading = false

                if let error = error {
                    logger.debug("API vendorGoogleAuth: Network error = \(error.localizedDescription)")
                    self?.error = error.localizedDescription
                    completion(.failure(error))
                    return
                }

                guard let data = data else {
                    logger.debug("API vendorGoogleAuth: FAILED - No data received")
                    completion(.failure(P2PAPIError.noData))
                    return
                }

                // Log raw response
                if let rawResponse = String(data: data, encoding: .utf8) {
                    logger.debug("API vendorGoogleAuth: Raw response = \(rawResponse.prefix(500))")
                }

                if let httpResponse = response as? HTTPURLResponse {
                    logger.debug("API vendorGoogleAuth: HTTP status = \(httpResponse.statusCode)")

                    if httpResponse.statusCode >= 400 {
                        // Check for registration-required response (403 with registration_url)
                        if httpResponse.statusCode == 403,
                           let regResponse = try? JSONDecoder().decode(P2PRegistrationRequiredResponse.self, from: data),
                           let regURL = regResponse.registrationUrl {
                            logger.debug("API vendorGoogleAuth: Registration required - \(regURL)")
                            completion(.failure(P2PAPIError.registrationRequired(regResponse.detail, regURL)))
                            return
                        }
                        if let errorResponse = try? JSONDecoder().decode(P2PErrorResponse.self, from: data) {
                            logger.debug("API vendorGoogleAuth: Server error = \(errorResponse.detail)")
                            completion(.failure(P2PAPIError.serverError(errorResponse.detail)))
                        } else {
                            logger.debug("API vendorGoogleAuth: Unknown server error")
                            completion(.failure(P2PAPIError.serverError("Google auth failed")))
                        }
                        return
                    }
                }

                do {
                    let loginResponse = try JSONDecoder().decode(P2PLoginResponse.self, from: data)
                    logger.debug("API vendorGoogleAuth: Decoded successfully - vendorId = \(loginResponse.user.vendorId ?? -1)")
                    // Store the token securely in Keychain
                    SecureStorage.shared.vendorAccessToken = loginResponse.accessToken
                    UserDefaults.standard.set(loginResponse.user.vendorId, forKey: UserDefaultsKey.vendorId)
                    // Save vendor name and email for profile display
                    UserDefaults.standard.set(loginResponse.user.fullName, forKey: UserDefaultsKey.vendorName)
                    UserDefaults.standard.set(loginResponse.user.email, forKey: UserDefaultsKey.vendorEmail)
                    logger.debug("API vendorGoogleAuth: Saved to UserDefaults and Keychain")
                    completion(.success(loginResponse))
                } catch {
                    logger.debug("API vendorGoogleAuth: DECODE FAILED - \(error)")
                    self?.error = "Failed to decode Google auth response: \(error.localizedDescription)"
                    completion(.failure(error))
                }
            }
        }.resume()
    }

    /// Apple OAuth login/registration for vendors
    /// This endpoint handles both login and registration - if user exists, logs them in; if not, registers them
    /// - identityToken: JWT from Apple containing user's real email (required for returning users)
    public func vendorAppleAuth(
        email: String,
        name: String,
        appleId: String,
        identityToken: String? = nil,
        completion: @escaping (Result<P2PLoginResponse, Error>) -> Void
    ) {
        let fullURL = "\(baseURL)/auth/vendor/apple-auth"
        logger.debug("API vendorAppleAuth: URL = \(fullURL)")

        guard let url = URL(string: fullURL) else {
            logger.debug("API vendorAppleAuth: FAILED - Invalid URL")
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
        logger.debug("API vendorAppleAuth: Request body = \(body)")

        isLoading = true

        secureSession.dataTask(with: request) { [weak self] data, response, error in
            DispatchQueue.main.async {
                self?.isLoading = false

                if let error = error {
                    logger.debug("API vendorAppleAuth: Network error = \(error.localizedDescription)")
                    self?.error = error.localizedDescription
                    completion(.failure(error))
                    return
                }

                guard let data = data else {
                    logger.debug("API vendorAppleAuth: FAILED - No data received")
                    completion(.failure(P2PAPIError.noData))
                    return
                }

                // Log raw response
                if let rawResponse = String(data: data, encoding: .utf8) {
                    logger.debug("API vendorAppleAuth: Raw response = \(rawResponse.prefix(500))")
                }

                if let httpResponse = response as? HTTPURLResponse {
                    logger.debug("API vendorAppleAuth: HTTP status = \(httpResponse.statusCode)")

                    if httpResponse.statusCode >= 400 {
                        // Check for registration-required response (403 with registration_url)
                        if httpResponse.statusCode == 403,
                           let regResponse = try? JSONDecoder().decode(P2PRegistrationRequiredResponse.self, from: data),
                           let regURL = regResponse.registrationUrl {
                            logger.debug("API vendorAppleAuth: Registration required - \(regURL)")
                            completion(.failure(P2PAPIError.registrationRequired(regResponse.detail, regURL)))
                            return
                        }
                        if let errorResponse = try? JSONDecoder().decode(P2PErrorResponse.self, from: data) {
                            logger.debug("API vendorAppleAuth: Server error = \(errorResponse.detail)")
                            completion(.failure(P2PAPIError.serverError(errorResponse.detail)))
                        } else {
                            logger.debug("API vendorAppleAuth: Unknown server error")
                            completion(.failure(P2PAPIError.serverError("Apple auth failed")))
                        }
                        return
                    }
                }

                do {
                    let loginResponse = try JSONDecoder().decode(P2PLoginResponse.self, from: data)
                    logger.debug("API vendorAppleAuth: Decoded successfully - vendorId = \(loginResponse.user.vendorId ?? -1)")
                    // Store the token securely in Keychain
                    SecureStorage.shared.vendorAccessToken = loginResponse.accessToken
                    UserDefaults.standard.set(loginResponse.user.vendorId, forKey: UserDefaultsKey.vendorId)
                    // Save vendor name and email for profile display
                    UserDefaults.standard.set(loginResponse.user.fullName, forKey: UserDefaultsKey.vendorName)
                    UserDefaults.standard.set(loginResponse.user.email, forKey: UserDefaultsKey.vendorEmail)
                    logger.debug("API vendorAppleAuth: Saved to UserDefaults and Keychain")
                    completion(.success(loginResponse))
                } catch {
                    logger.debug("API vendorAppleAuth: DECODE FAILED - \(error)")
                    self?.error = "Failed to decode Apple auth response: \(error.localizedDescription)"
                    completion(.failure(error))
                }
            }
        }.resume()
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

    /// Request password reset for vendor/restaurant - sends reset code to email
    public func requestVendorPasswordReset(
        email: String,
        completion: @escaping (Result<P2PPasswordResetResponse, Error>) -> Void
    ) {
        guard let url = URL(string: "\(baseURL)/vendor/password-reset/request") else {
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

    /// Confirm password reset for vendor/restaurant with code and new password
    public func confirmVendorPasswordReset(
        email: String,
        code: String,
        newPassword: String,
        completion: @escaping (Result<P2PPasswordResetResponse, Error>) -> Void
    ) {
        guard let url = URL(string: "\(baseURL)/vendor/password-reset/confirm") else {
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

    /// Get default address for a customer
    public func fetchDefaultAddress(
        userId: Int,
        completion: @escaping (Result<P2PCustomerAddress?, Error>) -> Void
    ) {
        guard let url = URL(string: "\(baseURL)/addresses/\(userId)/default") else {
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

                // Check for 404 - no addresses
                if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 404 {
                    completion(.success(nil))
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

    /// Fetch all favorites for a customer
    public func fetchCustomerFavorites(
        customerId: Int,
        completion: @escaping (Result<P2PFavoritesResponse, Error>) -> Void
    ) {
        guard let url = URL(string: "\(baseURL)/customer/favorites/\(customerId)") else {
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
                    let response = try JSONDecoder().decode(P2PFavoritesResponse.self, from: data)
                    completion(.success(response))
                } catch {
                    #if DEBUG
                    logger.error("Decode favorites error: \(error)")
                    #endif
                    completion(.failure(error))
                }
            }
        }.resume()
    }

    /// Add a restaurant to favorites
    public func addFavorite(
        customerId: Int,
        vendorId: Int,
        completion: @escaping (Result<P2PAddFavoriteResponse, Error>) -> Void
    ) {
        guard let url = URL(string: "\(baseURL)/customer/favorites/\(customerId)/\(vendorId)") else {
            completion(.failure(P2PAPIError.invalidURL))
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
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
                    let response = try JSONDecoder().decode(P2PAddFavoriteResponse.self, from: data)
                    completion(.success(response))
                } catch {
                    #if DEBUG
                    logger.error("Decode add favorite error: \(error)")
                    #endif
                    completion(.failure(error))
                }
            }
        }.resume()
    }

    /// Remove a restaurant from favorites
    public func removeFavorite(
        customerId: Int,
        vendorId: Int,
        completion: @escaping (Result<P2PMessageResponse, Error>) -> Void
    ) {
        guard let url = URL(string: "\(baseURL)/customer/favorites/\(customerId)/\(vendorId)") else {
            completion(.failure(P2PAPIError.invalidURL))
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"

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
                    let response = try JSONDecoder().decode(P2PMessageResponse.self, from: data)
                    completion(.success(response))
                } catch {
                    #if DEBUG
                    logger.error("Decode remove favorite error: \(error)")
                    #endif
                    completion(.failure(error))
                }
            }
        }.resume()
    }

    /// Check if a restaurant is in favorites
    public func checkFavorite(
        customerId: Int,
        vendorId: Int,
        completion: @escaping (Result<P2PCheckFavoriteResponse, Error>) -> Void
    ) {
        guard let url = URL(string: "\(baseURL)/customer/favorites/\(customerId)/check/\(vendorId)") else {
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
                    let response = try JSONDecoder().decode(P2PCheckFavoriteResponse.self, from: data)
                    completion(.success(response))
                } catch {
                    #if DEBUG
                    logger.error("Decode check favorite error: \(error)")
                    #endif
                    completion(.failure(error))
                }
            }
        }.resume()
    }

    // MARK: - Customer Order APIs

    /// Fetch all orders for the current customer
    public func fetchCustomerOrders(
        completion: @escaping (Result<[P2PCustomerOrder], Error>) -> Void
    ) {
        guard let url = URL(string: "\(baseURL)/customer/orders") else {
            completion(.failure(P2PAPIError.invalidURL))
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"

        // Add auth token if available
        if let token = customerToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        isLoading = true

        secureSession.dataTask(with: request) { [weak self] data, response, error in
            DispatchQueue.main.async {
                self?.isLoading = false

                if let error = error {
                    self?.error = error.localizedDescription
                    completion(.failure(error))
                    return
                }

                // Surface HTTP error status codes as real failures instead of
                // letting them fall through to the array→object fallback decode
                // path (which silently returns an empty array on 401, etc).
                if let httpResponse = response as? HTTPURLResponse,
                   !(200...299).contains(httpResponse.statusCode) {
                    let err = P2PAPIError.httpError(httpResponse.statusCode)
                    self?.error = "Server returned \(httpResponse.statusCode)"
                    completion(.failure(err))
                    return
                }

                guard let data = data else {
                    completion(.failure(P2PAPIError.noData))
                    return
                }

                do {
                    // First try to decode as array (success case)
                    let orders = try JSONDecoder().decode([P2PCustomerOrder].self, from: data)
                    completion(.success(orders))
                } catch {
                    // If array decode fails, try decoding as error response with orders array
                    do {
                        let errorResponse = try JSONDecoder().decode(P2POrdersErrorResponse.self, from: data)
                        completion(.success(errorResponse.orders ?? []))
                    } catch {
                        self?.error = "Failed to decode orders: \(error.localizedDescription)"
                        #if DEBUG
                        logger.error("Decode error: \(error)")
                        #endif
                        completion(.failure(error))
                    }
                }
            }
        }.resume()
    }

    /// Track a specific order with driver location
    public func trackOrder(
        orderId: Int,
        completion: @escaping (Result<P2POrderTracking, Error>) -> Void
    ) {
        guard let url = URL(string: "\(baseURL)/customer/orders/\(orderId)/track") else {
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
                    let tracking = try JSONDecoder().decode(P2POrderTracking.self, from: data)
                    completion(.success(tracking))
                } catch {
                    self?.error = "Failed to decode tracking: \(error.localizedDescription)"
                    completion(.failure(error))
                }
            }
        }.resume()
    }

    /// Fetch customer's active orders (for real-time tracking)
    public func fetchActiveOrders(
        completion: @escaping (Result<[P2PCustomerOrder], Error>) -> Void
    ) {
        guard let customerId = currentCustomerId else {
            // No customer ID, return empty array (guest user)
            completion(.success([]))
            return
        }

        guard let url = URL(string: "\(baseURL)/customer/\(customerId)/active-orders") else {
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
                    let orders = try JSONDecoder().decode([P2PCustomerOrder].self, from: data)
                    completion(.success(orders))
                } catch {
                    // Return empty array if endpoint doesn't exist yet
                    completion(.success([]))
                }
            }
        }.resume()
    }

    // MARK: - Order Creation API (Customer App)

    /// Create a new order and get backend-generated order number
    /// This ensures order numbers are synced across all three apps
    public func createOrder(
        vendorId: Int,
        customerName: String,
        customerEmail: String,
        customerPhone: String,
        deliveryAddress: [String: Any],
        deliveryInstructions: String?,
        items: [[String: Any]],
        tip: Double = 0.0,
        scheduledFor: Date? = nil,
        promoCode: String? = nil,
        completion: @escaping (Result<P2PCreateOrderResponse, Error>) -> Void
    ) {
        guard let url = URL(string: "\(baseURL)/erp/orders/create") else {
            completion(.failure(P2PAPIError.invalidURL))
            return
        }

        guard let token = customerToken else {
            completion(.failure(P2PAPIError.serverError("Customer not logged in")))
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        var body: [String: Any] = [
            "vendor_id": vendorId,
            "customer_name": customerName,
            "customer_email": customerEmail,
            "customer_phone": customerPhone,
            "delivery_address": deliveryAddress,
            "delivery_instructions": deliveryInstructions ?? "",
            "items": items,
            "tip": tip
        ]

        // Add scheduled delivery time if provided
        if let scheduledFor = scheduledFor {
            let formatter = ISO8601DateFormatter()
            body["scheduled_for"] = formatter.string(from: scheduledFor)
        }

        // Add promo code if provided
        if let promoCode = promoCode, !promoCode.isEmpty {
            body["promo_code"] = promoCode
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

                // Check for error response
                if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode >= 400 {
                    // 409: Price change detected
                    if httpResponse.statusCode == 409 {
                        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                           let message = json["message"] as? String,
                           let priceChanges = json["price_changes"] as? [[String: Any]] {
                            completion(.failure(P2PAPIError.priceChanged(message, priceChanges)))
                        } else {
                            completion(.failure(P2PAPIError.serverError("Menu prices have changed. Please refresh your cart.")))
                        }
                        return
                    }

                    // 400: Check for vendor offline
                    if httpResponse.statusCode == 400 {
                        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                           let detail = json["detail"] as? String,
                           detail.lowercased().contains("offline") {
                            completion(.failure(P2PAPIError.vendorOffline(detail)))
                        } else if let errorResponse = try? JSONDecoder().decode(P2PErrorResponse.self, from: data) {
                            completion(.failure(P2PAPIError.serverError(errorResponse.detail)))
                        } else {
                            completion(.failure(P2PAPIError.serverError("Order creation failed")))
                        }
                        return
                    }

                    // Default error handling for other status codes
                    if let errorResponse = try? JSONDecoder().decode(P2PErrorResponse.self, from: data) {
                        completion(.failure(P2PAPIError.serverError(errorResponse.detail)))
                    } else {
                        completion(.failure(P2PAPIError.serverError("Order creation failed")))
                    }
                    return
                }

                do {
                    let orderResponse = try JSONDecoder().decode(P2PCreateOrderResponse.self, from: data)
                    completion(.success(orderResponse))
                } catch {
                    self?.error = "Failed to decode order response: \(error.localizedDescription)"
                    completion(.failure(error))
                }
            }
        }.resume()
    }

    // MARK: - Confirm Order Payment (Customer App)

    /// Confirm payment for an order - called after Stripe payment succeeds
    /// This sends the order to the restaurant for acceptance
    public func confirmOrderPayment(
        orderId: Int,
        completion: @escaping (Result<Bool, Error>) -> Void
    ) {
        guard let url = URL(string: "\(baseURL)/erp/orders/\(orderId)/confirm-payment") else {
            completion(.failure(P2PAPIError.invalidURL))
            return
        }

        guard let token = customerToken else {
            completion(.failure(P2PAPIError.serverError("Customer not logged in")))
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        secureSession.dataTask(with: request) { data, response, error in
            DispatchQueue.main.async {
                if let error = error {
                    completion(.failure(error))
                    return
                }

                if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode >= 400 {
                    if let data = data,
                       let errorResponse = try? JSONDecoder().decode(P2PErrorResponse.self, from: data) {
                        completion(.failure(P2PAPIError.serverError(errorResponse.detail)))
                    } else {
                        completion(.failure(P2PAPIError.serverError("Payment confirmation failed")))
                    }
                    return
                }

                completion(.success(true))
            }
        }.resume()
    }

    // MARK: - Promo Code Validation API (Customer App)

    /// Validate and apply a promo code to get discount amount
    public func validatePromoCode(
        promoCode: String,
        orderTotal: Double,
        customerId: Int? = nil,
        completion: @escaping (Result<PromoCodeResponse, Error>) -> Void
    ) {
        guard let url = URL(string: "\(baseURL)/promotions/apply") else {
            completion(.failure(P2PAPIError.invalidURL))
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        var body: [String: Any] = [
            "promotion_code": promoCode,
            "order_total": orderTotal
        ]

        if let customerId = customerId {
            body["customer_id"] = customerId
        }

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

                // Check for error response
                if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode >= 400 {
                    if let errorResponse = try? JSONDecoder().decode(P2PErrorResponse.self, from: data) {
                        completion(.failure(P2PAPIError.serverError(errorResponse.detail)))
                    } else {
                        completion(.failure(P2PAPIError.serverError("Invalid promo code")))
                    }
                    return
                }

                do {
                    let response = try JSONDecoder().decode(PromoCodeResponse.self, from: data)
                    completion(.success(response))
                } catch {
                    self?.error = "Failed to decode promo response"
                    completion(.failure(error))
                }
            }
        }.resume()
    }

    // MARK: - Vendor Orders API (Restaurant App)

    /// Fetch orders for a vendor from the P2P backend
    /// quick-366: holds the in-flight fetch task so a newer call can cancel an
    /// older one in flight. Avoids race conditions where a slow fetch lands
    /// after a fresh fetch and overwrites with stale data.
    private var inFlightVendorOrdersTask: URLSessionDataTask?

    public func fetchVendorOrders(
        vendorId: Int,
        completion: @escaping (Result<[P2PVendorOrder], Error>) -> Void
    ) {
        guard let url = URL(string: "\(baseURL)/erp/orders/vendor/\(vendorId)") else {
            completion(.failure(P2PAPIError.invalidURL))
            return
        }

        guard let token = vendorToken else {
            completion(.failure(P2PAPIError.serverError("Vendor not logged in")))
            return
        }

        // Cancel any prior in-flight fetch for vendor orders so the latest
        // request wins. Cancelled tasks surface NSURLErrorCancelled which the
        // caller filters out.
        inFlightVendorOrdersTask?.cancel()

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 20

        isLoading = true

        let task = secureSession.dataTask(with: request) { [weak self] data, response, error in
            DispatchQueue.main.async {
                self?.isLoading = false
                self?.inFlightVendorOrdersTask = nil

                if let error = error {
                    self?.error = error.localizedDescription
                    completion(.failure(error))
                    return
                }

                // Surface HTTP-level failures with the actual status code, not
                // a generic decode error from trying to decode an error body.
                if let http = response as? HTTPURLResponse, http.statusCode != 200 {
                    let detail: String = {
                        if let data = data, let body = String(data: data, encoding: .utf8), !body.isEmpty {
                            return "HTTP \(http.statusCode): \(body.prefix(200))"
                        }
                        return "HTTP \(http.statusCode)"
                    }()
                    completion(.failure(P2PAPIError.serverError(detail)))
                    return
                }

                guard let data = data else {
                    completion(.failure(P2PAPIError.noData))
                    return
                }

                do {
                    let response = try JSONDecoder().decode(P2PVendorOrdersResponse.self, from: data)
                    completion(.success(response.orders))
                } catch {
                    self?.error = "Failed to decode vendor orders: \(error.localizedDescription)"
                    completion(.failure(error))
                }
            }
        }
        inFlightVendorOrdersTask = task
        task.resume()
    }

    /// Update order status via P2P backend
    /// - Parameters:
    ///   - orderId: The order ID to update
    ///   - status: New status (PREPARING, READY_FOR_PICKUP, etc.)
    ///   - estimatedMinutes: Optional estimated prep time in minutes (used when setting PREPARING status)
    public func updateOrderStatus(
        orderId: Int,
        status: String,
        estimatedMinutes: Int? = nil,
        completion: @escaping (Result<Bool, Error>) -> Void
    ) {
        var urlString = "\(baseURL)/erp/orders/\(orderId)/status?status=\(status.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? status)"

        // Add estimated_minutes parameter if provided (for prep time sync)
        if let minutes = estimatedMinutes, minutes > 0 {
            urlString += "&estimated_minutes=\(minutes)"
        }

        guard let url = URL(string: urlString) else {
            completion(.failure(P2PAPIError.invalidURL))
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "PUT"

        // Add authorization header - required for order status updates
        if let token = vendorToken {
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
                    completion(.failure(P2PAPIError.serverError("Failed to update order status")))
                }
            }
        }.resume()
    }

    /// Update vendor online/offline status
    public func updateVendorStatus(
        vendorId: Int,
        isOnline: Bool,
        completion: @escaping (Result<Bool, Error>) -> Void
    ) {
        guard let url = URL(string: "\(baseURL)/vendors/\(vendorId)/online-status?is_online=\(isOnline)") else {
            completion(.failure(P2PAPIError.invalidURL))
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "PUT"

        if let token = vendorToken {
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
                    completion(.failure(P2PAPIError.serverError("Failed to update vendor status")))
                }
            }
        }.resume()
    }

    // MARK: - Restaurant Acceptance Flow APIs (3-minute window)

    /// Restaurant accepts an order (within 3-minute window)
    /// POST /api/erp/orders/{orderId}/restaurant-accept
    /// - Parameters:
    ///   - orderId: The order ID to accept
    ///   - estimatedPrepMinutes: Optional prep time in minutes (default 15). Drivers are notified with this ETA.
    ///   - completion: Callback with success/failure
    public func restaurantAcceptOrder(
        orderId: Int,
        estimatedPrepMinutes: Int = 15,
        completion: @escaping (Result<Bool, Error>) -> Void
    ) {
        guard let url = URL(string: "\(baseURL)/erp/orders/\(orderId)/restaurant-accept") else {
            completion(.failure(P2PAPIError.invalidURL))
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        if let token = vendorToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        // Include estimated prep time in request body
        let body: [String: Any] = ["estimated_prep_minutes": estimatedPrepMinutes]
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
                    completion(.failure(P2PAPIError.serverError("Failed to accept order")))
                }
            }
        }.resume()
    }

    /// Restaurant declines an order (within 3-minute window)
    /// POST /api/erp/orders/{orderId}/restaurant-decline
    public func restaurantDeclineOrder(
        orderId: Int,
        reason: String? = nil,
        completion: @escaping (Result<Bool, Error>) -> Void
    ) {
        guard let url = URL(string: "\(baseURL)/erp/orders/\(orderId)/restaurant-decline") else {
            completion(.failure(P2PAPIError.invalidURL))
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        if let token = vendorToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        // Send reason in body
        let body: [String: Any] = ["reason": reason ?? "Restaurant unavailable"]
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
                    completion(.failure(P2PAPIError.serverError("Failed to decline order")))
                }
            }
        }.resume()
    }

    // MARK: - Delivery Decision Flow APIs (3-minute window)

    /// Restaurant accepts delivery (will self-deliver)
    /// POST /api/erp/orders/{orderId}/restaurant-accept-delivery
    public func restaurantAcceptDelivery(
        orderId: Int,
        completion: @escaping (Result<Bool, Error>) -> Void
    ) {
        guard let url = URL(string: "\(baseURL)/erp/orders/\(orderId)/restaurant-accept-delivery") else {
            completion(.failure(P2PAPIError.invalidURL))
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"

        if let token = vendorToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        secureSession.dataTask(with: request) { data, response, error in
            DispatchQueue.main.async {
                if let error = error {
                    completion(.failure(error))
                    return
                }

                if let httpResponse = response as? HTTPURLResponse {
                    if httpResponse.statusCode == 200 {
                        completion(.success(true))
                    } else if httpResponse.statusCode >= 400 {
                        if let data = data,
                           let errorResponse = try? JSONDecoder().decode(P2PErrorResponse.self, from: data) {
                            completion(.failure(P2PAPIError.serverError(errorResponse.detail)))
                        } else {
                            completion(.failure(P2PAPIError.serverError("Failed to accept delivery")))
                        }
                    } else {
                        completion(.success(true))
                    }
                } else {
                    completion(.failure(P2PAPIError.serverError("Invalid response")))
                }
            }
        }.resume()
    }

    /// Restaurant declines delivery (send to driver pool)
    /// POST /api/erp/orders/{orderId}/restaurant-decline-delivery
    public func restaurantDeclineDelivery(
        orderId: Int,
        completion: @escaping (Result<Bool, Error>) -> Void
    ) {
        guard let url = URL(string: "\(baseURL)/erp/orders/\(orderId)/restaurant-decline-delivery") else {
            completion(.failure(P2PAPIError.invalidURL))
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"

        if let token = vendorToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        secureSession.dataTask(with: request) { data, response, error in
            DispatchQueue.main.async {
                if let error = error {
                    completion(.failure(error))
                    return
                }

                if let httpResponse = response as? HTTPURLResponse {
                    if httpResponse.statusCode == 200 {
                        completion(.success(true))
                    } else if httpResponse.statusCode >= 400 {
                        if let data = data,
                           let errorResponse = try? JSONDecoder().decode(P2PErrorResponse.self, from: data) {
                            completion(.failure(P2PAPIError.serverError(errorResponse.detail)))
                        } else {
                            completion(.failure(P2PAPIError.serverError("Failed to send to driver pool")))
                        }
                    } else {
                        completion(.success(true))
                    }
                } else {
                    completion(.failure(P2PAPIError.serverError("Invalid response")))
                }
            }
        }.resume()
    }

    /// quick-370: Restaurant starts self-delivery
    /// POST /api/erp/orders/{orderId}/vendor-start-delivery
    /// Replaces the old admin-only PUT /erp/orders/{id}/status?status=OUT_FOR_DELIVERY.
    public func vendorStartDelivery(
        orderId: Int,
        completion: @escaping (Result<Bool, Error>) -> Void
    ) {
        guard let url = URL(string: "\(baseURL)/erp/orders/\(orderId)/vendor-start-delivery") else {
            completion(.failure(P2PAPIError.invalidURL))
            return
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        if let token = vendorToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        secureSession.dataTask(with: request) { data, response, error in
            DispatchQueue.main.async {
                if let error = error { completion(.failure(error)); return }
                guard let http = response as? HTTPURLResponse else {
                    completion(.failure(P2PAPIError.serverError("Invalid response"))); return
                }
                if http.statusCode == 200 {
                    completion(.success(true))
                } else {
                    let detail = data.flatMap { String(data: $0, encoding: .utf8) }?.prefix(200) ?? "HTTP \(http.statusCode)"
                    completion(.failure(P2PAPIError.serverError(String(detail))))
                }
            }
        }.resume()
    }

    /// Restaurant marks self-delivery order as delivered
    /// POST /api/erp/orders/{orderId}/delivered
    public func restaurantCompleteDelivery(
        orderId: Int,
        completion: @escaping (Result<DeliveryCompletionResponse, Error>) -> Void
    ) {
        guard let url = URL(string: "\(baseURL)/erp/orders/\(orderId)/delivered") else {
            completion(.failure(P2PAPIError.invalidURL))
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"

        if let token = vendorToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        secureSession.dataTask(with: request) { data, response, error in
            DispatchQueue.main.async {
                if let error = error {
                    completion(.failure(error))
                    return
                }

                guard let data = data,
                      let httpResponse = response as? HTTPURLResponse,
                      httpResponse.statusCode == 200 else {
                    completion(.failure(P2PAPIError.serverError("Failed to mark order as delivered")))
                    return
                }

                do {
                    let decoded = try JSONDecoder().decode(DeliveryCompletionResponse.self, from: data)
                    completion(.success(decoded))
                } catch {
                    completion(.success(DeliveryCompletionResponse(success: true, requiresPhoto: false)))
                }
            }
        }.resume()
    }

    // MARK: - Vendor Stripe Connect (Payout Setup)

    /// Response from GET /api/vendors/{id}/stripe/status
    public struct VendorStripeStatus: Decodable, Sendable {
        public let success: Bool?
        public let hasStripeAccount: Bool
        public let onboarded: Bool?
        public let chargesEnabled: Bool?
        public let payoutsEnabled: Bool?
        public let bankAccountLinked: Bool?
        public let bankAccount: BankAccount?
        public let detailsSubmitted: Bool?
        public let message: String?

        public struct BankAccount: Decodable, Sendable {
            public let bankName: String?
            public let last4: String?
            public let accountHolderName: String?
            public let status: String?

            enum CodingKeys: String, CodingKey {
                case bankName = "bank_name"
                case last4
                case accountHolderName = "account_holder_name"
                case status
            }
        }

        enum CodingKeys: String, CodingKey {
            case success
            case hasStripeAccount = "has_stripe_account"
            case onboarded
            case chargesEnabled = "charges_enabled"
            case payoutsEnabled = "payouts_enabled"
            case bankAccountLinked = "bank_account_linked"
            case bankAccount = "bank_account"
            case detailsSubmitted = "details_submitted"
            case message
        }
    }

    /// Response from POST /api/vendors/{id}/stripe/connect
    public struct VendorStripeConnectResponse: Decodable, Sendable {
        public let success: Bool
        public let stripeAccountId: String?
        public let onboarded: Bool?
        public let message: String?

        enum CodingKeys: String, CodingKey {
            case success
            case stripeAccountId = "stripe_account_id"
            case onboarded
            case message
        }
    }

    /// Response from GET /api/vendors/{id}/stripe/onboarding-link
    public struct VendorOnboardingLinkResponse: Decodable, Sendable {
        public let success: Bool?
        public let url: String?
        public let onboardingUrl: String?
        public let expiresAt: Int?

        /// The link the user must open in Safari to complete KYC.
        public var bestUrl: String? { onboardingUrl ?? url }

        enum CodingKeys: String, CodingKey {
            case success
            case url
            case onboardingUrl = "onboarding_url"
            case expiresAt = "expires_at"
        }
    }

    /// GET /api/vendors/{id}/stripe/status — what state the vendor's payout setup is in
    public func getVendorStripeStatus(
        vendorId: Int,
        completion: @escaping (Result<VendorStripeStatus, Error>) -> Void
    ) {
        guard let url = URL(string: "\(baseURL)/vendors/\(vendorId)/stripe/status") else {
            completion(.failure(P2PAPIError.invalidURL)); return
        }
        var request = URLRequest(url: url)
        if let token = vendorToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        secureSession.dataTask(with: request) { data, response, error in
            DispatchQueue.main.async {
                if let error = error { completion(.failure(error)); return }
                guard let data = data,
                      let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                    completion(.failure(P2PAPIError.serverError("Failed to load payout status"))); return
                }
                do {
                    let decoded = try JSONDecoder().decode(VendorStripeStatus.self, from: data)
                    completion(.success(decoded))
                } catch {
                    completion(.failure(error))
                }
            }
        }.resume()
    }

    /// POST /api/vendors/{id}/stripe/connect — create Stripe Connect Express account (idempotent)
    public func createVendorStripeAccount(
        vendorId: Int,
        completion: @escaping (Result<VendorStripeConnectResponse, Error>) -> Void
    ) {
        guard let url = URL(string: "\(baseURL)/vendors/\(vendorId)/stripe/connect") else {
            completion(.failure(P2PAPIError.invalidURL)); return
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let token = vendorToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        secureSession.dataTask(with: request) { data, response, error in
            DispatchQueue.main.async {
                if let error = error { completion(.failure(error)); return }
                guard let data = data,
                      let http = response as? HTTPURLResponse else {
                    completion(.failure(P2PAPIError.serverError("Invalid response from server"))); return
                }
                if http.statusCode >= 400 {
                    if let err = try? JSONDecoder().decode(P2PErrorResponse.self, from: data) {
                        completion(.failure(P2PAPIError.serverError(err.detail)))
                    } else {
                        completion(.failure(P2PAPIError.serverError("Payout setup failed (HTTP \(http.statusCode))")))
                    }
                    return
                }
                do {
                    let decoded = try JSONDecoder().decode(VendorStripeConnectResponse.self, from: data)
                    completion(.success(decoded))
                } catch {
                    completion(.failure(error))
                }
            }
        }.resume()
    }

    /// GET /api/vendors/{id}/stripe/onboarding-link — fetch a fresh Stripe-hosted onboarding URL
    public func getVendorStripeOnboardingLink(
        vendorId: Int,
        completion: @escaping (Result<VendorOnboardingLinkResponse, Error>) -> Void
    ) {
        guard let url = URL(string: "\(baseURL)/vendors/\(vendorId)/stripe/onboarding-link") else {
            completion(.failure(P2PAPIError.invalidURL)); return
        }
        var request = URLRequest(url: url)
        if let token = vendorToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        secureSession.dataTask(with: request) { data, response, error in
            DispatchQueue.main.async {
                if let error = error { completion(.failure(error)); return }
                guard let data = data,
                      let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                    completion(.failure(P2PAPIError.serverError("Failed to get onboarding link"))); return
                }
                do {
                    let decoded = try JSONDecoder().decode(VendorOnboardingLinkResponse.self, from: data)
                    completion(.success(decoded))
                } catch {
                    completion(.failure(error))
                }
            }
        }.resume()
    }

    /// Restaurant marks arrival at customer's delivery location (self-delivery)
    /// POST /api/erp/orders/{orderId}/vendor-arrived-at-delivery
    public func markArrivedAtDelivery(
        orderId: Int,
        completion: @escaping (Result<Bool, Error>) -> Void
    ) {
        guard let url = URL(string: "\(baseURL)/erp/orders/\(orderId)/vendor-arrived-at-delivery") else {
            completion(.failure(P2PAPIError.invalidURL))
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"

        if let token = vendorToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        secureSession.dataTask(with: request) { data, response, error in
            DispatchQueue.main.async {
                if let error = error {
                    completion(.failure(error))
                    return
                }

                guard let httpResponse = response as? HTTPURLResponse,
                      httpResponse.statusCode == 200 else {
                    completion(.failure(P2PAPIError.serverError("Failed to mark arrived at delivery")))
                    return
                }

                completion(.success(true))
            }
        }.resume()
    }

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

    /// Fetch available orders for delivery
    public func fetchAvailableDeliveryOrders(
        completion: @escaping (Result<[P2PDeliveryOrder], Error>) -> Void
    ) {
        let urlString = "\(baseURL)/erp/orders/available-for-delivery"
        #if DEBUG
        logger.info("=== fetchAvailableDeliveryOrders START ===")
        logger.info("URL: \(urlString)")
        #endif

        guard let url = URL(string: urlString) else {
            completion(.failure(P2PAPIError.invalidURL))
            return
        }

        guard let token = driverToken else {
            completion(.failure(P2PAPIError.serverError("Driver not logged in")))
            return
        }

        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        isLoading = true

        secureSession.dataTask(with: request) { [weak self] data, response, error in
            DispatchQueue.main.async {
                self?.isLoading = false

                if let error = error {
                    #if DEBUG
                    logger.error("fetchAvailableDeliveryOrders network error: \(error.localizedDescription)")
                    #endif
                    self?.error = error.localizedDescription
                    completion(.failure(error))
                    return
                }

                guard let data = data else {
                    #if DEBUG
                    logger.error("fetchAvailableDeliveryOrders: No data")
                    #endif
                    completion(.failure(P2PAPIError.noData))
                    return
                }

                #if DEBUG
                let httpStatus = (response as? HTTPURLResponse)?.statusCode ?? -1
                logger.info("fetchAvailableDeliveryOrders HTTP status: \(httpStatus)")
                logger.info("fetchAvailableDeliveryOrders data size: \(data.count) bytes")
                if let jsonString = String(data: data, encoding: .utf8) {
                    logger.info("fetchAvailableDeliveryOrders raw (first 500 chars): \(String(jsonString.prefix(500)))")
                }
                #endif

                do {
                    let response = try JSONDecoder().decode(P2PDeliveryOrdersResponse.self, from: data)
                    #if DEBUG
                    logger.info("fetchAvailableDeliveryOrders SUCCESS: \(response.orders.count) orders")
                    #endif
                    completion(.success(response.orders))
                } catch {
                    #if DEBUG
                    logger.error("fetchAvailableDeliveryOrders decode error: \(error)")
                    #endif
                    self?.error = "Failed to decode orders: \(error.localizedDescription)"
                    completion(.failure(error))
                }
            }
        }.resume()
    }

    /// Assign driver to an order (accept delivery)
    /// - Parameters:
    ///   - orderId: The order ID to accept
    ///   - driverEtaMinutes: Optional ETA in minutes for driver to reach restaurant
    ///   - completion: Completion handler with success/failure
    public func acceptDeliveryOrder(
        orderId: Int,
        driverEtaMinutes: Int? = nil,
        completion: @escaping (Result<Bool, Error>) -> Void
    ) {
        #if DEBUG
        logger.info("=== acceptDeliveryOrder START ===")
        logger.info("orderId: \(orderId)")
        logger.info("currentDriverId: \(String(describing: self.currentDriverId))")
        logger.info("driverToken exists: \(self.driverToken != nil)")
        #endif

        guard let token = driverToken else {
            #if DEBUG
            logger.error("acceptDeliveryOrder FAILED: driverToken is nil")
            #endif
            completion(.failure(P2PAPIError.serverError("Driver not logged in")))
            return
        }

        guard let driverId = currentDriverId else {
            #if DEBUG
            logger.error("acceptDeliveryOrder FAILED: currentDriverId is nil")
            #endif
            completion(.failure(P2PAPIError.serverError("Driver ID not available")))
            return
        }

        let urlString = "\(baseURL)/erp/orders/\(orderId)/assign-driver"
        #if DEBUG
        logger.info("acceptDeliveryOrder URL: \(urlString)")
        #endif

        guard let url = URL(string: urlString) else {
            completion(.failure(P2PAPIError.invalidURL))
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        var body: [String: Any] = ["driver_id": driverId]
        if let eta = driverEtaMinutes {
            body["driver_eta_minutes"] = eta
        }
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        #if DEBUG
        logger.info("acceptDeliveryOrder request body: \(body)")
        #endif

        secureSession.dataTask(with: request) { [weak self] data, response, error in
            DispatchQueue.main.async {
                #if DEBUG
                let httpStatus = (response as? HTTPURLResponse)?.statusCode ?? -1
                logger.info("acceptDeliveryOrder HTTP status: \(httpStatus)")
                if let data = data, let jsonString = String(data: data, encoding: .utf8) {
                    logger.info("acceptDeliveryOrder response: \(String(jsonString.prefix(500)))")
                }
                #endif

                if let error = error {
                    #if DEBUG
                    logger.error("acceptDeliveryOrder network error: \(error.localizedDescription)")
                    #endif
                    self?.error = error.localizedDescription
                    completion(.failure(error))
                    return
                }

                if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode >= 400 {
                    #if DEBUG
                    logger.error("acceptDeliveryOrder HTTP error: \(httpResponse.statusCode)")
                    #endif
                    if let data = data,
                       let errorResponse = try? JSONDecoder().decode(P2PErrorResponse.self, from: data) {
                        completion(.failure(P2PAPIError.serverError(errorResponse.detail)))
                    } else {
                        completion(.failure(P2PAPIError.serverError("Failed to accept order")))
                    }
                    return
                }

                #if DEBUG
                logger.info("acceptDeliveryOrder SUCCESS for order \(orderId)")
                #endif
                completion(.success(true))
            }
        }.resume()
    }

    /// Mark order as picked up
    public func markOrderPickedUp(
        orderId: Int,
        completion: @escaping (Result<Bool, Error>) -> Void
    ) {
        #if DEBUG
        logger.info("=== markOrderPickedUp START ===")
        logger.info("orderId: \(orderId)")
        logger.info("driverToken exists: \(self.driverToken != nil)")
        #endif

        guard let token = driverToken else {
            #if DEBUG
            logger.error("markOrderPickedUp FAILED: driverToken is nil")
            #endif
            completion(.failure(P2PAPIError.serverError("Driver not logged in")))
            return
        }

        let urlString = "\(baseURL)/erp/orders/\(orderId)/picked-up"
        #if DEBUG
        logger.info("markOrderPickedUp URL: \(urlString)")
        #endif

        guard let url = URL(string: urlString) else {
            completion(.failure(P2PAPIError.invalidURL))
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        secureSession.dataTask(with: request) { [weak self] data, response, error in
            DispatchQueue.main.async {
                #if DEBUG
                let httpStatus = (response as? HTTPURLResponse)?.statusCode ?? -1
                logger.info("markOrderPickedUp HTTP status: \(httpStatus)")
                if let data = data, let jsonString = String(data: data, encoding: .utf8) {
                    logger.info("markOrderPickedUp response: \(String(jsonString.prefix(500)))")
                }
                #endif

                if let error = error {
                    #if DEBUG
                    logger.error("markOrderPickedUp network error: \(error.localizedDescription)")
                    #endif
                    self?.error = error.localizedDescription
                    completion(.failure(error))
                    return
                }

                if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode >= 400 {
                    #if DEBUG
                    logger.error("markOrderPickedUp HTTP error: \(httpResponse.statusCode)")
                    #endif
                    if let data = data,
                       let errorResponse = try? JSONDecoder().decode(P2PErrorResponse.self, from: data) {
                        completion(.failure(P2PAPIError.serverError(errorResponse.detail)))
                    } else {
                        completion(.failure(P2PAPIError.serverError("Failed to mark as picked up")))
                    }
                    return
                }

                #if DEBUG
                logger.info("markOrderPickedUp SUCCESS for order \(orderId)")
                #endif
                completion(.success(true))
            }
        }.resume()
    }

    /// Mark order as delivered
    public func markOrderDelivered(
        orderId: Int,
        completion: @escaping (Result<Bool, Error>) -> Void
    ) {
        guard let token = driverToken else {
            completion(.failure(P2PAPIError.serverError("Driver not logged in")))
            return
        }

        guard let url = URL(string: "\(baseURL)/erp/orders/\(orderId)/delivered") else {
            completion(.failure(P2PAPIError.invalidURL))
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

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
                        completion(.failure(P2PAPIError.serverError("Failed to mark as delivered")))
                    }
                    return
                }

                completion(.success(true))
            }
        }.resume()
    }

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

    /// Fetch driver's active deliveries
    public func fetchMyDeliveries(
        completion: @escaping (Result<[P2PDeliveryOrder], Error>) -> Void
    ) {
        // LOGGING: Check driver ID
        #if DEBUG
        logger.info("=== fetchMyDeliveries START ===")
        logger.info("currentDriverId from UserDefaults: \(String(describing: self.currentDriverId))")
        logger.info("driverToken exists: \(self.driverToken != nil)")
        if let token = driverToken {
            logger.info("driverToken prefix: \(String(token.prefix(20)))...")
        }
        #endif

        guard let driverId = currentDriverId else {
            #if DEBUG
            logger.error("fetchMyDeliveries FAILED: currentDriverId is nil")
            logger.info("UserDefaults driverId key value: \(String(describing: UserDefaults.standard.object(forKey: UserDefaultsKey.driverId)))")
            #endif
            completion(.failure(P2PAPIError.serverError("Driver not logged in")))
            return
        }

        guard let token = driverToken else {
            #if DEBUG
            logger.error("fetchMyDeliveries FAILED: driverToken is nil")
            #endif
            completion(.failure(P2PAPIError.serverError("Driver not logged in")))
            return
        }

        let urlString = "\(baseURL)/erp/orders/driver/\(driverId)/active"
        #if DEBUG
        logger.info("fetchMyDeliveries URL: \(urlString)")
        #endif

        guard let url = URL(string: urlString) else {
            completion(.failure(P2PAPIError.invalidURL))
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        secureSession.dataTask(with: request) { [weak self] data, response, error in
            DispatchQueue.main.async {
                if let error = error {
                    #if DEBUG
                    logger.error("fetchMyDeliveries network error: \(error.localizedDescription)")
                    #endif
                    self?.error = error.localizedDescription
                    completion(.failure(error))
                    return
                }

                guard let data = data else {
                    #if DEBUG
                    logger.error("fetchMyDeliveries: No data returned")
                    #endif
                    completion(.failure(P2PAPIError.noData))
                    return
                }

                #if DEBUG
                let httpStatus = (response as? HTTPURLResponse)?.statusCode ?? -1
                logger.info("fetchMyDeliveries HTTP status: \(httpStatus)")
                logger.info("fetchMyDeliveries data size: \(data.count) bytes")
                if let jsonString = String(data: data, encoding: .utf8) {
                    logger.info("fetchMyDeliveries raw response (first 1000 chars): \(String(jsonString.prefix(1000)))")
                }
                #endif

                // Check for HTTP errors
                if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode >= 400 {
                    #if DEBUG
                    if let jsonString = String(data: data, encoding: .utf8) {
                        logger.error("fetchMyDeliveries HTTP \(httpResponse.statusCode): \(jsonString)")
                    }
                    #endif
                    if let errorJson = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                       let detail = errorJson["detail"] as? String {
                        completion(.failure(P2PAPIError.serverError(detail)))
                    } else {
                        completion(.failure(P2PAPIError.serverError("HTTP \(httpResponse.statusCode)")))
                    }
                    return
                }

                do {
                    let response = try JSONDecoder().decode(P2PDeliveryOrdersResponse.self, from: data)
                    #if DEBUG
                    logger.info("fetchMyDeliveries SUCCESS: \(response.orders.count) orders decoded")
                    for (index, order) in response.orders.prefix(3).enumerated() {
                        logger.info("  Order[\(index)]: id=\(order.id), status=\(order.status ?? "nil")")
                    }
                    #endif
                    completion(.success(response.orders))
                } catch {
                    #if DEBUG
                    logger.error("fetchMyDeliveries decode error: \(error)")
                    if let jsonString = String(data: data, encoding: .utf8) {
                        logger.info("Raw response: \(jsonString.prefix(500))")
                    }
                    #endif
                    // Return failure on decode errors so ViewModel can preserve existing data
                    completion(.failure(P2PAPIError.serverError("Failed to parse delivery orders: \(error.localizedDescription)")))
                }
            }
        }.resume()
    }

    /// Complete a delivery — returns DeliveryCompletionResponse which may require a proof photo
    public func completeDelivery(
        orderId: Int,
        completion: @escaping (Result<DeliveryCompletionResponse, Error>) -> Void
    ) {
        guard let token = driverToken ?? vendorToken else {
            completion(.failure(P2PAPIError.serverError("Not logged in")))
            return
        }

        guard let url = URL(string: "\(baseURL)/erp/orders/\(orderId)/complete-delivery") else {
            completion(.failure(P2PAPIError.invalidURL))
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        secureSession.dataTask(with: request) { data, response, error in
            DispatchQueue.main.async {
                if let error = error {
                    completion(.failure(error))
                    return
                }

                guard let data = data,
                      let httpResponse = response as? HTTPURLResponse,
                      httpResponse.statusCode == 200 else {
                    completion(.failure(P2PAPIError.serverError("Failed to complete delivery")))
                    return
                }

                do {
                    let decoded = try JSONDecoder().decode(DeliveryCompletionResponse.self, from: data)
                    completion(.success(decoded))
                } catch {
                    // Fallback: if decoding fails but status was 200, treat as completed
                    completion(.success(DeliveryCompletionResponse(success: true, requiresPhoto: false)))
                }
            }
        }.resume()
    }

    /// Upload delivery proof photo — triggers order completion after upload
    public func uploadDeliveryPhoto(
        orderId: Int,
        imageData: Data,
        completion: @escaping (Result<DeliveryCompletionResponse, Error>) -> Void
    ) {
        guard let token = driverToken ?? vendorToken else {
            completion(.failure(P2PAPIError.serverError("Not logged in")))
            return
        }

        guard let url = URL(string: "\(baseURL)/erp/orders/\(orderId)/delivery-photo") else {
            completion(.failure(P2PAPIError.invalidURL))
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let boundary = UUID().uuidString
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        var body = Data()

        // Add file
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"delivery_proof.jpg\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: image/jpeg\r\n\r\n".data(using: .utf8)!)
        body.append(imageData)
        body.append("\r\n".data(using: .utf8)!)
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)

        request.httpBody = body

        secureSession.dataTask(with: request) { data, response, error in
            DispatchQueue.main.async {
                if let error = error {
                    completion(.failure(error))
                    return
                }

                guard let data = data,
                      let httpResponse = response as? HTTPURLResponse,
                      httpResponse.statusCode == 200 else {
                    let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
                    completion(.failure(P2PAPIError.serverError("Photo upload failed (HTTP \(statusCode))")))
                    return
                }

                do {
                    let decoded = try JSONDecoder().decode(DeliveryCompletionResponse.self, from: data)
                    completion(.success(decoded))
                } catch {
                    completion(.success(DeliveryCompletionResponse(success: true, requiresPhoto: false)))
                }
            }
        }.resume()
    }

    /// Cancel delivery assignment (driver unassigns from order)
    public func cancelDeliveryAssignment(
        orderId: Int,
        completion: @escaping (Result<Bool, Error>) -> Void
    ) {
        guard let token = driverToken else {
            completion(.failure(P2PAPIError.serverError("Driver not logged in")))
            return
        }

        guard let url = URL(string: "\(baseURL)/erp/orders/\(orderId)/unassign-driver") else {
            completion(.failure(P2PAPIError.invalidURL))
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        secureSession.dataTask(with: request) { data, response, error in
            DispatchQueue.main.async {
                if let error = error {
                    completion(.failure(error))
                    return
                }

                if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 {
                    completion(.success(true))
                } else {
                    completion(.failure(P2PAPIError.serverError("Failed to cancel delivery")))
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

    // MARK: - Founding Membership APIs

    /// Fetch founding-member eligibility/status for the signed-in user.
    /// Customer: GET /api/founding/status · Driver: GET /api/founding/driver/status
    public func getFoundingStatus(
        isDriver: Bool,
        state: String? = nil,
        completion: @escaping (Result<FoundingStatus, Error>) -> Void
    ) {
        let path = isDriver ? "/founding/driver/status" : "/founding/status"
        var urlString = "\(baseURL)\(path)"
        if let state = state, !state.isEmpty {
            urlString += "?state=\(state)"
        }
        guard let url = URL(string: urlString) else {
            completion(.failure(P2PAPIError.invalidURL))
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let token = isDriver ? driverToken : customerToken {
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
                    let status = try JSONDecoder().decode(FoundingStatus.self, from: data)
                    completion(.success(status))
                } catch {
                    completion(.failure(error))
                }
            }
        }.resume()
    }

    /// Join the founding-member program ($100 lifetime fee lock).
    /// Customer: POST /api/founding/join · Driver: POST /api/founding/driver/join
    /// `paymentMethodId` is the Stripe PaymentMethod id collected via the app's existing
    /// Stripe mechanism. Demo accounts bypass the charge server-side (id may be nil).
    public func joinFounding(
        isDriver: Bool,
        state: String,
        paymentMethodId: String?,
        completion: @escaping (Result<FoundingJoinResult, Error>) -> Void
    ) {
        let path = isDriver ? "/founding/driver/join" : "/founding/join"
        guard let url = URL(string: "\(baseURL)\(path)") else {
            completion(.failure(P2PAPIError.invalidURL))
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let token = isDriver ? driverToken : customerToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        var body: [String: Any] = ["state": state]
        if let paymentMethodId = paymentMethodId {
            body["payment_method_id"] = paymentMethodId
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
                    let result = try JSONDecoder().decode(FoundingJoinResult.self, from: data)
                    completion(.success(result))
                } catch {
                    completion(.failure(error))
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

    /// Delete vendor/restaurant account and all associated data
    /// Required by Apple App Store Guidelines for account-based apps
    public func deleteVendorAccount(
        vendorId: Int,
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        guard let url = URL(string: "\(baseURL)/vendors/\(vendorId)") else {
            completion(.failure(P2PAPIError.invalidURL))
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"

        if let token = vendorToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        secureSession.dataTask(with: request) { data, response, error in
            if let error = error {
                DispatchQueue.main.async { completion(.failure(error)) }
                return
            }

            if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode < 300 {
                // Clear vendor session from secure storage
                SecureStorage.shared.clearAuthTokens(type: .vendor)
                DispatchQueue.main.async { completion(.success(())) }
            } else {
                DispatchQueue.main.async {
                    completion(.failure(P2PAPIError.serverError("Failed to delete vendor account")))
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

    enum CodingKeys: String, CodingKey {
        case id
        case rideRequestId = "ride_request_id"
        case senderType = "sender_type"
        case senderId = "sender_id"
        case message
        case createdAt = "created_at"
    }
}

/// Chat message model for food delivery order chat
/// Backend response: { "id", "order_id", "sender_type", "sender_id", "sender_name", "message", "created_at" }
public struct OrderChatMessage: Identifiable, Codable, Sendable {
    public let id: Int
    public let orderId: Int
    public let senderType: String // "customer" or "driver"
    public let senderId: Int
    public let senderName: String?
    public let message: String
    public let createdAt: String?

    public var isFromDriver: Bool {
        return senderType == "driver"
    }

    enum CodingKeys: String, CodingKey {
        case id
        case orderId = "order_id"
        case senderType = "sender_type"
        case senderId = "sender_id"
        case senderName = "sender_name"
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

/// Fare breakdown from production API
public struct RideFareBreakdown: Codable {
    public let baseFare: Double
    public let distanceCost: Double
    public let timeCost: Double
    public let timeAdjustment: Double?
    public let timeAdjustmentLabel: String?
    public let longDistanceDiscount: Double?

    enum CodingKeys: String, CodingKey {
        case baseFare = "base_fare"
        case distanceCost = "distance_cost"
        case timeCost = "time_cost"
        case timeAdjustment = "time_adjustment"
        case timeAdjustmentLabel = "time_adjustment_label"
        case longDistanceDiscount = "long_distance_discount"
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

public struct P2PLoginResponse: Codable {
    public let accessToken: String
    public let tokenType: String
    public let user: P2PUser

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case tokenType = "token_type"
        case user
    }
}

public struct P2PUser: Codable {
    public let id: Int
    public let email: String
    public let fullName: String
    public let role: String
    public let vendorId: Int?

    enum CodingKeys: String, CodingKey {
        case id
        case email
        case fullName = "full_name"
        case role
        case vendorId = "vendor_id"
    }
}

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

/// Response from /api/vendors/public registration endpoint
/// Matches Android VendorRegistrationResponse and backend VendorResponse
public struct P2PVendorRegistrationResponse: Codable {
    public let id: Int
    public let vendorId: Int  // Changed to Int to match backend and Android
    public let restaurantName: String
    public let contactEmail: String
    public let status: String
    public let message: String?

    enum CodingKeys: String, CodingKey {
        case id
        case vendorId = "vendor_id"
        case restaurantName = "restaurant_name"
        case contactEmail = "contact_email"
        case status
        case message
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

public struct P2PRestaurantsResponse: Decodable {
    public let success: Bool
    public let count: Int
    public let restaurants: [P2PRestaurant]

    enum CodingKeys: String, CodingKey {
        case success, count, restaurants
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        success = try container.decodeIfPresent(Bool.self, forKey: .success) ?? true
        count = try container.decodeIfPresent(Int.self, forKey: .count) ?? 0
        restaurants = try container.decodeIfPresent([P2PRestaurant].self, forKey: .restaurants) ?? []
    }
}

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

public struct P2PVendorProfileResponse: Codable {
    public let success: Bool
    public let restaurant: P2PVendorProfile
}

public struct P2PVendorProfile: Codable {
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
    public let rating: Double
    public let reviewsCount: Int

    enum CodingKeys: String, CodingKey {
        case id
        case vendorId = "vendor_id"
        case name
        case cuisineType = "cuisine_type"
        case address
        case location
        case contact
        case operatingHours = "operating_hours"
        case deliveryAvailable = "delivery_available"
        case pickupAvailable = "pickup_available"
        case averagePrepTime = "average_prep_time"
        case rating
        case reviewsCount = "reviews_count"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(Int.self, forKey: .id)
        vendorId = try container.decode(String.self, forKey: .vendorId)
        name = try container.decode(String.self, forKey: .name)
        cuisineType = try container.decodeIfPresent(String.self, forKey: .cuisineType)
        address = try container.decode(P2PAddress.self, forKey: .address)
        location = try container.decode(P2PLocation.self, forKey: .location)
        contact = try container.decode(P2PContact.self, forKey: .contact)
        operatingHours = try container.decodeIfPresent(String.self, forKey: .operatingHours)
        deliveryAvailable = try container.decodeIfPresent(Bool.self, forKey: .deliveryAvailable) ?? true
        pickupAvailable = try container.decodeIfPresent(Bool.self, forKey: .pickupAvailable) ?? true
        averagePrepTime = try container.decodeIfPresent(Int.self, forKey: .averagePrepTime)
        rating = try container.decodeIfPresent(Double.self, forKey: .rating) ?? 4.5
        reviewsCount = try container.decodeIfPresent(Int.self, forKey: .reviewsCount) ?? 0
    }
}

// MARK: - Vendor Settings PATCH API

extension P2PAPIService {
    /// Patch vendor settings (operating hours, notification preferences, etc.)
    /// - Parameters:
    ///   - vendorId: The vendor ID
    ///   - updates: Dictionary of fields to update
    ///   - completion: Result with success or error
    public func patchVendorSettings(
        vendorId: Int,
        updates: [String: Any],
        completion: @escaping (Result<Bool, Error>) -> Void
    ) {
        guard let url = URL(string: "\(baseURL)/vendors/\(vendorId)") else {
            completion(.failure(P2PAPIError.invalidURL))
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "PATCH"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        if let token = vendorToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: updates)
        } catch {
            completion(.failure(error))
            return
        }

        secureSession.dataTask(with: request) { data, response, error in
            DispatchQueue.main.async {
                if let error = error {
                    completion(.failure(error))
                    return
                }

                if let httpResponse = response as? HTTPURLResponse {
                    if httpResponse.statusCode < 400 {
                        completion(.success(true))
                    } else {
                        if let data = data,
                           let errorResponse = try? JSONDecoder().decode(P2PErrorResponse.self, from: data) {
                            completion(.failure(P2PAPIError.serverError(errorResponse.detail)))
                        } else {
                            completion(.failure(P2PAPIError.serverError("Failed to update vendor settings")))
                        }
                    }
                } else {
                    completion(.failure(P2PAPIError.serverError("Invalid response")))
                }
            }
        }.resume()
    }
}

// MARK: - Vendor Documents API

public struct P2PVendorDocumentsResponse: Codable {
    public let documents: [P2PVendorDocument]
    public let count: Int
}

public struct P2PVendorDocument: Codable, Identifiable {
    public let id: Int
    public let documentType: String
    public let fileName: String?
    public let fileUrl: String?
    public let uploadedAt: String?
    public let status: String
    public let adminNotes: String?

    enum CodingKeys: String, CodingKey {
        case id
        case documentType = "document_type"
        case fileName = "file_name"
        case fileUrl = "file_url"
        case uploadedAt = "uploaded_at"
        case status
        case adminNotes = "admin_notes"
    }
}

public struct P2PDocumentUploadResponse: Codable {
    public let message: String
    public let filePath: String?

    enum CodingKeys: String, CodingKey {
        case message
        case filePath = "file_path"
    }
}

extension P2PAPIService {

    /// Get documents for a vendor
    /// - Parameters:
    ///   - vendorId: The vendor ID
    ///   - completion: Completion handler with result
    public func getVendorDocuments(
        vendorId: Int,
        completion: @escaping (Result<[P2PVendorDocument], Error>) -> Void
    ) {
        guard let url = URL(string: "\(baseURL)/vendors/\(vendorId)/documents") else {
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
                    let response = try JSONDecoder().decode(P2PVendorDocumentsResponse.self, from: data)
                    completion(.success(response.documents))
                } catch {
                    completion(.failure(error))
                }
            }
        }.resume()
    }

    /// Upload a document for a vendor to the backend API
    /// - Parameters:
    ///   - vendorId: The vendor ID
    ///   - imageData: The document image data
    ///   - documentType: Type of document (w9_form, liability_insurance, health_permit, food_handler, business_license)
    ///   - completion: Completion handler with result
    public func uploadVendorDocument(
        vendorId: Int,
        imageData: Data,
        documentType: String,
        completion: @escaping (Result<P2PDocumentUploadResponse, Error>) -> Void
    ) {
        guard let url = URL(string: "\(baseURL)/vendors/\(vendorId)/documents") else {
            completion(.failure(P2PAPIError.invalidURL))
            return
        }

        // Create multipart form data
        let boundary = UUID().uuidString
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        if let token = vendorToken ?? customerToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        var body = Data()

        // Add document_type field
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"document_type\"\r\n\r\n".data(using: .utf8)!)
        body.append("\(documentType)\r\n".data(using: .utf8)!)

        // Add file field
        let filename = "\(documentType)_\(UUID().uuidString.prefix(8)).jpg"
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"\(filename)\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: image/jpeg\r\n\r\n".data(using: .utf8)!)
        body.append(imageData)
        body.append("\r\n".data(using: .utf8)!)

        // End boundary
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)

        request.httpBody = body

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
                        completion(.failure(P2PAPIError.serverError("Failed to upload document")))
                    }
                    return
                }

                do {
                    let response = try JSONDecoder().decode(P2PDocumentUploadResponse.self, from: data)
                    completion(.success(response))
                } catch {
                    // Even if decode fails, if we got a success status, return a basic response
                    if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode < 300 {
                        completion(.success(P2PDocumentUploadResponse(message: "Document uploaded successfully", filePath: nil)))
                    } else {
                        completion(.failure(error))
                    }
                }
            }
        }.resume()
    }

    /// Delete a document for a vendor
    /// - Parameters:
    ///   - vendorId: The vendor ID
    ///   - documentId: The document ID to delete
    ///   - completion: Completion handler with result
    public func deleteVendorDocument(
        vendorId: Int,
        documentId: Int,
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        guard let url = URL(string: "\(baseURL)/vendors/\(vendorId)/documents/\(documentId)") else {
            completion(.failure(P2PAPIError.invalidURL))
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"

        if let token = vendorToken ?? customerToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        secureSession.dataTask(with: request) { data, response, error in
            DispatchQueue.main.async {
                if let error = error {
                    completion(.failure(error))
                    return
                }

                if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode >= 400 {
                    completion(.failure(P2PAPIError.serverError("Failed to delete document")))
                    return
                }

                completion(.success(()))
            }
        }.resume()
    }
}

public struct P2PRestaurantDetailResponse: Codable {
    public let success: Bool
    public let restaurant: P2PRestaurantInfo
    public let menu: [String: [P2PDetailMenuItem]]

    public func toDetail() -> P2PRestaurantDetail {
        P2PRestaurantDetail(restaurant: restaurant, menu: menu)
    }
}

/// Menu item structure specifically for restaurant detail response
/// (Uses 'name' key instead of 'item_name')
public struct P2PDetailMenuItem: Identifiable, Codable {
    public let id: Int
    public let name: String
    public let description: String?
    public let price: Double
    public let imageUrl: String?
    public let isVegetarian: Bool
    public let isVegan: Bool
    public let isGlutenFree: Bool
    public let isSpicy: Bool
    public let spiceLevel: Int
    public let prepTime: Int?
    public let calories: Int?
    public let inStock: Bool
    public let customizations: [P2PMenuItemCustomization]?
    public let isBestseller: Bool
    public let isCombo: Bool
    public let comboItems: [ComboItemInfo]?
    public let comboSavings: Double?

    enum CodingKeys: String, CodingKey {
        case id, name, description, price, customizations
        case imageUrl = "image_url"
        case isVegetarian = "is_vegetarian"
        case isVegan = "is_vegan"
        case isGlutenFree = "is_gluten_free"
        case isSpicy = "is_spicy"
        case spiceLevel = "spice_level"
        case prepTime = "prep_time"
        case calories
        case inStock = "in_stock"
        case isBestseller = "is_bestseller"
        case isCombo = "is_combo"
        case comboItems = "combo_items"
        case comboSavings = "combo_savings"
    }

    /// Custom decoder with safe defaults to prevent crashes when API omits optional fields
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(Int.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        description = try container.decodeIfPresent(String.self, forKey: .description)
        price = try container.decode(Double.self, forKey: .price)
        imageUrl = try container.decodeIfPresent(String.self, forKey: .imageUrl)
        // Safe defaults for boolean fields
        isVegetarian = try container.decodeIfPresent(Bool.self, forKey: .isVegetarian) ?? false
        isVegan = try container.decodeIfPresent(Bool.self, forKey: .isVegan) ?? false
        isGlutenFree = try container.decodeIfPresent(Bool.self, forKey: .isGlutenFree) ?? false
        isSpicy = try container.decodeIfPresent(Bool.self, forKey: .isSpicy) ?? false
        spiceLevel = try container.decodeIfPresent(Int.self, forKey: .spiceLevel) ?? 0
        prepTime = try container.decodeIfPresent(Int.self, forKey: .prepTime)
        calories = try container.decodeIfPresent(Int.self, forKey: .calories)
        inStock = try container.decodeIfPresent(Bool.self, forKey: .inStock) ?? true
        customizations = try container.decodeIfPresent([P2PMenuItemCustomization].self, forKey: .customizations)
        isBestseller = try container.decodeIfPresent(Bool.self, forKey: .isBestseller) ?? false
        isCombo = try container.decodeIfPresent(Bool.self, forKey: .isCombo) ?? false
        comboItems = try container.decodeIfPresent([ComboItemInfo].self, forKey: .comboItems)
        comboSavings = try container.decodeIfPresent(Double.self, forKey: .comboSavings)
    }
}

public struct P2PRestaurantDetail {
    public let restaurant: P2PRestaurantInfo
    public let menu: [String: [P2PDetailMenuItem]]

    public var menuCategories: [String] {
        Array(menu.keys).sorted()
    }

    /// Get all menu items with their category included
    public var allMenuItemsWithCategory: [(item: P2PDetailMenuItem, category: String)] {
        menu.flatMap { category, items in
            items.map { (item: $0, category: category) }
        }
    }
}

public struct P2PRestaurantInfo: Codable {
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
    public let rating: Double
    public let reviewsCount: Int

    enum CodingKeys: String, CodingKey {
        case id
        case vendorId = "vendor_id"
        case name
        case cuisineType = "cuisine_type"
        case address
        case location
        case contact
        case operatingHours = "operating_hours"
        case deliveryAvailable = "delivery_available"
        case pickupAvailable = "pickup_available"
        case averagePrepTime = "average_prep_time"
        case rating
        case reviewsCount = "reviews_count"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(Int.self, forKey: .id)
        vendorId = try container.decode(String.self, forKey: .vendorId)
        name = try container.decode(String.self, forKey: .name)
        cuisineType = try container.decodeIfPresent(String.self, forKey: .cuisineType)
        address = try container.decode(P2PAddress.self, forKey: .address)
        location = try container.decode(P2PLocation.self, forKey: .location)
        contact = try container.decode(P2PContact.self, forKey: .contact)
        operatingHours = try container.decodeIfPresent(String.self, forKey: .operatingHours)
        deliveryAvailable = try container.decodeIfPresent(Bool.self, forKey: .deliveryAvailable) ?? true
        pickupAvailable = try container.decodeIfPresent(Bool.self, forKey: .pickupAvailable) ?? true
        averagePrepTime = try container.decodeIfPresent(Int.self, forKey: .averagePrepTime)
        rating = try container.decodeIfPresent(Double.self, forKey: .rating) ?? 4.5
        reviewsCount = try container.decodeIfPresent(Int.self, forKey: .reviewsCount) ?? 0
    }
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

public struct P2PMenuItem: Identifiable, Codable {
    public let id: Int
    public let name: String
    public let description: String?
    public let category: String?
    public let price: Double
    public let imageUrl: String?
    public let isVegetarian: Bool
    public let isVegan: Bool
    public let isGlutenFree: Bool
    public let isSpicy: Bool
    public let spiceLevel: Int
    public let prepTime: Int?
    public let calories: Int?
    public let inStock: Bool
    public let customizations: [P2PMenuItemCustomization]?
    public let isBestseller: Bool
    public let isCombo: Bool
    public let comboItems: [ComboItemInfo]?
    public let comboSavings: Double?

    enum CodingKeys: String, CodingKey {
        case id
        case name = "item_name"
        case description, category, price
        case imageUrl = "image_url"
        case isVegetarian = "is_vegetarian"
        case isVegan = "is_vegan"
        case isGlutenFree = "is_gluten_free"
        case isSpicy = "is_spicy"
        case spiceLevel = "spice_level"
        case prepTime = "prep_time"
        case calories
        case inStock = "in_stock"
        case customizations
        case isBestseller = "is_bestseller"
        case isCombo = "is_combo"
        case comboItems = "combo_items"
        case comboSavings = "combo_savings"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(Int.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        description = try container.decodeIfPresent(String.self, forKey: .description)
        category = try container.decodeIfPresent(String.self, forKey: .category)
        price = try container.decode(Double.self, forKey: .price)
        imageUrl = try container.decodeIfPresent(String.self, forKey: .imageUrl)
        isVegetarian = try container.decodeIfPresent(Bool.self, forKey: .isVegetarian) ?? false
        isVegan = try container.decodeIfPresent(Bool.self, forKey: .isVegan) ?? false
        isGlutenFree = try container.decodeIfPresent(Bool.self, forKey: .isGlutenFree) ?? false
        isSpicy = try container.decodeIfPresent(Bool.self, forKey: .isSpicy) ?? false
        spiceLevel = try container.decodeIfPresent(Int.self, forKey: .spiceLevel) ?? 0
        prepTime = try container.decodeIfPresent(Int.self, forKey: .prepTime)
        calories = try container.decodeIfPresent(Int.self, forKey: .calories)
        inStock = try container.decodeIfPresent(Bool.self, forKey: .inStock) ?? true
        customizations = try container.decodeIfPresent([P2PMenuItemCustomization].self, forKey: .customizations)
        isBestseller = try container.decodeIfPresent(Bool.self, forKey: .isBestseller) ?? false
        isCombo = try container.decodeIfPresent(Bool.self, forKey: .isCombo) ?? false
        comboItems = try container.decodeIfPresent([ComboItemInfo].self, forKey: .comboItems)
        comboSavings = try container.decodeIfPresent(Double.self, forKey: .comboSavings)
    }
}

public struct P2PMenuResponse: Codable {
    public let success: Bool
    public let items: [P2PMenuItem]
}

public struct P2PMenuItemResponse: Codable {
    public let success: Bool
    public let item: P2PMenuItem
}

public struct P2PStockImageResponse: Codable {
    public let success: Bool
    public let message: String
    public let itemsUpdated: Int

    enum CodingKeys: String, CodingKey {
        case success, message
        case itemsUpdated = "items_updated"
    }
}

/// Menu item creation model (for Restaurant App)
public struct P2PMenuItemCreate: Codable {
    public let itemName: String
    public let description: String?
    public let category: String
    public let price: Double
    public let isAvailable: Bool
    public let isVegetarian: Bool
    public let isVegan: Bool
    public let isGlutenFree: Bool
    public let isSpicy: Bool
    public let spiceLevel: Int
    public let prepTime: Int?
    public let calories: Int?
    public let imageUrl: String?
    public let inStock: Bool
    public let dailyLimit: Int?
    public let isBestseller: Bool
    public let isCombo: Bool

    enum CodingKeys: String, CodingKey {
        case itemName = "item_name"
        case description, category, price
        case isAvailable = "is_available"
        case isVegetarian = "is_vegetarian"
        case isVegan = "is_vegan"
        case isGlutenFree = "is_gluten_free"
        case isSpicy = "is_spicy"
        case spiceLevel = "spice_level"
        case prepTime = "prep_time"
        case calories
        case imageUrl = "image_url"
        case inStock = "in_stock"
        case dailyLimit = "daily_limit"
        case isBestseller = "is_bestseller"
        case isCombo = "is_combo"
    }

    public init(
        itemName: String,
        description: String? = nil,
        category: String,
        price: Double,
        isAvailable: Bool = true,
        isVegetarian: Bool = false,
        isVegan: Bool = false,
        isGlutenFree: Bool = false,
        isSpicy: Bool = false,
        spiceLevel: Int = 0,
        prepTime: Int? = nil,
        calories: Int? = nil,
        imageUrl: String? = nil,
        inStock: Bool = true,
        dailyLimit: Int? = nil,
        isBestseller: Bool = false,
        isCombo: Bool = false
    ) {
        self.itemName = itemName
        self.description = description
        self.category = category
        self.price = price
        self.isAvailable = isAvailable
        self.isVegetarian = isVegetarian
        self.isVegan = isVegan
        self.isGlutenFree = isGlutenFree
        self.isSpicy = isSpicy
        self.spiceLevel = spiceLevel
        self.prepTime = prepTime
        self.calories = calories
        self.imageUrl = imageUrl
        self.inStock = inStock
        self.dailyLimit = dailyLimit
        self.isBestseller = isBestseller
        self.isCombo = isCombo
    }
}

/// Menu categories response model
public struct P2PMenuCategoriesResponse: Codable {
    public let success: Bool
    public let categories: [String]
}

// MARK: - Promotion Models

/// Promotion creation model
public struct P2PPromotionCreate: Codable {
    public let name: String
    public let description: String?
    public let type: String  // percentage, flat_amount, bogo, free_delivery, free_item, bundle
    public let value: Double
    public let maxDiscount: Double?
    public let minOrderAmount: Double?
    public let targetAudience: String?
    public let startDate: String?
    public let endDate: String?
    public let isRecurring: Bool
    public let usageLimit: Int?
    public let perCustomerLimit: Int
    public let pushToApp: Bool

    public init(
        name: String,
        description: String? = nil,
        type: String,
        value: Double,
        maxDiscount: Double? = nil,
        minOrderAmount: Double? = 0,
        targetAudience: String? = "all",
        startDate: String? = nil,
        endDate: String? = nil,
        isRecurring: Bool = false,
        usageLimit: Int? = nil,
        perCustomerLimit: Int = 1,
        pushToApp: Bool = true
    ) {
        self.name = name
        self.description = description
        self.type = type
        self.value = value
        self.maxDiscount = maxDiscount
        self.minOrderAmount = minOrderAmount
        self.targetAudience = targetAudience
        self.startDate = startDate
        self.endDate = endDate
        self.isRecurring = isRecurring
        self.usageLimit = usageLimit
        self.perCustomerLimit = perCustomerLimit
        self.pushToApp = pushToApp
    }
}

/// Promotion model
public struct P2PPromotion: Codable, Identifiable {
    public let id: Int
    public let promotionCode: String
    public let vendorId: Int
    public let name: String
    public let description: String?
    public let type: String
    public let value: Double
    public let maxDiscount: Double?
    public let minOrderAmount: Double?
    public let status: String
    public let startDate: String?
    public let endDate: String?
    public let usageCount: Int?
    public let totalDiscountGiven: Double?
}

/// Promotions list response
public struct P2PPromotionsResponse: Codable {
    public let success: Bool
    public let promotions: [P2PPromotion]
}

/// Promotion suggestion from AI
public struct P2PPromotionSuggestion: Codable, Identifiable {
    public var id: String { suggestionType }
    public let suggestionType: String
    public let name: String
    public let description: String
    public let expectedImpact: String?
    public let recommendedValue: Double?
}

/// Promotion suggestions response
public struct P2PPromotionSuggestionsResponse: Codable {
    public let success: Bool
    public let suggestions: [P2PPromotionSuggestion]
}

/// Promotion analytics
public struct P2PPromotionAnalytics: Codable {
    public let success: Bool
    public let vendorId: Int
    public let totalPromotions: Int
    public let activePromotions: Int
    public let totalRedemptions: Int
    public let totalDiscountGiven: Double
    public let averageOrderValueWithPromo: Double?
    public let conversionRate: Double?
}

// MARK: - AI Insights Models

/// Demand forecast data point
public struct P2PDemandForecast: Codable, Identifiable {
    public var id: String { hour }
    public let hour: String
    public let hour24: Int
    public let predicted: Int
    public let minOrders: Int
    public let maxOrders: Int

    enum CodingKeys: String, CodingKey {
        case hour
        case hour24 = "hour_24"
        case predicted
        case minOrders = "min_orders"
        case maxOrders = "max_orders"
    }

    public init(hour: String, hour24: Int, predicted: Int, minOrders: Int, maxOrders: Int) {
        self.hour = hour
        self.hour24 = hour24
        self.predicted = predicted
        self.minOrders = minOrders
        self.maxOrders = maxOrders
    }
}

/// Popular item analytics
public struct P2PPopularItem: Codable, Identifiable {
    public var id: String { name }
    public let name: String
    public let quantity: Int
    public let revenue: Double
}

/// Hourly distribution data
public struct P2PHourlyData: Codable, Identifiable {
    public var id: Int { hour24 }
    public let hour: String
    public let hour24: Int
    public let orders: Int
    public let revenue: Double
    public let avgOrder: Double

    enum CodingKeys: String, CodingKey {
        case hour
        case hour24 = "hour_24"
        case orders
        case revenue
        case avgOrder = "avg_order"
    }
}

/// Peak hours info
public struct P2PPeakInfo: Codable {
    public let time: String
    public let orders: Int
}

/// Staffing recommendation
public struct P2PStaffingRecommendation: Codable, Identifiable {
    public var id: String { timeSlot }
    public let timeSlot: String
    public let recommendedStaff: Int
    public let expectedOrders: Int
    public let ordersPerHour: Double

    enum CodingKeys: String, CodingKey {
        case timeSlot = "time_slot"
        case recommendedStaff = "recommended_staff"
        case expectedOrders = "expected_orders"
        case ordersPerHour = "orders_per_hour"
    }
}

/// AI recommendation
public struct P2PAIRecommendation: Codable, Identifiable {
    public var id: String { type + title }
    public let type: String
    public let icon: String
    public let title: String
    public let description: String
    public let impact: String
    public let priority: String

    public init(type: String, icon: String, title: String, description: String, impact: String, priority: String) {
        self.type = type
        self.icon = icon
        self.title = title
        self.description = description
        self.impact = impact
        self.priority = priority
    }
}

/// Complete AI Insights response
public struct P2PAIInsightsResponse: Codable {
    public let success: Bool
    public let vendorId: Int
    public let period: String
    public let generatedAt: String

    // Demand Forecast
    public let demandForecast: [P2PDemandForecast]
    public let estimatedOrdersNextHour: Int
    public let peakHour: String
    public let peakHourOrders: Int
    public let forecastConfidence: Double

    // Popular Items
    public let popularItems: [P2PPopularItem]

    // Hourly Distribution
    public let hourlyDistribution: [P2PHourlyData]

    // Performance Metrics
    public let totalOrders: Int
    public let totalRevenue: Double
    public let averageOrderValue: Double
    public let orderCompletionRate: Double
    public let averagePrepTimeMinutes: Int

    // Peak Hours
    public let lunchPeak: P2PPeakInfo
    public let dinnerPeak: P2PPeakInfo

    // Staffing
    public let staffingRecommendations: [P2PStaffingRecommendation]

    // Recommendations
    public let recommendations: [P2PAIRecommendation]

    enum CodingKeys: String, CodingKey {
        case success
        case vendorId = "vendor_id"
        case period
        case generatedAt = "generated_at"
        case demandForecast = "demand_forecast"
        case estimatedOrdersNextHour = "estimated_orders_next_hour"
        case peakHour = "peak_hour"
        case peakHourOrders = "peak_hour_orders"
        case forecastConfidence = "forecast_confidence"
        case popularItems = "popular_items"
        case hourlyDistribution = "hourly_distribution"
        case totalOrders = "total_orders"
        case totalRevenue = "total_revenue"
        case averageOrderValue = "average_order_value"
        case orderCompletionRate = "order_completion_rate"
        case averagePrepTimeMinutes = "average_prep_time_minutes"
        case lunchPeak = "lunch_peak"
        case dinnerPeak = "dinner_peak"
        case staffingRecommendations = "staffing_recommendations"
        case recommendations
    }
}

/// Customer-facing promotion with vendor name
public struct P2PCustomerPromotion: Codable, Identifiable {
    public let id: Int
    public let promotionCode: String
    public let vendorId: Int
    public let vendorName: String
    public let name: String
    public let description: String?
    public let type: String
    public let value: Double
    public let maxDiscount: Double?
    public let minOrderAmount: Double?
    public let targetAudience: String?
    public let startDate: String?
    public let endDate: String?
    public let usageCount: Int?
    public let usageLimit: Int?

    enum CodingKeys: String, CodingKey {
        case id
        case promotionCode = "promotion_code"
        case vendorId = "vendor_id"
        case vendorName = "vendor_name"
        case name, description, type, value
        case maxDiscount = "max_discount"
        case minOrderAmount = "min_order_amount"
        case targetAudience = "target_audience"
        case startDate = "start_date"
        case endDate = "end_date"
        case usageCount = "usage_count"
        case usageLimit = "usage_limit"
    }
}

/// Active promotions response for customers
public struct P2PActivePromotionsResponse: Codable {
    public let success: Bool
    public let promotions: [P2PCustomerPromotion]
    public let count: Int
}

/// Featured deal for homepage
public struct P2PFeaturedDeal: Codable, Identifiable {
    public let id: Int
    public let promotionCode: String
    public let vendorId: Int
    public let vendorName: String
    public let headline: String
    public let name: String
    public let description: String?
    public let type: String
    public let value: Double
    public let minOrderAmount: Double?
    public let endDate: String?

    enum CodingKeys: String, CodingKey {
        case id
        case promotionCode = "promotion_code"
        case vendorId = "vendor_id"
        case vendorName = "vendor_name"
        case headline, name, description, type, value
        case minOrderAmount = "min_order_amount"
        case endDate = "end_date"
    }
}

/// Featured deals response
public struct P2PFeaturedDealsResponse: Codable {
    public let success: Bool
    public let featured: [P2PFeaturedDeal]
    public let count: Int

    enum CodingKeys: String, CodingKey {
        case success, featured, count
    }

    public init(success: Bool, featured: [P2PFeaturedDeal], count: Int) {
        self.success = success
        self.featured = featured
        self.count = count
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        success = try container.decodeIfPresent(Bool.self, forKey: .success) ?? true
        featured = try container.decodeIfPresent([P2PFeaturedDeal].self, forKey: .featured) ?? []
        count = try container.decodeIfPresent(Int.self, forKey: .count) ?? 0
    }
}

public struct P2PVerificationStatus: Codable {
    public let success: Bool
    public let status: String
    public let discrepanciesCount: Int
    public let canActivate: Bool

    enum CodingKeys: String, CodingKey {
        case success, status
        case discrepanciesCount = "discrepancies_count"
        case canActivate = "can_activate"
    }
}

public struct P2PApprovalResponse: Codable {
    public let success: Bool
    public let message: String
}

// MARK: - Conversion Extensions

public extension P2PRestaurant {
    /// Convert to the shared Restaurant model for compatibility with existing code
    func toRestaurant() -> Restaurant {
        var restaurant = Restaurant(
            id: String(id),  // Use numeric ID so MenuViewModel can fetch from P2P
            name: name,
            cuisine: cuisineType ?? "General",
            rating: rating,
            deliveryTime: averagePrepTime.map { "\($0)-\($0 + 15) min" } ?? "30-45 min",
            imageUrl: imageUrl ?? previewImages.first ?? "",
            address: address.fullAddress,
            latitude: location.latitude ?? 0,
            longitude: location.longitude ?? 0,
            phone: contact.phone ?? ""
        )
        // Add deal info if restaurant has active promotion
        if let promo = activePromotion {
            restaurant.dealText = promo.dealText
            restaurant.promoCode = promo.code
        }
        return restaurant
    }
}

public extension P2PMenuItem {
    /// Convert to the shared MenuItem model for compatibility with existing code
    func toMenuItem() -> MenuItem {
        MenuItem(
            id: String(id),
            name: name,
            description: description ?? "",
            price: price,
            imageUrl: imageUrl ?? "",
            isAvailable: inStock,
            category: nil,
            isPopular: false,
            prepTime: prepTime ?? 15,
            calories: (calories ?? 0) > 0 ? calories : nil,
            dietaryTags: buildDietaryTags(),
            customizations: convertCustomizations()
        )
    }

    private func buildDietaryTags() -> [String] {
        var tags: [String] = []
        if isVegetarian { tags.append("vegetarian") }
        if isVegan { tags.append("vegan") }
        if isGlutenFree { tags.append("gluten-free") }
        if isSpicy { tags.append("spicy") }
        return tags
    }

    private func convertCustomizations() -> [MenuItemCustomization]? {
        guard let p2pCustomizations = customizations, !p2pCustomizations.isEmpty else {
            return nil
        }

        return p2pCustomizations.map { p2pCust in
            let options = p2pCust.options.map { opt in
                CustomizationOption(
                    name: opt.name,
                    price: opt.price,
                    isDefault: opt.isDefault,
                    isAvailable: opt.isAvailable
                )
            }

            return MenuItemCustomization(
                name: p2pCust.name,
                type: p2pCust.type == "multiple" ? .multiple : .single,
                required: p2pCust.required,
                minSelections: p2pCust.minSelections,
                maxSelections: p2pCust.maxSelections,
                options: options
            )
        }
    }
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

public struct DeliveryCompletionResponse: Codable {
    public let success: Bool
    public let requiresPhoto: Bool

    enum CodingKeys: String, CodingKey {
        case success
        case requiresPhoto = "requires_photo"
    }

    public init(success: Bool, requiresPhoto: Bool) {
        self.success = success
        self.requiresPhoto = requiresPhoto
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.success = try container.decodeIfPresent(Bool.self, forKey: .success) ?? true
        self.requiresPhoto = try container.decodeIfPresent(Bool.self, forKey: .requiresPhoto) ?? false
    }
}

// MARK: - Delivery Order Models

public struct P2PDeliveryOrdersResponse: Codable {
    public let success: Bool
    public let orders: [P2PDeliveryOrder]
}

/// Nested delivery address structure from API
public struct P2PDeliveryAddress: Codable {
    public let street: String?
    public let city: String?
    public let state: String?
    public let zip: String?

    public var fullAddress: String {
        [street, city, state, zip].compactMap { $0 }.joined(separator: ", ")
    }
}

public struct P2PDeliveryOrder: Identifiable, Codable {
    public var id: Int { orderId }
    public let orderId: Int
    public let orderNumber: String
    public let status: String?
    public let restaurantName: String
    public let restaurantAddress: String
    public let customerName: String?
    public let customerAddress: String?
    public let deliveryAddressObj: P2PDeliveryAddress?
    public let customerPhone: String?
    public let pickupLatitude: Double?
    public let pickupLongitude: Double?
    public let dropoffLatitude: Double?
    public let dropoffLongitude: Double?
    public let estimatedDistance: Double?
    public let estimatedDuration: Int?
    public let deliveryFee: Double
    public let tip: Double?
    public let totalEarnings: Double?
    public let createdAt: String
    public let assignedAt: String?
    public let pickedUpAt: String?
    public let deliveredAt: String?

    // ETA fields for early driver notification
    public let estimatedPrepMinutes: Int?
    public let estimatedReadyAt: String?
    public let minutesUntilReady: Int?
    public let isReady: Bool?

    // Delivery details
    public let deliveryInstructions: String?
    public let items: [[String: AnyCodable]]?
    public let itemsCount: Int?

    // Driver en-route fields (early driver acceptance)
    public let driverEnRoute: Bool?
    public let driverAcceptedAt: String?
    public let driverEtaToRestaurant: Int?
    public let driverEtaText: String?

    /// Computed property to get delivery address as string
    public var deliveryAddressString: String {
        if let addr = customerAddress, !addr.isEmpty {
            return addr
        }
        return deliveryAddressObj?.fullAddress ?? "Address not available"
    }

    enum CodingKeys: String, CodingKey {
        case orderId = "order_id"
        case orderNumber = "order_number"
        case status
        case restaurantName = "restaurant"
        case restaurantAddress = "pickup_address"
        case customerName = "customer_name"
        case customerAddress = "customer_address"
        case deliveryAddressObj = "delivery_address"
        case customerPhone = "customer_phone"
        case pickupLatitude = "pickup_latitude"
        case pickupLongitude = "pickup_longitude"
        case dropoffLatitude = "dropoff_latitude"
        case dropoffLongitude = "dropoff_longitude"
        case estimatedDistance = "estimated_distance"
        case estimatedDuration = "estimated_duration"
        case deliveryFee = "delivery_fee"
        case tip
        case totalEarnings = "total_earnings"
        case createdAt = "created_at"
        case assignedAt = "assigned_at"
        case pickedUpAt = "picked_up_at"
        case deliveredAt = "delivered_at"
        // Delivery details
        case deliveryInstructions = "delivery_instructions"
        case items
        case itemsCount = "items_count"
        // ETA fields
        case estimatedPrepMinutes = "estimated_prep_minutes"
        case estimatedReadyAt = "estimated_ready_at"
        case minutesUntilReady = "minutes_until_ready"
        case isReady = "is_ready"
        // Driver en-route fields
        case driverEnRoute = "driver_en_route"
        case driverAcceptedAt = "driver_accepted_at"
        case driverEtaToRestaurant = "driver_eta_to_restaurant"
        case driverEtaText = "driver_eta_text"
    }
}

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

// MARK: - Checkr / Founding Membership Models

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

/// Founding-member eligibility/status. Decoded leniently to tolerate backend field variations.
public struct FoundingStatus: Decodable {
    public let eligible: Bool
    public let isMember: Bool
    public let slotsRemaining: Int?
    public let slotsTotal: Int?
    public let state: String?
    public let feeAmount: Double
    public let benefitDescription: String?
    public let demo: Bool
    public let publishableKey: String?

    enum CodingKeys: String, CodingKey {
        case eligible
        case isMember = "is_member"
        case isFoundingMember = "is_founding_member"
        case slotsRemaining = "slots_remaining"
        case slotsTotal = "slots_total"
        case state
        case feeAmount = "fee_amount"
        case fee
        case benefit
        case benefitDescription = "benefit_description"
        case demo
        case publishableKey = "publishable_key"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        eligible = (try? c.decodeIfPresent(Bool.self, forKey: .eligible)).flatMap { $0 } ?? true
        let member1 = (try? c.decodeIfPresent(Bool.self, forKey: .isMember)).flatMap { $0 }
        let member2 = (try? c.decodeIfPresent(Bool.self, forKey: .isFoundingMember)).flatMap { $0 }
        isMember = member1 ?? member2 ?? false
        slotsRemaining = (try? c.decodeIfPresent(Int.self, forKey: .slotsRemaining)).flatMap { $0 }
        slotsTotal = (try? c.decodeIfPresent(Int.self, forKey: .slotsTotal)).flatMap { $0 }
        state = (try? c.decodeIfPresent(String.self, forKey: .state)).flatMap { $0 }
        let fee1 = (try? c.decodeIfPresent(Double.self, forKey: .feeAmount)).flatMap { $0 }
        let fee2 = (try? c.decodeIfPresent(Double.self, forKey: .fee)).flatMap { $0 }
        feeAmount = fee1 ?? fee2 ?? 100.0
        let b1 = (try? c.decodeIfPresent(String.self, forKey: .benefit)).flatMap { $0 }
        let b2 = (try? c.decodeIfPresent(String.self, forKey: .benefitDescription)).flatMap { $0 }
        benefitDescription = b1 ?? b2
        demo = (try? c.decodeIfPresent(Bool.self, forKey: .demo)).flatMap { $0 } ?? false
        publishableKey = (try? c.decodeIfPresent(String.self, forKey: .publishableKey)).flatMap { $0 }
    }
}

/// Result of POST /api/founding/join (or /api/founding/driver/join)
public struct FoundingJoinResult: Decodable {
    public let success: Bool
    public let message: String?
    public let isMember: Bool

    enum CodingKeys: String, CodingKey {
        case success
        case message
        case isMember = "is_member"
        case isFoundingMember = "is_founding_member"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        success = (try? c.decodeIfPresent(Bool.self, forKey: .success)).flatMap { $0 } ?? true
        message = (try? c.decodeIfPresent(String.self, forKey: .message)).flatMap { $0 }
        let member1 = (try? c.decodeIfPresent(Bool.self, forKey: .isMember)).flatMap { $0 }
        let member2 = (try? c.decodeIfPresent(Bool.self, forKey: .isFoundingMember)).flatMap { $0 }
        isMember = member1 ?? member2 ?? true
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

/// Response from promo code validation
public struct PromoCodeResponse: Codable {
    public let success: Bool
    public let promotionCode: String
    public let promotionName: String
    public let discountAmount: Double
    public let originalTotal: Double
    public let finalTotal: Double
    public let message: String

    enum CodingKeys: String, CodingKey {
        case success
        case promotionCode = "promotion_code"
        case promotionName = "promotion_name"
        case discountAmount = "discount_amount"
        case originalTotal = "original_total"
        case finalTotal = "final_total"
        case message
    }
}

/// Response from backend when creating an order
/// Contains the backend-generated order number for syncing across all apps
public struct P2PCreateOrderResponse: Codable {
    public let success: Bool
    public let orderId: Int
    public let orderNumber: String
    public let status: String
    public let subtotal: Double
    public let tax: Double
    public let serviceFee: Double?
    public let deliveryFee: Double
    public let tip: Double?
    public let platformFee: Double
    public let total: Double
    public let processedBy: String?
    public let restaurant: String?

    enum CodingKeys: String, CodingKey {
        case success
        case orderId = "order_id"
        case orderNumber = "order_number"
        case status
        case subtotal
        case tax
        case serviceFee = "service_fee"
        case deliveryFee = "delivery_fee"
        case tip
        case platformFee = "platform_fee"
        case total
        case processedBy = "processed_by"
        case restaurant
    }
}

/// Response from vendor orders endpoint
public struct P2PVendorOrdersResponse: Codable {
    public let success: Bool
    public let orders: [P2PVendorOrder]
}

/// Item in a vendor order
public struct P2PVendorOrderItem: Codable {
    public let name: String
    public let quantity: Int
    public let unitPrice: Double
    public let totalPrice: Double

    enum CodingKeys: String, CodingKey {
        case name
        case quantity
        case unitPrice = "unit_price"
        case totalPrice = "total_price"
    }
}

/// Delivery address in a vendor order
public struct P2PVendorDeliveryAddress: Codable {
    public let street: String?
    public let city: String?
    public let state: String?
    public let zip: String?
    public let zipCode: String?
    public let latitude: Double?
    public let longitude: Double?

    enum CodingKeys: String, CodingKey {
        case street
        case city
        case state
        case zip
        case zipCode = "zip_code"
        case latitude
        case longitude
    }

    /// Get the zip code (supports both "zip" and "zip_code" keys)
    public var resolvedZip: String {
        return zipCode ?? zip ?? ""
    }

    /// quick-367: lenient decoder. The backend has ~14% of orders where
    /// `delivery_address.latitude` / `.longitude` arrive as STRINGS
    /// ("32.77") instead of numbers. Swift's default strict decoder
    /// rejected the field and aborted the WHOLE orders array decode,
    /// which is why the Restaurant app's History tab showed empty —
    /// one bad row poisoned all 287. Accept Double, Int, or String here.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        street = try c.decodeIfPresent(String.self, forKey: .street)
        city = try c.decodeIfPresent(String.self, forKey: .city)
        state = try c.decodeIfPresent(String.self, forKey: .state)
        zip = try c.decodeIfPresent(String.self, forKey: .zip)
        zipCode = try c.decodeIfPresent(String.self, forKey: .zipCode)
        latitude = Self.lenientDouble(in: c, key: .latitude)
        longitude = Self.lenientDouble(in: c, key: .longitude)
    }

    private static func lenientDouble(in c: KeyedDecodingContainer<CodingKeys>, key: CodingKeys) -> Double? {
        if let d = try? c.decodeIfPresent(Double.self, forKey: key) { return d }
        if let i = try? c.decodeIfPresent(Int.self, forKey: key) { return Double(i) }
        if let s = try? c.decodeIfPresent(String.self, forKey: key) { return Double(s) }
        return nil
    }
}

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

/// Order model as returned by the vendor orders endpoint
public struct P2PVendorOrder: Codable, Identifiable {
    public let id: Int
    public let orderNumber: String
    public let customerName: String
    public let customerPhone: String?
    public let items: [P2PVendorOrderItem]  // Array of items from backend
    public let subtotal: Double
    public let tax: Double
    public let deliveryFee: Double
    public let total: Double
    public let status: String
    public let deliveryAddress: P2PVendorDeliveryAddress?  // Object from backend
    public let deliveryInstructions: String?
    public let createdAt: String?
    // Driver info for pickup coordination
    public let driverId: Int?
    public let driverName: String?
    public let driver: P2PDriverInfo?
    public let pickedUpAt: String?

    // ETA fields for early driver notification
    public let estimatedPrepMinutes: Int?
    public let estimatedReadyAt: String?

    // Driver en-route fields (early driver acceptance)
    public let driverEnRoute: Bool?
    public let driverAcceptedAt: String?
    public let driverEtaToRestaurant: Int?
    public let driverEtaText: String?

    // Leave-at-door preference
    public let leaveAtDoor: Bool?

    // Vendor location for self-delivery map/navigation
    public let vendorLatitude: Double?
    public let vendorLongitude: Double?
    public let vendorName: String?

    // Delivery proof photo
    public let deliveryPhotoUrl: String?

    // Acceptance window timing — when the 3-minute restaurant acceptance window started
    // Populated from sent_to_restaurant_at on the backend; used by iOS countdown timer
    public let sentAt: String?

    enum CodingKeys: String, CodingKey {
        case id
        case orderNumber = "order_number"
        case customerName = "customer_name"
        case customerPhone = "customer_phone"
        case items
        case subtotal
        case tax
        case deliveryFee = "delivery_fee"
        case total
        case status
        case deliveryAddress = "delivery_address"
        case deliveryInstructions = "delivery_instructions"
        case createdAt = "created_at"
        case driverId = "driver_id"
        case driverName = "driver_name"
        case driver
        case pickedUpAt = "picked_up_at"
        case estimatedPrepMinutes = "estimated_prep_minutes"
        case estimatedReadyAt = "estimated_ready_at"
        case driverEnRoute = "driver_en_route"
        case driverAcceptedAt = "driver_accepted_at"
        case driverEtaToRestaurant = "driver_eta_to_restaurant"
        case driverEtaText = "driver_eta_text"
        case leaveAtDoor = "leave_at_door"
        case vendorLatitude = "vendor_latitude"
        case vendorLongitude = "vendor_longitude"
        case vendorName = "vendor_name"
        case deliveryPhotoUrl = "delivery_photo_url"
        case sentAt = "sent_at"
    }

    /// Get items as dictionary array for compatibility
    public var parsedItems: [[String: Any]] {
        return items.map { item in
            [
                "name": item.name,
                "quantity": item.quantity,
                "unit_price": item.unitPrice,
                "total_price": item.totalPrice
            ]
        }
    }

    /// Get delivery address as dictionary for compatibility
    public var parsedDeliveryAddress: [String: String]? {
        guard let addr = deliveryAddress else { return nil }
        return [
            "street": addr.street ?? "",
            "city": addr.city ?? "",
            "state": addr.state ?? "",
            "zip": addr.resolvedZip
        ]
    }

    /// Convert to shared Order model for compatibility
    public func toOrder(vendorId: String, restaurantName: String) -> Order {
        // Parse createdAt to timestamp
        let timestamp: Int64
        if let createdAtString = createdAt {
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = formatter.date(from: createdAtString) {
                timestamp = Int64(date.timeIntervalSince1970 * 1000)
            } else {
                // Try without fractional seconds
                formatter.formatOptions = [.withInternetDateTime]
                if let date = formatter.date(from: createdAtString) {
                    timestamp = Int64(date.timeIntervalSince1970 * 1000)
                } else {
                    timestamp = Int64(Date().timeIntervalSince1970 * 1000)
                }
            }
        } else {
            timestamp = Int64(Date().timeIntervalSince1970 * 1000)
        }

        // Convert typed items to OrderItem array
        let orderItems: [OrderItem] = items.map { item in
            OrderItem(
                menuItemId: "0",
                name: item.name,
                price: item.unitPrice,
                quantity: item.quantity,
                options: nil
            )
        }

        // Convert typed address to DeliveryAddress
        let addr = deliveryAddress
        let deliveryAddr = DeliveryAddress(
            fullAddress: addr.map { "\($0.street ?? ""), \($0.city ?? ""), \($0.state ?? "") \($0.resolvedZip)" } ?? "",
            street: addr?.street ?? "",
            city: addr?.city ?? "",
            state: addr?.state ?? "",
            zipCode: addr?.resolvedZip ?? "",
            latitude: addr?.latitude ?? 0,
            longitude: addr?.longitude ?? 0,
            landmark: deliveryInstructions
        )

        // Map P2P status to Firebase status
        // TODO: When app goes live, upgrade this logic for production delivery workflow
        let mappedStatus: String
        switch status.lowercased() {
        case "pending", "pending_payment":
            mappedStatus = "Placed"
        case "confirmed":
            mappedStatus = "Accepted"
        case "restaurant_timeout":
            // Restaurant didn't respond - order still active, awaiting driver assignment
            mappedStatus = "Accepted"
        case "preparing":
            mappedStatus = "Preparing"
        case "ready", "ready_for_pickup":
            mappedStatus = "Ready"
        case "picked_up":
            mappedStatus = "PickedUp"
        case "out_for_delivery":
            mappedStatus = "OnTheWay"
        case "pending_delivery_proof":
            mappedStatus = "pending_delivery_proof"
        case "delivered":
            mappedStatus = "Delivered"
        case "cancelled":
            mappedStatus = "Cancelled"
        default:
            mappedStatus = status
        }

        // Get driver info from nested driver object or top-level fields
        let resolvedDriverName = driver?.name ?? driverName
        let resolvedDriverPhone = driver?.phone
        let resolvedDriverRating = driver?.rating

        return Order(
            id: String(id),  // Database ID for API calls
            orderId: orderNumber,  // Display order number (e.g., "EF120500009")
            customerId: "",
            customerName: customerName,
            customerEmail: "",
            deliveryAddress: deliveryAddr,
            deliveryInstructions: deliveryInstructions ?? "",
            restaurant: RestaurantInfo(
                id: vendorId,
                name: vendorName ?? restaurantName,
                address: "",
                latitude: vendorLatitude ?? 0,
                longitude: vendorLongitude ?? 0,
                imageUrl: ""
            ),
            items: orderItems,
            itemsCount: orderItems.count,
            subtotal: subtotal,
            deliveryFee: deliveryFee,
            serviceFee: 0,
            priorityFee: 0,
            smallOrderFee: 0,
            tax: tax,
            total: total,
            status: mappedStatus,
            placedAt: timestamp,
            // Driver info
            driverName: resolvedDriverName,
            driverPhone: resolvedDriverPhone,
            driverRating: resolvedDriverRating,
            // ETA fields
            estimatedPrepMinutes: estimatedPrepMinutes,
            estimatedReadyAt: estimatedReadyAt,
            // Driver en-route fields
            driverEnRoute: driverEnRoute,
            driverAcceptedAt: driverAcceptedAt,
            driverEtaToRestaurant: driverEtaToRestaurant,
            driverEtaText: driverEtaText,
            leaveAtDoor: leaveAtDoor,
            deliveryPhotoUrl: deliveryPhotoUrl,
            sentAt: sentAt
        )
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

/// Error response from orders endpoint (when exception occurs)
public struct P2POrdersErrorResponse: Codable {
    public let error: String?
    public let traceback: String?
    public let orders: [P2PCustomerOrder]?
}

/// Order model as returned by the customer orders endpoint
public struct P2PCustomerOrder: Codable, Identifiable {
    public let id: Int
    public let orderNumber: String
    public let status: String
    public let vendorId: Int
    public let vendorName: String?
    public let customerName: String
    public let customerPhone: String?
    public let totalAmount: Double
    public let subtotal: Double
    public let taxAmount: Double
    public let deliveryFee: Double
    public let tip: Double?
    public let items: String  // JSON string of items
    public let deliveryAddress: String?  // JSON string
    public let deliveryInstructions: String?
    public let driverId: Int?
    public let driverName: String?
    public let driverPhone: String?
    public let driverRating: Double?
    public let driverLocation: String?  // JSON string with lat/lng

    // ETA fields for early driver notification
    public let estimatedPrepMinutes: Int?
    public let estimatedReadyAt: String?
    public let minutesUntilReady: Int?
    public let isReady: Bool?

    // Driver en-route fields (early driver acceptance)
    public let driverEnRoute: Bool?
    public let driverAcceptedAt: String?
    public let driverEtaToRestaurant: Int?
    public let driverEtaText: String?

    public let pickupLatitude: Double?
    public let pickupLongitude: Double?
    public let deliveryLatitude: Double?
    public let deliveryLongitude: Double?
    public let createdAt: String?
    public let confirmedAt: String?
    public let preparingAt: String?
    public let readyAt: String?
    public let pickedUpAt: String?
    public let deliveredAt: String?

    // Delivery proof photo
    public let deliveryPhotoUrl: String?

    enum CodingKeys: String, CodingKey {
        case id
        case orderNumber = "order_number"
        case status
        case vendorId = "vendor_id"
        case vendorName = "vendor_name"
        case customerName = "customer_name"
        case customerPhone = "customer_phone"
        case totalAmount = "total_amount"
        case subtotal
        case taxAmount = "tax_amount"
        case deliveryFee = "delivery_fee"
        case tip
        case items
        case deliveryAddress = "delivery_address"
        case deliveryInstructions = "delivery_instructions"
        case driverId = "driver_id"
        case driverName = "driver_name"
        case driverPhone = "driver_phone"
        case driverRating = "driver_rating"
        case driverLocation = "driver_location"
        case estimatedPrepMinutes = "estimated_prep_minutes"
        case estimatedReadyAt = "estimated_ready_at"
        case minutesUntilReady = "minutes_until_ready"
        case isReady = "is_ready"
        case driverEnRoute = "driver_en_route"
        case driverAcceptedAt = "driver_accepted_at"
        case driverEtaToRestaurant = "driver_eta_to_restaurant"
        case driverEtaText = "driver_eta_text"
        case pickupLatitude = "pickup_latitude"
        case pickupLongitude = "pickup_longitude"
        case deliveryLatitude = "delivery_latitude"
        case deliveryLongitude = "delivery_longitude"
        case createdAt = "created_at"
        case confirmedAt = "confirmed_at"
        case preparingAt = "preparing_at"
        case readyAt = "ready_at"
        case pickedUpAt = "picked_up_at"
        case deliveredAt = "delivered_at"
        case deliveryPhotoUrl = "delivery_photo_url"
    }

    // Backend serializes some Double / Int columns as strings for legacy orders
    // (delivery_latitude="37.4419" etc). Foundation's JSONDecoder is strict by
    // default — a single string-where-Double-expected throws
    // `typeMismatch`, which fails the WHOLE array decode and leaves the
    // Customer iOS app showing "No orders yet". This custom init is a
    // permissive decode that accepts either the Swift-typed value or the
    // string form for every Double?/Int? field.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        func d(_ k: CodingKeys) -> Double? {
            if let v = try? c.decodeIfPresent(Double.self, forKey: k) { return v }
            if let s = try? c.decodeIfPresent(String.self, forKey: k) { return Double(s) }
            return nil
        }
        func i(_ k: CodingKeys) -> Int? {
            if let v = try? c.decodeIfPresent(Int.self, forKey: k) { return v }
            if let s = try? c.decodeIfPresent(String.self, forKey: k) { return Int(s) }
            return nil
        }
        func s(_ k: CodingKeys) -> String? {
            try? c.decodeIfPresent(String.self, forKey: k)
        }
        func b(_ k: CodingKeys) -> Bool? {
            try? c.decodeIfPresent(Bool.self, forKey: k)
        }
        // Required fields — same lenience for the few that the backend
        // occasionally returns as strings.
        id           = try c.decode(Int.self, forKey: .id)
        orderNumber  = try c.decode(String.self, forKey: .orderNumber)
        status       = try c.decode(String.self, forKey: .status)
        vendorId     = try c.decode(Int.self, forKey: .vendorId)
        customerName = (try? c.decode(String.self, forKey: .customerName)) ?? ""
        totalAmount  = d(.totalAmount)  ?? 0
        subtotal     = d(.subtotal)     ?? 0
        taxAmount    = d(.taxAmount)    ?? 0
        deliveryFee  = d(.deliveryFee)  ?? 0
        items        = s(.items)        ?? "[]"

        vendorName               = s(.vendorName)
        customerPhone            = s(.customerPhone)
        tip                      = d(.tip)
        deliveryAddress          = s(.deliveryAddress)
        deliveryInstructions     = s(.deliveryInstructions)
        driverId                 = i(.driverId)
        driverName               = s(.driverName)
        driverPhone              = s(.driverPhone)
        driverRating             = d(.driverRating)
        driverLocation           = s(.driverLocation)
        estimatedPrepMinutes     = i(.estimatedPrepMinutes)
        estimatedReadyAt         = s(.estimatedReadyAt)
        minutesUntilReady        = i(.minutesUntilReady)
        isReady                  = b(.isReady)
        driverEnRoute            = b(.driverEnRoute)
        driverAcceptedAt         = s(.driverAcceptedAt)
        driverEtaToRestaurant    = i(.driverEtaToRestaurant)
        driverEtaText            = s(.driverEtaText)
        pickupLatitude           = d(.pickupLatitude)
        pickupLongitude          = d(.pickupLongitude)
        deliveryLatitude         = d(.deliveryLatitude)
        deliveryLongitude        = d(.deliveryLongitude)
        createdAt                = s(.createdAt)
        confirmedAt              = s(.confirmedAt)
        preparingAt              = s(.preparingAt)
        readyAt                  = s(.readyAt)
        pickedUpAt               = s(.pickedUpAt)
        deliveredAt              = s(.deliveredAt)
        deliveryPhotoUrl         = s(.deliveryPhotoUrl)
    }

    /// Parse items JSON string into array
    public var parsedItems: [[String: Any]] {
        guard let data = items.data(using: .utf8),
              let array = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            return []
        }
        return array
    }

    /// Parse delivery address JSON string
    public var parsedDeliveryAddress: [String: String]? {
        guard let addressString = deliveryAddress,
              let data = addressString.data(using: .utf8),
              let dict = try? JSONSerialization.jsonObject(with: data) as? [String: String] else {
            return nil
        }
        return dict
    }

    /// Parse driver location
    public var parsedDriverLocation: (latitude: Double, longitude: Double)? {
        guard let locationString = driverLocation,
              let data = locationString.data(using: .utf8),
              let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let lat = dict["latitude"] as? Double,
              let lng = dict["longitude"] as? Double else {
            return nil
        }
        return (latitude: lat, longitude: lng)
    }

    /// Map P2P status to display status
    /// TODO: When app goes live, upgrade this logic to handle restaurant self-delivery vs driver delivery
    /// Current flow: Restaurant can deliver themselves OR order auto-assigns to nearby driver after timeout
    /// Orders stay active for up to 30 minutes unless restaurant explicitly cancels
    public var displayStatus: String {
        switch status.lowercased() {
        case "pending", "pending_payment":
            return "Placed"
        case "pending_restaurant":
            // Order sent to restaurant, waiting for acceptance (3-min window)
            return "Confirming"
        case "confirmed":
            return "Accepted"
        case "restaurant_timeout":
            // Restaurant didn't respond yet - order is still active, awaiting driver assignment
            return "Accepted"
        case "preparing":
            return "Preparing"
        case "pending_delivery_decision":
            // Order ready, restaurant deciding delivery method (3-min window)
            return "Ready"
        case "ready", "ready_for_pickup":
            return "Ready"
        case "restaurant_will_deliver":
            // Restaurant chose self-delivery but hasn't started yet
            return "restaurant_will_deliver"
        case "out_for_delivery":
            return "OnTheWay"
        case "pending_delivery_proof":
            return "OnTheWay"
        case "delivered":
            return "Delivered"
        case "declined_by_restaurant":
            return "Cancelled"
        case "cancelled":
            return "Cancelled"
        default:
            return status.capitalized
        }
    }

    /// Check if order is currently active (not completed or cancelled)
    public var isActive: Bool {
        let completedStatuses = ["delivered", "cancelled"]
        return !completedStatuses.contains(status.lowercased())
    }

    /// Convert to shared Order model for compatibility
    public func toOrder() -> Order {
        // Parse createdAt to timestamp
        let timestamp: Int64
        if let createdAtString = createdAt {
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = formatter.date(from: createdAtString) {
                timestamp = Int64(date.timeIntervalSince1970 * 1000)
            } else {
                formatter.formatOptions = [.withInternetDateTime]
                if let date = formatter.date(from: createdAtString) {
                    timestamp = Int64(date.timeIntervalSince1970 * 1000)
                } else {
                    timestamp = Int64(Date().timeIntervalSince1970 * 1000)
                }
            }
        } else {
            timestamp = Int64(Date().timeIntervalSince1970 * 1000)
        }

        // Parse items
        let orderItems: [OrderItem] = parsedItems.map { item in
            OrderItem(
                menuItemId: String(item["menu_item_id"] as? Int ?? 0),
                name: item["name"] as? String ?? "Unknown",
                price: item["unit_price"] as? Double ?? item["price"] as? Double ?? 0,
                quantity: item["quantity"] as? Int ?? 1,
                options: nil
            )
        }

        // Parse address
        let addr = parsedDeliveryAddress
        let deliveryAddr = DeliveryAddress(
            fullAddress: addr.map { "\($0["street"] ?? ""), \($0["city"] ?? ""), \($0["state"] ?? "") \($0["zip"] ?? "")" } ?? "",
            street: addr?["street"] ?? "",
            city: addr?["city"] ?? "",
            state: addr?["state"] ?? "",
            zipCode: addr?["zip"] ?? "",
            latitude: deliveryLatitude ?? 0,
            longitude: deliveryLongitude ?? 0,
            landmark: deliveryInstructions
        )

        return Order(
            id: String(id),  // Database ID for API calls (cancel, refund, etc.)
            orderId: orderNumber,
            customerId: "",
            customerName: customerName,
            customerEmail: "",
            deliveryAddress: deliveryAddr,
            deliveryInstructions: deliveryInstructions ?? "",
            restaurant: RestaurantInfo(
                id: String(vendorId),
                name: vendorName ?? "Restaurant",
                address: "",
                latitude: pickupLatitude ?? 0,
                longitude: pickupLongitude ?? 0,
                imageUrl: ""
            ),
            items: orderItems,
            itemsCount: orderItems.count,
            subtotal: subtotal,
            deliveryFee: deliveryFee,
            serviceFee: 0,
            priorityFee: 0,
            smallOrderFee: 0,
            tax: taxAmount,
            tip: tip ?? 0,
            total: totalAmount,
            status: displayStatus,
            placedAt: timestamp,
            driverId: driverId.map { String($0) },
            // Driver info
            driverName: driverName,
            driverPhone: driverPhone,
            driverRating: driverRating,
            // ETA fields
            estimatedPrepMinutes: estimatedPrepMinutes,
            estimatedReadyAt: estimatedReadyAt,
            minutesUntilReady: minutesUntilReady,
            isReady: isReady,
            // Driver en-route fields
            driverEnRoute: driverEnRoute,
            driverAcceptedAt: driverAcceptedAt,
            driverEtaToRestaurant: driverEtaToRestaurant,
            driverEtaText: driverEtaText
        )
    }
}

// MARK: - Order Tracking Model

public struct P2POrderTracking: Codable {
    public let orderId: Int
    public let orderNumber: String
    public let status: String
    public let vendorName: String?
    public let vendorAddress: String?
    public let pickupLatitude: Double?
    public let pickupLongitude: Double?
    public let deliveryAddress: String?
    public let deliveryLatitude: Double?
    public let deliveryLongitude: Double?
    public let driverId: Int?
    public let driverName: String?
    public let driverPhone: String?
    public let driverLatitude: Double?
    public let driverLongitude: Double?
    public let estimatedDeliveryTime: String?
    public let statusHistory: [P2POrderStatusEvent]?

    enum CodingKeys: String, CodingKey {
        case orderId = "order_id"
        case orderNumber = "order_number"
        case status
        case vendorName = "vendor_name"
        case vendorAddress = "vendor_address"
        case pickupLatitude = "pickup_latitude"
        case pickupLongitude = "pickup_longitude"
        case deliveryAddress = "delivery_address"
        case deliveryLatitude = "delivery_latitude"
        case deliveryLongitude = "delivery_longitude"
        case driverId = "driver_id"
        case driverName = "driver_name"
        case driverPhone = "driver_phone"
        case driverLatitude = "driver_latitude"
        case driverLongitude = "driver_longitude"
        case estimatedDeliveryTime = "estimated_delivery_time"
        case statusHistory = "status_history"
    }

    /// Map P2P status to display status
    /// TODO: When app goes live, upgrade this logic for production delivery workflow
    public var displayStatus: String {
        switch status.lowercased() {
        case "pending", "pending_payment":
            return "Placed"
        case "confirmed":
            return "Accepted"
        case "restaurant_timeout":
            // Restaurant didn't respond - order still active, awaiting driver assignment
            return "Accepted"
        case "preparing":
            return "Preparing"
        case "ready", "ready_for_pickup":
            return "Ready"
        case "out_for_delivery":
            return "OnTheWay"
        case "pending_delivery_proof":
            return "OnTheWay"
        case "delivered":
            return "Delivered"
        case "cancelled":
            return "Cancelled"
        default:
            return status.capitalized
        }
    }
}

public struct P2POrderStatusEvent: Codable {
    public let status: String
    public let timestamp: String
    public let note: String?
}

// MARK: - Enterprise WebSocket Manager

/// WebSocket Manager for real-time updates
public class P2PWebSocketManager: NSObject, ObservableObject, URLSessionWebSocketDelegate {
    public static let shared = P2PWebSocketManager()

    @Published public var isConnected = false
    @Published public var lastMessage: P2PWebSocketMessage?

    private var webSocketTask: URLSessionWebSocketTask?
    private var session: URLSession?
    private var clientType: String = "customer"
    private var clientId: String = ""

    // WebSocket URL from AppConfig (environment-aware)
    private var wsBaseURL: String {
        let apiURL = AppConfig.shared.p2pAPIBaseURL
        // Convert https:// to wss:// for WebSocket
        let wsURL = apiURL.replacingOccurrences(of: "https://", with: "wss://")
        return "\(wsURL)/api/realtime/ws"
    }

    private override init() {
        super.init()
        session = URLSession(configuration: .default, delegate: self, delegateQueue: nil)
    }

    /// Connect to WebSocket server
    public func connect(clientType: String, clientId: String) {
        self.clientType = clientType
        self.clientId = clientId

        guard let url = URL(string: "\(wsBaseURL)/\(clientType)/\(clientId)") else {
            #if DEBUG
            logger.info("WebSocket Invalid URL")
            #endif
            return
        }

        webSocketTask = session?.webSocketTask(with: url)
        webSocketTask?.resume()

        DispatchQueue.main.async {
            self.isConnected = true
        }

        receiveMessage()
        startPingTimer()

        #if DEBUG
        logger.info("WebSocket Connecting to \(url.absoluteString)")
        #endif
    }

    /// Disconnect from WebSocket server
    public func disconnect() {
        webSocketTask?.cancel(with: .goingAway, reason: nil)
        DispatchQueue.main.async {
            self.isConnected = false
        }
        #if DEBUG
        logger.info("WebSocket Disconnected")
        #endif
    }

    /// Receive messages recursively
    private func receiveMessage() {
        webSocketTask?.receive { [weak self] result in
            switch result {
            case .success(let message):
                switch message {
                case .string(let text):
                    self?.handleTextMessage(text)
                case .data(let data):
                    if let text = String(data: data, encoding: .utf8) {
                        self?.handleTextMessage(text)
                    }
                @unknown default:
                    break
                }
                // Continue listening
                self?.receiveMessage()

            case .failure(let error):
                #if DEBUG
                logger.error("WebSocket Receive error: \(error)")
                #endif
                DispatchQueue.main.async {
                    self?.isConnected = false
                }
            }
        }
    }

    private func handleTextMessage(_ text: String) {
        guard let data = text.data(using: .utf8) else { return }

        do {
            let message = try JSONDecoder().decode(P2PWebSocketMessage.self, from: data)
            DispatchQueue.main.async {
                self.lastMessage = message
                NotificationCenter.default.post(
                    name: .p2pWebSocketMessage,
                    object: nil,
                    userInfo: ["message": message]
                )
            }
            #if DEBUG
            logger.info("WebSocket Received: \(message.type)")
            #endif
        } catch {
            #if DEBUG
            logger.info("WebSocket Failed to decode message: \(error)")
            #endif
        }
    }

    /// Send ping to keep connection alive
    private func startPingTimer() {
        DispatchQueue.global().asyncAfter(deadline: .now() + 30) { [weak self] in
            self?.sendPing()
        }
    }

    private func sendPing() {
        guard isConnected else { return }

        let pingMessage = ["type": "ping"]
        if let data = try? JSONSerialization.data(withJSONObject: pingMessage) {
            webSocketTask?.send(.data(data)) { [weak self] error in
                if let error = error {
                    #if DEBUG
                    logger.error("WebSocket Ping error: \(error)")
                    #endif
                } else {
                    self?.startPingTimer()
                }
            }
        }
    }

    // MARK: - URLSessionWebSocketDelegate

    public func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didOpenWithProtocol protocol: String?) {
        #if DEBUG
        logger.info("WebSocket Connected")
        #endif
        DispatchQueue.main.async {
            self.isConnected = true
        }
    }

    public func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didCloseWith closeCode: URLSessionWebSocketTask.CloseCode, reason: Data?) {
        #if DEBUG
        logger.info("WebSocket Closed with code: \(closeCode.rawValue)")
        #endif
        DispatchQueue.main.async {
            self.isConnected = false
        }
    }
}

/// WebSocket Message Model
public struct P2PWebSocketMessage: Codable {
    public let type: String
    public let orderId: Int?
    public let orderNumber: String?
    public let status: String?
    public let payload: [String: AnyCodable]?
    public let timestamp: String?

    enum CodingKeys: String, CodingKey {
        case type
        case orderId = "order_id"
        case orderNumber = "order_number"
        case status
        case payload
        case timestamp
    }
}

/// Helper for encoding/decoding Any types
public struct AnyCodable: Codable {
    public let value: Any

    public init(_ value: Any) {
        self.value = value
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let intValue = try? container.decode(Int.self) {
            value = intValue
        } else if let doubleValue = try? container.decode(Double.self) {
            value = doubleValue
        } else if let stringValue = try? container.decode(String.self) {
            value = stringValue
        } else if let boolValue = try? container.decode(Bool.self) {
            value = boolValue
        } else {
            value = ""
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        if let intValue = value as? Int {
            try container.encode(intValue)
        } else if let doubleValue = value as? Double {
            try container.encode(doubleValue)
        } else if let stringValue = value as? String {
            try container.encode(stringValue)
        } else if let boolValue = value as? Bool {
            try container.encode(boolValue)
        }
    }
}

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

    /// Save FCM token for vendor/restaurant
    public func saveVendorFCMToken(
        vendorId: Int,
        token: String,
        completion: @escaping (Result<Bool, Error>) -> Void
    ) {
        guard let url = URL(string: "\(baseURL)/erp/vendors/\(vendorId)/fcm-token") else {
            completion(.failure(P2PAPIError.invalidURL))
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let token = vendorToken {
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

    /// Get full order tracking info (for customer app)
    public func getFullOrderTracking(
        orderId: Int,
        completion: @escaping (Result<P2PFullOrderTracking, Error>) -> Void
    ) {
        guard let url = URL(string: "\(baseURL)/erp/orders/\(orderId)/full-tracking") else {
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
                    let tracking = try JSONDecoder().decode(P2PFullOrderTracking.self, from: data)
                    completion(.success(tracking))
                } catch {
                    completion(.failure(error))
                }
            }
        }.resume()
    }

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

    /// Get real-time analytics (for admin dashboard)
    public func getRealtimeAnalytics(
        completion: @escaping (Result<P2PRealtimeAnalytics, Error>) -> Void
    ) {
        guard let url = URL(string: "\(baseURL)/erp/analytics/realtime") else {
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
                    let analytics = try JSONDecoder().decode(P2PRealtimeAnalytics.self, from: data)
                    completion(.success(analytics))
                } catch {
                    completion(.failure(error))
                }
            }
        }.resume()
    }

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


    /// Submit restaurant rating for an order
    public func submitRestaurantRating(
        orderId: Int,
        restaurantId: Int,
        rating: Int,
        review: String? = nil,
        foodQuality: Bool = false,
        portionSize: Bool = false,
        valueForMoney: Bool = false,
        accuracy: Bool = false,
        completion: @escaping (Result<P2PRestaurantRatingResponse, Error>) -> Void
    ) {
        guard let url = URL(string: "\(baseURL)/customer/orders/\(orderId)/rate-restaurant") else {
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
            "order_id": orderId,
            "restaurant_id": restaurantId,
            "rating": rating,
            "food_quality": foodQuality,
            "portion_size": portionSize,
            "value_for_money": valueForMoney,
            "accuracy": accuracy
        ]
        if let review = review, !review.isEmpty {
            body["review"] = review
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
                        completion(.failure(P2PAPIError.serverError("Failed to submit restaurant rating")))
                    }
                    return
                }

                do {
                    let ratingResponse = try JSONDecoder().decode(P2PRestaurantRatingResponse.self, from: data)
                    completion(.success(ratingResponse))
                } catch {
                    completion(.failure(error))
                }
            }
        }.resume()
    }

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

    /// Get driver earnings for a specific period
    /// - Parameters:
    ///   - driverId: The driver ID
    ///   - period: Period for earnings: "today", "week", "month", "year"
    ///   - completion: Result with earnings data or error
    public func getDriverEarnings(
        driverId: Int,
        period: String = "week",
        completion: @escaping (Result<P2PDriverEarningsResponse, Error>) -> Void
    ) {
        guard let url = URL(string: "\(baseURL)/drivers/\(driverId)/earnings?period=\(period)") else {
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
                        completion(.failure(P2PAPIError.serverError("Failed to fetch driver earnings")))
                    }
                    return
                }

                do {
                    let decoder = JSONDecoder()
                    decoder.keyDecodingStrategy = .convertFromSnakeCase
                    let earningsResponse = try decoder.decode(P2PDriverEarningsResponse.self, from: data)
                    completion(.success(earningsResponse))
                } catch {
                    #if DEBUG
                    logger.error("getDriverEarnings decode error: \(error)")
                    if let jsonString = String(data: data, encoding: .utf8) {
                        logger.info("Response: \(jsonString.prefix(500))")
                    }
                    #endif
                    completion(.failure(error))
                }
            }
        }.resume()
    }

    // MARK: - Stripe Connect APIs (Driver Payouts)

    /// Create a Stripe Connect Express account for a driver
    public func createStripeConnectAccount(
        driverId: Int,
        completion: @escaping (Result<[String: Any], Error>) -> Void
    ) {
        guard let url = URL(string: "\(baseURL)/drivers/\(driverId)/stripe/connect") else {
            completion(.failure(P2PAPIError.invalidURL))
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
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
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                    completion(.failure(P2PAPIError.noData))
                    return
                }
                if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode >= 400 {
                    let detail = json["detail"] as? String ?? "Failed to create Stripe account"
                    completion(.failure(P2PAPIError.serverError(detail)))
                    return
                }
                completion(.success(json))
            }
        }.resume()
    }

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

    /// Get the driver's Stripe Connect account status
    public func getStripeAccountStatus(
        driverId: Int,
        completion: @escaping (Result<P2PStripeStatus, Error>) -> Void
    ) {
        guard let url = URL(string: "\(baseURL)/drivers/\(driverId)/stripe/status") else {
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
                        completion(.failure(P2PAPIError.serverError("Failed to get Stripe status")))
                    }
                    return
                }
                do {
                    let decoder = JSONDecoder()
                    decoder.keyDecodingStrategy = .convertFromSnakeCase
                    let status = try decoder.decode(P2PStripeStatus.self, from: data)
                    completion(.success(status))
                } catch {
                    completion(.failure(error))
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

    /// Get the current customer's cart
    /// - Parameter completion: Result with cart data or error
    public func getCart(
        completion: @escaping (Result<P2PCartResponse, Error>) -> Void
    ) {
        guard let url = URL(string: "\(baseURL)/cart") else {
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
                        completion(.failure(P2PAPIError.serverError("Failed to fetch cart")))
                    }
                    return
                }

                do {
                    let decoder = JSONDecoder()
                    decoder.keyDecodingStrategy = .convertFromSnakeCase
                    let cartResponse = try decoder.decode(P2PCartResponse.self, from: data)
                    completion(.success(cartResponse))
                } catch {
                    completion(.failure(error))
                }
            }
        }.resume()
    }

    /// Add an item to the cart
    /// - Parameters:
    ///   - menuItemId: The menu item ID to add
    ///   - quantity: Quantity to add
    ///   - specialInstructions: Optional special instructions
    ///   - completion: Result with updated cart or error
    public func addToCart(
        menuItemId: Int,
        quantity: Int,
        specialInstructions: String? = nil,
        completion: @escaping (Result<P2PCartResponse, Error>) -> Void
    ) {
        guard let url = URL(string: "\(baseURL)/cart/items") else {
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
            "menu_item_id": menuItemId,
            "quantity": quantity
        ]
        if let instructions = specialInstructions {
            body["special_instructions"] = instructions
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
                        completion(.failure(P2PAPIError.serverError("Failed to add item to cart")))
                    }
                    return
                }

                do {
                    let decoder = JSONDecoder()
                    decoder.keyDecodingStrategy = .convertFromSnakeCase
                    let cartResponse = try decoder.decode(P2PCartResponse.self, from: data)
                    completion(.success(cartResponse))
                } catch {
                    completion(.failure(error))
                }
            }
        }.resume()
    }

    /// Update a cart item's quantity or instructions
    /// - Parameters:
    ///   - itemId: The cart item ID to update
    ///   - quantity: New quantity (optional)
    ///   - specialInstructions: New special instructions (optional)
    ///   - completion: Result with updated cart or error
    public func updateCartItem(
        itemId: Int,
        quantity: Int? = nil,
        specialInstructions: String? = nil,
        completion: @escaping (Result<P2PCartResponse, Error>) -> Void
    ) {
        guard let url = URL(string: "\(baseURL)/cart/items/\(itemId)") else {
            completion(.failure(P2PAPIError.invalidURL))
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        if let token = customerToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        var body: [String: Any] = [:]
        if let qty = quantity {
            body["quantity"] = qty
        }
        if let instructions = specialInstructions {
            body["special_instructions"] = instructions
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
                        completion(.failure(P2PAPIError.serverError("Failed to update cart item")))
                    }
                    return
                }

                do {
                    let decoder = JSONDecoder()
                    decoder.keyDecodingStrategy = .convertFromSnakeCase
                    let cartResponse = try decoder.decode(P2PCartResponse.self, from: data)
                    completion(.success(cartResponse))
                } catch {
                    completion(.failure(error))
                }
            }
        }.resume()
    }

    /// Remove an item from the cart
    /// - Parameters:
    ///   - itemId: The cart item ID to remove
    ///   - completion: Result with updated cart or error
    public func removeCartItem(
        itemId: Int,
        completion: @escaping (Result<P2PCartResponse, Error>) -> Void
    ) {
        guard let url = URL(string: "\(baseURL)/cart/items/\(itemId)") else {
            completion(.failure(P2PAPIError.invalidURL))
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"

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
                        completion(.failure(P2PAPIError.serverError("Failed to remove cart item")))
                    }
                    return
                }

                do {
                    let decoder = JSONDecoder()
                    decoder.keyDecodingStrategy = .convertFromSnakeCase
                    let cartResponse = try decoder.decode(P2PCartResponse.self, from: data)
                    completion(.success(cartResponse))
                } catch {
                    completion(.failure(error))
                }
            }
        }.resume()
    }

    /// Clear all items from the cart
    /// - Parameter completion: Result with empty cart summary or error
    public func clearCart(
        completion: @escaping (Result<P2PCartSummary, Error>) -> Void
    ) {
        guard let url = URL(string: "\(baseURL)/cart") else {
            completion(.failure(P2PAPIError.invalidURL))
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"

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
                        completion(.failure(P2PAPIError.serverError("Failed to clear cart")))
                    }
                    return
                }

                do {
                    let decoder = JSONDecoder()
                    decoder.keyDecodingStrategy = .convertFromSnakeCase
                    // Backend returns { message, summary }
                    let clearResponse = try decoder.decode(P2PClearCartResponse.self, from: data)
                    completion(.success(clearResponse.summary))
                } catch {
                    completion(.failure(error))
                }
            }
        }.resume()
    }

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

    /// Process a refund for an order (Admin/Restaurant use)
    /// - Parameters:
    ///   - orderId: The order ID to refund
    ///   - amount: Refund amount (optional, defaults to full refund)
    ///   - reason: Reason for refund
    ///   - completion: Result with refund response or error
    public func processRefund(
        orderId: Int,
        amount: Double? = nil,
        reason: String,
        completion: @escaping (Result<P2PProcessRefundResponse, Error>) -> Void
    ) {
        guard let url = URL(string: "\(baseURL)/erp/payments/refund") else {
            completion(.failure(P2PAPIError.invalidURL))
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        // Use vendor token for restaurant-initiated refunds, customer token for customer-initiated
        if let token = vendorToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        } else if let token = customerToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        var body: [String: Any] = [
            "order_id": orderId,
            "reason": reason
        ]
        if let refundAmount = amount {
            body["amount"] = refundAmount
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
                        completion(.failure(P2PAPIError.serverError("Failed to process refund")))
                    }
                    return
                }

                do {
                    let decoder = JSONDecoder()
                    decoder.keyDecodingStrategy = .convertFromSnakeCase
                    let refundResponse = try decoder.decode(P2PProcessRefundResponse.self, from: data)
                    completion(.success(refundResponse))
                } catch {
                    completion(.failure(error))
                }
            }
        }.resume()
    }
}

// MARK: - Partial Order Response Models

public struct P2POrderModificationResponse: Codable {
    public let hasPendingModification: Bool
    public let isExpired: Bool?
    public let modificationNumber: String?
    public let unavailableItems: [UnavailableItem]?
    public let unavailableCount: Int?
    public let availableItems: [ModifiedOrderItem]?
    public let availableCount: Int?
    public let originalTotal: Double?
    public let newTotal: Double?
    public let partialRefundAmount: Double?
    public let timeRemainingSeconds: Int?
    public let expiresAt: String?
    public let restaurantName: String?
    public let orderStatus: String?

    enum CodingKeys: String, CodingKey {
        case hasPendingModification = "has_pending_modification"
        case isExpired = "is_expired"
        case modificationNumber = "modification_number"
        case unavailableItems = "unavailable_items"
        case unavailableCount = "unavailable_count"
        case availableItems = "available_items"
        case availableCount = "available_count"
        case originalTotal = "original_total"
        case newTotal = "new_total"
        case partialRefundAmount = "partial_refund_amount"
        case timeRemainingSeconds = "time_remaining_seconds"
        case expiresAt = "expires_at"
        case restaurantName = "restaurant_name"
        case orderStatus = "order_status"
    }
}

public struct P2PModificationResponseResult: Codable {
    public let success: Bool
    public let response: String
    public let message: String
    public let orderId: Int
    public let orderNumber: String
    public let orderStatus: String
    public let refundAmount: Double?
    public let refundNumber: String?

    enum CodingKeys: String, CodingKey {
        case success, response, message
        case orderId = "order_id"
        case orderNumber = "order_number"
        case orderStatus = "order_status"
        case refundAmount = "refund_amount"
        case refundNumber = "refund_number"
    }
}

public struct P2PMarkUnavailableResponse: Codable {
    public let success: Bool
    public let message: String
    public let modificationNumber: String
    public let orderId: Int
    public let orderNumber: String
    public let originalTotal: Double
    public let newTotal: Double
    public let partialRefundIfAccepted: Double
    public let expiresInMinutes: Int

    enum CodingKeys: String, CodingKey {
        case success, message
        case modificationNumber = "modification_number"
        case orderId = "order_id"
        case orderNumber = "order_number"
        case originalTotal = "original_total"
        case newTotal = "new_total"
        case partialRefundIfAccepted = "partial_refund_if_accepted"
        case expiresInMinutes = "expires_in_minutes"
    }
}

// MARK: - Order Cancellation Response Models

public struct P2PCancelOrderResponse: Codable {
    public let success: Bool
    public let message: String
    public let orderId: Int
    public let refundNumber: String?
    public let refundAmount: Double?
    public let refundStatus: String?

    enum CodingKeys: String, CodingKey {
        case success, message
        case orderId = "order_id"
        case refundNumber = "refund_number"
        case refundAmount = "refund_amount"
        case refundStatus = "refund_status"
    }
}

public struct P2PRefundStatusResponse: Codable {
    public let success: Bool
    public let orderId: Int
    public let refundStatus: String
    public let refundAmount: Double?
    public let refundNumber: String?
    public let processedAt: String?
    public let estimatedArrival: String?

    enum CodingKeys: String, CodingKey {
        case success
        case orderId = "order_id"
        case refundStatus = "refund_status"
        case refundAmount = "refund_amount"
        case refundNumber = "refund_number"
        case processedAt = "processed_at"
        case estimatedArrival = "estimated_arrival"
    }
}

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

public struct P2PRestaurantRatingResponse: Codable {
    public let success: Bool
    public let message: String
    public let orderId: Int
    public let newRestaurantRating: Double?

    enum CodingKeys: String, CodingKey {
        case success, message
        case orderId = "order_id"
        case newRestaurantRating = "new_restaurant_rating"
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

public struct P2PFavorite: Codable, Identifiable {
    public let id: Int
    public let customerId: Int
    public let vendorId: Int
    public let restaurantName: String?
    public let cuisine: String?
    public let rating: Double?
    public let imageUrl: String?
    public let address: String?
    public let latitude: Double?
    public let longitude: Double?
    public let phone: String?
    public let createdAt: String?

    enum CodingKeys: String, CodingKey {
        case id
        case customerId = "customer_id"
        case vendorId = "vendor_id"
        case restaurantName = "restaurant_name"
        case cuisine
        case rating
        case imageUrl = "image_url"
        case address
        case latitude
        case longitude
        case phone
        case createdAt = "created_at"
    }
}

public struct P2PFavoritesResponse: Codable {
    public let favorites: [P2PFavorite]
    public let count: Int
}

public struct P2PAddFavoriteResponse: Codable {
    public let message: String
    public let favoriteId: Int?
    public let restaurantName: String?

    enum CodingKeys: String, CodingKey {
        case message
        case favoriteId = "favorite_id"
        case restaurantName = "restaurant_name"
    }
}

public struct P2PCheckFavoriteResponse: Codable {
    public let isFavorite: Bool

    enum CodingKeys: String, CodingKey {
        case isFavorite = "is_favorite"
    }
}

public struct P2PMessageResponse: Codable {
    public let message: String
}

// MARK: - Enterprise Response Models

/// Traffic-aware ETA data from Google Maps Directions API
public struct P2PETAData: Codable {
    public let minutes: Int
    public let distanceMiles: Double
    public let distanceMeters: Int
    public let isTrafficAware: Bool
    public let routePolyline: String?

    enum CodingKeys: String, CodingKey {
        case minutes
        case distanceMiles = "distance_miles"
        case distanceMeters = "distance_meters"
        case isTrafficAware = "is_traffic_aware"
        case routePolyline = "route_polyline"
    }
}

public struct P2PFullOrderTracking: Codable {
    public let success: Bool
    public let order: P2PTrackingOrder
    public let restaurant: P2PTrackingRestaurant
    public let driver: P2PTrackingDriver?
    public let timeline: [P2PTimelineEvent]
    public let estimatedDelivery: String?
    public let eta: P2PETAData?

    enum CodingKeys: String, CodingKey {
        case success, order, restaurant, driver, timeline, eta
        case estimatedDelivery = "estimated_delivery"
    }
}

public struct P2PTrackingOrder: Codable {
    public let id: Int
    public let orderNumber: String
    public let status: String
    public let subtotal: Double
    public let tax: Double
    public let deliveryFee: Double
    public let tip: Double
    public let total: Double

    enum CodingKeys: String, CodingKey {
        case id
        case orderNumber = "order_number"
        case status, subtotal, tax
        case deliveryFee = "delivery_fee"
        case tip, total
    }
}

public struct P2PTrackingRestaurant: Codable {
    public let id: Int?
    public let name: String?
    public let address: String?
    public let phone: String?
    public let latitude: Double?
    public let longitude: Double?
}

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

public struct P2PTimelineEvent: Codable {
    public let status: String
    public let time: String
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

public struct P2PRealtimeAnalytics: Codable {
    public let success: Bool
    public let timestamp: String
    public let processedBy: String
    public let orders: P2POrdersAnalytics
    public let drivers: P2PDriversAnalytics
    public let restaurants: P2PRestaurantsAnalytics
    public let revenue: P2PRevenueAnalytics
    public let performance: P2PPerformanceAnalytics

    enum CodingKeys: String, CodingKey {
        case success, timestamp
        case processedBy = "processed_by"
        case orders, drivers, restaurants, revenue, performance
    }
}

public struct P2POrdersAnalytics: Codable {
    public let byStatus: [String: Int]
    public let totalToday: Int
    public let active: Int

    enum CodingKeys: String, CodingKey {
        case byStatus = "by_status"
        case totalToday = "total_today"
        case active
    }
}

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

public struct P2PRestaurantsAnalytics: Codable {
    public let active: Int
}

public struct P2PRevenueAnalytics: Codable {
    public let totalToday: Double
    public let platformFees: Double
    public let deliveryFees: Double
    public let tipsCollected: Double
    public let ordersCompleted: Int

    enum CodingKeys: String, CodingKey {
        case totalToday = "total_today"
        case platformFees = "platform_fees"
        case deliveryFees = "delivery_fees"
        case tipsCollected = "tips_collected"
        case ordersCompleted = "orders_completed"
    }
}

public struct P2PPerformanceAnalytics: Codable {
    public let avgPrepTimeMinutes: Double?
    public let avgDeliveryTimeMinutes: Double?

    enum CodingKeys: String, CodingKey {
        case avgPrepTimeMinutes = "avg_prep_time_minutes"
        case avgDeliveryTimeMinutes = "avg_delivery_time_minutes"
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

/// Delivery method options
public enum DeliveryMethod: String, Codable, CaseIterable {
    case pending = "pending"
    case restaurant = "restaurant"
    case driver = "driver"
    case pickup = "pickup"

    public var displayName: String {
        switch self {
        case .pending: return "Pending"
        case .restaurant: return "Restaurant Delivery"
        case .driver: return "Dollor Driver"
        case .pickup: return "Customer Pickup"
        }
    }

    public var icon: String {
        switch self {
        case .pending: return "clock"
        case .restaurant: return "storefront"
        case .driver: return "car.fill"
        case .pickup: return "figure.walk"
        }
    }
}

/// Response for delivery decision status
public struct DeliveryDecisionStatus: Codable {
    public let orderId: Int
    public let orderNumber: String
    public let status: String
    public let deliveryMethod: String
    public let deadline: String?
    public let remainingSeconds: Int?
    public let decisionMadeAt: String?
    public let delivererName: String?
    public let canDecide: Bool

    enum CodingKeys: String, CodingKey {
        case orderId = "order_id"
        case orderNumber = "order_number"
        case status
        case deliveryMethod = "delivery_method"
        case deadline
        case remainingSeconds = "remaining_seconds"
        case decisionMadeAt = "decision_made_at"
        case delivererName = "deliverer_name"
        case canDecide = "can_decide"
    }
}

/// Response for starting delivery decision
public struct StartDeliveryDecisionResponse: Codable {
    public let success: Bool
    public let orderId: Int
    public let orderNumber: String
    public let status: String
    public let deadline: String?
    public let timeoutSeconds: Int
    public let message: String

    enum CodingKeys: String, CodingKey {
        case success
        case orderId = "order_id"
        case orderNumber = "order_number"
        case status
        case deadline
        case timeoutSeconds = "timeout_seconds"
        case message
    }
}

/// Response for making delivery decision
public struct DeliveryDecisionResponse: Codable {
    public let success: Bool
    public let orderId: Int
    public let orderNumber: String
    public let status: String
    public let deliveryMethod: String
    public let delivererName: String?
    public let message: String

    enum CodingKeys: String, CodingKey {
        case success
        case orderId = "order_id"
        case orderNumber = "order_number"
        case status
        case deliveryMethod = "delivery_method"
        case delivererName = "deliverer_name"
        case message
    }
}

/// Order pending restaurant delivery decision
public struct PendingDeliveryOrder: Identifiable, Codable {
    public var id: Int { orderId }
    public let orderId: Int
    public let orderNumber: String
    public let customerName: String?
    public let subtotal: Double
    public let totalAmount: Double
    public let deliveryAddress: String?
    public let deadline: String?
    public let remainingSeconds: Int
    public let createdAt: String?

    enum CodingKeys: String, CodingKey {
        case orderId = "order_id"
        case orderNumber = "order_number"
        case customerName = "customer_name"
        case subtotal
        case totalAmount = "total_amount"
        case deliveryAddress = "delivery_address"
        case deadline
        case remainingSeconds = "remaining_seconds"
        case createdAt = "created_at"
    }
}

/// Response for pending delivery orders
public struct PendingDeliveryOrdersResponse: Codable {
    public let success: Bool
    public let count: Int
    public let orders: [PendingDeliveryOrder]
}

// MARK: - P2PAPIService Extension for Delivery Decision

extension P2PAPIService {

    /// Start the 60-second delivery decision window for an order
    public func startDeliveryDecision(
        orderId: Int,
        completion: @escaping (Result<StartDeliveryDecisionResponse, Error>) -> Void
    ) {
        guard let url = URL(string: "\(AppConfig.shared.p2pAPIBaseURL)/api/erp/orders/\(orderId)/start-delivery-decision") else {
            completion(.failure(P2PAPIError.invalidURL))
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let token = vendorToken {
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
                    let result = try JSONDecoder().decode(StartDeliveryDecisionResponse.self, from: data)
                    completion(.success(result))
                } catch {
                    completion(.failure(error))
                }
            }
        }.resume()
    }

    /// Restaurant makes delivery decision
    /// - Parameters:
    ///   - orderId: The order ID
    ///   - willDeliver: true if restaurant will deliver, false to pass to driver pool
    ///   - delivererName: Name of restaurant staff who will deliver (if willDeliver is true)
    public func makeDeliveryDecision(
        orderId: Int,
        willDeliver: Bool,
        delivererName: String? = nil,
        completion: @escaping (Result<DeliveryDecisionResponse, Error>) -> Void
    ) {
        guard let url = URL(string: "\(AppConfig.shared.p2pAPIBaseURL)/api/erp/orders/\(orderId)/restaurant-delivery-decision") else {
            completion(.failure(P2PAPIError.invalidURL))
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let token = vendorToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        var body: [String: Any] = ["will_deliver": willDeliver]
        if let name = delivererName {
            body["deliverer_name"] = name
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
                    let result = try JSONDecoder().decode(DeliveryDecisionResponse.self, from: data)
                    completion(.success(result))
                } catch {
                    completion(.failure(error))
                }
            }
        }.resume()
    }

    /// Get delivery decision status for an order
    public func getDeliveryDecisionStatus(
        orderId: Int,
        completion: @escaping (Result<DeliveryDecisionStatus, Error>) -> Void
    ) {
        guard let url = URL(string: "\(AppConfig.shared.p2pAPIBaseURL)/api/erp/orders/\(orderId)/delivery-decision-status") else {
            completion(.failure(P2PAPIError.invalidURL))
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let token = vendorToken {
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
                    let result = try JSONDecoder().decode(DeliveryDecisionStatus.self, from: data)
                    completion(.success(result))
                } catch {
                    completion(.failure(error))
                }
            }
        }.resume()
    }

    /// Get all orders pending restaurant delivery decision
    public func getPendingDeliveryOrders(
        vendorId: Int? = nil,
        completion: @escaping (Result<PendingDeliveryOrdersResponse, Error>) -> Void
    ) {
        var urlString = "\(AppConfig.shared.p2pAPIBaseURL)/api/erp/orders/pending-restaurant-delivery"
        if let vendorId = vendorId {
            urlString += "?vendor_id=\(vendorId)"
        }

        guard let url = URL(string: urlString) else {
            completion(.failure(P2PAPIError.invalidURL))
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let token = vendorToken {
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
                    let result = try JSONDecoder().decode(PendingDeliveryOrdersResponse.self, from: data)
                    completion(.success(result))
                } catch {
                    completion(.failure(error))
                }
            }
        }.resume()
    }

    // MARK: - KOT (Kitchen Order Ticket) / POS Integration API

    /// Get vendor's KOT/POS integration configuration
    public func getKOTConfig(
        vendorId: Int,
        completion: @escaping (Result<KOTConfigResponse, Error>) -> Void
    ) {
        guard let token = vendorToken else {
            completion(.failure(P2PAPIError.serverError("Unauthorized - please log in")))
            return
        }

        guard let url = URL(string: "\(baseURL)/vendor/kot-config") else {
            completion(.failure(P2PAPIError.invalidURL))
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

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
                        completion(.failure(P2PAPIError.serverError("Failed to get KOT config")))
                    }
                    return
                }

                do {
                    let result = try JSONDecoder().decode(KOTConfigResponse.self, from: data)
                    completion(.success(result))
                } catch {
                    completion(.failure(error))
                }
            }
        }.resume()
    }

    /// Update vendor's KOT/POS integration configuration
    public func updateKOTConfig(
        vendorId: Int,
        config: KOTConfigUpdate,
        completion: @escaping (Result<Bool, Error>) -> Void
    ) {
        guard let token = vendorToken else {
            completion(.failure(P2PAPIError.serverError("Unauthorized - please log in")))
            return
        }

        guard let url = URL(string: "\(baseURL)/vendor/kot-config") else {
            completion(.failure(P2PAPIError.invalidURL))
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        var body: [String: Any] = [
            "integration_type": config.integrationType,
            "enabled": config.enabled,
            "auto_print": config.autoPrint
        ]

        if let apiKey = config.apiKey, !apiKey.isEmpty { body["api_key"] = apiKey }
        if let apiSecret = config.apiSecret, !apiSecret.isEmpty { body["api_secret"] = apiSecret }
        if let locationId = config.locationId, !locationId.isEmpty { body["location_id"] = locationId }
        if let merchantId = config.merchantId, !merchantId.isEmpty { body["merchant_id"] = merchantId }
        if let restaurantGuid = config.restaurantGuid, !restaurantGuid.isEmpty { body["restaurant_guid"] = restaurantGuid }

        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        } catch {
            completion(.failure(error))
            return
        }

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
                        completion(.failure(P2PAPIError.serverError("Failed to update KOT config")))
                    }
                    return
                }

                completion(.success(true))
            }
        }.resume()
    }

    /// Test vendor's KOT/POS integration
    public func testKOTConnection(
        vendorId: Int,
        completion: @escaping (Result<KOTTestResponse, Error>) -> Void
    ) {
        guard let token = vendorToken else {
            completion(.failure(P2PAPIError.serverError("Unauthorized - please log in")))
            return
        }

        guard let url = URL(string: "\(baseURL)/vendor/kot-test") else {
            completion(.failure(P2PAPIError.invalidURL))
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

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
                    let result = try JSONDecoder().decode(KOTTestResponse.self, from: data)
                    completion(.success(result))
                } catch {
                    if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                       let errorMsg = json["error"] as? String {
                        completion(.success(KOTTestResponse(success: false, message: nil, posType: nil, posOrderId: nil, error: errorMsg)))
                    } else {
                        completion(.failure(error))
                    }
                }
            }
        }.resume()
    }

    /// Manually trigger KOT print for a specific order
    public func printKOT(
        orderId: Int,
        completion: @escaping (Result<KOTTestResponse, Error>) -> Void
    ) {
        guard let url = URL(string: "\(baseURL)/erp/orders/\(orderId)/print-kot") else {
            completion(.failure(P2PAPIError.invalidURL))
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let token = vendorToken {
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
                    let result = try JSONDecoder().decode(KOTTestResponse.self, from: data)
                    completion(.success(result))
                } catch {
                    completion(.failure(error))
                }
            }
        }.resume()
    }
}

// MARK: - KOT Configuration Models

public struct KOTConfigResponse: Codable {
    public let vendorId: Int
    public let integrationType: String
    public let enabled: Bool
    public let autoPrint: Bool
    public let locationId: String?
    public let merchantId: String?
    public let restaurantGuid: String?
    public let hasApiKey: Bool

    enum CodingKeys: String, CodingKey {
        case vendorId = "vendor_id"
        case integrationType = "integration_type"
        case enabled
        case autoPrint = "auto_print"
        case locationId = "location_id"
        case merchantId = "merchant_id"
        case restaurantGuid = "restaurant_guid"
        case hasApiKey = "has_api_key"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        vendorId = try container.decodeIfPresent(Int.self, forKey: .vendorId) ?? 0
        integrationType = try container.decodeIfPresent(String.self, forKey: .integrationType) ?? "none"
        enabled = try container.decodeIfPresent(Bool.self, forKey: .enabled) ?? false
        autoPrint = try container.decodeIfPresent(Bool.self, forKey: .autoPrint) ?? true
        locationId = try container.decodeIfPresent(String.self, forKey: .locationId)
        merchantId = try container.decodeIfPresent(String.self, forKey: .merchantId)
        restaurantGuid = try container.decodeIfPresent(String.self, forKey: .restaurantGuid)
        hasApiKey = try container.decodeIfPresent(Bool.self, forKey: .hasApiKey) ?? false
    }
}

public struct KOTConfigUpdate {
    public var integrationType: String
    public var enabled: Bool
    public var autoPrint: Bool
    public var apiKey: String?
    public var apiSecret: String?
    public var locationId: String?
    public var merchantId: String?
    public var restaurantGuid: String?

    public init(integrationType: String, enabled: Bool, autoPrint: Bool, apiKey: String? = nil, apiSecret: String? = nil, locationId: String? = nil, merchantId: String? = nil, restaurantGuid: String? = nil) {
        self.integrationType = integrationType
        self.enabled = enabled
        self.autoPrint = autoPrint
        self.apiKey = apiKey
        self.apiSecret = apiSecret
        self.locationId = locationId
        self.merchantId = merchantId
        self.restaurantGuid = restaurantGuid
    }
}

public struct KOTTestResponse: Codable {
    public let success: Bool
    public let message: String?
    public let posType: String?
    public let posOrderId: String?
    public let error: String?

    enum CodingKeys: String, CodingKey {
        case success, message, error
        case posType = "pos_type"
        case posOrderId = "pos_order_id"
    }

    public init(success: Bool, message: String?, posType: String?, posOrderId: String?, error: String?) {
        self.success = success
        self.message = message
        self.posType = posType
        self.posOrderId = posOrderId
        self.error = error
    }
}

// MARK: - Driver Earnings Response Models

public struct P2PDriverEarningsResponse: Codable {
    public let driverId: Int
    public let period: String
    public let earnings: P2PEarningsBreakdown
    public let multiPeriod: P2PMultiPeriodEarnings?
    public let dailyBreakdown: [P2PDailyEarning]?
    public let ratings: P2PRatingSummary?
    public let balance: P2PBalanceInfo?
    public let paymentHistory: [P2PPaymentHistoryItem]?

    enum CodingKeys: String, CodingKey {
        case driverId = "driver_id"
        case period, earnings
        case multiPeriod = "multi_period"
        case dailyBreakdown = "daily_breakdown"
        case ratings, balance
        case paymentHistory = "payment_history"
    }
}

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

public struct P2PRatingSummary: Codable {
    public let average: Double
    public let totalRatings: Int
    public let fiveStarCount: Int

    enum CodingKeys: String, CodingKey {
        case average
        case totalRatings = "total_ratings"
        case fiveStarCount = "five_star_count"
    }
}

public struct P2PBalanceInfo: Codable {
    public let available: Double
    public let pending: Double
    public let nextPayoutDate: String?

    enum CodingKeys: String, CodingKey {
        case available, pending
        case nextPayoutDate = "next_payout_date"
    }
}

public struct P2PPaymentHistoryItem: Codable {
    public let id: Int
    public let amount: Double
    public let type: String
    public let status: String
    public let date: String
}

// MARK: - Stripe Connect Response Models

public struct P2PStripeStatus: Codable {
    public let success: Bool
    public let hasStripeAccount: Bool
    public let stripeAccountId: String?
    public let onboarded: Bool
    public let chargesEnabled: Bool?
    public let payoutsEnabled: Bool?
    public let bankAccountLinked: Bool?
    public let bankAccount: P2PBankAccount?
    public let detailsSubmitted: Bool?
    public let requirements: P2PStripeRequirements?

    enum CodingKeys: String, CodingKey {
        case success
        case hasStripeAccount = "has_stripe_account"
        case stripeAccountId = "stripe_account_id"
        case onboarded
        case chargesEnabled = "charges_enabled"
        case payoutsEnabled = "payouts_enabled"
        case bankAccountLinked = "bank_account_linked"
        case bankAccount = "bank_account"
        case detailsSubmitted = "details_submitted"
        case requirements
    }
}

public struct P2PBankAccount: Codable {
    public let bankName: String?
    public let last4: String?
    public let routingNumber: String?
    public let accountHolderName: String?
    public let status: String?

    enum CodingKeys: String, CodingKey {
        case bankName = "bank_name"
        case last4
        case routingNumber = "routing_number"
        case accountHolderName = "account_holder_name"
        case status
    }
}

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

public struct P2PCartResponse: Codable {
    public let items: [P2PCartItem]
    public let summary: P2PCartSummary
    public let restaurantId: Int?
    public let restaurantName: String?

    enum CodingKeys: String, CodingKey {
        case items, summary
        case restaurantId = "restaurant_id"
        case restaurantName = "restaurant_name"
    }
}

public struct P2PCartItem: Codable, Identifiable {
    public let id: Int
    public let menuItemId: Int
    public let name: String
    public let quantity: Int
    public let price: Double
    public let totalPrice: Double
    public let specialInstructions: String?
    public let imageUrl: String?

    enum CodingKeys: String, CodingKey {
        case id
        case menuItemId = "menu_item_id"
        case name, quantity, price
        case totalPrice = "total_price"
        case specialInstructions = "special_instructions"
        case imageUrl = "image_url"
    }
}

public struct P2PCartSummary: Codable {
    public let subtotal: Double
    public let deliveryFee: Double
    public let platformFee: Double
    public let tax: Double
    public let discount: Double
    public let total: Double
    public let itemCount: Int
    public let restaurantCount: Int

    enum CodingKeys: String, CodingKey {
        case subtotal
        case deliveryFee = "delivery_fee"
        case platformFee = "platform_fee"
        case tax, discount, total
        case itemCount = "item_count"
        case restaurantCount = "restaurant_count"
    }
}

public struct P2PClearCartResponse: Codable {
    public let message: String
    public let summary: P2PCartSummary
}

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

public struct P2PProcessRefundResponse: Codable {
    public let success: Bool
    public let message: String
    public let refundId: String?
    public let orderId: Int
    public let refundAmount: Double
    public let refundStatus: String
    public let processedAt: String?

    enum CodingKeys: String, CodingKey {
        case success, message
        case refundId = "refund_id"
        case orderId = "order_id"
        case refundAmount = "refund_amount"
        case refundStatus = "refund_status"
        case processedAt = "processed_at"
    }
}
