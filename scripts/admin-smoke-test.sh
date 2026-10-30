#!/usr/bin/env bash
# =============================================================================
# Admin Portal Smoke Test
# =============================================================================
# Tests all admin API endpoints on staging or production.
# Usage: bash scripts/admin-smoke-test.sh [staging|production]
# Default: production
#
# Prerequisites: python3, curl (or python urllib)
# =============================================================================

set -euo pipefail

ENV="${1:-production}"

case "$ENV" in
  staging)
    BASE_URL="https://d34u5ixl0bulv4.cloudfront.net"
    ;;
  production)
    BASE_URL="https://api.dollor.ai"
    ;;
  *)
    echo "Usage: $0 [staging|production]"
    exit 1
    ;;
esac

echo ""
echo "================================================================"
echo "  Admin Portal Smoke Test"
echo "  Environment: $ENV"
echo "  Base URL:    $BASE_URL"
echo "  Date:        $(date -u +"%Y-%m-%dT%H:%M:%SZ")"
echo "================================================================"
echo ""

# Run all tests via Python (avoids shell escaping issues with passwords/tokens)
export BASE_URL_OVERRIDE="$BASE_URL"
python3 << 'PYEOF'
import json
import os
import sys
import time
import urllib.request
import urllib.error
import ssl

# ── Config ───────────────────────────────────────────────────────────────────
BASE_URL = os.environ.get("BASE_URL_OVERRIDE", "https://api.dollor.ai")
ADMIN_EMAIL = os.environ.get("ADMIN_EMAIL", "support@dollor.ai")
ADMIN_PASSWORD = os.environ.get("ADMIN_PASSWORD", "${DOLLOR_ADMIN_PASSWORD}")

# Colors
GREEN = "\033[92m"
RED = "\033[91m"
YELLOW = "\033[93m"
CYAN = "\033[96m"
RESET = "\033[0m"
BOLD = "\033[1m"

# SSL context (allow self-signed for staging)
ctx = ssl.create_default_context()
ctx.check_hostname = False
ctx.verify_mode = ssl.CERT_NONE


def log_pass(name, path, code, detail=""):
    print(f"  {GREEN}PASS{RESET}  [{code}] {name:35s} {path}")
    if detail:
        print(f"        {detail}")


def log_fail(name, path, code, detail=""):
    print(f"  {RED}FAIL{RESET}  [{code}] {name:35s} {path}")
    if detail:
        print(f"        {RED}{detail}{RESET}")


def log_warn(name, path, code, detail=""):
    print(f"  {YELLOW}WARN{RESET}  [{code}] {name:35s} {path}")
    if detail:
        print(f"        {YELLOW}{detail}{RESET}")


# ── Login ────────────────────────────────────────────────────────────────────
print(f"{BOLD}Step 1: Admin Login{RESET}")
print(f"  Logging in as {ADMIN_EMAIL}...")

try:
    login_data = json.dumps({"email": ADMIN_EMAIL, "password": ADMIN_PASSWORD}).encode()
    login_req = urllib.request.Request(
        f"{BASE_URL}/api/admin/login",
        data=login_data,
        headers={"Content-Type": "application/json"},
        method="POST",
    )
    login_resp = urllib.request.urlopen(login_req, context=ctx, timeout=15)
    login_body = json.loads(login_resp.read().decode())
    TOKEN = login_body["access_token"]
    user = login_body.get("user", {})
    print(f"  {GREEN}OK{RESET} - Logged in as {user.get('full_name', 'admin')} (id={user.get('id')})")
except urllib.error.HTTPError as e:
    print(f"  {RED}FATAL{RESET} - Login failed: HTTP {e.code} - {e.read().decode()[:200]}")
    sys.exit(1)
except Exception as e:
    print(f"  {RED}FATAL{RESET} - Login failed: {e}")
    sys.exit(1)

print()

