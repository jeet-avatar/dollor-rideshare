import Foundation
import os

private let configLogger = Logger(subsystem: "ai.dollor.shared", category: "AppConfig")

/// Centralized configuration for all EatFair apps
/// Configuration is fetched from Dollar.ai (P2P) backend API
/// Firebase/Google is ONLY used for authentication
///
/// Environment URLs are loaded from Info.plist (set via xcconfig files):
/// - All xcconfigs (Development/Staging/Production, Debug/Release): https://api.dollor.ai (single backend)
public class AppConfig: ObservableObject {
    public static let shared = AppConfig()

    // MARK: - P2P API Configuration
    /// Dollar.ai backend base URL - all data comes from here
    /// Loaded from Info.plist API_BASE_URL (set via xcconfig)
    /// Fallback: production URL
    @Published public var p2pAPIBaseURL: String = {
        if let url = Bundle.main.object(forInfoDictionaryKey: "API_BASE_URL") as? String, !url.isEmpty {
            return url
        }
        // Fallback to production if xcconfig not applied
        configLogger.warning("API_BASE_URL not found in Info.plist, using production default")
        return "https://api.dollor.ai"
    }()

    /// CDN base URL for media assets (driver photos, vehicle photos, etc.)
    /// Loaded from Info.plist CDN_URL (set via xcconfig)
    /// Fallback: production API base URL
    @Published public var cdnBaseURL: String = {
        if let url = Bundle.main.object(forInfoDictionaryKey: "CDN_URL") as? String, !url.isEmpty {
            return url
        }
        // Fallback to API base URL if CDN not configured
        if let apiUrl = Bundle.main.object(forInfoDictionaryKey: "API_BASE_URL") as? String, !apiUrl.isEmpty {
            return apiUrl
        }
        return "https://api.dollor.ai"
    }()

    // MARK: - Microservice URLs (derived from base URL)
    // TODO: [CRITICAL] API mismatch — These URLs cause double-prefix when services add /api/... to their paths.
    // ChatService, NegotiationService, CallService all construct /api/chat/api/chat/..., /api/negotiation/api/negotiations/..., etc.
    // Fix: Either remove the /api/* suffixes here, or update service files to not include /api/ in their paths.
    /// Negotiation service for real-time price negotiation between drivers and customers
    public var negotiationServiceURL: String {
        return "\(p2pAPIBaseURL)/api/negotiation"
    }
    /// Chat service for real-time messaging between drivers and customers
    public var chatServiceURL: String {
        return "\(p2pAPIBaseURL)/api/chat"
    }
    /// Call service for privacy-protected phone calls (number masking)
    public var callServiceURL: String {
        return "\(p2pAPIBaseURL)/api/call"
    }

    // MARK: - Published Properties (hardcoded defaults, can be fetched from P2P API)
    // NOTE: These defaults MUST match pricing_config.py in the backend
    @Published public var taxRate: Double = 0.06  // 6% default tax (matches backend DEFAULT_TAX_RATE in order_flow.py:568)
    @Published public var baseDeliveryFee: Double = 2.99  // Delivery fee (matches backend DELIVERY_FEE_CONFIG.base_fee)
    @Published public var extraStopFee: Double = 2.0
    @Published public var platformFeePerRestaurant: Double = 1.0  // $1 platform fee (matches PLATFORM_FEE_CONFIG.flat_fee)
    @Published public var maxRestaurantsPerOrder: Int = 3
    @Published public var serviceFeeRate: Double = 0.0  // DEPRECATED: Dollor.ai uses flat $1 fees, NOT percentage
    @Published public var smallOrderThreshold: Double = 10.0
    @Published public var smallOrderFee: Double = 2.0

    // =============================================================================
    // DOLLOR.AI PRICING MODEL
    // =============================================================================
    // MATCHMAKING SERVICE - We connect parties, not deliver or drive
    //
    // FOOD DELIVERY - FLAT $1 PRICING (No tiered pricing):
    //   Customer pays: $1 flat per order (per restaurant)
    //   Restaurant pays: $1 flat per order
    //   Driver pays: $0 (FREE - keeps 100% + tips)
    //   Tips: 100% go to driver
    //
    // RIDESHARE - TIERED FARE-BASED PRICING:
    //   Fares up to $35:    $1 rider + $1 driver (Tier 1)
    //   Fares $35.01-$70:   $2 rider + $2 driver (Tier 2)
    //   Fares above $70:    $3 rider + $3 driver (Tier 3)
    //   Tips: 100% go to driver
    //
    // Examples:
    //   $20 fare  -> $1 (Tier 1)
    //   $35 fare  -> $1 (Tier 1)
    //   $50 fare  -> $2 (Tier 2)
    //   $70 fare  -> $2 (Tier 2)
    //   $80 fare  -> $3 (Tier 3)
    //   $100 fare -> $3 (Tier 3)
    //
    // Total transparency - no hidden fees!
    // =============================================================================

    // FOOD DELIVERY - FLAT $1 FEES
    @Published public var foodCustomerFee: Double = 1.00      // $1 flat per order
    @Published public var foodRestaurantFee: Double = 1.00    // $1 flat per restaurant
    @Published public var foodDriverFee: Double = 0.00        // FREE - drivers keep 100%
    @Published public var tipPlatformFee: Double = 0.00       // 100% of tips go to driver

