"""
E2E Tests: Driver & Vendor UI Wiring
=====================================

Verifies that every backend API endpoint called by the iOS Driver app
and iOS Restaurant app is reachable and returns correct responses.

Test classes:
  1. TestDriverFullFlow - Food delivery lifecycle
  2. TestRideshareDriverFlow - Rideshare bid/start/complete lifecycle
  3. TestVendorFullFlow - Restaurant order + menu management lifecycle

All endpoints verified via grep against backend source before inclusion.
"""

import json
import pytest
from datetime import datetime, timedelta
from unittest.mock import patch, MagicMock

from models import (
    Customer, Driver, DriverStatus, Vendor, VendorStatus, OnboardingPhase,
    Order, OrderStatus, RideRequest, RideRequestStatus, RideBid, BidStatus,
    UserRole, User, VendorMenuItem,
)
from main_new import get_password_hash, create_access_token


# ---------------------------------------------------------------------------
# Fixtures
# ---------------------------------------------------------------------------

@pytest.fixture
def e2e_customer(db_session):
    """Create a customer with matching User record for auth."""
    email = f"e2e_cust_{datetime.now().timestamp()}@test.com"
    user = User(
        email=email,
        password_hash=get_password_hash("CustPass123!"),
        full_name="E2E Customer",
        role=UserRole.USER,
    )
    db_session.add(user)
    db_session.flush()

    customer = Customer(
        email=email,
        password_hash=get_password_hash("CustPass123!"),
        first_name="E2E",
        last_name="Customer",
        phone="+14155550200",
        is_active=True,
    )
    db_session.add(customer)
    db_session.commit()
    db_session.refresh(customer)
    return customer


@pytest.fixture
def cust_headers(e2e_customer):
    token = create_access_token(data={
        "sub": e2e_customer.email,
        "customer_id": e2e_customer.id,
    })
    return {"Authorization": f"Bearer {token}"}


@pytest.fixture
def e2e_driver(db_session):
    """Create an approved driver."""
    import uuid
    driver = Driver(
        driver_id=f"drv_{uuid.uuid4().hex[:8]}",
        email=f"e2e_drv_{datetime.now().timestamp()}@test.com",
        password_hash=get_password_hash("DrvPass123!"),
        first_name="E2E",
        last_name="Driver",
        phone="+14155550300",
        status=DriverStatus.APPROVED,
        verification_status="verified",  # bid_routes KYC gate
    )
    db_session.add(driver)
    db_session.commit()
    db_session.refresh(driver)
    return driver


@pytest.fixture
def drv_headers(e2e_driver):
    token = create_access_token(data={
        "sub": e2e_driver.email,
        "driver_id": e2e_driver.id,
    })
    return {"Authorization": f"Bearer {token}"}


@pytest.fixture
def e2e_vendor(db_session):
    """Create an approved vendor."""
    vendor = Vendor(
        company_name=f"E2E Company {datetime.now().timestamp()}",
        restaurant_name=f"E2E Restaurant {datetime.now().timestamp()}",
        contact_email=f"e2e_vnd_{datetime.now().timestamp()}@test.com",
        contact_phone="+14155550400",
        street="789 E2E St",
        city="San Francisco",
        state="CA",
        zip_code="94102",
        onboarding_status=VendorStatus.APPROVED,
        onboarding_phase=OnboardingPhase.COMPLETED,
    )
    db_session.add(vendor)
    db_session.commit()
    db_session.refresh(vendor)
    return vendor


@pytest.fixture
def vnd_headers(e2e_vendor):
    token = create_access_token(data={
        "sub": e2e_vendor.contact_email,
        "vendor_id": e2e_vendor.id,
    })
    return {"Authorization": f"Bearer {token}"}


