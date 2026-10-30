# iOS App Architecture - API Workflows, UI & Database

> **READ-ONLY REFERENCE DOCUMENT**
> Last Updated: 2026-02-02
> Status: Customer (Build 32), Driver (Dev), Restaurant (Build 17)

---

## Quick Reference

| App | Bundle ID | Backend | Status |
|-----|-----------|---------|--------|
| Customer | `com.dollorai.customer` | api.dollor.ai | App Store Review |
| Driver | `com.dollorai.delivery` | api.dollor.ai | Development |
| Restaurant | `com.dollorai.restaurant` | api.dollor.ai | TestFlight |

---

## 1. Environment Configuration

```
┌─────────────────────────────────────────────────────────────────┐
│                    ENVIRONMENT URLS                              │
├─────────────────────────────────────────────────────────────────┤
│  Production:   https://api.dollor.ai                            │
├─────────────────────────────────────────────────────────────────┤
│  Config Source: AppConfig.shared.p2pAPIBaseURL                  │
│  Files:         Config/Production.xcconfig                       │
│                 Config/Staging.xcconfig                          │
│                 Config/Development.xcconfig                      │
└─────────────────────────────────────────────────────────────────┘
```

---

## 2. Data Flow Architecture

```
┌──────────────────────────────────────────────────────────────────────────┐
│                           iOS APP DATA FLOW                               │
├──────────────────────────────────────────────────────────────────────────┤
│                                                                          │
│   ┌─────────────┐      ┌─────────────┐      ┌─────────────┐             │
│   │   SwiftUI   │ ──── │  ViewModel  │ ──── │   Service   │             │
│   │    View     │      │  @Published │      │   Layer     │             │
│   └─────────────┘      └─────────────┘      └─────────────┘             │
│          │                    │                    │                     │
│          │                    │                    ▼                     │
│          │                    │           ┌─────────────┐               │
│          │                    │           │ P2PAPIService│               │
│          │                    │           │ URLSession   │               │
│          │                    │           └──────┬──────┘               │
│          │                    │                  │                       │
│          │                    │                  ▼                       │
│          │                    │           ┌─────────────┐               │
│          │                    │           │   Backend   │               │
│          │                    │           │   API       │               │
│          │                    │           └─────────────┘               │
│          │                    │                                         │
│          ▼                    ▼                                         │
│   ┌─────────────┐      ┌─────────────┐                                 │
│   │  UserDefaults│      │  Keychain   │                                 │
│   │  (Non-Secret)│      │  (Tokens)   │                                 │
│   └─────────────┘      └─────────────┘                                 │
│                                                                          │
└──────────────────────────────────────────────────────────────────────────┘
```

---

## 3. Customer App - API Workflows

### 3.1 Authentication Flow

```
┌────────────────────────────────────────────────────────────────────────┐
│                    AUTHENTICATION FLOW                                  │
├────────────────────────────────────────────────────────────────────────┤
│                                                                        │
│  ┌──────────┐     ┌──────────┐     ┌──────────┐     ┌──────────┐     │
│  │ LoginView│ ──▶ │ Google/  │ ──▶ │ Backend  │ ──▶ │ Keychain │     │
│  │          │     │ Apple    │     │ /api/    │     │ Store    │     │
│  └──────────┘     │ OAuth    │     │ customer/│     │ Token    │     │
│                   └──────────┘     │ *-auth   │     └──────────┘     │
│                                    └──────────┘                       │
│                                                                        │
│  ENDPOINTS:                                                            │
│  ├─ POST /api/customer/google-auth   ← Google OAuth token             │
│  ├─ POST /api/customer/apple-auth    ← Apple identity token           │
│  ├─ POST /api/auth/customer/login    ← Email/password                 │
│  ├─ POST /api/auth/customer/register ← New account                    │
│  └─ POST /api/auth/customer/refresh  ← Refresh expired token          │
│                                                                        │
│  RESPONSE MODEL:                                                       │
│  {                                                                     │
│    "access_token": "eyJ...",                                          │
│    "token_type": "Bearer",                                            │
│    "customer": {                                                       │
│      "id": 123,                                                        │
│      "name": "John Doe",                                              │
│      "email": "john@example.com"                                      │
│    }                                                                   │
│  }                                                                     │
│                                                                        │
│  STORAGE:                                                              │
│  ├─ Keychain: access_token (SecureStorage.shared)                     │
│  └─ UserDefaults: p2p_customer_id, p2p_customer_name, p2p_customer_email│
│                                                                        │
└────────────────────────────────────────────────────────────────────────┘
```

