> Generated 2026-10-26 by automated audit passes. Line numbers refer to the code at that time; several findings listed here were fixed afterwards (see docs/LAUNCH_READINESS_REPORT.md section 10). Verify before relying on a specific line.

# Dead-code inventory: Dollor rideshare stack (Android / iOS / Backend)

Generated 2026-10-26. READ-ONLY audit. Client repo: `/Users/jeet/doordash-p2p` @ `release/rideshare-launch-ready-20261026` (HEAD d3498fc9). Backend: `/private/tmp/dollor-single-session-wt/apps/web/p2p-platform/backend` @ `release/rideshare-backend-20261026`. No file was modified or deleted.

## How the evidence was gathered (read this first)

- **Android**: every `.kt` in `app|driver|shared/src/main` was parsed for top-level class/object/interface/fun/val names. A file is a deletion unit only if NONE of its declared names occurs (comments stripped, string literals stripped) in any other live file, manifest, gradle, proguard or json (iterated as a cascade: removing a dead file can orphan another). Then each unit was re-verified with a raw `grep -rnw -I NAME app driver shared --include=*.kt,*.xml,*.gradle,*.kts,*.pro,*.json | grep -v <own file>`; the three counts in the evidence column are `all hits / hits under src/main / non-comment hits under src/main`. Every non-zero count is explained in the Notes column (always: another dead unit, a comment, a string, or an androidTest). Hilt: all `@Module` objects (`AppModule`, `RepoModule`, `SharedModule`) are registered by annotation, so they are KEEP even though nothing names them. Manifest components (Application, Activities, FCM services) are KEEP.
- **iOS**: same method on `.swift` in `customer/eatfaircustomer`, `delivery/eatffairdelivery`, `eatfair-ios-shared/Sources` (types AND methods, comment+string stripped, iterated cascade of 7 rounds, protocol-requirement names like `makeBody`/delegate callbacks excluded). Raw check: `grep -rnw -I NAME apps/ios --include=*.swift,*.plist,*.pbxproj,*.json,*.storyboard | grep -v <own file>`. **Xcode membership**: both app targets use `PBXFileSystemSynchronizedRootGroup` (customer pbxproj, delivery pbxproj: 5 matches each) and the shared code is an SPM local package that auto-includes `Sources/EatFairShared`, so NO `project.pbxproj` edit is needed to delete a file; `grep -c <filename> project.pbxproj` = 0 for every file listed. The only `membershipExceptions` entry is `Info.plist`.
- **Backend**: the real route table was extracted by importing `main_new.app` with `/private/tmp/ss-venv` (466 routes incl. aliases; `PYTHONDONTWRITEBYTECODE=1`, in-memory sqlite; worktree stayed clean). Each route was matched against: iOS + Android client endpoint lists (`calls.json`, re-derived), web `frontend/src` (relative, template and absolute `https://api.dollor.ai/...` strings), `admin_frontend` bundle, and `backend/tests`. 144 routes (excluding docs) have no reference anywhere. IMPORTANT finding: the backend branch has ALREADY removed essentially all food/vendor/restaurant/menu/order/cart routes (only 3 broken aliases remain, see below). 132 of the 134 iOS endpoint strings that sit inside dead iOS code point at routes that do not exist on the backend (`match.json` status `missing`; the other 2 are `TripBoardService.sendMessage`/`updateTripStatus` and `updateDriverLocation`, left out only because of method-name collisions), which independently corroborates that the iOS food/vendor surface is dead.
- Limits: static analysis cannot see `NSClassFromString`, `Class.forName`, KVC, Gson/Codable field reflection on property names, or callers outside the repo (e.g. production scripts). Those are flagged NEEDS-CHECK where plausible. Counts are lower bounds: names that are also common English words (`Order`, `Rating`, `Driver`) were hand-verified.

## Totals (lines)

| Platform | SAFE | NEEDS-CHECK | Notes |
|---|---:|---:|---|
| Android (src/main) | ~3,640 | ~610 (+2,403 SAFE / 903 NEEDS-CHECK stale tests) | 27 whole files = 3,266; plus 148 AppConfig, 52 ImportBlinkitCard, 56 Retrofit methods, ~118 res lines + 1 PNG (166 KB) |
| iOS | ~16,360 | ~3,544 (+1,059 SAFE / 1,697 NEEDS-CHECK stale tests) | 12 dead files = 4,095; unit-level (functions/types inside live files, incl. whole dead service files) 12,266 |
| Backend | ~6,500 | ~6,100 (+ 383 tracked PDFs) | 12 never-imported scripts 4,550; 8 tracked report/artifact files 1,604; 3 broken alias lines; ~340 dead helper lines |
| **Total** | **~26,500** | **~10,250 (+~2,600 NEEDS-CHECK tests, +~3,460 SAFE tests)** | |

(iOS SAFE figure: 4,095 dead files + 12,266 unit-level = 16,361. Unit-level numbers are the union of line ranges, so no double counting. Test files are listed separately and are not in the SAFE totals.)

---

# ANDROID

## A1. Whole-file deletions (verdict SAFE)

Paths relative to `/Users/jeet/doordash-p2p/apps/android/`. Evidence = `grep -rnw -I <symbol> app driver shared (kt/xml/gradle/kts/pro/json) | grep -v <own file>` as `all/src-main/non-comment`.

