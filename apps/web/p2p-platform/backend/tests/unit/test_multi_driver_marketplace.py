"""Multi-driver marketplace behaviour: dispatch, bidding, counters, accept races and the bidding window.

Every external service (Stripe, email, push, websocket) is patched; nothing leaves the process.
"""
import asyncio
import itertools
from datetime import datetime, timedelta
from types import SimpleNamespace
from unittest.mock import MagicMock, patch

import pytest

from main_new import create_access_token, get_password_hash
from models import (
    BidStatus, Customer, Driver, DriverStatus, RideBid, RideRequest, RideRequestStatus,
)

PICKUP = (37.7879, -122.4075)  # Union Square, SF
DROPOFF = (37.7955, -122.3937)
MILE = 1 / 69.0  # degrees of latitude per mile
_seq = itertools.count(1)
_HASH = get_password_hash("Password123!")  # bcrypt once, not per fixture row


def at_miles(miles):
    return (PICKUP[0] + miles * MILE, PICKUP[1])


def _auth(email, role, **ids):
    return {"Authorization": "Bearer " + create_access_token(data={"sub": email, "role": role, **ids})}


class World:
    """Builds drivers/riders and drives the HTTP API with every outside call patched."""

    def __init__(self, client, db):
        self.client, self.db = client, db
        self.pushes = []

    # --- people -----------------------------------------------------------------
    def driver(self, miles=None, online=True, verified=True, wav=False, fcm=True, status=DriverStatus.APPROVED, **extra):
        n = next(_seq)
        d = Driver(
            driver_id=f"drv_mdm_{n}", email=f"mdm_driver_{n}@test.com", password_hash=_HASH,
            first_name=f"Drv{n}", last_name="Test", phone="+14155550000", status=status,
            documents_verified=verified, is_online=online, vehicle_make="Toyota", vehicle_model=f"Prius{n}",
            accessibility_capable=wav, fcm_token=f"fcm-{n}" if fcm else None, **extra,
        )
        if miles is not None:
            d.current_latitude, d.current_longitude = at_miles(miles)
        self.db.add(d)
        self.db.commit()
        d.h = _auth(d.email, "driver", driver_id=d.id)
        d.miles = miles
        return d

    def rider(self):
        n = next(_seq)
        c = Customer(email=f"mdm_rider_{n}@test.com", password_hash=_HASH,
                     first_name=f"Rider{n}", last_name="Test", phone="+14155551111", is_active=True)
        self.db.add(c)
        self.db.commit()
        c.h = _auth(c.email, "customer", customer_id=c.id)
        return c

    # --- rides ------------------------------------------------------------------
    def request_ride(self, rider, wav=False, minutes=5):
        """Create a ride; returns (ride_id, ids of drivers the push batch was addressed to, in call order)."""
        captured = []

        def fake_create_task(coro, *a, **k):
            captured.append(coro)
            return MagicMock()

        with patch("bid_routes.send_push_notification") as push, patch("bid_routes._bg_email"), \
                patch("bid_routes.asyncio.create_task", side_effect=fake_create_task):
            resp = self.client.post("/api/rides/request", json={
                "customer_id": rider.id, "pickup_address": "Union Square",
                "pickup_latitude": PICKUP[0], "pickup_longitude": PICKUP[1],
                "dropoff_address": "Ferry Building", "dropoff_latitude": DROPOFF[0], "dropoff_longitude": DROPOFF[1],
                "ride_type": "standard", "bidding_duration_minutes": minutes, "accessibility_requested": wav,
            }, headers=rider.h)
            assert resp.status_code == 200, resp.text
            for coro in captured:
                if getattr(coro, "__name__", "") == "_send_push_batch":
                    asyncio.run(coro)
                else:
                    coro.close()
            notified = [c.kwargs["user_id"] for c in push.call_args_list if c.kwargs.get("user_type") == "driver"]
        return resp.json()["ride_request"]["id"], notified

    def age(self, ride_id, seconds):
        ride = self.db.query(RideRequest).get(ride_id)
        ride.created_at = datetime.utcnow() - timedelta(seconds=seconds)
        self.db.commit()

    def visible_to(self, driver, ride_id=None, with_location=True):
        params = {"latitude": at_miles(driver.miles)[0], "longitude": PICKUP[1]} if with_location and driver.miles is not None else {}
        resp = self.client.get("/api/rides/available", params=params, headers=driver.h)
        assert resp.status_code == 200, resp.text
        ids = [r["id"] for r in resp.json()["available_requests"]]
        return ids if ride_id is None else ride_id in ids

    def bid(self, driver, ride_id, price=12.0, eta=5):
        with patch("bid_routes.send_push_notification"), patch("bid_routes._bg_email"), patch("bid_routes.asyncio.create_task"):
            return self.client.post(f"/api/rides/request/{ride_id}/bid", json={
                "driver_id": driver.id, "proposed_price": price, "estimated_arrival_minutes": eta}, headers=driver.h)

    def call(self, method, url, headers, **kw):
        stripe_customer = SimpleNamespace(invoice_settings=SimpleNamespace(default_payment_method="pm_test"))
        with patch("bid_routes.send_push_notification"), patch("bid_routes._bg_email"), patch("bid_routes.asyncio.create_task"), \
                patch("stripe.Customer.create", return_value=SimpleNamespace(id="cus_test")), \
                patch("stripe.Customer.retrieve", return_value=stripe_customer), \
                patch("stripe.PaymentIntent.create", return_value=SimpleNamespace(id="pi_test", status="requires_capture")), \
                patch("stripe.PaymentIntent.cancel"):
            return getattr(self.client, method)(url, headers=headers, **kw)

    def respond(self, rider, bid_id, action, **kw):
        return self.call("post", f"/api/rides/bid/{bid_id}/respond", rider.h, json={"action": action, **kw})

    def accept_counter(self, driver, bid_id):
        return self.call("post", f"/api/rides/bid/{bid_id}/accept-counter", driver.h)

    def bids_for(self, rider, ride_id, **params):
        resp = self.client.get(f"/api/rides/request/{ride_id}/bids", params=params, headers=rider.h)
        assert resp.status_code == 200, resp.text
        return resp.json()

    def ride(self, ride_id):
        self.db.expire_all()
        return self.db.query(RideRequest).get(ride_id)

    def bid_row(self, bid_id):
        self.db.expire_all()
        return self.db.query(RideBid).get(bid_id)


