"""
E2E Rideshare Regression Test - Full Lifecycle
===============================================

Covers the complete rideshare flow:
  Fare estimate → Ride request → Driver views → Bid → Customer views bids →
  Customer counters → Driver counters → Customer accepts → Chat → Driver location →
  Pickup (start) → Tracking → Dropoff (complete) → Stripe payment → Rating → Tip

Plus edge-case tests: low bid rejection, max counter limit, active ride guard,
cancel with bid expiry, expired bidding window, and tiered pricing verification.
"""

import sys
from contextlib import contextmanager

import pytest
from datetime import datetime, timedelta
from unittest.mock import patch, MagicMock

from models import (
    Customer, Driver, DriverStatus, RideRequest, RideBid,
    RideRequestStatus, BidStatus, Order, OrderStatus,
)
from main_new import get_password_hash, create_access_token


# ---------------------------------------------------------------------------
# Fixtures
# ---------------------------------------------------------------------------

@pytest.fixture
def test_customer(db_session):
    """Create a test customer for rideshare tests."""
    customer = Customer(
        first_name="Alice",
        last_name="Rider",
        email=f"alice.rider.{datetime.now().timestamp()}@test.com",
        phone="+14155550100",
        password_hash=get_password_hash("CustomerPass123!"),
        is_active=True,
    )
    db_session.add(customer)
    db_session.commit()
    db_session.refresh(customer)
    return customer


@pytest.fixture
def customer_headers(test_customer):
    """Auth headers with customer_id in JWT for customer endpoints."""
    token = create_access_token(data={
        "sub": test_customer.email,
        "customer_id": test_customer.id,
    })
    return {"Authorization": f"Bearer {token}"}


@pytest.fixture
def driver_headers(test_driver):
    """Auth headers with driver_id in JWT for driver endpoints."""
    token = create_access_token(data={
        "sub": test_driver.email,
        "driver_id": test_driver.id,
    })
    return {"Authorization": f"Bearer {token}"}


@contextmanager
def patched_stripe():
    """bid_routes imports stripe inside its handlers, so swap the module itself for a mock."""
    fake = MagicMock()
    with patch.dict(sys.modules, {"stripe": fake}):
        yield fake


@pytest.fixture(autouse=True)
def ready_driver(db_session, test_driver):
    """Drivers only see rides when online, and only verified drivers may bid (bid_routes KYC gate)."""
    test_driver.is_online = True
    test_driver.verification_status = "verified"
    test_driver.documents_verified = True
    db_session.commit()
    return test_driver


@pytest.fixture
def mock_stripe():
    with patch("rideshare_payments.stripe.PaymentIntent.create") as mock_pi, \
         patch("rideshare_payments.stripe.Transfer.create") as mock_transfer, \
         patch("rideshare_payments.stripe.PaymentIntent.modify"), \
         patch("rideshare_payments.stripe.PaymentIntent.capture"):
        mock_pi.return_value = MagicMock(
            id="pi_test_123", client_secret="pi_test_secret"
        )
        mock_transfer.return_value = MagicMock(id="tr_test_456")
        yield {"payment_intent": mock_pi, "transfer": mock_transfer}


@pytest.fixture
def mock_notifications():
    """Suppress all async broadcasts, push notifications, and emails."""
    with patch("bid_routes.send_push_notification"), \
         patch("bid_routes.send_ride_request_confirmation_email"), \
         patch("bid_routes.send_ride_bid_received_email"), \
         patch("bid_routes.send_ride_matched_email"), \
         patch("bid_routes.send_ride_started_email"), \
         patch("bid_routes.send_ride_completed_email"), \
         patch("bid_routes.send_ride_cancelled_email"), \
         patch("bid_routes.asyncio.create_task"):
        yield


# SF coordinates used throughout tests
PICKUP_LAT, PICKUP_LNG = 37.7749, -122.4194   # Downtown SF
DROPOFF_LAT, DROPOFF_LNG = 37.6213, -122.3790  # SFO Airport


# ---------------------------------------------------------------------------
# Happy-path: full 17-step lifecycle
# ---------------------------------------------------------------------------

