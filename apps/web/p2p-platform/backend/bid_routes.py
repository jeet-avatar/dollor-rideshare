"""
Ride Bidding API Routes - Matchmaking Platform
Enables price negotiation between riders and drivers
"""

from fastapi import APIRouter, Depends, HTTPException, Header, Request
from sqlalchemy.orm import Session, joinedload
from sqlalchemy import and_, or_, select
from sqlalchemy.exc import IntegrityError
from datetime import datetime, timedelta
from typing import Optional, List
from pydantic import BaseModel, Field, field_validator
import math
import re
import uuid

from database import get_db, SessionLocal
from models import (
    RideRequest, RideBid, RideRequestStatus, BidStatus,
    Customer, Driver, DriverStatus,
    RideDispute, DisputeStatus, DisputeReason,
    RecurringRide,
    SupportTicket, TicketType, TicketPriority, TicketStatus
)
from websocket_server import (
    broadcast_new_ride_request, broadcast_new_bid, broadcast_bid_response,
    broadcast_ride_matched, broadcast_ride_request_cancelled,
    broadcast_bid_update, broadcast_bid_withdrawn, broadcast_counter_offer_response,
    broadcast_ride_status
)
from pricing_config import pricing_engine, get_fare_estimate, get_bid_label, platform_fee_for
from email_service import (
    send_ride_request_confirmation_email,
    send_ride_bid_received_email,
    send_ride_matched_email,
    send_ride_started_email,
    send_ride_completed_email,
    send_ride_cancelled_email
)
from order_flow import send_push_notification
from auth_utils import require_customer, require_driver, require_any_auth
from cache import check_rate_limit, RateLimiter
import asyncio
import logging

logger = logging.getLogger(__name__)


def _bg_email(name: str, *args, **kwargs):
    """Send a ride email without making the API caller wait on SMTP.

    Runs the (blocking) sender in a worker thread so request handlers return immediately and the event loop is
    not blocked. The sender is looked up by name at call time so tests can still patch `bid_routes.<name>`.
    Without a running event loop (scripts, sync callers) it runs inline as before.
    """
    fn = globals()[name]

    def _run():
        try:
            fn(*args, **kwargs)
        except Exception as exc:  # emails must never break a ride
            logger.error(f"Background email {name} failed: {exc}")

    try:
        asyncio.get_running_loop().run_in_executor(None, _run)
    except RuntimeError:
        _run()

# Public endpoint rate limiter — prevents scrapers from hammering the fare estimate endpoint
_public_estimate_rate_limiter = RateLimiter(max_requests=20, window_seconds=60)  # 20/min per IP


def _notify_customer(db: Session, customer_id: int, title: str, message: str,
                     notification_type: str = "ride", reference_id: int = None,
                     reference_type: str = None):
    """Create an in-app notification for a customer. Fails silently."""
    try:
        from models import InAppNotification
        notification = InAppNotification(
            customer_id=customer_id,
            title=title,
            message=message,
            type=notification_type,
            reference_id=reference_id,
            reference_type=reference_type
        )
        db.add(notification)
    except Exception as e:
        logger.warning(f"Failed to create in-app notification: {e}")


import ride_dispatch
from ride_dispatch import SHARED_DEMO_DRIVER_EMAILS, is_driver_notified

router = APIRouter(prefix="/api/rides", tags=["Ride Bidding"])


# =========================================================================
# PYDANTIC MODELS
# =========================================================================

class CreateRideRequestInput(BaseModel):
    customer_id: int
    pickup_address: str
    pickup_latitude: float
    pickup_longitude: float
    pickup_place_name: Optional[str] = None
    dropoff_address: str
    dropoff_latitude: float
    dropoff_longitude: float
    dropoff_place_name: Optional[str] = None
    ride_type: str = "standard"
    customer_max_price: Optional[float] = None
    customer_preferred_price: Optional[float] = None
    special_requests: Optional[str] = None
    accessibility_requested: bool = False  # TNC-12: Passenger needs wheelchair-accessible or disability-accessible vehicle
    accessibility_notes: Optional[str] = None  # TNC-12: Specific accessibility needs
    bidding_duration_minutes: int = pricing_engine.config.BIDDING_WINDOW_MINUTES  # How long to accept bids

    # A1/A6/A7: Input validation for API security
    @field_validator('pickup_latitude', 'dropoff_latitude')
    @classmethod
    def validate_latitude(cls, v):
        if v < -90 or v > 90:
            raise ValueError('Latitude must be between -90 and 90')
        return v

    @field_validator('pickup_longitude', 'dropoff_longitude')
    @classmethod
    def validate_longitude(cls, v):
        if v < -180 or v > 180:
            raise ValueError('Longitude must be between -180 and 180')
        return v

    @field_validator('bidding_duration_minutes')
    @classmethod
    def validate_bidding_duration(cls, v):
        if v < 1 or v > 120:
            raise ValueError('Bidding duration must be between 1 and 120 minutes')
        return v

    @field_validator('customer_max_price', 'customer_preferred_price')
    @classmethod
    def validate_price_positive(cls, v):
        if v is not None and v < 0:
            raise ValueError('Price cannot be negative')
        if v is not None and v > 10000:
            raise ValueError('Price cannot exceed $10,000')
        return v

    @field_validator('special_requests')
    @classmethod
    def sanitize_special_requests(cls, v):
        if v:
            import re
            v = re.sub(r'<[^>]+>', '', v).strip()  # Strip HTML tags
            if len(v) > 500:
                v = v[:500]
        return v


class SubmitBidInput(BaseModel):
    driver_id: int
    proposed_price: float
    message: Optional[str] = None
    estimated_arrival_minutes: Optional[int] = None

    # A1: Prevent negative prices
    @field_validator('proposed_price')
    @classmethod
    def validate_proposed_price(cls, v):
        if v <= 0:
            raise ValueError('Proposed price must be greater than zero')
        if v > 10000:
            raise ValueError('Proposed price cannot exceed $10,000')
        return v

    @field_validator('estimated_arrival_minutes')
    @classmethod
    def validate_eta(cls, v):
        if v is not None and (v < 1 or v > 180):
            raise ValueError('ETA must be between 1 and 180 minutes')
        return v


class RespondToBidInput(BaseModel):
    action: str  # "accept", "reject", "counter"
    counter_price: Optional[float] = None
    message: Optional[str] = None

    # A1: Prevent negative counter price
    @field_validator('counter_price')
    @classmethod
    def validate_counter_price(cls, v):
        if v is not None and v <= 0:
            raise ValueError('Counter price must be greater than zero')
        if v is not None and v > 10000:
            raise ValueError('Counter price cannot exceed $10,000')
        return v


class UpdateBidInput(BaseModel):
    proposed_price: float
    message: Optional[str] = None

    @field_validator('proposed_price')
    @classmethod
    def validate_proposed_price(cls, v):
        if v <= 0:
            raise ValueError('Proposed price must be greater than zero')
        if v > 10000:
            raise ValueError('Proposed price cannot exceed $10,000')
        return v


# =========================================================================
# HELPER FUNCTIONS
# =========================================================================

def generate_request_id():
    """Generate temporary ride request ID (will be updated after DB insert)"""
    return f"RIDE{datetime.utcnow().strftime('%Y')}000000"


def generate_clean_request_id(db_id: int):
    """Generate clean ride request ID using database ID: RIDE{year}{6-digit-id}"""
    return f"RIDE{datetime.utcnow().strftime('%Y')}{db_id:06d}"


def generate_bid_id():
    """Generate temporary bid ID (will be updated after DB insert)"""
    return f"BID{datetime.utcnow().strftime('%Y')}000000"


def generate_clean_bid_id(db_id: int):
    """Generate clean bid ID using database ID: BID{year}{6-digit-id}"""
    return f"BID{datetime.utcnow().strftime('%Y')}{db_id:06d}"


def calculate_distance_km(lat1: float, lon1: float, lat2: float, lon2: float) -> float:
    """Calculate distance between two points using Haversine formula"""
    R = 6371  # Earth's radius in km

    lat1_rad = math.radians(lat1)
    lat2_rad = math.radians(lat2)
    delta_lat = math.radians(lat2 - lat1)
    delta_lon = math.radians(lon2 - lon1)

    a = math.sin(delta_lat/2)**2 + math.cos(lat1_rad) * math.cos(lat2_rad) * math.sin(delta_lon/2)**2
    c = 2 * math.atan2(math.sqrt(a), math.sqrt(1-a))

    return R * c


def calculate_demand_multiplier(db: Session) -> tuple:
    """
    Calculate demand-based surge multiplier.
    Based on ratio of open ride requests to online drivers.
    Returns (multiplier, label) - capped at 1.5x per PricingConfig.
    """
    from models import RideRequestStatus

    # Count open/bidding ride requests
    open_requests = db.query(RideRequest).filter(
        RideRequest.status.in_([RideRequestStatus.OPEN, RideRequestStatus.BIDDING])
    ).count()

    # Count online drivers
    online_drivers = db.query(Driver).filter(Driver.is_online == True).count()

    if online_drivers == 0:
        if open_requests > 0:
            return (1.5, "High demand")
        return (1.0, "Standard")

    ratio = open_requests / online_drivers

    if ratio >= 3.0:
        return (1.5, "Very high demand")
    elif ratio >= 2.0:
        return (1.3, "High demand")
    elif ratio >= 1.5:
        return (1.15, "Busy")
    elif ratio <= 0.3:
        return (0.9, "Low demand")
    else:
        return (1.0, "Standard")


def calculate_suggested_price(distance_km: float, duration_minutes: int, ride_type: str, demand_multiplier: float = 1.0) -> float:
    """
    Calculate suggested price using competitive market-rate pricing.
    Uses the DollorPricingEngine for consistent pricing across all platforms.
    """
    # Use the centralized pricing engine
    estimate = pricing_engine.calculate_estimate(
        distance_km=distance_km,
        duration_minutes=duration_minutes
    )

    base_price = estimate.subtotal

    # Apply ride type multipliers
    if ride_type == "premium":
        base_price *= 1.5
    elif ride_type == "xl":
        base_price *= 1.25

    # Apply demand/surge multiplier
    base_price *= demand_multiplier

    return round(base_price, 2)


def estimate_duration_minutes(distance_km: float) -> int:
    """Estimate trip duration based on distance (assuming 30 km/h average)"""
    return max(5, int(distance_km * 2))  # ~30 km/h = 2 min per km


async def _send_push_batch(drivers_to_notify, ride_req, dist_miles, price):
    """Send push notifications concurrently to nearby drivers."""
    async def _send_one(drv):
        try:
            await asyncio.to_thread(
                send_push_notification,
                user_type="driver",
                user_id=drv.id,
                title="New Ride Request!",
                body=f"Pickup: {ride_req.pickup_address[:50]} — ~{dist_miles} mi, est. ${price:.0f}",
                data={
                    "type": "new_ride_request",
                    "ride_request_id": str(ride_req.id),
                    "request_id": ride_req.request_id,
                    "pickup_address": ride_req.pickup_address,
                    "dropoff_address": ride_req.dropoff_address,
                    "fare_estimate": str(round(price, 2))
                },
                db=None  # Don't pass db across threads -- let fallback create its own session
            )
            return True
        except Exception as err:
            logger.warning(f"Failed to push to driver {drv.id}: {err}")
            return False

    results = await asyncio.gather(*[_send_one(d) for d in drivers_to_notify], return_exceptions=True)
    sent = sum(1 for r in results if r is True)
    logger.info(f"Push sent to {sent}/{len(drivers_to_notify)} nearby drivers for ride {ride_req.request_id}")


def serialize_ride_request(request: RideRequest, include_bids: bool = False) -> dict:
    """Serialize ride request to dict"""
    data = {
        "id": request.id,
        "request_id": request.request_id,
        "customer_id": request.customer_id,
        "customer_name": request.customer_name,
        "pickup": {
            "address": request.pickup_address,
            "latitude": request.pickup_latitude,
            "longitude": request.pickup_longitude,
            "place_name": request.pickup_place_name
        },
        "dropoff": {
            "address": request.dropoff_address,
            "latitude": request.dropoff_latitude,
            "longitude": request.dropoff_longitude,
            "place_name": request.dropoff_place_name
        },
        "estimated_distance_km": request.estimated_distance_km,
        "estimated_duration_minutes": request.estimated_duration_minutes,
        "ride_type": request.ride_type,
        "suggested_price": request.suggested_price,
        "customer_max_price": request.customer_max_price,
        "customer_preferred_price": request.customer_preferred_price,
        "final_price": request.final_price,
        "status": request.status.value,
        "bidding_expires_at": request.bidding_expires_at.isoformat() if request.bidding_expires_at else None,
        "special_requests": request.special_requests,
        "accessibility_requested": getattr(request, 'accessibility_requested', False),
        "accessibility_notes": getattr(request, 'accessibility_notes', None),
        "created_at": request.created_at.isoformat() if request.created_at else None,
        "matched_at": request.matched_at.isoformat() if request.matched_at else None,
        "completed_at": request.completed_at.isoformat() if getattr(request, 'completed_at', None) else None,
        "bid_count": len(request.bids) if request.bids else 0,
        "tip_amount": float(request.tip_amount) if getattr(request, 'tip_amount', None) else 0.0,
        "customer_rating": request.customer_rating if getattr(request, 'customer_rating', None) else None,
        "customer_comment": request.customer_comment if getattr(request, 'customer_comment', None) else None,
        "platform_fee": float(request.platform_fee) if getattr(request, 'platform_fee', None) else None,
        "driver_payout": float(request.driver_payout) if getattr(request, 'driver_payout', None) else None,
        "driver_arrived_at": request.driver_arrived_at.isoformat() if getattr(request, 'driver_arrived_at', None) else None,
        # Prop 22 compliance fields
        "prop22_acceptance_lat": float(request.prop22_acceptance_lat) if getattr(request, 'prop22_acceptance_lat', None) else None,
        "prop22_acceptance_lon": float(request.prop22_acceptance_lon) if getattr(request, 'prop22_acceptance_lon', None) else None,
        "prop22_engaged_hours": float(request.prop22_engaged_hours) if getattr(request, 'prop22_engaged_hours', None) else None,
        "prop22_engaged_miles": float(request.prop22_engaged_miles) if getattr(request, 'prop22_engaged_miles', None) else None,
        "prop22_floor_amount": float(request.prop22_floor_amount) if getattr(request, 'prop22_floor_amount', None) else None,
    }

    if include_bids and request.bids:
        data["bids"] = [serialize_bid(bid) for bid in request.bids if bid.status == BidStatus.PENDING]

    if request.matched_driver_id:
        data["matched_driver"] = {
            "id": request.matched_driver_id,
            "name": request.matched_driver.first_name + " " + request.matched_driver.last_name if request.matched_driver else None
        }

    return data


def serialize_bid(bid: RideBid) -> dict:
    """Serialize bid to dict with individual vehicle fields from driver relationship"""
    driver = getattr(bid, 'driver', None)
    data = {
        "id": bid.id,
        "bid_id": bid.bid_id,
        "ride_request_id": bid.ride_request_id,
        "driver_id": bid.driver_id,
        "driver_name": bid.driver_name,
        "driver_rating": bid.driver_rating,
        "driver_photo_url": bid.driver_photo_url,
        "driver_vehicle": bid.driver_vehicle,
        # Individual vehicle fields from Driver relationship
        "driver_vehicle_make": driver.vehicle_make if driver else None,
        "driver_vehicle_model": driver.vehicle_model if driver else None,
        "driver_vehicle_year": driver.vehicle_year if driver else None,
        "driver_vehicle_color": driver.vehicle_color if driver else None,
        "driver_license_plate": driver.license_plate if driver else None,
        "driver_accessibility_capable": driver.accessibility_capable if driver else False,
        "driver_trips": driver.total_deliveries if driver else None,
        "proposed_price": bid.proposed_price,
        "message": bid.message,
        "estimated_arrival_minutes": bid.estimated_arrival_minutes,
        "is_counter_offer": bid.is_counter_offer,
        "original_price": bid.original_price,
        "status": bid.status.value,
        "customer_response": bid.customer_response,
        "customer_counter_price": bid.customer_counter_price,
        "expires_at": bid.expires_at.isoformat() if bid.expires_at else None,
        "created_at": bid.created_at.isoformat() if bid.created_at else None
    }
    return data


# =========================================================================
# CUSTOMER ENDPOINTS
# =========================================================================

@router.post("/request")
async def create_ride_request(data: CreateRideRequestInput, request: Request, customer: Customer = Depends(require_customer), db: Session = Depends(get_db)):
    """
    Customer creates a new ride request open for driver bidding.
    SECURITY: Requires customer JWT. Prevents customer_id spoofing.
    """
    # Prevent customer_id spoofing -- always use authenticated customer's ID
    data.customer_id = customer.id

    # SECURITY (NSA-005): Cap bidding duration to prevent abuse
    if data.bidding_duration_minutes < 1 or data.bidding_duration_minutes > 30:
        raise HTTPException(status_code=400, detail="Bidding duration must be between 1 and 30 minutes")

    # SECURITY (NSA-006): Limit concurrent open ride requests per customer
    open_requests = db.query(RideRequest).filter(
        and_(
            RideRequest.customer_id == customer.id,
            RideRequest.status.in_([RideRequestStatus.OPEN, RideRequestStatus.BIDDING])
        )
    ).count()
    if open_requests >= 3:
        raise HTTPException(
            status_code=429,
            detail="You already have 3 open ride requests. Please wait or cancel existing ones."
        )

    # Reject rides where pickup and dropoff are the same location
    if (data.pickup_latitude == data.dropoff_latitude and
            data.pickup_longitude == data.dropoff_longitude):
        raise HTTPException(
            status_code=400,
            detail="Pickup and dropoff locations must be different"
        )

    # Geofence: reject rides outside US service area (generous bounding box)
    # Continental US: lat 24.5-49.5, lon -125 to -66.5 (includes Hawaii: lat 18.9-22.3, lon -160.3 to -154.8)
    def _in_service_area(lat, lon):
        continental = 24.5 <= lat <= 49.5 and -125.0 <= lon <= -66.5
        hawaii = 18.9 <= lat <= 22.3 and -160.3 <= lon <= -154.8
        alaska = 51.0 <= lat <= 71.5 and -180.0 <= lon <= -129.0
        return continental or hawaii or alaska

    if not _in_service_area(data.pickup_latitude, data.pickup_longitude):
        raise HTTPException(
            status_code=400,
            detail="Pickup location is outside our service area (US only)"
        )
    if not _in_service_area(data.dropoff_latitude, data.dropoff_longitude):
        raise HTTPException(
            status_code=400,
            detail="Dropoff location is outside our service area (US only)"
        )

    # Block customers with unpaid balance from new bookings
    if customer.has_unpaid_balance:
        raise HTTPException(
            status_code=402,
            detail="You have an unpaid balance from a previous ride. Please contact support to resolve it before booking again."
        )

    # Calculate distance and duration
    distance_km = calculate_distance_km(
        data.pickup_latitude, data.pickup_longitude,
        data.dropoff_latitude, data.dropoff_longitude
    )
    duration_minutes = estimate_duration_minutes(distance_km)

    # Calculate demand/surge multiplier
    demand_multiplier, demand_label = calculate_demand_multiplier(db)

    # Calculate suggested price with surge
    suggested_price = calculate_suggested_price(distance_km, duration_minutes, data.ride_type, demand_multiplier)

    # SECURITY: Sanitize user-supplied text to prevent stored XSS
    import re
    _strip_html = lambda t: re.sub(r'<[^>]+>', '', t).strip() if t and isinstance(t, str) else t

    # Create ride request
    ride_request = RideRequest(
        request_id=generate_request_id(),
        customer_id=data.customer_id,
        customer_name=f"{customer.first_name} {customer.last_name}".strip() or customer.email,
        customer_phone=customer.phone,
        pickup_address=_strip_html(data.pickup_address),
        pickup_latitude=data.pickup_latitude,
        pickup_longitude=data.pickup_longitude,
        pickup_place_name=data.pickup_place_name,
        dropoff_address=_strip_html(data.dropoff_address),
        dropoff_latitude=data.dropoff_latitude,
        dropoff_longitude=data.dropoff_longitude,
        dropoff_place_name=_strip_html(data.dropoff_place_name),
        estimated_distance_km=round(distance_km, 2),
        estimated_duration_minutes=duration_minutes,
        ride_type=data.ride_type,
        suggested_price=round(suggested_price, 2),
        customer_max_price=data.customer_max_price,
        customer_preferred_price=data.customer_preferred_price,
        special_requests=_strip_html(data.special_requests),
        accessibility_requested=data.accessibility_requested,
        accessibility_notes=_strip_html(data.accessibility_notes) if data.accessibility_notes else None,
        access_for_all_fee=0.10,
        status=RideRequestStatus.OPEN,
        bidding_expires_at=datetime.utcnow() + timedelta(minutes=data.bidding_duration_minutes)
    )

    db.add(ride_request)
    db.flush()  # Gets auto-incremented id without committing
    ride_request.request_id = generate_clean_request_id(ride_request.id)
    db.commit()
    db.refresh(ride_request)

    # Broadcast to nearby drivers via WebSocket
    try:
        asyncio.create_task(broadcast_new_ride_request(
            ride_request_data=serialize_ride_request(ride_request),
            driver_ids=None  # Broadcast to all drivers
        ))
    except Exception as e:
        logger.error(f"WebSocket broadcast error: {e}")

    distance_miles = round(distance_km * 0.621371, 1)

    # Send push notification to nearby online drivers with FCM tokens (geo-filtered)
    try:
        NOTIFY_RADIUS_KM = 25  # ~15 miles + buffer
        pickup_lat = data.pickup_latitude
        pickup_lon = data.pickup_longitude
        lat_delta = NOTIFY_RADIUS_KM / 111.0
        lon_delta = NOTIFY_RADIUS_KM / (111.0 * max(math.cos(math.radians(pickup_lat)), 0.01))

        online_drivers = db.query(Driver).filter(
            Driver.is_online == True,
            Driver.fcm_token.isnot(None),
            Driver.current_latitude.isnot(None),
            Driver.current_longitude.isnot(None),
            Driver.current_latitude.between(pickup_lat - lat_delta, pickup_lat + lat_delta),
            Driver.current_longitude.between(pickup_lon - lon_delta, pickup_lon + lon_delta)
        ).all()

        # Haversine post-filter for precision (bounding box is a rough rectangle)
        online_drivers = [
            d for d in online_drivers
            if calculate_distance_km(pickup_lat, pickup_lon, d.current_latitude, d.current_longitude) <= NOTIFY_RADIUS_KM
        ]

        ride_request.drivers_notified = len(online_drivers)

        # Send push notifications concurrently via background task
        asyncio.create_task(_send_push_batch(online_drivers, ride_request, distance_miles, suggested_price))
    except Exception as e:
        logger.error(f"Failed to send ride request push to drivers: {e}")

    # Send confirmation email to customer
    try:
        _bg_email("send_ride_request_confirmation_email",
            to_email=customer.email,
            customer_name=f"{customer.first_name} {customer.last_name}".strip() or "Customer",
            request_id=ride_request.request_id,
            pickup_address=data.pickup_address,
            dropoff_address=data.dropoff_address,
            estimated_price=suggested_price,
            estimated_distance_miles=distance_miles,
            estimated_duration_minutes=duration_minutes
        )
        logger.info(f"Ride request confirmation email sent to {customer.email}")
    except Exception as e:
        logger.error(f"Failed to send ride request confirmation email: {e}")

    response = {
        "success": True,
        "message": "Ride request created - waiting for driver bids",
        "ride_request": serialize_ride_request(ride_request)
    }

    # Include surge info
    if demand_multiplier > 1.0:
        response["surge"] = {
            "multiplier": demand_multiplier,
            "label": demand_label,
            "message": f"Prices are {int((demand_multiplier - 1) * 100)}% higher due to {demand_label.lower()}"
        }

    return response