@pytest.fixture(autouse=True)
def stripe_env(monkeypatch):
    monkeypatch.setenv("STRIPE_SECRET_KEY", "sk_test_unit")


@pytest.fixture
def world(client, db_session):
    return World(client, db_session)


# =============================================================================
# (1) HOW DRIVERS ARE CONTACTED
# =============================================================================

def six_drivers(world):
    return {m: world.driver(miles=m) for m in (0.5, 1, 4, 8, 12, 30)}


@pytest.mark.parametrize("age_seconds, expected_miles", [
    (0, {0.5, 1}),
    (30, {0.5, 1, 4}),
    (60, {0.5, 1, 4, 8}),
    (120, {0.5, 1, 4, 8, 12}),
])
def test_visible_set_widens_with_age(world, age_seconds, expected_miles):
    drivers = six_drivers(world)
    ride_id, _ = world.request_ride(world.rider())
    world.age(ride_id, age_seconds)
    seen = {m for m, d in drivers.items() if world.visible_to(d, ride_id)}
    assert seen == expected_miles


def test_visible_set_is_capped_to_the_nearest_ten(world):
    drivers = [world.driver(miles=0.1 + i * 0.1) for i in range(12)]  # all inside 3 mi
    ride_id, _ = world.request_ride(world.rider())
    seen = [d for d in drivers if world.visible_to(d, ride_id)]
    assert seen == drivers[:10]


def test_offline_driver_sees_nothing_and_does_not_take_a_slot(world):
    offline = [world.driver(miles=0.1 + i * 0.05, online=False) for i in range(10)]
    online = world.driver(miles=2.0)
    ride_id, _ = world.request_ride(world.rider())
    assert all(world.visible_to(d, ride_id) is False for d in offline)
    assert world.visible_to(online, ride_id) is True


def test_driver_without_location_sees_every_open_ride(world):
    nolocation = world.driver(miles=None)
    ride_id, _ = world.request_ride(world.rider())
    assert world.visible_to(nolocation, ride_id) is True


def test_busy_driver_does_not_take_one_of_the_ten_slots(world):
    """Drivers already on a ride cannot bid, so they must not push real candidates out of the nearest ten."""
    rider = world.rider()
    busy = []
    for i in range(10):
        d = world.driver(miles=0.1 + i * 0.05)
        db_ride = RideRequest(
            request_id=f"RIDE-BUSY-{d.id}", customer_id=rider.id, pickup_address="a", pickup_latitude=PICKUP[0],
            pickup_longitude=PICKUP[1], dropoff_address="b", dropoff_latitude=DROPOFF[0], dropoff_longitude=DROPOFF[1],
            status=RideRequestStatus.IN_PROGRESS, matched_driver_id=d.id)
        world.db.add(db_ride)
        busy.append(d)
    world.db.commit()
    free = world.driver(miles=2.5)
    ride_id, _ = world.request_ride(world.rider())
    assert world.visible_to(free, ride_id) is True


def test_unapproved_or_unverified_driver_does_not_take_a_slot(world):
    for i in range(10):
        world.driver(miles=0.1 + i * 0.05, verified=False, status=DriverStatus.PENDING)
    free = world.driver(miles=2.5)
    ride_id, _ = world.request_ride(world.rider())
    assert world.visible_to(free, ride_id) is True


def test_shared_demo_driver_sees_far_rides(world):
    demo = world.driver(miles=30)
    demo.email = "demo.driver@dollor.ai"
    world.db.commit()
    demo.h = _auth(demo.email, "driver", driver_id=demo.id)
    ride_id, _ = world.request_ride(world.rider())
    assert world.visible_to(demo, ride_id) is True


def test_wav_request_only_visible_to_wav_capable_drivers(world):
    plain = world.driver(miles=1)
    wav = world.driver(miles=2, wav=True)
    ride_id, _ = world.request_ride(world.rider(), wav=True)
    assert world.visible_to(plain, ride_id) is False
    assert world.visible_to(wav, ride_id) is True


def test_non_wav_drivers_do_not_take_wav_slots(world):
    for i in range(10):
        world.driver(miles=0.1 + i * 0.05)  # plain drivers, closer than the WAV one
    wav = world.driver(miles=2.5, wav=True)
    ride_id, _ = world.request_ride(world.rider(), wav=True)
    assert world.visible_to(wav, ride_id) is True


def test_push_goes_to_nearest_first_and_equals_the_visible_set(world):
    drivers = six_drivers(world)
    ride_id, notified = world.request_ride(world.rider())
    visible = [d.id for d in sorted(drivers.values(), key=lambda d: d.miles) if world.visible_to(d, ride_id)]
    assert notified == visible
    assert notified == [drivers[0.5].id, drivers[1].id]
    assert world.ride(ride_id).drivers_notified == len(notified)


