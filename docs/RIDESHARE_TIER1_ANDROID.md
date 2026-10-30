# Rideshare Tier 1 Features — Android Implementation Reference

> **12 features: status across Backend (Python/FastAPI) and Android (Kotlin/Jetpack Compose)**
>
> Date: February 18, 2026
> Backend: `apps/web/p2p-platform/backend/`
> Android Customer: `apps/android/app/` (`:app` module)
> Android Driver: `apps/android/driver/` (`:driver` module)
> Android Shared: `apps/android/shared/` (`:shared` module)

---

## Implementation Status Summary

| # | Feature | Backend | Android Status | Notes |
|---|---------|---------|----------------|-------|
| 79 | Ride History UI (Customer) | DONE | API only — no UI screen | `CustomerRidesResponse` model + `getCustomerRides()` exist, no Composable calls them |
| 80 | Post-Ride Earnings (Driver) | DONE | IMPLEMENTED | `ActiveRideViewModel.completeRide()` shows earnings/tip/total |
| 81 | Driver Cancellation Flow | DONE | IMPLEMENTED | Customer cancel via `CustomerRideshareApiService`, driver cancel via `DollorRepository` |
| 82 | No-Show Timer | DONE | NOT IMPLEMENTED | Backend endpoint exists, no Android timer or UI |
| 83 | In-App Chat | DONE | IMPLEMENTED | Both customer `DriverChatScreen` and driver `RideChatScreen` with 3s polling |
| 84 | Driver Online/Offline Toggle | DONE | IMPLEMENTED | `ProfileScreen` toggle + `updateDriverStatus()` API |
| 85 | Driver Rates Passenger | DONE | IMPLEMENTED | `ActiveRideViewModel.submitRating()` with 1-5 stars + comment |
| 86 | SOS/Emergency Button | N/A | PARTIAL | Text-only in privacy screen, no dedicated SOS button during rides |
| 87 | Share Trip with Contacts | N/A | NOT IMPLEMENTED | No share intent or UI |
| 88 | Document Verification Before Bidding | DONE | IMPLEMENTED | Backend returns 403, driver UI shows documents screen |
| 89 | Background Location Tracking | DONE | IMPLEMENTED | `FusedLocationProvider` with 15s interval in `ActiveRideViewModel` |
| 90 | Surge/Dynamic Pricing | DONE | PARTIAL | Time-based multipliers in `AppConfig`, no surge badge or banner UI |

---

## Table of Contents

