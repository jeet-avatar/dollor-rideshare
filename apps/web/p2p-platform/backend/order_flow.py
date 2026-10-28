"""
EatFair P2P - Complete Order Flow
End-to-end order processing from customer to delivery with payouts

Flow:
1. Customer places order → Payment captured
2. Restaurant receives order → Confirms & prepares
3. Driver assigned → Picks up order
4. Driver delivers → Order completed
5. Accounting: Journal entries created, payouts calculated

AI Employees:
- OrderBot Alpha (AI_EMP_001): Order validation & creation
- KitchenBot Beta (AI_EMP_002): Restaurant coordination
- DispatchBot Gamma (AI_EMP_003): Driver assignment & delivery
- LedgerBot Delta (AI_EMP_004): Accounting & payouts
- QualityBot Epsilon (AI_EMP_005): Quality monitoring
"""

from fastapi import APIRouter, Depends, HTTPException, Query, UploadFile, File, Request
from auth_utils import require_any_auth, require_driver, require_customer, require_vendor, require_admin
from cache import check_rate_limit, RateLimiter
from sqlalchemy.orm import Session
from sqlalchemy import text, or_, and_, func
from datetime import datetime, timedelta
from typing import Optional, List, Dict, Any
from pydantic import BaseModel, Field
import asyncio
import json
import logging
import os
import requests

from database import get_db, SessionLocal
from email_service import send_order_delivered_with_receipt_email, send_delivery_completed_driver_email, send_delivery_completed_vendor_email, send_email
from driver_sessions import ensure_can_go_offline, ensure_can_go_online, ensure_open_session, record_online_state
from google_maps_service import get_traffic_eta, ETAResult
from apscheduler.schedulers.background import BackgroundScheduler
from apscheduler.triggers.interval import IntervalTrigger
from apscheduler.triggers.cron import CronTrigger

logger = logging.getLogger(__name__)

# Service URLs
PAYMENT_SERVICE_URL = os.getenv("PAYMENT_SERVICE_URL", "http://payment-service:8008")
NOTIFICATION_SERVICE_URL = os.getenv("NOTIFICATION_SERVICE_URL", "http://notification-service:8009")

# Firebase Admin SDK for direct push notifications
_firebase_initialized = False
_firebase_app = None

def _init_firebase():
    """Initialize Firebase Admin SDK for direct push notifications."""
    global _firebase_initialized, _firebase_app
    if _firebase_initialized:
        return _firebase_app is not None

    _firebase_initialized = True
    firebase_creds_path = os.getenv("FIREBASE_CREDENTIALS_PATH", "")
    firebase_creds_json = os.getenv("FIREBASE_CREDENTIALS_JSON", "")

    try:
        import firebase_admin
        from firebase_admin import credentials

        if firebase_creds_path and os.path.exists(firebase_creds_path):
            cred = credentials.Certificate(firebase_creds_path)
            _firebase_app = firebase_admin.initialize_app(cred)
            logging.info("Firebase initialized from credentials file")
            return True
        elif firebase_creds_json:
            import json as json_mod
            cred_dict = json_mod.loads(firebase_creds_json)
            cred = credentials.Certificate(cred_dict)
            _firebase_app = firebase_admin.initialize_app(cred)
            logging.info("Firebase initialized from JSON env var")
            return True
        else:
            logging.warning("No Firebase credentials configured - push notifications disabled")
            return False
    except Exception as e:
        logging.error(f"Failed to initialize Firebase: {e}")
        return False


def _send_fcm_direct(fcm_token: str, title: str, body: str, data: dict = None) -> bool:
    """Send FCM push notification directly using Firebase Admin SDK."""
    if not _init_firebase():
        return False

    try:
        from firebase_admin import messaging

        message = messaging.Message(
            notification=messaging.Notification(title=title, body=body),
            data={k: str(v) for k, v in (data or {}).items()},
            token=fcm_token
        )
        messaging.send(message)
        logging.info(f"Direct FCM push sent: {title}")
        return True
    except Exception as e:
        logging.error(f"Direct FCM push failed: {e}")
        return False
def send_push_notification(user_type: str, user_id: int, title: str, body: str, data: dict = None, db: Session = None) -> bool:
    """
    Send push notification via notification service or direct FCM.
    user_type: 'customer', 'driver', or 'vendor'
    Returns True if successful, False otherwise.

    Falls back to direct FCM if notification service is unavailable.
    """
    # First, try notification service
    try:
        payload = {
            "title": title,
            "body": body,
            "data": data or {}
        }

        # Map user_type to the correct field for notification service
        if user_type == "driver":
            payload["driver_id"] = user_id
        elif user_type == "vendor":
            payload["vendor_id"] = user_id
        else:  # customer or user
            payload["user_id"] = user_id

        response = requests.post(
            f"{NOTIFICATION_SERVICE_URL}/api/notifications/push/send",
            json=payload,
            timeout=5
        )
        if response.status_code == 200:
            logger.info(f"Push notification sent via service to {user_type} {user_id}")
            return True
        else:
            logger.warning(f"Notification service returned error: {response.text}")
            # Fall through to direct FCM
    except requests.RequestException as e:
        logger.warning(f"Notification service unavailable: {e}, trying direct FCM...")

    # Fallback: Direct FCM push notification
    try:
        # Get FCM token from database
        fcm_token = None
        if db is None:
            db = SessionLocal()
            should_close = True
        else:
            should_close = False

        try:
            if user_type == "driver":
                result = db.execute(
                    text("SELECT fcm_token FROM drivers WHERE id = :id"),
                    {"id": user_id}
                ).fetchone()
                if result:
                    fcm_token = result[0]
            elif user_type == "vendor":
                result = db.execute(
                    text("SELECT push_token FROM vendors WHERE id = :id"),
                    {"id": user_id}
                ).fetchone()
                if result:
                    fcm_token = result[0]
            else:  # customer
                result = db.execute(
                    text("SELECT push_token FROM customers WHERE id = :id"),
                    {"id": user_id}
                ).fetchone()
                if result:
                    fcm_token = result[0]
        finally:
            if should_close:
                db.close()

        if fcm_token:
            if _send_fcm_direct(fcm_token, title, body, data):
                logger.info(f"Direct FCM push sent to {user_type} {user_id}")
                return True
            else:
                logger.error(f"Direct FCM push failed for {user_type} {user_id}")
                return False
        else:
            logger.warning(f"No FCM token found for {user_type} {user_id}")
            return False
    except Exception as e:
        logger.error(f"Direct FCM fallback failed: {e}")
        return False

from models import (
    Order, OrderStatus, Vendor, VendorMenuItem, Driver, DriverStatus,
    VendorPayout, DriverPayout, JournalEntry, JournalEntryLine, VendorStatus,
    Customer, User, RideRequest as RideRequestModel, RideRequestStatus,
    Prop22EarningPeriod, Prop22EarningsStatement,
)

router = APIRouter(prefix="/api/erp", tags=["erp"])
# AI Employees
AI_EMPLOYEES = {
    "ORDER_PROCESSOR": {
        "id": "AI_EMP_001",
        "name": "OrderBot Alpha",
        "role": "Order Processor"
    },
    "RESTAURANT_COORDINATOR": {
        "id": "AI_EMP_002",
        "name": "KitchenBot Beta",
        "role": "Restaurant Coordinator"
    },
    "DELIVERY_DISPATCHER": {
        "id": "AI_EMP_003",
        "name": "DispatchBot Gamma",
        "role": "Delivery Dispatcher"
    },
    "ACCOUNTANT": {
        "id": "AI_EMP_004",
        "name": "LedgerBot Delta",
        "role": "Accounting Specialist"
    },
    "QA_MONITOR": {
        "id": "AI_EMP_005",
        "name": "QualityBot Epsilon",
        "role": "Quality Monitor"
    }
}


class AssignDriverRequest(BaseModel):
    """Request body for a driver accepting a ride (see accept_ride below)."""
    driver_id: int
    driver_eta_minutes: Optional[int] = None


class RideRequest(BaseModel):
    """P2P Ride Request - Customer picks pickup and dropoff locations"""
    customer_name: str
    customer_email: str
    customer_phone: str
    pickup_address: Dict[str, Any]  # {street, city, state, zip, lat, lng}
    dropoff_address: Dict[str, Any]  # {street, city, state, zip, lat, lng}
    notes: Optional[str] = None
    tip: float = 0.0


# ==================== WORLD-CLASS RIDE PRICING ====================
# Competitive with Uber/Lyft but driver-friendly (~90% to driver)
# Compliant with US tax regulations and business requirements

# Platform Fee (EatFair Revenue) - Simple $1 flat fee
PLATFORM_FEE = 1.00      # $1 flat platform fee - ONLY fee to EatFair

# Driver Earnings (100% to driver, minus taxes)
BASE_FARE = 2.50         # $2.50 base fare per ride (matches pricing_config.py:18)
PER_MILE_RATE = 1.15     # $1.15 per mile (matches pricing_config.py:19)
PER_MINUTE_RATE = 0.18   # $0.18 per minute (matches pricing_config.py:20)

# Minimums & Caps
MINIMUM_FARE = 8.00      # Minimum total fare (matches pricing_config.py:21)
MAXIMUM_SURGE = 3.0      # Maximum surge multiplier

