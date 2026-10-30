# iOS end-to-end test: Dollor rider + Dollor Driver (production)

## 1. Method and limits
- Builds: Release simulator builds of current code (rider Dollor.app com.dollorai.customer on iPhone 16 Pro E67C38DE; driver "Dollor Driver.app" com.dollorai.delivery on iPhone 16 0C3822BC). Both uninstalled/reinstalled clean. Release = PRODUCTION https://api.dollor.ai (Config/Production.xcconfig, per the brief; I did not re-read the xcconfig). Server read-backs confirm the apps wrote to production (ride 610 etc.).
- The former dev API host does not resolve (`dig +short` returned nothing). Debug builds / XCUITest not used.
- Driving: macOS pointer clicks via the `click` Swift binary on the Simulator windows (rider window at 661,38; driver at 1150,38), drags for swipe-to-confirm sliders / back-swipes, osascript keystroke for typing. Screenshots via `simctl io`. No XCUITest run.
- Flakiness / my automation errors (not app bugs): first typing attempts into driver login missed field focus; one run had Chrome frontmost (I added a frontmost guard; nothing was typed into Chrome); coordinate calibration for the driver window was wrong at first; one shell loop clobbered its args. A scroll-wheel attempt did nothing; drags worked.
- Evidence level: I opened screenshots for the steps below, but several rider/driver mid-flow screens I checked mainly via server read-back; where the on-screen result was not individually confirmed I say INFERRED. Screenshots in scratchpad/shots/ios_r_* (rider) and ios_d_* (driver).
- Ride tested: request 610 (RIDE2026000610), rider 74, driver 48 (Marcus Johnson), 250 Geary St -> SFO Terminal G, completed. No ride left open (read-back: driver active_rides = [], rider latest = 610 completed).

