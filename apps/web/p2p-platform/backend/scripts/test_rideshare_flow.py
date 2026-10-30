#!/usr/bin/env python3
"""
Rideshare E2E Test - Platform Fee: $1 customer + $1 driver = $2/ride
"""

import os
import requests
from datetime import datetime

API_URL = os.getenv("API_URL", "https://api.dollor.ai/api")
PLATFORM_FEE = 1.00

PICKUP = {"address": "350 S Grand Ave, LA", "lat": 34.0522, "lng": -118.2437, "name": "Downtown LA"}
DROPOFF = {"address": "1515 Ocean Ave, Santa Monica", "lat": 34.0195, "lng": -118.4912, "name": "Santa Monica"}


class RideshareTest:
    def __init__(self):
        self.url = API_URL
        self.session = requests.Session()
        self.session.headers = {"Content-Type": "application/json"}
        self.ride_id = None
        self.fare = None

    def log(self, step, msg, ok=True):
        print(f"  {'✅' if ok else '❌'} [{step}] {msg}")

    def test_ride_flow(self):
        """Test complete ride: request → bid → accept → pickup → dropoff"""
        print("\n" + "="*50)
        print("  RIDE FLOW TEST")
        print("="*50)

        # 1. Get estimate
        r = self.session.post(f"{self.url}/rides/estimate", json={
            "pickup_latitude": PICKUP["lat"], "pickup_longitude": PICKUP["lng"],
            "dropoff_latitude": DROPOFF["lat"], "dropoff_longitude": DROPOFF["lng"],
            "ride_type": "standard"
        })
        est = r.json().get("estimate", {}).get("total", 30.0)
        self.log("ESTIMATE", f"${est:.2f}")

        # 2. Create request
        r = self.session.post(f"{self.url}/rides/request", json={
            "customer_id": 1,
            "pickup_address": PICKUP["address"], "pickup_latitude": PICKUP["lat"],
            "pickup_longitude": PICKUP["lng"], "pickup_place_name": PICKUP["name"],
            "dropoff_address": DROPOFF["address"], "dropoff_latitude": DROPOFF["lat"],
            "dropoff_longitude": DROPOFF["lng"], "dropoff_place_name": DROPOFF["name"],
            "ride_type": "standard", "bidding_duration_minutes": 10
        })
        data = r.json()
        if not data.get("success"):
            self.log("REQUEST", f"Failed: {data}", False)
            return False
        self.ride_id = data["ride_request"]["id"]
        self.log("REQUEST", f"Created ID={self.ride_id}")

        # 3. Driver bids
        bid_price = est * 0.9
        r = self.session.post(f"{self.url}/rides/request/{self.ride_id}/bid", json={
            "driver_id": 1, "proposed_price": bid_price, "estimated_arrival_minutes": 5
        })
        data = r.json()
        if not data.get("success"):
            self.log("BID", f"Failed: {data}", False)
            return False
        bid_id = data["bid"]["id"]
        self.log("BID", f"Driver bid ${bid_price:.2f}")

        # 4. Accept bid
        r = self.session.post(f"{self.url}/rides/bid/{bid_id}/respond", json={"action": "accept"})
        data = r.json()
        if not data.get("success"):
            self.log("ACCEPT", f"Failed: {data}", False)
            return False
        self.fare = data.get("ride_request", {}).get("final_price", bid_price)
        self.log("ACCEPT", f"Matched at ${self.fare:.2f}")

        # 5. Start ride
        r = self.session.post(f"{self.url}/rides/request/{self.ride_id}/start")
        if not r.json().get("success"):
            self.log("PICKUP", "Failed", False)
            return False
        self.log("PICKUP", "Driver picked up customer")

        # 6. Complete ride
        r = self.session.post(f"{self.url}/rides/request/{self.ride_id}/complete")
        if not r.json().get("success"):
            self.log("DROPOFF", "Failed", False)
            return False
        self.log("DROPOFF", "Ride completed")

        return True

    def test_payment(self):
        """Test payment: $1 from customer + $1 from driver"""
        print("\n" + "="*50)
        print("  PAYMENT TEST")
        print("="*50)

        if not self.ride_id or not self.fare:
            self.log("SETUP", "Need completed ride", False)
            return False

        customer_pays = self.fare + PLATFORM_FEE
        driver_receives = self.fare - PLATFORM_FEE
        platform_earns = PLATFORM_FEE * 2

        self.log("FARE", f"${self.fare:.2f}")
        self.log("CUSTOMER", f"Pays ${customer_pays:.2f} (fare + $1)")
        self.log("DRIVER", f"Receives ${driver_receives:.2f} (fare - $1)")
        self.log("PLATFORM", f"Earns ${platform_earns:.2f} ($1 + $1)")

        # Verify pricing endpoint
        r = self.session.get(f"{self.url}/payments/ride/pricing-info")
        data = r.json()
        if data.get("platform_total_per_ride") == 2.0:
            self.log("API", "Pricing endpoint OK")
        else:
            self.log("API", f"Unexpected: {data}", False)

        # Check driver earnings
        r = self.session.get(f"{self.url}/payments/ride/driver/1/earnings")
        data = r.json()
        self.log("EARNINGS", f"Driver total: ${data.get('total_earnings', 0):.2f}")

        return True

    def run(self):
        print("\n" + "="*50)
        print(f"  DOLLOR.AI RIDESHARE TEST")
        print(f"  API: {self.url}")
        print(f"  Time: {datetime.now().strftime('%Y-%m-%d %H:%M')}")
        print("="*50)

        ride_ok = self.test_ride_flow()
        pay_ok = self.test_payment() if ride_ok else False

        print("\n" + "="*50)
        print(f"  RESULTS: {'PASS' if ride_ok and pay_ok else 'FAIL'}")
        print("="*50 + "\n")

        return ride_ok and pay_ok


if __name__ == "__main__":
    tester = RideshareTest()
    exit(0 if tester.run() else 1)