# Surge Pricing Thresholds
SURGE_LEVELS = {
    "normal": 1.0,       # Default
    "busy": 1.25,        # Rush hours
    "very_busy": 1.5,    # Weekend nights
    "high_demand": 2.0,  # Events/weather
    "extreme": 2.5       # NYE, emergencies
}

# ==================== TAX & COMPLIANCE CONFIGURATION ====================
# US Tax Rates by State (Sales Tax on ride-sharing services)
# Note: Some states exempt ride-sharing from sales tax
STATE_TAX_RATES = {
    # States WITH ride-share sales tax
    "CA": 0.0725,   # California 7.25% base (varies by city)
    "NY": 0.08875,  # New York 8.875% (NYC)
    "TX": 0.0625,   # Texas 6.25%
    "FL": 0.06,     # Florida 6%
    "IL": 0.0625,   # Illinois 6.25%
    "PA": 0.06,     # Pennsylvania 6%
    "OH": 0.0575,   # Ohio 5.75%
    "GA": 0.04,     # Georgia 4%
    "NC": 0.0475,   # North Carolina 4.75%
    "MI": 0.06,     # Michigan 6%
    "NJ": 0.06625,  # New Jersey 6.625%
    "VA": 0.053,    # Virginia 5.3%
    "WA": 0.065,    # Washington 6.5%
    "AZ": 0.056,    # Arizona 5.6%
    "MA": 0.0625,   # Massachusetts 6.25%
    "TN": 0.07,     # Tennessee 7%
    "IN": 0.07,     # Indiana 7%
    "MO": 0.04225,  # Missouri 4.225%
    "MD": 0.06,     # Maryland 6%
    "WI": 0.05,     # Wisconsin 5%
    "CO": 0.029,    # Colorado 2.9%
    "MN": 0.06875,  # Minnesota 6.875%
    "SC": 0.06,     # South Carolina 6%
    "AL": 0.04,     # Alabama 4%
    "LA": 0.0445,   # Louisiana 4.45%
    "KY": 0.06,     # Kentucky 6%
    "OK": 0.045,    # Oklahoma 4.5%
    "CT": 0.0635,   # Connecticut 6.35%
    "UT": 0.0485,   # Utah 4.85%
    "IA": 0.06,     # Iowa 6%
    "NV": 0.0685,   # Nevada 6.85%
    "AR": 0.065,    # Arkansas 6.5%
    "MS": 0.07,     # Mississippi 7%
    "KS": 0.065,    # Kansas 6.5%
    "NM": 0.05125,  # New Mexico 5.125%
    "NE": 0.055,    # Nebraska 5.5%
    "WV": 0.06,     # West Virginia 6%
    "ID": 0.06,     # Idaho 6%
    "HI": 0.04,     # Hawaii 4%
    "NH": 0.0,      # New Hampshire - No sales tax
    "ME": 0.055,    # Maine 5.5%
    "RI": 0.07,     # Rhode Island 7%
    "MT": 0.0,      # Montana - No sales tax
    "DE": 0.0,      # Delaware - No sales tax
    "SD": 0.045,    # South Dakota 4.5%
    "ND": 0.05,     # North Dakota 5%
    "AK": 0.0,      # Alaska - No state sales tax
    "VT": 0.06,     # Vermont 6%
    "DC": 0.06,     # Washington DC 6%
    "WY": 0.04,     # Wyoming 4%
    "OR": 0.0,      # Oregon - No sales tax
}

# Default tax rate if state not found
DEFAULT_TAX_RATE = 0.06  # 6% default

# Additional regulatory fees (some cities/states require these)
REGULATORY_FEES = {
    "airport_fee": 3.00,      # Airport pickup/dropoff fee
    "black_car_fund": 0.0,    # NY Black Car Fund (2.5% for black car only)
    "accessibility_fee": 0.10, # ADA accessibility fund
}

def get_tax_rate(state_code: str) -> float:
    """Get sales tax rate for a state"""
    return STATE_TAX_RATES.get(state_code.upper(), DEFAULT_TAX_RATE)


# NOTE: CUSTOMER_SERVICE_FEE and calculate_delivery_fee are kept as standalone
# definitions (the food-delivery fee constants they used to live alongside, and the
# /api/cart and food order-creation endpoints that used them, were removed) because
# stripe_integration.py's own /api/orders order-creation endpoint still imports them.
# That endpoint is a second, largely-duplicate food-order-creation path that was not
# in this cleanup's explicit scope — see the directive-3 report for why it was left
# alone (it shares a module with the live Stripe webhook that also processes ride
# payments, which is too risky to touch without dedicated review).
CUSTOMER_SERVICE_FEE = 1.00  # $1 service fee — used by stripe_integration.py's /api/orders


def calculate_delivery_fee(distance_miles: float = None, surge_multiplier: float = 1.0) -> float:
    """
    Calculate delivery fee based on distance and current demand.
    Used by stripe_integration.py's /api/orders (food order creation) — see note above.
    """
    DELIVERY_BASE_FEE = 2.49
    DELIVERY_PER_MILE = 0.50
    DELIVERY_MIN_FEE = 2.99
    DELIVERY_MAX_FEE = 12.99
    DELIVERY_DEFAULT_FEE = 4.99

    if distance_miles is None:
        base_fee = DELIVERY_DEFAULT_FEE
    else:
        base_fee = DELIVERY_BASE_FEE + (distance_miles * DELIVERY_PER_MILE)

    surge_multiplier = min(surge_multiplier, 2.0)
    total_fee = base_fee * surge_multiplier
    total_fee = max(DELIVERY_MIN_FEE, min(total_fee, DELIVERY_MAX_FEE))

    return round(total_fee, 2)

def calculate_ride_fare(
    distance_miles: float,
    duration_minutes: float,
    surge_multiplier: float = 1.0,
    tip: float = 0.0,
    state_code: str = "CA",
    is_airport: bool = False
):
    """
    Calculate ride fare with world-class pricing structure.
    Includes tax calculation for US compliance.

    Pricing Philosophy:
    - $1 FLAT platform fee (simple, transparent)
    - Driver gets ~90% of fare (industry-leading!)
    - Tax calculated based on rider's state
    - Tips 100% to driver (never taxed to platform)

    Returns complete breakdown for receipts/invoices.
    """
    # Calculate driver portion (before surge)
    base_fare = BASE_FARE
    distance_fee = distance_miles * PER_MILE_RATE
    time_fee = duration_minutes * PER_MINUTE_RATE

    # Apply surge to driver portion only
    driver_base = base_fare + distance_fee + time_fee
    driver_subtotal = driver_base * surge_multiplier
    surge_amount = driver_subtotal - driver_base if surge_multiplier > 1.0 else 0

    # Platform fee (ONLY $1, not affected by surge)
    platform_fee = PLATFORM_FEE

    # Subtotal before tax
    subtotal_before_tax = platform_fee + driver_subtotal

    # Apply minimum fare
    if subtotal_before_tax < MINIMUM_FARE:
        driver_subtotal = MINIMUM_FARE - platform_fee
        subtotal_before_tax = MINIMUM_FARE

    # Calculate tax (on the service, not on tips)
    tax_rate = get_tax_rate(state_code)
    tax_amount = round(subtotal_before_tax * tax_rate, 2)

    # Airport fee if applicable
    airport_fee = REGULATORY_FEES["airport_fee"] if is_airport else 0.0

    # Accessibility fund (small contribution)
    accessibility_fee = REGULATORY_FEES["accessibility_fee"]

    # Final totals
    total_before_tip = subtotal_before_tax + tax_amount + airport_fee + accessibility_fee
    total_fare = total_before_tip + tip

    # Driver earnings (fare portion + tip, driver handles their own income tax)
    driver_earnings = driver_subtotal + tip

    # Platform earnings (just the $1 fee)
    platform_earnings = platform_fee

    return {
        # Core pricing
        "platform_fee": platform_fee,
        "base_fare": BASE_FARE,
        "distance_fee": round(distance_fee, 2),
        "time_fee": round(time_fee, 2),
        "surge_multiplier": surge_multiplier,
        "surge_amount": round(surge_amount, 2),

        # Tax & regulatory (for compliance)
        "subtotal_before_tax": round(subtotal_before_tax, 2),
        "tax_rate": tax_rate,
        "tax_rate_percent": f"{tax_rate * 100:.2f}%",
        "tax_amount": tax_amount,
        "state_code": state_code.upper(),
        "airport_fee": airport_fee,
        "accessibility_fee": accessibility_fee,

        # Tip (100% to driver)
        "tip": tip,

        # Totals
        "total_before_tip": round(total_before_tip, 2),
        "total_fare": round(total_fare, 2),

        # Earnings split
        "driver_earnings": round(driver_earnings, 2),
        "platform_earnings": round(platform_earnings, 2),
        "driver_percentage": round((driver_earnings / total_fare) * 100, 1) if total_fare > 0 else 0,

        # Trip info
        "estimated_distance_miles": distance_miles,
        "estimated_duration_minutes": duration_minutes,

        # For receipts
        "receipt_line_items": [
            {"description": "Base Fare", "amount": BASE_FARE},
            {"description": f"Distance ({distance_miles:.1f} mi × $1.00)", "amount": round(distance_fee, 2)},
            {"description": f"Time ({int(duration_minutes)} min × $0.15)", "amount": round(time_fee, 2)},
            {"description": "Platform Fee", "amount": platform_fee},
            {"description": f"Sales Tax ({tax_rate * 100:.2f}%)", "amount": tax_amount},
        ]
    }