    // RIDESHARE - TIERED FARE-BASED PRICING. Must match the backend charge logic
    // (rideshare_payments.py get_tier_fee: <=$35 -> $1, <=$70 -> $2, else $3) and Android AppConfig.
    // Fare tier thresholds (in dollars)
    @Published public var rideshareTier1MaxFare: Double = 35.00   // Fares up to $35
    @Published public var rideshareTier2MaxFare: Double = 70.00   // Fares $35.01 to $70
    // Tier 3: Fares above $70 (capped at $3)

    // Platform fees per fare tier (both rider AND driver pay)
    @Published public var rideshareTier1Fee: Double = 1.00   // $1 for fares ≤ $35
    @Published public var rideshareTier2Fee: Double = 2.00   // $2 for fares $35.01-$70
    @Published public var rideshareTier3Fee: Double = 3.00   // $3 for fares > $70
    /// CPUC Access for All share deducted from the driver's payout (backend: access_for_all_fee.driver_share).
    @Published public var rideshareDriverRegulatoryShare: Double = 0.05

    // Driver bid presets as a share of the suggested fare (same on Android AppConfig)
    // Defaults mirror the backend; GET /api/config/rideshare replaces them (see applyRideshareConfig).
    @Published public var bidQuickAcceptFactor: Double = 0.92
    @Published public var bidFairFactor: Double = 1.00
    @Published public var bidPremiumFactor: Double = 1.08
    @Published public var biddingWindowMinutes: Int = 5
    @Published public var maxCustomerCounters: Int = 3
    @Published public var maxRoundsPerBid: Int = 2
    @Published public var noShowWaitSeconds: Int = 300
    @Published public var noShowFee: Double = 5.00
    @Published public var noShowDriverShare: Double = 0.80
    @Published public var etaOptionsMinutes: [Int] = [3, 5, 10, 15]

    // Legacy properties (kept for backwards compatibility)
    @Published public var ridesharePlatformFeePerMile: Double = 0.10  // Deprecated
    @Published public var ridesharePlatformFeeMinimum: Double = 1.00  // Deprecated
    // Distance-based properties deprecated - use fare-based above
    @Published public var rideshareDistanceTier1Max: Double = 10.0   // Deprecated
    @Published public var rideshareDistanceTier2Max: Double = 20.0   // Deprecated
    @Published public var rideshareDistanceTier1Fee: Double = 1.00   // Deprecated
    @Published public var rideshareDistanceTier2Fee: Double = 2.00   // Deprecated
    @Published public var rideshareDistanceTier3Fee: Double = 3.00   // Deprecated

    // Legacy properties (kept for backwards compatibility)
    @Published public var serviceFee: Double = 1.00           // Legacy - use foodCustomerFee
    @Published public var deliveryFee: Double = 2.99          // Base delivery fee (to driver)
    @Published public var restaurantPlatformFee: Double = 1.0 // Legacy - use foodRestaurantFee

    /// Get customer matchmaking fee for food delivery.
    /// Always $1 flat - no tiered pricing for food.
    public func getCustomerDeliveryFee(orderSubtotal: Double) -> Double {
        return foodCustomerFee
    }

    /// Get restaurant platform fee.
    /// Always $1 flat per restaurant.
    public func getRestaurantPlatformFee(orderSubtotal: Double) -> Double {
        return foodRestaurantFee
    }

    /// Get food delivery fee description for UI display.
    public func getFoodFeeDescription() -> String {
        return "$1 Matchmaking Fee"
    }

    /// Legacy method - use getFoodFeeDescription() instead
    public func getFeeTierDescription(orderSubtotal: Double) -> String {
        return getFoodFeeDescription()
    }

    /// Calculate TIERED FARE-BASED platform fee for RIDESHARE.
    /// Fares ≤$35: $1, $35.01-$70: $2, >$70: $3
    /// Both rider AND driver pay this same fee.
    public func calculateRidesharePlatformFee(fareAmount: Double) -> Double {
        if fareAmount <= rideshareTier1MaxFare {
            return rideshareTier1Fee  // $1
        } else if fareAmount <= rideshareTier2MaxFare {
            return rideshareTier2Fee  // $2
        } else {
            return rideshareTier3Fee  // $3
        }
    }

    /// Legacy method - kept for backwards compatibility.
    /// Now uses fare-based calculation (estimates fare from distance).
    public func calculateRidesharePlatformFee(distanceMiles: Double) -> Double {
        // Estimate fare from distance (average ~$1.50/mile + $5 base)
        let estimatedFare = 5.0 + (distanceMiles * 1.50)
        return calculateRidesharePlatformFee(fareAmount: estimatedFare)
    }

    /// Get rideshare fare tier (1, 2, or 3) based on fare amount.
    public func getRideshareTier(fareAmount: Double) -> Int {
        if fareAmount <= rideshareTier1MaxFare {
            return 1
        } else if fareAmount <= rideshareTier2MaxFare {
            return 2
        } else {
            return 3
        }
    }

