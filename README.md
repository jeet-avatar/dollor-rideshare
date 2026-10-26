# Dollor rideshare

Peer-to-peer rideshare with **negotiated fares**: a rider names a price, nearby drivers bid or counter, and the rider picks one. Four native apps share one FastAPI backend.

| App | Platform | Id | Source |
|---|---|---|---|
| Rider | iOS | `com.dollorai.customer` | `apps/ios/customer` |
| Driver | iOS | `com.dollorai.delivery` | `apps/ios/delivery` |
| Rider | Android | `ai.dollor.customer` | `apps/android/app` |
| Driver | Android | `ai.dollor.driver` | `apps/android/driver` |
| Backend | FastAPI | — | `apps/web/p2p-platform/backend` |

Shared code: `apps/ios/eatfair-ios-shared` (Swift package `EatFairShared`) and `apps/android/shared` (Kotlin module). The product is **rideshare only**; leftover food-delivery code is listed in [DO_NOT_USE.md](DO_NOT_USE.md) and must not be extended.

> This repository is a monorepo. Other folders under `apps/` (BeatMind, MixMind, Zietra, hospital pricing, and so on) are separate products and are out of scope here.

## How a ride works

1. **Request.** The rider picks pickup and dropoff and gets a suggested offer from `POST /api/rides/estimate`. `POST /api/rides/request` opens a 5-minute bidding window.
2. **Dispatch.** Only the nearest online drivers see the request (`ride_dispatch.py`): up to 10 drivers, search radius 3 → 5 → 10 → 25 mi at 0 / 30 / 60 / 120 s, and it stops widening once a bid exists.
3. **Bid.** A driver submits a price and ETA (`POST /api/rides/request/{id}/bid`). Drivers who are not yet approved (KYC and background check) cannot bid or go online.
4. **Choose.** The rider accepts, counters, or declines (`POST /api/rides/bid/{id}/respond`). When one driver is accepted, the other drivers see the ride as closed ("accepted by another driver").
5. **Trip.** `arrived` → `start` → `complete`, with in-ride chat, call, SOS and live tracking.
6. **After.** Receipt, ratings in both directions, and an optional tip.

A driver can be signed in on one device at a time (a new login revokes the old session by JWT `jti`).

### Fees

Fees are flat per ride and **come from configuration, never from copy**:

| Fare | Platform fee |
|---|---|
| up to $35 | $1 |
| $35.01 – $70 | $2 |
| over $70 | $3 |

The CPUC Access-for-All charge is $0.10, split $0.05 to the rider and $0.05 to the driver. Drivers keep the rest of the fare plus 100% of tips.

### Dynamic configuration

Fees, pricing rates, bidding presets (92% / 100% / 108%, 5-minute window, ETA choices), dispatch policy and support details are served by `GET /api/config/rideshare` (`rideshare_config.py`, built from `pricing_config.py`, `ride_dispatch.py` and environment variables). Both apps fetch it at launch, cache the last good response on the device, and fall back to bundled defaults that mirror the backend when offline. Change a value once in the backend and every app picks it up without a release.

Values the business has not set are returned as `null` and the apps hide them instead of showing a claim: support hours (`SUPPORT_HOURS_TEXT`), average chat response time (`SUPPORT_RESPONSE_MINUTES`), the ACH note (`ACH_FEE_DISCOUNT_TEXT`) and the referral reward (`REFERRAL_REWARD_TEXT`). Support email, phone and URL default to the existing support contact and can be overridden with `SUPPORT_EMAIL`, `SUPPORT_PHONE`, `SUPPORT_URL`.

Fee tiers are applied in exactly one place on the backend (`platform_fee_for` in `pricing_config.py`).

Where the numbers live on each platform (UI, legal and help text read from these; do not retype them in a screen):
- Android: `AppConfig.Rideshare` in `apps/android/shared/.../config/AppConfig.kt` (`calculatePlatformFee`, `feeRangeText`, `tierLines`).
- iOS: `AppConfig` in `apps/ios/eatfair-ios-shared/Sources/EatFairShared/AppConfig.swift` (`rideshareTierRows`, `rideshareFeeSummary`).
- Backend: the tier constants used when a ride completes (`bid_routes.py`). The backend is the source of truth for charged amounts.

## No hardcoding rules

