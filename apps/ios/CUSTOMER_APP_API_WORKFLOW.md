# Dollor Customer App - API Routing & Workflow (Build 32)

> **Build:** 32 (Version 1.0)
> **Extracted From:** `Dollor-Build32.xcarchive`
> **Archive Date:** 2026-01-27
> **Status:** Submitted for App Store Review

---

## Base URLs (Build 32 - Production)

| Environment | URL |
|-------------|-----|
| **Production API** | `https://api.dollor.ai` |

---

## Legal URLs (Build 32)

| Page | URL |
|------|-----|
| Terms of Service | `https://api.dollor.ai/terms` |
| Privacy Policy | `https://api.dollor.ai/privacy` |
| Support | `https://api.dollor.ai/support` |
| Driver Terms | `https://dollor.ai/driver-terms` |
| Restaurant Terms | `https://dollor.ai/restaurant-terms` |

---

## API Endpoints (Extracted from Build 32 Binary)

### Authentication (Customer)

| Method | Endpoint | Description |
|--------|----------|-------------|
| POST | `/api/customer/google-auth` | Google Sign-In |
| POST | `/api/customer/apple-auth` | Apple Sign-In |
| POST | `/api/auth/customer/login` | Email/password login |
| POST | `/api/auth/customer/register` | Email registration |
| POST | `/api/auth/customer/google` | Google auth (alternate) |
| POST | `/api/auth/customer/apple-auth` | Apple auth (alternate) |
| POST | `/api/auth/customer/refresh` | Refresh access token |
| GET | `/api/auth/customer/me` | Get current user info |

### Customer Profile

| Method | Endpoint | Description |
|--------|----------|-------------|
| GET | `/api/customer/profile` | Get customer profile |
| PUT | `/api/auth/customer/profile` | Update profile |
| PUT | `/api/customer/{customer_id}/profile` | Update profile by ID |
| DELETE | `/api/customers/{customer_id}/delete` | Delete account |

### Customer Password Reset

| Method | Endpoint | Description |
|--------|----------|-------------|
| POST | `/api/customer/password-reset/request` | Request password reset |
| POST | `/api/customer/password-reset/confirm` | Confirm password reset |

### Customer Email Verification

| Method | Endpoint | Description |
|--------|----------|-------------|
| POST | `/api/customer/email/send-verification` | Send verification email |
| POST | `/api/customer/email/verify` | Verify email |
| GET | `/api/customer/email/status` | Check email verification status |

### Customer Notifications

| Method | Endpoint | Description |
|--------|----------|-------------|
| GET | `/api/customer/{customer_id}/notification-preferences` | Get notification prefs |
| PUT | `/api/customer/{customer_id}/notification-preferences` | Update notification prefs |

### Customer Orders

| Method | Endpoint | Description |
|--------|----------|-------------|
| GET | `/api/customer/orders` | Get order history |

### App Configuration

| Method | Endpoint | Description |
|--------|----------|-------------|
| GET | `/api/config` | Get app configuration |
| GET | `/api/health` | Health check |

### Orders

| Method | Endpoint | Description |
|--------|----------|-------------|
| POST | `/api/erp/orders/create` | Create new order |
| GET | `/api/erp/orders` | Get orders |
| GET | `/api/erp/orders/{id}` | Get order by ID |
| GET | `/api/erp/orders/available-for-delivery` | Available orders for drivers |
| GET | `/api/erp/orders/driver` | Driver's orders |
| GET | `/api/erp/orders/pending-restaurant-delivery` | Pending restaurant deliveries |

### Orders V2 (New Flow)

| Method | Endpoint | Description |
|--------|----------|-------------|
| POST | `/api/orders/v2/customer/confirm-delivery` | Customer confirms delivery |
| POST | `/api/orders/v2/driver/confirm-payment` | Driver confirms payment |
| POST | `/api/orders/v2/restaurant/confirm-payment` | Restaurant confirms payment |
| GET | `/api/orders/v2/legal/zero-liability-model` | Zero liability legal info |

### Restaurants (Public - No Auth)

| Method | Endpoint | Description |
|--------|----------|-------------|
| GET | `/api/vendors/published` | Get published restaurants (for iOS) |
| GET | `/api/public/restaurants` | Get all public restaurants |
| GET | `/api/public/restaurants/{vendor_id}` | Get restaurant detail + menu |
| GET | `/api/erp/restaurants` | Get restaurants list |
| GET | `/api/erp/restaurants/nearby` | Get nearby restaurants |
| GET | `/api/erp/restaurants/{restaurant_id}` | Get restaurant by ID |
| GET | `/api/erp/restaurants/{restaurant_id}/menu` | Get restaurant menu |

### Payments