    /// Get rideshare platform fee breakdown for display (fare-based).
    public func getRidesharePlatformFeeBreakdown(fareAmount: Double) -> (fee: Double, description: String, tier: Int) {
        let fee = calculateRidesharePlatformFee(fareAmount: fareAmount)
        let tier = getRideshareTier(fareAmount: fareAmount)
        let tierDesc = tier == 1 ? "≤\(Self.money(rideshareTier1MaxFare))" : tier == 2 ? "\(Self.money(rideshareTier1MaxFare))-\(Self.money(rideshareTier2MaxFare))" : ">\(Self.money(rideshareTier2MaxFare))"
        let description = "$\(String(format: "%.2f", fee)) (Tier \(tier): \(tierDesc))"
        return (fee, description, tier)
    }

    /// Whole-dollar money text for fee-tier labels, derived from the tier config (never hardcode tiers in UI).
    static func money(_ value: Double) -> String { "$\(Int(value.rounded()))" }

    /// One-line fee summary for FAQ / legal copy, e.g. "$1 for fares up to $25, $2 for fares $25-$50, $3 for fares over $50".
    /// "$1" for whole amounts, "$1.50" otherwise, so fractional fees are never truncated.
    static func feeAmount(_ value: Double) -> String {
        value == value.rounded() ? "$\(Int(value))" : String(format: "$%.2f", value)
    }

    /// Lowest-to-highest platform fee, e.g. "$1-$3". Always in sync with the tier config.
    public var rideshareFeeRangeText: String {
        "\(Self.feeAmount(rideshareTier1Fee))-\(Self.feeAmount(rideshareTier3Fee))"
    }

    public var rideshareFeeSummary: String {
        "\(Self.feeAmount(rideshareTier1Fee)) for fares up to \(Self.money(rideshareTier1MaxFare)), \(Self.feeAmount(rideshareTier2Fee)) for fares \(Self.money(rideshareTier1MaxFare))-\(Self.money(rideshareTier2MaxFare)), \(Self.feeAmount(rideshareTier3Fee)) for fares over \(Self.money(rideshareTier2MaxFare))"
    }

    /// Human-readable fee tiers for UI/legal copy, always in sync with the tier config above.
    public var rideshareTierRows: [(label: String, fee: String)] {
        [
            ("Fares up to \(Self.money(rideshareTier1MaxFare))", "\(Self.feeAmount(rideshareTier1Fee)) flat"),
            ("Fares \(Self.money(rideshareTier1MaxFare))-\(Self.money(rideshareTier2MaxFare))", "\(Self.feeAmount(rideshareTier2Fee)) flat"),
            ("Fares over \(Self.money(rideshareTier2MaxFare))", "\(Self.feeAmount(rideshareTier3Fee)) flat")
        ]
    }

    /// Get rideshare tier name for display (fare-based).
    public func getRideshareTierName(fareAmount: Double) -> String {
        let tier = getRideshareTier(fareAmount: fareAmount)
        let tierDesc = tier == 1 ? "up to \(Self.money(rideshareTier1MaxFare))" : tier == 2 ? "\(Self.money(rideshareTier1MaxFare))-\(Self.money(rideshareTier2MaxFare))" : "above \(Self.money(rideshareTier2MaxFare))"
        return "Tier \(tier) (\(tierDesc))"
    }

    /// Get rideshare fee description for UI display.
    public func getRideshareFeeDescription(fareAmount: Double) -> String {
        let fee = calculateRidesharePlatformFee(fareAmount: fareAmount)
        let tier = getRideshareTier(fareAmount: fareAmount)
        return "$\(String(format: "%.0f", fee)) Platform Fee (Tier \(tier))"
    }

    // MARK: - Legacy Distance-Based Methods (Deprecated)

    /// Legacy method - use getRideshareTier(fareAmount:) instead.
    @available(*, deprecated, message: "Use getRideshareTier(fareAmount:) instead")
    public func getRideshareDistanceTier(distanceMiles: Double) -> Int {
        let estimatedFare = 5.0 + (distanceMiles * 1.50)
        return getRideshareTier(fareAmount: estimatedFare)
    }

    /// Legacy method - use getRideshareTierName(fareAmount:) instead.
    @available(*, deprecated, message: "Use getRideshareTierName(fareAmount:) instead")
    public func getRideshareTierName(distanceMiles: Double) -> String {
        let estimatedFare = 5.0 + (distanceMiles * 1.50)
        return getRideshareTierName(fareAmount: estimatedFare)
    }

    /// Legacy method - use getRideshareFeeDescription(fareAmount:) instead.
    @available(*, deprecated, message: "Use getRideshareFeeDescription(fareAmount:) instead")
    public func getRideshareFeeDescription(distanceMiles: Double) -> String {
        let estimatedFare = 5.0 + (distanceMiles * 1.50)
        return getRideshareFeeDescription(fareAmount: estimatedFare)
    }

    /// Legacy method - use getRidesharePlatformFeeBreakdown(fareAmount:) instead.
    @available(*, deprecated, message: "Use getRidesharePlatformFeeBreakdown(fareAmount:) instead")
    public func getRidesharePlatformFeeBreakdown(distanceMiles: Double) -> (fee: Double, description: String, tier: Int) {
        let estimatedFare = 5.0 + (distanceMiles * 1.50)
        return getRidesharePlatformFeeBreakdown(fareAmount: estimatedFare)
    }