### 3.2 Restaurant Discovery Flow

```
┌────────────────────────────────────────────────────────────────────────┐
│                    RESTAURANT DISCOVERY                                 │
├────────────────────────────────────────────────────────────────────────┤
│                                                                        │
│  RestaurantListView                                                    │
│       │                                                                │
│       ▼                                                                │
│  RestaurantListViewModel                                               │
│       │ fetchRestaurants()                                             │
│       ▼                                                                │
│  P2PAPIService.fetchRestaurants()                                      │
│       │                                                                │
│       ▼                                                                │
│  GET /api/vendors/published?platform=ios&city=X&cuisine=Y              │
│       │                                                                │
│       ▼                                                                │
│  Response: P2PRestaurantsResponse                                      │
│  {                                                                     │
│    "restaurants": [                                                    │
│      {                                                                 │
│        "id": 1,                                                        │
│        "name": "Pizza Place",                                          │
│        "cuisine_type": "Italian",                                      │
│        "address": "123 Main St",                                       │
│        "latitude": 34.0522,                                            │
│        "longitude": -118.2437,                                         │
│        "is_open": true,                                                │
│        "menu_items": [...],                                            │
│        "stripe_account_id": "acct_xxx"                                 │
│      }                                                                 │
│    ]                                                                   │
│  }                                                                     │
│                                                                        │
│  FILES INVOLVED:                                                       │
│  ├─ Views/RestaurantListView.swift                                     │
│  ├─ ViewModels/RestaurantListViewModel.swift                           │
│  ├─ Services/P2PAPIService.swift                                       │
│  └─ Models/P2PRestaurant.swift                                         │
│                                                                        │
└────────────────────────────────────────────────────────────────────────┘
```

### 3.3 Order Creation Flow (CRITICAL PATH)

