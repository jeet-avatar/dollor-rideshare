"""iOS legacy fare-negotiation routes and the iOS driver live-location route.

iOS calls (P2PAPIService.swift):
  POST /erp/rides/{id}/negotiate            driver or rider fare offer
  POST /erp/rides/{id}/accept-fare          accept a negotiated fare
  POST /erp/rides/{id}/customer-negotiate   rider offer (?proposed_fare=)
  POST /erp/rides/{id}/customer-accept-fare rider accepts (?accepted_fare=)
  GET  /erp/rides/{id}/negotiation-status   poll
  PUT  /erp/orders/{id}/driver-location     driver position push (id is a ride id)
Each is also served under /api.
"""
import uuid
from datetime import datetime

import pytest

from main_new import create_access_token, get_password_hash
from models import (
    BidStatus, Customer, Driver, DriverStatus, RideBid, RideRequest, RideRequestStatus,
)


def make_ride(db, customer, status=RideRequestStatus.OPEN, driver=None, **kw):
    ride = RideRequest(
        request_id=f"RIDE-{uuid.uuid4().hex[:8]}", customer_id=customer.id,
        pickup_address="a", pickup_latitude=37.7, pickup_longitude=-122.4,
        dropoff_address="b", dropoff_latitude=37.8, dropoff_longitude=-122.4,
        status=status, matched_driver_id=driver.id if driver else None,
        suggested_price=20.0, **kw,
    )
    db.add(ride)
    db.commit()
    db.refresh(ride)
    return ride


def make_driver(db):
    d = Driver(
        driver_id=f"drv_{uuid.uuid4().hex[:8]}", email=f"d_{uuid.uuid4().hex[:6]}@t.com",
        password_hash=get_password_hash("DriverPassword123!"), first_name="O", last_name="D",
        phone="+14155550000", status=DriverStatus.APPROVED,
    )
    db.add(d)
    db.commit()
    db.refresh(d)
    return d


def make_customer(db):
    c = Customer(
        email=f"c_{uuid.uuid4().hex[:6]}@t.com", password_hash=get_password_hash("CustomerPassword123!"),
        first_name="O", last_name="C", phone="+14155550001", is_active=True,
    )
    db.add(c)
    db.commit()
    db.refresh(c)
    return c


def cust_headers(c):
    return {"Authorization": "Bearer " + create_access_token(
        data={"sub": c.email, "role": "customer", "customer_id": c.id})}


def drv_headers(d):
    return {"Authorization": "Bearer " + create_access_token(
        data={"sub": d.email, "role": "driver", "driver_id": d.id})}


@pytest.fixture
def rider(db_session, test_customer):
    return test_customer


@pytest.fixture
def other_rider(db_session):
    return make_customer(db_session)


@pytest.fixture
def drv(db_session, test_driver):
    return test_driver


# ---------------------------------------------------------------- negotiation-status

@pytest.mark.parametrize("prefix", ["/erp", "/api/erp"])
def test_negotiation_status_before_match_does_not_500(client, db_session, rider, prefix):
    ride = make_ride(db_session, rider)  # no final_price yet: used to raise AttributeError
    resp = client.get(f"{prefix}/rides/{ride.id}/negotiation-status", headers=cust_headers(rider))
    assert resp.status_code == 200, resp.text
    body = resp.json()
    # fields iOS RideNegotiationStatus requires
    assert body["success"] is True
    assert body["ride_id"] == ride.id
    assert body["negotiation_status"] == "none"
    assert body["platform_fee"] == 1.0
    assert body["agreed_fare"] is None