| Method | Endpoint | Description |
|--------|----------|-------------|
| POST | `/api/erp/payments/intent` | Create payment intent |
| GET | `/api/erp/payments/intent/{id}` | Get payment intent status |
| POST | `/api/erp/payments/refund` | Request refund |
| GET | `/api/erp/payments` | Get payment history |
| GET | `/api/erp/payments/{id}` | Get payment by ID |
| GET | `/api/erp/payments/order/{order_id}/history` | Payment history for order |

### Customer Payment Methods

| Method | Endpoint | Description |
|--------|----------|-------------|
| GET | `/api/customer/payment-methods` | Get saved payment methods |
| POST | `/api/customer/payment-methods` | Add payment method |
| DELETE | `/api/customer/payment-methods/{id}` | Delete payment method |

### Trip Board (Rideshare)

| Method | Endpoint | Description |
|--------|----------|-------------|
| GET | `/api/trip-board/disclaimer` | Trip board disclaimer |
| GET | `/api/trip-board/listings` | Get trip listings |
| GET | `/api/trip-board/listings/{id}` | Get listing by ID |
| GET | `/api/trip-board/match-fee-info` | Match fee information |
| POST | `/api/trip-board/matches/confirm` | Confirm a match |
| POST | `/api/trip-board/matches/propose` | Propose a match |
| GET | `/api/trip-board/messages` | Get messages |
| GET | `/api/trip-board/my-matches` | Get my matches |
| GET | `/api/trip-board/price-helper` | Price helper |
| GET | `/api/trip-board/search-drivers` | Search for drivers |
| GET | `/api/trip-board/search-passengers` | Search for passengers |

### Trip Board Safety

| Method | Endpoint | Description |
|--------|----------|-------------|
| GET | `/api/trip-board/safety/agreement/{id}` | Safety agreement |
| POST | `/api/trip-board/safety/confirm-payment` | Confirm payment |
| GET | `/api/trip-board/safety/my-verification-code/{id}` | Get verification code |
| GET | `/api/trip-board/safety/pre-trip-summary/{id}` | Pre-trip summary |
| POST | `/api/trip-board/safety/recording-consent` | Recording consent |
| GET | `/api/trip-board/safety/safety-checklist` | Safety checklist |
| GET | `/api/trip-board/safety/safety-checklist-items` | Checklist items |
| GET | `/api/trip-board/safety/trip-status` | Trip status |
| POST | `/api/trip-board/safety/verify-identity` | Verify identity |

### Negotiations

| Method | Endpoint | Description |
|--------|----------|-------------|
| GET | `/api/negotiation` | Get negotiation |
| GET | `/api/negotiations` | Get all negotiations |
| GET | `/api/negotiations/{id}` | Get negotiation by ID |

### Chat & Calls

| Method | Endpoint | Description |
|--------|----------|-------------|
| GET | `/api/chat/conversations` | Get conversations |
| GET | `/api/chat/conversations/{id}` | Get conversation by ID |
| POST | `/api/call/initiate` | Initiate a call |
| GET | `/api/call/sessions` | Get call sessions |
| GET | `/api/call/sessions/{id}` | Get session by ID |
| GET | `/api/call/masked-number?session_id={id}` | Get masked phone number |

### Legal

| Method | Endpoint | Description |
|--------|----------|-------------|
| GET | `/api/legal/privacy-policy` | Privacy policy |
| GET | `/api/legal/tiered-pricing` | Tiered pricing info |
| GET | `/api/platform-legal/summary` | Platform legal summary |

### Realtime

| Method | Endpoint | Description |
|--------|----------|-------------|
| WS | `/api/realtime/ws` | WebSocket connection |

---

## Authentication Flow (Build 32)

### Google Sign-In

```
iOS App                    Google SDK                 P2P Backend
   │                           │                           │
   │  1. signIn()              │                           │
   │ ─────────────────────────▶│                           │
   │                           │                           │
   │  2. Returns idToken       │                           │
   │ ◀─────────────────────────│                           │
   │                           │                           │
   │  3. POST /api/customer/google-auth                    │
   │ ─────────────────────────────────────────────────────▶│
   │     {id_token, email, full_name}                      │
   │                           │                           │
   │  4. Returns access_token, customer_id                 │
   │ ◀─────────────────────────────────────────────────────│
   │                           │                           │
   │  5. Store token in Keychain                           │
   │                           │                           │
```

---

## Payment Flow (Build 32)

### Stripe Integration

