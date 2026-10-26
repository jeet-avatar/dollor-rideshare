"""
Dollor.ai Competitive Pricing Configuration
==========================================
Market-competitive pricing with transparent fees.
Our advantage: Low platform fee ($1-3) vs industry-standard 25-30% commission.
"""

from dataclasses import dataclass
from datetime import datetime
from typing import Tuple, List, Optional
import math


@dataclass
class PricingConfig:
    """Configurable pricing parameters - market competitive rates"""
    # Base rates (competitive with market)
    BASE_FARE: float = 2.50
    PER_MILE_RATE: float = 1.15
    PER_MINUTE_RATE: float = 0.18
    MINIMUM_FARE: float = 8.00

    # Platform fee tiers (MUCH lower than industry 25-30%)
    TIER_1_MAX: float = 35.00
    TIER_2_MAX: float = 70.00
    TIER_1_FEE: float = 1.00
    TIER_2_FEE: float = 2.00
    TIER_3_FEE: float = 3.00

    # Time-of-day multipliers (transparent, not "surge")
    PEAK_MORNING_MULTIPLIER: float = 1.15  # 7-9 AM
    PEAK_EVENING_MULTIPLIER: float = 1.20  # 5-7 PM
    LATE_NIGHT_MULTIPLIER: float = 1.10    # 10 PM - 5 AM
    OFF_PEAK_MULTIPLIER: float = 0.95      # 10 AM - 4 PM

    # Long-distance discount thresholds
    DISTANCE_DISCOUNT_TIER1: float = 10.0  # No discount under 10 mi
    DISTANCE_DISCOUNT_TIER2: float = 25.0  # 5% off miles 11-25
    DISTANCE_DISCOUNT_TIER3: float = 50.0  # 10% off miles 26-50
    # 15% off miles 50+

    # Demand caps (never exceed 1.5x unlike competitors)
    MAX_DEMAND_MULTIPLIER: float = 1.50
    MIN_DEMAND_MULTIPLIER: float = 0.90

    # CPUC Access-for-All charge per trip (Decision 19-06-033), split between rider and driver
    ACCESS_FOR_ALL_FEE: float = 0.10
    ACCESS_FOR_ALL_RIDER_SHARE: float = 0.05
    ACCESS_FOR_ALL_DRIVER_SHARE: float = 0.05

    # Riders are not charged to cancel a ride
    RIDER_CANCELLATION_FEE: float = 0.00

    # Bidding
    BIDDING_WINDOW_MINUTES: int = 5
    BID_QUICK_ACCEPT_FACTOR: float = 0.92   # 8% below the suggested fare for a fast pickup
    BID_FAIR_FACTOR: float = 1.00
    BID_PREMIUM_FACTOR: float = 1.08        # 8% above for premium service
    BID_ETA_OPTIONS_MINUTES: tuple = (3, 5, 10, 15)
    MAX_CUSTOMER_COUNTERS: int = 3          # counter-offers a rider may make on one request
    MAX_ROUNDS_PER_BID: int = 2             # negotiation rounds on a single bid

    # Passenger no-show: the driver may mark a no-show after waiting, and the rider is charged the fee
    NOSHOW_WAIT_SECONDS: int = 300
    NOSHOW_FEE: float = 5.00
    NOSHOW_DRIVER_SHARE: float = 0.80


@dataclass
class SuggestedBid:
    """Suggested bid option for drivers"""
    label: str
    emoji: str
    price: float
    driver_earnings: float
    acceptance_hint: str
    per_mile: float
    is_recommended: bool


@dataclass
class FareEstimate:
    """Complete fare estimate with breakdown"""
    distance_miles: float
    duration_minutes: int

    base_fare: float
    distance_cost: float
    time_cost: float

    time_adjustment: float
    time_adjustment_label: str

    long_distance_discount: float

    subtotal: float
    platform_fee: float
    total: float

    driver_earnings: float
    driver_earnings_per_mile: float
    driver_earnings_per_hour: float
    driver_percentage: float

    suggested_bids: List[SuggestedBid]
    tier: int
    tier_label: str