def test_negotiation_status_reflects_rider_offer_and_driver_bid(client, db_session, rider, drv):
    ride = make_ride(db_session, rider, status=RideRequestStatus.BIDDING, customer_preferred_price=18.0)
    h = cust_headers(rider)
    assert client.get(f"/erp/rides/{ride.id}/negotiation-status", headers=h).json()["negotiation_status"] == "customer_offered"

    db_session.add(RideBid(bid_id=f"BID-{uuid.uuid4().hex[:8]}", ride_request_id=ride.id, driver_id=drv.id, proposed_price=22.0, status=BidStatus.PENDING))
    db_session.commit()
    body = client.get(f"/erp/rides/{ride.id}/negotiation-status", headers=h).json()
    assert body["negotiation_status"] == "driver_countered"
    assert body["customer_offer"] == 18.0
    assert body["driver_offer"] == 22.0
    assert body["last_offer_by"] == "driver"


def test_negotiation_status_after_match_reports_agreed_fare(client, db_session, rider, drv):
    ride = make_ride(db_session, rider, status=RideRequestStatus.MATCHED, driver=drv, final_price=28.0)
    body = client.get(f"/erp/rides/{ride.id}/negotiation-status", headers=drv_headers(drv)).json()
    assert body["negotiation_status"] == "accepted"
    assert body["agreed_fare"] == 28.0
    assert body["platform_fee"] == 1.0
    assert body["driver_earnings"] == 27.0


def test_negotiation_status_unknown_ride_is_404(client, rider):
    assert client.get("/erp/rides/999999/negotiation-status", headers=cust_headers(rider)).status_code == 404


def test_negotiation_status_hidden_from_unrelated_users(client, db_session, rider, other_rider, drv):
    ride = make_ride(db_session, rider)
    assert client.get(f"/erp/rides/{ride.id}/negotiation-status", headers=cust_headers(other_rider)).status_code == 403


def test_negotiation_status_requires_auth(client, db_session, rider):
    ride = make_ride(db_session, rider)
    assert client.get(f"/erp/rides/{ride.id}/negotiation-status").status_code == 401


# ---------------------------------------------------------------- customer-negotiate

@pytest.mark.parametrize("prefix", ["/erp", "/api/erp"])
def test_customer_negotiate_updates_own_ride(client, db_session, rider, prefix):
    ride = make_ride(db_session, rider)
    resp = client.post(f"{prefix}/rides/{ride.id}/customer-negotiate?proposed_fare=17.5", headers=cust_headers(rider))
    assert resp.status_code == 200, resp.text
    body = resp.json()
    assert body["customer_offer"] == 17.5
    assert body["platform_fee_driver"] == 1.0 and body["platform_fee_customer"] == 1.0  # iOS FareNegotiationResponse
    db_session.refresh(ride)
    assert ride.customer_preferred_price == 17.5


def test_customer_negotiate_unknown_ride_is_404_not_fake_success(client, rider):
    assert client.post("/erp/rides/999999/customer-negotiate?proposed_fare=10", headers=cust_headers(rider)).status_code == 404


def test_customer_negotiate_cannot_touch_someone_elses_ride(client, db_session, rider, other_rider):
    ride = make_ride(db_session, rider)
    resp = client.post(f"/erp/rides/{ride.id}/customer-negotiate?proposed_fare=1", headers=cust_headers(other_rider))
    assert resp.status_code == 403
    db_session.refresh(ride)
    assert ride.customer_preferred_price is None


def test_customer_negotiate_rejects_driver_token(client, db_session, rider, drv):
    ride = make_ride(db_session, rider)
    assert client.post(f"/erp/rides/{ride.id}/customer-negotiate?proposed_fare=1", headers=drv_headers(drv)).status_code == 403


@pytest.mark.parametrize("fare", ["0", "-5", "0.0"])
def test_customer_negotiate_rejects_non_positive_fare(client, db_session, rider, fare):
    ride = make_ride(db_session, rider)
    assert client.post(f"/erp/rides/{ride.id}/customer-negotiate?proposed_fare={fare}", headers=cust_headers(rider)).status_code == 400


def test_customer_negotiate_not_allowed_after_match(client, db_session, rider, drv):
    ride = make_ride(db_session, rider, status=RideRequestStatus.MATCHED, driver=drv, final_price=28.0)
    assert client.post(f"/erp/rides/{ride.id}/customer-negotiate?proposed_fare=5", headers=cust_headers(rider)).status_code == 409