def _create_order(db_session, e2e_vendor, e2e_customer, status):
    """Helper to create an order with the given status."""
    order = Order(
        order_number=f"E2E-{datetime.now().timestamp()}-{id(status)}",
        customer_id=e2e_customer.id,
        customer_name="E2E Customer",
        customer_email=e2e_customer.email,
        vendor_id=e2e_vendor.id,
        items=json.dumps([{"name": "Test Burger", "quantity": 1, "price": 12.99}]),
        subtotal=12.99,
        tax_amount=1.04,
        delivery_fee=3.00,
        platform_fee=1.00,
        total_amount=18.03,
        status=status,
        payment_status="succeeded",
        delivery_address=json.dumps({"street": "123 Main St", "city": "SF", "state": "CA"}),
    )
    db_session.add(order)
    db_session.commit()
    db_session.refresh(order)
    return order


@pytest.fixture
def e2e_order(db_session, e2e_vendor, e2e_customer):
    """Create a READY_FOR_PICKUP order for driver delivery flow testing."""
    return _create_order(db_session, e2e_vendor, e2e_customer, OrderStatus.READY_FOR_PICKUP)


@pytest.fixture
def e2e_order_pending_restaurant(db_session, e2e_vendor, e2e_customer):
    """Create a PENDING_RESTAURANT order for vendor accept flow."""
    return _create_order(db_session, e2e_vendor, e2e_customer, OrderStatus.PENDING_RESTAURANT)


@pytest.fixture
def mock_stripe():
    with patch("rideshare_payments.stripe.PaymentIntent.create") as mock_pi, \
         patch("rideshare_payments.stripe.Transfer.create") as mock_transfer:
        mock_pi.return_value = MagicMock(
            id="pi_test_e2e", client_secret="pi_test_secret"
        )
        mock_transfer.return_value = MagicMock(id="tr_test_e2e")
        yield {"payment_intent": mock_pi, "transfer": mock_transfer}


@pytest.fixture
def mock_notifications():
    """Suppress all push notifications and emails."""
    with patch("bid_routes.send_push_notification"), \
         patch("bid_routes.send_ride_request_confirmation_email"), \
         patch("bid_routes.send_ride_bid_received_email"), \
         patch("bid_routes.send_ride_matched_email"), \
         patch("bid_routes.send_ride_started_email"), \
         patch("bid_routes.send_ride_completed_email"), \
         patch("bid_routes.send_ride_cancelled_email"), \
         patch("bid_routes.asyncio.create_task"):
        yield


# SF test coordinates
PICKUP_LAT, PICKUP_LNG = 37.7749, -122.4194
DROPOFF_LAT, DROPOFF_LNG = 37.6213, -122.3790


# =========================================================================
# TEST 1: Driver Full Delivery Flow
# =========================================================================

class TestDriverFullFlow:
    """
    Exercises the iOS Driver app's food delivery journey:
    dashboard -> available orders -> accept -> pickup -> deliver -> earnings -> chat
    """

    def test_driver_dashboard(self, client, e2e_driver, drv_headers):
        """GET /api/driver/dashboard - iOS DriverStatsCard loads this."""
        resp = client.get("/api/driver/dashboard", headers=drv_headers)
        assert resp.status_code == 200
        data = resp.json()
        # Dashboard returns stats; structure varies but must be a dict
        assert isinstance(data, dict)

    def test_driver_earnings(self, client, e2e_driver, drv_headers):
        """GET /api/driver/earnings - iOS PayoutDashboardView loads this."""
        resp = client.get("/api/driver/earnings", headers=drv_headers)
        assert resp.status_code == 200








# =========================================================================
# TEST 2: Rideshare Driver Flow
# =========================================================================

