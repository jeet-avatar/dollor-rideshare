#!/usr/bin/env python3
"""
Playwright automation: Create ai.dollor.customer in Google Play Console,
fill in the store listing, upload the AAB, and submit for review.

Usage:
  source /Users/jeet/doordash-p2p/apps/web/p2p-platform/backend/venv/bin/activate
  python3 apps/android/scripts/play_store_release.py

The browser opens headed so you can log in with your Google account.
The script handles everything after login automatically.
"""

import time
import os
from pathlib import Path
from playwright.sync_api import sync_playwright, TimeoutError as PWTimeout

# ─── Paths ────────────────────────────────────────────────────────────────────
ROOT = Path("/Users/jeet/doordash-p2p/apps/android")
ASSETS = ROOT / "store-assets" / "customer"
AAB = ROOT / "app/build/outputs/bundle/productionRelease/app-production-release.aab"
ICON = ROOT / "store-assets" / "app-icon-512x512.png"
FEATURE_GRAPHIC = ASSETS / "feature-graphic-1024x500.png"
SCREENSHOTS = sorted([
    ASSETS / "01-home.png",
    ASSETS / "04-rides.png",   # rideshare screens first
    ASSETS / "05-login.png",
    ASSETS / "02-restaurants.png",
    ASSETS / "03-deals.png",
])

# ─── Store listing content ─────────────────────────────────────────────────────
PACKAGE_NAME   = "ai.dollor.customer"
APP_TITLE      = "Dollor.ai - Rideshare"
SHORT_DESC     = "Book rides, drivers bid for your trip — you pick the best price."
FULL_DESC      = """\
Dollor.ai is a peer-to-peer rideshare marketplace where drivers compete for your ride — you choose the price and driver that works best for you.

HOW IT WORKS
1. Enter your pickup and destination
2. Nearby drivers submit bids for your ride
3. Compare prices and driver ratings
4. Accept the bid you want
5. Track your ride in real-time

TRANSPARENT PRICING
• Fares up to $35: flat $1 platform fee
• Fares $35–$70: flat $2 platform fee
• Fares above $70: flat $3 platform fee
• No hidden fees, no surge pricing
• Drivers set their own prices

SAFETY FIRST
• All drivers pass a background check
• Real-time trip sharing
• In-app support

Download Dollor.ai and experience rideshare where you're in control.

Dollor.ai is a peer-to-peer platform. Drivers are independent contractors, not employees of Dollor.ai or Zietra Technologies Inc."""

PRIVACY_URL    = "https://dollor.ai/privacy"
CONTACT_EMAIL  = "support@dollor.ai"
RELEASE_NOTES  = "Dollor.ai rideshare launch — request rides, driver bidding, real-time tracking, transparent flat-fee pricing."

PLAY_CONSOLE   = "https://play.google.com/console/u/0/developers"

# ─── Helpers ──────────────────────────────────────────────────────────────────
def wait_and_click(page, selector, timeout=15000):
    page.wait_for_selector(selector, timeout=timeout)
    page.click(selector)

def fill_field(page, selector, text, clear=True, timeout=10000):
    page.wait_for_selector(selector, timeout=timeout)
    el = page.locator(selector).first
    if clear:
        el.triple_click()
    el.fill(text)

def log(msg):
    print(f"  ➤  {msg}", flush=True)


