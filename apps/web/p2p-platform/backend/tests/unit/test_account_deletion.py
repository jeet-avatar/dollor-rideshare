"""In-app account deletion (DELETE /api/customers/{id}/delete, /api/drivers/{id}/delete).

Foreign keys are switched ON for these tests to mimic Postgres (SQLite ignores them by default):
the old hard-delete failed with an IntegrityError for any account with ride history.
Stripe is always mocked.
"""
import uuid
from datetime import datetime
from unittest.mock import MagicMock, patch

import pytest
from sqlalchemy.exc import IntegrityError

import account_deletion
from main_new import create_access_token, get_password_hash
from models import (
    BidStatus, Customer, Driver, DriverPayout, DriverStatus, InAppNotification, RideBid, RideChatMessage,
    RideRequest, RideRequestStatus, User, UserRole,
)
from tests.conftest import TestingSessionLocal, engine


@pytest.fixture(scope="function")
def db_session(test_db):
    """conftest's db_session with PRAGMA foreign_keys=ON (must be set outside a transaction)."""
    connection = engine.connect()
    connection.exec_driver_sql("PRAGMA foreign_keys=ON")
    assert connection.exec_driver_sql("PRAGMA foreign_keys").scalar() == 1
    connection.commit()
    transaction = connection.begin()
    session = TestingSessionLocal(bind=connection)
    yield session
    session.close()
    transaction.rollback()
    connection.exec_driver_sql("PRAGMA foreign_keys=OFF")
    connection.commit()
    connection.close()


PASSWORD = "Passw0rd!Passw0rd"


def uid():
    return uuid.uuid4().hex[:8]


def make_customer(db, email=None, **kw):
    email = email or f"cust_{uid()}@example.com"
    c = Customer(email=email, first_name="Rita", last_name="Rider", phone="+14155550111",
                 password_hash=get_password_hash(PASSWORD), is_active=True,
                 default_address={"street": "1 Main"}, saved_addresses=[{"street": "2 Elm"}],
                 saved_cards=[{"id": "pm_1", "last4": "4242"}], push_token="push-abc", device_id="dev-1",
                 stripe_customer_id="cus_123", google_id=f"g_{uid()}", **kw)
    db.add(c)
    db.commit()
    db.add(User(email=email, password_hash=get_password_hash(PASSWORD), full_name="Rita Rider", role=UserRole.USER))
    db.commit()
    return c


def make_driver(db, email=None, **kw):
    email = email or f"drv_{uid()}@example.com"
    d = Driver(driver_id=f"drv_{uid()}", email=email, first_name="Dan", last_name="Driver", phone="+14155550222",
               password_hash=get_password_hash(PASSWORD), status=DriverStatus.ACTIVE, license_number="D1234567",
               date_of_birth="1990-01-01", street="9 Oak", city="SF", vehicle_make="Toyota", vehicle_model="Prius",
               vehicle_year=2020, license_plate="7ABC123", drivers_license_url="https://s3/x/dl.jpg",
               insurance_url="https://s3/x/ins.jpg", photo_url="https://s3/x/me.jpg", push_token="p", fcm_token="f",
               bank_name="enc-bank", bank_last4="6789", stripe_account_id="acct_123", is_online=True, **kw)
    db.add(d)
    db.commit()
    db.add(User(email=email, password_hash=get_password_hash(PASSWORD), full_name="Dan Driver",
                role=UserRole.DRIVER, driver_id=d.id))
    db.commit()
    return d


def make_ride(db, customer, status, driver=None, **kw):
    ride = RideRequest(
        request_id=f"RR-{uid()}", customer_id=customer.id, customer_name="Rita Rider", customer_phone="+14155550111",
        pickup_address="A st", pickup_latitude=37.7, pickup_longitude=-122.4,
        dropoff_address="B st", dropoff_latitude=37.8, dropoff_longitude=-122.4,
        status=status, matched_driver_id=driver.id if driver else None,
        suggested_price=20.0, final_price=20.0, payment_status="completed", platform_fee=2.0, driver_payout=18.0,
        completed_at=datetime.utcnow() if status == RideRequestStatus.COMPLETED else None, **kw)
    db.add(ride)
    db.commit()
    return ride


def make_bid(db, ride, driver, status=BidStatus.ACCEPTED):
    bid = RideBid(bid_id=f"BID-{uid()}", ride_request_id=ride.id, driver_id=driver.id, driver_name="Dan Driver",
                  driver_photo_url="https://s3/x/me.jpg", driver_vehicle="Toyota Prius", proposed_price=20.0, status=status)
    db.add(bid)
    db.commit()
    return bid


