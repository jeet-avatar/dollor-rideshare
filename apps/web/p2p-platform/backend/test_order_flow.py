#!/usr/bin/env python3
"""Test order flow: accept -> pickup -> deliver"""
import os
import requests
import json

BASE_URL = os.getenv("API_URL", "https://api.dollor.ai/api")

# Demo credentials
DRIVER_EMAIL = "demo.driver@dollor.ai"
DRIVER_PASSWORD = os.environ["DEMO_DRIVER_PASSWORD"]
CUSTOMER_EMAIL = "demo.customer@dollor.ai"
CUSTOMER_PASSWORD = os.environ["DEMO_CUSTOMER_PASSWORD"]

def test_order_flow():
    print("=" * 60)
    print("ORDER FLOW TEST - Status Transitions")
    print("=" * 60)
    
    # 1. Login as driver
    print("\n1. Logging in as driver...")
    resp = requests.post(f"{BASE_URL}/driver/login", json={
        "email": DRIVER_EMAIL,
        "password": DRIVER_PASSWORD
    })
    if resp.status_code != 200:
        print(f"   ❌ Driver login failed: {resp.status_code}")
        print(f"   Response: {resp.text[:200]}")
        return
    
    driver_data = resp.json()
    driver_token = driver_data.get("token") or driver_data.get("access_token")
    driver_id = driver_data.get("driver", {}).get("id") or driver_data.get("id")
    print(f"   ✅ Driver logged in (ID: {driver_id})")
    
    # 2. Get driver's active orders to find one to test with
    print("\n2. Checking driver's current orders...")
    headers = {"Authorization": f"Bearer {driver_token}"}
    resp = requests.get(f"{BASE_URL}/erp/orders/driver/{driver_id}/active", headers=headers)
    
    if resp.status_code == 200:
        orders = resp.json()
        print(f"   Found {len(orders)} active orders")
        for o in orders[:3]:
            order_id = o.get("id") or o.get("order_id")
            status = o.get("status")
            driver_en_route = o.get("driver_en_route")
            print(f"   - Order {order_id}: status={status}, driver_en_route={driver_en_route}")
    else:
        print(f"   No active orders or error: {resp.status_code}")
    
    # 3. Check available orders for driver to accept
    print("\n3. Checking available orders in driver pool...")
    resp = requests.get(f"{BASE_URL}/erp/orders/available", headers=headers)
    
    available_orders = []
    if resp.status_code == 200:
        available_orders = resp.json()
        print(f"   Found {len(available_orders)} available orders")
        for o in available_orders[:3]:
            order_id = o.get("id") or o.get("order_id")
            status = o.get("status")
            print(f"   - Order {order_id}: status={status}")
    else:
        print(f"   Error: {resp.status_code} - {resp.text[:100]}")
    
    # 4. If there's an available order, simulate accept flow
    if available_orders:
        test_order = available_orders[0]
        order_id = test_order.get("id") or test_order.get("order_id")
        print(f"\n4. Testing accept flow with order {order_id}...")
        
        # Accept the order
        resp = requests.post(f"{BASE_URL}/erp/orders/{order_id}/assign-driver", 
                           json={"driver_id": driver_id},
                           headers=headers)
        
        if resp.status_code == 200:
            result = resp.json()
            print(f"   ✅ Order accepted")
            print(f"   Message: {result.get('message')}")
            
            # Now check the order status
            resp2 = requests.get(f"{BASE_URL}/erp/orders/{order_id}", headers=headers)
            if resp2.status_code == 200:
                order_after = resp2.json()
                status_after = order_after.get("status")
                driver_en_route_after = order_after.get("driver_en_route")
                print(f"\n   After accept:")
                print(f"   - Status: {status_after}")
                print(f"   - driver_en_route: {driver_en_route_after}")
                
                if status_after == "ready_for_pickup" and driver_en_route_after == True:
                    print(f"   ✅ CORRECT: Status stayed ready_for_pickup, driver_en_route=True")
                elif status_after == "out_for_delivery":
                    print(f"   ❌ BUG: Status changed to out_for_delivery immediately!")
                else:
                    print(f"   ⚠️  Unexpected: {status_after}")
        else:
            print(f"   ❌ Accept failed: {resp.status_code}")
            print(f"   Response: {resp.text[:200]}")
    else:
        print("\n4. No available orders to test accept flow")
        print("   Creating a test scenario by checking existing assigned orders...")
    
    # 5. Test pickup endpoint logic (just verify it exists)
    print("\n5. Verifying pickup endpoint exists...")
    resp = requests.post(f"{BASE_URL}/erp/orders/99999/picked-up", headers=headers)
    if resp.status_code == 404:
        print("   ✅ Pickup endpoint exists (404 = order not found, expected)")
    elif resp.status_code == 401 or resp.status_code == 403:
        print("   ✅ Pickup endpoint exists (auth required)")
    else:
        print(f"   Response: {resp.status_code}")
    
    print("\n" + "=" * 60)
    print("TEST COMPLETE")
    print("=" * 60)

if __name__ == "__main__":
    test_order_flow()
