package com.eatfair.shared.config

/**
 * Dollor.AI App Configuration
 * Matches iOS AppConfig.swift for cross-platform consistency
 *
 * BUSINESS MODEL: MATCHMAKING SERVICE (Not delivery/TNC company)
 *
 * =============================================================================
 * FOOD DELIVERY - FLAT $1 PRICING (No tiered pricing)
 * =============================================================================
 * - Customer: $1 flat per order (regardless of order value)
 * - Restaurant: $1 flat per restaurant in order
 * - Driver: $0 (keeps 100% of delivery fees)
 * - Tips: 100% go to driver
 * - Pickup: $1 per restaurant + $1 per customer
 *
 * =============================================================================
 * RIDESHARE - TIERED PRICING (Based on fare value)
 * =============================================================================
 * - Up to $35 fare:     $1 rider + $1 driver
 * - $35.01 - $70 fare:  $2 rider + $2 driver
 * - Above $70 fare:     $3 rider + $3 driver
 * - Tips: 100% go to driver
 *
 * Total transparency - no hidden fees!
 */
object AppConfig {

    // MARK: - Session Properties (for logged-in user)
    // These are set after successful login and used throughout the app
    var currentVendorId: Int? = null
    var vendorToken: String? = null
    var currentDriverId: Int? = null
    var driverToken: String? = null
    var currentCustomerId: Int? = null
    var customerToken: String? = null

    // MARK: - API Configuration
    // PRODUCTION BUILD - Default to production API
    private const val PRODUCTION_API_URL = "https://api.dollor.ai/api"

    // Runtime API URL - production by default
    private var _apiBaseUrl: String = PRODUCTION_API_URL
    private var _isProduction: Boolean = true

    val apiBaseUrl: String
        get() = _apiBaseUrl

    val isProduction: Boolean
        get() = _isProduction

    // Legacy constant for backward compatibility (prefer apiBaseUrl property)
    @Deprecated("Use apiBaseUrl property instead", ReplaceWith("apiBaseUrl"))
    val API_BASE_URL: String
        get() = _apiBaseUrl

    const val API_TIMEOUT_SECONDS = 30L

    /**
     * Initialize AppConfig with environment-specific settings.
     * PRODUCTION BUILD - Uses production API by default.
     *
     * @param apiBaseUrl The base URL for API calls (from BuildConfig.API_BASE_URL)
     * @param isProduction Whether this is production environment (default: true)
     */
    fun initialize(apiBaseUrl: String = PRODUCTION_API_URL, isProduction: Boolean = true) {
        _apiBaseUrl = apiBaseUrl
        _isProduction = isProduction
    }

    // MARK: - App Bundle IDs (Production)
    const val CUSTOMER_BUNDLE_ID = "ai.dollor.customer"
    const val DRIVER_BUNDLE_ID = "ai.dollor.driver"
    const val RESTAURANT_BUNDLE_ID = "ai.dollor.partner"

    // MARK: - Demo Credentials
    object DemoCredentials {
        const val CUSTOMER_EMAIL_HINT = "demo@dollor.ai"
        const val DRIVER_EMAIL_HINT = "demodriver@dollor.ai"
        const val VENDOR_EMAIL_HINT = "demobusiness@dollor.ai"
        const val DEMO_PASSWORD_PLACEHOLDER = "********"
    }

    // =============================================================================
    // RIDESHARE PRICING - COMPETITIVE MARKET RATES
    // =============================================================================
    // Our advantage: Low platform fee ($1-3) means riders pay LESS and drivers earn MORE
    // Compared to industry-standard 25-30% commission, we only take $1-3 flat!
    // =============================================================================
    object Rideshare {
        // Driver bid presets as a share of the suggested fare (same on iOS AppConfig)
        @Volatile var BID_QUICK_ACCEPT_FACTOR = 0.92
            private set
        @Volatile var BID_FAIR_FACTOR = 1.00
            private set
        @Volatile var BID_PREMIUM_FACTOR = 1.08
            private set

        // Tier thresholds (platform fee tiers)
        @Volatile var TIER_1_MAX_FARE = 35.00       // Fares up to $35
            private set
        @Volatile var TIER_2_MAX_FARE = 70.00       // Fares $35.01 to $70
            private set
        // Tier 3: Fares above $70

        // Platform fees per tier - MUCH LOWER than industry (25-30%)
        @Volatile var TIER_1_FEE = 1.00             // $1 for fares <= $35
            private set
        @Volatile var TIER_2_FEE = 2.00             // $2 for fares $35.01-$70
            private set
        @Volatile var TIER_3_FEE = 3.00             // $3 for fares > $70
            private set

