"""The iOS rider tracks a ride through /api/erp/rides/{id}/track, which must behave like /api/rides/{id}/track."""
from main_new import create_access_token
from models import RideRequest, RideRequestStatus


def test_ios_track_alias_matches_canonical_route(client, db_session, test_customer, test_driver):
    ride = RideRequest(
        request_id="RIDE-TRACK-ALIAS", customer_id=test_customer.id,
        pickup_address="a", pickup_latitude=37.7, pickup_longitude=-122.4,
        dropoff_address="b", dropoff_latitude=37.8, dropoff_longitude=-122.4,
        status=RideRequestStatus.MATCHED, matched_driver_id=test_driver.id, suggested_price=10, final_price=10,
    )
    db_session.add(ride)
    db_session.commit()
    headers = {"Authorization": "Bearer " + create_access_token(
        data={"sub": test_customer.email, "role": "customer", "customer_id": test_customer.id})}

    canonical = client.get(f"/api/rides/{ride.id}/track", headers=headers)
    alias = client.get(f"/api/erp/rides/{ride.id}/track", headers=headers)

    assert canonical.status_code == 200
    assert alias.status_code == 200
    assert alias.json()["status"] == canonical.json()["status"]


def test_matched_driver_gets_the_riders_phone_on_active_rides(client, db_session, test_customer, test_driver):
    test_customer.phone = "+14155550199"
    ride = RideRequest(
        request_id="RIDE-ACTIVE-PHONE", customer_id=test_customer.id,
        pickup_address="a", pickup_latitude=37.7, pickup_longitude=-122.4,
        dropoff_address="b", dropoff_latitude=37.8, dropoff_longitude=-122.4,
        status=RideRequestStatus.MATCHED, matched_driver_id=test_driver.id, suggested_price=10, final_price=10,
    )
    db_session.add(ride)
    db_session.commit()
    headers = {"Authorization": "Bearer " + create_access_token(
        data={"sub": test_driver.email, "role": "driver", "driver_id": test_driver.id})}

    rides = client.get("/api/rides/driver/active", headers=headers).json()["active_rides"]

    assert [r["customer_phone"] for r in rides] == ["+14155550199"]
