# Dollor rideshare — launch readiness report

Date: 2026-10-26 · Scope: iOS rider (`com.dollorai.customer`), iOS driver (`com.dollorai.delivery`), Android rider (`ai.dollor.customer`), Android driver (`ai.dollor.driver`) against production `https://api.dollor.ai`, plus the staged backend branch.

## 1. Verdict

**Not ready to submit yet.** The core ride works end to end across iOS and Android, and the API is healthy and fast. But these items are open and each can fail a review or hurt launch day:

| # | Blocker | Why it matters |
|---|---|---|
| 1 | **Two-driver competition never tested.** Driver 129 is still `pending` (needs admin approval; the harness blocks me from production admin). | "Accepted by another driver" and one-session behaviour have only been checked by logic/unit tests. |
| 2 | **Backend changes are staged, not deployed** (branch `deploy/single-driver-session`, unpushed). | Slow start/complete calls, dispatch narrowing, one-session rule, offline-mid-ride guard, history total all depend on a deploy you must approve. |
| 3 | **iOS fixes need a new build + Apple resubmission.** Apple is reviewing the old build (`202610140258`). | Cents formatting, chat decode, online sync, bid-sheet fix, cancel-fee text are not in that build. |
| 4 | **Play builds on Play are stale** (261026 customer / 261024 driver predate today's work). | Re-upload required before sending for review. |
| 5 | **Not built:** ride PIN, off-route alerts, rider "drivers contacted" count. | Uber/Lyft parity; not store-review blockers. |
| 6 | **Untested on current builds:** driver cancel/no-show, call button, tipping UI, SOS, trip sharing, scheduled rides, document upload/onboarding, payouts/bank, Google/Apple sign-in, iOS push. | See section 5. |

Nothing is committed. Working tree has ~110 Android, ~86 iOS and ~43 backend modified files across several sessions.

## 2. Method and limits (read this before trusting any number)

* **Static API audit:** every endpoint each app can call was extracted from code and matched against the live FastAPI route table (and spot-checked against production).
* **Latency:** `curl` from this Mac to production, 5 samples per endpoint (median/max). ~140 ms is the network floor from here; real phones on cellular will be slower. Not a load test.
* **Lifecycle:** one full ride driven through the production API, 18 steps, each timed.
* **Device checks:** Android emulator (Pixel 9a), iOS simulators (iPhone 16 Pro rider, iPhone 16 driver). Simulators cannot test iOS push, real calls, or real payments.
* **Demo accounts only** (`demo.customer@…`, `demo.driver@…`). Payment shows "Demo account (no charge)", so **real Stripe charging was not exercised**.
* The demo driver was logged in on both a driver simulator and an emulator at times (same account). That is a test artifact.

## 3. API audit

| | iOS | Android |
|---|---|---|
| Unique endpoints in code | 244 | 112 |
| Match a backend route | 115 | 96 |
| Unmatched | 129 | 16 |
| **Unmatched AND reachable from screens** | **0 rideshare** (4 flagged: 2 are trip-board/food code with no screens; 1 is a food-era overload; 1 geocode helper with no callers) | **1 — driver Forgot Password (fixed, below)** |

The unmatched iOS endpoints are the shared package's restaurant, vendor, promotions, trip-board and call-masking code; no screen in either rideshare app calls them. Android's other 15 are dead Retrofit declarations (`/v2/driver/*`, payouts, dashboard) with zero callers.

**Real bug found and fixed:** Android driver "Forgot password" posted to `/auth/driver/forgot-password`, which production answers `401 Authentication required`, so it always failed. It now uses `/api/driver/password-reset/request` and a second step (`/confirm` with code + new password), identical to iOS. *Compiles; not yet exercised on the emulator.*

**Method caveat:** this proves routes exist and methods match, not that request/response shapes are correct. Shapes were verified only for the calls in the lifecycle test (section 4) and screens exercised on devices.

## 4. Timing

### 4.1 Reads and auth (production, median / max of 5)

| Call | Median | Max |
|---|---|---|
| Health | 143 ms | 144 |
| Rider login | 725 ms | 766 |
| Driver login | 441 ms | 451 |
| Fare estimate | 154 | 157 |
| Rider: my requests | 293 | 375 |
| Rider: ride history | 158 | 163 |
| Rider: saved addresses | 145 | 148 |
| Rider: saved cards | 378 | 546 |
| Rider: receipt / track / chat list | 148 / 146 / 141 | ≤154 |
| Rider: founding status | 148 | 152 |
| Driver: me | 144 | 200 |
| Driver: available rides | 154 | 252 |
| Driver: active rides | 142 | 147 |
| Driver: my bids | 226 | 252 |
| Driver: earnings (today) | 149 | 196 |
| Driver: accessibility | 146 | 149 |

All returned 200 on every sample. Slowest: rider login (password hashing) and saved cards (Stripe lookup).

### 4.2 Full ride lifecycle through the API (18/18 passed, 6.7 s total API time)

| Step | Time |
|---|---|
| Rider create request | 390 ms |
| Driver sees ride | 157 |
| Driver bid | 609 |
| Rider list bids | 142 |
| Rider counter | 298 |
| Driver accept counter | 494 |
| Rider track after match | 149 |
| Driver arrived | 338 |
| Rider sees arrival | 149 |
| Chat send ×2, list | 160 / 161 / 141 |
| **Driver start trip** | **1,981 ms (slow)** |
| **Driver complete trip** | **924 ms (slow)** |
| Receipt | 144 |
| Rate driver / rate passenger / tip | 165 / 159 / 146 |

Final receipt: fare 8.00 + connection fee 1.00 + CPUC 0.05 + tip 2.00 = **11.05**.

**Slow calls diagnosed:** start/complete sent the notification email synchronously inside the request (SMTP wait), and because the handler is `async` it also blocked the server's event loop. **Fix (staged, not deployed):** send emails in a worker thread (`_bg_email`), unit-tested to not block the caller, still send, and never break a ride. Expect start/complete to approach the ~150–500 ms of their neighbours; this is **unconfirmed until deployed and re-measured**.

### 4.3 Real-time behaviour seen on devices
* New order reaches the iOS driver list within ~3 s (after fixing a polling bug: the app skipped polling while its WebSocket reported "connected").
* Android push "New Ride Request!" arrived with pickup and estimate.
* A bid expires after 5 minutes; the Android rider showed "No driver accepted in time", the countdown shows on the waiting and offers screens.

## 5. Feature-by-feature status

Legend: **V** verified on a device/API this session · **B** built and compiles, not run · **—** not tested · **✗** not built

### Rider
| Feature | iOS | Android | Notes |
|---|---|---|---|
| Email login | V | V | iOS rider was logged out after reinstall once; cause not investigated |
| Google / Apple sign-in, registration, email verification | — | — | |
| Legal acceptance | — | V | |
| Pickup (current location) and dropoff selection | V | V | iOS search box ignores simulator typing; map-pan used |
| Fare estimate and breakdown | V | V | |
| Request with custom offer | V | V | |
| Accessible-vehicle request | B | V | iOS toggle exists; flagged request verified end to end from Android only |
| Waiting screen with countdown | — | V | |
| Driver offers (name, rating, trips, vehicle, plate, ETA, message) | V | V | Android ETA/message code added this session |
| Counter / accept / decline | V | V | |
| Matched screen (driver card, rating, plate) | V | V | Duplicate card fixed on iOS (built, not re-viewed) |
| Driver-arrived banner | V | V | Android was missing it; fixed |
| In-ride status | — | V | |
| Chat (both directions with driver) | V | V | iOS decode bug fixed |
| Call driver | — | — | Button present; real call not tested |
| SOS, share trip | — | — | Present in iOS UI; not exercised |
| Cancel before / after match | — | V | Android dialog verified; iOS confirmation exists, not re-run |
| Ride completed screen | — | V | |
| Receipt | — | V | Matches server ($8.25) |
| Rate driver | — | V | Saved as 5; "Thanks" confirmation built, not seen |
| Tip | — | — | API verified; UI not run |
| Trips list | V | V | Amount now server-computed (below) |
| Profile, addresses, settings, help/chat, refer, founding | — | V (earlier session) | iOS Profile top verified only |
| Real card payment | — | — | Demo account bypasses charge |

### Driver
| Feature | iOS | Android | Notes |
|---|---|---|---|
| Login, terms | V | V | |
| Online state from server | V | V | Both apps now re-check the server and block offline mid-ride |
| Available rides, rider's offer | V | V | iOS now hides rides already bid on |
| Bid sheet (presets, ETA, message, slide to submit) | V | V | Cents precision; fee tiers from config |
| Counter-offer handling | V | V | iOS prices were rounded ($9.50 → "$10"); fixed |
| Accept rider's counter | — | V | iOS attempt expired before I could accept |
| Active ride: arrive / start / complete | V | V | iOS "Success" alerts were closing the ride screen; removed (built, **not re-run** after the fix) |
| Chat | V | V | |
| Closed-bid reasons ("Accepted by another driver", expired, etc.) | V (expired) | V (expired) | "Accepted by another driver" seen only by logic |
| Accessibility capability setting | B | V | |
| Driver cancel / no-show, SOS, call | — | — | |
| Earnings, profile | — | V (earlier session) | iOS not re-checked |
| Documents upload, onboarding, bank, payouts | — | — | |
| Forgot password | (code: OK) | B | Android fixed, not yet exercised |

## 6. Defects found and fixed in this work

| Defect | Where | Status |
|---|---|---|
| Prices rounded to whole dollars in 20+ places ($9.50 shown as "$10") | iOS both apps | Fixed, seen on simulator |
| Trips total disagreed with receipt ($11.00 / $8.00 / $11.05) | iOS + Android + backend | Server `total` added (staged); apps read it. **Needs deploy**; apps fall back to old math on the old server |
| Driver listed rides it had already bid on; stale counter on expired ride | iOS driver | Fixed, seen |
| iOS driver showed Offline when server said Online | iOS driver | Fixed (server is source of truth); self-correction not directly observed |
| Bid sheet opened blank white | iOS driver | Fixed, seen |
| New rides invisible until relaunch | iOS driver | Fixed, seen (~3 s) |
| Chat always "No messages yet" | iOS both | Fixed, seen |
| `Ride #Optional(...)` text | iOS rider | Fixed, seen |
| Completion screen price ignored negotiated fare | iOS rider | Built, not re-viewed |
| Driver Forgot Password dead endpoint, no code-entry step | Android driver | Fixed (compiles) |
| Arrival headline / rating / plate missing | Android rider | Fixed, seen |
| No cancel confirmation | Android rider | Fixed, seen |
| Rate button remained after rating | Android rider | Fixed (built) |
| "96% to driver" claims | all | Removed |
| Cancel-fee text ($5/$10) with no server fee | iOS | Set to 0 to match server. **A real fee needs a backend change and Terms alignment** |
| Mixed red/orange drop-off markers; off-theme cards/buttons; raw colours/fonts/radii | iOS + Android | Zero raw styling outside theme files |
| 7 duplicate backend routes (dead shadowed handlers); unprefixed `/rides/available` served old logic | backend | Fixed (staged) |

## 7. Backend (staged on `deploy/single-driver-session`, worktree `/private/tmp/dollor-single-session-wt`)

* One active session per driver (demo accounts exempt) · nearest-10 dispatch within 3 mi widening to 25 mi over 2 min (demo exempt; no GPS = show all) · cannot go offline mid-ride (409) · ride emails off the request path · history `total` · duplicate-route cleanup.
* Tests: unit gate plus the rideshare E2E file give **548 passed, 7 failed** (the same 7 fail on unmodified production: email and insurance-webhook tests). New tests were added for each change. The repo's 10-test rideshare E2E (it was failing at step 3 on production code because of stale fixtures and the CPUC fee) now **passes 10/10**.
* **Not tested against a live server:** session rule, offline guard, dispatch endpoint under real traffic.
* Deploy rule: pushing to `main` auto-deploys to production; staging is broken. Needs your review.

## 8. Open decisions and next steps

1. Approve driver 129 (`POST /api/admin/drivers/129/set-documents` then `/verify`), or accept launching without the competing-drivers test.
2. Review and approve the staged backend deploy.
3. Decide on a real rider cancellation fee (needs backend + Terms).
4. Decide whether to build ride PIN and off-route alerts before launch.
5. Then: exercise the "—" rows above on current builds, rebuild Play bundles and a new iOS build, re-shoot store screenshots, and resubmit.

See `DO_NOT_USE.md` for legacy code that must not be reused, and its hygiene checks.

## 9. Status update — Android re-test and commit (2026-10-26)

* **Full Android ride re-run on production** (rider + driver emulator apps, `ApiTiming` logcat, ride #595): estimate 169 ms, request 318 ms, bid 532 ms, accept 681 ms, arrived 296 ms, start 464 ms, complete 782 ms, rate-passenger 135 ms, receipt 309 ms. Driver earnings dialog: fare $20.32 − $1.00 connection fee − $0.05 CPUC = $19.27.
* **Fixed:** driver Home no longer shows "You're Online – Waiting for ride requests" while a ride is active (verified on device, ride #596).
* **Fixed:** fee tiers in Android Welcome, Login, Register, Terms, Help FAQ and the legal screen were typed into the copy; they now come from `AppConfig.Rideshare` (`feeRangeText`, `tierLines`). Verified on device: the Help FAQ renders "$1 platform fee for rides up to $35 / $2 … over $35 up to $70 / $3 … over $70".
* **Backend suite:** 803 passed / 67 failed on the staged branch versus 770 / 76 on a clean `origin/main`. No new failures; 9 previously failing tests now pass; the 67 are pre-existing.
* **Hardcode scans:** 0 raw colors/fonts/radii in iOS views, 0 raw colors in Android views, no live keys or localhost in app sources. Demo passwords exist only in debug-gated iOS code.
* **Still not re-run this pass:** iOS in-app timings, two-driver competition (driver 129 pending admin approval), Forgot-password code entry, real Stripe charging, push notifications.
* **Still hardcoded copy to clean up:** Help screen claims such as "Average response time: 2 mins", "Available 9AM - 9PM" and "ACH payments receive a discount on platform fees" are static text; confirm each is true or remove it before submission.
* The root `README.md` was an unrelated "Invoice Management System" template and has been replaced with this project's README.

## 10. Cleanup and API audit (2026-10-26)

Four audits were run (hardcodes, dead code, API map and cross-app features, public Uber/Lyft research); the reports are in `docs/audit-2026-10-26/`.

**Fixed and tested**
* iOS rider tracking (`GET /api/erp/rides/{id}/track`) raised an `AttributeError` for every call (also on production); it now matches the canonical route.
* Rides matched by the driver accepting the rider's counter-offer were never pre-authorized, so they completed unpaid. One helper (`_authorize_ride_payment`) now serves both match paths; a declined card cancels the ride (402).
* Ride chat had no participant check and trusted `sender_type` from the request body; now only the rider, the matched driver or an admin can use it and the sender comes from the token.
* iOS chat send reported failure although the message was saved (reply lacked `id` and `sender_id`).
* iOS "Skip Tip" sent a tip of 0 and got a 422.
* `GET /api/rides/available` defaulted to a 15 km radius, so Android drivers never saw rides at the 10 and 25 mile dispatch steps; the default is now the widest dispatch step.
* `accept-counter` no longer overwrites a ride that is no longer open and closes countered rival bids.
* The matched driver now receives `customer_phone` so the call button works.
* Hardcoded business values moved to the backend config: bid presets, ETA options, negotiation limits, no-show wait/fee/driver share, support contacts, referral reward. Wrong claims removed ("No hidden fees or surge pricing", "0% Commission", fake referral stats).

**Removed (grep- and compile-verified)**
* Android: 29 unreferenced files, food-era config objects, 10 unused Retrofit methods, unused drawables.
* iOS: 24 unreferenced files and about 7,300 lines of food/vendor/menu/promo/cart API code from `P2PAPIService.swift` (15,808 to 8,443 lines). The audit's list was not perfect (it marked two files whole-dead that contained live types, `EnhancedModels.swift`, `PaymentService.swift`, `PlaceholderViews.swift`); the build caught those and they were restored.

**Open, needs a decision or a real-money test**
* Tip after capture: the ride is captured at completion, then the tip endpoint modifies and captures the same PaymentIntent again. This will likely fail with real Stripe; the fix is a separate tip charge. Not changed because it cannot be verified without Stripe.
* Masked calling does not exist (clients dial raw numbers); Android rider has no SOS or share-trip; Android driver has no waybill; recurring rides have CRUD but never dispatch; push types do not match on Android; single-session is enforced only on password login.
* iOS negotiation endpoints (`negotiation-status`, `customer-negotiate`) are broken and unchecked; confirm whether that flow is still used.
* Not built: ride PIN, off-route and long-stop check-ins, rider-visible "drivers contacted" count.
* Backend cleanup left for an owner call: 12 never-imported scripts, `/api/demo/*` and `/api/debug/order/{id}` (look like an unauthenticated back door), unused ORM tables, 383 tracked vendor PDFs.
