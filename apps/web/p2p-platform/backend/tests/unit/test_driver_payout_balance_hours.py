"""GET /api/driver/earnings reports available_balance and hours_online; payouts draw the balance down."""
from datetime import datetime, timedelta
from types import SimpleNamespace
from unittest.mock import patch

import stripe

from main_new import create_access_token
from models import DriverOnlineSession, RideRequest, RideRequestStatus


def headers(driver):
    token = create_access_token(data={"sub": driver.email, "role": "driver", "driver_id": driver.id})
    return {"Authorization": f"Bearer {token}"}


def add_ride(db_session, customer, driver, request_id, payout, status=RideRequestStatus.COMPLETED):
    db_session.add(RideRequest(
        request_id=request_id, customer_id=customer.id,
        pickup_address="a", pickup_latitude=37.7, pickup_longitude=-122.4,
        dropoff_address="b", dropoff_latitude=37.8, dropoff_longitude=-122.4,
        status=status, matched_driver_id=driver.id, suggested_price=20, final_price=20, driver_payout=payout,
    ))
    db_session.commit()


def earnings(client, driver, period="today"):
    response = client.get(f"/api/driver/earnings?period={period}", headers=headers(driver))
    assert response.status_code == 200, response.text
    return response.json()


def test_available_balance_is_completed_ride_payouts_only(client, db_session, test_customer, test_driver):
    add_ride(db_session, test_customer, test_driver, "R-BAL-1", 18.95)
    add_ride(db_session, test_customer, test_driver, "R-BAL-2", 10.0)
    add_ride(db_session, test_customer, test_driver, "R-BAL-3", 99.0, status=RideRequestStatus.CANCELLED)
    body = earnings(client, test_driver)
    assert body["available_balance"] == 28.95
    assert body["pending_balance"] == 0.0


def test_a_payout_request_reduces_the_balance_and_cannot_be_repeated(client, db_session, test_customer, test_driver):
    test_driver.stripe_account_id = "acct_test"
    db_session.commit()
    add_ride(db_session, test_customer, test_driver, "R-PAY-1", 30.0)
    in_flight = SimpleNamespace(id="po_1", status="pending", arrival_date=1)
    with patch("stripe.Payout.create", return_value=in_flight) as create:
        first = client.post(f"/api/drivers/{test_driver.id}/payouts", json={"amount": 20.0}, headers=headers(test_driver))
        assert first.status_code == 200, first.text
        # Only 10.00 is left, so asking for 20.00 again must be refused before Stripe is called
        second = client.post(f"/api/drivers/{test_driver.id}/payouts", json={"amount": 20.0}, headers=headers(test_driver))
    assert second.status_code == 400
    assert create.call_count == 1

    body = earnings(client, test_driver)
    assert body["available_balance"] == 10.0
    assert body["pending_balance"] == 20.0


def test_a_failed_stripe_payout_leaves_the_balance_untouched(client, db_session, test_customer, test_driver):
    test_driver.stripe_account_id = "acct_test"
    db_session.commit()
    add_ride(db_session, test_customer, test_driver, "R-PAY-2", 30.0)
    with patch("stripe.Payout.create", side_effect=stripe.error.APIError("down")):
        response = client.post(f"/api/drivers/{test_driver.id}/payouts", json={"amount": 25.0}, headers=headers(test_driver))
    assert response.status_code == 400
    body = earnings(client, test_driver)
    assert body["available_balance"] == 30.0
    assert body["pending_balance"] == 0.0


def test_hours_online_comes_from_sessions_clipped_to_each_window(client, db_session, test_driver):
    now = datetime.utcnow()
    midnight = now.replace(hour=0, minute=0, second=0, microsecond=0)
    today_end = midnight + (now - midnight) / 2  # ends before "now" whatever time the test runs
    db_session.add_all([
        DriverOnlineSession(driver_id=test_driver.id, started_at=now - timedelta(days=3, hours=2), ended_at=now - timedelta(days=3)),
        DriverOnlineSession(driver_id=test_driver.id, started_at=now - timedelta(days=20, hours=1), ended_at=now - timedelta(days=20)),
        DriverOnlineSession(driver_id=test_driver.id, started_at=midnight - timedelta(hours=1), ended_at=today_end),
    ])
    db_session.commit()
    today_hours = round((today_end - midnight).total_seconds() / 3600, 2)
    body = earnings(client, test_driver)
    periods = body["hours_online_periods"]
    assert periods["today"] == today_hours  # the hour before midnight is not today
    assert periods["week"] == round(2 + 1 + today_hours, 2)
    assert periods["month"] == round(2 + 1 + 1 + today_hours, 2)
    assert body["hours_online"] == periods["today"]
    assert earnings(client, test_driver, "week")["hours_online"] == periods["week"]
    assert earnings(client, test_driver, "month")["hours_online"] == periods["month"]


def test_going_online_and_offline_logs_a_session(client, db_session, test_driver):
    test_driver.background_check = True
    db_session.commit()
    assert client.put("/api/auth/driver/online", json={"is_online": True}, headers=headers(test_driver)).status_code == 200
    sessions = db_session.query(DriverOnlineSession).filter_by(driver_id=test_driver.id).all()
    assert len(sessions) == 1 and sessions[0].ended_at is None

    assert client.put("/api/auth/driver/online", json={"is_online": False}, headers=headers(test_driver)).status_code == 200
    db_session.expire_all()
    sessions = db_session.query(DriverOnlineSession).filter_by(driver_id=test_driver.id).all()
    assert len(sessions) == 1 and sessions[0].ended_at is not None


def test_location_heartbeat_opens_a_session_for_a_driver_who_was_already_online(client, db_session, test_driver):
    test_driver.is_online = True
    db_session.commit()
    response = client.post("/api/driver/location", json={"latitude": 37.7, "longitude": -122.4}, headers=headers(test_driver))
    assert response.status_code == 200
    assert db_session.query(DriverOnlineSession).filter_by(driver_id=test_driver.id, ended_at=None).count() == 1
    client.post("/api/driver/location", json={"latitude": 37.7, "longitude": -122.4}, headers=headers(test_driver))
    assert db_session.query(DriverOnlineSession).filter_by(driver_id=test_driver.id).count() == 1


def test_an_abandoned_open_session_stops_counting_after_the_heartbeat_grace(client, db_session, test_driver):
    now = datetime.utcnow()
    test_driver.is_online = True
    test_driver.location_updated_at = now - timedelta(hours=2)  # app died two hours ago
    db_session.add(DriverOnlineSession(driver_id=test_driver.id, started_at=now - timedelta(minutes=30)))
    db_session.commit()
    # started 30 min ago but last seen 2h ago, so nothing is credited beyond the session start
    assert earnings(client, test_driver)["hours_online"] <= 0.01


def test_going_offline_mid_ride_is_refused_on_every_status_route(client, db_session, test_driver, test_customer):
    test_driver.is_online = True
    db_session.commit()
    add_ride(db_session, test_customer, test_driver, "R-OFF-1", 10.0, status=RideRequestStatus.IN_PROGRESS)
    android = client.post(f"/api/drivers/{test_driver.id}/status?is_online=false", headers=headers(test_driver))
    erp = client.put(f"/api/erp/drivers/{test_driver.id}/status?is_online=false", headers=headers(test_driver))
    assert android.status_code == 409
    assert erp.status_code == 409