    // Driver/Delivery Config (matches pricing_config.py)
    @Published public var perMileDeliveryFee: Double = 0.50  // Per mile fee (matches DELIVERY_FEE_CONFIG.per_mile_fee)
    @Published public var maxDeliveryFee: Double = 12.99  // Max delivery fee cap (matches DELIVERY_FEE_CONFIG.max_fee)
    @Published public var defaultTipRate: Double = 0.15
    @Published public var nearbyDistanceMeters: Double = 3218.69 // 2 miles
    @Published public var maxDeliveryDistanceMiles: Double = 15.0  // Max distance (matches DELIVERY_FEE_CONFIG.max_delivery_distance)

    // MARK: - Driver Polling + Location Constants
    /// How often the delivery/rideshare polling timers fire (seconds). Matches Android 5s standard (Quick-64).
    @Published public var driverPollingInterval: TimeInterval = 5.0
    /// Minimum gap between location updates sent to the backend (seconds). Prevents excessive PUT /auth/driver/location calls.
    @Published public var locationUpdateMinInterval: TimeInterval = 3.0
    /// Rate-limit window for order acceptance (seconds). Prevents double-tap race conditions.
    @Published public var orderAcceptanceRateLimitInterval: TimeInterval = 2.0
    /// Consecutive polling failures before showing connection warning in RideBiddingViewModel.
    public let maxPollingFailuresBeforeWarning: Int = 3
    /// Maximum rideshare search radius in kilometers. Caps global ride fetches when location unavailable.
    public let rideshareSearchRadiusKm: Double = 100.0

    // Tip options (in dollars for rideshare, percentages for delivery)
    @Published public var rideTipOptions: [Double] = [0.0, 2.0, 5.0, 10.0]  // Dollar amounts
    @Published public var deliveryTipPercentages: [Int] = [0, 15, 20, 25]   // Percentages

    // Driver earnings info (for transparency display)
    @Published public var driverEarningsPercentage: Int = 96  // Drivers keep 96% of fare

    // AI/Analytics Thresholds
    @Published public var busyLevelThresholds: BusyLevelThresholds = BusyLevelThresholds()
    @Published public var defaultPrepTimeMinutes: Int = 20
    @Published public var maxPrepTimeMinutes: Int = 60
    @Published public var additionalPrepTimePerOrder: Int = 3

    // MARK: - Rideshare Configuration
    // TIERED DISTANCE-BASED PRICING (for rideshare):
    //   - Trips 0-10 miles:   $1 rider + $1 driver (Tier 1)
    //   - Trips 10-20 miles:  $2 rider + $2 driver (Tier 2)
    //   - Trips 20+ miles:    $3 rider + $3 driver (Tier 3)

    @Published public var rideBaseFare: Double = 2.50          // Minimum base fare
    @Published public var ridePerMileRate: Double = 1.15       // Per mile rate
    @Published public var ridePerMinuteRate: Double = 0.18     // Per minute rate
    @Published public var rideMinFare: Double = 8.00           // Minimum fare (matches backend pricing_config.py:21 MINIMUM_FARE)
    @Published public var rideCancellationFee: Double = 0.00   // Rider cancel fee; the server charges none today (replaced by /api/config/rideshare)
    @Published public var rideCancellationFeeDriverEnRoute: Double = 0.00  // Server charges no rider cancel fee today (bid_routes.py cancel); keep UI truthful
    @Published public var rideCancellationFeeInProgress: Double = 0.00    // Server blocks cancelling in-progress rides; no fee is charged
    @Published public var rideSurgeEnabled: Bool = true        // Surge pricing enabled
    @Published public var rideMaxSurgeMultiplier: Double = 3.0 // Maximum surge multiplier

    /// Get rider platform fee based on fare amount (TIERED).
    public func getRiderPlatformFee(fareAmount: Double) -> Double {
        return calculateRidesharePlatformFee(fareAmount: fareAmount)
    }

    /// Get driver platform access fee based on fare amount (TIERED).
    public func getDriverPlatformFee(fareAmount: Double) -> Double {
        return calculateRidesharePlatformFee(fareAmount: fareAmount)
    }

    /// Legacy method - use getRiderPlatformFee() instead
    public func getRidesharePlatformFee(fareAmount: Double) -> Double {
        return calculateRidesharePlatformFee(fareAmount: fareAmount)
    }

    /// Calculate rideshare fare (before platform fees).
    public func calculateRideFare(distanceMiles: Double, durationMinutes: Double = 0.0) -> Double {
        let distanceFare = distanceMiles * ridePerMileRate
        let timeFare = durationMinutes * ridePerMinuteRate
        return max(rideMinFare, rideBaseFare + distanceFare + timeFare)
    }

    /// Calculate driver earnings after platform fee (DISTANCE-BASED).
    /// Driver pays $1 per 10 miles (same as rider).
    public func calculateDriverEarnings(fare: Double, distanceMiles: Double, tip: Double = 0.0) -> Double {
        let platformFee = calculateRidesharePlatformFee(distanceMiles: distanceMiles)
        return fare - platformFee + tip
    }

    /// Legacy method - use calculateDriverEarnings(fare:distanceMiles:tip:) instead.
    public func calculateDriverEarnings(fare: Double, tip: Double = 0.0) -> Double {
        let platformFee = calculateRidesharePlatformFee(fareAmount: fare)
        return fare - platformFee + tip
    }

    /// Calculate total rider payment (DISTANCE-BASED).
    /// Rider pays: fare + platform fee + tip
    public func calculateRiderTotal(fare: Double, distanceMiles: Double, tip: Double = 0.0) -> Double {
        let platformFee = calculateRidesharePlatformFee(distanceMiles: distanceMiles)
        return fare + platformFee + tip
    }