class TestRideshareE2EFlow:
    """Complete end-to-end regression for the rideshare lifecycle."""

    def test_full_rideshare_flow(
        self, client, db_session, test_customer, test_driver,
        customer_headers, driver_headers, auth_headers, mock_stripe, mock_notifications,
    ):
        customer = test_customer
        driver = test_driver
        # ── Step 1: Fare Estimate ────────────────────────────────────────
        resp = client.post("/api/rides/estimate", json={
            "pickup_latitude": PICKUP_LAT,
            "pickup_longitude": PICKUP_LNG,
            "dropoff_latitude": DROPOFF_LAT,
            "dropoff_longitude": DROPOFF_LNG,
            "ride_type": "standard",
        }, headers=customer_headers)
        assert resp.status_code == 200
        data = resp.json()
        assert data["success"] is True
        estimate = data["estimate"]
        assert "subtotal" in estimate
        assert "platform_fee" in estimate
        assert "suggested_bids" in estimate
        assert len(estimate["suggested_bids"]) > 0
        suggested_price = estimate["subtotal"]

        # ── Step 2: Create Ride Request ──────────────────────────────────
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
        }, headers=customer_headers)
        assert resp.status_code == 200
        data = resp.json()
        assert data["success"] is True
        ride = data["ride_request"]
        assert ride["status"] == "open"
        assert ride["request_id"].startswith("RIDE")
        assert ride["suggested_price"] > 0
        ride_id = ride["id"]

        # ── Step 3: Driver Views Available Rides ─────────────────────────
        resp = client.get("/api/rides/available", params={
            "driver_id": driver.id,
            "latitude": 37.78,
            "longitude": -122.41,
        }, headers=driver_headers)
        assert resp.status_code == 200
        data = resp.json()
        assert data["success"] is True
        assert data["count"] >= 1
        found = [r for r in data["available_requests"] if r["id"] == ride_id]
        assert len(found) == 1
        assert found[0]["already_bid"] is False

        # ── Step 4: Driver Submits Bid ───────────────────────────────────
        resp = client.post(f"/api/rides/request/{ride_id}/bid", json={
            "driver_id": driver.id,
            "proposed_price": 25.00,
            "message": "I'm nearby and ready!",
            "estimated_arrival_minutes": 8,
        }, headers=driver_headers)
        assert resp.status_code == 200
        data = resp.json()
        assert data["success"] is True
        bid = data["bid"]
        assert bid["status"] == "pending"
        assert bid["proposed_price"] == 25.00
        bid_id = bid["id"]

        # Verify ride request moved to BIDDING
        db_session.expire_all()
        ride_obj = db_session.query(RideRequest).get(ride_id)
        assert ride_obj.status == RideRequestStatus.BIDDING

        # ── Step 5: Customer Views Bids ──────────────────────────────────
        resp = client.get(f"/api/rides/request/{ride_id}/bids", headers=customer_headers)
        assert resp.status_code == 200
        data = resp.json()
        assert data["total_bids"] == 1
        assert data["bidding_open"] is True
        assert data["bids"][0]["proposed_price"] == 25.00

        # ── Step 6: Customer Counters (Round 1) ─────────────────────────
        resp = client.post(f"/api/rides/bid/{bid_id}/respond", json={
            "action": "counter",
            "counter_price": 20.00,
            "message": "Can you do $20?",
        }, headers=customer_headers)
        assert resp.status_code == 200
        data = resp.json()
        assert data["success"] is True
        assert data["customer_counters_remaining"] == 2  # 3 - 1

        db_session.expire_all()
        bid_obj = db_session.query(RideBid).get(bid_id)
        assert bid_obj.status == BidStatus.COUNTERED

        # ── Step 7: Driver Counter-Offers (Round 2) ─────────────────────
        resp = client.post(f"/api/rides/bid/{bid_id}/driver-counter", json={
            "counter_price": 22.00,
            "message": "Meet in the middle at $22?",
        }, headers=driver_headers)
        assert resp.status_code == 200
        data = resp.json()
        assert data["success"] is True
        assert data["is_final_round"] is True

        db_session.expire_all()
        bid_obj = db_session.query(RideBid).get(bid_id)
        assert bid_obj.status == BidStatus.PENDING
        assert bid_obj.proposed_price == 22.00

        # ── Step 8: Customer Accepts Final Price ─────────────────────────
        resp = client.post(f"/api/rides/bid/{bid_id}/respond", json={
            "action": "accept",
        }, headers=customer_headers)
        assert resp.status_code == 200
        data = resp.json()
        assert data["success"] is True
        assert data["fare"] == 22.00
        assert data["driver"] is not None
        assert data["driver"]["id"] == driver.id

        db_session.expire_all()
        ride_obj = db_session.query(RideRequest).get(ride_id)
        assert ride_obj.status == RideRequestStatus.MATCHED
        assert ride_obj.matched_driver_id == driver.id
        assert ride_obj.final_price == 22.00

        # ── Step 9: Chat – Customer Sends Message ────────────────────────
        resp = client.post(
            f"/api/p2p/ride-requests/{ride_id}/chat",
            json={
                "message": "I'm at the blue building",
                "sender_type": "customer",
            },
            headers=customer_headers,
        )
        assert resp.status_code == 200
        data = resp.json()
        assert data["success"] is True
        assert "message_id" in data

        # ── Step 10: Chat – Get Messages ─────────────────────────────────
        resp = client.get(f"/api/p2p/ride-requests/{ride_id}/chat", headers=customer_headers)
        assert resp.status_code == 200
        data = resp.json()
        assert "messages" in data

        # ── Step 11: Driver Location Update ──────────────────────────────
        resp = client.post("/api/driver/location", json={
            "driver_id": driver.id,
            "latitude": 37.775,
            "longitude": -122.418,
        }, headers=driver_headers)
        assert resp.status_code == 200
        data = resp.json()
        assert data["success"] is True

        db_session.expire_all()
        driver_obj = db_session.query(Driver).get(driver.id)
        assert driver_obj.current_latitude == 37.775
        assert driver_obj.current_longitude == -122.418

        # ── Step 12: Driver Starts Ride (Pickup) ─────────────────────────
        resp = client.post(f"/api/rides/request/{ride_id}/start", headers=driver_headers)
        assert resp.status_code == 200
        data = resp.json()
        assert data["success"] is True

        db_session.expire_all()
        ride_obj = db_session.query(RideRequest).get(ride_id)
        assert ride_obj.status == RideRequestStatus.IN_PROGRESS

        # ── Step 13: Ride Tracking ───────────────────────────────────────
        resp = client.get(f"/api/rides/request/{ride_id}", headers=customer_headers)
        assert resp.status_code == 200
        data = resp.json()
        assert data["ride_request"]["status"] == "in_progress"
        assert data["ride_request"].get("matched_driver") is not None

        # ── Step 14: Driver Completes Ride (Dropoff) ─────────────────────
        resp = client.post(f"/api/rides/request/{ride_id}/complete", headers=driver_headers)
        assert resp.status_code == 200
        data = resp.json()
        assert data["success"] is True
        assert data["final_price"] == 22.00

        db_session.expire_all()
        ride_obj = db_session.query(RideRequest).get(ride_id)
        assert ride_obj.status == RideRequestStatus.COMPLETED
        assert ride_obj.completed_at is not None

        # ── Step 15: Payment – Create Payment Intent ─────────────────────
        resp = client.post("/api/payments/ride/create-intent", json={
            "ride_request_id": ride_id,
        }, headers=customer_headers)
        assert resp.status_code == 200
        data = resp.json()
        assert data["success"] is True
        assert data["fare"] == 22.00
        assert data["tier_fee"] == 1.00          # fare ≤ $35 → $1
        assert data["customer_pays"] == 23.05     # 22 + 1 tier fee + 0.05 CPUC Access for All (customer share)
        assert data["driver_receives"] == 20.95   # 22 - 1 tier fee - 0.05 CPUC Access for All (driver share)
        assert data["platform_earns"] == 2.00     # 1 × 2

        # Verify Stripe mock called with 2300 cents
        mock_stripe["payment_intent"].assert_called_once()
        call_kwargs = mock_stripe["payment_intent"].call_args
        assert call_kwargs[1]["amount"] == 2305  # $23.05 in cents

        # ── Step 16: Customer Rates Driver ───────────────────────────────
        resp = client.post(
            f"/api/rides/{ride_id}/rate",
            json={"rating": 5, "comment": "Great ride!"},
            headers=customer_headers,
        )
        assert resp.status_code == 200
        data = resp.json()
        assert data["success"] is True
        assert data["rating"] == 5

        # ── Step 17: Customer Tips Driver ────────────────────────────────
        resp = client.post(
            f"/api/rides/{ride_id}/tip",
            json={"tip_amount": 5.00},
            headers=customer_headers,
        )
        assert resp.status_code == 200
        data = resp.json()
        assert data["success"] is True
        assert data["tip_amount"] == 5.00


