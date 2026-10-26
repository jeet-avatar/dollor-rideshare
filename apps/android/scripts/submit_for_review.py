#!/usr/bin/env python3
"""
Playwright: Submit both Dollor apps for Google Play review.
Opens Play Console, navigates to Production track for each app,
clicks Review release → Send for review.

Run:
  source /Users/jeet/doordash-p2p/apps/web/p2p-platform/backend/venv/bin/activate
  python3 apps/android/scripts/submit_for_review.py
"""

import time
from playwright.sync_api import sync_playwright, TimeoutError as PWTimeout

APPS = [
    {
        "package": "ai.dollor.customer",
        "label": "Dollor.ai (Customer / Rideshare)",
    },
    {
        "package": "ai.dollor.driver",
        "label": "Dollor Driver",
    },
]

CONSOLE_HOME = "https://play.google.com/console/u/0/developers"


def log(msg):
    print(f"  ➤  {msg}", flush=True)


def wait_click(page, selectors, timeout=15000):
    """Try multiple selectors, click first that appears."""
    if isinstance(selectors, str):
        selectors = [selectors]
    for sel in selectors:
        try:
            page.wait_for_selector(sel, timeout=timeout)
            page.click(sel)
            return True
        except PWTimeout:
            continue
    return False


def submit_app(page, app):
    package = app["package"]
    label = app["label"]
    print(f"\n{'='*60}")
    print(f"  {label}  ({package})")
    print(f"{'='*60}")

    # Navigate to app in Play Console
    # Search for the app or use the app list
    log("Looking for app in console...")
    try:
        # Click the app by package name link or title
        page.click(f"text={package}", timeout=8000)
    except PWTimeout:
        try:
            page.click(f"text={label.split(' (')[0]}", timeout=8000)
        except PWTimeout:
            log(f"Could not find '{label}' in app list — navigate manually, then press ENTER")
            input("  Press ENTER once you're on the app dashboard: ")

    time.sleep(2)

    # Navigate to Production track
    log("Navigating to Production track...")
    try:
        page.click("text=Production", timeout=10000)
    except PWTimeout:
        try:
            page.click("a[href*='tracks/production'], a[href*='production']", timeout=8000)
        except PWTimeout:
            log("Navigate to Production manually, then press ENTER")
            input("  Press ENTER once you're on the Production track page: ")

    time.sleep(2)

    # Click "Review release" or "Edit release"
    log("Looking for Review release button...")
    clicked = wait_click(page, [
        "button:has-text('Review release')",
        "button:has-text('Review')",
        "a:has-text('Review release')",
        "[aria-label*='Review release']",
    ], timeout=10000)

    if not clicked:
        log("Review button not found — click it manually, then press ENTER")
        input("  Press ENTER after clicking Review release: ")

    time.sleep(3)

    # Handle any "Start rollout" or warning dialogs
    try:
        page.click("button:has-text('Confirm')", timeout=4000)
        time.sleep(1)
    except PWTimeout:
        pass

    # Click "Send for review" / "Submit" / "Start rollout to production"
    log("Clicking Send for review...")
    sent = wait_click(page, [
        "button:has-text('Send for review')",
        "button:has-text('Send 1 app to review')",
        "button:has-text('Submit')",
        "button:has-text('Start rollout to Production')",
        "[aria-label*='Send for review']",
    ], timeout=12000)

    if not sent:
        log("Send for review button not found — click it manually, then press ENTER")
        input("  Press ENTER after clicking Send for review: ")
    else:
        time.sleep(2)
        # Confirm any dialog
        try:
            page.click("button:has-text('Send'), button:has-text('Confirm')", timeout=5000)
        except PWTimeout:
            pass
        log(f"✓  {label} submitted for review!")

    time.sleep(3)

    # Go back to console home for next app
    page.goto(CONSOLE_HOME)
    time.sleep(3)


CHROME_PROFILE = "/Users/jeet/Library/Application Support/Google/Chrome"


def run():
    with sync_playwright() as pw:
        # Use existing Chrome profile — no login needed, cookies already saved
        ctx = pw.chromium.launch_persistent_context(
            user_data_dir=CHROME_PROFILE,
            headless=False,
            channel="chrome",          # use installed Google Chrome
            args=["--start-maximized"],
            slow_mo=300,
        )
        page = ctx.new_page()

        # ── Navigate straight to Play Console ─────────────────────────────────
        print("\n" + "="*60)
        print("  OPENING PLAY CONSOLE IN YOUR EXISTING CHROME SESSION")
        print("="*60)
        page.goto(CONSOLE_HOME)

        try:
            page.wait_for_url("**/console/**", timeout=30_000)
        except PWTimeout:
            log("Waiting for Play Console to load...")
            page.wait_for_load_state("networkidle", timeout=30_000)
        time.sleep(3)
        log("In Play Console.")

        # ── Submit each app ───────────────────────────────────────────────────
        for app in APPS:
            submit_app(page, app)

        # ── Done ──────────────────────────────────────────────────────────────
        print("\n" + "="*60)
        print("  DONE — both apps submitted for Google Play review")
        print("  You will receive an email when each is approved (1–3 days).")
        print("="*60)
        input("\nPress ENTER to close the browser...")
        ctx.close()


if __name__ == "__main__":
    run()