def customer_headers(c):
    return {"Authorization": "Bearer " + create_access_token(
        data={"sub": c.email, "role": "customer", "customer_id": c.id})}


def driver_headers(d):
    return {"Authorization": "Bearer " + create_access_token(data={"sub": d.email, "role": "driver", "driver_id": d.id})}


def admin_headers(admin):
    return {"Authorization": "Bearer " + create_access_token(data={"sub": admin.email, "role": "admin"})}


@pytest.fixture
def stripe_mock():
    with patch.object(account_deletion, "stripe") as m:
        m.api_key = "sk_test_mock"
        m.PaymentMethod.list.return_value = MagicMock(data=[MagicMock(id="pm_1"), MagicMock(id="pm_2")])
        m.Balance.retrieve.return_value = MagicMock(available=[MagicMock(amount=0)], pending=[MagicMock(amount=0)])
        yield m


# --------------------------------------------------------------------------- reproduction of the old bug

def test_old_hard_delete_fails_on_foreign_key_with_ride_history(db_session):
    customer = make_customer(db_session)
    make_ride(db_session, customer, RideRequestStatus.COMPLETED)
    db_session.delete(customer)
    with pytest.raises(IntegrityError):
        db_session.commit()
    db_session.rollback()


# --------------------------------------------------------------------------- rider

def test_rider_with_history_is_anonymised_and_rides_remain(client, db_session, stripe_mock):
    customer = make_customer(db_session)
    driver = make_driver(db_session)
    done = make_ride(db_session, customer, RideRequestStatus.COMPLETED, driver)
    cancelled = make_ride(db_session, customer, RideRequestStatus.CANCELLED)
    make_bid(db_session, done, driver)
    db_session.add(RideChatMessage(ride_request_id=done.id, sender_type="customer", sender_id=customer.id, message="hi"))
    db_session.add(InAppNotification(customer_id=customer.id, title="t", message="m"))
    db_session.commit()
    cid, old_email = customer.id, customer.email

    resp = client.delete(f"/api/customers/{cid}/delete", headers=customer_headers(customer))
    assert resp.status_code == 200, resp.text
    assert resp.json()["success"] is True and "deleted" in resp.json()["message"].lower()

    db_session.expire_all()
    c = db_session.query(Customer).get(cid)
    assert (c.first_name, c.last_name) == ("Deleted", "User")
    assert c.email == f"deleted+c{cid}@deleted.invalid"
    for field in ("phone", "password_hash", "default_address", "saved_addresses", "saved_cards", "push_token",
                  "device_id", "google_id", "stripe_customer_id"):
        assert getattr(c, field) is None, field
    assert c.is_active is False

    rides = db_session.query(RideRequest).filter(RideRequest.customer_id == cid).all()
    assert {r.id for r in rides} == {done.id, cancelled.id}
    assert all(r.customer_name == "Deleted User" and r.customer_phone is None for r in rides)
    kept = db_session.query(RideRequest).get(done.id)
    assert (kept.final_price, kept.platform_fee, kept.driver_payout, kept.pickup_address) == (20.0, 2.0, 18.0, "A st")
    assert db_session.query(RideChatMessage).filter_by(ride_request_id=done.id).count() == 1
    assert db_session.query(InAppNotification).filter_by(customer_id=cid).count() == 0
    assert db_session.query(User).filter(User.email == old_email).count() == 0
    stripe_mock.Customer.delete.assert_called_once_with("cus_123")
    assert stripe_mock.PaymentMethod.detach.call_count == 2


@pytest.mark.parametrize("status", [RideRequestStatus.OPEN, RideRequestStatus.BIDDING,
                                    RideRequestStatus.MATCHED, RideRequestStatus.IN_PROGRESS])
def test_rider_with_active_ride_gets_409_and_nothing_changes(client, db_session, stripe_mock, status):
    customer = make_customer(db_session)
    driver = make_driver(db_session) if status in (RideRequestStatus.MATCHED, RideRequestStatus.IN_PROGRESS) else None
    make_ride(db_session, customer, status, driver)
    resp = client.delete(f"/api/customers/{customer.id}/delete", headers=customer_headers(customer))
    assert resp.status_code == 409
    assert "cancel" in resp.json()["detail"].lower()
    db_session.expire_all()
    assert db_session.query(Customer).get(customer.id).email.startswith("cust_")
    stripe_mock.Customer.delete.assert_not_called()


