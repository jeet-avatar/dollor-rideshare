#!/usr/bin/env python3
"""
Dollor.ai Rideshare UI Test Agent
Playwright-based testing for rideshare web interface

Tests:
1. Customer ride booking flow via UI
2. Driver ride bidding via UI
3. Chat interface
4. Ride tracking
"""

import sys
import time
import os
from datetime import datetime
from typing import Optional
from dataclasses import dataclass
from playwright.sync_api import sync_playwright, Page, Browser, TimeoutError as PlaywrightTimeout

# Configuration
BASE_URL = "https://www.dollor.ai"
API_URL = "https://api.dollor.ai"

# Demo credentials
CUSTOMER_EMAIL = "demo.customer@dollor.ai"
CUSTOMER_PASSWORD = os.environ["DEMO_CUSTOMER_PASSWORD"]
DRIVER_EMAIL = "demo.driver@dollor.ai"
DRIVER_PASSWORD = os.environ["DEMO_DRIVER_PASSWORD"]

# Real addresses in 92688 area
PICKUP_ADDRESS = "30012 Crown Valley Pkwy, Laguna Niguel, CA 92677"
DROPOFF_ADDRESS = "22352 El Paseo, Rancho Santa Margarita, CA 92688"


@dataclass
class TestResult:
    """Test step result"""
    success: bool
    message: str


