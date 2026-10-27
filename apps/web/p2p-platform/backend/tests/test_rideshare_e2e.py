"""
Rideshare E2E — 12-Step Lifecycle Test
=======================================

Executes the full rideshare lifecycle using FastAPI TestClient (in-memory
SQLite) so the test is hermetic and reproducible. Stripe, push notifications,
and email are mocked. Insurance events are allowed to fail silently.

Runnable with:
    cd apps/web/p2p-platform/backend
    python -m pytest tests/test_rideshare_e2e.py -v

Steps:
  1. Customer requests ride        — POST /api/rides/request
  2. Driver views available rides  — GET  /api/rides/available
  3. Driver places bid             — POST /api/rides/request/{id}/bid
  4. Customer sees bids            — GET  /api/rides/request/{id}/bids
  5. Customer accepts bid          — POST /api/rides/bid/{bid_id}/respond  (action=accept)
  6. Driver notified of acceptance — verified via ride status=MATCHED in DB
  7. Driver marks arrived at pickup— POST /api/rides/request/{id}/arrived
  8. Customer/driver confirms start— POST /api/rides/request/{id}/start
  9. Driver completes ride         — POST /api/rides/request/{id}/complete
 10. Payment captured              — POST /api/payments/ride/create-intent (Stripe mocked)
 11. Customer rates driver         — POST /api/rides/{id}/rate
 12. Driver rates customer         — POST /api/rides/request/{id}/rate-passenger
"""

from datetime import datetime
from unittest.mock import patch, MagicMock

import pytest

from main_new import create_access_token, get_password_hash
from models import (
    Customer,
    Driver,
    DriverStatus,
    RideBid,
    RideRequest,
    RideRequestStatus,
    BidStatus,
)

# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------

PICKUP_LAT = 37.7749
PICKUP_LNG = -122.4194   # Downtown SF
DROPOFF_LAT = 37.6213
DROPOFF_LNG = -122.3790  # SFO Airport


# ---------------------------------------------------------------------------
# Fixtures
# ---------------------------------------------------------------------------

@pytest.fixture
def e2e_customer(db_session) -> Customer:
    """Dedicated customer for the 12-step lifecycle test."""
    customer = Customer(
        first_name="Jordan",
        last_name="Rider",
        email=f"jordan.rider.{datetime.now().timestamp()}@e2e.test",
        phone="+14155550200",
        password_hash=get_password_hash("CustomerE2E2025!"),
        is_active=True,
    )
    db_session.add(customer)
    db_session.commit()
    db_session.refresh(customer)
    return customer


@pytest.fixture
def e2e_driver(db_session) -> Driver:
    """Dedicated APPROVED driver for the 12-step lifecycle test."""
    import uuid
    driver = Driver(
        driver_id=f"drv_e2e_{uuid.uuid4().hex[:8]}",
        first_name="Morgan",
        last_name="Driver",
        email=f"morgan.driver.{datetime.now().timestamp()}@e2e.test",
        phone="+14155550201",
        password_hash=get_password_hash("DriverE2E2025!"),
        status=DriverStatus.APPROVED,
        current_latitude=37.78,
        current_longitude=-122.41,
        is_online=True,  # get_available_ride_requests returns nothing for offline drivers
        verification_status="verified",  # bid_routes KYC gate
    )
    db_session.add(driver)
    db_session.commit()
    db_session.refresh(driver)
    return driver


@pytest.fixture
def e2e_customer_headers(e2e_customer) -> dict:
    token = create_access_token(data={
        "sub": e2e_customer.email,
        "customer_id": e2e_customer.id,
    })
    return {"Authorization": f"Bearer {token}"}


@pytest.fixture
def e2e_driver_headers(e2e_driver) -> dict:
    token = create_access_token(data={
        "sub": e2e_driver.email,
        "driver_id": e2e_driver.id,
    })
    return {"Authorization": f"Bearer {token}"}


@pytest.fixture
def mock_stripe():
    """Mock Stripe PaymentIntent.create and Transfer.create."""
    with patch("rideshare_payments.stripe.PaymentIntent.create") as mock_pi, \
         patch("rideshare_payments.stripe.Transfer.create") as mock_transfer:
        mock_pi.return_value = MagicMock(
            id="pi_e2e_test_001", client_secret="pi_e2e_secret_001"
        )
        mock_transfer.return_value = MagicMock(id="tr_e2e_test_001")
        yield {"payment_intent": mock_pi, "transfer": mock_transfer}