@router.get("/surge")
async def get_surge_status(_auth: dict = Depends(require_any_auth), db: Session = Depends(get_db)):
    """Get current surge/demand pricing status. Requires auth."""
    multiplier, label = calculate_demand_multiplier(db)

    open_requests = db.query(RideRequest).filter(
        RideRequest.status.in_([RideRequestStatus.OPEN, RideRequestStatus.BIDDING])
    ).count()
    online_drivers = db.query(Driver).filter(Driver.is_online == True).count()

    return {
        "success": True,
        "surge_multiplier": multiplier,
        "label": label,
        "is_surging": multiplier > 1.0,
        "open_requests": open_requests,
        "online_drivers": online_drivers,
        "message": f"Prices are {int((multiplier - 1) * 100)}% higher due to {label.lower()}" if multiplier > 1.0 else "Standard pricing"
    }


@router.get("/request/{request_id}")
async def get_ride_request(request_id: int, request: Request, _auth: dict = Depends(require_any_auth), db: Session = Depends(get_db)):
    """Get ride request details with all bids. Requires auth."""
    ride_request = db.query(RideRequest).filter(RideRequest.id == request_id).first()
    if not ride_request:
        raise HTTPException(status_code=404, detail="Ride request not found")

    # Verify caller is a participant (customer, matched driver, or admin)
    jwt_customer_id = _auth.get("customer_id")
    jwt_driver_id = _auth.get("driver_id")
    jwt_role = _auth.get("role", "")
    if jwt_role != "admin" and jwt_customer_id != ride_request.customer_id and jwt_driver_id != ride_request.matched_driver_id:
        raise HTTPException(status_code=403, detail="Not authorized to view this ride")

    return {
        "success": True,
        "ride_request": serialize_ride_request(ride_request, include_bids=True)
    }


@router.get("/customer/{customer_id}/requests")
async def get_customer_ride_requests(
    customer_id: int,
    request: Request,
    status: Optional[str] = None,
    customer: Customer = Depends(require_customer),
    db: Session = Depends(get_db)
):
    """Get all ride requests for a customer. Requires customer auth + ownership."""
    if customer.id != customer_id:
        raise HTTPException(status_code=403, detail="Not authorized to view this customer's rides")

    query = db.query(RideRequest).filter(RideRequest.customer_id == customer_id)

    if status:
        try:
            status_enum = RideRequestStatus(status)
            query = query.filter(RideRequest.status == status_enum)
        except ValueError:
            pass

    requests = query.order_by(RideRequest.created_at.desc()).limit(50).all()

    return {
        "success": True,
        "requests": [serialize_ride_request(r, include_bids=True) for r in requests]
    }


@router.get("/request/{request_id}/bids")
async def get_bids_for_request(request_id: int, request: Request, customer: Customer = Depends(require_customer), db: Session = Depends(get_db)):
    """Get all pending bids for a ride request. Requires customer auth + ownership."""
    ride_request = db.query(RideRequest).filter(RideRequest.id == request_id).first()
    if not ride_request:
        raise HTTPException(status_code=404, detail="Ride request not found")

    # Only the ride's customer can view bids
    if customer.id != ride_request.customer_id:
        raise HTTPException(status_code=403, detail="Not authorized to view bids for this ride")

    # Get pending bids, sorted by price (lowest first), eager-load driver for vehicle info
    bids = db.query(RideBid).options(
        joinedload(RideBid.driver)
    ).filter(
        and_(
            RideBid.ride_request_id == request_id,
            RideBid.status == BidStatus.PENDING
        )
    ).order_by(RideBid.proposed_price.asc()).all()

    # Return iOS-compatible format (CustomerRideBidsResponse)
    return {
        "request_id": request_id,
        "bids": [serialize_bid(b) for b in bids],
        "total_bids": len(bids),
        "bidding_open": ride_request.status == RideRequestStatus.OPEN or ride_request.status == RideRequestStatus.BIDDING,
        "bidding_ends_at": ride_request.bidding_expires_at.isoformat() if ride_request.bidding_expires_at else None
    }


def _authorize_ride_payment(db: Session, ride_request: RideRequest, bid: RideBid, amount: float) -> None:
    """Authorize (not capture) the rider's card for the agreed fare. Capture happens when the ride completes.

    Shared by every path that matches a ride (rider accepts a bid, driver accepts the rider's counter) so no
    matched ride can complete without a pre-authorization. A card failure cancels the ride and raises 402.
    """
    # Create Stripe PaymentIntent for customer charge (authorize now, capture on completion)
    try:
        import stripe
        import os
        stripe.api_key = os.getenv("STRIPE_SECRET_KEY")

        customer_obj = db.query(Customer).filter(Customer.id == ride_request.customer_id).first()
        if customer_obj and stripe.api_key:
            # Demo accounts (App Store review): skip real Stripe, set demo marker so
            # /create-intent idempotency path returns the demo secret correctly
            _demo_emails = ["demo.customer@dollor.ai", "demo.driver@dollor.ai"]
            if customer_obj.email and customer_obj.email.lower() in _demo_emails:
                ride_request.stripe_payment_intent_id = "demo_pi_appstore_review"
                db.commit()
                logger.info(f"Ride {ride_request.id} demo account — skipping Stripe pre-auth")
            else:
                # Ensure customer has Stripe customer ID
                stripe_customer_id = getattr(customer_obj, 'stripe_customer_id', None)
                if not stripe_customer_id:
                    stripe_cust = stripe.Customer.create(
                        email=customer_obj.email,
                        name=getattr(customer_obj, 'name', None) or getattr(customer_obj, 'full_name', None) or customer_obj.email,
                        metadata={"dollor_customer_id": str(customer_obj.id)},
                        idempotency_key=f"ride-cust-{customer_obj.id}"
                    )
                    customer_obj.stripe_customer_id = stripe_cust.id
                    stripe_customer_id = stripe_cust.id
                    db.commit()

                # Require a saved payment method before charging. Previously this created
                # an unconfirmed PaymentIntent with no payment_method attached, which just
                # sat in requires_payment_method forever — no charge, no error, no signal
                # to the customer, driver, or anyone watching logs that anything was wrong.
                stripe_customer = stripe.Customer.retrieve(stripe_customer_id)
                default_payment_method = stripe_customer.invoice_settings.default_payment_method
                if not default_payment_method:
                    # No explicit default — fall back to any attached card.
                    # This covers Apple Pay cards (added via SetupIntent) and manually
                    # added cards that the customer never tapped "Set as Default".
                    pms = stripe.PaymentMethod.list(customer=stripe_customer_id, type="card", limit=1)
                    if pms.data:
                        default_payment_method = pms.data[0].id
                        # Auto-promote so future rides skip this fallback path.
                        stripe.Customer.modify(
                            stripe_customer_id,
                            invoice_settings={"default_payment_method": default_payment_method}
                        )
                        logger.info(f"Auto-set default payment method {default_payment_method} for customer {customer_obj.id}")
                    else:
                        # CardError is a StripeError subclass, caught below (ride-cancel + notify).
                        raise stripe.error.CardError(
                            message="No payment method on file for this ride.",
                            param="payment_method", code="no_payment_method"
                        )

                final_price_cents = int(float(amount) * 100)
                if final_price_cents > 0:
                    payment_intent = stripe.PaymentIntent.create(
                        amount=final_price_cents,
                        currency="usd",
                        customer=stripe_customer_id,
                        payment_method=default_payment_method,
                        off_session=True,
                        confirm=True,
                        description=f"Rideshare #{ride_request.request_id}",
                        metadata={
                            "ride_request_id": str(ride_request.id),
                            "request_id": ride_request.request_id,
                            "driver_id": str(bid.driver_id),
                            "type": "rideshare"
                        },
                        capture_method="manual",
                        idempotency_key=f"ride-pi-{ride_request.id}"
                    )
                    if payment_intent.status not in ("succeeded", "requires_capture"):
                        raise stripe.error.CardError(
                            message=f"PaymentIntent confirm landed in unexpected status: {payment_intent.status}",
                            param=None, code="confirm_incomplete"
                        )
                    ride_request.stripe_payment_intent_id = payment_intent.id
                    db.commit()
                    logger.info(f"Ride {ride_request.id} PaymentIntent {payment_intent.id} confirmed, status={payment_intent.status} (${amount:.2f})")
    except stripe.error.StripeError as stripe_err:
        # Blocking failure: card declined / Stripe error — auto-cancel the ride
        logger.error(f"Ride {ride_request.id} Stripe pre-auth FAILED ({type(stripe_err).__name__}): {stripe_err} — auto-cancelling")
        ride_request.status = RideRequestStatus.CANCELLED
        ride_request.cancelled_at = datetime.utcnow()
        ride_request.payment_status = "pre_auth_failed"
        ride_request.matched_bid_id = None
        ride_request.matched_driver_id = None
        ride_request.final_price = None
        db.commit()

        # Notify customer
        try:
            send_push_notification(
                "customer", ride_request.customer_id,
                "Payment Failed",
                "Your card could not be pre-authorized. Please update your payment method and try booking again.",
                data={"type": "payment_failed", "ride_request_id": str(ride_request.id)},
                db=db
            )
            _notify_customer(
                db, ride_request.customer_id,
                "Payment Failed",
                "Your card could not be pre-authorized for this ride. Please update your payment method.",
                "ride", ride_request.id, "ride"
            )
        except Exception as notify_err:
            logger.warning(f"Ride {ride_request.id} customer payment-failed notification error: {notify_err}")

        # Notify driver
        try:
            send_push_notification(
                "driver", bid.driver_id,
                "Ride Cancelled",
                "The customer's payment method failed. The ride has been cancelled.",
                data={"type": "payment_failed", "ride_request_id": str(ride_request.id)},
                db=db
            )
        except Exception as notify_err:
            logger.warning(f"Ride {ride_request.id} driver payment-failed notification error: {notify_err}")

        try:
            db.commit()
        except Exception:
            pass

        raise HTTPException(
            status_code=402,
            detail={"error": "payment_failed", "message": "Your card was declined. Please update your payment method and try again."}
        )
    except Exception as e:
        logger.error(f"Ride {ride_request.id} Stripe PaymentIntent creation failed (non-blocking): {e}")


@router.post("/bid/{bid_id}/respond")
async def respond_to_bid(bid_id: int, data: RespondToBidInput, request: Request, customer: Customer = Depends(require_customer), db: Session = Depends(get_db)):
    """
    Customer responds to a driver's bid. Requires customer auth + ride ownership.
    Actions: accept, reject, counter
    """
    bid = db.query(RideBid).filter(RideBid.id == bid_id).first()
    if not bid:
        raise HTTPException(status_code=404, detail="Bid not found")

    # Verify ride exists and caller is the ride's customer (single query)
    ride_request = db.query(RideRequest).filter(RideRequest.id == bid.ride_request_id).first()
    if not ride_request:
        raise HTTPException(status_code=404, detail="Ride request not found")
    if customer.id != ride_request.customer_id:
        raise HTTPException(status_code=403, detail="Only the ride's customer can respond to bids")

    if bid.status != BidStatus.PENDING:
        raise HTTPException(status_code=400, detail=f"Bid is already {bid.status.value}")

    if ride_request.status == RideRequestStatus.MATCHED:
        raise HTTPException(status_code=400, detail="Ride already matched with a driver")

    now = datetime.utcnow()

    if data.action == "accept":
        # Accept this bid - match the ride
        bid.status = BidStatus.ACCEPTED
        bid.accepted_at = now
        bid.responded_at = now

        # Update ride request
        ride_request.status = RideRequestStatus.MATCHED
        ride_request.matched_bid_id = bid.id
        ride_request.matched_driver_id = bid.driver_id
        ride_request.final_price = bid.proposed_price
        ride_request.matched_at = now

        # Increment driver accept count for cancel rate tracking
        accepting_driver = db.query(Driver).filter(Driver.id == bid.driver_id).first()
        if accepting_driver:
            accepting_driver.ride_accept_count = (accepting_driver.ride_accept_count or 0) + 1

        # Prop 22: capture driver GPS at acceptance moment (BPC §7463 — engagement begins at matched_at)
        # Primary: driver's current_latitude/longitude IF within 50mi of pickup (sanity check for stale GPS)
        # Fallback: ride pickup_latitude/longitude (slightly overstates engaged miles — legally safer)
        _driver_lat = accepting_driver.current_latitude if accepting_driver else None
        _driver_lon = accepting_driver.current_longitude if accepting_driver else None
        _use_driver_gps = False
        if _driver_lat is not None and _driver_lon is not None and ride_request.pickup_latitude and ride_request.pickup_longitude:
            try:
                from insurance.utils import haversine_miles as _hav
                _dist = _hav(_driver_lat, _driver_lon, ride_request.pickup_latitude, ride_request.pickup_longitude)
                _use_driver_gps = _dist is not None and _dist <= 50
            except Exception:
                pass
        ride_request.prop22_acceptance_lat = _driver_lat if _use_driver_gps else ride_request.pickup_latitude
        ride_request.prop22_acceptance_lon = _driver_lon if _use_driver_gps else ride_request.pickup_longitude

        # Insurance: Period 1 END + Period 2 START — ride matched
        try:
            from insurance.events import log_insurance_event, get_or_create_session_id
            _session_id = get_or_create_session_id(db, bid.driver_id)
            log_insurance_event(
                db=db, driver_id=bid.driver_id, trip_type="rideshare",
                trip_id=ride_request.id, session_id=_session_id, period=1,
                event_type="period_end",
            )
            log_insurance_event(
                db=db, driver_id=bid.driver_id, trip_type="rideshare",
                trip_id=ride_request.id, session_id=_session_id, period=2,
                event_type="period_start",
            )
        except Exception as e:
            logging.warning(f"Insurance event (bid accept) failed: {e}")

        # Close every other open bid (pending or countered) so none of them can match this ride again
        other_bids = db.query(RideBid).filter(
            and_(
                RideBid.ride_request_id == ride_request.id,
                RideBid.id != bid.id,
                RideBid.status.in_([BidStatus.PENDING, BidStatus.COUNTERED])
            )
        ).all()

        for other_bid in other_bids:
            other_bid.status = BidStatus.REJECTED
            other_bid.rejected_at = now
            other_bid.customer_response = "Another bid was accepted"

        # In-app notification: ride matched
        driver = db.query(Driver).filter(Driver.id == bid.driver_id).first()
        driver_name = f"{driver.first_name} {driver.last_name}" if driver and driver.first_name else "A driver"
        _notify_customer(db, ride_request.customer_id,
                         "Driver Matched!",
                         f"{driver_name} accepted your ride for ${bid.proposed_price:.2f}.",
                         "ride", ride_request.id, "ride")

        db.commit()

        _authorize_ride_payment(db, ride_request, bid, bid.proposed_price)

        # Send WebSocket update - ride matched
        try:
            asyncio.create_task(broadcast_ride_matched(
                ride_request_id=ride_request.id,
                customer_id=ride_request.customer_id,
                driver_id=bid.driver_id,
                match_details=serialize_bid(bid)
            ))
        except Exception as e:
            logger.error(f"WebSocket broadcast error: {e}")

        # Build driver info for iOS AcceptedDriverInfo format
        driver_info = None
        if driver:
            driver_info = {
                "id": driver.id,
                "name": f"{driver.first_name} {driver.last_name}" if driver.first_name else driver.email,
                "phone": driver.phone,
                "rating": driver.rating,
                "photo_url": driver.photo_url,
                "vehicle_make": driver.vehicle_make,
                "vehicle_model": driver.vehicle_model,
                "vehicle_color": driver.vehicle_color,
                "vehicle_year": driver.vehicle_year,
                "license_plate": driver.license_plate,
                "vehicle_photo_url": driver.vehicle_photo_url
            }

        # Send ride matched email to customer
        try:
            customer = db.query(Customer).filter(Customer.id == ride_request.customer_id).first()
            if customer and customer.email and driver:
                _bg_email("send_ride_matched_email",
                    to_email=customer.email,
                    customer_name=f"{customer.first_name} {customer.last_name}".strip() or "Customer",
                    request_id=ride_request.request_id,
                    driver_name=f"{driver.first_name} {driver.last_name}",
                    driver_phone=driver.phone or "",
                    driver_vehicle=bid.driver_vehicle or "",
                    final_price=ride_request.final_price,
                    eta_minutes=bid.estimated_arrival_minutes or 10,
                    pickup_address=ride_request.pickup_address
                )
                logger.info(f"Ride matched email sent to {customer.email}")
        except Exception as e:
            logger.error(f"Failed to send ride matched email: {e}")

        # Send push notification to driver - BID ACCEPTED
        try:
            customer_name = "Customer"
            if customer:
                customer_name = f"{customer.first_name} {customer.last_name}".strip() or "Customer"

            send_push_notification(
                user_type="driver",
                user_id=bid.driver_id,
                title="Bid Accepted!",
                body=f"{customer_name} accepted your ${bid.proposed_price:.0f} bid. Head to pickup!",
                data={
                    "type": "bid_accepted",
                    "ride_request_id": str(ride_request.id),
                    "request_id": ride_request.request_id,
                    "pickup_address": ride_request.pickup_address,
                    "final_price": str(bid.proposed_price)
                },
                db=db
            )
            logger.info(f"Push notification sent to driver {bid.driver_id} - bid accepted")
        except Exception as e:
            logger.error(f"Failed to send push notification to driver: {e}")

        # Push notification to customer — driver en route
        try:
            driver_name = f"{driver.first_name}".strip() if driver else "Your driver"
            eta_minutes = bid.estimated_arrival_minutes or 10
            vehicle_desc = bid.driver_vehicle or "their vehicle"
            send_push_notification(
                user_type="customer",
                user_id=ride_request.customer_id,
                title="Driver on the way!",
                body=f"{driver_name} is heading to you in {vehicle_desc}. ETA: ~{eta_minutes} min",
                data={
                    "type": "driver_en_route",
                    "ride_request_id": str(ride_request.id),
                    "request_id": ride_request.request_id,
                    "driver_name": driver_name,
                    "eta_minutes": str(eta_minutes)
                },
                db=db
            )
        except Exception as e:
            logger.error(f"Failed to send driver en-route push to customer: {e}")

        # Return iOS AcceptedRideDetails format + backward compatible fields
        return {
            "success": True,
            "message": f"Bid accepted! Ride matched with {bid.driver_name}",
            # iOS AcceptedRideDetails fields
            "ride_id": ride_request.id,
            "driver": driver_info,
            "pickup": {
                "address": ride_request.pickup_address,
                "latitude": ride_request.pickup_latitude,
                "longitude": ride_request.pickup_longitude
            },
            "dropoff": {
                "address": ride_request.dropoff_address,
                "latitude": ride_request.dropoff_latitude,
                "longitude": ride_request.dropoff_longitude
            },
            "estimated_arrival_minutes": bid.estimated_arrival_minutes,
            "fare": bid.proposed_price,
            "status": "accepted",
            # Backward compatible fields
            "ride_request": serialize_ride_request(ride_request),
            "accepted_bid": serialize_bid(bid)
        }

    elif data.action == "reject":
        bid.status = BidStatus.REJECTED
        bid.rejected_at = now
        bid.responded_at = now
        bid.customer_response = data.message or "Bid rejected by customer"

        db.commit()

        # Send WebSocket update to driver
        try:
            asyncio.create_task(broadcast_bid_response(
                driver_id=bid.driver_id,
                bid_id=bid.id,
                action="rejected",
                details={"message": bid.customer_response}
            ))
        except Exception as e:
            logger.error(f"WebSocket broadcast error: {e}")

        # Push notification to driver — bid rejected
        try:
            send_push_notification(
                user_type="driver",
                user_id=bid.driver_id,
                title="Bid Not Accepted",
                body=f"Your ${bid.proposed_price:.2f} bid was not accepted. Keep bidding on other rides!",
                data={
                    "type": "bid_rejected",
                    "bid_id": str(bid.id),
                    "ride_request_id": str(bid.ride_request_id),
                    "proposed_price": str(bid.proposed_price)
                },
                db=db
            )
        except Exception as e:
            logger.error(f"Failed to send bid rejected push: {e}")

        return {
            "success": True,
            "message": "Bid rejected",
            "bid": serialize_bid(bid)
        }

    elif data.action == "counter":
        if not data.counter_price:
            raise HTTPException(status_code=400, detail="Counter price required")

        # Multi-round negotiation: Check customer counter limit (max 3 total)
        MAX_CUSTOMER_COUNTERS = pricing_engine.config.MAX_CUSTOMER_COUNTERS
        current_counter_count = ride_request.customer_counter_count or 0

        if current_counter_count >= MAX_CUSTOMER_COUNTERS:
            raise HTTPException(
                status_code=400,
                detail=f"Maximum {MAX_CUSTOMER_COUNTERS} counter-offers reached. Please accept a bid or request a new ride."
            )

        # Check negotiation round for this bid (max 2 rounds per bid)
        MAX_ROUNDS_PER_BID = pricing_engine.config.MAX_ROUNDS_PER_BID
        current_round = bid.negotiation_round or 1

        if current_round >= MAX_ROUNDS_PER_BID and bid.last_offer_by == "customer":
            raise HTTPException(
                status_code=400,
                detail="Maximum negotiation rounds reached for this bid. Accept, reject, or try another driver."
            )

        # Price validation
        suggested_price = ride_request.suggested_price or 15.0
        counter_price = data.counter_price
        warning_message = None

        # Counter must be positive
        if counter_price <= 0:
            raise HTTPException(status_code=400, detail="Counter price must be greater than $0")

        # Customer counter should be lower than driver's bid (negotiating down)
        if counter_price >= bid.proposed_price:
            raise HTTPException(
                status_code=400,
                detail=f"Counter must be less than driver's bid of ${bid.proposed_price:.2f}"
            )

        # Very low bid (< 40% of suggested) - reject with message
        if counter_price < suggested_price * 0.4:
            min_acceptable = round(suggested_price * 0.5, 2)
            raise HTTPException(
                status_code=400,
                detail=f"Offer too low. Minimum acceptable: ${min_acceptable:.2f}. Suggested fare: ${suggested_price:.2f}"
            )

        # Low bid (< 60% of suggested) - allow but warn
        elif counter_price < suggested_price * 0.6:
            warning_message = f"Warning: Your offer is {int((1 - counter_price/suggested_price) * 100)}% below market rate. Drivers may not accept."
            ride_request.low_bid_warning_shown = True

        # Update bid with counter
        # Note: negotiation_round only increments when DRIVER makes a new offer
        # Customer counter is still part of current round (responding to driver's offer)
        bid.status = BidStatus.COUNTERED
        bid.responded_at = now
        bid.customer_response = data.message
        bid.customer_counter_price = data.counter_price
        # Don't increment negotiation_round here - customer is responding, not starting new round
        bid.last_offer_by = "customer"
        bid.round_counter = (bid.round_counter or 0) + 1

        # Update ride request counter count
        ride_request.customer_counter_count = current_counter_count + 1

        db.commit()

        # Send push notification to driver about counter-offer
        try:
            send_push_notification(
                user_type="driver",
                user_id=bid.driver_id,
                title="Counter Offer Received!",
                body=f"Customer offered ${data.counter_price:.2f} (Round {current_round}/2)",
                data={
                    "type": "counter_offer",
                    "bid_id": str(bid.id),
                    "ride_request_id": str(ride_request.id),
                    "counter_price": str(data.counter_price),
                    "round": str(current_round)
                },
                db=db
            )
        except Exception as e:
            logger.error(f"Failed to send counter-offer push notification: {e}")

        # Send WebSocket update to driver with counter-offer
        try:
            asyncio.create_task(broadcast_bid_response(
                driver_id=bid.driver_id,
                bid_id=bid.id,
                action="countered",
                details={
                    "counter_price": data.counter_price,
                    "message": data.message,
                    "negotiation_round": current_round,
                    "rounds_remaining": MAX_ROUNDS_PER_BID - current_round
                }
            ))
        except Exception as e:
            logger.error(f"WebSocket broadcast error: {e}")

        response = {
            "success": True,
            "message": f"Counter-offer of ${data.counter_price:.2f} sent to driver",
            "bid": serialize_bid(bid),
            "negotiation_round": current_round,
            "customer_counters_remaining": MAX_CUSTOMER_COUNTERS - ride_request.customer_counter_count,
            "rounds_remaining_this_bid": MAX_ROUNDS_PER_BID - current_round
        }

        if warning_message:
            response["warning"] = warning_message

        return response

    else:
        raise HTTPException(status_code=400, detail="Invalid action. Use: accept, reject, or counter")


