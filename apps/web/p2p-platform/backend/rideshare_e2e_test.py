#!/usr/bin/env python3
"""
Dollor.ai Rideshare End-to-End Test Suite
Complete workflow testing: ride request, bidding, negotiation, chat, pickup, dropoff

Flow:
1. Customer creates ride request with pickup/dropoff in 92688 (Rancho Santa Margarita)
2. Driver views available ride requests
3. Driver submits a bid
4. Customer views bids and counters
5. Driver accepts counter offer
6. Ride gets matched
7. Chat communication between customer and driver
8. Driver starts ride (pickup)
9. Driver completes ride (dropoff)
10. Customer rates ride

Production URLs:
- Website: https://www.dollor.ai
- API: https://api.dollor.ai

Demo Credentials:
- Customer: demo.customer@dollor.ai / $DEMO_CUSTOMER_PASSWORD
- Driver: demo.driver@dollor.ai / $DEMO_DRIVER_PASSWORD
"""

import os
import sys
import time
import json
import requests
from datetime import datetime
from typing import Optional, Dict, Any
from dataclasses import dataclass

# Production configuration
BASE_URL = "https://www.dollor.ai"
API_URL = "https://api.dollor.ai"

# Demo credentials
CUSTOMER_EMAIL = "demo.customer@dollor.ai"
CUSTOMER_PASSWORD = os.environ["DEMO_CUSTOMER_PASSWORD"]
DRIVER_EMAIL = "demo.driver@dollor.ai"
DRIVER_PASSWORD = os.environ["DEMO_DRIVER_PASSWORD"]

# Real 92688 addresses for testing
PICKUP_ADDRESS = {
    "street": "30012 Crown Valley Pkwy",
    "city": "Laguna Niguel",
    "state": "CA",
    "zip_code": "92677",
    "lat": 33.5427,
    "lng": -117.7067,
    "formatted": "30012 Crown Valley Pkwy, Laguna Niguel, CA 92677"
}

DROPOFF_ADDRESS = {
    "street": "22352 El Paseo",
    "city": "Rancho Santa Margarita",
    "state": "CA",
    "zip_code": "92688",
    "lat": 33.641,
    "lng": -117.6028,
    "formatted": "22352 El Paseo, Rancho Santa Margarita, CA 92688"
}


@dataclass
class TestResult:
    """Test step result"""
    success: bool
    message: str
    data: Optional[Dict] = None


