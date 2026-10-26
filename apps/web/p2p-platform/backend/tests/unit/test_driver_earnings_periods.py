"""GET /api/driver/earnings reports today, week and month totals whichever period is requested."""
from datetime import datetime, timedelta

from main_new import create_access_token
from models import RideRequest, RideRequestStatus


def _ride(db_session, customer, driver, request_id, created_at, payout, tip):
    ride = RideRequest(
        request_id=request_id, customer_id=customer.id,
        pickup_address="a", pickup_latitude=37.7, pickup_longitude=-122.4,
        dropoff_address="b", dropoff_latitude=37.8, dropoff_longitude=-122.4,
        status=RideRequestStatus.COMPLETED, matched_driver_id=driver.id,
        suggested_price=20, final_price=20, driver_payout=payout, tip_amount=tip, created_at=created_at,
    )
    db_session.add(ride)
    db_session.commit()


def test_all_three_period_totals_are_returned_for_the_default_period(client, db_session, test_customer, test_driver):
    now = datetime.utcnow()
    _ride(db_session, test_customer, test_driver, "RIDE-EARN-1", now, payout=10.0, tip=1.0)
    _ride(db_session, test_customer, test_driver, "RIDE-EARN-2", now - timedelta(days=3), payout=20.0, tip=0)
    _ride(db_session, test_customer, test_driver, "RIDE-EARN-3", now - timedelta(days=20), payout=30.0, tip=0)
    headers = {"Authorization": "Bearer " + create_access_token(
        data={"sub": test_driver.email, "role": "driver", "driver_id": test_driver.id})}

    default = client.get("/api/driver/earnings", headers=headers).json()
    week = client.get("/api/driver/earnings?period=week", headers=headers).json()

    for body in (default, week):
        assert body["today"] == 11.0
        assert body["week"] == 31.0
        assert body["month"] == 61.0
    assert default["total_earnings"] == 11.0 and week["total_earnings"] == 31.0