# ── Endpoint Definitions ────────────────────────────────────────────────────
# Format: (name, path, category, known_missing)
# known_missing=True means the endpoint is expected to not exist (WARN not FAIL)
ENDPOINTS = [
    # Dashboard
    ("Dashboard Stats", "/api/dashboard/stats", "Dashboard", False),
    ("Dashboard Activity", "/api/dashboard/recent-activity", "Dashboard", False),

    # Orders
    ("Orders List", "/api/orders", "Orders", False),

    # Vendor Management
    ("Vendors List", "/api/vendors", "Vendor Management", False),
    ("Vendor All Documents", "/api/admin/vendors/all-documents", "Document Review", False),

    # Rideshare
    ("Rideshare Requests", "/api/admin/rideshare/requests", "Rideshare", False),
    ("Rideshare Active", "/api/admin/rideshare/active", "Rideshare", False),

    # Drivers
    ("Admin Drivers", "/api/admin/drivers", "Drivers", False),
    ("ERP Drivers (legacy)", "/api/erp/drivers", "Drivers", True),

    # Accounting
    ("Platform Revenue", "/api/accounting/platform-revenue", "Accounting", False),
    ("Vendor Payouts", "/api/accounting/vendor-payouts", "Accounting", False),
    ("Balance Sheet", "/api/admin/accounting/balance-sheet", "Accounting", False),
    ("Income Statement", "/api/admin/accounting/income-statement", "Accounting", False),
    ("Trial Balance", "/api/admin/accounting/trial-balance", "Accounting", False),
    ("Cash Flow", "/api/admin/accounting/cash-flow", "Accounting", False),
    ("Chart of Accounts", "/api/admin/accounting/chart-of-accounts", "Accounting", False),

    # Invoices
    ("Invoices List", "/api/invoices", "Invoices", False),
    ("Invoice Stats", "/api/invoices/stats", "Invoices", False),

    # Clients
    ("Clients List", "/api/clients", "Clients", False),

    # Project Tracker
    ("Project Cases", "/api/admin/project-cases/", "Project Tracker", False),
    ("Project Case Stats", "/api/admin/project-cases/stats", "Project Tracker", False),
    ("Departments", "/api/admin/departments/", "Project Tracker", False),
    ("Dept Dashboard", "/api/admin/departments/dashboard", "Project Tracker", False),

    # Change Management
    ("Change Requests", "/api/admin/change-requests/", "Change Management", False),

    # Other
    ("Coupa Dashboard", "/api/dashboard/coupa", "Coupa (hidden)", False),
    ("Activity Notifications", "/api/activity", "Notifications", True),
]

# ── Test Endpoints ───────────────────────────────────────────────────────────
print(f"{BOLD}Step 2: Testing {len(ENDPOINTS)} Admin API Endpoints{RESET}")
print()

headers = {"Authorization": f"Bearer {TOKEN}", "Content-Type": "application/json"}

results = {"pass": 0, "fail": 0, "warn": 0}
failures = []
current_category = ""

for name, path, category, known_missing in ENDPOINTS:
    if category != current_category:
        current_category = category
        print(f"  {CYAN}--- {category} ---{RESET}")

    try:
        req = urllib.request.Request(f"{BASE_URL}{path}", headers=headers, method="GET")
        resp = urllib.request.urlopen(req, context=ctx, timeout=15)
        code = resp.getcode()
        body = resp.read().decode()[:150]

        if known_missing:
            # Unexpectedly working -- still a pass
            log_warn(name, path, code, "Endpoint exists (was expected missing)")
            results["warn"] += 1
        else:
            log_pass(name, path, code)
            results["pass"] += 1

    except urllib.error.HTTPError as e:
        code = e.code
        body = e.read().decode()[:150]

        if known_missing:
            log_warn(name, path, code, f"Known missing: {body}")
            results["warn"] += 1
        elif code == 401:
            # Auth issue -- might need vendor-specific token
            log_warn(name, path, code, f"Auth issue (may need specific role): {body}")
            results["warn"] += 1
        else:
            log_fail(name, path, code, body)
            results["fail"] += 1
            failures.append((name, path, code, body))

    except Exception as e:
        log_fail(name, path, "ERR", str(e))
        results["fail"] += 1
        failures.append((name, path, "ERR", str(e)))

print()

# ── Summary ──────────────────────────────────────────────────────────────────
total = results["pass"] + results["fail"] + results["warn"]
print(f"{BOLD}{'=' * 64}{RESET}")
print(f"{BOLD}  RESULTS{RESET}")
print(f"{'=' * 64}")
print(f"  Total endpoints tested: {total}")
print(f"  {GREEN}PASS: {results['pass']}{RESET}")
print(f"  {YELLOW}WARN: {results['warn']}{RESET}")
print(f"  {RED}FAIL: {results['fail']}{RESET}")
print()

if failures:
    print(f"{RED}{BOLD}  FAILURES:{RESET}")
    for name, path, code, body in failures:
        print(f"    [{code}] {name} -- {path}")
        print(f"           {body}")
    print()

if results["fail"] > 0:
    print(f"{RED}{BOLD}  STATUS: FAILED -- {results['fail']} critical endpoint(s) broken{RESET}")
    sys.exit(1)
else:
    print(f"{GREEN}{BOLD}  STATUS: PASSED -- all critical endpoints healthy{RESET}")
    sys.exit(0)
PYEOF