@router.post("/request/{request_id}/cancel")
async def cancel_ride_request(request_id: int, request: Request, customer: Customer = Depends(require_customer), db: Session = Depends(get_db)):
    """Customer cancels their ride request. Requires customer auth + ownership."""
    ride_request = db.query(RideRequest).filter(RideRequest.id == request_id).first()
    if not ride_request:
        raise HTTPException(status_code=404, detail="Ride request not found")

    # Only the ride's customer can cancel
    if customer.id != ride_request.customer_id:
        raise HTTPException(status_code=403, detail="Only the ride's customer can cancel")

    if ride_request.status in [RideRequestStatus.IN_PROGRESS, RideRequestStatus.COMPLETED, RideRequestStatus.CANCELLED]:
        raise HTTPException(status_code=400, detail=f"Cannot cancel ride with status: {ride_request.status.value}")

    ride_request.status = RideRequestStatus.CANCELLED
    ride_request.cancelled_at = datetime.utcnow()

    # Cancel Stripe PaymentIntent if one was created
    if ride_request.stripe_payment_intent_id and not ride_request.stripe_payment_intent_id.startswith("demo_"):
        try:
            import stripe
            import os
            stripe.api_key = os.getenv("STRIPE_SECRET_KEY")
            stripe.PaymentIntent.cancel(
                ride_request.stripe_payment_intent_id,
                idempotency_key=f"ride-cancel-{ride_request.id}"
            )
            logger.info(f"Ride {ride_request.id} PaymentIntent cancelled on customer cancel")
        except Exception as e:
            logger.error(f"Ride {ride_request.id} PaymentIntent cancel failed: {e}")

    # Expire all pending bids
    pending_bids = db.query(RideBid).filter(
        and_(
            RideBid.ride_request_id == request_id,
            RideBid.status == BidStatus.PENDING
        )
    ).all()

    for bid in pending_bids:
        bid.status = BidStatus.EXPIRED
        bid.customer_response = "Ride request cancelled by customer"

    db.commit()

    # Notify matched driver if ride was matched (Task #24)
    matched_driver_id = ride_request.matched_driver_id
    if matched_driver_id:
        try:
            send_push_notification(
                user_type="driver",
                user_id=matched_driver_id,
                title="Ride cancelled by customer",
                body=f"Ride {ride_request.request_id} has been cancelled by the customer.",
                data={
                    "type": "ride_cancelled",
                    "ride_request_id": str(ride_request.id),
                    "request_id": ride_request.request_id,
                    "reason": "customer_cancelled"
                },
                db=db
            )
            logger.info(f"Cancellation push sent to matched driver {matched_driver_id}")
        except Exception as e:
            logger.error(f"Failed to notify matched driver of cancellation: {e}")

    # Send cancellation email to customer
    try:
        customer = db.query(Customer).filter(Customer.id == ride_request.customer_id).first()
        if customer and customer.email:
            _bg_email("send_ride_cancelled_email",
                to_email=customer.email,
                customer_name=f"{customer.first_name} {customer.last_name}".strip() or "Customer",
                request_id=ride_request.request_id,
                cancelled_by="Customer",
                reason="Cancelled by customer request",
                refund_amount=ride_request.final_price if ride_request.final_price else None
            )
            logger.info(f"Ride cancellation email sent to {customer.email}")
    except Exception as e:
        logger.error(f"Failed to send ride cancellation email: {e}")

    return {
        "success": True,
        "message": "Ride request cancelled"
    }


# =========================================================================
# DRIVER ENDPOINTS
# =========================================================================

@router.get("/available")
async def get_available_ride_requests(
    request: Request,
    driver_id: Optional[int] = None,
    latitude: Optional[float] = None,
    longitude: Optional[float] = None,
    radius_km: Optional[float] = None,
    driver: Driver = Depends(require_driver),
    db: Session = Depends(get_db)
):
    """
    Get available ride requests near the driver for bidding. Requires driver auth.
    """
    # Default search radius is the widest dispatch step, so every driver the policy notifies can see the ride
    if radius_km is None:
        radius_km = ride_dispatch.max_radius_miles() * 1.609344

    # Only online drivers receive bids
    if not driver.is_online:
        return {"success": True, "available_requests": [], "count": 0}

    # If driver_id provided, verify it matches the authenticated driver
    if driver_id and driver.id != driver_id:
        raise HTTPException(status_code=403, detail="driver_id does not match authenticated user")
    # Use authenticated driver's id if not explicitly provided
    if not driver_id:
        driver_id = driver.id
    # Get open and bidding ride requests (BIDDING = at least one driver has bid)
    now = datetime.utcnow()
    open_requests = db.query(RideRequest).filter(
        and_(
            RideRequest.status.in_([RideRequestStatus.OPEN, RideRequestStatus.BIDDING]),
            or_(
                RideRequest.bidding_expires_at > now,
                and_(
                    RideRequest.bidding_expires_at.is_(None),
                    RideRequest.created_at > now - timedelta(minutes=30)
                )
            )
        )
    ).all()

    # WAV filter: if driver is not accessibility_capable, exclude accessibility_requested rides
    # (TNC-12 compliance: only WAV-capable drivers see WAV ride requests)
    if not getattr(driver, 'accessibility_capable', False):
        open_requests = [r for r in open_requests if not getattr(r, 'accessibility_requested', False)]

    # Batch check: which of these rides does the driver already have an active bid on?
    request_ids = [r.id for r in open_requests]
    driver_existing_bids = {}
    if driver_id is not None and request_ids:
        existing_bids = db.query(RideBid).filter(
            and_(
                RideBid.ride_request_id.in_(request_ids),
                RideBid.driver_id == driver_id,
                RideBid.status.in_([BidStatus.PENDING, BidStatus.COUNTERED])
            )
        ).all()
        for eb in existing_bids:
            driver_existing_bids[eb.ride_request_id] = eb

    # Dispatch policy (ride_dispatch.py): offer each request to the nearest drivers around the pickup,
    # widening the search if nobody bids. Only applies when the app sent a live location; without one
    # (e.g. no GPS fix) every open request stays visible rather than hiding rides from the driver.
    dispatch_enabled = (
        latitude is not None and longitude is not None
        and (driver.email or "").lower() not in SHARED_DEMO_DRIVER_EMAILS
    )
    online_points = []
    if dispatch_enabled:
        online_points = [
            (d.id, d.current_latitude, d.current_longitude)
            for d in db.query(Driver).filter(
                Driver.is_online == True,  # noqa: E712
                Driver.current_latitude.isnot(None),
                Driver.current_longitude.isnot(None),
                Driver.id != driver.id,
            ).all()
        ]
        online_points.append((driver.id, latitude, longitude))

    nearby_requests = []
    for request in open_requests:
        if dispatch_enabled:
            age_seconds = (now - (request.created_at or now)).total_seconds()
            if not is_driver_notified(
                driver.id, request.pickup_latitude, request.pickup_longitude,
                online_points, age_seconds, has_bids=bool(getattr(request, "bids", None)),
            ):
                continue
        # Calculate distance if driver location provided
        distance = None
        if latitude is not None and longitude is not None and request.pickup_latitude and request.pickup_longitude:
            distance = calculate_distance_km(
                latitude, longitude,
                request.pickup_latitude, request.pickup_longitude
            )
            if distance > radius_km:
                continue

        existing_bid = driver_existing_bids.get(request.id)

        request_data = serialize_ride_request(request)
        request_data["distance_to_pickup_km"] = round(distance, 2) if distance is not None else None
        request_data["already_bid"] = existing_bid is not None
        if existing_bid:
            request_data["my_bid"] = serialize_bid(existing_bid)

        nearby_requests.append(request_data)

    # Sort by distance if available (closest first)
    nearby_requests.sort(key=lambda x: x.get("distance_to_pickup_km") or 999)

    return {
        "success": True,
        "available_requests": nearby_requests,
        "count": len(nearby_requests)
    }


@router.get("/driver/active")
async def get_driver_active_rides(
    driver: Driver = Depends(require_driver),
    db: Session = Depends(get_db)
):
    """Get MATCHED and IN_PROGRESS rides for the authenticated driver.
    Used by iOS DeliveryViewModel.fetchMyActiveRides() to populate myActiveRides.
    """
    active_statuses = [RideRequestStatus.MATCHED, RideRequestStatus.IN_PROGRESS]
    rides = db.query(RideRequest).filter(
        and_(
            RideRequest.matched_driver_id == driver.id,
            RideRequest.status.in_(active_statuses)
        )
    ).order_by(RideRequest.matched_at.desc()).limit(10).all()
    # The matched driver may call the rider; the phone is only included here, never in the public serializer
    phones = {}
    customer_ids = {r.customer_id for r in rides}
    if customer_ids:
        phones = {c.id: c.phone for c in db.query(Customer).filter(Customer.id.in_(customer_ids)).all()}
    active_rides = []
    for r in rides:
        payload = serialize_ride_request(r)
        payload["customer_phone"] = phones.get(r.customer_id)
        active_rides.append(payload)
    return {
        "success": True,
        "active_rides": active_rides,
        "count": len(rides)
    }


@router.post("/request/{request_id}/bid")
async def submit_bid(request_id: int, data: SubmitBidInput, request: Request, driver: Driver = Depends(require_driver), db: Session = Depends(get_db)):
    """
    Driver submits a bid on a ride request. Requires driver auth. Prevents driver_id spoofing.
    """
    # Prevent driver_id spoofing -- always use authenticated driver's ID
    data.driver_id = driver.id

    # Validate bid price (Task #18)
    if data.proposed_price is not None and data.proposed_price <= 0:
        raise HTTPException(status_code=400, detail="Bid price must be greater than $0")
    if data.proposed_price is not None and data.proposed_price > 10000:
        raise HTTPException(status_code=400, detail="Bid price exceeds maximum allowed ($10,000)")

    # Get ride request
    ride_request = db.query(RideRequest).filter(RideRequest.id == request_id).first()
    if not ride_request:
        raise HTTPException(status_code=404, detail="Ride request not found")

    # SECURITY (NSA-008): Prevent self-bidding (driver bidding on own ride request)
    if ride_request.customer_id and driver.id:
        customer_check = db.query(Customer).filter(Customer.id == ride_request.customer_id).first()
        if customer_check and customer_check.email and driver.email:
            if driver.email.lower() == customer_check.email.lower():
                raise HTTPException(status_code=403, detail="Cannot bid on your own ride request")

    # Allow bidding when status is OPEN or BIDDING (status becomes BIDDING after first bid)
    if ride_request.status not in [RideRequestStatus.OPEN, RideRequestStatus.BIDDING]:
        raise HTTPException(status_code=400, detail=f"Ride request is {ride_request.status.value}, not accepting bids")

    # Check if bidding expired
    if ride_request.bidding_expires_at and datetime.utcnow() > ride_request.bidding_expires_at:
        raise HTTPException(status_code=400, detail="Bidding window has closed")

    # Get driver
    driver = db.query(Driver).filter(Driver.id == data.driver_id).first()
    if not driver:
        raise HTTPException(status_code=404, detail="Driver not found")

    # KYC gate: driver must be identity-verified before submitting bids.
    # "verified"/documents_verified come from the older Persona-based pipeline;
    # "passed" is what checkr_service.py actually sets on a clear Checkr report
    # (the flow this app's onboarding uses) — without it, every Checkr-approved
    # driver was silently blocked here despite being fully APPROVED and online.
    kyc_verified = (
        getattr(driver, 'verification_status', None) in ("verified", "passed") or
        getattr(driver, 'documents_verified', False)
    )
    if not kyc_verified:
        raise HTTPException(
            status_code=403,
            detail="Identity verification required before you can accept rides. Please complete verification in your profile."
        )

    # Verify driver is approved/active
    driver_status = driver.status if isinstance(driver.status, DriverStatus) else DriverStatus(driver.status) if driver.status else None
    if driver_status not in [DriverStatus.APPROVED, DriverStatus.ACTIVE]:
        missing_docs = []
        if not driver.drivers_license:
            missing_docs.append("driver's license")
        if not driver.insurance:
            missing_docs.append("insurance")
        if not driver.photo_url:
            missing_docs.append("profile photo")

        if missing_docs:
            detail = f"Please upload and verify: {', '.join(missing_docs)}"
        else:
            detail = "Your documents are pending verification. You'll be notified when approved."

        raise HTTPException(status_code=403, detail=detail)

    # Check if driver has an active ride or delivery
    active_ride = db.query(RideRequest).filter(
        and_(
            RideRequest.matched_driver_id == data.driver_id,
            RideRequest.status.in_([RideRequestStatus.MATCHED, RideRequestStatus.IN_PROGRESS])
        )
    ).first()
    if active_ride:
        raise HTTPException(
            status_code=400,
            detail="You have an active ride in progress. Complete your current ride before bidding on new requests."
        )

    # Check if driver has an active delivery order (any status where driver is assigned)
    from models import Order, OrderStatus
    active_delivery = db.query(Order).filter(
        and_(
            Order.driver_id == data.driver_id,
            Order.status.in_([OrderStatus.PREPARING, OrderStatus.READY_FOR_PICKUP, OrderStatus.OUT_FOR_DELIVERY])
        )
    ).first()
    if active_delivery:
        raise HTTPException(
            status_code=400,
            detail="You have an active delivery in progress. Complete your current delivery before bidding on rides."
        )

    # Check if driver already has any bid (PENDING or otherwise) using SELECT FOR UPDATE
    # to prevent race conditions where two concurrent requests both see NULL and both INSERT.
    existing_bid = db.execute(
        select(RideBid).where(
            and_(
                RideBid.ride_request_id == request_id,
                RideBid.driver_id == data.driver_id,
            )
        ).with_for_update()
    ).scalars().first()

    if existing_bid:
        raise HTTPException(status_code=400, detail="You already have a bid on this request. Update or withdraw it first.")

    # Check max bids limit (default 10)
    # First, auto-expire old pending bids (older than 10 minutes)
    now = datetime.utcnow()
    expired_bids = db.query(RideBid).filter(
        and_(
            RideBid.ride_request_id == request_id,
            RideBid.status == BidStatus.PENDING,
            RideBid.expires_at < now
        )
    ).all()

    for expired_bid in expired_bids:
        expired_bid.status = BidStatus.EXPIRED
        expired_bid.customer_response = "Bid expired (no response within 10 minutes)"

    if expired_bids:
        db.commit()

    # Count only active (non-expired) pending bids
    current_bid_count = db.query(RideBid).filter(
        and_(
            RideBid.ride_request_id == request_id,
            RideBid.status == BidStatus.PENDING,
            or_(
                RideBid.expires_at > now,
                RideBid.expires_at.is_(None)
            )
        )
    ).count()

    max_bids = ride_request.max_bids or 10
    if current_bid_count >= max_bids:
        raise HTTPException(
            status_code=400,
            detail=f"This ride has reached the maximum of {max_bids} active bids. Try another ride request."
        )

    # Create bid
    vehicle_info = f"{driver.vehicle_make} {driver.vehicle_model}"
    if driver.vehicle_year:
        vehicle_info += f" {driver.vehicle_year}"
    if driver.vehicle_color:
        vehicle_info += f" - {driver.vehicle_color}"

    bid = RideBid(
        bid_id=generate_bid_id(),
        ride_request_id=request_id,
        driver_id=data.driver_id,
        driver_name=f"{driver.first_name} {driver.last_name}",
        driver_rating=driver.rating,
        driver_photo_url=driver.photo_url,
        driver_vehicle=vehicle_info,
        proposed_price=data.proposed_price,
        message=data.message,
        estimated_arrival_minutes=data.estimated_arrival_minutes,
        status=BidStatus.PENDING,
        expires_at=datetime.utcnow() + timedelta(minutes=10)  # Bid valid for 10 minutes
    )

    try:
        db.add(bid)

        # Update ride request status to BIDDING if first bid
        if ride_request.status == RideRequestStatus.OPEN:
            ride_request.status = RideRequestStatus.BIDDING

        db.flush()  # Gets auto-incremented id without committing
        bid.bid_id = generate_clean_bid_id(bid.id)
        db.commit()
        db.refresh(bid)
    except IntegrityError:
        db.rollback()
        raise HTTPException(status_code=400, detail="Bid already submitted. Please refresh and try again.")

    # Send WebSocket update to customer about new bid
    try:
        asyncio.create_task(broadcast_new_bid(
            ride_request_id=request_id,
            customer_id=ride_request.customer_id,
            bid_data=serialize_bid(bid)
        ))
    except Exception as e:
        logger.error(f"WebSocket broadcast error: {e}")

    # Send email notification to customer about new bid
    try:
        customer = db.query(Customer).filter(Customer.id == ride_request.customer_id).first()
        if customer and customer.email:
            # Count total pending bids
            total_bids = db.query(RideBid).filter(
                RideBid.ride_request_id == request_id,
                RideBid.status == BidStatus.PENDING
            ).count()

            _bg_email("send_ride_bid_received_email",
                to_email=customer.email,
                customer_name=f"{customer.first_name} {customer.last_name}".strip() or "Customer",
                request_id=ride_request.request_id,
                driver_name=f"{driver.first_name} {driver.last_name}",
                driver_rating=driver.rating or 0.0,
                proposed_price=data.proposed_price,
                eta_minutes=data.estimated_arrival_minutes or 10,
                total_bids=total_bids
            )
            logger.info(f"Bid notification email sent to {customer.email}")
    except Exception as e:
        logger.error(f"Failed to send bid notification email: {e}")

    # Send push notification to customer about new bid
    try:
        driver_name = f"{driver.first_name} {driver.last_name}".strip()
        send_push_notification(
            user_type="customer",
            user_id=ride_request.customer_id,
            title="New Driver Bid!",
            body=f"{driver_name} bid ${data.proposed_price:.2f} for your ride",
            data={
                "type": "new_bid",
                "ride_request_id": str(request_id),
                "bid_id": str(bid.id),
                "driver_name": driver_name,
                "proposed_price": str(data.proposed_price),
                "eta_minutes": str(data.estimated_arrival_minutes or 10)
            },
            db=db
        )
        logger.info(f"Push notification sent to customer {ride_request.customer_id} for new bid")
    except Exception as e:
        logger.error(f"Failed to send push notification for new bid: {e}")

    return {
        "success": True,
        "message": "Bid submitted successfully",
        "bid": serialize_bid(bid)
    }