1. [Task #79 — Ride History UI (Customer)](#task-79--ride-history-ui-customer)
2. [Task #80 — Post-Ride Earnings Summary (Driver)](#task-80--post-ride-earnings-summary-driver)
3. [Task #81 — Driver Cancellation Flow](#task-81--driver-cancellation-flow)
4. [Task #82 — No-Show Handling with Timer](#task-82--no-show-handling-with-timer)
5. [Task #83 — In-App Chat (Customer ↔ Driver)](#task-83--in-app-chat-customer--driver)
6. [Task #84 — Driver Online/Offline Toggle](#task-84--driver-onlineoffline-toggle)
7. [Task #85 — Driver Rates Passenger](#task-85--driver-rates-passenger)
8. [Task #86 — SOS/Emergency Button (Both Apps)](#task-86--sosemergency-button-both-apps)
9. [Task #87 — Share Trip with Contacts](#task-87--share-trip-with-contacts)
10. [Task #88 — Driver Document Verification Before Bidding](#task-88--driver-document-verification-before-bidding)
11. [Task #89 — Background Location Tracking (Driver)](#task-89--background-location-tracking-driver)
12. [Task #90 — Surge/Dynamic Pricing](#task-90--surgedynamic-pricing)

---

## Task #79 — Ride History UI (Customer)

### Status: API ONLY — NO UI SCREEN

### What Exists

**Models** — `shared/.../ApiModels.kt`:
- `CustomerRidesResponse` (line 695): wraps `rides: List<Ride>` + `count: Int`
- `Ride` (line 700): full ride model with `@SerializedName` for `pickup_address`, `dropoff_address`, `fare_amount`, `platform_fee`, `driver_earnings`, `created_at`, `completed_at`, `distance_miles`, `driver: DriverInfo?`

**API Definition** — `shared/.../DollorApiService.kt`:
- `@GET("customer/rides")` at line 307 → `getCustomerRides(): CustomerRidesResponse`

**Repository** — `shared/.../DollorRepository.kt`:
- `getCustomerRides()` at line 1063 → calls `GET /api/customer/rides`

**Backend** — `main_new.py:14812`:
- `GET /api/customer/rides` — returns paginated ride list with driver info, addresses, fares
- Response includes `rides[]`, `count`, `total`, `has_more`

### What's Missing

No Composable screen calls `getCustomerRides()`. The customer app has food order history but no ride history tab or screen.

### What to Build

1. **ViewModel** — `RideHistoryViewModel.kt` in `app/.../ui/rideshare/`:
   - `loadRides()`: call `repository.getCustomerRides()`, populate `rides: List<Ride>` state
   - `loadMore()`: fetch with offset, append to list
   - Published state: `rides`, `isLoading`, `hasMore`

2. **UI** — `RideHistoryScreen.kt`:
   - `LazyColumn` with `RideHistoryCard` per ride
   - Card shows: date, pickup → dropoff, status chip, fare amount
   - Empty state: car icon + "No rides yet"
   - "Load More" button when `hasMore`

3. **Integration** — Add "Rides" tab to order history or as separate nav item

### Test Checklist

- [ ] Empty state shows "No rides yet" for new users
- [ ] Completed rides show fare, driver name, distance
- [ ] Cancelled rides show "Cancelled" status in red
- [ ] Pagination works (20+ rides loads next page)
- [ ] Pull-to-refresh works
- [ ] Unauthenticated request returns 401

---

## Task #80 — Post-Ride Earnings Summary (Driver)

### Status: IMPLEMENTED

### How It Works

**ViewModel** — `driver/.../rides/ActiveRideViewModel.kt`:
- `completeRide()` at line 215: calls `repository.completeRide(rideId)`
- On success (line 220-229): sets `phase = RidePhase.COMPLETED`, stores `earnings`, `tip`, `totalEarned`
- Location tracking cancelled on completion (line 221)

**Model** — `shared/.../ApiModels.kt`:
- `RideCompleteResponse` (line 823): `success`, `status`, `earnings: Double`, `tip: Double?`, `totalEarned: Double`

**Repository** — `shared/.../DollorRepository.kt`:
- `completeRide(rideId)` at line 1241 → `POST /api/erp/rides/{id}/complete`

**Backend** — `bid_routes.py:1701-1823`:
- Sets status COMPLETED, calculates platform fee ($1/$2/$3 tiered)
- Calculates `driver_payout = final_price - platform_fee`
- Auto-triggers Stripe Connect transfer
- Returns `earnings` + `total_earned` fields

**UI** — `driver/.../rides/ActiveRideScreen.kt`:
- Completion phase shows earnings amount, tip if present, total earned
- Green checkmark + "Ride Completed!" header

### Test Checklist

- [x] After completing ride, earnings summary appears
- [x] Platform fee correct: $1 for fares ≤$35, $2 for $35-$70, $3 for >$70
- [x] `driver_payout = final_price - platform_fee` math correct
- [x] Tip displays when customer tipped
- [x] Demo rides skip Stripe but still show earnings
- [ ] Detailed earnings breakdown (fare, fee deduction, tip, net) — currently shows summary only

---

## Task #81 — Driver Cancellation Flow

### Status: IMPLEMENTED

### How It Works

**Customer cancel** — `app/.../data/CustomerRideshareApiService.kt`:
- `cancelRideRequest(rideRequestId, reason)` at line 458
- `POST /api/rides/request/{id}/cancel` with optional reason
- Returns `RideStatusResponse` (success + message + status)

**Driver cancel** — `shared/.../DollorRepository.kt`:
- `cancelRide(rideId, reason)` at line 1079
- `POST /api/rides/{id}/cancel`
- Returns `GenericResponse`

**Models** — `shared/.../ApiModels.kt`:
- `CancelRideRequest` (line 737): `reason: String?`

**Customer ViewModel** — `app/.../rideshare/RideRequestViewModel.kt`:
- Cancel called at line 765 via `CustomerRideshareApiService.cancelRideRequest()`

**Backend** — `bid_routes.py:1500-1560`:
- Validates ride is in MATCHED or IN_PROGRESS status
- Reverts ride status to OPEN so other drivers can bid
- Clears `matched_driver_id`
- Sends push notification to customer

### Test Checklist

- [x] Customer can cancel before ride starts
- [x] Driver can cancel active ride
- [x] Ride status reverts to OPEN after driver cancel
- [x] Customer receives push notification
- [x] Cannot cancel completed ride (backend rejects)
- [x] Cannot cancel someone else's ride (ownership check)
- [ ] Predefined cancellation reasons UI (currently free-text only)

---

## Task #82 — No-Show Handling with Timer

### Status: NOT IMPLEMENTED

### What Exists (Backend Only)

**Endpoint** — `bid_routes.py:1565-1632`:
- `POST /api/rides/request/{id}/no-show`
- Validation: ride must be MATCHED, driver must have arrived (`driver_arrived_at` set), must wait 5+ minutes
- If <5 min: returns 400 with "Please wait X more seconds"
- On success: sets status CANCELLED, `cancelled_by = "driver_noshow"`, charges $5 fee, driver gets $4

### What to Build

1. **API call** in `DollorApiService.kt` or `DollorRepository.kt`:
   ```kotlin
   @POST("api/rides/request/{id}/no-show")
   suspend fun markPassengerNoShow(@Path("id") requestId: Int): NoShowResponse
   ```

2. **Timer** in `ActiveRideViewModel.kt` — when phase is `ARRIVED_AT_PICKUP`:
   - Start 300-second countdown using coroutine `delay(1000)` loop
   - Expose `timerSeconds: StateFlow<Int>` to UI
   - Enable "Mark No-Show" button only when timer reaches 0

3. **UI** in `ActiveRideScreen.kt`:
   - Countdown display: "Waiting: 4:32" in orange
   - When expired: "Wait time exceeded" in red
   - "Mark as No-Show" button (disabled until timer hits 0)
   - Confirmation dialog: "The passenger will be charged $5.00. You will receive $4.00."

### Test Checklist

- [ ] Timer starts when driver arrives at pickup
- [ ] Timer counts down from 5:00 to 0:00
- [ ] "Mark as No-Show" hidden while timer running
- [ ] "Mark as No-Show" appears after timer expires
- [ ] Backend rejects if driver hasn't arrived (400)
- [ ] Backend rejects if <5 minutes waited
- [ ] Customer charged $5.00, driver receives $4.00
- [ ] Starting a ride cancels the no-show timer

---

## Task #83 — In-App Chat (Customer ↔ Driver)

### Status: IMPLEMENTED

### How It Works

**Model** — `shared/.../rideshare/RideshareModels.kt`:
- `RideChatMessage` (line 137): `id`, `rideRequestId`, `senderType` (driver/customer), `senderId`, `message`, `createdAt`
- Computed property `isFromDriver` at line 145

**Customer Chat** — `app/.../rideshare/DriverChatScreen.kt`:
- `DriverChatScreen` composable at line 21
- Uses `CustomerRideshareApiService` for API calls

**Customer API** — `app/.../data/CustomerRideshareApiService.kt`:
- `fetchChatMessages(rideRequestId)` at line 531 → `GET /api/p2p/ride-requests/{id}/chat`
- `sendChatMessage(rideRequestId, message)` at line 561 → `POST /api/p2p/ride-requests/{id}/chat`
- Uses `ChatMessagesWrapper` (line 896) to unwrap `{"messages": [], "total": 0}` response
- Sends `sender_type: "customer"` in body

**Driver Chat** — `driver/.../rides/RideChatScreen.kt`:
- `RideChatScreen` composable at line 37
- Full chat UI with message bubbles, send button, phone call action in toolbar
- Auto-scrolls to bottom on new messages (line 46)

**Driver ViewModel** — `driver/.../rides/RideChatViewModel.kt`:
- `startPolling()` at line 116 — polls every 3 seconds for new messages
- Uses `DollorRepository.getRideChatMessages()` + `sendRideChatMessage()`

**Repository** — `shared/.../DollorRepository.kt`:
- `getRideChatMessages(rideRequestId)` at line 843
- `sendRideChatMessage(rideRequestId, message)` at line 852

**Backend** — `main_new.py:15673`:
- `RideChatMessage` table with `ride_request_id`, `sender_type`, `sender_id`, `message`, `created_at`
- GET returns messages ordered by `created_at ASC`
- POST inserts message, determines `sender_id` from auth token

### Test Checklist

- [x] Customer messages appear on right (blue), driver on left (gray)
- [x] Driver messages appear on right, customer on left
- [x] Messages appear within 3 seconds (polling interval)
- [x] Messages persist across app close/reopen
- [x] Chat button visible when driver is assigned
- [x] Phone call button in driver chat toolbar
- [ ] Quick reply buttons ("On my way!", "Be right there") — not yet added
- [ ] Empty state: "No messages yet" — currently shows blank

---

## Task #84 — Driver Online/Offline Toggle

### Status: IMPLEMENTED

### How It Works

**Model** — `shared/.../ApiModels.kt`:
- `DriverProfile.isOnline` at line 868: `@SerializedName("is_online") val isOnline: Boolean`
- `DriverStatusResponse` (line 936): `driverId`, `isOnline`, `driverType`
- `UpdateDriverStatusRequest` (line 942): `isOnline: Boolean`, `driverType: String?`

**Repository** — `shared/.../DollorRepository.kt`:
- `updateDriverStatus(isOnline)` at line 1122 → `PUT /api/driver/{id}/status`
- Sends `UpdateDriverStatusRequest(isOnline)` body

**UI** — `driver/.../profile/ProfileScreen.kt`:
- Toggle switch in driver profile (line 33)
- Shows online/offline status

**Backend** — `main_new.py:2652-2708`:
- `PUT /api/auth/driver/online` — authenticated endpoint
- Blocks unapproved drivers (403 with missing docs message)
- Sets `driver.is_online`, updates `location_updated_at`

### Note

Android uses `PUT /api/driver/{id}/status` while iOS uses `PUT /api/auth/driver/online`. Both work but the iOS endpoint has stricter validation (blocks unapproved drivers). Consider switching Android to the iOS endpoint for consistency.

### Test Checklist

- [x] Toggle shows correct initial state from backend
- [x] Toggling online calls API
- [x] Toggling offline calls API
- [ ] Unapproved driver gets 403 with missing docs message (only if using `/auth/driver/online`)
- [ ] Toggle reverts on API failure
- [ ] Location tracking starts when going online
- [ ] Location tracking stops when going offline

---

## Task #85 — Driver Rates Passenger

### Status: IMPLEMENTED

### How It Works

**ViewModel** — `driver/.../rides/ActiveRideViewModel.kt`:
- `setRating(stars)` at line 241: sets rating 1-5
- `setRatingComment(comment)` at line 245: sets optional comment
- `submitRating()` at line 249: calls `repository.rateRide(rideId, rating, comment)`
- On success: sets `ratingSubmitted = true` (line 264)
- Validates `rating != 0` before submitting (line 251)

**Model** — `shared/.../ApiModels.kt`:
- `RateRideRequest` (line 741): `rating: Int`, `comment: String?`

**Repository** — `shared/.../DollorRepository.kt`:
- `rateRide(rideId, rating, comment)` at line 1353 → `POST /api/rides/{id}/rate`

**Customer Rating** — `app/.../data/CustomerRideshareApiService.kt`:
- `submitRideRating(rideId, rating, comment)` at line 601 → `POST /api/rides/{rideId}/rate`
- `RideRatingResponse` (line 940): `rating: Int?`

**Backend** — `bid_routes.py:1978-2023`:
- Validates ride COMPLETED, rating 1-5, prevents double-rating
- Stores `passenger_rating` and `passenger_comment` on `RideRequest`
- Updates `Customer.rating` with rolling average
- Increments `Customer.total_rides`

### Test Checklist

- [x] Star selector works (tap star 3 → stars 1-3 filled)
- [x] Can submit rating without comment
- [x] Can submit rating with comment
- [x] Rating 0 rejected (client-side check)
- [x] Rating UI hidden after successful submission
- [ ] Double-rating rejected ("Already rated") — backend handles, no client message
- [ ] Customer's average rating updates correctly — verify via API

---

## Task #86 — SOS/Emergency Button (Both Apps)

### Status: PARTIAL — Text only, no button during active rides

### What Exists

**Privacy Screen** — `app/.../privacy/DriverPrivacyScreens.kt`:
- Contains text: "Call 911 for immediate emergencies. Use in-app support for non-emergency issues."
- No actionable SOS button

### What's Missing

Neither the customer ride tracking screen (`RideRequestScreen.kt`) nor the driver active ride screen (`ActiveRideScreen.kt`) has an SOS button.

### What to Build

1. **Customer** — `app/.../rideshare/RideRequestScreen.kt`:
   - Add red SOS IconButton in the ride tracking section (near chat/phone buttons)
   - Confirmation AlertDialog: "Call Emergency Services? This will call 911."
   - On confirm: `Intent(Intent.ACTION_DIAL, Uri.parse("tel:911"))`

2. **Driver** — `driver/.../rides/ActiveRideScreen.kt`:
   - Add red SOS badge in toolbar (next to existing actions)
   - Same confirmation dialog pattern

### Test Checklist

- [ ] SOS button visible during active ride (both apps)
- [ ] Tapping SOS shows confirmation dialog
- [ ] "Cancel" dismisses dialog without calling
- [ ] "Call 911" opens phone dialer with 911
- [ ] Button NOT visible on ride request/selection screens

---

## Task #87 — Share Trip with Contacts

### Status: NOT IMPLEMENTED

### What to Build

1. **Share function** in `app/.../rideshare/RideRequestScreen.kt`:
   ```kotlin
   fun shareTripDetails(context: Context, rideDetails: ...) {
       val shareText = buildString {
           appendLine("I'm on a Dollor ride!")
           appendLine()
           appendLine("From: ${rideDetails.pickupAddress}")
           appendLine("To: ${rideDetails.dropoffAddress}")
           rideDetails.driverName?.let { appendLine("Driver: $it") }
           rideDetails.licensePlate?.let { appendLine("License: $it") }
           appendLine()
           appendLine("Shared via Dollor - dollor.ai")
       }
       val intent = Intent(Intent.ACTION_SEND).apply {
           type = "text/plain"
           putExtra(Intent.EXTRA_TEXT, shareText)
       }
       context.startActivity(Intent.createChooser(intent, "Share ride details"))
   }
   ```

2. **UI**: Add share button (`Icons.Filled.Share`) on ride tracking screen, visible only when driver is assigned

### Test Checklist

- [ ] Share button visible during active ride with driver assigned
- [ ] Share text includes addresses, driver name, license plate
- [ ] Native share sheet opens
- [ ] Can share via Messages, email, social apps
- [ ] Share button NOT visible before driver is assigned

---

## Task #88 — Driver Document Verification Before Bidding

### Status: IMPLEMENTED

### How It Works

**Backend gate** — `bid_routes.py:941-957`:
- Before allowing a bid, checks `driver.status in [APPROVED, ACTIVE]`
- If not approved: returns 403 with specific missing docs list
- "Please upload and verify: driver's license, insurance"

**Document UI** — `driver/.../documents/DocumentsScreen.kt`:
- `DocumentsScreen` composable at line 47
- File picker launcher at line 56
- `viewModel.uploadDocument(context, uri, docType)` at line 61
- Persona verification integration at lines 68-74

**Models** — `shared/.../ApiModels.kt`:
- `DriverDocumentsResponse` (line 908): `driverId`, `documents: List<DriverDocument>`, `count`, `allVerified`
- `DriverDocument` (line 915): `documentType`, `fileName`, `fileUrl`, `uploadDate`, `expiryDate`, `status`, `verified`
- `DocumentUploadResponse` (line 926): `success`, `fileUrl`, `verificationStatus`, `personaInquiryId`

**Profile check** — `shared/.../ApiModels.kt`:
- `DriverProfile.driversLicense` (line 859): Boolean
- `DriverProfile.insurance` (line 861): Boolean
- `DriverProfile.documentsVerified` (line 866): Boolean

### Test Checklist

- [x] Unapproved driver gets 403 when trying to bid
- [x] Error message shows which docs are missing
- [x] Documents upload screen functional
- [x] Approved driver can bid successfully
- [ ] "Upload Documents" button in bid error dialog navigating to documents screen

---

## Task #89 — Background Location Tracking (Driver)

### Status: IMPLEMENTED (foreground coroutine, not full foreground service)

### How It Works

**Active Ride Tracking** — `driver/.../rides/ActiveRideViewModel.kt`:
- `startLocationUpdates()` at line 74
- Uses `FusedLocationProviderClient` with `Priority.PRIORITY_HIGH_ACCURACY` (line 81-82)
- Sends location every 15 seconds (line 93: `delay(15_000L)`)
- Calls `repository.updateDriverLocation(lat, lng)` (line 85)
- Cancelled on ride completion (line 221) or ViewModel cleared (line 71)

**Location API** — `shared/.../DollorRepository.kt`:
- `updateDriverLocation(lat, lng)` at line 1201 → `POST /api/driver/location`

**Models** — `shared/.../ApiModels.kt`:
- `DriverLocationRequest` (line 947): `driverId`, `latitude`, `longitude`, `heading`, `speed`
- `DriverLocationResponse` (line 955): `latitude`, `longitude`, `heading`, `updatedAt`

**Customer Tracking** — `app/.../rideshare/RideRequestViewModel.kt`:
- `locationClient: FusedLocationProviderClient` at line 226
- Used to get customer's current location for ride requests

### Limitations

Current implementation uses a coroutine in `ActiveRideViewModel` — location stops when app is killed. For true background tracking, need:

1. **Foreground Service** with persistent notification ("Dollor Driver - On Ride")
2. `android.permission.FOREGROUND_SERVICE_LOCATION` in manifest
3. `LocationRequest.Builder` with proper interval instead of `getCurrentLocation` loop

### Test Checklist

- [x] Location updates sent every 15 seconds during active ride
- [x] Customer sees driver location on tracking map
- [x] Location tracking stops on ride completion
- [ ] Location continues when app is backgrounded (needs foreground service)
- [ ] Foreground notification shows "Dollor Driver - Online"
- [ ] Battery usage is reasonable

---

## Task #90 — Surge/Dynamic Pricing

### Status: PARTIAL — Time multipliers exist, no surge badge/banner UI

### What Exists

**Time-Based Multipliers** — `shared/.../config/AppConfig.kt`:
- `getTimeMultiplier(hour)` returns `(multiplier, label)`:
  - Morning peak (7-8 AM): +15% "Morning peak"
  - Evening peak (5-6 PM): +20% "Evening peak"
  - Off-peak (10 AM-3 PM): -5% "Off-peak"
- Used in `ScheduleDeliverySheet.kt` for food delivery peak pricing

**Fare Estimate Model** — `shared/.../ApiModels.kt`:
- `RideEstimateResponse` (line 753): has `estimatedFare`, `breakdown: FareBreakdown`
- `FareBreakdown` (line 760): `base`, `distance`, `platformFee`
- **Missing**: `surge_multiplier`, `surge_label`, `is_surging` fields

### What's Missing

1. **Surge fields not in models**: `RideEstimateResponse` lacks `surge_multiplier`, `surge_label`, `is_surging`
2. **No surge badge UI**: No orange badge showing "1.3x High demand" on fare estimate screen
3. **No surge banner**: No "Prices are 30% higher" info banner in fare breakdown

### What to Build

1. **Model update** — Add to `RideEstimateResponse` in `ApiModels.kt`:
   ```kotlin
   @SerializedName("surge_multiplier") val surgeMultiplier: Double? = null,
   @SerializedName("surge_label") val surgeLabel: String? = null,
   @SerializedName("is_surging") val isSurging: Boolean? = null
   ```

2. **ViewModel** — In `RideRequestViewModel.kt`, read surge from estimate response:
   ```kotlin
   _surgeMultiplier.value = estimate.surgeMultiplier ?: 1.0
   _surgeLabel.value = estimate.surgeLabel ?: "Standard"
   ```

3. **UI** — In `RideRequestScreen.kt`:
   - Orange badge: "1.3x" with "High demand" label (only when multiplier > 1.0)
   - Info banner: "Prices are X% higher due to high demand" with flame icon
   - Both hidden when not surging

**Backend already supports this** — `bid_routes.py:121-153`:
- `calculate_demand_multiplier(db)`: ratio of open requests to online drivers
- Returns surge in `/api/rides/estimate` response
- Standalone: `GET /api/rides/surge`

### Test Checklist

- [ ] No surge: badge hidden, no banner
- [ ] Surge 1.15x: badge "1.2x", label "Busy"
- [ ] Surge 1.3x: badge "1.3x", label "High demand"
- [ ] Surge 1.5x (max): badge "1.5x", label "Very high demand"
- [ ] Low demand 0.9x: no badge, prices slightly lower
- [ ] Fare math: `(base + distance + time) * surge + platformFee = total`
- [ ] Surge updates when re-estimating fare

---

## Key Android Files Reference

### Customer App (`:app` module)

| File | Purpose |
|------|---------|
| `app/.../rideshare/RideRequestScreen.kt` | Main customer rideshare UI — ride request, tracking, driver card |
| `app/.../rideshare/RideRequestViewModel.kt` | Customer ride state management — request, bid, cancel, track |
| `app/.../rideshare/DriverChatScreen.kt` | Customer ↔ driver chat UI |
| `app/.../data/CustomerRideshareApiService.kt` | All customer rideshare API calls (OkHttp) |
| `app/.../checkout/ScheduleDeliverySheet.kt` | Peak pricing display (food delivery) |

### Driver App (`:driver` module)

| File | Purpose |
|------|---------|
| `driver/.../rides/ActiveRideViewModel.kt` | Active ride lifecycle — arrive, start, complete, rate, location |
| `driver/.../rides/ActiveRideScreen.kt` | Driver active ride UI — swipe actions, earnings display |
| `driver/.../rides/AvailableRidesScreen.kt` | Browse available ride requests |
| `driver/.../rides/RideChatScreen.kt` | Driver ↔ customer chat UI |
| `driver/.../rides/RideChatViewModel.kt` | Chat polling + message management |
| `driver/.../profile/ProfileScreen.kt` | Driver profile with online/offline toggle |
| `driver/.../profile/ProfileViewModel.kt` | Profile state + status update |
| `driver/.../documents/DocumentsScreen.kt` | Document upload + verification UI |
| `driver/.../earnings/EarningsScreen.kt` | Earnings history display |

### Shared Module (`:shared`)

| File | Purpose |
|------|---------|
| `shared/.../model/ApiModels.kt` | All data classes — Ride, DriverProfile, RideCompleteResponse, etc. |
| `shared/.../model/rideshare/RideshareModels.kt` | RideBid, RideChatMessage, RideStatusResponse |
| `shared/.../data/remote/DollorApiService.kt` | Retrofit API interface definitions |
| `shared/.../data/repository/DollorRepository.kt` | Repository layer — all ride API calls |
| `shared/.../config/AppConfig.kt` | App configuration, time multipliers |

---

## Priority Build Order

Based on user impact and App Store review requirements:

| Priority | Feature | Effort | Impact |
|----------|---------|--------|--------|
| **P0** | Ride History UI (#79) | Medium | App Store review requirement |
| **P0** | SOS Button (#86) | Small | Safety requirement for App Store |
| **P1** | Surge Badge UI (#90) | Small | Fare transparency |
| **P1** | Share Trip (#87) | Small | Safety feature |
| **P2** | No-Show Timer (#82) | Medium | Driver protection |
| **P2** | Foreground Location Service (#89) | Medium | Background reliability |

---

## Build Commands

```bash
cd apps/android

# Debug builds
./gradlew :app:assembleDebug       # Customer
./gradlew :driver:assembleDebug    # Driver

# Production builds
./gradlew :app:assembleRelease     # Customer APK
./gradlew :app:bundleRelease       # Customer AAB (Play Store)
./gradlew :driver:assembleRelease  # Driver APK
```

---

*Last Updated: February 18, 2026*
*Companion doc: `docs/RIDESHARE_TIER1_IMPLEMENTATION.md` (iOS + Backend)*