def test_push_skips_offline_drivers_and_those_without_a_token(world):
    online = world.driver(miles=1)
    world.driver(miles=1.2, online=False)
    world.driver(miles=1.4, fcm=False)
    ride_id, notified = world.request_ride(world.rider())
    assert notified == [online.id]


def test_push_is_capped_at_ten_nearest(world):
    drivers = [world.driver(miles=0.1 + i * 0.1) for i in range(12)]
    ride_id, notified = world.request_ride(world.rider())
    assert notified == [d.id for d in drivers[:10]]
    assert world.ride(ride_id).drivers_notified == 10


def test_push_for_wav_ride_only_reaches_wav_drivers(world):
    world.driver(miles=1)
    wav = world.driver(miles=2, wav=True)
    ride_id, notified = world.request_ride(world.rider(), wav=True)
    assert notified == [wav.id]


# =============================================================================
# (2) HOW THEY BID
# =============================================================================

class _SessionProxy:
    """Lets the background jobs (which open their own SessionLocal) run against the test session."""

    def __init__(self, db):
        self._db = db

    def close(self):
        pass

    def __getattr__(self, name):
        return getattr(self._db, name)


def run_job(world, job_name):
    import bid_routes
    with patch("bid_routes.SessionLocal", return_value=_SessionProxy(world.db)), \
            patch("order_flow.send_push_notification"):
        getattr(bid_routes, job_name)()
    world.db.expire_all()


def lapse_window(world, ride_id):
    ride = world.db.query(RideRequest).get(ride_id)
    ride.bidding_expires_at = datetime.utcnow() - timedelta(seconds=1)
    world.db.commit()


def test_rider_sees_bids_cheapest_first_with_vehicle_and_eta(world):
    rider = world.rider()
    d1, d2, d3 = world.driver(miles=1), world.driver(miles=2), world.driver(miles=3)
    ride_id, _ = world.request_ride(rider)
    for d, price, eta in ((d1, 15.0, 4), (d2, 9.0, 11), (d3, 12.0, 7)):
        assert world.bid(d, ride_id, price, eta).status_code == 200
    body = world.bids_for(rider, ride_id)
    assert [b["proposed_price"] for b in body["bids"]] == [9.0, 12.0, 15.0]
    assert [b["estimated_arrival_minutes"] for b in body["bids"]] == [11, 7, 4]
    assert body["total_bids"] == 3
    assert body["bidding_open"] is True
    assert body["bidding_ends_at"]
    first = body["bids"][0]
    assert first["driver_vehicle_make"] == "Toyota" and first["driver_vehicle_model"] == d2.vehicle_model
    assert first["status"] == "pending" and first["expires_at"]
    assert world.ride(ride_id).status == RideRequestStatus.BIDDING


def test_max_bids_default_is_ten_and_the_eleventh_is_refused(world):
    rider = world.rider()
    drivers = [world.driver(miles=0.5) for _ in range(11)]
    ride_id, _ = world.request_ride(rider)
    codes = [world.bid(d, ride_id, 10.0 + i).status_code for i, d in enumerate(drivers)]
    assert codes == [200] * 10 + [400]
    assert world.bids_for(rider, ride_id)["total_bids"] == 10


def test_max_bids_can_be_lowered_per_ride(world):
    rider = world.rider()
    drivers = [world.driver(miles=0.5) for _ in range(4)]
    ride_id, _ = world.request_ride(rider)
    ride = world.db.query(RideRequest).get(ride_id)
    ride.max_bids = 3
    world.db.commit()
    assert [world.bid(d, ride_id).status_code for d in drivers] == [200, 200, 200, 400]


def test_a_withdrawn_bid_frees_a_slot_for_another_driver(world):
    rider = world.rider()
    drivers = [world.driver(miles=0.5) for _ in range(3)]
    ride_id, _ = world.request_ride(rider)
    world.db.query(RideRequest).get(ride_id).max_bids = 2
    world.db.commit()
    first = world.bid(drivers[0], ride_id).json()["bid"]
    assert world.bid(drivers[1], ride_id).status_code == 200
    assert world.bid(drivers[2], ride_id).status_code == 400
    assert world.call("post", f"/api/rides/bid/{first['id']}/withdraw", drivers[0].h).status_code == 200
    assert world.bid(drivers[2], ride_id).status_code == 200


def test_duplicate_bid_by_same_driver_is_refused_and_leaves_one_row(world):
    d = world.driver(miles=1)
    ride_id, _ = world.request_ride(world.rider())
    assert world.bid(d, ride_id, 10).status_code == 200
    assert world.bid(d, ride_id, 11).status_code == 400
    assert world.db.query(RideBid).filter(RideBid.ride_request_id == ride_id).count() == 1


def test_bid_after_the_window_closed_is_refused_even_before_the_cleanup_job_runs(world):
    d = world.driver(miles=1)
    ride_id, _ = world.request_ride(world.rider())
    lapse_window(world, ride_id)
    resp = world.bid(d, ride_id)
    assert resp.status_code == 400 and "closed" in resp.json()["detail"]


def test_bid_on_an_expired_ride_is_refused(world):
    d = world.driver(miles=1)
    ride_id, _ = world.request_ride(world.rider())
    lapse_window(world, ride_id)
    run_job(world, "check_ride_bidding_expiry_job")
    assert world.ride(ride_id).status == RideRequestStatus.EXPIRED
    resp = world.bid(d, ride_id)
    assert resp.status_code == 400 and "expired" in resp.json()["detail"]


