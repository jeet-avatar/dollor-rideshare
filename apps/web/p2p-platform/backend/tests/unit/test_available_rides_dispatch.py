"""GET /api/rides/available applies the dispatch policy (nearest drivers, widening over time)."""
from datetime import datetime, timedelta
from unittest.mock import patch

import pytest

from main_new import create_access_token
from models import RideRequest

PICKUP = (37.7879, -122.4075)  # Union Square, SF
NEAR = (37.7879 + 1 / 69.0, -122.4075)    # ~1 mile away
FAR = (37.7879 + 8 / 69.0, -122.4075)     # ~8 miles away


@pytest.fixture
def online_driver(db_session, test_driver):
    test_driver.is_online = True
    test_driver.current_latitude, test_driver.current_longitude = NEAR
    db_session.commit()
    return test_driver


@pytest.fixture
def driver_headers_online(online_driver):
    token = create_access_token(data={"sub": online_driver.email, "role": "driver", "driver_id": online_driver.id})
    return {"Authorization": f"Bearer {token}"}


@pytest.fixture
def open_ride(client, db_session, test_customer):
    customer_headers = {"Authorization": "Bearer " + create_access_token(
        data={"sub": test_customer.email, "role": "customer", "customer_id": test_customer.id})}
    patches = [
        patch("bid_routes.send_push_notification"),
        patch("bid_routes.send_ride_request_confirmation_email"),
        patch("bid_routes.asyncio.create_task"),
    ]
    for p in patches:
        p.start()
    try:
        resp = client.post("/api/rides/request", json={
            "customer_id": test_customer.id,
            "pickup_address": "Union Square", "pickup_latitude": PICKUP[0], "pickup_longitude": PICKUP[1],
            "dropoff_address": "Ferry Building", "dropoff_latitude": 37.7955, "dropoff_longitude": -122.3937,
            "ride_type": "standard", "bidding_duration_minutes": 5,
        }, headers=customer_headers)
    finally:
        for p in patches:
            p.stop()
    assert resp.status_code == 200
    return resp.json()["ride_request"]["id"]


def available(client, headers, lat=None, lon=None):
    params = {} if lat is None else {"latitude": lat, "longitude": lon}
    resp = client.get("/api/rides/available", params=params, headers=headers)
    assert resp.status_code == 200
    return [r["id"] for r in resp.json()["available_requests"]]


def test_nearby_driver_sees_the_ride(client, open_ride, driver_headers_online):
    assert open_ride in available(client, driver_headers_online, *NEAR)


def test_far_driver_does_not_see_a_fresh_ride(client, open_ride, driver_headers_online):
    assert open_ride not in available(client, driver_headers_online, *FAR)


def test_search_widens_after_waiting(client, db_session, open_ride, driver_headers_online):
    ride = db_session.query(RideRequest).get(open_ride)
    ride.created_at = datetime.utcnow() - timedelta(seconds=70)  # past the 10-mile step
    db_session.commit()
    assert open_ride in available(client, driver_headers_online, *FAR)


def test_driver_without_location_still_sees_rides(client, open_ride, driver_headers_online):
    assert open_ride in available(client, driver_headers_online)


def test_shared_demo_driver_always_sees_rides(client, db_session, open_ride, driver_headers_online, online_driver):
    online_driver.email = "demo.driver@dollor.ai"
    db_session.commit()
    token = create_access_token(data={"sub": online_driver.email, "role": "driver", "driver_id": online_driver.id})
    assert open_ride in available(client, {"Authorization": f"Bearer {token}"}, *FAR)


def test_default_radius_reaches_the_widest_dispatch_step(client, db_session, open_ride, driver_headers_online):
    """Without a radius param (Android sends none) a driver 20 miles out still sees a ride once the search widened to 25 mi."""
    ride = db_session.query(RideRequest).get(open_ride)
    ride.created_at = datetime.utcnow() - timedelta(seconds=130)
    db_session.commit()
    twenty_miles_out = (37.7879 + 20 / 69.0, -122.4075)
    assert open_ride in available(client, driver_headers_online, *twenty_miles_out)
