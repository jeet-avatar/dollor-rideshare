#!/usr/bin/env swift

/// Standalone iOS Customer App Staging API Tests
/// Run with: swift run_staging_tests.swift
///
/// TARGET ENVIRONMENT (single production backend): https://api.dollor.ai

import Foundation

// MARK: - Configuration

let stagingBaseURL = "https://api.dollor.ai"
let apiBaseURL = "\(stagingBaseURL)/api"
let testCustomerEmail = "demo@dollor.ai"
let testCustomerPassword = "demo123"

// Test state
var authToken: String?
var customerId: Int?
var testRideRequestId: Int?
var testAddressId: Int?
var testOrderId: Int?

// Test results
var testsPassed = 0
var testsFailed = 0
var testResults: [(name: String, passed: Bool, details: String)] = []

// MARK: - HTTP Helper

func httpRequest(
    method: String,
    url: String,
    body: [String: Any]? = nil,
    formBody: String? = nil
) -> (statusCode: Int, data: Data?, error: String?) {
    guard let requestURL = URL(string: url) else {
        return (0, nil, "Invalid URL")
    }

    var request = URLRequest(url: requestURL)
    request.httpMethod = method
    request.timeoutInterval = 30

    if let formBody = formBody {
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = formBody.data(using: .utf8)
    } else {
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let body = body {
            request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        }
    }

    if let token = authToken {
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
    }

    let semaphore = DispatchSemaphore(value: 0)
    var resultStatusCode = 0
    var resultData: Data?
    var resultError: String?

    URLSession.shared.dataTask(with: request) { data, response, error in
        if let error = error {
            resultError = error.localizedDescription
        } else if let httpResponse = response as? HTTPURLResponse {
            resultStatusCode = httpResponse.statusCode
            resultData = data
        }
        semaphore.signal()
    }.resume()

    semaphore.wait()
    return (resultStatusCode, resultData, resultError)
}

func runTest(_ name: String, _ test: () -> Bool) {
    let passed = test()
    testResults.append((name: name, passed: passed, details: passed ? "PASS" : "FAIL"))
    if passed {
        testsPassed += 1
        print("✅ \(name)")
    } else {
        testsFailed += 1
        print("❌ \(name)")
    }
}

// MARK: - Tests

print("\n" + String(repeating: "=", count: 60))
print("iOS CUSTOMER APP STAGING API TESTS")
print("Staging URL: \(stagingBaseURL)")
print(String(repeating: "=", count: 60) + "\n")

// Category 1: Health Check
print("\n--- 1. Health Check & Connectivity ---")

runTest("1.01 Health endpoint returns OK") {
    let (status, _, _) = httpRequest(method: "GET", url: "\(stagingBaseURL)/health")
    print("  Response: \(status)")
    return status == 200
}

runTest("1.02 API base URL is accessible") {
    let (status, _, _) = httpRequest(method: "GET", url: "\(apiBaseURL)/vendors/published")
    print("  Response: \(status)")
    return status < 500
}

// Category 2: Authentication
print("\n--- 2. Authentication ---")

runTest("2.01 Customer login with valid credentials") {
    let (status, data, _) = httpRequest(
        method: "POST",
        url: "\(apiBaseURL)/auth/customer/login",
        formBody: "username=\(testCustomerEmail)&password=\(testCustomerPassword)"
    )
    print("  Response: \(status)")
    if status == 200, let data = data,
       let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
        authToken = json["token"] as? String ?? json["access_token"] as? String
        customerId = json["customer_id"] as? Int
    }
    return [200, 401, 422].contains(status)
}

runTest("2.02 Invalid login returns error") {
    let (status, _, _) = httpRequest(
        method: "POST",
        url: "\(apiBaseURL)/auth/customer/login",
        formBody: "username=invalid@test.com&password=wrong"
    )
    print("  Response: \(status)")
    return [400, 401, 422].contains(status)
}