# ---------------------------------------------------------------------------
# Edge-case & validation tests
# ---------------------------------------------------------------------------

class TestRideshareEdgeCases:

    def test_low_bid_rejection(
        self, client, db_session, test_customer, test_driver,
        customer_headers, driver_headers, mock_notifications,
    ):
        """Counter with price < 40% of suggested → 400."""
        customer = test_customer
        driver = test_driver

        # Create ride
        resp = client.post("/api/rides/request", json={
            "customer_id": customer.id,
            "pickup_address": "123 Market St",
            "pickup_latitude": PICKUP_LAT,
            "pickup_longitude": PICKUP_LNG,
            "dropoff_address": "SFO Airport",
            "dropoff_latitude": DROPOFF_LAT,
            "dropoff_longitude": DROPOFF_LNG,
            "bidding_duration_minutes": 5,
        }, headers=customer_headers)
        ride_id = resp.json()["ride_request"]["id"]
        suggested = resp.json()["ride_request"]["suggested_price"]

        # Driver bids
        resp = client.post(f"/api/rides/request/{ride_id}/bid", json={
            "driver_id": driver.id,
            "proposed_price": suggested,
        }, headers=driver_headers)
        bid_id = resp.json()["bid"]["id"]

        # Customer counters with < 40% of suggested → 400
        low_price = round(suggested * 0.3, 2)
        resp = client.post(f"/api/rides/bid/{bid_id}/respond", json={
            "action": "counter",
            "counter_price": low_price,
        }, headers=customer_headers)
        assert resp.status_code == 400
        assert "too low" in resp.json()["detail"].lower()

    def test_max_counter_limit(
        self, client, db_session, test_customer, test_driver,
        customer_headers, driver_headers, mock_notifications,
    ):
        """4th customer counter → 400 'Maximum 3 counter-offers reached'."""
        customer = test_customer
        driver = test_driver

        resp = client.post("/api/rides/request", json={
            "customer_id": customer.id,
            "pickup_address": "123 Market St",
            "pickup_latitude": PICKUP_LAT,
            "pickup_longitude": PICKUP_LNG,
            "dropoff_address": "SFO Airport",
            "dropoff_latitude": DROPOFF_LAT,
            "dropoff_longitude": DROPOFF_LNG,
            "bidding_duration_minutes": 5,
        }, headers=customer_headers)
        ride_id = resp.json()["ride_request"]["id"]
        suggested = resp.json()["ride_request"]["suggested_price"]

        # Driver bids
        resp = client.post(f"/api/rides/request/{ride_id}/bid", json={
            "driver_id": driver.id,
            "proposed_price": suggested,
        }, headers=driver_headers)
        bid_id = resp.json()["bid"]["id"]

        # Manually set counter count to 3 (simulate 3 prior counters)
        db_session.expire_all()
        ride_obj = db_session.query(RideRequest).get(ride_id)
        ride_obj.customer_counter_count = 3
        db_session.commit()

        # 4th counter → 400
        resp = client.post(f"/api/rides/bid/{bid_id}/respond", json={
            "action": "counter",
            "counter_price": round(suggested * 0.8, 2),
        }, headers=customer_headers)
        assert resp.status_code == 400
        assert "Maximum 3 counter-offers" in resp.json()["detail"]

    def test_driver_cannot_bid_with_active_ride(
        self, client, db_session, test_customer, test_driver,
        customer_headers, driver_headers, mock_notifications,
    ):
        """Driver with an active ride cannot bid on new requests."""
        customer = test_customer
        driver = test_driver

        # Create an active ride for this driver
        active_ride = RideRequest(
            request_id="RIDE2026999999",
            customer_id=customer.id,
            pickup_address="A",
            pickup_latitude=37.78,
            pickup_longitude=-122.41,
            dropoff_address="B",
            dropoff_latitude=37.62,
            dropoff_longitude=-122.38,
            status=RideRequestStatus.IN_PROGRESS,
            matched_driver_id=driver.id,
        )
        db_session.add(active_ride)
        db_session.commit()

        # Create a new ride request (from a different customer)
        customer2 = Customer(
            first_name="Bob",
            last_name="Passenger",
            email=f"bob.{datetime.now().timestamp()}@test.com",
            phone="+14155550200",
            password_hash=get_password_hash("Pass123!"),
        )
        db_session.add(customer2)
        db_session.commit()
        db_session.refresh(customer2)

        customer2_token = create_access_token(data={
            "sub": customer2.email,
            "customer_id": customer2.id,
        })
        customer2_headers = {"Authorization": f"Bearer {customer2_token}"}

        resp = client.post("/api/rides/request", json={
            "customer_id": customer2.id,
            "pickup_address": "123 Market St",
            "pickup_latitude": PICKUP_LAT,
            "pickup_longitude": PICKUP_LNG,
            "dropoff_address": "SFO Airport",
            "dropoff_latitude": DROPOFF_LAT,
            "dropoff_longitude": DROPOFF_LNG,
            "bidding_duration_minutes": 5,
        }, headers=customer2_headers)
        new_ride_id = resp.json()["ride_request"]["id"]

        # Driver with active ride tries to bid → 400
        resp = client.post(f"/api/rides/request/{new_ride_id}/bid", json={
            "driver_id": driver.id,
            "proposed_price": 25.00,
        }, headers=driver_headers)
        assert resp.status_code == 400
        assert "active ride" in resp.json()["detail"].lower()

    def test_cancel_ride_request(
        self, client, db_session, test_customer, test_driver,
        customer_headers, driver_headers, mock_notifications,
    ):
        """Cancel an OPEN ride → all pending bids get expired."""
        customer = test_customer
        driver = test_driver

        resp = client.post("/api/rides/request", json={
            "customer_id": customer.id,
            "pickup_address": "123 Market St",
            "pickup_latitude": PICKUP_LAT,
            "pickup_longitude": PICKUP_LNG,
            "dropoff_address": "SFO Airport",
            "dropoff_latitude": DROPOFF_LAT,
            "dropoff_longitude": DROPOFF_LNG,
            "bidding_duration_minutes": 5,
        }, headers=customer_headers)
        ride_id = resp.json()["ride_request"]["id"]

        # Driver bids
        resp = client.post(f"/api/rides/request/{ride_id}/bid", json={
            "driver_id": driver.id,
            "proposed_price": 25.00,
        }, headers=driver_headers)
        bid_id = resp.json()["bid"]["id"]

        # Cancel
        resp = client.post(f"/api/rides/request/{ride_id}/cancel", headers=customer_headers)
        assert resp.status_code == 200
        assert resp.json()["success"] is True

        db_session.expire_all()
        ride_obj = db_session.query(RideRequest).get(ride_id)
        assert ride_obj.status == RideRequestStatus.CANCELLED

        bid_obj = db_session.query(RideBid).get(bid_id)
        assert bid_obj.status == BidStatus.EXPIRED

    def test_bid_on_expired_window(
        self, client, db_session, test_customer, test_driver,
        customer_headers, driver_headers, mock_notifications,
    ):
        """Bid after the bidding window expired → 400."""
        customer = test_customer
        driver = test_driver

        resp = client.post("/api/rides/request", json={
            "customer_id": customer.id,
            "pickup_address": "123 Market St",
            "pickup_latitude": PICKUP_LAT,
            "pickup_longitude": PICKUP_LNG,
            "dropoff_address": "SFO Airport",
            "dropoff_latitude": DROPOFF_LAT,
            "dropoff_longitude": DROPOFF_LNG,
            "bidding_duration_minutes": 5,
        }, headers=customer_headers)
        ride_id = resp.json()["ride_request"]["id"]

        # Manually expire the bidding window
        db_session.expire_all()
        ride_obj = db_session.query(RideRequest).get(ride_id)
        ride_obj.bidding_expires_at = datetime.utcnow() - timedelta(minutes=1)
        db_session.commit()

        # Attempt to bid → 400
        resp = client.post(f"/api/rides/request/{ride_id}/bid", json={
            "driver_id": driver.id,
            "proposed_price": 25.00,
        }, headers=driver_headers)
        assert resp.status_code == 400
        assert "closed" in resp.json()["detail"].lower()

    def test_tiered_pricing_tiers(
        self, client, db_session, test_customer, test_driver,
        customer_headers, driver_headers, mock_stripe, mock_notifications,
    ):
        """Verify $1/$2/$3 tier fees at $30, $50, and $80 fares."""
        customer = test_customer
        driver = test_driver

        test_cases = [
            (30.00, 1.00),   # Tier 1: fare ≤ $35 → $1
            (50.00, 2.00),   # Tier 2: $35 < fare ≤ $70 → $2
            (80.00, 3.00),   # Tier 3: fare > $70 → $3
        ]

        for fare, expected_fee in test_cases:
            # Create ride request
            resp = client.post("/api/rides/request", json={
                "customer_id": customer.id,
                "pickup_address": "A",
                "pickup_latitude": PICKUP_LAT,
                "pickup_longitude": PICKUP_LNG,
                "dropoff_address": "B",
                "dropoff_latitude": DROPOFF_LAT,
                "dropoff_longitude": DROPOFF_LNG,
                "bidding_duration_minutes": 5,
            }, headers=customer_headers)
            rid = resp.json()["ride_request"]["id"]

            # Set the final price and status directly for payment test
            db_session.expire_all()
            ride_obj = db_session.query(RideRequest).get(rid)
            ride_obj.final_price = fare
            ride_obj.status = RideRequestStatus.COMPLETED
            ride_obj.matched_driver_id = driver.id
            db_session.commit()

            # Reset stripe mock call count
            mock_stripe["payment_intent"].reset_mock()

            resp = client.post("/api/payments/ride/create-intent", json={
                "ride_request_id": rid,
            }, headers=customer_headers)
            assert resp.status_code == 200
            data = resp.json()
            assert data["tier_fee"] == expected_fee, (
                f"Fare ${fare}: expected tier_fee ${expected_fee}, got ${data['tier_fee']}"
            )
            cpuc_share = 0.05  # CPUC Access for All: $0.05 from the rider and $0.05 from the driver
            assert data["customer_pays"] == round(fare + expected_fee + cpuc_share, 2)
            assert data["driver_receives"] == round(fare - expected_fee - cpuc_share, 2)
            assert data["platform_earns"] == expected_fee * 2

    # ride_id verified: iOS passes Int (P2PAPIService.swift:5471 rideId: Int interpolated into URL)
    # backend expects int PK (main_new.py:15646 ride_id: int path param) — MATCH, no fix needed

    def test_wav_filter_excludes_non_capable_driver(
        self, client, db_session, test_customer, test_driver,
        customer_headers, driver_headers, mock_notifications,
    ):
        """bid_routes.py:1204-1207: WAV filter — driver with accessibility_capable=False must NOT see
        accessibility_requested=True rides; driver with accessibility_capable=True must see them."""
        import uuid
        customer = test_customer

        # Create a WAV ride request (accessibility_requested=True)
        resp = client.post("/api/rides/request", json={
            "customer_id": customer.id,
            "pickup_address": "123 Market St",
            "pickup_latitude": PICKUP_LAT,
            "pickup_longitude": PICKUP_LNG,
            "dropoff_address": "SFO Airport",
            "dropoff_latitude": DROPOFF_LAT,
            "dropoff_longitude": DROPOFF_LNG,
            "bidding_duration_minutes": 5,
            "accessibility_requested": True,
        }, headers=customer_headers)
        assert resp.status_code == 200
        wav_ride_id = resp.json()["ride_request"]["id"]

        # Verify WAV field was stored
        db_session.expire_all()
        ride_obj = db_session.query(RideRequest).get(wav_ride_id)
        assert ride_obj.accessibility_requested is True

        # Non-WAV driver (test_driver has accessibility_capable=False by default)
        non_wav_driver = test_driver
        assert non_wav_driver.accessibility_capable is False or getattr(non_wav_driver, 'accessibility_capable', False) is False

        resp = client.get("/api/rides/available", params={
            "driver_id": non_wav_driver.id,
            "latitude": PICKUP_LAT,
            "longitude": PICKUP_LNG,
        }, headers=driver_headers)
        assert resp.status_code == 200
        data = resp.json()
        wav_ride_ids = [r["id"] for r in data["available_requests"]]
        assert wav_ride_id not in wav_ride_ids, (
            "Non-WAV driver should NOT see accessibility_requested rides"
        )

        # WAV-capable driver should see the ride
        from models import DriverStatus
        wav_driver = Driver(
            driver_id=f"drv_{uuid.uuid4().hex[:8]}",
            email=f"wav_driver_{datetime.now().timestamp()}@test.com",
            password_hash=get_password_hash("DriverPass123!"),
            first_name="WAV",
            last_name="Driver",
            phone="+14155550999",
            is_online=True,
            status=DriverStatus.ACTIVE,
            accessibility_capable=True,
        )
        db_session.add(wav_driver)
        db_session.commit()
        db_session.refresh(wav_driver)

        wav_token = create_access_token(data={
            "sub": wav_driver.email,
            "driver_id": wav_driver.id,
        })
        wav_headers = {"Authorization": f"Bearer {wav_token}"}

        resp = client.get("/api/rides/available", params={
            "driver_id": wav_driver.id,
            "latitude": PICKUP_LAT,
            "longitude": PICKUP_LNG,
        }, headers=wav_headers)
        assert resp.status_code == 200
        data = resp.json()
        wav_ride_ids = [r["id"] for r in data["available_requests"]]
        assert wav_ride_id in wav_ride_ids, (
            "WAV-capable driver SHOULD see accessibility_requested rides"
        )

    def test_stripe_payment_failure_rollback(
        self, client, db_session, test_customer, test_driver,
        customer_headers, driver_headers, mock_notifications,
    ):
        """When Stripe.PaymentIntent.create raises StripeError during bid acceptance,
        the ride is still matched (non-blocking) but no payment intent ID is stored.
        The customer is NOT silently charged (no intent = no capture later).
        bid_routes.py:748-789: Stripe failure is caught as non-blocking exception."""
        import stripe as stripe_lib

        customer = test_customer
        driver = test_driver

        # Create ride request
        resp = client.post("/api/rides/request", json={
            "customer_id": customer.id,
            "pickup_address": "123 Market St",
            "pickup_latitude": PICKUP_LAT,
            "pickup_longitude": PICKUP_LNG,
            "dropoff_address": "SFO Airport",
            "dropoff_latitude": DROPOFF_LAT,
            "dropoff_longitude": DROPOFF_LNG,
            "bidding_duration_minutes": 5,
        }, headers=customer_headers)
        assert resp.status_code == 200
        ride_id = resp.json()["ride_request"]["id"]

        # Driver bids
        resp = client.post(f"/api/rides/request/{ride_id}/bid", json={
            "driver_id": driver.id,
            "proposed_price": 25.00,
        }, headers=driver_headers)
        assert resp.status_code == 200
        bid_id = resp.json()["bid"]["id"]

        # Customer accepts bid — with Stripe failing
        with patched_stripe() as mock_stripe_module:
            mock_stripe_module.PaymentIntent.create.side_effect = Exception(
                "StripeError: Your card was declined"
            )
            mock_stripe_module.Customer.list.return_value = MagicMock(data=[])
            mock_stripe_module.Customer.create.return_value = MagicMock(id="cus_test_fail")

            resp = client.post(f"/api/rides/bid/{bid_id}/respond", json={
                "action": "accept",
            }, headers=customer_headers)

        # Ride is still matched (Stripe failure is non-blocking per bid_routes.py:788-789)
        assert resp.status_code == 200
        data = resp.json()
        assert data["success"] is True
        assert data["driver"] is not None

        # No payment intent stored — customer NOT silently charged
        db_session.expire_all()
        ride_obj = db_session.query(RideRequest).get(ride_id)
        assert ride_obj.status == RideRequestStatus.MATCHED
        assert ride_obj.stripe_payment_intent_id is None, (
            "No payment intent should be stored when Stripe fails"
        )

    def test_driver_cancel_mid_ride(
        self, client, db_session, test_customer, test_driver,
        customer_headers, driver_headers, mock_notifications,
    ):
        """POST /api/rides/request/{id}/driver-cancel:
        - Requires driver auth and matched driver only (403 for wrong driver)
        - Requires MATCHED status
        - Transitions ride to OPEN (so other drivers can re-bid)
        - Matched bid transitions to WITHDRAWN
        bid_routes.py:1957-2041
        """
        import uuid
        customer = test_customer
        driver = test_driver

        # Create ride request
        resp = client.post("/api/rides/request", json={
            "customer_id": customer.id,
            "pickup_address": "123 Market St",
            "pickup_latitude": PICKUP_LAT,
            "pickup_longitude": PICKUP_LNG,
            "dropoff_address": "SFO Airport",
            "dropoff_latitude": DROPOFF_LAT,
            "dropoff_longitude": DROPOFF_LNG,
            "bidding_duration_minutes": 5,
        }, headers=customer_headers)
        assert resp.status_code == 200
        ride_id = resp.json()["ride_request"]["id"]

        # Driver bids
        resp = client.post(f"/api/rides/request/{ride_id}/bid", json={
            "driver_id": driver.id,
            "proposed_price": 25.00,
        }, headers=driver_headers)
        assert resp.status_code == 200
        bid_id = resp.json()["bid"]["id"]

        # Customer accepts bid (mock Stripe to avoid network calls)
        with patched_stripe() as mock_stripe_module:
            mock_stripe_module.PaymentIntent.create.return_value = MagicMock(id="pi_test_cancel")
            mock_stripe_module.Customer.list.return_value = MagicMock(data=[])
            mock_stripe_module.Customer.create.return_value = MagicMock(id="cus_test_cancel")

            resp = client.post(f"/api/rides/bid/{bid_id}/respond", json={
                "action": "accept",
            }, headers=customer_headers)
        assert resp.status_code == 200
        assert resp.json()["success"] is True

        db_session.expire_all()
        ride_obj = db_session.query(RideRequest).get(ride_id)
        assert ride_obj.status == RideRequestStatus.MATCHED

        # A different driver (not the matched one) tries to cancel — expect 403
        from models import DriverStatus
        other_driver = Driver(
            driver_id=f"drv_{uuid.uuid4().hex[:8]}",
            email=f"other_driver_{datetime.now().timestamp()}@test.com",
            password_hash=get_password_hash("DriverPass123!"),
            first_name="Other",
            last_name="Driver",
            phone="+14155550888",
            is_online=True,
            status=DriverStatus.ACTIVE,
        )
        db_session.add(other_driver)
        db_session.commit()
        db_session.refresh(other_driver)

        other_token = create_access_token(data={
            "sub": other_driver.email,
            "driver_id": other_driver.id,
        })
        other_headers = {"Authorization": f"Bearer {other_token}"}

        resp = client.post(
            f"/api/rides/request/{ride_id}/driver-cancel",
            json={"reason": "Change of plans"},
            headers=other_headers,
        )
        assert resp.status_code == 403, (
            f"Non-matched driver should get 403, got {resp.status_code}: {resp.json()}"
        )

        # Unauthenticated call — expect 401 or 403
        resp = client.post(
            f"/api/rides/request/{ride_id}/driver-cancel",
            json={"reason": "No auth"},
        )
        assert resp.status_code in (401, 403), (
            f"Unauthenticated cancel should be rejected, got {resp.status_code}"
        )

        # Matched driver cancels — ride reverts to OPEN, bid to WITHDRAWN
        with patched_stripe() as mock_stripe_module:
            mock_stripe_module.PaymentIntent.cancel.return_value = MagicMock()
            resp = client.post(
                f"/api/rides/request/{ride_id}/driver-cancel",
                json={"reason": "Emergency"},
                headers=driver_headers,
            )
        assert resp.status_code == 200
        data = resp.json()
        assert data["success"] is True

        db_session.expire_all()
        ride_obj = db_session.query(RideRequest).get(ride_id)
        assert ride_obj.status == RideRequestStatus.OPEN, (
            f"Ride should revert to OPEN after driver cancel, got {ride_obj.status}"
        )
        assert ride_obj.matched_driver_id is None

        bid_obj = db_session.query(RideBid).get(bid_id)
        assert bid_obj.status == BidStatus.WITHDRAWN, (
            f"Bid should be WITHDRAWN after driver cancel, got {bid_obj.status}"
        )