def test_bid_on_a_ride_matched_to_someone_else_is_refused(world):
    rider = world.rider()
    a, b = world.driver(miles=1), world.driver(miles=2)
    ride_id, _ = world.request_ride(rider)
    bid_a = world.bid(a, ride_id).json()["bid"]
    assert world.respond(rider, bid_a["id"], "accept").status_code == 200
    resp = world.bid(b, ride_id)
    assert resp.status_code == 400 and "matched" in resp.json()["detail"]


def test_driver_with_an_active_ride_cannot_bid(world):
    busy = world.driver(miles=1)
    first_ride, _ = world.request_ride(world.rider())
    rider2 = world.rider()
    bid = world.bid(busy, first_ride).json()["bid"]
    rider1 = world.db.query(Customer).get(world.db.query(RideRequest).get(first_ride).customer_id)
    rider1.h = _auth(rider1.email, "customer", customer_id=rider1.id)
    assert world.respond(rider1, bid["id"], "accept").status_code == 200
    second_ride, _ = world.request_ride(rider2)
    resp = world.bid(busy, second_ride)
    assert resp.status_code == 400 and "active ride" in resp.json()["detail"]


@pytest.mark.parametrize("price", [0, -5, 10001, 99999999])
def test_out_of_range_bid_prices_are_rejected(world, price):
    d = world.driver(miles=1)
    ride_id, _ = world.request_ride(world.rider())
    assert world.bid(d, ride_id, price).status_code in (400, 422)
    assert world.db.query(RideBid).count() == 0


def test_non_numeric_bid_price_is_rejected(world):
    d = world.driver(miles=1)
    ride_id, _ = world.request_ride(world.rider())
    resp = world.client.post(f"/api/rides/request/{ride_id}/bid", json={"driver_id": d.id, "proposed_price": "abc"}, headers=d.h)
    assert resp.status_code == 422
    resp = world.client.post(f"/api/rides/request/{ride_id}/bid", json={"driver_id": d.id, "proposed_price": None}, headers=d.h)
    assert resp.status_code == 422


@pytest.mark.parametrize("price", [0.50, 1.00, 1.05])
def test_bid_that_would_pay_the_driver_nothing_is_rejected(world, price):
    """Fee is $1 plus a $0.05 driver Access-for-All share; a bid at or below $1.05 leaves the driver with <= $0."""
    d = world.driver(miles=1)
    ride_id, _ = world.request_ride(world.rider())
    resp = world.bid(d, ride_id, price)
    assert resp.status_code == 400
    assert "platform fee" in resp.json()["detail"]


def test_bid_just_above_the_fee_floor_is_accepted(world):
    d = world.driver(miles=1)
    ride_id, _ = world.request_ride(world.rider())
    assert world.bid(d, ride_id, 1.06).status_code == 200


def test_driver_can_update_a_pending_bid_and_rider_sees_the_new_price(world):
    rider = world.rider()
    d = world.driver(miles=1)
    ride_id, _ = world.request_ride(rider)
    bid = world.bid(d, ride_id, 14).json()["bid"]
    resp = world.call("put", f"/api/rides/bid/{bid['id']}", d.h, json={"proposed_price": 11.5})
    assert resp.status_code == 200
    assert world.bids_for(rider, ride_id)["bids"][0]["proposed_price"] == 11.5


@pytest.mark.parametrize("price", [0, -1, 10001])
def test_bid_update_validates_price(world, price):
    d = world.driver(miles=1)
    ride_id, _ = world.request_ride(world.rider())
    bid = world.bid(d, ride_id, 14).json()["bid"]
    assert world.call("put", f"/api/rides/bid/{bid['id']}", d.h, json={"proposed_price": price}).status_code in (400, 422)
    assert world.bid_row(bid["id"]).proposed_price == 14


def test_bid_update_cannot_undercut_the_fee_floor(world):
    d = world.driver(miles=1)
    ride_id, _ = world.request_ride(world.rider())
    bid = world.bid(d, ride_id, 14).json()["bid"]
    resp = world.call("put", f"/api/rides/bid/{bid['id']}", d.h, json={"proposed_price": 1.0})
    assert resp.status_code == 400
    assert world.bid_row(bid["id"]).proposed_price == 14


def test_only_the_owner_can_update_or_withdraw(world):
    a, b = world.driver(miles=1), world.driver(miles=2)
    ride_id, _ = world.request_ride(world.rider())
    bid = world.bid(a, ride_id, 14).json()["bid"]
    assert world.call("put", f"/api/rides/bid/{bid['id']}", b.h, json={"proposed_price": 5}).status_code == 403
    assert world.call("post", f"/api/rides/bid/{bid['id']}/withdraw", b.h).status_code == 403


def test_bid_update_is_refused_once_the_window_closed(world):
    d = world.driver(miles=1)
    ride_id, _ = world.request_ride(world.rider())
    bid = world.bid(d, ride_id, 14).json()["bid"]
    lapse_window(world, ride_id)
    resp = world.call("put", f"/api/rides/bid/{bid['id']}", d.h, json={"proposed_price": 9})
    assert resp.status_code == 400
    assert world.bid_row(bid["id"]).proposed_price == 14


def test_withdraw_reopens_the_ride_only_when_no_other_bid_is_live(world):
    rider = world.rider()
    a, b = world.driver(miles=1), world.driver(miles=2)
    ride_id, _ = world.request_ride(rider)
    bid_a = world.bid(a, ride_id).json()["bid"]
    bid_b = world.bid(b, ride_id).json()["bid"]
    assert world.call("post", f"/api/rides/bid/{bid_a['id']}/withdraw", a.h).status_code == 200
    assert world.ride(ride_id).status == RideRequestStatus.BIDDING
    assert [x["id"] for x in world.bids_for(rider, ride_id)["bids"]] == [bid_b["id"]]
    assert world.call("post", f"/api/rides/bid/{bid_b['id']}/withdraw", b.h).status_code == 200
    assert world.ride(ride_id).status == RideRequestStatus.OPEN
    assert world.bids_for(rider, ride_id)["bids"] == []