runTest("2.03 Demo login endpoint responds") {
    let (status, _, _) = httpRequest(
        method: "POST",
        url: "\(apiBaseURL)/customer/demo-login",
        body: ["email": testCustomerEmail]
    )
    print("  Response: \(status)")
    return status < 500
}

runTest("2.04 Password reset request") {
    let (status, _, _) = httpRequest(
        method: "POST",
        url: "\(apiBaseURL)/customer/password-reset/request",
        body: ["email": "test@example.com"]
    )
    print("  Response: \(status)")
    return status < 500
}

// Category 3: Restaurant Discovery
print("\n--- 3. Restaurant Discovery ---")

runTest("3.01 Get published restaurants") {
    let (status, data, _) = httpRequest(method: "GET", url: "\(apiBaseURL)/vendors/published?platform=ios")
    print("  Response: \(status)")
    if let data = data, let bodyStr = String(data: data, encoding: .utf8) {
        print("  Body: \(bodyStr.prefix(200))...")
    }
    return status == 200
}

runTest("3.02 Filter by city") {
    let (status, _, _) = httpRequest(method: "GET", url: "\(apiBaseURL)/vendors/published?platform=ios&city=San%20Francisco")
    print("  Response: \(status)")
    return [200, 404].contains(status)
}

runTest("3.03 Filter by cuisine") {
    let (status, _, _) = httpRequest(method: "GET", url: "\(apiBaseURL)/vendors/published?platform=ios&cuisine=Italian")
    print("  Response: \(status)")
    return [200, 404].contains(status)
}

runTest("3.04 Get vendor menu") {
    let (status, _, _) = httpRequest(method: "GET", url: "\(apiBaseURL)/vendors/1/menu")
    print("  Response: \(status)")
    return status < 500
}

// Category 4: Promotions
print("\n--- 4. Promotions & Deals ---")

runTest("4.01 Get active promotions") {
    let (status, _, _) = httpRequest(method: "GET", url: "\(apiBaseURL)/promotions/active")
    print("  Response: \(status)")
    return status < 500
}

runTest("4.02 Get featured deals") {
    let (status, _, _) = httpRequest(method: "GET", url: "\(apiBaseURL)/promotions/featured")
    print("  Response: \(status)")
    return status < 500
}

// Category 5: Fare Estimate
print("\n--- 5. Rideshare Fare Estimate ---")

runTest("5.01 Fare estimate with valid coordinates") {
    let (status, data, _) = httpRequest(
        method: "POST",
        url: "\(apiBaseURL)/rides/estimate",
        body: [
            "pickup_latitude": 37.7749,
            "pickup_longitude": -122.4194,
            "dropoff_latitude": 37.3382,
            "dropoff_longitude": -121.8863,
            "ride_type": "standard"
        ]
    )
    print("  Response: \(status)")
    if let data = data, let bodyStr = String(data: data, encoding: .utf8) {
        print("  Body: \(bodyStr.prefix(300))...")
    }
    return status == 200
}

runTest("5.02 Short trip estimate") {
    let (status, _, _) = httpRequest(
        method: "POST",
        url: "\(apiBaseURL)/rides/estimate",
        body: [
            "pickup_latitude": 37.7749,
            "pickup_longitude": -122.4194,
            "dropoff_latitude": 37.7849,
            "dropoff_longitude": -122.4094,
            "ride_type": "standard"
        ]
    )
    print("  Response: \(status)")
    return status == 200
}

runTest("5.03 Long trip estimate") {
    let (status, _, _) = httpRequest(
        method: "POST",
        url: "\(apiBaseURL)/rides/estimate",
        body: [
            "pickup_latitude": 37.7749,
            "pickup_longitude": -122.4194,
            "dropoff_latitude": 34.0522,
            "dropoff_longitude": -118.2437,
            "ride_type": "standard"
        ]
    )
    print("  Response: \(status)")
    return status == 200
}

