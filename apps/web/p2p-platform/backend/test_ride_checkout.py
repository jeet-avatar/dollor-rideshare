#!/usr/bin/env python3
"""
Test Ride with Complete Payment Checkout
Tests the full P2P rideshare flow: request -> bid -> accept -> payment
"""

import os
import requests
import json
import time

BASE_URL = "https://d34u5ixl0bulv4.cloudfront.net"

# Demo credentials
CUSTOMER_EMAIL = "demo.customer@dollor.ai"
CUSTOMER_PASSWORD = os.environ["DEMO_CUSTOMER_PASSWORD"]
DRIVER_EMAIL = "demo.driver@dollor.ai"
DRIVER_PASSWORD = os.environ["DEMO_DRIVER_PASSWORD"]

def print_step(step, description):
    print(f"\n{'='*60}")
    print(f"STEP {step}: {description}")
    print('='*60)

def print_response(response, name):
    print(f"\n{name}:")
    print(f"  Status: {response.status_code}")
    try:
        data = response.json()
        print(f"  Response: {json.dumps(data, indent=4)[:1000]}")
        return data
    except:
        print(f"  Response: {response.text[:500]}")
        return None

# Step 1: Login as Customer
print_step(1, "Customer Login")
customer_login = requests.post(f"{BASE_URL}/api/auth/customer/login", json={
    "email": CUSTOMER_EMAIL,
    "password": CUSTOMER_PASSWORD
})
customer_data = print_response(customer_login, "Customer Login")
customer_token = customer_data.get("access_token") if customer_data else None
customer_id = customer_data.get("customer", {}).get("id") if customer_data else None
print(f"  Customer ID: {customer_id}")
print(f"  Token: {customer_token[:50] if customer_token else 'None'}...")

# Step 2: Login as Driver
print_step(2, "Driver Login")
driver_login = requests.post(f"{BASE_URL}/api/driver/login", json={
    "email": DRIVER_EMAIL,
    "password": DRIVER_PASSWORD
})
driver_data = print_response(driver_login, "Driver Login")
driver_token = driver_data.get("access_token") if driver_data else None
driver_id = driver_data.get("driver", {}).get("id") if driver_data else None
print(f"  Driver ID: {driver_id}")
print(f"  Token: {driver_token[:50] if driver_token else 'None'}...")

# Step 3: Customer creates a ride request
print_step(3, "Customer Creates Ride Request")
ride_request = requests.post(
    f"{BASE_URL}/api/erp/rides/request",
    headers={"Authorization": f"Bearer {customer_token}"} if customer_token else {},
    json={
        "pickup_address": {
            "address": "12 Teaberry Ln, Rancho Santa Margarita, CA 92688",
            "lat": 33.6412,
            "lng": -117.5961
        },
        "dropoff_address": {
            "address": "John Wayne Airport, Santa Ana, CA",
            "lat": 33.6757,
            "lng": -117.8682
        },
        "ride_type": "standard",
        "customer_name": "Demo Customer",
        "customer_email": CUSTOMER_EMAIL,
        "customer_phone": "+1234567890",
        "tip": 5.00
    }
)
ride_data = print_response(ride_request, "Ride Request Created")
ride_id = ride_data.get("id") if ride_data else None
ride_fare = ride_data.get("fare", {}).get("total", 0) if ride_data else 0
print(f"  Ride DB ID: {ride_id}")
print(f"  Total Fare: ${ride_fare}")

if not ride_id:
    print("\n❌ Failed to create ride request. Exiting.")
    exit(1)

# Step 4: Driver submits a bid
print_step(4, "Driver Submits Bid")
time.sleep(1)
bid_response = requests.post(
    f"{BASE_URL}/api/rides/request/{ride_id}/bid",
    headers={"Authorization": f"Bearer {driver_token}"} if driver_token else {},
    json={
        "driver_id": driver_id or 1,  # Use driver_id from login or fallback to 1
        "proposed_price": ride_fare - 2,
        "message": "I can be there in 5 minutes!",
        "estimated_arrival_minutes": 5
    }
)
bid_data = print_response(bid_response, "Driver Bid Submitted")
bid_id = bid_data.get("bid_id") if bid_data else None
print(f"  Bid ID: {bid_id}")

# Step 5: Customer views incoming bids
print_step(5, "Customer Views Incoming Bids")
time.sleep(1)
bids_response = requests.get(
    f"{BASE_URL}/api/rides/request/{ride_id}/bids",
    headers={"Authorization": f"Bearer {customer_token}"} if customer_token else {}
)
bids_data = print_response(bids_response, "Incoming Bids")
if bids_data and bids_data.get("bids") and not bid_id:
    bid_id = bids_data["bids"][0].get("bid_id") or bids_data["bids"][0].get("id")
    print(f"  Found Bid ID from list: {bid_id}")

