"""
Rideshare Payment Routes - Tiered Platform Fee
===============================================

Tiered Fee Model (based on fare):
- Tier 1 (fare <= $35):  $1 from customer + $1 from driver = $2 platform
- Tier 2 ($35 < fare <= $70): $2 from customer + $2 from driver = $4 platform
- Tier 3 (fare > $70): $3 from customer + $3 from driver = $6 platform
"""

from fastapi import APIRouter, Depends, HTTPException, Header, Request
from auth_utils import require_any_auth, require_driver, require_customer
from cache import check_rate_limit, RateLimiter
from sqlalchemy.orm import Session
from sqlalchemy import and_
from pydantic import BaseModel
from typing import Optional
import stripe
import os
import logging

from database import get_db
from pricing_config import platform_fee_for
from models import RideRequest, RideRequestStatus, Driver, Customer

stripe.api_key = os.getenv("STRIPE_SECRET_KEY", "")  # SECURITY: No hardcoded fallback
logger = logging.getLogger(__name__)

router = APIRouter(prefix="/api/payments/ride", tags=["Rideshare Payments"])

payment_limiter = RateLimiter(max_requests=10, window_seconds=60)  # 10 per minute per user

# Demo account emails for App Store review
DEMO_CUSTOMER_EMAILS = [
    "demo.customer@dollor.ai",
    "demo.driver@dollor.ai",
]


def get_tier_fee(fare: float) -> float:
    """Get platform fee based on fare tier (configured in pricing_config)."""
    return platform_fee_for(fare)


class CreatePaymentIntent(BaseModel):
    ride_request_id: int


class PaymentResponse(BaseModel):
    success: bool
    fare: float
    tier_fee: float
    access_for_all_fee: float = 0.10  # TNC-13: CPUC $0.10/trip — $0.05 from customer + $0.05 from driver
    customer_pays: float
    driver_receives: float
    platform_earns: float
    payment_intent_id: Optional[str] = None
    client_secret: Optional[str] = None


@router.post("/create-intent", response_model=PaymentResponse)
async def create_payment_intent(http_request: Request, data: CreatePaymentIntent, db: Session = Depends(get_db), customer: Customer = Depends(require_customer)):
    """Create Stripe payment for completed ride with tiered pricing.

    SECURITY: Requires customer authentication and verifies ride ownership.

    For demo accounts (App Store review), returns a demo payment response
    that bypasses actual Stripe processing.
    """
    check_rate_limit(http_request, payment_limiter, "payment", identifier=str(customer.id))
    ride = db.query(RideRequest).filter(RideRequest.id == data.ride_request_id).first()

    if not ride:
        raise HTTPException(status_code=404, detail="Ride not found")

    # SECURITY: Verify the requesting customer owns this ride
    if ride.customer_id != customer.id:
        raise HTTPException(status_code=403, detail="You can only pay for your own rides")

    if ride.status not in [RideRequestStatus.MATCHED, RideRequestStatus.IN_PROGRESS, RideRequestStatus.COMPLETED]:
        raise HTTPException(status_code=400, detail=f"Invalid status: {ride.status.value}")

    # Idempotency: if payment already exists, return existing data
    if ride.stripe_payment_intent_id and ride.stripe_payment_intent_id != "demo_pi_appstore_review":
        fare = ride.final_price or ride.suggested_price
        tier_fee = get_tier_fee(fare)
        return PaymentResponse(
            success=True,
            fare=fare,
            tier_fee=tier_fee,
            access_for_all_fee=0.10,
            customer_pays=fare + tier_fee + 0.05,
            driver_receives=fare - tier_fee - 0.05,
            platform_earns=tier_fee * 2,
            payment_intent_id=ride.stripe_payment_intent_id,
            client_secret=None  # Cannot retrieve secret after creation
        )

    fare = ride.final_price or ride.suggested_price
    tier_fee = get_tier_fee(fare)
    # TNC-13: Access for All fee — $0.10/trip split: $0.05 customer + $0.05 driver
    access_for_all_fee = 0.10
    customer_a4a_share = 0.05
    driver_a4a_share = 0.05
    customer_pays = fare + tier_fee + customer_a4a_share
    driver_receives = fare - tier_fee - driver_a4a_share
    platform_earns = tier_fee * 2  # Platform fee unchanged; A4A is pass-through to CPUC

    # Check for demo account - bypass Stripe for App Store review
    if ride.customer_id:
        customer = db.query(Customer).filter(Customer.id == ride.customer_id).first()
        if customer and customer.email and customer.email.lower() in [e.lower() for e in DEMO_CUSTOMER_EMAILS]:
            logger.info(f"Demo account detected for ride {ride.id}: {customer.email} - bypassing Stripe payment")
            # Mark ride as demo paid
            ride.stripe_payment_intent_id = "demo_pi_appstore_review"
            ride.platform_fee = platform_earns
            ride.driver_payout = driver_receives
            db.commit()

            return PaymentResponse(
                success=True,
                fare=fare,
                tier_fee=tier_fee,
                access_for_all_fee=access_for_all_fee,
                customer_pays=customer_pays,
                driver_receives=driver_receives,
                platform_earns=platform_earns,
                payment_intent_id="demo_pi_appstore_review",
                client_secret="demo_pi_appstore_review_secret"
            )

    try:
        payment_intent = stripe.PaymentIntent.create(
            amount=int(round(customer_pays * 100)),
            currency="usd",
            metadata={
                "ride_id": ride.id,
                "fare": str(fare),
                "tier_fee": str(tier_fee),
                "access_for_all_fee": str(access_for_all_fee),
                "customer_a4a_share": str(customer_a4a_share),
                "driver_a4a_share": str(driver_a4a_share),
                "customer_pays": str(customer_pays),
                "driver_payout": str(driver_receives),
                "platform_earns": str(platform_earns)
            },
            idempotency_key=f"ride_pi_{ride.id}_{ride.request_id}"
        )

        ride.stripe_payment_intent_id = payment_intent.id
        ride.platform_fee = platform_earns
        ride.driver_payout = driver_receives
        db.commit()

        return PaymentResponse(
            success=True,
            fare=fare,
            tier_fee=tier_fee,
            access_for_all_fee=access_for_all_fee,
            customer_pays=customer_pays,
            driver_receives=driver_receives,
            platform_earns=platform_earns,
            payment_intent_id=payment_intent.id,
            client_secret=payment_intent.client_secret
        )
    except stripe.error.StripeError:
        raise HTTPException(status_code=500, detail="Payment failed")