@pytest.fixture
def mock_notifications():
    """Suppress push notifications, emails, WebSocket broadcasts."""
    with patch("bid_routes.send_push_notification"), \
         patch("bid_routes.send_ride_request_confirmation_email", return_value=None), \
         patch("bid_routes.send_ride_bid_received_email", return_value=None), \
         patch("bid_routes.send_ride_matched_email", return_value=None), \
         patch("bid_routes.send_ride_started_email", return_value=None), \
         patch("bid_routes.send_ride_completed_email", return_value=None), \
         patch("bid_routes.send_ride_cancelled_email", return_value=None), \
         patch("bid_routes.asyncio.create_task"):
        yield


# ---------------------------------------------------------------------------
# 12-Step Lifecycle
# ---------------------------------------------------------------------------

class TestRideshare12StepLifecycle:
    """Full rideshare lifecycle — 12 consecutive steps in one test function."""

    def test_12_step_rideshare_lifecycle(
        self,
        client,
        db_session,
        e2e_customer,
        e2e_driver,
        e2e_customer_headers,
        e2e_driver_headers,
        mock_stripe,
        mock_notifications,
    ):
        customer = e2e_customer
        driver = e2e_driver

        # ── Step 1: Customer requests ride ──────────────────────────────────
        resp = client.post("/api/rides/request", json={
            "customer_id": customer.id,
            "pickup_address": "123 Market St, San Francisco, CA",
            "pickup_latitude": PICKUP_LAT,
            "pickup_longitude": PICKUP_LNG,
            "pickup_place_name": "Downtown SF",
            "dropoff_address": "SFO Airport, San Francisco, CA",
            "dropoff_latitude": DROPOFF_LAT,
            "dropoff_longitude": DROPOFF_LNG,
            "dropoff_place_name": "SFO Airport",
            "ride_type": "standard",
            "customer_max_price": 40.00,
            "bidding_duration_minutes": 5,
        }, headers=e2e_customer_headers)
        assert resp.status_code == 200, f"Step 1 failed: {resp.text}"
        data = resp.json()
        assert data["success"] is True
        ride = data["ride_request"]
        assert ride["status"] == "open"
        assert ride["request_id"].startswith("RIDE")
        ride_id = ride["id"]

        # ── Step 2: Driver views available rides ────────────────────────────
        resp = client.get("/api/rides/available", params={
            "driver_id": driver.id,
            "latitude": 37.78,
            "longitude": -122.41,
        }, headers=e2e_driver_headers)
        assert resp.status_code == 200, f"Step 2 failed: {resp.text}"
        data = resp.json()
        assert data["success"] is True
        assert data["count"] >= 1
        found = [r for r in data["available_requests"] if r["id"] == ride_id]
        assert len(found) == 1, "Newly created ride not in available list"
        assert found[0]["already_bid"] is False

        # ── Step 3: Driver places bid ────────────────────────────────────────
        resp = client.post(f"/api/rides/request/{ride_id}/bid", json={
            "driver_id": driver.id,
            "proposed_price": 28.00,
            "message": "I'm nearby, ready in 5 minutes.",
            "estimated_arrival_minutes": 5,
        }, headers=e2e_driver_headers)
        assert resp.status_code == 200, f"Step 3 failed: {resp.text}"
        data = resp.json()
        assert data["success"] is True
        bid = data["bid"]
        assert bid["status"] == "pending"
        assert bid["proposed_price"] == 28.00
        bid_id = bid["id"]

        # Verify ride moved to BIDDING
        db_session.expire_all()
        ride_obj = db_session.query(RideRequest).get(ride_id)
        assert ride_obj.status == RideRequestStatus.BIDDING

        # ── Step 4: Customer sees bids ───────────────────────────────────────
        resp = client.get(f"/api/rides/request/{ride_id}/bids", headers=e2e_customer_headers)
        assert resp.status_code == 200, f"Step 4 failed: {resp.text}"
        data = resp.json()
        assert data["total_bids"] == 1
        assert data["bidding_open"] is True
        assert data["bids"][0]["proposed_price"] == 28.00

        # ── Step 5: Customer accepts bid ─────────────────────────────────────
        resp = client.post(f"/api/rides/bid/{bid_id}/respond", json={
            "action": "accept",
        }, headers=e2e_customer_headers)
        assert resp.status_code == 200, f"Step 5 failed: {resp.text}"
        data = resp.json()
        assert data["success"] is True
        assert data["fare"] == 28.00
        assert data["driver"] is not None
        assert data["driver"]["id"] == driver.id

        # ── Step 6: Driver notified — ride status = MATCHED ──────────────────
        db_session.expire_all()
        ride_obj = db_session.query(RideRequest).get(ride_id)
        assert ride_obj.status == RideRequestStatus.MATCHED, \
            f"Expected MATCHED, got {ride_obj.status}"
        assert ride_obj.matched_driver_id == driver.id
        assert ride_obj.final_price == 28.00

        # Bid status also moves to accepted
        bid_obj = db_session.query(RideBid).get(bid_id)
        assert bid_obj.status == BidStatus.ACCEPTED

        # ── Step 7: Driver marks arrived at pickup ───────────────────────────
        resp = client.post(f"/api/rides/request/{ride_id}/arrived",
                           headers=e2e_driver_headers)
        assert resp.status_code == 200, f"Step 7 failed: {resp.text}"
        data = resp.json()
        assert data["success"] is True
        assert data["message"] == "Driver arrived at pickup"

        db_session.expire_all()
        ride_obj = db_session.query(RideRequest).get(ride_id)
        assert ride_obj.driver_arrived_at is not None

        # ── Step 8: Customer/driver confirms start (pickup) ──────────────────
        resp = client.post(f"/api/rides/request/{ride_id}/start",
                           headers=e2e_driver_headers)
        assert resp.status_code == 200, f"Step 8 failed: {resp.text}"
        data = resp.json()
        assert data["success"] is True

        db_session.expire_all()
        ride_obj = db_session.query(RideRequest).get(ride_id)
        assert ride_obj.status == RideRequestStatus.IN_PROGRESS

        # ── Step 9: Driver completes ride ────────────────────────────────────
        resp = client.post(f"/api/rides/request/{ride_id}/complete",
                           headers=e2e_driver_headers)
        assert resp.status_code == 200, f"Step 9 failed: {resp.text}"
        data = resp.json()
        assert data["success"] is True
        assert data["final_price"] == 28.00

        db_session.expire_all()
        ride_obj = db_session.query(RideRequest).get(ride_id)
        assert ride_obj.status == RideRequestStatus.COMPLETED
        assert ride_obj.completed_at is not None

        # ── Step 10: Payment captured (Stripe mocked) ────────────────────────
        resp = client.post("/api/payments/ride/create-intent", json={
            "ride_request_id": ride_id,
        }, headers=e2e_customer_headers)
        assert resp.status_code == 200, f"Step 10 failed: {resp.text}"
        data = resp.json()
        assert data["success"] is True
        assert data["fare"] == 28.00
        # Fare $28 is <= $35 -> $1 platform fee per side, plus the $0.05/side
        # CPUC Access for All pass-through (TNC-13)
        assert data["tier_fee"] == 1.00
        assert data["customer_pays"] == pytest.approx(29.05)   # 28 + 1 + 0.05
        assert data["driver_receives"] == pytest.approx(26.95)  # 28 - 1 - 0.05
        assert data["platform_earns"] == 2.00    # 1 x 2 (both sides pay $1)

        # Verify Stripe was called with correct cents amount
        mock_stripe["payment_intent"].assert_called_once()
        call_kwargs = mock_stripe["payment_intent"].call_args
        assert call_kwargs[1]["amount"] == 2905, \
            f"Expected 2905 cents, got {call_kwargs[1]['amount']}"

        # ── Step 11: Customer rates driver ───────────────────────────────────
        resp = client.post(f"/api/rides/{ride_id}/rate", json={
            "rating": 5,
            "comment": "Excellent, punctual driver!",
        }, headers=e2e_customer_headers)
        assert resp.status_code == 200, f"Step 11 failed: {resp.text}"
        data = resp.json()
        assert data["success"] is True
        assert data["rating"] == 5

        # ── Step 12: Driver rates customer (passenger) ───────────────────────
        resp = client.post(f"/api/rides/request/{ride_id}/rate-passenger", json={
            "rating": 5,
            "comment": "Great passenger, easy pickup.",
        }, headers=e2e_driver_headers)
        assert resp.status_code == 200, f"Step 12 failed: {resp.text}"
        data = resp.json()
        assert data["success"] is True
        assert data["rating"] == 5

        # Final DB verification — both ratings persisted
        db_session.expire_all()
        ride_obj = db_session.query(RideRequest).get(ride_id)
        assert ride_obj.customer_rating == 5, "Customer-side driver rating not saved"
        assert ride_obj.passenger_rating == 5, "Driver-side passenger rating not saved"