| path (symbols) | lines | evidence of zero references | verdict | notes |
|---|---:|---|---|---|
| `shared/src/main/java/com/eatfair/shared/data/remote/NegotiationService.kt` (NegotiationService, NegotiationEvent, NegotiationResult) | 394 | `NegotiationService` 0/0/0; `NegotiationEvent` 0/0/0; `NegotiationResult` 0/0/0 | SAFE | Hilt @Inject class never injected; only mentions are KDoc in CustomerRideshareApiService/RideRequestScreen |
| `shared/src/main/java/com/eatfair/shared/data/remote/CallService.kt` (CallService, CallSession, CallLog) | 372 | `CallService` 0/0/0; `CallSession` 0/0/0; `CallLog` 0/0/0 | SAFE | never injected/constructed |
| `app/src/main/java/com/eatfair/app/ui/tip/TipDriverScreen.kt` (TipDriverScreen, TipCard, TipOption) | 340 | `TipDriverScreen` 0/0/0; `TipCard` 0/0/0; `TipOption` 0/0/0 | SAFE | not in NavigationGraph; tipping is via RateDriverScreen/RideReceipt |
| `shared/src/main/java/com/eatfair/shared/model/order/MultiRestaurantOrder.kt` (MultiRestaurantOrder, MultiRestaurantOrderItem, RestaurantInfo) | 261 | `MultiRestaurantOrder` 0/0/0; `MultiRestaurantOrderItem` 0/0/0; `RestaurantInfo` 0/0/0 | SAFE | food multi-restaurant order model |
| `shared/src/main/java/com/eatfair/shared/model/order/OrderModification.kt` (OrderModification, AcceptPartialOrderRequest, CancelPartialOrderRequest) | 219 | `OrderModification` 0/0/0; `AcceptPartialOrderRequest` 0/0/0; `CancelPartialOrderRequest` 0/0/0 | SAFE | restaurant partial-order flow |
| `shared/src/main/java/com/eatfair/shared/model/order/OrderDto.kt` (OrderTracking, DeliveryPartner, PickUpLocation) | 70 | `OrderTracking` 0/0/0; `DeliveryPartner` 0/0/0; `PickUpLocation` 0/0/0 | SAFE | food order DTOs; only user is OrderNumberFormatter (also dead) |
| `shared/src/main/java/com/eatfair/shared/util/OrderNumberFormatter.kt` (OrderNumberFormatter, OrderNumberComponents, toOrderDisplay) | 181 | `OrderNumberFormatter` 3/3/3; `OrderNumberComponents` 0/0/0; `toOrderDisplay` 0/0/0 | SAFE | only user is OrderDto.kt (dead) 3 hits are all in OrderDto.kt (also deleted here). Delete together. |
| `shared/src/main/java/com/eatfair/shared/model/order/OrderEntity.kt` (OrderEntity) | 17 | `OrderEntity` 0/0/0 | SAFE | Room-style entity, never in a @Database |
| `shared/src/main/java/com/eatfair/shared/model/driver/Driver.kt` (DriverAddress, DriversLicense, InsuranceInfo) | 342 | `DriverAddress` 0/0/0; `DriversLicense` 0/0/0; `InsuranceInfo` 0/0/0 | SAFE | Firestore-era Driver model (fromMap); live code uses DriverStats in ApiModels.kt. Class "Driver" itself is a common word: verified with `grep -rnE "\bDriver\(\|model\.driver\.Driver\b"` -> 0 hits outside file except an unrelated nested class CustomerRideshareApiService.kt:1053 |
| `shared/src/main/java/com/eatfair/shared/model/driver/DriverSession.kt` (DriverSession, Promotion) | 113 | `DriverSession` 0/0/0; `Promotion` 1/1/1 | SAFE | Firestore-era; also contains food Promotion model `Promotion` 1 hit = a log string in CustomerFirebaseMessagingService.kt:99, not the class. |
| `shared/src/main/java/com/eatfair/shared/auth/GoogleSignInHelper.kt` (GoogleSignInHelper) | 145 | `GoogleSignInHelper` 0/0/0 | SAFE | sign-in uses Firebase/Credential flows elsewhere; never referenced (not auth routes - client helper). Verify Google sign-in build still passes |
| `app/src/main/java/com/eatfair/app/ui/auth/WelcomeScreen.kt` (WelcomeScreen, FeatureRow) | 230 | `WelcomeScreen` 21/2/1; `FeatureRow` 0/0/0 | SAFE | NavigationGraph.kt:198-201 comments say it was removed; androidTest/.../WelcomeScreenTest.kt (317 lines) must be deleted with it 21 hits = 19 in androidTest/WelcomeScreenTest.kt + 2 comments NavigationGraph.kt:198,201 ("WelcomeScreen removed"). No nav route uses it. Delete WelcomeScreenTest.kt (317 lines) with it. |
| `app/src/main/java/com/eatfair/app/ui/profile/LanguageModal.kt` (LanguageScreen, LanguageItem, getSampleLanguages) | 171 | `LanguageScreen` 0/0/0; `LanguageItem` 0/0/0; `getSampleLanguages` 0/0/0 | SAFE | no nav destination |
| `app/src/main/java/com/eatfair/app/ui/common/ConfettiAnimation.kt` (ConfettiAnimation) | 82 | `ConfettiAnimation` 0/0/0 | SAFE | plus shared/model/ConfettiParticle.kt |
| `shared/src/main/java/com/eatfair/shared/model/ConfettiParticle.kt` (ConfettiParticle) | 12 | `ConfettiParticle` 2/2/2 | SAFE | only used by dead ConfettiAnimation 2 hits are in ConfettiAnimation.kt (dead). |
| `app/src/main/java/com/eatfair/app/data/repo/PaymentRepo.kt` (PaymentRepo, getPaymentSheetKeys) | 57 | `PaymentRepo` 0/0/0; `getPaymentSheetKeys` 0/0/0 | SAFE | never injected |
| `shared/src/main/java/com/eatfair/shared/model/payment/PaymentSheetKeys.kt` (PaymentSheetKeys) | 8 | `PaymentSheetKeys` 3/3/3 | SAFE | only used by dead PaymentRepo 3 hits are in PaymentRepo.kt (dead). |
| `shared/src/main/java/com/eatfair/shared/model/restaurant/Restaurant.kt` (Restaurant) | 63 | `Restaurant` 25/24/10 | SAFE | data class never constructed; remaining word hits are comments/strings/enum names (EnumConst, LegalAcceptanceScreen) - verified with `grep -rnw Restaurant` code-only 25 hits: comments, string literals, enum constants in EnumConst.kt/LegalAcceptanceScreen.kt, an androidTest string, and OrderDto.kt import (dead). Zero code uses of the type. |
| `shared/src/main/java/com/eatfair/shared/model/restaurant/MenuItem.kt` (MenuItem) | 14 | `MenuItem` 1/1/1 | SAFE | food 1 hit = CartItem.kt (dead). |
| `shared/src/main/java/com/eatfair/shared/model/restaurant/CartItem.kt` (CartItem) | 7 | `CartItem` 3/0/0 | SAFE | food 3 hits are an androidTest that defines its own CartItem. |
| `shared/src/main/java/com/eatfair/shared/model/home/FeaturedDeal.kt` (FeaturedDeal, DealType) | 31 | `FeaturedDeal` 0/0/0; `DealType` 0/0/0 | SAFE | food |
| `shared/src/main/java/com/eatfair/shared/model/home/FoodItem.kt` (FoodItem) | 9 | `FoodItem` 0/0/0 | SAFE | food |
| `shared/src/main/java/com/eatfair/shared/model/home/CarouselItem.kt` (CarouselItem) | 12 | `CarouselItem` 7/0/0 | SAFE | food 7 hits are androidTest only. |
| `shared/src/main/java/com/eatfair/shared/model/home/Category.kt` (Category) | 14 | `Category` 18/2/0 | SAFE | `Category` hits in HelpSupportScreen.kt are a different local identifier (verify: no import of model.home.Category) 18 hits: androidTest + 2 unrelated local identifiers in HelpSupportScreen.kt (no import of model.home.Category). |
| `shared/src/main/java/com/eatfair/shared/model/search/SearchResultDto.kt` (SearchResultDto) | 12 | `SearchResultDto` 0/0/0 | SAFE | food search |
| `shared/src/main/java/com/eatfair/shared/model/rating/Rating.kt` (Tip) | 39 | `Tip` 14/14/9 | SAFE | Rating/Tip data classes never constructed (`grep -rnE "\bRating\(\|: Rating\b"` -> only Rating.kt) `Tip` is a common word (14 hits in strings/composable names); `grep -rnE "\bTip\(\|: Tip\b\|\bRating\(\|: Rating\b"` finds only the declarations. |
| `shared/src/main/java/com/eatfair/shared/model/LanguageDto.kt` (LanguageDto) | 8 | `LanguageDto` 15/15/15 | SAFE | 15 hits all in LanguageModal.kt (dead). |
| `app/src/main/java/com/eatfair/app/model/profile/ProfileMenuItemDto.kt` (ProfileMenuItemDto) | 12 | `ProfileMenuItemDto` 0/0/0 | SAFE |  |
| `app/src/main/java/com/eatfair/app/constants/Constants.kt` (AppConstants, PricingConfig) | 31 | `AppConstants` 0/0/0; `PricingConfig` 0/0/0 | SAFE | PricingConfig = old delivery fee table; contradicts AppConfig.Rideshare |
| **Subtotal** | **3266** | | | |

## A2. Partial deletions inside live files