@router.get("/driver/{driver_id}/earnings")
async def get_driver_earnings(driver_id: int, db: Session = Depends(get_db), driver: Driver = Depends(require_driver)):
    """Get driver earnings summary with tiered fees.

    SECURITY: Requires driver authentication and verifies ownership.
    """
    # SECURITY: Driver can only view their own earnings
    if driver.id != driver_id:
        raise HTTPException(status_code=403, detail="Access denied")

    rides = db.query(RideRequest).filter(
        and_(
            RideRequest.matched_driver_id == driver_id,
            RideRequest.status == RideRequestStatus.COMPLETED
        )
    ).all()

    total_earnings = 0.0
    total_a4a_deducted = 0.0
    for r in rides:
        fare = r.final_price or r.suggested_price or 0
        tier_fee = get_tier_fee(fare)
        driver_a4a = 0.05  # TNC-13: driver's share of Access for All fee
        total_earnings += fare - tier_fee - driver_a4a
        total_a4a_deducted += driver_a4a

    return {
        "driver_id": driver_id,
        "total_rides": len(rides),
        "total_earnings": round(total_earnings, 2),
        "total_platform_fees": round(sum(get_tier_fee(r.final_price or r.suggested_price or 0) for r in rides), 2),
        "total_access_for_all_fees": round(total_a4a_deducted, 2),
        "access_for_all_note": "$0.05/trip — supports wheelchair-accessible vehicle services (CPUC mandate, not a Dollor.ai fee)"
    }


@router.get("/pricing-info")
async def get_pricing_info():
    """Platform tiered pricing info with Access for All fee transparency."""
    return {
        "tiers": [
            {"max_fare": 35.00, "fee": 1.00, "platform_total": 2.00},
            {"min_fare": 35.01, "max_fare": 70.00, "fee": 2.00, "platform_total": 4.00},
            {"min_fare": 70.01, "fee": 3.00, "platform_total": 6.00}
        ],
        "access_for_all_fee": {
            "total": 0.10,
            "customer_share": 0.05,
            "driver_share": 0.05,
            "description": "CPUC Access for All Fund — supports wheelchair-accessible vehicle services in California",
            "authority": "CPUC Decision 19-06-033"
        },
        "examples": [
            {"fare": 25.00, "tier_fee": 1.00, "a4a_fee": 0.10, "customer_pays": 26.05, "driver_receives": 23.95, "platform_earns": 2.00},
            {"fare": 50.00, "tier_fee": 2.00, "a4a_fee": 0.10, "customer_pays": 52.05, "driver_receives": 47.95, "platform_earns": 4.00},
            {"fare": 100.00, "tier_fee": 3.00, "a4a_fee": 0.10, "customer_pays": 103.05, "driver_receives": 96.95, "platform_earns": 6.00}
        ],
        "transparency_note": "The $0.10 Access for All fee is split equally ($0.05 each) between rider and driver. 100% is remitted quarterly to the CPUC — Dollor.ai keeps none of it."
    }
