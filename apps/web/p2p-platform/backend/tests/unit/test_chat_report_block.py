"""Chat report/block (Guideline 1.2), Apple token revocation on deletion, and driver bank-number handling.
Email, Apple and Stripe are always mocked."""
from unittest.mock import MagicMock, patch

import pytest

import apple_signin
import account_deletion
from main_new import get_password_hash
from models import (
    AppleSigninToken, ChatReport, Driver, RideChatMessage, RideRequest, RideRequestStatus, User, UserRole,
)
from tests.unit.test_account_deletion import (
    PASSWORD, admin_headers, customer_headers, driver_headers, make_customer, make_driver, make_ride, uid,
)


@pytest.fixture(autouse=True)
def mail_mock():
    with patch("email_service.notify_support", return_value=True) as m:
        yield m


@pytest.fixture
def stripe_mock():
    with patch.object(account_deletion, "stripe") as m:
        m.api_key = "unit-test-stripe-key"
        m.PaymentMethod.list.return_value = MagicMock(data=[])
        m.Balance.retrieve.return_value = MagicMock(available=[MagicMock(amount=0)], pending=[MagicMock(amount=0)])
        yield m


@pytest.fixture
def trip(db_session):
    rider = make_customer(db_session)
    driver = make_driver(db_session)
    ride = make_ride(db_session, rider, RideRequestStatus.IN_PROGRESS, driver)
    return rider, driver, ride


def chat_url(ride):
    return f"/api/p2p/ride-requests/{ride.id}/chat"


def say(client, ride, headers, text="hello"):
    return client.post(chat_url(ride), json={"message": text, "sender_type": "customer"}, headers=headers)


def block(client, headers, user_type, user_id):
    return client.post("/api/chat/block", json={"blocked_user_type": user_type, "blocked_user_id": user_id},
                       headers=headers)


def texts(client, ride, headers):
    return [m["message"] for m in client.get(chat_url(ride), headers=headers).json()["messages"]]


# ------------------------------------------------------------------ report

def test_participants_can_report_and_support_is_emailed(client, db_session, trip, mail_mock):
    rider, driver, ride = trip
    msg_id = say(client, ride, driver_headers(driver), "rude message").json()["id"]

    r = client.post("/api/chat/report", headers=customer_headers(rider), json={
        "ride_request_id": ride.id, "message_id": msg_id, "reason": "harassment", "details": "insulting"})
    assert r.status_code == 200, r.text
    row = db_session.query(ChatReport).filter(ChatReport.id == r.json()["report_id"]).one()
    assert (row.reporter_type, row.reporter_id) == ("customer", rider.id)
    assert (row.reported_type, row.reported_id) == ("driver", driver.id)
    assert row.status == "open" and row.reason == "harassment" and row.message_id == msg_id
    mail_mock.assert_called_once()
    assert "harassment" in str(mail_mock.call_args)

    # driver reports the rider without a message
    r2 = client.post("/api/chat/report", headers=driver_headers(driver),
                     json={"ride_request_id": ride.id, "reason": "spam"})
    assert r2.status_code == 200
    row2 = db_session.query(ChatReport).filter(ChatReport.id == r2.json()["report_id"]).one()
    assert (row2.reported_type, row2.reported_id) == ("customer", rider.id)


def test_stranger_cannot_report_and_bad_input_rejected(client, db_session, trip):
    rider, driver, ride = trip
    stranger = make_customer(db_session)
    other_driver = make_driver(db_session)
    body = {"ride_request_id": ride.id, "reason": "spam"}
    assert client.post("/api/chat/report", json=body, headers=customer_headers(stranger)).status_code == 403
    assert client.post("/api/chat/report", json=body, headers=driver_headers(other_driver)).status_code == 403
    assert client.post("/api/chat/report", json=body).status_code == 401
    assert client.post("/api/chat/report", headers=customer_headers(rider),
                       json={"ride_request_id": ride.id, "reason": "because"}).status_code == 422
    assert client.post("/api/chat/report", headers=customer_headers(rider),
                       json={**body, "details": "x" * 1001}).status_code == 422
    assert client.post("/api/chat/report", headers=customer_headers(rider),
                       json={"ride_request_id": 999999, "reason": "spam"}).status_code == 404
    own = say(client, ride, customer_headers(rider)).json()["id"]
    assert client.post("/api/chat/report", headers=customer_headers(rider),
                       json={**body, "message_id": own}).status_code == 400
    assert db_session.query(ChatReport).count() == 0


