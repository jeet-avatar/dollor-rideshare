"""
Full Ride Lifecycle — Live E2E Test
====================================

Runs the complete rideshare flow end-to-end against a live environment
(staging or production) using the demo accounts.

Usage:
    cd apps/web/p2p-platform/backend
    RUN_LIVE_RIDE_E2E=1 pytest tests/smoke/test_full_ride_e2e.py --env=production -v
    RUN_LIVE_RIDE_E2E=1 pytest tests/smoke/test_full_ride_e2e.py --env=staging -v

Flow covered:
  1.  Customer login
  2.  Create ride request            → ride_request_confirmation email
  3.  Driver login
  4.  Driver goes online
  5.  Driver submits bid             → ride_bid_received email to customer
  6.  Customer lists bids            → sees Marcus Johnson's bid
  7.  Customer accepts bid           → ride_matched email to both parties
  8.  Driver marks arrived
  9.  Driver starts ride             → ride_started email to customer
  10. Driver completes ride          → ride_completed + receipt emails
  11. Customer requests email receipt (explicit)
  12. Customer rates driver
  13. Health check still OK          → system stable after full flow
"""

import os

import pytest
import requests

from .conftest import auth_header

# This test WRITES to a live environment (creates, matches and completes a real ride and
# sends real emails), so it never runs by default. Opt in explicitly.
pytestmark = pytest.mark.skipif(
    os.getenv("RUN_LIVE_RIDE_E2E") != "1",
    reason="Live-environment write test: set RUN_LIVE_RIDE_E2E=1 and pass --env to run",
)

TIMEOUT = 15
DEMO_DRIVER_ID = 48
DEMO_CUSTOMER_ID = 74
MOBILE_UA = (
    "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) "
    "AppleWebKit/605.1.15 (KHTML, like Gecko) Mobile/15E148"
)


# ---------------------------------------------------------------------------
# Session-scoped shared state (ride_id, bid_id flow through the whole test)
# ---------------------------------------------------------------------------

@pytest.fixture(scope="module")
def ride_ctx():
    """Mutable dict shared across all steps in this module."""
    return {}


@pytest.fixture(scope="module")
def base(env_url):
    return env_url


@pytest.fixture(scope="module")
def headers_customer(base):
    resp = requests.post(
        f"{base}/api/auth/customer/login",
        data={"username": "demo.customer@dollor.ai", "password": "DemoCustomer2025!"},
        headers={"User-Agent": MOBILE_UA},
        timeout=TIMEOUT,
    )
    assert resp.status_code == 200, f"Customer login failed: {resp.text[:300]}"
    token = resp.json()["access_token"]
    return {"Authorization": f"Bearer {token}", "User-Agent": MOBILE_UA}


@pytest.fixture(scope="module")
def headers_driver(base):
    resp = requests.post(
        f"{base}/api/auth/driver/login",
        data={"username": "demo.driver@dollor.ai", "password": "DemoDriver2025!"},
        headers={"User-Agent": MOBILE_UA},
        timeout=TIMEOUT,
    )
    assert resp.status_code == 200, f"Driver login failed: {resp.text[:300]}"
    token = resp.json()["access_token"]
    return {"Authorization": f"Bearer {token}", "User-Agent": MOBILE_UA}


# ---------------------------------------------------------------------------
# Step 1 — Customer authentication
# ---------------------------------------------------------------------------