## 2a. Rider app results
| Feature / screen | How exercised | RESULT | Evidence | Notes |
|---|---|---|---|---|
| Login (email/password) | typed demo.customer@dollor.ai / password, tapped sign in | PASS | ios_r_01_login_typed, ios_r_02_after_login; later screens show Demo Customer | |
| Ride tab: pickup/dropoff pick | Pickup (SF location default) and dropoff search "San Francisco International Airport", selected a result | PASS | ios_r_04..08 | Result chosen resolved to "SFO Airport Terminal G" |
| Find Driver (request) | tapped Find Driver | PASS | ios_r_09; server: request 610 status open->bidding | |
| Receive driver bid | driver bid via driver app | PASS | ios_r_10_riderbid; server bid 387 proposed 20.60 | |
| Rider counter-offer | in bids sheet, counter, slide | PASS | ios_r_11/12; server bid shows customer_counter_price 18.54 | |
| Driver counter back (driver app) | opened counter, swiped confirm | UNTESTED/INCONCLUSIVE | ios_d_14/15 | Server afterwards still showed bid 387 proposed 20.6, is_counter_offer false; could not confirm a counter-back was recorded. |
| Accept offer | tapped Accept in bids sheet | PASS | ios_r_15_accepted; server request 610 status matched, final_price 20.60 | final price = 20.60 (driver's price), not rider's 18.54 counter |
| Chat: rider sends | typed message, send | PASS | ios_r_17_chat_sent; server chat id 50 sender customer "Hi from rider iOS test" | |
| Chat: rider receives driver reply | driver sent reply | PASS (server) / UI INFERRED | server shows driver msg "Reply from driver iOS test"; ios_r_18 | |
| Driver arrived / trip started (rider UI) | driver swiped | INFERRED (rider UI) | server driver_arrived_at set, status in_progress; ios_r_19/20; rider completed screen later shows "Driver has arrived!" banner remnant | |
| Ride complete screen, fare breakdown | scrolled | PASS | ios_r_25b: Ride Fare 20.60, Connection Fee 1.00, CPUC 0.05, Total Paid 21.65, Driver earned 19.55 | matches server receipt |
| Rate driver | 5 stars + slide | PASS | ios_r_24; server customer_rating 5 | |
| Tip / Skip tip | tip buttons visible ($2 selected, ios_r_26) | UNTESTED (action) | ios_r_26 | did not complete add-tip or skip |
| Receipt | Trips tab > View Receipt | PASS | ios_r_30_receipt; server /receipt total 21.65 | see bugs |
| Trips / history | Trips tab | PASS | ios_r_29_trips; server /customer/rides/history lists 610 completed rating 5 | |
| Profile screen | Profile tab | PASS | ios_r_31, ios_r_40 | |
| Manage Addresses | opened | PASS (view) | ios_r_32; matches server 2 addresses | add/edit/delete UNTESTED |
| Payment Methods | opened | PASS (view) | ios_r_33; Visa 6255 matches server | add/remove UNTESTED (not allowed to add cards) |
| Founding Member | opened | PASS (view) | ios_r_34 | purchase UNTESTED (real payment) |
| Settings | opened | PASS (opens) with defect | ios_r_37 | rows have no text labels, see bugs; toggles/language/legal UNTESTED |
| Notifications | opened | PASS (view) | ios_r_38 | toggle writes UNTESTED |
| Help & Support | opened | PASS (view) | ios_r_41 | Live Chat/Email/Phone/FAQ expand UNTESTED |
| What Drivers See | opened | PASS (view) | ios_r_42 | |
| Your Privacy | opened | PASS (view) | ios_r_43 | |
| Safety Features | opened | PASS (view) | ios_r_44 | |
| Log Out / Delete Account / edit avatar | - | UNTESTED | | deliberately not pressed |
| Cancel ride, SOS, share trip, dispute, safety report, recurring rides, refer & earn, live chat, order history (food), rider decline of bid | - | UNTESTED | | not reached in time |

## 2b. Driver app results
| Feature / screen | How exercised | RESULT | Evidence | Notes |
|---|---|---|---|---|
| Login | typed demo.driver creds | PASS | ios_d_01b, ios_d_03b | |
| Terms & Conditions gate | scrolled, viewed full terms, accepted | PASS | ios_d_04..07 | accepted-state persisted? not read back |
| Online/offline toggle | toggled | PASS (UI) | ios_d_07e/08_toggled, ios_d_09 shows Online | server availability not read back; ended Online |
| Rideshare dashboard tabs (Available/My Bids/Active) | viewed | PASS | ios_d_10_avail, ios_d_24_done | |
| Available ride -> submit bid (slide) | opened ride 610, slid | PASS | ios_d_11b/12; server bid 387 driver 48 proposed 20.60 | |
| Counter-offer sheet | opened | PASS (opens) | ios_d_14 | counter-back result inconclusive |
| Active ride: chat with rider | sent message | PASS | ios_d_18; server chat id (driver) | |
| Mark arrived / start / complete (sliders) | each slider | PASS | server: driver_arrived_at set; in_progress; completed at 20:38:19, platform_fee 1.0, driver_payout 19.55 | ios_d_19..21 |
| Completion screen fare/earnings | viewed | PASS with defect | ios_d_22 shows Your Earnings 19.55; header shows 17.54 (bug) | |
| Rate passenger + Done | stars + slider, Done | PASS | ios_d_23/24; server rated 5 (ride read-back) | |
| My Bids history | viewed | PASS | ios_d_24 | |
| Messages tab | opened | PASS (shows empty state) | ios_d_26 | empty even after chat on ride 610 (conversation list probably only active rides); not claiming bug |
| Profile > Personal | opened | PASS (view) | ios_d_27 | |
| Profile > Documents (vehicle info) | opened | PASS (view) | ios_d_28 | upload UNTESTED |
| Profile > Earnings tab | opened | PASS (view) | ios_d_29: week 172.02, month 370.04, 16 trips | not cross-checked to API |
| Profile > Settings tab | opened | PASS (view) | ios_d_30 | Preferences toggles UNTESTED |
| Compliance & Safety (incl. Accessibility toggles) | opened | PASS (view) with defect | ios_d_31 | toggle writes, Submit Inspection UNTESTED |
| Payout dashboard ($ icon) | tapped twice | UNTESTED/SUSPECT | ios_d_32b, 32d | sheet did not appear; could be a missed tap on my side. Not claiming a bug. |
| Founding Member (driver), Edit profile, Onboarding, Waybill sheet, MyBids withdraw, SOS | - | UNTESTED | | |

## 3. API calls per action
| Action | Call | Basis |
|---|---|---|
| Rider/driver login | POST /api/auth/customer/login, /api/auth/driver/login | FROM SOURCE (not read); login evidently succeeded |
| Find Driver | ride request create -> request 610 appears (GET /api/rides/customer/74/requests) | OBSERVED |
| Driver bid | bid 387 present in GET /api/rides/request/610/bids | OBSERVED |
| Rider counter | customer_counter_price 18.54 on bid | OBSERVED |
| Accept | request status matched, final_price 20.60 | OBSERVED |
| Chat send (both) | GET /api/p2p/ride-requests/610/chat shows both messages | OBSERVED |
| Arrive / Start / Complete | GET /api/rides/driver/active status; completion sets platform_fee 1.0, driver_payout 19.55 | OBSERVED |
| Rating | customer_rating 5 on request | OBSERVED |
| Receipt | GET /api/rides/request/610/receipt (200) | OBSERVED (endpoint returns total 21.65) |
| History | GET /api/customer/rides/history | OBSERVED |
| Addresses / cards | GET /api/addresses/74, /api/customers/74/cards match what UI shows | OBSERVED (data equality) |
| Everything else | not traced to source | not reported |
No per-call timings measured on-device. Curl reference only: GET https://api.dollor.ai/health returned 200 in 0.148 s (one sample, my network). GET /api/erp/rides/610/negotiation-status returned 500 Internal Server Error (called by me via curl; unknown whether either app calls it).

## 4. Bugs (observed)
App bugs:
1. Driver completion screen shows wrong earnings in header: top card "$17.54 earnings" vs body "Your Earnings $19.55" (ios_d_23). Cause (source): ActiveRideView.swift:84-90 computes finalPrice = customer_counter_price ?? proposed_price (18.54) although the ride settled at 20.60. Actual payout 19.55 (server). Severity: medium (money display mismatch).
2. Rider Settings screen has no visible text labels: ios_r_37 shows icon rows on white cards without titles (Notifications, Language, Legal, Support, About rows blank). Severity: medium (unusable labels; also white cards break the dark theme).
3. Driver Compliance screen contradictory: "Passed, Checked 2024-01-15" together with "Your background check is in progress" (ios_d_31). Severity: low/medium.
4. Receipt shows raw ISO timestamps ("2026-10-26T20:33:23.100623") (ios_r_30). Severity: low.
5. Trips list shows $21.60 for ride 610 while receipt/complete screen total is $21.65 (history fare+platform fee omits $0.05 CPUC fee) (ios_r_29 vs ios_r_30). Severity: low.
6. Rider counter 18.54 was ignored at accept (final 20.60) - may be intended (driver's last offer governs); noted as question, not a defect.
Automation mistakes (not app bugs): mistyped/unfocused fields, Chrome frontmost, calibration errors, shell arg bug, failed scroll-wheel.

## 5. Not tested and why
Tip add / skip tip, cancel ride (and cancellation fee), SOS/share trip, dispute, safety report, recurring rides, refer & earn, live chat, add/edit/delete address, add payment card (forbidden), founding purchase (real payment), notification/setting toggles, log out/delete account (forbidden), driver payout dashboard (tap did not open), waybill, document upload/inspection, onboarding, edit profile, driver counter-back result, bid withdrawal, driver decline paths, XCUITest suites (not run), Debug build / dev-api (host does not resolve), per-call timing on device.
