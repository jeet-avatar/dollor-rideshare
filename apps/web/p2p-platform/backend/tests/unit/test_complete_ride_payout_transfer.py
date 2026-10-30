"""Completing a non-demo ride with a Stripe-onboarded driver must create the Connect transfer (regression: NameError on platform_fee)."""
from types import SimpleNamespace
from unittest.mock import patch

from main_new import create_access_token
from models import RideRequest

PICKUP = (37.7879, -122.4075)


def _headers(email, role, **ids):
    return {"Authorization": "Bearer " + create_access_token(data={"sub": email, "role": role, **ids})}


def test_complete_ride_creates_connect_transfer_for_onboarded_driver(client, db_session, monkeypatch, test_customer, test_driver):
    monkeypatch.setenv("STRIPE_SECRET_KEY", "sk_unit_test")
    test_driver.is_online = True
    test_driver.documents_verified = True
    test_driver.current_latitude, test_driver.current_longitude = PICKUP
    test_driver.stripe_account_id = "acct_unit_test"
    test_driver.stripe_onboarded = True
    db_session.commit()
    customer_h = _headers(test_customer.email, "customer", customer_id=test_customer.id)
    driver_h = _headers(test_driver.email, "driver", driver_id=test_driver.id)
    stripe_customer = SimpleNamespace(invoice_settings=SimpleNamespace(default_payment_method="pm_test"))
    transfers = []

    def fake_transfer_create(**kwargs):
        transfers.append(kwargs)
        return SimpleNamespace(id="tr_unit_test")

    with patch("bid_routes.send_push_notification"), patch("bid_routes.send_ride_request_confirmation_email"), \
            patch("bid_routes.asyncio.create_task"), patch("bid_routes._bg_email"), \
            patch("stripe.Customer.create", return_value=SimpleNamespace(id="cus_test")), \
            patch("stripe.Customer.retrieve", return_value=stripe_customer), \
            patch("stripe.PaymentIntent.create", return_value=SimpleNamespace(id="pi_test", status="requires_capture")), \
            patch("stripe.PaymentIntent.capture", return_value=SimpleNamespace(id="pi_test", status="succeeded")), \
            patch("stripe.PaymentIntent.retrieve", return_value=SimpleNamespace(id="pi_test", status="requires_capture", amount=1105)), \
            patch("stripe.PaymentIntent.modify", return_value=SimpleNamespace(id="pi_test", status="requires_capture")), \
            patch("stripe.Transfer.create", side_effect=fake_transfer_create):
        ride = client.post("/api/rides/request", json={
            "customer_id": test_customer.id, "pickup_address": "Union Square",
            "pickup_latitude": PICKUP[0], "pickup_longitude": PICKUP[1],
            "dropoff_address": "Ferry Building", "dropoff_latitude": 37.7955, "dropoff_longitude": -122.3937,
            "ride_type": "standard", "bidding_duration_minutes": 5,
        }, headers=customer_h).json()["ride_request"]
        bid = client.post(f"/api/rides/request/{ride['id']}/bid", json={
            "driver_id": test_driver.id, "proposed_price": 10.0, "estimated_arrival_minutes": 5,
        }, headers=driver_h).json()["bid"]
        assert client.post(f"/api/rides/bid/{bid['id']}/respond", json={"action": "accept"}, headers=customer_h).status_code == 200
        for step in ("arrived", "start"):
            r = client.post(f"/api/rides/request/{ride['id']}/{step}", headers=driver_h)
            assert r.status_code == 200, r.text
        done = client.post(f"/api/rides/request/{ride['id']}/complete", headers=driver_h)
        assert done.status_code == 200, done.text

    db_session.expire_all()
    row = db_session.query(RideRequest).get(ride["id"])
    assert transfers, "no Stripe transfer was created for the onboarded driver"
    assert transfers[0]["amount"] == int(round(row.driver_payout * 100))
    assert transfers[0]["metadata"]["platform_fee"] == str(row.platform_fee)
    assert row.stripe_transfer_id == "tr_unit_test"