| path (symbol) | lines | evidence | verdict | notes |
|---|---:|---|---|---|
| shared/.../config/AppConfig.kt `object FoodDelivery` + `FoodOrderFees` | 45 | `grep -rnw 'FoodDelivery\|FoodOrderFees' app driver shared` = 0 outside AppConfig.kt | SAFE | food $1 fee table (lines 116-~160) |
| shared/.../config/AppConfig.kt `object DriverPay` | 39 | `grep -rnw DriverPay app driver shared --include=*.kt` = 0 outside AppConfig.kt (the 6 loose hits were `DriverPayout*` substrings) | SAFE | lines 562-600; per-delivery pay, contradicts DO_NOT_USE fee rules |
| shared/.../config/AppConfig.kt `object TieredPricing` | 26 | `grep -rnw TieredPricing` = 0 outside AppConfig.kt | SAFE | lines 606-631 ($35/$70 tiers; DO_NOT_USE section 2 says these drifted) |
| shared/.../config/AppConfig.kt `object Tax` | 20 | `grep -rnE 'Tax\.(getTaxRate\|STATE_TAX_RATES\|DEFAULT_TAX_RATE)' app driver shared` = 0 | SAFE | lines 634-653 |
| shared/.../config/AppConfig.kt `object Microservices` | 18 | `grep -rnw Microservices` = 0 outside AppConfig.kt (one internal call at AppConfig.kt:70 `Microservices.initialize`) | SAFE | also delete the call at line 70. restaurantServiceUrl/menuServiceUrl live here |
| app/.../ui/address/SavedAddressesScreen.kt `ImportBlinkitCard` | 52 | `grep -rnw ImportBlinkitCard` = 1 (declaration only) | SAFE | Blinkit = Indian grocery-delivery import |
| shared/.../data/remote/DollorApiService.kt 10 Retrofit methods: addPaymentCard, deletePaymentCard, getDriverProfile, updateDriverProfile, getDriverDocuments, getDriverStatus, updateDriverStatus, getDriverRides, getTermsOfService, getPrivacyPolicy | 56 | each name: `grep -rnw NAME app driver shared --include=*.kt` = 1 (declaration). Lines 248-269, 349-390, 580-585, 697-702 | SAFE | backend routes behind them stay (other clients). `getDriverRides` hits `erp/driver/{id}/rides` (legacy) |
| shared/.../data/remote/DollorApiService.kt `customerAppleAuth`, `customerPasswordReset`, `refreshDriverToken` | 12 | names occur once (declaration) but auth | NEEDS-CHECK | auth: confirm sign-in-with-Apple / reset / refresh paths are served elsewhere (TokenRefreshInterceptor.kt:21-25 refreshes CUSTOMER tokens only via POST /api/auth/customer/refresh; a driver 401 just clears auth, so `refreshDriverToken` is truly unused) |
| shared/.../model/driver/DriverEarnings.kt `DriverDashboardResponse`(9-44) `DriverTaxInfo`(79-96) `DriverPlatformFees`(101-106) `DriverPaymentMethods`(111-129) | 79 | `grep -rnw 'DriverTaxInfo\|DriverPlatformFees\|DriverPaymentMethods' ...` = 0; `DriverDashboardResponse` live copy is ApiModels.kt:501, this one is never imported | NEEDS-CHECK | Gson response classes; fields are not read by name in code, but delete only after confirming no JSON reflection |
| shared/.../constants/EnumConst.kt `enum class OrderStatus` (47-232, 186 lines) + helper funs (requiresRestaurantAction, canCancel, shouldRefund...) | 186 | only importers are OrderEntity.kt and OrderDto.kt (both dead above); `DollorTheme.OrderStatus` is a different object | NEEDS-CHECK | becomes SAFE after A1 batch; 13 RESTAURANT_* constants |
| shared/.../model/ApiModels.kt `CustomerLoginRequest`(10-19) `ErrorResponse` `ChatMessageRequest` `ChatMessage` `UpdateCustomerProfileRequest`(669-692) | -61 | each = 1 occurrence (declaration) in src/main | NEEDS-CHECK | Gson DTOs; low value |
| shared/.../model/rideshare/RideshareModels.kt `SubmitBidRequest`, `CounterOfferActionRequest`, `CreateRideRequest`, `CustomerCounterOfferRequest` | -41 | each = 1 occurrence outside own declaration in src/main | NEEDS-CHECK | rideshare vocabulary: may be intended for the shared driver/customer clients |
| app/.../ui/theme/Color.kt `OrderStatusColors`(48-70) `PaymentStatusColors`(73-78); DollorTheme.kt `PaymentStatus`(117-131) `getColors/getGradient/getBadgeColor` | -66 | each = 1 occurrence | NEEDS-CHECK | DO_NOT_USE lists ~118 colors already removed; these are the leftovers |
| shared/.../ui/LegalAcceptanceScreen.kt Restaurant branch (userType=="Restaurant", lines ~257-310) | -56 | `grep -rn 'userType *= *"Restaurant"\|LegalAcceptanceScreen(' app driver` = no caller passes Restaurant | NEEDS-CHECK | shared screen, edit carefully |
| shared/.../data/local/SecureStorage.kt vendor members (`vendorToken`, `vendorEmail`, `saveVendorAuth`, `clearVendorAuth`) + TokenRefreshInterceptor.kt:143 | -51 | `vendorEmail`, `saveVendorAuth` = 1 occurrence each; `vendorToken` 2 (SecureStorage + interceptor) | NEEDS-CHECK | touches token storage (auth): leave for last |
| app/.../ui/auth/AuthViewModel.kt `loginWithDemo`(179-204), `resetEmailVerificationState` | -31 | 1 occurrence each | NEEDS-CHECK | demo login: confirm App Review does not need it |
| app/.../ui/rideshare/RideRequestViewModel.kt `dismissSuccess`, `totalWithPlatformFee`, `selectedTipAmount`, `isGettingLocation`, `showSuccess`, `authError` | -26 | 1 occurrence each | NEEDS-CHECK | small; StateFlows |

## A3. Resources (verdict SAFE unless noted)

| path | lines | evidence | verdict | notes |
|---|---:|---|---|---|
| `app/src/main/res/drawable/ic_delivery_bike.xml, ic_fork_knife.xml, ic_add.xml, ic_remove.xml, ic_dot_rounded.xml` | 30 | `grep -rnw '<name>' app driver shared --include=*.kt,*.xml,*.kts` = 0 for each (R.drawable.x, @drawable/x, bare name) | SAFE | food icons + unused |
| `app/src/main/res/drawable/ic_launcher_foreground.xml, ic_launcher_background.xml; driver/.../drawable/ic_launcher_foreground.xml, ic_launcher_background.xml` | 30 | 0 refs (manifests use @mipmap/ic_launcher; driver mipmap-anydpi-v26 uses @mipmap/ic_launcher_fg + @color/ic_launcher_bg) | SAFE | legacy launcher vectors |
| `app/src/main/res/drawable/ic_background.png` | 0 | 0 refs; 166,145 bytes | SAFE | largest resource win (bytes, not lines) |
| `app/src/main/res/values/colors.xml (23 of 24 colors)` | 23 | `@color/` appears only in manifests (`@color/primary`) and driver mipmaps; none of the 23 names is referenced. KEEP `primary` | SAFE | values are the old green palette |
| `driver/src/main/res/values/colors.xml (all but `primary`, `ic_launcher_bg` in ic_launcher_bg.xml)` | 12 | 0 refs | SAFE |  |
| `app/src/main/res/values/strings.xml `app_display_name`, `app_tagline`, `company_name`, `app_description`` | 4 | 0 refs (`app_name` is used by both manifests: KEEP) | SAFE |  |
| `driver/src/main/res/values/strings.xml (19 of 20: nav_*, login_*, sign_in, log_out, delete_account, ...)` | 19 | 0 refs (only `app_name` used) | SAFE |  |
| `app/src/main/res/values/font_certs.xml `com_google_android_gms_fonts_certs_dev\|prod`` | 10 | referenced only by the sibling `<array>` in the same file; no downloadable-font resource uses `@array/com_google_android_gms_fonts_certs` | NEEDS-CHECK | verify no downloadable fonts in themes |
| `app/src/main/res/xml/backup_rules.xml` | 12 | 0 refs; manifest has `fullBackupContent="false"` and uses data_extraction_rules.xml | NEEDS-CHECK | Android 11- backup behaviour |

## A4. Stale tests (verdict NEEDS-CHECK; none imports `com.eatfair.*`)

Verified: none of these files has a single `import com.eatfair`; each defines its own fake composables/data classes (e.g. `CartScreenComponentsTest.kt:529 data class CartItem`). They test food UIs that do not exist in production code.

| path | lines | verdict | notes |
|---|---:|---|---|
| `app/src/androidTest/java/com/eatfair/app/ui/cart/CartScreenComponentsTest.kt` | 537 | SAFE | tests a test-local CartItem |
| `app/src/androidTest/java/com/eatfair/app/ui/home/HomeScreenComponentsTest.kt` | 551 | SAFE | food home |
| `app/src/androidTest/java/com/eatfair/app/ui/order/OrderTrackingScreenTest.kt` | 444 | SAFE | 'Restaurant is preparing' strings |
| `app/src/androidTest/java/com/eatfair/app/ui/profile/ProfileScreenComponentsTest.kt` | 557 | NEEDS-CHECK | profile is live; check content |
| `app/src/androidTest/java/com/eatfair/app/ui/search/SearchScreenComponentsTest.kt` | 554 | SAFE | food search |
| `app/src/androidTest/java/com/eatfair/app/ui/auth/WelcomeScreenTest.kt` | 317 | SAFE | delete with WelcomeScreen.kt |
| `app/src/test/java/com/eatfair/app/staging/OrderCreationFieldMappingTest.kt` | 122 | NEEDS-CHECK | hits staging API with order payloads |
| `app/src/test/java/com/eatfair/app/staging/CustomerAppStagingApiTest.kt` | 224 | NEEDS-CHECK | hits staging API |

## A5. Looked dead, is NOT dead (KEEP)

- `app/.../di/AppModule.kt`, `RepoModule.kt`, `shared/.../di/SharedModule.kt`: Hilt `@Module` (no name references by design). `RepoModule` is an empty module (17 lines, all commented) -> NEEDS-CHECK, harmless to delete.
- `AppDatabase.kt`, `AddressDao.kt`, `AddressRepo.kt`, `AddressDto.kt`: used by `LocationViewModel` -> NavigationGraph (address book is live).
- Manifest components: DollorApp, DriverApp, CustomerFirebaseMessagingService, DriverFirebaseMessagingService, all Activities.
- `TokenRefreshInterceptor`, `CustomerRideshareApiService` methods with exactly one caller (`getMyRideRequests`, `getBidsForRide`, `cancelRideRequest`, `tipRide`, ...): live.
- Previews (`*Preview`, ~12): unreferenced by design; only delete if the team drops previews.

