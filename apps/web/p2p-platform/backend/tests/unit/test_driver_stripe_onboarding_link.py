"""GET /api/drivers/{id}/stripe/onboarding-link must always answer with a clean JSON error
(never an unhandled exception / plain-text 500) when Stripe misbehaves."""
from unittest.mock import MagicMock, patch

import pytest
import stripe
from fastapi.testclient import TestClient

from main_new import app, create_access_token


@pytest.fixture(autouse=True)
def stripe_key(monkeypatch):
    monkeypatch.setenv("STRIPE_SECRET_KEY", "sk_test_dummy")


@pytest.fixture
def headers(test_driver):
    token = create_access_token(data={"sub": test_driver.email, "role": "driver", "driver_id": test_driver.id})
    return {"Authorization": f"Bearer {token}"}


@pytest.fixture
def lenient_client(client):
    """Same app/db override as `client`, but unhandled exceptions become real 500 responses
    (as in production) instead of being re-raised into the test."""
    return TestClient(app, raise_server_exceptions=False)


def url(driver):
    return f"/api/drivers/{driver.id}/stripe/onboarding-link"


def test_happy_path_creates_account_and_returns_link(client, db_session, test_driver, headers):
    with patch("stripe.Account.create", return_value=MagicMock(id="acct_new1")) as create, \
         patch("stripe.AccountLink.create", return_value=MagicMock(url="https://connect.stripe.com/x", expires_at=123)):
        resp = client.get(url(test_driver), headers=headers)
    assert resp.status_code == 200
    body = resp.json()
    assert body["onboarding_url"] == "https://connect.stripe.com/x"
    assert body["stripe_account_id"] == "acct_new1"
    create.assert_called_once()
    db_session.refresh(test_driver)
    assert test_driver.stripe_account_id == "acct_new1"


def test_other_drivers_account_is_forbidden(client, test_driver, headers):
    assert client.get(f"/api/drivers/{test_driver.id + 1}/stripe/onboarding-link", headers=headers).status_code == 403


@pytest.mark.parametrize("error, expected_status", [
    (stripe.AuthenticationError("No API key provided"), 503),
    (stripe.APIConnectionError("network down"), 503),
    (stripe.RateLimitError("slow down"), 429),
    (stripe.InvalidRequestError("Connect not enabled", param=None), 502),
    (stripe.StripeError("boom"), 502),
])
def test_stripe_errors_on_link_creation_return_clean_json(lenient_client, db_session, test_driver, headers, error, expected_status):
    test_driver.stripe_account_id = "acct_existing"
    db_session.commit()
    with patch("stripe.AccountLink.create", side_effect=error):
        resp = lenient_client.get(url(test_driver), headers=headers)
    assert resp.status_code == expected_status
    assert resp.headers["content-type"].startswith("application/json")
    assert resp.json()["detail"]


def test_stripe_errors_on_account_creation_return_clean_json(lenient_client, test_driver, headers):
    with patch("stripe.Account.create", side_effect=stripe.AuthenticationError("No API key provided")):
        resp = lenient_client.get(url(test_driver), headers=headers)
    assert resp.status_code == 503
    assert resp.json()["detail"]


def test_unexpected_exception_returns_json_detail(lenient_client, test_driver, headers):
    with patch("stripe.Account.create", side_effect=RuntimeError("unexpected")):
        resp = lenient_client.get(url(test_driver), headers=headers)
    assert resp.status_code == 502
    assert resp.headers["content-type"].startswith("application/json")
    assert resp.json()["detail"]


def test_stale_account_id_is_replaced_once(client, db_session, test_driver, headers):
    """A saved account id that Stripe no longer knows (e.g. platform key changed) must not wedge the driver."""
    test_driver.stripe_account_id = "acct_gone"
    db_session.commit()
    missing = stripe.InvalidRequestError("No such account: 'acct_gone'", param="account", code="resource_missing")
    link = MagicMock(url="https://connect.stripe.com/y", expires_at=456)
    with patch("stripe.AccountLink.create", side_effect=[missing, link]), \
         patch("stripe.Account.create", return_value=MagicMock(id="acct_fresh")):
        resp = client.get(url(test_driver), headers=headers)
    assert resp.status_code == 200
    assert resp.json()["stripe_account_id"] == "acct_fresh"
    db_session.refresh(test_driver)
    assert test_driver.stripe_account_id == "acct_fresh"


def test_missing_stripe_key_returns_503(lenient_client, test_driver, headers, monkeypatch):
    monkeypatch.delenv("STRIPE_SECRET_KEY", raising=False)
    resp = lenient_client.get(url(test_driver), headers=headers)
    assert resp.status_code == 503
    assert resp.json()["detail"]
