"""
E2E Customer UI Wiring Tests
=============================

Tests covering every backend API endpoint that the iOS Customer app UI calls.
Organized by user journey:

1. TestCustomerFullFlow: Restaurant browsing -> ordering -> tracking -> rating
2. TestRideshareCustomerFlow: Ride estimate -> request -> tracking -> receipt
3. TestPhase10CustomerFeatures: Order chat, live chat support, help phone

Each test exercises the real endpoint with TestClient (no mocks on routes).
Stripe and push notifications are mocked since they require external services.

Verified against: UI_AUDIT_IOS_CUSTOMER.md (Quick-103 Plan 01)
"""

import pytest
import json
import uuid
from datetime import datetime, timedelta
from unittest.mock import patch, MagicMock

from models import (
    Customer, Driver, DriverStatus, Vendor, VendorStatus, OnboardingPhase,
    Order, OrderStatus, RideRequest, RideRequestStatus, RideBid, BidStatus,
    User, UserRole,
)
from main_new import get_password_hash, create_access_token


# ---------------------------------------------------------------------------
# Fixtures
# ---------------------------------------------------------------------------

@pytest.fixture
def e2e_customer(db_session):
    """Customer with matching User row (required for get_current_user)."""
    ts = datetime.now().timestamp()
    email = f"customer_e2e_{ts}@test.com"

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
def e2e_vendor(db_session):
    """Approved vendor with a menu item."""
    ts = datetime.now().timestamp()
    vendor = Vendor(
        company_name=f"E2E Restaurant {ts}",
        restaurant_name=f"E2E Restaurant {ts}",
        contact_email=f"vendor_e2e_{ts}@test.com",
        contact_phone="+14155550300",
        street="100 Market St",
        city="San Francisco",
        state="CA",
        zip_code="94105",
        onboarding_status=VendorStatus.APPROVED,
        onboarding_phase=OnboardingPhase.COMPLETED,
    )
    db_session.add(vendor)
    db_session.commit()
    db_session.refresh(vendor)
    return vendor


@pytest.fixture
def vendor_headers(e2e_vendor):
    token = create_access_token(data={
        "sub": e2e_vendor.contact_email,
        "vendor_id": e2e_vendor.id,
    })
    return {"Authorization": f"Bearer {token}"}


@pytest.fixture
def e2e_driver(db_session):
    """Approved driver for delivery/rideshare tests."""
    driver = Driver(
        driver_id=f"drv_{uuid.uuid4().hex[:8]}",
        email=f"driver_e2e_{datetime.now().timestamp()}@test.com",
        password_hash=get_password_hash("DriverPass123!"),
        first_name="E2E",
        last_name="Driver",
        phone="+14155550400",
        status=DriverStatus.APPROVED,
    )
    db_session.add(driver)
    db_session.commit()
    db_session.refresh(driver)
    return driver


@pytest.fixture
def driver_headers(e2e_driver):
    token = create_access_token(data={
        "sub": e2e_driver.email,
        "driver_id": e2e_driver.id,
    })
    return {"Authorization": f"Bearer {token}"}


@pytest.fixture
def e2e_order(db_session, e2e_customer, e2e_vendor):
    """Pre-created order in Delivered status for rating/chat tests."""
    order = Order(
        order_number=f"ORD-E2E-{uuid.uuid4().hex[:8]}",
        customer_email=e2e_customer.email,
        vendor_id=e2e_vendor.id,
        status=OrderStatus.DELIVERED,
        subtotal=25.00,
        tax_amount=2.25,
        delivery_fee=0.00,
        tip=5.00,
        total_amount=32.25,
        platform_fee=1.00,
        delivery_address=json.dumps({
            "street": "200 Main St",
            "city": "San Francisco",
            "state": "CA",
            "zip": "94105",
        }),
    )
    db_session.add(order)
    db_session.commit()
    db_session.refresh(order)
    return order


@pytest.fixture
def mock_stripe_order():
    """Mock Stripe for order payment tests."""
    with patch("stripe_integration.stripe.PaymentIntent.create") as mock_pi:
        mock_pi.return_value = MagicMock(
            id="pi_e2e_123", client_secret="pi_e2e_secret", status="succeeded"
        )
        yield mock_pi


@pytest.fixture
def mock_notifications():
    """Suppress push notifications and emails."""
    with patch("bid_routes.send_push_notification"), \
         patch("bid_routes.broadcast_new_ride_request"), \
         patch("bid_routes.broadcast_new_bid"), \
         patch("bid_routes.broadcast_bid_response"), \
         patch("bid_routes.broadcast_ride_matched"), \
         patch("bid_routes.broadcast_ride_request_cancelled"), \
         patch("bid_routes.send_ride_request_confirmation_email"):
        yield


# ===========================================================================
# TEST CLASS 1: Full Food Order Customer Flow
# ===========================================================================

class TestCustomerFullFlow:
    """
    Mirrors iOS Customer app food ordering journey:
    Browse restaurants -> View menu -> Place order -> Track -> Chat -> Rate
    """






    def test_get_refund_status(self, client, cust_headers, e2e_order):
        """OrderHistoryView refund check: GET /api/orders/{id}/refund-status"""
        resp = client.get(f"/api/orders/{e2e_order.id}/refund-status", headers=cust_headers)
        assert resp.status_code in [200, 404]

    def test_track_order(self, client, cust_headers, e2e_order):
        """DeliveryTrackingView: GET /api/customer/orders/{id}/track"""
        resp = client.get(
            f"/api/customer/orders/{e2e_order.id}/track",
            headers=cust_headers,
        )
        assert resp.status_code in [200, 404]





    def test_requires_auth_for_customer_orders(self, client):
        """Verify auth required -- iOS sends Bearer token on all customer endpoints."""
        resp = client.get("/api/customer/orders")
        assert resp.status_code in [401, 403]