def test_report_rate_limit_is_ten_per_hour(client, db_session, trip):
    rider, _, ride = trip
    for _ in range(10):
        assert client.post("/api/chat/report", headers=customer_headers(rider),
                           json={"ride_request_id": ride.id, "reason": "spam"}).status_code == 200
    r = client.post("/api/chat/report", headers=customer_headers(rider),
                    json={"ride_request_id": ride.id, "reason": "spam"})
    assert r.status_code == 429


def test_email_failure_never_breaks_report(client, trip, mail_mock):
    rider, _, ride = trip
    mail_mock.side_effect = RuntimeError("smtp down")
    r = client.post("/api/chat/report", headers=customer_headers(rider),
                    json={"ride_request_id": ride.id, "reason": "safety"})
    assert r.status_code == 200


# ------------------------------------------------------------------ block

def test_block_hides_messages_and_prevents_sending_both_ways_then_unblock_restores(client, db_session, trip):
    rider, driver, ride = trip
    rh, dh = customer_headers(rider), driver_headers(driver)
    say(client, ride, dh, "from driver 1")
    say(client, ride, rh, "from rider 1")
    db_session.add(RideChatMessage(ride_request_id=ride.id, sender_type="system", sender_id=0, message="Driver arrived"))
    db_session.commit()

    assert block(client, rh, "driver", driver.id).json() == {"success": True}
    assert texts(client, ride, rh) == ["from rider 1", "Driver arrived"]  # driver hidden, system kept
    assert texts(client, ride, dh) == ["from driver 1", "from rider 1", "Driver arrived"]  # blocked user unaffected

    refused = say(client, ride, dh, "hello??")
    assert (refused.status_code, refused.json()["detail"]) == (403, "You cannot message this user")
    assert say(client, ride, rh, "hi").status_code == 403  # blocker cannot message the blocked user either

    blocks = client.get("/api/chat/blocks", headers=rh).json()["blocks"]
    assert [(b["blocked_user_type"], b["blocked_user_id"]) for b in blocks] == [("driver", driver.id)]
    assert client.get("/api/chat/blocks", headers=dh).json() == {"blocks": []}

    assert client.request("DELETE", "/api/chat/block", headers=rh,
                          json={"blocked_user_type": "driver", "blocked_user_id": driver.id}).json() == {"success": True}
    assert "from driver 1" in texts(client, ride, rh)
    assert say(client, ride, dh, "back").status_code == 200
    assert client.get("/api/chat/blocks", headers=rh).json() == {"blocks": []}


def test_driver_can_block_rider_and_unblock_by_query(client, db_session, trip):
    rider, driver, ride = trip
    rh, dh = customer_headers(rider), driver_headers(driver)
    say(client, ride, rh, "rider says")
    assert block(client, dh, "customer", rider.id).status_code == 200
    assert texts(client, ride, dh) == []
    assert say(client, ride, rh).status_code == 403
    assert client.delete(f"/api/chat/block?blocked_user_type=customer&blocked_user_id={rider.id}",
                         headers=dh).status_code == 200
    assert texts(client, ride, dh) == ["rider says"]


def test_block_is_idempotent_and_validated(client, db_session, trip):
    rider, driver, _ = trip
    rh = customer_headers(rider)
    assert block(client, rh, "driver", driver.id).status_code == 200
    assert block(client, rh, "driver", driver.id).status_code == 200
    assert len(client.get("/api/chat/blocks", headers=rh).json()["blocks"]) == 1
    assert block(client, rh, "customer", rider.id).status_code == 400
    assert block(client, rh, "driver", 999999).status_code == 404
    assert client.post("/api/chat/block", headers=rh,
                       json={"blocked_user_type": "vendor", "blocked_user_id": 1}).status_code == 422
    assert client.post("/api/chat/block", json={"blocked_user_type": "driver", "blocked_user_id": 1}).status_code == 401
    # unblocking something never blocked is a harmless success
    assert client.request("DELETE", "/api/chat/block", headers=rh,
                          json={"blocked_user_type": "driver", "blocked_user_id": 424242}).status_code == 200


def test_block_does_not_touch_ride_or_admin_visibility(client, db_session, trip):
    rider, driver, ride = trip
    rh, dh = customer_headers(rider), driver_headers(driver)
    say(client, ride, dh, "driver text")
    assert block(client, rh, "driver", driver.id).status_code == 200

    db_session.expire_all()
    ride_after = db_session.query(RideRequest).filter(RideRequest.id == ride.id).one()
    assert ride_after.status == RideRequestStatus.IN_PROGRESS
    assert ride_after.matched_driver_id == driver.id and ride_after.payment_status == "completed"

    admin = User(email=f"adm_{uid()}@example.com", password_hash=get_password_hash(PASSWORD), full_name="A",
                 role=UserRole.ADMIN)
    db_session.add(admin)
    db_session.commit()
    assert texts(client, ride, admin_headers(admin)) == ["driver text"]  # admin sees everything
    assert client.get(f"/api/chat/ride/{ride.id}", headers=rh).json()["total"] == 0  # alias is filtered too