def estimate_distance_and_time(pickup_lat: float, pickup_lng: float, dropoff_lat: float, dropoff_lng: float):
    """
    Estimate distance (miles) and duration (minutes) between two points.
    Uses Haversine formula for distance, estimates time based on average speed.
    """
    import math

    # Haversine formula for distance
    R = 3959  # Earth's radius in miles

    lat1, lon1 = math.radians(pickup_lat), math.radians(pickup_lng)
    lat2, lon2 = math.radians(dropoff_lat), math.radians(dropoff_lng)

    dlat = lat2 - lat1
    dlon = lon2 - lon1

    a = math.sin(dlat/2)**2 + math.cos(lat1) * math.cos(lat2) * math.sin(dlon/2)**2
    c = 2 * math.asin(math.sqrt(a))

    distance_miles = R * c

    # Estimate duration: assume average 25 mph in urban areas (accounts for traffic, stops)
    # Add 20% buffer for real-world conditions
    avg_speed_mph = 25
    duration_minutes = (distance_miles / avg_speed_mph) * 60 * 1.2

    return round(distance_miles, 1), round(duration_minutes, 0)


# ==================== P2P RIDE FARE ESTIMATION ====================

@router.post("/rides/estimate")
async def estimate_ride_fare_endpoint(
    pickup_lat: float,
    pickup_lng: float,
    dropoff_lat: float,
    dropoff_lng: float,
    state_code: str = "CA",
    tip: float = 0.0,
    is_airport: bool = False
):
    """
    Get fare estimate before requesting a ride.
    Shows customer exactly what they'll pay including taxes.
    Fully compliant with US tax regulations.
    """
    # Estimate distance and duration
    distance_miles, duration_minutes = estimate_distance_and_time(
        pickup_lat, pickup_lng, dropoff_lat, dropoff_lng
    )

    # Calculate fare with tax
    fare_normal = calculate_ride_fare(distance_miles, duration_minutes, 1.0, tip, state_code, is_airport)
    fare_surge = calculate_ride_fare(distance_miles, duration_minutes, 1.5, tip, state_code, is_airport)

    return {
        "success": True,
        "distance_miles": distance_miles,
        "duration_minutes": duration_minutes,
        "fare_estimate": fare_normal,
        "fare_range": {
            "low": fare_normal["total_fare"],
            "high": fare_surge["total_fare"]
        },
        "pricing_info": {
            "platform_fee": "$1.00 flat",
            "base_fare": f"${BASE_FARE:.2f}",
            "per_mile": f"${PER_MILE_RATE:.2f}/mi",
            "per_minute": f"${PER_MINUTE_RATE:.2f}/min",
            "minimum_fare": f"${MINIMUM_FARE:.2f}",
            "tax_rate": fare_normal["tax_rate_percent"],
            "state": state_code.upper()
        },
        "driver_take_rate": f"{fare_normal['driver_percentage']}%",
        "message": f"Estimated {distance_miles} miles, {int(duration_minutes)} mins"
    }


@router.get("/rides/available")
async def get_available_rides(
    driver_lat: Optional[float] = None,
    driver_lng: Optional[float] = None,
    db: Session = Depends(get_db),
    driver: Driver = Depends(require_driver),
):
    """
    Get available P2P rides for drivers
    Returns ride requests waiting for driver acceptance
    """
    try:
        # Query RideRequest table for open/bidding rides (exclude expired)
        # Note: Using RideRequestModel to avoid shadowing by Pydantic RideRequest class
        now = datetime.utcnow()
        rides = db.query(RideRequestModel).filter(
            RideRequestModel.status.in_([RideRequestStatus.OPEN, RideRequestStatus.BIDDING]),
            or_(
                RideRequestModel.bidding_expires_at > now,
                RideRequestModel.bidding_expires_at.is_(None)
            )
        ).order_by(RideRequestModel.created_at.desc()).limit(50).all()

        result = []
        for ride in rides:
            # Get customer name
            customer_name = ride.customer_name or "Customer"

            # iOS P2PRideLocation expects: street, city, state, zip, lat, lng
            result.append({
                "ride_id": ride.id,
                "ride_number": ride.request_id or f"RR-{ride.id}",
                "customer_name": customer_name,
                "pickup": {
                    "street": ride.pickup_address or "",
                    "city": "",
                    "state": "",
                    "zip": "",
                    "lat": ride.pickup_latitude,
                    "lng": ride.pickup_longitude
                },
                "dropoff": {
                    "street": ride.dropoff_address or "",
                    "city": "",
                    "state": "",
                    "zip": "",
                    "lat": ride.dropoff_latitude,
                    "lng": ride.dropoff_longitude
                },
                "fee": ride.suggested_price or 0,
                "tip": 0,
                "total_earnings": ride.suggested_price or 0,
                "customer_preferred_price": ride.customer_preferred_price,  # Customer's negotiated offer
                "notes": None,
                "created_at": ride.created_at.isoformat() if ride.created_at else None,
                "status": ride.status.value if hasattr(ride.status, 'value') else str(ride.status),
                "distance_miles": (ride.estimated_distance_km or 0) * 0.621371
            })

        return {"success": True, "rides": result}
    except Exception as e:
        import traceback
        print(f"ERROR in get_available_rides: {e}")
        print(traceback.format_exc())
        return {"success": False, "rides": [], "error": str(e)}


@router.post("/rides/{ride_id}/accept")
async def accept_ride(
    ride_id: int,
    request: AssignDriverRequest,
    db: Session = Depends(get_db),
    driver: Driver = Depends(require_driver),
):
    """
    Retired: matched a ride with no bid and no payment authorization. No app calls it.
    Drivers bid (POST /api/rides/request/{id}/bid) and the rider accepts, or the driver accepts a counter.
    """
    raise HTTPException(status_code=410, detail="Deprecated endpoint. Use the bid flow: POST /api/rides/request/{id}/bid.")


@router.post("/rides/{ride_id}/picked-up")
async def ride_picked_up(
    ride_id: int,
    request: Request,
    db: Session = Depends(get_db),
    driver: Driver = Depends(require_driver),
):
    """
    Driver picked up customer. Runs the canonical start logic (matched driver only, MATCHED rides only).
    """
    from bid_routes import start_ride
    await start_ride(ride_id, request, driver, db)
    return {
        "success": True,
        "ride_id": ride_id,
        "status": "in_progress",
        "picked_up_at": datetime.now().isoformat()
    }


@router.post("/rides/{ride_id}/completed")
async def ride_completed(
    ride_id: int,
    db: Session = Depends(get_db),
    driver: Driver = Depends(require_driver),
):
    """
    Ride completed - customer dropped off.
    Called by Android driver app: POST /api/erp/rides/{rideId}/completed
    """
    ai_employee = AI_EMPLOYEES["DELIVERY_DISPATCHER"]

    from rideshare_payments import get_tier_fee

    ride = db.query(RideRequestModel).filter(RideRequestModel.id == ride_id).first()
    if not ride:
        raise HTTPException(status_code=404, detail="Ride not found")

    # IDOR: verify driver is assigned to this ride
    if ride.matched_driver_id != driver.id:
        raise HTTPException(status_code=403, detail="Not authorized for this ride")

    if ride.status == RideRequestStatus.COMPLETED:
        raise HTTPException(status_code=400, detail="Ride already completed")

    ride.status = RideRequestStatus.COMPLETED
    ride.completed_at = datetime.now()

    # Calculate driver earnings with tiered platform fee (aligned with bid_routes.py)
    fare = ride.final_price or ride.suggested_price or 0
    tier_fee = get_tier_fee(fare)
    tip = float(ride.tip_amount or 0)
    driver_earnings = round(fare - tier_fee + tip, 2)

    ride.platform_fee = tier_fee  # driver-side fee only (aligned with bid_routes.py)
    ride.driver_payout = driver_earnings

    db.commit()

    # Auto-trigger driver payout via Stripe Connect (non-blocking)
    try:
        import stripe
        stripe.api_key = os.getenv("STRIPE_SECRET_KEY")

        # Demo rides: skip Stripe, just mark payment status
        if ride.stripe_payment_intent_id and ride.stripe_payment_intent_id.startswith("demo_"):
            ride.payment_status = "demo"
            ride.payment_completed_at = datetime.now()
            db.commit()
            logging.getLogger(__name__).info(f"Ride {ride.id} is demo — skipping Stripe payout")
        else:
            driver = db.query(Driver).filter(Driver.id == ride.matched_driver_id).first()
            if driver and getattr(driver, 'stripe_account_id', None) and getattr(driver, 'stripe_onboarded', False):
                payout_cents = int(round(ride.driver_payout * 100))
                if payout_cents > 0:
                    transfer = stripe.Transfer.create(
                        amount=payout_cents,
                        currency="usd",
                        destination=driver.stripe_account_id,
                        description=f"Ride {ride.request_id} payout",
                        metadata={
                            "ride_id": str(ride.id),
                            "ride_request_id": ride.request_id,
                            "driver_id": str(driver.id),
                            "fare": str(fare),
                            "platform_fee": str(tier_fee),
                        },
                        idempotency_key=f"ride_driver_xfer_{ride.id}"
                    )
                    ride.stripe_transfer_id = transfer.id
                    ride.driver_paid_at = datetime.now()
                    db.commit()
                    logging.getLogger(__name__).info(f"Ride {ride.id} auto-payout ${ride.driver_payout:.2f} to driver {driver.id}")
            else:
                logging.getLogger(__name__).info(f"Ride {ride.id} driver not Stripe-onboarded, skipping auto-payout")
    except Exception as e:
        logging.getLogger(__name__).error(f"Ride {ride.id} auto-payout failed (non-blocking): {e}")

    return {
        "success": True,
        "ride_id": ride.id,
        "ride_number": ride.request_id,
        "status": "completed",
        "completed_at": ride.completed_at.isoformat(),
        "fare": fare,
        "tier_fee": tier_fee,
        "driver_earnings": driver_earnings,
        # Fields expected by Android RideCompleteResponse
        "earnings": driver_earnings,
        "tip": tip if tip > 0 else None,
        "total_earned": driver_earnings,
        "platform_fee": tier_fee,
        "processed_by": ai_employee["name"]
    }


