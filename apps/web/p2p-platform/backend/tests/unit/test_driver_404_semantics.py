"""Three driver endpoints that returned 404 in the production probe. A 404 is correct when the id
does not belong to a driver / to this driver's periods; these tests pin that and prove the
success paths work for a real driver."""
import uuid
from datetime import datetime, timedelta

from main_new import create_access_token
from models import Prop22EarningPeriod, RideRequest, RideRequestStatus


def headers_for(driver):
    return {"Authorization": "Bearer " + create_access_token(
        data={"sub": driver.email, "role": "driver", "driver_id": driver.id})}


def test_checkr_status_404_for_unknown_driver_and_200_for_own(client, test_driver):
    h = headers_for(test_driver)
    missing = client.get("/api/checkr/background-check/999999/status", headers=h)
    assert missing.status_code == 404
    assert missing.json()["detail"] == "Driver not found"

    own = client.get(f"/api/checkr/background-check/{test_driver.id}/status", headers=h)
    assert own.status_code == 200
    assert own.json()["status"] == "not_started"


def test_checkr_status_forbidden_for_other_driver(client, test_driver, db_session):
    from tests.unit.test_ios_negotiation_and_location import make_driver
    other = make_driver(db_session)
    assert client.get(f"/api/checkr/background-check/{other.id}/status", headers=headers_for(test_driver)).status_code == 403


def test_vehicle_inspection_status_404_for_unknown_driver_and_200_for_own(client, test_driver, test_admin):
    h = headers_for(test_driver)
    admin_h = {"Authorization": "Bearer " + create_access_token(data={"sub": test_admin.email, "role": "admin"})}
    missing = client.get("/api/tnc/vehicle-inspection/999999/status", headers=admin_h)
    assert missing.status_code == 404
    assert missing.json()["detail"] == "Driver not found"
    # a driver asking about an id that is not theirs learns nothing, not even whether it exists
    assert client.get("/api/tnc/vehicle-inspection/999999/status", headers=h).status_code == 403

    own = client.get(f"/api/tnc/vehicle-inspection/{test_driver.id}/status", headers=h)
    assert own.status_code == 200
    assert own.json()["driver_id"] == test_driver.id


def test_prop22_period_rides_404_for_unknown_or_foreign_period_and_lists_own_rides(client, db_session, test_driver, test_customer):
    from tests.unit.test_ios_negotiation_and_location import make_driver
    h = headers_for(test_driver)
    assert client.get("/api/driver/prop22/periods/999999/rides", headers=h).status_code == 404

    now = datetime.utcnow()
    other = make_driver(db_session)
    foreign = Prop22EarningPeriod(driver_id=other.id, period_start=now - timedelta(days=7), period_end=now + timedelta(days=1))
    own = Prop22EarningPeriod(driver_id=test_driver.id, period_start=now - timedelta(days=7), period_end=now + timedelta(days=1))
    db_session.add_all([foreign, own])
    db_session.commit()

    # someone else's period must look exactly like a missing one
    assert client.get(f"/api/driver/prop22/periods/{foreign.id}/rides", headers=h).status_code == 404

    ride = RideRequest(
        request_id=f"RIDE-{uuid.uuid4().hex[:8]}", customer_id=test_customer.id,
        pickup_address="a", pickup_latitude=37.7, pickup_longitude=-122.4,
        dropoff_address="b", dropoff_latitude=37.8, dropoff_longitude=-122.4,
        status=RideRequestStatus.COMPLETED, matched_driver_id=test_driver.id,
        matched_at=now - timedelta(days=1), completed_at=now - timedelta(hours=23),
        suggested_price=20.0, final_price=20.0,
    )
    db_session.add(ride)
    db_session.commit()

    resp = client.get(f"/api/driver/prop22/periods/{own.id}/rides", headers=h)
    assert resp.status_code == 200, resp.text
    assert [r["ride_id"] for r in resp.json()] == [ride.id]


def test_vehicle_inspection_status_is_private_to_the_driver_and_admins(client, db_session, test_driver, test_customer, test_admin):
    from tests.unit.test_ios_negotiation_and_location import make_driver
    other = make_driver(db_session)
    url = f"/api/tnc/vehicle-inspection/{test_driver.id}/status"
    customer_h = {"Authorization": "Bearer " + create_access_token(
        data={"sub": test_customer.email, "role": "customer", "customer_id": test_customer.id})}
    admin_h = {"Authorization": "Bearer " + create_access_token(data={"sub": test_admin.email, "role": "admin"})}

    assert client.get(url, headers=customer_h).status_code == 403
    assert client.get(url, headers=headers_for(other)).status_code == 403
    assert client.get(url).status_code == 401
    assert client.get(url, headers=headers_for(test_driver)).status_code == 200
    assert client.get(url, headers=admin_h).status_code == 200
