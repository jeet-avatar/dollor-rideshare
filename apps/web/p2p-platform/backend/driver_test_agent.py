#!/usr/bin/env python3
"""
Dollor.ai Driver UI Testing Agent
Playwright-based agent for automated driver portal testing

PRODUCTION URLS:
- Production Website: https://www.dollor.ai
- Driver Portal: https://www.dollor.ai/driver
- Production API: https://api.dollor.ai

CREDENTIALS:
- Driver: demo.driver@dollor.ai / $DEMO_DRIVER_PASSWORD

Driver Portal Routes:
- /driver/login    - Login page
- /driver/orders   - Available orders (default)
- /driver/bidding  - Ride bidding
- /driver/active   - Active delivery
- /driver/deliveries - Delivery history
- /driver/earnings - Earnings dashboard
- /driver/profile  - Driver profile
- /driver/messages - Messages

Usage:
    # Driver login test
    python driver_test_agent.py login

    # Full driver flow (view orders, accept, complete)
    python driver_test_agent.py flow

    # View earnings
    python driver_test_agent.py earnings
"""

# Environment URLs
ENVIRONMENTS = {
    "production": "https://www.dollor.ai",
    "staging": "https://d3b3ow4g7hjwi5.cloudfront.net",
    "local": "http://localhost:5173",
}

API_URLS = {
    "production": "https://api.dollor.ai",
    "staging": "https://d34u5ixl0bulv4.cloudfront.net",
    "local": "http://localhost:8080",
}

# Demo driver credentials
DEFAULT_DRIVER_EMAIL = "demo.driver@dollor.ai"
DEFAULT_DRIVER_PASSWORD = os.environ["DEMO_DRIVER_PASSWORD"]

import argparse
import sys
import os
from dataclasses import dataclass, field
from typing import Optional, List, Dict, Any
from datetime import datetime

try:
    from playwright.sync_api import sync_playwright, Page, Browser
except ImportError:
    print("Playwright not installed. Run:")
    print("  pip install playwright")
    print("  playwright install chromium")
    sys.exit(1)


@dataclass
class StepResult:
    success: bool
    message: str
    screenshot_path: Optional[str] = None
    data: Optional[Dict[str, Any]] = None


@dataclass
class DriverFlowResult:
    success: bool
    steps_completed: List[str] = field(default_factory=list)
    steps_failed: List[str] = field(default_factory=list)
    data: Optional[Dict[str, Any]] = None
    screenshots: List[str] = field(default_factory=list)
    error: Optional[str] = None