# ---------------------------------------------------------------- customer-accept-fare (money)

@pytest.mark.parametrize("prefix", ["/erp", "/api/erp"])
def test_customer_accept_fare_before_match(client, db_session, rider, prefix):
    ride = make_ride(db_session, rider, status=RideRequestStatus.BIDDING)
    resp = client.post(f"{prefix}/rides/{ride.id}/customer-accept-fare?accepted_fare=21", headers=cust_headers(rider))
    assert resp.status_code == 200, resp.text
    assert resp.json()["customer_offer"] == 21
    db_session.refresh(ride)
    assert ride.final_price == 21


def test_customer_accept_fare_cannot_lower_the_price_of_a_matched_ride(client, db_session, rider, drv):
    """final_price drives the Stripe charge and driver payout, so it must not be rewritable after matching."""
    ride = make_ride(db_session, rider, status=RideRequestStatus.MATCHED, driver=drv, final_price=28.0)
    resp = client.post(f"/erp/rides/{ride.id}/customer-accept-fare?accepted_fare=0.01", headers=cust_headers(rider))
    assert resp.status_code == 409
    db_session.refresh(ride)
    assert ride.final_price == 28.0


def test_customer_accept_fare_cannot_touch_someone_elses_ride(client, db_session, rider, other_rider):
    ride = make_ride(db_session, rider, status=RideRequestStatus.BIDDING)
    resp = client.post(f"/erp/rides/{ride.id}/customer-accept-fare?accepted_fare=3", headers=cust_headers(other_rider))
    assert resp.status_code == 403
    db_session.refresh(ride)
    assert ride.final_price is None


def test_customer_accept_fare_unknown_ride_and_bad_fare(client, db_session, rider):
    assert client.post("/erp/rides/999999/customer-accept-fare?accepted_fare=3", headers=cust_headers(rider)).status_code == 404
    ride = make_ride(db_session, rider, status=RideRequestStatus.BIDDING)
    assert client.post(f"/erp/rides/{ride.id}/customer-accept-fare?accepted_fare=0", headers=cust_headers(rider)).status_code == 400


# ---------------------------------------------------------------- negotiate (driver / rider JSON body)

@pytest.mark.parametrize("prefix", ["/erp", "/api/erp"])
def test_driver_negotiate_offer(client, db_session, rider, drv, prefix):
    ride = make_ride(db_session, rider, status=RideRequestStatus.BIDDING)
    resp = client.post(f"{prefix}/rides/{ride.id}/negotiate",
                       json={"proposed_fare": 24.0, "is_driver_offer": True}, headers=drv_headers(drv))
    assert resp.status_code == 200, resp.text
    body = resp.json()
    assert body["driver_offer"] == 24.0
    assert body["platform_fee_driver"] == 1.0
    assert body["status"] == "pending"


def test_rider_negotiate_offer_sets_preferred_price(client, db_session, rider):
    ride = make_ride(db_session, rider)
    resp = client.post(f"/erp/rides/{ride.id}/negotiate",
                       json={"proposed_fare": 16.0, "is_driver_offer": False}, headers=cust_headers(rider))
    assert resp.status_code == 200, resp.text
    db_session.refresh(ride)
    assert ride.customer_preferred_price == 16.0


def test_negotiate_rider_cannot_send_driver_offer_and_driver_cannot_send_rider_offer(client, db_session, rider, drv):
    ride = make_ride(db_session, rider)
    assert client.post(f"/erp/rides/{ride.id}/negotiate", json={"proposed_fare": 9, "is_driver_offer": True},
                       headers=cust_headers(rider)).status_code == 403
    assert client.post(f"/erp/rides/{ride.id}/negotiate", json={"proposed_fare": 9, "is_driver_offer": False},
                       headers=drv_headers(drv)).status_code == 403