def test_withdrawn_bid_cannot_be_withdrawn_or_updated_again(world):
    d = world.driver(miles=1)
    ride_id, _ = world.request_ride(world.rider())
    bid = world.bid(d, ride_id).json()["bid"]
    assert world.call("post", f"/api/rides/bid/{bid['id']}/withdraw", d.h).status_code == 200
    assert world.call("post", f"/api/rides/bid/{bid['id']}/withdraw", d.h).status_code == 400
    assert world.call("put", f"/api/rides/bid/{bid['id']}", d.h, json={"proposed_price": 9}).status_code == 400


def test_bid_expires_after_ten_minutes_and_the_job_marks_it_expired(world):
    rider = world.rider()
    d = world.driver(miles=1)
    ride_id, _ = world.request_ride(rider, minutes=30)
    bid = world.bid(d, ride_id).json()["bid"]
    row = world.db.query(RideBid).get(bid["id"])
    assert timedelta(minutes=9, seconds=50) < row.expires_at - datetime.utcnow() <= timedelta(minutes=10)
    row.expires_at = datetime.utcnow() - timedelta(seconds=1)
    world.db.commit()
    run_job(world, "check_individual_bid_expiry_job")
    assert world.bid_row(bid["id"]).status == BidStatus.EXPIRED
    assert world.bids_for(rider, ride_id)["bids"] == []


def test_a_lapsed_bid_is_not_shown_or_acceptable_before_the_job_runs(world):
    rider = world.rider()
    d = world.driver(miles=1)
    ride_id, _ = world.request_ride(rider, minutes=30)
    bid = world.bid(d, ride_id).json()["bid"]
    row = world.db.query(RideBid).get(bid["id"])
    row.expires_at = datetime.utcnow() - timedelta(seconds=1)
    world.db.commit()
    assert world.bids_for(rider, ride_id)["bids"] == []
    resp = world.respond(rider, bid["id"], "accept")
    assert resp.status_code == 400
    assert world.ride(ride_id).status != RideRequestStatus.MATCHED


def test_expired_bid_can_be_replaced_by_the_same_driver(world):
    d = world.driver(miles=1)
    ride_id, _ = world.request_ride(world.rider(), minutes=30)
    bid = world.bid(d, ride_id, 10).json()["bid"]
    row = world.db.query(RideBid).get(bid["id"])
    row.expires_at = datetime.utcnow() - timedelta(seconds=1)
    world.db.commit()
    run_job(world, "check_individual_bid_expiry_job")
    again = world.bid(d, ride_id, 9)
    assert again.status_code == 200
    assert world.db.query(RideBid).filter(RideBid.ride_request_id == ride_id).count() == 1


def test_driver_going_offline_mid_bid_keeps_the_bid_but_leaves_the_feed(world):
    rider = world.rider()
    d = world.driver(miles=1)
    ride_id, _ = world.request_ride(rider)
    assert world.bid(d, ride_id).status_code == 200
    d.is_online = False
    world.db.commit()
    assert world.visible_to(d) == []
    assert len(world.bids_for(rider, ride_id)["bids"]) == 1


def test_offline_driver_cannot_place_a_new_bid(world):
    d = world.driver(miles=1)
    ride_id, _ = world.request_ride(world.rider())
    d.is_online = False
    world.db.commit()
    assert world.bid(d, ride_id).status_code == 403


def test_unverified_or_unapproved_driver_cannot_bid(world):
    ride_id, _ = world.request_ride(world.rider())
    assert world.bid(world.driver(miles=1, verified=False), ride_id).status_code == 403
    assert world.bid(world.driver(miles=1, status=DriverStatus.PENDING), ride_id).status_code == 403


# =============================================================================
# (3) COUNTERS / ACCEPT RACES
# =============================================================================

def assert_single_consistent_match(world, ride_id, winner_bid_id, winner_driver):
    ride = world.ride(ride_id)
    assert ride.status == RideRequestStatus.MATCHED
    assert ride.matched_driver_id == winner_driver.id
    assert ride.matched_bid_id == winner_bid_id
    bids = world.db.query(RideBid).filter(RideBid.ride_request_id == ride_id).all()
    accepted = [b for b in bids if b.status == BidStatus.ACCEPTED]
    assert [b.id for b in accepted] == [winner_bid_id]
    assert all(b.status in (BidStatus.ACCEPTED, BidStatus.REJECTED) for b in bids)


def two_countered_bids(world):
    rider = world.rider()
    a, b = world.driver(miles=1), world.driver(miles=2)
    ride_id, _ = world.request_ride(rider)
    bid_a = world.bid(a, ride_id, 20).json()["bid"]
    bid_b = world.bid(b, ride_id, 21).json()["bid"]
    suggested = world.ride(ride_id).suggested_price
    counter = round(max(suggested * 0.7, 5.0), 2)
    assert counter < 20
    assert world.respond(rider, bid_a["id"], "counter", counter_price=counter).status_code == 200
    assert world.respond(rider, bid_b["id"], "counter", counter_price=counter).status_code == 200
    return SimpleNamespace(rider=rider, a=a, b=b, ride_id=ride_id, bid_a=bid_a["id"], bid_b=bid_b["id"], counter=counter)