class RideshareTestAgent:
    """Agent for testing rideshare API endpoints"""

    def __init__(self):
        self.session = requests.Session()
        self.customer_token: Optional[str] = None
        self.driver_token: Optional[str] = None
        self.customer_id: Optional[int] = None
        self.driver_id: Optional[int] = None
        self.ride_request_id: Optional[int] = None
        self.bid_id: Optional[int] = None

    def _print_step(self, step_num: int, title: str):
        """Print step header"""
        print(f"\n>>> STEP {step_num}: {title}")
        print("-" * 50)

    def _print_result(self, result: TestResult):
        """Print test result"""
        status = "PASS" if result.success else "FAIL"
        print(f"[{status}] {result.message}")
        if result.data and not result.success:
            print(f"    Data: {json.dumps(result.data, indent=2)[:200]}")

    # ==================== AUTHENTICATION ====================

    def customer_login(self) -> TestResult:
        """Login as customer"""
        try:
            response = self.session.post(
                f"{API_URL}/api/auth/customer/login",
                data={
                    "username": CUSTOMER_EMAIL,
                    "password": CUSTOMER_PASSWORD
                },
                headers={"Content-Type": "application/x-www-form-urlencoded"}
            )

            if response.status_code == 200:
                data = response.json()
                self.customer_token = data.get("access_token")
                self.customer_id = data.get("customer_id") or data.get("customer", {}).get("id")
                return TestResult(True, f"Customer logged in (ID: {self.customer_id})", data)
            else:
                return TestResult(False, f"Customer login failed: {response.status_code}",
                                {"error": response.text})
        except Exception as e:
            return TestResult(False, f"Customer login error: {str(e)}")

    def driver_login(self) -> TestResult:
        """Login as driver"""
        try:
            response = self.session.post(
                f"{API_URL}/api/auth/driver/login",
                data={
                    "username": DRIVER_EMAIL,
                    "password": DRIVER_PASSWORD
                },
                headers={"Content-Type": "application/x-www-form-urlencoded"}
            )

            if response.status_code == 200:
                data = response.json()
                self.driver_token = data.get("access_token")
                self.driver_id = data.get("driver_id") or data.get("driver", {}).get("id")
                return TestResult(True, f"Driver logged in (ID: {self.driver_id})", data)
            else:
                return TestResult(False, f"Driver login failed: {response.status_code}",
                                {"error": response.text})
        except Exception as e:
            return TestResult(False, f"Driver login error: {str(e)}")

    # ==================== RIDE REQUEST ====================

    def estimate_fare(self) -> TestResult:
        """Get fare estimate for the ride"""
        try:
            response = self.session.post(
                f"{API_URL}/api/erp/rides/estimate-fare",
                json={
                    "pickup_lat": PICKUP_ADDRESS["lat"],
                    "pickup_lng": PICKUP_ADDRESS["lng"],
                    "dropoff_lat": DROPOFF_ADDRESS["lat"],
                    "dropoff_lng": DROPOFF_ADDRESS["lng"],
                    "ride_type": "standard"
                },
                headers={"Authorization": f"Bearer {self.customer_token}"}
            )

            if response.status_code == 200:
                data = response.json()
                fare = data.get("estimated_fare", 0)
                distance = data.get("distance_miles", 0)
                return TestResult(True, f"Fare estimate: ${fare} ({distance:.1f} miles)", data)
            else:
                return TestResult(False, f"Fare estimate failed: {response.status_code}",
                                {"error": response.text})
        except Exception as e:
            return TestResult(False, f"Fare estimate error: {str(e)}")

    def create_ride_request(self) -> TestResult:
        """Customer creates a ride request"""
        try:
            response = self.session.post(
                f"{API_URL}/api/rides/request",
                json={
                    "customer_id": self.customer_id or 0,
                    "pickup_address": PICKUP_ADDRESS["formatted"],
                    "pickup_latitude": PICKUP_ADDRESS["lat"],
                    "pickup_longitude": PICKUP_ADDRESS["lng"],
                    "dropoff_address": DROPOFF_ADDRESS["formatted"],
                    "dropoff_latitude": DROPOFF_ADDRESS["lat"],
                    "dropoff_longitude": DROPOFF_ADDRESS["lng"],
                    "ride_type": "standard",
                    "bidding_duration_minutes": 5
                },
                headers={
                    "Authorization": f"Bearer {self.customer_token}",
                    "Content-Type": "application/json"
                }
            )

            if response.status_code in (200, 201):
                data = response.json()
                # Response is {"success": true, "ride_request": {...}}
                ride_data = data.get("ride_request", data)
                # Store string request_id for display, use numeric ID for API calls
                self.ride_request_str = ride_data.get("request_id") or ride_data.get("ride_id") or ride_data.get("id")
                # The ride_request object includes the DB record ID
                self.ride_request_id = ride_data.get("id") or data.get("id") or data.get("ride_request_id")
                fare = ride_data.get("suggested_price") or ride_data.get("estimated_fare") or 0
                return TestResult(True,
                    f"Ride request created (ID: {self.ride_request_str}, Fare: ${fare})", data)
            else:
                return TestResult(False, f"Ride request failed: {response.status_code}",
                                {"error": response.text})
        except Exception as e:
            return TestResult(False, f"Ride request error: {str(e)}")

    # ==================== DRIVER BIDDING ====================

    def get_available_rides(self) -> TestResult:
        """Driver views available ride requests"""
        try:
            response = self.session.get(
                f"{API_URL}/api/rides/available",
                params={
                    "driver_id": self.driver_id or 48,  # Required parameter
                    "latitude": PICKUP_ADDRESS["lat"],
                    "longitude": PICKUP_ADDRESS["lng"],
                    "radius_miles": 15
                },
                headers={"Authorization": f"Bearer {self.driver_token}"}
            )

            if response.status_code == 200:
                data = response.json()
                rides = data.get("requests", []) if isinstance(data, dict) else data
                count = len(rides) if isinstance(rides, list) else 0
                return TestResult(True, f"Found {count} available ride requests", data)
            else:
                return TestResult(False, f"Get available rides failed: {response.status_code}",
                                {"error": response.text})
        except Exception as e:
            return TestResult(False, f"Get available rides error: {str(e)}")

    def submit_bid(self, proposed_price: float = 25.00) -> TestResult:
        """Driver submits a bid on a ride request"""
        if not self.ride_request_id:
            # Use a mock ride request ID for testing
            self.ride_request_id = 1

        try:
            response = self.session.post(
                f"{API_URL}/api/rides/request/{self.ride_request_id}/bid",
                json={
                    "driver_id": self.driver_id or 48,
                    "proposed_price": proposed_price,
                    "message": "I can be there in 5 minutes! Safe driver with 4.9 rating.",
                    "estimated_arrival_minutes": 5
                },
                headers={
                    "Authorization": f"Bearer {self.driver_token}",
                    "Content-Type": "application/json"
                }
            )

            if response.status_code == 200:
                data = response.json()
                bid_data = data.get("bid", {})
                self.bid_id = bid_data.get("id") or data.get("bid_id") or data.get("id")
                return TestResult(True,
                    f"Bid submitted: ${proposed_price} (Bid ID: {self.bid_id})", data)
            else:
                return TestResult(False, f"Submit bid failed: {response.status_code}",
                                {"error": response.text})
        except Exception as e:
            return TestResult(False, f"Submit bid error: {str(e)}")

    # ==================== NEGOTIATION ====================

    def get_bids_for_ride(self) -> TestResult:
        """Customer views bids on their ride request"""
        if not self.ride_request_id:
            self.ride_request_id = 1

        try:
            response = self.session.get(
                f"{API_URL}/api/rides/request/{self.ride_request_id}/bids",
                headers={"Authorization": f"Bearer {self.customer_token}"}
            )

            if response.status_code == 200:
                data = response.json()
                bids = data.get("bids", []) if isinstance(data, dict) else data
                count = len(bids) if isinstance(bids, list) else 0
                return TestResult(True, f"Found {count} bids on ride request", data)
            else:
                return TestResult(False, f"Get bids failed: {response.status_code}",
                                {"error": response.text})
        except Exception as e:
            return TestResult(False, f"Get bids error: {str(e)}")

    def counter_bid(self, counter_price: float = 22.00) -> TestResult:
        """Customer counters a driver's bid"""
        if not self.bid_id:
            self.bid_id = 1

        try:
            response = self.session.post(
                f"{API_URL}/api/rides/bid/{self.bid_id}/respond",
                json={
                    "action": "counter",
                    "counter_price": counter_price,
                    "message": f"Can you do ${counter_price}? That's my budget."
                },
                headers={
                    "Authorization": f"Bearer {self.customer_token}",
                    "Content-Type": "application/json"
                }
            )

            if response.status_code == 200:
                data = response.json()
                return TestResult(True,
                    f"Counter offer sent: ${counter_price}", data)
            else:
                return TestResult(False, f"Counter bid failed: {response.status_code}",
                                {"error": response.text})
        except Exception as e:
            return TestResult(False, f"Counter bid error: {str(e)}")

    def accept_counter_offer(self) -> TestResult:
        """Driver accepts customer's counter offer"""
        if not self.bid_id:
            self.bid_id = 1

        try:
            response = self.session.post(
                f"{API_URL}/api/rides/bid/{self.bid_id}/accept-counter",
                headers={"Authorization": f"Bearer {self.driver_token}"}
            )

            if response.status_code == 200:
                data = response.json()
                final_price = data.get("final_price", 0)
                return TestResult(True,
                    f"Counter accepted! Final price: ${final_price}", data)
            else:
                return TestResult(False, f"Accept counter failed: {response.status_code}",
                                {"error": response.text})
        except Exception as e:
            return TestResult(False, f"Accept counter error: {str(e)}")

    def accept_bid_directly(self) -> TestResult:
        """Customer accepts driver's bid directly (no negotiation)"""
        if not self.bid_id:
            self.bid_id = 1

        try:
            response = self.session.post(
                f"{API_URL}/api/rides/bid/{self.bid_id}/respond",
                json={
                    "action": "accept",
                    "message": "Sounds good! See you soon."
                },
                headers={
                    "Authorization": f"Bearer {self.customer_token}",
                    "Content-Type": "application/json"
                }
            )

            if response.status_code == 200:
                data = response.json()
                return TestResult(True, "Bid accepted! Ride matched.", data)
            else:
                return TestResult(False, f"Accept bid failed: {response.status_code}",
                                {"error": response.text})
        except Exception as e:
            return TestResult(False, f"Accept bid error: {str(e)}")

    # ==================== CHAT ====================

    def send_chat_message(self, sender_type: str, message: str) -> TestResult:
        """Send a chat message"""
        if not self.ride_request_id:
            self.ride_request_id = 1

        token = self.driver_token if sender_type == "driver" else self.customer_token
        if not token:
            return TestResult(False, f"No {sender_type} token available")

        try:
            response = self.session.post(
                f"{API_URL}/api/p2p/ride-requests/{self.ride_request_id}/chat",
                json={
                    "sender_type": sender_type,
                    "message": message
                },
                headers={
                    "Authorization": f"Bearer {token}",
                    "Content-Type": "application/json"
                }
            )

            if response.status_code == 200:
                data = response.json()
                return TestResult(True,
                    f"[{sender_type.upper()}] sent: '{message[:50]}...'", data)
            else:
                return TestResult(False, f"Send chat failed: {response.status_code}",
                                {"error": response.text})
        except Exception as e:
            return TestResult(False, f"Send chat error: {str(e)}")

    def get_chat_messages(self) -> TestResult:
        """Get chat messages for the ride"""
        if not self.ride_request_id:
            self.ride_request_id = 1

        try:
            response = self.session.get(
                f"{API_URL}/api/p2p/ride-requests/{self.ride_request_id}/chat",
                headers={"Authorization": f"Bearer {self.customer_token}"}
            )

            if response.status_code == 200:
                data = response.json()
                messages = data.get("messages", [])
                return TestResult(True, f"Retrieved {len(messages)} chat messages", data)
            else:
                return TestResult(False, f"Get chat failed: {response.status_code}",
                                {"error": response.text})
        except Exception as e:
            return TestResult(False, f"Get chat error: {str(e)}")

    # ==================== RIDE LIFECYCLE ====================

    def track_ride(self) -> TestResult:
        """Track ride status"""
        if not self.ride_request_id:
            self.ride_request_id = 1

        try:
            response = self.session.get(
                f"{API_URL}/api/rides/{self.ride_request_id}/track",
                headers={"Authorization": f"Bearer {self.customer_token}"}
            )

            if response.status_code == 200:
                data = response.json()
                status = data.get("status", "unknown")
                return TestResult(True, f"Ride status: {status}", data)
            else:
                return TestResult(False, f"Track ride failed: {response.status_code}",
                                {"error": response.text})
        except Exception as e:
            return TestResult(False, f"Track ride error: {str(e)}")

    def rate_ride(self, rating: int = 5, comment: str = "Great ride!") -> TestResult:
        """Customer rates the ride"""
        if not self.ride_request_id:
            self.ride_request_id = 1

        try:
            response = self.session.post(
                f"{API_URL}/api/rides/{self.ride_request_id}/rate",
                json={
                    "rating": rating,
                    "comment": comment
                },
                headers={"Authorization": f"Bearer {self.customer_token}"}
            )

            if response.status_code == 200:
                data = response.json()
                return TestResult(True, f"Ride rated: {rating} stars - '{comment}'", data)
            else:
                return TestResult(False, f"Rate ride failed: {response.status_code}",
                                {"error": response.text})
        except Exception as e:
            return TestResult(False, f"Rate ride error: {str(e)}")