def test_negotiate_other_riders_cannot_set_price(client, db_session, rider, other_rider):
    ride = make_ride(db_session, rider)
    assert client.post(f"/erp/rides/{ride.id}/negotiate", json={"proposed_fare": 1, "is_driver_offer": False},
                       headers=cust_headers(other_rider)).status_code == 403
    db_session.refresh(ride)
    assert ride.customer_preferred_price is None


@pytest.mark.parametrize("bad", ["abc", None, -3, 0, [1]])
def test_negotiate_invalid_fare_is_400_not_500(client, db_session, rider, drv, bad):
    ride = make_ride(db_session, rider)
    resp = client.post(f"/erp/rides/{ride.id}/negotiate", json={"proposed_fare": bad, "is_driver_offer": True},
                       headers=drv_headers(drv))
    assert resp.status_code == 400, resp.text


def test_negotiate_unknown_ride_404(client, drv):
    assert client.post("/erp/rides/999999/negotiate", json={"proposed_fare": 9, "is_driver_offer": True},
                       headers=drv_headers(drv)).status_code == 404


def test_negotiate_not_allowed_after_match(client, db_session, rider, drv):
    ride = make_ride(db_session, rider, status=RideRequestStatus.MATCHED, driver=drv, final_price=28.0)
    assert client.post(f"/erp/rides/{ride.id}/negotiate", json={"proposed_fare": 9, "is_driver_offer": False},
                       headers=cust_headers(rider)).status_code == 409


# ---------------------------------------------------------------- accept-fare (driver/rider JSON body)

def test_accept_fare_by_ride_owner_before_match(client, db_session, rider):
    ride = make_ride(db_session, rider, status=RideRequestStatus.BIDDING)
    resp = client.post(f"/erp/rides/{ride.id}/accept-fare", json={"accepted_fare": 19.0}, headers=cust_headers(rider))
    assert resp.status_code == 200, resp.text
    db_session.refresh(ride)
    assert ride.final_price == 19.0


def test_accept_fare_cannot_rewrite_matched_price_or_other_riders_ride(client, db_session, rider, other_rider, drv):
    matched = make_ride(db_session, rider, status=RideRequestStatus.MATCHED, driver=drv, final_price=28.0)
    assert client.post(f"/erp/rides/{matched.id}/accept-fare", json={"accepted_fare": 1}, headers=cust_headers(rider)).status_code == 409
    open_ride = make_ride(db_session, rider, status=RideRequestStatus.BIDDING)
    assert client.post(f"/erp/rides/{open_ride.id}/accept-fare", json={"accepted_fare": 1}, headers=cust_headers(other_rider)).status_code == 403
    db_session.refresh(matched)
    db_session.refresh(open_ride)
    assert matched.final_price == 28.0 and open_ride.final_price is None


@pytest.mark.parametrize("bad", ["abc", -1, 0])
def test_accept_fare_invalid_fare_400(client, db_session, rider, bad):
    ride = make_ride(db_session, rider, status=RideRequestStatus.BIDDING)
    assert client.post(f"/erp/rides/{ride.id}/accept-fare", json={"accepted_fare": bad}, headers=cust_headers(rider)).status_code == 400


# ---------------------------------------------------------------- driver-location

@pytest.mark.parametrize("prefix", ["/erp", "/api/erp"])
def test_driver_location_updates_matched_drivers_position(client, db_session, rider, drv, prefix):
    ride = make_ride(db_session, rider, status=RideRequestStatus.MATCHED, driver=drv, final_price=20.0)
    resp = client.put(f"{prefix}/orders/{ride.id}/driver-location",
                      json={"latitude": 37.7749, "longitude": -122.4194, "updated_at": datetime.utcnow().isoformat() + "Z"},
                      headers=drv_headers(drv))
    assert resp.status_code == 200, resp.text
    assert resp.json()["success"] is True
    db_session.refresh(drv)
    assert drv.current_latitude == 37.7749
    assert drv.current_longitude == -122.4194
    assert drv.location_updated_at is not None


