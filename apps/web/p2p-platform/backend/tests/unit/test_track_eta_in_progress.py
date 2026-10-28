"""The track endpoint's eta_minutes is the pickup ETA while matched and the destination ETA once the trip is under way."""
from main_new import create_access_token
from models import RideRequest, RideRequestStatus


def _track(client, db_session, test_customer, test_driver, status):
    test_driver.current_latitude, test_driver.current_longitude = 37.7000, -122.4000
    ride = RideRequest(
        request_id=f"RIDE-ETA-{status.value}", customer_id=test_customer.id,
        pickup_address="a", pickup_latitude=37.7000, pickup_longitude=-122.4000,
        dropoff_address="b", dropoff_latitude=37.8000, dropoff_longitude=-122.4000,
        status=status, matched_driver_id=test_driver.id, suggested_price=10, final_price=10,
    )
    db_session.add(ride)
    db_session.commit()
    headers = {"Authorization": "Bearer " + create_access_token(
        data={"sub": test_customer.email, "role": "customer", "customer_id": test_customer.id})}
    return client.get(f"/api/rides/{ride.id}/track", headers=headers).json()


def test_matched_ride_eta_is_pickup_eta(client, db_session, test_customer, test_driver):
    body = _track(client, db_session, test_customer, test_driver, RideRequestStatus.MATCHED)
    assert body["eta_minutes"] == body["eta_pickup_minutes"] == 1


def test_in_progress_ride_eta_is_destination_eta(client, db_session, test_customer, test_driver):
    body = _track(client, db_session, test_customer, test_driver, RideRequestStatus.IN_PROGRESS)
    assert body["eta_pickup_minutes"] == 1
    assert body["eta_minutes"] == body["eta_destination_minutes"]
    assert body["eta_minutes"] > 10