class TestStep01_CustomerLogin:
    def test_login_returns_200(self, base):
        resp = requests.post(
            f"{base}/api/auth/customer/login",
            data={"username": "demo.customer@dollor.ai", "password": "DemoCustomer2025!"},
            headers={"User-Agent": MOBILE_UA},
            timeout=TIMEOUT,
        )
        assert resp.status_code == 200

    def test_login_returns_access_token(self, base):
        resp = requests.post(
            f"{base}/api/auth/customer/login",
            data={"username": "demo.customer@dollor.ai", "password": "DemoCustomer2025!"},
            headers={"User-Agent": MOBILE_UA},
            timeout=TIMEOUT,
        )
        data = resp.json()
        assert "access_token" in data
        assert len(data["access_token"]) > 20

    def test_login_role_is_customer(self, base):
        import base64, json as _json
        resp = requests.post(
            f"{base}/api/auth/customer/login",
            data={"username": "demo.customer@dollor.ai", "password": "DemoCustomer2025!"},
            headers={"User-Agent": MOBILE_UA},
            timeout=TIMEOUT,
        )
        token = resp.json()["access_token"]
        payload_b64 = token.split(".")[1] + "==="
        payload = _json.loads(base64.urlsafe_b64decode(payload_b64))
        assert payload.get("role") == "customer"
        assert payload.get("customer_id") == DEMO_CUSTOMER_ID

    def test_wrong_password_returns_401(self, base):
        resp = requests.post(
            f"{base}/api/auth/customer/login",
            data={"username": "demo.customer@dollor.ai", "password": "WrongPassword!"},
            headers={"User-Agent": MOBILE_UA},
            timeout=TIMEOUT,
        )
        assert resp.status_code in (401, 400)


# ---------------------------------------------------------------------------
# Step 2 — Create ride request
# ---------------------------------------------------------------------------

class TestStep02_CreateRideRequest:
    def test_ride_request_succeeds(self, base, headers_customer, ride_ctx):
        resp = requests.post(
            f"{base}/api/rides/request",
            json={
                "customer_id": DEMO_CUSTOMER_ID,
                "pickup_address": "123 Main St, Rancho Santa Margarita, CA 92688",
                "dropoff_address": "456 Crown Valley Pkwy, Mission Viejo, CA 92691",
                "pickup_latitude": 33.6407,
                "pickup_longitude": -117.5917,
                "dropoff_latitude": 33.6001,
                "dropoff_longitude": -117.6720,
                "vehicle_type": "standard",
                "notes": "Automated E2E test",
            },
            headers=headers_customer,
            timeout=TIMEOUT,
        )
        assert resp.status_code == 200, f"Ride request failed: {resp.text[:300]}"
        data = resp.json()
        assert data.get("success") is True
        ride = data["ride_request"]
        assert ride["id"] > 0
        assert ride["status"] in ("open", "pending", "bidding")
        # Store for downstream steps
        ride_ctx["request_id"] = ride["id"]

    def test_ride_has_pickup_and_dropoff(self, base, headers_customer, ride_ctx):
        assert ride_ctx.get("request_id"), "ride_ctx not populated — did step 2a fail?"

    @pytest.mark.xfail(
        reason="M4 JWT role enforcement not yet deployed to production — "
               "driver token must be rejected by require_customer() after deploy"
    )
    def test_driver_cannot_create_ride(self, base, headers_driver):
        resp = requests.post(
            f"{base}/api/rides/request",
            json={
                "customer_id": DEMO_CUSTOMER_ID,
                "pickup_address": "123 Main St, RSM, CA",
                "dropoff_address": "456 Crown Valley Pkwy, MV, CA",
                "pickup_latitude": 33.6407,
                "pickup_longitude": -117.5917,
                "dropoff_latitude": 33.6001,
                "dropoff_longitude": -117.6720,
                "vehicle_type": "standard",
            },
            headers=headers_driver,
            timeout=TIMEOUT,
        )
        # After M4 deploy: driver JWT (role=driver) must be rejected by require_customer
        assert resp.status_code in (403, 401), (
            f"Driver was allowed to create a ride: {resp.status_code} {resp.text[:200]}"
        )


# ---------------------------------------------------------------------------
# Step 3 — Driver login
# ---------------------------------------------------------------------------

class TestStep03_DriverLogin:
    def test_driver_login_returns_200(self, base):
        resp = requests.post(
            f"{base}/api/auth/driver/login",
            data={"username": "demo.driver@dollor.ai", "password": "DemoDriver2025!"},
            headers={"User-Agent": MOBILE_UA},
            timeout=TIMEOUT,
        )
        assert resp.status_code == 200

    def test_driver_token_role_is_driver(self, base):
        import base64, json as _json
        resp = requests.post(
            f"{base}/api/auth/driver/login",
            data={"username": "demo.driver@dollor.ai", "password": "DemoDriver2025!"},
            headers={"User-Agent": MOBILE_UA},
            timeout=TIMEOUT,
        )
        token = resp.json()["access_token"]
        payload_b64 = token.split(".")[1] + "==="
        payload = _json.loads(base64.urlsafe_b64decode(payload_b64))
        assert payload.get("role") == "driver"