def test_double_delete_is_idempotent(client, db_session, stripe_mock):
    customer = make_customer(db_session)
    headers = customer_headers(customer)
    assert client.delete(f"/api/customers/{customer.id}/delete", headers=headers).status_code == 200
    # same token: it was revoked, so the repeat is refused at the door, never a 500
    assert client.delete(f"/api/customers/{customer.id}/delete", headers=headers).status_code == 401
    # an admin repeating the call gets a clear 200
    admin = User(email=f"adm_{uid()}@example.com", password_hash=get_password_hash(PASSWORD), full_name="A", role=UserRole.ADMIN)
    db_session.add(admin)
    db_session.commit()
    again = client.delete(f"/api/customers/{customer.id}/delete", headers=admin_headers(admin))
    assert again.status_code == 200 and "already" in again.json()["message"].lower()
    assert client.delete("/api/customers/999999/delete", headers=admin_headers(admin)).status_code == 404


def test_stranger_cannot_delete_someone_else(client, db_session, stripe_mock):
    victim = make_customer(db_session)
    stranger = make_customer(db_session)
    driver = make_driver(db_session)
    assert client.delete(f"/api/customers/{victim.id}/delete", headers=customer_headers(stranger)).status_code == 403
    assert client.delete(f"/api/customers/{victim.id}/delete", headers=driver_headers(driver)).status_code == 403
    assert client.delete(f"/api/drivers/{driver.id}/delete", headers=customer_headers(stranger)).status_code == 403
    assert client.delete(f"/api/customers/{victim.id}/delete").status_code == 401
    db_session.expire_all()
    assert db_session.query(Customer).get(victim.id).email.startswith("cust_")


def test_admin_can_delete_a_customer(client, db_session, stripe_mock):
    customer = make_customer(db_session)
    admin = User(email=f"adm_{uid()}@example.com", password_hash=get_password_hash(PASSWORD), full_name="A", role=UserRole.ADMIN)
    db_session.add(admin)
    db_session.commit()
    assert client.delete(f"/api/customers/{customer.id}/delete", headers=admin_headers(admin)).status_code == 200
    db_session.expire_all()
    assert db_session.query(Customer).get(customer.id).email.endswith("@deleted.invalid")
    assert db_session.query(User).get(admin.id).email.startswith("adm_")  # admin rows are never touched


def test_login_and_old_tokens_fail_after_deletion(client, db_session, stripe_mock):
    customer = make_customer(db_session)
    email = customer.email
    old_token = customer_headers(customer)
    other_token = customer_headers(customer)  # a second device, token never seen by the delete call
    assert client.post("/api/auth/customer/login", data={"username": email, "password": PASSWORD}).status_code == 200
    assert client.delete(f"/api/customers/{customer.id}/delete", headers=old_token).status_code == 200

    assert client.post("/api/auth/customer/login", data={"username": email, "password": PASSWORD}).status_code == 401
    tomb = f"deleted+c{customer.id}@deleted.invalid"
    assert client.post("/api/auth/customer/login", data={"username": tomb, "password": PASSWORD}).status_code == 401
    assert client.get("/api/customer/rides/history", headers=other_token).status_code == 401
    # the email can be used to sign up again
    again = make_customer(db_session, email=email)
    assert again.id != customer.id


def test_stripe_errors_do_not_fail_the_deletion(client, db_session, stripe_mock):
    stripe_mock.PaymentMethod.list.side_effect = RuntimeError("stripe down")
    stripe_mock.Customer.delete.side_effect = RuntimeError("stripe down")
    customer = make_customer(db_session)
    resp = client.delete(f"/api/customers/{customer.id}/delete", headers=customer_headers(customer))
    assert resp.status_code == 200, resp.text
    db_session.expire_all()
    c = db_session.query(Customer).get(customer.id)
    assert c.email.endswith("@deleted.invalid") and c.phone is None
    assert c.stripe_customer_id == "cus_123"  # kept so a repeat call can retry the cleanup

    stripe_mock.PaymentMethod.list.side_effect = None
    stripe_mock.Customer.delete.side_effect = None
    admin = User(email=f"adm_{uid()}@example.com", password_hash=get_password_hash(PASSWORD), full_name="A", role=UserRole.ADMIN)
    db_session.add(admin)
    db_session.commit()
    assert client.delete(f"/api/customers/{customer.id}/delete", headers=admin_headers(admin)).status_code == 200
    db_session.expire_all()
    assert db_session.query(Customer).get(customer.id).stripe_customer_id is None