class DollorPricingEngine:
    """
    Fair Market Pricing Engine for Dollor.ai

    Calculates competitive prices that:
    - Are comparable to market rates
    - Give drivers 96%+ of the fare
    - Provide transparent breakdowns
    """

    def __init__(self, config: PricingConfig = None):
        self.config = config or PricingConfig()

    def km_to_miles(self, km: float) -> float:
        """Convert kilometers to miles"""
        return km * 0.621371

    def miles_to_km(self, miles: float) -> float:
        """Convert miles to kilometers"""
        return miles / 0.621371

    def calculate_estimate(
        self,
        distance_km: float,
        duration_minutes: int,
        pickup_time: datetime = None,
        demand_level: float = 0.5
    ) -> FareEstimate:
        """
        Calculate complete fare estimate with all adjustments
        """
        pickup_time = pickup_time or datetime.now()
        distance_miles = self.km_to_miles(distance_km)

        # Base calculations
        base_fare = self.config.BASE_FARE
        distance_cost = distance_miles * self.config.PER_MILE_RATE
        time_cost = duration_minutes * self.config.PER_MINUTE_RATE

        raw_subtotal = base_fare + distance_cost + time_cost

        # Time-of-day adjustment
        time_mult, time_label = self._get_time_adjustment(pickup_time)
        time_adjustment = raw_subtotal * (time_mult - 1)

        # Long-distance discount
        long_distance_discount = self._get_distance_discount(distance_miles)

        # Calculate subtotal
        subtotal = raw_subtotal + time_adjustment - long_distance_discount
        subtotal = max(subtotal, self.config.MINIMUM_FARE)

        # Platform fee
        platform_fee = self._get_platform_fee(subtotal)
        tier = self._get_tier(subtotal)
        tier_label = self._get_tier_label(subtotal)

        # Total and driver earnings (iOS model: both customer AND driver pay tier fee)
        total = subtotal + platform_fee  # Customer pays fare + platform_fee
        driver_earnings = subtotal - platform_fee  # Driver pays platform_fee too
        driver_per_mile = driver_earnings / distance_miles if distance_miles > 0 else 0
        driver_per_hour = (driver_earnings / duration_minutes) * 60 if duration_minutes > 0 else 0
        driver_percentage = (driver_earnings / total) * 100 if total > 0 else 0

        # Generate suggested bids
        suggested_bids = self._generate_bid_suggestions(subtotal, distance_miles)

        return FareEstimate(
            distance_miles=round(distance_miles, 2),
            duration_minutes=duration_minutes,
            base_fare=round(base_fare, 2),
            distance_cost=round(distance_cost, 2),
            time_cost=round(time_cost, 2),
            time_adjustment=round(time_adjustment, 2),
            time_adjustment_label=time_label,
            long_distance_discount=round(long_distance_discount, 2),
            subtotal=round(subtotal, 2),
            platform_fee=round(platform_fee, 2),
            total=round(total, 2),
            driver_earnings=round(driver_earnings, 2),
            driver_earnings_per_mile=round(driver_per_mile, 2),
            driver_earnings_per_hour=round(driver_per_hour, 2),
            driver_percentage=round(driver_percentage, 1),
            suggested_bids=suggested_bids,
            tier=tier,
            tier_label=tier_label
        )

    def _get_time_adjustment(self, pickup_time: datetime) -> Tuple[float, str]:
        """Get time-of-day multiplier and label"""
        hour = pickup_time.hour

        if 7 <= hour < 9:
            return self.config.PEAK_MORNING_MULTIPLIER, "Morning peak (+15%)"
        elif 17 <= hour < 19:
            return self.config.PEAK_EVENING_MULTIPLIER, "Evening peak (+20%)"
        elif hour >= 22 or hour < 5:
            return self.config.LATE_NIGHT_MULTIPLIER, "Late night (+10%)"
        elif 10 <= hour < 16:
            return self.config.OFF_PEAK_MULTIPLIER, "Off-peak (-5%)"
        else:
            return 1.0, "Standard"

    def _get_distance_discount(self, distance_miles: float) -> float:
        """
        Long-distance discount (drivers prefer highway miles)
        """
        if distance_miles <= self.config.DISTANCE_DISCOUNT_TIER1:
            return 0.0

        discount = 0.0

        # 5% discount on miles 11-25
        if distance_miles > self.config.DISTANCE_DISCOUNT_TIER1:
            tier1_miles = min(distance_miles - self.config.DISTANCE_DISCOUNT_TIER1, 15.0)
            discount += tier1_miles * self.config.PER_MILE_RATE * 0.05

        # 10% discount on miles 26-50
        if distance_miles > self.config.DISTANCE_DISCOUNT_TIER2:
            tier2_miles = min(distance_miles - self.config.DISTANCE_DISCOUNT_TIER2, 25.0)
            discount += tier2_miles * self.config.PER_MILE_RATE * 0.10

        # 15% discount on miles 50+
        if distance_miles > self.config.DISTANCE_DISCOUNT_TIER3:
            tier3_miles = distance_miles - self.config.DISTANCE_DISCOUNT_TIER3
            discount += tier3_miles * self.config.PER_MILE_RATE * 0.15

        return discount

    def _get_platform_fee(self, subtotal: float) -> float:
        """Get tiered platform fee"""
        if subtotal <= self.config.TIER_1_MAX:
            return self.config.TIER_1_FEE
        elif subtotal <= self.config.TIER_2_MAX:
            return self.config.TIER_2_FEE
        else:
            return self.config.TIER_3_FEE

    def _get_tier(self, subtotal: float) -> int:
        """Get pricing tier number"""
        if subtotal <= self.config.TIER_1_MAX:
            return 1
        elif subtotal <= self.config.TIER_2_MAX:
            return 2
        else:
            return 3

    def _get_tier_label(self, subtotal: float) -> str:
        """Get tier label for display"""
        if subtotal <= self.config.TIER_1_MAX:
            return "Tier 1 (up to $35)"
        elif subtotal <= self.config.TIER_2_MAX:
            return "Tier 2 ($35-$70)"
        else:
            return "Tier 3 (above $70)"

    def _generate_bid_suggestions(
        self,
        subtotal: float,
        distance_miles: float
    ) -> List[SuggestedBid]:
        """Generate three suggested bid levels for drivers"""

        quick_accept_price = subtotal * self.config.BID_QUICK_ACCEPT_FACTOR
        fair_price = subtotal
        premium_price = subtotal * self.config.BID_PREMIUM_FACTOR

        return [
            SuggestedBid(
                label="Quick Accept",
                emoji="⚡",
                price=round(quick_accept_price, 2),
                driver_earnings=round(quick_accept_price - self._get_platform_fee(quick_accept_price), 2),
                acceptance_hint="90% acceptance rate",
                per_mile=round((quick_accept_price - self._get_platform_fee(quick_accept_price)) / distance_miles, 2) if distance_miles > 0 else 0,
                is_recommended=False
            ),
            SuggestedBid(
                label="Fair Price",
                emoji="✓",
                price=round(fair_price, 2),
                driver_earnings=round(fair_price - self._get_platform_fee(fair_price), 2),
                acceptance_hint="75% acceptance rate",
                per_mile=round((fair_price - self._get_platform_fee(fair_price)) / distance_miles, 2) if distance_miles > 0 else 0,
                is_recommended=True
            ),
            SuggestedBid(
                label="Premium",
                emoji="💎",
                price=round(premium_price, 2),
                driver_earnings=round(premium_price - self._get_platform_fee(premium_price), 2),
                acceptance_hint="50% acceptance rate",
                per_mile=round((premium_price - self._get_platform_fee(premium_price)) / distance_miles, 2) if distance_miles > 0 else 0,
                is_recommended=False
            )
        ]

    def get_bid_comparison_label(self, bid_price: float, fare_estimate: float) -> Tuple[str, str, str]:
        """
        Get bid comparison label for customers.
        Returns (label, description, color)
        """
        if fare_estimate == 0:
            return ("Unknown", "Cannot compare", "gray")

        difference_percent = ((bid_price - fare_estimate) / fare_estimate) * 100

        if difference_percent <= -10:
            return ("Great Deal", "10%+ below market rate", "green")
        elif difference_percent <= -5:
            return ("Good Value", "Below market rate", "green")
        elif difference_percent <= 5:
            return ("Fair Price", "At market rate", "blue")
        elif difference_percent <= 15:
            return ("Above Average", "Slightly above market", "orange")
        else:
            return ("Premium", "Above market rate", "gray")

    def get_driver_earnings_context(
        self,
        earnings: float,
        distance_miles: float,
        duration_minutes: int
    ) -> List[str]:
        """Generate helpful earnings context for drivers"""
        messages = []

        if distance_miles > 0:
            per_mile = earnings / distance_miles
            if per_mile >= 1.50:
                messages.append(f"🔥 Excellent rate: ${per_mile:.2f}/mile")
            elif per_mile >= 1.20:
                messages.append(f"✓ Good rate: ${per_mile:.2f}/mile")
            else:
                messages.append(f"📊 Rate: ${per_mile:.2f}/mile")

        if duration_minutes > 0:
            per_hour = (earnings / duration_minutes) * 60
            if per_hour >= 35:
                messages.append(f"💰 This trip pays ${per_hour:.0f}/hour equivalent")
            elif per_hour >= 25:
                messages.append(f"📈 ${per_hour:.0f}/hour equivalent")

        # Platform fee transparency (driver pays tier fee from fare)
        fare_estimate = earnings + self._get_platform_fee(earnings)  # Estimate original fare
        fee = self._get_platform_fee(fare_estimate)
        messages.append(f"💎 Platform fee: ${fee:.2f} from fare")

        # Long trip bonus messaging
        if distance_miles > 20:
            messages.append("🛣️ Long trip = more highway miles, less city traffic")

        return messages


