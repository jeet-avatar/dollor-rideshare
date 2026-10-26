> Generated 2026-10-26 by automated audit passes. Line numbers refer to the code at that time; several findings listed here were fixed afterwards (see docs/LAUNCH_READINESS_REPORT.md section 10). Verify before relying on a specific line.

# Hardcoded business values audit (rideshare apps)

Repo `/Users/jeet/doordash-p2p`, branch `release/rideshare-launch-ready-20261026`. Read-only audit, no source edited.
Scope: Android `apps/android/{app,driver,shared}/src/main`, iOS `apps/ios/customer/eatfaircustomer`, `apps/ios/delivery/eatffairdelivery`, `apps/ios/eatfair-ios-shared/Sources`.
Backend truth: `/private/tmp/dollor-single-session-wt/apps/web/p2p-platform/backend` (`pricing_config.py`, `ride_dispatch.py`, `rideshare_config.py`, `bid_routes.py`, `founding_members.py`).

Path shorthand (all under `apps/`):
- `A:app` = `android/app/src/main/java/com/eatfair/app`
- `A:drv` = `android/driver/src/main/java/com/eatfair/driver`
- `A:shr` = `android/shared/src/main/java/com/eatfair/shared`
- `I:cust` = `ios/customer/eatfaircustomer`
- `I:drv` = `ios/delivery/eatffairdelivery`
- `I:shr` = `ios/eatfair-ios-shared/Sources/EatFairShared`

Risk key: **W** = user-visible wrong or unsupported claim, **B** = behavior differs from backend or between platforms, **C** = cosmetic or latent (static, dead or unreachable code).
Category key: F money/fees, R rule claim, T time/timer, D distance/radius, U contact/URL, L limits/option lists, P promo/referral, X dead/unreachable.

Backend reference values: base 2.50, 1.15/mi, 0.18/min, **minimum fare 8.00** (`pricing_config.py:18-21`); tiers 35/70 -> 1/2/3 (:24-28); Access for All 0.10 (0.05 rider + 0.05 driver) (:47-49); **rider cancellation fee 0.00** (:52); bidding window 5 min, factors 0.92/1.00/1.08, ETA options 3/5/10/15 (:55-59); time-of-day multipliers 1.15/1.20/1.10/0.95 and demand multiplier up to 1.50 (:31-44); dispatch max 10 drivers, radius steps 3/5/10/25 mi at 0/30/60/120 s (`ride_dispatch.py:13-21`); **no-show fee $5.00, driver gets 80%, wait 300 s** (`bid_routes.py:2307, 2330, 2345`); bid price only >0 and <=10000 (:168-174); counter floor 40% reject / 60% warn of suggested (:1171-1180); `MAX_CUSTOMER_COUNTERS=3` (:1135), `MAX_ROUNDS_PER_BID=2` (:1145); `/rides/available` default `radius_km=15.0` (:1350); founding deposit $100 (`founding_members.py:40`).

## Findings (sorted by risk)