```
┌────────────────────────────────────────────────────────────────────────┐
│                    ORDER CREATION FLOW                                  │
├────────────────────────────────────────────────────────────────────────┤
│                                                                        │
│  STEP 1: Cart Management (Local)                                       │
│  ┌─────────────────────────────────────────────────┐                  │
│  │ MultiRestaurantCartViewModel                     │                  │
│  │ @Published var items: [CartItem] = []           │                  │
│  │ @Published var orderPlaced: Bool = false        │                  │
│  └─────────────────────────────────────────────────┘                  │
│                                                                        │
│  STEP 2: Checkout Initiation                                           │
│  ┌─────────────────────────────────────────────────┐                  │
│  │ MultiRestaurantCheckoutView                      │                  │
│  │  └─ Trigger: initiatePayment()                  │                  │
│  └─────────────────────────────────────────────────┘                  │
│       │                                                                │
│       ▼                                                                │
│  STEP 3: Fetch Payment Keys                                            │
│  ┌─────────────────────────────────────────────────┐                  │
│  │ PaymentService.fetchPaymentSheetKeys()          │                  │
│  │ POST /api/erp/payments/intent                    │                  │
│  │                                                  │                  │
│  │ Request:                                         │                  │
│  │ {                                               │                  │
│  │   "amount": 2500,  // cents                     │                  │
│  │   "currency": "usd"                             │                  │
│  │ }                                               │                  │
│  │                                                  │                  │
│  │ Response (PaymentSheetKeys):                    │                  │
│  │ {                                               │                  │
│  │   "paymentIntent": "pi_xxx",                    │                  │
│  │   "ephemeralKey": "ek_xxx",                     │                  │
│  │   "customer": "cus_xxx",                        │                  │
│  │   "publishableKey": "pk_live_xxx",             │                  │
│  │   "demo": false  // ⚠️ App Store review flag   │                  │
│  │ }                                               │                  │
│  └─────────────────────────────────────────────────┘                  │
│       │                                                                │
│       ▼                                                                │
│  STEP 4: Demo Payment Check (⚠️ CRITICAL FOR APP STORE)               │
│  ┌─────────────────────────────────────────────────┐                  │
│  │ if keys.isDemoPayment {                         │                  │
│  │     // Bypass Stripe, place order directly      │                  │
│  │     self.placeOrder()                           │                  │
│  │ } else {                                        │                  │
│  │     // Continue with Stripe payment             │                  │
│  │ }                                               │                  │
│  └─────────────────────────────────────────────────┘                  │
│       │                                                                │
│       ▼                                                                │
│  STEP 5: Stripe Payment (Apple Pay or Card)                           │
│  ┌─────────────────────────────────────────────────┐                  │
│  │ STPPaymentSheet.present() or                    │                  │
│  │ STPApplePayContext.presentApplePay()            │                  │
│  │                                                  │                  │
│  │ On Success: paymentIntentClientSecret confirmed │                  │
│  └─────────────────────────────────────────────────┘                  │
│       │                                                                │
│       ▼                                                                │
│  STEP 6: Create Order in Backend                                       │
│  ┌─────────────────────────────────────────────────┐                  │
│  │ POST /api/v3/order/create                        │                  │
│  │                                                  │                  │
│  │ Request (V3CreateOrderRequest):                 │                  │
│  │ {                                               │                  │
│  │   "customerEmail": "john@example.com",          │                  │
│  │   "customerName": "John Doe",                   │                  │
│  │   "customerPhone": "+1234567890",               │                  │
│  │   "restaurantId": 1,                            │                  │
│  │   "restaurantStripeAccount": "acct_xxx",        │                  │
│  │   "items": [{"id": 5, "quantity": 2}],          │                  │
│  │   "deliveryAddress": "456 Oak Ave",             │                  │
│  │   "deliveryLat": 34.0522,                       │                  │
│  │   "deliveryLng": -118.2437,                     │                  │
│  │   "tipAmount": 5.00,                            │                  │
│  │   "promoCode": null                             │                  │
│  │ }                                               │                  │
│  │                                                  │                  │
│  │ Response (V3OrderResponse):                     │                  │
│  │ {                                               │                  │
│  │   "orderId": 456,                               │                  │
│  │   "status": "confirmed",                        │                  │
│  │   "subtotal": 20.00,                            │                  │
│  │   "tax": 1.75,                                  │                  │
│  │   "deliveryFee": 3.00,                          │                  │
│  │   "serviceFee": 1.00,                           │                  │
│  │   "tip": 5.00,                                  │                  │
│  │   "total": 30.75,                               │                  │
│  │   "estimatedDelivery": "2024-01-01T18:30:00Z"   │                  │
│  │ }                                               │                  │
│  └─────────────────────────────────────────────────┘                  │
│       │                                                                │
│       ▼                                                                │
│  STEP 7: Show Success Screen (⚠️ KNOWN ISSUE)                         │
│  ┌─────────────────────────────────────────────────┐                  │
│  │ MainAppView.onChange(of: orderPlaced)           │                  │
│  │  └─ showCartSheet = false                       │                  │
│  │  └─ DispatchQueue.main.asyncAfter(1.0s) {      │                  │
│  │       showOrderSuccess = true  // ⚠️ MAY FAIL  │                  │
│  │     }                                           │                  │
│  │                                                  │                  │
│  │ ISSUE: Sheet dismissal race condition           │                  │
│  │ SUCCESS screen may not appear!                  │                  │
│  └─────────────────────────────────────────────────┘                  │
│                                                                        │
│  FILES INVOLVED:                                                       │
│  ├─ Views/MultiRestaurantCheckoutView.swift:1001 (demo check)          │
│  ├─ ViewModels/MultiRestaurantCartViewModel.swift                      │
│  ├─ Services/PaymentService.swift:14,27 (demo flag)                    │
│  ├─ Services/DollorV3Service.swift                                     │
│  └─ Views/MainAppView.swift:88-100 (success screen issue)              │
│                                                                        │
└────────────────────────────────────────────────────────────────────────┘
```