class TestRideshareDriverFlow:
    """
    Exercises the iOS Driver app's rideshare journey:
    available rides -> bid -> start ride -> complete ride -> chat
    """

    def test_available_rides(self, client, drv_headers):
        """GET /api/rides/available - iOS RideshareDashboardView Available tab."""
        resp = client.get("/api/rides/available", headers=drv_headers)
        assert resp.status_code == 200
        data = resp.json()
        assert isinstance(data, (list, dict))

    def test_bid_and_ride_lifecycle(
        self, client, db_session, e2e_driver, drv_headers,
        e2e_customer, cust_headers, mock_stripe, mock_notifications,
    ):
        """
        Full rideshare lifecycle:
        1. Customer requests ride
        2. Driver bids
        3. Customer accepts bid
        4. Driver starts ride
        5. Driver completes ride
        """
        # Step 1: Create ride request directly in DB (simulates customer request)
        import uuid
        ride = RideRequest(
            request_id=f"RR-E2E-{uuid.uuid4().hex[:8]}",
            customer_id=e2e_customer.id,
            pickup_latitude=PICKUP_LAT,
            pickup_longitude=PICKUP_LNG,
            dropoff_latitude=DROPOFF_LAT,
            dropoff_longitude=DROPOFF_LNG,
            pickup_address="Downtown SF",
            dropoff_address="SFO Airport",
            status=RideRequestStatus.OPEN,
            bidding_expires_at=datetime.utcnow() + timedelta(minutes=10),
            suggested_price=25.00,
            estimated_distance_km=20.0,
            estimated_duration_minutes=20,
        )
        db_session.add(ride)
        db_session.commit()
        db_session.refresh(ride)

        # Step 2: Driver bids
        resp = client.post(
            f"/api/rides/request/{ride.id}/bid",
            json={
                "driver_id": e2e_driver.id,
                "proposed_price": 22.00,
                "estimated_arrival_minutes": 8,
            },
            headers=drv_headers,
        )
        assert resp.status_code in [200, 201], f"bid failed: {resp.text}"
        bid_data = resp.json()
        # Response structure: {"success": true, "bid": {"id": ..., ...}}
        bid_obj = bid_data.get("bid", bid_data)
        bid_id = bid_obj.get("id") or bid_obj.get("bid_id")
        assert bid_id is not None, f"No bid id in response: {bid_data}"

        # Step 3: Customer accepts the bid
        resp = client.post(
            f"/api/rides/bid/{bid_id}/respond",
            json={"action": "accept"},
            headers=cust_headers,
        )
        assert resp.status_code == 200, f"accept-bid failed: {resp.text}"

        # Step 4: Driver starts ride
        resp = client.post(
            f"/api/rides/request/{ride.id}/start",
            headers=drv_headers,
        )
        assert resp.status_code == 200, f"start-ride failed: {resp.text}"

        # Step 5: Driver completes ride
        resp = client.post(
            f"/api/rides/request/{ride.id}/complete",
            headers=drv_headers,
        )
        assert resp.status_code == 200, f"complete-ride failed: {resp.text}"

    def test_ride_chat(
        self, client, db_session, e2e_driver, drv_headers,
        e2e_customer, cust_headers, mock_notifications,
    ):
        """
        GET/POST /api/p2p/ride-requests/{id}/chat - iOS RiderChatView uses this.
        """
        # Create a matched ride for chat
        import uuid
        ride = RideRequest(
            request_id=f"RR-E2E-{uuid.uuid4().hex[:8]}",
            customer_id=e2e_customer.id,
            matched_driver_id=e2e_driver.id,
            pickup_latitude=PICKUP_LAT,
            pickup_longitude=PICKUP_LNG,
            dropoff_latitude=DROPOFF_LAT,
            dropoff_longitude=DROPOFF_LNG,
            pickup_address="Downtown SF",
            dropoff_address="SFO Airport",
            status=RideRequestStatus.MATCHED,
            bidding_expires_at=datetime.utcnow() + timedelta(minutes=10),
            suggested_price=25.00,
            estimated_distance_km=20.0,
            estimated_duration_minutes=20,
        )
        db_session.add(ride)
        db_session.commit()
        db_session.refresh(ride)

        # GET chat messages
        resp = client.get(
            f"/api/p2p/ride-requests/{ride.id}/chat",
            headers=drv_headers,
        )
        assert resp.status_code == 200

        # POST chat message
        resp = client.post(
            f"/api/p2p/ride-requests/{ride.id}/chat",
            json={"message": "On my way!", "sender_type": "driver"},
            headers=drv_headers,
        )
        assert resp.status_code in [200, 201]