    /// Legacy method - use calculateRiderTotal(fare:distanceMiles:tip:) instead.
    public func calculateRiderTotal(fare: Double, tip: Double = 0.0) -> Double {
        let platformFee = calculateRidesharePlatformFee(fareAmount: fare)
        return fare + platformFee + tip
    }

    /// Get rideshare fee tier description for UI display.
    public func getRideshareTierDescription(fareAmount: Double) -> String {
        return getRideshareTierName(fareAmount: fareAmount)
    }

    /// Get rideshare fee tier description with distance (preferred method).
    public func getRideshareTierDescription(distanceMiles: Double) -> String {
        let estimatedFare = 5.0 + (distanceMiles * 1.50)
        let tier = getRideshareTier(fareAmount: estimatedFare)
        let fee = calculateRidesharePlatformFee(distanceMiles: distanceMiles)
        let tierDesc = tier == 1 ? "≤10mi" : tier == 2 ? "10-20mi" : ">20mi"
        return "$\(Int(fee)) (Tier \(tier): \(tierDesc))"
    }

    // Support - Using Production API
    @Published public var supportUrl: String = "https://www.dollor.ai/support"
    @Published public var supportPhone: String = "+1-800-365-5671"
    @Published public var supportEmail: String = "support@dollor.ai"
    /// Shown only when the backend configures them, so the app never displays an unconfirmed claim.
    @Published public var supportHoursText: String?
    @Published public var supportResponseMinutes: Int?
    @Published public var achFeeDiscountText: String?
    /// e.g. "$5 off your first ride"; nil until the backend configures a real reward.
    @Published public var referralRewardText: String?

    // Legal URLs (Required for App Store - Apple Guideline 5.1.1)
    public var termsOfServiceUrl: String { AppConstants.termsOfServiceURL }
    public var privacyPolicyUrl: String { AppConstants.privacyPolicyURL }

    // Feature Flags - Production defaults
    // LIVE PAYMENTS ENABLED - Real Stripe integration active
    @Published public var isDummyPaymentMode: Bool = false  // Real payments enabled
    @Published public var isAIFeaturesEnabled: Bool = true
    @Published public var isDynamicPricingEnabled: Bool = false

    private var configLoaded = false

    private static let rideshareConfigCacheKey = "rideshare_config_json"

    private init() {
        if let cached = UserDefaults.standard.data(forKey: Self.rideshareConfigCacheKey),
           let json = try? JSONSerialization.jsonObject(with: cached) as? [String: Any] {
            applyRideshareConfig(json)
        }
    }

    // MARK: - Rideshare policy from the backend (fees, bidding presets, support)