### 3.4 Payment Methods

```
┌────────────────────────────────────────────────────────────────────────┐
│                    PAYMENT ENDPOINTS                                    │
├────────────────────────────────────────────────────────────────────────┤
│                                                                        │
│  Payment Intent:                                                       │
│  ├─ POST /api/erp/payments/intent      Create payment intent           │
│  ├─ GET  /api/erp/payments/intent/{id} Get payment status              │
│  └─ GET  /api/erp/payments             Payment history                 │
│                                                                        │
│  Saved Cards:                                                          │
│  ├─ GET    /api/customer/payment-methods     List saved cards          │
│  ├─ POST   /api/customer/payment-methods     Add new card              │
│  └─ DELETE /api/customer/payment-methods/{id} Remove card              │
│                                                                        │
│  Stripe Configuration:                                                 │
│  ├─ Publishable Key: From /api/erp/payments/intent response            │
│  ├─ Merchant ID: merchant.com.dollorai.customer                        │
│  └─ Apple Pay: Enabled in entitlements                                 │
│                                                                        │
└────────────────────────────────────────────────────────────────────────┘
```

---

## 4. Driver App - API Workflows

### 4.1 Driver Authentication & Onboarding

```
┌────────────────────────────────────────────────────────────────────────┐
│                    DRIVER ONBOARDING FLOW                               │
├────────────────────────────────────────────────────────────────────────┤
│                                                                        │
│  STEP 1: Authentication                                                │
│  ├─ POST /api/driver/google-auth                                       │
│  └─ POST /api/driver/apple-auth                                        │
│                                                                        │
│  STEP 2: Profile Setup                                                 │
│  ├─ GET  /api/driver/{id}/profile                                      │
│  └─ PUT  /api/driver/{id}/profile                                      │
│                                                                        │
│  STEP 3: Document Upload                                               │
│  ├─ POST /api/driver/{id}/documents                                    │
│  │   - Driver's license                                                │
│  │   - Vehicle registration                                            │
│  │   - Insurance                                                       │
│  │   - Profile photo                                                   │
│  │                                                                     │
│  │  Response: { "status": "pending_review" }                          │
│                                                                        │
│  STEP 4: Approval (Async via Notification)                             │
│  ├─ Backend reviews documents                                          │
│  ├─ Sends push notification: "DriverApproved"                          │
│  └─ App updates: UserDefaults.p2p_driver_is_approved = true            │
│                                                                        │
│  ⚠️ ISSUE: If notification missed, state is stale until restart        │
│                                                                        │
│  STORAGE:                                                              │
│  ├─ Keychain: driver_access_token                                      │
│  └─ UserDefaults:                                                      │
│      ├─ p2p_driver_id: Int                                             │
│      ├─ p2p_driver_name: String                                        │
│      ├─ p2p_driver_status: String                                      │
│      ├─ p2p_driver_is_approved: Bool                                   │
│      └─ p2p_driver_requires_documents: Bool                            │
│                                                                        │
└────────────────────────────────────────────────────────────────────────┘
```

### 4.2 Order Acceptance Flow