def test_deletion_works_when_stripe_is_not_configured(client, db_session):
    with patch.object(account_deletion, "stripe") as m:
        m.api_key = ""
        customer = make_customer(db_session)
        assert client.delete(f"/api/customers/{customer.id}/delete", headers=customer_headers(customer)).status_code == 200
        m.Customer.delete.assert_not_called()


# --------------------------------------------------------------------------- driver

def test_driver_with_history_is_anonymised_and_rides_remain(client, db_session, stripe_mock):
    driver = make_driver(db_session)
    customer = make_customer(db_session)
    done = make_ride(db_session, customer, RideRequestStatus.COMPLETED, driver)
    bid = make_bid(db_session, done, driver)
    pending_ride = make_ride(db_session, customer, RideRequestStatus.OPEN)
    pending_bid = make_bid(db_session, pending_ride, driver, BidStatus.PENDING)
    db_session.add(DriverPayout(payout_number=f"PO-{uid()}", driver_id=driver.id, period_start=datetime.utcnow(),
                                period_end=datetime.utcnow(), net_payout=18.0, status="completed"))
    db_session.commit()
    did, old_email = driver.id, driver.email

    resp = client.delete(f"/api/drivers/{did}/delete", headers=driver_headers(driver))
    assert resp.status_code == 200, resp.text

    db_session.expire_all()
    d = db_session.query(Driver).get(did)
    assert (d.first_name, d.last_name) == ("Deleted", "User") and d.email == f"deleted+d{did}@deleted.invalid"
    for field in ("phone", "password_hash", "license_number", "date_of_birth", "street", "city", "vehicle_make",
                  "license_plate", "drivers_license_url", "insurance_url", "photo_url", "push_token", "fcm_token",
                  "bank_name", "bank_last4", "stripe_account_id", "apple_id"):
        assert getattr(d, field) is None, field
    assert d.is_online is False and d.status == DriverStatus.INACTIVE

    kept = db_session.query(RideRequest).get(done.id)
    assert kept.matched_driver_id == did and kept.driver_payout == 18.0
    assert db_session.query(DriverPayout).filter_by(driver_id=did).count() == 1
    b = db_session.query(RideBid).get(bid.id)
    assert b.driver_name == "Deleted User" and b.driver_photo_url is None and b.driver_vehicle is None
    assert db_session.query(RideBid).get(pending_bid.id).status == BidStatus.WITHDRAWN
    assert db_session.query(User).filter(User.email == old_email).count() == 0
    stripe_mock.Account.delete.assert_called_once_with("acct_123")

    # the rider's receipt still renders with the anonymised driver
    receipt = client.get(f"/api/rides/request/{done.id}/receipt", headers=customer_headers(customer))
    assert receipt.status_code == 200, receipt.text
    assert receipt.json()["receipt"]["driver"]["name"] == "Deleted User"


def test_driver_login_fails_after_deletion(client, db_session, stripe_mock):
    driver = make_driver(db_session)
    email = driver.email
    assert client.post("/api/auth/driver/login", data={"username": email, "password": PASSWORD}).status_code == 200
    assert client.delete(f"/api/drivers/{driver.id}/delete", headers=driver_headers(driver)).status_code == 200
    assert client.post("/api/auth/driver/login", data={"username": email, "password": PASSWORD}).status_code == 401
    tomb = f"deleted+d{driver.id}@deleted.invalid"
    assert client.post("/api/auth/driver/login", data={"username": tomb, "password": PASSWORD}).status_code == 401
    assert client.get("/api/driver/prop22/periods/1/rides", headers=driver_headers(driver)).status_code == 401


@pytest.mark.parametrize("status", [RideRequestStatus.MATCHED, RideRequestStatus.IN_PROGRESS])
def test_driver_mid_ride_gets_409(client, db_session, stripe_mock, status):
    driver = make_driver(db_session)
    make_ride(db_session, make_customer(db_session), status, driver)
    resp = client.delete(f"/api/drivers/{driver.id}/delete", headers=driver_headers(driver))
    assert resp.status_code == 409 and "finish" in resp.json()["detail"].lower()
    db_session.expire_all()
    assert db_session.query(Driver).get(driver.id).email.startswith("drv_")
    stripe_mock.Account.delete.assert_not_called()


