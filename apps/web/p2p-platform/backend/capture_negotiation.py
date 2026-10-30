#!/usr/bin/env python3
"""
Focused Rideshare Negotiation Screenshot Capture

Captures specifically:
1. Customer ride request with fare estimate
2. Driver viewing ride request and entering bid
3. Customer viewing driver bids
4. Customer accepting bid
"""

import asyncio
import os
from datetime import datetime
from playwright.async_api import async_playwright

# Use production site
BASE_URL = "https://www.dollor.ai"

# Credentials
CUSTOMER_EMAIL = "demo.customer@dollor.ai"
CUSTOMER_PASSWORD = os.environ["DEMO_CUSTOMER_PASSWORD"]
DRIVER_EMAIL = "demo.driver@dollor.ai"
DRIVER_PASSWORD = os.environ["DEMO_DRIVER_PASSWORD"]

TIMESTAMP = datetime.now().strftime("%Y%m%d_%H%M%S")
OUTPUT_DIR = f"screenshots/negotiation_{TIMESTAMP}"

os.makedirs(OUTPUT_DIR, exist_ok=True)

async def save(page, name, desc):
    path = f"{OUTPUT_DIR}/{name}.png"
    await page.screenshot(path=path)
    print(f"  [{name}] {desc}")
    print(f"       -> {path}")

