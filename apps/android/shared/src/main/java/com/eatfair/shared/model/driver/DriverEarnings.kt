package com.eatfair.shared.model.driver

import com.google.gson.annotations.SerializedName

/**
 * Driver Dashboard Response from V5 API
 * Matches iOS DriverDashboardResponse
 */
data class DriverDashboardResponse(
    @SerializedName("driver_id")
    val driverId: String = "",

    @SerializedName("snapshot_time")
    val snapshotTime: String = "",

    val today: DriverEarningsPeriod = DriverEarningsPeriod(),

    @SerializedName("this_week")
    val thisWeek: DriverEarningsPeriod = DriverEarningsPeriod(),

    @SerializedName("this_month")
    val thisMonth: DriverEarningsPeriod = DriverEarningsPeriod(),

    @SerializedName("tax_info")
    val taxInfo: DriverTaxInfo? = null,

    @SerializedName("platform_fees_paid")
    val platformFeesPaid: DriverPlatformFees? = null,

    @SerializedName("payment_methods")
    val paymentMethods: DriverPaymentMethods? = null,

    val ratings: DriverRatings? = null,

    // Payout info
    @SerializedName("available_balance")
    val availableBalance: Double = 0.0,

    @SerializedName("pending_balance")
    val pendingBalance: Double = 0.0,

    @SerializedName("last_payout")
    val lastPayout: PayoutInfo? = null
)

/**
 * Earnings for a specific time period (today, this week, this month)
 * Unified structure across iOS, Android, and Web
 */
data class DriverEarningsPeriod(
    val deliveries: Int = 0,

    @SerializedName("gross_earnings")
    val grossEarnings: Double = 0.0,

    @SerializedName("base_pay")
    val basePay: Double = 0.0,

    val tips: Double = 0.0,

    val bonuses: Double = 0.0,

    @SerializedName("total_miles")
    val totalMiles: Double? = null,

    @SerializedName("active_hours")
    val activeHours: Double? = null,

    @SerializedName("effective_hourly_rate")
    val effectiveHourlyRate: Double? = null,

    @SerializedName("per_delivery_average")
    val perDeliveryAverage: Double? = null
)

/**
 * Tax information for driver
 */
data class DriverTaxInfo(
    @SerializedName("total_miles_ytd")
    val totalMilesYtd: Double? = null,

    @SerializedName("mileage_deduction_ytd")
    val mileageDeductionYtd: Double? = null,

    @SerializedName("gross_earnings_ytd")
    val grossEarningsYtd: Double? = null,

    @SerializedName("estimated_taxable_after_mileage")
    val estimatedTaxableAfterMileage: Double? = null,

    val note: String? = null,

    @SerializedName("other_deductions")
    val otherDeductions: List<String>? = null
)

/**
 * Platform fees paid by driver
 */
data class DriverPlatformFees(
    @SerializedName("to_dollor")
    val toDollor: Double? = null,

    val note: String? = null
)

/**
 * Driver payment methods configuration
 */
data class DriverPaymentMethods(
    @SerializedName("has_bank_account")
    val hasBankAccount: Boolean = false,

    @SerializedName("has_instant_payout")
    val hasInstantPayout: Boolean = false,

    @SerializedName("default_method")
    val defaultMethod: String = "standard", // "standard", "instant"

    @SerializedName("bank_account_last4")
    val bankAccountLast4: String? = null,

    @SerializedName("bank_name")
    val bankName: String? = null,

    @SerializedName("stripe_connect_id")
    val stripeConnectId: String? = null
)

/**
 * Driver ratings summary - Unified across iOS, Android, and Web
 */
data class DriverRatings(
    val average: Double = 5.0,

    @SerializedName("total_ratings")
    val totalRatings: Int = 0,

    @SerializedName("five_star")
    val fiveStar: Int = 0,

    @SerializedName("four_star")
    val fourStar: Int = 0,

    @SerializedName("three_star")
    val threeStar: Int = 0,

    @SerializedName("two_star")
    val twoStar: Int = 0,

    @SerializedName("one_star")
    val oneStar: Int = 0,

    @SerializedName("on_time_percentage")
    val onTimePercentage: Int = 95
)

/**
 * Payout information
 */
data class PayoutInfo(
    val id: String = "",
    val amount: Double = 0.0,
    val currency: String = "usd",
    val status: String = "pending", // "pending", "processing", "completed", "failed"
    val method: String = "standard", // "standard", "instant"

    @SerializedName("created_at")
    val createdAt: Long = 0,

    @SerializedName("arrival_date")
    val arrivalDate: Long? = null,

    @SerializedName("bank_last4")
    val bankLast4: String? = null,

    val fee: Double = 0.0 // Instant payout fee if applicable
)

/**
 * Request to create a payout
 */
