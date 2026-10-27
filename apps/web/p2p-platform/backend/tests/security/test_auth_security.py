"""
Auth security integration tests (H5).

Tests verify:
- Cross-role access prevention (customer/driver/vendor token misuse)
- Account enumeration protection (generic error messages)
- Token manipulation (tampered, expired, missing)
- Rate limiting (11 attempts → 429)
- Password reset one-time-use
- WebSocket auth (no token → 4001)

Run: pytest tests/security/test_auth_security.py -v
"""

import pytest
import os
import sys
import time
from datetime import datetime, timedelta, timezone

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.dirname(__file__))))

from fastapi.testclient import TestClient
from jose import jwt

# Test configuration
BASE_URL = os.getenv("TEST_BASE_URL", "")  # empty = use TestClient
JWT_SECRET = os.getenv("JWT_SECRET_KEY", "test-secret-key")
ALGORITHM = "HS256"
SKIP_EMAIL_TESTS = os.getenv("SKIP_EMAIL_TESTS", "1") == "1"
SKIP_RATE_LIMIT_TESTS = os.getenv("SKIP_RATE_LIMIT_TESTS", "1") == "1"


@pytest.fixture(scope="module")
def client():
    from main_new import app
    with TestClient(app, raise_server_exceptions=False) as c:
        yield c


@pytest.fixture(scope="module")
def customer_token(client):
    """Get a valid customer JWT."""
    resp = client.post(
        "/api/auth/customer/login",
        data={"username": "demo.customer@dollor.ai", "password": "DemoCustomer2025!"},
    )
    if resp.status_code == 200:
        return resp.json().get("access_token")
    pytest.skip("Demo customer login failed — skipping token-dependent tests")


@pytest.fixture(scope="module")
def driver_token(client):
    """Get a valid driver JWT."""
    resp = client.post(
        "/api/auth/driver/login",
        data={"username": "demo.driver@dollor.ai", "password": "DemoDriver2025!"},
    )
    if resp.status_code == 200:
        return resp.json().get("access_token")
    pytest.skip("Demo driver login failed — skipping token-dependent tests")


# ──────────────────────────────────────────────────────────────────────────────
# 1. CROSS-ROLE ACCESS PREVENTION
# ──────────────────────────────────────────────────────────────────────────────

class TestCrossRoleAccess:
    def test_customer_token_cannot_access_driver_earnings(self, client, customer_token):
        """Customer JWT must not access driver earnings endpoint."""
        resp = client.get(
            "/api/driver/earnings",
            headers={"Authorization": f"Bearer {customer_token}"},
        )
        assert resp.status_code in (401, 403), (
            f"Expected 401/403 but got {resp.status_code}: {resp.text}"
        )

    def test_driver_token_cannot_request_ride_as_customer(self, client, driver_token):
        """Driver JWT must not create a customer ride request."""
        resp = client.post(
            "/api/rides/request",
            json={"pickup_location": "A", "dropoff_location": "B", "fare": 10},
            headers={"Authorization": f"Bearer {driver_token}"},
        )
        assert resp.status_code in (401, 403), (
            f"Expected 401/403 but got {resp.status_code}: {resp.text}"
        )

    def test_customer_token_cannot_access_admin_users(self, client, customer_token):
        """Customer JWT must not list admin users."""
        resp = client.get(
            "/api/admin/users",
            headers={"Authorization": f"Bearer {customer_token}"},
        )
        assert resp.status_code in (401, 403), (
            f"Expected 401/403 but got {resp.status_code}: {resp.text}"
        )


# ──────────────────────────────────────────────────────────────────────────────
# 2. ACCOUNT ENUMERATION PROTECTION
# ──────────────────────────────────────────────────────────────────────────────

class TestEnumerationProtection:
    def test_nonexistent_email_returns_generic_error(self, client):
        """Login with non-existent email → generic error (no email-existence leak)."""
        resp = client.post(
            "/api/auth/customer/login",
            data={"username": "nonexistent_xyz_123@example.com", "password": "WrongPass1!"},
        )
        assert resp.status_code in (400, 401, 422), f"Unexpected status: {resp.status_code}"
        body = resp.text.lower()
        assert "incorrect" in body or "invalid" in body or "wrong" in body, (
            f"Unexpected error message: {resp.text}"
        )
        # Must NOT say "email not found" or "no account"
        assert "not found" not in body, "Error reveals email non-existence"
        assert "no account" not in body, "Error reveals email non-existence"
        assert "does not exist" not in body, "Error reveals email non-existence"

    def test_wrong_password_returns_same_error_format(self, client):
        """Login with existing email + wrong password → same generic error format."""
        resp = client.post(
            "/api/auth/customer/login",
            data={"username": "demo.customer@dollor.ai", "password": "WrongPassword999!"},
        )
        assert resp.status_code in (400, 401, 422)
        body = resp.text.lower()
        assert "not found" not in body, "Error reveals email existence via different message"


# ──────────────────────────────────────────────────────────────────────────────
# 3. TOKEN MANIPULATION
# ──────────────────────────────────────────────────────────────────────────────