def test_blocker_account_deletion_still_allowed(client, db_session, trip, stripe_mock):
    rider, driver, ride = trip
    ride.status = RideRequestStatus.COMPLETED
    db_session.commit()
    assert block(client, customer_headers(rider), "driver", driver.id).status_code == 200
    assert client.delete(f"/api/customers/{rider.id}/delete", headers=customer_headers(rider)).status_code == 200


# ------------------------------------------------------------------ admin listing

def test_admin_lists_reports_and_others_cannot(client, db_session, trip):
    rider, driver, ride = trip
    msg_id = say(client, ride, driver_headers(driver), "bad words").json()["id"]
    client.post("/api/chat/report", headers=customer_headers(rider),
                json={"ride_request_id": ride.id, "message_id": msg_id, "reason": "inappropriate"})
    admin = User(email=f"adm_{uid()}@example.com", password_hash=get_password_hash(PASSWORD), full_name="A",
                 role=UserRole.ADMIN)
    db_session.add(admin)
    db_session.commit()

    r = client.get("/api/admin/chat-reports", headers=admin_headers(admin))
    assert r.status_code == 200, r.text
    report = r.json()["reports"][0]
    assert (report["reason"], report["message_text"], report["status"]) == ("inappropriate", "bad words", "open")


def test_non_admin_cannot_list_reports(client, trip):
    rider, _, _ = trip
    assert client.get("/api/admin/chat-reports", headers=customer_headers(rider)).status_code == 403
    assert client.get("/api/admin/chat-reports").status_code == 401


def test_admin_status_filter(client, db_session, trip):
    rider, _, ride = trip
    client.post("/api/chat/report", headers=customer_headers(rider),
                json={"ride_request_id": ride.id, "reason": "spam"})
    admin = User(email=f"adm_{uid()}@example.com", password_hash=get_password_hash(PASSWORD), full_name="A",
                 role=UserRole.ADMIN)
    db_session.add(admin)
    db_session.commit()
    # the admin middleware closes the shared test connection after one request, so one admin call per test
    assert client.get("/api/admin/chat-reports?status=closed", headers=admin_headers(admin)).json()["total"] == 0


# ------------------------------------------------------------------ Apple token revocation

APPLE_ENV = {"APPLE_TEAM_ID": "TEAM123456", "APPLE_KEY_ID": "KEY1234567"}
APPLE_ROLE_VARS = ("APPLE_CLIENT_ID", "APPLE_CLIENT_ID_CUSTOMER", "APPLE_CLIENT_ID_DRIVER",
                   "APPLE_KEY_ID_DRIVER", "APPLE_PRIVATE_KEY_DRIVER")


def new_pem():
    from cryptography.hazmat.primitives import serialization
    from cryptography.hazmat.primitives.asymmetric import ec
    return ec.generate_private_key(ec.SECP256R1()).private_bytes(
        serialization.Encoding.PEM, serialization.PrivateFormat.PKCS8, serialization.NoEncryption()).decode()


def secret_claims_and_kid(secret):
    from jose import jwt as jose_jwt
    return jose_jwt.get_unverified_claims(secret), jose_jwt.get_unverified_header(secret)["kid"]


@pytest.fixture
def apple_env(monkeypatch):
    for name in APPLE_ROLE_VARS:
        monkeypatch.delenv(name, raising=False)
    pem = new_pem()
    for k, v in {**APPLE_ENV, "APPLE_PRIVATE_KEY": pem}.items():
        monkeypatch.setenv(k, v)
    from cryptography.fernet import Fernet
    monkeypatch.setenv("ENCRYPTION_KEY", Fernet.generate_key().decode())
    import encryption
    monkeypatch.setattr(encryption, "_fernet", None)


def fake_response(status=200, body=None):
    return MagicMock(status_code=status, json=MagicMock(return_value=body or {}))