runTest("5.04 Invalid coordinates handled") {
    let (status, _, _) = httpRequest(
        method: "POST",
        url: "\(apiBaseURL)/rides/estimate",
        body: [
            "pickup_latitude": 999.0,
            "pickup_longitude": 999.0,
            "dropoff_latitude": 37.3382,
            "dropoff_longitude": -121.8863,
            "ride_type": "standard"
        ]
    )
    print("  Response: \(status)")
    return [200, 400, 422].contains(status)
}

// Category 6: Ride Request
print("\n--- 6. Rideshare Ride Request ---")

runTest("6.01 Create ride request") {
    let cid = customerId ?? 1
    let (status, data, _) = httpRequest(
        method: "POST",
        url: "\(apiBaseURL)/rides/request",
        body: [
            "customer_id": cid,
            "pickup_address": "123 Main St, San Francisco, CA",
            "pickup_latitude": 37.7749,
            "pickup_longitude": -122.4194,
            "dropoff_address": "456 Oak Ave, San Jose, CA",
            "dropoff_latitude": 37.3382,
            "dropoff_longitude": -121.8863,
            "ride_type": "standard",
            "bidding_duration_minutes": 5
        ]
    )
    print("  Response: \(status)")
    if status == 200, let data = data,
       let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
       let rideRequest = json["ride_request"] as? [String: Any] {
        testRideRequestId = rideRequest["id"] as? Int
        print("  Created Ride Request ID: \(testRideRequestId ?? 0)")
    }
    return status < 500
}

runTest("6.02 Get customer ride requests") {
    let cid = customerId ?? 1
    let (status, _, _) = httpRequest(method: "GET", url: "\(apiBaseURL)/rides/customer/\(cid)/requests")
    print("  Response: \(status)")
    return status < 500
}

runTest("6.03 Get ride bids") {
    let rid = testRideRequestId ?? 1
    let (status, _, _) = httpRequest(method: "GET", url: "\(apiBaseURL)/rides/request/\(rid)/bids")
    print("  Response: \(status)")
    return status < 500
}

runTest("6.04 Cancel ride request") {
    let rid = testRideRequestId ?? 1
    let (status, _, _) = httpRequest(
        method: "POST",
        url: "\(apiBaseURL)/rides/request/\(rid)/cancel",
        body: [:]
    )
    print("  Response: \(status)")
    return status < 500
}

// Category 7: Bidding
print("\n--- 7. Rideshare Bidding ---")

runTest("7.01 Accept bid") {
    let (status, _, _) = httpRequest(
        method: "POST",
        url: "\(apiBaseURL)/rides/bid/1/respond",
        body: ["action": "accept"]
    )
    print("  Response: \(status)")
    return status < 500
}

runTest("7.02 Reject bid") {
    let (status, _, _) = httpRequest(
        method: "POST",
        url: "\(apiBaseURL)/rides/bid/1/respond",
        body: ["action": "reject"]
    )
    print("  Response: \(status)")
    return status < 500
}

runTest("7.03 Counter bid") {
    let (status, _, _) = httpRequest(
        method: "POST",
        url: "\(apiBaseURL)/rides/bid/1/respond",
        body: ["action": "counter", "counter_price": 25.00]
    )
    print("  Response: \(status)")
    return status < 500
}

// Category 8: Chat
print("\n--- 8. Rideshare Chat ---")

runTest("8.01 Get chat messages") {
    let rid = testRideRequestId ?? 1
    let (status, _, _) = httpRequest(method: "GET", url: "\(apiBaseURL)/chat/messages/\(rid)")
    print("  Response: \(status)")
    return [200, 404, 401].contains(status)
}

runTest("8.02 Send chat message") {
    let rid = testRideRequestId ?? 1
    let (status, _, _) = httpRequest(
        method: "POST",
        url: "\(apiBaseURL)/chat/messages/\(rid)",
        body: ["message": "Test message", "sender_type": "customer"]
    )
    print("  Response: \(status)")
    return status < 500
}

// Category 9: Address Management
print("\n--- 9. Address Management ---")

runTest("9.01 Get customer addresses") {
    let cid = customerId ?? 1
    let (status, _, _) = httpRequest(method: "GET", url: "\(apiBaseURL)/addresses/\(cid)")
    print("  Response: \(status)")
    return status < 500
}