@router.put("/bid/{bid_id}")
async def update_bid(bid_id: int, data: UpdateBidInput, request: Request, auth_driver: Driver = Depends(require_driver), db: Session = Depends(get_db)):
    """Driver updates their bid (only if still pending). Requires driver auth (bid owner)."""
    bid = db.query(RideBid).filter(RideBid.id == bid_id).first()
    if not bid:
        raise HTTPException(status_code=404, detail="Bid not found")

    if auth_driver.id != bid.driver_id:
        raise HTTPException(status_code=403, detail="Only the bid owner can update it")

    if bid.status != BidStatus.PENDING:
        raise HTTPException(status_code=400, detail=f"Cannot update bid that is {bid.status.value}")

    bid.proposed_price = data.proposed_price
    if data.message:
        bid.message = data.message
    bid.updated_at = datetime.utcnow()

    db.commit()
    db.refresh(bid)

    return {
        "success": True,
        "message": "Bid updated",
        "bid": serialize_bid(bid)
    }


@router.post("/bid/{bid_id}/withdraw")
async def withdraw_bid(bid_id: int, request: Request, auth_driver: Driver = Depends(require_driver), db: Session = Depends(get_db)):
    """Driver withdraws their bid. Requires driver auth (bid owner)."""
    bid = db.query(RideBid).filter(RideBid.id == bid_id).first()
    if not bid:
        raise HTTPException(status_code=404, detail="Bid not found")

    if auth_driver.id != bid.driver_id:
        raise HTTPException(status_code=403, detail="Only the bid owner can withdraw it")

    if bid.status not in [BidStatus.PENDING, BidStatus.COUNTERED]:
        raise HTTPException(status_code=400, detail=f"Cannot withdraw bid that is {bid.status.value}")

    bid.status = BidStatus.WITHDRAWN
    bid.updated_at = datetime.utcnow()

    db.commit()

    # Keep ride request open for other drivers
    ride_request = db.query(RideRequest).filter(RideRequest.id == bid.ride_request_id).first()
    if ride_request and ride_request.status == RideRequestStatus.BIDDING:
        # Check if there are other pending bids
        other_pending = db.query(RideBid).filter(
            and_(
                RideBid.ride_request_id == ride_request.id,
                RideBid.status == BidStatus.PENDING
            )
        ).count()
        if other_pending == 0:
            ride_request.status = RideRequestStatus.OPEN  # Reopen for new bids
            db.commit()

    return {
        "success": True,
        "message": "Bid withdrawn. Ride is available for other drivers."
    }


class DriverCounterInput(BaseModel):
    counter_price: float
    message: Optional[str] = None


@router.post("/bid/{bid_id}/driver-counter")
async def driver_counter_offer(bid_id: int, data: DriverCounterInput, request: Request, auth_driver: Driver = Depends(require_driver), db: Session = Depends(get_db)):
    """
    Driver responds to customer's counter-offer with their own counter (Round 2). Requires driver auth.
    This is the final round - customer must accept or reject.
    """
    bid = db.query(RideBid).filter(RideBid.id == bid_id).first()
    if not bid:
        raise HTTPException(status_code=404, detail="Bid not found")

    if auth_driver.id != bid.driver_id:
        raise HTTPException(status_code=403, detail="Only the bid owner can counter")

    if bid.status != BidStatus.COUNTERED:
        raise HTTPException(status_code=400, detail="Can only counter a bid that has been countered by customer")

    if bid.last_offer_by != "customer":
        raise HTTPException(status_code=400, detail="Waiting for customer response")

    ride_request = db.query(RideRequest).filter(RideRequest.id == bid.ride_request_id).first()
    if not ride_request:
        raise HTTPException(status_code=404, detail="Ride request not found")

    # Validate counter price
    if data.counter_price <= 0:
        raise HTTPException(status_code=400, detail="Counter price must be greater than $0")

    # Driver counter should be higher than customer's counter (negotiating up)
    if bid.customer_counter_price and data.counter_price <= bid.customer_counter_price:
        raise HTTPException(
            status_code=400,
            detail=f"Counter must be more than customer's offer of ${bid.customer_counter_price:.2f}"
        )

    MAX_ROUNDS_PER_BID = pricing_engine.config.MAX_ROUNDS_PER_BID
    if bid.negotiation_round >= MAX_ROUNDS_PER_BID:
        raise HTTPException(
            status_code=400,
            detail="Maximum negotiation rounds reached. Accept customer's offer or withdraw."
        )

    now = datetime.utcnow()

    # Update bid with driver's counter
    bid.proposed_price = data.counter_price
    bid.message = data.message
    bid.negotiation_round = (bid.negotiation_round or 1) + 1
    bid.last_offer_by = "driver"
    bid.round_counter = (bid.round_counter or 0) + 1
    bid.updated_at = now
    bid.status = BidStatus.PENDING  # Back to pending for customer decision

    db.commit()

    # Send push notification to customer about driver's counter
    try:
        send_push_notification(
            user_type="customer",
            user_id=ride_request.customer_id,
            title="Driver Counter Offer!",
            body=f"Driver offered ${data.counter_price:.2f} - Final offer (Round {bid.negotiation_round}/2)",
            data={
                "type": "driver_counter",
                "bid_id": str(bid.id),
                "ride_request_id": str(ride_request.id),
                "counter_price": str(data.counter_price),
                "round": str(bid.negotiation_round),
                "is_final": "true"
            },
            db=db
        )
    except Exception as e:
        logger.error(f"Failed to send driver counter push notification: {e}")

    # WebSocket broadcast
    try:
        asyncio.create_task(broadcast_bid_update(
            ride_request_id=ride_request.id,
            customer_id=ride_request.customer_id,
            bid_data={
                **serialize_bid(bid),
                "is_driver_counter": True,
                "is_final_round": bid.negotiation_round >= MAX_ROUNDS_PER_BID
            }
        ))
    except Exception as e:
        logger.error(f"WebSocket broadcast error: {e}")

    return {
        "success": True,
        "message": f"Counter-offer of ${data.counter_price:.2f} sent to customer. This is the final round.",
        "bid": serialize_bid(bid),
        "negotiation_round": bid.negotiation_round,
        "is_final_round": True
    }


@router.post("/bid/{bid_id}/accept-counter")
async def accept_counter_offer(bid_id: int, request: Request, auth_driver: Driver = Depends(require_driver), db: Session = Depends(get_db)):
    """Driver accepts customer's counter-offer. Requires driver auth (bid owner)."""
    bid = db.query(RideBid).filter(RideBid.id == bid_id).first()
    if not bid:
        raise HTTPException(status_code=404, detail="Bid not found")

    if auth_driver.id != bid.driver_id:
        raise HTTPException(status_code=403, detail="Only the bid owner can accept counter")

    if bid.status != BidStatus.COUNTERED:
        raise HTTPException(status_code=400, detail="This bid doesn't have a counter-offer")

    ride_request = db.query(RideRequest).filter(RideRequest.id == bid.ride_request_id).first()
    if not ride_request:
        raise HTTPException(status_code=404, detail="Ride request not found")

    # A counter can only be accepted while the ride is still open; otherwise this would overwrite another driver's match
    if ride_request.status not in (RideRequestStatus.OPEN, RideRequestStatus.BIDDING):
        raise HTTPException(status_code=409, detail="This ride is no longer available")

    now = datetime.utcnow()

    # Save original price before updating (for history tracking)
    original_driver_price = bid.proposed_price

    # Accept the counter-offer price
    bid.status = BidStatus.ACCEPTED
    bid.proposed_price = bid.customer_counter_price
    bid.is_counter_offer = True
    if not bid.original_price:  # Only set if not already set
        bid.original_price = original_driver_price
    bid.accepted_at = now

    # Match the ride
    ride_request.status = RideRequestStatus.MATCHED
    ride_request.matched_bid_id = bid.id
    ride_request.matched_driver_id = bid.driver_id
    ride_request.final_price = bid.customer_counter_price
    ride_request.matched_at = now

    # Close every other open bid (pending or countered) so none of them can match this ride again
    other_bids = db.query(RideBid).filter(
        and_(
            RideBid.ride_request_id == ride_request.id,
            RideBid.id != bid.id,
            RideBid.status.in_([BidStatus.PENDING, BidStatus.COUNTERED])
        )
    ).all()

    for other_bid in other_bids:
        other_bid.status = BidStatus.REJECTED
        other_bid.customer_response = "Another bid was accepted"

    db.commit()

    # Authorize the rider's card for the countered fare, same as when the rider accepts a bid
    try:
        _authorize_ride_payment(db, ride_request, bid, bid.customer_counter_price)
    except HTTPException as payment_error:
        if payment_error.status_code == 402:
            raise HTTPException(
                status_code=402,
                detail={"error": "payment_failed", "message": "The rider's card could not be authorized, so the ride was cancelled."},
            )
        raise

    # Send push notification to customer - COUNTER ACCEPTED
    try:
        driver = db.query(Driver).filter(Driver.id == bid.driver_id).first()
        driver_name = "Your driver"
        if driver:
            driver_name = f"{driver.first_name}".strip() or "Your driver"

        send_push_notification(
            user_type="customer",
            user_id=ride_request.customer_id,
            title="Driver Accepted Your Offer!",
            body=f"{driver_name} accepted ${bid.customer_counter_price:.0f}. Pickup in ~{bid.estimated_arrival_minutes or 10} min",
            data={
                "type": "counter_accepted",
                "ride_request_id": str(ride_request.id),
                "request_id": ride_request.request_id,
                "final_price": str(bid.customer_counter_price),
                "driver_name": driver_name
            },
            db=db
        )
        logger.info(f"Push notification sent to customer {ride_request.customer_id} - counter accepted")
    except Exception as e:
        logger.error(f"Failed to send push notification to customer: {e}")

    # Send WebSocket update - ride matched (same as respond_to_bid accept path)
    try:
        asyncio.create_task(broadcast_ride_matched(
            ride_request_id=ride_request.id,
            customer_id=ride_request.customer_id,
            driver_id=bid.driver_id,
            match_details=serialize_bid(bid)
        ))
    except Exception as e:
        logger.error(f"WebSocket broadcast error (accept_counter_offer): {e}")

    # Send ride matched email to customer
    try:
        customer = db.query(Customer).filter(Customer.id == ride_request.customer_id).first()
        driver = db.query(Driver).filter(Driver.id == bid.driver_id).first()
        if customer and customer.email and driver:
            _bg_email("send_ride_matched_email",
                to_email=customer.email,
                customer_name=f"{customer.first_name} {customer.last_name}".strip() or "Customer",
                request_id=ride_request.request_id,
                driver_name=f"{driver.first_name} {driver.last_name}",
                driver_phone=driver.phone or "",
                driver_vehicle=bid.driver_vehicle or "",
                final_price=ride_request.final_price,
                eta_minutes=bid.estimated_arrival_minutes or 10,
                pickup_address=ride_request.pickup_address
            )
            logger.info(f"Ride matched email sent to {customer.email}")
    except Exception as e:
        logger.error(f"Failed to send ride matched email: {e}")

    return {
        "success": True,
        "message": f"Counter-offer accepted! Ride matched at ${bid.customer_counter_price:.2f}",
        "ride_request": serialize_ride_request(ride_request),
        "bid": serialize_bid(bid)
    }


@router.post("/bid/{bid_id}/reject-counter")
async def reject_counter_offer(bid_id: int, request: Request, auth_driver: Driver = Depends(require_driver), db: Session = Depends(get_db)):
    """Driver rejects customer's counter-offer. Requires driver auth (bid owner)."""
    bid = db.query(RideBid).filter(RideBid.id == bid_id).first()
    if not bid:
        raise HTTPException(status_code=404, detail="Bid not found")

    if auth_driver.id != bid.driver_id:
        raise HTTPException(status_code=403, detail="Only the bid owner can reject counter")

    if bid.status != BidStatus.COUNTERED:
        raise HTTPException(status_code=400, detail="This bid doesn't have a counter-offer")

    bid.status = BidStatus.WITHDRAWN
    bid.updated_at = datetime.utcnow()

    db.commit()

    return {
        "success": True,
        "message": "Counter-offer rejected, bid withdrawn"
    }


@router.get("/driver/{driver_id}/bids")
async def get_driver_bids(
    driver_id: int,
    request: Request,
    status: Optional[str] = None,
    days: int = 7,
    auth_driver: Driver = Depends(require_driver),
    db: Session = Depends(get_db)
):
    """Get all bids for a driver. Requires driver auth + ownership. Filterable by days (default 7)."""
    if auth_driver.id != driver_id:
        raise HTTPException(status_code=403, detail="Not authorized to view this driver's bids")
    query = db.query(RideBid).options(
        joinedload(RideBid.driver)
    ).filter(RideBid.driver_id == driver_id)

    # Filter by time window
    cutoff = datetime.utcnow() - timedelta(days=days)
    query = query.filter(RideBid.created_at >= cutoff)

    if status:
        try:
            status_enum = BidStatus(status)
            query = query.filter(RideBid.status == status_enum)
        except ValueError:
            pass

    bids = query.order_by(RideBid.created_at.desc()).limit(50).all()

    # Include ride request info and count active rides
    result = []
    active_rides_count = 0
    for bid in bids:
        bid_data = serialize_bid(bid)
        if bid.ride_request:
            bid_data["ride_request"] = serialize_ride_request(bid.ride_request)
        result.append(bid_data)

        # Count bids where driver is actively matched on a live ride
        if bid.status == BidStatus.ACCEPTED and bid.ride_request and \
           bid.ride_request.status in (RideRequestStatus.MATCHED, RideRequestStatus.IN_PROGRESS):
            active_rides_count += 1

    return {
        "success": True,
        "bids": result,
        "active_rides_count": active_rides_count
    }


# =========================================================================
# RIDE LIFECYCLE
# =========================================================================

@router.post("/request/{request_id}/arrived")
async def driver_arrived(request_id: int, request: Request, auth_driver: Driver = Depends(require_driver), db: Session = Depends(get_db)):
    """Mark that the driver has arrived at pickup location. Requires driver auth (matched driver)."""
    ride_request = db.query(RideRequest).filter(RideRequest.id == request_id).first()
    if not ride_request:
        raise HTTPException(status_code=404, detail="Ride request not found")

    # Only the matched driver can mark arrived
    if auth_driver.id != ride_request.matched_driver_id:
        raise HTTPException(status_code=403, detail="Only the matched driver can mark arrived")

    if ride_request.status != RideRequestStatus.MATCHED:
        raise HTTPException(status_code=400, detail=f"Ride must be matched first (current: {ride_request.status.value})")

    ride_request.driver_arrived_at = datetime.utcnow()

    # Insurance: Period 2 END + Period 3 START — passenger pickup
    try:
        from insurance.events import log_insurance_event, get_or_create_session_id
        _session_id = get_or_create_session_id(db, ride_request.matched_driver_id)
        log_insurance_event(
            db=db, driver_id=ride_request.matched_driver_id, trip_type="rideshare",
            trip_id=ride_request.id, session_id=_session_id, period=2,
            event_type="period_end",
        )
        log_insurance_event(
            db=db, driver_id=ride_request.matched_driver_id, trip_type="rideshare",
            trip_id=ride_request.id, session_id=_session_id, period=3,
            event_type="period_start",
        )
    except Exception as e:
        logging.warning(f"Insurance event (driver arrived) failed: {e}")

    # In-app notification: driver arrived
    driver = db.query(Driver).filter(Driver.id == ride_request.matched_driver_id).first()
    driver_name = f"{driver.first_name}".strip() if driver and driver.first_name else "Your driver"
    _notify_customer(db, ride_request.customer_id,
                     "Driver Arrived",
                     f"{driver_name} is at the pickup location. Head out to meet them.",
                     "ride", ride_request.id, "ride")

    db.commit()

    # Send push notification to customer - DRIVER ARRIVED
    try:
        customer = db.query(Customer).filter(Customer.id == ride_request.customer_id).first()
        driver = db.query(Driver).filter(Driver.id == ride_request.matched_driver_id).first()
        if customer:
            driver_name = "Your driver"
            if driver:
                driver_name = f"{driver.first_name}".strip() or "Your driver"

            send_push_notification(
                user_type="customer",
                user_id=ride_request.customer_id,
                title="Your driver has arrived!",
                body=f"{driver_name} is at the pickup location. Head out to meet them.",
                data={
                    "type": "driver_arrived",
                    "ride_request_id": str(ride_request.id),
                    "request_id": ride_request.request_id,
                    "pickup_address": ride_request.pickup_address
                },
                db=db
            )
            logger.info(f"Push notification sent to customer {ride_request.customer_id} - driver arrived")
    except Exception as e:
        logger.error(f"Failed to send driver arrived notification: {e}")

    # Broadcast ride status via WebSocket
    try:
        asyncio.create_task(broadcast_ride_status(
            ride_id=str(ride_request.id),
            status="driver_arrived",
            details={"ride_request_id": ride_request.id, "request_id": ride_request.request_id}
        ))
    except Exception as e:
        logger.error(f"WebSocket broadcast error: {e}")

    return {
        "success": True,
        "message": "Driver arrived at pickup",
        "ride_request": serialize_ride_request(ride_request)
    }