class RideshareUIAgent:
    """UI test agent for rideshare booking flow"""

    def __init__(self, base_url: str = BASE_URL, headless: bool = False, slow_mo: int = 500):
        self.base_url = base_url
        self.headless = headless
        self.slow_mo = slow_mo
        self.playwright = None
        self.browser: Optional[Browser] = None
        self.page: Optional[Page] = None
        self.session_id = datetime.now().strftime("%Y%m%d_%H%M%S")
        self.screenshot_dir = "screenshots/rideshare"

        # Ensure screenshot directory exists
        os.makedirs(self.screenshot_dir, exist_ok=True)

    def start(self):
        """Start browser session"""
        self.playwright = sync_playwright().start()
        self.browser = self.playwright.chromium.launch(
            headless=self.headless,
            slow_mo=self.slow_mo
        )
        self.page = self.browser.new_page(viewport={"width": 1280, "height": 900})
        print(f"[Rideshare Agent] Browser started (headless={self.headless}, slow_mo={self.slow_mo}ms)")

    def stop(self):
        """Stop browser session"""
        if self.browser:
            self.browser.close()
        if self.playwright:
            self.playwright.stop()
        print("[Rideshare Agent] Browser stopped")

    def screenshot(self, name: str):
        """Take screenshot"""
        if self.page:
            path = f"{self.screenshot_dir}/{self.session_id}_{name}.png"
            self.page.screenshot(path=path)
            print(f"[Screenshot] {path}")

    # ==================== CUSTOMER FLOW ====================

    def customer_login(self, email: str, password: str) -> TestResult:
        """Login as customer"""
        try:
            # Go to homepage first
            self.page.goto(self.base_url)
            self.page.wait_for_load_state("networkidle")
            time.sleep(1)

            # Click Customer Login button in header
            customer_login_btn = self.page.query_selector('a:has-text("Customer Login"), button:has-text("Customer Login")')
            if customer_login_btn:
                customer_login_btn.click()
                self.page.wait_for_load_state("networkidle")
                time.sleep(1)
            else:
                self.page.goto(f"{self.base_url}/customer/login")
                self.page.wait_for_load_state("networkidle")

            self.screenshot("01_customer_login_page")

            # Enter credentials
            email_input = self.page.wait_for_selector(
                'input[type="email"], input[name="email"], input[placeholder*="email" i]',
                timeout=5000
            )
            password_input = self.page.wait_for_selector('input[type="password"]', timeout=5000)

            email_input.fill(email)
            time.sleep(0.3)
            password_input.fill(password)
            self.screenshot("02_customer_credentials")

            # Find and click the correct login button (avoid social logins)
            all_buttons = self.page.query_selector_all('button')
            login_btn = None
            for btn in all_buttons:
                btn_text = btn.text_content() or ""
                if "Google" in btn_text or "Apple" in btn_text or "Signing" in btn_text:
                    continue
                if "Continue" in btn_text or "Sign In" in btn_text or "Login" in btn_text or "Log In" in btn_text:
                    login_btn = btn
                    break

            if login_btn:
                login_btn.click()
            else:
                # Fallback: try submit button
                submit_btn = self.page.query_selector('button[type="submit"]')
                if submit_btn:
                    submit_btn.click()

            self.page.wait_for_load_state("networkidle")
            time.sleep(2)
            self.screenshot("03_customer_logged_in")

            current_url = self.page.url
            if "customer" in current_url and "login" not in current_url:
                return TestResult(True, f"Customer logged in: {current_url}")
            else:
                return TestResult(False, f"Login may have failed: {current_url}")

        except Exception as e:
            self.screenshot("error_customer_login")
            return TestResult(False, f"Login error: {str(e)}")

    def navigate_to_rideshare(self) -> TestResult:
        """Navigate to rideshare booking page"""
        try:
            # Look for rideshare link/button
            rideshare_link = self.page.locator(
                'a:has-text("Rideshare"), a:has-text("Book Ride"), '
                'button:has-text("Rideshare"), button:has-text("Book Ride"), '
                '[href*="ride"], [href*="rideshare"]'
            ).first

            if rideshare_link.is_visible():
                rideshare_link.click()
                self.page.wait_for_load_state("networkidle")
                self.screenshot("04_rideshare_page")
                return TestResult(True, f"Navigated to rideshare: {self.page.url}")
            else:
                # Try direct navigation
                self.page.goto(f"{self.base_url}/customer/ride")
                self.page.wait_for_load_state("networkidle")
                self.screenshot("04_rideshare_page_direct")
                return TestResult(True, f"Direct navigation to rideshare: {self.page.url}")

        except Exception as e:
            self.screenshot("error_rideshare_nav")
            return TestResult(False, f"Navigate error: {str(e)}")

    def enter_ride_addresses(self, pickup: str, dropoff: str) -> TestResult:
        """Enter pickup and dropoff addresses"""
        try:
            # Find pickup input
            pickup_inputs = self.page.locator(
                'input[placeholder*="pickup" i], input[placeholder*="from" i], '
                'input[placeholder*="current location" i], input[name*="pickup" i]'
            )

            if pickup_inputs.count() > 0:
                pickup_inputs.first.fill(pickup)
                time.sleep(0.5)
            self.screenshot("05_pickup_entered")

            # Find dropoff input
            dropoff_inputs = self.page.locator(
                'input[placeholder*="dropoff" i], input[placeholder*="drop" i], '
                'input[placeholder*="destination" i], input[placeholder*="to" i], '
                'input[name*="dropoff" i], input[name*="destination" i]'
            )

            if dropoff_inputs.count() > 0:
                dropoff_inputs.first.fill(dropoff)
                time.sleep(0.5)
            self.screenshot("06_dropoff_entered")

            return TestResult(True, "Addresses entered")

        except Exception as e:
            self.screenshot("error_addresses")
            return TestResult(False, f"Address entry error: {str(e)}")

    def select_ride_type(self, ride_type: str = "standard") -> TestResult:
        """Select ride type (standard, premium, xl, shared)"""
        try:
            # Look for ride type options
            ride_option = self.page.locator(
                f'[data-ride-type="{ride_type}"], '
                f'button:has-text("{ride_type}"), '
                f'.ride-option:has-text("{ride_type}"), '
                f'label:has-text("{ride_type}")'
            ).first

            if ride_option.is_visible():
                ride_option.click()
                self.screenshot("07_ride_type_selected")
                return TestResult(True, f"Selected ride type: {ride_type}")
            else:
                self.screenshot("07_ride_type_default")
                return TestResult(True, "Using default ride type")

        except Exception as e:
            return TestResult(False, f"Ride type selection error: {str(e)}")

    def request_ride(self) -> TestResult:
        """Submit ride request (handles 2-step flow: Get Estimate -> Confirm Request)"""
        try:
            # Step 1: Click "Get Price Estimate" button first
            estimate_btn = self.page.locator(
                'button:has-text("Get Price Estimate"), button:has-text("Get Estimate"), '
                'button:has-text("Get Quote"), button.main-button'
            ).first

            if estimate_btn.is_visible():
                print("[Rideshare Agent] Clicking 'Get Price Estimate' button")
                estimate_btn.click()
                self.page.wait_for_load_state("networkidle")
                time.sleep(2)
                self.screenshot("08a_fare_estimate")

            # Step 2: Click "Confirm & Request Ride" button
            confirm_btn = self.page.locator(
                'button:has-text("Confirm & Request Ride"), button:has-text("Request Ride"), '
                'button:has-text("Confirm"), button.confirm-button'
            ).first

            if confirm_btn.is_visible():
                print("[Rideshare Agent] Clicking 'Confirm & Request Ride' button")
                confirm_btn.click()
                self.page.wait_for_load_state("networkidle")
                time.sleep(2)
                self.screenshot("08b_ride_requested")
                return TestResult(True, "Ride request submitted")

            # Fallback: Look for any primary action button
            primary_btn = self.page.locator(
                'button[type="submit"], button.ant-btn-primary:visible'
            ).first

            if primary_btn.is_visible():
                print("[Rideshare Agent] Clicking primary button")
                primary_btn.click()
                self.page.wait_for_load_state("networkidle")
                time.sleep(2)
                self.screenshot("08_ride_requested")
                return TestResult(True, "Ride request submitted via primary button")

            self.screenshot("08_no_button_found")
            return TestResult(False, "Request button not found")

        except Exception as e:
            self.screenshot("error_request_ride")
            return TestResult(False, f"Request ride error: {str(e)}")

    def view_driver_bids(self) -> TestResult:
        """View incoming driver bids"""
        try:
            # Wait for bids to appear
            time.sleep(3)
            self.screenshot("09_viewing_bids")

            # Look for bid cards/list
            bids = self.page.locator(
                '.bid-card, .driver-bid, [data-bid-id], '
                '.bid-item, .quote-card'
            )

            if bids.count() > 0:
                return TestResult(True, f"Found {bids.count()} driver bids")
            else:
                return TestResult(True, "Waiting for driver bids...")

        except Exception as e:
            return TestResult(False, f"View bids error: {str(e)}")

    def accept_bid(self) -> TestResult:
        """Accept a driver bid"""
        try:
            # Look for accept button on first bid
            accept_btn = self.page.locator(
                'button:has-text("Accept"), button:has-text("Book"), '
                'button:has-text("Confirm"), .accept-bid-btn'
            ).first

            if accept_btn.is_visible():
                accept_btn.click()
                self.page.wait_for_load_state("networkidle")
                time.sleep(1)
                self.screenshot("10_bid_accepted")
                return TestResult(True, "Bid accepted!")
            else:
                return TestResult(False, "Accept button not found")

        except Exception as e:
            self.screenshot("error_accept_bid")
            return TestResult(False, f"Accept bid error: {str(e)}")

    def counter_bid(self, amount: float) -> TestResult:
        """Counter a driver's bid"""
        try:
            # Look for counter option
            counter_btn = self.page.locator(
                'button:has-text("Counter"), button:has-text("Negotiate"), '
                '.counter-bid-btn'
            ).first

            if counter_btn.is_visible():
                counter_btn.click()
                time.sleep(0.5)

                # Enter counter amount
                counter_input = self.page.locator(
                    'input[type="number"], input[placeholder*="price" i], '
                    'input[name*="counter" i], input[name*="price" i]'
                ).first

                if counter_input.is_visible():
                    counter_input.fill(str(amount))
                    self.screenshot("11_counter_entered")

                    # Submit counter
                    submit_btn = self.page.locator(
                        'button:has-text("Send"), button:has-text("Submit"), '
                        'button[type="submit"]'
                    ).first

                    if submit_btn.is_visible():
                        submit_btn.click()
                        time.sleep(1)
                        self.screenshot("12_counter_submitted")
                        return TestResult(True, f"Counter offer sent: ${amount}")

            return TestResult(False, "Counter option not available")

        except Exception as e:
            self.screenshot("error_counter_bid")
            return TestResult(False, f"Counter bid error: {str(e)}")

    # ==================== DRIVER FLOW ====================

    def driver_login(self, email: str, password: str) -> TestResult:
        """Login as driver"""
        try:
            self.page.goto(f"{self.base_url}/driver/login")
            self.page.wait_for_load_state("networkidle")
            self.screenshot("driver_01_login_page")

            # Enter credentials
            email_input = self.page.locator(
                'input[type="email"], input[placeholder*="@"], '
                'input[name="email"], input[placeholder*="email" i]'
            ).first
            email_input.fill(email)

            self.page.fill('input[type="password"]', password)
            self.screenshot("driver_02_credentials")

            # Click login
            login_btn = self.page.locator(
                'button:has-text("Sign In"), button:has-text("Login"), '
                'button:has-text("Log In"), button[type="submit"]'
            ).first
            login_btn.click()

            self.page.wait_for_load_state("networkidle")
            time.sleep(1)
            self.screenshot("driver_03_logged_in")

            current_url = self.page.url
            if "driver" in current_url and "login" not in current_url:
                return TestResult(True, f"Driver logged in: {current_url}")
            else:
                return TestResult(False, f"Login may have failed: {current_url}")

        except Exception as e:
            self.screenshot("error_driver_login")
            return TestResult(False, f"Driver login error: {str(e)}")

    def navigate_to_ride_requests(self) -> TestResult:
        """Navigate to available ride requests"""
        try:
            # Look for ride requests link
            rides_link = self.page.locator(
                'a:has-text("Rides"), a:has-text("Ride Requests"), '
                'a:has-text("Available Rides"), [href*="rides"], '
                'button:has-text("Find Rides")'
            ).first

            if rides_link.is_visible():
                rides_link.click()
                self.page.wait_for_load_state("networkidle")
            else:
                self.page.goto(f"{self.base_url}/driver/rides")
                self.page.wait_for_load_state("networkidle")

            self.screenshot("driver_04_ride_requests")
            return TestResult(True, f"Viewing ride requests: {self.page.url}")

        except Exception as e:
            self.screenshot("error_ride_requests")
            return TestResult(False, f"Navigate error: {str(e)}")

    def view_ride_details(self) -> TestResult:
        """View details of a ride request"""
        try:
            # Click on first ride request
            ride_cards = self.page.locator(
                '.ride-card, .ride-request, [data-ride-id], '
                '.request-card, .available-ride'
            )

            if ride_cards.count() > 0:
                ride_cards.first.click()
                time.sleep(1)
                self.screenshot("driver_05_ride_details")
                return TestResult(True, "Viewing ride details")
            else:
                return TestResult(True, "No ride requests available")

        except Exception as e:
            return TestResult(False, f"View details error: {str(e)}")

    def submit_driver_bid(self, amount: float, message: str = "") -> TestResult:
        """Submit a bid on a ride request"""
        try:
            # Look for bid input
            bid_input = self.page.locator(
                'input[name*="bid" i], input[name*="price" i], '
                'input[placeholder*="bid" i], input[placeholder*="price" i], '
                'input[type="number"]'
            ).first

            if bid_input.is_visible():
                bid_input.fill(str(amount))

            # Add message if input exists
            msg_input = self.page.locator(
                'textarea, input[placeholder*="message" i], '
                'input[name*="message" i]'
            ).first

            if msg_input.is_visible() and message:
                msg_input.fill(message)

            self.screenshot("driver_06_bid_entered")

            # Submit bid
            submit_btn = self.page.locator(
                'button:has-text("Submit Bid"), button:has-text("Place Bid"), '
                'button:has-text("Send Bid"), button[type="submit"]'
            ).first

            if submit_btn.is_visible():
                submit_btn.click()
                time.sleep(1)
                self.screenshot("driver_07_bid_submitted")
                return TestResult(True, f"Bid submitted: ${amount}")
            else:
                return TestResult(False, "Submit button not found")

        except Exception as e:
            self.screenshot("error_submit_bid")
            return TestResult(False, f"Submit bid error: {str(e)}")

    # ==================== CHAT ====================

    def open_chat(self) -> TestResult:
        """Open chat with driver/customer"""
        try:
            chat_btn = self.page.locator(
                'button:has-text("Chat"), button:has-text("Message"), '
                '.chat-btn, [data-chat], .message-icon'
            ).first

            if chat_btn.is_visible():
                chat_btn.click()
                time.sleep(0.5)
                self.screenshot("chat_01_opened")
                return TestResult(True, "Chat opened")
            else:
                return TestResult(False, "Chat button not found")

        except Exception as e:
            return TestResult(False, f"Open chat error: {str(e)}")

    def send_chat_message(self, message: str) -> TestResult:
        """Send a chat message"""
        try:
            # Find chat input
            chat_input = self.page.locator(
                'input[placeholder*="message" i], textarea[placeholder*="message" i], '
                'input[name="message"], .chat-input, .message-input'
            ).first

            if chat_input.is_visible():
                chat_input.fill(message)

                # Send message
                send_btn = self.page.locator(
                    'button:has-text("Send"), button[type="submit"], '
                    '.send-btn, .send-message'
                ).first

                if send_btn.is_visible():
                    send_btn.click()
                    time.sleep(0.5)
                    self.screenshot("chat_02_message_sent")
                    return TestResult(True, f"Message sent: {message[:30]}...")
                else:
                    # Try pressing Enter
                    chat_input.press("Enter")
                    time.sleep(0.5)
                    self.screenshot("chat_02_message_sent")
                    return TestResult(True, f"Message sent: {message[:30]}...")

            return TestResult(False, "Chat input not found")

        except Exception as e:
            return TestResult(False, f"Send message error: {str(e)}")

    # ==================== RIDE TRACKING ====================

    def track_ride(self) -> TestResult:
        """View ride tracking screen"""
        try:
            self.screenshot("tracking_01_status")

            # Look for tracking elements
            tracking_status = self.page.locator(
                '.ride-status, .tracking-status, [data-status], '
                '.status-badge, .ride-progress'
            )

            if tracking_status.count() > 0:
                status_text = tracking_status.first.inner_text()
                return TestResult(True, f"Ride status: {status_text}")
            else:
                return TestResult(True, "Tracking view loaded")

        except Exception as e:
            return TestResult(False, f"Track ride error: {str(e)}")

    def rate_ride(self, stars: int = 5) -> TestResult:
        """Rate the completed ride"""
        try:
            # Look for rating stars
            star_elements = self.page.locator('.star, .rating-star, [data-rating]')

            if star_elements.count() >= stars:
                star_elements.nth(stars - 1).click()
                self.screenshot("rating_01_selected")

                # Submit rating
                submit_btn = self.page.locator(
                    'button:has-text("Submit"), button:has-text("Rate"), '
                    'button[type="submit"]'
                ).first

                if submit_btn.is_visible():
                    submit_btn.click()
                    time.sleep(1)
                    self.screenshot("rating_02_submitted")
                    return TestResult(True, f"Rated {stars} stars")

            return TestResult(False, "Rating UI not found")

        except Exception as e:
            return TestResult(False, f"Rate ride error: {str(e)}")