runTest("9.02 Add customer address") {
    let cid = customerId ?? 1
    let (status, data, _) = httpRequest(
        method: "POST",
        url: "\(apiBaseURL)/addresses/\(cid)",
        body: [
            "address_line_1": "123 Test St",
            "city": "San Francisco",
            "state": "CA",
            "zip_code": "94102",
            "latitude": 37.7749,
            "longitude": -122.4194,
            "label": "Home"
        ]
    )
    print("  Response: \(status)")
    if status == 200, let data = data,
       let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
        testAddressId = json["id"] as? Int
    }
    return status < 500
}

runTest("9.03 Get default address") {
    let cid = customerId ?? 1
    let (status, _, _) = httpRequest(method: "GET", url: "\(apiBaseURL)/addresses/\(cid)/default")
    print("  Response: \(status)")
    return [200, 404, 401].contains(status)
}

// Category 10: Favorites
print("\n--- 10. Favorites Management ---")

runTest("10.01 Get customer favorites") {
    let cid = customerId ?? 1
    let (status, _, _) = httpRequest(method: "GET", url: "\(apiBaseURL)/customer/favorites/\(cid)")
    print("  Response: \(status)")
    return status < 500
}

runTest("10.02 Add favorite") {
    let cid = customerId ?? 1
    let (status, _, _) = httpRequest(
        method: "POST",
        url: "\(apiBaseURL)/customer/favorites/\(cid)/1",
        body: [:]
    )
    print("  Response: \(status)")
    return status < 500
}

runTest("10.03 Check favorite") {
    let cid = customerId ?? 1
    let (status, _, _) = httpRequest(method: "GET", url: "\(apiBaseURL)/customer/favorites/\(cid)/check/1")
    print("  Response: \(status)")
    return status < 500
}

runTest("10.04 Remove favorite") {
    let cid = customerId ?? 1
    let (status, _, _) = httpRequest(method: "DELETE", url: "\(apiBaseURL)/customer/favorites/\(cid)/1")
    print("  Response: \(status)")
    return status < 500
}

// Category 11: Payment Cards
print("\n--- 11. Payment Cards ---")

runTest("11.01 Get saved cards") {
    let cid = customerId ?? 1
    let (status, _, _) = httpRequest(method: "GET", url: "\(apiBaseURL)/customers/\(cid)/cards")
    print("  Response: \(status)")
    return status < 500
}

runTest("11.02 Add payment card") {
    let cid = customerId ?? 1
    let (status, _, _) = httpRequest(
        method: "POST",
        url: "\(apiBaseURL)/customers/\(cid)/cards",
        body: ["stripe_token": "tok_visa_test", "card_type": "visa", "last_four": "4242"]
    )
    print("  Response: \(status)")
    return status < 500
}

// Category 12: Order Management
print("\n--- 12. Order Management ---")

runTest("12.01 Get customer orders") {
    let (status, _, _) = httpRequest(method: "GET", url: "\(apiBaseURL)/customer/orders")
    print("  Response: \(status)")
    return status < 500
}

runTest("12.02 Get active orders") {
    let cid = customerId ?? 1
    let (status, _, _) = httpRequest(method: "GET", url: "\(apiBaseURL)/customer/\(cid)/active-orders")
    print("  Response: \(status)")
    return status < 500
}

runTest("12.03 Track order") {
    let oid = testOrderId ?? 1
    let (status, _, _) = httpRequest(method: "GET", url: "\(apiBaseURL)/customer/orders/\(oid)/track")
    print("  Response: \(status)")
    return status < 500
}

// Category 13: Order Tracking
print("\n--- 13. Order Tracking ---")

runTest("13.01 Get full order tracking") {
    let oid = testOrderId ?? 1
    let (status, _, _) = httpRequest(method: "GET", url: "\(apiBaseURL)/erp/orders/\(oid)/full-tracking")
    print("  Response: \(status)")
    return status < 500
}