- **API host:** never typed in a screen. Android reads `API_BASE_URL` from the build flavor (`staging` / `production` in each module's `build.gradle.kts`); iOS reads `API_BASE_URL` from `Info.plist`, set by `apps/ios/Config/{Development,Staging,Production}.xcconfig`.
- **Design:** colors, fonts, radii and spacing come from design tokens: `Lx` in `apps/android/shared/.../ui/Lx.kt` and `Lx` in `LxDesignSystem.swift`. Buttons use `LxButton` (Android) and `.lxPrimary / .lxSecondary / .lxSuccess / .lxDestructive` (iOS).
- **Money:** show cents everywhere (`Lx.Money.text` on iOS, `"%.2f"` on Android). Never round a $9.50 bid to "$10".
- **Secrets:** none in the repo. Server secrets live in the backend environment and AWS Secrets Manager; app keys come from build config. Demo logins exist only in `#if DEBUG` code on iOS.

Check it yourself (both should print `0`):

```bash
grep -rnE 'Color\(hex|\.font\(\.system\(size:|cornerRadius\([0-9]' --include='*.swift' apps/ios/customer apps/ios/delivery | grep -v 'Theme.swift\|UITests' | wc -l
grep -rnE 'Color\(0x' --include='*.kt' apps/android/app/src/main apps/android/driver/src/main | grep -v '/ui/theme/\|DollorLogo' | wc -l
```

## Build and run

### Android (JDK 17)

```bash
cd apps/android
export JAVA_HOME=$(/usr/libexec/java_home -v 17)
./gradlew :app:assembleProductionDebug :driver:assembleProductionDebug
adb install -r app/build/outputs/apk/production/debug/app-production-debug.apk
adb install -r driver/build/outputs/apk/production/debug/driver-production-debug.apk
```

Debug builds log one line per API call under the logcat tag `ApiTiming` (method, path, status, milliseconds; no headers or bodies). Release builds log nothing from the network layer.

```bash
adb logcat -s ApiTiming
```

### iOS (Xcode)

Open `apps/ios/EatFair.xcworkspace`, pick the `eatfaircustomer` or `eatffairdelivery` scheme, and choose Debug (dev API) or Release (production API). Release/TestFlight builds go through `apps/ios/fastlane`. Use automatic signing and a date-based build number; verify processing in App Store Connect.

### Backend

```bash
cd apps/web/p2p-platform/backend
python3 -m venv .venv && . .venv/bin/activate
pip install -r requirements.txt            # FastAPI 0.115.0 / Starlette 0.38.6
cp .env.example .env                        # fill in DATABASE_URL, JWT_SECRET_KEY, Stripe, SMTP, Google Maps, Firebase
uvicorn main_new:app --reload --port 3000
```

Production runs the same app in Docker (`uvicorn main_new:app` on port 8080). Pushing to `main` deploys production, so work on a branch and open a pull request.

## Tests

```bash
cd apps/web/p2p-platform/backend
export JWT_SECRET_KEY=<at least 32 chars> DATABASE_URL=sqlite:///./test.db
python -m pytest tests -q
```

Use a venv built from `requirements.txt`. An old Starlette (0.27) makes request tests hang. On the launch-readiness backend branch the suite is 803 passed / 67 failed against a baseline of 770 passed / 76 failed on `origin/main`: no new failures, and the 67 remaining are pre-existing (smoke, wiring and email-template tests).

Route hygiene: no `(method, path)` may be registered twice. See the script in [DO_NOT_USE.md](DO_NOT_USE.md) section 6.

## Repository map

```
apps/
  android/{app,driver,shared}            Android rider, driver, shared module
  ios/{customer,delivery}                iOS rider and driver
  ios/eatfair-ios-shared                 shared Swift package
  ios/Config                             per-environment xcconfig (API_BASE_URL)
  web/p2p-platform/backend               FastAPI backend (main_new.py, bid_routes.py, order_flow.py, ride_dispatch.py)
docs/LAUNCH_READINESS_REPORT.md          audit, timings, open items
DO_NOT_USE.md                            legacy code register: what not to call or copy
```

## Read next

- [docs/LAUNCH_READINESS_REPORT.md](docs/LAUNCH_READINESS_REPORT.md): API audit, timings and what is still untested.
- [DO_NOT_USE.md](DO_NOT_USE.md): legacy names, endpoints and repo hygiene.
- `apps/android/CLAUDE.md`: Android conventions.

## Known open items

Driver 129 approval (needs an admin) blocks the two-driver competition test. Not built yet: ride PIN, off-route alerts, a rider-facing "drivers contacted" count. Real Stripe charging and iOS push were not exercised with demo accounts. The full list is in the launch-readiness report.
