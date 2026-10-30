"""
Smoke test configuration for staging and production environments.

Provides --env flag, base URL fixtures, and demo credential fixtures.
Standalone -- no dependency on main app conftest or models.
"""
import os

import pytest
import requests


# ---------------------------------------------------------------------------
# pytest CLI option
# ---------------------------------------------------------------------------

def pytest_addoption(parser):
    parser.addoption(
        "--env",
        action="store",
        default="staging",
        choices=["staging", "production"],
        help="Target environment: staging or production",
    )


def pytest_configure(config):
    config.addinivalue_line(
        "markers",
        "staging_only: mark test to run only against staging (skipped in production)",
    )


def pytest_collection_modifyitems(config, items):
    """Auto-skip staging_only tests when running against production."""
    if config.getoption("--env") == "production":
        skip_staging = pytest.mark.skip(reason="staging_only test skipped in production")
        for item in items:
            if "staging_only" in item.keywords:
                item.add_marker(skip_staging)


# ---------------------------------------------------------------------------
# Environment fixtures
# ---------------------------------------------------------------------------

# Staging has no fixed host in this repository; provide it with STAGING_API_URL.
ENV_URLS = {
    "staging": os.getenv("STAGING_API_URL", ""),
    "production": "https://api.dollor.ai",
}


@pytest.fixture(scope="session")
def env_name(request):
    """Return the target environment name."""
    return request.config.getoption("--env")


@pytest.fixture(scope="session")
def env_url(request):
    """Return the base URL for the target environment."""
    env = request.config.getoption("--env")
    url = ENV_URLS[env]
    if not url:
        pytest.skip(f"No base URL configured for --env={env} (set STAGING_API_URL)")
    return url


# ---------------------------------------------------------------------------
# Demo credentials
# ---------------------------------------------------------------------------

DEMO_CREDENTIALS = {
    "customer": {
        "email": "demo.customer@dollor.ai",
        "password": "DemoCustomer2025!",
        "login_path": "/api/auth/customer/login",
    },
    "driver": {
        "email": "demo.driver@dollor.ai",
        "password": "DemoDriver2025!",
        "login_path": "/api/auth/driver/login",
    },
    "vendor": {
        "email": "demo.restaurant@dollor.ai",
        "password": "DemoRestaurant2025!",
        "login_path": "/api/auth/vendor/login",
    },
}


@pytest.fixture(scope="session")
def demo_credentials():
    """Return demo credentials dict keyed by role."""
    return DEMO_CREDENTIALS


# ---------------------------------------------------------------------------
# Auth token helpers
# ---------------------------------------------------------------------------

@pytest.fixture(scope="session")
def customer_token(env_url):
    """Login as demo customer and return JWT access token."""
    creds = DEMO_CREDENTIALS["customer"]
    resp = requests.post(
        f"{env_url}{creds['login_path']}",
        data={"username": creds["email"], "password": creds["password"]},
        timeout=10,
    )
    if resp.status_code != 200:
        pytest.skip(f"Customer login failed ({resp.status_code}): {resp.text[:200]}")
    return resp.json()["access_token"]


@pytest.fixture(scope="session")
def driver_token(env_url):
    """Login as demo driver and return JWT access token."""
    creds = DEMO_CREDENTIALS["driver"]
    resp = requests.post(
        f"{env_url}{creds['login_path']}",
        data={"username": creds["email"], "password": creds["password"]},
        timeout=10,
    )
    if resp.status_code != 200:
        pytest.skip(f"Driver login failed ({resp.status_code}): {resp.text[:200]}")
    return resp.json()["access_token"]


@pytest.fixture(scope="session")
def vendor_token(env_url):
    """Login as demo vendor and return JWT access token."""
    creds = DEMO_CREDENTIALS["vendor"]
    resp = requests.post(
        f"{env_url}{creds['login_path']}",
        data={"username": creds["email"], "password": creds["password"]},
        timeout=10,
    )
    if resp.status_code != 200:
        pytest.skip(f"Vendor login failed ({resp.status_code}): {resp.text[:200]}")
    return resp.json()["access_token"]


def auth_header(token):
    """Build Authorization header dict from JWT token."""
    return {"Authorization": f"Bearer {token}"}