def test_rider_counters_two_drivers_first_accept_wins_and_second_gets_409(world):
    s = two_countered_bids(world)
    assert world.accept_counter(s.a, s.bid_a).status_code == 200
    late = world.accept_counter(s.b, s.bid_b)
    assert late.status_code == 409
    assert_single_consistent_match(world, s.ride_id, s.bid_a, s.a)
    assert world.bid_row(s.bid_b).status == BidStatus.REJECTED
    assert world.ride(s.ride_id).final_price == s.counter


def test_losing_driver_cannot_revive_the_closed_bid_with_a_counter(world):
    s = two_countered_bids(world)
    assert world.accept_counter(s.b, s.bid_b).status_code == 200
    resp = world.call("post", f"/api/rides/bid/{s.bid_a}/driver-counter", s.a.h, json={"counter_price": 19})
    assert resp.status_code == 400
    assert_single_consistent_match(world, s.ride_id, s.bid_b, s.b)


def test_rider_accepts_a_bid_after_a_counter_was_accepted_is_refused(world):
    rider = world.rider()
    a, b = world.driver(miles=1), world.driver(miles=2)
    ride_id, _ = world.request_ride(rider)
    bid_a = world.bid(a, ride_id, 20).json()["bid"]
    bid_b = world.bid(b, ride_id, 18).json()["bid"]
    counter = round(max(world.ride(ride_id).suggested_price * 0.7, 5.0), 2)
    assert world.respond(rider, bid_a["id"], "counter", counter_price=counter).status_code == 200
    assert world.accept_counter(a, bid_a["id"]).status_code == 200
    late = world.respond(rider, bid_b["id"], "accept")
    assert late.status_code in (400, 409)
    assert_single_consistent_match(world, ride_id, bid_a["id"], a)


def test_driver_accepts_counter_after_rider_accepted_another_bid_gets_409(world):
    rider = world.rider()
    a, b = world.driver(miles=1), world.driver(miles=2)
    ride_id, _ = world.request_ride(rider)
    bid_a = world.bid(a, ride_id, 20).json()["bid"]
    bid_b = world.bid(b, ride_id, 18).json()["bid"]
    counter = round(max(world.ride(ride_id).suggested_price * 0.7, 5.0), 2)
    assert world.respond(rider, bid_a["id"], "counter", counter_price=counter).status_code == 200
    assert world.respond(rider, bid_b["id"], "accept").status_code == 200
    late = world.accept_counter(a, bid_a["id"])
    assert late.status_code == 409
    assert_single_consistent_match(world, ride_id, bid_b["id"], b)


def test_a_competing_match_landing_between_read_and_write_cannot_be_overwritten(world):
    """Both accepts read the ride as open; the database, not the stale read, must decide the single winner."""
    from sqlalchemy import event, text

    s = two_countered_bids(world)
    fired = []

    @event.listens_for(world.db, "do_orm_execute")
    def steal(orm_execute):
        if orm_execute.is_update and not fired and "ride_requests" in str(orm_execute.statement):
            fired.append(True)
            world.db.connection().execute(text(
                "UPDATE ride_requests SET status='MATCHED', matched_driver_id=:d, matched_bid_id=:b WHERE id=:r"
            ), {"d": s.b.id, "b": s.bid_b, "r": s.ride_id})

    try:
        resp = world.accept_counter(s.a, s.bid_a)
    finally:
        event.remove(world.db, "do_orm_execute", steal)

    assert fired, "the competing match never ran"
    assert resp.status_code == 409
    ride = world.ride(s.ride_id)
    assert ride.matched_driver_id == s.b.id and ride.matched_bid_id == s.bid_b
    assert world.bid_row(s.bid_a).status != BidStatus.ACCEPTED


def test_double_accept_of_the_same_bid_matches_once(world):
    rider = world.rider()
    d = world.driver(miles=1)
    ride_id, _ = world.request_ride(rider)
    bid = world.bid(d, ride_id, 12).json()["bid"]
    assert world.respond(rider, bid["id"], "accept").status_code == 200
    assert world.respond(rider, bid["id"], "accept").status_code == 400
    assert d.ride_accept_count == 1
    assert_single_consistent_match(world, ride_id, bid["id"], d)


def test_double_accept_counter_matches_once(world):
    s = two_countered_bids(world)
    assert world.accept_counter(s.a, s.bid_a).status_code == 200
    assert world.accept_counter(s.a, s.bid_a).status_code in (400, 409)
    assert_single_consistent_match(world, s.ride_id, s.bid_a, s.a)


def test_accept_after_rider_cancel_is_refused_for_bid_and_counter(world):
    s = two_countered_bids(world)
    assert world.call("post", f"/api/rides/request/{s.ride_id}/cancel", s.rider.h).status_code == 200
    assert world.respond(s.rider, s.bid_a, "accept").status_code in (400, 409)
    assert world.accept_counter(s.a, s.bid_a).status_code == 409
    assert world.accept_counter(s.b, s.bid_b).status_code == 409
    ride = world.ride(s.ride_id)
    assert ride.status == RideRequestStatus.CANCELLED and ride.matched_driver_id is None


def test_rider_cancel_closes_countered_bids_too(world):
    s = two_countered_bids(world)
    assert world.call("post", f"/api/rides/request/{s.ride_id}/cancel", s.rider.h).status_code == 200
    live = world.db.query(RideBid).filter(
        RideBid.ride_request_id == s.ride_id, RideBid.status.in_([BidStatus.PENDING, BidStatus.COUNTERED])).count()
    assert live == 0


