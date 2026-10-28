"""A ride re-opened by the matched driver's cancel must get a fresh bidding window."""
from datetime import datetime, timedelta
from types import SimpleNamespace
from unittest.mock import patch

from main_new import create_access_token
from models import RideRequest, RideRequestStatus

PICKUP = (37.7879, -122.4075)


def _headers(email, role, **ids):
    return {"Authorization": "Bearer " + create_access_token(data={"sub": email, "role": role, **ids})}


def test_driver_cancel_resets_expired_bidding_window(client, db_session, monkeypatch, test_customer, test_driver):
    monkeypatch.setenv("STRIPE_SECRET_KEY", "sk_test_unit")
    test_driver.is_online = True
    test_driver.documents_verified = True
    test_driver.current_latitude, test_driver.current_longitude = PICKUP
    db_session.commit()
    customer_h = _headers(test_customer.email, "customer", customer_id=test_customer.id)
    driver_h = _headers(test_driver.email, "driver", driver_id=test_driver.id)
    stripe_customer = SimpleNamespace(invoice_settings=SimpleNamespace(default_payment_method="pm_test"))

    with patch("bid_routes.send_push_notification"), patch("bid_routes.send_ride_request_confirmation_email"), \
            patch("bid_routes.asyncio.create_task"), patch("bid_routes._bg_email"), \
            patch("stripe.Customer.create", return_value=SimpleNamespace(id="cus_test")), \
            patch("stripe.Customer.retrieve", return_value=stripe_customer), \
            patch("stripe.PaymentIntent.create", return_value=SimpleNamespace(id="demo_pi", status="requires_capture")), \
            patch("stripe.PaymentIntent.cancel"):
        ride = client.post("/api/rides/request", json={
            "customer_id": test_customer.id, "pickup_address": "Union Square",
            "pickup_latitude": PICKUP[0], "pickup_longitude": PICKUP[1],
            "dropoff_address": "Ferry Building", "dropoff_latitude": 37.7955, "dropoff_longitude": -122.3937,
            "ride_type": "standard", "bidding_duration_minutes": 5,
        }, headers=customer_h).json()["ride_request"]
        bid = client.post(f"/api/rides/request/{ride['id']}/bid", json={
            "driver_id": test_driver.id, "proposed_price": 10.0, "estimated_arrival_minutes": 5,
        }, headers=driver_h).json()["bid"]
        accepted = client.post(f"/api/rides/bid/{bid['id']}/respond", json={"action": "accept"}, headers=customer_h)
        assert accepted.status_code == 200, accepted.text

        # The original window has lapsed while the ride was matched
        row = db_session.query(RideRequest).get(ride["id"])
        row.bidding_expires_at = datetime.utcnow() - timedelta(minutes=10)
        db_session.commit()

        cancel = client.post(f"/api/rides/request/{ride['id']}/driver-cancel", json={"reason": "test"}, headers=driver_h)
        assert cancel.status_code == 200, cancel.text

    db_session.expire_all()
    row = db_session.query(RideRequest).get(ride["id"])
    assert row.status == RideRequestStatus.OPEN
    assert row.matched_driver_id is None
    assert row.bidding_expires_at > datetime.utcnow() + timedelta(minutes=4)
