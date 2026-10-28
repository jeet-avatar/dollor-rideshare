"""Legacy ride/driver-status aliases can no longer bypass the bid flow, and every login route enforces one session."""
import cache
import pytest
from unittest.mock import patch

from main_new import create_access_token
from models import DriverStatus, RideRequest, RideRequestStatus
from tests.unit.test_ios_negotiation_and_location import make_driver


def headers(driver):
    token = create_access_token(data={"sub": driver.email, "role": "driver", "driver_id": driver.id})
    return {"Authorization": f"Bearer {token}"}


def make_ride(db_session, customer, status, driver=None, request_id="R-LEGACY-1"):
    ride = RideRequest(
        request_id=request_id, customer_id=customer.id, pickup_address="a", pickup_latitude=37.78, pickup_longitude=-122.41,
        dropoff_address="b", dropoff_latitude=37.79, dropoff_longitude=-122.40,
        status=status, matched_driver_id=driver.id if driver else None,
    )
    db_session.add(ride)
    db_session.commit()
    return ride


ACCEPT_PATHS = ["/api/erp/rides/{id}/accept", "/erp/rides/{id}/accept"]


@pytest.mark.parametrize("path", ACCEPT_PATHS)
def test_legacy_accept_is_retired_and_matches_nothing(client, db_session, test_driver, test_customer, path):
    ride = make_ride(db_session, test_customer, RideRequestStatus.OPEN)
    response = client.post(path.format(id=ride.id), json={"driver_id": test_driver.id}, headers=headers(test_driver))
    assert response.status_code == 410
    db_session.refresh(ride)
    assert ride.status == RideRequestStatus.OPEN and ride.matched_driver_id is None


@pytest.mark.parametrize("path", ACCEPT_PATHS)
def test_legacy_accept_cannot_match_a_cancelled_ride(client, db_session, test_driver, test_customer, path):
    ride = make_ride(db_session, test_customer, RideRequestStatus.CANCELLED)
    client.post(path.format(id=ride.id), json={"driver_id": test_driver.id}, headers=headers(test_driver))
    db_session.refresh(ride)
    assert ride.status == RideRequestStatus.CANCELLED and ride.matched_driver_id is None


START_PATHS = ["/api/erp/rides/{id}/start", "/erp/rides/{id}/start", "/api/erp/rides/{id}/picked-up", "/erp/rides/{id}/picked-up"]


@pytest.mark.parametrize("path", START_PATHS)
def test_legacy_start_needs_a_driver_token(client, db_session, test_driver, test_customer, path):
    ride = make_ride(db_session, test_customer, RideRequestStatus.MATCHED, test_driver)
    assert client.post(path.format(id=ride.id)).status_code == 401
    customer_token = create_access_token(data={"sub": test_customer.email, "role": "customer", "customer_id": test_customer.id})
    assert client.post(path.format(id=ride.id), headers={"Authorization": f"Bearer {customer_token}"}).status_code in (401, 403)
    db_session.refresh(ride)
    assert ride.status == RideRequestStatus.MATCHED


@pytest.mark.parametrize("path", START_PATHS)
def test_legacy_start_only_by_the_matched_driver(client, db_session, test_driver, test_customer, path):
    other = make_driver(db_session)
    ride = make_ride(db_session, test_customer, RideRequestStatus.MATCHED, test_driver)
    assert client.post(path.format(id=ride.id), headers=headers(other)).status_code == 403
    db_session.refresh(ride)
    assert ride.status == RideRequestStatus.MATCHED


@pytest.mark.parametrize("path", START_PATHS)
@pytest.mark.parametrize("status", [RideRequestStatus.OPEN, RideRequestStatus.CANCELLED, RideRequestStatus.COMPLETED])
def test_legacy_start_needs_a_matched_ride(client, db_session, test_driver, test_customer, path, status):
    ride = make_ride(db_session, test_customer, status, test_driver)
    assert client.post(path.format(id=ride.id), headers=headers(test_driver)).status_code == 400
    db_session.refresh(ride)
    assert ride.status == status


@pytest.mark.parametrize("path", START_PATHS)
def test_legacy_start_works_for_the_matched_driver(client, db_session, test_driver, test_customer, path):
    ride = make_ride(db_session, test_customer, RideRequestStatus.MATCHED, test_driver)
    with patch("bid_routes.send_push_notification"), patch("bid_routes._bg_email"), patch("bid_routes.asyncio.create_task"):
        response = client.post(path.format(id=ride.id), headers=headers(test_driver))
    assert response.status_code == 200, response.text
    assert response.json()["status"] == "in_progress"
    db_session.refresh(ride)
    assert ride.status == RideRequestStatus.IN_PROGRESS


def test_erp_driver_status_cannot_go_online_while_pending_or_unchecked(client, db_session, test_driver):
    url = f"/api/erp/drivers/{test_driver.id}/status?is_online=true"
    test_driver.status = DriverStatus.PENDING
    test_driver.background_check = True
    db_session.commit()
    assert client.put(url, headers=headers(test_driver)).status_code == 403

    test_driver.status = DriverStatus.APPROVED
    test_driver.background_check = False
    db_session.commit()
    assert client.put(url, headers=headers(test_driver)).status_code == 403
    db_session.refresh(test_driver)
    assert test_driver.is_online is not True

    test_driver.background_check = True
    db_session.commit()
    assert client.put(url, headers=headers(test_driver)).status_code == 200
    db_session.refresh(test_driver)
    assert test_driver.is_online is True


def test_android_status_route_cannot_go_online_without_a_background_check(client, db_session, test_driver):
    test_driver.background_check = False
    db_session.commit()
    response = client.post(f"/api/drivers/{test_driver.id}/status?is_online=true", headers=headers(test_driver))
    assert response.status_code == 403


def test_google_login_signs_out_the_previous_device(client, db_session, sample_driver_data, monkeypatch):
    monkeypatch.setattr(cache, "redis_client", None)
    cache._active_sessions.clear()
    cache._revoked_tokens.clear()
    registered = client.post("/api/auth/driver/register", json={**sample_driver_data, "first_name": "New", "last_name": "Driver"})
    assert registered.status_code in (200, 201), registered.text
    first_token = registered.json()["access_token"]
    first = {"Authorization": f"Bearer {first_token}"}
    assert client.get("/api/driver/earnings", headers=first).status_code == 200

    with patch("main_new.decode_google_jwt", return_value={"email": sample_driver_data["email"], "name": "New Driver", "sub": "g-1"}):
        google = client.post("/api/auth/driver/google", json={"id_token": "x"})
    assert google.status_code == 200, google.text
    second = {"Authorization": f"Bearer {google.json()['access_token']}"}

    assert client.get("/api/driver/earnings", headers=first).status_code == 401
    assert client.get("/api/driver/earnings", headers=second).status_code == 200