| # | file:line | literal / snippet | what it represents | platform | correct source | risk | cat |
|---|---|---|---|---|---|---|---|
| 1 | A:app/ui/auth/RegisterScreen.kt:325 | `"No hidden fees or surge pricing"` | Rule claim shown on register screen. Backend applies demand surge (`bid_routes.py:515-518, 622`; `pricing_config.py:43`) and time multipliers (:31-34); iOS shows surge banners (I:cust/Views/RideRequestView.swift:544-569) | Android | Remove or reword (truly a claim, not a config value) | W | R |
| 2 | A:app/ui/auth/RegisterScreen.kt:193-195 | `"$1"` "Platform Fee", `"0%"` "Commission", `"100%"` "Tips to Drivers" | Fee is 1-3 (tiers) plus 0.10 Access for All; "0% commission" is a rule claim | Android | `fees.tier1Fee..tier3Fee` (use `AppConfig.Rideshare.feeRangeText`); reword the 0% claim | W | F,R |
| 3 | A:app/ui/auth/RegisterScreen.kt:179, :328 | `"100% of your payment goes directly to drivers"`, `"Drivers receive 100% of fares & tips"` | Contradicts platform fee 1-3 and Access for All 0.10 deducted from driver (`ActiveRideViews.kt:371-372` shows it) | Android | Reword; amounts from `fees.*` | W | R |
| 4 | A:app/ui/auth/LoginScreen.kt:497, :505 | `text = "$1"` + `"flat platform fee. 100% tips go to drivers."` | Fee shown as flat $1; real fee is 1/2/3 by fare. iOS uses `AppConfig.shared.rideshareFeeRangeText` (I:cust/Views/LoginView.swift:304) | Android | `fees.*` via `AppConfig.Rideshare.feeRangeText` | W | F |
| 5 | I:cust/Views/PlaceholderViews.swift:94 | `"a small cancellation fee may apply depending on how far the driver has traveled"` | Backend rider cancellation fee is 0.00 (`pricing_config.py:52`, `rideshare_config.py` `riderCancellationFee`). iOS own config says 0 (I:shr/AppConfig.swift:313-315) | iOS | `fees.riderCancellationFee` (conditional text) | W | R |
| 6 | I:cust/Views/HelpSupportView.swift:292 | `"Cancellation fees may apply depending on the ride status."` | Same as #5 | iOS | `fees.riderCancellationFee` | W | R |
| 7 | I:cust/Views/HelpSupportView.swift:328 | `"you both get $5 credit!"` | Referral reward. Backend `referral.rewardText` is null until a reward exists (`rideshare_config.py`, comment above `"referral"`) | iOS | `referral.rewardText` (hide if null) | W | P |
| 8 | I:cust/Views/ReferAndEarnView.swift:177, :191 | `"You both get $5 in credits!"`, `"Referral credits expire 90 days after issue."` | Reward amount and an expiry rule with no backend source. The share message at :208 is already config-gated, the on-screen copy is not | iOS | `referral.rewardText`; new field for expiry (or remove) | W | P |
| 9 | A:app/ui/refer/ReferAndEarnScreen.kt:95, :221 | `"you and your friend will get $5 off your next ride!"`, `"You both get $5"` | Same as #7; also iOS says "credit", Android says "off your next ride" | Android | `referral.rewardText` | W | P |
| 10 | I:cust/Views/ReferAndEarnView.swift:224-227 (shown at :127-139) | `Int.random(in: 0...5)`, `Double.random(in: 0...15)`, `Double.random(in: 0...25)` | Fabricated referral counts and credits displayed as real stats ("in production, fetch from API") | iOS | Real API or hide the stats card | W | P |
| 11 | A:app/ui/help/HelpSupportScreen.kt:310; A:app/ui/privacy/DriverPrivacyScreens.kt:465-466; I:cust/Views/HelpSupportView.swift:183; I:cust/Views/DriverPrivacyViews.swift:412 | `"available 24/7"`, `"24/7 Support"`, `"around the clock"` | Support hours claim. Backend `support.hoursText` is null unless configured; phone row already uses it (HelpSupportScreen.kt:147, HelpSupportView.swift:115) | both | `support.hoursText` (hide if null) | W | R |
| 12 | I:cust/Views/PlaceholderViews.swift:215 | `"get back to you within 24 hours"` | Response-time promise; Android and the HelpSupport row use `support.responseMinutes` | iOS | `support.responseMinutes` | W | T |
| 13 | I:cust/Views/SafetyReportSheet.swift:112 | `"review within 48 hours"` (also says driver "immediately suspended") | Safety SLA and action claim, no backend source | iOS | New field `support.safetyReviewHours` or reword | W | T |
| 14 | I:cust/Views/DisputeRideView.swift:250 vs A:app/ui/help/HelpSupportScreen.kt:125 | iOS `"within 3-5 business days"`, Android `"within 5-7 business days"` | Refund timing; the two apps disagree and neither has a source | both | New field `support.refundDaysText` or reword | W | T |
| 15 | A:drv/ui/compliance/DriverComplianceScreens.kt:581 | `"15 years old or newer (2010 or later)"` | Vehicle age rule. Today is 2026-10-26, so "15 years or newer" means 2011 or later; the year goes stale annually. No backend constant found (grep) | Android | New field `compliance.maxVehicleAgeYears`, compute year | W | R |
| 16 | A:app/ui/rideshare/RideRequestScreen.kt:837, :924 | `"(tiered $1-$3)"`, `"$1-$3 tiered connection fee"` | Fee range as literal text; `AppConfig.Rideshare.feeRangeText` exists (AppConfig.kt:339-341) | Android | `fees.tier1Fee..tier3Fee` | W | F |
| 17 | I:cust/Views/SettingsView.swift:556; I:cust/Views/PlaceholderViews.swift:86; I:drv/Views/Rideshare/SubmitBidSheet.swift:520; A:drv/ui/compliance/DriverComplianceScreens.kt:791 | `"$1-$3 based on fare"`, `"$1–$3"`, `"$1-3 flat fee"`, `"Only a $1-$3 fee"` | Fee range literals (and Access for All 0.10 not disclosed) | both | `fees.*` (feeRangeText / tierLines) | W | F |
| 18 | A:shr/ui/LegalAcceptanceScreen.kt:271 | `"Dollor only charges \$1-\$3 per order"` under "Restaurant Partner Agreement" | Food/restaurant wording in a rideshare app ("per order") | Android | Remove (not rideshare) | W | R |
| 19 | I:drv/Views/Rideshare/SubmitBidSheet.swift:284, :297, :310 | `subtitle: "92%"`, `"100%"`, `"108%"` | Bid preset labels; amounts use config (`RideBiddingViewModel.swift:703-709` via `bidQuickAcceptFactor...`), labels do not. Android computes `${(factor*100).roundToInt()}%` (A:drv SubmitBidSheet.kt:140) | iOS | `bidding.quickAcceptFactor/fairFactor/premiumFactor` | W | L |
| 20 | I:drv/Views/DriverOnboardingView.swift:284 | `"standard (≈2 days) free · instant cash-out ~1%"` | Payout timing and fee. Android model default says instant fee `1.50` (A:shr model/ApiModels.kt:537; DriverEarnings.kt:186 comment "$1.50 fee"); no backend constant found | iOS | New field `payout.standardDays`, `payout.instantFee` | W | F,T |
| 21 | I:drv/Views/Rideshare/ActiveRideView.swift:207 | `"charged a $5.00 cancellation fee. You will receive $4.00 for your wait time."` | No-show fee and driver share; matches backend `NOSHOW_CANCELLATION_FEE=5.00` and 80% (`bid_routes.py:2307, 2345`) but literal. Android driver shows no such disclosure | iOS (Android lacks) | New fields `noShow.feeAmount`, `noShow.driverShare` | B | F |
| 22 | I:cust/Views/RideRequestView.swift:612-617; I:cust/ViewModels/RideRequestViewModel.swift:159-167, :220 (state table I:shr/AppConfig.swift:720-737) | local fallback `estimatedFare = fare + platformFee + taxAmount`, "Tax (x%)" | Fallback estimate adds state sales tax. Backend has no ride tax (no `tax` in `pricing_config.py`); Android fallback adds none | iOS | Remove tax from ride fallback (no source) | B | F |
| 23 | A:shr/config/AppConfig.kt:200 | `MINIMUM_FARE = 5.00` ("matches iOS") | Android default 5.00 vs backend 8.00 (`pricing_config.py:21`) and iOS 8.00 (AppConfig.swift:312). Drives offer floor (A:app RideRequestScreen.kt:1838, :2008) and fallback fare (CustomerRideshareApiService.kt:81, :883) until remote config lands | Android | `pricing.minimumFare` (fix default to 8.00) | B | F |
| 24 | A:drv/ui/orders/AvailableOrdersScreen.kt:196, :202 | `"Minimum $5.00"`, `price >= 5.0` | Final counter-offer floor. Backend enforces only >0 and <=10000 (`bid_routes.py:168-174`); app minimum fare is 8.00; iOS driver uses `proposedAmount > platformFee` (I:drv SubmitBidSheet.swift:34) | Android | `pricing.minimumFare` or new `bidding.minCounter` | B | F,L |
| 25 | A:app/ui/rideshare/RideRequestScreen.kt:1840-1843; I:cust/Views/RideRequestView.swift:785-788 | quick offers `fare * 0.6/0.7/0.8/0.9` | Rider quick-offer ladder. Backend rejects counters under 40% and warns under 60% (`bid_routes.py:1171-1180`) | both (same values) | New field `bidding.riderOfferFactors` | B | L |
| 26 | I:cust/Views/RideRequestView.swift:2898 | `ForEach([5, 10, 15, 20]...)` quick offer buttons, no min-fare check in `submitOffer` (:2955-2957) | A $5 offer is below the 8.00 minimum fare | iOS | `pricing.minimumFare` floor, or derive from fare | B | L |
| 27 | I:cust/Views/RideRequestView.swift:3174 | `bid.proposed_price * 0.9` | Pre-filled counter at 90% of driver bid | iOS | New `bidding.counterPrefillFactor` | C | L |
| 28 | A:app/ui/rideshare/RideRequestScreen.kt:736; A:app/ui/rating/RateDriverScreen.kt:257; A:app/ui/tip/TipDriverScreen.kt:39-42; I:cust/Views/RideRequestView.swift:2626; I:shr/AppConfig.swift:291 (`rideTipOptions`, unused) | tips `[0,2,3,5]`, `[2,3,5,0]`, `[2,3,5,10]`, iOS `[2,5,10]`, config `[0,2,5,10]` | Tip option lists; four different sets across screens/platforms | both | New field `tips.rideOptions` | B | L |
| 29 | I:cust/Views/RideRequestView.swift:3297 | `"Round \(round)/2"` | Negotiation rounds cap; backend `MAX_ROUNDS_PER_BID=2` (`bid_routes.py:1145`), `MAX_CUSTOMER_COUNTERS=3` (:1135) | iOS | New `bidding.maxRounds`, `bidding.maxCustomerCounters` | B | L |
| 30 | A:drv/ui/home/ActiveRideViews.kt:45; I:drv/Views/Rideshare/ActiveRideView.swift:22, :808 | `NO_SHOW_WAIT_SECONDS = 300L`; `noShowTimerSeconds = 300`; `noShowWindowSeconds = 300` | No-show wait; matches backend `300` (`bid_routes.py:2330`) but hardcoded in 3 places + backend | both | New `noShow.waitSeconds` | B | T |
| 31 | I:shr/AppConfig.swift:288 -> I:drv/ViewModels/RideBiddingViewModel.swift:214 vs A:shr/data/remote/DollorApiService.kt:431-435 | iOS sends `radiusKm = 100.0`; Android sends no radius, so backend default `radius_km=15.0` (`bid_routes.py:1350, 1437`) applies | Driver ride-list radius. Android caps at ~9.3 mi, so `dispatch.radiusSteps` 10/25 mi (`ride_dispatch.py:16-21`) never reach Android drivers; iOS sees up to 100 km | both (disagree) | `dispatch.radiusSteps` (or server ignores client radius) | B | D |
| 32 | I:shr/AppConfig.swift:181, :246, :253, :260, :267, :374 | `5.0 + (distanceMiles * 1.50)`, `"≤10mi"/"10-20mi"/">20mi"` | Deprecated distance->fare estimate; disagrees with base 2.50 + 1.15/mi + 0.18/min. No callers outside AppConfig found by grep | iOS | Delete | C | F |
| 33 | I:shr/AppConfig.swift:295, :317 | `driverEarningsPercentage = 96`, `rideMaxSurgeMultiplier = 3.0` | 96% contradicts flat-fee model; max surge 3.0 vs backend `MAX_DEMAND_MULTIPLIER=1.50` (`pricing_config.py:43`). Both unused outside AppConfig (grep) | iOS | Delete or fix defaults | C | F |
| 34 | A:app/ui/rideshare/RideRequestViewModel.kt:517; I:cust/ViewModels/RideRequestViewModel.swift:365-366 | `distance / 25.0 * 60 * 1.2` | Fallback ETA: 25 mph + 20% buffer (offline only) | both (same) | New `pricing.fallbackSpeedMph` or truly ok | C | T |
| 35 | I:drv/Views/Rideshare/WaybillSheet.swift:48 | `fare["access_for_all_fee"] ?? "0.10"` | Fallback A4A amount shown if the field is missing | iOS | `fees.accessForAllFee` | C | F |
| 36 | A:drv/ui/home/DriverHomeScreen.kt:318, :324; A:drv/ui/profile/ProfileScreen.kt:71, :77, :276; A:app/ui/rideshare/RideReceiptScreen.kt:134; A:app/ui/help/SupportChatScreen.kt:58; A:app/constants/Constants.kt:29; I:cust/Views/RideReceiptView.swift:578 | `"support@dollor.ai"`, `"+1-800-365-5671"` as literals | Support email/phone. Customer Settings/NavGraph already use `AppConfig.Rideshare.support.email` (SettingsScreen.kt:208, NavigationGraph.kt:705) | both | `support.email`, `support.phone` | C | U |
| 37 | A:drv/ui/profile/ProfileScreen.kt:239; I:drv/Views/DriverProfileView.swift:1083; A:app/ui/founding/FoundingViewModel.kt:36 and A:drv/ui/founding/FoundingViewModel.kt:33 (`deposit=100.0`); I:cust/Views/FoundingMemberView.swift:263, I:drv/Views/FoundingMemberView.swift:242 (`feeAmount=100`) | `"$100"` | Founding deposit; backend `FOUNDING_DEPOSIT_CENTS=10000` (`founding_members.py:40`). The founding screens read the live value; only profile menu subtitles are literal | both | Founding status API value | C | F |
| 38 | I:cust/Views/SafetyReportSheet.swift:91, :131; I:drv/Views/Rideshare/WaybillSheet.swift:54; I:cust/Views/RideReceiptView.swift:578 | `1-800-894-9444`, `CIU_intake@cpuc.ca.gov` | CPUC regulator contact | iOS | Truly static / ok (regulatory); Android receipt uses `receipt.cpucPhone` from API | C | U |
| 39 | I:drv/ViewModels/DriverProfileViewModel.swift:485 (60 days), :84 (30), I:drv/Views/ComplianceView.swift:108 (30) | document-expiry alert thresholds | Doc expiry warning windows | iOS | New `compliance.expiryWarningDays` or ok | C | T |
| 40 | A:drv/ui/compliance/DriverComplianceScreens.kt:353, :376-380, :583 | `7 years`, `3 moving violations in past 3 years`, `Minimum 4 passengers` | Background-check / vehicle criteria copy; Checkr scope is server-side | Android | New `compliance.*` text or ok | C | R |
| 41 | I:drv/Views/PayoutDashboardView.swift:475 | `"Periods are calculated every 14 days"` | Prop 22 period length | iOS | Backend field or ok | C | T |
| 42 | A:shr/config/AppConfig.kt:231-240 (`Support.phone=null`, `url=null`) vs I:shr/AppConfig.swift:381-383 (phone `+1-800-365-5671`, url set); A:shr Legal `SUPPORT_URL="https://dollor.ai/support"` vs backend `https://www.dollor.ai/support` | support defaults | Android has no offline phone/URL, iOS does; Android URL lacks `www` | both | `support.*` | C | U |
| 43 | A:app/ui/address/AddAddressDetailsScreen.kt:252 vs :275 | `if (it.length <= 100)` vs `"${instructions.length}/200"` | Delivery-instructions limit shown as 200, enforced at 100 | Android | One constant | C | L |
| 44 | A:app/res/values/strings.xml:4, :6 | `"No Commission. Just $1."`, `"flat $1-$3 fee, no commission"` | Tagline strings; `R.string.app_tagline/app_description` are not referenced in Kotlin (grep) | Android | Delete or `fees.*` | C | R |
| 45 | A:app/ui/profile/TermsConditionsScreen.kt:67 | `"platforms that take 25-35% commission"` | Competitor-commission marketing claim inside Terms | Android | Remove (claim) | C | R |
| 46 | A:shr/config/AppConfig.kt:204-217, :405-428 (time multipliers 1.15/1.20/1.10/0.95, distance discounts, `generateSuggestedBids` 0.92/1.08, `getBidComparisonLabel` -10/-5/5/15 %) | local pricing helpers | Duplicate pricing engine; none referenced by the apps (grep for `calculateFare(`, `getTimeMultiplier`, `generateSuggestedBids`, `getBidComparisonLabel`, `calculateDistanceDiscount` outside AppConfig: none). Values match backend `pricing_config.py:31-34, 212-228` | Android | Delete | C | X |
| 47 | A:app/constants/Constants.kt:9-25 | `DEFAULT_TAX_RATE 0.0725`, delivery tiers `1/2/3`, `DRIVER_BASE_PAY 3.00`, `DRIVER_PER_MILE 0.50` | Food-era constants; `PricingConfig`/`AppConstants` have no references (grep) | Android | Delete | C | X |
| 48 | A:app/data/CustomerRideshareApiService.kt:921-923 | `"Tier 1 (up to $35)"`, `"Tier 2 ($35-$70)"`, `"Tier 3 (above $70)"` | Tier labels literal; no callers (the live path is `AppConfig.Rideshare.getTierName`, RideRequestViewModel.kt:986) | Android | Delete | C | X |
| 49 | A:shr/model/order/MultiRestaurantOrder.kt:166-170 | `PLATFORM_FEE_PER_RESTAURANT 1.0`, `BASE_DELIVERY_FEE 5.0`, `EXTRA_STOP_FEE 2.0`, `DEFAULT_TAX_RATE 0.08`, `DEFAULT_TIP_RATE 0.20` | Food order math; not rideshare (reachability not confirmed) | Android | Delete if unreferenced | C | X |
| 50 | I:shr/Views/ViralFeaturesView.swift:53, :139, :145, :282, :425, :613-614, :632-639 | `"Give $10, Get $10"`, `"10% off"`, `"expires in 2 hours"`, fake code `DLR8X7K9`, fake leaderboard | Referral/group-order marketing with fake data. `ReferralHubView`/`GroupOrderView` referenced only inside the file and previews | iOS | Delete | C | X |
| 51 | I:shr/Views/PaymentBreakdownView.swift:161, :170, :230, :295, :453-477; I:shr/Views/V3CheckoutView.swift:729; I:shr/Utilities/Calculators.swift:9-191 | `"$1.00 per order"`, `"$2.99"`, tips `[15,18,20,25]`, 50-state tax tables, `defaultRate 7.0`, 20 mph | Food checkout/tax code. `PaymentBreakdownView`, `V3CheckoutView`, `TaxCalculator`, `TipCalculator` have no call sites outside their own files | iOS | Delete | C | X |
| 52 | I:cust/Services/ACHPaymentService.swift:439-442 | `0.029 + 0.30`, `min(amount*0.008, 5.0)`, `discount 0.50` | Offline ACH fee fallback; `ACHPaymentButton` has no call site (grep) | iOS | `support.achFeeDiscountText` / backend | C | X |
| 53 | A:shr/data/remote/CallService.kt:352; A:shr/model/driver/Driver.kt:259-261 | `+ 14400000` (4 h), `100.0` default rates | Fallback call expiry; stat defaults | Android | ok | C | T |
| 54 | A:app/ui/rideshare/RideRequestViewModel.kt:296, :363; A:app/ui/address/LocationMapScreen.kt:139; I:drv/Services/LocationManager.swift:378 | GPS accuracy `<100` / `<200` m | Location quality gates, not business rules | both | truly static / ok | C | D |
| 55 | Polling/timers: A:app DriverChatScreen.kt:57 (3 s), RideRequestViewModel.kt:703 (3 s), :827 (5 s); A:drv DriverHomeViewModel.kt:72 (5 s), :182 (3 s), AvailableRidesViewModel.kt:50 (5 s); I:cust RideRequestViewModel.swift:557 (5), :912 (5), :1016 (3); I:drv LocationManager.swift:52 (5), ComplianceView.swift:313 (15), DriverOnboardingView.swift:943 (10); AppConfig.swift:280 `driverPollingInterval 5.0` | polling intervals | Transport cadence, not a business rule | both | truly static / ok | C | T |
| 56 | Phone length rules: A:app LoginScreen.kt:102 / RegisterScreen.kt:107 (10 digits); I:drv/DriverLoginView.swift:230-240, :309 (10-15 digits) | validation | Android 10 only vs iOS driver 10-15 | both | ok | C | L |

