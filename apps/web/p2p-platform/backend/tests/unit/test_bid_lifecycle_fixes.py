"""Re-bid after a decline, countered bids in the rider's list, first-name-only privacy, history timestamp."""
from unittest.mock import patch

import pytest

from main_new import create_access_token
from models import BidStatus, RideBid, RideRequest
from tests.unit.test_available_rides_dispatch import (  # noqa: F401  (fixtures)
    driver_headers_online, online_driver, open_ride,
)


@pytest.fixture(autouse=True)
def verified_driver(db_session, online_driver):
    online_driver.documents_verified = True
    online_driver.vehicle_make, online_driver.vehicle_model = "Toyota", "Prius"
    db_session.commit()


def _bid(client, headers, ride_id, price=12.0):
    with patch("bid_routes.send_push_notification"), patch("bid_routes._bg_email"), \
            patch("bid_routes.asyncio.create_task"):
        return client.post(f"/api/rides/request/{ride_id}/bid", json={"driver_id": 0, "proposed_price": price}, headers=headers)


def _set_status(db_session, ride_id, status):
    bid = db_session.query(RideBid).filter(RideBid.ride_request_id == ride_id).first()
    bid.status = status
    db_session.commit()
    return bid


def test_pending_bid_blocks_a_second_bid(client, open_ride, driver_headers_online):
    r = _bid(client, driver_headers_online, open_ride)
    assert r.status_code == 200, r.text
    assert _bid(client, driver_headers_online, open_ride, 13.0).status_code == 400


@pytest.mark.parametrize("status", [BidStatus.REJECTED, BidStatus.WITHDRAWN, BidStatus.EXPIRED])
def test_driver_can_rebid_after_a_dead_bid(client, db_session, open_ride, driver_headers_online, status):
    assert _bid(client, driver_headers_online, open_ride).status_code == 200
    _set_status(db_session, open_ride, status)
    assert _bid(client, driver_headers_online, open_ride, 14.0).status_code == 200


def test_countered_bid_blocks_a_second_bid(client, db_session, open_ride, driver_headers_online):
    assert _bid(client, driver_headers_online, open_ride).status_code == 200
    _set_status(db_session, open_ride, BidStatus.COUNTERED)
    assert _bid(client, driver_headers_online, open_ride, 14.0).status_code == 400


def test_rider_list_includes_countered_only_when_asked(client, db_session, open_ride, driver_headers_online, test_customer):
    assert _bid(client, driver_headers_online, open_ride).status_code == 200
    _set_status(db_session, open_ride, BidStatus.COUNTERED)
    rider = {"Authorization": "Bearer " + create_access_token(
        data={"sub": test_customer.email, "role": "customer", "customer_id": test_customer.id})}

    default = client.get(f"/api/rides/request/{open_ride}/bids", headers=rider).json()
    with_counters = client.get(f"/api/rides/request/{open_ride}/bids?include_countered=true", headers=rider).json()

    assert default["bids"] == []
    assert default["includes_countered"] is False
    assert with_counters["includes_countered"] is True
    assert [b["status"] for b in with_counters["bids"]] == ["countered"]


def test_driver_declining_a_counter_drops_it_from_the_rider_list(client, db_session, open_ride, driver_headers_online, test_customer):
    assert _bid(client, driver_headers_online, open_ride).status_code == 200
    bid = _set_status(db_session, open_ride, BidStatus.COUNTERED)
    rider = {"Authorization": "Bearer " + create_access_token(
        data={"sub": test_customer.email, "role": "customer", "customer_id": test_customer.id})}

    assert client.post(f"/api/rides/bid/{bid.id}/reject-counter", headers=driver_headers_online).status_code == 200

    listed = client.get(f"/api/rides/request/{open_ride}/bids?include_countered=true", headers=rider).json()["bids"]
    assert listed == []


def test_drivers_see_the_rider_first_name_only(client, db_session, open_ride, driver_headers_online):
    ride = db_session.query(RideRequest).get(open_ride)
    ride.customer_name = "Demo Customer"
    db_session.commit()

    resp = client.get("/api/rides/available", headers=driver_headers_online)

    assert resp.status_code == 200
    names = {r["id"]: r["customer_name"] for r in resp.json()["available_requests"]}
    assert names[open_ride] == "Demo"