# ==================== RIDE RECEIPT ====================

@router.get("/rides/{ride_id}/receipt")
async def get_ride_receipt(
    ride_id: int,
    db: Session = Depends(get_db),
    _auth: dict = Depends(require_any_auth),
):
    """
    Generate a detailed receipt for a completed ride.
    Includes full tax breakdown for compliance.
    """
    ride = db.query(Order).filter(Order.id == ride_id).first()
    if not ride:
        raise HTTPException(status_code=404, detail="Ride not found")

    # Parse stored data
    try:
        addr = json.loads(ride.delivery_address) if ride.delivery_address else {}
        items_data = json.loads(ride.items) if ride.items else []
        fare_breakdown = items_data[0].get("fare_breakdown", {}) if items_data else {}
        receipt_line_items = items_data[0].get("receipt_line_items", []) if items_data else []
    except Exception:
        addr = {}
        fare_breakdown = {}
        receipt_line_items = []

    pickup = addr.get("pickup", {})
    dropoff = addr.get("dropoff", {})
    state_code = addr.get("state_code", "CA")

    # Build comprehensive receipt
    receipt = {
        "receipt_id": f"RCP-{ride.order_number}",
        "ride_number": ride.order_number,
        "date": ride.created_at.isoformat() if ride.created_at else None,
        "completed_at": ride.delivered_at.isoformat() if ride.delivered_at else None,

        # Customer info
        "customer": {
            "name": ride.customer_name,
            "email": ride.customer_email,
            "phone": ride.customer_phone
        },

        # Driver info
        "driver": {
            "name": ride.driver_name,
            "id": ride.driver_id
        } if ride.driver_id else None,

        # Trip details
        "trip": {
            "pickup_address": pickup.get("street", ""),
            "pickup_city": pickup.get("city", ""),
            "pickup_state": pickup.get("state", ""),
            "dropoff_address": dropoff.get("street", ""),
            "dropoff_city": dropoff.get("city", ""),
            "dropoff_state": dropoff.get("state", ""),
            "distance_miles": fare_breakdown.get("estimated_distance_miles", 0),
            "duration_minutes": fare_breakdown.get("estimated_duration_minutes", 0)
        },

        # Itemized charges
        "line_items": receipt_line_items if receipt_line_items else [
            {"description": "Base Fare", "amount": fare_breakdown.get("base_fare", 0)},
            {"description": f"Distance", "amount": fare_breakdown.get("distance_fee", 0)},
            {"description": f"Time", "amount": fare_breakdown.get("time_fee", 0)},
            {"description": "Platform Fee", "amount": PLATFORM_FEE},
            {"description": f"Sales Tax ({(ride.tax_rate or 0) * 100:.2f}%)", "amount": ride.tax_amount or 0}
        ],

        # Tax details (for compliance)
        "tax_details": {
            "state_code": state_code,
            "tax_rate": ride.tax_rate or 0,
            "tax_rate_percent": f"{(ride.tax_rate or 0) * 100:.2f}%",
            "tax_amount": ride.tax_amount or 0,
            "taxable_amount": ride.subtotal or 0
        },

        # Totals
        "subtotal": ride.subtotal or 0,
        "tax_amount": ride.tax_amount or 0,
        "tip": ride.tip or 0,
        "total": ride.total_amount or 0,

        # Earnings breakdown (transparency)
        "earnings_split": {
            "driver_earnings": ride.delivery_fee or 0,
            "platform_fee": ride.platform_fee or PLATFORM_FEE,
            "driver_percentage": round(((ride.delivery_fee or 0) / (ride.total_amount or 1)) * 100, 1)
        },

        # Payment info
        "payment": {
            "status": ride.payment_status or "completed",
            "method": "card"
        },

        # Legal footer
        "legal": {
            "company_name": "Dollor.ai by Zietra Technologies inc",
            "support_email": "support@dollor.ai",
            "terms_url": "https://dollor.ai/terms"
        },

        # TNC-14: Regulatory info (CPUC compliance)
        "regulatory": {
            "zero_tolerance_policy": "Dollor.ai maintains a zero-tolerance policy for drug and alcohol use by drivers.",
            "report_safety_concern": "support@dollor.ai",
            "cpuc_consumer_complaint": {
                "phone": "1-800-894-9444",
                "email": "CIU_intake@cpuc.ca.gov"
            }
        }
    }

    return {
        "success": True,
        "receipt": receipt
    }


# Initialize the background scheduler (rideshare + Prop 22 compliance jobs only —
# food-delivery timeout jobs were removed along with the rest of the food order flow)
restaurant_timeout_scheduler = BackgroundScheduler()


