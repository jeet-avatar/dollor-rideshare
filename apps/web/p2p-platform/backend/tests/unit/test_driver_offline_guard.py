"""A driver with a live ride cannot go offline."""
from main_new import create_access_token
from models import RideRequest, RideRequestStatus


def make_ride(db_session, customer, driver, status):
    ride = RideRequest(
        request_id=f"RIDE-TEST-{status.value}", customer_id=customer.id, pickup_address="a", pickup_latitude=37.78, pickup_longitude=-122.41,
        dropoff_address="b", dropoff_latitude=37.79, dropoff_longitude=-122.40,
        status=status, matched_driver_id=driver.id,
    )
    db_session.add(ride)
    db_session.commit()
    return ride


def headers(driver):
    token = create_access_token(data={"sub": driver.email, "role": "driver", "driver_id": driver.id})
    return {"Authorization": f"Bearer {token}"}


def test_cannot_go_offline_mid_ride(client, db_session, test_driver, test_customer):
    test_driver.is_online = True
    db_session.commit()
    make_ride(db_session, test_customer, test_driver, RideRequestStatus.IN_PROGRESS)
    resp = client.put("/api/auth/driver/online", json={"is_online": False}, headers=headers(test_driver))
    assert resp.status_code == 409
    assert "current ride" in resp.json()["detail"]


def test_can_go_offline_when_idle(client, db_session, test_driver, test_customer):
    test_driver.is_online = True
    db_session.commit()
    make_ride(db_session, test_customer, test_driver, RideRequestStatus.COMPLETED)
    resp = client.put("/api/auth/driver/online", json={"is_online": False}, headers=headers(test_driver))
    assert resp.status_code == 200
    assert resp.json()["is_online"] is False