def test_driver_with_unpaid_payout_gets_409(client, db_session, stripe_mock):
    driver = make_driver(db_session)
    db_session.add(DriverPayout(payout_number=f"PO-{uid()}", driver_id=driver.id, period_start=datetime.utcnow(),
                                period_end=datetime.utcnow(), net_payout=18.0, status="pending"))
    db_session.commit()
    resp = client.delete(f"/api/drivers/{driver.id}/delete", headers=driver_headers(driver))
    assert resp.status_code == 409 and "payout" in resp.json()["detail"].lower()


def test_driver_connect_account_with_balance_is_not_deleted_but_account_is(client, db_session, stripe_mock):
    stripe_mock.Balance.retrieve.return_value = MagicMock(available=[MagicMock(amount=1500)], pending=[])
    driver = make_driver(db_session)
    assert client.delete(f"/api/drivers/{driver.id}/delete", headers=driver_headers(driver)).status_code == 200
    stripe_mock.Account.delete.assert_not_called()
    db_session.expire_all()
    d = db_session.query(Driver).get(driver.id)
    assert d.email.endswith("@deleted.invalid") and d.stripe_account_id == "acct_123"


def test_driver_stripe_errors_do_not_fail_deletion(client, db_session, stripe_mock):
    stripe_mock.Balance.retrieve.side_effect = RuntimeError("stripe down")
    driver = make_driver(db_session)
    assert client.delete(f"/api/drivers/{driver.id}/delete", headers=driver_headers(driver)).status_code == 200


# --------------------------------------------------------------------------- demo accounts

@pytest.mark.parametrize("kind,email", [("customer", "demo.customer@dollor.ai"), ("driver", "demo.driver@dollor.ai"),
                                        ("driver", "demo.driver2@dollor.ai")])
def test_demo_accounts_report_success_but_are_untouched(client, db_session, stripe_mock, kind, email):
    existing = db_session.query(Customer if kind == "customer" else Driver).filter_by(email=email).first()
    if existing is None:
        existing = make_customer(db_session, email=email) if kind == "customer" else make_driver(db_session, email=email)
    headers = customer_headers(existing) if kind == "customer" else driver_headers(existing)
    before = (existing.email, existing.first_name, existing.password_hash)
    for _ in range(2):
        resp = client.delete(f"/api/{kind}s/{existing.id}/delete", headers=headers)
        assert resp.status_code == 200 and resp.json()["success"] is True and "deleted" in resp.json()["message"].lower()
    db_session.expire_all()
    again = db_session.query(type(existing)).get(existing.id)
    assert (again.email, again.first_name, again.password_hash) == before
    assert not account_deletion.is_deleted_account(again)
    stripe_mock.Customer.delete.assert_not_called()
    stripe_mock.Account.delete.assert_not_called()
    assert client.get("/api/customer/rides/history" if kind == "customer" else "/api/driver/prop22/periods/1/rides",
                      headers=headers).status_code != 401  # token still valid


# --------------------------------------------------------------------------- other users unaffected

def test_other_users_receipts_and_history_are_unaffected(client, db_session, stripe_mock):
    gone, stays = make_customer(db_session), make_customer(db_session)
    driver = make_driver(db_session)
    gone_ride = make_ride(db_session, gone, RideRequestStatus.COMPLETED, driver)
    stay_ride = make_ride(db_session, stays, RideRequestStatus.COMPLETED, driver)

    assert client.delete(f"/api/customers/{gone.id}/delete", headers=customer_headers(gone)).status_code == 200

    receipt = client.get(f"/api/rides/request/{stay_ride.id}/receipt", headers=customer_headers(stays))
    assert receipt.status_code == 200 and receipt.json()["receipt"]["driver"]["name"] == "Dan Driver"
    history = client.get("/api/customer/rides/history", headers=customer_headers(stays))
    assert history.status_code == 200, history.text
    assert "Rita" in db_session.query(Customer).get(stays.id).first_name
    # the driver keeps working and still sees both completed rides in his account
    assert db_session.query(RideRequest).filter_by(matched_driver_id=driver.id).count() == 2
    # the deleted rider's receipt is still available to the driver, with no personal data
    drv_receipt = client.get(f"/api/rides/request/{gone_ride.id}/receipt", headers=driver_headers(driver))
    assert drv_receipt.status_code == 200