        // =============================================================================
        // COMPETITIVE BASE RATES (Market-aligned pricing)
        // =============================================================================
        @Volatile var BASE_FARE = 2.50              // Competitive base fare
            private set
        @Volatile var PER_MILE_RATE = 1.15          // Market-rate per mile
            private set
        @Volatile var PER_MINUTE_RATE = 0.18        // Market-rate per minute
            private set
        @Volatile var MINIMUM_FARE = 8.00           // Minimum fare for short trips (matches iOS)
            private set

        // Time-of-day multipliers (transparent, not surge pricing)
        const val PEAK_MORNING_MULTIPLIER = 1.15    // 7-9 AM (+15%)
        const val PEAK_EVENING_MULTIPLIER = 1.20    // 5-7 PM (+20%)
        const val LATE_NIGHT_MULTIPLIER = 1.10      // 10 PM-5 AM (+10%)
        const val OFF_PEAK_MULTIPLIER = 0.95        // 10 AM-4 PM (-5% discount)

        // Long-distance discounts (drivers prefer highway miles)
        const val DISTANCE_DISCOUNT_TIER1_MILES = 10.0   // No discount under 10 mi
        const val DISTANCE_DISCOUNT_TIER2_MILES = 25.0   // 5% off miles 11-25
        const val DISTANCE_DISCOUNT_TIER3_MILES = 50.0   // 10% off miles 26-50
        // 15% off miles 50+

        // Demand caps (never exceed 1.5x, unlike competitors)
        const val MAX_DEMAND_MULTIPLIER = 1.50
        const val MIN_DEMAND_MULTIPLIER = 0.90


        // Values below default to the backend's current policy and are replaced by GET /api/config/rideshare
        // (see RideshareConfigLoader). Defaults only matter before the first successful fetch.
        @Volatile var biddingWindowMinutes = 5
            private set
        @Volatile var etaOptionsMinutes: List<Int> = listOf(3, 5, 10, 15)
            private set
        @Volatile var maxCustomerCounters = 3
            private set
        @Volatile var maxRoundsPerBid = 2
            private set
        @Volatile var noShowWaitSeconds = 300
            private set
        @Volatile var noShowFee = 5.00
            private set
        @Volatile var noShowDriverShare = 0.80
            private set
        @Volatile var accessForAllRiderShare = 0.05
            private set
        @Volatile var accessForAllDriverShare = 0.05
            private set

        /** Support details. Hours, response time and the ACH note are null until the backend configures them. */
        data class Support(
            val email: String = "support@dollor.ai",
            val phone: String? = null,
            val url: String? = null,
            val hoursText: String? = null,
            val responseMinutes: Int? = null,
            val achFeeDiscountText: String? = null
        )
        @Volatile var support = Support()
            private set

        /** e.g. "$5 off your first ride"; null until the backend configures a real reward. */
        @Volatile var referralRewardText: String? = null
            private set

        /** Replace the policy values with the backend's. Missing keys keep their current value. */
        fun apply(json: org.json.JSONObject) {
            json.optJSONObject("fees")?.let { f ->
                TIER_1_MAX_FARE = f.optDouble("tier1MaxFare", TIER_1_MAX_FARE)
                TIER_2_MAX_FARE = f.optDouble("tier2MaxFare", TIER_2_MAX_FARE)
                TIER_1_FEE = f.optDouble("tier1Fee", TIER_1_FEE)
                TIER_2_FEE = f.optDouble("tier2Fee", TIER_2_FEE)
                TIER_3_FEE = f.optDouble("tier3Fee", TIER_3_FEE)
                accessForAllRiderShare = f.optDouble("accessForAllRiderShare", accessForAllRiderShare)
                accessForAllDriverShare = f.optDouble("accessForAllDriverShare", accessForAllDriverShare)
            }
            json.optJSONObject("pricing")?.let { p ->
                BASE_FARE = p.optDouble("baseFare", BASE_FARE)
                PER_MILE_RATE = p.optDouble("perMileRate", PER_MILE_RATE)
                PER_MINUTE_RATE = p.optDouble("perMinuteRate", PER_MINUTE_RATE)
                MINIMUM_FARE = p.optDouble("minimumFare", MINIMUM_FARE)
            }
            json.optJSONObject("bidding")?.let { b ->
                BID_QUICK_ACCEPT_FACTOR = b.optDouble("quickAcceptFactor", BID_QUICK_ACCEPT_FACTOR)
                BID_FAIR_FACTOR = b.optDouble("fairFactor", BID_FAIR_FACTOR)
                BID_PREMIUM_FACTOR = b.optDouble("premiumFactor", BID_PREMIUM_FACTOR)
                biddingWindowMinutes = b.optInt("windowMinutes", biddingWindowMinutes)
                maxCustomerCounters = b.optInt("maxCustomerCounters", maxCustomerCounters)
                maxRoundsPerBid = b.optInt("maxRoundsPerBid", maxRoundsPerBid)
                b.optJSONArray("etaOptionsMinutes")?.let { arr ->
                    val options = (0 until arr.length()).map { arr.getInt(it) }
                    if (options.isNotEmpty()) etaOptionsMinutes = options
                }
            }
            json.optJSONObject("noShow")?.let { n ->
                noShowWaitSeconds = n.optInt("waitSeconds", noShowWaitSeconds)
                noShowFee = n.optDouble("fee", noShowFee)
                noShowDriverShare = n.optDouble("driverShare", noShowDriverShare)
            }
            json.optJSONObject("referral")?.let { r ->
                referralRewardText = if (r.isNull("rewardText")) null else r.optString("rewardText").ifBlank { null }
            }
            json.optJSONObject("support")?.let { s ->
                fun text(key: String): String? = if (s.isNull(key)) null else s.optString(key).ifBlank { null }
                support = Support(
                    email = text("email") ?: support.email,
                    phone = text("phone"),
                    url = text("url"),
                    hoursText = text("hoursText"),
                    responseMinutes = if (s.isNull("responseMinutes")) null else s.optInt("responseMinutes"),
                    achFeeDiscountText = text("achFeeDiscountText")
                )
            }
        }