---

# iOS

Paths relative to `/Users/jeet/doordash-p2p/apps/ios/`. `SH/` = `eatfair-ios-shared/Sources/EatFairShared/`.

## I1. Whole-file deletions with zero references (verdict SAFE)

| path | lines | evidence (`grep -rnw -I SYMBOL customer delivery eatfair-ios-shared/Sources (swift/plist/pbxproj/json/storyboard) \| grep -v <own file>`: hit count) | verdict | notes |
|---|---:|---|---|---|
| `SH/Utilities/Calculators.swift` | 200 | `DistanceCalculator`: 0; `PromotionCalculator`: 0; `TaxCalculator`: 0 | SAFE | tax/tip/promotion/distance calculators (food checkout era) |
| `customer/eatfaircustomer/AppFeatures.swift` | 15 | `AppFeatures`: 0 | SAFE | feature flags nobody reads |
| `customer/eatfaircustomer/ContentView.swift` | 93 | `ContentView`: 0; `contentLogger`: 0; `itemFormatter`: 0 | SAFE | Xcode template leftover (CoreData Item list). Delete with Persistence.swift and `eatfaircustomer.xcdatamodeld` (template Item entity, 632 B) |
| `customer/eatfaircustomer/Services/VoiceSearchService.swift` | 133 | `VoiceSearchService`: 0 | SAFE | food voice search. Check Info.plist NSSpeechRecognitionUsageDescription afterwards (permission string would become unused) |
| `SH/Utilities/DateTimeFormatter.swift` | 486 | `DateTimeFormatter`: 0 | SAFE |  |
| `SH/Services/EnterpriseNetworkLayer.swift` | 830 | `CircuitBreaker`: 0; `CircuitState`: 0; `EnterpriseLogger`: 0 | SAFE | circuit breaker / health monitor; never wired |
| `SH/ErrorHandler.swift` | 325 | `ActionStyle`: 0; `AlertAction`: 0; `EatFairError`: 0 | SAFE |  |
| `SH/Views/GooglePlacesSearchView.swift` | 190 | `GooglePlacesSearchView`: 0; `GooglePlacesSearchViewModel`: 0; `GooglePlacesSearchView_Previews`: 0 | SAFE | customer uses own AddressSearchView; also delete GoogleMapsService.swift (I2) |
| `SH/Views/OrderConfirmationViews.swift` | 665 | `ConfirmationStep`: 0; `CustomerDeliveryConfirmationView`: 0; `DriverPaymentConfirmationView`: 0 | SAFE | restaurant/driver payment confirmation views |
| `customer/eatfaircustomer/Persistence.swift` | 48 | `PersistenceController`: 1 (ContentView.swift:1); `coreDataLogger`: 0 | SAFE | 1 hit = ContentView.swift (dead). `NSPersistentContainer(name: "eatfaircustomer")` is its only user; delivery app has no CoreData code at all |
| `SH/Views/LegalAcceptanceView.swift` | 371 | `LegalAcceptanceView`: 0; `LegalDocumentType`: 0; `OnboardingLegalAcceptanceView`: 0 | SAFE | only user of LegalService (I2) |
| `SH/Views/V3CheckoutView.swift` | 739 | `PaymentMethod`: 1 (P2PAPIService.swift:1); `TipOptionButton`: 0; `TransparencyRow`: 0 | SAFE | 1 hit for `PaymentMethod` = a comment in P2PAPIService. Food checkout; with DollorV3Service.swift (I2) |
| **Subtotal** | **4095** | | | |

## I2. Dead files after cascade + dead units inside live files, per file

`safe` / `check` = lines in deletion units (union of line ranges). Unit = function or type with zero code references (cascade: a function called only by other dead functions is dead). `raw hits` = symbols that still show a whole-word hit outside their own file in raw grep; every one is accounted for in Notes (hits are in other dead units, in comments, or are test-local names).

