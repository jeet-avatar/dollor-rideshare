# Rideshare Tier 1 Features — Full Implementation Guide

> **12 features implemented across Backend (Python/FastAPI), iOS (Swift/SwiftUI), with Android (Kotlin/Jetpack Compose) instructions**
>
> Date: February 18, 2026
> Backend: `apps/web/p2p-platform/backend/`
> iOS Customer: `apps/ios/customer/eatfaircustomer/`
> iOS Driver: `apps/ios/delivery/eatffairdelivery/`
> Android: `apps/android/`

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
13. [Audit Fixes](#audit-fixes)

---

## Task #79 — Ride History UI (Customer)

### Business Requirement

Customers need to see their past rides. Without ride history, users can't verify charges, reference past trips, or dispute billing. Every ride-hailing platform (Uber, Lyft) provides this. It also builds trust — users see exactly what they paid and where they went.

### Why We Did This

- App Store reviewers check for order/ride history during review
- Customers need receipts for expense reports
- Supports dispute resolution ("I was overcharged on ride X")
- Retention: users who see value in past rides are more likely to book again

### How We Did It (Backend)

**Endpoint**: `GET /api/customer/rides/history` — `main_new.py:6213`

- Accepts `limit` (default 20) and `offset` (default 0) for pagination
- Queries `ride_requests` table filtered by `customer_id` from auth token
- Orders by `created_at DESC` (newest first)
- Returns each ride with: pickup/dropoff addresses, status, final price, driver name, date, distance, duration

**Response shape**:
```json
{
  "rides": [
    {
      "id": 42,
      "request_id": "RR-20260218-ABC123",
      "status": "completed",
      "pickup_address": "123 Main St",
      "dropoff_address": "456 Oak Ave",
      "final_price": 24.50,
      "platform_fee": 1.00,
      "tip_amount": 5.00,
      "driver_name": "John D.",
      "created_at": "2026-02-18T10:30:00",
      "distance_miles": 8.2,
      "duration_minutes": 22
    }
  ],
  "total": 15,
  "has_more": false
}
```

### How We Did It (iOS)

**API Method**: `P2PAPIService.getCustomerRideHistory(limit:offset:completion:)` — line 6061

**Models**: `RideHistoryResponse`, `RideHistoryItem` — P2PAPIService.swift:9314-9335

**UI**: `RideHistorySection` in `OrderHistoryView.swift:258-356`
- Segmented picker: "Orders" / "Rides" tabs
- Lazy-loaded list with `RideHistoryCard` for each ride
- "Load More" button for pagination
- Empty state: car icon + "No rides yet"

### Android Implementation

**Where**: `:app` module (Customer app)

1. **API call** — Add to your Retrofit `ApiService`:
   ```kotlin
   @GET("api/customer/rides/history")
   suspend fun getRideHistory(
       @Header("Authorization") token: String,
       @Query("limit") limit: Int = 20,
       @Query("offset") offset: Int = 0
   ): RideHistoryResponse
   ```

2. **Data model** — Create `RideHistoryItem`:
   ```kotlin
   data class RideHistoryResponse(
       val rides: List<RideHistoryItem>,
       val total: Int,
       val has_more: Boolean
   )

   data class RideHistoryItem(
       val id: Int,
       val request_id: String,
       val status: String,
       val pickup_address: String?,
       val dropoff_address: String?,
       val final_price: Double?,
       val platform_fee: Double?,
       val tip_amount: Double?,
       val driver_name: String?,
       val created_at: String?,
       val distance_miles: Double?,
       val duration_minutes: Int?
   )
   ```

3. **ViewModel** — Add `fetchRideHistory()` to existing `OrderHistoryViewModel` or create `RideHistoryViewModel`:
   - Published state: `rides: List<RideHistoryItem>`, `isLoading`, `hasMore`, `currentOffset`
   - `loadRides()`: fetch with offset=0, replace list
   - `loadMore()`: fetch with current offset, append to list

4. **UI** — Add "Rides" tab to order history screen:
   - `LazyColumn` with `RideHistoryCard` composable
   - Card shows: date, pickup → dropoff, status chip, price
   - "Load More" button at bottom when `hasMore`
   - Empty state when no rides

### What to Test

- [ ] First-time user sees empty state with "No rides yet" message
- [ ] After completing a ride, it appears in history (refresh needed)
- [ ] Pagination: create 25+ rides, verify "Load More" fetches next page
- [ ] Cancelled rides show "Cancelled" status in red
- [ ] In-progress rides show "In Progress" in purple
- [ ] Completed rides show correct final price, driver name, distance
- [ ] Pull-to-refresh works
- [ ] Unauthenticated request returns 401

---

## Task #80 — Post-Ride Earnings Summary (Driver)

### Business Requirement

Drivers need to see how much they earned immediately after completing a ride. This is the #1 driver engagement feature — if drivers don't see their earnings clearly, they lose trust and stop driving. The breakdown must show: fare, platform fee deduction, tip, and net earnings.

### Why We Did This

- Transparency: drivers see exactly how the $1-$3 platform fee works
- Motivation: seeing earnings after each ride keeps drivers active
- Trust: no hidden deductions — everything is itemized
- Required for tax reporting (drivers are independent contractors)

### How We Did It (Backend)

**Endpoint**: `POST /api/rides/request/{id}/complete` — `bid_routes.py:1701-1823`

When driver completes a ride, the backend:
1. Sets status to `COMPLETED`, records `completed_at`
2. Calculates platform fee (fare-tiered: $1 ≤$35, $2 $35-$70, $3 >$70)
3. Calculates `driver_payout = final_price - platform_fee`
4. Auto-triggers Stripe Connect transfer to driver (if onboarded)
5. Sends receipt email to customer
6. Sends push notification to customer

**Response shape**:
```json
{
  "success": true,
  "message": "Ride completed",
  "ride": {
    "id": 42,
    "status": "completed",
    "final_price": 24.50,
    "platform_fee": 1.00,
    "driver_payout": 23.50,
    "tip_amount": 5.00,
    "distance_miles": 8.2,
    "duration_minutes": 22,
    "pickup_address": "123 Main St",
    "dropoff_address": "456 Oak Ave"
  }
}
```

### How We Did It (iOS)

**API Method**: `P2PAPIService.completeRideRequest()` — line 5734

**Models**: `RideCompletionResponse`, `RideCompletionDetail` — P2PAPIService.swift:9245-9289

**ViewModel**: `RideBiddingViewModel.completeRide()` — line 472
- Calls API, stores response in `completionData`
- Shows success message with earnings amount

**UI**: `ActiveRideView.rideCompletionSummary` — line 522-589
- Green checkmark + "Ride Completed!" header
- Route summary: pickup → dropoff
- Distance and duration
- Earnings breakdown:
  - Ride Fare (total)
  - Platform Fee (red, deducted)
  - Tip (green, if present)
  - **Your Earnings** (bold green total)

### Android Implementation

**Where**: `:orderapp` module (Driver app)

1. **API call** — The complete ride endpoint already exists. Ensure your response model captures:
   ```kotlin
   data class RideCompletionDetail(
       val final_price: Double?,
       val platform_fee: Double?,
       val driver_payout: Double?,
       val tip_amount: Double?,
       val distance_miles: Double?,
       val duration_minutes: Int?,
       val pickup_address: String?,
       val dropoff_address: String?
   )
   ```

2. **UI** — After `completeRide()` succeeds, show earnings summary dialog/screen:
   ```
   ✓ Ride Completed!

   123 Main St → 456 Oak Ave
   8.2 mi • 22 min

   Ride Fare          $24.50
   Platform Fee       -$1.00
   Tip                +$5.00
   ─────────────────────────
   Your Earnings      $28.50
   ```

3. Use green for positive (tip, total earnings), red for deductions (platform fee)

### What to Test

- [ ] After completing ride, earnings summary appears immediately
- [ ] Platform fee is correct: $1 for fares ≤$35, $2 for $35-$70, $3 for >$70
- [ ] `driver_payout = final_price - platform_fee` (verify math)
- [ ] Tip displays correctly when customer tipped
- [ ] Tip row hidden when tip is $0
- [ ] Pickup and dropoff addresses display correctly
- [ ] Distance and duration display correctly
- [ ] Stripe transfer occurs for onboarded drivers
- [ ] Demo rides skip Stripe but still show earnings

---

## Task #81 — Driver Cancellation Flow

### Business Requirement

Drivers must be able to cancel rides for legitimate reasons (safety, vehicle issue, wrong location). Without this, drivers are trapped in rides they can't complete, leading to support tickets and bad experiences. The ride must be reopened for other drivers.

### Why We Did This

- Safety: drivers need an escape from unsafe situations
- Operational: vehicle breakdowns happen — rider needs to be re-matched
- Legal: independent contractors cannot be forced to complete work
- UX: structured cancellation with reasons helps Dollor identify problem patterns

### How We Did It (Backend)

**Endpoint**: `POST /api/rides/request/{id}/driver-cancel` — `bid_routes.py:1500-1560`

- Validates ride is in MATCHED or IN_PROGRESS status
- Accepts optional `reason` in request body
- Reverts ride status to OPEN so other drivers can bid
- Clears `matched_driver_id`
- Sends push notification to customer: "Your driver cancelled. We're finding a new driver."
- Returns success with reason

### How We Did It (iOS)

**API Method**: `P2PAPIService.driverCancelRide()` — line 5825

**ViewModel**: `RideBiddingViewModel.driverCancelRide()` — line 498
- Calls API with ride ID and reason
- Stops location tracking
- Shows message: "Ride cancelled. The rider will be matched with another driver."

**UI**: `ActiveRideView` toolbar — line 104
- "Cancel" button in navigation bar
- `confirmationDialog` with predefined reasons:
  - Passenger not at pickup
  - Safety concern
  - Vehicle issue
  - Personal emergency
  - Wrong pickup location
  - Other

### Android Implementation

**Where**: `:orderapp` module

1. **API call**:
   ```kotlin
   @POST("api/rides/request/{id}/driver-cancel")
   suspend fun driverCancelRide(
       @Path("id") requestId: Int,
       @Header("Authorization") token: String,
       @Body body: Map<String, String>  // {"reason": "Safety concern"}
   ): GenericResponse
   ```

2. **ViewModel**: Add `cancelRide(requestId, reason)` method
   - Call API → on success, navigate back to available rides
   - Stop location tracking

3. **UI**: Add "Cancel Ride" option in ride action menu
   - Show bottom sheet with cancellation reasons (same list as iOS)
   - Confirm dialog before cancelling
   - After cancel, return to ride list

### What to Test

- [ ] Cancel button visible during active ride
- [ ] Cancellation reasons dialog shows all 6 options
- [ ] After cancellation, ride status reverts to OPEN in backend
- [ ] Customer receives push notification about cancellation
- [ ] Driver returns to available rides screen
- [ ] Cannot cancel an already completed ride (400 error)
- [ ] Cannot cancel someone else's ride (403 error)
- [ ] Location tracking stops after cancellation

---

## Task #82 — No-Show Handling with Timer

### Business Requirement

When a driver arrives at pickup and the passenger doesn't show up, the driver shouldn't wait indefinitely. After a 5-minute wait, the driver can mark the passenger as no-show. The passenger is charged a $5.00 cancellation fee (driver receives $4.00). This protects driver time and deters passengers from requesting rides they don't intend to take.

### Why We Did This

- Driver compensation: waiting at pickup costs money (gas, time, missed rides)
- Accountability: passengers who no-show face a fee, reducing repeat offenses
- Fair split: driver gets 80% of no-show fee ($4 of $5)
- 5-minute minimum: prevents premature no-show reports

### How We Did It (Backend)

**Endpoint**: `POST /api/rides/request/{id}/no-show` — `bid_routes.py:1565-1632`

**Constant**: `NOSHOW_CANCELLATION_FEE = 5.00`

Validation chain:
1. Ride must be in MATCHED status
2. Driver must have arrived first (`driver_arrived_at` must be set)
3. Must have waited 5+ minutes (`wait_seconds >= 300`)
4. If <5 min: returns 400 with "Please wait X more seconds"

On success:
- Sets status to CANCELLED
- Sets `cancelled_by = "driver_noshow"`
- Records `cancellation_fee = $5.00`
- Records `driver_payout = $4.00` (80%)
- Sends push notification to customer

### How We Did It (iOS)

**API Method**: `P2PAPIService.markPassengerNoShow()` — line 5870

**ViewModel**: `RideBiddingViewModel.markPassengerNoShow()` — line 523
- Calls API, shows message: "No-show confirmed. You earned $4.00 for your wait time."

**UI**: `ActiveRideView` — arrived at pickup state (lines 435-491)

Timer implementation:
- `@State noShowTimerSeconds = 300` (5 minutes)
- `@State noShowTimerActive = false`
- Timer uses `Timer.publish(every: 1)` with Combine sink
- Countdown display: "Waiting: 4:32" (orange) → "Wait time exceeded" (red)
- "Mark as No-Show" button appears ONLY after timer hits 0
- Confirmation alert: "The passenger will be charged a $5.00 cancellation fee. You will receive $4.00."

### Android Implementation

**Where**: `:orderapp` module

1. **API call**:
   ```kotlin
   @POST("api/rides/request/{id}/no-show")
   suspend fun markPassengerNoShow(
       @Path("id") requestId: Int,
       @Header("Authorization") token: String
   ): NoShowResponse

   data class NoShowResponse(
       val success: Boolean,
       val message: String,
       val cancellation_fee: Double,
       val driver_payout: Double
   )
   ```

2. **Timer** — Use `CountDownTimer` or coroutine-based timer:
   ```kotlin
   private var noShowTimer: CountDownTimer? = null
   private val _timerSeconds = MutableStateFlow(300)

   fun startNoShowTimer() {
       noShowTimer = object : CountDownTimer(300_000L, 1000L) {
           override fun onTick(millisUntilFinished: Long) {
               _timerSeconds.value = (millisUntilFinished / 1000).toInt()
           }
           override fun onFinish() {
               _timerSeconds.value = 0
           }
       }.start()
   }
   ```

3. **UI**:
   - Show countdown when driver status is "arrived at pickup"
   - Format: `MM:SS` countdown in orange
   - When timer reaches 0: show "Mark as No-Show" button in red
   - Confirmation dialog before marking

### What to Test

- [ ] Timer starts automatically when driver arrives at pickup
- [ ] Timer counts down from 5:00 to 0:00
- [ ] "Mark as No-Show" button hidden while timer is running
- [ ] "Mark as No-Show" button appears after timer expires
- [ ] Backend rejects no-show if driver hasn't arrived (400)
- [ ] Backend rejects no-show if <5 minutes waited (400 with remaining time)
- [ ] Customer charged $5.00 cancellation fee
- [ ] Driver receives $4.00 payout
- [ ] Customer receives push notification
- [ ] Starting a ride cancels the no-show timer

---

## Task #83 — In-App Chat (Customer ↔ Driver)

### Business Requirement

During a ride, customers and drivers need to communicate ("I'm at the side entrance", "Running 2 minutes late"). Phone calls are intrusive and share personal phone numbers. In-app chat keeps communication within the platform, maintains privacy, and creates an audit trail for disputes.

### Why We Did This

- Privacy: no phone number sharing needed
- Audit trail: all messages are stored for dispute resolution
- Convenience: quick text is less disruptive than a phone call
- Safety: messages can be reviewed if there's an incident
- Platform engagement: keeps users inside the app

### How We Did It (Backend)

**Model**: `RideChatMessage` — `models.py` (new table)
```python
class RideChatMessage(Base):
    __tablename__ = "ride_chat_messages"
    id = Column(Integer, primary_key=True, index=True)
    ride_request_id = Column(Integer, ForeignKey("ride_requests.id"), nullable=False, index=True)
    sender_type = Column(String(20), nullable=False)  # 'customer' or 'driver'
    sender_id = Column(Integer, nullable=False)
    message = Column(Text, nullable=False)
    created_at = Column(DateTime, default=datetime.utcnow)
```

**Endpoints** — `main_new.py:15673`

GET `/api/p2p/ride-requests/{ride_request_id}/chat`:
- Queries `ride_chat_messages` ordered by `created_at ASC`
- Returns array of messages with id, sender_type, sender_id, message, created_at

POST `/api/p2p/ride-requests/{ride_request_id}/chat`:
- Accepts `{ "message": "...", "sender_type": "customer"|"driver" }`
- Determines `sender_id` from auth token (customer_id or driver_id)
- Inserts into database, returns the created message

**Migration**: Table `ride_chat_messages` created on startup + index on `ride_request_id`

### How We Did It (iOS)

**API Methods** — `P2PAPIService.swift:6718-6767`:
- `fetchRideChatMessages(rideRequestId:completion:)` — GET
- `sendRideChatMessage(rideRequestId:message:senderType:completion:)` — POST

**Model**: `RideChatMessage` in shared package with `isFromDriver` computed property

**Customer Chat View**: `DriverChatView.swift`
- Full chat UI with message bubbles (customer=blue/right, driver=gray/left)
- 3-second polling for new messages
- Text input with send button
- Quick message buttons ("On my way!", "Be right there", etc.)
- `senderType: "customer"`

**Integration**: `RideRequestView.swift`
- Blue chat button next to phone button in accepted driver section
- Opens `DriverChatView` in sheet
- Visible when `activeRide?.rideId != nil`

**Driver Chat View**: Already existed as `RiderChatView.swift` using same API methods with `senderType: "driver"`

### Android Implementation

**Where**: `:app` module (Customer) and `:orderapp` module (Driver)

1. **API calls**:
   ```kotlin
   @GET("api/p2p/ride-requests/{id}/chat")
   suspend fun getChatMessages(
       @Path("id") rideRequestId: Int,
       @Header("Authorization") token: String
   ): ChatMessagesResponse

   @POST("api/p2p/ride-requests/{id}/chat")
   suspend fun sendChatMessage(
       @Path("id") rideRequestId: Int,
       @Header("Authorization") token: String,
       @Body body: SendChatRequest
   ): SendChatResponse

   data class ChatMessage(
       val id: Int,
       val ride_request_id: Int,
       val sender_type: String,
       val sender_id: Int,
       val message: String,
       val created_at: String
   )

   data class ChatMessagesResponse(
       val ride_request_id: Int,
       val messages: List<ChatMessage>,
       val total: Int
   )

   data class SendChatRequest(
       val message: String,
       val sender_type: String  // "customer" or "driver"
   )
   ```

2. **ViewModel**:
   ```kotlin
   class RideChatViewModel : ViewModel() {
       private val _messages = MutableStateFlow<List<ChatMessage>>(emptyList())
       val messages: StateFlow<List<ChatMessage>> = _messages

       private var pollingJob: Job? = null

       fun startPolling(rideRequestId: Int) {
           pollingJob = viewModelScope.launch {
               while (isActive) {
                   fetchMessages(rideRequestId)
                   delay(3000) // 3-second polling
               }
           }
       }

       fun sendMessage(rideRequestId: Int, message: String, senderType: String) {
           // POST to API, then refresh messages
       }

       fun stopPolling() { pollingJob?.cancel() }
   }
   ```

3. **UI** — Chat screen with:
   - `LazyColumn` (reversed) for message list
   - Message bubbles: user's messages on right (blue), other on left (gray)
   - Text field + send button at bottom
   - Quick reply chips above text field
   - Chat button on ride tracking screen (next to phone button)

### What to Test

- [ ] Messages persist across app close/reopen
- [ ] Customer sees own messages on right (blue), driver on left (gray)
- [ ] Driver sees own messages on right, customer on left
- [ ] Messages appear within 3 seconds (polling interval)
- [ ] Empty state: "No messages yet. Say hi!"
- [ ] Message limit: 1000 characters max
- [ ] Quick reply buttons send the correct text
- [ ] Chat button only visible when driver is assigned
- [ ] Messages ordered by created_at ascending
- [ ] Cannot send empty messages

---

## Task #84 — Driver Online/Offline Toggle

### Business Requirement

Drivers must be able to go online (available for rides) and offline (not accepting rides). This is fundamental to any ride-hailing platform. The toggle controls whether the driver appears in search results and receives ride requests. Unapproved drivers cannot go online.

### Why We Did This

- Operational control: drivers choose when they work
- Legal: independent contractor model requires voluntary work hours
- Quality: only verified drivers should receive ride requests
- Safety: unapproved drivers are blocked from going online

### How We Did It (Backend)

**Endpoint**: `PUT /api/auth/driver/online` — `main_new.py:2652-2708`

- Accepts `is_online` as query param or body field
- Requires authentication (driver token)
- **Blocks unapproved drivers**: checks `driver.status` against `[APPROVED, ACTIVE]`
  - If not approved, returns 403 with specific missing docs
  - "Please upload and verify: driver's license, insurance"
  - Or "Your documents are pending verification. You'll be notified when approved."
- Sets `driver.is_online`, updates `location_updated_at` and `went_online_at`
- Returns `{"success": true, "is_online": true}`

### How We Did It (iOS)

**API Method**: `P2PAPIService.setDriverOnlineStatus(isOnline:completion:)` — line 4401
- Uses `PUT /auth/driver/online?is_online={bool}`
- Authenticated with driver token
- **NOT** the admin-only `updateDriverOnlineStatus` endpoint

**ViewModels**:
- `DeliveryViewModel.setOnlineStatus()` — line 135 (food delivery mode)
- `RideBiddingViewModel.setOnlineStatus()` — line 98 (rideshare mode)
- Both: call API → update `isOnline` → start/stop location tracking → revert on failure

**UI**:
- `AvailableOrdersView.swift` — toggle banner with green/red dot + status text + Toggle switch
- `RideshareDashboardView.swift` — inline HStack toggle above ride list

### Android Implementation

**Where**: `:orderapp` module

1. **API call** — May already exist. Verify it uses the authenticated endpoint:
   ```kotlin
   @PUT("api/auth/driver/online")
   suspend fun setDriverOnlineStatus(
       @Header("Authorization") token: String,
       @Query("is_online") isOnline: Boolean
   ): OnlineStatusResponse
   ```
   **IMPORTANT**: Do NOT use `/api/erp/drivers/{id}` — that's admin-only.

2. **ViewModel**:
   ```kotlin
   fun setOnlineStatus(online: Boolean) {
       viewModelScope.launch {
           val previousState = _isOnline.value
           _isOnline.value = online

           // Start/stop location tracking
           if (online) locationManager.startTracking()
           else locationManager.stopTracking()

           try {
               api.setDriverOnlineStatus(token, online)
           } catch (e: Exception) {
               // Revert on failure
               _isOnline.value = previousState
               if (previousState) locationManager.startTracking()
               else locationManager.stopTracking()

               _errorMessage.value = e.message
           }
       }
   }
   ```

3. **UI**: Toggle switch in toolbar or banner
   - Green dot + "Online" when active
   - Red dot + "Offline" when inactive
   - Handle 403 error: show "Documents required" dialog

### What to Test

- [ ] Toggle shows correct initial state from backend
- [ ] Toggling online → API called → backend `is_online = true`
- [ ] Toggling offline → API called → backend `is_online = false`
- [ ] Unapproved driver gets 403 with missing docs message
- [ ] Toggle reverts on API failure
- [ ] Location tracking starts when going online
- [ ] Location tracking stops when going offline
- [ ] Driver appears in surge calculation when online
- [ ] Driver disappears from available drivers when offline

---

## Task #85 — Driver Rates Passenger

### Business Requirement

Two-way ratings create accountability. Drivers rate passengers to flag problematic riders (aggressive, no-shows, rude). Future matching can use passenger ratings to protect drivers. This is standard in Uber/Lyft and expected by drivers.

### Why We Did This

- Driver safety: flag and avoid problematic passengers
- Platform quality: low-rated passengers may face restrictions
- Fairness: both sides can rate each other
- Data: identifies patterns (e.g., passenger consistently rated low → review account)

### How We Did It (Backend)

**Endpoint**: `POST /api/rides/request/{id}/rate-passenger` — `bid_routes.py:1978-2023`

**Pydantic model**: `PassengerRatingRequest` with `rating: int` (1-5) and `comment: Optional[str]`

Logic:
1. Validates ride exists and is COMPLETED
2. Validates rating 1-5
3. Prevents double-rating (checks if `passenger_rating` already set)
4. Stores `passenger_rating` and `passenger_comment` on `RideRequest`
5. Updates `Customer.rating` with rolling average: `new = (current * total + rating) / (total + 1)`
6. Increments `Customer.total_rides`

**New DB columns**:
- `ride_requests.passenger_rating` (Integer)
- `ride_requests.passenger_comment` (Text)
- `customers.rating` (Float, default 5.0)
- `customers.total_rides` (Integer, default 0)

### How We Did It (iOS)

**API Method**: `P2PAPIService.ratePassenger()` — line 5957

**ViewModel**: `RideBiddingViewModel.ratePassenger()` — line 549

**UI**: `ActiveRideView` completion section — lines 623-653
- 5-star selector (tap to select rating)
- Comment text field (optional)
- "Submit Rating" button
- Success message: "Rating submitted!"
- Hidden after submission (`hasSubmittedRating` flag)

### Android Implementation

**Where**: `:orderapp` module

1. **API call**:
   ```kotlin
   @POST("api/rides/request/{id}/rate-passenger")
   suspend fun ratePassenger(
       @Path("id") requestId: Int,
       @Header("Authorization") token: String,
       @Body body: RatePassengerRequest
   ): GenericResponse

   data class RatePassengerRequest(
       val rating: Int,  // 1-5
       val comment: String? = null
   )
   ```

2. **UI**: After ride completion, show rating section:
   - 5 star icons (filled/unfilled based on selection)
   - Optional comment TextField
   - "Submit" button
   - Hide after submission

### What to Test

- [ ] Star selector works (tap star 3 → stars 1-3 filled)
- [ ] Can submit rating without comment
- [ ] Can submit rating with comment
- [ ] Rating 0 or 6 rejected by backend (400)
- [ ] Double-rating rejected ("Already rated")
- [ ] Customer's average rating updates correctly
- [ ] Rating only available after ride completion
- [ ] Rating UI hidden after successful submission

---

## Task #86 — SOS/Emergency Button (Both Apps)

### Business Requirement

Safety is paramount. Both customers and drivers need a way to quickly call emergency services (911) during a ride. The button must be prominent but require confirmation to prevent accidental calls.

### Why We Did This

- Safety requirement for all ride-hailing platforms
- App Store/Play Store review expectation
- Legal compliance: duty of care for platform users
- Trust: users feel safer knowing emergency help is one tap away

### How We Did It (iOS)

**Customer** — `RideRequestView.swift` (RideTrackingView):
- Red SOS circle button in top-right corner of tracking view
- `@State showSOSAlert = false`
- Confirmation alert: "Call 911? This will call emergency services."
- On confirm: `UIApplication.shared.open(URL(string: "tel://911")!)`

**Driver** — `ActiveRideView.swift`:
- Red SOS badge in toolbar (next to chat button)
- `@State showSOSAlert = false`
- Same confirmation alert pattern
- Same `tel://911` action

### Android Implementation

**Where**: Both `:app` and `:orderapp` modules

1. **Customer** — Add SOS button to ride tracking screen:
   ```kotlin
   @Composable
   fun SOSButton() {
       var showAlert by remember { mutableStateOf(false) }

       IconButton(onClick = { showAlert = true }) {
           Icon(
               Icons.Filled.Warning,
               contentDescription = "Emergency",
               tint = Color.White,
               modifier = Modifier
                   .background(Color.Red, CircleShape)
                   .padding(8.dp)
           )
       }

       if (showAlert) {
           AlertDialog(
               onDismissRequest = { showAlert = false },
               title = { Text("Call Emergency Services?") },
               text = { Text("This will call 911. Only use in genuine emergencies.") },
               confirmButton = {
                   TextButton(onClick = {
                       val intent = Intent(Intent.ACTION_DIAL, Uri.parse("tel:911"))
                       context.startActivity(intent)
                       showAlert = false
                   }) { Text("Call 911", color = Color.Red) }
               },
               dismissButton = {
                   TextButton(onClick = { showAlert = false }) { Text("Cancel") }
               }
           )
       }
   }
   ```

2. Place in both Customer ride tracking and Driver active ride screens

### What to Test

- [ ] SOS button visible during active ride (both apps)
- [ ] Tapping SOS shows confirmation dialog
- [ ] "Cancel" dismisses dialog without calling
- [ ] "Call 911" opens phone dialer with 911
- [ ] Button is NOT visible on ride request/selection screens (only during active ride)
- [ ] Button is prominent but not so large it's accidentally tapped

---

## Task #87 — Share Trip with Contacts

### Business Requirement

Customers want to share their ride details with friends/family for safety. "I'm in an Uber, here are the details" is extremely common. Sharing ride info (route, driver name, license plate) provides a safety net.

### Why We Did This

- Safety: loved ones know your route and driver
- Trust: feature expected by users from Uber/Lyft
- Marketing: shared rides include "via Dollor" branding
- Peace of mind: especially for late-night rides

### How We Did It (iOS)

**Share text** — `RideRequestView.swift`, computed property `tripShareText`:
```
I'm on a Dollor ride!

Ride #RR-20260218-ABC123
From: 123 Main St
To: 456 Oak Ave
Driver: John D. (ABC-1234)

Shared via Dollor - dollor.ai
```

**Share sheet** — `ShareTripActivityView` (UIViewControllerRepresentable wrapping UIActivityViewController)

**UI**: Blue share button below SOS button in RideTrackingView
- Opens native iOS share sheet
- Can share via Messages, WhatsApp, email, etc.

### Android Implementation

**Where**: `:app` module

1. **Share text**: Build the same formatted string
2. **Share intent**:
   ```kotlin
   fun shareTripDetails(context: Context, rideDetails: RideDetails) {
       val shareText = buildString {
           appendLine("I'm on a Dollor ride!")
           appendLine()
           appendLine("Ride #${rideDetails.requestId}")
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

3. **UI**: Add share button (icon: `Icons.Filled.Share`) on ride tracking screen

### What to Test

- [ ] Share button visible during active ride with driver assigned
- [ ] Share text includes ride number, addresses, driver name
- [ ] Share text includes license plate when available
- [ ] Native share sheet opens with correct text
- [ ] Can share via Messages, email, social apps
- [ ] Share button NOT visible before driver is assigned

---

## Task #88 — Driver Document Verification Before Bidding

### Business Requirement

Only approved drivers with verified documents should be able to bid on rides. This is a safety and legal requirement. Unapproved drivers bidding on rides creates liability and safety risks.

### Why We Did This

- Safety: unverified drivers should never transport passengers
- Legal: Dollor must ensure all drivers meet requirements
- Quality: prevents new signups from immediately bidding without docs
- Compliance: insurance, license verification required in most jurisdictions

### How We Did It (Backend)

**Location**: `bid_routes.py`, `submit_bid` function (lines 941-957)

Before allowing a bid:
```python
driver_status = driver.status if isinstance(driver.status, DriverStatus) else DriverStatus(driver.status)
if driver_status not in [DriverStatus.APPROVED, DriverStatus.ACTIVE]:
    missing_docs = []
    if not driver.drivers_license: missing_docs.append("driver's license")
    if not driver.insurance: missing_docs.append("insurance")
    if not driver.photo_url: missing_docs.append("profile photo")

    if missing_docs:
        detail = f"Please upload and verify: {', '.join(missing_docs)}"
    else:
        detail = "Your documents are pending verification."

    raise HTTPException(status_code=403, detail=detail)
```

### How We Did It (iOS)

**ViewModel**: `RideBiddingViewModel.submitBid()` error handler — line 279
- Detects verification keywords: "upload", "verify", "pending verification", "approved"
- Shows the backend error message directly to the driver
- Driver sees: "Please upload and verify: driver's license, insurance"

### Android Implementation

**Where**: `:orderapp` module

1. The backend already returns 403 with a descriptive message
2. In your bid submission error handler:
   ```kotlin
   fun submitBid(requestId: Int, amount: Double) {
       viewModelScope.launch {
           try {
               api.submitBid(requestId, token, BidRequest(amount))
           } catch (e: HttpException) {
               if (e.code() == 403) {
                   val errorBody = e.response()?.errorBody()?.string()
                   // Parse "detail" field from JSON error
                   val detail = parseErrorDetail(errorBody)
                   _errorMessage.value = detail
                   // Optionally navigate to document upload screen
               }
           }
       }
   }
   ```

3. Show a dialog with the error message and a "Upload Documents" button linking to the documents screen

### What to Test

- [ ] Unapproved driver with no docs: sees "Please upload and verify: driver's license, insurance, profile photo"
- [ ] Unapproved driver with partial docs: sees only missing items
- [ ] Driver with all docs but pending approval: sees "pending verification" message
- [ ] Approved driver can bid successfully
- [ ] Active driver can bid successfully
- [ ] Error message displays correctly in UI (not a generic error)

---

## Task #89 — Background Location Tracking (Driver)

### Business Requirement

Drivers need continuous location tracking even when the app is in the background. This enables real-time tracking by customers, accurate ETA calculations, and location-based ride matching. Without background tracking, the customer map goes stale when the driver switches apps.

### Why We Did This

- Customer experience: live driver location on map
- ETA accuracy: requires continuous GPS data
- Safety: platform knows driver's location during rides
- Ride matching: nearby drivers get priority for new requests

### How We Did It (iOS)

**LocationManager.swift** — already had full background location infrastructure:
- `allowsBackgroundLocationUpdates = true`
- `pausesLocationUpdatesAutomatically = false`
- `showsBackgroundLocationIndicator = true`
- `activityType = .automotiveNavigation`

**What was missing**: `requestAlwaysAuthorization()` was defined but never called

**Fix**: Added auto-upgrade in `startTracking()`:
```swift
if authorizationStatus == .authorizedWhenInUse {
    requestAlwaysPermission()  // Upgrade to Always for background
}
```

**Integration**: Both ViewModels now start/stop location tracking on online toggle:
- `DeliveryViewModel.setOnlineStatus()` — calls `LocationManager.shared.startTracking()`/`stopTracking()`
- `RideBiddingViewModel.setOnlineStatus()` — same pattern
- On API failure: reverts location tracking to previous state

### Android Implementation

**Where**: `:orderapp` module

1. **Foreground Service** — Android requires a foreground service for continuous location:
   ```kotlin
   class LocationTrackingService : Service() {
       private lateinit var fusedLocationClient: FusedLocationProviderClient

       override fun onCreate() {
           fusedLocationClient = LocationServices.getFusedLocationProviderClient(this)
           startForeground(NOTIFICATION_ID, createNotification())
       }

       private fun startLocationUpdates() {
           val request = LocationRequest.Builder(
               Priority.PRIORITY_HIGH_ACCURACY, 5000L  // 5 second interval
           ).setMinUpdateDistanceMeters(10f).build()

           fusedLocationClient.requestLocationUpdates(request, locationCallback, Looper.getMainLooper())
       }

       private val locationCallback = object : LocationCallback() {
           override fun onLocationResult(result: LocationResult) {
               result.lastLocation?.let { location ->
                   // Send to backend via API
                   sendLocationToBackend(location.latitude, location.longitude)
               }
           }
       }
   }
   ```

2. **Permissions** — AndroidManifest.xml:
   ```xml
   <uses-permission android:name="android.permission.ACCESS_FINE_LOCATION" />
   <uses-permission android:name="android.permission.ACCESS_BACKGROUND_LOCATION" />
   <uses-permission android:name="android.permission.FOREGROUND_SERVICE" />
   <uses-permission android:name="android.permission.FOREGROUND_SERVICE_LOCATION" />
   ```

3. **Start/Stop** — Tie to online/offline toggle:
   ```kotlin
   fun setOnlineStatus(online: Boolean) {
       if (online) {
           startService(Intent(context, LocationTrackingService::class.java))
       } else {
           stopService(Intent(context, LocationTrackingService::class.java))
       }
   }
   ```

### What to Test

- [ ] Location updates continue when app is backgrounded
- [ ] Location indicator appears in iOS status bar (blue pill)
- [ ] Android foreground notification shows "Dollor Driver - Online"
- [ ] Location updates sent to backend every 5 seconds
- [ ] Location tracking starts when going online
- [ ] Location tracking stops when going offline
- [ ] Customer sees live driver location on tracking map
- [ ] Battery usage is reasonable (check in Settings)
- [ ] "Always" permission requested on first online toggle (iOS)
- [ ] Background location permission requested (Android 11+)

---

## Task #90 — Surge/Dynamic Pricing

### Business Requirement

When demand exceeds supply (many ride requests, few drivers), prices should increase to incentivize more drivers to come online and balance the market. Surge pricing is transparent — customers see exactly why prices are higher and by how much. Maximum surge is capped at 1.5x to prevent gouging.

### Why We Did This

- Market balancing: higher prices attract more drivers during peak demand
- Transparency: customers make informed decisions about whether to ride now or wait
- Fair compensation: drivers earn more during difficult/busy periods
- Capped at 1.5x: prevents price gouging (Uber has gone to 9x+)
- Low demand discount: 0.9x when many drivers, few requests

### How We Did It (Backend)

**Demand calculation**: `calculate_demand_multiplier(db)` — `bid_routes.py:121-153`

```
ratio = open_ride_requests / online_drivers

ratio >= 3.0  →  1.5x  "Very high demand"
ratio >= 2.0  →  1.3x  "High demand"
ratio >= 1.5  →  1.15x "Busy"
ratio <= 0.3  →  0.9x  "Low demand"
otherwise     →  1.0x  "Standard"

0 drivers + requests  →  1.5x  "High demand"
0 drivers + 0 requests → 1.0x  "Standard"
```

**Integration points**:

1. `POST /api/rides/estimate` — fare estimate now includes surge
   - Added `db: Session = Depends(get_db)` parameter
   - Calls `calculate_demand_multiplier(db)`
   - Applies surge to subtotal, total, driver earnings, suggested bids
   - Returns `surge_multiplier`, `surge_label`, `is_surging` in response
   - **NOTE**: `breakdown` fields (baseFare, distanceCost, timeCost) are NOT surge-adjusted — they remain raw values

2. `POST /api/rides/request` — ride creation applies surge to suggested price

3. `GET /api/rides/surge` — standalone surge check endpoint

**Response from /rides/estimate** (new fields):
```json
{
  "estimate": {
    "breakdown": { "base_fare": 3.0, "distance_cost": 12.0, "time_cost": 5.0 },
    "subtotal": 26.00,
    "total": 27.00,
    "surge_multiplier": 1.3,
    "surge_label": "High demand",
    "is_surging": true
  }
}
```

### How We Did It (iOS)

**Shared models** — `P2PAPIService.swift`:
- Added `surgeMultiplier: Double?`, `surgeLabel: String?`, `isSurging: Bool?` to `RideFareEstimate`
- Added `SurgeStatusResponse` model + `getSurgeStatus()` method

**ViewModel** — `RideRequestViewModel.swift`:
- Added `surgeLabel: String` published property
- `estimateFare()` reads surge from API response (no extra API call needed)
- Computed properties apply `* surgeMultiplier` to raw breakdown values
- **IMPORTANT**: Backend returns raw breakdown values. iOS applies surge once in computed properties. No double-surge.

**UI** — `RideRequestView.swift`:
- Orange surge badge: "1.3x" with label "High demand" below
- Surge info banner in fare breakdown: "Prices are 30% higher due to high demand" with flame icon
- Both hidden when `surgeMultiplier <= 1.0`

### Android Implementation

**Where**: `:app` module (Customer)

1. **Model update** — Add surge fields to fare estimate response:
   ```kotlin
   data class FareEstimate(
       // ... existing fields ...
       val surge_multiplier: Double? = null,
       val surge_label: String? = null,
       val is_surging: Boolean? = null
   )
   ```

2. **ViewModel** — Apply surge from estimate response:
   ```kotlin
   fun estimateFare() {
       viewModelScope.launch {
           val response = api.estimateRideFare(...)
           val estimate = response.estimate

           _baseFare.value = estimate.breakdown.base_fare
           _distanceFee.value = estimate.breakdown.distance_cost
           _timeFee.value = estimate.breakdown.time_cost
           _surgeMultiplier.value = estimate.surge_multiplier ?: 1.0
           _surgeLabel.value = estimate.surge_label ?: "Standard"
       }
   }

   // Apply surge in computed total (same pattern as iOS)
   val fareBeforeTax: Double
       get() = (baseFare + distanceFee + timeFee) * surgeMultiplier + platformFee
   ```

3. **UI** — Surge indicator:
   ```kotlin
   @Composable
   fun SurgeBadge(multiplier: Double, label: String) {
       if (multiplier > 1.0) {
           Column(horizontalAlignment = Alignment.CenterHorizontally) {
               Text(
                   "${String.format("%.1f", multiplier)}x",
                   color = Color.White,
                   fontWeight = FontWeight.Bold,
                   modifier = Modifier
                       .background(Color(0xFFFF9800), RoundedCornerShape(6.dp))
                       .padding(horizontal = 8.dp, vertical = 4.dp)
               )
               Text(label, fontSize = 10.sp, color = Color(0xFFFF9800))
           }
       }
   }

   // Surge banner in fare breakdown
   if (surgeMultiplier > 1.0) {
       Row(modifier = Modifier
           .fillMaxWidth()
           .background(Color(0xFFFF9800).copy(alpha = 0.1f), RoundedCornerShape(8.dp))
           .padding(8.dp)
       ) {
           Icon(Icons.Filled.Whatshot, tint = Color(0xFFFF9800))
           Text(
               "Prices are ${((surgeMultiplier - 1) * 100).toInt()}% higher due to ${surgeLabel.lowercase()}",
               color = Color(0xFFFF9800),
               fontSize = 12.sp
           )
       }
   }
   ```

### What to Test

- [ ] No surge: multiplier = 1.0, badge hidden, no banner
- [ ] Surge 1.15x: badge shows "1.2x", label "Busy", banner shows "15% higher"
- [ ] Surge 1.3x: badge shows "1.3x", label "High demand"
- [ ] Surge 1.5x (max): badge shows "1.5x", label "Very high demand"
- [ ] Low demand 0.9x: no badge (0.9 < 1.0), prices slightly lower
- [ ] Fare breakdown numbers match: `(base + distance + time) * surge + platformFee = total`
- [ ] No double-surge: iOS computed total matches backend total
- [ ] `GET /rides/surge` returns current surge info
- [ ] Surge updates when re-estimating fare (not cached)
- [ ] Suggested bids in fare estimate are surge-adjusted

---

## Audit Fixes

During the pre-push audit, two issues were found and fixed:

### Fix 1: Chat Backend Persistence (HIGH)

**Problem**: The ride chat GET/POST endpoints were mock stubs returning empty data. No `RideChatMessage` table existed. Messages were not persisted — they'd be lost on app close.

**Fix**:
1. Added `RideChatMessage` model to `models.py` with columns: `id`, `ride_request_id`, `sender_type`, `sender_id`, `message`, `created_at`
2. Replaced mock GET endpoint with real DB query (ordered by `created_at ASC`)
3. Replaced mock POST endpoint with real DB insert (determines `sender_id` from auth token)
4. Added `ride_chat_messages` table + index to startup migrations

**Files changed**: `models.py`, `main_new.py`

### Fix 2: Surge Pattern Documentation (MEDIUM)

**Problem**: Backend applies surge to `subtotal`/`total` but NOT to `breakdown` fields. iOS reads raw breakdown values and applies `* surgeMultiplier` in computed properties. This is correct but fragile — if backend ever starts adjusting breakdown fields, iOS would double-apply surge.

**Fix**: Added protective comment to `RideRequestViewModel.fareBeforeTax`:
```swift
/// NOTE: Backend /rides/estimate returns breakdown values (baseFare, distanceFee, timeFee) WITHOUT surge.
/// Surge is applied here to raw breakdown values. Do NOT remove surgeMultiplier unless backend changes.
```

**Files changed**: `RideRequestViewModel.swift`

---

## Files Modified (Complete List)

### Backend
| File | Changes |
|------|---------|
| `bid_routes.py` | driver-cancel, no-show, rate-passenger, surge calculation, doc verification, surge in estimate |
| `main_new.py` | startup migrations (4 new columns + 1 new table), chat endpoints fixed |
| `models.py` | passenger_rating/comment on RideRequest, rating/total_rides on Customer, RideChatMessage model |

### iOS Shared
| File | Changes |
|------|---------|
| `P2PAPIService.swift` | ratePassenger(), getSurgeStatus(), SurgeStatusResponse, surge fields on RideFareEstimate |

### iOS Customer
| File | Changes |
|------|---------|
| `RideRequestView.swift` | chat button, SOS button, share button, surge badge + banner |
| `RideRequestViewModel.swift` | surgeLabel property, surge from API response, protective comment |
| `DriverChatView.swift` | rewritten for ride chat (was food delivery stub) |

### iOS Driver
| File | Changes |
|------|---------|
| `ActiveRideView.swift` | passenger rating UI, SOS button, no-show timer |
| `RideBiddingViewModel.swift` | online toggle, ratePassenger(), bid error handling, location tracking |
| `DeliveryViewModel.swift` | fixed API endpoint (was admin-only), location tracking |
| `AvailableOrdersView.swift` | online toggle banner |
| `RideshareDashboardView.swift` | online toggle |
| `LocationManager.swift` | always permission auto-upgrade |

---

## Build Verification

| App | Status |
|-----|--------|
| Backend (Python syntax) | PASS |
| iOS Customer (`eatfaircustomer`) | BUILD SUCCEEDED |
| iOS Driver (`eatffairdelivery`) | BUILD SUCCEEDED |
| iOS Restaurant (`eatfairrestaurant`) | Not affected |
| Android | Pending implementation |