        // Tips
        const val TIP_PLATFORM_FEE = 0.00       // 100% of tips go to driver

        /**
         * Calculate tiered platform fee for rideshare based on fare value.
         * Returns the fee amount for BOTH rider AND driver (same amount each).
         */
        fun calculatePlatformFee(fareAmount: Double): Double {
            return when {
                fareAmount <= TIER_1_MAX_FARE -> TIER_1_FEE
                fareAmount <= TIER_2_MAX_FARE -> TIER_2_FEE
                else -> TIER_3_FEE
            }
        }

        /**
         * Get rider platform fee based on fare amount.
         */
        fun getRiderFee(fareAmount: Double): Double = calculatePlatformFee(fareAmount)

        /**
         * Get driver platform access fee based on fare amount.
         */
        fun getDriverFee(fareAmount: Double): Double = calculatePlatformFee(fareAmount)

        /**
         * Get tier number for display (1, 2, or 3).
         */
        fun getTier(fareAmount: Double): Int {
            return when {
                fareAmount <= TIER_1_MAX_FARE -> 1
                fareAmount <= TIER_2_MAX_FARE -> 2
                else -> 3
            }
        }

        /**
         * Get tier name for display.
         */
        fun getTierName(fareAmount: Double): String {
            return when {
                fareAmount <= TIER_1_MAX_FARE -> "Tier 1 (up to ${money(TIER_1_MAX_FARE)})"
                fareAmount <= TIER_2_MAX_FARE -> "Tier 2 (${money(TIER_1_MAX_FARE)}-${money(TIER_2_MAX_FARE)})"
                else -> "Tier 3 (above ${money(TIER_2_MAX_FARE)})"
            }
        }

        private fun money(amount: Double): String =
            if (amount == Math.rint(amount)) "$" + amount.toInt() else "$" + String.format(java.util.Locale.US, "%.2f", amount)

        /** Lowest-to-highest platform fee, e.g. "$1-$3". Always in sync with the tier config. */
        val feeRangeText: String
            get() = "${money(TIER_1_FEE)}-${money(TIER_3_FEE)}"

        /** One line per tier for legal/help copy, e.g. "$1 platform fee for rides up to $35". */
        val tierLines: List<String>
            get() = listOf(
                "${money(TIER_1_FEE)} platform fee for rides up to ${money(TIER_1_MAX_FARE)}",
                "${money(TIER_2_FEE)} platform fee for rides over ${money(TIER_1_MAX_FARE)} up to ${money(TIER_2_MAX_FARE)}",
                "${money(TIER_3_FEE)} platform fee for rides over ${money(TIER_2_MAX_FARE)}"
            )

        /**
         * Get fee description for UI display.
         */
        fun getFeeDescription(fareAmount: Double): String {
            val fee = calculatePlatformFee(fareAmount).toInt()
            return "$$fee Platform Fee"
        }