```
┌────────────────────────────────────────────────────────────────────────┐
│                    DRIVER ORDER FLOW                                    │
├────────────────────────────────────────────────────────────────────────┤
│                                                                        │
│  Available Orders:                                                     │
│  GET /api/erp/orders/available-for-delivery                            │
│  Response: [{ orderId, restaurant, customer, pickup, dropoff }]        │
│       │                                                                │
│       ▼                                                                │
│  Accept Order:                                                         │
│  POST /api/erp/orders/{id}/accept                                      │
│  Response: { status: "driver_assigned", driverId: X }                  │
│       │                                                                │
│       ▼                                                                │
│  Pick Up:                                                              │
│  POST /api/erp/orders/{id}/pickup                                      │
│  Response: { status: "picked_up" }                                     │
│       │                                                                │
│       ▼                                                                │
│  Deliver:                                                              │
│  POST /api/erp/orders/{id}/deliver                                     │
│  Response: { status: "delivered" }                                     │
│                                                                        │
│  Driver's Orders:                                                      │
│  GET /api/erp/orders/driver                                            │
│  Response: [{ orders assigned to this driver }]                        │
│                                                                        │
└────────────────────────────────────────────────────────────────────────┘
```

---

## 5. Restaurant App - API Workflows

### 5.1 Menu Management

```
┌────────────────────────────────────────────────────────────────────────┐
│                    RESTAURANT MENU MANAGEMENT                           │
├────────────────────────────────────────────────────────────────────────┤
│                                                                        │
│  Authentication:                                                       │
│  ├─ POST /api/vendors/google-auth                                      │
│  └─ POST /api/vendors/apple-auth                                       │
│                                                                        │
│  Menu CRUD:                                                            │
│  ├─ GET    /api/vendors/{id}/menu                 List all items       │
│  ├─ POST   /api/vendors/{id}/menu                 Create item          │
│  ├─ PATCH  /api/vendors/{id}/menu/{itemId}        Update item          │
│  └─ DELETE /api/vendors/{id}/menu/{itemId}        Delete item          │
│                                                                        │
│  Menu Item Model:                                                      │
│  {                                                                     │
│    "id": 123,                                                          │
│    "name": "Pepperoni Pizza",                                          │
│    "description": "Classic pepperoni with cheese",                     │
│    "price": 15.99,                                                     │
│    "category": "Pizza",                                                │
│    "in_stock": true,                                                   │
│    "image_url": "https://...",                                         │
│    "is_popular": true,                                                 │
│    "dietary_flags": ["vegetarian_option"]                              │
│  }                                                                     │
│                                                                        │
│  Order Management:                                                     │
│  ├─ GET /api/vendors/{id}/orders                  Restaurant orders    │
│  ├─ GET /api/vendors/{id}/analytics               Order analytics      │
│  └─ GET /api/vendors/{id}/ai-insights             AI-powered insights  │
│                                                                        │
│  STORAGE:                                                              │
│  ├─ Keychain: vendor_access_token                                      │
│  └─ UserDefaults: p2p_vendor_id                                        │
│                                                                        │
└────────────────────────────────────────────────────────────────────────┘
```

---

## 6. Storage Architecture

### 6.1 Keychain (Secure Storage)

```
┌────────────────────────────────────────────────────────────────────────┐
│                    KEYCHAIN STORAGE (SECURE)                            │
├────────────────────────────────────────────────────────────────────────┤
│                                                                        │
│  Implementation: SecureStorage.shared (EatFairShared)                  │
│                                                                        │
│  Customer App:                                                         │
│  └─ customerAccessToken: String                                        │
│                                                                        │
│  Driver App:                                                           │
│  └─ driverAccessToken: String                                          │
│                                                                        │
│  Restaurant App:                                                       │
│  └─ vendorAccessToken: String                                          │
│                                                                        │
│  Methods:                                                              │
│  ├─ store(token: String, for key: String)                              │
│  ├─ retrieve(for key: String) -> String?                               │
│  ├─ delete(for key: String)                                            │
│  └─ migrateFromUserDefaults()  // Legacy migration                     │
│                                                                        │
└────────────────────────────────────────────────────────────────────────┘
```

### 6.2 UserDefaults (Non-Sensitive)