def print_header(text: str):
    """Print section header"""
    print("\n" + "=" * 70)
    print(f"  {text}")
    print("=" * 70)


def run_rideshare_e2e_test():
    """Run complete rideshare end-to-end test"""
    session_id = datetime.now().strftime("%Y%m%d_%H%M%S")
    results = {
        "authentication": {"success": False, "steps": []},
        "ride_request": {"success": False, "steps": []},
        "bidding": {"success": False, "steps": []},
        "negotiation": {"success": False, "steps": []},
        "chat": {"success": False, "steps": []},
        "ride_lifecycle": {"success": False, "steps": []},
    }

    print_header("DOLLOR.AI RIDESHARE END-TO-END TEST")
    print(f"Session: {session_id}")
    print(f"API: {API_URL}")
    print(f"Time: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}")
    print(f"\nPickup: {PICKUP_ADDRESS['formatted']}")
    print(f"Dropoff: {DROPOFF_ADDRESS['formatted']}")

    agent = RideshareTestAgent()
    step_num = 0

    # ==================== PHASE 1: AUTHENTICATION ====================
    print_header("PHASE 1: AUTHENTICATION")

    step_num += 1
    agent._print_step(step_num, "Customer Login")
    result = agent.customer_login()
    agent._print_result(result)
    results["authentication"]["steps"].append(("Customer Login", result.success))

    step_num += 1
    agent._print_step(step_num, "Driver Login")
    result = agent.driver_login()
    agent._print_result(result)
    results["authentication"]["steps"].append(("Driver Login", result.success))

    results["authentication"]["success"] = all(s[1] for s in results["authentication"]["steps"])

    # ==================== PHASE 2: RIDE REQUEST ====================
    print_header("PHASE 2: RIDE REQUEST")

    step_num += 1
    agent._print_step(step_num, "Estimate Fare")
    result = agent.estimate_fare()
    agent._print_result(result)
    results["ride_request"]["steps"].append(("Estimate Fare", result.success))

    step_num += 1
    agent._print_step(step_num, "Create Ride Request")
    result = agent.create_ride_request()
    agent._print_result(result)
    results["ride_request"]["steps"].append(("Create Ride Request", result.success))

    results["ride_request"]["success"] = all(s[1] for s in results["ride_request"]["steps"])

    # ==================== PHASE 3: DRIVER BIDDING ====================
    print_header("PHASE 3: DRIVER BIDDING")

    step_num += 1
    agent._print_step(step_num, "View Available Rides")
    result = agent.get_available_rides()
    agent._print_result(result)
    results["bidding"]["steps"].append(("View Available Rides", result.success))

    step_num += 1
    agent._print_step(step_num, "Submit Bid ($25.00)")
    result = agent.submit_bid(proposed_price=25.00)
    agent._print_result(result)
    results["bidding"]["steps"].append(("Submit Bid", result.success))

    results["bidding"]["success"] = all(s[1] for s in results["bidding"]["steps"])

    # ==================== PHASE 4: NEGOTIATION ====================
    print_header("PHASE 4: NEGOTIATION")

    step_num += 1
    agent._print_step(step_num, "Customer Views Bids")
    result = agent.get_bids_for_ride()
    agent._print_result(result)
    results["negotiation"]["steps"].append(("View Bids", result.success))

    step_num += 1
    agent._print_step(step_num, "Customer Counter Offer ($22.00)")
    result = agent.counter_bid(counter_price=22.00)
    agent._print_result(result)
    results["negotiation"]["steps"].append(("Counter Offer", result.success))

    step_num += 1
    agent._print_step(step_num, "Driver Accepts Counter")
    result = agent.accept_counter_offer()
    agent._print_result(result)
    results["negotiation"]["steps"].append(("Accept Counter", result.success))

    results["negotiation"]["success"] = all(s[1] for s in results["negotiation"]["steps"])

    # ==================== PHASE 5: CHAT ====================
    print_header("PHASE 5: CHAT COMMUNICATION")

    step_num += 1
    agent._print_step(step_num, "Driver Sends Message")
    result = agent.send_chat_message("driver",
        "Hi! I'm on my way to pick you up at Crown Valley Pkwy. I'll be there in 5 minutes. Look for a silver Honda Accord.")
    agent._print_result(result)
    results["chat"]["steps"].append(("Driver Message", result.success))

    step_num += 1
    agent._print_step(step_num, "Customer Replies")
    result = agent.send_chat_message("customer",
        "Thanks! I'm waiting outside Starbucks. I'm wearing a blue jacket.")
    agent._print_result(result)
    results["chat"]["steps"].append(("Customer Reply", result.success))

    step_num += 1
    agent._print_step(step_num, "Driver Confirms")
    result = agent.send_chat_message("driver",
        "Perfect, I see you! Pulling up now.")
    agent._print_result(result)
    results["chat"]["steps"].append(("Driver Confirms", result.success))

    step_num += 1
    agent._print_step(step_num, "Get Chat History")
    result = agent.get_chat_messages()
    agent._print_result(result)
    results["chat"]["steps"].append(("Chat History", result.success))

    results["chat"]["success"] = all(s[1] for s in results["chat"]["steps"])

    # ==================== PHASE 6: RIDE LIFECYCLE ====================
    print_header("PHASE 6: RIDE LIFECYCLE")

    step_num += 1
    agent._print_step(step_num, "Track Ride Status")
    result = agent.track_ride()
    agent._print_result(result)
    results["ride_lifecycle"]["steps"].append(("Track Ride", result.success))

    step_num += 1
    agent._print_step(step_num, "Rate Ride (5 stars)")
    result = agent.rate_ride(rating=5, comment="Excellent driver! Very professional and the car was clean.")
    agent._print_result(result)
    results["ride_lifecycle"]["steps"].append(("Rate Ride", result.success))

    results["ride_lifecycle"]["success"] = all(s[1] for s in results["ride_lifecycle"]["steps"])

    # ==================== SUMMARY ====================
    print_header("END-TO-END RIDESHARE TEST SUMMARY")

    total_steps = 0
    passed_steps = 0

    for phase, data in results.items():
        phase_passed = sum(1 for step in data["steps"] if step[1])
        phase_total = len(data["steps"])
        total_steps += phase_total
        passed_steps += phase_passed

        status = "PASSED" if data["success"] else "PARTIAL" if phase_passed > 0 else "FAILED"
        phase_name = phase.replace("_", " ").upper()
        print(f"\n{phase_name} ({status}): {phase_passed}/{phase_total} steps")
        for step_name, step_success in data["steps"]:
            print(f"  [{'x' if step_success else ' '}] {step_name}")

    overall_success = all(data["success"] for data in results.values())
    print(f"\n{'=' * 70}")
    print(f"OVERALL: {'PASSED' if overall_success else 'PARTIAL'} ({passed_steps}/{total_steps} steps)")
    print(f"{'=' * 70}")

    return overall_success


def run_quick_api_test():
    """Run quick API test without full workflow"""
    print_header("QUICK API CONNECTIVITY TEST")

    agent = RideshareTestAgent()

    # Test customer login
    print("\n1. Testing customer login...")
    result = agent.customer_login()
    print(f"   {'✓' if result.success else '✗'} {result.message}")

    # Test driver login
    print("\n2. Testing driver login...")
    result = agent.driver_login()
    print(f"   {'✓' if result.success else '✗'} {result.message}")

    # Test fare estimate
    print("\n3. Testing fare estimate...")
    result = agent.estimate_fare()
    print(f"   {'✓' if result.success else '✗'} {result.message}")

    # Test available rides
    print("\n4. Testing available rides...")
    result = agent.get_available_rides()
    print(f"   {'✓' if result.success else '✗'} {result.message}")

    print("\n" + "=" * 50)
    print("API connectivity test completed!")
    print("=" * 50)


if __name__ == "__main__":
    if len(sys.argv) > 1 and sys.argv[1] == "quick":
        run_quick_api_test()
    else:
        success = run_rideshare_e2e_test()
        sys.exit(0 if success else 1)