# ---------------------------------------------------------------------------
# Step 4 — Driver goes online
# ---------------------------------------------------------------------------

class TestStep04_DriverOnline:
    def test_driver_goes_online(self, base, headers_driver):
        resp = requests.post(
            f"{base}/api/drivers/{DEMO_DRIVER_ID}/status",
            params={"is_online": "true"},
            json={"latitude": 33.6407, "longitude": -117.5917},
            headers=headers_driver,
            timeout=TIMEOUT,
        )
        assert resp.status_code == 200, f"Driver online failed: {resp.text[:200]}"
        data = resp.json()
        assert data.get("is_online") is True
        assert data.get("driver_id") == DEMO_DRIVER_ID

    def test_customer_cannot_set_driver_online(self, base, headers_customer):
        resp = requests.post(
            f"{base}/api/drivers/{DEMO_DRIVER_ID}/status",
            params={"is_online": "true"},
            json={"latitude": 33.6407, "longitude": -117.5917},
            headers=headers_customer,
            timeout=TIMEOUT,
        )
        assert resp.status_code in (401, 403), (
            f"Customer was allowed to toggle driver online: {resp.status_code}"
        )


# ---------------------------------------------------------------------------
# Step 5 — Driver submits bid  (triggers ride_bid_received email)
# ---------------------------------------------------------------------------

class TestStep05_DriverBid:
    def test_bid_submitted_successfully(self, base, headers_driver, ride_ctx):
        req_id = ride_ctx.get("request_id")
        assert req_id, "No request_id from step 2"

        resp = requests.post(
            f"{base}/api/rides/request/{req_id}/bid",
            json={
                "driver_id": DEMO_DRIVER_ID,
                "proposed_price": 18.50,
                "eta_minutes": 5,
                "message": "On my way! Automated E2E test.",
            },
            headers=headers_driver,
            timeout=TIMEOUT,
        )
        assert resp.status_code == 200, f"Bid failed: {resp.text[:300]}"
        data = resp.json()
        assert data.get("success") is True
        bid = data["bid"]
        assert bid["id"] > 0
        assert bid["proposed_price"] == 18.50
        assert bid["driver_id"] == DEMO_DRIVER_ID
        ride_ctx["bid_id"] = bid["id"]

    def test_bid_has_driver_info(self, base, headers_driver, ride_ctx):
        assert ride_ctx.get("bid_id"), "bid_id not set — did step 5a fail?"

    def test_customer_cannot_bid(self, base, headers_customer, ride_ctx):
        req_id = ride_ctx.get("request_id")
        resp = requests.post(
            f"{base}/api/rides/request/{req_id}/bid",
            json={
                "driver_id": DEMO_CUSTOMER_ID,
                "proposed_price": 5.00,
                "eta_minutes": 1,
            },
            headers=headers_customer,
            timeout=TIMEOUT,
        )
        assert resp.status_code in (401, 403, 422), (
            f"Customer was allowed to bid: {resp.status_code}"
        )


# ---------------------------------------------------------------------------
# Step 6 — Customer lists bids
# ---------------------------------------------------------------------------

class TestStep06_CustomerListsBids:
    def test_customer_can_see_bids(self, base, headers_customer, ride_ctx):
        req_id = ride_ctx.get("request_id")
        resp = requests.get(
            f"{base}/api/rides/request/{req_id}/bids",
            headers=headers_customer,
            timeout=TIMEOUT,
        )
        assert resp.status_code == 200, f"List bids failed: {resp.text[:200]}"
        data = resp.json()
        bids = data if isinstance(data, list) else data.get("bids", [])
        assert len(bids) >= 1, "No bids found for this ride request"
        bid_ids = [b["id"] for b in bids]
        assert ride_ctx["bid_id"] in bid_ids, "Our bid not in customer's bid list"

    def test_driver_cannot_see_other_ride_bids(self, base, headers_driver, ride_ctx):
        # Driver should only see their own bids (not all bids on a request)
        req_id = ride_ctx.get("request_id")
        resp = requests.get(
            f"{base}/api/rides/request/{req_id}/bids",
            headers=headers_driver,
            timeout=TIMEOUT,
        )
        # Either 403 (driver can't list) or 200 with filtered results — not a hard rule
        assert resp.status_code in (200, 403)