```
┌────────────────────────────────────────────────────────────────────────┐
│                    USERDEFAULTS STORAGE                                 │
├────────────────────────────────────────────────────────────────────────┤
│                                                                        │
│  Customer App:                                                         │
│  ├─ p2p_customer_id: String                                            │
│  ├─ p2p_customer_name: String                                          │
│  ├─ p2p_customer_email: String                                         │
│  └─ customerAccessToken: String (DEPRECATED - migrating to Keychain)   │
│                                                                        │
│  Driver App:                                                           │
│  ├─ p2p_driver_id: Int                                                 │
│  ├─ p2p_driver_name: String                                            │
│  ├─ p2p_driver_status: String                                          │
│  ├─ p2p_driver_is_approved: Bool                                       │
│  └─ p2p_driver_requires_documents: Bool                                │
│                                                                        │
│  Restaurant App:                                                       │
│  └─ p2p_vendor_id: Int                                                 │
│                                                                        │
│  ⚠️ WARNING: UserDefaults is NOT encrypted                              │
│                                                                        │
└────────────────────────────────────────────────────────────────────────┘
```

### 6.3 CoreData (Local Persistence)

```
┌────────────────────────────────────────────────────────────────────────┐
│                    COREDATA USAGE                                       │
├────────────────────────────────────────────────────────────────────────┤
│                                                                        │
│  Customer App: eatfaircustomer.xcdatamodeld                            │
│  └─ Entity: Item (timestamp) - Minimal, mostly for previews            │
│                                                                        │
│  Driver App: eatffairdelivery.xcdatamodeld                             │
│  └─ In-progress orders cache                                           │
│                                                                        │
│  Restaurant App: eatffairrestaurant.xcdatamodeld                       │
│  └─ Menu cache + local modifications                                   │
│                                                                        │
│  Setup (PersistenceController.swift):                                  │
│  container = NSPersistentContainer(name: "...")                        │
│  container.loadPersistentStores { error in                             │
│      if let error = error {                                            │
│          print("CoreData error (non-fatal): \(error)")                 │
│          // ⚠️ App continues silently with broken CoreData             │
│      }                                                                 │
│  }                                                                     │
│                                                                        │
│  ⚠️ ISSUE: Errors ignored silently, no offline support                  │
│                                                                        │
└────────────────────────────────────────────────────────────────────────┘
```

---

## 7. Known Issues & Failure Points

### 7.1 Critical Issues

| Issue | Location | Impact | Status |
|-------|----------|--------|--------|
| Order success screen not showing | MainAppView.swift:88-100 | Users unsure if order placed | ACTIVE BUG |
| No token refresh | P2PAPIService.swift | Session expires, all calls fail | MISSING |
| Demo payment not integrated | MultiRestaurantCheckoutView.swift | App Store rejection risk | PARTIAL |

### 7.2 High Risk Issues

| Issue | Location | Impact | Status |
|-------|----------|--------|--------|
| Driver approval state cache | UserDefaults | Stale approval status | DESIGN FLAW |
| Payment + Order race condition | Checkout flow | Charged but no order | POSSIBLE |
| WebSocket drops in background | AppDelegate.swift | Missed order updates | KNOWN |

### 7.3 Medium Risk Issues

| Issue | Location | Impact | Status |
|-------|----------|--------|--------|
| Inconsistent error handling | Multiple services | Generic errors shown | TECH DEBT |
| CoreData error ignored | Persistence.swift | Silent failures | TECH DEBT |
| No SSL pinning | NetworkSecurity.swift | Security gap | DISABLED |

---

## 8. Demo Payment Flow (App Store Review)