    /// Fetches GET /api/config/rideshare, applies it and caches the last good response for offline launches.
    public func fetchRideshareConfig() {
        guard let url = URL(string: "\(p2pAPIBaseURL)/api/config/rideshare") else { return }
        URLSession.shared.dataTask(with: url) { [weak self] data, response, _ in
            guard let self = self,
                  (response as? HTTPURLResponse)?.statusCode == 200,
                  let data = data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                configLogger.warning("Using cached/default rideshare config")
                return
            }
            UserDefaults.standard.set(data, forKey: Self.rideshareConfigCacheKey)
            DispatchQueue.main.async { self.applyRideshareConfig(json) }
        }.resume()
    }

    /// Replaces policy values with the backend's. Missing keys keep their current value.
    func applyRideshareConfig(_ json: [String: Any]) {
        if let fees = json["fees"] as? [String: Any] {
            if let v = fees["tier1MaxFare"] as? Double { rideshareTier1MaxFare = v }
            if let v = fees["tier2MaxFare"] as? Double { rideshareTier2MaxFare = v }
            if let v = fees["tier1Fee"] as? Double { rideshareTier1Fee = v }
            if let v = fees["tier2Fee"] as? Double { rideshareTier2Fee = v }
            if let v = fees["tier3Fee"] as? Double { rideshareTier3Fee = v }
            if let v = fees["accessForAllDriverShare"] as? Double { rideshareDriverRegulatoryShare = v }
            if let v = fees["riderCancellationFee"] as? Double {
                rideCancellationFee = v
                rideCancellationFeeDriverEnRoute = v
            }
        }
        if let pricing = json["pricing"] as? [String: Any] {
            if let v = pricing["baseFare"] as? Double { rideBaseFare = v }
            if let v = pricing["perMileRate"] as? Double { ridePerMileRate = v }
            if let v = pricing["perMinuteRate"] as? Double { ridePerMinuteRate = v }
            if let v = pricing["minimumFare"] as? Double { rideMinFare = v }
        }
        if let bidding = json["bidding"] as? [String: Any] {
            if let v = bidding["quickAcceptFactor"] as? Double { bidQuickAcceptFactor = v }
            if let v = bidding["fairFactor"] as? Double { bidFairFactor = v }
            if let v = bidding["premiumFactor"] as? Double { bidPremiumFactor = v }
            if let v = bidding["windowMinutes"] as? Int { biddingWindowMinutes = v }
            if let v = bidding["maxCustomerCounters"] as? Int { maxCustomerCounters = v }
            if let v = bidding["maxRoundsPerBid"] as? Int { maxRoundsPerBid = v }
            if let v = bidding["etaOptionsMinutes"] as? [Int], !v.isEmpty { etaOptionsMinutes = v }
        }
        if let noShow = json["noShow"] as? [String: Any] {
            if let v = noShow["waitSeconds"] as? Int { noShowWaitSeconds = v }
            if let v = noShow["fee"] as? Double { noShowFee = v }
            if let v = noShow["driverShare"] as? Double { noShowDriverShare = v }
        }
        if let referral = json["referral"] as? [String: Any] {
            referralRewardText = referral["rewardText"] as? String
        }
        if let support = json["support"] as? [String: Any] {
            if let v = support["email"] as? String, !v.isEmpty { supportEmail = v }
            if let v = support["phone"] as? String, !v.isEmpty { supportPhone = v }
            if let v = support["url"] as? String, !v.isEmpty { supportUrl = v }
            supportHoursText = support["hoursText"] as? String
            supportResponseMinutes = support["responseMinutes"] as? Int
            achFeeDiscountText = support["achFeeDiscountText"] as? String
        }
    }

    // MARK: - Fetch Configuration from P2P (Dollar.ai) Backend

    /// Fetches app configuration from Dollar.ai backend
    /// All data comes from P2P backend - Firebase is only for authentication
    public func fetchConfig(completion: ((Bool) -> Void)? = nil) {
        // The rideshare endpoint owns support and ride pricing: it is fetched only AFTER /api/config
        // has been applied (or has failed), so the two responses can never race on the same properties.
        guard let url = URL(string: "\(p2pAPIBaseURL)/api/config") else {
            configLogger.error("Invalid URL for config endpoint")
            // Use default values if API fails
            self.configLoaded = true
            self.fetchRideshareConfig()
            completion?(true)
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            guard let self = self else { return }

            // If API fails, use default values (already set above)
            guard error == nil, let data = data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                configLogger.warning("Using default configuration (P2P API not available)")
                DispatchQueue.main.async {
                    self.configLoaded = true
                    self.fetchRideshareConfig()
            completion?(true)
                }
                return
            }

            DispatchQueue.main.async {
                // Fees (from P2P API response)
                if let taxRate = json["taxRate"] as? Double { self.taxRate = taxRate }
                if let baseDeliveryFee = json["baseDeliveryFee"] as? Double { self.baseDeliveryFee = baseDeliveryFee }
                if let extraStopFee = json["extraStopFee"] as? Double { self.extraStopFee = extraStopFee }
                if let maxRestaurants = json["maxRestaurantsPerOrder"] as? Int { self.maxRestaurantsPerOrder = maxRestaurants }

                // Uber-style Fee Structure
                if let serviceFee = json["serviceFee"] as? Double { self.serviceFee = serviceFee }
                if let deliveryFee = json["deliveryFee"] as? Double { self.deliveryFee = deliveryFee }
                if let restaurantFee = json["restaurantPlatformFee"] as? Double { self.restaurantPlatformFee = restaurantFee }

                // Delivery
                if let tipRate = json["defaultTipRate"] as? Double { self.defaultTipRate = tipRate }
                if let nearbyDist = json["nearbyDistanceMeters"] as? Double { self.nearbyDistanceMeters = nearbyDist }
                if let maxDist = json["maxDeliveryDistanceMiles"] as? Double { self.maxDeliveryDistanceMiles = maxDist }

                // Prep Time
                if let defaultPrep = json["defaultPrepTimeMinutes"] as? Int { self.defaultPrepTimeMinutes = defaultPrep }
                if let maxPrep = json["maxPrepTimeMinutes"] as? Int { self.maxPrepTimeMinutes = maxPrep }

                // Support
                if let supportUrl = json["supportUrl"] as? String { self.supportUrl = supportUrl }
                if let supportPhone = json["supportPhone"] as? String { self.supportPhone = supportPhone }
                if let supportEmail = json["supportEmail"] as? String { self.supportEmail = supportEmail }

                // Feature Flags
                // APP STORE FIX: Never allow dummy payment mode in Release builds
                #if DEBUG
                if let dummyMode = json["isDummyPaymentMode"] as? Bool { self.isDummyPaymentMode = dummyMode }
                #else
                // In Release builds, always use real payments - ignore backend flag
                self.isDummyPaymentMode = false
                #endif
                if let aiEnabled = json["isAIFeaturesEnabled"] as? Bool { self.isAIFeaturesEnabled = aiEnabled }
                if let dynamicPricing = json["isDynamicPricingEnabled"] as? Bool { self.isDynamicPricingEnabled = dynamicPricing }

                // Rideshare Pricing (from backend)
                if let rideBaseFare = json["rideBaseFare"] as? Double { self.rideBaseFare = rideBaseFare }
                if let ridePerMileRate = json["ridePerMileRate"] as? Double { self.ridePerMileRate = ridePerMileRate }
                if let ridePerMinuteRate = json["ridePerMinuteRate"] as? Double { self.ridePerMinuteRate = ridePerMinuteRate }
                // ridePlatformFee is now tiered - use rideshareTier1Fee, rideshareTier2Fee, rideshareTier3Fee instead
                if let rideMinFare = json["rideMinFare"] as? Double { self.rideMinFare = rideMinFare }
                if let rideCancellationFee = json["rideCancellationFee"] as? Double { self.rideCancellationFee = rideCancellationFee }
                if let rideCancellationFeeDriverEnRoute = json["rideCancellationFeeDriverEnRoute"] as? Double { self.rideCancellationFeeDriverEnRoute = rideCancellationFeeDriverEnRoute }
                if let rideCancellationFeeInProgress = json["rideCancellationFeeInProgress"] as? Double { self.rideCancellationFeeInProgress = rideCancellationFeeInProgress }
                if let rideSurgeEnabled = json["rideSurgeEnabled"] as? Bool { self.rideSurgeEnabled = rideSurgeEnabled }
                if let rideMaxSurgeMultiplier = json["rideMaxSurgeMultiplier"] as? Double { self.rideMaxSurgeMultiplier = rideMaxSurgeMultiplier }

                // Per mile delivery fee
                if let perMileDeliveryFee = json["perMileDeliveryFee"] as? Double { self.perMileDeliveryFee = perMileDeliveryFee }
                if let maxDeliveryFee = json["maxDeliveryFee"] as? Double { self.maxDeliveryFee = maxDeliveryFee }

                self.configLoaded = true
                configLogger.info("Configuration loaded from Dollar.ai backend")
                self.fetchRideshareConfig()
            completion?(true)
            }
        }.resume()
    }

    // MARK: - App Version

    public var appVersion: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(version) (\(build))"
    }

    public var bundleIdentifier: String {
        Bundle.main.bundleIdentifier ?? "com.dollor.unknown"
    }
}