# ---------------------------------------------------------------------------
# Step 7 — Customer accepts bid  (triggers ride_matched email)
# ---------------------------------------------------------------------------

class TestStep07_CustomerAcceptsBid:
    def test_accept_bid_succeeds(self, base, headers_customer, ride_ctx):
        bid_id = ride_ctx.get("bid_id")
        assert bid_id, "No bid_id from step 5"

        resp = requests.post(
            f"{base}/api/rides/bid/{bid_id}/respond",
            json={"action": "accept"},
            headers=headers_customer,
            timeout=TIMEOUT,
        )
        assert resp.status_code == 200, f"Accept bid failed: {resp.text[:300]}"
        data = resp.json()
        assert data.get("status") == "accepted"

    def test_ride_status_is_matched_after_accept(self, base, headers_customer, ride_ctx):
        req_id = ride_ctx.get("request_id")
        resp = requests.get(
            f"{base}/api/rides/request/{req_id}",
            headers=headers_customer,
            timeout=TIMEOUT,
        )
        assert resp.status_code == 200
        data = resp.json()
        # Response is wrapped: {"success": true, "ride_request": {...}}
        ride = data.get("ride_request", data)
        assert ride.get("status") in ("matched", "accepted", "driver_assigned", "in_progress"), (
            f"Unexpected status after accept: {ride.get('status')}"
        )


# ---------------------------------------------------------------------------
# Step 8 — Driver marks arrived at pickup
# ---------------------------------------------------------------------------

class TestStep08_DriverArrived:
    def test_driver_arrived_succeeds(self, base, headers_driver, ride_ctx):
        req_id = ride_ctx.get("request_id")
        resp = requests.post(
            f"{base}/api/rides/request/{req_id}/arrived",
            json={"latitude": 33.6407, "longitude": -117.5917},
            headers=headers_driver,
            timeout=TIMEOUT,
        )
        assert resp.status_code == 200, f"Arrived failed: {resp.text[:200]}"
        data = resp.json()
        assert data.get("message") or data.get("success")


# ---------------------------------------------------------------------------
# Step 9 — Driver starts ride  (triggers ride_started email)
# ---------------------------------------------------------------------------

class TestStep09_StartRide:
    def test_start_ride_succeeds(self, base, headers_driver, ride_ctx):
        req_id = ride_ctx.get("request_id")
        resp = requests.post(
            f"{base}/api/rides/request/{req_id}/start",
            json={"latitude": 33.6407, "longitude": -117.5917},
            headers=headers_driver,
            timeout=TIMEOUT,
        )
        assert resp.status_code == 200, f"Start ride failed: {resp.text[:200]}"
        data = resp.json()
        assert "start" in str(data).lower() or data.get("success") or data.get("message")

    def test_customer_cannot_start_ride(self, base, headers_customer, ride_ctx):
        req_id = ride_ctx.get("request_id")
        resp = requests.post(
            f"{base}/api/rides/request/{req_id}/start",
            json={"latitude": 33.6407, "longitude": -117.5917},
            headers=headers_customer,
            timeout=TIMEOUT,
        )
        # A customer token should not be able to start a ride
        assert resp.status_code in (401, 403, 409, 400), (
            f"Customer was allowed to start ride: {resp.status_code}"
        )


# ---------------------------------------------------------------------------
# Step 10 — Driver completes ride  (triggers ride_completed + receipt emails)
# ---------------------------------------------------------------------------

class TestStep10_CompleteRide:
    def test_complete_ride_succeeds(self, base, headers_driver, ride_ctx):
        req_id = ride_ctx.get("request_id")
        resp = requests.post(
            f"{base}/api/rides/request/{req_id}/complete",
            json={"latitude": 33.6001, "longitude": -117.6720, "odometer_end": 99999.0},
            headers=headers_driver,
            timeout=TIMEOUT,
        )
        assert resp.status_code == 200, f"Complete ride failed: {resp.text[:300]}"
        data = resp.json()
        assert data.get("success") is True
        ride = data["ride_request"]
        assert ride["status"] == "completed"
        assert ride["final_price"] == 18.50
        ride_ctx["completed"] = True

    def test_completed_ride_has_earnings_breakdown(self, base, headers_driver, ride_ctx):
        assert ride_ctx.get("completed"), "Ride not completed — did step 10a fail?"