def test_driver_counter_after_rider_cancel_cannot_revive_the_ride(world):
    s = two_countered_bids(world)
    assert world.call("post", f"/api/rides/request/{s.ride_id}/cancel", s.rider.h).status_code == 200
    resp = world.call("post", f"/api/rides/bid/{s.bid_a}/driver-counter", s.a.h, json={"counter_price": 19})
    assert resp.status_code in (400, 409)
    assert world.respond(s.rider, s.bid_a, "accept").status_code in (400, 409)
    assert world.ride(s.ride_id).status == RideRequestStatus.CANCELLED


def test_driver_counter_gives_the_rider_a_fresh_ten_minutes(world):
    s = two_countered_bids(world)
    row = world.db.query(RideBid).get(s.bid_a)
    row.expires_at = datetime.utcnow() - timedelta(minutes=1)
    world.db.commit()
    resp = world.call("post", f"/api/rides/bid/{s.bid_a}/driver-counter", s.a.h, json={"counter_price": s.counter + 1})
    assert resp.status_code == 200, resp.text
    assert world.bid_row(s.bid_a).expires_at > datetime.utcnow() + timedelta(minutes=9)
    assert world.respond(s.rider, s.bid_a, "accept").status_code == 200


def test_driver_cannot_be_matched_to_two_rides_at_once(world):
    r1, r2 = world.rider(), world.rider()
    d = world.driver(miles=1)
    ride1, _ = world.request_ride(r1)
    ride2, _ = world.request_ride(r2)
    bid1 = world.bid(d, ride1, 12).json()["bid"]
    bid2 = world.bid(d, ride2, 13).json()["bid"]
    assert world.respond(r1, bid1["id"], "accept").status_code == 200
    second = world.respond(r2, bid2["id"], "accept")
    assert second.status_code == 409
    ride = world.ride(ride2)
    assert ride.status == RideRequestStatus.BIDDING and ride.matched_driver_id is None
    assert world.db.query(RideRequest).filter(RideRequest.matched_driver_id == d.id).count() == 1
    assert world.bids_for(r2, ride2)["bids"] == []


def test_driver_cannot_accept_a_counter_while_on_another_ride(world):
    r1, r2 = world.rider(), world.rider()
    d = world.driver(miles=1)
    ride1, _ = world.request_ride(r1)
    ride2, _ = world.request_ride(r2)
    bid1 = world.bid(d, ride1, 12).json()["bid"]
    bid2 = world.bid(d, ride2, 20).json()["bid"]
    counter = round(max(world.ride(ride2).suggested_price * 0.7, 5.0), 2)
    assert world.respond(r2, bid2["id"], "counter", counter_price=counter).status_code == 200
    assert world.respond(r1, bid1["id"], "accept").status_code == 200
    assert world.accept_counter(d, bid2["id"]).status_code == 409
    assert world.ride(ride2).matched_driver_id is None


def test_rider_cannot_accept_a_bid_from_a_driver_who_went_offline(world):
    rider = world.rider()
    d = world.driver(miles=1)
    ride_id, _ = world.request_ride(rider)
    bid = world.bid(d, ride_id, 12).json()["bid"]
    d.is_online = False
    world.db.commit()
    assert world.respond(rider, bid["id"], "accept").status_code == 409
    assert world.ride(ride_id).status != RideRequestStatus.MATCHED


def test_accepting_a_bid_rejects_every_other_live_bid(world):
    rider = world.rider()
    drivers = [world.driver(miles=1 + i) for i in range(4)]
    ride_id, _ = world.request_ride(rider)
    bids = [world.bid(d, ride_id, 10 + i).json()["bid"] for i, d in enumerate(drivers)]
    assert world.respond(rider, bids[2]["id"], "accept").status_code == 200
    assert_single_consistent_match(world, ride_id, bids[2]["id"], drivers[2])


# =============================================================================
# (4) THE 5-MINUTE TIMER
# =============================================================================

def test_default_window_is_five_minutes_and_exposed_to_both_apps(world):
    rider = world.rider()
    d = world.driver(miles=1)
    ride_id, _ = world.request_ride(rider)
    ends = world.ride(ride_id).bidding_expires_at
    assert timedelta(minutes=4, seconds=55) < ends - datetime.utcnow() <= timedelta(minutes=5)
    feed = world.client.get("/api/rides/available", params={"latitude": at_miles(1)[0], "longitude": PICKUP[1]}, headers=d.h).json()
    assert feed["available_requests"][0]["bidding_expires_at"] == ends.isoformat()
    assert world.bids_for(rider, ride_id)["bidding_ends_at"] == ends.isoformat()
    detail = world.client.get(f"/api/rides/request/{ride_id}", headers=rider.h).json()
    assert "bidding_expires_at" in str(detail)


def test_no_bid_ride_expires_and_every_endpoint_agrees(world):
    rider = world.rider()
    d = world.driver(miles=1)
    ride_id, _ = world.request_ride(rider)
    lapse_window(world, ride_id)
    # Lazy view before the 60s job runs: already invisible and closed
    assert world.visible_to(d, ride_id) is False
    assert world.bids_for(rider, ride_id)["bidding_open"] is False
    assert world.bid(d, ride_id).status_code == 400

    run_job(world, "check_ride_bidding_expiry_job")
    assert world.ride(ride_id).status == RideRequestStatus.EXPIRED
    assert world.visible_to(d, ride_id) is False
    body = world.bids_for(rider, ride_id)
    assert body["bidding_open"] is False and body["bids"] == []
    assert world.bid(d, ride_id).status_code == 400


