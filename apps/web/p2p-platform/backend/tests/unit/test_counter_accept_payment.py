"""A ride matched by the driver accepting the rider's counter-offer must be pre-authorized like any other match."""
from types import SimpleNamespace
from unittest.mock import MagicMock, patch

import pytest
import stripe

from main_new import create_access_token
from models import RideRequest, RideRequestStatus

PICKUP = (37.7879, -122.4075)
COUNTER_PRICE = 8.0


def _headers(email, role, **ids):
    return {"Authorization": "Bearer " + create_access_token(data={"sub": email, "role": role, **ids})}


@pytest.fixture
def countered_bid(client, db_session, test_customer, test_driver):
    test_driver.is_online = True
    test_driver.documents_verified = True
    test_driver.current_latitude, test_driver.current_longitude = PICKUP
    db_session.commit()
    customer_h = _headers(test_customer.email, "customer", customer_id=test_customer.id)
    driver_h = _headers(test_driver.email, "driver", driver_id=test_driver.id)

    with patch("bid_routes.send_push_notification"), patch("bid_routes.send_ride_request_confirmation_email"), \
            patch("bid_routes.asyncio.create_task"), patch("bid_routes._bg_email"):
        ride = client.post("/api/rides/request", json={
            "customer_id": test_customer.id, "pickup_address": "Union Square",
            "pickup_latitude": PICKUP[0], "pickup_longitude": PICKUP[1],
            "dropoff_address": "Ferry Building", "dropoff_latitude": 37.7955, "dropoff_longitude": -122.3937,
            "ride_type": "standard", "bidding_duration_minutes": 5,
        }, headers=customer_h).json()["ride_request"]
        bid = client.post(f"/api/rides/request/{ride['id']}/bid", json={
            "driver_id": test_driver.id, "proposed_price": 10.0, "estimated_arrival_minutes": 5,
        }, headers=driver_h)
        assert bid.status_code == 200, bid.text
        bid = bid.json()["bid"]
        counter = client.post(f"/api/rides/bid/{bid['id']}/respond",
                              json={"action": "counter", "counter_price": COUNTER_PRICE}, headers=customer_h)
        assert counter.status_code == 200, counter.text
    return SimpleNamespace(ride_id=ride["id"], bid_id=bid["id"], driver_h=driver_h)


def _stripe_ok():
    customer = SimpleNamespace(invoice_settings=SimpleNamespace(default_payment_method="pm_test"))
    return {
        "customer_create": patch("stripe.Customer.create", return_value=SimpleNamespace(id="cus_test")),
        "customer_retrieve": patch("stripe.Customer.retrieve", return_value=customer),
        "intent_create": patch("stripe.PaymentIntent.create",
                               return_value=SimpleNamespace(id="pi_test", status="requires_capture")),
    }


def test_accepting_a_counter_authorizes_the_countered_fare(client, db_session, monkeypatch, countered_bid):
    monkeypatch.setenv("STRIPE_SECRET_KEY", "sk_test_unit")
    mocks = _stripe_ok()
    with mocks["customer_create"], mocks["customer_retrieve"], mocks["intent_create"] as create, \
            patch("bid_routes.send_push_notification"), patch("bid_routes.asyncio.create_task"), patch("bid_routes._bg_email"):
        response = client.post(f"/api/rides/bid/{countered_bid.bid_id}/accept-counter", headers=countered_bid.driver_h)

    assert response.status_code == 200, response.text
    create.assert_called_once()
    kwargs = create.call_args.kwargs
    assert kwargs["amount"] == int(COUNTER_PRICE * 100)
    assert kwargs["capture_method"] == "manual"
    ride = db_session.query(RideRequest).get(countered_bid.ride_id)
    assert ride.stripe_payment_intent_id == "pi_test"
    assert ride.status == RideRequestStatus.MATCHED


def test_declined_card_cancels_the_ride_when_a_counter_is_accepted(client, db_session, monkeypatch, countered_bid):
    monkeypatch.setenv("STRIPE_SECRET_KEY", "sk_test_unit")
    mocks = _stripe_ok()
    declined = stripe.error.CardError(message="declined", param=None, code="card_declined")
    with mocks["customer_create"], mocks["customer_retrieve"], \
            patch("stripe.PaymentIntent.create", side_effect=declined), \
            patch("bid_routes.send_push_notification"), patch("bid_routes.asyncio.create_task"), patch("bid_routes._bg_email"):
        response = client.post(f"/api/rides/bid/{countered_bid.bid_id}/accept-counter", headers=countered_bid.driver_h)

    assert response.status_code == 402
    ride = db_session.query(RideRequest).get(countered_bid.ride_id)
    assert ride.status == RideRequestStatus.CANCELLED
    assert ride.payment_status == "pre_auth_failed"


def test_a_counter_cannot_be_accepted_once_the_ride_is_no_longer_open(client, db_session, countered_bid):
    ride = db_session.query(RideRequest).get(countered_bid.ride_id)
    ride.status = RideRequestStatus.CANCELLED
    db_session.commit()
    with patch("bid_routes.send_push_notification"), patch("bid_routes.asyncio.create_task"), patch("bid_routes._bg_email"):
        response = client.post(f"/api/rides/bid/{countered_bid.bid_id}/accept-counter", headers=countered_bid.driver_h)

    assert response.status_code == 409
    db_session.refresh(ride)
    assert ride.status == RideRequestStatus.CANCELLED
    assert ride.matched_driver_id is None