| path | lines (safe/check) | evidence | verdict | notes |
|---|---:|---|---|---|
| `SH/Services/P2PAPIService.swift` | 8416 (6524/1892) | 243 units, all 0 code refs outside dead units; raw-hit symbols: 19 | SAFE (safe part) / NEEDS-CHECK | 15,808-line file; 243 dead units. Breakdown in I3. 132 of 134 endpoint strings found in dead iOS code hit backend routes that no longer exist. |
| `SH/Services/TripBoardService.swift` | 1479 (1380/99) | 55 units, all 0 code refs outside dead units; raw-hit symbols: 1 | SAFE (safe part) / NEEDS-CHECK | trip-board marketplace: `/api/trip-board/*` routes do not exist on backend (`match.json`: missing). 55 units; only `confirmPayment` shows raw hits and those are same-named methods in other classes, not calls. |
| `SH/Services/LegalService.swift` | 626 (626/0) | 28 units, all 0 code refs outside dead units; raw-hit symbols: 16 | SAFE | whole file; only users are LegalAcceptanceView + OrderConfirmationViews (both dead). Raw hits all in those two files. |
| `SH/Services/GoogleMapsService.swift` | 624 (624/0) | 32 units, all 0 code refs outside dead units; raw-hit symbols: 5 | SAFE | whole file; raw hits only in GooglePlacesSearchView.swift (dead). `GoogleMapsConfig.swift`/`GoogleMapView.swift` stay. |
| `SH/Models/Order.swift` | 601 (601/0) | 10 units, all 0 code refs outside dead units; raw-hit symbols: 6 | SAFE | delete everything from line 198 down (OrderModification, Order, DeliveryAddress, RestaurantInfo, OrderItem, MultiRestaurantOrder). KEEP `OrderStatus` (19-191) + `typealias DeliveryOrderStatus` (:195) for now: live code `EarningsViewModel.swift:284,342` still uses `DeliveryOrderStatus.delivered` in food-era Firestore queries (`db.collection("orders")`), see EarningsViewModel row. Raw `Order` hits are the English word / other dead units / test-local mocks. |
| `SH/Services/AIEmployeeService.swift` | 468 (468/0) | 20 units, all 0 code refs outside dead units; raw-hit symbols: 0 | SAFE | AI-employee product (vibingticket era); 0 raw hits |
| `customer/eatfaircustomer/Services/ACHPaymentService.swift` | 460 (0/460) | 6 units, all 0 code refs outside dead units; raw-hit symbols: 0 | NEEDS-CHECK | 0 raw hits, but it is a rider payment method -> confirm ACH is not planned before deleting |
| `SH/Services/CallService.swift` | 431 (431/0) | 9 units, all 0 code refs outside dead units; raw-hit symbols: 1 | SAFE | raw hit = a comment/AppConfig string `CallService` |
| `SH/Services/NegotiationService.swift` | 370 (370/0) | 9 units, all 0 code refs outside dead units; raw-hit symbols: 1 | SAFE | raw hit = AppConfig.swift string. Android twin is also dead (A1). |
| `SH/Services/DollorV3Service.swift` | 368 (368/0) | 12 units, all 0 code refs outside dead units; raw-hit symbols: 5 | SAFE | raw hits only in V3CheckoutView.swift (dead). Keep the 6-line `extension Double.rounded(toPlaces:)` only if used: `grep -rn "toPlaces"` = 0 outside. |
| `delivery/eatffairdelivery/ViewModels/DriverProfileViewModel.swift` | 276 (0/276) | 7 units, all 0 code refs outside dead units; raw-hit symbols: 0 | NEEDS-CHECK | parseDriverData, buildDriverObject, createNewProfile, uploadDocument, checkDocumentExpirations: driver onboarding remnants. Driver profile is live: review |
| `SH/Models/Restaurant.swift` | 244 (244/0) | 6 units, all 0 code refs outside dead units; raw-hit symbols: 0 | SAFE | Restaurant/MenuItem/BusinessLicense... see note |
| `delivery/eatffairdelivery/ViewModels/EarningsViewModel.swift` | 198 (0/198) | 7 units, all 0 code refs outside dead units; raw-hit symbols: 3 | NEEDS-CHECK | startSession/endSession/loadMockData/listenForTips dead. ALSO live-but-food: `fetchPeriodEarnings` (:280) queries Firestore collection "orders" with `DeliveryOrderStatus.delivered` (food delivery counters, DO_NOT_USE section 4); removing that is a behaviour change -> NEEDS-CHECK |
| `customer/eatfaircustomer/Services/PaymentService.swift` | 193 (193/0) | 5 units, all 0 code refs outside dead units; raw-hit symbols: 2 | SAFE | Stripe PaymentSheet helper; raw hit `PaymentService` = 3 comments in SecureStorage.swift:83,89,132 |
| `customer/eatfaircustomer/Views/PlaceholderViews.swift` | 173 (173/0) | 2 units, all 0 code refs outside dead units; raw-hit symbols: 0 | SAFE | LegacyHelpSupportView + FAQDetailView (the live HelpSupportView is separate) |
| `SH/Models/EnhancedModels.swift` | 149 (149/0) | 5 units, all 0 code refs outside dead units; raw-hit symbols: 5 | SAFE | Rating, Promotion, TaxRate, DriverSession, LocationCoordinate, Tip: raw hits are the English words / dead units |
| `delivery/eatffairdelivery/Views/DriverProfileView.swift` | 141 (0/141) | 2 units, all 0 code refs outside dead units; raw-hit symbols: 0 | NEEDS-CHECK | DocumentStatusRowItem, VehiclePhotoUploadView |
| `delivery/eatffairdelivery/Services/ChatManager.swift` | 120 (0/120) | 3 units, all 0 code refs outside dead units; raw-hit symbols: 0 | NEEDS-CHECK | sendVoiceMessage, createConversation (restaurant conversation), endConversation (DO_NOT_USE section 4) |
| `SH/AppConfig.swift` | 97 (0/97) | 18 units, all 0 code refs outside dead units; raw-hit symbols: 1 | NEEDS-CHECK | food/rideshare fee helpers + OrderStatusConstants + APIEndpoints. DO_NOT_USE says tier text must come from `rideshareTierRows`; these are superseded helpers |
| `SH/Models/AIEmployee.swift` | 70 (70/0) | 3 units, all 0 code refs outside dead units; raw-hit symbols: 0 | SAFE | 3 request/response types |
| `SH/NotificationManager.swift` | 61 (0/61) | 7 units, all 0 code refs outside dead units; raw-hit symbols: 0 | NEEDS-CHECK | 7 helper methods never called |
| `customer/eatfaircustomer/ViewModels/RideRequestViewModel.swift` | 56 (0/56) | 3 units, all 0 code refs outside dead units; raw-hit symbols: 2 | NEEDS-CHECK | declineDriverOffer, createPaymentIntent (calls dead P2P createRidePaymentIntent), updateBid |
| `SH/Views/DeliveryProofCameraView.swift` | 45 (45/0) | 1 units, all 0 code refs outside dead units; raw-hit symbols: 1 | SAFE | raw hit = a doc comment in DocumentCaptureView.swift:5 |
| `delivery/eatffairdelivery/Services/LocationManager.swift` | 34 (0/34) | 5 units, all 0 code refs outside dead units; raw-hit symbols: 2 | NEEDS-CHECK |  |
| `delivery/eatffairdelivery/ViewModels/RideBiddingViewModel.swift` | 23 (0/23) | 4 units, all 0 code refs outside dead units; raw-hit symbols: 2 | NEEDS-CHECK |  |
| `delivery/eatffairdelivery/DriverLoginView.swift` | 18 (0/18) | 1 units, all 0 code refs outside dead units; raw-hit symbols: 0 | NEEDS-CHECK |  |
| `SH/Services/WebSocketManager.swift` | 14 (0/14) | 1 units, all 0 code refs outside dead units; raw-hit symbols: 0 | NEEDS-CHECK |  |
| `delivery/eatffairdelivery/Views/PayoutDashboardView.swift` | 10 (0/10) | 1 units, all 0 code refs outside dead units; raw-hit symbols: 0 | NEEDS-CHECK |  |
| `delivery/eatffairdelivery/Views/Rideshare/RideshareDashboardView.swift` | 10 (0/10) | 1 units, all 0 code refs outside dead units; raw-hit symbols: 0 | NEEDS-CHECK |  |
| `SH/Security/NetworkSecurity.swift` | 8 (0/8) | 1 units, all 0 code refs outside dead units; raw-hit symbols: 0 | NEEDS-CHECK |  |
| `delivery/eatffairdelivery/ViewModels/OnlineStatusManager.swift` | 8 (0/8) | 2 units, all 0 code refs outside dead units; raw-hit symbols: 2 | NEEDS-CHECK |  |
| `delivery/eatffairdelivery/Services/VoiceAssistantManager.swift` | 7 (0/7) | 2 units, all 0 code refs outside dead units; raw-hit symbols: 0 | NEEDS-CHECK |  |
| `customer/eatfaircustomer/ViewModels/AddressViewModel.swift` | 5 (0/5) | 1 units, all 0 code refs outside dead units; raw-hit symbols: 0 | NEEDS-CHECK |  |
| `SH/Config/GoogleMapsConfig.swift` | 4 (0/4) | 1 units, all 0 code refs outside dead units; raw-hit symbols: 0 | NEEDS-CHECK |  |
| `delivery/eatffairdelivery/Services/AuthManager.swift` | 3 (0/3) | 1 units, all 0 code refs outside dead units; raw-hit symbols: 0 | NEEDS-CHECK |  |

Not counted (design-system/protocol conformances flagged by the scanner and excluded): `SH/LxDesignSystem.swift` `makeBody`, `lxCompact` (documented replacement API in DO_NOT_USE: KEEP).

## I3. P2PAPIService.swift breakdown (largest single unit: ~8,416 dead lines of 15,808)

Group line counts overlap slightly (nested types), sum is +212 over the 8,416 union. Evidence for every function below: it is `public` in an SPM package but `grep -rnw -I <name> customer delivery eatfair-ios-shared/Sources` returns only its own declaration (or other dead units / test-local names; the only test hits are test-method names such as `func getActivePromotions()` in `CustomerAppStagingAPITests.swift:300` that do NOT call the service).

| group | lines | members (name@startLine(lines)) | verdict |
|---|---:|---|---|
| vendor/restaurant account + auth + docs + stripe-for-vendor | 1423 | vendorLogin@1191, vendorRegister@1280, vendorPublicRegister@1351, vendorGoogleAuth@1416, vendorAppleAuth@1513, requestVendorPasswordReset@2109, confirmVendorPasswordReset@2163, fetchRestaurants@72, fetchRestaurantDetail@161, fetchVendorProfile@210, fetchVendorOrders@3242, restaurantAcceptOrder@3399, restaurantDeclineOrder@3439, restaurantAcceptDelivery@3481, restaurantDeclineDelivery@3526, vendorStartDelivery@3572, restaurantCompleteDelivery@3603, getVendorStripeStatus@3718, createVendorStripeAccount@3747, getVendorStripeOnboardingLink@3786, deleteVendorAccount@8259, patchVendorSettings@9442, get/upload/deleteVendorDocument@9536-9662, saveVendorFCMToken@12779, submitRestaurantRating@13068 | SAFE |
| menu / combo / stock images / verification | 667 | fetchMenuItems@253, createMenuItem@299, createComboItem@362, updateMenuItem@424, deleteMenuItem@479, getMenuCategories@527, toggleItemAvailability@575, assignStockImages@1067, getVerificationStatus@1109, approveAllPrices@1149, toRestaurant@10423, toMenuItem@10447, buildDietaryTags@10464, convertCustomizations@10473 + P2PMenu*/P2PStockImage*/P2PDetailMenuItem types | SAFE |
| promotions / featured deals / AI insights / analytics | 769 | getActivePromotions@594, getFeaturedDeals@635, createPromotion@697, updatePromotion@799, deletePromotion@844, getPromotionSuggestions@877, getPromotionAnalytics@918, getAIInsights@965, quickCreatePromotion@1025, getRealtimeAnalytics@12991 + 17 P2P* DTO types | SAFE |
| customer food orders / cart / favorites / tracking / refunds | 1369 | fetchCustomerFavorites@2679, addFavorite@2721, removeFavorite@2765, checkFavorite@2808, fetchCustomerOrders@2853, trackOrder@2919, fetchActiveOrders@2960, confirmOrderPayment@3130, validatePromoCode@3174, getFullOrderTracking@12913, getCart@14018, addToCart@14072, updateCartItem@14139, removeCartItem@14204, clearCart@14255, processRefund@14373, toOrder@11884(123), toOrder@12316(89) + 20 DTO types | SAFE |
| KOT printing / delivery-decision / vendor orders | 817 | startDeliveryDecision@15067, makeDeliveryDecision@15110, getDeliveryDecisionStatus@15157, getPendingDeliveryOrders@15196, getKOTConfig@15242, updateKOTConfig@15293, testKOTConnection@15354, printKOT@15401, P2PVendorOrder@11783(225) + DTOs | SAFE |
| driver food-delivery flow | 663 | fetchAvailableDeliveryOrders@4773, acceptDeliveryOrder@4849(92), markOrderPickedUp@4943, markOrderDelivered@5016, fetchMyDeliveries@5452(111), completeDelivery@5565, uploadDeliveryPhoto@5609, cancelDeliveryAssignment@5669, markArrivedAtDelivery@3816 + P2PDeliveryOrder(89) | SAFE |
| other food/legacy: createOrder, updateOrderStatus, updateVendorStatus, P2PCustomerOrder(328), P2PWebSocketManager(158), AnyCodable, vendor profile types | 1250 | createOrder@3009(116), updateOrderStatus@3315, updateVendorStatus@3358, P2PCustomerOrder@12078(328), P2PWebSocketManager@12486(158), AnyCodable@12665 (only used by dead DTOs), P2PVendorProfile@9385 ... | SAFE |
| rideshare/driver/payment-named (unreferenced by iOS today) | 1892 | fetchAvailableRides@5742 (DO_NOT_USE section 3 already says do not call), fetchDriverActiveRides@5802, acceptRide@5841, ridePickedUp@5890, respondToCounterOffer@6739, cancelRideRequest@6901, getSurgeStatus@7348, getCustomerRideRequests@7433, updateBid@7563, submitFareNegotiation@7614, acceptFareNegotiation@7666, createRidePaymentIntent@7714, confirmRidePayment@7765, emailRideReceipt@13305, createRideDispute@13373, fetchMyDisputes@13420, fetchDisputeStatus@13455, sendChatMessage@13620, fetchChatMessages@13678, getDriverEarnings@13732, getPayoutHistory@13968, assignDriver@14311, getDriverLocation@12951, updateDriverOnlineStatus@12851, driverLogout@4077, createStripeConnectAccount@13791, getStripeAccountStatus@13881, fetchDefaultAddress@2354 + ride/driver/earnings DTO types | NEEDS-CHECK |