def test_revocation_is_noop_without_credentials(db_session, monkeypatch):
    for name in apple_signin.REQUIRED_ENV:
        monkeypatch.delenv(name, raising=False)
    customer = make_customer(db_session)
    db_session.add(AppleSigninToken(account_type="customer", account_id=customer.id, refresh_token_encrypted="x"))
    db_session.commit()
    with patch.object(apple_signin.requests, "post") as post:
        assert apple_signin.store_refresh_token_from_code(db_session, "customer", customer.id, "code") is False
        assert apple_signin.revoke_for_account(db_session, "customer", customer.id) is False
        post.assert_not_called()


def test_code_is_exchanged_stored_encrypted_and_revoked_on_delete(client, db_session, apple_env, stripe_mock):
    customer = make_customer(db_session)
    with patch.object(apple_signin.requests, "post", return_value=fake_response(200, {"refresh_token": "r-secret"})) as post:
        assert apple_signin.store_refresh_token_from_code(db_session, "customer", customer.id, "auth-code")
    assert post.call_args.args[0] == apple_signin.TOKEN_URL
    data = post.call_args.kwargs["data"]
    assert data["code"] == "auth-code" and data["grant_type"] == "authorization_code"
    assert data["client_id"] == "com.dollorai.customer" and data["client_secret"].count(".") == 2
    row = db_session.query(AppleSigninToken).one()
    assert "r-secret" not in row.refresh_token_encrypted and row.refresh_token_encrypted.startswith("enc:")

    with patch.object(apple_signin.requests, "post", return_value=fake_response(200)) as post:
        r = client.delete(f"/api/customers/{customer.id}/delete", headers=customer_headers(customer))
    assert r.status_code == 200
    assert post.call_args.args[0] == apple_signin.REVOKE_URL
    assert post.call_args.kwargs["data"]["token"] == "r-secret"
    assert post.call_args.kwargs["data"]["token_type_hint"] == "refresh_token"
    assert db_session.query(AppleSigninToken).count() == 0


def test_apple_failure_never_fails_deletion_and_is_retried(client, db_session, apple_env, stripe_mock):
    driver = make_driver(db_session)
    db_session.add(AppleSigninToken(account_type="driver", account_id=driver.id,
                                    refresh_token_encrypted=__import__("encryption").encrypt_field("r2")))
    db_session.commit()
    with patch.object(apple_signin.requests, "post", side_effect=ConnectionError("apple down")):
        r = client.delete(f"/api/drivers/{driver.id}/delete", headers=driver_headers(driver))
    assert r.status_code == 200
    assert db_session.query(AppleSigninToken).count() == 1  # kept for a retry

    admin = User(email=f"adm_{uid()}@example.com", password_hash=get_password_hash(PASSWORD), full_name="A",
                 role=UserRole.ADMIN)
    db_session.add(admin)
    db_session.commit()
    with patch.object(apple_signin.requests, "post", return_value=fake_response(200)):
        assert client.delete(f"/api/drivers/{driver.id}/delete", headers=admin_headers(admin)).status_code == 200
    assert db_session.query(AppleSigninToken).count() == 0


@pytest.mark.parametrize("role,bundle", [("customer", "com.dollorai.customer"), ("driver", "com.dollorai.delivery")])
def test_exchange_and_revoke_use_the_role_client_id(db_session, apple_env, role, bundle):
    account = make_customer(db_session) if role == "customer" else make_driver(db_session)
    with patch.object(apple_signin.requests, "post", return_value=fake_response(200, {"refresh_token": "r"})) as post:
        assert apple_signin.store_refresh_token_from_code(db_session, role, account.id, "code")
    data = post.call_args.kwargs["data"]
    claims, kid = secret_claims_and_kid(data["client_secret"])
    assert data["client_id"] == bundle and claims["sub"] == bundle and claims["iss"] == "TEAM123456"
    assert claims["aud"] == apple_signin.APPLE_AUDIENCE and claims["exp"] - claims["iat"] <= 300 and kid == "KEY1234567"
    with patch.object(apple_signin.requests, "post", return_value=fake_response(200)) as post:
        assert apple_signin.revoke_for_account(db_session, role, account.id)
    revoke_data = post.call_args.kwargs["data"]
    assert revoke_data["client_id"] == bundle
    assert secret_claims_and_kid(revoke_data["client_secret"])[0]["sub"] == bundle