```
┌────────────────────────────────────────────────────────────────────────┐
│                    DEMO PAYMENT - APP STORE REVIEW                      │
├────────────────────────────────────────────────────────────────────────┤
│                                                                        │
│  Demo Credentials:                                                     │
│  ├─ Email: demo.customer@dollor.ai                                     │
│  └─ Password: DemoCustomer2025!                                        │
│                                                                        │
│  Backend Response for Demo User:                                       │
│  POST /api/erp/payments/intent                                         │
│  Response: { ..., "demo": true }                                       │
│                                                                        │
│  iOS Check (CRITICAL - Must exist):                                    │
│  ┌─────────────────────────────────────────────────┐                  │
│  │ PaymentService.swift:14                          │                  │
│  │   let demo: Bool?  // Must decode this field    │                  │
│  │                                                  │                  │
│  │ PaymentService.swift:27                          │                  │
│  │   var isDemoPayment: Bool {                     │                  │
│  │       demo == true                              │                  │
│  │   }                                              │                  │
│  └─────────────────────────────────────────────────┘                  │
│                                                                        │
│  Checkout Logic (CRITICAL - Must exist):                               │
│  ┌─────────────────────────────────────────────────┐                  │
│  │ MultiRestaurantCheckoutView.swift:1001          │                  │
│  │   if keys.isDemoPayment {                       │                  │
│  │       // Bypass Stripe payment                  │                  │
│  │       self.placeOrder()  // Line ~1006          │                  │
│  │   } else {                                      │                  │
│  │       // Continue with Stripe                   │                  │
│  │   }                                              │                  │
│  └─────────────────────────────────────────────────┘                  │
│                                                                        │
│  ⚠️ FAILURE MODE: If these patterns are removed,                        │
│     Apple reviewer cannot complete order → REJECTION                   │
│                                                                        │
└────────────────────────────────────────────────────────────────────────┘
```

---

## 9. API Headers & Authentication

```
┌────────────────────────────────────────────────────────────────────────┐
│                    API REQUEST HEADERS                                  │
├────────────────────────────────────────────────────────────────────────┤
│                                                                        │
│  All Authenticated Requests:                                           │
│  ├─ Authorization: Bearer {access_token}                               │
│  ├─ Content-Type: application/json                                     │
│  ├─ Accept: application/json                                           │
│  ├─ X-Request-ID: {UUID}  (optional, for tracing)                      │
│  └─ X-Request-Timestamp: {ISO8601}  (optional)                         │
│                                                                        │
│  iOS-Specific Headers:                                                 │
│  ├─ X-Platform: ios                                                    │
│  ├─ X-App-Version: {CFBundleShortVersionString}                        │
│  └─ X-Build-Number: {CFBundleVersion}                                  │
│                                                                        │
│  Token Refresh Flow (MISSING IMPLEMENTATION):                          │
│  1. API returns 401 Unauthorized                                       │
│  2. Should call POST /api/auth/customer/refresh                        │
│  3. Should retry original request with new token                       │
│  4. Currently: User sees error, must re-login                          │
│                                                                        │
└────────────────────────────────────────────────────────────────────────┘
```

---

## 10. File Reference Index

### Customer App Key Files

| File | Purpose | Lines of Interest |
|------|---------|-------------------|
| `Views/MainAppView.swift` | Root view, tab navigation | 88-100 (success screen issue) |
| `Views/MultiRestaurantCheckoutView.swift` | Checkout flow | 1001 (demo check) |
| `ViewModels/MultiRestaurantCartViewModel.swift` | Cart state | orderPlaced flag |
| `Services/PaymentService.swift` | Stripe integration | 14, 27 (demo flag) |
| `Services/P2PAPIService.swift` | Backend API calls | All endpoints |
| `Services/DollorV3Service.swift` | V3 order creation | createOrder() |
| `Views/LoginView.swift` | Authentication | 283 (demo email) |

### Shared Framework Key Files

| File | Purpose |
|------|---------|
| `EatFairShared/AppConfig.swift` | Environment URLs |
| `EatFairShared/SecureStorage.swift` | Keychain wrapper |
| `EatFairShared/NetworkSecurity.swift` | SSL pinning (disabled) |

---

*This document is READ-ONLY reference. Update when architecture changes.*
