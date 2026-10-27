"""
E2E Tests for Wave 1+2 Features
================================

Wave 1 (Quick-89): Idempotency, refund, price change detection, vendor offline
Wave 2 (Quick-93,94,95,96): Leave-at-door, driver-arrived, cancel-no-customer,
                             reassign delivery, address validation, address-unreachable, fare estimate

Uses TestClient (conftest.client) with test DB. All Stripe calls mocked.
"""

import json
import pytest
from datetime import datetime, timedelta
from unittest.mock import patch, MagicMock

from models import (
    Order, OrderStatus, Vendor, VendorMenuItem, VendorStatus,
    OnboardingPhase, Customer, Driver, DriverStatus,
)
from main_new import create_access_token, get_password_hash


# ---------------------------------------------------------------------------
# Fixtures
# ---------------------------------------------------------------------------

@pytest.fixture
def e2e_vendor(db_session):
    """Vendor with is_online=True and a menu item."""
    vendor = Vendor(
        company_name=f"E2E Restaurant {datetime.now().timestamp()}",
        restaurant_name=f"E2E Restaurant {datetime.now().timestamp()}",
        contact_email=f"e2e_vendor_{datetime.now().timestamp()}@test.com",
        contact_phone="+14155550200",
        street="456 E2E St",
        city="San Francisco",
        state="CA",
        zip_code="94102",
        latitude=37.7749,
        longitude=-122.4194,
        onboarding_status=VendorStatus.APPROVED,
        onboarding_phase=OnboardingPhase.COMPLETED,
        is_online=True,
    )
    db_session.add(vendor)
    db_session.commit()
    db_session.refresh(vendor)
    return vendor


@pytest.fixture
def e2e_menu_item(db_session, e2e_vendor):
    """A menu item priced at $10.00."""
    item = VendorMenuItem(
        vendor_id=e2e_vendor.id,
        item_name="E2E Burger",
        description="Test burger for E2E",
        category="Main Course",
        price=10.00,
        is_available=True,
        in_stock=True,
        review_status="approved",
        needs_review=False,
    )
    db_session.add(item)
    db_session.commit()
    db_session.refresh(item)
    return item


@pytest.fixture
def e2e_customer(db_session):
    """Test customer with matching User record."""
    from models import User, UserRole
    email = f"e2e_cust_{datetime.now().timestamp()}@test.com"
    user = User(
        email=email,
        password_hash=get_password_hash("E2EPassword123!"),
        full_name="E2E Customer",
        role=UserRole.USER,
    )
    db_session.add(user)
    db_session.flush()
    customer = Customer(
        email=email,
        password_hash=get_password_hash("E2EPassword123!"),
        first_name="E2E",
        last_name="Customer",
        phone="+14155550300",
        is_active=True,
    )
    db_session.add(customer)
    db_session.commit()
    db_session.refresh(customer)
    return customer


@pytest.fixture
def e2e_driver(db_session):
    """Test driver with APPROVED status."""
    import uuid
    driver = Driver(
        driver_id=f"drv_{uuid.uuid4().hex[:8]}",
        email=f"e2e_drv_{datetime.now().timestamp()}@test.com",
        password_hash=get_password_hash("E2EPassword123!"),
        first_name="E2E",
        last_name="Driver",
        phone="+14155550400",
        status=DriverStatus.APPROVED,
        stripe_account_id="acct_test_e2e",
    )
    db_session.add(driver)
    db_session.commit()
    db_session.refresh(driver)
    return driver


@pytest.fixture
def e2e_driver_b(db_session):
    """A second driver for cross-driver auth tests."""
    import uuid
    driver = Driver(
        driver_id=f"drv_{uuid.uuid4().hex[:8]}",
        email=f"e2e_drv_b_{datetime.now().timestamp()}@test.com",
        password_hash=get_password_hash("E2EPassword123!"),
        first_name="E2E",
        last_name="DriverB",
        phone="+14155550401",
        status=DriverStatus.APPROVED,
    )
    db_session.add(driver)
    db_session.commit()
    db_session.refresh(driver)
    return driver


@pytest.fixture
def e2e_customer_headers(e2e_customer):
    token = create_access_token(data={"sub": e2e_customer.email, "customer_id": e2e_customer.id})
    return {"Authorization": f"Bearer {token}"}