## Already correct (verified, no action)

- Fee tier text/amounts come from `AppConfig.Rideshare` / `AppConfig.shared`: Android `HelpSupportScreen.kt:95` (`tierLines`), shared `LegalAcceptanceScreen.kt:92` (`feeRangeText`), iOS `HelpSupportView.swift:280`, `LoginView.swift:304`, `DriverOnboardingView.swift:274`.
- ETA options: Android `A:drv SubmitBidSheet.kt:63`, iOS `I:drv SubmitBidSheet.swift:449` both use `etaOptionsMinutes`.
- Bid amounts use remote factors on both platforms (`A:drv SubmitBidSheet.kt:136`, `RideBiddingViewModel.swift:703-709`).
- Support email/phone/hours/response/ACH text and referral share message are config-gated in Settings, Help, and share intents.
- iOS cancel confirmation (`RideRequestView.swift:2321-2328`) is driven by `estimatedCancellationFee`.
- Bidding countdown (`A:app RideRequestScreen.kt:2250`) uses the server expiry, not `windowMinutes`.
- `biddingWindowMinutes`, `accessForAllRiderShare/DriverShare`, `dispatch.*` are fetched but never read by any UI on either platform (grep), so they are not used to display anything. iOS `applyRideshareConfig` also ignores `accessForAll*`, `dispatch`.

