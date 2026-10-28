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
    minimum_fare_adjustment: float = 0.0


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

        # Every line is rounded to cents first so the breakdown lines add up to the subtotal exactly.
        base_fare = round(self.config.BASE_FARE, 2)
        distance_cost = round(distance_miles * self.config.PER_MILE_RATE, 2)
        time_cost = round(duration_minutes * self.config.PER_MINUTE_RATE, 2)
        raw_subtotal = base_fare + distance_cost + time_cost

        time_mult, time_label = self._get_time_adjustment(pickup_time)
        time_adjustment = round(raw_subtotal * (time_mult - 1), 2)
        long_distance_discount = round(self._get_distance_discount(distance_miles), 2)

        computed = round(raw_subtotal + time_adjustment - long_distance_discount, 2)
        minimum_fare_adjustment = round(max(0.0, self.config.MINIMUM_FARE - computed), 2)
        subtotal = round(computed + minimum_fare_adjustment, 2)

        charge = ride_charge_breakdown(subtotal)
        platform_fee = charge["platform_fee"]
        tier = self._get_tier(subtotal)
        tier_label = self._get_tier_label(subtotal)

        total = charge["customer_total"]  # fare + platform fee + rider Access-for-All share
        driver_earnings = charge["driver_payout"]  # fare - platform fee - driver Access-for-All share
        driver_per_mile = driver_earnings / distance_miles if distance_miles > 0 else 0
        driver_per_hour = (driver_earnings / duration_minutes) * 60 if duration_minutes > 0 else 0
        driver_percentage = (driver_earnings / total) * 100 if total > 0 else 0

        suggested_bids = self._generate_bid_suggestions(subtotal, distance_miles)

        return FareEstimate(
            distance_miles=round(distance_miles, 2),
            duration_minutes=duration_minutes,
            base_fare=base_fare,
            distance_cost=distance_cost,
            time_cost=time_cost,
            time_adjustment=time_adjustment,
            time_adjustment_label=time_label,
            long_distance_discount=long_distance_discount,
            subtotal=subtotal,
            platform_fee=platform_fee,
            total=total,
            driver_earnings=driver_earnings,
            driver_earnings_per_mile=round(driver_per_mile, 2),
            driver_earnings_per_hour=round(driver_per_hour, 2),
            driver_percentage=round(driver_percentage, 1),
            suggested_bids=suggested_bids,
            tier=tier,
            tier_label=tier_label,
            minimum_fare_adjustment=minimum_fare_adjustment
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

        prices = (
            ("Quick Accept", "⚡", subtotal * self.config.BID_QUICK_ACCEPT_FACTOR, "90% acceptance rate", False),
            ("Fair Price", "✓", subtotal, "75% acceptance rate", True),
            ("Premium", "💎", subtotal * self.config.BID_PREMIUM_FACTOR, "50% acceptance rate", False),
        )
        bids = []
        for label, emoji, raw_price, hint, recommended in prices:
            price = round(raw_price, 2)
            earnings = ride_charge_breakdown(price)["driver_payout"]
            bids.append(SuggestedBid(
                label=label,
                emoji=emoji,
                price=price,
                driver_earnings=earnings,
                acceptance_hint=hint,
                per_mile=round(earnings / distance_miles, 2) if distance_miles > 0 else 0,
                is_recommended=recommended,
            ))
        return bids

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


def ride_charge_breakdown(agreed_price: float) -> dict:
    """Single source of truth for what a ride at `agreed_price` costs the rider and pays the driver.

    The rider is charged price + platform fee + rider Access-for-All share. The driver receives
    price - platform fee - driver Access-for-All share. Used by the estimate, the pre-authorization at
    accept, the payment intent, completion payout and receipts so they can never drift apart.
    """
    cfg = pricing_engine.config
    price = round(float(agreed_price), 2)
    fee = round(platform_fee_for(price), 2)
    rider_share = round(cfg.ACCESS_FOR_ALL_RIDER_SHARE, 2)
    driver_share = round(cfg.ACCESS_FOR_ALL_DRIVER_SHARE, 2)
    return {
        "price": price,
        "platform_fee": fee,
        "rider_a4a_share": rider_share,
        "driver_a4a_share": driver_share,
        "customer_total": round(price + fee + rider_share, 2),
        "driver_payout": round(price - fee - driver_share, 2),
    }


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
    cfg = pricing_engine.config

    return {
        "distance_miles": estimate.distance_miles,
        "duration_minutes": estimate.duration_minutes,
        "breakdown": {
            "base_fare": estimate.base_fare,
            "distance_cost": estimate.distance_cost,
            "time_cost": estimate.time_cost,
            "time_adjustment": estimate.time_adjustment,
            "time_adjustment_label": estimate.time_adjustment_label,
            "long_distance_discount": estimate.long_distance_discount,
            "minimum_fare_adjustment": estimate.minimum_fare_adjustment
        },
        "subtotal": estimate.subtotal,
        "platform_fee": estimate.platform_fee,
        "access_for_all_fee": {
            "total": cfg.ACCESS_FOR_ALL_FEE,
            "customer_share": cfg.ACCESS_FOR_ALL_RIDER_SHARE,
            "driver_share": cfg.ACCESS_FOR_ALL_DRIVER_SHARE,
            "description": "CPUC Access for All Fund"
        },
        "total": estimate.total,  # subtotal + platform fee + rider Access-for-All share
        "tier": estimate.tier,
        "tier_label": estimate.tier_label,
        "driver_info": {
            "earnings": estimate.driver_earnings,  # subtotal - platform fee - driver A4A share
            "per_mile": estimate.driver_earnings_per_mile,
            "per_hour": estimate.driver_earnings_per_hour,
            "percentage": estimate.driver_percentage,
            "a4a_deduction": cfg.ACCESS_FOR_ALL_DRIVER_SHARE
        },
        "suggested_bids": [
            {
                "label": bid.label,
                "emoji": bid.emoji,
                "price": bid.price,
                "driver_earnings": bid.driver_earnings,
                "customer_total": ride_charge_breakdown(bid.price)["customer_total"],
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


def apply_fare_multiplier(estimate: dict, multiplier: float) -> dict:
    """Scale an estimate dict (ride type / demand) and keep every line reconciled.

    The extra amount appears as breakdown["demand_adjustment"]; fee, total, driver earnings and the
    suggested bids are recomputed from the new fares via ride_charge_breakdown.
    """
    estimate["breakdown"]["demand_adjustment"] = 0.0
    if multiplier == 1.0:
        return estimate
    old_subtotal = estimate["subtotal"]
    subtotal = round(old_subtotal * multiplier, 2)
    charge = ride_charge_breakdown(subtotal)
    estimate["breakdown"]["demand_adjustment"] = round(subtotal - old_subtotal, 2)
    estimate["subtotal"] = subtotal
    estimate["platform_fee"] = charge["platform_fee"]
    estimate["total"] = charge["customer_total"]
    estimate["driver_info"]["earnings"] = charge["driver_payout"]
    miles = estimate["distance_miles"]
    minutes = estimate["duration_minutes"]
    estimate["driver_info"]["per_mile"] = round(charge["driver_payout"] / miles, 2) if miles > 0 else 0
    estimate["driver_info"]["per_hour"] = round(charge["driver_payout"] / minutes * 60, 2) if minutes > 0 else 0
    estimate["driver_info"]["percentage"] = round(charge["driver_payout"] / charge["customer_total"] * 100, 1)
    for bid in estimate["suggested_bids"]:
        bid_charge = ride_charge_breakdown(round(bid["price"] * multiplier, 2))
        bid["price"] = bid_charge["price"]
        bid["driver_earnings"] = bid_charge["driver_payout"]
        bid["customer_total"] = bid_charge["customer_total"]
        bid["per_mile"] = round(bid_charge["driver_payout"] / miles, 2) if miles > 0 else 0
    return estimate


def get_bid_label(bid_price: float, fare_estimate: float) -> dict:
    """Get bid comparison label for customer UI"""
    label, description, color = pricing_engine.get_bid_comparison_label(bid_price, fare_estimate)
    return {
        "label": label,
        "description": description,
        "color": color
    }