def _should_run_scheduler() -> bool:
    """
    Guard: Only ONE worker process per container should run the background scheduler.
    Without this guard, each uvicorn worker (--workers 4) starts its own scheduler,
    causing all background jobs to run 4x per interval with separate in-memory dedup sets.
    This leads to duplicate emails, duplicate refunds, and duplicate push notifications.

    Strategy:
    1. Try Redis SET NX PX (distributed lock, auto-expires after 55s if container crashes)
    2. Fall back to fcntl file lock if Redis unavailable (single-host protection)
    """
    global _scheduler_lock_fd

    # Strategy 1: Redis distributed lock (preferred — auto-expires on container crash)
    try:
        from cache import redis_client, REDIS_AVAILABLE
        if REDIS_AVAILABLE and redis_client:
            lock_key = "dollor:scheduler:lock"
            lock_value = str(os.getpid())
            # SET NX PX: set only if not exists, with 55-second expiry
            acquired = redis_client.set(lock_key, lock_value, nx=True, px=55000)
            if acquired:
                logger.info(f"Scheduler Redis lock acquired by PID {os.getpid()}")
                _scheduler_lock_fd = None  # No fd needed for Redis lock
                return True
            else:
                current_holder = redis_client.get(lock_key)
                logger.info(f"Scheduler Redis lock NOT acquired by PID {os.getpid()} — held by PID {current_holder}")
                return False
    except Exception as e:
        logger.warning(f"Redis scheduler lock failed ({e}), falling back to file lock")

    # Strategy 2: File lock fallback (works on single host, not distributed)
    import fcntl
    lock_path = "/tmp/dollor-scheduler.lock"
    try:
        # O_CREAT | O_WRONLY — create if missing
        lock_fd = os.open(lock_path, os.O_CREAT | os.O_WRONLY, 0o644)
        # Non-blocking exclusive lock — only one process wins
        fcntl.flock(lock_fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
        # Write our PID for debugging
        os.write(lock_fd, f"{os.getpid()}\n".encode())
        os.fsync(lock_fd)
        # Keep lock_fd open (lock held for process lifetime — released on exit)
        # Store on module to prevent garbage collection
        _scheduler_lock_fd = lock_fd
        logger.info(f"Scheduler file lock acquired by PID {os.getpid()}")
        return True
    except (OSError, IOError):
        # Another process already holds the lock
        logger.info(f"Scheduler file lock NOT acquired by PID {os.getpid()} — another worker is the scheduler leader")
        return False


def prop22_period_reconciliation_job():
    """
    Prop 22 14-day period reconciliation (BPC §§7453-7454).
    Runs nightly at PT midnight. Only processes on period boundary nights.
    Per-driver db.commit() — single-driver Stripe failure does not roll back others.
    """
    import fcntl
    lock_path = "/tmp/prop22_reconciliation.lock"
    try:
        lock_fd = os.open(lock_path, os.O_CREAT | os.O_WRONLY, 0o644)
        fcntl.flock(lock_fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
    except BlockingIOError:
        logger.info("Prop 22 reconciliation: another process is handling this, skipping")
        return

    try:
        from prop22_utils import (
            get_previous_period_bounds, get_next_period_end,
            get_qtd_engaged_hours, CA_LAT_MIN, CA_LAT_MAX, CA_LON_MIN, CA_LON_MAX
        )
        from zoneinfo import ZoneInfo
        CA_TZ = ZoneInfo("America/Los_Angeles")

        now = datetime.now(CA_TZ)
        prev_start, prev_end = get_previous_period_bounds()

        # Period boundary guard: only process on the 14th-day midnight
        if now.date() != prev_end.date():
            return

        logger.info(f"Prop 22 reconciliation: processing period {prev_start.date()} -> {prev_end.date()}")
        db = SessionLocal()
        try:
            # --- Rideshare drivers with CA-accepted rides ---
            rideshare_driver_ids = (
                db.query(RideRequestModel.driver_id)
                .filter(
                    RideRequestModel.matched_at >= prev_start,
                    RideRequestModel.matched_at < prev_end,
                    RideRequestModel.status == "completed",
                    RideRequestModel.prop22_acceptance_lat.isnot(None),
                    RideRequestModel.prop22_acceptance_lat.between(CA_LAT_MIN, CA_LAT_MAX),
                    RideRequestModel.prop22_acceptance_lon.between(CA_LON_MIN, CA_LON_MAX),
                )
                .distinct()
                .all()
            )

            # --- Food delivery drivers with CA-accepted orders ---
            food_driver_ids = (
                db.query(Order.driver_id)
                .filter(
                    Order.driver_accepted_at >= prev_start,
                    Order.driver_accepted_at < prev_end,
                    Order.prop22_acceptance_lat.isnot(None),
                    Order.prop22_acceptance_lat.between(CA_LAT_MIN, CA_LAT_MAX),
                    Order.prop22_acceptance_lon.between(CA_LON_MIN, CA_LON_MAX),
                )
                .distinct()
                .all()
            )

            # Combine unique driver IDs with service type tracking
            rideshare_ids = {r[0] for r in rideshare_driver_ids}
            food_ids = {r[0] for r in food_driver_ids}
            drivers_to_process = [(did, "RIDESHARE") for did in rideshare_ids]
            for did in food_ids:
                if did not in rideshare_ids:  # rideshare takes precedence for dual-service drivers
                    drivers_to_process.append((did, "FOOD_DELIVERY"))

            for driver_id, service_type in drivers_to_process:
                try:
                    # SELECT-before-INSERT: skip if already processed (job retry safety)
                    existing = db.query(Prop22EarningPeriod).filter_by(
                        driver_id=driver_id,
                        period_start=prev_start
                    ).first()
                    if existing:
                        logger.debug(f"Prop 22: driver {driver_id} period already processed, skipping")
                        continue

                    if service_type == "RIDESHARE":
                        work_items = db.query(RideRequestModel).filter(
                            RideRequestModel.driver_id == driver_id,
                            RideRequestModel.matched_at >= prev_start,
                            RideRequestModel.matched_at < prev_end,
                            RideRequestModel.status == "completed",
                            RideRequestModel.prop22_acceptance_lat.between(CA_LAT_MIN, CA_LAT_MAX),
                            RideRequestModel.prop22_acceptance_lon.between(CA_LON_MIN, CA_LON_MAX),
                        ).all()
                        engaged_hours = sum(r.prop22_engaged_hours or 0 for r in work_items)
                        engaged_miles = sum(r.prop22_engaged_miles or 0 for r in work_items)
                        # Tips excluded: driver_payout (models.py:1379) = fare minus platform_fee;
                        # tip is tracked in tip_amount column separately
                        net_earnings = sum(r.driver_payout or 0 for r in work_items)
                        prop22_floor = sum(r.prop22_floor_amount or 0 for r in work_items)
                    else:  # FOOD_DELIVERY
                        work_items = db.query(Order).filter(
                            Order.driver_id == driver_id,
                            Order.driver_accepted_at >= prev_start,
                            Order.driver_accepted_at < prev_end,
                            Order.prop22_acceptance_lat.between(CA_LAT_MIN, CA_LAT_MAX),
                            Order.prop22_acceptance_lon.between(CA_LON_MIN, CA_LON_MAX),
                        ).all()
                        engaged_hours = sum(o.prop22_engaged_hours or 0 for o in work_items)
                        engaged_miles = sum(o.prop22_engaged_miles or 0 for o in work_items)
                        # Tips excluded: Order.delivery_fee (models.py:438) excludes Order.tip (models.py:439)
                        net_earnings = sum(o.delivery_fee or 0 for o in work_items)
                        prop22_floor = sum(o.prop22_floor_amount or 0 for o in work_items)

                    top_up = max(0.0, prop22_floor - net_earnings)
                    qtd_hours = get_qtd_engaged_hours(db, driver_id, prev_end)
                    driver = db.query(Driver).filter(Driver.id == driver_id).first()
                    if not driver:
                        logger.warning(f"Prop 22: driver {driver_id} not found, skipping")
                        continue

                    period = Prop22EarningPeriod(
                        driver_id=driver_id,
                        period_start=prev_start,
                        period_end=prev_end,
                        service_type=service_type,
                        engaged_hours=engaged_hours,
                        engaged_miles=engaged_miles,
                        net_earnings=net_earnings,
                        prop22_floor=prop22_floor,
                        top_up_amount=top_up,
                        status="PENDING",
                        deadline_at=get_next_period_end(prev_end),
                    )
                    db.add(period)
                    db.flush()  # get period.id for earnings statement FK

                    statement = Prop22EarningsStatement(
                        driver_id=driver_id,
                        period_id=period.id,
                        period_engaged_hours=engaged_hours,
                        qtd_engaged_hours=qtd_hours,
                        period_engaged_miles=engaged_miles,
                        net_earnings=net_earnings,
                        prop22_floor=prop22_floor,
                        top_up_amount=top_up,
                    )
                    db.add(statement)

                    if top_up <= 0:
                        period.status = "RECONCILED"
                        send_push_notification(
                            "driver", driver_id,
                            "Prop 22 — No Top-Up Needed",
                            f"Your earnings of ${net_earnings:.2f} exceeded the ${prop22_floor:.2f} floor.",
                            {"type": "prop22_statement", "period_id": period.id},
                            db
                        )
                    elif driver.stripe_onboarded and driver.stripe_account_id:
                        try:
                            import stripe as stripe_lib
                            transfer = stripe_lib.Transfer.create(
                                amount=int(round(top_up * 100)),
                                currency="usd",
                                destination=driver.stripe_account_id,
                                idempotency_key=f"prop22_topup_{driver_id}_{period.id}",
                            )
                            period.top_up_stripe_id = transfer["id"]
                            period.status = "PAID"
                            send_push_notification(
                                "driver", driver_id,
                                f"Prop 22 Top-Up: ${top_up:.2f}",
                                "Your Prop 22 earnings top-up has been transferred.",
                                {"type": "prop22_topup", "period_id": period.id},
                                db
                            )
                        except Exception as stripe_err:
                            logger.warning(
                                f"Prop 22: Stripe transfer failed for driver {driver_id}: {stripe_err}"
                            )
                            period.status = "MANUAL_REVIEW"
                    else:
                        period.status = "MANUAL_REVIEW"
                        logger.warning(
                            f"Prop 22: driver {driver_id} not Stripe-onboarded — "
                            f"top-up ${top_up:.2f} flagged MANUAL_REVIEW"
                        )

                    db.commit()  # commit per driver — single failure does not roll back others
                    logger.info(f"Prop 22: driver {driver_id} period {period.id} -> {period.status}")

                    # Send Prop 22 earnings statement email (non-blocking)
                    try:
                        from email_service import send_prop22_earnings_statement_email
                        healthcare_eligible = (qtd_hours / max(1, (prev_end - prev_start).days / 7)) >= 15
                        send_prop22_earnings_statement_email(
                            driver_email=driver.email,
                            driver_name=f"{driver.first_name} {driver.last_name}".strip(),
                            period_start=prev_start.strftime("%b %d, %Y"),
                            period_end=prev_end.strftime("%b %d, %Y"),
                            engaged_hours=engaged_hours,
                            engaged_miles=engaged_miles,
                            floor_amount=prop22_floor,
                            net_earnings=net_earnings,
                            top_up_amount=top_up,
                            qtd_hours=qtd_hours,
                            healthcare_eligible=healthcare_eligible,
                        )
                    except Exception as email_err:
                        logger.error(f"Prop 22 earnings statement email failed for driver {driver_id}: {email_err}")

                except Exception as driver_err:
                    db.rollback()
                    logger.error(f"Prop 22 reconciliation: driver {driver_id} failed: {driver_err}")
                    continue

        finally:
            db.close()

    finally:
        try:
            fcntl.flock(lock_fd, fcntl.LOCK_UN)
            os.close(lock_fd)
        except Exception:
            pass


def prop22_manual_review_escalation_job():
    """
    Checks MANUAL_REVIEW periods daily at 9 AM PT.
    Marks OVERDUE when deadline_at has passed.
    Logs 3-day warning for approaching deadlines.
    Uses logger.warning() — no send_admin_alert() function exists (RESEARCH.md pitfall #6).
    """
    from zoneinfo import ZoneInfo
    CA_TZ = ZoneInfo("America/Los_Angeles")
    now = datetime.now(CA_TZ)

    db = SessionLocal()
    try:
        pending = db.query(Prop22EarningPeriod).filter(
            Prop22EarningPeriod.status == "MANUAL_REVIEW"
        ).all()

        for p in pending:
            if not p.deadline_at:
                continue
            days_remaining = (p.deadline_at.astimezone(CA_TZ) - now).days
            if days_remaining < 0:
                p.status = "OVERDUE"
                logger.warning(
                    f"PROP22 OVERDUE: driver_id={p.driver_id} period_id={p.id} "
                    f"top_up=${p.top_up_amount:.2f} — UCL violation risk ($2,500). "
                    f"Process via ACH/check within 48h."
                )
            elif days_remaining <= 3:
                logger.warning(
                    f"PROP22 DEADLINE APPROACHING: driver_id={p.driver_id} period_id={p.id} "
                    f"top_up=${p.top_up_amount:.2f} due in {days_remaining} day(s). "
                    f"Admin portal: /admin/prop22"
                )

        db.commit()
    except Exception as e:
        db.rollback()
        logger.error(f"Prop 22 escalation job failed: {e}")
    finally:
        db.close()


def monthly_earnings_summary_job():
    """
    Sends monthly earnings summary email to all active drivers on the 1st of each month.
    Covers previous month's food delivery + rideshare earnings.
    Uses file-lock guard to prevent duplicate execution across workers.
    """
    import fcntl
    lock_path = "/tmp/monthly_earnings_summary.lock"
    try:
        lock_fd = os.open(lock_path, os.O_CREAT | os.O_WRONLY, 0o644)
        fcntl.flock(lock_fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
    except BlockingIOError:
        logger.info("Monthly earnings summary: another process is handling this, skipping")
        return

    try:
        from email_service import send_monthly_earnings_summary_email, get_driver_ytd_earnings
        from models import RideRequest as RideRequestModel, Order, Driver, Prop22EarningPeriod

        now = datetime.utcnow()
        # Previous month
        if now.month == 1:
            prev_year, prev_month = now.year - 1, 12
        else:
            prev_year, prev_month = now.year, now.month - 1

        import calendar
        _, last_day = calendar.monthrange(prev_year, prev_month)
        month_start = datetime(prev_year, prev_month, 1)
        month_end = datetime(prev_year, prev_month, last_day, 23, 59, 59)

        db = SessionLocal()
        try:
            # Get all active drivers
            drivers = db.query(Driver).filter(Driver.is_active == True).all()

            for driver in drivers:
                try:
                    # Food delivery stats
                    food_orders_q = db.query(Order).filter(
                        Order.driver_id == driver.id,
                        Order.status == "delivered",
                        Order.delivered_at >= month_start,
                        Order.delivered_at <= month_end,
                    ).all()
                    food_orders = len(food_orders_q)
                    food_delivery_fees = sum(float(o.delivery_fee or 0) for o in food_orders_q)
                    food_tips = sum(float(o.tip or 0) for o in food_orders_q)

                    # Rideshare stats
                    rides_q = db.query(RideRequestModel).filter(
                        RideRequestModel.matched_driver_id == driver.id,
                        RideRequestModel.status == "completed",
                        RideRequestModel.completed_at >= month_start,
                        RideRequestModel.completed_at <= month_end,
                    ).all()
                    ride_count = len(rides_q)
                    ride_fares = sum(float(r.driver_payout or 0) for r in rides_q)
                    ride_tips = sum(float(r.tip_amount or 0) for r in rides_q)

                    # Platform fees (rideshare only: $1/$2/$3 tiered)
                    platform_fees_paid = sum(float(r.platform_fee or 0) for r in rides_q)

                    # Prop 22 top-ups for this month
                    prop22_topups = 0.0
                    periods = db.query(Prop22EarningPeriod).filter(
                        Prop22EarningPeriod.driver_id == driver.id,
                        Prop22EarningPeriod.period_end >= month_start,
                        Prop22EarningPeriod.period_end <= month_end,
                        Prop22EarningPeriod.status.in_(["PAID", "RECONCILED"]),
                    ).all()
                    prop22_topups = sum(float(p.top_up_amount or 0) for p in periods)

                    # Net payout
                    net_payout = food_delivery_fees + food_tips + ride_fares + ride_tips - platform_fees_paid + prop22_topups

                    # Skip drivers with zero activity
                    if food_orders == 0 and ride_count == 0:
                        continue

                    # YTD
                    ytd_total = get_driver_ytd_earnings(db, driver.id, now.year)

                    send_monthly_earnings_summary_email(
                        driver_email=driver.email,
                        driver_name=f"{driver.first_name} {driver.last_name}".strip(),
                        year=prev_year,
                        month=prev_month,
                        food_orders=food_orders,
                        food_delivery_fees=food_delivery_fees,
                        food_tips=food_tips,
                        ride_count=ride_count,
                        ride_fares=ride_fares,
                        ride_tips=ride_tips,
                        platform_fees_paid=platform_fees_paid,
                        prop22_topups=prop22_topups,
                        net_payout=net_payout,
                        ytd_total=ytd_total,
                    )
                    logger.info(f"Monthly earnings summary sent to driver {driver.id}")

                except Exception as driver_err:
                    logger.error(f"Monthly earnings summary failed for driver {driver.id}: {driver_err}")
                    continue

        finally:
            db.close()

    finally:
        try:
            fcntl.flock(lock_fd, fcntl.LOCK_UN)
            os.close(lock_fd)
        except Exception:
            pass


def quarterly_compliance_report_job():
    """
    Sends quarterly compliance report to admin on Jan/Apr/Jul/Oct 1st.
    Includes Prop 22 summary, per-driver breakdown, 1099 tracking, revenue summary.
    Uses file-lock guard to prevent duplicate execution across workers.
    """
    import fcntl
    lock_path = "/tmp/quarterly_compliance_report.lock"
    try:
        lock_fd = os.open(lock_path, os.O_CREAT | os.O_WRONLY, 0o644)
        fcntl.flock(lock_fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
    except BlockingIOError:
        logger.info("Quarterly compliance report: another process is handling this, skipping")
        return

    try:
        from email_service import send_quarterly_compliance_report_email, get_driver_ytd_earnings
        from models import RideRequest as RideRequestModel, Order, Driver, Prop22EarningPeriod

        now = datetime.utcnow()
        # Previous quarter
        current_quarter = ((now.month - 1) // 3) + 1
        if current_quarter == 1:
            prev_quarter = 4
            q_year = now.year - 1
        else:
            prev_quarter = current_quarter - 1
            q_year = now.year

        q_start_month = (prev_quarter - 1) * 3 + 1
        q_end_month = q_start_month + 2
        import calendar
        _, q_end_day = calendar.monthrange(q_year, q_end_month)
        q_start = datetime(q_year, q_start_month, 1)
        q_end = datetime(q_year, q_end_month, q_end_day, 23, 59, 59)

        db = SessionLocal()
        try:
            # Get drivers with activity in this quarter
            ride_driver_ids = {r[0] for r in db.query(RideRequestModel.matched_driver_id).filter(
                RideRequestModel.status == "completed",
                RideRequestModel.completed_at >= q_start,
                RideRequestModel.completed_at <= q_end,
                RideRequestModel.matched_driver_id.isnot(None),
            ).distinct().all()}

            food_driver_ids = {r[0] for r in db.query(Order.driver_id).filter(
                Order.status == "delivered",
                Order.delivered_at >= q_start,
                Order.delivered_at <= q_end,
                Order.driver_id.isnot(None),
            ).distinct().all()}

            all_driver_ids = ride_driver_ids | food_driver_ids
            total_drivers = len(all_driver_ids)

            # Prop 22 summary
            periods = db.query(Prop22EarningPeriod).filter(
                Prop22EarningPeriod.period_end >= q_start,
                Prop22EarningPeriod.period_end <= q_end,
            ).all()

            total_hours = sum(float(p.engaged_hours or 0) for p in periods)
            total_floor = sum(float(p.prop22_floor or 0) for p in periods)
            total_topups = sum(float(p.top_up_amount or 0) for p in periods if p.status in ("PAID", "RECONCILED"))
            drivers_with_topups = len({p.driver_id for p in periods if (p.top_up_amount or 0) > 0 and p.status in ("PAID", "RECONCILED")})

            prop22_summary = {
                "total_hours": total_hours,
                "total_floor": total_floor,
                "total_topups": total_topups,
                "drivers_with_topups": drivers_with_topups,
            }

            # Per-driver breakdown
            driver_breakdown = []
            threshold_drivers = []
            approaching_drivers = []

            for did in all_driver_ids:
                driver = db.query(Driver).filter(Driver.id == did).first()
                if not driver:
                    continue

                driver_name = f"{driver.first_name} {driver.last_name}".strip()
                driver_periods = [p for p in periods if p.driver_id == did]
                d_hours = sum(float(p.engaged_hours or 0) for p in driver_periods)
                d_floor = sum(float(p.prop22_floor or 0) for p in driver_periods)
                d_earned = sum(float(p.net_earnings or 0) for p in driver_periods)
                d_topup = sum(float(p.top_up_amount or 0) for p in driver_periods if p.status in ("PAID", "RECONCILED"))
                d_status = driver_periods[-1].status if driver_periods else "N/A"

                driver_breakdown.append({
                    "name": driver_name,
                    "engaged_hours": d_hours,
                    "floor": d_floor,
                    "earned": d_earned,
                    "top_up": d_topup,
                    "status": d_status,
                })

                # 1099 check
                ytd = get_driver_ytd_earnings(db, did, q_year)
                if ytd >= 600:
                    threshold_drivers.append({"name": driver_name, "ytd": ytd})
                elif ytd >= 500:
                    approaching_drivers.append({"name": driver_name, "ytd": ytd})

            # Revenue summary
            from sqlalchemy import func as sqla_func

            customer_ride_fees = db.query(sqla_func.count(RideRequestModel.id)).filter(
                RideRequestModel.status == "completed",
                RideRequestModel.completed_at >= q_start,
                RideRequestModel.completed_at <= q_end,
            ).scalar() or 0
            # Customer pays $1 service fee per ride
            customer_ride_fee_total = float(customer_ride_fees) * 1.0

            customer_order_fees = db.query(sqla_func.count(Order.id)).filter(
                Order.status == "delivered",
                Order.delivered_at >= q_start,
                Order.delivered_at <= q_end,
            ).scalar() or 0
            # Customer pays $1 service fee per food order
            customer_order_fee_total = float(customer_order_fees) * 1.0

            customer_fees = customer_ride_fee_total + customer_order_fee_total

            # Driver platform fees (rideshare only: sum of platform_fee column)
            driver_fees = db.query(sqla_func.sum(RideRequestModel.platform_fee)).filter(
                RideRequestModel.status == "completed",
                RideRequestModel.completed_at >= q_start,
                RideRequestModel.completed_at <= q_end,
            ).scalar() or 0

            # Restaurant platform fees ($1 per order)
            restaurant_fees = float(customer_order_fees) * 1.0

            revenue_summary = {
                "customer_fees": customer_fees,
                "driver_fees": float(driver_fees) + restaurant_fees,
                "net_revenue": customer_fees + float(driver_fees) + restaurant_fees,
            }

            send_quarterly_compliance_report_email(
                admin_email="jeetnair.in@gmail.com",
                year=q_year,
                quarter=prev_quarter,
                total_drivers=total_drivers,
                prop22_summary=prop22_summary,
                driver_breakdown=driver_breakdown,
                threshold_drivers=threshold_drivers,
                approaching_drivers=approaching_drivers,
                revenue_summary=revenue_summary,
            )
            logger.info(f"Quarterly compliance report Q{prev_quarter} {q_year} sent to admin")

        finally:
            db.close()

    finally:
        try:
            fcntl.flock(lock_fd, fcntl.LOCK_UN)
            os.close(lock_fd)
        except Exception:
            pass


def start_timeout_scheduler():
    """Start the background scheduler for timeout checks"""
    if not restaurant_timeout_scheduler.running and _should_run_scheduler():
        # Import ride cleanup jobs here to avoid circular import
        # (bid_routes imports from order_flow at module level)
        from bid_routes import (
            check_ride_bidding_expiry_job,
            check_ride_matched_timeout_job,
            check_ride_in_progress_timeout_job,
            check_individual_bid_expiry_job,
            check_capture_retry_job,
            RIDE_CLEANUP_CHECK_INTERVAL_SECONDS,
            RIDE_BIDDING_EXPIRY_MINUTES,
            RIDE_MATCHED_TIMEOUT_MINUTES,
            RIDE_IN_PROGRESS_TIMEOUT_HOURS,
        )
        restaurant_timeout_scheduler.add_job(
            check_ride_bidding_expiry_job,
            IntervalTrigger(seconds=RIDE_CLEANUP_CHECK_INTERVAL_SECONDS),
            id="ride_bidding_expiry_checker",
            name="Auto-expire OPEN/BIDDING rides past bidding window",
            replace_existing=True
        )
        restaurant_timeout_scheduler.add_job(
            check_ride_matched_timeout_job,
            IntervalTrigger(seconds=RIDE_CLEANUP_CHECK_INTERVAL_SECONDS),
            id="ride_matched_timeout_checker",
            name="Auto-reopen MATCHED rides where driver didn't arrive",
            replace_existing=True
        )
        restaurant_timeout_scheduler.add_job(
            check_ride_in_progress_timeout_job,
            IntervalTrigger(seconds=RIDE_CLEANUP_CHECK_INTERVAL_SECONDS),
            id="ride_in_progress_timeout_checker",
            name="Auto-cancel stale IN_PROGRESS rides (2h+)",
            replace_existing=True
        )
        restaurant_timeout_scheduler.add_job(
            check_individual_bid_expiry_job,
            IntervalTrigger(seconds=RIDE_CLEANUP_CHECK_INTERVAL_SECONDS),
            id="individual_bid_expiry_checker",
            name="Auto-expire individual bids past their expires_at",
            replace_existing=True
        )
        restaurant_timeout_scheduler.add_job(
            check_capture_retry_job,
            IntervalTrigger(seconds=300),  # every 5 minutes
            id="ride_capture_retry",
            name="Retry failed Stripe payment captures",
            replace_existing=True
        )
        # Prop 22 BPC §§7453-7454 reconciliation: nightly at PT midnight (boundary nights only)
        restaurant_timeout_scheduler.add_job(
            prop22_period_reconciliation_job,
            CronTrigger(hour=0, minute=0, timezone="America/Los_Angeles"),
            id="prop22_reconciliation",
            name="Prop 22 14-day period reconciliation (BPC §7454)",
            replace_existing=True
        )
        # Prop 22 escalation: daily at 9 AM PT — OVERDUE transition + 3-day deadline warnings
        restaurant_timeout_scheduler.add_job(
            prop22_manual_review_escalation_job,
            CronTrigger(hour=9, minute=0, timezone="America/Los_Angeles"),
            id="prop22_escalation",
            name="Prop 22 MANUAL_REVIEW escalation and OVERDUE marking",
            replace_existing=True
        )
        # Monthly earnings summary: 1st of month at 9 AM PT
        restaurant_timeout_scheduler.add_job(
            monthly_earnings_summary_job,
            CronTrigger(day=1, hour=9, minute=0, timezone="America/Los_Angeles"),
            id="monthly_earnings_summary",
            name="Monthly driver earnings summary email (1st of month 9 AM PT)",
            replace_existing=True
        )
        # Quarterly compliance report: Jan/Apr/Jul/Oct 1st at 9 AM PT
        restaurant_timeout_scheduler.add_job(
            quarterly_compliance_report_job,
            CronTrigger(month="1,4,7,10", day=1, hour=9, minute=0, timezone="America/Los_Angeles"),
            id="quarterly_compliance_report",
            name="Quarterly compliance report email (Q start 9 AM PT)",
            replace_existing=True
        )
        # Refresh Redis scheduler lock every 50s (lock TTL is 55s — keeps leader alive across job cycles)
        try:
            from cache import redis_client, REDIS_AVAILABLE
            if REDIS_AVAILABLE and redis_client:
                def _refresh_scheduler_lock():
                    try:
                        redis_client.expire("dollor:scheduler:lock", 55)
                    except Exception:
                        pass
                restaurant_timeout_scheduler.add_job(
                    _refresh_scheduler_lock,
                    IntervalTrigger(seconds=50),
                    id="scheduler_lock_refresh",
                    name="Refresh Redis scheduler lock",
                    replace_existing=True
                )
        except Exception:
            pass  # Redis not available — file lock handles single-host protection
        restaurant_timeout_scheduler.start()
        logger.info(
            f"Timeout scheduler started (rideshare + Prop 22 compliance only — "
            f"food-delivery timeout jobs removed). "
            f"Rideshare: bidding expiry ({RIDE_BIDDING_EXPIRY_MINUTES}min), "
            f"matched timeout ({RIDE_MATCHED_TIMEOUT_MINUTES}min), "
            f"in-progress timeout ({RIDE_IN_PROGRESS_TIMEOUT_HOURS}h), "
            f"individual bid expiry every {RIDE_CLEANUP_CHECK_INTERVAL_SECONDS}s."
        )
def stop_timeout_scheduler():
    """Stop the background scheduler"""
    if restaurant_timeout_scheduler.running:
        restaurant_timeout_scheduler.shutdown()
        logger.info("Restaurant timeout scheduler stopped.")


# ==================== PAYOUTS ====================

@router.get("/payouts/pending")
async def get_pending_payouts(
    db: Session = Depends(get_db),
    admin: User = Depends(require_admin),
):
    """
    Get all pending payouts - Restaurant & Driver
    """
    vendor_payouts = db.query(VendorPayout).filter(VendorPayout.status == "pending").all()
    driver_payouts = db.query(DriverPayout).filter(DriverPayout.status == "pending").all()

    return {
        "success": True,
        "restaurant_payouts": [{
            "id": p.id,
            "payout_number": p.payout_number,
            "vendor_id": p.vendor_id,
            "gross_revenue": p.gross_revenue,
            "platform_fee": p.platform_fee,
            "net_payout": p.net_payout,
            "status": p.status,
            "created_at": p.created_at.isoformat()
        } for p in vendor_payouts],
        "driver_payouts": [{
            "id": p.id,
            "payout_number": p.payout_number,
            "driver_id": p.driver_id,
            "delivery_fee": p.delivery_fee,
            "tip": p.tip,
            "net_payout": p.net_payout,
            "status": p.status,
            "created_at": p.created_at.isoformat()
        } for p in driver_payouts],
        "totals": {
            "restaurant_total": sum(p.net_payout for p in vendor_payouts),
            "driver_total": sum(p.net_payout for p in driver_payouts)
        }
    }


@router.post("/payouts/{payout_id}/process")
async def process_payout(
    payout_id: int,
    payout_type: str,  # "vendor" or "driver"
    db: Session = Depends(get_db),
    admin: User = Depends(require_admin),
):
    """
    Process a payout - Mark as completed
    AI Employee: LedgerBot Delta
    """
    ai_employee = AI_EMPLOYEES["ACCOUNTANT"]

    if payout_type == "vendor":
        payout = db.query(VendorPayout).filter(VendorPayout.id == payout_id).first()
    else:
        payout = db.query(DriverPayout).filter(DriverPayout.id == payout_id).first()

    if not payout:
        raise HTTPException(status_code=404, detail="Payout not found")

    payout.status = "completed"
    payout.paid_at = datetime.now()
    payout.payment_method = "bank_transfer"

    db.commit()

    return {
        "success": True,
        "payout_id": payout.id,
        "payout_number": payout.payout_number,
        "amount": payout.net_payout,
        "status": "completed",
        "processed_by": ai_employee["name"]
    }


# ==================== JOURNAL ENTRIES ====================

@router.get("/journal-entries")
async def get_journal_entries(
    limit: int = 50,
    db: Session = Depends(get_db),
    admin: User = Depends(require_admin),
):
    """
    Get journal entries for accounting dashboard
    """
    entries = db.query(JournalEntry).order_by(JournalEntry.created_at.desc()).limit(limit).all()

    result = []
    for entry in entries:
        lines = db.query(JournalEntryLine).filter(
            JournalEntryLine.journal_entry_id == entry.id
        ).all()

        result.append({
            "id": entry.id,
            "entry_number": entry.entry_number,
            "order_id": entry.order_id,
            "entry_type": entry.entry_type,
            "description": entry.description,
            "status": entry.status,
            "created_by": entry.created_by_ai_name,
            "created_at": entry.created_at.isoformat(),
            "lines": [{
                "account": line.account_name,
                "debit": line.debit,
                "credit": line.credit,
                "description": line.description
            } for line in lines],
            "total_debit": sum(line.debit for line in lines),
            "total_credit": sum(line.credit for line in lines)
        })

    return {"success": True, "entries": result}


# ==================== DRIVERS ====================

@router.get("/drivers")
async def get_drivers(
    db: Session = Depends(get_db),
    admin: User = Depends(require_admin),
):
    """
    Get all drivers
    """
    drivers = db.query(Driver).all()

    return {
        "success": True,
        "drivers": [{
            "id": d.id,
            "driver_id": d.driver_id,
            "name": f"{d.first_name} {d.last_name}",
            "email": d.email,
            "phone": d.phone,
            "status": d.status.value,
            "rating": d.rating,
            "total_deliveries": d.total_deliveries,
            "is_online": d.is_online
        } for d in drivers]
    }


@router.post("/drivers/create")
async def create_driver(
    driver_data: Dict[str, Any],
    db: Session = Depends(get_db),
    admin: User = Depends(require_admin),
):
    """
    Create a new driver
    """
    driver_count = db.query(Driver).count()
    driver_id = f"DRV-{driver_count + 1:05d}"

    driver = Driver(
        driver_id=driver_id,
        first_name=driver_data.get("first_name"),
        last_name=driver_data.get("last_name"),
        email=driver_data.get("email"),
        phone=driver_data.get("phone"),
        status=DriverStatus.ACTIVE
    )

    db.add(driver)
    db.commit()
    db.refresh(driver)

    return {
        "success": True,
        "driver_id": driver.id,
        "driver_code": driver_id
    }


# ==================== DRIVER AUTHENTICATION ====================

class DriverLoginRequest(BaseModel):
    email: str
    password: str


class DriverRegisterRequest(BaseModel):
    email: str
    password: str
    first_name: str
    last_name: str
    phone: Optional[str] = None


@router.post("/drivers/login")
async def driver_login(
    request: DriverLoginRequest,
    db: Session = Depends(get_db)
):
    """
    Driver login - Returns JWT token for iOS Driver App
    """
    from passlib.context import CryptContext
    from jose import jwt
    from datetime import datetime, timedelta
    import os

    pwd_context = CryptContext(schemes=["bcrypt"], bcrypt__rounds=13, deprecated="auto")
    SECRET_KEY = os.getenv("JWT_SECRET_KEY", "")  # SECURITY: No hardcoded fallback
    ALGORITHM = "HS256"

    driver = db.query(Driver).filter(Driver.email == request.email).first()
    if not driver:
        raise HTTPException(status_code=401, detail="Invalid email or password")

    # Check password (for Google OAuth users, password is 'google_oauth_<userid>')
    if not pwd_context.verify(request.password, driver.password_hash):
        # Allow Google OAuth passwords
        if not request.password.startswith("google_oauth_"):
            raise HTTPException(status_code=401, detail="Invalid email or password")

    # Create JWT token
    token_data = {
        "sub": str(driver.id),
        "email": driver.email,
        "driver_id": driver.id,
        "driver_code": driver.driver_id,
        "exp": datetime.utcnow() + timedelta(days=30)
    }
    access_token = jwt.encode(token_data, SECRET_KEY, algorithm=ALGORITHM)

    # Combine first/last name for iOS compatibility (expects 'name' field)
    full_name = f"{driver.first_name or ''} {driver.last_name or ''}".strip() or driver.email.split('@')[0]

    return {
        "access_token": access_token,
        "token_type": "bearer",
        "driver_id": driver.id,
        "driver_code": driver.driver_id,
        "name": full_name,  # iOS requires combined name field
        "first_name": driver.first_name,
        "last_name": driver.last_name,
        "email": driver.email,
        "phone": driver.phone,
        "vehicle_type": driver.vehicle_type if hasattr(driver, 'vehicle_type') else None,
        "status": driver.status.value,
        "is_approved": driver.status.value == "approved"  # iOS compatibility
    }


@router.post("/drivers/register")
async def driver_register(
    request: DriverRegisterRequest,
    db: Session = Depends(get_db)
):
    """
    Driver registration - Creates new driver account for iOS Driver App
    """
    from passlib.context import CryptContext
    from jose import jwt
    from datetime import datetime, timedelta
    import os

    pwd_context = CryptContext(schemes=["bcrypt"], bcrypt__rounds=13, deprecated="auto")
    SECRET_KEY = os.getenv("JWT_SECRET_KEY", "")  # SECURITY: No hardcoded fallback
    ALGORITHM = "HS256"

    # Check if driver already exists
    existing = db.query(Driver).filter(Driver.email == request.email).first()
    if existing:
        raise HTTPException(status_code=400, detail="Email already registered")

    # Create driver
    driver_count = db.query(Driver).count()
    driver_id = f"DRV-{driver_count + 1:05d}"

    driver = Driver(
        driver_id=driver_id,
        first_name=request.first_name,
        last_name=request.last_name,
        email=request.email,
        phone=request.phone,
        password_hash=pwd_context.hash(request.password),
        status=DriverStatus.ACTIVE
    )

    db.add(driver)
    db.commit()
    db.refresh(driver)

    # Create JWT token
    token_data = {
        "sub": str(driver.id),
        "email": driver.email,
        "driver_id": driver.id,
        "driver_code": driver.driver_id,
        "exp": datetime.utcnow() + timedelta(days=30)
    }
    access_token = jwt.encode(token_data, SECRET_KEY, algorithm=ALGORITHM)

    return {
        "access_token": access_token,
        "token_type": "bearer",
        "driver_id": driver.id,
        "driver_code": driver.driver_id,
        "first_name": driver.first_name,
        "last_name": driver.last_name,
        "email": driver.email,
        "phone": driver.phone,
        "status": driver.status.value
    }

class DriverLocationUpdate(BaseModel):
    latitude: float
    longitude: float
    updated_at: Optional[str] = None


@router.put("/drivers/{driver_id}/location")
async def update_driver_current_location(
    driver_id: int,
    location: DriverLocationUpdate,
    db: Session = Depends(get_db),
    driver: Driver = Depends(require_driver),
):
    """
    Update driver's current location (called periodically by driver app)
    """
    # IDOR: verify driver_id path param matches authenticated driver
    if int(driver_id) != driver.id:
        raise HTTPException(status_code=403, detail="Not authorized for this resource")

    driver.current_latitude = location.latitude
    driver.current_longitude = location.longitude
    driver.location_updated_at = datetime.now()
    ensure_open_session(db, driver)

    db.commit()

    return {
        "success": True,
        "driver_id": driver.id,
        "location_updated": True,
    }


@router.put("/drivers/{driver_id}/status")
async def update_driver_status(
    driver_id: int,
    is_online: bool,
    db: Session = Depends(get_db),
    driver: Driver = Depends(require_driver),
):
    """
    Toggle driver online/offline status
    """
    # IDOR: verify driver_id path param matches authenticated driver
    if int(driver_id) != driver.id:
        raise HTTPException(status_code=403, detail="Not authorized for this resource")

    if is_online:
        ensure_can_go_online(driver)
    else:
        ensure_can_go_offline(db, driver)

    driver.is_online = is_online
    record_online_state(db, driver, is_online)
    if is_online:
        driver.went_online_at = datetime.now()
    else:
        driver.went_offline_at = datetime.now()

    db.commit()

    return {
        "success": True,
        "driver_id": driver.id,
        "is_online": driver.is_online
    }