NEEDS-CHECK reason: these are rideshare-flavoured. No iOS screen calls them today, but the backend routes (`/api/rides/...`) are live for Android/web and the functions may be the intended implementation of a missing iOS feature (dispute, receipt email, surge, chat). Decide per feature: delete (git keeps history) or wire up.

## I4. Project / hygiene items

| path | lines | evidence | verdict | notes |
|---|---:|---|---|---|
| `delivery/Info.plist` (stray, 30 lines) | 30 | delivery pbxproj uses `INFOPLIST_FILE = eatffairdelivery/Info.plist` (pbxproj:549,592); `grep -rn 'delivery/Info.plist' fastlane Config *.plist` = 0 | SAFE | duplicate of the 79-line real one |
| `delivery/Assets.xcassets/` (stray; target uses `delivery/eatffairdelivery/Assets.xcassets`) | 3 | synchronized root group is `eatffairdelivery/`; stray folder only has Contents.json, AccentColor, AppIcon with no PNG | SAFE | the real set has the 19 KB AppIcon.png |
| `delivery/eatffairdelivery.xcdatamodeld` and `delivery/eatffairdelivery/eatffairdelivery.xcdatamodeld` | 2 | `grep -rn 'NSPersistent\|import CoreData' delivery` = 0 (delivery app has no CoreData); both are 632 B Xcode template Item entity | SAFE | two copies |
| `customer/eatfaircustomer/eatfaircustomer.xcdatamodeld` | 2 | only consumer is Persistence.swift (dead) | SAFE | delete with Persistence.swift |

## I5. Stale tests (verdict NEEDS-CHECK)

| path | lines | evidence | verdict | notes |
|---|---:|---|---|---|
| `customer/eatfaircustomerTests/eatfaircustomerTests.swift` | 352 | no `@testable import`; defines its own cart/menu mocks (`createMenuItem`, `cart.addToCart`, `clearCart` at :305) | SAFE | food cart tests of test-local code; `delivery/eatffairdeliveryTests/eatffairdeliveryTests.swift` (352) is a near-identical copy (diff = header comments) |
| `delivery/eatffairdeliveryTests/eatffairdeliveryTests.swift` | 352 | same as above | SAFE |  |
| `customer/eatfaircustomerUITests/Flows/FoodDeliveryFlowTests.swift` | 355 | UI test for the food flow; app has no such screens | SAFE |  |
| `customer/eatfaircustomerTests/CustomerAppStagingAPITests.swift` | 1071 | 54 tests: ride + food endpoints on staging (`getActivePromotions`, `addFavorite`, `trackOrder`, `addToCart`...) | NEEDS-CHECK | keep the ride ones; delete the food ones |
| `customer/run_staging_tests.swift` | 626 | stand-alone script, not in any target | NEEDS-CHECK |  |

## I6. KEEP (looked dead, is not)

- `LxDesignSystem.swift` (`makeBody` x5, `lxCompact`): ButtonStyle requirement / documented replacement API.
- Delegate/protocol methods the scanner cannot see callers of: `presentationAnchor`, `completerDidUpdateResults`, `paymentCardTextFieldDidChange`, `placeSubviews`, `imagePickerController*`.
- `WebSocketManager.swift`, `LocationManager`, `AuthManager`, `OnlineStatusManager`: live; only single helper methods inside are dead (listed NEEDS-CHECK above).
- `*_Previews` structs (5): by design.

---

# BACKEND

Paths relative to `/private/tmp/dollor-single-session-wt/apps/web/p2p-platform/backend/`.

## B1. Routes

Result of the route-vs-client matching: 466 routes; 144 (non-docs) have zero client, web, admin-bundle or test references. Food/vendor/restaurant/menu/cart routes: **none left** except the 3 below. Rules applied: auth, payments/webhooks, driver/customer lifecycle, admin, insurance, checkr, legal, health are never SAFE.

| route(s) | lines | evidence | verdict | notes |
|---|---:|---|---|---|
| `POST /erp/orders/{id}/start-delivery-decision`, `POST /erp/orders/{id}/restaurant-delivery-decision`, `GET /erp/orders/{id}/delivery-decision-status` (main_new.py:13697-13699, `app.add_api_route(..., _format_address, ...)`) | 3 | `grep -rIl 'delivery-decision' apps/web android ios` -> only main_new.py + iOS P2PAPIService.swift (dead iOS functions startDeliveryDecision/getDeliveryDecisionStatus, I3) + planning docs. The handler is `_format_address` (a dict-formatter helper, main_new.py:10505): these three routes are registered to the WRONG function and would 422/500 if hit | SAFE | delete the 3 lines. Keep `_format_address` itself (6 other users) |
| Dead helper handlers in main_new.py (non-route): `get_current_vendor`@1442(27), `get_current_vendor_user`@2509(12), `sanitize_text`@665(5), `_legacy_placeholder`@10241(3), `create_in_app_notification`@11639(16), `AIInsightsResponse`@13607(36), `TaxCalculationRequest`@13814(5) | 104 | AST scan: identifier occurs once in the whole backend incl. tests (`grep -rnw NAME --include=*.py . \| wc -l` = 1) | SAFE | vendor-auth helpers, AI insights, tax request DTO |
| `get_current_customer`@1380(27), `get_current_driver`@1409(31), `DriverLoginResponse`@2539, `CustomerLoginResponse`@3208, `CustomerLoginRequest`@3221, `SendVerificationRequest`@3700 | ~95 | each occurs once in whole backend | NEEDS-CHECK | auth helpers: product owner sign-off |
| `/api/demo/*` x9 (setup 273 lines, reset-ride-state, recreate-customer, force-reset-passwords, debug-driver-login, debug-customer-login, fix-driver-login, update-driver-profile, setup-support-customer, clear-driver-bids) + `/api/debug/order/{id}` (main_new.py:11734-12590) | 885 | zero refs in ios/android/web/admin/tests (`grep -rIl 'api/demo/' apps/web android ios` = main_new.py + backend/update_demo_driver.py only) | NEEDS-CHECK | insecure demo/debug surface; App Store review demo accounts may depend on `/api/demo/setup`. Not auth-gated? verify before deleting |
| `/api/erp/rides/estimate-fare`, `/api/erp/rides/fare-estimate`, `/api/erp/rides/{id}/full-tracking`, `/api/erp/rides/{id}/start` (+unprefixed), `/api/rides/{id}/complete-and-pay`, `/api/rides/{id}/negotiate` (iOS alias), `/api/erp/payments/intent`, `/api/chat/ride/{id}` + `/chat/ride/{id}` | 474 | zero refs in clients/web/admin/tests; only `rideshare_e2e_test.py` (dead script) mentions estimate-fare. DO_NOT_USE section 3 already lists the `/erp` ride aliases as legacy | NEEDS-CHECK | payment/lifecycle aliases: verify prod app versions in the wild do not call them (Android/iOS in stores) |
| order_flow.py: `/api/erp/rides/{id}/completed`, `/receipt`, `/api/erp/payouts/pending`, `/payouts/{id}/process`, `/journal-entries`, `/api/erp/drivers`, `/drivers/create`, `/drivers/login`, `/drivers/register` | 493 | zero refs outside test_ios_api_contracts.py for payouts/journal-entries | NEEDS-CHECK | ERP-era accounting and a duplicate driver login/register (auth) |
| matchmaking_routes.py (12 routes `/api/matchmaking/*`) + state_config.py (only importer is matchmaking_routes) | 1306 | `grep -rIl 'api/matchmaking' apps/web android ios` = backend only; tests: only `tests/unit/test_payment_safety.py` imports it | NEEDS-CHECK | superseded by bid_routes.py; compliance/legal configuration inside state_config.py -> owner decision |
| `/api/tickets*` x8, `/api/dashboard/consolidated`, `/api/system-dashboard/coupa`, `/api/invoices/{id}/status`, `/api/erp/analytics/dashboard/realtime`, `/api/erp/health/services`, `/api/tax/rates`, `/api/websocket/stats` | 615 | zero refs (web frontend has Coupa/vendor-management screens but calls other paths) | NEEDS-CHECK | Coupa/ERP-era admin; admin category -> not auto-dead |
| realtime_events.py 7 routes (`/api/realtime/publish\|notify\|status\|events\|communications/*`) | 289 | `/api/realtime/ws` is built by prefix in frontend `api.ts:1057` and admin bundle; module is imported by main_new + change_management; tests/unit/test_realtime_events.py (1,462 lines) | KEEP | live infrastructure |
| accounting_module (4), tnc_compliance (8), checkr (1), stripe webhooks (2), investor `/views` (1), project_tracker (2), change_management (9), bid_routes (4: bid-label, pricing/tiers, dispute resolve, admin cleanup), rideshare_payments (2), admin x19, legal x4, health x3, auth logout/me/demo-login, `set_driver_online` aliases | -4 | 900 | unreferenced by clients but in protected categories | KEEP |