def test_client_id_env_precedence(monkeypatch):
    for name in APPLE_ROLE_VARS:
        monkeypatch.delenv(name, raising=False)
    assert apple_signin.client_id_for_role("customer") == "com.dollorai.customer"
    assert apple_signin.client_id_for_role("driver") == "com.dollorai.delivery"
    assert apple_signin.client_id_for_role("vendor") is None
    monkeypatch.setenv("APPLE_CLIENT_ID", "com.legacy.app")  # legacy fallback applies to both roles
    assert apple_signin.client_id_for_role("customer") == apple_signin.client_id_for_role("driver") == "com.legacy.app"
    monkeypatch.setenv("APPLE_CLIENT_ID_CUSTOMER", "com.new.rider")
    monkeypatch.setenv("APPLE_CLIENT_ID_DRIVER", "com.new.driver")
    assert apple_signin.client_id_for_role("customer") == "com.new.rider"
    assert apple_signin.client_id_for_role("driver") == "com.new.driver"
    assert apple_signin.accepted_audiences() == {"com.legacy.app", "com.new.rider", "com.new.driver"}


def test_driver_key_override_with_shared_fallback(db_session, apple_env, monkeypatch):
    customer, driver = make_customer(db_session), make_driver(db_session)
    monkeypatch.setenv("APPLE_KEY_ID_DRIVER", "DRIVERKEY1")
    # override needs both variables: with only the key id, the shared key is still used
    with patch.object(apple_signin.requests, "post", return_value=fake_response(200, {"refresh_token": "r"})) as post:
        apple_signin.store_refresh_token_from_code(db_session, "driver", driver.id, "c")
    assert secret_claims_and_kid(post.call_args.kwargs["data"]["client_secret"])[1] == "KEY1234567"
    monkeypatch.setenv("APPLE_PRIVATE_KEY_DRIVER", new_pem())
    with patch.object(apple_signin.requests, "post", return_value=fake_response(200, {"refresh_token": "r"})) as post:
        apple_signin.store_refresh_token_from_code(db_session, "driver", driver.id, "c")
        apple_signin.store_refresh_token_from_code(db_session, "customer", customer.id, "c")
    driver_call, customer_call = post.call_args_list
    assert secret_claims_and_kid(driver_call.kwargs["data"]["client_secret"])[1] == "DRIVERKEY1"
    assert secret_claims_and_kid(customer_call.kwargs["data"]["client_secret"])[1] == "KEY1234567"


def test_missing_shared_credentials_make_both_roles_noop(db_session, monkeypatch):
    for name in apple_signin.REQUIRED_ENV + APPLE_ROLE_VARS:
        monkeypatch.delenv(name, raising=False)
    assert not apple_signin.is_configured("customer") and not apple_signin.is_configured("driver")


def test_apple_auth_passes_authorization_code_to_storage(client, db_session):
    with patch("main_new.verify_apple_identity", return_value=("apple-sub-1", "rider@example.com")), \
            patch.object(apple_signin, "store_refresh_token_from_code") as store:
        r = client.post("/api/customer/apple-auth", json={"identity_token": "t", "authorization_code": "abc"})
    assert r.status_code == 200, r.text
    assert store.call_args.args[1] == "customer" and store.call_args.args[3] == "abc"


# ------------------------------------------------------------------ driver bank numbers

def test_raw_bank_numbers_are_not_persisted(client, db_session):
    driver = make_driver(db_session)
    driver.bank_name = driver.bank_last4 = None
    db_session.commit()
    r = client.put(f"/api/drivers/{driver.id}", headers=driver_headers(driver), json={
        "city": "Oakland", "bank_name": "Chase", "bank_routing_number": "121000248", "account_number": "000123456789"})
    assert r.status_code == 200, r.text
    body = r.json()
    assert body["success"] is True and body["bank_details_ignored"] is True and "Stripe" in body["bank_error"]
    db_session.expire_all()
    stored = db_session.query(Driver).filter(Driver.id == driver.id).one()
    assert stored.city == "Oakland"  # the rest of the profile still saves
    assert (stored.bank_name, stored.bank_last4, stored.bank_routing_number, stored.bank_verified) == (None, None, None, False)


def test_profile_update_without_bank_fields_is_unchanged(client, db_session):
    driver = make_driver(db_session)
    r = client.put(f"/api/drivers/{driver.id}", headers=driver_headers(driver), json={"city": "Fresno"})
    assert r.status_code == 200 and "bank_details_ignored" not in r.json()


# ------------------------------------------------------------------ legal pages

@pytest.mark.parametrize("path", ["/terms", "/privacy"])
def test_link_checkers_can_read_legal_pages(client, path):
    assert client.get(path, headers={"User-Agent": "python-requests/2.32"}).status_code == 200
    assert client.get(path, headers={"User-Agent": "curl/8.4"}).status_code == 200


def test_terms_describe_report_block_and_support_contact(client):
    html = client.get("/terms").text
    assert "Content and Conduct" in html and "block a user" in html and "support@dollor.ai" in html