class DriverCancelRequest(BaseModel):
    reason: Optional[str] = None

@router.post("/request/{request_id}/driver-cancel")
async def driver_cancel_ride(request_id: int, request: Request, data: DriverCancelRequest = DriverCancelRequest(), auth_driver: Driver = Depends(require_driver), db: Session = Depends(get_db)):
    """Driver cancels a matched ride before starting it. Requires driver auth (matched driver)."""
    ride_request = db.query(RideRequest).filter(RideRequest.id == request_id).first()
    if not ride_request:
        raise HTTPException(status_code=404, detail="Ride request not found")

    # Only the matched driver can cancel
    if auth_driver.id != ride_request.matched_driver_id:
        raise HTTPException(status_code=403, detail="Only the matched driver can cancel")

    if ride_request.status not in [RideRequestStatus.MATCHED]:
        raise HTTPException(status_code=400, detail=f"Can only cancel matched rides (current: {ride_request.status.value})")

    # Cancel Stripe PaymentIntent if one was created
    if ride_request.stripe_payment_intent_id and not ride_request.stripe_payment_intent_id.startswith("demo_"):
        try:
            import stripe
            import os
            stripe.api_key = os.getenv("STRIPE_SECRET_KEY")
            stripe.PaymentIntent.cancel(
                ride_request.stripe_payment_intent_id,
                idempotency_key=f"ride-cancel-{ride_request.id}"
            )
            ride_request.stripe_payment_intent_id = None
            logger.info(f"Ride {ride_request.id} PaymentIntent cancelled on driver cancel")
        except Exception as e:
            logger.error(f"Ride {ride_request.id} PaymentIntent cancel failed: {e}")

    # Revert ride to OPEN so other drivers can bid
    ride_request.status = RideRequestStatus.OPEN
    cancelled_driver_id = ride_request.matched_driver_id
    ride_request.matched_driver_id = None
    ride_request.matched_at = None
    ride_request.driver_arrived_at = None

    # Expire the matched bid
    matched_bid = db.query(RideBid).filter(
        and_(
            RideBid.ride_request_id == request_id,
            RideBid.driver_id == cancelled_driver_id,
            RideBid.status == BidStatus.ACCEPTED
        )
    ).first()
    if matched_bid:
        matched_bid.status = BidStatus.WITHDRAWN
        matched_bid.customer_response = f"Driver cancelled: {data.reason or 'No reason provided'}"

    # Increment cancel count + send threshold push warnings
    cancelling_driver = db.query(Driver).filter(Driver.id == cancelled_driver_id).first()
    if cancelling_driver:
        cancelling_driver.ride_cancel_count = (cancelling_driver.ride_cancel_count or 0) + 1
        total = (cancelling_driver.ride_accept_count or 0) + (cancelling_driver.ride_cancel_count or 0)
        if total >= 10:  # Enough data to compute a meaningful rate
            cancel_rate = cancelling_driver.ride_cancel_count / total
            if cancel_rate >= 0.30:
                try:
                    send_push_notification(
                        user_type="driver",
                        user_id=cancelled_driver_id,
                        title="High cancellation rate",
                        body=f"Your cancel rate is {cancel_rate*100:.0f}%. Frequent cancellations may affect your standing.",
                        data={"type": "cancel_rate_warning", "cancel_rate": str(round(cancel_rate * 100, 1))},
                        db=db
                    )
                except Exception:
                    pass
            elif cancel_rate >= 0.20:
                try:
                    send_push_notification(
                        user_type="driver",
                        user_id=cancelled_driver_id,
                        title="Cancellation reminder",
                        body=f"You've cancelled {cancelling_driver.ride_cancel_count} of your last {total} rides. Try to reduce cancellations.",
                        data={"type": "cancel_rate_warning", "cancel_rate": str(round(cancel_rate * 100, 1))},
                        db=db
                    )
                except Exception:
                    pass

    db.commit()

    # Notify customer that driver cancelled
    try:
        customer = db.query(Customer).filter(Customer.id == ride_request.customer_id).first()
        driver = db.query(Driver).filter(Driver.id == cancelled_driver_id).first()
        if customer:
            driver_name = "Your driver"
            if driver:
                driver_name = f"{driver.first_name}".strip() or "Your driver"

            send_push_notification(
                user_type="customer",
                user_id=ride_request.customer_id,
                title="Driver cancelled",
                body=f"{driver_name} had to cancel. We're finding you another driver.",
                data={
                    "type": "ride_cancelled",
                    "ride_request_id": str(ride_request.id),
                    "request_id": ride_request.request_id,
                    "reason": data.reason or ""
                },
                db=db
            )
    except Exception as e:
        logger.error(f"Failed to send driver cancel notification: {e}")

    # WebSocket broadcast: ride reopened after driver cancel
    try:
        asyncio.create_task(broadcast_ride_status(
            ride_id=str(ride_request.id),
            status="driver_cancelled",
            details={"ride_request_id": ride_request.id, "request_id": ride_request.request_id, "reason": data.reason or ""}
        ))
    except Exception as e:
        logger.error(f"WebSocket broadcast error: {e}")

    return {
        "success": True,
        "message": "Ride cancelled by driver. Ride re-opened for other drivers.",
        "reason": data.reason
    }



@router.post("/request/{request_id}/no-show")
async def mark_passenger_no_show(request_id: int, request: Request, auth_driver: Driver = Depends(require_driver), db: Session = Depends(get_db)):
    """Driver marks passenger as no-show. Requires driver auth (matched driver)."""
    ride_request = db.query(RideRequest).filter(RideRequest.id == request_id).first()
    if not ride_request:
        raise HTTPException(status_code=404, detail="Ride request not found")

    # Only the matched driver can mark no-show
    if auth_driver.id != ride_request.matched_driver_id:
        raise HTTPException(status_code=403, detail="Only the matched driver can mark no-show")

    if ride_request.status != RideRequestStatus.MATCHED:
        raise HTTPException(status_code=400, detail=f"Ride must be in matched status (current: {ride_request.status.value})")

    # Verify driver has arrived (must have arrived before marking no-show)
    if not ride_request.driver_arrived_at:
        raise HTTPException(status_code=400, detail="You must arrive at pickup first before marking no-show")

    # Verify wait time (minimum 5 minutes after arrival)
    wait_seconds = (datetime.utcnow() - ride_request.driver_arrived_at).total_seconds()
    noshow_wait = pricing_engine.config.NOSHOW_WAIT_SECONDS
    if wait_seconds < noshow_wait:
        remaining = int(noshow_wait - wait_seconds)
        raise HTTPException(
            status_code=400,
            detail=f"Please wait {remaining} more seconds before marking no-show (minimum {noshow_wait // 60} minutes)"
        )

    # Cancel the ride with no-show flag
    ride_request.status = RideRequestStatus.CANCELLED
    ride_request.cancelled_at = datetime.utcnow()

    # Apply cancellation fee to customer
    cancellation_fee = pricing_engine.config.NOSHOW_FEE
    ride_request.platform_fee = cancellation_fee

    # Pay driver a portion for their time
    ride_request.driver_payout = round(cancellation_fee * pricing_engine.config.NOSHOW_DRIVER_SHARE, 2)

    db.commit()

    charge_succeeded = False
    # --- Stripe no-show fee charge (non-blocking) ---
    try:
        import stripe, os
        stripe.api_key = os.getenv("STRIPE_SECRET_KEY")

        # Step 1: Cancel the original pre-auth PaymentIntent (full fare amount)
        if ride_request.stripe_payment_intent_id and not ride_request.stripe_payment_intent_id.startswith("demo_"):
            try:
                stripe.PaymentIntent.cancel(
                    ride_request.stripe_payment_intent_id,
                    idempotency_key=f"ride-noshow-cancel-{ride_request.id}"
                )
                logger.info(f"Ride {ride_request.id} pre-auth cancelled for no-show")
            except Exception as cancel_err:
                # Intent may already be cancelled or in uncancellable state — log and continue
                logger.warning(f"Ride {ride_request.id} pre-auth cancel warning: {cancel_err}")
            ride_request.stripe_payment_intent_id = None
            db.commit()

        # Step 2: Charge customer $5.00 via new PaymentIntent (off-session, requires saved default PM)
        customer_obj = db.query(Customer).filter(Customer.id == ride_request.customer_id).first()
        stripe_customer_id = getattr(customer_obj, 'stripe_customer_id', None) if customer_obj else None

        # Resolve default payment_method ID from saved_cards JSON
        # saved_cards schema (models.py:640): [{id, brand, last4, exp_month, exp_year, is_default}]
        default_pm_id = None
        if customer_obj and customer_obj.saved_cards:
            for card in (customer_obj.saved_cards or []):
                if card.get('is_default'):
                    default_pm_id = card.get('id')
                    break

        if stripe_customer_id and default_pm_id:
            try:
                fee_intent = stripe.PaymentIntent.create(
                    amount=500,  # $5.00 in cents
                    currency="usd",
                    customer=stripe_customer_id,
                    payment_method=default_pm_id,
                    description=f"No-show fee — Ride {ride_request.request_id}",
                    confirm=True,
                    off_session=True,
                    idempotency_key=f"ride-noshow-fee-{ride_request.id}"
                )
                ride_request.stripe_payment_intent_id = fee_intent.id
                ride_request.payment_status = "captured"
                db.commit()
                logger.info(f"Ride {ride_request.id} no-show fee $5.00 charged, intent {fee_intent.id}")
                charge_succeeded = True

                # Step 3: Pay driver $4.00 via Stripe Connect transfer
                matched_driver = db.query(Driver).filter(Driver.id == ride_request.matched_driver_id).first()
                if matched_driver and getattr(matched_driver, 'stripe_account_id', None) and getattr(matched_driver, 'stripe_onboarded', False):
                    if not ride_request.stripe_transfer_id:
                        transfer = stripe.Transfer.create(
                            amount=400,  # $4.00 in cents
                            currency="usd",
                            destination=matched_driver.stripe_account_id,
                            description=f"No-show compensation — Ride {ride_request.request_id}",
                            metadata={"ride_id": str(ride_request.id), "type": "noshow_compensation"},
                            idempotency_key=f"ride-noshow-xfer-{ride_request.id}"
                        )
                        ride_request.stripe_transfer_id = transfer.id
                        ride_request.driver_paid_at = datetime.utcnow()
                        db.commit()
                        logger.info(f"Ride {ride_request.id} no-show driver compensation $4.00 transferred to {matched_driver.stripe_account_id}")
                    else:
                        logger.info(f"Ride {ride_request.id} driver transfer already exists, skipping")
                else:
                    logger.info(f"Ride {ride_request.id} driver not Stripe-onboarded — skipping Connect transfer")

            except (stripe.error.CardError, stripe.error.InvalidRequestError) as stripe_charge_err:
                # Card declined, requires_action, or no default PM attached to Stripe customer object
                # Either way: no-show is recorded, flag for manual follow-up
                logger.warning(f"Ride {ride_request.id} no-show charge failed ({type(stripe_charge_err).__name__}): {stripe_charge_err} — flagged for manual review")
                ride_request.payment_status = "manual_review"
                db.commit()
                # Notify customer: charge failed
                send_push_notification(
                    user_type="customer",
                    user_id=ride_request.customer_id,
                    title="No-show fee couldn't be collected",
                    body="We were unable to charge the $5.00 no-show fee. Please ensure you have a valid payment method on file. Our team will follow up.",
                    data={"type": "noshow_charge_failed", "ride_request_id": str(ride_request.id), "request_id": ride_request.request_id},
                    db=db
                )
                _notify_customer(
                    db, ride_request.customer_id,
                    "No-show fee couldn't be collected",
                    f"We couldn't charge the $5.00 no-show fee for ride {ride_request.request_id}. Please add a valid payment method. Our support team will follow up.",
                    notification_type="payment",
                    reference_id=ride_request.id,
                    reference_type="ride"
                )
                # Auto-create P1 support ticket for manual follow-up
                try:
                    last_ticket = db.query(SupportTicket).order_by(SupportTicket.id.desc()).first()
                    next_ticket_num = (last_ticket.id + 1) if last_ticket else 1
                    support_ticket = SupportTicket(
                        ticket_id=f"DOLLOR-{next_ticket_num}",
                        title=f"No-show charge failed — Ride {ride_request.request_id}",
                        description=f"Stripe charge for $5.00 no-show fee failed ({type(stripe_charge_err).__name__}) on ride {ride_request.request_id}. Customer ID: {ride_request.customer_id}. Manual collection required.",
                        ticket_type=TicketType.SUPPORT,
                        priority=TicketPriority.P1_HIGH,
                        status=TicketStatus.OPEN,
                        customer_id=ride_request.customer_id,
                        driver_id=ride_request.matched_driver_id,
                        component="Payment",
                        labels=["no-show", "payment-failed"],
                        reporter="system"
                    )
                    db.add(support_ticket)
                    db.commit()
                    logger.info(f"Ride {ride_request.id} no-show charge failure — support ticket {support_ticket.ticket_id} created")
                except Exception as ticket_err:
                    logger.warning(f"Ride {ride_request.id} failed to create support ticket: {ticket_err}")
        else:
            # No stripe_customer_id OR no default card in saved_cards — log for manual follow-up
            reason = "no stripe_customer_id" if not stripe_customer_id else "no default card in saved_cards"
            logger.warning(f"Ride {ride_request.id} no-show: {reason} — flagged for manual review")
            ride_request.payment_status = "manual_review"
            db.commit()
            # Notify customer: charge failed
            send_push_notification(
                user_type="customer",
                user_id=ride_request.customer_id,
                title="No-show fee couldn't be collected",
                body="We were unable to charge the $5.00 no-show fee. Please ensure you have a valid payment method on file. Our team will follow up.",
                data={"type": "noshow_charge_failed", "ride_request_id": str(ride_request.id), "request_id": ride_request.request_id},
                db=db
            )
            _notify_customer(
                db, ride_request.customer_id,
                "No-show fee couldn't be collected",
                f"We couldn't charge the $5.00 no-show fee for ride {ride_request.request_id}. Please add a valid payment method. Our support team will follow up.",
                notification_type="payment",
                reference_id=ride_request.id,
                reference_type="ride"
            )
            # Auto-create P1 support ticket for manual follow-up
            try:
                last_ticket = db.query(SupportTicket).order_by(SupportTicket.id.desc()).first()
                next_ticket_num = (last_ticket.id + 1) if last_ticket else 1
                support_ticket = SupportTicket(
                    ticket_id=f"DOLLOR-{next_ticket_num}",
                    title=f"No-show charge failed — Ride {ride_request.request_id}",
                    description=f"No-show $5.00 fee could not be charged ({reason}) for ride {ride_request.request_id}. Customer ID: {ride_request.customer_id}. Manual collection required.",
                    ticket_type=TicketType.SUPPORT,
                    priority=TicketPriority.P1_HIGH,
                    status=TicketStatus.OPEN,
                    customer_id=ride_request.customer_id,
                    driver_id=ride_request.matched_driver_id,
                    component="Payment",
                    labels=["no-show", "payment-failed"],
                    reporter="system"
                )
                db.add(support_ticket)
                db.commit()
                logger.info(f"Ride {ride_request.id} no-show charge failure ({reason}) — support ticket {support_ticket.ticket_id} created")
            except Exception as ticket_err:
                logger.warning(f"Ride {ride_request.id} failed to create support ticket: {ticket_err}")

    except Exception as e:
        # Non-blocking: no-show is already recorded in DB, Stripe failure should not undo it
        logger.error(f"Ride {ride_request.id} no-show Stripe processing error: {e}")

    # Notify customer
    try:
        customer = db.query(Customer).filter(Customer.id == ride_request.customer_id).first()
        driver = db.query(Driver).filter(Driver.id == ride_request.matched_driver_id).first()
        if customer:
            driver_name = "Your driver"
            if driver:
                driver_name = f"{driver.first_name}".strip() or "Your driver"

            send_push_notification(
                user_type="customer",
                user_id=ride_request.customer_id,
                title="Ride cancelled — No show",
                body=f"{driver_name} waited at the pickup but you didn't show up. A ${cancellation_fee:.2f} fee has been applied." if charge_succeeded else f"{driver_name} waited at the pickup but you didn't show up. We couldn't process the no-show fee — our team will follow up.",
                data={
                    "type": "ride_cancelled",
                    "ride_request_id": str(ride_request.id),
                    "request_id": ride_request.request_id,
                    "reason": "passenger_no_show",
                    "cancellation_fee": str(cancellation_fee)
                },
                db=db
            )
    except Exception as e:
        logger.error(f"Failed to send no-show notification: {e}")

    # WebSocket broadcast: passenger no-show
    try:
        asyncio.create_task(broadcast_ride_status(
            ride_id=str(ride_request.id),
            status="passenger_no_show",
            details={"ride_request_id": ride_request.id, "request_id": ride_request.request_id, "cancellation_fee": cancellation_fee}
        ))
    except Exception as e:
        logger.error(f"WebSocket broadcast error: {e}")

    return {
        "success": True,
        "message": "Passenger marked as no-show. Cancellation fee applied.",
        "cancellation_fee": cancellation_fee,
        "driver_payout": ride_request.driver_payout
    }


@router.post("/request/{request_id}/start")
async def start_ride(request_id: int, request: Request, auth_driver: Driver = Depends(require_driver), db: Session = Depends(get_db)):
    """Start the matched ride (driver picked up customer). Requires driver auth (matched driver)."""
    ride_request = db.query(RideRequest).filter(RideRequest.id == request_id).first()
    if not ride_request:
        raise HTTPException(status_code=404, detail="Ride request not found")

    # Only the matched driver can start the ride
    if auth_driver.id != ride_request.matched_driver_id:
        raise HTTPException(status_code=403, detail="Only the matched driver can start the ride")

    if ride_request.status != RideRequestStatus.MATCHED:
        raise HTTPException(status_code=400, detail=f"Ride must be matched first (current: {ride_request.status.value})")

    # Auto-set driver_arrived_at if the /arrived call was missed (e.g. silent API failure)
    if not ride_request.driver_arrived_at:
        ride_request.driver_arrived_at = datetime.utcnow()

    ride_request.status = RideRequestStatus.IN_PROGRESS

    # In-app notification: ride started
    _notify_customer(db, ride_request.customer_id,
                     "Ride Started",
                     "Your ride is in progress. Enjoy the trip!",
                     "ride", ride_request.id, "ride")

    db.commit()

    # Send ride started email to customer
    try:
        customer = db.query(Customer).filter(Customer.id == ride_request.customer_id).first()
        driver = db.query(Driver).filter(Driver.id == ride_request.matched_driver_id).first()
        if customer and customer.email and driver:
            _bg_email("send_ride_started_email",
                to_email=customer.email,
                customer_name=f"{customer.first_name} {customer.last_name}".strip() or "Customer",
                request_id=ride_request.request_id,
                driver_name=f"{driver.first_name} {driver.last_name}",
                pickup_address=ride_request.pickup_address,
                dropoff_address=ride_request.dropoff_address,
                estimated_duration_minutes=ride_request.estimated_duration_minutes or 15,
                final_price=ride_request.final_price
            )
            logger.info(f"Ride started email sent to {customer.email}")
    except Exception as e:
        logger.error(f"Failed to send ride started email: {e}")

    # Send push notification to customer - RIDE STARTED
    try:
        customer = db.query(Customer).filter(Customer.id == ride_request.customer_id).first()
        driver = db.query(Driver).filter(Driver.id == ride_request.matched_driver_id).first()
        if customer:
            driver_name = "Your driver"
            if driver:
                driver_name = f"{driver.first_name}".strip() or "Your driver"

            eta_minutes = ride_request.estimated_duration_minutes or 15
            send_push_notification(
                user_type="customer",
                user_id=ride_request.customer_id,
                title="You're on your way!",
                body=f"{driver_name} picked you up. ETA to destination: ~{eta_minutes} min",
                data={
                    "type": "ride_started",
                    "ride_request_id": str(ride_request.id),
                    "request_id": ride_request.request_id,
                    "dropoff_address": ride_request.dropoff_address
                },
                db=db
            )
            logger.info(f"Push notification sent to customer {ride_request.customer_id} - ride started")
    except Exception as e:
        logger.error(f"Failed to send push notification to customer: {e}")

    # WebSocket broadcast: ride started
    try:
        asyncio.create_task(broadcast_ride_status(
            ride_id=str(ride_request.id),
            status="in_progress",
            details={"ride_request_id": ride_request.id, "request_id": ride_request.request_id}
        ))
    except Exception as e:
        logger.error(f"WebSocket broadcast error: {e}")

    return {
        "success": True,
        "message": "Ride started",
        "ride_request": serialize_ride_request(ride_request)
    }