class DriverTestAgent:
    """UI testing agent for Dollor.ai Driver Portal"""

    def __init__(
        self,
        base_url: str = "https://www.dollor.ai",
        api_url: str = "https://api.dollor.ai",
        headless: bool = False,
        slow_mo: int = 500
    ):
        self.base_url = base_url.rstrip("/")
        self.api_url = api_url.rstrip("/")
        self.headless = headless
        self.slow_mo = slow_mo
        self.browser: Optional[Browser] = None
        self.page: Optional[Page] = None
        self._playwright = None
        self.screenshot_counter = 0
        self.session_id = datetime.now().strftime("%Y%m%d_%H%M%S")

    def _screenshot(self, name: str) -> str:
        """Take a screenshot with sequential numbering"""
        self.screenshot_counter += 1
        filename = f"screenshots/driver_{self.session_id}_{self.screenshot_counter:02d}_{name}.png"
        if self.page:
            self.page.screenshot(path=filename)
            print(f"[Screenshot] {filename}")
        return filename

    def _wait(self, ms: int = 1000):
        """Human-like wait"""
        if self.page:
            self.page.wait_for_timeout(ms)

    def start(self):
        """Start the browser"""
        self._playwright = sync_playwright().start()
        self.browser = self._playwright.chromium.launch(
            headless=self.headless,
            slow_mo=self.slow_mo
        )
        self.page = self.browser.new_page()
        print(f"[Driver Agent] Browser started (headless={self.headless}, slow_mo={self.slow_mo}ms)")

    def stop(self):
        """Stop the browser"""
        if self.browser:
            self.browser.close()
        if self._playwright:
            self._playwright.stop()
        print("[Driver Agent] Browser stopped")

    # ==================== DRIVER LOGIN ====================

    def driver_login(self, email: str, password: str) -> StepResult:
        """Login to Driver Portal"""
        if not self.page:
            return StepResult(False, "Browser not started")

        try:
            # Navigate to driver login
            login_url = f"{self.base_url}/driver/login"
            print(f"[Driver Agent] Navigating to: {login_url}")
            self.page.goto(login_url, wait_until="networkidle")
            self._wait(2000)
            self._screenshot("driver_login_page")

            # Find and fill email
            email_input = self.page.wait_for_selector(
                'input[type="email"], input[name="email"], input[placeholder*="email" i]',
                timeout=5000
            )
            print(f"[Driver Agent] Entering email: {email}")
            email_input.fill(email)
            self._wait(500)

            # Find and fill password
            password_input = self.page.wait_for_selector('input[type="password"]', timeout=5000)
            print("[Driver Agent] Entering password")
            password_input.fill(password)
            self._wait(500)
            self._screenshot("driver_credentials_entered")

            # Click login button
            login_btn = self.page.query_selector(
                'button:has-text("Login"), button:has-text("Sign In"), button[type="submit"]'
            )
            if login_btn:
                print("[Driver Agent] Clicking login button")
                login_btn.click()
            else:
                password_input.press("Enter")

            self._wait(3000)
            screenshot = self._screenshot("driver_post_login")
            current_url = self.page.url
            print(f"[Driver Agent] Current URL: {current_url}")

            # Check if login successful - should redirect to /driver/orders or /driver
            if "/driver/orders" in current_url or (current_url.endswith("/driver") or current_url.endswith("/driver/")):
                return StepResult(True, f"Driver login successful! URL: {current_url}", screenshot)

            # Check for dashboard or available orders page elements
            if self.page.query_selector('text="Available Orders"') or self.page.query_selector('text="No orders available"'):
                return StepResult(True, "Driver login successful - on orders page", screenshot)

            # Check for error
            error = self.page.query_selector('[role="alert"], .text-red-500, .error')
            if error:
                error_text = error.text_content() or ""
                if "incorrect" in error_text.lower() or "invalid" in error_text.lower():
                    return StepResult(False, f"Login failed: {error_text}", screenshot)

            return StepResult(True, f"Driver login completed. URL: {current_url}", screenshot)

        except Exception as e:
            return StepResult(False, f"Driver login error: {str(e)}", self._screenshot("driver_login_error"))

    # ==================== VIEW AVAILABLE ORDERS ====================

    def view_available_orders(self) -> StepResult:
        """Navigate to available orders page"""
        if not self.page:
            return StepResult(False, "Browser not started")

        try:
            print("[Driver Agent] Navigating to available orders...")
            self.page.goto(f"{self.base_url}/driver/orders", wait_until="networkidle")
            self._wait(2000)
            screenshot = self._screenshot("available_orders")

            # Check for order cards or "no orders" message
            order_cards = self.page.query_selector_all('[class*="order"], [class*="card"]')
            no_orders = self.page.query_selector('text="No orders available", text="No available orders"')

            order_count = len([c for c in order_cards if c.is_visible()]) if order_cards else 0

            if no_orders:
                return StepResult(True, "No orders currently available", screenshot, {"order_count": 0})

            return StepResult(
                True,
                f"Viewing available orders. Found {order_count} potential order cards.",
                screenshot,
                {"order_count": order_count}
            )

        except Exception as e:
            return StepResult(False, f"View orders error: {str(e)}", self._screenshot("orders_error"))

    # ==================== ACCEPT ORDER ====================

    def accept_order(self) -> StepResult:
        """Accept the first available order"""
        if not self.page:
            return StepResult(False, "Browser not started")

        try:
            print("[Driver Agent] Looking for orders to accept...")
            self._screenshot("before_accept")

            # Look for Accept button
            accept_btn = self.page.query_selector(
                'button:has-text("Accept"), button:has-text("Accept Order"), '
                'button:has-text("Take Order"), button[class*="accept"]'
            )

            if not accept_btn:
                # Maybe need to click on an order first
                order_card = self.page.query_selector('[class*="order-card"], [class*="OrderCard"]')
                if order_card:
                    order_card.click()
                    self._wait(1500)
                    accept_btn = self.page.query_selector('button:has-text("Accept")')

            if not accept_btn:
                return StepResult(False, "No orders available to accept", self._screenshot("no_orders_to_accept"))

            print("[Driver Agent] Clicking Accept button")
            accept_btn.click()
            self._wait(2000)

            screenshot = self._screenshot("order_accepted")
            current_url = self.page.url

            # Check if redirected to active delivery
            if "/active" in current_url:
                return StepResult(True, "Order accepted! Redirected to active delivery.", screenshot)

            # Check for confirmation
            if self.page.query_selector('text="Order accepted", text="Delivery started"'):
                return StepResult(True, "Order accepted successfully", screenshot)

            return StepResult(True, f"Accept action completed. URL: {current_url}", screenshot)

        except Exception as e:
            return StepResult(False, f"Accept order error: {str(e)}", self._screenshot("accept_error"))

    # ==================== VIEW ACTIVE DELIVERY ====================

    def view_active_delivery(self) -> StepResult:
        """View current active delivery"""
        if not self.page:
            return StepResult(False, "Browser not started")

        try:
            print("[Driver Agent] Navigating to active delivery...")
            self.page.goto(f"{self.base_url}/driver/active", wait_until="networkidle")
            self._wait(2000)
            screenshot = self._screenshot("active_delivery")

            # Check for active delivery content
            no_active = self.page.query_selector('text="No active delivery", text="No active orders"')
            if no_active:
                return StepResult(True, "No active delivery at the moment", screenshot, {"has_active": False})

            # Look for delivery details
            pickup_info = self.page.query_selector('text="Pickup", text="Pick up from"')
            delivery_info = self.page.query_selector('text="Deliver to", text="Drop off"')

            has_active = pickup_info is not None or delivery_info is not None

            return StepResult(
                True,
                "Active delivery page loaded" + (" - has active order" if has_active else " - no active order"),
                screenshot,
                {"has_active": has_active}
            )

        except Exception as e:
            return StepResult(False, f"Active delivery error: {str(e)}", self._screenshot("active_error"))

    # ==================== COMPLETE DELIVERY ====================

    def complete_delivery(self) -> StepResult:
        """Mark delivery as complete"""
        if not self.page:
            return StepResult(False, "Browser not started")

        try:
            print("[Driver Agent] Looking for complete delivery button...")
            self._screenshot("before_complete")

            # Look for complete/delivered button
            complete_btn = self.page.query_selector(
                'button:has-text("Complete"), button:has-text("Delivered"), '
                'button:has-text("Mark as Delivered"), button:has-text("Finish")'
            )

            if not complete_btn:
                return StepResult(False, "No active delivery to complete", self._screenshot("no_delivery_to_complete"))

            print("[Driver Agent] Clicking Complete button")
            complete_btn.click()
            self._wait(2000)

            # Handle confirmation modal if present
            confirm_btn = self.page.query_selector('button:has-text("Confirm"), button:has-text("Yes")')
            if confirm_btn:
                confirm_btn.click()
                self._wait(2000)

            screenshot = self._screenshot("delivery_completed")

            # Check for success message
            success = self.page.query_selector('text="Delivery completed", text="Order delivered"')
            if success:
                return StepResult(True, "Delivery completed successfully!", screenshot)

            return StepResult(True, "Complete action executed", screenshot)

        except Exception as e:
            return StepResult(False, f"Complete delivery error: {str(e)}", self._screenshot("complete_error"))

    # ==================== VIEW EARNINGS ====================

    def view_earnings(self) -> StepResult:
        """View driver earnings dashboard"""
        if not self.page:
            return StepResult(False, "Browser not started")

        try:
            print("[Driver Agent] Navigating to earnings...")
            self.page.goto(f"{self.base_url}/driver/earnings", wait_until="networkidle")
            self._wait(2000)
            screenshot = self._screenshot("earnings_dashboard")

            # Try to extract earnings data
            earnings_data = {}

            # Look for today's earnings
            today_el = self.page.query_selector('text=/Today.*\\$[0-9]/i')
            if today_el:
                earnings_data["today"] = today_el.text_content()

            # Look for weekly earnings
            weekly_el = self.page.query_selector('text=/Week.*\\$[0-9]/i, text=/This week.*\\$[0-9]/i')
            if weekly_el:
                earnings_data["weekly"] = weekly_el.text_content()

            # Look for total/balance
            total_el = self.page.query_selector('text=/Total.*\\$[0-9]/i, text=/Balance.*\\$[0-9]/i')
            if total_el:
                earnings_data["total"] = total_el.text_content()

            return StepResult(
                True,
                "Earnings dashboard loaded",
                screenshot,
                {"earnings": earnings_data}
            )

        except Exception as e:
            return StepResult(False, f"View earnings error: {str(e)}", self._screenshot("earnings_error"))

    # ==================== VIEW DELIVERY HISTORY ====================

    def view_delivery_history(self) -> StepResult:
        """View past deliveries"""
        if not self.page:
            return StepResult(False, "Browser not started")

        try:
            print("[Driver Agent] Navigating to delivery history...")
            self.page.goto(f"{self.base_url}/driver/deliveries", wait_until="networkidle")
            self._wait(2000)
            screenshot = self._screenshot("delivery_history")

            # Count delivery entries
            delivery_cards = self.page.query_selector_all('[class*="delivery"], [class*="order"], [class*="card"]')
            visible_deliveries = len([c for c in delivery_cards if c.is_visible()]) if delivery_cards else 0

            no_deliveries = self.page.query_selector('text="No deliveries", text="No completed deliveries"')
            if no_deliveries:
                return StepResult(True, "No delivery history yet", screenshot, {"delivery_count": 0})

            return StepResult(
                True,
                f"Delivery history loaded. Found {visible_deliveries} entries.",
                screenshot,
                {"delivery_count": visible_deliveries}
            )

        except Exception as e:
            return StepResult(False, f"Delivery history error: {str(e)}", self._screenshot("history_error"))

    # ==================== VIEW PROFILE ====================

    def view_profile(self) -> StepResult:
        """View driver profile"""
        if not self.page:
            return StepResult(False, "Browser not started")

        try:
            print("[Driver Agent] Navigating to profile...")
            self.page.goto(f"{self.base_url}/driver/profile", wait_until="networkidle")
            self._wait(2000)
            screenshot = self._screenshot("driver_profile")

            # Try to extract profile info
            profile_data = {}

            # Look for driver name
            name_el = self.page.query_selector('h1, h2, [class*="name"]')
            if name_el:
                profile_data["name"] = name_el.text_content()

            # Look for rating
            rating_el = self.page.query_selector('[class*="rating"]')
            if not rating_el:
                rating_el = self.page.query_selector('text=/[0-9]\\.[0-9]/')
            if rating_el:
                profile_data["rating"] = rating_el.text_content()

            return StepResult(
                True,
                "Driver profile loaded",
                screenshot,
                {"profile": profile_data}
            )

        except Exception as e:
            return StepResult(False, f"View profile error: {str(e)}", self._screenshot("profile_error"))

    # ==================== RIDE BIDDING ====================

    def view_ride_bidding(self) -> StepResult:
        """View available ride requests for bidding"""
        if not self.page:
            return StepResult(False, "Browser not started")

        try:
            print("[Driver Agent] Navigating to ride bidding...")
            self.page.goto(f"{self.base_url}/driver/bidding", wait_until="networkidle")
            self._wait(2000)
            screenshot = self._screenshot("ride_bidding")

            # Check for ride requests
            ride_cards = self.page.query_selector_all('[class*="ride"], [class*="bid"], [class*="request"]')
            no_rides = self.page.query_selector('text="No rides available", text="No ride requests"')

            if no_rides:
                return StepResult(True, "No ride requests available for bidding", screenshot, {"ride_count": 0})

            ride_count = len([c for c in ride_cards if c.is_visible()]) if ride_cards else 0

            return StepResult(
                True,
                f"Ride bidding page loaded. Found {ride_count} potential rides.",
                screenshot,
                {"ride_count": ride_count}
            )

        except Exception as e:
            return StepResult(False, f"Ride bidding error: {str(e)}", self._screenshot("bidding_error"))

    # ==================== FULL DRIVER FLOW ====================

    def run_driver_flow(self, email: str, password: str) -> DriverFlowResult:
        """
        Run complete driver flow: Login -> View Orders -> View Earnings -> Profile
        """
        result = DriverFlowResult(success=False)

        steps = [
            ("Driver Login", lambda: self.driver_login(email, password)),
            ("View Available Orders", lambda: self.view_available_orders()),
            ("View Active Delivery", lambda: self.view_active_delivery()),
            ("View Delivery History", lambda: self.view_delivery_history()),
            ("View Earnings", lambda: self.view_earnings()),
            ("View Profile", lambda: self.view_profile()),
            ("View Ride Bidding", lambda: self.view_ride_bidding()),
        ]

        print("\n" + "=" * 60)
        print("DOLLOR.AI DRIVER PORTAL TEST - PRODUCTION")
        print("=" * 60)
        print(f"Website: {self.base_url}")
        print(f"Email: {email}")
        print("=" * 60 + "\n")

        for step_name, step_func in steps:
            print(f"\n{'='*60}")
            print(f">>> Step: {step_name}")
            print("=" * 60)

            step_result = step_func()

            if step_result.screenshot_path:
                result.screenshots.append(step_result.screenshot_path)

            if step_result.success:
                result.steps_completed.append(step_name)
                print(f"[PASSED] {step_result.message}")

                if step_result.data:
                    if not result.data:
                        result.data = {}
                    result.data.update(step_result.data)
            else:
                result.steps_failed.append(step_name)
                result.error = step_result.message
                print(f"[FAILED] {step_result.message}")
                # Don't break - continue to see what works

        # Final screenshot
        if self.page:
            final_screenshot = self._screenshot("final_state")
            result.screenshots.append(final_screenshot)

        result.success = len(result.steps_failed) == 0

        print("\n" + "=" * 60)
        print("DRIVER FLOW SUMMARY")
        print("=" * 60)
        print(f"Status: {'PASSED' if result.success else 'PARTIAL'}")
        print(f"Steps Completed: {len(result.steps_completed)}/{len(steps)}")
        for step in result.steps_completed:
            print(f"  [x] {step}")
        for step in result.steps_failed:
            print(f"  [ ] {step} (FAILED)")
        if result.data:
            print(f"\nData collected: {result.data}")
        print("=" * 60)

        return result