def run_customer_ui_test():
    """Run customer rideshare UI test"""
    print("\n" + "=" * 60)
    print("  CUSTOMER RIDESHARE UI TEST")
    print("=" * 60)

    agent = RideshareUIAgent(headless=False, slow_mo=500)
    results = []

    try:
        agent.start()

        # Step 1: Login
        print("\n>>> Step 1: Customer Login")
        result = agent.customer_login(CUSTOMER_EMAIL, CUSTOMER_PASSWORD)
        print(f"[{'PASS' if result.success else 'FAIL'}] {result.message}")
        results.append(("Login", result.success))

        # Step 2: Navigate to rideshare
        print("\n>>> Step 2: Navigate to Rideshare")
        result = agent.navigate_to_rideshare()
        print(f"[{'PASS' if result.success else 'FAIL'}] {result.message}")
        results.append(("Navigate", result.success))

        # Step 3: Enter addresses
        print("\n>>> Step 3: Enter Addresses")
        result = agent.enter_ride_addresses(PICKUP_ADDRESS, DROPOFF_ADDRESS)
        print(f"[{'PASS' if result.success else 'FAIL'}] {result.message}")
        results.append(("Addresses", result.success))

        # Step 4: Select ride type
        print("\n>>> Step 4: Select Ride Type")
        result = agent.select_ride_type("standard")
        print(f"[{'PASS' if result.success else 'FAIL'}] {result.message}")
        results.append(("Ride Type", result.success))

        # Step 5: Request ride
        print("\n>>> Step 5: Request Ride")
        result = agent.request_ride()
        print(f"[{'PASS' if result.success else 'FAIL'}] {result.message}")
        results.append(("Request", result.success))

        # Step 6: View bids
        print("\n>>> Step 6: View Driver Bids")
        result = agent.view_driver_bids()
        print(f"[{'PASS' if result.success else 'FAIL'}] {result.message}")
        results.append(("View Bids", result.success))

    except Exception as e:
        print(f"[ERROR] {str(e)}")
    finally:
        agent.stop()

    # Summary
    passed = sum(1 for _, s in results if s)
    print(f"\n{'=' * 60}")
    print(f"CUSTOMER UI TEST: {passed}/{len(results)} steps passed")
    print("=" * 60)

    return passed == len(results)