        /**
         * Calculate rideshare fare (before platform fees).
         * Uses competitive market-rate pricing.
         */
        fun calculateFare(distanceMiles: Double, durationMinutes: Double = 0.0): Double {
            val distanceFare = distanceMiles * PER_MILE_RATE
            val timeFare = durationMinutes * PER_MINUTE_RATE
            val baseFare = BASE_FARE + distanceFare + timeFare

            // Apply long-distance discount
            val discount = calculateDistanceDiscount(distanceMiles)

            return maxOf(MINIMUM_FARE, baseFare - discount)
        }

        /**
         * Calculate fare with time-of-day adjustment.
         * @param hour Hour of day (0-23)
         */
        fun calculateFareWithTimeAdjustment(
            distanceMiles: Double,
            durationMinutes: Double,
            hour: Int
        ): Pair<Double, String> {
            val baseFare = calculateFare(distanceMiles, durationMinutes)
            val (multiplier, label) = getTimeMultiplier(hour)
            return Pair(baseFare * multiplier, label)
        }

        /**
         * Get time-of-day multiplier and label.
         */
        fun getTimeMultiplier(hour: Int): Pair<Double, String> {
            return when {
                hour in 7..8 -> Pair(PEAK_MORNING_MULTIPLIER, "Morning peak (+15%)")
                hour in 17..18 -> Pair(PEAK_EVENING_MULTIPLIER, "Evening peak (+20%)")
                hour >= 22 || hour < 5 -> Pair(LATE_NIGHT_MULTIPLIER, "Late night (+10%)")
                hour in 10..15 -> Pair(OFF_PEAK_MULTIPLIER, "Off-peak (-5%)")
                else -> Pair(1.0, "Standard")
            }
        }

        /**
         * Calculate long-distance discount.
         * Drivers prefer highway miles - reward longer trips with discounts.
         */
        fun calculateDistanceDiscount(distanceMiles: Double): Double {
            if (distanceMiles <= DISTANCE_DISCOUNT_TIER1_MILES) return 0.0

            var discount = 0.0

            // 5% discount on miles 11-25
            if (distanceMiles > DISTANCE_DISCOUNT_TIER1_MILES) {
                val tier1Miles = minOf(distanceMiles - DISTANCE_DISCOUNT_TIER1_MILES, 15.0)
                discount += tier1Miles * PER_MILE_RATE * 0.05
            }

            // 10% discount on miles 26-50
            if (distanceMiles > DISTANCE_DISCOUNT_TIER2_MILES) {
                val tier2Miles = minOf(distanceMiles - DISTANCE_DISCOUNT_TIER2_MILES, 25.0)
                discount += tier2Miles * PER_MILE_RATE * 0.10
            }

            // 15% discount on miles 50+
            if (distanceMiles > DISTANCE_DISCOUNT_TIER3_MILES) {
                val tier3Miles = distanceMiles - DISTANCE_DISCOUNT_TIER3_MILES
                discount += tier3Miles * PER_MILE_RATE * 0.15
            }

            return discount
        }

        /**
         * Generate suggested bid prices for drivers.
         * Returns three options: Quick Accept (92%), Fair Price (100%), Premium (108%)
         *
         * New competitive pricing with transparent platform fees ($1-3 flat).
         * Drivers keep the fare minus the flat platform fee.
         */
        fun generateSuggestedBids(fareEstimate: Double, distanceMiles: Double, durationMinutes: Double = 0.0): List<SuggestedBid> {
            val quickAcceptPrice = fareEstimate * 0.92  // 92% of estimate for fast pickup
            val fairPrice = fareEstimate                // 100% of estimate (recommended)
            val premiumPrice = fareEstimate * 1.08      // 108% of estimate for premium

            return listOf(
                SuggestedBid(
                    label = "Quick Accept",
                    price = quickAcceptPrice,
                    driverEarnings = quickAcceptPrice - calculatePlatformFee(quickAcceptPrice),
                    acceptanceHint = "Higher acceptance",
                    perMile = if (distanceMiles > 0) (quickAcceptPrice - calculatePlatformFee(quickAcceptPrice)) / distanceMiles else 0.0,
                    isRecommended = false
                ),
                SuggestedBid(
                    label = "Fair Price",
                    price = fairPrice,
                    driverEarnings = fairPrice - calculatePlatformFee(fairPrice),
                    acceptanceHint = "Recommended",
                    perMile = if (distanceMiles > 0) (fairPrice - calculatePlatformFee(fairPrice)) / distanceMiles else 0.0,
                    isRecommended = true
                ),
                SuggestedBid(
                    label = "Premium",
                    price = premiumPrice,
                    driverEarnings = premiumPrice - calculatePlatformFee(premiumPrice),
                    acceptanceHint = "Maximum earnings",
                    perMile = if (distanceMiles > 0) (premiumPrice - calculatePlatformFee(premiumPrice)) / distanceMiles else 0.0,
                    isRecommended = false
                )
            )
        }

