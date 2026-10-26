# Dollor rideshare: final test and store-review report

Date: 2026-10-26. Apps: iOS rider `com.dollorai.customer`, iOS driver `com.dollorai.delivery`, Android rider `ai.dollor.customer`, Android driver `ai.dollor.driver`, and the FastAPI backend.

Branches (nothing is merged or deployed; `main` is untouched):
- Apps and docs: `release/rideshare-launch-ready-20261026` (head `3c3017d0`)
- Backend: `release/rideshare-backend-20261026` (head `349a7e2a`)

Production (`api.dollor.ai`) is built from `main` of this repo (`apps/web/p2p-platform/backend`) by `.github/workflows/deploy-dollar-ai.yml` into ECS cluster `dollor-production`, service `dollor-api-service`. Production runs `origin/main` at `259cdf3b`. None of the backend fixes below are live until the backend branch is merged to `main`.

---

## 1. What was run, and what was not

| Check | Result | Notes |
|---|---|---|
| Backend test suite (all of `tests/`) | 823 passed, 67 failed, 29 skipped | Baseline on a clean `origin/main`: 770 passed, 76 failed. **0 failures are new; 9 baseline failures now pass.** |
| New and updated backend unit tests | 39 test functions in 10 files, all passing | Each fix below has a test that fails without the fix (shown for the radius and counter-accept payment fixes) |
| Full 12-step ride lifecycle test (`tests/e2e/test_rideshare_e2e_flow.py`) | 10 of 10 pass | Runs against the local app with mocked Stripe and notifications, not production |
| iOS rider and driver, Release configuration, simulator | Both build; both launch | **Not run end to end this pass.** No archive or device build. |
| Android rider and driver, debug | Both compile and install | |
| Android rider and driver, signed release (R8 minified) | Both build; rider installed, launched and signed in | Driver release APK installed but not driven |
| Full ride on Android, production API | Completed (ride #595) | Timings below |
| Route table | 0 duplicate (method, path) registrations | Checked by importing the app |
| Hardcode scans | See section 5 | |

Not run: real Stripe charges, push notifications (FCM/APNs), WebSockets, the iOS ride flow end to end in this pass, anything on a physical device, Play Console or App Store Connect forms.

## 2. Backend tests in detail

Final totals: **67 failed, 823 passed, 29 skipped** (4 min 15 s).

The 67 remaining failures were all failing on the clean `origin/main` baseline before any of this work. By file:

| File | Failures | What the visible errors say |
|---|---:|---|
| `tests/e2e/test_wave1_wave2_e2e.py` | 13 | Tests call live hosts or removed food routes (`503`, `Not Found`) |
| `tests/e2e/test_customer_ui_wiring_e2e.py` | 11 | Same |
| `tests/smoke/test_wave1_wave2_smoke.py` | 9 | Live login returns 503 |
| `tests/smoke/test_smoke.py` | 9 | Live login/health returns 503 |
| `tests/e2e/test_driver_vendor_ui_wiring_e2e.py` | 7 | Removed vendor/food routes, driver identity gate |
| `tests/test_prop22_migration.py` | 5 | Not investigated |
| `tests/unit/test_email_service.py` | 4 | Not investigated |
| `tests/test_project_tracker.py` | 4 | Not investigated |
| `tests/unit/test_insurance_webhooks.py` | 3 | Not investigated |
| `tests/test_rideshare_e2e.py` | 1 | Driver never set online (online guard already on `origin/main`); stale test |
| `tests/security/test_auth_security.py` | 1 | Demo login 503 on the live host |

These are not caused by this work, but they are real red tests. Several of them target removed food/vendor routes and should be deleted or rewritten.

New and updated tests (all passing):

| File | Covers |
|---|---|
| `test_counter_accept_payment.py` | Accepting a counter-offer pre-authorizes the card for the countered fare; a declined card cancels the ride (402); a counter cannot be accepted once the ride is no longer open (409) |
| `test_ios_track_alias.py` | The iOS tracking route works; the matched driver receives the rider's phone |
| `test_ride_chat_send_shape.py` | Chat reply has every field iOS decodes; strangers get 403; the sender comes from the token, not the body |
| `test_rideshare_config.py` | Fee tier boundaries, config-driven tiers, public config endpoint, claims are null until configured |
| `test_available_rides_dispatch.py` | Nearest-driver dispatch; default radius reaches the widest dispatch step (fails without the fix) |
| `test_ride_dispatch.py`, `test_single_session.py`, `test_driver_offline_guard.py`, `test_ride_history_total.py`, `test_background_email.py` | Dispatch policy, one active driver session, offline guard, history total, background email |

## 3. Device checks

### 3.1 Android, full ride on production (debug build, `ApiTiming` logcat)

Ride #595: rider requests an SFO ride, driver bids $20.32, rider accepts, driver arrives, starts and completes, driver rates, rider opens the receipt.

| Action | Call | Time |
|---|---|---|
| Driver login | `POST /auth/driver/login` | 465 ms |
| Rider fare estimate | `POST /rides/estimate` | 169 ms |
| Rider request | `POST /rides/request` | 318 ms |
| Driver bid | `POST /rides/request/{id}/bid` | 532 ms |
| Rider accepts | `POST /rides/bid/{id}/respond` | 681 ms |
| Arrived | `POST /rides/request/{id}/arrived` | 296 ms |
| Start trip | `POST /rides/request/{id}/start` | 464 ms |
| Complete trip | `POST /rides/request/{id}/complete` | 782 ms |
| Driver rates rider | `POST /rides/request/{id}/rate-passenger` | 135 ms |
| Rider receipt | `GET /rides/request/{id}/receipt` | 309 ms |

Money check: fare $20.32, minus $1.00 platform fee, minus $0.05 CPUC Access-for-All, driver earns $19.27. Rider and driver both showed $20.32.

Observed behavior and caveats:
- Reads polled every few seconds returned 90 to 215 ms. How quickly a new request reaches a driver was not measured.
- Both apps logged short `UnknownHostException` errors (0 to 5 ms) several times. They were DNS failures on the emulator; the next poll succeeded each time and nothing showed in the UI. Cause not confirmed.
- Demo account only: the receipt shows "Demo account (no charge)", so card capture was not exercised.

### 3.2 Android UI fixes verified on the device

- Driver Home hides the "You're Online / Waiting for ride requests" card while a ride is active (ride #596).
- The Help FAQ renders the fee tiers from config ("$1 up to $35 / $2 over $35 up to $70 / $3 over $70").
- Dynamic config: I put a test config on the device (support email, hours, response time, different tiers) and the Help screen showed it. That test value was removed afterwards, on Android and iOS. Real rates remain $1 / $2 / $3.
- The signed release build installs, launches and signs in with the demo account (confirms R8 did not break JSON parsing on the login path).

### 3.3 iOS

Both apps build in Release for the simulator and launch without a crash after the dead-code removal and permission changes. The rider screen showed the config-driven fee footer. The iOS ride flow, chat, tip and tracking fixes are covered by backend tests and code review, **not by a device run in this pass**.

## 4. Bugs found and fixed

| # | Bug | Evidence | Where fixed |
|---|---|---|---|
| 1 | **Rides matched by the driver accepting the rider's counter were never charged** (no PaymentIntent created) | Test fails without fix, passes with | Backend: shared `_authorize_ride_payment`, used by both match paths |
| 2 | **iOS rider tracking crashed on every call** (`'Depends' object has no attribute 'get'`), also on production | Reproduced with a test | Backend alias now passes its auth |
| 3 | **Any signed-in user could read and post in any ride's chat**, and could post as the other party | Test | Backend: participant check, sender from token, id-less tokens resolved by email |
| 4 | iOS chat send showed failure although the message was saved | Reply lacked `id` and `sender_id` | Backend reply now includes them |
| 5 | **Android drivers never saw rides at the 10 and 25 mile dispatch steps** (default radius 15 km) | Test fails without fix | Backend default is the widest dispatch step |
| 6 | A counter could be accepted after the ride was matched to someone else | Test | Backend returns 409; countered rival bids are closed |
| 7 | Driver could not call the rider (phone never sent) | Test | Backend adds `customer_phone` to the driver's active rides |
| 8 | iOS "Skip Tip" sent a $0 tip and got a 422 | Read endpoint validator | iOS no longer sends it |
| 9 | Terms "Continue" button had no visible label while disabled (Android); ten other disabled buttons across the Android apps defined no readable label color | Screenshot | Shared button on the terms screen; readable disabled label color on the others |
| 10 | Android minimum-fare default $5.00 vs backend $8.00 | Code | Default now $8.00 and read from config |
| 11 | Wrong claims in the apps: "No hidden fees or surge pricing", "0% Commission", "100% of your payment goes to drivers", fake random referral stats and code | Code | Removed or made config-driven; Refer & Earn hidden until a reward is configured |

## 5. Hardcoding and dead code

Hardcode scans on the committed code:
- iOS raw colors, fixed fonts and numeric radii in views: **0**
- Android raw `Color(0x...)` in the rider and driver views: **0**
- Android support email typed outside legal text: **0**
- Android `$1-$3` literal in screens: **0**
- iOS `$1-$3` literal: **0** (one remaining hit is a code comment)

Now served by `GET /api/config/rideshare` and read by both apps (with cached and built-in fallbacks): fee tiers, CPUC split, pricing rates, bid presets, ETA options, negotiation limits, no-show wait/fee/driver share, dispatch policy, support contacts, referral reward. Claims the business has not configured (support hours, chat response time, ACH note, referral reward) are `null` and hidden.

Fee tiers are applied in one backend function (`platform_fee_for`); seven duplicated copies were removed.

Dead code removed (vs `origin/main`, app code only): 236 files changed, +12,606 / -34,800 lines. This includes 29 Android files and unused API methods, 24 iOS files, and about 7,300 lines of food/vendor/menu/promo/cart code from `P2PAPIService.swift` (15,808 to 8,443 lines). Everything was grep-checked and then compile-checked; the audit's file list was wrong about three iOS files that held live types, and the compiler caught them.

Known remaining hardcoded or unbacked items: tip option lists differ between screens; a few fallback fare multipliers in the rider apps; the iOS "default offer" before an address is chosen; legal and terms text is static on purpose. Full list: `docs/audit-2026-10-26/hardcodes.md`.

## 6. Apple and Google review risk

### High: needs your decision

1. **$100 non-refundable "Founding Member" payment inside the apps by card** (rider iOS and Android). It grants a digital entitlement (fees locked for life, priority matching, surge protection). Apple rule 3.1.1 and Google's payments policy are likely to require their billing for this. The iOS store description also cites the wrong guideline (3.1.3(a)). Recommended: sell on the web only and hide the screen in store builds.
2. **Store text claims with no matching code.** Driver description: Proposition 22 earnings guarantee (120% of minimum wage), quarterly healthcare stipend, occupational accident insurance, "only verified riders book trips", weekly bank payouts, "earn more per mile than any other rideshare platform", "incidents reviewed within 24 hours". Unsupported claims are a rejection reason for both stores.
3. **Stale Android store assets in the repo.** `android/store-assets/customer/listing.md` still says "Food & Rides", category "Food & Drink", with restaurant and deals screenshots. Confirm what is in the live Play listing.

### Medium
- Ride chat has no report or block option on Android; iOS rider has only the safety report form. Reviewers may ask about moderation.
- Reviewers need working demo credentials in the review notes; the driver demo account must be approved to go online.
- Android asks for notification permission on the login screen, before sign-in.
- App Store Connect privacy labels and the Play Data Safety form must match what the apps collect (location, name, email, phone, photos, chat, payment, driver documents). The Play draft in the repo describes the old three-app, food-era set.
- The Android driver has no background-location support; sharing stops when the app is backgrounded. Adding it triggers Google's background-location review.

### Fixed in this pass
- Removed unused iOS purpose strings (rider: microphone, speech recognition, contacts, "always" location; driver: contacts) and the driver's "audio" background mode.
- Privacy manifests now also declare chat messages and photos.
- Removed the false "no surge pricing" line from the iOS store description.
- Driver voice prompt says "ride requests", not "orders".
- Duplicate `targetSdk` removed (target is 36).

### Checked and fine
In-app account deletion in both apps; Sign in with Apple beside Google on both iOS apps; HTTPS only, no cleartext; legal, support and `dollor.ai/delete-account` pages return 200; `ITSAppUsesNonExemptEncryption` is set; the CPUC TNC permit TNC0050982-N was issued 2026-10-07.

## 7. Open items

Needs a decision or a real-money test:
- **Tips after capture.** The fare is captured at completion, then the tip endpoint modifies and captures the same PaymentIntent again. This will probably fail with real Stripe. The fix is a separate tip charge. Not changed, because it cannot be verified without Stripe.
- Production still runs the old backend: the payment fix (bug 1), tracking (2), chat security (3) and radius (5) only take effect after the backend branch is merged to `main`. Merging deploys.

Not built or incomplete: masked calling (apps dial raw numbers); Android rider SOS and share-trip; Android driver waybill; recurring rides never dispatch; Android push type handling does not match the backend; single driver session is enforced only on password login; ride PIN; off-route and long-stop check-ins; rider-visible "drivers contacted" count; iOS negotiation endpoints (`negotiation-status`, `customer-negotiate`) are broken and may be unused.

Not tested: two-driver competition (driver 129 is still pending admin approval), forgot-password code entry, real Stripe charging, push delivery, scheduled rides, driver cancel and no-show on a device, iOS timings.

Backend cleanup that needs an owner call: 12 never-imported scripts, `/api/demo/*` and `/api/debug/order/{id}` (look like an unauthenticated back door, but App Review may use the demo setup), unused ORM tables, 383 tracked vendor PDFs.

## 8. Before you submit

1. Decide on the founding-member purchase (section 6, item 1).
2. Remove or back each store-text claim in section 6, item 2; replace the stale Android listing text and screenshots.
3. Merge the backend branch to `main` and let CI deploy; then re-run the production lifecycle and check `GET /api/config/rideshare` returns 200.
4. Build iOS archives and Android bundles from the app branch; set build numbers; test on a physical device (location, push, card, call).
5. Write App Review notes with demo rider and driver logins; update privacy labels and Data Safety.
6. Do not push local `main`: it is 8 commits ahead of `origin/main`, includes backend changes, and a push deploys production.

Supporting audits: `docs/audit-2026-10-26/` (hardcodes, dead code, API map and cross-app feature matrix, Uber/Lyft research). Line numbers in those files predate the fixes above.