async def main():
    print("="*60)
    print("  RIDESHARE NEGOTIATION CAPTURE")
    print(f"  Output: {OUTPUT_DIR}")
    print("="*60)

    async with async_playwright() as p:
        browser = await p.chromium.launch(headless=False)  # Use visible browser for debugging

        # Customer context with persistent state
        customer_ctx = await browser.new_context(
            viewport={"width": 1400, "height": 900},
            storage_state=None
        )
        customer = await customer_ctx.new_page()

        # Driver context
        driver_ctx = await browser.new_context(
            viewport={"width": 1400, "height": 900}
        )
        driver = await driver_ctx.new_page()

        try:
            # ========== CUSTOMER LOGIN ==========
            print("\n[1] Customer Login...")
            await customer.goto(f"{BASE_URL}/customer/login", wait_until="networkidle")
            await asyncio.sleep(1)

            # Fill login form - use placeholder selectors
            email_input = await customer.query_selector('input[placeholder*="mail"], input[placeholder*="Email"]')
            if email_input:
                await email_input.fill(CUSTOMER_EMAIL)
            await asyncio.sleep(0.5)

            pass_input = await customer.query_selector('input[placeholder*="assword"], input[placeholder*="Password"]')
            if pass_input:
                await pass_input.fill(CUSTOMER_PASSWORD)
            await asyncio.sleep(0.5)

            await customer.click('button:has-text("Continue")')
            await asyncio.sleep(3)
            await save(customer, "01_customer_logged_in", "Customer logged in")

            # ========== CUSTOMER RIDESHARE ==========
            print("\n[2] Customer opens rideshare...")
            await customer.goto(f"{BASE_URL}/customer/rideshare", wait_until="networkidle")
            await asyncio.sleep(2)
            await save(customer, "02_rideshare_form", "Rideshare booking form")

            # Enter locations
            print("\n[3] Entering ride details...")

            # Try different selectors for pickup
            pickup_selectors = [
                'input[placeholder*="ickup"]',
                'input[name="pickup"]',
                'input[id*="pickup"]',
                '#pickup',
                'input:first-of-type'
            ]
            for sel in pickup_selectors:
                try:
                    el = await customer.query_selector(sel)
                    if el:
                        await el.fill("University of Texas, Austin, TX")
                        await asyncio.sleep(1)
                        break
                except:
                    pass

            # Destination
            dest_selectors = [
                'input[placeholder*="estination"]',
                'input[placeholder*="rop"]',
                'input[name="destination"]',
                'input[id*="destination"]',
                'input[id*="dropoff"]'
            ]
            for sel in dest_selectors:
                try:
                    el = await customer.query_selector(sel)
                    if el:
                        await el.fill("Austin-Bergstrom Airport, TX")
                        await asyncio.sleep(1)
                        break
                except:
                    pass

            await save(customer, "03_locations_entered", "Pickup & destination entered")

            # Get estimate
            print("\n[4] Getting fare estimate...")
            estimate_btns = ['button:has-text("Get")', 'button:has-text("Search")', 'button:has-text("Continue")', 'button:has-text("Estimate")']
            for sel in estimate_btns:
                try:
                    btn = await customer.query_selector(sel)
                    if btn:
                        await btn.click()
                        await asyncio.sleep(3)
                        break
                except:
                    pass

            await save(customer, "04_fare_estimate", "FARE ESTIMATE - Original price shown")

            # Request ride
            print("\n[5] Requesting ride...")
            request_btns = ['button:has-text("Request")', 'button:has-text("Confirm")', 'button:has-text("Book")']
            for sel in request_btns:
                try:
                    btn = await customer.query_selector(sel)
                    if btn:
                        await btn.click()
                        await asyncio.sleep(3)
                        break
                except:
                    pass

            await save(customer, "05_waiting_for_bids", "Customer waiting for driver bids")

            # ========== DRIVER LOGIN ==========
            print("\n[6] Driver Login...")
            await driver.goto(f"{BASE_URL}/driver/login", wait_until="networkidle")
            await asyncio.sleep(1)

            # Fill driver login form
            email_input = await driver.query_selector('input[placeholder*="mail"], input[placeholder*="Email"]')
            if email_input:
                await email_input.fill(DRIVER_EMAIL)
            await asyncio.sleep(0.5)

            pass_input = await driver.query_selector('input[placeholder*="assword"], input[placeholder*="Password"]')
            if pass_input:
                await pass_input.fill(DRIVER_PASSWORD)
            await asyncio.sleep(0.5)

            # Click login button
            login_btn = await driver.query_selector('button:has-text("Sign In"), button:has-text("Continue"), button:has-text("Login")')
            if login_btn:
                await login_btn.click()

            await asyncio.sleep(3)
            await save(driver, "06_driver_logged_in", "Driver logged in")

            # ========== DRIVER RIDE BIDS ==========
            print("\n[7] Driver views ride requests...")

            # Try clicking Ride Bids in nav
            ride_bids_selectors = [
                'a:has-text("Ride Bids")',
                'a:has-text("Ride")',
                'nav a:has-text("Ride")',
                '[href*="ride"]'
            ]
            for sel in ride_bids_selectors:
                try:
                    link = await driver.query_selector(sel)
                    if link:
                        await link.click()
                        await asyncio.sleep(2)
                        break
                except:
                    pass

            await save(driver, "07_driver_ride_bids", "Driver - Ride Bids section")

            # Look for the ride request
            print("\n[8] Driver looking for ride request...")
            await driver.reload()
            await asyncio.sleep(2)
            await save(driver, "08_driver_available_requests", "Driver sees available ride requests")

            # Click on a ride request if available
            ride_cards = ['.ride-card', '.request-card', '[data-ride]', '.order-card', 'tr', '.list-item']
            for sel in ride_cards:
                try:
                    card = await driver.query_selector(sel)
                    if card:
                        await card.click()
                        await asyncio.sleep(1)
                        break
                except:
                    pass

            await save(driver, "09_driver_ride_details", "Driver views ride details")

            # Enter bid
            print("\n[9] Driver entering bid...")
            bid_inputs = ['input[type="number"]', 'input[placeholder*="bid"]', 'input[name="bid"]', 'input[placeholder*="price"]']
            for sel in bid_inputs:
                try:
                    inp = await driver.query_selector(sel)
                    if inp:
                        await inp.fill("35")
                        await asyncio.sleep(0.5)
                        break
                except:
                    pass

            await save(driver, "10_driver_entering_bid", "DRIVER NEGOTIATION - Entering $35 bid")

            # Submit bid
            submit_btns = ['button:has-text("Submit")', 'button:has-text("Bid")', 'button:has-text("Send")']
            for sel in submit_btns:
                try:
                    btn = await driver.query_selector(sel)
                    if btn:
                        await btn.click()
                        await asyncio.sleep(2)
                        break
                except:
                    pass

            await save(driver, "11_driver_bid_submitted", "Driver bid submitted")

            # ========== CUSTOMER VIEWS BIDS ==========
            print("\n[10] Customer checking for bids...")
            await asyncio.sleep(3)
            await customer.reload()
            await asyncio.sleep(3)
            await save(customer, "12_customer_sees_bids", "CUSTOMER SEES DRIVER BIDS - Compare prices")

            # Accept bid
            print("\n[11] Customer accepting bid...")
            accept_btns = ['button:has-text("Accept")', 'button:has-text("Choose")', 'button:has-text("Select")']
            for sel in accept_btns:
                try:
                    btn = await customer.query_selector(sel)
                    if btn:
                        await btn.click()
                        await asyncio.sleep(2)
                        break
                except:
                    pass

            await save(customer, "13_customer_accepts_bid", "CUSTOMER ACCEPTS BID - Driver confirmed")

            # Final state
            await asyncio.sleep(2)
            await save(customer, "14_ride_confirmed", "Ride confirmed - Driver en route")

            print("\n" + "="*60)
            print("  CAPTURE COMPLETE!")
            print(f"  Screenshots saved to: {OUTPUT_DIR}")
            print("="*60)

            # Keep browser open for 10 seconds to see results
            await asyncio.sleep(10)

        except Exception as e:
            print(f"\n[ERROR] {e}")
            import traceback
            traceback.print_exc()
            await save(customer, "error_customer", "Error state - customer")
            await save(driver, "error_driver", "Error state - driver")

        finally:
            await browser.close()

    # List files
    print("\nCaptured files:")
    for f in sorted(os.listdir(OUTPUT_DIR)):
        print(f"  - {f}")

if __name__ == "__main__":
    asyncio.run(main())