        /**
         * Calculate earnings per hour for a ride.
         * Helps drivers understand hourly earnings potential.
         */
        fun calculateEarningsPerHour(fareAmount: Double, durationMinutes: Double): Double {
            if (durationMinutes <= 0) return 0.0
            val earnings = fareAmount - calculatePlatformFee(fareAmount)
            return (earnings / durationMinutes) * 60.0  // Convert to per hour
        }

        /**
         * Get platform fee percentage for display.
         * Shows how much of the fare the platform takes (typically 3-4% vs industry 25-30%).
         */
        fun getPlatformFeePercentage(fareAmount: Double): Double {
            val fee = calculatePlatformFee(fareAmount)
            return if (fareAmount > 0) (fee / fareAmount) * 100.0 else 0.0
        }

        /**
         * Get driver earnings percentage for display.
         * Drivers keep 96%+ of every fare with our low flat fees.
         */
        fun getDriverEarningsPercentage(fareAmount: Double): Double {
            return 100.0 - getPlatformFeePercentage(fareAmount)
        }

        /**
         * Get bid comparison label for customers.
         * Helps customers understand if a bid is good value.
         */
        fun getBidComparisonLabel(bidPrice: Double, fareEstimate: Double): Triple<String, String, String> {
            val differencePercent = ((bidPrice - fareEstimate) / fareEstimate) * 100

            return when {
                differencePercent <= -10 -> Triple("Great Deal", "10%+ below market rate", "green")
                differencePercent <= -5 -> Triple("Good Value", "Below market rate", "green")
                differencePercent <= 5 -> Triple("Fair Price", "At market rate", "blue")
                differencePercent <= 15 -> Triple("Above Average", "Slightly above market", "orange")
                else -> Triple("Premium", "Above market rate", "gray")
            }
        }

        /**
         * Calculate driver earnings after platform fee.
         */
        fun calculateDriverEarnings(fare: Double, tip: Double = 0.0): Double {
            val platformFee = calculatePlatformFee(fare)
            return fare - platformFee + tip
        }

        /**
         * Calculate total rider payment.
         */
        fun calculateRiderTotal(fare: Double, tip: Double = 0.0): Double {
            val platformFee = calculatePlatformFee(fare)
            return fare + platformFee + tip
        }

        /**
         * Calculate all ride fees.
         */
        fun calculateRideFees(fareAmount: Double): RideFees {
            val platformFee = calculatePlatformFee(fareAmount)
            return RideFees(
                riderFee = platformFee,
                driverFee = platformFee,
                totalPlatformRevenue = platformFee * 2
            )
        }
    }

    data class RideFees(
        val riderFee: Double,
        val driverFee: Double,
        val totalPlatformRevenue: Double
    )

    /**
     * Suggested bid option for drivers.
     */
    data class SuggestedBid(
        val label: String,
        val price: Double,
        val driverEarnings: Double,
        val acceptanceHint: String,
        val perMile: Double,
        val isRecommended: Boolean
    )

    // MARK: - Location Configuration
    object Location {
        /** Map centre shown only until the first GPS fix arrives. */
        const val FALLBACK_LATITUDE = 37.7879
        const val FALLBACK_LONGITUDE = -122.4075
        const val DRIVER_LOCATION_UPDATE_INTERVAL_MS = 10_000L  // 10 seconds
        const val MAX_DELIVERY_RADIUS_MILES = 10.0
        const val MAX_RIDESHARE_RADIUS_MILES = 5.0
    }

    // MARK: - Legal URLs
    // Production URLs for Dollor.ai by Vibing World Inc
    object Legal {
        // Production legal pages
        const val TERMS_OF_SERVICE_URL = "https://www.dollor.ai/terms"
        const val PRIVACY_POLICY_URL = "https://www.dollor.ai/privacy"
        const val SUPPORT_URL = "https://www.dollor.ai/support"
        const val CONTACT_EMAIL = "support@dollor.ai"
        const val COMPANY_NAME = "Vibing World Inc"
    }

    // MARK: - Stripe Configuration
    object Stripe {
        const val PUBLISHABLE_KEY_PLACEHOLDER = "LOADED_FROM_BUILD_CONFIG"

        fun getPublishableKey(buildConfigKey: String): String {
            require(buildConfigKey.isNotBlank()) {
                "Stripe publishable key not configured. Add STRIPE_PUBLISHABLE_KEY to local.properties"
            }
            return buildConfigKey
        }
    }
}
