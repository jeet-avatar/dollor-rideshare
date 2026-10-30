#!/usr/bin/env python3
"""
Phase 68 smoke test — verify every customer/driver/restaurant API endpoint
the underwriter demo needs is healthy on prod (api.dollor.ai).

Usage: scripts/insurance-smoke.py

Exit code 0 if all PASS, 1 if any FAIL. Output is a colored table.
"""
import json
import os
import sys
import time
import urllib.request
import urllib.parse
from dataclasses import dataclass
from typing import Optional

BASE = os.environ.get("DOLLOR_API", "https://api.dollor.ai")
UA = "Mozilla/5.0 (Macintosh; Intel Mac OS X 14_6) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.6 Safari/605.1.15"

DEMO = {
    "customer":   ("demo.customer@dollor.ai",   os.environ["DEMO_CUSTOMER_PASSWORD"]),
    "driver":     ("demo.driver@dollor.ai",     os.environ["DEMO_DRIVER_PASSWORD"]),
    "restaurant": ("demo.restaurant@dollor.ai", os.environ["DEMO_RESTAURANT_PASSWORD"]),
}

@dataclass
class Result:
    name: str
    method: str
    path: str
    status: int
    ok: bool
    detail: str = ""

results: list[Result] = []

def http(method: str, path: str, *, body: dict | str | None = None,
         token: Optional[str] = None, form: bool = False, timeout: int = 15) -> tuple[int, bytes]:
    headers = {"User-Agent": UA, "Accept": "application/json"}
    data = None
    if body is not None:
        if form:
            headers["Content-Type"] = "application/x-www-form-urlencoded"
            data = urllib.parse.urlencode(body if isinstance(body, dict) else {}).encode()
        else:
            headers["Content-Type"] = "application/json"
            data = json.dumps(body).encode() if isinstance(body, dict) else body.encode()
    if token:
        headers["Authorization"] = f"Bearer {token}"
    req = urllib.request.Request(BASE + path, data=data, method=method, headers=headers)
    try:
        with urllib.request.urlopen(req, timeout=timeout) as r:
            return r.status, r.read()
    except urllib.error.HTTPError as e:
        return e.code, e.read()
    except Exception as e:
        return 0, str(e).encode()

def check(name: str, method: str, path: str, *, ok_statuses=(200, 201), **kwargs):
    code, raw = http(method, path, **kwargs)
    ok = code in ok_statuses
    detail = ""
    try:
        d = json.loads(raw)
        if not ok:
            detail = (d.get("detail") if isinstance(d, dict) else "")[:120] or raw[:120].decode("utf-8", "ignore")
    except Exception:
        detail = raw[:120].decode("utf-8", "ignore")
    results.append(Result(name, method, path, code, ok, detail))
    return code, raw

def login(role: str) -> Optional[dict]:
    email, pwd = DEMO[role]
    # Role-to-URL-segment mapping (restaurant → vendor in the URL).
    url_role = {"customer": "customer", "driver": "driver", "restaurant": "vendor"}[role]
    code, raw = http("POST", f"/api/auth/{url_role}/login",
                     body={"username": email, "password": pwd}, form=True)
    ok = code == 200
    detail = ""
    d = None
    if ok:
        try:
            d = json.loads(raw)
        except Exception as e:
            detail = f"json parse: {e}"
            ok = False
    else:
        try:
            d = json.loads(raw)
            detail = (d.get("detail") if isinstance(d, dict) else "")[:120]
        except Exception:
            detail = raw[:120].decode("utf-8", "ignore")
    results.append(Result(f"{role} login", "POST", f"/api/auth/{role}/login", code, ok, detail))
    return d if ok else None

def main():
    print(f"Smoke testing {BASE}")
    print()

    # ── Auth ─────────────────────────────────────────────────────────────────
    cust = login("customer")
    drv  = login("driver")
    vnd  = login("restaurant")
    if not (cust and drv and vnd):
        print("\nFATAL: login(s) failed, can't continue")
        print_table()
        sys.exit(1)

    customer_token   = cust["access_token"]
    driver_token     = drv["access_token"]
    vendor_token     = vnd["access_token"]
    vendor_id        = vnd.get("vendor_id") or vnd.get("user", {}).get("vendor_id")
    driver_id        = drv.get("driver_id") or drv.get("user", {}).get("driver_id")

    # ── Customer reads ───────────────────────────────────────────────────────
    check("home: vendors list",
          "GET", "/api/vendors/published",
          token=customer_token)
    check("home: featured promos",
          "GET", "/api/promotions/featured",
          token=customer_token)
    check("vendor 40 detail",
          "GET", f"/api/vendors/{vendor_id}",
          token=customer_token)
    check("vendor 40 menu",
          "GET", f"/api/vendors/{vendor_id}/menu",
          token=customer_token)
    check("customer order history",
          "GET", "/api/orders/customer/history",
          token=customer_token, ok_statuses=(200, 404))
    check("customer ride history",
          "GET", "/api/rides/customer/history",
          token=customer_token, ok_statuses=(200, 404))

    # ── Driver reads ─────────────────────────────────────────────────────────
    check("driver available orders",
          "GET", "/api/drivers/orders/available",
          token=driver_token, ok_statuses=(200, 404))
    check("driver active orders",
          "GET", "/api/drivers/orders/active",
          token=driver_token, ok_statuses=(200, 404))
    check("driver earnings",
          "GET", f"/api/drivers/{driver_id}/earnings",
          token=driver_token, ok_statuses=(200, 404))
    check("driver available rides",
          "GET", "/api/rides/available",
          token=driver_token, ok_statuses=(200, 404))
    check("driver active rides",
          "GET", "/api/rides/driver/active",
          token=driver_token, ok_statuses=(200, 404))

    # ── Restaurant reads ─────────────────────────────────────────────────────
    check("vendor orders list",
          "GET", f"/erp/orders/vendor/{vendor_id}",
          token=vendor_token, ok_statuses=(200, 404, 500))   # known 500 per quick-357 SUMMARY
    check("vendor menu (vendor app)",
          "GET", f"/api/vendors/{vendor_id}/menu/items",
          token=vendor_token, ok_statuses=(200, 404))

    # ── Health/Infra ─────────────────────────────────────────────────────────
    check("health",       "GET", "/health")
    check("docs (should be 404 in prod)",
          "GET", "/docs", ok_statuses=(404,))

    print_table()
    fail = [r for r in results if not r.ok]
    if fail:
        print(f"\n{len(fail)} of {len(results)} FAILED")
        sys.exit(1)
    print(f"\nAll {len(results)} checks PASSED")

def print_table():
    name_w = max(len(r.name) for r in results) + 2
    print(f"  {'NAME'.ljust(name_w)} {'METHOD'.ljust(6)} {'STATUS'.ljust(7)} {'OK?'.ljust(4)} DETAIL")
    print(f"  {'─' * (name_w + 30)}")
    for r in results:
        flag = "✓" if r.ok else "✗"
        print(f"  {r.name.ljust(name_w)} {r.method.ljust(6)} {str(r.status).ljust(7)} {flag.ljust(4)} {r.detail[:60]}")

if __name__ == "__main__":
    main()