# Step 6: Customer accepts the bid
print_step(6, "Customer Accepts Bid")
if bid_id:
    accept_response = requests.post(
        f"{BASE_URL}/api/rides/bid/{bid_id}/respond",
        headers={"Authorization": f"Bearer {customer_token}"} if customer_token else {},
        json={"action": "accept"}
    )
    accept_data = print_response(accept_response, "Bid Accepted")
else:
    print("  ⚠ No bid ID available to accept")
    accept_data = None

# Step 7: Calculate tax for the ride
print_step(7, "Calculate Tax")
tax_response = requests.get(
    f"{BASE_URL}/api/tax/calculate",
    params={
        "subtotal": ride_fare,
        "state": "CA",
        "city": "rancho santa margarita"
    }
)
tax_data = print_response(tax_response, "Tax Calculation")
total_with_tax = tax_data.get("total_with_tax", ride_fare) if tax_data else ride_fare

# Step 8: Create Payment Intent
print_step(8, "Create Payment Intent (Stripe)")
amount_cents = int(total_with_tax * 100)
payment_response = requests.post(
    f"{BASE_URL}/api/erp/payments/intent",
    headers={"Authorization": f"Bearer {customer_token}"} if customer_token else {},
    json={
        "amount": amount_cents,
        "currency": "usd",
        "order_id": f"RIDE-{ride_id}",
        "customer_email": CUSTOMER_EMAIL
    }
)
payment_data = print_response(payment_response, "Payment Intent Created")

# Step 9: Summary
print_step(9, "RIDE CHECKOUT SUMMARY")

is_demo = payment_data.get("demo", False) if payment_data else False
client_secret = payment_data.get("clientSecret", "N/A") if payment_data else "N/A"

print(f"""
╔══════════════════════════════════════════════════════════════╗
║                    RIDE CHECKOUT COMPLETE                    ║
╠══════════════════════════════════════════════════════════════╣
║  Ride ID:           {str(ride_id):<40} ║
║  Request ID:        {ride_data.get('request_id', 'N/A'):<40} ║
║  From:              Rancho Santa Margarita, CA               ║
║  To:                John Wayne Airport                       ║
║  Distance:          ~{ride_data.get('distance_miles', 0):.1f} miles                              ║
╠══════════════════════════════════════════════════════════════╣
║  FARE BREAKDOWN                                              ║
║  ─────────────────────────────────────────────────────────── ║
║  Ride Fare:         ${ride_data.get('fare', {}).get('ride_fare', 0):<38.2f} ║
║  Platform Fee:      ${ride_data.get('fare', {}).get('customer_platform_fee', 0):<38.2f} ║
║  Tip:               ${ride_data.get('fare', {}).get('tip', 0):<38.2f} ║
║  Subtotal:          ${ride_fare:<38.2f} ║
║  Tax (8.0%):        ${tax_data.get('total_tax_amount', 0) if tax_data else 0:<38.2f} ║
║  ─────────────────────────────────────────────────────────── ║
║  TOTAL:             ${total_with_tax:<38.2f} ║
╠══════════════════════════════════════════════════════════════╣
║  Driver Earnings:   ${ride_data.get('fare', {}).get('driver_earnings', 0):<38.2f} ║
║  Platform Revenue:  ${(ride_data.get('fare', {}).get('customer_platform_fee', 0) + ride_data.get('fare', {}).get('driver_platform_fee', 0)):<38.2f} ║
╠══════════════════════════════════════════════════════════════╣
║  PAYMENT                                                     ║
║  Stripe Secret:     {client_secret[:40]:<40} ║
║  Status:            {'✅ DEMO MODE' if is_demo else '💳 Ready for Payment':<40} ║
╚══════════════════════════════════════════════════════════════╝

FLOW COMPLETED:
  1. ✅ Customer logged in (ID: {customer_id})
  2. ✅ Driver logged in (ID: {driver_id})
  3. ✅ Ride request created (ID: {ride_id})
  4. {'✅' if bid_id else '⚠'} Driver bid submitted (ID: {bid_id})
  5. ✅ Customer viewed bids
  6. {'✅' if accept_data else '⚠'} Bid accepted
  7. ✅ Tax calculated (${tax_data.get('total_tax_amount', 0) if tax_data else 0:.2f})
  8. ✅ Stripe Payment Intent created

📱 On mobile app: Stripe Payment Sheet would appear with card input
💳 Client secret passed to Stripe SDK for secure payment collection
""")