class TestTokenManipulation:
    def test_tampered_jwt_returns_401(self, client, customer_token):
        """Tampered JWT signature must be rejected."""
        tampered = customer_token[:-4] + "XXXX"
        resp = client.get(
            "/api/customers/profile",
            headers={"Authorization": f"Bearer {tampered}"},
        )
        assert resp.status_code == 401, f"Expected 401 but got {resp.status_code}"

    def test_expired_token_returns_401(self, client):
        """Expired JWT must be rejected."""
        expired_token = jwt.encode(
            {
                "sub": "demo.customer@dollor.ai",
                "role": "customer",
                "customer_id": 1,
                "exp": datetime.now(timezone.utc) - timedelta(hours=1),
            },
            JWT_SECRET,
            algorithm=ALGORITHM,
        )
        resp = client.get(
            "/api/customers/profile",
            headers={"Authorization": f"Bearer {expired_token}"},
        )
        assert resp.status_code == 401, f"Expected 401 for expired token, got {resp.status_code}"

    def test_missing_auth_header_returns_401(self, client):
        """Protected endpoint without Authorization header must return 401."""
        resp = client.get("/api/customers/profile")
        assert resp.status_code == 401, f"Expected 401 but got {resp.status_code}"

    def test_malformed_bearer_token_returns_401(self, client):
        """Garbage token must be rejected."""
        resp = client.get(
            "/api/customers/profile",
            headers={"Authorization": "Bearer not.a.real.jwt"},
        )
        assert resp.status_code == 401, f"Expected 401 but got {resp.status_code}"


# ──────────────────────────────────────────────────────────────────────────────
# 4. RATE LIMITING
# ──────────────────────────────────────────────────────────────────────────────

class TestRateLimiting:
    @pytest.mark.skipif(SKIP_RATE_LIMIT_TESTS, reason="SKIP_RATE_LIMIT_TESTS=1")
    def test_login_rate_limit_triggers_after_10_attempts(self, client):
        """11th login attempt within rate window must return 429."""
        # Use a unique email so we don't interfere with other tests
        email = f"ratelimit_test_{int(time.time())}@example.com"
        status_codes = []
        for i in range(11):
            resp = client.post(
                "/api/auth/customer/login",
                data={"username": email, "password": f"WrongPass{i}!"},
            )
            status_codes.append(resp.status_code)

        assert 429 in status_codes, (
            f"Expected 429 on 11th attempt but got status codes: {status_codes}"
        )
        # Verify Retry-After or X-RateLimit-Reset header is present on 429
        for i, code in enumerate(status_codes):
            if code == 429:
                resp_429 = client.post(
                    "/api/auth/customer/login",
                    data={"username": email, "password": "WrongPass!"},
                )
                has_retry_header = (
                    "retry-after" in resp_429.headers
                    or "x-ratelimit-reset" in resp_429.headers
                )
                assert has_retry_header, "429 response missing Retry-After/X-RateLimit-Reset header"
                break


# ──────────────────────────────────────────────────────────────────────────────
# 5. PASSWORD RESET ONE-TIME-USE
# ──────────────────────────────────────────────────────────────────────────────

class TestPasswordReset:
    @pytest.mark.skipif(SKIP_EMAIL_TESTS, reason="SKIP_EMAIL_TESTS=1 (requires email interception)")
    def test_reset_token_is_single_use(self, client):
        """Password reset token must be invalidated after first use."""
        # Request reset
        resp = client.post(
            "/api/customer/password-reset/request",
            json={"email": "demo.customer@dollor.ai"},
        )
        assert resp.status_code == 200

        # In a real test environment, we'd intercept the email to get the token.
        # This test is skipped unless email interception is configured.
        pytest.skip("Token interception not configured — set SKIP_EMAIL_TESTS=0 and wire email mock")

    def test_vendor_admin_reset_returns_success_for_unknown_email(self, client):
        """Password reset for unknown email must return 200 (no enumeration)."""
        resp = client.post(
            "/api/auth/password-reset/request",
            json={"email": "nobody_xyz_999@example.com"},
        )
        assert resp.status_code == 200, f"Unexpected status: {resp.status_code}"
        body = resp.json()
        assert "message" in body


# ──────────────────────────────────────────────────────────────────────────────
# 6. WEBSOCKET AUTH
# ──────────────────────────────────────────────────────────────────────────────

class TestWebSocketAuth:
    def test_websocket_without_token_is_rejected(self, client):
        """WebSocket connection without token must be closed with code 4001."""
        from starlette.websockets import WebSocketDisconnect

        with pytest.raises(WebSocketDisconnect) as exc_info:
            with client.websocket_connect("/ws/test-client-id") as ws:
                ws.receive_text()
        assert exc_info.value.code == 4001

    def test_websocket_with_invalid_token_is_rejected(self, client):
        """WebSocket connection with a garbage token must be closed (4001/4003)."""
        from starlette.websockets import WebSocketDisconnect

        with pytest.raises(WebSocketDisconnect) as exc_info:
            with client.websocket_connect("/ws/test-client-id?token=garbage") as ws:
                ws.receive_text()
        assert exc_info.value.code in (4001, 4003)