@pytest.fixture
def e2e_driver_headers(e2e_driver):
    token = create_access_token(data={"sub": e2e_driver.email, "driver_id": e2e_driver.id})
    return {"Authorization": f"Bearer {token}"}


@pytest.fixture
def e2e_driver_b_headers(e2e_driver_b):
    token = create_access_token(data={"sub": e2e_driver_b.email, "driver_id": e2e_driver_b.id})
    return {"Authorization": f"Bearer {token}"}


@pytest.fixture
def e2e_vendor_headers(e2e_vendor):
    token = create_access_token(data={"sub": e2e_vendor.contact_email, "vendor_id": e2e_vendor.id})
    return {"Authorization": f"Bearer {token}"}


@pytest.fixture
def mock_push():
    """Suppress push notifications."""
    with patch("order_flow.send_push_notification"):
        yield


def _valid_address():
    return {
        "street": "123 Test St",
        "city": "San Francisco",
        "state": "CA",
        "zip": "94102",
        "latitude": 37.7749,
        "longitude": -122.4194,
    }


def _make_order(db_session, e2e_vendor, e2e_driver, e2e_customer, **overrides):
    """Helper to create an order with sensible defaults."""
    defaults = dict(
        order_number=f"ORD-E2E-{datetime.now().timestamp()}",
        customer_id=e2e_customer.id,
        customer_name="E2E Customer",
        customer_email=e2e_customer.email,
        customer_phone="+14155550300",
        vendor_id=e2e_vendor.id,
        driver_id=e2e_driver.id,
        driver_name="E2E Driver",
        items=json.dumps([{"name": "Burger", "quantity": 1, "price": 10.00}]),
        subtotal=10.00,
        tax_rate=0.08,
        tax_amount=0.80,
        delivery_fee=3.00,
        tip=0.0,
        platform_fee=1.00,
        total_amount=14.80,
        delivery_address=json.dumps(_valid_address()),
        status=OrderStatus.CONFIRMED,
        payment_status="succeeded",
        stripe_payment_intent_id="pi_test_e2e_123",
    )
    defaults.update(overrides)
    order = Order(**defaults)
    db_session.add(order)
    db_session.commit()
    db_session.refresh(order)
    return order


# ===========================================================================
# Wave 1 E2E Tests (Quick-89)
# ===========================================================================





# ===========================================================================
# Wave 2 E2E Tests (Quick-93, 94, 95, 96)
# ===========================================================================













class TestWave2FareEstimate:
    """E2E tests for ride fare estimate."""

    @pytest.mark.e2e
    def test_fare_estimate_public(self, client):
        """POST /api/rides/estimate with NYC coords returns fare breakdown."""
        resp = client.post("/api/rides/estimate", json={
            "pickup_latitude": 40.7128,
            "pickup_longitude": -74.0060,
            "dropoff_latitude": 40.7580,
            "dropoff_longitude": -73.9855,
            "ride_type": "standard",
        })
        assert resp.status_code == 200, f"Expected 200 for fare estimate, got {resp.status_code}: {resp.text}"
        data = resp.json()
        assert data["success"] is True
        estimate = data["estimate"]
        assert "subtotal" in estimate
        assert "platform_fee" in estimate
        assert estimate["subtotal"] > 0

    @pytest.mark.e2e
    def test_fare_estimate_distance_varies(self, client):
        """Longer trip produces higher fare than shorter trip."""
        # Short trip: ~3 miles in Manhattan
        resp_short = client.post("/api/rides/estimate", json={
            "pickup_latitude": 40.7128,
            "pickup_longitude": -74.0060,
            "dropoff_latitude": 40.7280,
            "dropoff_longitude": -73.9950,
            "ride_type": "standard",
        })
        assert resp_short.status_code == 200

        # Long trip: ~20 miles Manhattan to JFK area
        resp_long = client.post("/api/rides/estimate", json={
            "pickup_latitude": 40.7128,
            "pickup_longitude": -74.0060,
            "dropoff_latitude": 40.6413,
            "dropoff_longitude": -73.7781,
            "ride_type": "standard",
        })
        assert resp_long.status_code == 200

        short_total = resp_short.json()["estimate"]["subtotal"]
        long_total = resp_long.json()["estimate"]["subtotal"]
        assert long_total > short_total, (
            f"Long trip ({long_total}) should cost more than short trip ({short_total})"
        )