data class CreatePayoutRequest(
    val amount: Double,
    val method: String = "standard", // "standard" (free, 2-3 days) or "instant" ($1.50 fee)
    val currency: String = "usd"
)

/**
 * Response from payout creation
 */
data class CreatePayoutResponse(
    val success: Boolean = false,
    val payout: PayoutInfo? = null,
    val message: String? = null,
    val error: String? = null
)

/**
 * Request to link bank account for payouts
 */
data class LinkBankAccountRequest(
    @SerializedName("account_holder_name")
    val accountHolderName: String,

    @SerializedName("routing_number")
    val routingNumber: String,

    @SerializedName("account_number")
    val accountNumber: String,

    @SerializedName("account_type")
    val accountType: String = "checking" // "checking" or "savings"
)

/**
 * Response from bank account linking
 */
data class LinkBankAccountResponse(
    val success: Boolean = false,

    @SerializedName("bank_account_id")
    val bankAccountId: String? = null,

    @SerializedName("bank_name")
    val bankName: String? = null,

    @SerializedName("last4")
    val last4: String? = null,

    val message: String? = null,
    val error: String? = null
)

/**
 * List of driver's payouts
 */
data class PayoutHistoryResponse(
    val payouts: List<PayoutInfo> = emptyList(),

    @SerializedName("total_paid_out")
    val totalPaidOut: Double = 0.0,

    @SerializedName("has_more")
    val hasMore: Boolean = false
)

/**
 * Daily earnings breakdown for charts - Unified across iOS, Android, and Web
 */
data class DailyEarning(
    val day: String = "",
    val date: String = "",
    val deliveries: Int = 0,
    val earnings: Double = 0.0,
    val hours: Double = 0.0
)

data class DriverEarningsSummaryDto(
    @SerializedName("total_earnings") val totalEarnings: Double = 0.0,
    @SerializedName("base_earnings") val baseEarnings: Double = 0.0,
    @SerializedName("rideshare_earnings") val rideshareEarnings: Double = 0.0,
    val tips: Double = 0.0,
    val bonuses: Double = 0.0,
    @SerializedName("rideshare_rides") val rideshareRides: Int = 0,
    val today: Double = 0.0,
    val week: Double = 0.0,
    val month: Double = 0.0,
    val pending: Double = 0.0
) {
    fun toResponse(): DriverEarningsResponse = DriverEarningsResponse(
        total = totalEarnings,
        basePay = baseEarnings + rideshareEarnings,
        tips = tips,
        bonuses = bonuses,
        deliveries = rideshareRides,
        today = DriverEarningsPeriod(grossEarnings = today),
        thisWeek = DriverEarningsPeriod(grossEarnings = week),
        thisMonth = DriverEarningsPeriod(grossEarnings = month),
        pendingBalance = pending
    )
}

/**
 * Unified Driver Earnings Response - Aligned across iOS, Android, and Web
 * Matches backend /api/drivers/{driver_id}/earnings response
 */
data class DriverEarningsResponse(
    // === Primary earnings data (for selected period) ===
    val total: Double = 0.0,

    @SerializedName("base_pay")
    val basePay: Double = 0.0,

    val tips: Double = 0.0,

    val bonuses: Double = 0.0,

    @SerializedName("previous_period")
    val previousPeriod: Double = 0.0,

    val deliveries: Int = 0,

    @SerializedName("hours_online")
    val hoursOnline: Double = 0.0,

    @SerializedName("avg_per_delivery")
    val avgPerDelivery: Double = 0.0,

    @SerializedName("hourly_rate")
    val hourlyRate: Double = 0.0,

    // === Multi-period data (for dashboard) ===
    val today: DriverEarningsPeriod = DriverEarningsPeriod(),

    @SerializedName("this_week")
    val thisWeek: DriverEarningsPeriod = DriverEarningsPeriod(),

    @SerializedName("this_month")
    val thisMonth: DriverEarningsPeriod = DriverEarningsPeriod(),

    // === Daily breakdown (for charts) ===
    @SerializedName("daily_breakdown")
    val dailyBreakdown: List<DailyEarning> = emptyList(),

    // === Ratings ===
    val ratings: DriverRatings = DriverRatings(),

    // === Payout info ===
    @SerializedName("available_balance")
    val availableBalance: Double = 0.0,

    @SerializedName("pending_balance")
    val pendingBalance: Double = 0.0,

    @SerializedName("last_payout")
    val lastPayout: PayoutInfo? = null,

    // === Payment history ===
    @SerializedName("payment_history")
    val paymentHistory: List<PayoutInfo> = emptyList(),

    // === Metadata ===
    @SerializedName("driver_id")
    val driverId: Int = 0,

    val period: String = "week",

    @SerializedName("snapshot_time")
    val snapshotTime: String = ""
)
