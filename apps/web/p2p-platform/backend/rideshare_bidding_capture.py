#!/usr/bin/env python3
"""
Rideshare Bidding Workflow Screenshot Capture

Captures the complete driver bidding/negotiation workflow:
1. Customer creates ride request
2. Driver sees ride request and submits bid
3. Customer views driver bids
4. Customer accepts a bid
5. Driver completes trip

Usage: python rideshare_bidding_capture.py
"""

import asyncio
import os
from datetime import datetime
from playwright.async_api import async_playwright

# Configuration - Use production URL
BASE_URL = "https://www.dollor.ai"

# Demo credentials
CUSTOMER_EMAIL = "demo.customer@dollor.ai"
CUSTOMER_PASSWORD = os.environ["DEMO_CUSTOMER_PASSWORD"]
DRIVER_EMAIL = "demo.driver@dollor.ai"
DRIVER_PASSWORD = os.environ["DEMO_DRIVER_PASSWORD"]

# Output directory
TIMESTAMP = datetime.now().strftime("%Y%m%d_%H%M%S")
OUTPUT_DIR = f"screenshots/rideshare_bidding_{TIMESTAMP}"

screenshot_count = 0


async def save_screenshot(page, name: str, description: str):
    """Save screenshot with consistent naming."""
    global screenshot_count
    screenshot_count += 1
    filename = f"{screenshot_count:02d}_{name}.png"
    filepath = os.path.join(OUTPUT_DIR, filename)
    await page.screenshot(path=filepath, full_page=False)
    print(f"  [{screenshot_count:02d}] {description}")
    print(f"       Saved: {filepath}")
    return filepath


async def login(page, email, password, role="customer"):
    """Generic login helper using query_selector."""
    try:
        email_input = await page.query_selector('input[type="email"], input[name="email"], #email')
        if email_input:
            await email_input.fill(email)
            await asyncio.sleep(0.3)

        pass_input = await page.query_selector('input[type="password"], input[name="password"], #password')
        if pass_input:
            await pass_input.fill(password)
            await asyncio.sleep(0.3)

        login_btn = await page.query_selector('button[type="submit"], button:has-text("Login"), button:has-text("Sign In")')
        if login_btn:
            await login_btn.click()
            await page.wait_for_load_state("networkidle")
            await asyncio.sleep(2)
            return True
    except Exception as e:
        print(f"    Login note: {e}")
    return False