## Counts per category (rows in table above)

| Category | Rows |
|---|---|
| F money/fees | 2, 4, 16, 17, 20, 21, 22, 23, 24, 32, 33, 35, 37 = 13 |
| R rule claim | 1, 2, 3, 5, 6, 11, 15, 17(part), 18, 40, 44, 45 = 11 (primary) |
| P promo/referral | 7, 8, 9, 10 = 4 |
| T time/timer/SLA | 12, 13, 14, 20, 30, 34, 39, 41, 53, 55 = 10 |
| D distance/radius | 31, 54 = 2 |
| U contact/URL | 36, 38, 42 = 3 |
| L limits/option lists | 19, 25, 26, 27, 28, 29, 43, 56 = 8 |
| X dead/unreachable | 46-52 = 7 |

By risk: **W = 20** (rows 1-20), **B = 11** (rows 21-31), **C = 25** (rows 32-56 including dead code and static ok items). Total 56 rows.

## Android vs iOS vs backend disagreements

1. Minimum fare: Android default 5.00 (AppConfig.kt:200) vs iOS 8.00 (AppConfig.swift:312) vs backend 8.00 (pricing_config.py:21).
2. Ride-list radius: iOS sends 100 km, Android sends none (backend 15 km default), backend dispatch steps up to 25 mi (rows 31).
3. Tax on rides: iOS fallback adds state tax, Android does not, backend has none (row 22).
4. Login fee line: Android "$1 flat", iOS fee range from config (row 4).
5. Cancellation fee copy: iOS static FAQ says a fee may apply, backend and iOS config say 0 (rows 5-6); Android FAQ says nothing about a fee but also says rides can be cancelled only before a driver matches (HelpSupportScreen.kt:83) while the app allows cancelling after acceptance (RideRequestScreen.kt:1464-1473).
6. Referral reward wording: iOS "$5 credit(s)" with 90-day expiry, Android "$5 off your next ride", backend reward null (rows 7-9).
7. Refund timing copy: iOS 3-5 business days, Android 5-7 (row 14).
8. Tip option sets differ across screens and platforms (row 28).
9. No-show: iOS driver shows $5.00 / $4.00 disclosure, Android driver shows none; backend charges $5.00 and pays driver 80% (row 21).
10. Driver counter floor: Android $5.00 minimum, iOS only `> platformFee`, backend only `> 0` (row 24).
11. Instant payout fee: iOS copy "~1%", Android model default 1.50 (row 20); backend source not found by grep.
12. Support defaults offline: iOS has phone and URL, Android phone/URL null; Android Legal URL has no `www` (row 42).
13. Driver phone validation: iOS 10-15 digits vs Android 10 (row 56).
14. iOS `rideMaxSurgeMultiplier 3.0` vs backend 1.50 and iOS `driverEarningsPercentage 96` vs flat fee (row 33), both unused.
15. iOS `applyRideshareConfig` applies `riderCancellationFee` only to two of three cancellation constants (AppConfig.swift:434-445); Android ignores `riderCancellationFee` entirely.

AppConfig defaults other than #1 and #14 agree with backend (tiers 35/70, fees 1/2/3, factors 0.92/1.00/1.08, window 5, ETA 3/5/10/15, base 2.50, 1.15, 0.18).