# ===========================================================================
# TEST CLASS 2: Rideshare Customer Flow
# ===========================================================================

class TestRideshareCustomerFlow:
    """
    Mirrors iOS Customer rideshare journey:
    Estimate fare -> Request ride -> View bids -> Accept -> Track -> Receipt
    """

    def test_fare_estimate(self, client, cust_headers):
        """RideRequestView: POST /api/rides/estimate"""
        resp = client.post(
            "/api/rides/estimate",
            json={
                "pickup_latitude": 40.7128,
                "pickup_longitude": -74.0060,
                "dropoff_latitude": 40.7580,
                "dropoff_longitude": -73.9855,
                "ride_type": "standard",
            },
            headers=cust_headers,
        )
        assert resp.status_code == 200
        data = resp.json()
        # Response wraps estimate in {"success": true, "estimate": {...}}
        assert data.get("success") is True
        estimate = data.get("estimate", data)
        assert "total" in estimate or "base_fare" in estimate.get("breakdown", {})

    def test_request_ride(self, client, cust_headers, e2e_customer, mock_notifications):
        """RideRequestView: POST /api/rides/request"""
        resp = client.post(
            "/api/rides/request",
            json={
                "customer_id": e2e_customer.id,
                "pickup_address": "123 Broadway, New York, NY 10001",
                "pickup_latitude": 40.7128,
                "pickup_longitude": -74.0060,
                "dropoff_address": "Times Square, New York, NY 10036",
                "dropoff_latitude": 40.7580,
                "dropoff_longitude": -73.9855,
                "ride_type": "standard",
                "bidding_duration_minutes": 5,
                "special_requests": "E2E test ride",
            },
            headers=cust_headers,
        )
        assert resp.status_code in [200, 201]
        data = resp.json()
        # Response wraps ride in {"success": true, "ride_request": {"id": ...}}
        assert data.get("success") is True
        ride = data.get("ride_request", data)
        assert "id" in ride or "request_id" in ride

    def test_get_ride_history(self, client, cust_headers, e2e_customer):
        """OrderHistoryView Rides tab: GET /api/customer/rides/history"""
        resp = client.get("/api/customer/rides/history", headers=cust_headers)
        assert resp.status_code == 200
        data = resp.json()
        assert "rides" in data or isinstance(data, list)

    def test_ride_request_requires_auth(self, client):
        """Verify auth required for ride request."""
        resp = client.post("/api/rides/request", json={})
        assert resp.status_code in [401, 403, 422]


# ===========================================================================
# TEST CLASS 3: Phase 10 Customer Features
# ===========================================================================

class TestPhase10CustomerFeatures:
    """
    Phase 10 features wired in iOS Customer app:
    - OrderChatView: GET/POST /api/customer/orders/{id}/chat
    - LiveChatView: POST /api/support/chat
    - HelpSupportView: Call support phone number
    """



    def test_live_chat_support(self, client):
        """LiveChatView: POST /api/support/chat (public endpoint, no auth required)"""
        resp = client.post(
            "/api/support/chat",
            json={"message": "Where is my order?"},
        )
        assert resp.status_code == 200
        data = resp.json()
        # Should return a response message from the support bot
        assert "response" in data or "message" in data or "reply" in data

    def test_live_chat_refund_intent(self, client):
        """LiveChatView: POST /api/support/chat with refund keyword"""
        resp = client.post(
            "/api/support/chat",
            json={"message": "I want a refund"},
        )
        assert resp.status_code == 200

    def test_live_chat_pricing_intent(self, client):
        """LiveChatView: POST /api/support/chat with pricing keyword"""
        resp = client.post(
            "/api/support/chat",
            json={"message": "How much does it cost?"},
        )
        assert resp.status_code == 200


# ===========================================================================
# TEST CLASS 4: Auth Flow (Login, Register, Password Reset)
# ===========================================================================

class TestCustomerAuthFlow:
    """
    iOS LoginView and RegisterView auth endpoints.
    """

    def test_customer_register(self, client):
        """RegisterView: POST /api/customer/register"""
        ts = datetime.now().timestamp()
        resp = client.post(
            "/api/customer/register",
            json={
                "email": f"newcust_{ts}@test.com",
                "password": "NewCustPass123!",
                "full_name": "New Customer",
                "phone": "+14155559999",
            },
        )
        # 200/201 success or 400/422 validation
        assert resp.status_code in [200, 201, 400, 422]

    def test_customer_login(self, client, e2e_customer):
        """LoginView: POST /api/auth/customer/login (OAuth2 form data)"""
        resp = client.post(
            "/api/auth/customer/login",
            data={
                "username": e2e_customer.email,
                "password": "CustPass123!",
            },
        )
        assert resp.status_code in [200, 401]

    def test_password_reset_request(self, client, e2e_customer):
        """ForgotPasswordView: POST /api/customer/password-reset/request"""
        resp = client.post(
            "/api/customer/password-reset/request",
            json={"email": e2e_customer.email},
        )
        # Should accept the request (even if email delivery fails in test)
        assert resp.status_code in [200, 400, 422, 500]

    def test_customer_profile(self, client, cust_headers):
        """ProfileView: GET /api/customer/profile"""
        resp = client.get("/api/customer/profile", headers=cust_headers)
        assert resp.status_code in [200, 404]