def test_driver_location_is_visible_to_rider_tracking(client, db_session, rider, drv):
    ride = make_ride(db_session, rider, status=RideRequestStatus.IN_PROGRESS, driver=drv, final_price=20.0)
    client.put(f"/erp/orders/{ride.id}/driver-location", json={"latitude": 37.71, "longitude": -122.41},
               headers=drv_headers(drv))
    track = client.get(f"/api/erp/rides/{ride.id}/track", headers=cust_headers(rider))
    assert track.status_code == 200
    assert "37.71" in track.text


def test_driver_location_other_driver_forbidden(client, db_session, rider, drv):
    ride = make_ride(db_session, rider, status=RideRequestStatus.MATCHED, driver=drv, final_price=20.0)
    stranger = make_driver(db_session)
    resp = client.put(f"/erp/orders/{ride.id}/driver-location", json={"latitude": 1.0, "longitude": 2.0},
                      headers=drv_headers(stranger))
    assert resp.status_code == 403
    db_session.refresh(stranger)
    assert stranger.current_latitude is None


def test_driver_location_rider_token_is_rejected(client, db_session, rider, drv):
    ride = make_ride(db_session, rider, status=RideRequestStatus.MATCHED, driver=drv, final_price=20.0)
    assert client.put(f"/erp/orders/{ride.id}/driver-location", json={"latitude": 1.0, "longitude": 2.0},
                      headers=cust_headers(rider)).status_code in (401, 403)


def test_driver_location_requires_auth(client, db_session, rider, drv):
    ride = make_ride(db_session, rider, status=RideRequestStatus.MATCHED, driver=drv, final_price=20.0)
    assert client.put(f"/erp/orders/{ride.id}/driver-location", json={"latitude": 1.0, "longitude": 2.0}).status_code == 401


def test_driver_location_unknown_ride_404(client, drv):
    assert client.put("/erp/orders/999999/driver-location", json={"latitude": 1.0, "longitude": 2.0},
                      headers=drv_headers(drv)).status_code == 404


@pytest.mark.parametrize("status", [RideRequestStatus.COMPLETED, RideRequestStatus.CANCELLED, RideRequestStatus.OPEN])
def test_driver_location_inactive_ride_conflict(client, db_session, rider, drv, status):
    ride = make_ride(db_session, rider, status=status, driver=drv if status != RideRequestStatus.OPEN else None)
    assert client.put(f"/erp/orders/{ride.id}/driver-location", json={"latitude": 1.0, "longitude": 2.0},
                      headers=drv_headers(drv)).status_code in (403, 409)


@pytest.mark.parametrize("body", [{"latitude": 95, "longitude": 0}, {"latitude": 0, "longitude": 190}, {"latitude": 1}, {}])
def test_driver_location_validates_coordinates(client, db_session, rider, drv, body):
    ride = make_ride(db_session, rider, status=RideRequestStatus.MATCHED, driver=drv, final_price=20.0)
    assert client.put(f"/erp/orders/{ride.id}/driver-location", json=body, headers=drv_headers(drv)).status_code == 422


def test_get_driver_location_for_rider_and_privacy(client, db_session, rider, other_rider, drv):
    ride = make_ride(db_session, rider, status=RideRequestStatus.IN_PROGRESS, driver=drv, final_price=20.0)
    client.put(f"/erp/orders/{ride.id}/driver-location", json={"latitude": 37.5, "longitude": -122.3}, headers=drv_headers(drv))

    body = client.get(f"/api/erp/orders/{ride.id}/driver-location", headers=cust_headers(rider)).json()
    assert body["success"] is True and body["order_id"] == ride.id
    assert body["location"] == {"latitude": 37.5, "longitude": -122.3}
    assert body["order_status"] == "in_progress"
    assert "phone" not in str(body["driver"])

    assert client.get(f"/erp/orders/{ride.id}/driver-location", headers=cust_headers(other_rider)).status_code == 403
    assert client.get(f"/erp/orders/{ride.id}/driver-location").status_code == 401
    assert client.get("/erp/orders/999999/driver-location", headers=cust_headers(rider)).status_code == 404
