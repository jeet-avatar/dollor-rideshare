# Feature test report: all four apps (2026-10-26)

What was tested, what passed, what failed, what was fixed, and what is still untested. Detail: [Android report](audit-2026-10-26/android_feature_test.md), [iOS report](audit-2026-10-26/ios_feature_test.md), [API inventory](API_INVENTORY.md), [API action matrix script](audit-2026-10-26/action_matrix.py).

## How to read this
- Every app was driven through its screens on a simulator or emulator against the **production API** with the public demo accounts. Production does not yet run the backend fixes on `release/rideshare-backend-20261026`, so these runs show what users would see today.
- PASS means it was observed working (screenshot or server read-back). Rows that rest on logs or inference are labelled so in the detailed reports. Where a screenshot could no longer be re-read, the Android agent said so and I carry that caveat here.
- Android: debug builds, per-call logging (`ApiTiming`). iOS: Release simulator builds, no per-call logger, effects confirmed by server read-back.

## Coverage
| App | Rows | PASS | FAIL | BLOCKED | UNTESTED |
|---|---:|---:|---:|---:|---:|
| Android rider | 36 | 28 (about 12 rely partly on logs) | 0 | 2 | 6 |
| Android driver | 40 | 31 (several logs-only) | 1 (Home tab bug, fixed) | 1 | 7 |
| iOS rider | about 31 | 25 | 0 | 0 | 3 + a bundled row of untouched features |
| iOS driver | about 20 | 15 | 0 | 0 | 5 |

Plus: 78 API checks of every ride action on production (77 as expected, 1 real failure: the iOS-incompatible chat reply, fixed on the backend branch), and a read-only probe of 49 GET endpoints (42 returned 200; the others were my wrong test ids, the not-yet-deployed config route, and one real 500, `GET /api/drivers/{id}/stripe/onboarding-link`, cause unknown).

Full rides observed end to end: Android rider+driver (rides 605, 606, 607: request, bid, counter both ways, accept, chat, arrive, start, complete, rate, receipt, history) and iOS rider+driver (ride 610: request, bid, rider counter, accept, chat both ways, arrive, start, complete, rate, receipt, history).

## Defects found by these runs
| # | App | Defect | Status |
|---|---|---|---|
| 1 | Android rider | Log Out button had no readable label (white on white) | Fixed, verified on the emulator |
| 2 | Android driver | After the History shortcut, the Home tab kept showing Earnings | Fixed, Home tab verified once; not repeated |
| 3 | Backend | Earnings API filled only the requested period, so the driver Profile showed $0.00 for week and month | Fixed on the backend branch with a failing-then-passing test; not live until deployed |
| 4 | iOS rider | Settings screen rows had no visible labels (white cards, white text) | Fixed (dark surface token), builds; not re-verified on a simulator |
| 5 | iOS driver | Completion header showed $17.54 while the body showed $19.55 | Fixed (uses the server's settled price and payout), builds; not re-verified on a simulator |
| 6 | iOS driver | Compliance screen says "Passed" and "background check is in progress" at once | Fixed (message follows the status), builds; not re-verified on a simulator |
| 7 | iOS rider | Receipt shows raw ISO timestamps (the server sends UTC without a zone suffix, which the parser rejected) | Fixed (parser accepts it), builds; not re-verified on a simulator |
| 8 | iOS rider | Trips list shows $21.60 where the receipt shows $21.65 (CPUC $0.05 left out) | Cause confirmed: production's history rows carry only fare and platform fee, no per-ride total; the backend branch adds `total`. Fixed by deploying the backend branch |
| 9 | Production | Chat reply lacks `id` and `sender_id`; an unrelated driver can read and post in any ride's chat | Fixed on the backend branch; live only after deploy |
| 10 | Production | `GET /api/drivers/{id}/stripe/onboarding-link` returns 500 for the demo driver | Open, cause not investigated |
| 11 | iOS driver | `PUT /api/erp/orders/{id}/driver-location` has no backend route | Open |
| 12 | iOS | `GET /api/erp/rides/{id}/negotiation-status` returns 500 (iOS negotiation endpoints) | Open |
| 13 | Android rider | Chat message time stamp 7 hours off (a UTC time was read as local time) | Fixed in code; a JDK check shows 7:15 PM before and 12:15 PM after for the same stamp in Los Angeles. Not re-verified in the app |

Questions rather than defects: the iOS rider's counter ($18.54) was ignored when the rider then tapped Accept on the driver's $20.60 bid (the driver's price governs; confirm this is intended). The iOS driver's counter-back could not be confirmed on the server in that run.

## Not tested (read this before trusting "all features")
- **Not tested on a device or simulator:** iOS tip and skip tip, cancel ride and its fee, SOS, share trip, dispute, safety report, recurring rides, live chat, address add/edit/delete, setting and notification toggles, driver payout dashboard, document and inspection upload, onboarding, waybill, bid withdrawal, driver decline paths, driver counter-back result.
- **Not tested on Android:** rider Help & Support actions, call driver, share-trip, driver own-bid Decline and Counter-back, driver Cancel ride, Navigate with an active ride, driver Support mailto, driver Request Payout.
- **Deliberately not run (destructive or real money):** delete account, log out, password reset, sign-up, email verification, add or delete cards, founding-member purchase, payout, Google sign-in.
- **Not exercised anywhere:** real card charges, push notifications, WebSockets, scheduled and recurring rides, the two-driver competition (driver 129 pending approval), per-call timings on iOS.
- XCUITest suites were not run; Debug iOS builds were not used because `dev-api.dollor.ai` does not resolve.

## API coverage
134 distinct endpoints are called by the four apps (166 call sites). 133 have a matching route in the release backend; the one that does not is the iOS driver location PUT above (a Google Maps call is excluded). 76 of the 134 were exercised in a run (Android UI log or the production matrix); the rest were not exercised in this pass. See [API_INVENTORY.md](API_INVENTORY.md) for each endpoint, its apps, route status, production GET result and coverage.