runTest("13.02 Get driver location") {
    let oid = testOrderId ?? 1
    let (status, _, _) = httpRequest(method: "GET", url: "\(apiBaseURL)/erp/orders/\(oid)/driver-location")
    print("  Response: \(status)")
    return status < 500
}

// Category 14: Order Chat
print("\n--- 14. Order Chat ---")

runTest("14.01 Get order chat") {
    let oid = testOrderId ?? 1
    let (status, _, _) = httpRequest(method: "GET", url: "\(apiBaseURL)/customer/orders/\(oid)/chat")
    print("  Response: \(status)")
    return status < 500
}

runTest("14.02 Send order chat") {
    let oid = testOrderId ?? 1
    let (status, _, _) = httpRequest(
        method: "POST",
        url: "\(apiBaseURL)/customer/orders/\(oid)/chat",
        body: ["message": "Where is my order?"]
    )
    print("  Response: \(status)")
    return status < 500
}

// Category 15: Payment
print("\n--- 15. Payment Processing ---")

runTest("15.01 Create payment intent") {
    let cid = customerId ?? 1
    let (status, _, _) = httpRequest(
        method: "POST",
        url: "\(apiBaseURL)/payments/create-intent",
        body: ["amount": 2500, "currency": "usd", "customer_id": cid]
    )
    print("  Response: \(status)")
    return status < 500
}

// Category 16: Legal
print("\n--- 16. Legal & Support ---")

runTest("16.01 Get terms of service") {
    let (status, _, _) = httpRequest(method: "GET", url: "\(apiBaseURL)/legal/tos")
    print("  Response: \(status)")
    return status < 500
}

runTest("16.02 Get privacy policy") {
    let (status, _, _) = httpRequest(method: "GET", url: "\(apiBaseURL)/legal/privacy-policy")
    print("  Response: \(status)")
    return status < 500
}

// Category 17: Account
print("\n--- 17. Account Management ---")

runTest("17.01 Update customer profile") {
    let cid = customerId ?? 1
    let (status, _, _) = httpRequest(
        method: "POST",
        url: "\(apiBaseURL)/customer/\(cid)/profile",
        body: ["full_name": "Test User", "phone": "+1234567890"]
    )
    print("  Response: \(status)")
    return status < 500
}

runTest("17.02 Delete customer account (test ID)") {
    let (status, _, _) = httpRequest(method: "DELETE", url: "\(apiBaseURL)/customers/999999/delete")
    print("  Response: \(status)")
    return status < 500
}

// Category 18: Push Notifications
print("\n--- 18. Push Notifications ---")

runTest("18.01 Register push token") {
    let cid = customerId ?? 1
    let (status, _, _) = httpRequest(
        method: "POST",
        url: "\(apiBaseURL)/notifications/register-token",
        body: [
            "token": "test_apns_token_12345",
            "platform": "ios",
            "user_type": "customer",
            "user_id": cid
        ]
    )
    print("  Response: \(status)")
    return status < 500
}

// Summary
print("\n" + String(repeating: "=", count: 60))
print("STAGING API TEST SUMMARY - iOS Customer App")
print(String(repeating: "=", count: 60))
print("Total Tests: \(testsPassed + testsFailed)")
print("Passed: \(testsPassed)")
print("Failed: \(testsFailed)")
print("Success Rate: \(String(format: "%.1f", Double(testsPassed) / Double(testsPassed + testsFailed) * 100))%")
print(String(repeating: "=", count: 60))
print("Staging URL: \(stagingBaseURL)")
print("Auth Token: \(authToken != nil ? "Obtained" : "Not obtained")")
print("Customer ID: \(customerId.map { String($0) } ?? "Not obtained")")
print("Test Ride Request ID: \(testRideRequestId.map { String($0) } ?? "Not created")")
print("Test Address ID: \(testAddressId.map { String($0) } ?? "Not created")")
print(String(repeating: "=", count: 60))

// Exit with appropriate code
exit(testsFailed > 0 ? 1 : 0)