// MARK: - Supporting Types

public struct BusyLevelThresholds {
    public var slow: Int = 2
    public var normal: Int = 5
    public var busy: Int = 8

    public init(slow: Int = 2, normal: Int = 5, busy: Int = 8) {
        self.slow = slow
        self.normal = normal
        self.busy = busy
    }
}

// MARK: - Order Status Constants

public struct OrderStatusConstants {
    public static let placed = "Placed"
    public static let accepted = "Accepted"
    public static let preparing = "Preparing"
    public static let ready = "Ready"
    public static let pickedUp = "Picked Up"
    public static let outForDelivery = "Out for Delivery"
    public static let delivered = "Delivered"
    public static let rejected = "Rejected"
    public static let cancelled = "Cancelled"

    public static let activeStatuses = [placed, accepted, preparing, ready, pickedUp, outForDelivery]
    public static let completedStatuses = [delivered]
    public static let cancelledStatuses = [rejected, cancelled]
}

// MARK: - API Endpoints (P2P Backend / Dollar.ai)
// NOTE: Firebase is ONLY used for authentication
// All data comes from Dollar.ai P2P backend

public struct APIEndpoints {
    /// PRODUCTION ENVIRONMENT - api.dollor.ai
    public static let baseURL = "https://api.dollor.ai"

    // Customer endpoints
    public static let customerAuth = "/api/customer/google-auth"
    public static let customerOrders = "/api/customer/orders"
    public static let restaurants = "/api/erp/restaurants"
    public static let restaurantMenu = "/api/erp/restaurants"  // + /{id}/menu

    // Driver endpoints
    public static let driverAuth = "/api/erp/drivers/login"
    public static let driverRegister = "/api/erp/drivers/register"
    public static let availableOrders = "/api/erp/orders/available-for-delivery"
    public static let driverDeliveries = "/api/erp/orders/driver"  // + /{id}/active

    // Order flow endpoints
    public static let createOrder = "/api/erp/orders/create"
    public static let orderStatus = "/api/erp/orders"  // + /{id}/status
    public static let assignDriver = "/api/erp/orders"  // + /{id}/assign-driver

    // Config endpoint
    public static let appConfig = "/api/config"
}

// MARK: - Map Configuration

public struct MapConfig {
    public static let defaultZoomSpan: Double = 0.05
    public static let detailedZoomSpan: Double = 0.01
    public static let overviewZoomSpan: Double = 0.1

    // Default fallback coordinates (Irvine, CA - Orange County)
    // These are only used when user location is unavailable
    // In production, always prioritize user's actual location
    public static let defaultLatitude: Double = 33.6846
    public static let defaultLongitude: Double = -117.8265

    /// Returns default coordinates as CLLocationCoordinate2D
    /// Only use this as a fallback when user location is unavailable
    public static var defaultCoordinate: (latitude: Double, longitude: Double) {
        (defaultLatitude, defaultLongitude)
    }
}

// MARK: - UserDefaults Keys (Centralized)

public struct UserDefaultsKeys {
    // MARK: - Customer App
    public static let selectedAddressId = "selectedAddressId"
    public static let customerAccessToken = "p2p_customer_access_token"
    public static let customerId = "p2p_customer_id"
    public static let customerName = "p2p_customer_name"
    public static let customerEmail = "p2p_customer_email"

    // MARK: - Vendor/Restaurant App
    public static let vendorAccessToken = "p2p_access_token"
    public static let vendorId = "p2p_vendor_id"
    public static let vendorName = "p2p_vendor_name"
    public static let vendorEmail = "p2p_vendor_email"

    // MARK: - Driver App
    public static let driverAccessToken = "p2p_driver_access_token"
    public static let driverId = "p2p_driver_id"
    public static let driverName = "p2p_driver_name"
    public static let driverEmail = "p2p_driver_email"
    public static let driverCode = "p2p_driver_code"
    public static let driverTermsAccepted = "p2p_driver_terms_accepted"
    public static let driverFCMToken = "driver_fcm_token"