def test_ride_with_bids_at_expiry_closes_pending_and_countered_bids(world):
    s = two_countered_bids(world)
    d3 = world.driver(miles=3)
    pending = world.bid(d3, s.ride_id, 15).json()["bid"]
    lapse_window(world, s.ride_id)
    # Before the job: the rider can neither accept the pending bid nor the drivers accept their counters
    assert world.respond(s.rider, pending["id"], "accept").status_code == 409
    assert world.accept_counter(s.a, s.bid_a).status_code == 409
    run_job(world, "check_ride_bidding_expiry_job")
    assert world.ride(s.ride_id).status == RideRequestStatus.EXPIRED
    statuses = {b.id: b.status for b in world.db.query(RideBid).filter(RideBid.ride_request_id == s.ride_id)}
    assert set(statuses.values()) == {BidStatus.EXPIRED}
    assert world.respond(s.rider, pending["id"], "accept").status_code == 400
    assert world.accept_counter(s.b, s.bid_b).status_code in (400, 409)
    assert world.ride(s.ride_id).matched_driver_id is None


def test_rider_accept_on_a_lapsed_window_does_not_match(world):
    rider = world.rider()
    d = world.driver(miles=1)
    ride_id, _ = world.request_ride(rider)
    bid = world.bid(d, ride_id).json()["bid"]
    lapse_window(world, ride_id)
    resp = world.respond(rider, bid["id"], "accept")
    assert resp.status_code == 409
    assert world.ride(ride_id).status != RideRequestStatus.MATCHED


def test_there_is_no_window_extension_endpoint(world):
    rider = world.rider()
    ride_id, _ = world.request_ride(rider)
    for method, url in (("post", f"/api/rides/request/{ride_id}/extend"), ("put", f"/api/rides/request/{ride_id}/extend"),
                        ("post", f"/api/rides/request/{ride_id}/extend-bidding")):
        assert getattr(world.client, method)(url, headers=rider.h).status_code in (404, 405)


def test_driver_cancel_reopens_with_a_fresh_window_and_dead_bids_can_rebid(world):
    rider = world.rider()
    a, b = world.driver(miles=1), world.driver(miles=2)
    ride_id, _ = world.request_ride(rider)
    bid_a = world.bid(a, ride_id, 12).json()["bid"]
    bid_b = world.bid(b, ride_id, 14).json()["bid"]
    assert world.respond(rider, bid_a["id"], "accept").status_code == 200
    assert world.bid_row(bid_b["id"]).status == BidStatus.REJECTED
    lapse_window(world, ride_id)
    assert world.call("post", f"/api/rides/request/{ride_id}/driver-cancel", a.h, json={"reason": "flat tyre"}).status_code == 200
    ride = world.ride(ride_id)
    assert ride.status == RideRequestStatus.OPEN and ride.matched_driver_id is None and ride.matched_bid_id is None
    assert ride.bidding_expires_at > datetime.utcnow() + timedelta(minutes=4)
    assert world.bid_row(bid_a["id"]).status == BidStatus.WITHDRAWN
    # Both the cancelling driver and the earlier loser may bid again, one row each
    assert world.bid(b, ride_id, 13).status_code == 200
    assert world.bid(a, ride_id, 15).status_code == 200
    assert world.db.query(RideBid).filter(RideBid.ride_request_id == ride_id).count() == 2
    assert [x["proposed_price"] for x in world.bids_for(rider, ride_id)["bids"]] == [13.0, 15.0]


def test_rider_cancelled_ride_is_not_listed_or_biddable(world):
    rider = world.rider()
    d = world.driver(miles=1)
    ride_id, _ = world.request_ride(rider)
    assert world.call("post", f"/api/rides/request/{ride_id}/cancel", rider.h).status_code == 200
    assert world.visible_to(d, ride_id) is False
    assert world.bid(d, ride_id).status_code == 400


# =============================================================================
# (5) CONSISTENCY SWEEP
# =============================================================================

def test_busy_marketplace_never_double_matches_or_leaves_odd_state(world):
    riders = [world.rider() for _ in range(3)]
    drivers = [world.driver(miles=0.5 + i * 0.4) for i in range(6)]
    rides = [world.request_ride(r)[0] for r in riders]
    bids = {}
    for ride_id in rides:
        for i, d in enumerate(drivers):
            resp = world.bid(d, ride_id, 10 + i)
            assert resp.status_code == 200, resp.text
            bids[(ride_id, d.id)] = resp.json()["bid"]["id"]
    for r, ride_id in zip(riders, rides):  # every rider tries to take driver 0 first, then the next cheapest
        for d in drivers:
            resp = world.respond(r, bids[(ride_id, d.id)], "accept")
            assert resp.status_code in (200, 400, 409), resp.text
            if resp.status_code == 200:
                break
    world.db.expire_all()
    matched = world.db.query(RideRequest).filter(RideRequest.status == RideRequestStatus.MATCHED).all()
    assert len(matched) == 3
    assert len({m.matched_driver_id for m in matched}) == 3
    for m in matched:
        accepted = world.db.query(RideBid).filter(RideBid.ride_request_id == m.id, RideBid.status == BidStatus.ACCEPTED).all()
        assert [a.id for a in accepted] == [m.matched_bid_id]
        assert accepted[0].driver_id == m.matched_driver_id
    for d in drivers:
        world.db.refresh(d)
        assert (d.ride_accept_count or 0) in (0, 1)
    assert world.db.query(RideRequest).filter(
        RideRequest.status.in_([RideRequestStatus.OPEN, RideRequestStatus.BIDDING]), RideRequest.matched_driver_id.isnot(None)).count() == 0