def run_driver_ui_test():
    """Run driver rideshare UI test"""
    print("\n" + "=" * 60)
    print("  DRIVER RIDESHARE UI TEST")
    print("=" * 60)

    agent = RideshareUIAgent(headless=False, slow_mo=500)
    results = []

    try:
        agent.start()

        # Step 1: Login
        print("\n>>> Step 1: Driver Login")
        result = agent.driver_login(DRIVER_EMAIL, DRIVER_PASSWORD)
        print(f"[{'PASS' if result.success else 'FAIL'}] {result.message}")
        results.append(("Login", result.success))

        # Step 2: Navigate to ride requests
        print("\n>>> Step 2: Navigate to Ride Requests")
        result = agent.navigate_to_ride_requests()
        print(f"[{'PASS' if result.success else 'FAIL'}] {result.message}")
        results.append(("Navigate", result.success))

        # Step 3: View ride details
        print("\n>>> Step 3: View Ride Details")
        result = agent.view_ride_details()
        print(f"[{'PASS' if result.success else 'FAIL'}] {result.message}")
        results.append(("View Details", result.success))

        # Step 4: Submit bid
        print("\n>>> Step 4: Submit Bid")
        result = agent.submit_driver_bid(25.00, "I can be there in 5 minutes!")
        print(f"[{'PASS' if result.success else 'FAIL'}] {result.message}")
        results.append(("Submit Bid", result.success))

    except Exception as e:
        print(f"[ERROR] {str(e)}")
    finally:
        agent.stop()

    # Summary
    passed = sum(1 for _, s in results if s)
    print(f"\n{'=' * 60}")
    print(f"DRIVER UI TEST: {passed}/{len(results)} steps passed")
    print("=" * 60)

    return passed == len(results)


if __name__ == "__main__":
    if len(sys.argv) > 1:
        if sys.argv[1] == "customer":
            run_customer_ui_test()
        elif sys.argv[1] == "driver":
            run_driver_ui_test()
        else:
            print("Usage: python rideshare_ui_agent.py [customer|driver]")
    else:
        # Run both tests
        print("\nRunning Customer UI Test...")
        run_customer_ui_test()

        print("\n\nRunning Driver UI Test...")
        run_driver_ui_test()