# Singleton instance
pricing_engine = DollorPricingEngine()


def platform_fee_for(fare: float) -> float:
    """Flat platform fee for a fare. The only place the fee tiers are applied."""
    return pricing_engine._get_platform_fee(fare)


def fare_tier_description(fare: float) -> str:
    """Human-readable tier for a fare, built from the configured thresholds."""
    cfg = pricing_engine.config
    if fare <= cfg.TIER_1_MAX:
        return f"fare <= ${cfg.TIER_1_MAX:.0f}"
    if fare <= cfg.TIER_2_MAX:
        return f"fare ${cfg.TIER_1_MAX:.0f}-${cfg.TIER_2_MAX:.0f}"
    return f"fare > ${cfg.TIER_2_MAX:.0f}"


def get_fare_estimate(
    distance_km: float,
    duration_minutes: int,
    pickup_time: datetime = None
) -> dict:
    """
    Get fare estimate as dictionary for API response
    """
    estimate = pricing_engine.calculate_estimate(
        distance_km=distance_km,
        duration_minutes=duration_minutes,
        pickup_time=pickup_time
    )

    return {
        "distance_miles": estimate.distance_miles,
        "duration_minutes": estimate.duration_minutes,
        "breakdown": {
            "base_fare": estimate.base_fare,
            "distance_cost": estimate.distance_cost,
            "time_cost": estimate.time_cost,
            "time_adjustment": estimate.time_adjustment,
            "time_adjustment_label": estimate.time_adjustment_label,
            "long_distance_discount": estimate.long_distance_discount
        },
        "subtotal": estimate.subtotal,
        "platform_fee": estimate.platform_fee,
        "access_for_all_fee": {
            "total": 0.10,
            "customer_share": 0.05,
            "driver_share": 0.05,
            "description": "CPUC Access for All Fund"
        },
        "total": round(estimate.total + 0.05, 2),  # Customer total includes A4A share
        "tier": estimate.tier,
        "tier_label": estimate.tier_label,
        "driver_info": {
            "earnings": round(estimate.driver_earnings - 0.05, 2),  # Driver A4A share deducted
            "per_mile": estimate.driver_earnings_per_mile,
            "per_hour": estimate.driver_earnings_per_hour,
            "percentage": estimate.driver_percentage,
            "a4a_deduction": 0.05
        },
        "suggested_bids": [
            {
                "label": bid.label,
                "emoji": bid.emoji,
                "price": bid.price,
                "driver_earnings": bid.driver_earnings,
                "acceptance_hint": bid.acceptance_hint,
                "per_mile": bid.per_mile,
                "is_recommended": bid.is_recommended
            }
            for bid in estimate.suggested_bids
        ],
        "messaging": {
            "customer": f"Fair market estimate: ${estimate.subtotal:.2f}",
            "driver": pricing_engine.get_driver_earnings_context(
                estimate.driver_earnings,
                estimate.distance_miles,
                estimate.duration_minutes
            )
        }
    }


def get_bid_label(bid_price: float, fare_estimate: float) -> dict:
    """Get bid comparison label for customer UI"""
    label, description, color = pricing_engine.get_bid_comparison_label(bid_price, fare_estimate)
    return {
        "label": label,
        "description": description,
        "color": color
    }