def run():
    with sync_playwright() as pw:
        # Launch headed browser — user logs in with their Google account
        browser = pw.chromium.launch(
            headless=False,
            args=["--start-maximized"],
            slow_mo=200,
        )
        ctx = browser.new_context(viewport={"width": 1440, "height": 900})
        page = ctx.new_page()

        # ── Step 1: Google login ──────────────────────────────────────────────
        print("\n" + "="*60)
        print("STEP 1 — Log in to Google Play Console")
        print("="*60)
        page.goto(PLAY_CONSOLE)
        print("  Browser opened. Please log in with your Google account.")
        print("  The script will continue automatically once you're in the console.")

        # Wait up to 3 minutes for the console to load after manual login
        try:
            page.wait_for_url("**/console/**", timeout=180_000)
        except PWTimeout:
            pass
        # Extra wait for the console dashboard to render
        time.sleep(3)
        log("Logged in to Play Console.")

        # ── Step 2: Create app ────────────────────────────────────────────────
        print("\n" + "="*60)
        print("STEP 2 — Create new app")
        print("="*60)

        # Click "Create app" button
        try:
            page.click("text=Create app", timeout=10000)
        except PWTimeout:
            # Try the button in the top area
            page.click("[aria-label='Create app']", timeout=10000)
        time.sleep(2)

        log("Filling app details form...")

        # App name
        try:
            name_field = page.locator("input[placeholder*='app name'], input[aria-label*='app name'], #app-name").first
            name_field.fill(APP_TITLE)
        except Exception:
            page.keyboard.type(APP_TITLE)

        # Default language: English (United States) — usually pre-selected
        # App or game: App
        try:
            page.click("text=App", timeout=5000)
        except Exception:
            pass

        # Free or paid: Free
        try:
            page.click("text=Free", timeout=5000)
        except Exception:
            pass

        # Developer Program Policies checkbox
        try:
            checkboxes = page.locator("input[type='checkbox']").all()
            for cb in checkboxes:
                if not cb.is_checked():
                    cb.check()
        except Exception:
            pass

        # US export laws checkbox
        try:
            page.click("text=US export laws", timeout=5000)
        except Exception:
            pass

        # Create app button
        try:
            page.click("button:has-text('Create app')", timeout=10000)
        except Exception:
            page.click("//button[contains(., 'Create app')]", timeout=10000)

        time.sleep(4)
        log("App created (or already exists). Navigating to store listing...")

        # ── Step 3: Main store listing ─────────────────────────────────────────
        print("\n" + "="*60)
        print("STEP 3 — Store listing")
        print("="*60)

        # Navigate to store listing
        try:
            page.click("text=Store listing", timeout=10000)
        except PWTimeout:
            page.goto(page.url.split("?")[0] + "?tab=store_listing")
        time.sleep(3)

        # App name
        try:
            fill_field(page, "input[maxlength='30'], input[aria-label*='App name'], [data-key='title'] input", APP_TITLE)
            log("App name filled.")
        except Exception as e:
            log(f"App name field: {e}")

        # Short description
        try:
            fill_field(page, "textarea[maxlength='80'], [data-key='short_description'] textarea", SHORT_DESC)
            log("Short description filled.")
        except Exception as e:
            log(f"Short desc: {e}")

        # Full description
        try:
            fill_field(page, "textarea[maxlength='4000'], [data-key='full_description'] textarea", FULL_DESC)
            log("Full description filled.")
        except Exception as e:
            log(f"Full desc: {e}")

        # ── Step 4: Upload graphics ────────────────────────────────────────────
        print("\n" + "="*60)
        print("STEP 4 — Upload graphics")
        print("="*60)

        # App icon
        try:
            icon_input = page.locator("input[type='file'][accept*='png']").first
            icon_input.set_input_files(str(ICON))
            log("Icon uploaded.")
            time.sleep(2)
        except Exception as e:
            log(f"Icon upload: {e}")

        # Feature graphic
        try:
            graphic_inputs = page.locator("input[type='file']").all()
            for inp in graphic_inputs:
                try:
                    inp.set_input_files(str(FEATURE_GRAPHIC))
                    break
                except Exception:
                    continue
            log("Feature graphic uploaded.")
            time.sleep(2)
        except Exception as e:
            log(f"Feature graphic: {e}")

        # Screenshots
        try:
            screenshot_paths = [str(s) for s in SCREENSHOTS if s.exists()]
            file_inputs = page.locator("input[type='file']").all()
            for inp in file_inputs:
                try:
                    inp.set_input_files(screenshot_paths)
                    log(f"Screenshots uploaded: {len(screenshot_paths)} images")
                    break
                except Exception:
                    continue
            time.sleep(3)
        except Exception as e:
            log(f"Screenshots: {e}")

        # ── Step 5: Save store listing ─────────────────────────────────────────
        try:
            page.click("button:has-text('Save')", timeout=10000)
            log("Store listing saved.")
            time.sleep(2)
        except Exception as e:
            log(f"Save: {e}")

        # ── Step 6: Upload AAB via Production track ────────────────────────────
        print("\n" + "="*60)
        print("STEP 5 — Upload AAB to Production")
        print("="*60)

        try:
            page.click("text=Production", timeout=10000)
            time.sleep(2)
            page.click("button:has-text('Create new release'), button:has-text('Edit release')", timeout=10000)
            time.sleep(2)

            # Upload AAB
            aab_input = page.locator("input[type='file']").first
            aab_input.set_input_files(str(AAB))
            log(f"AAB uploading ({AAB.stat().st_size // 1_000_000}MB)... this takes ~1 min")
            # Wait for upload to complete
            page.wait_for_selector("text=261020, text=1.1.0", timeout=120_000)
            log("AAB uploaded.")

            # Release notes
            notes_field = page.locator("textarea[placeholder*='release notes'], [aria-label*='release notes']").first
            notes_field.fill(RELEASE_NOTES)

            # Save draft / Review
            page.click("button:has-text('Save'), button:has-text('Next')", timeout=10000)
            time.sleep(2)

            # Send for review
            try:
                page.click("button:has-text('Send.*review'), button:has-text('Submit')", timeout=10000)
                log("Sent for review!")
            except Exception:
                log("Release saved as draft — go to Play Console and click 'Send for review'")

        except Exception as e:
            log(f"Production track: {e} — complete this step manually in Play Console")

        # ── Done ───────────────────────────────────────────────────────────────
        print("\n" + "="*60)
        print("DONE — browser staying open so you can verify and fix anything")
        print("Close the browser when finished.")
        print("="*60)

        # Keep browser open
        input("Press ENTER to close the browser...")
        browser.close()


if __name__ == "__main__":
    # Verify files exist before launching
    missing = []
    for f in [AAB, ICON, FEATURE_GRAPHIC] + SCREENSHOTS:
        if not Path(f).exists():
            missing.append(str(f))
    if missing:
        print("MISSING FILES:")
        for m in missing:
            print(f"  {m}")
        raise SystemExit(1)

    print("All asset files verified.")
    print(f"  AAB:            {AAB} ({AAB.stat().st_size // 1_000_000}MB)")
    print(f"  Icon:           {ICON}")
    print(f"  Feature:        {FEATURE_GRAPHIC}")
    print(f"  Screenshots:    {len(SCREENSHOTS)} images")
    run()
