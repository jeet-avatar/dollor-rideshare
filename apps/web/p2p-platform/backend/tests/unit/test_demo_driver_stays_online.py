"""The shared demo drivers used by App Review / Play review cannot be taken offline."""
from main_new import create_access_token
from models import DriverStatus


def headers(driver):
    token = create_access_token(data={"sub": driver.email, "role": "driver", "driver_id": driver.id})
    return {"Authorization": f"Bearer {token}"}


def make_demo(db_session, driver):
    driver.email = "demo.driver@dollor.ai"
    driver.status = DriverStatus.APPROVED
    driver.background_check = True
    driver.is_online = True
    db_session.commit()


def test_demo_driver_offline_request_is_ignored(client, db_session, test_driver):
    make_demo(db_session, test_driver)
    resp = client.put("/api/auth/driver/online", json={"is_online": False}, headers=headers(test_driver))
    assert resp.status_code == 200
    assert resp.json()["is_online"] is True
    db_session.refresh(test_driver)
    assert test_driver.is_online is True


def test_demo_driver_offline_via_status_route_is_ignored(client, db_session, test_driver):
    make_demo(db_session, test_driver)
    resp = client.post(f"/api/drivers/{test_driver.id}/status?is_online=false", headers=headers(test_driver))
    assert resp.status_code == 200
    db_session.refresh(test_driver)
    assert test_driver.is_online is True


def test_regular_driver_can_still_go_offline(client, db_session, test_driver):
    test_driver.is_online = True
    db_session.commit()
    resp = client.put("/api/auth/driver/online", json={"is_online": False}, headers=headers(test_driver))
    assert resp.status_code == 200
    assert resp.json()["is_online"] is False