    // MARK: - App Settings
    public static let notificationsEnabled = "notifications_enabled"
    public static let darkModeEnabled = "dark_mode_enabled"
    public static let lastKnownLatitude = "last_known_latitude"
    public static let lastKnownLongitude = "last_known_longitude"

    // MARK: - Terms & Conditions
    public static let driverTermsAcceptedAt = "p2p_driver_terms_accepted_at"
    public static let driverTermsVersion = "p2p_driver_terms_version"
}

// MARK: - App Constants

public struct AppConstants {
    // Current terms version - increment when terms change
    public static let termsVersion = "1.1"

    // Company Information - Matches Android AppConfig.Legal
    public static let companyName = "Zietra Technologies Inc"
    public static let contactEmail = "support@dollor.ai"
    public static let supportURL = "https://www.dollor.ai/support"

    // Legal URLs (Required for App Store - Apple Guideline 5.1.1)
    // PRODUCTION ENVIRONMENT - api.dollor.ai
    public static let termsOfServiceURL = "https://api.dollor.ai/terms"
    public static let privacyPolicyURL = "https://api.dollor.ai/privacy"
    public static let driverApplicationURL = "https://dollor.ai/driver-application"
    public static let adminPanelURL = "https://www.dollor.ai/admin"
    public static let vendorDocumentsURL = "https://www.dollor.ai/vendor/documents"
    public static let appDownloadURL = "https://dollor.ai/app"
}

// MARK: - State Tax Rates (matches pricing_config.py STATE_TAX_RATES)
// US state tax rates for rideshare/delivery services
public struct StateTaxRates {
    /// State tax rate lookup - matches backend pricing_config.py
    public static let rates: [String: Double] = [
        "AL": 0.04, "AK": 0.0, "AZ": 0.056, "AR": 0.065,
        "CA": 0.0725, "CO": 0.029, "CT": 0.0635, "DE": 0.0,
        "FL": 0.06, "GA": 0.04, "HI": 0.04, "ID": 0.06,
        "IL": 0.0625, "IN": 0.07, "IA": 0.06, "KS": 0.065,
        "KY": 0.06, "LA": 0.0445, "ME": 0.055, "MD": 0.06,
        "MA": 0.0625, "MI": 0.06, "MN": 0.06875, "MS": 0.07,
        "MO": 0.04225, "MT": 0.0, "NE": 0.055, "NV": 0.0685,
        "NH": 0.0, "NJ": 0.06625, "NM": 0.05125, "NY": 0.08875,
        "NC": 0.0475, "ND": 0.05, "OH": 0.0575, "OK": 0.045,
        "OR": 0.0, "PA": 0.06, "RI": 0.07, "SC": 0.06,
        "SD": 0.045, "TN": 0.07, "TX": 0.0625, "UT": 0.061,
        "VT": 0.06, "VA": 0.053, "WA": 0.065, "WV": 0.06,
        "WI": 0.05, "WY": 0.04, "DC": 0.06
    ]

    /// Get tax rate for a state code (e.g., "CA", "NY")
    public static func rate(for stateCode: String) -> Double {
        return rates[stateCode.uppercased()] ?? 0.0
    }

    /// Convert full state name to state code
    public static func stateCode(from name: String) -> String {
        let stateNames: [String: String] = [
            "ALABAMA": "AL", "ALASKA": "AK", "ARIZONA": "AZ", "ARKANSAS": "AR",
            "CALIFORNIA": "CA", "COLORADO": "CO", "CONNECTICUT": "CT", "DELAWARE": "DE",
            "FLORIDA": "FL", "GEORGIA": "GA", "HAWAII": "HI", "IDAHO": "ID",
            "ILLINOIS": "IL", "INDIANA": "IN", "IOWA": "IA", "KANSAS": "KS",
            "KENTUCKY": "KY", "LOUISIANA": "LA", "MAINE": "ME", "MARYLAND": "MD",
            "MASSACHUSETTS": "MA", "MICHIGAN": "MI", "MINNESOTA": "MN", "MISSISSIPPI": "MS",
            "MISSOURI": "MO", "MONTANA": "MT", "NEBRASKA": "NE", "NEVADA": "NV",
            "NEW HAMPSHIRE": "NH", "NEW JERSEY": "NJ", "NEW MEXICO": "NM", "NEW YORK": "NY",
            "NORTH CAROLINA": "NC", "NORTH DAKOTA": "ND", "OHIO": "OH", "OKLAHOMA": "OK",
            "OREGON": "OR", "PENNSYLVANIA": "PA", "RHODE ISLAND": "RI", "SOUTH CAROLINA": "SC",
            "SOUTH DAKOTA": "SD", "TENNESSEE": "TN", "TEXAS": "TX", "UTAH": "UT",
            "VERMONT": "VT", "VIRGINIA": "VA", "WASHINGTON": "WA", "WEST VIRGINIA": "WV",
            "WISCONSIN": "WI", "WYOMING": "WY", "DISTRICT OF COLUMBIA": "DC"
        ]
        let upper = name.uppercased()
        // If already a code, return it
        if upper.count == 2 { return upper }
        return stateNames[upper] ?? upper
    }
}