## B2. Modules / scripts never imported

Import graph over all `*.py` (incl. tests, scripts, alembic) plus text refs in `*.sh`, Dockerfile*, toml, ini, `.github/**`, and a whole-repo `grep -rIlw NAME` (excluding node_modules/venv/Pods/build). pytest is configured `testpaths = tests`, so the root-level `test_*.py` are never collected.

| path | lines | evidence | verdict | notes |
|---|---:|---|---|---|
| `capture_negotiation.py` | 302 | 0 importers, 0 text refs repo-wide | SAFE |  |
| `rideshare_bidding_capture.py` | 364 | 0 importers, 0 text refs | SAFE |  |
| `rideshare_ui_agent.py` | 723 | 0 importers, 0 text refs | SAFE |  |
| `update_demo_driver.py` | 146 | 0 importers, 0 text refs | SAFE | calls /api/demo/* |
| `run_doc_verification_tests.py` | 40 | 0 importers, 0 text refs | SAFE |  |
| `rideshare_full_flow.py` | 791 | 0 importers; only `.planning/quick/54-*/54-PLAN.md` | SAFE | ad-hoc E2E script |
| `driver_test_agent.py` | 647 | 0 importers; registered in DO_NOT_USE section 5 | SAFE | already scheduled for deletion |
| `rideshare_e2e_test.py` | 693 | 0 importers; DO_NOT_USE section 5 | SAFE | outside tests/ |
| `test_negotiation_flow.py` | 272 | 0 importers; DO_NOT_USE section 5; not collected (testpaths=tests) | SAFE |  |
| `test_order_flow.py` | 120 | 0 importers; DO_NOT_USE section 5; `scripts/seed_departments.py` has the substring only | SAFE |  |
| `test_ride_checkout.py` | 208 | 0 importers; DO_NOT_USE section 5 | SAFE |  |
| `endpoint_config.py` | 244 | `grep -ln endpoint_config *.py` = only itself; text refs only in `.planning/` docs; `get_config`/`get_expected_statuses` occur once | SAFE |  |
| `password_reset_service.py` | 619 | 0 importers; main_new implements `/api/auth/password-reset/*` inline; `PasswordResetToken` model is used by database.py + this file | NEEDS-CHECK | auth: confirm which implementation prod uses before deleting |
| `seed_wyoming_data.py` | 320 | 0 importers; mentioned in legal/WYOMING_TNC_MASTER_COMPLIANCE.md | NEEDS-CHECK | seed data for the Wyoming launch |
| `run_migrations.py` | 176 | 0 importers; referenced by a runbook; `run_migrations` also names a route function and alembic's standard hook (false text hits) | NEEDS-CHECK | ops tool |
| `reset_admin.py` | 55 | 0 importers; called by `apps/web/p2p-platform/FIX_LOGIN.sh` | NEEDS-CHECK | ops script |
| `add_driver_activation_columns.py / migrate_auto_dispatch.py` | 89 | 0 importers; one-off schema migrations | NEEDS-CHECK | confirm columns exist in prod (see `tests/unit/test_ride_dispatch.py`) then delete |

## B3. Dead helpers inside live modules (AST scan, identifier occurs once in whole backend incl. tests)

| path (symbol@line(lines)) | lines | evidence | verdict | notes |
|---|---:|---|---|---|
| email_service.py `verify_unsubscribe_token`@69(36), `generate_email_footer`@122(48) | 84 | `grep -rnw verify_unsubscribe_token --include=*.py .` = 1 | SAFE |  |
| prop22_utils.py `calculate_prop22_order_data`@178 | 59 | = 1 (the order-based Prop22 path was removed with food orders) | SAFE | keep rest of module (used by order_flow/bid_routes) |
| state_config.py `get_privacy_policy_requirements`@467 | 43 | = 1 | SAFE | module is itself NEEDS-CHECK (B1) |
| encryption.py `mask_value`@108 | 17 | = 1 | SAFE |  |
| cache.py `cache_json_get`@70, `cache_json_set`@81 | 15 | = 1 each | SAFE |  |
| google_maps_service.py `clear_cache`@230, `get_cache_stats`@236 | 14 | = 1 each | SAFE |  |
| bid_routes.py `_require_auth`@3136 | 12 | = 1 | SAFE | private helper |
| change_management.py `get_approver_for_case`@371 | 10 | = 1 | SAFE |  |
| founding_members.py `founding_platform_fee`@121 | 6 | = 1 | SAFE |  |
| checkr_service.py `get_report`@204 | 2 | = 1 | SAFE |  |

## B4. ORM models with no code references (verdict NEEDS-CHECK: dropping a class changes `create_all`/alembic)

| path (class@line(lines)) | lines | evidence | verdict | notes |
|---|---:|---|---|---|
| models.py `Cart`@675(19), `CartItem`@696(29) | 48 | `grep -rnw 'Cart\|CartItem' --include=*.py .` outside models.py = 0 (tests: 1 word hit) | NEEDS-CHECK | food cart tables |
| models.py `RestaurantRating`@292(26), `VendorPurchaseOrder`@320(18), `VendorMenuItem`@339(52) (1 ref order_flow) | 96 | 0 refs outside models.py (relationships on Vendor@142 point at them) | NEEDS-CHECK | remove together with the `Vendor` relationships at models.py:282-289 |
| models.py `AIEmployee`@947, `AIEmployeeActivity`@990, `AIEmployeeHourlyReport`@1019, `AIEmployeeDailyReport`@1063, `DashboardMetric`@1103 | 169 | 0 refs outside models.py (only `tests/unit/test_models.py` lists them) | NEEDS-CHECK | also route `/api/erp/analytics/ai-employees` (main_new.py:11302) and alias :13707, whose handler may read these tables |
| models.py `ChatConversation`@1228, `ChatMessage`@1266, `MessageSenderType`@1222; `TicketComment`@1201; `CoupaPurchaseOrderLine`@1641 | -111 | 0 refs outside models.py | NEEDS-CHECK |  |
| models_extended.py `Promotion`@89, `PromotionRedemption`@148, `RestaurantInvitation`@171, `OnboardingLog`@221, `ScrapedMenuItem`@262, `CustomerFavorite`@408, `VendorAnalytics`@426, `EmailTemplate`/`EmailSchedule`/`EmailABTest` + 8 enums | -561 | only reference is the table-registration import in database.py:83-84 (and 1 in realtime_events.py for Promotion) | NEEDS-CHECK | food-era tables; confirm no live DB rows needed |

## B5. Tracked artifacts / data

| path | lines | evidence | verdict | notes |
|---|---:|---|---|---|
| `test_report_v1.txt`,`v2`,`v3` | 462 | `git ls-files` tracked, 0 refs (DO_NOT_USE section 5) | SAFE |  |
| `use_case_report.txt`,`v2`,`v3` | 492 | tracked, 0 refs | SAFE |  |
| `security_report.txt` | 613 | tracked, 0 refs | SAFE | review for secrets before publishing history |
| `test_order.json` | 37 | tracked, 0 refs | SAFE |  |
| `eatfair.db` | 0 | tracked, 0 bytes in this worktree (DO_NOT_USE section 5) | SAFE |  |
| `uploads/vendor_documents/*.pdf` (383 files, 1.5 MB) | 0 | `git ls-files uploads \| wc -l` = 383; only reader is `serve_upload` (main_new.py:595), vendor document route no longer exists | NEEDS-CHECK | PII (business licences). Untrack; verify production reads S3 not this dir |

## B6. Tests that depend on removed food surface (follow-up after batches)

`tests/unit/test_models.py` (1,420; 54 food-word hits), `tests/e2e/test_customer_ui_wiring_e2e.py` (482), `tests/e2e/test_driver_vendor_ui_wiring_e2e.py` (425), `tests/integration/test_ios_api_contracts.py` (1,148; vendor/menu contract tests), `tests/test_cross_platform.py`. NEEDS-CHECK: they reference vendor/menu/restaurant names; run them to see which already fail.

---

# Recommended deletion order (lowest risk first) and verification after each batch

| # | batch | what | verify |
|---|---|---|---|
| 0 | Repo hygiene (no build impact) | Backend B5 SAFE artifacts; iOS I4 stray `delivery/Info.plist`, `delivery/Assets.xcassets`, delivery xcdatamodeld x2 | `git status`; `xcodebuild -list -project delivery/eatffairdelivery.xcodeproj` still resolves; backend `python -c 'import main_new'` with the requirements.txt venv |
| 1 | Backend never-imported scripts (B2 SAFE, 4,550 lines) + B3 dead helpers + 3 alias lines | delete `capture_negotiation`, `rideshare_*`, `driver_test_agent`, `update_demo_driver`, `endpoint_config`, root `test_*.py`, `run_doc_verification_tests`; remove main_new.py:13697-13699 | `python -m compileall -q .`; `pytest tests -q` in a venv built from requirements.txt (stale venv hangs, per DO_NOT_USE section 5); re-run the route-extraction script and diff against `routes.json` (expect exactly -3 routes); run the duplicate-route check from DO_NOT_USE section 6 |
| 2 | Android resources | A3 SAFE rows | `./gradlew :app:assembleDebug :driver:assembleDebug`; lint `UnusedResources` should now be clean |
| 3 | Android leaf files (no dependents) | Confetti*, TipDriverScreen, LanguageModal+LanguageDto, PaymentRepo+PaymentSheetKeys, Constants.kt, ProfileMenuItemDto, Negotiation/Call services, GoogleSignInHelper, MultiRestaurantOrder, OrderModification, Driver.kt, DriverSession.kt, home/*, search/*, restaurant/*, Rating.kt | `:shared:compileDebugKotlin`, `:app:assembleDebug`, `:driver:assembleDebug`, `:app:testDebugUnitTest`, `:app:compileDebugAndroidTestKotlin` (WelcomeScreenTest must go with WelcomeScreen) |
| 4 | Android cascade | OrderDto.kt -> OrderNumberFormatter.kt -> OrderEntity.kt -> EnumConst OrderStatus (then NEEDS-CHECK); AppConfig dead objects; Retrofit methods; ImportBlinkitCard | same Gradle tasks; additionally `grep -rn 'OrderStatus' shared app driver --include=*.kt` = 0 |
| 5 | iOS dead files | I1 table (12 files) + Persistence/ContentView/xcdatamodeld together | `xcodebuild -workspace customer/eatfaircustomer.xcworkspace -scheme eatfaircustomer -sdk iphonesimulator -configuration Debug build` and the same for `delivery/eatffairdelivery.xcworkspace` (CocoaPods workspaces); `swift build` in `eatfair-ios-shared` |
| 6 | iOS shared dead services | Legal, GoogleMaps, AIEmployee(+model), CallService, NegotiationService, DollorV3Service, Order.swift, Restaurant.swift, EnhancedModels, AIEmployee models, TripBoardService units | both app builds + `swift build`; `grep -rnw <deleted type> apps/ios --include=*.swift` = 0 |
| 7 | iOS P2PAPIService.swift food groups (I3 SAFE rows) | delete top-down: functions then DTO types, one group at a time (vendor, menu, promo, customer food, KOT, driver food, other) | build both apps after EACH group (compile errors reveal any missed caller); finally `wc -l` should drop from 15,808 to ~7,400 |
| 8 | Tests | Android A4 SAFE rows; iOS I5 SAFE rows | `xcodebuild test` customer/delivery unit schemes; Gradle `testDebugUnitTest` |
| 9 | NEEDS-CHECK items | owner decisions: iOS ride/driver/payment functions (I3 last row), ACH, backend demo/debug, ERP aliases, matchmaking+state_config, models/tables, password_reset_service, uploads PDFs | each with its own PR; backend ones need a prod access-log check (CloudWatch/ALB logs for the last 30 days) before removal |

# Top 15 safest big deletions

| rank | deletion | lines | evidence |
|---:|---|---:|---|
| 1 | iOS `P2PAPIService.swift` food/vendor/menu/promo/cart/KOT/delivery groups | 6,524 (safe part, 8,416 incl. check) | 0 code refs; 132 endpoint strings hit non-existent routes |
| 2 | Backend 12 never-imported scripts (rideshare_full_flow, rideshare_ui_agent, driver_test_agent, rideshare_e2e_test, rideshare_bidding_capture, capture_negotiation, test_*.py x3, endpoint_config, update_demo_driver, run_doc_verification_tests) | 4,550 | 0 importers, 0 repo refs (7 already registered in DO_NOT_USE) |
| 3 | iOS `TripBoardService.swift` (55 units) | 1,380 safe | `/api/trip-board/*` missing on backend; 0 refs |
| 4 | iOS `Order.swift` lines 198-810 (Order, OrderModification, MultiRestaurantOrder, ...) | 601 | 0 code refs outside dead units |
| 5 | iOS `EnterpriseNetworkLayer.swift` | 830 | 0 refs, file-level |
| 6 | iOS `V3CheckoutView.swift` + `DollorV3Service.swift` | 739 + 368 | 0 refs (only each other) |
| 7 | iOS `OrderConfirmationViews.swift` | 665 | 0 refs |
| 8 | iOS `LegalService.swift` + `LegalAcceptanceView.swift` | 626 + 371 | only each other |
| 9 | iOS `GoogleMapsService.swift` + `GooglePlacesSearchView.swift` | 624 + 190 | only each other |
| 10 | iOS `DateTimeFormatter.swift` | 486 | 0 refs, file-level |
| 11 | iOS `AIEmployeeService.swift` + `AIEmployee.swift` types | 468 + 70 | 0 refs |
| 12 | iOS `CallService.swift` | 431 | 0 refs |
| 13 | Android `NegotiationService.kt` (+ iOS twin 370) | 394 | 0 refs; Hilt class never injected |
| 14 | Android `Driver.kt` (342), `TipDriverScreen.kt` (340), `CallService.kt` (372) | 1,054 | 0 refs each |
| 15 | Android `MultiRestaurantOrder.kt` + `OrderModification.kt` + `OrderDto.kt` + `OrderNumberFormatter.kt` | 731 | 0 live refs |

# Open questions for the owner

- iOS rideshare-named but unreferenced functions (I3 last row, 1,892 lines) and `ACHPaymentService` (460): delete or wire up?
- Backend `/api/demo/*` + `/api/debug/order/{id}` (885 lines) look like an unauthenticated back door; confirm gating and whether App Review uses them.
- The web `frontend/src` still has Restaurants/Cart/Checkout/Vendor screens (App.tsx:175-210) calling routes the backend already removed: that is a fourth dead-code platform outside this scope.