@router.post("/request/{request_id}/complete")
async def complete_ride(request_id: int, request: Request, auth_driver: Driver = Depends(require_driver), db: Session = Depends(get_db)):
    """Complete the ride (driver dropped off customer). Requires driver auth (matched driver)."""
    ride_request = db.query(RideRequest).filter(RideRequest.id == request_id).first()
    if not ride_request:
        raise HTTPException(status_code=404, detail="Ride request not found")

    # Only the matched driver can complete the ride
    if auth_driver.id != ride_request.matched_driver_id:
        raise HTTPException(status_code=403, detail="Only the matched driver can complete the ride")

    # Auto-advance MATCHED→IN_PROGRESS if driver somehow skipped the /start call
    # (e.g. app went to Maps before the API round-trip completed).
    if ride_request.status == RideRequestStatus.MATCHED:
        ride_request.status = RideRequestStatus.IN_PROGRESS
        if not ride_request.driver_arrived_at:
            ride_request.driver_arrived_at = datetime.utcnow()
        db.flush()

    if ride_request.status != RideRequestStatus.IN_PROGRESS:
        raise HTTPException(status_code=400, detail=f"Ride must be in progress first (current: {ride_request.status.value})")

    ride_request.status = RideRequestStatus.COMPLETED
    ride_request.completed_at = datetime.utcnow()

    # Insurance: Period 3 END — ride complete
    try:
        from insurance.events import log_insurance_event, get_or_create_session_id
        _session_id = get_or_create_session_id(db, ride_request.matched_driver_id)
        log_insurance_event(
            db=db, driver_id=ride_request.matched_driver_id, trip_type="rideshare",
            trip_id=ride_request.id, session_id=_session_id, period=3,
            event_type="period_end",
        )
    except Exception as e:
        logging.warning(f"Insurance event (ride complete) failed: {e}")

    # Calculate and persist platform fee + driver payout (fare-tiered Model A)
    final_price = float(ride_request.final_price or ride_request.suggested_price or 0)
    platform_fee = platform_fee_for(final_price)
    ride_request.platform_fee = platform_fee
    driver_a4a_share = pricing_engine.config.ACCESS_FOR_ALL_DRIVER_SHARE  # TNC-13
    ride_request.driver_payout = round(final_price - platform_fee - driver_a4a_share, 2)

    # Prop 22: compute per-ride floor data (non-blocking — failure must not block ride completion)
    try:
        from prop22_utils import calculate_prop22_ride_data
        _p22 = calculate_prop22_ride_data(ride_request, db)
        if _p22:
            ride_request.prop22_engaged_hours = _p22["prop22_engaged_hours"]
            ride_request.prop22_engaged_miles = _p22["prop22_engaged_miles"]
            ride_request.prop22_floor_amount = _p22["prop22_floor_amount"]
    except Exception as _e:
        logger.error(f"Prop 22 ride calculation failed (non-blocking): {_e}")

    # 1099-NEC threshold check (non-blocking)
    try:
        from email_service import get_driver_ytd_earnings, send_1099_threshold_alert_email
        from sqlalchemy import extract as sqla_extract
        _ytd = get_driver_ytd_earnings(db, ride_request.matched_driver_id, datetime.utcnow().year)
        if _ytd >= 600:
            # Dedup: check if 1099 alert already sent this year
            from models_extended import Communication, CommunicationChannel
            _existing_1099 = db.query(Communication).filter(
                Communication.recipient_id == ride_request.matched_driver_id,
                Communication.template_name == "1099_threshold_alert",
                Communication.channel == CommunicationChannel.EMAIL,
                sqla_extract('year', Communication.sent_at) == datetime.utcnow().year,
            ).first()
            if not _existing_1099:
                _driver_1099 = db.query(Driver).filter(Driver.id == ride_request.matched_driver_id).first()
                if _driver_1099 and _driver_1099.email:
                    send_1099_threshold_alert_email(
                        driver_email=_driver_1099.email,
                        driver_name=f"{_driver_1099.first_name} {_driver_1099.last_name}".strip(),
                        ytd_earnings=_ytd,
                    )
                    logger.info(f"1099 threshold alert sent to driver {ride_request.matched_driver_id} (YTD=${_ytd:.2f})")
    except Exception as _e:
        logger.error(f"1099 threshold check failed (non-blocking): {_e}")

    # In-app notification: ride completed
    _notify_customer(db, ride_request.customer_id,
                     "Ride Complete",
                     f"You've arrived! Your fare was ${final_price:.2f}. Rate your driver to help improve the community.",
                     "ride", ride_request.id, "ride")

    db.commit()

    # Capture the customer's PaymentIntent (authorized at bid acceptance)
    try:
        import stripe
        import os
        stripe.api_key = os.getenv("STRIPE_SECRET_KEY")

        if ride_request.stripe_payment_intent_id and not ride_request.stripe_payment_intent_id.startswith("demo_"):
            stripe.PaymentIntent.capture(
                ride_request.stripe_payment_intent_id,
                idempotency_key=f"ride-capture-{ride_request.id}"
            )
            ride_request.payment_status = "captured"
            ride_request.payment_completed_at = datetime.utcnow()
            db.commit()
            logger.info(f"Ride {ride_request.id} PaymentIntent {ride_request.stripe_payment_intent_id} captured")
    except Exception as e:
        logger.error(f"Ride {ride_request.id} PaymentIntent capture failed (non-blocking): {e}")
        try:
            ride_request.payment_status = "capture_failed"
            ride_request.payment_retry_count = (ride_request.payment_retry_count or 0) + 1
            db.commit()
        except Exception as db_err:
            logger.error(f"Ride {ride_request.id} failed to write capture_failed status: {db_err}")
            db.rollback()

    # Auto-trigger driver payout via Stripe Connect (non-blocking)
    # Skip payout if capture failed — payout requires a successful charge source
    if ride_request.payment_status == "capture_failed":
        logger.warning(f"Ride {ride_request.id} skipping driver payout — capture failed")
    else:
        try:
            import stripe
            import os
            stripe.api_key = os.getenv("STRIPE_SECRET_KEY")

            # Demo rides: skip Stripe, just mark payment status
            if ride_request.stripe_payment_intent_id and ride_request.stripe_payment_intent_id.startswith("demo_"):
                ride_request.payment_status = "demo"
                ride_request.payment_completed_at = datetime.utcnow()
                db.commit()
                logger.info(f"Ride {ride_request.id} is demo — skipping Stripe payout")
            else:
                driver = db.query(Driver).filter(Driver.id == ride_request.matched_driver_id).first()
                if driver and getattr(driver, 'stripe_account_id', None) and getattr(driver, 'stripe_onboarded', False):
                    # Idempotency: skip if transfer already created
                    if ride_request.stripe_transfer_id:
                        logger.info(f"Ride {ride_request.id} transfer already exists ({ride_request.stripe_transfer_id}), skipping")
                    else:
                        payout_cents = int(ride_request.driver_payout * 100)
                        if payout_cents > 0:
                            transfer = stripe.Transfer.create(
                                amount=payout_cents,
                                currency="usd",
                                destination=driver.stripe_account_id,
                                description=f"Ride {ride_request.request_id} payout",
                                metadata={
                                    "ride_id": str(ride_request.id),
                                    "ride_request_id": ride_request.request_id,
                                    "driver_id": str(driver.id),
                                    "fare": str(final_price),
                                    "platform_fee": str(platform_fee),
                                },
                                idempotency_key=f"ride_xfer_{ride_request.id}"
                            )
                            ride_request.stripe_transfer_id = transfer.id
                            ride_request.driver_paid_at = datetime.utcnow()
                            db.commit()
                            logger.info(f"Ride {ride_request.id} auto-payout ${ride_request.driver_payout:.2f} to driver {driver.id}")

                            # Push notification to driver — payment received
                            try:
                                send_push_notification(
                                    user_type="driver",
                                    user_id=driver.id,
                                    title="Payment Received!",
                                    body=f"${ride_request.driver_payout:.2f} from ride {ride_request.request_id} has been transferred to your account.",
                                    data={
                                        "type": "payment_processed",
                                        "ride_request_id": str(ride_request.id),
                                        "request_id": ride_request.request_id,
                                        "amount": str(ride_request.driver_payout)
                                    },
                                    db=db
                                )
                            except Exception as e:
                                logger.error(f"Failed to send payment push to driver: {e}")
                else:
                    logger.info(f"Ride {ride_request.id} driver not Stripe-onboarded, skipping auto-payout")
                    # Notify driver to complete payout setup — they earned money but can't receive it yet
                    if driver:
                        try:
                            send_push_notification(
                                user_type="driver",
                                user_id=driver.id,
                                title="Complete your payout setup",
                                body=f"You earned ${ride_request.driver_payout:.2f} on ride {ride_request.request_id}. Connect your bank account to receive payments.",
                                data={
                                    "type": "payout_setup_required",
                                    "ride_request_id": str(ride_request.id),
                                    "request_id": ride_request.request_id,
                                    "amount": str(ride_request.driver_payout)
                                },
                                db=db
                            )
                        except Exception as e:
                            logger.error(f"Failed to send payout setup push to driver: {e}")
        except Exception as e:
            logger.error(f"Ride {ride_request.id} auto-payout failed (non-blocking): {e}")

    # Send ride completed email with receipt to customer
    try:
        customer = db.query(Customer).filter(Customer.id == ride_request.customer_id).first()
        driver = db.query(Driver).filter(Driver.id == ride_request.matched_driver_id).first()
        if customer and customer.email and driver:
            # Convert km to miles for receipt
            distance_miles = (ride_request.estimated_distance_km or 0) * 0.621371

            _bg_email("send_ride_completed_email",
                to_email=customer.email,
                customer_name=f"{customer.first_name} {customer.last_name}".strip() or "Customer",
                request_id=ride_request.request_id,
                driver_name=f"{driver.first_name} {driver.last_name}",
                pickup_address=ride_request.pickup_address,
                dropoff_address=ride_request.dropoff_address,
                final_price=final_price,
                platform_fee=platform_fee,
                distance_miles=round(distance_miles, 1),
                duration_minutes=ride_request.estimated_duration_minutes or 15
            )
            logger.info(f"Ride completed email sent to {customer.email}")
    except Exception as e:
        logger.error(f"Failed to send ride completed email: {e}")

    # Send push notification to customer - RIDE COMPLETED
    try:
        customer = db.query(Customer).filter(Customer.id == ride_request.customer_id).first()
        driver = db.query(Driver).filter(Driver.id == ride_request.matched_driver_id).first()
        if customer:
            driver_name = "Your driver"
            if driver:
                driver_name = f"{driver.first_name} {driver.last_name}".strip() or "Your driver"

            _push_price = float(ride_request.final_price or 0)
            send_push_notification(
                user_type="customer",
                user_id=ride_request.customer_id,
                title="Ride Complete!",
                body=f"You've arrived! Total: ${_push_price:.2f}. Rate {driver_name} and add a tip.",
                data={
                    "type": "ride_completed",
                    "ride_request_id": str(ride_request.id),
                    "request_id": ride_request.request_id,
                    "final_price": str(final_price),
                    "driver_name": driver_name
                },
                db=db
            )
            logger.info(f"Push notification sent to customer {ride_request.customer_id} - ride completed")
    except Exception as e:
        logger.error(f"Failed to send push notification to customer: {e}")

    # WebSocket broadcast: ride completed
    try:
        asyncio.create_task(broadcast_ride_status(
            ride_id=str(ride_request.id),
            status="completed",
            details={"ride_request_id": ride_request.id, "request_id": ride_request.request_id, "final_price": str(ride_request.final_price)}
        ))
    except Exception as e:
        logger.error(f"WebSocket broadcast error: {e}")

    return {
        "success": True,
        "message": "Ride completed",
        "ride_request": serialize_ride_request(ride_request),
        "final_price": ride_request.final_price
    }


# =========================================================================
# FARE ESTIMATE ENDPOINTS - Competitive Pricing
# =========================================================================

class FareEstimateInput(BaseModel):
    """Input for fare estimate calculation"""
    pickup_latitude: float = Field(..., ge=-90, le=90)
    pickup_longitude: float = Field(..., ge=-180, le=180)
    dropoff_latitude: float = Field(..., ge=-90, le=90)
    dropoff_longitude: float = Field(..., ge=-180, le=180)
    ride_type: str = "standard"


@router.post("/estimate")
async def get_fare_estimate_endpoint(request: Request, data: FareEstimateInput, db: Session = Depends(get_db)):
    """
    Get fare estimate with full breakdown and driver suggestions.

    Returns competitive market-rate pricing with:
    - Detailed fare breakdown
    - Platform fee (transparent, $1-3 flat)
    - Suggested bid prices for drivers
    - Driver earnings information
    - Bid comparison labels for customers
    - Surge/demand multiplier info
    """
    check_rate_limit(request, _public_estimate_rate_limiter, "public_fare_estimate")
    # Calculate distance
    distance_km = calculate_distance_km(
        data.pickup_latitude, data.pickup_longitude,
        data.dropoff_latitude, data.dropoff_longitude
    )

    # Estimate duration
    duration_minutes = estimate_duration_minutes(distance_km)

    # Get full fare estimate
    estimate = get_fare_estimate(
        distance_km=distance_km,
        duration_minutes=duration_minutes
    )

    # Calculate demand/surge multiplier from live data
    surge_multiplier, surge_label = calculate_demand_multiplier(db)

    # Apply ride type multiplier to suggested bids
    multiplier = 1.0
    if data.ride_type == "premium":
        multiplier = 1.5
    elif data.ride_type == "xl":
        multiplier = 1.25

    # Combine ride type and surge multipliers
    combined_multiplier = multiplier * surge_multiplier

    if combined_multiplier != 1.0:
        estimate["subtotal"] = round(estimate["subtotal"] * combined_multiplier, 2)
        estimate["total"] = round(estimate["total"] * combined_multiplier, 2)
        estimate["driver_info"]["earnings"] = round(estimate["driver_info"]["earnings"] * combined_multiplier, 2)
        for bid in estimate["suggested_bids"]:
            bid["price"] = round(bid["price"] * combined_multiplier, 2)
            bid["driver_earnings"] = round(bid["driver_earnings"] * combined_multiplier, 2)

    estimate["ride_type"] = data.ride_type
    estimate["distance_km"] = round(distance_km, 2)

    # Add surge info to estimate
    estimate["surge_multiplier"] = surge_multiplier
    estimate["surge_label"] = surge_label
    estimate["is_surging"] = surge_multiplier > 1.0

    return {
        "success": True,
        "estimate": estimate
    }


@router.get("/estimate/bid-label")
async def get_bid_label_endpoint(bid_price: float, fare_estimate: float, _auth: dict = Depends(require_any_auth)):
    """
    Get comparison label for a bid price vs fare estimate.

    Returns:
    - label: "Great Deal", "Good Value", "Fair Price", "Above Average", "Premium"
    - description: Explanation of the label
    - color: Suggested UI color (green, blue, orange, gray)
    """
    label_info = get_bid_label(bid_price, fare_estimate)
    return {
        "success": True,
        **label_info
    }


@router.get("/pricing/tiers")
async def get_pricing_tiers(_auth: dict = Depends(require_any_auth)):
    """
    Get current pricing tier information.

    Dollor.ai uses flat platform fees ($1-3) instead of percentage-based
    commissions (unlike industry-standard 25-30%).

    This means:
    - Riders pay less
    - Drivers earn more
    - Transparent pricing
    """
    return {
        "success": True,
        "tiers": [
            {
                "tier": 1,
                "fare_range": "Up to $35",
                "platform_fee": 1.00,
                "driver_keeps": "97%+"
            },
            {
                "tier": 2,
                "fare_range": "$35.01 - $70",
                "platform_fee": 2.00,
                "driver_keeps": "97%+"
            },
            {
                "tier": 3,
                "fare_range": "Above $70",
                "platform_fee": 3.00,
                "driver_keeps": "96%+"
            }
        ],
        "comparison": {
            "dollor_ai": {
                "fee_type": "Flat fee ($1-3)",
                "driver_keeps": "96-97%",
                "transparent": True
            },
            "industry_average": {
                "fee_type": "Percentage (25-30%)",
                "driver_keeps": "70-75%",
                "transparent": False
            }
        },
        "messaging": {
            "customer": "Pay fair market rates. 96% goes directly to your driver.",
            "driver": "Keep 96%+ of every fare. No commission cuts. Your price, your earnings."
        }
    }


class PassengerRatingRequest(BaseModel):
    rating: int  # 1-5 stars
    comment: Optional[str] = None


@router.post("/request/{request_id}/rate-passenger")
async def rate_passenger(
    request_id: int,
    body: PassengerRatingRequest,
    request: Request,
    auth_driver: Driver = Depends(require_driver),
    db: Session = Depends(get_db)
):
    """Driver rates passenger after ride completion. Requires driver auth (matched driver)."""
    ride_request = db.query(RideRequest).filter(RideRequest.id == request_id).first()
    if not ride_request:
        raise HTTPException(status_code=404, detail="Ride request not found")

    # Only the matched driver can rate the passenger
    if auth_driver.id != ride_request.matched_driver_id:
        raise HTTPException(status_code=403, detail="Only the matched driver can rate the passenger")

    if ride_request.status != RideRequestStatus.COMPLETED:
        raise HTTPException(
            status_code=400,
            detail=f"Can only rate completed rides (current: {ride_request.status.value})"
        )

    if ride_request.passenger_rating is not None:
        raise HTTPException(status_code=400, detail="Passenger already rated for this ride")

    rating = body.rating
    if rating < 1 or rating > 5:
        raise HTTPException(status_code=400, detail="Rating must be between 1 and 5")

    # Store rating on ride
    ride_request.passenger_rating = rating
    ride_request.passenger_comment = body.comment

    # Update customer's average rating
    customer = db.query(Customer).filter(Customer.id == ride_request.customer_id).first()
    if customer:
        current_rating = customer.rating or 5.0
        total_rides = customer.total_rides or 0
        new_rating = round(((current_rating * total_rides) + rating) / (total_rides + 1), 2)
        customer.rating = new_rating
        customer.total_rides = total_rides + 1

    db.commit()

    return {
        "success": True,
        "message": "Passenger rated successfully",
        "ride_id": request_id,
        "rating": rating,
        "newPassengerRating": customer.rating if customer else None
    }


# =========================================================================
# T2-5: RIDE RECEIPT / INVOICE
# =========================================================================

import os as _os
from jose import jwt as _jwt

_JWT_SECRET = _os.getenv("JWT_SECRET_KEY", "")


def _require_auth(request: Request) -> dict:
    """Require JWT auth and return decoded payload. Raises 401 on failure."""
    if not _JWT_SECRET:
        raise HTTPException(status_code=500, detail="Server misconfiguration")
    auth_header = request.headers.get("authorization", "")
    if not auth_header.startswith("Bearer "):
        raise HTTPException(status_code=401, detail="Authentication required")
    try:
        payload = _jwt.decode(auth_header[7:], _JWT_SECRET, algorithms=["HS256"])
        return payload
    except Exception:
        raise HTTPException(status_code=401, detail="Invalid or expired token")