async def main():
    """Main workflow capture function."""
    global screenshot_count

    print("=" * 70)
    print("  RIDESHARE BIDDING WORKFLOW CAPTURE")
    print(f"  Output: {OUTPUT_DIR}")
    print(f"  Started: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}")
    print("=" * 70)

    # Create output directory
    os.makedirs(OUTPUT_DIR, exist_ok=True)

    async with async_playwright() as p:
        # Launch browser
        browser = await p.chromium.launch(headless=True)

        # Create two browser contexts - one for customer, one for driver
        customer_context = await browser.new_context(
            viewport={"width": 1440, "height": 900},
            device_scale_factor=2
        )
        driver_context = await browser.new_context(
            viewport={"width": 1440, "height": 900},
            device_scale_factor=2
        )

        customer_page = await customer_context.new_page()
        driver_page = await driver_context.new_page()

        try:
            # ============================================
            # PHASE 1: CUSTOMER CREATES RIDE REQUEST
            # ============================================
            print("\n" + "=" * 70)
            print("  PHASE 1: CUSTOMER CREATES RIDE REQUEST")
            print("=" * 70)

            # Customer Login
            print("\n[Customer] Navigating to login...")
            await customer_page.goto(f"{BASE_URL}/customer/login", wait_until="networkidle")
            await save_screenshot(customer_page, "customer_login", "Customer Login Page")

            print("[Customer] Logging in...")
            await login(customer_page, CUSTOMER_EMAIL, CUSTOMER_PASSWORD, "customer")
            await save_screenshot(customer_page, "customer_logged_in", "Customer Dashboard")

            # Navigate to Rideshare
            print("[Customer] Opening rideshare...")
            await customer_page.goto(f"{BASE_URL}/customer/rideshare", wait_until="networkidle")
            await asyncio.sleep(2)
            await save_screenshot(customer_page, "rideshare_home", "Rideshare - Book a Ride")

            # Enter pickup location
            print("[Customer] Entering pickup location...")
            pickup_input = await customer_page.query_selector('input[placeholder*="pickup" i], input[placeholder*="Pickup"], input[name="pickup"], input[id*="pickup"]')
            if pickup_input:
                await pickup_input.fill("30012 Crown Valley Pkwy, Laguna Niguel, CA 92677")
                await asyncio.sleep(1)
                # Try clicking suggestion
                suggestion = await customer_page.query_selector('.autocomplete-suggestion, [role="option"], .suggestion-item, .pac-item')
                if suggestion:
                    await suggestion.click()
                await asyncio.sleep(1)
            await save_screenshot(customer_page, "pickup_entered", "Pickup Location - Laguna Niguel")

            # Enter destination
            print("[Customer] Entering destination...")
            dest_input = await customer_page.query_selector('input[placeholder*="destination" i], input[placeholder*="drop" i], input[name="destination"], input[id*="destination"], input[id*="dropoff"]')
            if dest_input:
                await dest_input.fill("22352 El Paseo, Rancho Santa Margarita, CA 92688")
                await asyncio.sleep(1)
                suggestion = await customer_page.query_selector('.autocomplete-suggestion, [role="option"], .suggestion-item, .pac-item')
                if suggestion:
                    await suggestion.click()
                await asyncio.sleep(1)
            await save_screenshot(customer_page, "destination_entered", "Destination - Rancho Santa Margarita")

            # Get price estimate
            print("[Customer] Getting price estimate...")
            estimate_btn = await customer_page.query_selector('button:has-text("Get Price"), button:has-text("Get Estimate"), button:has-text("Search"), button:has-text("Continue")')
            if estimate_btn:
                await estimate_btn.click()
                await customer_page.wait_for_load_state("networkidle")
                await asyncio.sleep(2)
            await save_screenshot(customer_page, "fare_estimate", "Fare Estimate - Price Breakdown with $2 Platform Fee")

            # Submit ride request
            print("[Customer] Submitting ride request...")
            confirm_btn = await customer_page.query_selector('button:has-text("Confirm"), button:has-text("Request Ride"), button:has-text("Request"), button:has-text("Book")')
            if confirm_btn:
                await confirm_btn.click()
                await customer_page.wait_for_load_state("networkidle")
                await asyncio.sleep(3)
            await save_screenshot(customer_page, "ride_requested", "Ride Requested - Waiting for Driver Bids")

            # Wait for request to propagate
            print("\n[Waiting 5s for ride request to propagate to drivers...]")
            await asyncio.sleep(5)

            # ============================================
            # PHASE 2: DRIVER VIEWS AND SUBMITS BID
            # ============================================
            print("\n" + "=" * 70)
            print("  PHASE 2: DRIVER VIEWS AND SUBMITS BID")
            print("=" * 70)

            # Driver Login
            print("\n[Driver] Navigating to login...")
            await driver_page.goto(f"{BASE_URL}/driver/login", wait_until="networkidle")
            await save_screenshot(driver_page, "driver_login", "Driver Login Page")

            print("[Driver] Logging in...")
            await login(driver_page, DRIVER_EMAIL, DRIVER_PASSWORD, "driver")
            await save_screenshot(driver_page, "driver_dashboard", "Driver Dashboard - Online & Ready")

            # Navigate to Ride Bids
            print("[Driver] Viewing ride requests...")
            await driver_page.goto(f"{BASE_URL}/driver/rideshare", wait_until="networkidle")
            await asyncio.sleep(2)
            await save_screenshot(driver_page, "driver_ride_requests", "Driver - Ride Requests Section")

            # Click on Ride Bids tab/link
            ride_bids_link = await driver_page.query_selector('a:has-text("Ride Bids"), button:has-text("Ride Bids"), [href*="ride-bids"], nav a:has-text("Ride")')
            if ride_bids_link:
                await ride_bids_link.click()
                await asyncio.sleep(2)
            await save_screenshot(driver_page, "driver_available_rides", "Driver - Available Ride Requests to Bid")

            # Click on Available tab if exists
            available_tab = await driver_page.query_selector('button:has-text("Available"), [role="tab"]:has-text("Available")')
            if available_tab:
                await available_tab.click()
                await asyncio.sleep(2)
                await save_screenshot(driver_page, "driver_available_tab", "Driver - Available Rides Tab")

            # Look for a ride request to bid on
            print("[Driver] Looking for ride request...")
            ride_card = await driver_page.query_selector('.ride-request, .ride-card, [data-ride], .request-card, .order-card')
            if ride_card:
                await ride_card.click()
                await asyncio.sleep(1)
                await save_screenshot(driver_page, "driver_ride_details", "Driver - Ride Request Details")

            # Enter bid amount
            print("[Driver] Entering bid...")
            bid_input = await driver_page.query_selector('input[placeholder*="bid" i], input[name="bid"], input[type="number"], input[placeholder*="price" i], input[placeholder*="offer" i]')
            if bid_input:
                await bid_input.fill("28")
                await asyncio.sleep(0.5)
                await save_screenshot(driver_page, "driver_entering_bid", "Driver - Entering Bid Amount ($28)")

            # Submit bid
            print("[Driver] Submitting bid...")
            submit_btn = await driver_page.query_selector('button:has-text("Submit"), button:has-text("Place Bid"), button:has-text("Send"), button:has-text("Bid")')
            if submit_btn:
                await submit_btn.click()
                await driver_page.wait_for_load_state("networkidle")
                await asyncio.sleep(2)
            await save_screenshot(driver_page, "driver_bid_submitted", "Driver - Bid Submitted ($28 offer)")

            # View My Bids
            my_bids_tab = await driver_page.query_selector('button:has-text("My Bids"), [role="tab"]:has-text("My Bids")')
            if my_bids_tab:
                await my_bids_tab.click()
                await asyncio.sleep(2)
                await save_screenshot(driver_page, "driver_my_bids", "Driver - My Pending Bids")

            # Wait for bid to propagate
            print("\n[Waiting 3s for bid to propagate to customer...]")
            await asyncio.sleep(3)

            # ============================================
            # PHASE 3: CUSTOMER VIEWS AND ACCEPTS BID
            # ============================================
            print("\n" + "=" * 70)
            print("  PHASE 3: CUSTOMER VIEWS AND ACCEPTS BID")
            print("=" * 70)

            # Refresh customer page to see bids
            print("\n[Customer] Checking for driver bids...")
            await customer_page.reload()
            await customer_page.wait_for_load_state("networkidle")
            await asyncio.sleep(3)
            await save_screenshot(customer_page, "customer_viewing_bids", "Customer - Viewing Incoming Driver Bids")

            # Look for bids list
            bids_container = await customer_page.query_selector('.bids-list, .driver-bids, [data-bids], .incoming-bids')
            if bids_container:
                await save_screenshot(customer_page, "customer_bids_list", "Customer - Compare Driver Offers")

            # Accept a bid
            print("[Customer] Accepting driver bid...")
            accept_btn = await customer_page.query_selector('button:has-text("Accept"), button:has-text("Choose"), button:has-text("Select"), button:has-text("Book")')
            if accept_btn:
                await accept_btn.click()
                await customer_page.wait_for_load_state("networkidle")
                await asyncio.sleep(2)
            await save_screenshot(customer_page, "customer_bid_accepted", "Customer - Bid Accepted! Driver Confirmed")

            # View ride tracking
            await asyncio.sleep(2)
            await save_screenshot(customer_page, "customer_tracking", "Customer - Driver En Route to Pickup")

            # Wait for acceptance to propagate
            print("\n[Waiting 3s for acceptance to propagate to driver...]")
            await asyncio.sleep(3)

            # ============================================
            # PHASE 4: DRIVER COMPLETES TRIP
            # ============================================
            print("\n" + "=" * 70)
            print("  PHASE 4: DRIVER COMPLETES TRIP")
            print("=" * 70)

            # Refresh driver page
            print("\n[Driver] Checking accepted ride...")
            await driver_page.reload()
            await driver_page.wait_for_load_state("networkidle")
            await asyncio.sleep(2)

            # Navigate to Active rides
            active_link = await driver_page.query_selector('a:has-text("Active"), button:has-text("Active"), nav a:has-text("Active")')
            if active_link:
                await active_link.click()
                await asyncio.sleep(2)
            await save_screenshot(driver_page, "driver_ride_accepted", "Driver - Ride Accepted, Navigate to Pickup")

            # Arrive at pickup
            print("[Driver] Arriving at pickup...")
            arrived_btn = await driver_page.query_selector('button:has-text("Arrived"), button:has-text("At Pickup"), button:has-text("I\'m Here")')
            if arrived_btn:
                await arrived_btn.click()
                await asyncio.sleep(2)
            await save_screenshot(driver_page, "driver_at_pickup", "Driver - Arrived at Pickup Location")

            # Start trip
            print("[Driver] Starting trip...")
            start_btn = await driver_page.query_selector('button:has-text("Start"), button:has-text("Begin"), button:has-text("Pick Up")')
            if start_btn:
                await start_btn.click()
                await asyncio.sleep(2)
            await save_screenshot(driver_page, "driver_trip_started", "Driver - Trip in Progress")

            # Complete trip
            print("[Driver] Completing trip...")
            complete_btn = await driver_page.query_selector('button:has-text("Complete"), button:has-text("End"), button:has-text("Drop Off"), button:has-text("Finish")')
            if complete_btn:
                await complete_btn.click()
                await asyncio.sleep(2)
            await save_screenshot(driver_page, "driver_trip_completed", "Driver - Trip Completed!")

            # View earnings
            print("[Driver] Viewing earnings...")
            await driver_page.goto(f"{BASE_URL}/driver/earnings", wait_until="networkidle")
            await asyncio.sleep(2)
            await save_screenshot(driver_page, "driver_earnings", "Driver - Earnings: $27 (Fare minus $1 platform fee)")

            # Final customer view
            print("\n[Customer] Final ride status...")
            await customer_page.reload()
            await asyncio.sleep(2)
            await save_screenshot(customer_page, "customer_ride_complete", "Customer - Ride Complete, Rate Your Driver")

        except Exception as e:
            print(f"\n[ERROR] {str(e)}")
            import traceback
            traceback.print_exc()
            # Save error state screenshots
            await customer_page.screenshot(path=os.path.join(OUTPUT_DIR, "error_customer.png"))
            await driver_page.screenshot(path=os.path.join(OUTPUT_DIR, "error_driver.png"))

        finally:
            await customer_context.close()
            await driver_context.close()
            await browser.close()

    # Summary
    print("\n" + "=" * 70)
    print("  WORKFLOW CAPTURE COMPLETE")
    print(f"  Total Screenshots: {screenshot_count}")
    print(f"  Output Directory: {OUTPUT_DIR}")
    print("=" * 70)

    # List captured files
    print("\nCaptured Screenshots:")
    for f in sorted(os.listdir(OUTPUT_DIR)):
        if f.endswith('.png'):
            print(f"  - {f}")


if __name__ == "__main__":
    asyncio.run(main())