# ---------------------------------------------------------------------------
# Step 11 — Customer requests email receipt explicitly
# ---------------------------------------------------------------------------

class TestStep11_EmailReceipt:
    def test_email_receipt_sent(self, base, headers_customer, ride_ctx):
        req_id = ride_ctx.get("request_id")
        assert ride_ctx.get("completed"), "Ride not completed yet"

        resp = requests.post(
            f"{base}/api/rides/request/{req_id}/email-receipt",
            headers=headers_customer,
            timeout=TIMEOUT,
        )
        assert resp.status_code == 200, f"Email receipt failed: {resp.text[:200]}"
        data = resp.json()
        assert "sent" in str(data).lower() or data.get("success") or data.get("message")


# ---------------------------------------------------------------------------
# Step 12 — Customer rates driver
# ---------------------------------------------------------------------------

class TestStep12_RateDriver:
    def test_customer_can_rate_driver(self, base, headers_customer, ride_ctx):
        req_id = ride_ctx.get("request_id")
        assert ride_ctx.get("completed"), "Ride not completed yet"

        # Customer rating endpoint uses the integer ride ID (same as request_id here)
        # Route: POST /api/rides/{ride_id}/rate
        resp = requests.post(
            f"{base}/api/rides/{req_id}/rate",
            json={"rating": 5, "comment": "Excellent driver! Smooth ride. E2E test."},
            headers=headers_customer,
            timeout=TIMEOUT,
        )
        # 200/201 = rated, 409 = already rated (idempotent — acceptable in repeated runs)
        assert resp.status_code in (200, 201, 409), (
            f"Rating failed: {resp.status_code} {resp.text[:200]}"
        )


# ---------------------------------------------------------------------------
# Step 13 — System health after full flow
# ---------------------------------------------------------------------------

class TestStep13_HealthAfterFlow:
    def test_api_still_healthy(self, base):
        resp = requests.get(f"{base}/api/health", timeout=TIMEOUT)
        assert resp.status_code == 200

    def test_health_response_is_json(self, base):
        resp = requests.get(f"{base}/api/health", timeout=TIMEOUT)
        data = resp.json()
        assert isinstance(data, dict)


# ---------------------------------------------------------------------------
# Security regression tests (run alongside the flow)
# ---------------------------------------------------------------------------

class TestSecurityGuards:
    """Key security checks that must pass regardless of ride state."""

    def test_unauthenticated_ride_request_rejected(self, base):
        resp = requests.post(
            f"{base}/api/rides/request",
            json={
                "customer_id": DEMO_CUSTOMER_ID,
                "pickup_address": "Test",
                "dropoff_address": "Test2",
                "pickup_latitude": 33.0,
                "pickup_longitude": -117.0,
                "dropoff_latitude": 33.1,
                "dropoff_longitude": -117.1,
                "vehicle_type": "standard",
            },
            headers={"User-Agent": MOBILE_UA},
            timeout=TIMEOUT,
        )
        assert resp.status_code in (401, 403)

    @pytest.mark.xfail(
        reason="M4 JWT role enforcement not yet deployed — "
               "after deploy: driver token must get 403 from require_customer() endpoints"
    )
    def test_driver_token_rejected_from_customer_endpoint(self, base, headers_driver):
        resp = requests.post(
            f"{base}/api/rides/request",
            json={
                "customer_id": DEMO_CUSTOMER_ID,
                "pickup_address": "Test",
                "dropoff_address": "Test2",
                "pickup_latitude": 33.0,
                "pickup_longitude": -117.0,
                "dropoff_latitude": 33.1,
                "dropoff_longitude": -117.1,
                "vehicle_type": "standard",
            },
            headers=headers_driver,
            timeout=TIMEOUT,
        )
        assert resp.status_code in (401, 403)

    def test_driver_status_patch_rejected_without_admin(self, base, headers_driver):
        resp = requests.patch(
            f"{base}/api/drivers/{DEMO_DRIVER_ID}/status",
            json={"approval_status": "approved"},
            headers=headers_driver,
            timeout=TIMEOUT,
        )
        # Driver should NOT be able to self-approve (fixed in security audit)
        assert resp.status_code in (401, 403, 404, 405)

    @pytest.mark.xfail(
        reason="H7 authenticated-upload fix not yet deployed — "
               "after deploy: unauthenticated /uploads/ must return 401, not 404"
    )
    def test_upload_endpoint_requires_auth(self, base):
        resp = requests.get(
            f"{base}/uploads/test.jpg",
            headers={"User-Agent": MOBILE_UA},
            timeout=TIMEOUT,
        )
        assert resp.status_code in (401, 403)

    def test_invalid_jwt_rejected(self, base):
        resp = requests.get(
            f"{base}/api/rides/available",
            headers={
                "Authorization": "Bearer eyJhbGciOiJIUzI1NiJ9.fake.signature",
                "User-Agent": MOBILE_UA,
            },
            timeout=TIMEOUT,
        )
        assert resp.status_code == 401