@router.get("/request/{request_id}/receipt")
async def get_ride_receipt(request_id: int, request: Request, _auth: dict = Depends(require_any_auth), db: Session = Depends(get_db)):
    """Get full receipt for a completed ride. Requires auth."""
    ride = db.query(RideRequest).filter(RideRequest.id == request_id).first()
    if not ride:
        raise HTTPException(status_code=404, detail="Ride request not found")

    if ride.status != RideRequestStatus.COMPLETED:
        raise HTTPException(status_code=400, detail="Receipt only available for completed rides")

    # SECURITY: Only ride participants or admin can view receipt
    jwt_customer_id = _auth.get("customer_id")
    jwt_driver_id = _auth.get("driver_id")
    jwt_role = _auth.get("role", "")
    if jwt_role != "admin" and jwt_customer_id != ride.customer_id and jwt_driver_id != ride.matched_driver_id:
        raise HTTPException(status_code=403, detail="Not authorized to view this receipt")

    driver = db.query(Driver).filter(Driver.id == ride.matched_driver_id).first() if ride.matched_driver_id else None

    final_price = float(ride.final_price or ride.suggested_price or 0)
    platform_fee = float(ride.platform_fee or 0)
    tip = float(ride.tip_amount or 0)
    driver_payout = float(ride.driver_payout or 0)
    distance_miles = (ride.estimated_distance_km or 0) * 0.621371

    return {
        "success": True,
        "receipt": {
            "ride_id": ride.id,
            "request_id": ride.request_id,
            "status": ride.status.value,
            "route": {
                "pickup_address": ride.pickup_address,
                "dropoff_address": ride.dropoff_address,
                "distance_miles": round(distance_miles, 1),
                "duration_minutes": ride.estimated_duration_minutes
            },
            "fare_breakdown": {
                "base_fare": final_price,
                "platform_fee": platform_fee,
                "access_for_all_fee": 0.10,
                "access_for_all_customer_share": 0.05,
                "access_for_all_driver_share": 0.05,
                "tip": tip,
                "total": round(final_price + platform_fee + 0.05 + tip, 2)
            },
            "payment": {
                "status": ride.payment_status or "pending",
                "paid_at": ride.payment_completed_at.isoformat() if ride.payment_completed_at else None
            },
            "driver": {
                "id": driver.id if driver else None,
                "name": (" ".join(filter(None, [driver.first_name, driver.last_name])).strip() or "Driver") if driver else None,
                "photo_url": driver.photo_url if driver else None,
                "rating": driver.rating if driver else None,
                "vehicle": f"{driver.vehicle_year or ''} {driver.vehicle_make or ''} {driver.vehicle_model or ''}".strip() if driver else None,
                "license_plate": driver.license_plate if driver else None
            },
            "timestamps": {
                "requested_at": ride.created_at.isoformat() if ride.created_at else None,
                "matched_at": ride.matched_at.isoformat() if ride.matched_at else None,
                "completed_at": ride.completed_at.isoformat() if ride.completed_at else None
            },
            "rating": {
                "customer_rating": ride.customer_rating,
                "customer_comment": ride.customer_comment
            },
            "regulatory": {
                "zero_tolerance_policy": "Dollor.ai maintains a zero-tolerance policy for drug and alcohol use by drivers. If you suspect your driver was under the influence, please report immediately.",
                "report_safety_concern": {
                    "dollor_email": "support@dollor.ai",
                    "dollor_phone": "Report via app or email"
                },
                "cpuc_consumer_complaint": {
                    "phone": "1-800-894-9444",
                    "email": "CIU_intake@cpuc.ca.gov",
                    "note": "California Public Utilities Commission Consumer Intake Unit"
                },
                "access_for_all_fee": "$0.10 per trip collected for the CPUC Access for All Fund"
            }
        }
    }


@router.post("/request/{request_id}/email-receipt")
async def email_ride_receipt(request_id: int, request: Request, _auth: dict = Depends(require_any_auth), db: Session = Depends(get_db)):
    """Re-send ride completion email with receipt. Requires auth (ride participant)."""
    ride = db.query(RideRequest).filter(RideRequest.id == request_id).first()
    if not ride:
        raise HTTPException(status_code=404, detail="Ride request not found")

    if ride.status != RideRequestStatus.COMPLETED:
        raise HTTPException(status_code=400, detail="Receipt only available for completed rides")

    # Ownership check -- only ride participants or admin
    jwt_customer_id = _auth.get("customer_id")
    jwt_driver_id = _auth.get("driver_id")
    jwt_role = _auth.get("role", "")
    if jwt_role != "admin" and jwt_customer_id != ride.customer_id and jwt_driver_id != ride.matched_driver_id:
        raise HTTPException(status_code=403, detail="Not authorized")

    customer = db.query(Customer).filter(Customer.id == ride.customer_id).first()
    driver = db.query(Driver).filter(Driver.id == ride.matched_driver_id).first() if ride.matched_driver_id else None

    if not customer or not customer.email:
        raise HTTPException(status_code=400, detail="Customer email not available")

    final_price = float(ride.final_price or ride.suggested_price or 0)
    platform_fee = float(ride.platform_fee or 0)
    distance_miles = (ride.estimated_distance_km or 0) * 0.621371

    customer_name = " ".join(filter(None, [customer.first_name, customer.last_name])).strip() or "Customer"
    sent = send_ride_completed_email(
        to_email=customer.email,
        customer_name=customer_name,
        request_id=ride.request_id,
        driver_name=(" ".join(filter(None, [driver.first_name, driver.last_name])).strip() or "Driver") if driver else "Driver",
        pickup_address=ride.pickup_address,
        dropoff_address=ride.dropoff_address,
        final_price=final_price,
        platform_fee=platform_fee,
        distance_miles=round(distance_miles, 1),
        duration_minutes=ride.estimated_duration_minutes or 15
    )

    return {"success": sent, "message": "Receipt email sent" if sent else "Failed to send email"}


# =========================================================================
# TNC-15: DIGITAL WAYBILL (CPUC Compliance)
# =========================================================================

@router.get("/request/{request_id}/waybill")
async def get_ride_waybill(request_id: int, request: Request, _auth: dict = Depends(require_any_auth), db: Session = Depends(get_db)):
    """TNC-15: Digital waybill for active/completed rides. Driver must have this during trip.
    Contains all CPUC-required trip information for TNC compliance."""
    ride = db.query(RideRequest).filter(RideRequest.id == request_id).first()
    if not ride:
        raise HTTPException(status_code=404, detail="Ride request not found")

    # SECURITY: Only ride participants or admin
    jwt_driver_id = _auth.get("driver_id")
    jwt_customer_id = _auth.get("customer_id")
    jwt_role = _auth.get("role", "")
    if jwt_role != "admin" and jwt_customer_id != ride.customer_id and jwt_driver_id != ride.matched_driver_id:
        raise HTTPException(status_code=403, detail="Not authorized to view this waybill")

    driver = db.query(Driver).filter(Driver.id == ride.matched_driver_id).first() if ride.matched_driver_id else None

    return {
        "success": True,
        "waybill": {
            "tnc_operator": {
                "carrier_name": "Zietra Technologies inc",
                "dba": "Dollor.ai",
                "permit_type": "TCP-P TNC",
                "permit_number": None  # To be filled after CPUC issues permit
            },
            "trip_id": ride.request_id,
            "status": ride.status.value,
            "passenger": {
                "name": ride.customer_name,
                "phone": ride.customer_phone
            },
            "driver": {
                "name": f"{driver.first_name} {driver.last_name}".strip() if driver else None,
                "license_number": driver.license_number if driver else None,
                "vehicle": f"{driver.vehicle_year or ''} {driver.vehicle_make or ''} {driver.vehicle_model or ''}".strip() if driver else None,
                "license_plate": driver.license_plate if driver else None
            },
            "route": {
                "pickup_address": ride.pickup_address,
                "pickup_time": ride.matched_at.isoformat() if ride.matched_at else None,
                "dropoff_address": ride.dropoff_address,
                "dropoff_time": ride.completed_at.isoformat() if ride.completed_at else None
            },
            "fare": {
                "amount": float(ride.final_price or ride.suggested_price or 0),
                "platform_fee": float(ride.platform_fee or 0),
                "access_for_all_fee": 0.10,
                "payment_method": "card"
            },
            "accessibility_requested": getattr(ride, 'accessibility_requested', False),
            "prearranged": True,  # All TNC rides are prearranged by definition
            "created_at": ride.created_at.isoformat() if ride.created_at else None
        }
    }


# =========================================================================
# T2-6: DRIVER PAYOUT DASHBOARD
# =========================================================================

@router.get("/driver/{driver_id}/payout-history")
async def get_driver_payout_history(
    driver_id: int,
    request: Request,
    period: Optional[str] = "week",
    start_date: Optional[str] = None,
    end_date: Optional[str] = None,
    auth_driver: Driver = Depends(require_driver),
    db: Session = Depends(get_db)
):
    """Get per-ride payout breakdown for a driver. Requires driver auth + ownership."""
    if auth_driver.id != driver_id:
        raise HTTPException(status_code=403, detail="Not authorized to view this driver's payouts")

    # Determine date range
    now = datetime.utcnow()
    if start_date and end_date:
        try:
            start = datetime.fromisoformat(start_date)
            end = datetime.fromisoformat(end_date)
        except ValueError:
            raise HTTPException(status_code=400, detail="Invalid date format. Use ISO format.")
    elif period == "today":
        start = now.replace(hour=0, minute=0, second=0, microsecond=0)
        end = now
    elif period == "week":
        start = now - timedelta(days=7)
        end = now
    elif period == "month":
        start = now - timedelta(days=30)
        end = now
    else:
        start = now - timedelta(days=7)
        end = now

    # Query completed rides for this driver in the period
    rides = db.query(RideRequest).filter(
        and_(
            RideRequest.matched_driver_id == driver_id,
            RideRequest.status == RideRequestStatus.COMPLETED,
            RideRequest.completed_at >= start,
            RideRequest.completed_at <= end
        )
    ).order_by(RideRequest.completed_at.desc()).all()

    # Build per-ride breakdown
    ride_items = []
    total_gross = 0.0
    total_fees = 0.0
    total_tips = 0.0
    total_net = 0.0

    for ride in rides:
        fare = float(ride.final_price or ride.suggested_price or 0)
        fee = float(ride.platform_fee or 0)
        tip = float(ride.tip_amount or 0)
        net = float(ride.driver_payout or 0) + tip

        total_gross += fare
        total_fees += fee
        total_tips += tip
        total_net += net

        stripe_status = "paid" if ride.driver_paid_at else ("demo" if ride.payment_status == "demo" else "pending")

        ride_items.append({
            "ride_id": ride.id,
            "request_id": ride.request_id,
            "date": ride.completed_at.isoformat() if ride.completed_at else None,
            "pickup_address": ride.pickup_address,
            "dropoff_address": ride.dropoff_address,
            "fare": fare,
            "platform_fee": fee,
            "tip": tip,
            "net_payout": round(net, 2),
            "stripe_status": stripe_status
        })

    ride_count = len(rides)
    avg_per_ride = round(total_net / ride_count, 2) if ride_count > 0 else 0

    return {
        "success": True,
        "period": period,
        "start_date": start.isoformat(),
        "end_date": end.isoformat(),
        "summary": {
            "total_gross": round(total_gross, 2),
            "total_fees": round(total_fees, 2),
            "total_tips": round(total_tips, 2),
            "total_net": round(total_net, 2),
            "ride_count": ride_count,
            "avg_per_ride": avg_per_ride
        },
        "rides": ride_items
    }


# =========================================================================
# T2-7: PAYMENT DISPUTE / REFUND
# =========================================================================

class CreateDisputeInput(BaseModel):
    ride_request_id: int
    reason: str  # DisputeReason value
    description: Optional[str] = None


@router.post("/dispute")
async def create_ride_dispute(
    data: CreateDisputeInput,
    request: Request,
    customer: Customer = Depends(require_customer),
    db: Session = Depends(get_db)
):
    """Customer creates a dispute for a completed ride. Requires customer auth."""
    # Verify ride exists and is completed
    ride = db.query(RideRequest).filter(RideRequest.id == data.ride_request_id).first()
    if not ride:
        raise HTTPException(status_code=404, detail="Ride request not found")

    if ride.status != RideRequestStatus.COMPLETED:
        raise HTTPException(status_code=400, detail="Can only dispute completed rides")

    # Only ride's customer can dispute
    if customer.id != ride.customer_id:
        raise HTTPException(status_code=403, detail="Only the ride's customer can create a dispute")

    # Validate reason
    try:
        reason_enum = DisputeReason(data.reason)
    except ValueError:
        raise HTTPException(
            status_code=400,
            detail=f"Invalid reason. Valid: {[r.value for r in DisputeReason]}"
        )

    # Check for existing dispute on this ride
    existing = db.query(RideDispute).filter(
        RideDispute.ride_request_id == data.ride_request_id
    ).first()
    if existing:
        raise HTTPException(status_code=400, detail="A dispute already exists for this ride")

    _strip = lambda t: re.sub(r'<[^>]+>', '', t).strip() if t and isinstance(t, str) else t
    dispute = RideDispute(
        ride_request_id=data.ride_request_id,
        customer_id=ride.customer_id,
        reason=reason_enum,
        description=_strip(data.description),
        status=DisputeStatus.SUBMITTED
    )
    db.add(dispute)
    db.commit()
    db.refresh(dispute)

    return {
        "success": True,
        "message": "Dispute submitted successfully. We'll review within 24-48 hours.",
        "dispute": {
            "id": dispute.id,
            "ride_request_id": dispute.ride_request_id,
            "reason": dispute.reason.value,
            "description": dispute.description,
            "status": dispute.status.value,
            "created_at": dispute.created_at.isoformat()
        }
    }


@router.get("/dispute/{dispute_id}")
async def get_dispute_status(dispute_id: int, request: Request, _auth: dict = Depends(require_any_auth), db: Session = Depends(get_db)):
    """Get dispute status. Requires auth (dispute owner or admin)."""
    dispute = db.query(RideDispute).filter(RideDispute.id == dispute_id).first()
    if not dispute:
        raise HTTPException(status_code=404, detail="Dispute not found")

    jwt_customer_id = _auth.get("customer_id")
    jwt_role = _auth.get("role", "")
    if jwt_role != "admin" and jwt_customer_id != dispute.customer_id:
        raise HTTPException(status_code=403, detail="Not authorized to view this dispute")

    result = {
        "id": dispute.id,
        "ride_request_id": dispute.ride_request_id,
        "reason": dispute.reason.value,
        "description": dispute.description,
        "status": dispute.status.value,
        "refund_amount": dispute.refund_amount,
        "resolved_at": dispute.resolved_at.isoformat() if dispute.resolved_at else None,
        "created_at": dispute.created_at.isoformat(),
        "updated_at": dispute.updated_at.isoformat()
    }
    # Only include admin_notes for admin users
    if _auth.get("role") == "admin":
        result["admin_notes"] = dispute.admin_notes

    return {"success": True, "dispute": result}


@router.get("/customer/{customer_id}/disputes")
async def get_customer_disputes(customer_id: int, request: Request, customer: Customer = Depends(require_customer), db: Session = Depends(get_db)):
    """List all disputes for a customer. Requires customer auth + ownership."""
    if customer.id != customer_id:
        raise HTTPException(status_code=403, detail="Not authorized to view these disputes")
    disputes = db.query(RideDispute).filter(
        RideDispute.customer_id == customer_id
    ).order_by(RideDispute.created_at.desc()).all()

    return {
        "success": True,
        "disputes": [{
            "id": d.id,
            "ride_request_id": d.ride_request_id,
            "reason": d.reason.value,
            "status": d.status.value,
            "refund_amount": d.refund_amount,
            "created_at": d.created_at.isoformat()
        } for d in disputes]
    }


class ResolveDisputeInput(BaseModel):
    resolution: str  # "refund" or "no_refund"
    refund_amount: Optional[float] = None
    admin_notes: Optional[str] = None


@router.post("/dispute/{dispute_id}/resolve")
async def resolve_dispute(dispute_id: int, data: ResolveDisputeInput, request: Request, _auth: dict = Depends(require_any_auth), db: Session = Depends(get_db)):
    """Admin resolves a dispute. Optionally issues a Stripe refund. Requires admin auth."""
    jwt_role = _auth.get("role", "")
    if jwt_role != "admin":
        raise HTTPException(status_code=403, detail="Only admins can resolve disputes")

    dispute = db.query(RideDispute).filter(RideDispute.id == dispute_id).first()
    if not dispute:
        raise HTTPException(status_code=404, detail="Dispute not found")

    if dispute.status.value not in ("submitted", "under_review"):
        raise HTTPException(status_code=400, detail=f"Dispute already resolved (status: {dispute.status.value})")

    if data.resolution == "refund":
        ride = db.query(RideRequest).filter(RideRequest.id == dispute.ride_request_id).first()
        refund_amount = data.refund_amount or (float(ride.final_price or 0) if ride else 0)
        if refund_amount <= 0:
            raise HTTPException(status_code=400, detail="Refund amount must be greater than $0")

        # Attempt Stripe refund if payment intent exists
        stripe_refund_id = None
        if ride and ride.stripe_payment_intent_id and not ride.stripe_payment_intent_id.startswith("demo_"):
            try:
                import stripe as stripe_lib
                import os
                stripe_lib.api_key = os.getenv("STRIPE_SECRET_KEY")
                refund = stripe_lib.Refund.create(
                    payment_intent=ride.stripe_payment_intent_id,
                    amount=int(refund_amount * 100),
                    metadata={"dispute_id": str(dispute_id), "ride_id": str(ride.id)}
                )
                stripe_refund_id = refund.id
                logger.info(f"Stripe refund {refund.id} created for dispute {dispute_id}")
            except Exception as e:
                logger.error(f"Stripe refund failed for dispute {dispute_id}: {e}")
                raise HTTPException(status_code=500, detail="Refund processing failed. Please try again or contact support.")

        dispute.status = DisputeStatus.RESOLVED_REFUND
        dispute.refund_amount = refund_amount
        dispute.stripe_refund_id = stripe_refund_id
    elif data.resolution == "no_refund":
        dispute.status = DisputeStatus.RESOLVED_NO_REFUND
    else:
        raise HTTPException(status_code=400, detail="Resolution must be 'refund' or 'no_refund'")

    dispute.admin_notes = data.admin_notes
    dispute.resolved_at = datetime.utcnow()
    db.commit()

    # Notify customer of resolution
    try:
        if data.resolution == "refund":
            msg = f"Your dispute has been resolved. A refund of ${dispute.refund_amount:.2f} has been issued."
        else:
            msg = "Your dispute has been reviewed. After careful review, no refund will be issued."
        send_push_notification(
            user_type="customer",
            user_id=dispute.customer_id,
            title="Dispute Resolved",
            body=msg,
            data={"type": "dispute_resolved", "dispute_id": str(dispute_id), "resolution": data.resolution},
            db=db
        )
    except Exception as e:
        logger.error(f"Failed to send dispute resolution notification: {e}")

    return {
        "success": True,
        "message": f"Dispute resolved: {data.resolution}",
        "dispute": {
            "id": dispute.id,
            "status": dispute.status.value,
            "refund_amount": dispute.refund_amount,
            "stripe_refund_id": dispute.stripe_refund_id,
            "admin_notes": dispute.admin_notes,
            "resolved_at": dispute.resolved_at.isoformat()
        }
    }


# =========================================================================
# T2-8: RECURRING RIDE MATCHING
# =========================================================================

class CreateRecurringRideInput(BaseModel):
    pickup_address: str
    pickup_latitude: float
    pickup_longitude: float
    dropoff_address: str
    dropoff_latitude: float
    dropoff_longitude: float
    schedule_days: str  # "mon,wed,fri"
    schedule_time: str  # "08:30"
    timezone: Optional[str] = "America/New_York"
    preferred_driver_id: Optional[int] = None
    max_price: Optional[float] = None
    ride_type: Optional[str] = "standard"


class UpdateRecurringRideInput(BaseModel):
    schedule_days: Optional[str] = None
    schedule_time: Optional[str] = None
    preferred_driver_id: Optional[int] = None
    max_price: Optional[float] = None
    is_active: Optional[bool] = None


def serialize_recurring_ride(r: RecurringRide) -> dict:
    return {
        "id": r.id,
        "customer_id": r.customer_id,
        "pickup_address": r.pickup_address,
        "pickup_latitude": r.pickup_latitude,
        "pickup_longitude": r.pickup_longitude,
        "dropoff_address": r.dropoff_address,
        "dropoff_latitude": r.dropoff_latitude,
        "dropoff_longitude": r.dropoff_longitude,
        "schedule_days": r.schedule_days,
        "schedule_time": r.schedule_time,
        "timezone": r.timezone,
        "preferred_driver_id": r.preferred_driver_id,
        "max_price": r.max_price,
        "ride_type": r.ride_type,
        "is_active": r.is_active,
        "last_triggered_at": r.last_triggered_at.isoformat() if r.last_triggered_at else None,
        "created_at": r.created_at.isoformat() if r.created_at else None
    }