```
iOS App                    P2P Backend                 Stripe
   │                           │                           │
   │  1. POST /api/erp/payments/intent                     │
   │ ─────────────────────────▶│                           │
   │     {amount, currency}    │                           │
   │                           │  2. Create PaymentIntent  │
   │                           │ ─────────────────────────▶│
   │                           │                           │
   │                           │  3. Returns client_secret │
   │                           │ ◀─────────────────────────│
   │                           │                           │
   │  4. Returns {paymentIntent, publishableKey}           │
   │ ◀─────────────────────────│                           │
   │                           │                           │
   │  5. Apple Pay / Card via Stripe SDK                   │
   │ ─────────────────────────────────────────────────────▶│
   │                           │                           │
   │  6. Payment confirmed                                 │
   │ ◀─────────────────────────────────────────────────────│
```

### Stripe Configuration (Build 32)

| Property | Value |
|----------|-------|
| Merchant ID | `merchant.com.dollorai.customer` |
| Publishable Key | Fetched from `/api/erp/payments/intent` |
| Account ID | `acct_1SoXl3ReyIzV18V4` |

---

## Order Flow (Build 32)

```
┌─────────────┐    ┌─────────────┐    ┌─────────────┐    ┌─────────────┐
│  Customer   │    │   Backend   │    │ Restaurant  │    │   Driver    │
│   (iOS)     │    │             │    │   (iOS)     │    │   (iOS)     │
└──────┬──────┘    └──────┬──────┘    └──────┬──────┘    └──────┬──────┘
       │                  │                  │                  │
       │ 1. Create Order  │                  │                  │
       │ POST /api/erp/   │                  │                  │
       │ orders/create    │                  │                  │
       │─────────────────▶│                  │                  │
       │                  │                  │                  │
       │                  │ 2. Notify        │                  │
       │                  │─────────────────▶│                  │
       │                  │                  │                  │
       │                  │                  │ 3. Accept        │
       │                  │◀─────────────────│                  │
       │                  │                  │                  │
       │                  │ 4. Available for │                  │
       │                  │    delivery      │                  │
       │                  │─────────────────────────────────────▶
       │                  │                  │                  │
       │                  │                  │ 5. Accept        │
       │                  │◀─────────────────────────────────────
       │                  │                  │                  │
       │ 6. Order status  │                  │                  │
       │   updates        │                  │                  │
       │◀─────────────────│                  │                  │
       │                  │                  │                  │
       │ 7. Confirm       │                  │                  │
       │ POST /api/orders │                  │                  │
       │ /v2/customer/    │                  │                  │
       │ confirm-delivery │                  │                  │
       │─────────────────▶│                  │                  │
```

---

## WebSocket (Realtime Updates)

**Endpoint:** `wss://api.dollor.ai/api/realtime/ws`

Used for:
- Order status updates
- Driver location tracking
- Chat messages
- Trip board updates

---

## Request Headers (Build 32)

```
Authorization: Bearer {access_token}
Content-Type: application/json
Accept: application/json
```

---

## Token Storage (Build 32)

| Key | Storage | Description |
|-----|---------|-------------|
| Customer Token | Keychain (`SecureStorage`) | JWT access token |
| Customer ID | UserDefaults | `p2p_customer_id` |
| Customer Name | UserDefaults | `p2p_customer_name` |
| Customer Email | UserDefaults | `p2p_customer_email` |

---

## Referral System (Build 32)

| Feature | URL/Code |
|---------|----------|
| App Download | `https://dollor.ai/app` |
| Referral Link | `https://dollor.ai/r/{CODE}` |
| Group Order | `https://dollor.ai/group/{GROUP_ID}` |
| Example Code | `DLR8X7K9` |
| Referral Bonus | $5 off first order |
| Invite Text | "Get $10 off your first Dollor.ai order!" |

---

## Third-Party Services (Build 32)

| Service | Usage |
|---------|-------|
| **Stripe** | Payments, Apple Pay |
| **Google Maps** | Maps, Places, Directions |
| **Firebase** | Analytics, Crash Reporting |
| **Google Sign-In** | Authentication |
| **Apple Sign-In** | Authentication |

---

---

## Verification Summary

| Source | Count | Status |
|--------|-------|--------|
| Build 32 Binary (strings) | 50+ endpoints | Extracted |
| Backend (main_new.py) | 405 routes | Cross-referenced |
| Customer-specific | 35+ endpoints | Documented |

**Cross-Referenced Against:**
1. `Dollor-Build32.xcarchive` binary strings
2. `/apps/web/p2p-platform/backend/main_new.py`
3. P2PAPIService.swift in iOS shared code

---

**VERIFIED FROM BUILD 32 ARCHIVE**
**Source:** `~/Library/Developer/Xcode/Archives/2026-01-27/Dollor-Build32.xcarchive`
**Backend:** `/apps/web/p2p-platform/backend/main_new.py` (405 routes)

---

**END OF DOCUMENT**