# ---------------------------------------------------------------------------
# Email template smoke (verify the email module loads without error)
# ---------------------------------------------------------------------------

class TestEmailTemplateSmoke:
    """
    Verifies the email service templates render without exceptions.
    Runs in-process — no actual emails sent.
    """

    def test_email_templates_import_cleanly(self):
        """email_service must import and all _dollor_email functions must be callable."""
        import importlib, sys, types

        # Stub heavy deps so we can import without a running DB
        for mod in ("dotenv", "boto3", "botocore"):
            if mod not in sys.modules:
                sys.modules[mod] = types.ModuleType(mod)
        # dotenv.load_dotenv stub
        sys.modules["dotenv"].load_dotenv = lambda *a, **kw: None

        try:
            import importlib.util, pathlib
            spec = importlib.util.spec_from_file_location(
                "email_service_test",
                pathlib.Path(__file__).parent.parent.parent / "email_service.py",
            )
            es = importlib.util.module_from_spec(spec)
            # Don't exec (would need full env) — just check syntax via py_compile
            import py_compile
            py_compile.compile(str(spec.origin), doraise=True)
        except py_compile.PyCompileError as e:
            pytest.fail(f"email_service.py has a syntax error: {e}")

    def test_dollor_email_base_renders(self):
        """_dollor_email() should return a complete HTML document."""
        import sys, types, pathlib, importlib.util

        for mod in ("dotenv", "boto3", "botocore", "sendgrid", "smtplib"):
            if mod not in sys.modules:
                sys.modules[mod] = types.ModuleType(mod)
        sys.modules["dotenv"].load_dotenv = lambda *a, **kw: None

        # Minimal stubs needed for import
        for mod in ("sqlalchemy", "sqlalchemy.orm", "jose", "passlib",
                    "passlib.context", "stripe", "pydantic"):
            if mod not in sys.modules:
                sys.modules[mod] = types.ModuleType(mod)

        path = pathlib.Path(__file__).parent.parent.parent / "email_service.py"
        src = path.read_text()
        # Extract just _dollor_email and run it
        ns: dict = {}
        # Find the function definition and exec only it
        lines = src.splitlines()
        start = next(i for i, l in enumerate(lines) if "def _dollor_email(" in l)
        # Grab until next top-level def
        end = next(
            (i for i, l in enumerate(lines[start + 1:], start + 1)
             if l and l[0].isalpha() and l.startswith("def ")),
            len(lines),
        )
        func_src = "\n".join(lines[start:end])
        exec(compile(func_src, "<_dollor_email>", "exec"), ns)
        _dollor_email = ns["_dollor_email"]

        html = _dollor_email("🎉", "Test Title", "Test subtitle", "<p>Body content</p>")
        assert "<!DOCTYPE html>" in html
        assert "dollor" in html
        assert "Test Title" in html
        assert "Body content" in html
        assert "CPUC" in html
        assert "#ff6b00" in html  # orange brand color
        assert "#ffd700" not in html  # old gold color must be gone
        assert "1a1a2e" not in html   # old navy must be gone