@router.post("/customer/{customer_id}/recurring-rides")
async def create_recurring_ride(
    customer_id: int,
    data: CreateRecurringRideInput,
    request: Request,
    customer: Customer = Depends(require_customer),
    db: Session = Depends(get_db)
):
    """Create a recurring ride pattern. Requires customer auth + ownership."""
    if customer.id != customer_id:
        raise HTTPException(status_code=403, detail="Not authorized")

    # Limit recurring rides per customer
    existing_count = db.query(RecurringRide).filter(RecurringRide.customer_id == customer_id).count()
    if existing_count >= 20:
        raise HTTPException(status_code=400, detail="Maximum 20 recurring rides allowed")

    # Validate coordinates
    for name, val, lo, hi in [
        ("pickup_latitude", data.pickup_latitude, -90, 90),
        ("pickup_longitude", data.pickup_longitude, -180, 180),
        ("dropoff_latitude", data.dropoff_latitude, -90, 90),
        ("dropoff_longitude", data.dropoff_longitude, -180, 180),
    ]:
        if not (lo <= val <= hi):
            raise HTTPException(status_code=400, detail=f"Invalid {name}: must be between {lo} and {hi}")

    if data.max_price is not None and data.max_price <= 0:
        raise HTTPException(status_code=400, detail="max_price must be positive")

    # Validate schedule_days
    valid_days = {"mon", "tue", "wed", "thu", "fri", "sat", "sun"}
    days = [d.strip().lower() for d in data.schedule_days.split(",")]
    if not all(d in valid_days for d in days):
        raise HTTPException(status_code=400, detail=f"Invalid days. Use: {valid_days}")

    # Validate schedule_time format
    try:
        datetime.strptime(data.schedule_time, "%H:%M")
    except ValueError:
        raise HTTPException(status_code=400, detail="Invalid time format. Use HH:MM")

    _strip = lambda t: re.sub(r'<[^>]+>', '', t).strip() if t and isinstance(t, str) else t
    recurring = RecurringRide(
        customer_id=customer_id,
        pickup_address=_strip(data.pickup_address),
        pickup_latitude=data.pickup_latitude,
        pickup_longitude=data.pickup_longitude,
        dropoff_address=_strip(data.dropoff_address),
        dropoff_latitude=data.dropoff_latitude,
        dropoff_longitude=data.dropoff_longitude,
        schedule_days=",".join(days),
        schedule_time=data.schedule_time,
        timezone=data.timezone,
        preferred_driver_id=data.preferred_driver_id,
        max_price=data.max_price,
        ride_type=data.ride_type
    )
    db.add(recurring)
    db.commit()
    db.refresh(recurring)

    return {
        "success": True,
        "message": "Recurring ride created",
        "recurring_ride": serialize_recurring_ride(recurring)
    }


@router.get("/customer/{customer_id}/recurring-rides")
async def get_customer_recurring_rides(customer_id: int, request: Request, customer: Customer = Depends(require_customer), db: Session = Depends(get_db)):
    """List all recurring rides for a customer. Requires customer auth + ownership."""
    if customer.id != customer_id:
        raise HTTPException(status_code=403, detail="Not authorized")
    rides = db.query(RecurringRide).filter(
        RecurringRide.customer_id == customer_id
    ).order_by(RecurringRide.created_at.desc()).all()

    return {
        "success": True,
        "recurring_rides": [serialize_recurring_ride(r) for r in rides]
    }


@router.put("/recurring-rides/{ride_id}")
async def update_recurring_ride(
    ride_id: int,
    data: UpdateRecurringRideInput,
    request: Request,
    customer: Customer = Depends(require_customer),
    db: Session = Depends(get_db)
):
    """Update a recurring ride pattern. Requires customer auth + ownership."""
    recurring = db.query(RecurringRide).filter(RecurringRide.id == ride_id).first()
    if not recurring:
        raise HTTPException(status_code=404, detail="Recurring ride not found")
    # Ownership check
    if customer.id != recurring.customer_id:
        raise HTTPException(status_code=403, detail="Not authorized")

    if data.schedule_days is not None:
        valid_days = {"mon", "tue", "wed", "thu", "fri", "sat", "sun"}
        days = [d.strip().lower() for d in data.schedule_days.split(",")]
        if not all(d in valid_days for d in days):
            raise HTTPException(status_code=400, detail=f"Invalid days. Use: {valid_days}")
        recurring.schedule_days = ",".join(days)

    if data.schedule_time is not None:
        try:
            datetime.strptime(data.schedule_time, "%H:%M")
        except ValueError:
            raise HTTPException(status_code=400, detail="Invalid time format. Use HH:MM")
        recurring.schedule_time = data.schedule_time

    if data.preferred_driver_id is not None:
        recurring.preferred_driver_id = data.preferred_driver_id
    if data.max_price is not None:
        if data.max_price <= 0:
            raise HTTPException(status_code=400, detail="max_price must be positive")
        recurring.max_price = data.max_price
    if data.is_active is not None:
        recurring.is_active = data.is_active

    db.commit()

    return {
        "success": True,
        "message": "Recurring ride updated",
        "recurring_ride": serialize_recurring_ride(recurring)
    }


@router.delete("/recurring-rides/{ride_id}")
async def delete_recurring_ride(ride_id: int, request: Request, customer: Customer = Depends(require_customer), db: Session = Depends(get_db)):
    """Delete a recurring ride pattern. Requires customer auth + ownership."""
    recurring = db.query(RecurringRide).filter(RecurringRide.id == ride_id).first()
    if not recurring:
        raise HTTPException(status_code=404, detail="Recurring ride not found")
    # Ownership check
    if customer.id != recurring.customer_id:
        raise HTTPException(status_code=403, detail="Not authorized")

    db.delete(recurring)
    db.commit()

    return {"success": True, "message": "Recurring ride deleted"}


# ==================== ADMIN CLEANUP ====================

@router.post("/admin/cleanup-stale-rides")
async def admin_cleanup_stale_rides(
    request: Request,
    max_age_hours: int = 24,
    _auth: dict = Depends(require_any_auth),
    db: Session = Depends(get_db)
):
    """Admin endpoint to force-expire all stale OPEN/BIDDING rides older than max_age_hours."""
    jwt_role = _auth.get("role", "")
    if jwt_role != "admin":
        raise HTTPException(status_code=403, detail="Only admins can cleanup stale rides")

    now = datetime.utcnow()
    cutoff = now - timedelta(hours=max_age_hours)

    stale_rides = db.query(RideRequest).filter(
        RideRequest.status.in_([RideRequestStatus.OPEN, RideRequestStatus.BIDDING]),
        RideRequest.created_at < cutoff
    ).all()

    cleaned_count = 0
    for ride in stale_rides:
        ride.status = RideRequestStatus.EXPIRED
        ride.updated_at = now
        cleaned_count += 1

        # Expire pending bids
        pending_bids = db.query(RideBid).filter(
            RideBid.ride_request_id == ride.id,
            RideBid.status == BidStatus.PENDING
        ).all()
        for bid in pending_bids:
            bid.status = BidStatus.EXPIRED
            bid.updated_at = now

    db.commit()

    return {
        "success": True,
        "cleaned_rides": cleaned_count,
        "max_age_hours": max_age_hours,
        "cutoff_time": cutoff.isoformat()
    }


# ==================== RIDE TIMEOUT / CLEANUP JOBS ====================
# These run as background scheduler jobs (registered in order_flow.py)

# Configurable timeouts
RIDE_BIDDING_EXPIRY_MINUTES = 5       # OPEN/BIDDING rides auto-expire after bidding window closes
RIDE_MATCHED_TIMEOUT_MINUTES = 30     # MATCHED rides auto-cancel if driver doesn't arrive within 30 min
RIDE_IN_PROGRESS_TIMEOUT_HOURS = 2    # IN_PROGRESS rides flagged/cancelled if not completed in 2 hours
RIDE_CLEANUP_CHECK_INTERVAL_SECONDS = 60  # Check every 60 seconds


def check_ride_bidding_expiry_job():
    """
    Auto-expire OPEN/BIDDING rides whose bidding window has closed.
    Rides with bidding_expires_at in the past but still OPEN/BIDDING
    are transitioned to EXPIRED status.
    """
    db = SessionLocal()
    try:
        now = datetime.utcnow()
        expired_rides = db.query(RideRequest).filter(
            RideRequest.status.in_([RideRequestStatus.OPEN, RideRequestStatus.BIDDING]),
            RideRequest.bidding_expires_at.isnot(None),
            RideRequest.bidding_expires_at < now
        ).all()

        if not expired_rides:
            return

        expired_count = 0
        for ride in expired_rides:
            ride.status = RideRequestStatus.EXPIRED
            ride.updated_at = now
            expired_count += 1
            logger.info(
                f"Ride {ride.request_id} auto-expired: bidding window closed "
                f"({ride.bidding_expires_at.isoformat()})"
            )

            # Also expire any pending bids on this ride
            pending_bids = db.query(RideBid).filter(
                RideBid.ride_request_id == ride.id,
                RideBid.status == BidStatus.PENDING
            ).all()
            for bid in pending_bids:
                bid.status = BidStatus.EXPIRED
                bid.updated_at = now

            # Notify customer that ride expired with no match
            try:
                from order_flow import send_push_notification
                send_push_notification(
                    "customer",
                    ride.customer_id,
                    "No Drivers Available",
                    "No drivers were available for your ride. Please try again.",
                    {"type": "ride_expired", "ride_id": str(ride.id), "ride_request_id": ride.request_id or ""}
                )
            except Exception as push_err:
                logger.warning(f"Failed to send expiry push for ride {ride.request_id}: {push_err}")

        db.commit()
        logger.info(f"Ride bidding expiry check: {expired_count} rides expired")

        # Also expire stale rides with null bidding_expires_at (older than 30 min)
        stale_null_rides = db.query(RideRequest).filter(
            RideRequest.status.in_([RideRequestStatus.OPEN, RideRequestStatus.BIDDING]),
            RideRequest.bidding_expires_at.is_(None),
            RideRequest.created_at < now - timedelta(minutes=30)
        ).all()

        stale_count = 0
        for ride in stale_null_rides:
            ride.status = RideRequestStatus.EXPIRED
            ride.updated_at = now
            stale_count += 1
            logger.info(
                f"Ride {ride.request_id} auto-expired: null expiry, created "
                f"{ride.created_at.isoformat()} (stale > 30 min)"
            )

            # Also expire any pending bids on this ride
            pending_bids = db.query(RideBid).filter(
                RideBid.ride_request_id == ride.id,
                RideBid.status == BidStatus.PENDING
            ).all()
            for bid in pending_bids:
                bid.status = BidStatus.EXPIRED
                bid.updated_at = now

            # Notify customer that ride expired with no match
            try:
                from order_flow import send_push_notification
                send_push_notification(
                    "customer",
                    ride.customer_id,
                    "No Drivers Available",
                    "No drivers were available for your ride. Please try again.",
                    {"type": "ride_expired", "ride_id": str(ride.id), "ride_request_id": ride.request_id or ""}
                )
            except Exception as push_err:
                logger.warning(f"Failed to send expiry push for stale ride {ride.request_id}: {push_err}")

        if stale_count > 0:
            db.commit()
            logger.info(f"Stale null-expiry cleanup: {stale_count} rides expired")

    except Exception as e:
        logger.error(f"Error in ride bidding expiry check: {e}")
        db.rollback()
    finally:
        db.close()


def check_ride_matched_timeout_job():
    """
    Auto-cancel MATCHED rides where the driver hasn't started within 10 minutes.
    Reopens the ride for other drivers by resetting to OPEN status.
    Notifies the customer.
    """
    db = SessionLocal()
    try:
        now = datetime.utcnow()
        cutoff = now - timedelta(minutes=RIDE_MATCHED_TIMEOUT_MINUTES)

        stale_matched = db.query(RideRequest).filter(
            RideRequest.status == RideRequestStatus.MATCHED,
            RideRequest.matched_at.isnot(None),
            RideRequest.matched_at < cutoff,
            RideRequest.driver_arrived_at.is_(None)  # Driver never arrived
        ).all()

        if not stale_matched:
            return

        reopened_count = 0
        for ride in stale_matched:
            elapsed_min = (now - ride.matched_at).total_seconds() / 60

            # Reset ride to OPEN for other drivers
            old_driver_id = ride.matched_driver_id
            ride.status = RideRequestStatus.OPEN
            ride.matched_driver_id = None
            ride.matched_bid_id = None
            ride.final_price = None
            ride.matched_at = None
            ride.updated_at = now
            # Extend bidding window by 5 more minutes
            ride.bidding_expires_at = now + timedelta(minutes=RIDE_BIDDING_EXPIRY_MINUTES)
            reopened_count += 1

            # Mark the accepted bid as expired
            if old_driver_id:
                accepted_bid = db.query(RideBid).filter(
                    RideBid.ride_request_id == ride.id,
                    RideBid.driver_id == old_driver_id,
                    RideBid.status == BidStatus.ACCEPTED
                ).first()
                if accepted_bid:
                    accepted_bid.status = BidStatus.EXPIRED
                    accepted_bid.updated_at = now

            logger.info(
                f"Ride {ride.request_id} reopened: matched driver {old_driver_id} "
                f"didn't arrive after {elapsed_min:.0f} min (limit: {RIDE_MATCHED_TIMEOUT_MINUTES} min)"
            )

            # Send push notification to customer
            try:
                from order_flow import send_push_notification
                send_push_notification(
                    "customer",
                    ride.customer_id,
                    "Driver Unavailable",
                    "Your driver didn't respond in time. Your ride has been reopened for other drivers.",
                    {"type": "ride_reopened", "ride_id": str(ride.id)}
                )
            except Exception as push_err:
                logger.warning(f"Failed to send push for ride {ride.request_id}: {push_err}")

        db.commit()
        logger.info(f"Ride matched timeout check: {reopened_count} rides reopened")

        # Second pass: MATCHED rides where driver arrived but never started (>30 min)
        stale_arrived = db.query(RideRequest).filter(
            RideRequest.status == RideRequestStatus.MATCHED,
            RideRequest.driver_arrived_at.isnot(None),
            RideRequest.driver_arrived_at < now - timedelta(minutes=30)
        ).all()

        cancelled_count = 0
        for ride in stale_arrived:
            elapsed_min = (now - ride.driver_arrived_at).total_seconds() / 60
            old_driver_id = ride.matched_driver_id

            ride.status = RideRequestStatus.CANCELLED
            ride.cancelled_at = now
            ride.updated_at = now
            ride.cancellation_reason = "Auto-cancelled: driver arrived but never started ride within 30 minutes"
            cancelled_count += 1

            # Mark the accepted bid as expired
            if old_driver_id:
                accepted_bid = db.query(RideBid).filter(
                    RideBid.ride_request_id == ride.id,
                    RideBid.driver_id == old_driver_id,
                    RideBid.status == BidStatus.ACCEPTED
                ).first()
                if accepted_bid:
                    accepted_bid.status = BidStatus.EXPIRED
                    accepted_bid.updated_at = now

            logger.warning(
                f"Ride {ride.request_id} auto-cancelled: driver {old_driver_id} arrived "
                f"{elapsed_min:.0f} min ago but never started ride (limit: 30 min)"
            )

            # Notify both customer and driver
            try:
                from order_flow import send_push_notification
                send_push_notification(
                    "customer", ride.customer_id,
                    "Ride Cancelled",
                    "Your ride was automatically cancelled because the driver didn't start the trip. Please request a new ride.",
                    {"type": "ride_auto_cancelled", "ride_id": str(ride.id)}
                )
                if old_driver_id:
                    send_push_notification(
                        "driver", old_driver_id,
                        "Ride Cancelled",
                        "The ride was auto-cancelled because it was not started within 30 minutes of arrival.",
                        {"type": "ride_auto_cancelled", "ride_id": str(ride.id)}
                    )
            except Exception as push_err:
                logger.warning(f"Failed to send push for stale arrived ride {ride.request_id}: {push_err}")

        if cancelled_count > 0:
            db.commit()
            logger.info(f"Stale arrived ride cleanup: {cancelled_count} rides auto-cancelled")

    except Exception as e:
        logger.error(f"Error in ride matched timeout check: {e}")
        db.rollback()
    finally:
        db.close()


def check_ride_in_progress_timeout_job():
    """
    Auto-flag/cancel IN_PROGRESS rides that have been running for 2+ hours.
    These are likely abandoned — driver accepted but never completed.
    Cancels the ride and notifies admin for manual review.
    """
    db = SessionLocal()
    try:
        now = datetime.utcnow()
        cutoff = now - timedelta(hours=RIDE_IN_PROGRESS_TIMEOUT_HOURS)

        stale_rides = db.query(RideRequest).filter(
            RideRequest.status == RideRequestStatus.IN_PROGRESS,
            RideRequest.updated_at < cutoff
        ).all()

        if not stale_rides:
            return

        cancelled_count = 0
        for ride in stale_rides:
            elapsed_hours = (now - ride.updated_at).total_seconds() / 3600
            ride.status = RideRequestStatus.CANCELLED
            ride.cancelled_at = now
            ride.updated_at = now
            # Add a note about auto-cancellation
            note = f"[AUTO-CANCELLED] Ride in progress for {elapsed_hours:.1f} hours without completion."
            ride.special_requests = f"{ride.special_requests or ''}\n{note}".strip()
            cancelled_count += 1

            logger.warning(
                f"Ride {ride.request_id} auto-cancelled: in_progress for "
                f"{elapsed_hours:.1f} hours (limit: {RIDE_IN_PROGRESS_TIMEOUT_HOURS}h). "
                f"Driver: {ride.matched_driver_id}, Customer: {ride.customer_id}"
            )

            # Notify customer
            try:
                from order_flow import send_push_notification
                send_push_notification(
                    "customer",
                    ride.customer_id,
                    "Ride Cancelled",
                    "Your ride was automatically cancelled due to inactivity. Please request a new ride.",
                    {"type": "ride_auto_cancelled", "ride_id": str(ride.id)}
                )
            except Exception as push_err:
                logger.warning(f"Failed to send push for ride {ride.request_id}: {push_err}")

        db.commit()
        logger.info(f"Ride in-progress timeout check: {cancelled_count} rides auto-cancelled")

    except Exception as e:
        logger.error(f"Error in ride in-progress timeout check: {e}")
        db.rollback()
    finally:
        db.close()


def check_capture_retry_job():
    """Retry Stripe PaymentIntent capture for COMPLETED rides where capture failed or was skipped."""
    from sqlalchemy.orm import Session as SASession
    db: SASession = SessionLocal()
    try:
        import stripe, os
        stripe.api_key = os.getenv("STRIPE_SECRET_KEY")
        now = datetime.utcnow()
        MAX_RETRIES = 3

        # Find rides completed in the last 48 hours where capture did not succeed
        failed_rides = db.query(RideRequest).filter(
            RideRequest.status == RideRequestStatus.COMPLETED,
            (RideRequest.payment_status.is_(None)) | (RideRequest.payment_status == "capture_failed"),
            RideRequest.stripe_payment_intent_id.isnot(None),
            RideRequest.completed_at > now - timedelta(hours=48)
        ).all()

        for ride in failed_rides:
            # Skip demo rides
            if ride.stripe_payment_intent_id.startswith("demo_"):
                continue

            retry_count = ride.payment_retry_count or 0

            if retry_count >= MAX_RETRIES:
                if ride.payment_status != "capture_failed":
                    ride.payment_status = "capture_failed"
                    db.commit()
                # Block customer from new bookings until unpaid balance is resolved
                customer_record = db.query(Customer).filter(Customer.id == ride.customer_id).first()
                if customer_record and not customer_record.has_unpaid_balance:
                    customer_record.has_unpaid_balance = True
                    db.commit()
                    logger.warning(f"Customer {ride.customer_id} flagged has_unpaid_balance=True (ride {ride.id} retries exhausted)")
                logger.warning(f"Ride {ride.id} capture retry exhausted ({retry_count}/{MAX_RETRIES}) — flagged for manual review")
                continue

            try:
                # Idempotent: same key as original capture attempt
                stripe.PaymentIntent.capture(
                    ride.stripe_payment_intent_id,
                    idempotency_key=f"ride-capture-{ride.id}"
                )
                ride.payment_status = "captured"
                ride.payment_completed_at = datetime.utcnow()
                ride.payment_retry_count = retry_count + 1
                db.commit()
                logger.info(f"Ride {ride.id} capture retry succeeded on attempt {retry_count + 1}")
            except Exception as retry_err:
                ride.payment_retry_count = retry_count + 1
                ride.payment_status = "capture_failed"
                db.commit()
                logger.error(f"Ride {ride.id} capture retry {retry_count + 1}/{MAX_RETRIES} failed: {retry_err}")

    except Exception as e:
        logger.error(f"check_capture_retry_job error: {e}")
        db.rollback()
    finally:
        db.close()


def check_individual_bid_expiry_job():
    """Auto-expire individual bids whose expires_at has passed while still PENDING."""
    db = SessionLocal()
    try:
        now = datetime.utcnow()
        expired_bids = db.query(RideBid).filter(
            RideBid.status == BidStatus.PENDING,
            RideBid.expires_at.isnot(None),
            RideBid.expires_at < now
        ).all()

        if not expired_bids:
            return

        expired_count = 0
        for bid in expired_bids:
            bid.status = BidStatus.EXPIRED
            bid.updated_at = now
            expired_count += 1
            logger.info(f"Bid {bid.id} on ride {bid.ride_request_id} auto-expired (expires_at: {bid.expires_at.isoformat()})")

        db.commit()
        logger.info(f"Individual bid expiry check: {expired_count} bids expired")

    except Exception as e:
        logger.error(f"Error in individual bid expiry check: {e}")
        db.rollback()
    finally:
        db.close()