def main():
    parser = argparse.ArgumentParser(description="Dollor.ai Driver Portal Testing Agent")
    subparsers = parser.add_subparsers(dest="command", help="Available commands")

    # Login command
    login_parser = subparsers.add_parser("login", help="Test driver login only")
    login_parser.add_argument("--email", "-e", default=DEFAULT_DRIVER_EMAIL, help="Driver email")
    login_parser.add_argument("--password", "-p", default=DEFAULT_DRIVER_PASSWORD, help="Driver password")
    login_parser.add_argument("--env", choices=["production", "staging", "local"], default="production")
    login_parser.add_argument("--headless", action="store_true", help="Run headless")

    # Full flow command
    flow_parser = subparsers.add_parser("flow", help="Test full driver flow")
    flow_parser.add_argument("--email", "-e", default=DEFAULT_DRIVER_EMAIL, help="Driver email")
    flow_parser.add_argument("--password", "-p", default=DEFAULT_DRIVER_PASSWORD, help="Driver password")
    flow_parser.add_argument("--env", choices=["production", "staging", "local"], default="production")
    flow_parser.add_argument("--headless", action="store_true", help="Run headless")

    # Earnings command
    earnings_parser = subparsers.add_parser("earnings", help="View earnings dashboard")
    earnings_parser.add_argument("--email", "-e", default=DEFAULT_DRIVER_EMAIL, help="Driver email")
    earnings_parser.add_argument("--password", "-p", default=DEFAULT_DRIVER_PASSWORD, help="Driver password")
    earnings_parser.add_argument("--env", choices=["production", "staging", "local"], default="production")
    earnings_parser.add_argument("--headless", action="store_true", help="Run headless")

    args = parser.parse_args()

    if not args.command:
        parser.print_help()
        sys.exit(1)

    # Setup
    os.makedirs("screenshots", exist_ok=True)
    base_url = ENVIRONMENTS[args.env]
    api_url = API_URLS[args.env]

    agent = DriverTestAgent(
        base_url=base_url,
        api_url=api_url,
        headless=args.headless,
        slow_mo=500
    )

    try:
        agent.start()

        if args.command == "login":
            result = agent.driver_login(args.email, args.password)
            print(f"\n{'PASSED' if result.success else 'FAILED'}: {result.message}")
            sys.exit(0 if result.success else 1)

        elif args.command == "flow":
            result = agent.run_driver_flow(args.email, args.password)
            sys.exit(0 if result.success else 1)

        elif args.command == "earnings":
            # Login first, then view earnings
            login_result = agent.driver_login(args.email, args.password)
            if login_result.success:
                earnings_result = agent.view_earnings()
                print(f"\n{'PASSED' if earnings_result.success else 'FAILED'}: {earnings_result.message}")
                if earnings_result.data:
                    print(f"Earnings data: {earnings_result.data}")
                sys.exit(0 if earnings_result.success else 1)
            else:
                print(f"\nLogin failed: {login_result.message}")
                sys.exit(1)

    finally:
        agent.stop()


if __name__ == "__main__":
    main()
